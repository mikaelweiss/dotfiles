-- Ports of Obsidian's list editing commands. Rows are 0-based, columns are byte offsets.
local api = vim.api
local parse = require("mdlive.parse")
local state = require("mdlive.state")
local config = require("mdlive.config")

local at = parse.at
local M = {}

local function lines_of(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function settings_of(buf)
  local b = state.get(buf)
  return b and b.settings or config.defaults
end

local function in_code(buf, row)
  local b = state.get(buf)
  local info = b and b:doc().rows[row]
  local t = info and info.block and info.block.type
  return t == "code" or t == "math" or t == "frontmatter" or t == "comment"
end

-- A view over buffer lines with Obsidian's per-line list facts (its nE helper).
local function view(buf)
  local lines = lines_of(buf)
  local cache = {}
  local v = { lines = lines, n = #lines }
  function v.info(row)
    if cache[row] then
      return cache[row]
    end
    local text = lines[row + 1]
    local res
    if text == nil or text:match("^[%s>]*$") then
      res = { blank = true, isItem = false, indent = 0, blockquote = 0, columns = 0, prefix = "" }
    else
      local m = at(text)
      local bq = parse.quote_depth(m.prefix)
      res = {
        blank = false,
        isItem = m.part ~= nil and not in_code(buf, row),
        indent = parse.indent_level(m.prefix),
        blockquote = bq,
        columns = parse.columns_after_quotes(m.prefix, bq),
        prefix = m.prefix,
      }
    end
    cache[row] = res
    return res
  end
  return v
end

local function is_child(n, i)
  if n.blockquote == i.blockquote then
    if n.indent > i.indent and n.columns > i.columns then
      return true
    end
    if n.isItem then
      return n.indent > i.indent
    end
    return n.columns > i.columns
  end
  return n.blockquote > i.blockquote and parse.columns_after_quotes(n.prefix, i.blockquote) > i.columns
end

function M.item_block(v, row)
  if row < 0 or row >= v.n then
    return nil
  end
  local e = v.info(row)
  if not e.isItem then
    return nil
  end
  local blk = { fromLine = row, toLine = row, indent = e.indent, blockquote = e.blockquote, columns = e.columns }
  for r = row + 1, v.n - 1 do
    local n = v.info(r)
    if not n.blank then
      if not is_child(n, blk) then
        break
      end
      blk.toLine = r
    end
  end
  return blk
end

local function first_child(v, row)
  local e = v.info(row)
  if not e.isItem then
    return nil
  end
  local blk = { indent = e.indent, blockquote = e.blockquote, columns = e.columns }
  for r = row + 1, v.n - 1 do
    local n = v.info(r)
    if not n.blank then
      return (n.isItem and n.blockquote == e.blockquote and is_child(n, blk)) and r or nil
    end
  end
end

local function neighbor(v, start, dir, blk)
  local stop = dir == -1 and -1 or v.n
  local r = start
  while r ~= stop do
    local a = v.info(r)
    if not (a.blank or is_child(a, blk)) then
      if a.isItem and a.blockquote == blk.blockquote then
        local s = M.item_block(v, r)
        return { kind = a.indent == blk.indent and "sibling" or "shallower", block = s }
      end
      if not (not a.isItem and a.blockquote >= blk.blockquote and parse.columns_after_quotes(a.prefix, blk.blockquote) > 0) then
        return { kind = a.isItem and "none" or "paragraph" }
      end
    end
    r = r + dir
  end
  return { kind = start == stop and "none" or "paragraph" }
end

local function has_prev_sibling(v, blk)
  return neighbor(v, blk.fromLine - 1, -1, blk).kind == "sibling"
end

local function cursor()
  local c = api.nvim_win_get_cursor(0)
  return c[1] - 1, c[2]
end

local function set_cursor(row, col)
  api.nvim_win_set_cursor(0, { row + 1, math.max(0, col) })
end

local function set_text(buf, r1, c1, r2, c2, repl)
  api.nvim_buf_set_text(buf, r1, c1, r2, c2, repl)
end

local function newline_only(buf, row, col)
  set_text(buf, row, col, row, col, { "", "" })
  set_cursor(row + 1, 0)
end

function M.newline_indent_only(buf)
  local row, col = cursor()
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local s = at(line)
  if s.full == "" or col < #s.full then
    return newline_only(buf, row, col)
  end
  local cont = s.prefix .. (s.part and s.part:gsub("\t", "    "):gsub(".", " ") or "")
  set_text(buf, row, col, row, col, { "", cont })
  set_cursor(row + 1, #cont)
end

-- Obsidian's newlineAndIndentContinueMarkdownList.
local function continue_list(buf, row, ch)
  local a = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local s = at(a)
  if s.full == "" then
    return false
  end
  local l, c, d, h, u, p, f = s.full, s.prefix, s.part, s.bullet, s.num, s.delim, s.cb
  local m = #l
  if ch < #l or (not d and c == "") then
    return false
  end
  if not d then
    for vr = row - 1, 0, -1 do
      local k = at(api.nvim_buf_get_lines(buf, vr, vr + 1, false)[1])
      if k.part and #k.full == m then
        l, c, d, h, u, p, f = k.full, k.prefix, k.part, k.bullet, k.num, k.delim, k.cb
        break
      end
      if #k.full < m then
        break
      end
    end
  end
  if vim.trim(a:sub(#l + 1)) == "" then
    if c == "" then
      set_text(buf, row, 0, row, ch, { "" })
      set_cursor(row, 0)
      return true
    end
    if c:sub(-1) == ">" or c:sub(-2) == "> " then
      if d then
        set_text(buf, row, #c, row, ch, { "" })
        set_cursor(row, #c)
        return true
      end
      local y = c:sub(-1) == ">" and 1 or 2
      local prev = row > 0 and api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      if prev == c then
        set_text(buf, row, #c - y, row, #c, { "" })
        set_text(buf, row - 1, #c - y, row - 1, #c, { "" })
        set_cursor(row, ch - y)
        return true
      end
      local k = c:sub(1, #c - y)
      set_text(buf, row, #c - y, row, #c, { "", k })
      set_cursor(row + 1, #k + ch - #c)
      return true
    end
    if c:sub(-1) == "\t" then
      set_text(buf, row, #c - 1, row, #c, { "" })
      set_cursor(row, ch - 1)
      return true
    end
    local vs = 0
    while vs < 4 and c:sub(#c - vs, #c - vs) == " " do
      vs = vs + 1
    end
    if vs > 0 then
      set_text(buf, row, #c - vs, row, #c, { "" })
      set_cursor(row, ch - vs)
      return true
    end
    set_text(buf, row, 0, row, #c, { "" })
    set_cursor(row, ch - #c)
    return true
  end
  if not d then
    set_text(buf, row, ch, row, ch, { "", c })
    set_cursor(row + 1, #c)
    return true
  end
  local g = h
  if u then
    g = tostring(tonumber(u) + 1) .. p
  end
  if f then
    g = g .. "[ ] "
  end
  local b = at(a:sub(ch + 1))
  if b.bullet then
    g = ""
  end
  local del = #b.prefix
  set_text(buf, row, ch, row, ch + del, { "", c .. g })
  set_cursor(row + 1, #c + #g)
  return true
end

local function item_text(line)
  local s = at(line)
  return s.part and vim.trim(line:sub(#s.full + 1)) ~= "", s
end

-- Enter at the end of a folded item adds a sibling after the fold (Obsidian's Cte).
local function folded_sibling(buf, row, col)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if col ~= #line or vim.fn.foldclosed(row + 1) ~= row + 1 then
    return false
  end
  local ok, s = item_text(line)
  if not ok then
    return false
  end
  local last = vim.fn.foldclosedend(row + 1) - 1
  local u = s.prefix .. (s.num and (tonumber(s.num) + 1 .. s.delim) or s.bullet) .. (s.cb and "[ ] " or "")
  local last_line = api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
  set_text(buf, last, #last_line, last, #last_line, { "", u })
  set_cursor(last + 1, #u)
  return true
end

-- Enter at the end of an item with children inserts a new first child (Obsidian's Ste).
local function first_child_item(buf, row, col)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if col ~= #line then
    return false
  end
  local ok = item_text(line)
  if not ok then
    return false
  end
  local v = view(buf)
  local child = first_child(v, row)
  if not child then
    return false
  end
  local k = at(v.lines[child + 1])
  local new = k.prefix .. k.bullet .. (k.cb and "[ ] " or "")
  set_text(buf, row, #line, row, #line, { "", new })
  set_cursor(row + 1, #new)
  return true
end

local function in_table_code_math(buf, row)
  local b = state.get(buf)
  local info = b and b:doc().rows[row]
  local t = info and info.block and info.block.type
  return t == "code" or t == "icode" or t == "math" or t == "table"
end

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "ni", false)
end

function M.enter()
  local buf = api.nvim_get_current_buf()
  local row, col = cursor()
  if not settings_of(buf).smartIndentList then
    return feed("<CR>")
  end
  if in_table_code_math(buf, row) then
    return M.newline_indent_only(buf)
  end
  if folded_sibling(buf, row, col) or first_child_item(buf, row, col) or continue_list(buf, row, col) then
    return
  end
  feed("<CR>")
end

function M.shift_enter()
  local buf = api.nvim_get_current_buf()
  if not settings_of(buf).smartIndentList then
    return feed("<CR>")
  end
  M.newline_indent_only(buf)
end

local function indent_string(settings, cols)
  if settings.useTab then
    local size = settings.tabSize or 4
    return string.rep("\t", math.floor(cols / size)) .. string.rep(" ", cols % size)
  end
  return string.rep(" ", cols)
end

local function after_quotes(line, depth)
  local e = 0
  for _ = 1, depth do
    local gt = line:find(">", e + 1, true)
    if not gt then
      break
    end
    e = gt
  end
  if depth > 0 and line:sub(e + 1, e + 1) == " " then
    e = e + 1
  end
  return e
end

-- Obsidian's indentMore / indentLess with smart list handling.
function M.indent(dir, srow, erow, has_selection)
  local buf = api.nvim_get_current_buf()
  local settings = settings_of(buf)
  local unit = config.indent_unit(settings)
  local v = view(buf)
  local changes = {}
  local function insert_at(row, col)
    changes[#changes + 1] = { row = row, s = col, e = col, text = unit }
  end
  local function dedent_at(row, pos)
    local line = v.lines[row + 1]
    local ws = line:sub(pos + 1):match("^[ \t]*")
    if ws == "" then
      return
    end
    local cols = parse.columns(ws, settings.tabSize or 4)
    local new = indent_string(settings, math.max(0, cols - 4))
    changes[#changes + 1] = { row = row, s = pos, e = pos + #ws, text = new }
  end
  local handled, left = {}, {}
  local checked = false
  local f = srow
  while f <= erow do
    if handled[f] then
      f = f + 1
    else
      local m = M.item_block(v, f)
      if dir > 0 and m and settings.smartIndentList and not checked then
        checked = true
        if not left[m.fromLine] and not has_prev_sibling(v, m) then
          return
        end
      end
      if not m or not settings.smartIndentList then
        local line = v.lines[f + 1]
        if dir > 0 then
          local prefix = line:match("^[%s>]+")
          local pos = 0
          if prefix then
            local c = prefix:match(".*()>")
            if c then
              pos = line:sub(c + 1, c + 1) == " " and c + 1 or c
            end
          end
          insert_at(f, pos)
        else
          local a = line:match("^[%s>]+")
          if a then
            local first_gt = a:find(">", 1, true)
            if first_gt and first_gt > 1 then
              changes[#changes + 1] = { row = f, s = 0, e = first_gt - 1, text = "" }
            elseif a ~= "> " then
              local c = a:match(".*()>")
              local pos = 0
              if c then
                pos = a:sub(c + 1, c + 1) == " " and c + 1 or c
              end
              dedent_at(f, pos)
            end
          end
        end
        handled[f] = true
        f = f + 1
      elseif dir < 0 and m.columns <= 0 then
        f = f + 1
      else
        local g = m.fromLine
        while g <= m.toLine do
          local b2 = (dir > 0 and has_selection and g > erow and not in_code(buf, g)) and M.item_block(v, g) or nil
          if b2 and b2.blockquote == m.blockquote then
            left[g] = true
            g = b2.toLine + 1
          else
            local pos = after_quotes(v.lines[g + 1], m.blockquote)
            if dir > 0 then
              insert_at(g, pos)
            else
              dedent_at(g, pos)
            end
            handled[g] = true
            g = g + 1
          end
        end
        f = m.toLine + 1
      end
    end
  end
  if #changes == 0 then
    return
  end
  local crow, ccol = cursor()
  table.sort(changes, function(x, y)
    return x.row > y.row
  end)
  for _, ch in ipairs(changes) do
    set_text(buf, ch.row, ch.s, ch.row, ch.e, { ch.text })
    if ch.row == crow and ccol >= ch.s then
      ccol = math.max(ch.s, ccol + #ch.text - (ch.e - ch.s))
    end
  end
  set_cursor(crow, ccol)
end

-- Obsidian's swap-line commands move a list item together with its children.
function M.move(dir)
  local buf = api.nvim_get_current_buf()
  local row = cursor()
  local v = view(buf)
  local t = M.item_block(v, row)
  local function plain()
    if dir < 0 and row > 0 then
      vim.cmd("silent! move .-2")
    elseif dir > 0 and row < v.n - 1 then
      vim.cmd("silent! move .+1")
    end
  end
  if not t or not settings_of(buf).smartIndentList then
    return plain()
  end
  local function swap(a, b, moving_first)
    local la = vim.list_slice(v.lines, a.fromLine + 1, a.toLine + 1)
    local lb = vim.list_slice(v.lines, b.fromLine + 1, b.toLine + 1)
    api.nvim_buf_set_lines(buf, b.fromLine, b.toLine + 1, false, la)
    api.nvim_buf_set_lines(buf, a.fromLine, a.toLine + 1, false, lb)
    local crow, ccol = cursor()
    local offset = crow - t.fromLine
    local new_start = moving_first and (b.toLine - #la + 1) or a.fromLine
    set_cursor(new_start + offset, ccol)
  end
  local target = neighbor(v, dir < 0 and t.fromLine - 1 or t.toLine + 1, dir, t)
  if target.kind == "sibling" then
    if dir < 0 then
      swap(target.block, t, false)
    else
      swap(t, target.block, true)
    end
  elseif target.kind == "paragraph" then
    local d = dir < 0 and t.fromLine - 1 or t.toLine + 1
    if d < 0 or d >= v.n then
      return
    end
    local single = { fromLine = d, toLine = d }
    if dir < 0 then
      swap(single, t, false)
    else
      swap(t, single, true)
    end
  elseif target.kind == "shallower" then
    local e = target.block
    if e.indent ~= t.indent - 1 then
      return
    end
    local block_lines = vim.list_slice(v.lines, t.fromLine + 1, t.toLine + 1)
    local crow, ccol = cursor()
    local offset = crow - t.fromLine
    local count = t.toLine - t.fromLine + 1
    if dir < 0 then
      if not has_prev_sibling(v, e) then
        return
      end
      api.nvim_buf_set_lines(buf, t.fromLine, t.toLine + 1, false, {})
      api.nvim_buf_set_lines(buf, e.fromLine, e.fromLine, false, block_lines)
      set_cursor(e.fromLine + offset, ccol)
    else
      local anchor
      for r = e.fromLine + 1, e.toLine do
        local ib = M.item_block(v, r)
        if ib and ib.blockquote == e.blockquote then
          anchor = r
          break
        end
      end
      api.nvim_buf_set_lines(buf, t.fromLine, t.toLine + 1, false, {})
      local at_row = anchor and anchor - count or e.toLine - count + 1
      api.nvim_buf_set_lines(buf, at_row, at_row, false, block_lines)
      set_cursor(at_row + offset, ccol)
    end
  end
end

-- Obsidian's toggleCheckList, including its cycle variant.
function M.toggle_checklist(srow, erow, cycle)
  local buf = api.nvim_get_current_buf()
  local lines = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  local e = 3
  local matches = {}
  for i, line in ipairs(lines) do
    local n = at(line)
    matches[i] = n
    if e > 2 and n.cb == " " then
      e = 2
    end
    if e > 1 and not n.cb then
      e = 1
    end
    if cycle and e > 0 and not n.bullet then
      e = 0
    end
  end
  local crow, ccol = cursor()
  for i, n in ipairs(matches) do
    local d = n.prefix .. (n.bullet or "- ")
    local new = d
    if e == 1 then
      if not n.cb then
        new = d .. "[ ] "
      end
    elseif e == 2 then
      new = d .. "[x] "
    elseif e == 3 and not cycle then
      new = d .. "[ ] "
    end
    local row = srow + i - 1
    set_text(buf, row, 0, row, #n.full, { new })
    if row == crow then
      ccol = ccol >= #n.full and ccol + #new - #n.full or math.min(ccol, #new)
    end
  end
  set_cursor(crow, ccol)
end

-- Ordered-list renumbering, ported from Obsidian's transaction filter.
local function block_start(s)
  return s:match("^%s*> ") ~= nil
    or s:match("^%s*#+ ") ~= nil
    or s:match("^%s*~~~") ~= nil
    or s:match("^%s*```") ~= nil
    or (s:match("^%s*([-_*])") and s:gsub("%s", ""):match("^([-_*])%1%1+$") ~= nil)
end

local function prev_sibling_number(lines, row, f, m, A)
  local seen_text = false
  for s = row - 1, 0, -1 do
    local l = lines[s + 1]
    local c = A(l)
    local d = parse.quote_depth(c.prefix)
    if l == "" or l == c.prefix then
      if m > d or seen_text then
        break
      end
    elseif c.full == "" then
      if m > 0 or block_start(l) then
        break
      end
      seen_text = true
    elseif not c.part then
      seen_text = true
    else
      local h = parse.indent_level(c.prefix)
      if h == f and d == m then
        return c.num and tonumber(c.num) or nil
      end
      if h < f or d < m then
        break
      end
    end
  end
end

local function first_number(lines, row, f, i, A)
  local n, seen_text = 1, false
  for s = row, 0, -1 do
    local l = lines[s + 1]
    if l == "" then
      if i > 0 or seen_text then
        break
      end
    else
      local c = A(l)
      if c.full == "" then
        if i > 0 or block_start(l) then
          break
        end
        seen_text = true
      elseif not c.part then
        seen_text = true
      else
        local d, h = parse.indent_level(c.prefix), parse.quote_depth(c.prefix)
        if d == f and h == i and c.num then
          n = tonumber(c.num)
        end
        if d < f or h < i then
          break
        end
      end
    end
  end
  return n
end

function M.renumber_changes(new, old, first, last, new_last)
  local cache = {}
  local function A(s)
    local r = cache[s]
    if not r then
      r = at(s)
      cache[s] = r
    end
    return r
  end
  local function old_row(row)
    if row < first then
      return row
    elseif row >= new_last then
      return row - (new_last - last)
    elseif last > first then
      return math.min(row, last - 1)
    end
    return math.max(first - 1, 0)
  end
  local changes, visited = {}, {}
  local function process(row)
    if visited[row] then
      return
    end
    visited[row] = true
    local u = A(new[row + 1])
    if u.full == "" or not u.num then
      return
    end
    local p = u.prefix
    local f, m = parse.indent_level(p), parse.quote_depth(p)
    local b = prev_sibling_number(new, row, f, m, A)
    if b == nil then
      b = 1
      local orow = old_row(row)
      local otext = old[orow + 1]
      local x = otext and A(otext)
      local changed_marker = row >= first and row < new_last and (not x or x.part ~= u.part)
      if changed_marker then
        b = tonumber(u.num)
      elseif x and parse.indent_level(x.prefix) == f then
        b = first_number(old, orow, f, parse.quote_depth(x.prefix), A)
      end
    else
      b = b + 1
    end
    if tostring(b) ~= u.num then
      changes[#changes + 1] = { row = row, s = #p, e = #p + #u.num, text = tostring(b), expect = new[row + 1] }
    end
    local blank_seen = false
    for y = row + 1, #new - 1 do
      if visited[y] then
        break
      end
      local k = new[y + 1]
      if k == "" then
        blank_seen = true
      else
        local E = A(k)
        if E.full == "" then
          if blank_seen or block_start(k) then
            break
          end
        elseif not (E.prefix ~= "" and not E.part) then
          local x, C = parse.indent_level(E.prefix), parse.quote_depth(E.prefix)
          if x == f and C == m then
            if not E.num then
              break
            end
            b = b + 1
            if tostring(b) == E.num then
              visited[y] = true
              break
            end
            changes[#changes + 1] = { row = y, s = #E.prefix, e = #E.prefix + #E.num, text = tostring(b), expect = k }
            visited[y] = true
          end
          if x < f then
            break
          end
        end
      end
    end
  end
  for row = first, new_last do
    if row < #new then
      process(row)
    end
  end
  return changes
end

return M
