-- Neutral grays replace tokyonight's navy base so only the accent colors carry hue.
-- on_colors runs after tokyonight derives its background colors, so those are rebuilt here too.
return {
  "folke/tokyonight.nvim",
  opts = {
    on_colors = function(c)
      local util = require("tokyonight.util")
      local grays = {
        bg = "#1e1e1e",
        bg_dark = "#1a1a1a",
        bg_dark1 = "#161616",
        bg_highlight = "#2c2c2c",
        fg = "#dadada",
        fg_dark = "#a3a3a3",
        fg_gutter = "#3a3a3a",
        comment = "#7a7a7a",
        dark3 = "#5c5c5c",
        dark5 = "#808080",
        terminal_black = "#4a4a4a",
      }
      for key, value in pairs(grays) do
        c[key] = value
      end
      util.bg, util.fg = c.bg, c.fg
      c.black = util.blend(c.bg, 0.8, "#000000")
      c.border = c.black
      c.bg_popup = c.bg_dark
      c.bg_statusline = c.bg_dark
      c.bg_sidebar = c.bg_dark
      c.bg_float = c.bg_dark
      c.bg_visual = util.blend(c.blue0, 0.4, c.bg)
      c.fg_sidebar = c.fg_dark
      c.fg_float = c.fg
      c.diff = {
        add = util.blend(c.green2, 0.25, c.bg),
        delete = util.blend(c.red1, 0.25, c.bg),
        change = util.blend(c.blue7, 0.15, c.bg),
        text = c.blue7,
      }
      c.git.ignore = c.dark3
    end,
  },
}
