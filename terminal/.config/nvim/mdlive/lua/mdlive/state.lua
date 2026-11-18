local parse = require("mdlive.parse")
local config = require("mdlive.config")
local vault = require("mdlive.vault")

local M = { buffers = {} }

local Buf = {}
Buf.__index = Buf

function M.attach(buf)
  if M.buffers[buf] then
    return M.buffers[buf]
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local root, is_vault = vault.root_for(path)
  local settings = config.get(is_vault and root or nil)
  local b = setmetatable({ buf = buf, mode = "live", root = root, is_vault = is_vault, settings = settings, path = path }, Buf)
  M.buffers[buf] = b
  vault.index(root)
  return b
end

function M.get(buf)
  return M.buffers[buf]
end

function M.detach(buf)
  M.buffers[buf] = nil
end

function Buf:doc()
  local tick = vim.api.nvim_buf_get_changedtick(self.buf)
  if self.tick ~= tick or not self._doc then
    self._doc = parse.parse(vim.api.nvim_buf_get_lines(self.buf, 0, -1, false))
    self.tick = tick
  end
  return self._doc
end

return M
