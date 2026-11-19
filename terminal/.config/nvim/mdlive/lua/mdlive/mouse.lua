-- Neovim maps a click to a column as if concealed text were still drawn, and a click on virtual
-- lines lands on the line they hang from. This maps the clicked screen cell back to the buffer
-- position actually drawn there.
local api = vim.api
local state = require("mdlive.state")
local render = require("mdlive.render")
local static = require("mdlive.static")

local M = {}

local function table_hit(b, win, pos)
  for _, t in ipairs(b.tables or {}) do
    local first = vim.fn.screenpos(win, t.anchor + 1, 1).row
    if first > 0 then
      local h = api.nvim_win_text_height(win, { start_row = t.anchor, end_row = t.anchor })
      local top = t.above and first - #t.rows or first + h.all - h.fill
      local k = pos.screenrow - top + 1
      local row = t.rows[k]
      if k >= 1 and row then
        local info = vim.fn.getwininfo(win)[1]
        local x = pos.wincol - info.textoff - 1
        local j = 1
        for i, s in ipairs(t.starts) do
          if x >= s - 1 then
            j = i
          end
        end
        local cell = t.cells[row][j]
        local col = cell and math.min(cell[3] + math.max(x - t.starts[j], 0), math.max(cell[4] - 1, cell[3])) or 0
        return row, col
      end
    end
  end
end

-- The characters a row shows, each tagged with the byte column it stands for.
local function visible(win, buf, row, line)
  local hidden = render.hidden(win, buf, row)
  local inline = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(buf, static.ns, { row, 0 }, { row, -1 }, { details = true })) do
    local d = m[4]
    if d.conceal and d.end_col then
      hidden[#hidden + 1] = { s = m[3], e = d.end_col, text = d.conceal }
    elseif d.virt_text_pos == "inline" then
      inline[m[3]] = d.virt_text
    end
  end
  local seq = {}
  local function push(text, col)
    for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
      seq[#seq + 1] = { ch = ch, col = col }
    end
  end
  local i = 0
  while i < #line do
    for _, chunk in ipairs(inline[i] or {}) do
      push(chunk[1], i)
    end
    local skip
    for _, h in ipairs(hidden) do
      if i >= h.s and i < h.e then
        skip = h
        break
      end
    end
    if skip then
      if i == skip.s then
        push(skip.text, i)
      end
      i = skip.e
    else
      local ch = vim.fn.strpart(line, i, 1, true)
      ch = ch ~= "" and ch or line:sub(i + 1, i + 1)
      seq[#seq + 1] = { ch = ch, col = i }
      i = i + #ch
    end
  end
  return seq
end

-- Walks the drawn cells of the line up to the click, pairing each with the next visible character.
-- Spaces that pair with nothing are wrap or indent padding, and other mismatches are overlays.
local function text_hit(win, buf, pos)
  local row = pos.line - 1
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local first = vim.fn.screenpos(win, pos.line, 1).row
  if first == 0 or first > pos.screenrow then
    return nil
  end
  local seq = visible(win, buf, row, line)
  local info = vim.fn.getwininfo(win)[1]
  local left = info.wincol + info.textoff
  local right = info.wincol + info.width - 1
  local p, last = 1, 0
  for r = first, pos.screenrow do
    for c = left, right do
      local ch = vim.fn.screenstring(r, c)
      local hit
      if ch ~= "" and seq[p] then
        if ch == seq[p].ch then
          hit = p
        elseif not ch:match("^%s$") then
          hit = p
          for q = p + 1, math.min(p + 8, #seq) do
            if seq[q].ch == ch then
              hit = q
              break
            end
          end
        end
      end
      if hit then
        p = hit + 1
        last = seq[hit].col
      end
      if r == pos.screenrow and c == pos.screencol then
        return row, last, hit ~= nil
      end
    end
  end
  return row, last, false
end

-- Returns the clicked row and byte column, and whether the click landed on drawn text.
function M.locate(b, win, buf, pos)
  local row, col = table_hit(b, win, pos)
  if row then
    return row, col, false
  end
  return text_hit(win, buf, pos)
end

local last

-- The markdown window, buffer position and state under the mouse, or nil where Neovim's own handling applies.
-- A click can reveal raw markdown and shift the line, so repeat clicks on the same cell reuse the first position.
function M.at_mouse(repeated)
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  if win == 0 or pos.line == 0 then
    return nil
  end
  if repeated and last and last.win == win and last.screenrow == pos.screenrow and last.screencol == pos.screencol then
    return last
  end
  local buf = api.nvim_win_get_buf(win)
  local b = state.get(buf)
  if not (b and b.enabled and b.mode ~= "source") then
    return nil
  end
  local row, col, on_text = M.locate(b, win, buf, pos)
  if row then
    last = { win = win, buf = buf, b = b, row = row, col = col, on_text = on_text, screenrow = pos.screenrow, screencol = pos.screencol }
    return last
  end
end

function M.feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "n", false)
end

local function visual()
  return api.nvim_get_mode().mode:match("^[vV\22]") ~= nil
end

local dragging = false

function M.drag()
  local hit = M.at_mouse()
  if not hit or hit.win ~= api.nvim_get_current_win() then
    dragging = false
    return M.feed("<LeftDrag>")
  end
  dragging = true
  if not visual() then
    vim.cmd("normal! v")
  end
  api.nvim_win_set_cursor(hit.win, { hit.row + 1, hit.col })
end

function M.release()
  if dragging then
    dragging = false
    return
  end
  M.feed("<LeftRelease>")
end

local function select_at(motion, key)
  return function()
    local hit = M.at_mouse(true)
    if not hit then
      return M.feed(key)
    end
    if visual() then
      vim.cmd("normal! " .. api.nvim_replace_termcodes("<Esc>", true, false, true))
    end
    api.nvim_set_current_win(hit.win)
    api.nvim_win_set_cursor(hit.win, { hit.row + 1, hit.col })
    vim.cmd("normal! " .. motion)
  end
end

M.double = select_at("viw", "<2-LeftMouse>")
M.triple = select_at("V", "<3-LeftMouse>")

return M
