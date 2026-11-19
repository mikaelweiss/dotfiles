-- The base colors match Ghostty's default theme so Neovim blends into the terminal, as Claude Code does.
-- on_colors runs after tokyonight derives its background colors, so those are rebuilt here too.
return {
  "folke/tokyonight.nvim",
  opts = {
    on_colors = function(c)
      local util = require("tokyonight.util")
      local bg, fg = "#282c34", "#ffffff"
      local function tint(alpha)
        return util.blend(fg, alpha, bg)
      end
      local grays = {
        bg = bg,
        bg_dark = util.blend("#000000", 0.15, bg),
        bg_dark1 = util.blend("#000000", 0.25, bg),
        bg_highlight = tint(0.06),
        fg = fg,
        fg_dark = tint(0.7),
        fg_gutter = tint(0.15),
        comment = tint(0.45),
        dark3 = tint(0.3),
        dark5 = tint(0.5),
        terminal_black = tint(0.2),
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
      for level = 1, 6 do
        hl["@markup.heading." .. level .. ".markdown"] = { fg = c.fg, bold = true }
      end
      hl["@markup.link"] = { fg = link }
      hl["@markup.link.label"] = { fg = link }
      hl["@markup.link.url"] = { fg = link, underline = true }
      hl["@markup.raw"] = { fg = c.fg }
      hl["@markup.raw.markdown_inline"] = { fg = c.fg }
      hl.WinSeparator = { fg = c.fg_gutter }
    end,
  },
}
