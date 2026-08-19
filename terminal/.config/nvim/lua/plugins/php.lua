local function composer_root(filename)
  local composer = vim.fs.find("composer.json", { path = filename, upward = true })[1]
  return composer and vim.fs.dirname(composer)
end

-- Laravel resolves `->forCompletedUploads()` at runtime to the model method
-- `scopeForCompletedUploads`, so no language server can follow the call.
-- Retry a failed definition with the `scope`-prefixed name.
local function scope_symbol(results, query)
  for client_id, response in pairs(results) do
    for _, symbol in ipairs(response and response.result or {}) do
      local name = symbol.name:match("[^:]+$") or symbol.name
      if name == query and symbol.location then
        local client = vim.lsp.get_client_by_id(client_id)
        return symbol.location, client and client.offset_encoding
      end
    end
  end
end

local function goto_eloquent_scope(word)
  local query = "scope" .. word:sub(1, 1):upper() .. word:sub(2)

  if #vim.lsp.get_clients({ bufnr = 0, method = "workspace/symbol" }) == 0 then
    vim.notify("No locations found for " .. word, vim.log.levels.INFO)
    return
  end

  vim.lsp.buf_request_all(0, "workspace/symbol", { query = query }, function(results)
    local location, encoding = scope_symbol(results, query)
    if not location then
      vim.notify("No locations found for " .. word .. " or " .. query, vim.log.levels.INFO)
      return
    end
    vim.schedule(function()
      vim.cmd("normal! m'")
      vim.lsp.util.show_document(location, encoding, { focus = true })
    end)
  end)
end

local function has_location(results)
  for _, response in pairs(results) do
    local result = response and response.result
    if result and (not vim.islist(result) or #result > 0) then
      return true
    end
  end
  return false
end

local function goto_definition()
  local word = vim.fn.expand("<cword>")

  vim.lsp.buf_request_all(0, "textDocument/definition", function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end, function(results)
    vim.schedule(function()
      if has_location(results) then
        Snacks.picker.lsp_definitions()
      else
        goto_eloquent_scope(word)
      end
    end)
  end)
end

-- Snacks keeps the newest keymap for a given key, so this must register after
-- LazyVim binds its own gd inside the nvim-lspconfig config.
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyLoad",
  desc = "PHP goto definition falls back to Eloquent scopes",
  callback = function(event)
    if event.data ~= "nvim-lspconfig" or not Snacks then
      return
    end
    Snacks.keymap.set("n", "gd", goto_definition, {
      lsp = { name = "intelephense", method = "textDocument/definition" },
      desc = "Goto Definition (Eloquent scope aware)",
    })
  end,
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "php", "php_only", "phpdoc", "blade", "css" },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        intelephense = {
          root_markers = { "composer.json", ".git" },
          settings = {
            intelephense = {
              files = { maxSize = 5000000 },
              format = { enable = false },
            },
          },
        },
        laravel_lsp = {
          cmd = { "laravel-lsp" },
          filetypes = { "php", "blade" },
          root_markers = { "artisan", "composer.json", ".git" },
          init_options = {
            phpEnvironment = "local",
          },
        },
      },
    },
  },

  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "blade-formatter",
        "php-debug-adapter",
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        blade = { "blade-formatter" },
      },
    },
  },

  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        php = { "phpstan" },
      },
      linters = {
        phpstan = {
          prepend_args = { "--memory-limit=1G" },
          condition = function(ctx)
            local root = composer_root(ctx.filename)
            if not root then
              return false
            end
            local bin = root .. "/vendor/bin/phpstan"
            if vim.fn.executable(bin) == 0 then
              return false
            end
            local phpstan = require("lint").linters.phpstan
            phpstan.cmd = bin
            phpstan.cwd = root
            return true
          end,
        },
      },
    },
  },

  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "V13Axel/neotest-pest",
      "olimorris/neotest-phpunit",
    },
    opts = {
      adapters = {
        ["neotest-pest"] = {},
        ["neotest-phpunit"] = {
          root_ignore_files = { "tests/Pest.php" },
        },
      },
    },
  },
}
