// Weekly plan usage from CodexBar's CLI, with its pace math: how far through the
// window you are versus how much of the allowance you've used.

import { View, div, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, theme, props } from "herdr";

const REFRESH = 5 * 60 * 1000;
const PROVIDER_CARD = { claude: "claude", codex: "codex", cursor: "cursor", gemini: "gemini" };

function span(seconds) {
  const m = Math.max(0, Math.round(seconds / 60));
  const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60), min = m % 60;
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${min}m`;
  return `${min}m`;
}

// CodexBar's UsagePace.weekly, without its work-day option.
function pace(window, now) {
  const duration = (window.windowMinutes ?? 10080) * 60;
  const untilReset = (Date.parse(window.resetsAt) - now) / 1000;
  if (!(untilReset > 0 && untilReset <= duration)) return null;
  const elapsed = duration - untilReset;
  const expected = Math.min(100, Math.max(0, (elapsed / duration) * 100));
  const actual = Math.min(100, Math.max(0, window.usedPercent));
  const delta = actual - expected;
  let eta = null, lasts = false;
  if (actual >= 100) eta = 0;
  else if (elapsed > 0 && actual > 0) {
    const left = (100 - actual) / (actual / elapsed);
    if (left >= untilReset) lasts = true;
    else eta = left;
  } else lasts = true;
  return { expected, actual, delta, eta, lasts, untilReset };
}

export default class RexUsage extends View {
  init(_props, cx) {
    this.provider = props()?.provider ?? "claude";
    this.data = null;
    this.error = null;
    this.refresh(cx);
    cx.timer.every(REFRESH, (cx) => this.refresh(cx));
    // The countdown and pace move with the clock.
    cx.timer.every(60 * 1000, (cx) => cx.notify());
  }

  refresh(cx) {
    cx.spawn(async (cx) => {
      try {
        const r = await exec("codexbar", ["usage", "--provider", this.provider, "--format", "json", "--no-credits"]);
        if (r.code !== 0) throw new Error((r.stderr || r.stdout || "codexbar failed").trim());
        const entry = JSON.parse(r.stdout).find((e) => e.provider === this.provider);
        const labels = entry?.rateWindowLabels ?? {};
        const key = Object.keys(labels).find((k) => labels[k] === "Weekly") ?? "secondary";
        const window = entry?.usage?.[key];
        if (!window?.resetsAt) throw new Error("No weekly window");
        this.data = { window, plan: entry.usage.loginMethod };
        this.error = null;
      } catch (e) {
        this.error = String(e.message ?? e);
      }
      cx.notify();
    });
  }

  render() {
    const t = theme();
    const shell = (content) => div().size_full().bg(t.chrome).px(10).pb(6).child(
      v_flex().size_full().px(12).py(10).gap(7).rounded(12).bg(t.surface).border(0.5).border_color("#ffffff14").text_size(12).child(content));
    if (!this.data) return shell(div().text_color(t.dim).child(this.error ? "Usage unavailable" : "Loading usage…"));
    const p = pace(this.data.window, Date.now());
    const used = Math.round(this.data.window.usedPercent);
    const card = PROVIDER_CARD[this.provider];
    const fill = this.provider === "claude" ? "#e56a40" : t.accent;
    const paceText = !p ? null : Math.round(Math.abs(p.delta)) === 0 || Math.abs(p.delta) <= 2
      ? "On pace" : p.delta > 0 ? `${Math.round(p.delta)}% in deficit` : `${Math.round(-p.delta)}% in reserve`;
    const paceColor = !p || Math.abs(p.delta) <= 2 ? t.muted : p.delta > 0 ? (p.delta > 12 ? t.blocked : t.working) : t.ansi2;
    const eta = !p ? null : p.lasts ? "Lasts until reset" : p.eta === 0 ? "Runs out now" : `Runs out in ${span(p.eta)}`;
    return shell(v_flex().gap(7)
      .child(h_flex().gap(7).items_center()
        .when(Boolean(card), (el) => el.child(image(`mods/rex-tabs/cards/${card}.svg`).w(18).h(15).flex_none()))
        .child(div().flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground).child(`Weekly ${used}% used`))
        .when(Boolean(p), (el) => el.child(div().id("resets").flex_none().text_color(t.dim).tooltip(`Resets in ${span(p.untilReset)}`).child(span(p.untilReset)))))
      .child(div().relative().h(6).w_full().rounded_full().bg(t.hover)
        .child(div().absolute().left(0).top(0).h(6).rounded_full().bg(fill).w(`${Math.min(100, used)}%`))
        .when(Boolean(p), (el) => el.child(div().absolute().top(-2).h(10).w(1.5).rounded_full().bg(t.foreground).left(`${p.expected}%`))))
      .when(Boolean(p), (el) => el.child(h_flex().gap(8).justify_between()
        .child(div().flex_none().text_color(paceColor).child(paceText))
        .child(div().min_w(0).truncate().text_color(t.dim).child(eta)))));
  }
}
