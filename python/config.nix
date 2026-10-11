{ self, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib)
    mkPerSystemOption;
  python-spec = types.submodule {
    imports = [ ./python-config.nix ];
  };
  perSystem = { pkgs, config, ... }:
  let
    x = 42;
  in
    {
    }
  ;
in
  {
    options = {
      development-tools.python = {
        type = types.attrsOf python-spec;
        description = ''
          Define python interpreters which are available to to
          the flake.
        '';
        default = {};
      };
      perSystem = mkPerSystemOption perSystem;
    };
  }
