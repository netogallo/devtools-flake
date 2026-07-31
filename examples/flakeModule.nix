{ ... }:
let
  x = 42;
in
  {
    config.development-tools.neovim.example1 = {
      enable = true;
      plugins.telescope.enable = true;
    };
  }
