{ config, ... }:
let
  x = 42;
in
  {
    config.development-tools.neovim.example1 = {
      enable = true;
      plugins.telescope = {
        enable = true;
        globals.file-ignore-patterns = ["**/*.nix"];
      };
      plugins.indent-blankline = {
        enable = true;
        colors = {
          RainbowRed = "#E06C75";
          RainbowYellow ="#E5C07B";
          RainbowBlue = "#61AFEF";
        };
      };
      keymaps = with config.development-tools.neovim.example1.commands.telescope; [
        {
          mode = "n";
          keymap = "<leader>ff";
          action = find-files;
          desc = "Find files with telescope";
        }
        {
          mode = "n";
          keymap = "<leader>fg";
          action = live-grep;
          desc = "Live grep search using telescope";
        }
      ];
    };
  }
