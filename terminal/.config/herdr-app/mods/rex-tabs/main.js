import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme } from "herdr";

const ICON = "mods/rex-tabs";
const stop = (_e, cx) => cx.stop_propagation();

function label(tab, tabPanes) {
  if (tab.named) return tab.name;
  const agent = tabPanes.find((p) => p.program?.agent);
  if (agent) return agent.title || agent.program.name;
  return tabPanes[0]?.program?.name ?? "Terminal";
}

function icon(program, t) {
  if (!program?.icon) return svg(`${ICON}/monitor.svg`).size(13).text_color(t.muted);
  const glyph = program.tint ? svg(program.icon).size(11).text_color(program.color ?? t.muted) : image(program.icon).size(11);
  return div().size(17).flex_none().rounded(5).when(Boolean(program.tile), (el) => el.bg(program.tile)).flex().items_center().justify_center().child(glyph);
}

export default class RexTabs extends View {
  init() {
    this.pressed = null;
  }

  tab(space, tab, i, allPanes) {
    const t = theme();
    const tabPanes = allPanes.filter((p) => p.tab === tab.id);
    const program = tabPanes.find((p) => p.program?.agent)?.program ?? tabPanes[0]?.program;
    return h_flex().id(`tab-${tab.id}`).h(28).pl(8).pr(tab.active ? 6 : 12).gap(7).flex_none().items_center().rounded_full().text_size(13)
      .border(1).border_color(tab.active ? "#ffffff1a" : t.background)
      .bg(tab.active ? t.selected : t.background).text_color(tab.active ? t.foreground : t.muted)
      .when(!tab.active, (el) => el.hover((s) => s.bg(t.hover).text_color(t.foreground)))
      .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); this.pressed = i; if (e.click_count === 2) run("tab.rename", { id: tab.id }); })
      .on_mouse_up("left", () => {
        const from = this.pressed;
        this.pressed = null;
        if (from !== null && from !== i) run("tab.move", { id: space.tabs[from].id, index: i + 1 });
        else run("tab.select", { id: tab.id });
      })
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: tab.id, space: space.id } } }); })
      .child(icon(program, t))
      .child(div().max_w(200).truncate().child(tab.zoomed ? `${label(tab, tabPanes)} (zoomed)` : label(tab, tabPanes)))
      .when(tab.status === "working", (el) => el.child(svg(`${ICON}/spinner.svg`).size(11).flex_none().text_color(t.working).spin(900)))
      .when(tab.status === "blocked" || tab.status === "done", (el) => el.child(div().size(6).flex_none().rounded(3).bg(t[tab.status])))
      .when(tab.active, (el) => el.child(div().id(`close-${tab.id}`).size(18).flex_none().flex().items_center().justify_center().rounded_full()
        .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)).on_mouse_down("left", stop)
        .on_click((_e, cx) => { cx.stop_propagation(); run("tab.close", { id: tab.id }); })
        .child(svg(`${ICON}/close.svg`).size(10))));
  }

  render() {
    const t = theme();
    const space = spaces().find((s) => s.active);
    const allPanes = panes();
    return h_flex().size_full().min_w(0).px(10).gap(4).items_center().bg(t.background)
      .on_mouse_up("left", () => { this.pressed = null; })
      .child(h_flex().id("tab-scroll").flex_1().min_w(0).h_full().gap(4).items_center().overflow_x_scrollbar()
        .children((space?.tabs ?? []).map((tab, i) => this.tab(space, tab, i, allPanes))))
      .child(div().id("tab-new").size(26).flex_none().flex().items_center().justify_center().rounded_full().text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_mouse_down("left", stop)
        .on_click(() => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 }))
        .child(svg(`${ICON}/plus.svg`).size(14)));
  }
}
