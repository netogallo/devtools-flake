{ self, lib, config, ... }:
let
  inherit (lib) mkOption types;
in
  {
    imports = [
      ./keymaps/keymaps-config.nix
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
