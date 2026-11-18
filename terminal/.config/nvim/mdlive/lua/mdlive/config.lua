local M = {}

-- Obsidian's own defaults, taken from its app bundle.
M.defaults = {
  useTab = true,
  tabSize = 4,
  showInlineTitle = true,
  spellcheck = true,
  autoPairBrackets = true,
  autoPairMarkdown = true,
  smartIndentList = true,
  foldHeading = true,
  foldIndent = true,
  showIndentGuide = true,
  showLineNumber = false,
  newFileLocation = "root",
  newFileFolderPath = "/",
  newLinkFormat = "shortest",
  attachmentFolderPath = "/",
}

local cache = {}

local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  return ok and data or nil
end

local function obsidian_json()
  local candidates = {
    vim.fn.expand("~/Library/Application Support/obsidian/obsidian.json"),
    vim.fn.expand("~/.config/obsidian/obsidian.json"),
  }
  for _, path in ipairs(candidates) do
    local data = read_json(path)
    if data then
      return data
    end
  end
end

function M.vault_root(path)
  local dir = vim.fs.dirname(path ~= "" and path or vim.fn.getcwd() .. "/x")
  local found = vim.fs.find(".obsidian", { upward = true, path = dir, type = "directory" })[1]
  return found and vim.fs.dirname(found) or nil
end

-- Outside a vault, the settings of the vault Obsidian opened last still describe how the user writes.
function M.last_vault()
  local data = obsidian_json()
  if not data or not data.vaults then
    return nil
  end
  local best, best_ts
  for _, vault in pairs(data.vaults) do
    if vault.path and (not best_ts or (vault.ts or 0) > best_ts) then
      best, best_ts = vault.path, vault.ts or 0
    end
  end
  return best
end

function M.get(root)
  root = root or M.last_vault()
  local key = root or ""
  if cache[key] then
    return cache[key]
  end
  local settings = vim.deepcopy(M.defaults)
  if root then
    for _, name in ipairs({ "app.json", "appearance.json" }) do
      local data = read_json(root .. "/.obsidian/" .. name)
      if data then
        settings = vim.tbl_extend("force", settings, data)
      end
    end
    local types = read_json(root .. "/.obsidian/types.json")
    settings.propertyTypes = types and types.types or {}
  else
    settings.propertyTypes = {}
  end
  cache[key] = settings
  return settings
end

function M.indent_unit(settings)
  return settings.useTab and "\t" or "    "
end

return M
