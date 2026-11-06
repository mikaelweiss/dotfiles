// Live CPU, memory and storage for each connected computer, measured the way the
// status collector measures them (~/code/status/collector/sources/hosts.go):
// idle plus iowait counts as idle, Linux memory is total minus available, macOS memory
// is active plus wired plus compressed, and storage is the fullest writable disk.

import { View, div, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, machines, theme, run, settings, nextCommand } from "herdr";

// Apple's dark-mode system colors.
const APPLE = { blue: "#0a84ff", purple: "#bf5af2", mint: "#66d4cf", green: "#30d158", orange: "#ff9f0a", red: "#ff453a" };

const EVERY = 3000;
const HISTORY = (5 * 60 * 1000) / EVERY;
const ICON = "mods/workspace-chrome";

const SAMPLE = `if [ "$(uname)" = Darwin ]; then
  iostat -c 2 -w 1 -n 0 | awk 'END {print "cpu=" 100-$3}'
  vm_stat | awk -v ps="$(sysctl -n hw.pagesize)" -v t="$(sysctl -n hw.memsize)" '/Pages active/ {a=$3} /Pages wired down/ {w=$4} /occupied by compressor/ {c=$5} END {gsub(/\\./,"",a); gsub(/\\./,"",w); gsub(/\\./,"",c); print "mem=" (a+w+c)*ps; print "memtotal=" t}'
  df -k /System/Volumes/Data | awk 'NR==2 {print "disk=" ($2-$4)*1024; print "disktotal=" $2*1024; print "mount=/"}'
else
  head -1 /proc/stat | awk '{t=0; for (i=2; i<=NF; i++) t+=$i; print "cputotal=" t; print "cpuidle=" $5+$6}'
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print "mem=" (t-a)*1024; print "memtotal=" t*1024}' /proc/meminfo
  df -kPT 2>/dev/null | awk 'NR>1 && $2 !~ /^(tmpfs|devtmpfs|overlay|squashfs|vfat|efivarfs|ramfs|autofs)$/ && $7 !~ /^\\/(nix\\/store|run|boot|dev|var\\/lib\\/containers)(\\/|$)/ && $3 > 0 {used=($3-$5)*1024; p=used/($3*1024); if (p > best) {best=p; u=used; tot=$3*1024; m=$7}} END {print "disk=" u; print "disktotal=" tot; print "mount=" m}'
fi`;

function parse(stdout) {
  const v = {};
  for (const line of stdout.split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) v[line.slice(0, i)] = line.slice(i + 1).trim();
  }
  return v;
}

const pct = (used, total) => (Number(total) > 0 ? (100 * Number(used)) / Number(total) : null);

export default class RexMachines extends View {
  init(_props, cx) {
    this.open = (localStorage.getItem("open") ?? "true") === "true";
    this.hosts = {}; // machine key -> { cpu: [], mem: [], disk, mount, prev, busy, offline }
    this.asked = null;
    this.sampleAll(cx);
    cx.timer.every(EVERY, (cx) => this.sampleAll(cx));
    cx.spawn(async (cx) => {
      for (;;) if ((await nextCommand()) === "toggle") this.toggle(cx);
    });
  }

  list() {
    return [null, ...machines().map((m) => m.name).filter((n) => n !== null)];
  }

  sampleAll(cx) {
    for (const name of this.list()) {
      const key = name ?? "";
      const host = (this.hosts[key] ??= { cpu: [], mem: [], disks: [], disk: null, mount: null, prev: null, busy: false, offline: false });
      if (host.busy) continue;
      host.busy = true;
      cx.spawn(async (cx) => {
        try {
          const r = await exec("sh", ["-c", SAMPLE], { on: name });
          if (r.code !== 0) throw new Error(r.stderr);
          this.record(host, parse(r.stdout));
          host.offline = false;
        } catch {
          host.offline = true;
        } finally {
          host.busy = false;
        }
        cx.notify();
      });
    }
  }

  record(host, v) {
    let cpu = v.cpu !== undefined ? Number(v.cpu) : null;
    if (v.cputotal !== undefined) {
      const total = Number(v.cputotal), idle = Number(v.cpuidle);
      if (host.prev && total > host.prev.total) cpu = 100 * (1 - (idle - host.prev.idle) / (total - host.prev.total));
      host.prev = { total, idle };
    }
    const push = (series, value) => {
      if (value === null || !Number.isFinite(value)) return;
      series.push(Math.max(0, Math.min(100, value)));
      if (series.length > HISTORY) series.shift();
    };
    push(host.cpu, cpu);
    push(host.mem, pct(v.mem, v.memtotal));
    host.disk = pct(v.disk, v.disktotal);
    push(host.disks, host.disk);
    host.mount = v.mount || null;
  }

  // The card grows and shrinks its own layout block to fit what it shows.
  fit(height) {
    const want = Math.ceil(height / settings().zoom) + 6;
    if (this.asked !== null && Math.abs(want - this.asked) < 2) return;
    this.asked = want;
    run("layout.resize", { id: "machines", px: want });
  }

  toggle(cx) {
    this.open = !this.open;
    localStorage.setItem("open", String(this.open));
    cx.notify();
  }

  colors(t) {
    return { cpu: APPLE.blue, mem: APPLE.purple, disk: APPLE.mint };
  }

  // Numbers stay quiet unless something is nearly full.
  level(t, value) {
    if (value === null || value === undefined) return t.dim;
    return value >= 90 ? APPLE.red : t.muted;
  }

  // One graph per machine: the three series drawn over each other, newest at the right.
  graph(t, host) {
    const c = this.colors(t);
    const line = (raw, color, smooth = 1) => {
      if (raw.length < 2) return null;
      const series = raw.map((_, i) => {
        const w = raw.slice(Math.max(0, i - smooth + 1), i + 1);
        return w.reduce((a, b) => a + b, 0) / w.length;
      });
      const start = HISTORY - series.length;
      const points = series.map((v, i) => [`${((start + i) / (HISTORY - 1)) * 100}%`, `${6 + (100 - v) * 0.88}%`]);
      const path = PathBuilder.stroke(1.25).add_polygon(points, false).build();
      return window.paint_path(path, color).absolute().inset_0();
    };
    return div().relative().w_full().h(30)
      .children([line(host.disks, c.disk), line(host.mem, c.mem), line(host.cpu, c.cpu, 4)].filter(Boolean));
  }

  value(t, v, color) {
    return div().w(32).flex_none().text_right().text_color(color).child(v === null || v === undefined ? "–" : `${Math.round(v)}%`);
  }

  expanded(t, name, host) {
    return v_flex().gap(5).when(host.offline, (el) => el.opacity(0.5))
      .child(this.collapsed(t, name, host, true))
      .when(host.cpu.length > 0, (el) => el.child(this.graph(t, host)));
  }

  collapsed(t, name, host, open = false) {
    const last = (s) => (s.length ? s[s.length - 1] : null);
    return h_flex().id(`machine-${name ?? "local"}`).gap(4).items_center().text_size(11.5).when(host.offline && !open, (el) => el.opacity(0.5))
      .tooltip(host.offline ? "Offline" : host.mount ? `Disk: ${host.mount}` : "")
      .when(open, (el) => el.child(svg(`${ICON}/${name ? "server" : "monitor"}.svg`).size(13).text_color(t.dim)))
      .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).when(open, (el) => el.text_size(12.5).font_medium()).child(name ?? "This Mac"))
      .child(this.value(t, last(host.cpu), this.level(t, last(host.cpu))))
      .child(this.value(t, last(host.mem), this.level(t, last(host.mem))))
      .child(this.value(t, host.disk, this.level(t, host.disk)));
  }

  render() {
    const t = theme();
    const names = this.list();
    const header = h_flex().id("machines-toggle").gap(6).items_center().cursor_pointer()
      .on_click((_e, cx) => this.toggle(cx))
      .child(div().flex_1().text_size(12).font_medium().text_color(t.dim).child("Computers"))
      .child(div().w(32).text_right().text_size(10.5).text_color(this.colors(t).cpu).child("CPU"))
      .child(div().w(32).text_right().text_size(10.5).text_color(this.colors(t).mem).child("RAM"))
      .child(div().w(32).text_right().text_size(10.5).text_color(this.colors(t).disk).child("Disk"))
      .child(svg(`${ICON}/${this.open ? "chevron-down" : "chevron-right"}.svg`).size(12).text_color(t.dim));
    const rows = names.map((name) => {
      const host = this.hosts[name ?? ""] ?? { cpu: [], mem: [], disks: [], disk: null, offline: false };
      return this.open ? this.expanded(t, name, host) : this.collapsed(t, name, host);
    });
    return div().size_full().bg(t.chrome).px(10).pb(6).child(
      v_flex().id("machines-card").w_full().px(12).py(9).gap(this.open ? 10 : 6).rounded(12).bg(t.surface).border(0.5).border_color("#ffffff14")
        .on_size_change((size) => this.fit(size.height))
        .child(header)
        .children(rows));
  }
}
