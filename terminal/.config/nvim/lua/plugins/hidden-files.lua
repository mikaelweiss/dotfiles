return {
  -- Show hidden files in neo-tree (file browser)
  {
    "nvim-neo-tree/neo-tree.nvim",
    init = function()
      -- Fix: neo-tree defaults to --ignored=traditional which enumerates every
      -- file inside node_modules (~8s). Switch to --ignored=matching which only
      -- reports top-level ignored dirs (~90ms).
      local events = require("neo-tree.events")
      events.subscribe({
        event = events.BEFORE_GIT_STATUS,
        handler = function(args)
          for i, arg in ipairs(args.status_args) do
            if arg == "--ignored=traditional" then
              args.status_args[i] = "--ignored=matching"
            end
          end
        end,
      })
    end,
    opts = {
      filesystem = {
        filtered_items = {
          visible = false,
          hide_dotfiles = true,
          hide_gitignored = true,
          always_show_by_pattern = {
            ".env*",
          },
          never_show = {
            ".conductor",
            ".worktrees",
            ".nvim",
          },
        },
      },
    },
  },

  -- Show hidden files in telescope (file finder)
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        file_ignore_patterns = {
          "%.conductor/",
          "%.worktrees/",
          "%.nvim/",
        },
      },
      pickers = {
        find_files = {
          hidden = true,
          no_ignore = true,
        },
      },
    },
  },

  -- Show hidden files in snacks picker (space+f+f)
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          files = {
            hidden = true,
            ignored = true,
            exclude = { ".conductor", ".worktrees", ".nvim" },
          },
        },
      },
    },
  },
}
