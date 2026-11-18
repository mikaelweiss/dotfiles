-- Obsidian's readable line length. Neovim always wraps at the window edge, so empty padding windows
-- narrow the note's window and center it.
local api = vim.api
local state = require("mdlive.state")

local M = {}

-- Obsidian caps lines at 700px, which wraps body text at about 90 characters.
M.width = 90

local PAD_FT = "mdlive_pad"
local MIN_PAD = 4
local pads = {}

local function valid(win)
  return win and api.nvim_win_is_valid(win)
end

local function is_pad(win)
  return valid(win) and vim.bo[api.nvim_win_get_buf(win)].filetype == PAD_FT
end

local function editing_windows(tab)
  local out = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_win_get_config(win).relative == "" and not is_pad(win) and vim.bo[buf].buftype == "" then
      out[#out + 1] = win
    end
  end
  return out
end

local function new_pad(main, side, width)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = PAD_FT
  local win = api.nvim_open_win(buf, false, { split = side, win = main, width = width })
  local wo = vim.wo[win]
  wo.winfixwidth = true
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.winbar = ""
  wo.list = false
  wo.spell = false
  wo.fillchars = "eob: ,vert: "
  wo.winhighlight = "NormalNC:Normal,EndOfBuffer:Normal,WinSeparator:MdPadSeparator"
  return win
end

local function remove(tab)
  local p = pads[tab]
  if not p then
    return
  end
  pads[tab] = nil
  for _, win in ipairs({ p.left, p.right }) do
    if valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
  if valid(p.main) then
    vim.wo[p.main].winhighlight = p.main_whl
  end
end

local updating = false

function M.update()
  if updating then
    return
  end
  updating = true
  local ok, err = pcall(function()
    local tab = api.nvim_get_current_tabpage()
    local mains = editing_windows(tab)
    local main = #mains == 1 and mains[1] or nil
    local b = main and state.get(api.nvim_win_get_buf(main))
    if not (b and b.enabled and b.settings.readableLineLength ~= false) then
      return remove(tab)
    end
    local p = pads[tab]
    if p and p.main ~= main then
      remove(tab)
      p = nil
    end
    local total = api.nvim_win_get_width(main)
    if p then
      for _, win in ipairs({ p.left, p.right }) do
        if valid(win) then
          total = total + api.nvim_win_get_width(win) + 1
        end
      end
    end
    local target = M.width + vim.fn.getwininfo(main)[1].textoff
    local spare = total - target - 2
    if spare < 2 * MIN_PAD then
      return remove(tab)
    end
    local left = math.floor(spare / 2)
    local right = spare - left
    if not p then
      p = { main = main, main_whl = vim.wo[main].winhighlight }
      pads[tab] = p
      local whl = p.main_whl ~= "" and (p.main_whl .. ",") or ""
      vim.wo[main].winhighlight = whl .. "WinSeparator:MdPadSeparator"
    end
    if not valid(p.left) then
      p.left = new_pad(main, "left", left)
    end
    if not valid(p.right) then
      p.right = new_pad(main, "right", right)
    end
    api.nvim_win_set_width(p.left, left)
    api.nvim_win_set_width(p.right, right)
  end)
  updating = false
  if not ok then
    vim.notify("mdlive: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local scheduled = false
function M.schedule()
  if scheduled then
    return
  end
  scheduled = true
  vim.schedule(function()
    scheduled = false
    M.update()
  end)
end

-- Focus never rests in a pad: coming from the note it continues outward, otherwise it returns to the note.
local function on_enter()
  local win = api.nvim_get_current_win()
  if not is_pad(win) then
    return
  end
  local p = pads[api.nvim_get_current_tabpage()]
  if not p or not valid(p.main) then
    return
  end
  local from = vim.fn.win_getid(vim.fn.winnr("#"))
  vim.schedule(function()
    if api.nvim_get_current_win() ~= win then
      return
    end
    if from == p.main then
      vim.cmd("wincmd " .. (win == p.left and "h" or "l"))
    end
    if is_pad(api.nvim_get_current_win()) then
      api.nvim_set_current_win(p.main)
    end
  end)
end

function M.setup(group)
  local bg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  api.nvim_set_hl(0, "MdPadSeparator", { fg = bg, bg = bg })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      local nbg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
      api.nvim_set_hl(0, "MdPadSeparator", { fg = nbg, bg = nbg })
    end,
  })
  api.nvim_create_autocmd({ "BufWinEnter", "WinNew", "WinClosed", "WinResized", "VimResized", "TabEnter" }, {
    group = group,
    callback = M.schedule,
  })
  api.nvim_create_autocmd("WinEnter", { group = group, callback = on_enter })
  -- Closing the note should quit as if the pads were not there.
  api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local tab = api.nvim_get_current_tabpage()
      local p = pads[tab]
      if p and p.main == api.nvim_get_current_win() then
        remove(tab)
      end
    end,
  })
end

return M
