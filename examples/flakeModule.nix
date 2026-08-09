{ config, lib, ... }:
let
  ibl-colors = [
    { name = "RainbowRed"; fg = "#E06C75"; }
    { name = "RainbowYellow"; fg ="#E5C07B"; }
    { name = "RainbowBlue"; fg = "#61AFEF"; }
  ];
in
  {
    config.development-tools.neovim.example1 = {
      enable = true;
      plugins.telescope = {
        enable = true;
        #globals.file-ignore-patterns = ["**/*.nix"];
      };
      plugins.indent-blankline = {
        enable = true;
        colors = ibl-colors;
      };
      keymaps = with config.development-tools.neovim.example1.commands.telescope; [
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
  }
