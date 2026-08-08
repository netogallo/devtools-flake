{ self, lib, config, neovim-prelude, ... }:
let
  inherit (neovim-prelude) command-spec;
  inherit (lib) mkOption types;
in
  {
    imports = [
      ./keymaps/keymaps-config.nix
      ./plugins/telescope-config.nix
      ./plugins/indent-blankline-config.nix
    ];
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable a neovim configuration.
        '';
        default = false;
      };

      globals = {
        mapleader = mkOption {
          type = types.str;
          description = ''
            The key combination to which the '<leader>' key is mapped
            to.
          '';
          default = " ";
        };
      };

      commands = mkOption {
        type = types.attrsOf (types.attrsOf command-spec);
        description = ''
          This configuration option is meant to serve as
          the attribute set where the available neovim
          commands are enumerated for declarative use.
        '';
        default = {};
      };
    };
  }
