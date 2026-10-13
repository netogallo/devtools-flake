{ config, lib, ... }:
let
  ibl-colors = [
    { name = "RainbowRed"; fg = "#E06C75"; }
    { name = "RainbowYellow"; fg ="#E5C07B"; }
    { name = "RainbowBlue"; fg = "#61AFEF"; }
  ];
in
  {
    # Enable neovim using the 'prelude' preset.
    # Use the name 'prelude-nvim' for this setup
    config.development-tools.presets.prelude.neovim.prelude-nvim.enable = true;

    # Customize the telescope exclusions of the
    # 'prelude-nvim' setup
    config.development-tools.neovim.prelude-nvim = {
      plugins.telescope.globals.file-ignore-patterns = ["flake.lock"];
    };


    config.development-tools.llm-netogallo.prelude-llm = {
      enable = true;
      task-branch-prefix = "feature";
    };

    config.development-tools.neovim.neovim-example1 = {
      enable = true;
      plugins.telescope = {
        enable = true;
        globals.file-ignore-patterns = ["flake.lock"];
      };
      plugins.indent-blankline = {
        enable = true;
        colors = ibl-colors;
      };
      keymaps = with config.development-tools.neovim.neovim-example1.commands.telescope; [
        {
          mode = "n";
          keymap = "<leader>ff";
          action = find-files;
          description = "Find files with telescope";
        }
        {
          mode = "n";
          keymap = "<leader>fg";
          action = live-grep;
          description = "Live grep search using telescope";
        }
      ];
    };

    config.development-tools.lite-llm.prelude-lite-llm = {
      enable = true;
      models = {
        "master" = {
          model = "openrouter/mistralai/devstral";
        };
      };
    };
  }
