local api = vim.api
local state = require("mdlive.state")
local config = require("mdlive.config")
local palette = require("mdlive.palette")
local render = require("mdlive.render")
local static = require("mdlive.static")
local vault = require("mdlive.vault")
local lists = require("mdlive.lists")
local edit = require("mdlive.edit")
local links = require("mdlive.links")
local fold = require("mdlive.fold")
local center = require("mdlive.center")

local M = {}

local group = api.nvim_create_augroup("mdlive", { clear = true })

-- Treesitter keeps highlighting code inside fences, while this plugin owns all markdown styling and concealing.
local QUERIES = {
  markdown = "(inline) @spell",
  markdown_inline = "[(code_span) (link_destination) (uri_autolink) (email_autolink)] @nospell",
}

-- The markdown ftplugin restarts the default highlighter whenever FileType fires again, so this runs each time.
local function ensure_highlighter(buf)
  local b = state.get(buf)
  if not b or (b.highlighter and vim.treesitter.highlighter.active[buf] == b.highlighter) then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then
    return
  end
  if vim.treesitter.highlighter.active[buf] then
    vim.treesitter.stop(buf)
  end
  b.highlighter = vim.treesitter.highlighter.new(parser, { queries = QUERIES })
end

local function redraw(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    pcall(api.nvim__redraw, { win = win, valid = false })
  end
end

function M.setup_window(win, buf)
  local b = state.get(buf)
  if not b or not api.nvim_win_is_valid(win) then
    return
  end
  local s = b.settings
  api.nvim_win_call(win, function()
    local o = vim.opt_local
    o.conceallevel = 2
    o.concealcursor = "nvic"
    o.wrap = true
    o.linebreak = true
    o.breakindent = true
    o.breakindentopt = "list:-1"
    o.number = s.showLineNumber
    o.relativenumber = false
    o.cursorline = false
    o.list = false
    o.colorcolumn = ""
    o.spell = false
    o.foldmethod = "expr"
    o.foldexpr = "v:lua.require'mdlive.fold'.expr()"
    o.foldtext = "v:lua.require'mdlive.fold'.text()"
    o.fillchars:append({ fold = " " })
    local key = "mdlive_folds_" .. buf
    if not vim.w[key] then
      vim.w[key] = true
      o.foldlevel = 99
    end
  end)
  if not b.folds_initialized then
    b.folds_initialized = true
    vim.schedule(function()
      fold.close_collapsed_callouts(buf, win)
    end)
  end
  static.fix_topfill(buf)
end

local function set_mode(buf, mode)
  local b = state.get(buf)
  if not b then
    return
  end
  if mode == "reading" and b.mode ~= "reading" then
    b.was_modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = false
  elseif mode ~= "reading" and b.mode == "reading" then
    vim.bo[buf].modifiable = b.was_modifiable ~= false
  end
  b.mode = mode
  static.refresh(buf, true)
  redraw(buf)
end

function M.toggle_reading(buf)
  buf = buf or api.nvim_get_current_buf()
  local b = state.get(buf)
  if b then
    set_mode(buf, b.mode == "reading" and (b.edit_mode or "live") or "reading")
  end
end

function M.set_mode(mode, buf)
  buf = buf or api.nvim_get_current_buf()
  local b = state.get(buf)
  if b and mode ~= "reading" then
    b.edit_mode = mode
  end
  set_mode(buf, mode)
end

local function keymaps(buf)
  local function map(modes, lhs, rhs, desc, opts)
    vim.keymap.set(modes, lhs, rhs, vim.tbl_extend("force", { buffer = buf, silent = true, desc = desc }, opts or {}))
  end
  local nix = { "n", "i", "x" }
  map(nix, "<D-b>", function() edit.toggle("bold") end, "Toggle bold")
  map(nix, "<D-i>", function() edit.toggle("italic") end, "Toggle italic")
  map(nix, "<D-/>", function() edit.toggle("comment") end, "Toggle comment")
  map(nix, "<D-S-c>", function() edit.toggle("code") end, "Toggle code")
  map(nix, "<D-C>", function() edit.toggle("code") end, "Toggle code")
  map(nix, "<D-k>", edit.insert_link, "Insert link")
  map(nix, "<D-l>", function() edit.toggle_checklist(false) end, "Toggle checklist status")
  map(nix, "<D-e>", function() M.toggle_reading(buf) end, "Toggle reading view")
  map(nix, "<M-CR>", links.follow_cursor, "Follow link")
  map(nix, "<C-D-j>", links.follow_cursor, "Follow link")
  map(nix, "<D-CR>", links.follow_cursor, "Open link")
  map({ "n", "x" }, "<D-[>", "<C-o>", "Go back")
  map({ "n", "x" }, "<D-]>", "<C-i>", "Go forward")
  map(nix, "<M-D-Up>", function() lists.move(-1) end, "Swap line up")
  map(nix, "<M-D-Down>", function() lists.move(1) end, "Swap line down")
  map("n", "<CR>", links.enter, "Follow link or toggle task")
  map("n", "gf", links.gf, "Follow link")
  map({ "n", "i" }, "<LeftMouse>", links.click, "Click link or checkbox")
  -- blink.cmp wraps these keys and calls them as expressions, so each one hands back a <Cmd> call.
  local function cmd(fn)
    return function()
      return "<Cmd>lua require('mdlive')." .. fn .. "()<CR>"
    end
  end
  local expr = { expr = true, replace_keycodes = true }
  map("i", "<CR>", cmd("insert_enter"), "Continue list", expr)
  map("i", "<S-CR>", cmd("insert_shift_enter"), "New line in list item", expr)
  map("i", "<Tab>", cmd("insert_tab"), "Indent", expr)
  map("i", "<S-Tab>", cmd("insert_shift_tab"), "Unindent", expr)
  map("i", "<BS>", edit.backspace, "Delete pair", { expr = true, replace_keycodes = true })
  local pairs_chars = { "(", ")", "[", "]", "{", "}", "'", '"', "*", "_", "`" }
  for _, ch in ipairs(pairs_chars) do
    map("i", ch, function()
      return edit.key(ch)
    end, "Auto pair", { expr = true, replace_keycodes = true })
  end
end

function M.insert_enter()
  local ok, blink = pcall(require, "blink.cmp")
  if ok and blink.is_visible() then
    blink.accept()
    return
  end
  lists.enter()
end

function M.insert_shift_enter()
  lists.shift_enter()
end

function M.insert_tab()
  if vim.snippet.active({ direction = 1 }) then
    return vim.snippet.jump(1)
  end
  edit.indent(1)
end

function M.insert_shift_tab()
  if vim.snippet.active({ direction = -1 }) then
    return vim.snippet.jump(-1)
  end
  edit.indent(-1)
end

local function attach_renumber(buf)
  local b = state.get(buf)
  b.shadow = api.nvim_buf_get_lines(buf, 0, -1, false)
  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, first, last, new_last)
      if not state.get(buf) then
        return true
      end
      local old = b.shadow
      local new = api.nvim_buf_get_lines(buf, 0, -1, false)
      b.shadow = new
      if b.renumbering or not b.settings.smartIndentList then
        return
      end
      local changes = lists.renumber_changes(new, old, first, last, new_last)
      if #changes == 0 then
        return
      end
      vim.schedule(function()
        if not api.nvim_buf_is_valid(buf) then
          return
        end
        table.sort(changes, function(x, y)
          return x.row > y.row
        end)
        b.renumbering = true
        local insert = api.nvim_get_mode().mode:sub(1, 1) == "i"
        for _, ch in ipairs(changes) do
          local line = api.nvim_buf_get_lines(buf, ch.row, ch.row + 1, false)[1]
          if line == ch.expect then
            if not insert then
              pcall(vim.cmd, "silent! undojoin")
            end
            api.nvim_buf_set_text(buf, ch.row, ch.s, ch.row, ch.e, { ch.text })
          end
        end
        b.renumbering = false
        b.shadow = api.nvim_buf_get_lines(buf, 0, -1, false)
      end)
    end,
    on_detach = function()
      state.detach(buf)
    end,
  })
end

function M.attach(buf)
  if state.get(buf) and state.get(buf).enabled then
    return
  end
  local b = state.attach(buf)
  b.enabled = true
  local s = b.settings
  vim.bo[buf].expandtab = not s.useTab
  vim.bo[buf].tabstop = s.tabSize or 4
  vim.bo[buf].shiftwidth = s.useTab and 0 or 4
  vim.bo[buf].textwidth = 0
  vim.bo[buf].formatlistpat = [[^\s*\([-*+]\|\d\+[.)]\)\s\+\(\[.\]\s\+\)\?]]
  vim.bo[buf].formatoptions = "jql"
  vim.b[buf].autoformat = false
  vim.b[buf].minipairs_disable = true
  vim.b[buf].snacks_indent = false
  vim.b[buf].minianimate_disable = true
  ensure_highlighter(buf)
  keymaps(buf)
  attach_renumber(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    M.setup_window(win, buf)
  end
  vim.schedule(function()
    static.refresh(buf, true)
  end)
  center.schedule()
end

local function attached(buf)
  local b = state.get(buf)
  return b and b.enabled
end

local pending = {}
local function schedule_static(buf, force)
  if pending[buf] then
    pending[buf] = pending[buf] or force
    return
  end
  pending[buf] = force or false
  vim.schedule(function()
    local f = pending[buf]
    pending[buf] = nil
    static.refresh(buf, f)
  end)
end

-- Reveal state depends on the cursor, so lines whose syntax shows or hides must be redrawn when it moves.
local last_key = {}
local function reveal_key(win, buf)
  local b = state.get(buf)
  local sel = render.selection(win)
  local doc = b:doc()
  local parts = { sel.srow, sel.erow, sel.visual and (sel.scol .. "-" .. sel.ecol) or "" }
  for row = sel.srow, math.min(sel.erow, sel.srow + 200) do
    for _, sp in ipairs(doc:inlines(row)) do
      local from = row == sel.srow and sel.scol or 0
      local to = row == sel.erow and sel.ecol or math.huge
      if sp.s <= to + 1 and from <= sp.e then
        parts[#parts + 1] = row .. ":" .. sp.s
      end
    end
  end
  return table.concat(parts, ",")
end

local function on_cursor()
  local buf = api.nvim_get_current_buf()
  if not attached(buf) then
    return
  end
  local win = api.nvim_get_current_win()
  local key = reveal_key(win, buf)
  if last_key[win] ~= key then
    last_key[win] = key
    pcall(api.nvim__redraw, { win = win, valid = false })
  end
  schedule_static(buf, false)
end

function M.setup()
  palette.apply()
  render.setup()
  center.setup(group)

  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      vim.schedule(function()
        if api.nvim_buf_is_valid(ev.buf) and vim.bo[ev.buf].filetype == "markdown" then
          M.attach(ev.buf)
          ensure_highlighter(ev.buf)
          for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
            M.setup_window(win, ev.buf)
          end
        end
      end)
    end,
  })
  api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      if ev.match ~= "markdown" and attached(ev.buf) then
        state.get(ev.buf).enabled = false
        static.clear(ev.buf)
      end
    end,
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if attached(ev.buf) then
        M.setup_window(api.nvim_get_current_win(), ev.buf)
        schedule_static(ev.buf, true)
      end
    end,
  })
  api.nvim_create_autocmd({ "ColorScheme", "OptionSet" }, {
    group = group,
    callback = function(ev)
      if ev.event == "OptionSet" and ev.match ~= "background" then
        return
      end
      palette.apply()
    end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      if attached(ev.buf) then
        schedule_static(ev.buf, false)
      end
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = on_cursor,
  })
  api.nvim_create_autocmd({ "CursorMovedI", "InsertLeave" }, {
    group = group,
    callback = function(ev)
      local b = state.get(ev.buf)
      if not b then
        return
      end
      local row = api.nvim_win_get_cursor(0)[1]
      if ev.event == "InsertLeave" or b.pair_row ~= row then
        edit.clear_tracking(ev.buf)
      end
      b.pair_row = row
    end,
  })
  api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      for _, win in ipairs(vim.v.event.windows or api.nvim_list_wins()) do
        local buf = api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win)
        if buf and attached(buf) then
          schedule_static(buf, false)
        end
      end
    end,
  })
  api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      local buf = api.nvim_get_current_buf()
      if attached(buf) then
        static.fix_topfill(buf)
      end
    end,
  })
  api.nvim_create_autocmd({ "BufWritePost", "BufFilePost", "BufDelete" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local b = state.get(ev.buf)
      local root = b and b.root or vault.root_for(ev.file)
      if root then
        vault.refresh(root)
      end
    end,
  })
  vault.on_change(function(root)
    for buf, b in pairs(state.buffers) do
      if b.root == root and api.nvim_buf_is_valid(buf) then
        schedule_static(buf, true)
        redraw(buf)
      end
    end
  end)

  api.nvim_create_user_command("Md", function(opts)
    local arg = opts.args
    if arg == "live" or arg == "source" or arg == "reading" then
      M.set_mode(arg)
    elseif arg == "toggle" then
      M.toggle_reading()
    end
  end, {
    nargs = 1,
    complete = function()
      return { "live", "source", "reading", "toggle" }
    end,
    desc = "Switch the markdown view: live preview, source, or reading",
  })

  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
      M.attach(buf)
    end
  end
end

return M
