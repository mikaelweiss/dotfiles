import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run, theme, props, window } from "herdr";

const ICON = "mods/rex-sidebar";
const stop = (_e, cx) => cx.stop_propagation();

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
    return h_flex().size_full().bg(t.chrome).pl(lights ? 88 : 12).pr(10).gap(2).items_center()
      .child(this.iconButton("toggle", svg(`${ICON}/sidebar.svg`).size(15), () => run("layout.toggle", { id: "sidebar" })))
      .child(div().flex_1())
      .child(this.iconButton("search", svg(`${ICON}/search.svg`).size(15), () => run("mod.open", { name: "picker" })))
      .child(this.iconButton("palette", div().text_size(15).child("⌘"), () => run("app.palette")));
  }

  footer() {
    const t = theme();
    return h_flex().size_full().bg(t.chrome).px(10).gap(2).items_center()
      .child(this.iconButton("settings", svg(`${ICON}/settings.svg`).size(15), () => run("mod.open", { name: "rex-settings" })))
      .child(div().flex_1())
      .child(this.iconButton("add-machine", svg(`${ICON}/server.svg`).size(15), () => run("mod.open", { name: "machine-add" })));
  }

  render() {
    const part = props()?.part;
    if (part === "top") return this.top();
    return this.footer();
  }
}
