{ lib, config, ... }:
let
  inherit (lib) mkOption types;
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
  }
