// Weekly Claude plan usage, read the way CodexBar's OAuth source does: Claude Code's
// own login from the Keychain, sent to Anthropic's usage endpoint. Pace follows
// CodexBar's math: how far through the window you are versus how much you've used.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, theme, home, run, settings, nextCommand } from "herdr";

const REFRESH = 5 * 60 * 1000;
const WEEK = 7 * 24 * 60 * 60;
const USAGE_URL = "https://api.anthropic.com/api/oauth/usage";

function span(seconds) {
  const m = Math.max(0, Math.round(seconds / 60));
  const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), min = m % 60;
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${min}m`;
  return `${min}m`;
}

// CodexBar's UsagePace.weekly, without its work-day option.
function pace(usedPercent, resetsAt, now) {
  const untilReset = (Date.parse(resetsAt) - now) / 1000;
  if (!(untilReset > 0 && untilReset <= WEEK)) return null;
  const elapsed = WEEK - untilReset;
  const expected = Math.min(100, Math.max(0, (elapsed / WEEK) * 100));
  const actual = Math.min(100, Math.max(0, usedPercent));
  const delta = actual - expected;
  let eta = null, lasts = false;
  if (actual >= 100) eta = 0;
  else if (elapsed > 0 && actual > 0) {
    const left = (100 - actual) / (actual / elapsed);
    if (left >= untilReset) lasts = true;
    else eta = left;
  } else lasts = true;
  return { expected, delta, eta, lasts, untilReset };
}

// Claude Code keeps its login in the Keychain and renews it while it runs. Only read it:
// renewing here would replace the refresh token Claude Code holds and sign it out.
async function claudeLogin() {
  const r = await exec("security", ["find-generic-password", "-s", "Claude Code-credentials", "-a", home().split("/").pop(), "-w"]);
  if (r.code !== 0) throw new Error("No Claude Code login in the Keychain");
  const oauth = JSON.parse(r.stdout).claudeAiOauth;
  const expiresAt = oauth.expiresAt > 1e11 ? oauth.expiresAt : oauth.expiresAt * 1000;
  return { token: oauth.accessToken, expired: expiresAt <= Date.now() };
}

export default class RexUsage extends View {
  init(_props, cx) {
    this.usage = null;
    this.stale = false;
    this.error = null;
    this.open = (localStorage.getItem("open") ?? "true") === "true";
    this.asked = null;
    cx.spawn(async (cx) => {
      for (;;) if ((await nextCommand()) === "toggle") this.toggle(cx);
    });
    cx.spawn(async (cx) => {
      const r = await exec("claude", ["--version"]).catch(() => null);
      this.agent = `claude-cli/${r?.stdout?.trim().split(/\s+/)[0] || "unknown"} (external, cli)`;
      this.refresh(cx);
    });
    cx.timer.every(REFRESH, (cx) => this.refresh(cx));
    // The countdown and pace move with the clock.
    cx.timer.every(60 * 1000, (cx) => cx.notify());
  }

  refresh(cx) {
    cx.spawn(async (cx) => {
      try {
        const login = await claudeLogin();
        if (login.expired) throw new Error("Claude Code's login has expired; it renews when Claude Code runs");
        const res = await fetch(USAGE_URL, {
          headers: { Authorization: `Bearer ${login.token}`, "anthropic-beta": "oauth-2025-04-20", Accept: "application/json", "User-Agent": this.agent },
        });
        if (!res.ok) throw new Error(`Usage request failed (${res.status})`);
        const week = (await res.json()).seven_day;
        if (!week?.resets_at) throw new Error("No weekly limit in the response");
        this.usage = { usedPercent: week.utilization, resetsAt: week.resets_at };
        this.stale = false;
        this.error = null;
      } catch (e) {
        this.error = String(e.message ?? e);
        this.stale = Boolean(this.usage);
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
    run("layout.resize", { id: "usage", px: want });
  }

  render() {
    const t = theme();
    const chevron = svg(`mods/workspace-chrome/${this.open ? "chevron-down" : "chevron-right"}.svg`).size(12).flex_none().text_color(t.dim);
    const shell = (content) => div().size_full().bg(t.chrome).px(10).pb(6).child(
      v_flex().id("usage-card").w_full().px(12).py(9).gap(8).rounded(12).bg(t.surface).border(0.5).border_color("#ffffff14").text_size(12)
        .on_size_change((size) => this.fit(size.height))
        .child(content));
    if (!this.usage) return shell(div().id("usage-error").text_color(t.dim).when(Boolean(this.error), (el) => el.tooltip(this.error)).child(this.error ? "Usage unavailable" : "Loading usage…"));
    const p = pace(this.usage.usedPercent, this.usage.resetsAt, Date.now());
    const used = Math.round(this.usage.usedPercent);
    const onPace = !p || Math.abs(p.delta) <= 2 || Math.round(Math.abs(p.delta)) === 0;
    const paceText = !p ? null : onPace ? "On pace" : p.delta > 0 ? `${Math.round(p.delta)}% in deficit` : `${Math.round(-p.delta)}% in reserve`;
    const paceShort = !p ? "" : onPace ? "On pace" : p.delta > 0 ? `${Math.round(p.delta)}% over` : `${Math.round(-p.delta)}% under`;
    const paceColor = onPace ? t.muted : p.delta > 0 ? (p.delta > 12 ? t.blocked : t.working) : t.ansi2;
    const eta = !p ? null : p.lasts ? "Lasts until reset" : p.eta === 0 ? "Runs out now" : `Runs out in ${span(p.eta)}`;
    const bar = (h) => div().relative().h(h).flex_1().min_w(0).rounded_full().bg(t.hover)
      .child(div().absolute().left(0).top(0).h(h).rounded_full().bg("#e56a40").w(`${Math.min(100, used)}%`))
      .when(Boolean(p), (el) => el.child(div().absolute().top(-2).h(h + 4).w(1.5).rounded_full().bg(t.foreground).left(`${p.expected}%`)));
    const card = image("mods/rex-tabs/cards/claude.svg").w(18).h(15).flex_none();
    if (!this.open) {
      return shell(h_flex().id("usage-toggle").gap(8).items_center().cursor_pointer().when(this.stale, (el) => el.opacity(0.6))
        .tooltip([`Weekly ${used}% used`, paceText, eta, p && `Resets in ${span(p.untilReset)}`].filter(Boolean).join(" · "))
        .on_click((_e, cx) => this.toggle(cx))
        .child(card)
        .child(div().flex_none().text_size(12.5).font_medium().text_color(t.foreground).child(`${used}%`))
        .child(bar(4))
        .child(div().flex_none().text_color(paceColor).child(paceShort))
        .child(chevron));
    }
    return shell(v_flex().gap(8).when(this.stale, (el) => el.opacity(0.6))
      .child(h_flex().id("usage-toggle").gap(7).items_center().cursor_pointer().on_click((_e, cx) => this.toggle(cx))
        .child(card)
        .child(div().id("usage-title").flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground)
          .when(this.stale, (el) => el.tooltip(`Last known. ${this.error}`)).child(`Weekly ${used}% used`))
        .when(Boolean(p), (el) => el.child(div().id("resets").flex_none().text_color(t.dim).tooltip(`Resets in ${span(p.untilReset)}`).child(span(p.untilReset))))
        .child(chevron))
      .child(h_flex().child(bar(6)))
      .when(Boolean(p), (el) => el.child(h_flex().gap(8).justify_between()
        .child(div().flex_none().text_color(paceColor).child(paceText))
        .child(div().min_w(0).truncate().text_color(t.dim).child(eta)))));
  }
}
