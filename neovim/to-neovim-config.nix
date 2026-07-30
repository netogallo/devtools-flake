/** This module accepts a neovim spec alongside the
    coontext and produces an attribute set containing
    the various parts that become part of the flake.
**/
{
  name,
  spec,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  configure = {
    inherit name;
    enable = true;
    #  customLuaRC = ''
    #  '';

    #  packages.nvim-netogallo = {
    #    start = with pkgs.vimPlugins; [
    #      telescope-nvim
    #      diffview-nvim
    #      #mason-nvim
    #    ];
    #  };
  };
  neovim = pkgs.wrapNeovim pkgs.neovim-unwrapped { inherit configure; };
  neovim-qt = pkgs.neovim-qt.override { inherit neovim; };
  app-name = "devtools-neovim-${name}";
  app-name-qt = "devtools-neovim-${name}-qt";
in
  {
    apps = mkIf spec.enabled {
      ${app-name} = {
        type = "app";
        program = "${neovim}/bin/nvim";
      };
      ${app-name-qt} = {
        type = "app";
        program = "${neovim-qt}/bin/nvim-qt";
      };
    };
  }

