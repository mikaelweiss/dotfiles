-- Rows are 0-based. Columns are 0-based byte offsets.
local inline = require("mdlive.inline")

local M = {}

-- Port of Obsidian's list regex: /^([>\s]*)(([*+-] |(\d+)([.)] ))(?:\[(.)\] )?)?/
function M.at(line)
  local prefix = line:match("^[>%s]*")
  local rest = line:sub(#prefix + 1)
  local bullet, num, delim = rest:match("^([*+-] )"), nil, nil
  if not bullet then
    num, delim = rest:match("^(%d+)([.)] )")
    if num then
      bullet = num .. delim
    end
  end
  local cb, part
  if bullet then
    local box = rest:sub(#bullet + 1):match("^%[([%z\1-\127\194-\244][\128-\191]*)%] ")
    if box then
      cb = box
      part = bullet .. "[" .. box .. "] "
    else
      part = bullet
    end
  end
  return {
    full = prefix .. (part or ""),
    prefix = prefix,
    part = part,
    bullet = bullet,
    num = num,
    delim = delim,
    cb = cb,
  }
end

-- Indent level as Obsidian counts it: tabs or groups of four spaces after the last quote marker.
function M.indent_level(prefix)
  local t = 0
  local function eat()
    while true do
      if prefix:sub(1, 1) == "\t" then
        prefix = prefix:sub(2)
      elseif prefix:sub(1, 4) == "    " then
        prefix = prefix:sub(5)
      else
        break
      end
      t = t + 1
    end
  end
  local last = prefix:match(".*()>")
  if last then
    prefix = prefix:sub(last + 1)
    eat()
    if prefix:sub(1, 1) == " " then
      prefix = prefix:sub(2)
    end
  end
  eat()
  return t
end

function M.quote_depth(prefix)
  local _, n = prefix:gsub(">", "")
  return n
end

function M.columns(text, tab)
  local cols = 0
  for c in text:gmatch(".") do
    cols = c == "\t" and cols + tab - cols % tab or cols + 1
  end
  return cols
end

function M.columns_after_quotes(prefix, depth)
  for _ = 1, depth do
    local gt = prefix:find(">", 1, true)
    prefix = prefix:sub(gt + 1):gsub("^ ", "")
  end
  return M.columns(prefix:match("^[ \t]*"), 4)
end

local function quote_prefix(line)
  local pos, cols = 1, {}
  while true do
    local spaces = line:match("^ ? ? ?", pos)
    if line:sub(pos + #spaces, pos + #spaces) ~= ">" then
      break
    end
    local gt = pos + #spaces
    cols[#cols + 1] = gt - 1
    pos = gt + 1
    if line:sub(pos, pos) == " " then
      pos = pos + 1
    end
  end
  return #cols, cols, pos - 1
end

local function strip_quotes(line, depth)
  local count, pos = 0, 1
  while count < depth do
    local spaces = line:match("^ ? ? ?", pos)
    if line:sub(pos + #spaces, pos + #spaces) ~= ">" then
      break
    end
    pos = pos + #spaces + 1
    if line:sub(pos, pos) == " " then
      pos = pos + 1
    end
    count = count + 1
  end
  return pos - 1
end

local function split_cells(line, from)
  local cells, pipes = {}, {}
  local text = line:sub(from + 1)
  local lead = text:match("^%s*")
  local i, n = #lead + 1, #text
  local start = i
  if text:sub(i, i) == "|" then
    pipes[#pipes + 1] = from + i - 1
    i = i + 1
    start = i
  end
  local in_code = false
  while i <= n do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 2
    else
      if c == "`" then
        in_code = not in_code
      elseif c == "|" then
        cells[#cells + 1] = { from + start - 1, from + i - 1 }
        pipes[#pipes + 1] = from + i - 1
        start = i + 1
      end
      i = i + 1
    end
  end
  local tail = text:sub(start)
  if tail:match("%S") then
    cells[#cells + 1] = { from + start - 1, from + n }
  end
  for _, cell in ipairs(cells) do
    local raw = line:sub(cell[1] + 1, cell[2])
    local l = #raw:match("^%s*")
    local r = #raw:match("%s*$")
    if l == #raw then
      cell[3], cell[4] = cell[1], cell[1]
    else
      cell[3], cell[4] = cell[1] + l, cell[2] - r
    end
  end
  return cells, pipes
end

local function delimiter_row(line, from)
  local text = line:sub(from + 1)
  if not text:match("^%s*|?%s*:?%-+:?%s*") or not text:match("%-") then
    return nil
  end
  local body = text:gsub("^%s*|", ""):gsub("|%s*$", "")
  local aligns = {}
  for cell in (body .. "|"):gmatch("([^|]*)|") do
    local c = vim.trim(cell)
    if not c:match("^:?%-+:?$") then
      return nil
    end
    if c:sub(1, 1) == ":" and c:sub(-1) == ":" then
      aligns[#aligns + 1] = "center"
    elseif c:sub(-1) == ":" then
      aligns[#aligns + 1] = "right"
    else
      aligns[#aligns + 1] = "left"
    end
  end
  return aligns
end

local function fence_open(content)
  local ws, fence, info = content:match("^(%s*)(```+)([^`]*)$")
  if not fence then
    ws, fence, info = content:match("^(%s*)(~~~+)(.*)$")
  end
  if fence then
    return #ws, fence, vim.trim(info or "")
  end
end

local function hr(content)
  local stripped = content:gsub("%s", "")
  if #content:match("^%s*") > 3 or #stripped < 3 then
    return false
  end
  local c = stripped:sub(1, 1)
  return (c == "-" or c == "*" or c == "_") and stripped:match("^%" .. c .. "+$") ~= nil
end

local function parse_frontmatter(lines, last)
  local props, i = {}, 2
  while i <= last do
    local line = lines[i]
    local key, rest = line:match("^([^%s#:][^:]*):%s*(.*)$")
    if key then
      local prop = { key = vim.trim(key), row = i - 1, raw = rest, items = nil, item_rows = {} }
      if rest == "" or rest == "|" or rest == ">" or rest == "|-" or rest == ">-" then
        local items, j = {}, i + 1
        while j <= last and (lines[j]:match("^%s+") or lines[j] == "") do
          local item = lines[j]:match("^%s*%-%s+(.*)$") or lines[j]:match("^%s*%-$") and ""
          if item then
            items[#items + 1] = item
          elseif rest ~= "" then
            items[#items + 1] = vim.trim(lines[j])
          end
          prop.item_rows[#prop.item_rows + 1] = j - 1
          j = j + 1
        end
        if rest == "" then
          prop.items = #items > 0 and items or nil
        else
          prop.raw = table.concat(items, rest:sub(1, 1) == "|" and "\n" or " ")
        end
        i = j
      else
        local list = rest:match("^%[(.*)%]$")
        if list then
          prop.items = {}
          for item in list:gmatch("[^,]+") do
            prop.items[#prop.items + 1] = vim.trim(item)
          end
        end
        i = i + 1
      end
      for idx, item in ipairs(prop.items or {}) do
        prop.items[idx] = item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      end
      prop.raw = prop.raw:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      props[#props + 1] = prop
    else
      i = i + 1
    end
  end
  return props
end

local Doc = {}
Doc.__index = Doc

function M.parse(lines)
  local doc = setmetatable({ lines = lines, rows = {}, blocks = {}, headings = {}, footnotes = {}, footdefs = {}, inlines_cache = {} }, Doc)
  local rows, n = doc.rows, #lines

  local fm_end
  if lines[1] == "---" then
    for i = 2, n do
      if lines[i] == "---" or lines[i] == "..." then
        fm_end = i
        break
      end
    end
  end
  if fm_end then
    local block = { type = "frontmatter", s = 0, e = fm_end - 1, props = parse_frontmatter(lines, fm_end - 1) }
    doc.blocks[#doc.blocks + 1] = block
    doc.frontmatter = block
    for i = 1, fm_end do
      rows[i - 1] = { text = lines[i], kind = (i == 1 or i == fm_end) and "fence" or "frontmatter", block = block, q = 0, qcols = {}, qend = 0 }
    end
  end

  local code, open_math, comment, in_list = nil, nil, nil, false
  local i = (fm_end or 0) + 1
  while i <= n do
    local row, line = i - 1, lines[i]
    local depth, qcols, qend = quote_prefix(line)
    local info = { text = line, q = depth, qcols = qcols, qend = qend, kind = "text" }
    rows[row] = info
    local content = line:sub(qend + 1)

    if code then
      local strip = strip_quotes(line, code.q)
      info.qend = strip
      info.q = math.min(depth, code.q)
      info.qcols = vim.list_slice(qcols, 1, info.q)
      info.block = code
      code.e = row
      local inner = line:sub(strip + 1)
      local ws, fence = inner:match("^(%s*)([`~]+)%s*$")
      if fence and fence:sub(1, 1) == code.char and #fence >= code.len and #ws <= code.indent + 3 then
        info.kind = "fence"
        info.fence_col = strip + #ws
        code.closed = true
        code = nil
      else
        info.kind = "code"
      end
    elseif open_math then
      info.kind = "math"
      info.block = open_math
      open_math.e = row
      if content:find("$$", 1, true) then
        info.kind = "fence"
        info.fence_col = qend + content:find("$$", 1, true) - 1
        open_math.e = row
        open_math.closed = true
        open_math = nil
      end
    elseif comment then
      info.kind = "comment"
      info.block = comment
      comment.e = row
      if line:find("%%", 1, true) then
        comment.e = row
        comment.closed = true
        comment = nil
      end
    else
      local indent, fence, lang = fence_open(content)
      local blank = content:match("^%s*$") ~= nil
      if fence then
        code = { type = "code", s = row, e = row, char = fence:sub(1, 1), len = #fence, indent = indent, lang = lang:match("^%S*"), q = depth }
        doc.blocks[#doc.blocks + 1] = code
        info.kind = "fence"
        info.fence_col = qend + indent
        info.block = code
      elseif content:match("^%s*%$%$") then
        local after = content:match("^%s*%$%$(.*)$")
        local block = { type = "math", s = row, e = row, q = depth }
        doc.blocks[#doc.blocks + 1] = block
        info.kind = "fence"
        info.fence_col = qend + #content:match("^%s*")
        info.block = block
        if after:find("$$", 1, true) then
          block.closed = true
          block.single = true
        else
          open_math = block
        end
      elseif content:match("^%%%%") and select(2, content:gsub("%%%%", "")) % 2 == 1 then
        comment = { type = "comment", s = row, e = row }
        doc.blocks[#doc.blocks + 1] = comment
        info.kind = "comment"
        info.block = comment
      elseif blank then
        info.kind = "blank"
      elseif
        not in_list
        and content:match("^    ")
        and depth == 0
        and rows[row - 1]
        and (rows[row - 1].kind == "blank" or rows[row - 1].kind == "icode")
      then
        info.kind = "icode"
        local prev = rows[row - 1].block
        if prev and prev.type == "icode" then
          prev.e = row
          info.block = prev
        else
          local block = { type = "icode", s = row, e = row }
          doc.blocks[#doc.blocks + 1] = block
          info.block = block
        end
      else
        local hashes, space = content:match("^ ? ? ?(#+)(%s+)")
        if not hashes then
          hashes = content:match("^ ? ? ?(#+)$")
          space = ""
        end
        local prev = rows[row - 1]
        local setext = content:match("^ ? ? ?=+%s*$") and 1 or (content:match("^ ? ? ?%-+%s*$") and 2)
        if hashes and #hashes <= 6 then
          info.kind = "heading"
          info.level = #hashes
          local lead = #content:match("^%s*")
          info.marker = { qend + lead, qend + lead + #hashes + #space }
          info.cs = info.marker[2]
          doc.headings[#doc.headings + 1] = { row = row, level = #hashes, text = vim.trim(content:sub(lead + #hashes + 1)) }
          in_list = false
        elseif setext and prev and prev.kind == "text" and not prev.list and prev.q == depth then
          prev.kind = "heading"
          prev.level = setext
          prev.setext = true
          prev.cs = prev.qend + #prev.text:sub(prev.qend + 1):match("^%s*")
          doc.headings[#doc.headings + 1] = { row = row - 1, level = setext, text = vim.trim(prev.text:sub(prev.qend + 1)) }
          info.kind = "setext"
          in_list = false
        elseif hr(content) then
          info.kind = "hr"
          in_list = false
        else
          local m = M.at(line)
          if m.bullet then
            local lead = #m.prefix - qend
            local mc = qend + lead
            info.list = {
              prefix = m.prefix,
              marker_s = mc,
              marker_e = mc + #m.bullet,
              bullet = m.bullet,
              num = m.num,
              delim = m.delim,
              cb = m.cb,
              ordered = m.num ~= nil,
              columns = M.columns(line:sub(qend + 1, mc), 4),
            }
            if m.cb then
              info.list.cb_s = mc + #m.bullet
              info.list.cb_e = info.list.cb_s + 3 + #m.cb - 1
            end
            info.cs = qend + #m.full - #m.prefix + lead
            info.kind = "text"
            in_list = true
          else
            if depth == 0 and not content:match("^%s") then
              in_list = false
            end
            local def = content:match("^%[%^([^%]]+)%]:")
            if def then
              info.footdef = def
              doc.footdefs[def] = row
              info.cs = qend + #def + 4
              in_list = true
            end
          end
          local nxt = lines[i + 1]
          if nxt and content:find("|", 1, true) then
            local nd, _, nq = quote_prefix(nxt)
            local aligns = nd == depth and delimiter_row(nxt, nq)
            local cells = aligns and split_cells(line, qend)
            if cells and #cells == #aligns then
              local block = { type = "table", s = row, e = row + 1, aligns = aligns, rows = {}, q = depth }
              doc.blocks[#doc.blocks + 1] = block
              info.kind = "table_row"
              info.list = nil
              info.cells, info.pipes = split_cells(line, qend)
              info.block = block
              block.rows[1] = row
              rows[row + 1] = { text = nxt, q = nd, qcols = select(2, quote_prefix(nxt)), qend = nq, kind = "table_delim", block = block }
              rows[row + 1].cells, rows[row + 1].pipes = split_cells(nxt, nq)
              local j = i + 2
              while j <= n do
                local d2, c2, q2 = quote_prefix(lines[j])
                local body = lines[j]:sub(q2 + 1)
                if d2 ~= depth or not body:find("|", 1, true) or body:match("^%s*$") then
                  break
                end
                local r = { text = lines[j], q = d2, qcols = c2, qend = q2, kind = "table_row", block = block }
                r.cells, r.pipes = split_cells(lines[j], q2)
                rows[j - 1] = r
                block.rows[#block.rows + 1] = j - 1
                block.e = j - 1
                j = j + 1
              end
              i = j - 1
            end
          end
        end
      end
    end
    i = i + 1
  end

  doc:_callouts()
  doc:_list_tree()
  doc.line_count = n
  return doc
end

function Doc:_callouts()
  local rows, n = self.rows, #self.lines
  local r = 0
  while r < n do
    local info = rows[r]
    if info and info.q > 0 and (not info.block or info.block.type == "table") then
      local content = info.text:sub(info.qend + 1)
      local ctype, fold, title = content:match("^%[!([^%]]+)%]([%+%-]?)%s*(.*)$")
      local prev = rows[r - 1]
      if ctype and (not prev or prev.q < info.q) then
        local block = {
          type = "callout",
          s = r,
          e = r,
          q = info.q,
          ctype = ctype:lower(),
          fold = fold,
          title = title,
          title_col = title ~= "" and (#info.text - #title) or nil,
          header_end = info.qend + #content - #title,
        }
        local j = r + 1
        while j < n and rows[j] and rows[j].q >= info.q do
          j = j + 1
        end
        block.e = j - 1
        self.blocks[#self.blocks + 1] = block
        for k = r, block.e do
          rows[k].callouts = rows[k].callouts or {}
          table.insert(rows[k].callouts, block)
        end
        info.callout_header = block
        info.cs = info.qend + (#content - #title)
        if info.kind == "heading" then
          info.kind = "text"
        end
      end
    end
    r = r + 1
  end
end

-- Parent links for list items, used by indent guides, folding, and smart lists.
function Doc:_list_tree()
  local stack = {}
  for r = 0, #self.lines - 1 do
    local info = self.rows[r]
    if info then
      if info.list then
        local col = info.list.columns
        while #stack > 0 and (stack[#stack].q ~= info.q or self.rows[stack[#stack].row].list.columns >= col) do
          table.remove(stack)
        end
        info.list.parent = #stack > 0 and stack[#stack].row or nil
        info.list.ancestors = {}
        for _, entry in ipairs(stack) do
          table.insert(info.list.ancestors, entry.row)
        end
        stack[#stack + 1] = { row = r, q = info.q }
      elseif info.kind ~= "blank" then
        local lead = M.columns(info.text:sub(info.qend + 1):match("^[ \t]*"), 4)
        while #stack > 0 and (stack[#stack].q ~= info.q or self.rows[stack[#stack].row].list.columns >= lead) do
          table.remove(stack)
        end
        if #stack > 0 and info.kind == "text" then
          info.list_cont = {}
          for _, entry in ipairs(stack) do
            table.insert(info.list_cont, entry.row)
          end
        end
      end
    end
  end
end

-- Footnotes are numbered by first reference, the way Obsidian's reading view numbers them.
function Doc:footnote_number(row, span)
  if not self.footnote_order then
    local order, count = {}, 0
    for r = 0, #self.lines - 1 do
      for _, sp in ipairs(self:inlines(r)) do
        if sp.t == "footref" and not order[sp.id] then
          count = count + 1
          order[sp.id] = count
        elseif sp.t == "inline_footnote" then
          count = count + 1
          order[r .. ":" .. sp.s] = count
        end
      end
    end
    self.footnote_order = order
  end
  if span.t == "footref" then
    return self.footnote_order[span.id]
  end
  return self.footnote_order[row .. ":" .. span.s]
end

function Doc:block_at(row, type)
  local info = self.rows[row]
  if not info then
    return nil
  end
  if type == "callout" then
    return info.callouts and info.callouts[#info.callouts]
  end
  if info.block and (not type or info.block.type == type) then
    return info.block
  end
end

local function shift(spans, offset)
  for _, sp in ipairs(spans) do
    sp.s, sp.e = sp.s + offset, sp.e + offset
    for _, key in ipairs({ "cs", "ce", "ts", "te", "ds", "de", "hash", "url_s", "url_e" }) do
      if sp[key] then
        sp[key] = sp[key] + offset
      end
    end
    for _, m in ipairs(sp.ms or {}) do
      m[1], m[2] = m[1] + offset, m[2] + offset
    end
  end
  return spans
end

function Doc:inlines(row)
  local cached = self.inlines_cache[row]
  if cached then
    return cached
  end
  local info = self.rows[row]
  local spans = {}
  if info then
    local kind = info.kind
    if kind == "table_row" then
      for _, cell in ipairs(info.cells) do
        for _, sp in ipairs(shift(inline.parse(info.text:sub(cell[3] + 1, cell[4])), cell[3])) do
          spans[#spans + 1] = sp
        end
      end
    elseif kind == "text" or kind == "heading" then
      local from = info.cs or info.qend
      local to = #info.text
      if kind == "heading" and not info.setext then
        local closing = info.text:match("()%s+#+%s*$")
        if closing and closing - 1 >= from then
          to = closing - 1
        end
      end
      spans = shift(inline.parse(info.text:sub(from + 1, to)), from)
    end
  end
  self.inlines_cache[row] = spans
  return spans
end

return M
