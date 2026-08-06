{ lib, config, ... }:
let
  inherit (lib) mkOption mkIf types;
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
        type = types.attrsOf types.str;
        description = ''
          Define a set of colors that will be used for
          each line at every indentation level. The
          keys are the names given to each color and
          the value is the hex representation of the
          color. Example:
          `
            {
              RainbowRed = "#E06C75"
              RainbowYellow = "#E5C07B",
              RainbowBlue" = "#61AFEF"
            }
          `
        '';
        default = {};
      };
    };
  }
