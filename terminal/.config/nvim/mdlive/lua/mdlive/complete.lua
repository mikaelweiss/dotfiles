-- blink.cmp source for Obsidian's link suggestions (`[[`) and tag suggestions (`#`).
local api = vim.api
local state = require("mdlive.state")
local vault = require("mdlive.vault")
local parse = require("mdlive.parse")

local source = {}

local tag_cache = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return vim.bo.filetype == "markdown" and state.get(api.nvim_get_current_buf()) ~= nil
end

function source:get_trigger_characters()
  return { "[", "#", "^", "|" }
end

local function fuzzy(query, str)
  if query == "" then
    return 1
  end
  local q, s = query:lower(), str:lower()
  local pos, score, last = 1, 0, 0
  for word in q:gmatch("%S+") do
    for c in word:gmatch(".") do
      local found = s:find(c, pos, true)
      if not found then
        return nil
      end
      score = score + (found == last + 1 and 3 or 1)
      last = found
      pos = found + 1
    end
  end
  return score
end

local function range(row, s, e)
  return { start = { line = row, character = s }, ["end"] = { line = row, character = e } }
end

local function kinds()
  return require("blink.cmp.types").CompletionItemKind
end

local function file_items(b, query, row, s, e, closing)
  local idx = vault.index(b.root)
  local items = {}
  for _, f in ipairs(idx.files or {}) do
    local is_md = f.rel:match("%.md$") ~= nil
    local label = is_md and vault.strip_md(vim.fs.basename(f.rel)) or vim.fs.basename(f.rel)
    local score = fuzzy(query, is_md and vault.strip_md(f.rel) or f.rel)
    if score then
      local link = vault.link_text(b.root, f.abs, b.settings)
      items[#items + 1] = {
        label = label,
        labelDetails = { description = vim.fs.dirname(f.rel) ~= "." and vim.fs.dirname(f.rel) or nil },
        kind = kinds().File,
        filterText = label,
        score_offset = score,
        textEdit = { newText = link .. closing, range = range(row, s, e) },
      }
    end
  end
  return items
end

local function target_doc(b, path_part)
  local path = path_part == "" and b.path or vault.resolve(b.root, path_part, b.path)
  if not path then
    return nil
  end
  local lines = vault.read(path)
  return lines and parse.parse(lines), path
end

local function heading_items(b, path_part, query, row, s, e, closing)
  local doc = target_doc(b, path_part)
  local items = {}
  for _, h in ipairs(doc and doc.headings or {}) do
    if fuzzy(query, h.text) then
      items[#items + 1] = {
        label = h.text,
        labelDetails = { description = ("H%d"):format(h.level) },
        kind = kinds().Reference,
        filterText = h.text,
        textEdit = { newText = path_part .. "#" .. h.text .. closing, range = range(row, s, e) },
      }
    end
  end
  return items
end

local function random_id()
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local out = {}
  for i = 1, 6 do
    local k = math.random(1, #chars)
    out[i] = chars:sub(k, k)
  end
  return table.concat(out)
end

local function block_items(b, path_part, query, row, s, e, closing)
  local doc, path = target_doc(b, path_part)
  local items = {}
  if not doc then
    return items
  end
  for r = 0, #doc.lines - 1 do
    local info = doc.rows[r]
    local next_info = doc.rows[r + 1]
    local ends_block = info.kind == "text" and (not next_info or next_info.kind ~= "text" or next_info.list or info.list)
    if ends_block or info.kind == "heading" then
      local line = doc.lines[r + 1]
      local id = line:match("%s%^([%w%-]+)%s*$")
      local shown = vim.trim((line:sub((info.cs or 0) + 1):gsub("%s%^[%w%-]+%s*$", "")))
      if shown ~= "" and fuzzy(query, shown) then
        local new_id = id or random_id()
        items[#items + 1] = {
          label = shown,
          kind = kinds().Reference,
          filterText = shown,
          textEdit = { newText = path_part .. "#^" .. new_id .. closing, range = range(row, s, e) },
          data = not id and { path = path, row = r, id = new_id } or nil,
        }
      end
    end
  end
  return items
end

local function add_block_id(data)
  local buf = vim.fn.bufnr(data.path)
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    local line = api.nvim_buf_get_lines(buf, data.row, data.row + 1, false)[1]
    api.nvim_buf_set_text(buf, data.row, #line, data.row, #line, { " ^" .. data.id })
    return
  end
  local lines = vim.fn.readfile(data.path)
  lines[data.row + 1] = lines[data.row + 1] .. " ^" .. data.id
  vim.fn.writefile(lines, data.path)
end

local function scan_tags(root)
  local entry = tag_cache[root]
  if entry and (entry.loading or vim.uv.now() - entry.time < 30000) then
    return entry.tags
  end
  tag_cache[root] = { tags = entry and entry.tags or {}, loading = true, time = vim.uv.now() }
  local cmd = { "rg", "--no-filename", "--no-line-number", "-o", "-g", "*.md", [[(?:^|\s)#[^\s#!@$%^&*(),.?":{}|<>\[\]=+;~`'\\]+]], "." }
  pcall(vim.system, cmd, { cwd = root, text = true }, function(res)
    local seen, tags = {}, {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local tag = line:match("#(.+)$")
      if tag and tag:match("[^%d]") and not seen[tag] then
        seen[tag] = true
        tags[#tags + 1] = tag
      end
    end
    tag_cache[root] = { tags = tags, loading = false, time = vim.uv.now() }
  end)
  return tag_cache[root].tags
end

function source:get_completions(ctx, callback)
  local b = state.get(ctx.bufnr)
  if not b then
    callback({ items = {} })
    return
  end
  local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local line = ctx.line
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  local open = before:match(".*()%[%[")
  if open and not before:sub(open):find("]]", 1, true) then
    local query = before:sub(open + 2)
    local closing = "]]"
    local s, e = open + 1, col + (after:match("^%]%]") and 2 or 0)
    local items = {}
    if not query:find("|", 1, true) then
      local path_part, sub = query:match("^(.-)#(.*)$")
      if path_part then
        s = s + #path_part + 1
        if sub:sub(1, 1) == "^" then
          items = block_items(b, path_part, sub:sub(2), row, open + 1, e, closing)
        else
          items = heading_items(b, path_part, sub, row, open + 1, e, closing)
        end
      else
        local block_path, block_query = query:match("^(.-)%^(.*)$")
        if block_path and block_path ~= "" then
          items = block_items(b, block_path, block_query, row, open + 1, e, closing)
        else
          items = file_items(b, query, row, s, e, closing)
        end
      end
    end
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
    return
  end
  local hash, tag = before:match("()#([^%s#]*)$")
  if hash and (hash == 1 or before:sub(hash - 1, hash - 1):match("%s")) and not before:match("^#+$") then
    local items = {}
    for _, name in ipairs(scan_tags(b.root)) do
      if fuzzy(tag, name) then
        items[#items + 1] = {
          label = "#" .. name,
          kind = kinds().Keyword,
          filterText = name,
          textEdit = { newText = "#" .. name, range = range(row, hash - 1, col) },
        }
      end
    end
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
    return
  end
  callback({ items = {} })
end

function source:execute(_, item, callback, default)
  default()
  if item.data and item.data.id then
    pcall(add_block_id, item.data)
  end
  callback()
end

return source
