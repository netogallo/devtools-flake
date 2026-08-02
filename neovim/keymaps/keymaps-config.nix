{ lib, callPackage, ... }:
let
  inherit (lib) mkOption types;
  inherit (callPackage ./prelude.nix {}) modes;
  mode-type = types.enum modes;
  keymap =
    types.submodule {
      options = {
        mode = mkOption {
          type = types.oneOf [ mode-type (types.listOf mode-type) ];
          description = ''
            The mode on which the keymap is applicable. It defaults to
            "normal" (n) if omited.
            See: https://neovim.io/doc/user/map/#_1.3-mapping-and-modes
          '';
          default = "n";
        };
        keymap = mkOption {
          type = types.str;
          description = ''
            The string encoding the key combination that will
            activate this mapping. It follows the notation
            used by the `vim.keymap.set` function.
          '';
        };
        action = mkOption {
          type = types.str;
          description = ''
            The action to be performed when the key combination
            corresponding to this keymap is pressed.
          '';
        };
        desc = mkOption {
          type = types.str;
          description = ''
            The `desc` argument that is supplied to the `vim.keymap.set`
            function when creating the keymap.
          '';
        };
      };
    }
  ;
in
  {
    options = {
      keymaps = mkOption {
        type = types.listOf keymap;
        description = ''
          Allows setting keymaps for neovim. Keymaps will be activated
          on startup by creating calls to the `vim.keymap.set` function
          in the Lua RC file.
        '';
      };
    };
  }
