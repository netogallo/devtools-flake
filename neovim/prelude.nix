{ lib, ... }:
let
  inherit (lib) mkOption types;
  command-spec = types.submodule {
    options = {
      lua-run-script = mkOption {
        description = ''
          The lua script that is to be run for the
          command to happen. This code will be embeded
          in the luaRC file in paces where the command
          is to be run.
        '';
        type = types.str;
      };
      description = mkOption {
        description = ''
          A field that allows documenting the command.
        '';
        type = types.str;
        default = "";
      };
    };
  };
  overlay = final: prev: final.callPackage ./overlay.nix {};
in
  {
    inherit command-spec overlay;
  }
