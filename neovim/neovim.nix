{ self, lib, config, ... }:
let
  inherit (lib) mkOption types;
  #enabled = config.enabled;
in
  {
    #imports = [
    #  ./telescope.nix
    #];
    options = {
      enabled = mkOption {
        type = types.bool;
        description = ''
          Enable a neovim configuration.
        '';
        default = false;
      };
    };
  }
