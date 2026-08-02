{ lib, config, ... }:
let
  inherit (lib) mkOption mkIf types;
in
  {
    options.plugins.telescope = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the telescopoe plugin
        '';
        default = false;
      };
    };
    config = mkIf config.plugins.telescope.enable {
      commands.telescope = {
        find-files = {
          lua-run-script = ''
            local telescope = require('telescope.builtin')
            telescope.find_files()
          '';
          description = ''
            Command to display the file picker.
          '';
        };
      };
    };
  }
