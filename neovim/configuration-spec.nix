/**
This module specs out the 'configuration' object that gets passed
to the `pkgs.wrapNeovim` function. Since that configuration will
be built by mergeing mulitple components, we will leverage the
the power of nixos modules to merge everything into the final
configuration object (rather than doing it manually).
*/
{ lib, ... }:
let
  inherit (lib) mkOption types;
  neovim-package = types.submodule {
    options = {
      start = mkOption {
        type = types.listOf types.package;
        description = ''
          A list of vim/neovim plugins that will
          be bundled as part of this package.
        '';
        default = [];
      };
    };
  };
in
  {
    options = {
      customLuaRC = mkOption {
        type = types.lines;
        description = ''
          Lua script that gets executed upon neovim's
          startup.
        '';
        default = "";
      };
      packages = mkOption {
        type = types.attrsOf neovim-package;
        description = ''
          The neovim packages that will be installed
          alongside the editor. A package allows bundling
          plugins amongst other things.
        '';
        default = {};
      };
    };
  }
