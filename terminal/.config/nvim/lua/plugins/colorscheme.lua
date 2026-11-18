-- Neutral grays replace tokyonight's navy base so only the accent colors carry hue. The grays and the
-- markdown colors are sampled from Obsidian's default dark theme.
-- on_colors runs after tokyonight derives its background colors, so those are rebuilt here too.
return {
  "folke/tokyonight.nvim",
  opts = {
    on_colors = function(c)
      local util = require("tokyonight.util")
      local grays = {
        bg = "#1c1c1c",
        bg_dark = "#181818",
        bg_dark1 = "#151515",
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
    on_highlights = function(hl, c)
      local link = "#3f8df5"
      local code_bg = "#232323"
      for level = 1, 6 do
        hl["@markup.heading." .. level .. ".markdown"] = { fg = c.fg, bold = true }
      end
      hl["@markup.link"] = { fg = link }
      hl["@markup.link.label"] = { fg = link }
      hl["@markup.link.url"] = { fg = link, underline = true }
      hl["@markup.raw"] = { fg = c.fg, bg = code_bg }
      hl["@markup.raw.markdown_inline"] = { fg = c.fg, bg = code_bg }
      hl.WinSeparator = { fg = "#333333" }
    end,
  },
}
