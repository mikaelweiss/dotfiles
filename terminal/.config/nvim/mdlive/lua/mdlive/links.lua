local api = vim.api
local state = require("mdlive.state")
local vault = require("mdlive.vault")
local parse = require("mdlive.parse")
local render = require("mdlive.render")
local lists = require("mdlive.lists")

local M = {}

local FOLLOWABLE = {
  wikilink = true,
  embed = true,
  link = true,
  image = true,
  url = true,
  autolink = true,
  tag = true,
  footref = true,
}

function M.span_at(doc, row, col)
  local best
  for _, sp in ipairs(doc:inlines(row)) do
    if FOLLOWABLE[sp.t] and sp.s <= col and col < sp.e then
      if not best or (sp.e - sp.s) < (best.e - best.s) then
        best = sp
      end
    end
  end
  return best
end

local function jump_to(buf, sub)
  if not sub or sub == "" then
    return
  end
  local b = state.get(buf)
  if not b then
    return
  end
  local doc = b:doc()
  local row
  if sub:sub(1, 1) == "^" then
    row = vault.find_block(doc.lines, sub:sub(2))
  else
    local h = vault.find_heading(doc, sub)
    row = h and h.row
  end
  if row then
    api.nvim_win_set_cursor(0, { row + 1, 0 })
    vim.cmd("normal! zvzt")
  end
end

local function open_file(path, sub)
  if path ~= api.nvim_buf_get_name(0) then
    vim.cmd.edit(vim.fn.fnameescape(path))
  else
    vim.cmd("normal! m'")
  end
  jump_to(api.nvim_get_current_buf(), sub)
end

local function new_note_dir(b)
  local loc = b.settings.newFileLocation
  if loc == "current" and b.path ~= "" then
    return vim.fs.dirname(b.path)
  elseif loc == "folder" then
    return vim.fs.normalize(b.root .. "/" .. (b.settings.newFileFolderPath or ""))
  end
  return b.root
end

-- Following an unresolved link creates the note, as clicking one does in Obsidian.
local function create_note(b, target)
  local dir = target:find("/", 1, true) and b.root or new_note_dir(b)
  local path = vim.fs.normalize(dir .. "/" .. target .. (target:match("%.md$") and "" or ".md"))
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if not vim.uv.fs_stat(path) then
    vim.fn.writefile({}, path)
  end
  vault.refresh(b.root)
  return path
end

local function open_external(url)
  if url:match("^www%.") then
    url = "https://" .. url
  end
  vim.ui.open(url)
end

function M.follow(sp, b, row)
  local t = sp.t
  if t == "wikilink" or t == "embed" then
    local path = sp.path == "" and b.path or vault.resolve(b.root, sp.path, b.path)
    if not path then
      path = create_note(b, sp.path)
    end
    if not path:match("%.md$") then
      return vim.ui.open(path)
    end
    open_file(path, sp.sub)
  elseif t == "link" or t == "image" then
    local url = sp.url
    if url:match("^%a[%w+.-]*:") then
      return open_external(url)
    end
    local target, anchor = url:match("^([^#]*)#?(.*)$")
    target = vim.uri_decode and vim.uri_decode(target) or target:gsub("%%20", " ")
    if target == "" then
      return jump_to(api.nvim_get_current_buf(), anchor)
    end
    local path = vault.resolve(b.root, target, b.path)
    if not path then
      path = create_note(b, (target:gsub("%.md$", "")))
    end
    if path:match("%.md$") then
      open_file(path, anchor)
    else
      vim.ui.open(path)
    end
  elseif t == "url" or t == "autolink" then
    local url = sp.url
    if t == "autolink" and not url:match("^%a[%w+.-]*:") then
      url = "mailto:" .. url
    end
    open_external(url)
  elseif t == "tag" then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.grep({ search = "#" .. sp.name, regex = false, cwd = b.root, glob = "*.md" })
    else
      vim.cmd("silent! vimgrep /#" .. vim.fn.escape(sp.name, "/") .. "\\>/gj " .. vim.fn.fnameescape(b.root) .. "/**/*.md")
      vim.cmd("copen")
    end
  elseif t == "footref" then
    local def = b:doc().footdefs[sp.id]
    if def then
      vim.cmd("normal! m'")
      api.nvim_win_set_cursor(0, { def + 1, 0 })
    end
  end
  return true
end

local function current()
  local buf = api.nvim_get_current_buf()
  local b = state.get(buf)
  if not b then
    return nil
  end
  local c = api.nvim_win_get_cursor(0)
  return b, c[1] - 1, c[2]
end

function M.follow_cursor()
  local b, row, col = current()
  if not b then
    return false
  end
  local doc = b:doc()
  local sp = M.span_at(doc, row, col)
  if sp then
    M.follow(sp, b, row)
    return true
  end
  local info = doc.rows[row]
  if info and info.footdef then
    for r = 0, #doc.lines - 1 do
      for _, s in ipairs(doc:inlines(r)) do
        if s.t == "footref" and s.id == info.footdef then
          vim.cmd("normal! m'")
          api.nvim_win_set_cursor(0, { r + 1, s.s })
          return true
        end
      end
    end
  end
  return false
end

-- Enter in Normal mode does what a click does in Obsidian: follow a link or toggle a task.
function M.enter()
  if M.follow_cursor() then
    return
  end
  local b, row = current()
  if b then
    local info = b:doc().rows[row]
    if info and info.list and info.list.cb then
      return lists.toggle_checklist(row, row, false)
    end
  end
  api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
end

function M.gf()
  if not M.follow_cursor() then
    api.nvim_feedkeys("gf", "n", false)
  end
end

local function toggle_box(buf, row)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local m = parse.at(line)
  if not m.cb then
    return
  end
  local s = #m.prefix + #m.bullet + 1
  api.nvim_buf_set_text(buf, row, s, row, s + #m.cb, { m.cb == " " and "x" or " " })
end

-- A click on a rendered link or checkbox acts on it without moving the cursor.
function M.click()
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  if win ~= 0 and pos.line > 0 then
    local buf = api.nvim_win_get_buf(win)
    local b = state.get(buf)
    if b and b.enabled and b.mode ~= "source" then
      local ctx = render.context(win, buf)
      local doc = ctx.doc
      local row, col = pos.line - 1, pos.column - 1
      local info = doc.rows[row]
      if info and info.list and info.list.cb then
        local L = info.list
        local box_s = L.ordered and L.cb_s or L.marker_s
        local active = b.mode == "live" and ctx.sel.srow <= row and row <= ctx.sel.erow and ctx.sel.scol <= L.cb_e and ctx.sel.ecol >= L.marker_s
        if not active and col >= box_s and col <= box_s + 1 then
          toggle_box(buf, row)
          return
        end
      end
      local sp = M.span_at(doc, row, col)
      if sp and sp.t ~= "tag" and sp.t ~= "footref" then
        local sel = ctx.sel
        local active = b.mode == "live" and sel.srow <= row and row <= sel.erow and sp.s <= sel.scol and sel.scol <= sp.e
        if not active then
          api.nvim_set_current_win(win)
          M.follow(sp, b, row)
          return
        end
      end
    end
  end
  api.nvim_feedkeys(api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "n", false)
end

return M
