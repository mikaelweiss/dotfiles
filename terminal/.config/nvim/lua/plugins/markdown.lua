return {
  {
    dir = vim.fn.stdpath("config") .. "/mdlive",
    name = "mdlive",
    ft = "markdown",
    config = function()
      require("mdlive").setup()
    end,
  },
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      opts.sources.per_filetype.markdown = { "mdlive" }
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.mdlive = { name = "Obsidian", module = "mdlive.complete", score_offset = 100 }
    end,
  },
  {
    "folke/snacks.nvim",
    opts = {
      image = { doc = { enabled = false } },
    },
  },
}
