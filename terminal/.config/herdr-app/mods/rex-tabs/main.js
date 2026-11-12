import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { agents, spaces, panes, run, openOverlay, theme, shared, layout, window, settings, nextCommand, appHome, readTextFile, writeTextFile } from "herdr";
import * as fs from "fs/promises";

// Rex-style program cards, built by mods/rex-tabs/cards/build.py. Programs without one keep their plain glyph.
let cards = new Set();
async function loadCards() {
  try {
    cards = new Set((await fs.readdir(`${appHome()}/mods/rex-tabs/cards`)).filter((f) => f.endsWith(".svg")).map((f) => f.slice(0, -4)));
  } catch {
    cards = new Set();
  }
}
const cardOf = (p) => (p?.key && cards.has(p.key) ? `mods/rex-tabs/cards/${p.key}.svg` : null);


const ICON = "mods/rex-tabs";
const stop = (_e, cx) => cx.stop_propagation();
// Rex's glass edge: a bright outer hairline over a softer inner one.
const rim = () => div().absolute().inset_0().rounded_full().border(0.5).border_color("#ffffff12");

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
  if (cardOf(program)) return image(cardOf(program)).w(22).h(18).flex_none();
  if (!program?.icon) return svg(`${ICON}/monitor.svg`).size(13).text_color(t.muted);
  const glyph = program.tint ? svg(program.icon).size(11).text_color(program.color ?? t.muted) : image(program.icon).size(11);
  return div().size(17).flex_none().rounded(5).when(Boolean(program.tile), (el) => el.bg(program.tile)).flex().items_center().justify_center().child(glyph);
}

export default class RexTabs extends View {
  init(_props, cx) {
    this.pressed = null;
    this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}");
    cx.spawn(async (cx) => { await loadCards(); cx.notify(); });
    // The sidebar's list keys live here: this bar is always shown, the sidebar can be hidden.
    cx.spawn(async (cx) => {
      for (;;) {
        this.sidebarCommand(await nextCommand());
        cx.notify();
      }
    });
  }

  // Steps through the agents list as shown, wrapping at the ends.
  stepAgent(by) {
    const order = shared("agents.order") ?? [];
    if (!order.length) return run(by > 0 ? "agent.next" : "agent.prev");
    const at = order.indexOf(agents().find((a) => a.focused)?.address);
    const next = at < 0 ? (by > 0 ? 0 : order.length - 1) : (at + by + order.length) % order.length;
    run("agent.focus", { terminal: order[next] });
  }

  sidebarCommand(command) {
    const root = layout();
    const showing = find(root, "agents")?.hidden ? "spaces" : find(root, "spaces")?.hidden ? "agents" : "both";
    if (command === "sidebar-switch") {
      const next = { spaces: "agents", agents: "both", both: "spaces" }[showing];
      run(next === "agents" ? "layout.hide" : "layout.show", { id: "spaces" });
      run(next === "spaces" ? "layout.hide" : "layout.show", { id: "agents" });
      if (find(root, "sidebar")?.hidden) run("layout.show", { id: "sidebar" });
    } else if (command === "sidebar-down") {
      showing === "spaces" ? run("space.next") : this.stepAgent(1);
    } else if (command === "sidebar-up") {
      showing === "spaces" ? run("space.prev") : this.stepAgent(-1);
    } else if (command === "last-tab") {
      this.goLastTab();
    } else if (command === "zoom-in" || command === "zoom-out") {
      this.zoomBy(command === "zoom-in" ? 0.05 : -0.05);
    }
  }

  // 5% steps: Herdr's zoom commands move 10% at a time.
  async zoomBy(step) {
    const file = `${appHome()}/settings.json`;
    for (let attempt = 0; attempt < 3; attempt++) {
      const raw = await readTextFile(file);
      const person = raw ? JSON.parse(raw) : {};
      person.zoom = Math.max(0.5, Math.min(3, Math.round(((person.zoom ?? 1) + step) * 100) / 100));
      try {
        await writeTextFile(file, JSON.stringify(person, null, 2) + "\n", raw);
        return;
      } catch {}
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
    return h_flex().id(`panel-${id}`).relative().h(28).px(10).gap(6).flex_none().items_center().rounded_full().text_size(13)
      .border(0.5).border_color(on ? "#ffffff29" : t.background)
      .when(on, (el) => el.child(rim()))
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
    return h_flex().id(`tab-${tab.id}`).relative().h(28).pl(8).pr(tab.active ? 6 : 12).gap(7).flex_none().items_center().rounded_full().text_size(13)
      .border(0.5).border_color(tab.active ? "#ffffff29" : t.background)
      .when(tab.active, (el) => el.child(rim()))
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
