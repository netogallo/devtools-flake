/** This module builds the neovim overlay
  * configuration for telescope. It will
  * create a neovim package which starts
  * the telescope plugin. Furthermore, it
  * will also generate the neovim lua
  * configuration with the specified customizations.
*/
{ lib, pkgs, neovim-spec, config, ... }:
let
  inherit (lib) mkIf;
  enable = neovim-spec.plugins.telescope.enable;
in
  {
    config = mkIf enable {
      packages.telescope-plugin = {
        start = with pkgs.vimPlugins; [
          telescope-nvim
          plenary-nvim
        ];
      };
    };
  }

