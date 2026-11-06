import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, openOverlay, theme, shared, layout, window, settings, nextCommand } from "herdr";

const ICON = "mods/rex-tabs";
const stop = (_e, cx) => cx.stop_propagation();

function label(tab, tabPanes) {
  if (tab.named) return tab.name;
  const agent = tabPanes.find((p) => p.program?.agent);
  if (agent) return agent.title || agent.program.name;
  return tabPanes[0]?.program?.name ?? "Terminal";
}

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

function icon(program, t) {
  if (!program?.icon) return svg(`${ICON}/monitor.svg`).size(13).text_color(t.muted);
  const glyph = program.tint ? svg(program.icon).size(11).text_color(program.color ?? t.muted) : image(program.icon).size(11);
  return div().size(17).flex_none().rounded(5).when(Boolean(program.tile), (el) => el.bg(program.tile)).flex().items_center().justify_center().child(glyph);
}

export default class RexTabs extends View {
  init(_props, cx) {
    this.pressed = null;
    this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}");
    // The sidebar's list keys live here: this bar is always shown, the sidebar can be hidden.
    cx.spawn(async (cx) => {
      for (;;) {
        this.sidebarCommand(await nextCommand());
        cx.notify();
      }
    });
  }

  sidebarCommand(command) {
    const root = layout();
    const showing = find(root, "sidebar-lists")?.active ?? "spaces";
    if (command === "sidebar-switch") {
      run("layout.select", { stack: "sidebar-lists", child: showing === "spaces" ? "agents" : "spaces" });
      if (find(root, "sidebar")?.hidden) run("layout.show", { id: "sidebar" });
    } else if (command === "sidebar-down") {
      run(showing === "agents" ? "agent.next" : "space.next");
    } else if (command === "sidebar-up") {
      run(showing === "agents" ? "agent.prev" : "space.prev");
    } else if (command === "last-tab") {
      this.goLastTab();
    }
  }

  // Remembers the tab shown before this one, in any space.
  trackTab(all) {
    const space = all.find((s) => s.active);
    const tab = space?.tabs?.find((c) => c.active);
    if (!tab || tab.id === this.current?.tab) return;
    this.previous = this.current;
    this.current = { space: space.id, tab: tab.id };
  }

  goLastTab() {
    const last = this.previous;
    const space = last && spaces().find((s) => s.id === last.space);
    if (!space?.tabs?.some((c) => c.id === last.tab)) return;
    if (!space.active) run("space.select", { id: space.id });
    run("tab.select", { id: last.tab });
  }

  // Herdr's side panel behavior: each space remembers which panel it had open.
  syncPanel(space, panel, body, enabled) {
    if (!space || !panel) return;
    const now = panel.hidden ? null : body?.active ?? null;
    if (space.id !== this.space) {
      const first = this.space === undefined;
      this.space = space.id;
      this.pending = null;
      if (!(first && !(space.id in this.panels))) {
        const stored = this.panels[space.id] ?? null;
        const want = enabled.includes(stored) ? stored : null;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          if (want) { run("layout.select", { stack: "panel-body", child: want }); run("layout.show", { id: "panel" }); }
          else run("layout.hide", { id: "panel" });
          return;
        }
      }
    }
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[space.id] === now) return;
    this.panels[space.id] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  }

  panelButton(id, text, glyph, panel, body) {
    const t = theme();
    const on = panel && !panel.hidden && body?.active === id;
    return h_flex().id(`panel-${id}`).h(28).px(10).gap(6).flex_none().items_center().rounded_full().text_size(13)
      .border(1).border_color(on ? "#ffffff1a" : t.background)
      .bg(on ? t.selected : t.background).text_color(on ? t.foreground : t.muted)
      .hover((s) => s.bg(on ? t.selected : t.hover).text_color(t.foreground)).on_mouse_down("left", stop)
      .on_click(() => {
        if (on) run("layout.hide", { id: "panel" });
        else { run("layout.select", { stack: "panel-body", child: id }); run("layout.show", { id: "panel" }); }
      })
      .child(svg(`${ICON}/${glyph}.svg`).size(14))
      .child(text);
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
    const all = spaces();
    this.trackTab(all);
    const space = all.find((s) => s.active);
    const allPanes = panes();
    const root = layout();
    const panel = find(root, "panel");
    const body = find(root, "panel-body");
    const enabled = shared("workspace.panels") ?? ["files", "changes"];
    this.syncPanel(space, panel, body, enabled);
    // With the sidebar hidden or narrow, the macOS window buttons sit over this bar.
    const w = window();
    const sidebar = find(root, "sidebar");
    const lights = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      ? Math.max(10, (root.traffic_lights[0] + 64) / settings().zoom - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    return h_flex().size_full().min_w(0).px(10).pl(lights).gap(4).items_center().bg(t.background)
      .on_mouse_up("left", () => { this.pressed = null; })
      .child(h_flex().id("tab-scroll").flex_1().min_w(0).h_full().gap(4).items_center().overflow_x_scrollbar()
        .children((space?.tabs ?? []).map((tab, i) => this.tab(space, tab, i, allPanes))))
      .child(div().id("tab-new").size(26).flex_none().flex().items_center().justify_center().rounded_full().text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_mouse_down("left", stop)
        .on_click(() => openOverlay({ mod: "new-menu", kind: "popup", width: 250, height: 512 }))
        .child(svg(`${ICON}/plus.svg`).size(14)))
      .when(Boolean(panel) && enabled.includes("files"), (el) => el.child(this.panelButton("files", "Files", "file", panel, body)))
      .when(Boolean(panel) && enabled.includes("changes"), (el) => el.child(this.panelButton("changes", "Changes", "changes", panel, body)));
  }
}
