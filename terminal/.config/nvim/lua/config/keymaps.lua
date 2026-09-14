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

-- Review against main: neo-tree lists the branch's files, gitsigns marks its lines.
-- Diffing against the merge base rather than main keeps main's newer commits out.
local function git_in(dir)
  return function(...)
    local result = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or nil
  end
end

-- The cwd is often outside any repo, so locate one from an open file instead.
local function repo_root()
  local buffers = { 0 }
  vim.list_extend(buffers, vim.api.nvim_list_bufs())
  for _, buf in ipairs(buffers) do
    local name = vim.api.nvim_buf_get_name(buf)
    local stat = name ~= "" and vim.uv.fs_stat(name)
    if stat and stat.type == "file" then
      local root = git_in(vim.fs.dirname(name))("rev-parse", "--show-toplevel")
      if root then
        return root
      end
    end
  end
  local tree = require("neo-tree.sources.manager").get_state("filesystem")
  for _, dir in ipairs({ tree and tree.path, vim.uv.cwd() }) do
    local root = dir and git_in(dir)("rev-parse", "--show-toplevel")
    if root then
      return root
    end
  end
end

local reviewing_vs_trunk = false
local base_diff_restored = false

-- neo-tree returns no base diff whenever its git status cache hits, so recompute it.
local function restore_base_diff()
  if base_diff_restored then
    return
  end
  base_diff_restored = true
  local git = require("neo-tree.git")
  local status = git.status
  git.status = function(path, base_lookup, skip_bubbling, opts)
    local git_status, root, over_base = status(path, base_lookup, skip_bubbling, opts)
    local base = root and base_lookup and base_lookup[root]
    if base and base ~= "HEAD" and not over_base then
      over_base = require("neo-tree.git.diff").diff_name_status(root, base, skip_bubbling)
    end
    return git_status, root, over_base
  end
end

vim.keymap.set("n", "<leader>gm", function()
  local root = repo_root()
  if not root then
    vim.notify("No git repo found for any open file", vim.log.levels.WARN)
    return
  end

  local gitsigns = require("gitsigns")

  -- Setting the base on the state skips the Neotree command parser, which
  -- verifies refs against the cwd instead of the repo.
  local function show_git_status(base)
    restore_base_diff()
    local state = require("neo-tree.sources.manager").get_state("git_status")
    state.git_base_by_worktree = state.git_base_by_worktree or {}
    state.git_base_by_worktree[root] = base
    state.dirty = true
    require("neo-tree.command").execute({ action = "focus", source = "git_status", dir = root })
  end

  if reviewing_vs_trunk then
    reviewing_vs_trunk = false
    gitsigns.change_base("HEAD", true)
    show_git_status("HEAD")
    vim.notify("Diffing against HEAD")
    return
  end

  local git = git_in(root)
  local trunk = git("rev-parse", "--verify", "--quiet", "main") and "main" or "master"
  local base = git("merge-base", trunk, "HEAD")
  if not base then
    vim.notify("No merge base with " .. trunk, vim.log.levels.WARN)
    return
  end
  reviewing_vs_trunk = true
  gitsigns.change_base(base, true)
  show_git_status(base)
  vim.notify("Diffing against " .. trunk .. " (" .. base:sub(1, 8) .. ")")
end, { desc = "Toggle review vs main" })
