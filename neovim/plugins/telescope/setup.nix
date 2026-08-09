/** This module builds the neovim overlay
  * configuration for telescope. It will
  * create a neovim package which starts
  * the telescope plugin. Furthermore, it
  * will also generate the neovim lua
  * configuration with the specified customizations.
*/
{ lib, pkgs, neovim-spec, config, ... }:
let
  inherit (pkgs) nix-lua;
  inherit (lib) mkIf;
  inherit (neovim-spec.plugins) telescope;
  enable = telescope.enable;
  setup = {
    defaults = {
      file_ignore_patterns = telescope.globals.file-ignore-patterns;
    };
  };
in
  {
    config = mkIf enable {
      packages.telescope-plugin = {
        start = with pkgs.vimPlugins; [
          telescope-nvim
          plenary-nvim
        ];
      };
      customLuaRC = ''require('telescope').setup(${nix-lua.as-expr setup})'';
    };
  }

