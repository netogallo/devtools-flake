/** This module is used to enable and configure the 'indent-blankline' plugin. It aims
 *  to offer a declarative set of configuration parameters which then get translated to
 *  lua code that becomes part of the lua RC file.
 */
{ lib, config, ... }:
let
  inherit (lib) mkOption mkIf types callPackageWith;
  inherit (callPackageWith { inherit lib; } ./prelude.nix {}) presets;
  color-type = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "The name that will be used to register the color within neovim.";
      };
      fg = mkOption {
        type = types.str;
        description = "The value that will be passed as the 'fg' component of the color.";
      };
    };
  };
  color-presets = types.enum (lib.attrNames presets);
in
  {
    options.plugins.indent-blankline = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enables the "indent-blankline" plugin.
        '';
        default = false;
      };
      colors = mkOption {
        type = types.either color-presets (types.listOf color-type);
        description = ''
          Defines the list of colors that will be used by the indent-plankline
          plugin to color each of the lines of the indent. The order in which
          theese colors appear in the list will be order in which indents will
          be colored by the 'indent-blankline' plugin.

          You may also speficy preset names as strings. See the type of this
          option to know what presets exist.
        '';
        default = "none";
      };
    };
  }
