{ config, ... }:
let
  x = 42;
in
  {
    config.development-tools.neovim.example1 = {
      enable = true;
      plugins.telescope.enable = true;
      keymaps = with config.development-tools.neovim.example1.plugins.telescope.commands; [
        {
          mode = "n";
          keymap = "<leader>ff";
          action = find-files;
          desc = "Find files with telescope";
        }
      ];
    };
  }
