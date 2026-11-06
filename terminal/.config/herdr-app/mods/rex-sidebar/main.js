import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { spaces, panes, machines, run, openOverlay, theme, props, window } from "herdr";

const ICON = "mods/rex-sidebar";
const stop = (_e, cx) => cx.stop_propagation();

function tabLabel(tab, tabPanes) {
  if (tab.named) return tab.name;
  const agent = tabPanes.find((p) => p.program?.agent);
  if (agent) return agent.title || agent.program.name;
  return tabPanes[0]?.program?.name ?? "Terminal";
}

function programIcon(program, t) {
  if (!program?.icon) return svg(`${ICON}/monitor.svg`).size(14).text_color(t.muted);
  const glyph = program.tint ? svg(program.icon).size(13).text_color(program.color ?? t.muted) : image(program.icon).size(13);
  if (!program.tile) return div().size(20).flex_none().flex().items_center().justify_center().child(glyph);
  return div().size(20).flex_none().rounded(6).bg(program.tile).flex().items_center().justify_center().child(glyph);
}

export default class RexSidebar extends View {
  iconButton(id, label, action) {
    const t = theme();
    return div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6)
      .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", stop).on_click(action).child(label);
  }

  top() {
    const t = theme();
    const w = window();
    const lights = w?.platform === "macos" && !w.fullscreen;
    return h_flex().size_full().bg(t.chrome).pl(lights ? 78 : 12).pr(10).gap(2).items_center()
      .child(this.iconButton("toggle", svg(`${ICON}/sidebar.svg`).size(15), () => run("layout.toggle", { id: "sidebar" })))
      .child(div().flex_1())
      .child(this.iconButton("search", svg(`${ICON}/search.svg`).size(15), () => run("mod.open", { name: "picker" })))
      .child(this.iconButton("palette", div().text_size(15).child("⌘"), () => run("app.palette")))
      .child(this.iconButton("new", svg(`${ICON}/plus.svg`).size(15), () => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 })));
  }

  footer() {
    const t = theme();
    return h_flex().size_full().bg(t.chrome).px(10).gap(2).items_center()
      .child(this.iconButton("settings", svg(`${ICON}/settings.svg`).size(15), () => run("app.settings")))
      .child(div().flex_1())
      .child(this.iconButton("new-space", svg(`${ICON}/plus.svg`).size(15), () => run("space.new")))
      .child(this.iconButton("add-machine", svg(`${ICON}/server.svg`).size(15), () => run("mod.open", { name: "machine-add" })));
  }

  machineRow(name) {
    const t = theme();
    return h_flex().id(`machine-${name ?? "local"}`).h(30).px(10).gap(9).items_center().text_size(13.5).text_color(t.foreground)
      .child(svg(`${ICON}/${name ? "server" : "monitor"}.svg`).size(15).text_color(t.muted))
      .child(div().truncate().child(name ?? "This Mac"));
  }

  spaceHeader(space) {
    const t = theme();
    return h_flex().id(`space-${space.id}`).h(24).pl(10).pr(6).mt(4).gap(6).items_center().text_size(12.5).text_color(t.muted)
      .on_click(() => run("space.select", { id: space.id }))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: space.id } } }); })
      .child(div().flex_1().truncate().child(space.name))
      .child(div().id(`space-new-${space.id}`).size(20).flex().items_center().justify_center().rounded(5).text_color(t.dim)
        .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_mouse_down("left", stop)
        .on_click((_e, cx) => { cx.stop_propagation(); run("tab.new", { space: space.id }); })
        .child(svg(`${ICON}/plus.svg`).size(12)));
  }

  tabRow(space, tab, allPanes) {
    const t = theme();
    const tabPanes = allPanes.filter((p) => p.tab === tab.id);
    const program = tabPanes.find((p) => p.program?.agent)?.program ?? tabPanes[0]?.program;
    const current = space.active && tab.active;
    return h_flex().id(`tab-${tab.id}`).h(32).px(8).gap(8).items_center().rounded_full().text_size(13.5)
      .border(1).border_color(current ? "#ffffff1a" : t.chrome)
      .bg(current ? t.selected : t.chrome).text_color(current ? t.foreground : t.muted)
      .when(!current, (el) => el.hover((s) => s.bg(t.hover).text_color(t.foreground)))
      .on_click((e) => {
        if (e.click_count === 2) return run("tab.rename", { id: tab.id });
        if (!space.active) run("space.select", { id: space.id });
        run("tab.select", { id: tab.id });
      })
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: tab.id, space: space.id } } }); })
      .child(programIcon(program, t))
      .child(div().flex_1().min_w(0).truncate().child(tabLabel(tab, tabPanes)))
      .when(tab.status === "working", (el) => el.child(svg(`${ICON}/spinner.svg`).size(12).flex_none().text_color(t.working).spin(900)))
      .when(tab.status === "blocked" || tab.status === "done", (el) => el.child(div().size(7).flex_none().rounded(4).bg(t[tab.status])));
  }

  newSessionRow(machine) {
    const t = theme();
    return h_flex().id(`new-session-${machine}`).h(32).px(10).gap(9).items_center().rounded_full().text_size(13.5).text_color(t.muted)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click(() => run("space.new", { machine }))
      .child(svg(`${ICON}/plus.svg`).size(14))
      .child("New Session");
  }

  list() {
    const t = theme();
    const allPanes = panes();
    const all = spaces();
    const names = [null, ...machines().map((m) => m.name).filter((n) => n !== null)];
    for (const s of all) if (!names.includes(s.machine)) names.push(s.machine);
    const groups = names.map((name) => {
      const own = all.filter((s) => s.machine === name);
      const rows = [this.machineRow(name)];
      for (const space of own) {
        rows.push(this.spaceHeader(space));
        for (const tab of space.tabs ?? []) rows.push(this.tabRow(space, tab, allPanes));
      }
      if (!own.length) rows.push(this.newSessionRow(name ?? ""));
      return v_flex().gap(1).children(rows);
    });
    return v_flex().id("rex-list").size_full().bg(t.chrome).px(8).pt(2).pb(8).gap(18).overflow_y_scrollbar().children(groups);
  }

  render() {
    const part = props()?.part;
    if (part === "top") return this.top();
    if (part === "footer") return this.footer();
    return this.list();
  }
}
