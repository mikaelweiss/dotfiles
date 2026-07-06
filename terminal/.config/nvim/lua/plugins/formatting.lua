return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    local util = require("conform.util")

    opts.formatters_by_ft = vim.tbl_deep_extend("force", opts.formatters_by_ft or {}, {
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      jsonc = { "prettier" },
      css = { "prettier" },
      scss = { "prettier" },
      less = { "prettier" },
      html = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      graphql = { "prettier" },
      php = { "pint" },
    })

    opts.formatters = vim.tbl_deep_extend("force", opts.formatters or {}, {
      -- Prefer the project-local binaries so version + config match the repo.
      prettier = {
        command = util.find_executable({ "node_modules/.bin/prettier" }, "prettier"),
      },
      pint = {
        command = util.find_executable({ "apps/api/vendor/bin/pint", "vendor/bin/pint" }, "pint"),
      },
    })

    return opts
  end,
}
