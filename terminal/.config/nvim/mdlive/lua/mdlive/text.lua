-- Turns markdown into virtual-text chunks that look the way Live Preview renders it.
local inline = require("mdlive.inline")
local latex = require("mdlive.latex")
local vault = require("mdlive.vault")
local palette = require("mdlive.palette")

local M = {}

function M.superscript(n)
  return (tostring(n):gsub("%d", latex.superscript))
end

local function link_group(ctx, target)
  if not ctx or not ctx.root then
    return "MdLink"
  end
  return vault.is_resolved(ctx.root, target, ctx.path) and "MdLink" or "MdLinkUnresolved"
end

-- ctx: { root, path, doc, row } for link resolution and footnote numbers.
function M.inline_chunks(text, base, ctx)
  local n = #text
  if n == 0 then
    return {}, 0
  end
  local hidden, groups, replace = {}, {}, {}
  local function style(s, e, group)
    for i = s, e - 1 do
      groups[i] = groups[i] or {}
      table.insert(groups[i], group)
    end
  end
  local function hide(s, e)
    for i = s, e - 1 do
      hidden[i] = true
    end
  end
  for _, sp in ipairs(inline.parse(text)) do
    local t = sp.t
    if t == "em" then
      style(sp.cs, sp.ce, "MdItalic")
    elseif t == "strong" then
      style(sp.cs, sp.ce, "MdBold")
    elseif t == "strike" then
      style(sp.cs, sp.ce, "MdStrike")
    elseif t == "highlight" then
      style(sp.cs, sp.ce, "MdHighlight")
    elseif t == "code" then
      style(sp.cs, sp.ce, "MdCode")
    elseif t == "escape" then
      hide(sp.s, sp.s + 1)
    elseif t == "comment" then
      hide(sp.s, sp.e)
    elseif t == "wikilink" or t == "embed" then
      style(sp.ds, sp.de, link_group(ctx, sp.path))
      if sp.hash then
        replace[sp.hash] = { ">", link_group(ctx, sp.path) }
        hide(sp.hash, sp.hash + 1)
      end
    elseif t == "link" then
      local external = sp.url:match("^%a[%w+.-]*:") ~= nil
      style(sp.cs, sp.ce, external and "MdLink" or link_group(ctx, (sp.url:gsub("%%20", " "))))
      if external then
        replace[sp.ce] = { "󰏌", "MdExternalIcon" }
      end
    elseif t == "image" then
      style(sp.cs, sp.ce, "MdLink")
    elseif t == "url" then
      style(sp.s, sp.e, "MdUrl")
    elseif t == "autolink" then
      style(sp.cs, sp.ce, "MdUrl")
    elseif t == "math" then
      replace[sp.s] = { latex.render(text:sub(sp.cs + 1, sp.ce)), "MdMath" }
      hide(sp.s, sp.e)
    elseif t == "footref" or t == "inline_footnote" then
      local num = ctx and ctx.doc and ctx.doc:footnote_number(ctx.row, sp) or 1
      replace[sp.s] = { M.superscript(num), "MdFootref" }
      hide(sp.s, sp.e)
    elseif t == "tag" then
      style(sp.s, sp.e, "MdTag")
    elseif t == "blockid" then
      style(sp.s, sp.e, "MdBlockId")
    end
    for _, m in ipairs(sp.ms or {}) do
      if t ~= "comment" then
        hide(m[1], m[2])
      end
    end
  end
  local chunks, width = {}, 0
  local cur_text, cur_key, cur_groups = {}, nil, nil
  local function flush()
    if #cur_text > 0 then
      local s = table.concat(cur_text)
      chunks[#chunks + 1] = { s, cur_groups }
      width = width + vim.fn.strdisplaywidth(s)
    end
    cur_text, cur_key, cur_groups = {}, nil, nil
  end
  local i = 0
  while i < n do
    if replace[i] then
      flush()
      chunks[#chunks + 1] = { replace[i][1], { base, replace[i][2] } }
      width = width + vim.fn.strdisplaywidth(replace[i][1])
    end
    if not hidden[i] then
      local gs = { base }
      for _, g in ipairs(groups[i] or {}) do
        gs[#gs + 1] = g
      end
      local key = table.concat(gs, ",")
      if key ~= cur_key then
        flush()
        cur_key, cur_groups = key, gs
      end
      local b = text:byte(i + 1)
      local len = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
      cur_text[#cur_text + 1] = text:sub(i + 1, i + len)
      i = i + len
    else
      i = i + 1
    end
  end
  flush()
  return chunks, width
end

-- One rendered line of another note, for embeds and fold text.
function M.line_chunks(doc, row, ctx)
  local info = doc.rows[row]
  if not info then
    return {}
  end
  local text = info.text
  local out = {}
  local function add(chunks)
    for _, c in ipairs(chunks) do
      out[#out + 1] = c
    end
  end
  local block = info.block
  if block and block.type == "frontmatter" then
    return nil
  end
  for _ = 1, info.q do
    out[#out + 1] = { "▎ ", "MdQuoteBar" }
  end
  local sub = vim.tbl_extend("force", ctx or {}, { doc = doc, row = row })
  if block and (block.type == "code" or block.type == "icode") then
    if info.kind == "fence" then
      out[#out + 1] = { "", "MdCodeBlock" }
    else
      out[#out + 1] = { text:sub(info.qend + 1), "MdCode" }
    end
    return out
  end
  if block and (block.type == "math" or block.type == "comment") then
    if info.kind ~= "fence" and block.type == "math" then
      out[#out + 1] = { latex.render(text:sub(info.qend + 1)), "MdMath" }
    end
    return out
  end
  if info.kind == "heading" then
    local from = info.setext and info.cs or info.marker[2]
    add((M.inline_chunks(text:sub(from + 1), "MdH" .. info.level, sub)))
    return out
  end
  if info.kind == "setext" then
    return nil
  end
  if info.kind == "hr" then
    out[#out + 1] = { string.rep("─", 40), "MdHr" }
    return out
  end
  if info.kind == "table_delim" then
    out[#out + 1] = { text:sub(info.qend + 1), "MdTableBorder" }
    return out
  end
  local from = info.cs or info.qend
  if info.list then
    local L = info.list
    out[#out + 1] = { text:sub(info.qend + 1, L.marker_s), "MdText" }
    if L.cb then
      if L.ordered then
        out[#out + 1] = { L.bullet, "MdListMarker" }
      end
      local checked = L.cb ~= " "
      out[#out + 1] = { checked and "󰄲 " or "󰄱 ", checked and "MdCheckboxChecked" or "MdCheckbox" }
      add((M.inline_chunks(text:sub(from + 1), checked and "MdTaskDone" or "MdText", sub)))
      return out
    end
    out[#out + 1] = { L.ordered and L.bullet or "• ", "MdListMarker" }
  elseif info.callout_header then
    local b = info.callout_header
    local spec = palette.callouts[b.ctype] or palette.callouts.note
    local name = palette.callouts[b.ctype] and b.ctype or "note"
    local group = "MdCallout" .. name:sub(1, 1):upper() .. name:sub(2)
    local title = b.title ~= "" and b.title or (b.ctype:sub(1, 1):upper() .. b.ctype:sub(2))
    out[#out + 1] = { spec.icon .. " ", group }
    add((M.inline_chunks(title, group, sub)))
    return out
  else
    out[#out + 1] = { text:sub(info.qend + 1, from), "MdText" }
  end
  add((M.inline_chunks(text:sub(from + 1), "MdText", sub)))
  return out
end

return M
