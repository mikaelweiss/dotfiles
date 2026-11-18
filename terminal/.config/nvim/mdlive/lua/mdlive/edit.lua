local api = vim.api
local state = require("mdlive.state")
local lists = require("mdlive.lists")

local M = {}

local track_ns = api.nvim_create_namespace("mdlive.pairs")
local CLOSE = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }
local CLOSE_BEFORE = ")]}:;>"

local function closing(tok)
  local c = tok:sub(1, 1)
  return CLOSE[c] or c
end

function M.tokens(settings)
  local list = {}
  if settings.autoPairBrackets then
    vim.list_extend(list, { "(", "[", "{", "'", '"' })
  end
  if settings.autoPairMarkdown then
    vim.list_extend(list, { "*", "_", "`", "```" })
  end
  return list
end

local function is_word(c)
  return c ~= "" and (c:match("[%w_]") ~= nil or c:byte() >= 128)
end

local function cursor()
  local c = api.nvim_win_get_cursor(0)
  return c[1] - 1, c[2]
end

local function tracked(row, col)
  return #api.nvim_buf_get_extmarks(0, track_ns, { row, col }, { row, col }, {}) > 0
end

-- Runs from a <Cmd> appended to the inserted keys, so the cursor already sits on the closer.
function M.track()
  local c = api.nvim_win_get_cursor(0)
  pcall(api.nvim_buf_set_extmark, 0, track_ns, c[1] - 1, c[2], {})
end

local TRACK = "<Cmd>lua require('mdlive.edit').track()<CR>"

-- CodeMirror skips pairing when the typed mark would close an emphasis or code span.
local function closes_span(before, tok)
  local test = before .. tok
  for _, sp in ipairs(require("mdlive.inline").parse(test)) do
    if sp.e == #test and (sp.t == "em" or sp.t == "strong" or sp.t == "code") then
      return true
    end
  end
  return false
end

local function untrack(row, col)
  for _, m in ipairs(api.nvim_buf_get_extmarks(0, track_ns, { row, col }, { row, col }, {})) do
    api.nvim_buf_del_extmark(0, track_ns, m[1])
  end
end

function M.clear_tracking(buf)
  api.nvim_buf_clear_namespace(buf, track_ns, 0, -1)
end

local LEFT = "<C-g>U<Left>"
local RIGHT = "<C-g>U<Right>"

-- CodeMirror's closeBrackets, configured the way Obsidian configures it.
function M.key(ch)
  local b = state.get(api.nvim_get_current_buf())
  if not b then
    return ch
  end
  local row, col = cursor()
  local line = api.nvim_get_current_line()
  local next_char = line:sub(col + 1, col + 1)
  local tokens = M.tokens(b.settings)
  local has_triple = vim.tbl_contains(tokens, "```")
  for _, tok in ipairs(tokens) do
    local close = closing(tok)
    if ch == tok then
      if close == tok then
        if next_char == tok then
          if tracked(row, col) then
            untrack(row, col)
            if tok == "`" and has_triple and line:sub(col + 1, col + 3) == "```" then
              return RIGHT .. RIGHT .. RIGHT
            end
            return RIGHT
          end
          return ch
        end
        if tok == "`" and has_triple and col >= 2 and line:sub(col - 1, col) == "``" and not is_word(line:sub(col - 2, col - 2)) then
          return "````" .. LEFT .. LEFT .. LEFT .. TRACK
        end
        if
          not is_word(next_char)
          and (col == 0 or not is_word(line:sub(col, col)))
          and not ((tok == "*" or tok == "_" or tok == "`") and closes_span(line:sub(1, col), tok))
        then
          return tok .. tok .. LEFT .. TRACK
        end
        return ch
      end
      if next_char == "" or next_char:match("%s") or CLOSE_BEFORE:find(next_char, 1, true) then
        return tok .. close .. LEFT .. TRACK
      end
      return ch
    end
    if ch == close and tracked(row, col) then
      if next_char == close then
        untrack(row, col)
        return RIGHT
      end
      return ch
    end
  end
  return ch
end

function M.backspace()
  local b = state.get(api.nvim_get_current_buf())
  local _, col = cursor()
  local line = api.nvim_get_current_line()
  if b and col > 0 then
    local before, after = line:sub(col, col), line:sub(col + 1, col + 1)
    for _, tok in ipairs(M.tokens(b.settings)) do
      if tok == before and after == closing(tok) then
        return "<BS><Del>"
      end
    end
  end
  return "<BS>"
end

local SURROUND = {
  bold = "**",
  italic = "*",
  code = "`",
  highlight = "==",
  strikethrough = "~~",
  comment = "%%",
  math = "$",
}
local SPAN = {
  bold = "strong",
  italic = "em",
  code = "code",
  highlight = "highlight",
  strikethrough = "strike",
  comment = "comment",
  math = "math",
}

-- Returns the selection as 0-based rows and end-exclusive columns, leaving visual mode.
local function take_selection()
  local mode = api.nvim_get_mode().mode
  local row, col = cursor()
  if mode == "v" or mode == "V" or mode == "\22" then
    local v = vim.fn.getpos("v")
    local sr, sc, er, ec = v[2] - 1, v[3] - 1, row, col
    if sr > er or (sr == er and sc > ec) then
      sr, sc, er, ec = er, ec, sr, sc
    end
    local last = api.nvim_buf_get_lines(0, er, er + 1, false)[1]
    if mode == "V" then
      sc, ec = 0, #last
    else
      local ch = last:sub(ec + 1):match("^[%z\1-\127\194-\244][\128-\191]*") or ""
      ec = ec + #ch
    end
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    return { srow = sr, scol = sc, erow = er, ecol = ec, visual = true }
  end
  return { srow = row, scol = col, erow = row, ecol = col, insert = mode:sub(1, 1) == "i" }
end

local function reselect(sr, sc, er, ec)
  api.nvim_buf_set_mark(0, "<", sr + 1, sc, {})
  api.nvim_buf_set_mark(0, ">", er + 1, math.max(sc, ec - 1), {})
  vim.cmd("normal! gv")
end

local function word_at(line, col)
  local s, e = col, col
  while s > 0 and is_word(line:sub(s, s)) do
    s = s - 1
  end
  while e < #line and is_word(line:sub(e + 1, e + 1)) do
    e = e + 1
  end
  if s == e then
    return nil
  end
  return s, e
end

-- Obsidian's toggleMarkdownFormatting.
function M.toggle(kind)
  local buf = api.nvim_get_current_buf()
  local b = state.get(buf)
  if not b then
    return
  end
  local chars = SURROUND[kind]
  local sel = take_selection()
  local doc = b:doc()
  local function inside_span(row, s, e)
    for _, sp in ipairs(doc:inlines(row)) do
      if sp.t == SPAN[kind] and sp.s <= s and e <= sp.e then
        return sp
      end
    end
  end
  if sel.srow == sel.erow then
    local sp = inside_span(sel.srow, sel.scol, sel.ecol)
    if sp and not sp.open then
      local open_len, close_s, close_e
      if sp.ms then
        open_len, close_s, close_e = sp.ms[1][2] - sp.ms[1][1], sp.ms[2][1], sp.ms[2][2]
      else
        open_len, close_s, close_e = 2, sp.e - 2, sp.e
      end
      api.nvim_buf_set_text(buf, sel.srow, close_s, sel.srow, close_e, { "" })
      api.nvim_buf_set_text(buf, sel.srow, sp.s, sel.srow, sp.s + open_len, { "" })
      if sel.visual then
        reselect(sel.srow, math.max(sp.s, sel.scol - open_len), sel.erow, math.min(close_s - open_len, sel.ecol - open_len))
      else
        api.nvim_win_set_cursor(0, { sel.srow + 1, math.max(sp.s, sel.scol - open_len) })
      end
      return
    end
  end
  local n = #chars
  if not sel.visual then
    local line = api.nvim_get_current_line()
    local s, e = word_at(line, sel.scol)
    if s then
      api.nvim_buf_set_text(buf, sel.srow, e, sel.srow, e, { chars })
      api.nvim_buf_set_text(buf, sel.srow, s, sel.srow, s, { chars })
      api.nvim_win_set_cursor(0, { sel.srow + 1, sel.scol + n })
    else
      api.nvim_buf_set_text(buf, sel.srow, sel.scol, sel.srow, sel.scol, { chars .. chars })
      api.nvim_win_set_cursor(0, { sel.srow + 1, sel.scol + n })
    end
    return
  end
  local first_shift, last_shift = 0, 0
  for row = sel.erow, sel.srow, -1 do
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    local info = doc.rows[row]
    local t = info and info.block and info.block.type
    local skip = sel.srow ~= sel.erow and (t == "code" or t == "table" or t == "math")
    local s = row == sel.srow and sel.scol or 0
    local e = row == sel.erow and sel.ecol or #line
    while s < e and line:sub(s + 1, s + 1):match("%s") do
      s = s + 1
    end
    while e > s and line:sub(e, e):match("%s") do
      e = e - 1
    end
    if not skip and e > s then
      api.nvim_buf_set_text(buf, row, e, row, e, { chars })
      api.nvim_buf_set_text(buf, row, s, row, s, { chars })
      if row == sel.srow then
        first_shift = n
      end
      if row == sel.erow then
        last_shift = n
      end
    end
  end
  reselect(sel.srow, sel.scol + first_shift, sel.erow, sel.ecol + last_shift)
end

-- Obsidian's insertMarkdownLink: `[selection]()` with the cursor where the next input goes.
function M.insert_link()
  local sel = take_selection()
  local buf = api.nvim_get_current_buf()
  if sel.visual and sel.srow == sel.erow then
    local line = api.nvim_buf_get_lines(buf, sel.srow, sel.srow + 1, false)[1]
    local selected = line:sub(sel.scol + 1, sel.ecol)
    api.nvim_buf_set_text(buf, sel.srow, sel.scol, sel.srow, sel.ecol, { "[" .. selected .. "]()" })
    api.nvim_win_set_cursor(0, { sel.srow + 1, sel.scol + #selected + 3 })
  else
    api.nvim_buf_set_text(buf, sel.srow, sel.scol, sel.srow, sel.scol, { "[]()" })
    api.nvim_win_set_cursor(0, { sel.srow + 1, sel.scol + 1 })
  end
  if not sel.insert then
    vim.cmd("startinsert")
  end
end

function M.toggle_checklist(cycle)
  local sel = take_selection()
  lists.toggle_checklist(sel.srow, sel.erow, cycle)
end

function M.indent(dir)
  local row = cursor()
  lists.indent(dir, row, row, false)
end

return M
