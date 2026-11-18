local config = require("mdlive.config")

local M = {}

local indexes = {}
local listeners = {}

function M.root_for(path)
  local root = config.vault_root(path)
  if root then
    return root, true
  end
  local dir = vim.fs.dirname(path ~= "" and path or vim.fn.getcwd() .. "/x")
  local git = vim.fs.find(".git", { upward = true, path = dir })[1]
  return git and vim.fs.dirname(git) or dir, false
end

function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

local function strip_md(name)
  return (name:gsub("%.md$", ""))
end

local function build(root, files)
  local idx = { root = root, files = {}, by_name = {}, by_rel = {}, ready = true }
  for _, rel in ipairs(files) do
    local abs = root .. "/" .. rel
    idx.files[#idx.files + 1] = { rel = rel, abs = abs }
    local name = vim.fs.basename(rel)
    local key = (name:match("%.md$") and strip_md(name) or name):lower()
    idx.by_name[key] = idx.by_name[key] or {}
    table.insert(idx.by_name[key], abs)
    idx.by_rel[(rel:match("%.md$") and strip_md(rel) or rel):lower()] = abs
  end
  for _, list in pairs(idx.by_name) do
    table.sort(list, function(a, b)
      return #a < #b
    end)
  end
  return idx
end

function M.refresh(root)
  local current = indexes[root]
  if current and current.loading then
    return
  end
  indexes[root] = current or { root = root, files = {}, by_name = {}, by_rel = {}, ready = false }
  indexes[root].loading = true
  local cmd = { "rg", "--files", "--hidden", "--follow", "-g", "!.obsidian", "-g", "!.git", "-g", "!.trash" }
  local ok = pcall(vim.system, cmd, { cwd = root, text = true }, function(res)
    local files = {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      files[#files + 1] = line
    end
    vim.schedule(function()
      indexes[root] = build(root, files)
      for _, fn in ipairs(listeners) do
        pcall(fn, root)
      end
    end)
  end)
  if not ok then
    indexes[root].loading = false
  end
end

function M.index(root)
  if not indexes[root] then
    M.refresh(root)
  end
  return indexes[root]
end

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

-- Obsidian resolves a link by exact vault path first, then by file name anywhere in the vault.
function M.resolve(root, target, from)
  if target == nil or target == "" then
    return from
  end
  target = target:gsub("^/", "")
  local has_ext = target:match("%.[%w]+$") ~= nil
  local candidates = has_ext and { target } or { target .. ".md", target }
  local from_dir = from and vim.fs.dirname(from) or root
  for _, cand in ipairs(candidates) do
    for _, base in ipairs({ root, from_dir }) do
      local p = vim.fs.normalize(base .. "/" .. cand)
      if exists(p) then
        return p
      end
    end
  end
  local idx = M.index(root)
  local key = (has_ext and not target:match("%.md$")) and target or strip_md(target)
  key = key:lower()
  if idx.by_rel[key] then
    return idx.by_rel[key]
  end
  local list = idx.by_name[vim.fs.basename(key)]
  if list and #list > 0 then
    if #list == 1 or not key:find("/", 1, true) then
      return list[1]
    end
    for _, abs in ipairs(list) do
      if abs:lower():sub(-#key - 3) == key .. ".md" or abs:lower():sub(-#key) == key then
        return abs
      end
    end
  end
  return nil
end

function M.is_resolved(root, target, from)
  local idx = indexes[root]
  if not idx or not idx.ready then
    return true
  end
  return M.resolve(root, target, from) ~= nil
end

function M.link_text(root, abs, settings)
  local rel = abs:sub(#root + 2)
  local is_md = rel:match("%.md$") ~= nil
  local name = vim.fs.basename(rel)
  local short = is_md and strip_md(name) or name
  local format = settings and settings.newLinkFormat or "shortest"
  if format == "absolute" then
    return is_md and strip_md(rel) or rel
  end
  local idx = M.index(root)
  local list = idx.by_name[short:lower()] or {}
  if #list <= 1 then
    return short
  end
  return is_md and strip_md(rel) or rel
end

function M.read(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  if not exists(path) then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

local function normalize_heading(text)
  return text:lower():gsub("[%[%]#|%^:%%]", ""):gsub("%s+", " ")
end

function M.find_heading(doc, heading)
  local want = vim.trim(normalize_heading(heading))
  for _, h in ipairs(doc.headings) do
    if vim.trim(normalize_heading(h.text)) == want then
      return h
    end
  end
end

function M.find_block(lines, id)
  for i, line in ipairs(lines) do
    if line:match("%s%^" .. vim.pesc(id) .. "%s*$") or line:match("^%^" .. vim.pesc(id) .. "%s*$") then
      return i - 1
    end
  end
end

-- Rows of a note section: a heading through the line before the next heading of equal or higher rank.
function M.section(doc, heading)
  local h = M.find_heading(doc, heading)
  if not h then
    return nil
  end
  local last = #doc.lines - 1
  for _, other in ipairs(doc.headings) do
    if other.row > h.row and other.level <= h.level then
      last = other.row - 1
      break
    end
  end
  return h.row, last
end

function M.block_range(doc, id)
  local row = M.find_block(doc.lines, id)
  if not row then
    return nil
  end
  local last = row
  if doc.lines[row + 1]:match("^%^") then
    last = row - 1
    while last > 0 and doc.rows[last].kind == "blank" do
      last = last - 1
    end
    local info = doc.rows[last]
    if info.block then
      return info.block.s, info.block.e
    end
  end
  local first = last
  if not doc.rows[last].list then
    while first > 0 and doc.rows[first - 1].kind == "text" and not doc.rows[first - 1].list do
      first = first - 1
    end
  end
  return first, last
end

M.strip_md = strip_md

return M
