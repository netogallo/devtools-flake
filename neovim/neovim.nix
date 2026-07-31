{ self, lib, config, ... }:
let
  inherit (lib) mkOption types;
  #enabled = config.enabled;
in
  {
    imports = [
     ./plugins/telescope-config.nix
    ];
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable a neovim configuration.
        '';
        default = false;
      };
    };
  }
