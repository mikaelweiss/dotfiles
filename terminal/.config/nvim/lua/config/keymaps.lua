-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle file explorer with cmd+s or leader+e
vim.keymap.set("n", "<D-s>", ":Neotree toggle last<CR>", { desc = "Toggle file explorer" })
vim.keymap.set("n", "<leader>e", ":Neotree toggle last<CR>", { desc = "Toggle file explorer" })

-- Open file search with shift+cmd+o
vim.keymap.set("n", "<D-S-o>", "<cmd>Telescope find_files<cr>", { desc = "Find Files" })

-- Open terminal with shift+cmd+y
vim.keymap.set("n", "<D-S-y>", function()
  Snacks.terminal(nil, { win = { position = "bottom" } })
end, { desc = "Open terminal" })

-- Edit all in scope
vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename)

-- Helper to find nearest file matching pattern, searching up from current file's directory
local function find_nearest_file(pattern)
  local current_dir = vim.fn.expand("%:p:h")
  while current_dir ~= "/" do
    local files = vim.fn.glob(current_dir .. "/" .. pattern, false, true)
    if #files > 0 then
      return files[1]
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return nil
end

-- Run code based on file type with cmd+r
vim.keymap.set("n", "<D-r>", function()
  local filetype = vim.bo.filetype
  local file = vim.fn.expand("%:p")

  if filetype == "cs" then
    local csproj = find_nearest_file("*.csproj")
    if csproj then
      local run_cmd = "dotnet run --project " .. vim.fn.shellescape(csproj)
      local cmd = vim.o.shell .. " -c " .. vim.fn.shellescape(run_cmd .. "; exec " .. vim.o.shell)
      Snacks.terminal(cmd, {
        win = { position = "bottom" },
        interactive = true,
        auto_close = false,
      })
    else
      print("No .csproj file found")
    end
    return
  elseif filetype == "swift" then
    vim.cmd("XcodebuildBuildRun")
    return
  elseif filetype == "dart" then
    vim.cmd("FlutterQuit")
    vim.cmd("FlutterRun")
    return
  elseif filetype == "rust" then
    local filename = vim.fn.expand("%:t:r")
    local filepath = vim.fn.expand("%:p")
    local output = "/tmp/" .. filename
    local cmd = "rustc " .. vim.fn.shellescape(filepath) .. " -o " .. output .. " && " .. output
    Snacks.terminal(cmd, {
      win = { position = "bottom" },
      interactive = true,
      auto_close = false,
    })
  else
    vim.cmd("XcodebuildBuildRun")
    return
  end

  local run_cmd

  if filetype == "elixir" then
    run_cmd = "elixir " .. vim.fn.shellescape(file)
  elseif filetype == "python" then
    run_cmd = "python3 " .. vim.fn.shellescape(file)
  else
    print("No run command configured for filetype: " .. filetype)
    return
  end

  -- Run the command in a shell, then keep the shell open
  local cmd = vim.o.shell .. " -c " .. vim.fn.shellescape(run_cmd .. "; exec " .. vim.o.shell)

  Snacks.terminal(cmd, {
    win = { position = "bottom" },
    interactive = true,
    auto_close = false,
  })
end, { desc = "Run current file" })

-- Run tests in current file with cmd+u
vim.keymap.set("n", "<D-u>", function()
  local filetype = vim.bo.filetype

  if filetype == "cs" then
    local csproj = find_nearest_file("*.csproj")
    if csproj then
      local run_cmd = "dotnet test " .. vim.fn.shellescape(csproj)
      local cmd = vim.o.shell .. " -c " .. vim.fn.shellescape(run_cmd .. "; exec " .. vim.o.shell)
      Snacks.terminal(cmd, {
        win = { position = "bottom" },
        interactive = true,
        auto_close = false,
      })
    else
      print("No .csproj file found")
    end
  elseif filetype == "rust" then
    local module_name = vim.fn.expand("%:t:r")
    local cmd = "cargo test " .. module_name
    Snacks.terminal(cmd, {
      win = { position = "bottom" },
      interactive = true,
      auto_close = false,
    })
  else
    print("No test command configured for filetype: " .. filetype)
  end
end, { desc = "Run tests in current file" })

-- Fix ctrl+/ terminal toggle: use stable cwd so terminal ID stays consistent
-- (LazyVim.root() changes when focus is on a terminal buffer, causing new terminals)
vim.keymap.set({ "n", "t" }, "<C-/>", function()
  Snacks.terminal.toggle(nil, { cwd = vim.uv.cwd() })
end, { desc = "Toggle Terminal" })
vim.keymap.set({ "n", "t" }, "<C-_>", function()
  Snacks.terminal.toggle(nil, { cwd = vim.uv.cwd() })
end, { desc = "Toggle Terminal" })

-- Toggle comment with cmd+/
vim.keymap.set("n", "<D-/>", "gcc", { desc = "Toggle comment line", remap = true })
vim.keymap.set("v", "<D-/>", "gc", { desc = "Toggle comment selection", remap = true })

-- Buffer navigation
vim.keymap.set("n", "[[", ":bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "]]", ":bnext<CR>", { desc = "Next buffer" })
