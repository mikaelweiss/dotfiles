-- Cursor-aware decorations, drawn per window on every redraw.
local api = vim.api
local state = require("mdlive.state")
local palette = require("mdlive.palette")
local latex = require("mdlive.latex")
local vault = require("mdlive.vault")
local text = require("mdlive.text")

local M = {}
M.ns = api.nvim_create_namespace("mdlive.render")
local ns = M.ns

local ctx

local function mark(row, col, opts)
  opts.ephemeral = true
  pcall(api.nvim_buf_set_extmark, ctx.buf, ns, row, col, opts)
end

local function hl(row, s, e, group, priority)
  if e > s then
    mark(row, s, { end_col = e, hl_group = group, priority = priority or 200 })
  end
end

local function nospell(row, s, e)
  if e > s then
    mark(row, s, { end_col = e, spell = false })
  end
end

local function hide(row, s, e, replacement, group)
  if e > s then
    mark(row, s, { end_col = e, conceal = replacement or "", hl_group = group, priority = 300 })
  end
end

local function overlay(row, col, chunks)
  mark(row, col, { virt_text = chunks, virt_text_pos = "overlay", hl_mode = "combine", priority = 300 })
end

local function line_bg(row, group)
  mark(row, 0, { end_row = row + 1, end_col = 0, hl_group = group, hl_eol = true, priority = 50 })
end

function M.selection(win)
  local cur = api.nvim_win_get_cursor(win)
  local r, c = cur[1] - 1, cur[2]
  if win == api.nvim_get_current_win() then
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
      local v = vim.fn.getpos("v")
      local sr, sc, er, ec = v[2] - 1, v[3] - 1, r, c
      if sr > er or (sr == er and sc > ec) then
        sr, sc, er, ec = er, ec, sr, sc
      end
      if mode == "V" then
        sc, ec = 0, math.huge
      end
      return { visual = true, srow = sr, scol = sc, erow = er, ecol = ec }
    end
  end
  return { srow = r, scol = c, erow = r, ecol = c }
end

local function line_active(row)
  if ctx.mode ~= "live" then
    return ctx.mode == "source"
  end
  return row >= ctx.sel.srow and row <= ctx.sel.erow
end

local function block_active(block)
  if ctx.mode ~= "live" then
    return ctx.mode == "source"
  end
  return block.s <= ctx.sel.erow and block.e >= ctx.sel.srow
end
M.block_active = function(c, block)
  local saved = ctx
  ctx = c
  local res = block_active(block)
  ctx = saved
  return res
end

local function span_active(row, s, e)
  if ctx.mode ~= "live" then
    return ctx.mode == "source"
  end
  local sel = ctx.sel
  if row < sel.srow or row > sel.erow then
    return false
  end
  local from = row == sel.srow and sel.scol or 0
  local to = row == sel.erow and sel.ecol or math.huge
  if sel.visual then
    return from <= e and to + 1 >= s
  end
  return s <= from and from <= e
end

local function callout_groups(block)
  local name = palette.callouts[block.ctype] and block.ctype or "note"
  local cap = name:sub(1, 1):upper() .. name:sub(2)
  return palette.callouts[name], "MdCallout" .. cap, "MdCallout" .. cap .. "Bg"
end
M.callout_groups = callout_groups

local function quote_markers(row, info, from_depth, active)
  for idx, col in ipairs(info.qcols) do
    if idx >= from_depth then
      if active then
        hl(row, col, col + 1, "MdQuoteMarker")
      else
        overlay(row, col, { { "▎", "MdQuoteBar" } })
      end
    end
  end
end

local function render_callout(row, info, block)
  local spec, fg, bg = callout_groups(block)
  if block_active(block) then
    quote_markers(row, info, 1, line_active(row))
    return
  end
  line_bg(row, bg)
  for idx, col in ipairs(info.qcols) do
    if idx <= block.q then
      local e = info.text:sub(col + 2, col + 2) == " " and col + 2 or col + 1
      hide(row, col, e)
    end
  end
  if #info.qcols > block.q then
    quote_markers(row, info, block.q + 1, false)
  end
  if row == block.s then
    local hs, he = info.qend, block.header_end
    if block.title ~= "" then
      overlay(row, hs, { { spec.icon, fg } })
      hide(row, hs + 1, he - 1)
      hl(row, he, #info.text, fg)
    else
      local title = block.ctype:sub(1, 1):upper() .. block.ctype:sub(2)
      local shown = spec.icon .. " " .. title
      local w = vim.fn.strdisplaywidth(shown)
      overlay(row, hs, { { shown, fg } })
      hide(row, hs + w, #info.text)
    end
    if block.fold ~= "" then
      local closed = api.nvim_win_call(ctx.win, function()
        return vim.fn.foldclosed(row + 2) ~= -1
      end)
      mark(row, 0, { virt_text = { { " " .. (closed and "󰅂" or "󰅀"), fg } }, virt_text_pos = "eol" })
    end
  end
end

-- The code box starts at the block's own indent, so code inside a list item lines up with the item.
local function code_bg(row, info, block)
  local line = info.text
  local indent = block.indent or 0
  local lead = #line:sub(info.qend + 1):match("^%s*")
  if #line < info.qend + indent and indent > 0 then
    mark(row, 0, { end_row = row + 1, end_col = 0, hl_group = "MdCodeBlock", hl_eol = true, priority = 50 })
    overlay(row, 0, { { string.rep(" ", info.qend + indent), "Normal" } })
    return
  end
  local start = info.qend + math.min(indent, lead)
  mark(row, start, { end_row = row + 1, end_col = 0, hl_group = "MdCodeBlock", hl_eol = true, priority = 50 })
end

local function render_fence(row, info, block)
  local active = block_active(block)
  if block.type == "icode" then
    return line_bg(row, "MdCodeBlock")
  end
  code_bg(row, info, block)
  if info.kind == "fence" then
    local fc = info.fence_col or info.qend
    if active then
      hl(row, fc, #info.text, "MdCodeFence")
    else
      hide(row, fc, #info.text)
      if row == block.s and block.lang and block.lang ~= "" then
        mark(row, 0, { virt_text = { { block.lang .. "  ", "MdCodeLang" } }, virt_text_pos = "right_align" })
      end
    end
  end
end

local function centered(row, rendered, group)
  local w = vim.fn.strdisplaywidth(rendered)
  local col = math.max(0, math.floor((ctx.width - w) / 2))
  mark(row, 0, { virt_text = { { rendered, group } }, virt_text_win_col = col, priority = 300 })
end

local function render_math(row, info, block)
  local line = info.text
  if block_active(block) then
    hl(row, info.qend, #line, "MdMath")
    return
  end
  hide(row, info.qend, #line)
  local content = vim.trim((line:sub(info.qend + 1):gsub("%$%$", "")))
  if content ~= "" then
    centered(row, latex.render(content), "MdMath")
  end
end

local function render_table_raw(row, info)
  for _, p in ipairs(info.pipes or {}) do
    hl(row, p, p + 1, "MdFormatting")
  end
  if info.kind == "table_delim" then
    hl(row, info.qend, #info.text, "MdFormatting")
  elseif info.block.rows[1] == row then
    hl(row, info.qend, #info.text, "MdTableHeader")
  end
end

local function render_heading(row, info)
  local line = info.text
  if info.setext then
    hl(row, info.cs, #line, "MdH" .. info.level)
    return
  end
  local ms, me = info.marker[1], info.marker[2]
  if line_active(row) then
    hl(row, ms, me, "MdHeadingMarker")
  else
    hide(row, ms, me)
  end
  hl(row, me, #line, "MdH" .. info.level)
end

local function guides(row, ancestors)
  if not ctx.settings.showIndentGuide then
    return
  end
  local line = ctx.doc.rows[row].text
  for _, a in ipairs(ancestors) do
    local col = ctx.doc.rows[a].list.marker_s
    local ch = line:sub(col + 1, col + 1)
    if ch == " " or ch == "\t" then
      local group = ctx.active_guide == a and "MdIndentGuideActive" or "MdIndentGuide"
      overlay(row, col, { { "│", group } })
    end
  end
end

local function render_list(row, info)
  local L = info.list
  local line = info.text
  local ms, me = L.marker_s, L.marker_e
  guides(row, L.ancestors)
  if L.cb then
    local checked = L.cb ~= " "
    if span_active(row, ms, L.cb_e) then
      hl(row, ms, L.cb_e, "MdTaskMarker")
    else
      local icon = checked and "󰄲" or "󰄱"
      local group = checked and "MdCheckboxChecked" or "MdCheckbox"
      if L.ordered then
        hl(row, ms, me, "MdListMarker")
        overlay(row, L.cb_s, { { icon, group } })
        hide(row, L.cb_s + 1, L.cb_e)
      else
        overlay(row, ms, { { icon, group } })
        hide(row, ms + 1, L.cb_e)
      end
    end
    if checked then
      hl(row, info.cs, #line, "MdTaskDone", 210)
    end
  elseif L.ordered then
    hl(row, ms, me, "MdListMarker")
  elseif span_active(row, ms, ms + 1) then
    hl(row, ms, ms + 1, "MdListMarker")
  else
    overlay(row, ms, { { "•", "MdListMarker" } })
  end
end

local function wikilink_group(target)
  return vault.is_resolved(ctx.root, target, ctx.path) and "MdLink" or "MdLinkUnresolved"
end

local function render_inlines(row, info)
  local line = info.text
  local doc = ctx.doc
  for _, sp in ipairs(doc:inlines(row)) do
    local t = sp.t
    local act = span_active(row, sp.s, sp.e)
    if t == "url" or t == "autolink" or t == "code" or t == "math" or t == "tag" or t == "embed" or t == "image" then
      nospell(row, sp.s, sp.e)
    elseif t == "link" then
      nospell(row, sp.url_s, sp.url_e)
    elseif t == "wikilink" and sp.alias then
      nospell(row, sp.ts, sp.te)
    end
    if t == "em" or t == "strong" or t == "strike" then
      local group = t == "em" and "MdItalic" or t == "strong" and "MdBold" or "MdStrike"
      hl(row, sp.cs, sp.ce, group)
      if not act then
        for _, m in ipairs(sp.ms) do
          hide(row, m[1], m[2])
        end
      end
    elseif t == "highlight" or t == "code" then
      local group = t == "code" and "MdCode" or "MdHighlight"
      if act then
        hl(row, sp.s, sp.e, group)
      else
        hl(row, sp.cs, sp.ce, group)
        for _, m in ipairs(sp.ms) do
          hide(row, m[1], m[2])
        end
      end
    elseif t == "math" then
      local raw = line:sub(sp.cs + 1, sp.ce)
      local rendered = latex.render(raw)
      local w = vim.fn.strdisplaywidth(rendered)
      if act then
        hl(row, sp.s, sp.e, "MdMath")
      elseif not line:sub(sp.s + 1, sp.e):find("[\128-\255]") and w <= sp.e - sp.s then
        overlay(row, sp.s, { { rendered, "MdMath" } })
        hide(row, sp.s + w, sp.e)
      else
        hl(row, sp.cs, sp.ce, "MdMath")
        for _, m in ipairs(sp.ms) do
          hide(row, m[1], m[2])
        end
      end
    elseif t == "comment" then
      if ctx.mode == "reading" then
        hide(row, sp.s, sp.e)
      else
        hl(row, sp.s, sp.e, "MdComment", 250)
      end
    elseif t == "escape" then
      if line_active(row) then
        hl(row, sp.s, sp.s + 1, "MdFormatting")
      else
        hide(row, sp.s, sp.s + 1)
      end
    elseif t == "wikilink" then
      local group = wikilink_group(sp.path)
      if act then
        hl(row, sp.s, sp.ts, "MdFormatting")
        hl(row, sp.ts, sp.te, group)
        if sp.alias then
          hl(row, sp.te, sp.te + 1, "MdFormatting")
          hl(row, sp.ds, sp.de, group)
        end
        hl(row, sp.e - 2, sp.e, "MdFormatting")
      else
        for _, m in ipairs(sp.ms) do
          hide(row, m[1], m[2])
        end
        hl(row, sp.ds, sp.de, group)
        if sp.hash then
          hide(row, sp.hash, sp.hash + 1, ">", group)
        end
      end
    elseif t == "embed" then
      if act or not ctx.embedded[row .. ":" .. sp.s] then
        hl(row, sp.s, sp.ts, "MdFormatting")
        hl(row, sp.ts, sp.te, wikilink_group(sp.path))
        hl(row, sp.te, sp.e, "MdFormatting")
      else
        hide(row, sp.s, sp.e)
      end
    elseif t == "link" or t == "image" then
      local external = sp.url:match("^%a[%w+.-]*:") ~= nil
      local group = external and "MdLink" or wikilink_group((sp.url:gsub("%%20", " ")))
      if t == "image" and not act and ctx.embedded[row .. ":" .. sp.s] then
        hide(row, sp.s, sp.e)
      elseif act then
        hl(row, sp.s, sp.cs, "MdFormatting")
        hl(row, sp.cs, sp.ce, group)
        hl(row, sp.ce, sp.url_s, "MdFormatting")
        hl(row, sp.url_s, sp.url_e, "MdUrl")
        hl(row, sp.url_e, sp.e, "MdFormatting")
      else
        hide(row, sp.s, sp.cs)
        hl(row, sp.cs, sp.ce, group)
        if external then
          hide(row, sp.ce, sp.e, "󰏌", "MdExternalIcon")
        else
          hide(row, sp.ce, sp.e)
        end
      end
    elseif t == "url" then
      hl(row, sp.s, sp.e, "MdUrl")
    elseif t == "autolink" then
      hl(row, sp.cs, sp.ce, "MdUrl")
      for _, m in ipairs(sp.ms) do
        if act then
          hl(row, m[1], m[2], "MdFormatting")
        else
          hide(row, m[1], m[2])
        end
      end
    elseif t == "footref" or t == "inline_footnote" then
      if act then
        hl(row, sp.s, sp.e, "MdFootref")
      else
        local sup = text.superscript(doc:footnote_number(row, sp) or 1)
        local w = vim.fn.strdisplaywidth(sup)
        overlay(row, sp.s, { { sup, "MdFootref" } })
        hide(row, sp.s + w, sp.e)
      end
    elseif t == "tag" then
      hl(row, sp.s, sp.e, "MdTag")
    elseif t == "blockid" then
      hl(row, sp.s, sp.e, "MdBlockId")
    end
  end
end

local function render_row(row)
  local doc = ctx.doc
  local info = doc.rows[row]
  if not info then
    return
  end
  local line = info.text
  local callout = info.callouts and info.callouts[#info.callouts]
  if callout then
    render_callout(row, info, callout)
  elseif info.q > 0 then
    quote_markers(row, info, 1, line_active(row))
  end
  local block = info.block
  if block then
    local t = block.type
    if t == "frontmatter" then
      if block_active(block) then
        hl(row, 0, #line, "MdFrontmatter", 250)
      end
      return
    elseif t == "code" or t == "icode" then
      return render_fence(row, info, block)
    elseif t == "math" then
      return render_math(row, info, block)
    elseif t == "comment" then
      if ctx.mode == "reading" then
        hide(row, 0, #line)
      else
        hl(row, 0, #line, "MdComment", 250)
      end
      return
    elseif t == "table" then
      if block_active(block) then
        render_table_raw(row, info)
        render_inlines(row, info)
      end
      return
    end
  end
  local kind = info.kind
  if kind == "heading" then
    render_heading(row, info)
  elseif kind == "setext" then
    if line_active(row) then
      hl(row, 0, #line, "MdHeadingMarker")
    else
      hide(row, info.qend, #line)
    end
    return
  elseif kind == "hr" then
    if line_active(row) then
      hl(row, info.qend, #line, "MdHrRaw")
    else
      hide(row, info.qend, #line)
      local col = vim.fn.strdisplaywidth(line:sub(1, info.qend))
      mark(row, 0, { virt_text = { { string.rep("─", math.max(0, ctx.width - col)), "MdHr" } }, virt_text_win_col = col, priority = 300 })
    end
    return
  end
  if info.list then
    render_list(row, info)
  end
  if info.footdef then
    hl(row, info.qend, info.cs - 1, "MdFootnoteMarker")
  end
  render_inlines(row, info)
end

local function active_guide(doc, row)
  local info = doc.rows[row]
  if not info then
    return nil
  end
  if info.list then
    return info.list.parent
  end
  if info.list_cont then
    return info.list_cont[#info.list_cont - 1]
  end
end

function M.context(win, buf)
  local b = state.get(buf)
  if not b then
    return nil
  end
  local doc = b:doc()
  local info = vim.fn.getwininfo(win)[1]
  local c = {
    win = win,
    buf = buf,
    doc = doc,
    mode = b.mode,
    root = b.root,
    path = b.path,
    settings = b.settings,
    sel = M.selection(win),
    width = api.nvim_win_get_width(win) - (info and info.textoff or 0),
    embedded = b.embedded or {},
  }
  c.active_guide = c.mode == "live" and active_guide(doc, c.sel.srow) or nil
  return c
end

function M.setup()
  api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, buf)
      local b = state.get(buf)
      if not b or not b.enabled then
        return false
      end
      local ok, c = pcall(M.context, win, buf)
      if not ok or not c then
        return false
      end
      ctx = c
      return true
    end,
    on_line = function(_, win, buf, row)
      if ctx and ctx.win == win and ctx.buf == buf then
        local ok, err = pcall(render_row, row)
        if not ok and not ctx.errored then
          ctx.errored = true
          vim.schedule(function()
            vim.notify("mdlive: " .. tostring(err), vim.log.levels.ERROR)
          end)
        end
      end
    end,
  })
end

return M
