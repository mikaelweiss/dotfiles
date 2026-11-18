local api = vim.api
local state = require("mdlive.state")
local text = require("mdlive.text")

local M = {}

local cache = {}

local function contains(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then
      return true
    end
  end
  return false
end

local function subtree_end(doc, row)
  local last, j, n = row, row + 1, #doc.lines
  while j < n do
    local info = doc.rows[j]
    if info.kind == "blank" then
      j = j + 1
    elseif (info.list and contains(info.list.ancestors, row)) or contains(info.list_cont, row) then
      last = j
      j = j + 1
    else
      break
    end
  end
  return last
end

local function compute(doc, settings)
  local levels = {}
  local heading = 0
  local stack = {}
  for row = 0, #doc.lines - 1 do
    local info = doc.rows[row]
    while #stack > 0 and stack[#stack] < row do
      table.remove(stack)
    end
    if info.kind == "heading" and settings.foldHeading and info.q == 0 then
      heading = info.level
      stack = {}
      levels[row + 1] = ">" .. heading
    else
      local close
      if settings.foldIndent and info.list then
        local e = subtree_end(doc, row)
        if e > row then
          close = e
        end
      end
      if not close and info.callout_header and info.callout_header.e > row then
        close = info.callout_header.e
      end
      if close then
        stack[#stack + 1] = close
        levels[row + 1] = ">" .. (heading + #stack)
      else
        levels[row + 1] = tostring(heading + #stack)
      end
    end
  end
  return levels
end

function M.expr()
  local buf = api.nvim_get_current_buf()
  local b = state.get(buf)
  if not b then
    return "0"
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if not c or c.tick ~= tick then
    c = { tick = tick, levels = compute(b:doc(), b.settings) }
    cache[buf] = c
  end
  return c.levels[vim.v.lnum] or "0"
end

function M.text()
  local buf = api.nvim_get_current_buf()
  local b = state.get(buf)
  local row = vim.v.foldstart - 1
  local chunks = b and text.line_chunks(b:doc(), row, { root = b.root, path = b.path })
  if not chunks then
    chunks = { { api.nvim_buf_get_lines(buf, row, row + 1, false)[1], "MdText" } }
  end
  local out = {}
  for _, c in ipairs(chunks) do
    local group = c[2]
    if type(group) == "table" then
      group = group[#group]
    end
    out[#out + 1] = { c[1], group }
  end
  out[#out + 1] = { " …", "MdFoldEllipsis" }
  return out
end

function M.clear(buf)
  cache[buf] = nil
end

-- Collapsed callouts (`[!type]-`) start folded, as they do in Obsidian.
function M.close_collapsed_callouts(buf, win)
  local b = state.get(buf)
  if not b then
    return
  end
  api.nvim_win_call(win, function()
    for _, block in ipairs(b:doc().blocks) do
      if block.type == "callout" and block.fold == "-" and block.e > block.s then
        pcall(vim.cmd, ("silent! %dfoldclose"):format(block.s + 1))
      end
    end
  end)
end

return M
