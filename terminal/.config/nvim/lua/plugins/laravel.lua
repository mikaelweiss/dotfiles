return {
  {
    "adalessa/laravel.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
    },
    ft = { "php", "blade" },
    event = { "BufEnter composer.json" },
    opts = {
      features = {
        pickers = {
          provider = "snacks",
        },
      },
    },
    keys = {
      {
        "<leader>pl",
        function()
          Laravel.pickers.laravel()
        end,
        desc = "Laravel",
      },
      {
        "<leader>pa",
        function()
          Laravel.pickers.artisan()
        end,
        desc = "Artisan",
      },
      {
        "<leader>pr",
        function()
          Laravel.pickers.routes()
        end,
        desc = "Routes",
      },
      {
        "<leader>pm",
        function()
          Laravel.pickers.make()
        end,
        desc = "Make",
      },
      {
        "<leader>pc",
        function()
          Laravel.pickers.commands()
        end,
        desc = "Commands",
      },
      {
        "<leader>po",
        function()
          Laravel.pickers.resources()
        end,
        desc = "Resources",
      },
      {
        "<leader>pt",
        function()
          Laravel.commands.run("actions")
        end,
        desc = "Code Actions",
      },
      {
        "<leader>ph",
        function()
          Laravel.commands.run("hub")
        end,
        desc = "Artisan Hub",
      },
      {
        "<leader>pp",
        function()
          Laravel.commands.run("command_center")
        end,
        desc = "Command Center",
      },
      {
        "<leader>pd",
        function()
          Laravel.run("artisan docs")
        end,
        desc = "Documentation",
      },
      {
        "<c-g>",
        function()
          Laravel.commands.run("view:finder")
        end,
        ft = { "php", "blade" },
        desc = "View Finder",
      },
      {
        "gf",
        function()
          local ok, resource = pcall(function()
            return Laravel("laravel.services.gf"):cursorOnResource()
          end)
          if ok and resource then
            Laravel.commands.run("gf")
          else
            vim.cmd("normal! gf")
          end
        end,
        ft = { "php", "blade" },
        desc = "Goto Resource or File",
      },
    },
  },

  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>p", group = "laravel" },
      },
    },
  },
}
