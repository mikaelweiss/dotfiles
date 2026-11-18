-- Decorations that add width or lines. Extmarks here persist until the next refresh.
local api = vim.api
local state = require("mdlive.state")
local text = require("mdlive.text")
local vault = require("mdlive.vault")
local parse = require("mdlive.parse")
local render = require("mdlive.render")

local M = {}
M.ns = api.nvim_create_namespace("mdlive.static")
local ns = M.ns

local images = {}

local prop_icons = {
  text = "󰉢",
  multitext = "󰉹",
  number = "󰎠",
  checkbox = "󰄵",
  date = "󰃭",
  datetime = "󰅐",
  tags = "󰓻",
  aliases = "󰊍",
}
local LABEL_WIDTH = 14
-- Powerline round caps (U+E0B6, U+E0B4) give tags their pill shape.
local CAP_LEFT, CAP_RIGHT = "\238\130\182", "\238\130\180"
local IMAGE_EXT = { png = true, jpg = true, jpeg = true, gif = true, bmp = true, webp = true, svg = true, avif = true, heic = true }

local function set(buf, row, col, opts)
  opts.strict = false
  return pcall(api.nvim_buf_set_extmark, buf, ns, row, col, opts)
end

local function pad(chunks, width, target, align)
  local gap = math.max(0, target - width)
  local left = align == "right" and gap or align == "center" and math.floor(gap / 2) or 0
  local out = {}
  if left > 0 then
    out[#out + 1] = { string.rep(" ", left), "MdText" }
  end
  for _, c in ipairs(chunks) do
    out[#out + 1] = c
  end
  if gap - left > 0 then
    out[#out + 1] = { string.rep(" ", gap - left), "MdText" }
  end
  return out
end

local function border(widths, left, mid, right)
  local parts = {}
  for _, w in ipairs(widths) do
    parts[#parts + 1] = string.rep("─", w + 2)
  end
  return left .. table.concat(parts, mid) .. right
end

local function quote_prefix_chunks(doc, row)
  local info = doc.rows[row]
  if info.callouts then
    return {}
  end
  local out = {}
  for _ = 1, info.q do
    out[#out + 1] = { "▎ ", "MdQuoteBar" }
  end
  return out
end

local function width_of(s)
  return vim.fn.strdisplaywidth(s)
end

-- Wraps styled chunks at word boundaries, the way Obsidian wraps text inside a table cell.
local function wrap(chunks, limit)
  local lines, cur, cur_w = {}, {}, 0
  local function push(s, group)
    if s == "" then
      return
    end
    cur[#cur + 1] = { s, group }
    cur_w = cur_w + width_of(s)
  end
  local function newline()
    local last = cur[#cur]
    if last then
      local trimmed = last[1]:gsub("%s+$", "")
      cur_w = cur_w - (width_of(last[1]) - width_of(trimmed))
      last[1] = trimmed
    end
    lines[#lines + 1] = { cur, cur_w }
    cur, cur_w = {}, 0
  end
  for _, c in ipairs(chunks) do
    local s, group = c[1], c[2]
    local lead = s:match("^%s*")
    if lead ~= "" and cur_w > 0 and cur_w + width_of(lead) <= limit then
      push(lead, group)
    end
    for word, space in s:gmatch("(%S+)(%s*)") do
      local ww = width_of(word)
      if cur_w > 0 and cur_w + ww > limit then
        newline()
      end
      if ww > limit then
        for _, ch in ipairs(vim.fn.split(word, "\\zs")) do
          if cur_w + width_of(ch) > limit then
            newline()
          end
          push(ch, group)
        end
      else
        push(word, group)
      end
      if space ~= "" and cur_w + width_of(space) <= limit then
        push(space, group)
      end
    end
  end
  if #cur > 0 or #lines == 0 then
    newline()
  end
  return lines
end

-- Shrinks the widest columns first until the table fits the window.
local function fit(natural, budget)
  local total = 0
  for _, w in ipairs(natural) do
    total = total + w
  end
  if total <= budget then
    return vim.deepcopy(natural)
  end
  local order = {}
  for j = 1, #natural do
    order[j] = j
  end
  table.sort(order, function(a, b)
    return natural[a] < natural[b]
  end)
  local widths, remaining, left = {}, budget, #natural
  for _, j in ipairs(order) do
    widths[j] = math.max(3, math.min(natural[j], math.floor(remaining / left)))
    remaining = remaining - widths[j]
    left = left - 1
  end
  return widths
end

local function render_table(b, doc, block, ctx, avail)
  local buf = b.buf
  local ncols = #block.aligns
  local cells, natural = {}, {}
  for j = 1, ncols do
    natural[j] = 1
  end
  for _, row in ipairs(block.rows) do
    local info = doc.rows[row]
    cells[row] = {}
    for j = 1, ncols do
      local cell = info.cells[j]
      local chunks, w = {}, 0
      if cell then
        local base = row == block.rows[1] and "MdTableHeader" or "MdText"
        chunks, w = text.inline_chunks(info.text:sub(cell[3] + 1, cell[4]), base, vim.tbl_extend("force", ctx, { doc = doc, row = row }))
      end
      cells[row][j] = chunks
      natural[j] = math.max(natural[j], w)
    end
  end
  local prefix = quote_prefix_chunks(doc, block.s)
  local prefix_w = 0
  for _, c in ipairs(prefix) do
    prefix_w = prefix_w + width_of(c[1])
  end
  local widths = fit(natural, avail - prefix_w - 1 - 3 * ncols)
  local function border_line(left, mid, right)
    local out = vim.deepcopy(prefix)
    out[#out + 1] = { border(widths, left, mid, right), "MdTableBorder" }
    return out
  end
  local lines = { border_line("┌", "┬", "┐") }
  local last = block.rows[#block.rows]
  for _, row in ipairs(block.rows) do
    local wrapped, height = {}, 1
    for j = 1, ncols do
      wrapped[j] = wrap(cells[row][j], widths[j])
      height = math.max(height, #wrapped[j])
    end
    for k = 1, height do
      local chunks = vim.deepcopy(prefix)
      chunks[#chunks + 1] = { "│", "MdTableBorder" }
      for j = 1, ncols do
        local line = wrapped[j][k] or { {}, 0 }
        chunks[#chunks + 1] = { " ", "MdText" }
        vim.list_extend(chunks, pad(line[1], line[2], widths[j], block.aligns[j]))
        chunks[#chunks + 1] = { " │", "MdTableBorder" }
      end
      lines[#lines + 1] = chunks
    end
    lines[#lines + 1] = row == last and border_line("└", "┴", "┘") or border_line("├", "┼", "┤")
  end
  -- Concealed text keeps its wrapped height, so the raw rows collapse entirely and the grid
  -- hangs off a neighboring line instead.
  local before = block.s > 0 and doc.rows[block.s - 1]
  if before and not (before.block and before.block.type == "frontmatter") then
    set(buf, block.s - 1, 0, { virt_lines = lines })
  elseif block.e + 1 < #doc.lines then
    set(buf, block.e + 1, 0, { virt_lines = lines, virt_lines_above = true })
  else
    return
  end
  set(buf, block.s, 0, { end_row = block.e, conceal_lines = "" })
end

-- Obsidian pads code inside its box, so each line gets two columns of box-colored space.
local function pad_code(buf, doc, block)
  for row = block.s, block.e do
    local info = doc.rows[row]
    local col = info.qend + (block.indent or 0)
    if #info.text >= col then
      set(buf, row, col, { virt_text = { { "  ", "MdCodeBlock" } }, virt_text_pos = "inline", right_gravity = false })
    end
  end
end

local function prop_type(settings, prop)
  local t = settings.propertyTypes[prop.key]
  if t then
    return t
  end
  if prop.key == "tags" or prop.key == "aliases" then
    return prop.key
  end
  if prop.key == "cssclasses" or prop.items then
    return "multitext"
  end
  local v = prop.raw
  if v == "true" or v == "false" then
    return "checkbox"
  end
  if v:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d") then
    return "datetime"
  end
  if v:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return "date"
  end
  if v:match("^%-?%d+%.?%d*$") then
    return "number"
  end
  return "text"
end

local function pill(label, group, edge)
  return { { CAP_LEFT, edge }, { label, group }, { CAP_RIGHT, edge } }
end

local function prop_value(prop, ptype, ctx)
  local out = {}
  if ptype == "checkbox" then
    local on = prop.raw == "true"
    return { { on and "󰄲" or "󰄱", on and "MdCheckboxChecked" or "MdCheckbox" } }
  end
  if ptype == "date" then
    local y, m, d = prop.raw:match("^(%d+)%-(%d+)%-(%d+)$")
    return { { ("%s/%s/%s"):format(m, d, y), "MdPropValue" } }
  end
  if ptype == "datetime" then
    local y, m, d, hh, mm = prop.raw:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+)")
    local h = tonumber(hh)
    local suffix = h >= 12 and "PM" or "AM"
    h = h % 12 == 0 and 12 or h % 12
    return { { ("%s/%s/%s, %d:%s %s"):format(m, d, y, h, mm, suffix), "MdPropValue" } }
  end
  local items = prop.items
  if not items and (ptype == "multitext" or ptype == "tags" or ptype == "aliases") and prop.raw ~= "" then
    items = { prop.raw }
  end
  if items then
    for i, item in ipairs(items) do
      if i > 1 then
        out[#out + 1] = { " ", "MdText" }
      end
      if ptype == "tags" then
        vim.list_extend(out, pill((item:gsub("^#", "")), "MdTag", "MdTagEdge"))
      else
        local chunks = text.inline_chunks(item, "MdText", ctx)
        out[#out + 1] = { CAP_LEFT, "MdPillEdge" }
        for _, c in ipairs(chunks) do
          c[2] = vim.list_extend({ "MdPill" }, type(c[2]) == "table" and c[2] or { c[2] })
          out[#out + 1] = c
        end
        out[#out + 1] = { CAP_RIGHT, "MdPillEdge" }
      end
    end
    return out
  end
  return (text.inline_chunks(prop.raw, "MdPropValue", ctx))
end

local function render_properties(b, doc, block, ctx)
  local buf = b.buf
  local covered = {}
  set(buf, 0, 0, { end_col = 3, conceal = "" })
  set(buf, 0, 0, { virt_text = { { "Properties", "MdPropHeading" } }, virt_text_pos = "inline" })
  covered[0] = true
  for _, prop in ipairs(block.props) do
    local ptype = prop_type(b.settings, prop)
    local key = prop.key
    if vim.fn.strdisplaywidth(key) > LABEL_WIDTH - 3 then
      key = vim.fn.strcharpart(key, 0, LABEL_WIDTH - 4) .. "…"
    end
    local chunks = {
      { prop_icons[ptype] or prop_icons.text, "MdPropIcon" },
      { " " .. key .. string.rep(" ", math.max(1, LABEL_WIDTH - 2 - vim.fn.strdisplaywidth(key))), "MdPropKey" },
    }
    vim.list_extend(chunks, prop_value(prop, ptype, ctx))
    local line = doc.lines[prop.row + 1]
    set(buf, prop.row, 0, { end_col = #line, conceal = "" })
    set(buf, prop.row, 0, { virt_text = chunks, virt_text_pos = "inline" })
    covered[prop.row] = true
    for _, r in ipairs(prop.item_rows) do
      set(buf, r, 0, { end_row = r, conceal_lines = "" })
      covered[r] = true
    end
  end
  for r = 1, block.e - 1 do
    if not covered[r] then
      set(buf, r, 0, { end_row = r, conceal_lines = "" })
    end
  end
  set(buf, block.e, 0, { end_col = #doc.lines[block.e + 1], conceal = "" })
end

local function embed_lines(b, sp)
  local target = vault.resolve(b.root, sp.path, b.path)
  if not target then
    return nil
  end
  local ext = target:match("%.(%w+)$")
  if ext and ext:lower() ~= "md" then
    return nil, target, ext:lower()
  end
  local lines = vault.read(target)
  if not lines then
    return nil
  end
  local doc = parse.parse(lines)
  local first, last = 0, #lines - 1
  if sp.sub and sp.sub ~= "" then
    if sp.sub:sub(1, 1) == "^" then
      first, last = vault.block_range(doc, sp.sub:sub(2))
    else
      first, last = vault.section(doc, sp.sub)
    end
    if not first then
      return nil
    end
  end
  local ctx = { root = b.root, path = target }
  local out = {}
  for row = first, math.min(last, first + 199) do
    local chunks = text.line_chunks(doc, row, ctx)
    if chunks then
      table.insert(chunks, 1, { "▎ ", "MdEmbedBorder" })
      out[#out + 1] = chunks
    end
  end
  while #out > 0 and #out[#out] == 1 do
    table.remove(out)
  end
  return out
end

local function close_images(buf, keep)
  for key, placement in pairs(images[buf] or {}) do
    if not keep[key] then
      pcall(function()
        placement:close()
      end)
      images[buf][key] = nil
    end
  end
end

local function image_supported()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.image then
    return false
  end
  local sup, res = pcall(snacks.image.supports_terminal)
  return sup and res
end

local function place_image(b, key, row, path, keep)
  images[b.buf] = images[b.buf] or {}
  keep[key] = true
  if images[b.buf][key] then
    return true
  end
  local ok, placement = pcall(function()
    return Snacks.image.placement.new(b.buf, path, { pos = { row + 1, 0 }, inline = true, max_height = 30 })
  end)
  if ok and placement then
    images[b.buf][key] = placement
    return true
  end
  return false
end

local function render_embeds(b, doc, ctx)
  local embedded, keep = {}, {}
  local can_image = image_supported()
  for row = 0, #doc.lines - 1 do
    local info = doc.rows[row]
    if info and (info.kind == "text" or info.kind == "table_row") then
      for _, sp in ipairs(doc:inlines(row)) do
        local key = row .. ":" .. sp.s
        if sp.t == "embed" then
          local lines, file, ext = embed_lines(b, sp)
          if lines and #lines > 0 then
            set(b.buf, row, 0, { virt_lines = lines })
            embedded[key] = true
          elseif file and IMAGE_EXT[ext] and can_image then
            embedded[key] = place_image(b, file .. "@" .. row, row, file, keep)
          end
        elseif sp.t == "image" and can_image then
          local url = sp.url
          local file = url:match("^https?://") and url or vault.resolve(b.root, (url:gsub("%%20", " ")), b.path)
          if file then
            embedded[key] = place_image(b, file .. "@" .. row, row, file, keep)
          end
        end
      end
    end
  end
  close_images(b.buf, keep)
  b.embedded = embedded
end

local function render_tags(b, doc)
  for row = 0, #doc.lines - 1 do
    for _, sp in ipairs(doc:inlines(row)) do
      if sp.t == "tag" then
        set(b.buf, row, sp.s, { virt_text = { { CAP_LEFT, "MdTagEdge" } }, virt_text_pos = "inline" })
        set(b.buf, row, sp.e, { virt_text = { { CAP_RIGHT, "MdTagEdge" } }, virt_text_pos = "inline", right_gravity = false })
      end
    end
  end
end

local function title_lines(b)
  if not b.settings.showInlineTitle or b.path == "" then
    return nil
  end
  local name = vim.fs.basename(b.path):gsub("%.md$", "")
  return { { { name, "MdInlineTitle" } }, { { "", "MdText" } } }
end

-- Active blocks change what the static layer draws, so they form part of its cache key.
local function signature(b, doc, ctx)
  local active = {}
  for _, block in ipairs(doc.blocks) do
    if (block.type == "table" or block.type == "frontmatter") and render.block_active(ctx, block) then
      active[#active + 1] = block.s
    end
  end
  return table.concat({ b.tick, b.mode, ctx.width, table.concat(active, ",") }, "|")
end

function M.refresh(buf, force)
  local b = state.get(buf)
  if not b or not b.enabled or not api.nvim_buf_is_valid(buf) then
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  if api.nvim_win_get_buf(api.nvim_get_current_win()) == buf then
    win = api.nvim_get_current_win()
  end
  local ctx = render.context(win, buf)
  local doc = ctx.doc
  local sig = signature(b, doc, ctx)
  if sig == b.static_sig and not force then
    return
  end
  b.static_sig = sig
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local link_ctx = { root = b.root, path = b.path }
  local title = title_lines(b)
  if title then
    set(buf, 0, 0, { virt_lines = title, virt_lines_above = true })
  end
  if b.mode == "source" then
    b.embedded = {}
    close_images(buf, {})
    render_tags(b, doc)
    M.fix_topfill(buf)
    return
  end
  for _, block in ipairs(doc.blocks) do
    if block.type == "code" then
      pad_code(buf, doc, block)
    end
    if not render.block_active(ctx, block) then
      if block.type == "table" then
        render_table(b, doc, block, link_ctx, ctx.width)
      elseif block.type == "frontmatter" then
        render_properties(b, doc, block, vim.tbl_extend("force", link_ctx, { doc = doc }))
      end
    end
  end
  render_embeds(b, doc, link_ctx)
  render_tags(b, doc)
  M.fix_topfill(buf)
end

-- Neovim hides virtual lines above the first line unless 'topfill' asks for them.
function M.fix_topfill(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    api.nvim_win_call(win, function()
      local view = vim.fn.winsaveview()
      if view.topline == 1 then
        local above = 0
        for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, { details = true })) do
          if m[4].virt_lines and m[4].virt_lines_above then
            above = above + #m[4].virt_lines
          end
        end
        if view.topfill ~= above then
          view.topfill = above
          vim.fn.winrestview(view)
        end
      end
    end)
  end
end

function M.clear(buf)
  if api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  close_images(buf, {})
end

return M
