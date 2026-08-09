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
      globals = {
        file-ignore-patterns = mkOption {
          type = types.listOf types.str;
          description = ''
            Supplementary patters to ignore files, in addition
            to the .gitignore file. Theese are specified as
            glob patterns.
          '';
          default = [];
        };
      };
    };
    config = mkIf config.plugins.telescope.enable {
      commands.telescope = {
        find-files = {
          lua-run-script = "require('telescope.builtin').find_files()";
          description = ''
            Command to display the file picker.
          '';
        };
        live-grep = {
          lua-run-script = "require('telescope.builtin').live_grep()";
          description = ''
            Command to find strings in the workspace with telescope.
          '';
        };
      };
    };
  }
