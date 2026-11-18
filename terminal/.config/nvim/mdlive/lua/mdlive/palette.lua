local M = {}

M.ns = vim.api.nvim_create_namespace("mdlive.palette")

-- Values from Obsidian's default theme (app.css).
local themes = {
  dark = {
    base00 = "#1c1c1c",
    base10 = "#232323",
    base30 = "#333333",
    base50 = "#666666",
    base70 = "#b3b3b3",
    base100 = "#dadada",
    mono100 = "#ffffff",
    red = "#fb464c",
    orange = "#e9973f",
    yellow = "#e0de71",
    green = "#44cf6e",
    cyan = "#53dfdd",
    blue = "#027aff",
    purple = "#a882ff",
    pink = "#fa99cd",
  },
  light = {
    base00 = "#ffffff",
    base10 = "#fafafa",
    base30 = "#e4e4e4",
    base50 = "#ababab",
    base70 = "#5c5c5c",
    base100 = "#222222",
    mono100 = "#000000",
    red = "#e93147",
    orange = "#ec7500",
    yellow = "#e0ac00",
    green = "#08b94e",
    cyan = "#00bfbc",
    blue = "#086ddd",
    purple = "#7852ee",
    pink = "#d53984",
  },
}

M.callouts = {
  note = { color = "blue", icon = "󰏫" },
  abstract = { color = "cyan", icon = "󱃔" },
  summary = { color = "cyan", icon = "󱃔" },
  tldr = { color = "cyan", icon = "󱃔" },
  info = { color = "blue", icon = "󰋽" },
  todo = { color = "blue", icon = "󰗡" },
  important = { color = "cyan", icon = "󰈸" },
  tip = { color = "cyan", icon = "󰈸" },
  hint = { color = "cyan", icon = "󰈸" },
  success = { color = "green", icon = "󰄬" },
  check = { color = "green", icon = "󰄬" },
  done = { color = "green", icon = "󰄬" },
  question = { color = "orange", icon = "󰘥" },
  help = { color = "orange", icon = "󰘥" },
  faq = { color = "orange", icon = "󰘥" },
  warning = { color = "orange", icon = "󰀪" },
  caution = { color = "orange", icon = "󰀪" },
  attention = { color = "orange", icon = "󰀪" },
  failure = { color = "red", icon = "󰅖" },
  fail = { color = "red", icon = "󰅖" },
  missing = { color = "red", icon = "󰅖" },
  danger = { color = "red", icon = "󱐋" },
  error = { color = "red", icon = "󱐋" },
  bug = { color = "red", icon = "󰃤" },
  example = { color = "purple", icon = "󰉹" },
  quote = { color = "quote", icon = "󰉾" },
  cite = { color = "quote", icon = "󰉾" },
}

local function rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function to_hex(r, g, b)
  local function c(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return string.format("#%02x%02x%02x", c(r), c(g), c(b))
end

function M.mix(fg, bg, alpha)
  local r1, g1, b1 = rgb(fg)
  local r2, g2, b2 = rgb(bg)
  return to_hex(r1 * alpha + r2 * (1 - alpha), g1 * alpha + g2 * (1 - alpha), b1 * alpha + b2 * (1 - alpha))
end

local function hex_to_hsl(hex)
  local r, g, b = rgb(hex)
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  if max == min then
    return 0, 0, l * 100
  end
  local d = max - min
  local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
  local h
  if max == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, s * 100, l * 100
end

local function hsl(h, s, l)
  h = (h % 360) / 360
  s = math.min(100, s) / 100
  l = math.min(100, l) / 100
  if s == 0 then
    return to_hex(l * 255, l * 255, l * 255)
  end
  local function hue(p, q, t)
    if t < 0 then
      t = t + 1
    elseif t > 1 then
      t = t - 1
    end
    if t < 1 / 6 then
      return p + (q - p) * 6 * t
    elseif t < 1 / 2 then
      return q
    elseif t < 2 / 3 then
      return p + (q - p) * (2 / 3 - t) * 6
    end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return to_hex(hue(p, q, h + 1 / 3) * 255, hue(p, q, h) * 255, hue(p, q, h - 1 / 3) * 255)
end

function M.colors(settings)
  local mode = vim.o.background == "light" and "light" or "dark"
  local t = vim.deepcopy(themes[mode])
  local h, s, l = 258, 88, 66
  if settings.accentColor and settings.accentColor:match("^#%x%x%x%x%x%x$") then
    h, s, l = hex_to_hsl(settings.accentColor)
  end
  local accent = hsl(h, s, l)
  if mode == "dark" then
    t.text_accent = hsl(h - 3, s * 1.02, l * 1.15)
    t.interactive = accent
  else
    t.text_accent = accent
    t.interactive = hsl(h - 1, s * 1.01, l * 1.075)
  end
  t.bg = t.base00
  t.code_bg = t.base10
  t.border = t.base30
  t.faint = t.base50
  t.muted = t.base70
  t.text = t.base100
  t.quote = "#9e9e9e"
  return t
end

local function define(groups)
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

function M.apply(settings)
  local c = M.colors(settings)
  M.current = c
  local bg = c.bg
  local tag_bg = M.mix(c.interactive, bg, 0.1)
  local guide = M.mix(c.mono100, bg, 0.12)
  local groups = {
    MdText = { fg = c.text },
    MdInlineTitle = { fg = c.text, bold = true },
    MdHeadingMarker = { fg = c.faint },
    MdBold = { bold = true },
    MdItalic = { italic = true },
    MdStrike = { strikethrough = true },
    MdHighlight = { bg = M.mix(c.yellow, bg, 0.3), fg = c.text },
    MdCode = { bg = c.code_bg, fg = c.text },
    MdCodeBlock = { bg = c.code_bg },
    MdCodeFence = { fg = c.text, bg = c.code_bg },
    MdCodeLang = { fg = c.muted, bg = c.code_bg },
    MdFormatting = { fg = c.faint },
    MdLink = { fg = c.text_accent, underline = true, sp = c.text_accent },
    MdLinkUnresolved = {
      fg = M.mix(c.text_accent, bg, 0.7),
      underline = true,
      sp = M.mix(c.interactive, bg, 0.3),
    },
    MdUrl = { fg = c.text_accent, underline = true, sp = c.text_accent },
    MdExternalIcon = { fg = c.muted },
    MdTag = { fg = c.text_accent, bg = tag_bg },
    MdTagEdge = { fg = tag_bg },
    MdPill = { fg = c.text, bg = M.mix(c.mono100, bg, 0.067) },
    MdPillEdge = { fg = M.mix(c.mono100, bg, 0.067) },
    MdListMarker = { fg = c.faint },
    MdIndentGuide = { fg = guide },
    MdIndentGuideActive = { fg = M.mix(c.mono100, bg, 0.3) },
    MdCheckbox = { fg = c.faint },
    MdCheckboxChecked = { fg = c.interactive },
    MdTaskMarker = { fg = c.muted },
    MdTaskDone = { fg = c.muted, strikethrough = true },
    MdQuoteBar = { fg = c.interactive },
    MdQuoteMarker = { fg = c.faint },
    MdHr = { fg = c.border },
    MdHrRaw = { fg = c.muted },
    MdTableBorder = { fg = c.border },
    MdTableHeader = { bold = true },
    MdComment = { fg = c.faint },
    MdMath = { fg = c.text, italic = true },
    MdFootref = { fg = c.muted },
    MdFootnoteMarker = { fg = c.faint },
    MdBlockId = { fg = c.muted },
    MdEmbedBorder = { fg = c.interactive },
    MdPropHeading = { fg = c.text, bold = true },
    MdPropKey = { fg = c.muted },
    MdPropIcon = { fg = c.muted },
    MdPropValue = { fg = c.text },
    MdFrontmatter = { fg = c.muted },
    MdFoldEllipsis = { fg = c.muted },
  }
  for i = 1, 6 do
    groups["MdH" .. i] = { fg = c.text, bold = true }
  end
  for name, spec in pairs(M.callouts) do
    local color = c[spec.color]
    local cap = name:sub(1, 1):upper() .. name:sub(2)
    groups["MdCallout" .. cap] = { fg = color, bold = true }
    groups["MdCallout" .. cap .. "Bg"] = { bg = M.mix(color, bg, 0.1) }
  end
  define(groups)
  M.apply_window_ns(c)
end

-- Code-block token colors only apply inside markdown windows, so the rest of the editor keeps its theme.
function M.apply_window_ns(c)
  local ns = M.ns
  local function set(names, spec)
    for _, name in ipairs(names) do
      vim.api.nvim_set_hl(ns, name, spec)
    end
  end
  set({ "Normal", "NormalNC" }, { fg = c.text, bg = c.bg })
  set({ "EndOfBuffer" }, { fg = c.bg, bg = c.bg })
  set({ "Visual" }, { bg = M.mix(c.interactive, c.bg, 0.33) })
  set({ "Folded" }, { fg = c.text, bg = c.bg })
  set({ "SpellBad" }, { undercurl = true, sp = c.red })
  set({ "SpellCap", "SpellRare", "SpellLocal" }, {})
  set({ "Conceal" }, { fg = c.faint })
  set({ "SignColumn", "FoldColumn" }, { bg = c.bg })
  set({ "@comment", "@comment.documentation" }, { fg = c.faint })
  set({ "@tag", "@constant", "@constant.builtin", "@constant.macro", "@string.special.symbol", "@diff.minus" }, { fg = c.red })
  set({ "@punctuation", "@punctuation.bracket", "@punctuation.delimiter", "@punctuation.special" }, { fg = c.muted })
  set({ "@boolean", "@number", "@number.float" }, { fg = c.purple })
  set({ "@string", "@string.documentation", "@character", "@tag.attribute", "@diff.plus", "@attribute.builtin" }, { fg = c.green })
  set({ "@operator" }, { fg = c.red })
  set({
    "@property",
    "@variable",
    "@variable.member",
    "@variable.parameter",
    "@variable.parameter.builtin",
    "@string.special.url",
    "@label",
    "@module",
  }, { fg = c.cyan })
  set({
    "@function",
    "@function.call",
    "@function.builtin",
    "@function.macro",
    "@function.method",
    "@function.method.call",
    "@constructor",
    "@type",
    "@type.definition",
    "@attribute",
    "@variable.builtin",
    "@module.builtin",
  }, { fg = c.yellow })
  set({
    "@keyword",
    "@keyword.function",
    "@keyword.operator",
    "@keyword.return",
    "@keyword.conditional",
    "@keyword.conditional.ternary",
    "@keyword.repeat",
    "@keyword.import",
    "@keyword.exception",
    "@keyword.modifier",
    "@keyword.type",
    "@keyword.coroutine",
    "@keyword.debug",
    "@keyword.directive",
    "@keyword.directive.define",
    "@keyword.storage",
    "@type.builtin",
    "@type.qualifier",
  }, { fg = c.pink })
  set({ "@string.regexp", "@string.escape", "@string.special" }, { fg = c.orange })
  set({ "@none", "@variable.other", "@markup", "@spell", "@nospell" }, {})
end

function M.attach_window(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, M.ns)
  end
end

function M.detach_window(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, 0)
  end
end

return M
