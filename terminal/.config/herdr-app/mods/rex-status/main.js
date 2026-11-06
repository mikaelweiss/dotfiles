// The overall status from status.weissfamily.us, decided the way its public page decides it.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme, run, settings, nextCommand, exec } from "herdr";

// Apple's dark-mode system colors.
const APPLE = { blue: "#0a84ff", purple: "#bf5af2", mint: "#66d4cf", green: "#30d158", orange: "#ff9f0a", red: "#ff453a" };

const PAGE = "https://status.weissfamily.us";
const REFRESH = 60 * 1000;
const STALE = 5 * 60;

// Floored, so a bad hour never rounds up to 100%.
const percent = (pct) => (Math.floor(pct * 100) / 100).toFixed(2) + "%";

function ago(seconds) {
  const m = Math.max(0, Math.round(seconds / 60));
  if (m < 1) return "now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h ago` : `${Math.floor(h / 24)}d ago`;
}

export default class RexStatus extends View {
  init(_props, cx) {
    this.now = null;
    this.uptime = null;
    this.error = null;
    this.open = (localStorage.getItem("open") ?? "true") === "true";
    this.asked = null;
    this.refresh(cx);
    cx.timer.every(REFRESH, (cx) => this.refresh(cx));
    cx.spawn(async (cx) => {
      for (;;) if ((await nextCommand()) === "toggle") this.toggle(cx);
    });
  }

  refresh(cx) {
    cx.spawn(async (cx) => {
      try {
        const res = await fetch(`${PAGE}/api/public/now`);
        if (!res.ok) throw new Error(`Status request failed (${res.status})`);
        this.now = await res.json();
        this.error = null;
        const up = await fetch(`${PAGE}/api/public/uptime?range=7d`);
        this.uptime = up.ok ? await up.json() : null;
      } catch (e) {
        this.error = String(e.message ?? e);
      }
      cx.notify();
    });
  }

  toggle(cx) {
    this.open = !this.open;
    localStorage.setItem("open", String(this.open));
    cx.notify();
  }

  // The card grows and shrinks its own layout block to fit what it shows.
  fit(height) {
    const want = Math.ceil(height / settings().zoom) + 6;
    if (this.asked !== null && Math.abs(want - this.asked) < 2) return;
    this.asked = want;
    run("layout.resize", { id: "status-card", px: want });
  }

  summary() {
    const now = this.now;
    const out = now?.outside;
    if (!out) return { level: "idle", text: this.error ? "Status unavailable" : now ? "No checks yet" : "Loading status…", down: [], events: [] };
    const up = new Map([...out.sites, ...out.minecraft].map((s) => [s.id, s.up]));
    const down = [...now.sites.map((s) => ({ id: s.id, name: s.id })), ...now.minecraft]
      .filter((s) => up.get(s.id) === false).map((s) => s.name);
    const events = now.events.filter((e) => e.ended == null);
    const stale = Date.now() / 1000 - out.at > STALE;
    const level = down.length > 2 ? "crit" : down.length || events.length ? "warn" : "good";
    const text = down.length ? `${down.length} ${down.length === 1 ? "service is" : "services are"} down` : events.length ? events[0].title : "All green here :)";
    return { level, text, down, events, stale, at: out.at, total: now.sites.length + now.minecraft.length };
  }

  // The console's headline: uptime across every site over 7 days, one bar per rollup.
  uptimeView(t) {
    const u = this.uptime;
    const hours = u.minutes >= 60 ? `${u.minutes / 60} hours` : `${u.minutes} minutes`;
    const note = `Each bar is ${hours}, across ${u.sites} sites. Click to open the status page.`;
    const bars = u.bars.map(([at, frac], i) => {
      const color = frac == null ? t.hover : frac >= 0.9999 ? APPLE.green : frac >= 0.99 ? APPLE.orange : APPLE.red;
      const when = new Date(at * 1000).toLocaleString("en-US", { timeZone: "America/Denver", weekday: "short", hour: "numeric" });
      const down = frac == null ? 0 : Math.round((1 - frac) * u.minutes);
      return div().id(`bar-${i}`).flex_1().h_full().rounded_full().bg(color)
        .tooltip(frac == null ? `${when}: no data` : `${when}: ${percent(frac * 100)}${down ? `, about ${down} min down` : ""}`);
    });
    return v_flex().gap(7).pt(2)
      .child(h_flex().id("uptime").items_baseline().gap(6).cursor_pointer().tooltip(note).on_click(() => exec("open", [PAGE]))
        .child(div().text_size(22).font_semibold().text_color(t.foreground).child(u.uptime == null ? "–" : percent(u.uptime)))
        .child(div().text_color(t.dim).child("7-day uptime")))
      .child(h_flex().h(12).gap(1).children(bars));
  }

  render() {
    const t = theme();
    const s = this.summary();
    const color = { good: APPLE.green, warn: APPLE.orange, crit: APPLE.red, idle: t.dim }[s.level];
    const header = h_flex().id("status-toggle").gap(8).items_center().cursor_pointer()
      .when(Boolean(this.error), (el) => el.tooltip(this.error))
      .on_click((_e, cx) => this.toggle(cx))
      .child(div().size(8).flex_none().rounded_full().bg(color))
      .child(div().flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground).child(s.text))
      .when(!this.open && this.uptime?.uptime != null, (el) => el.child(div().flex_none().text_color(t.dim).child(percent(this.uptime.uptime))))
      .when(this.open && Boolean(s.at), (el) => el.child(div().flex_none().text_color(s.stale ? APPLE.orange : t.dim).child(ago(Date.now() / 1000 - s.at))))
      .child(svg(`mods/workspace-chrome/${this.open ? "chevron-down" : "chevron-right"}.svg`).size(12).flex_none().text_color(t.dim));
    const line = (id, dot, text, note) => h_flex().id(id).gap(8).items_center()
      .child(div().size(6).mx(1).flex_none().rounded_full().bg(dot))
      .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(text))
      .when(Boolean(note), (el) => el.child(div().flex_none().text_color(t.dim).child(note)));
    const details = [
      ...s.down.map((name) => line(`down-${name}`, APPLE.red, name, "down")),
      ...s.events.map((e) => line(`event-${e.key}`, e.level === "crit" ? APPLE.red : APPLE.orange, e.title, ago(Date.now() / 1000 - e.started))),
    ];
    const body = v_flex().gap(6).text_size(12)
      .children(details)
      .when(!details.length && Boolean(s.at) && !this.uptime, (el) => el.child(div().text_color(t.dim).child(`${s.total} services checked every minute`)))
      .when(Boolean(this.uptime), (el) => el.child(this.uptimeView(t)));
    return div().size_full().bg(t.chrome).px(10).pb(6).child(
      v_flex().id("status-card").w_full().px(12).py(9).gap(8).rounded(12).bg(t.surface).border(0.5).border_color("#ffffff14").text_size(12)
        .on_size_change((size) => this.fit(size.height))
        .child(header)
        .when(this.open, (el) => el.child(body)));
  }
}
