local M = {}

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

-- Callout kinds borrow the colorscheme's diagnostic and syntax colors.
local roles = {
  blue = { "DiagnosticInfo" },
  cyan = { "DiagnosticHint" },
  green = { "DiagnosticOk", "String" },
  orange = { "DiagnosticWarn" },
  red = { "DiagnosticError" },
  purple = { "Keyword", "Statement" },
  quote = { "Comment" },
}

local function hl(name)
  local ok, spec = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and spec or {}
end

local function first(...)
  for _, name in ipairs({ ... }) do
    if next(hl(name)) then
      return name
    end
  end
  return select(select("#", ...), ...)
end

local function hex(n)
  return n and string.format("#%06x", n) or nil
end

local function fg(...)
  for _, name in ipairs({ ... }) do
    local c = hl(name).fg
    if c then
      return hex(c)
    end
  end
end

local function bg(...)
  for _, name in ipairs({ ... }) do
    local c = hl(name).bg
    if c then
      return hex(c)
    end
  end
end

local function rgb(h)
  h = h:gsub("#", "")
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end

function M.mix(a, b, alpha)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function c(x, y)
    return math.floor(x * alpha + y * (1 - alpha) + 0.5)
  end
  return string.format("#%02x%02x%02x", c(r1, r2), c(g1, g2), c(b1, b2))
end

function M.apply()
  local base = bg("Normal") or (vim.o.background == "light" and "#ffffff" or "#000000")
  local text = fg("Normal") or (vim.o.background == "light" and "#000000" or "#ffffff")
  local link = first("@markup.link.label", "@markup.link", "Underlined")
  local link_fg = fg(link) or text
  local faint = first("Comment")
  local faint_fg = fg(faint) or text
  -- Claude Code's inline code color, its dark theme "permission" color.
  local code_fg = vim.o.background == "light" and "#5769f7" or "#b1b9f9"
  local tag_fg = fg("@markup.link.label", "Special") or link_fg
  local tag_bg = M.mix(tag_fg, base, 0.15)
  local pill_bg = bg("CursorLine") or M.mix(text, base, 0.08)
  -- Resolved to a color rather than linked, since note windows remap WinSeparator to hide their edges.
  local border = fg("WinSeparator", "NonText") or M.mix(text, base, 0.2)
  -- Headings match Claude Code: the top level is bold, italic and underlined, the rest only bold.
  local function heading(level)
    return { fg = text, bold = true, italic = level == 1, underline = level == 1 }
  end
  local groups = {
    MdText = { link = "Normal" },
    MdInlineTitle = heading(1),
    MdHeadingMarker = { link = faint },
    MdBold = { link = first("@markup.strong", "Bold") },
    MdItalic = { link = first("@markup.italic", "Italic") },
    MdStrike = { link = first("@markup.strikethrough") },
    MdHighlight = { link = "Search" },
    MdCode = { fg = code_fg },
    MdCodeBlock = {},
    MdCodeFence = { fg = faint_fg },
    MdCodeLang = { fg = faint_fg },
    MdFormatting = { link = faint },
    MdLink = { fg = link_fg, underline = true, sp = link_fg },
    MdLinkUnresolved = { fg = M.mix(link_fg, base, 0.6), underline = true, sp = M.mix(link_fg, base, 0.3) },
    MdUrl = { link = first("@markup.link.url", "Underlined") },
    MdExternalIcon = { link = faint },
    MdTag = { fg = tag_fg, bg = tag_bg },
    MdTagEdge = { fg = tag_bg },
    MdPill = { fg = text, bg = pill_bg },
    MdPillEdge = { fg = pill_bg },
    MdListMarker = { link = "Normal" },
    MdIndentGuide = { link = first("SnacksIndent", "IblIndent", "NonText") },
    MdIndentGuideActive = { link = first("SnacksIndentScope", "IblScope", "Comment") },
    MdCheckbox = { link = first("@markup.list.unchecked", "@markup.list") },
    MdCheckboxChecked = { link = first("@markup.list.checked", "DiagnosticOk") },
    MdTaskMarker = { link = first("@markup.list") },
    MdTaskDone = { fg = faint_fg, strikethrough = true },
    MdQuoteBar = { fg = fg("@markup.quote", "Comment") or faint_fg },
    MdQuoteMarker = { link = faint },
    MdHr = { fg = border },
    MdHrRaw = { link = faint },
    MdTableBorder = { fg = border },
    MdTableHeader = { bold = true },
    MdComment = { link = faint },
    MdMath = { link = first("@markup.math", "Special") },
    MdFootref = { link = faint },
    MdFootnoteMarker = { link = faint },
    MdBlockId = { link = faint },
    MdEmbedBorder = { fg = fg("@markup.quote", "Comment") or faint_fg },
    MdPropHeading = { bold = true },
    MdPropKey = { link = faint },
    MdPropIcon = { link = faint },
    MdPropValue = { link = "Normal" },
    MdFrontmatter = { link = faint },
    MdFoldEllipsis = { link = faint },
  }
  for i = 1, 6 do
    groups["MdH" .. i] = heading(i)
  end
  for name, spec in pairs(M.callouts) do
    local color = fg(unpack(roles[spec.color])) or text
    local cap = name:sub(1, 1):upper() .. name:sub(2)
    groups["MdCallout" .. cap] = { fg = color, bold = true }
    groups["MdCallout" .. cap .. "Bg"] = { bg = M.mix(color, base, 0.1) }
  end
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

return M
