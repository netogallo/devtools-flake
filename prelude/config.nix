top@{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  perSystem = { pkgs, lib, ... }:
  let
    inherit (top.config.development-tools) global-config;
    get-config = name: pkgs.callPackage ./config-instance.nix { inherit lib global-config name; };
  in
    {
      config._module.args.devtools-prelude = {
        inherit get-config;
        inherit global-config;
      };
    }
  ;
in
  {
    options = {
      development-tools.global-config = {
        config-dir = mkOption {
          type = types.str;
          description = ''
            The base directory that will contain the configuration for
            all the tools. This is meant to contain user-specific values
            that should not live at the store, potentially including
            credentials. Relative paths are allowed and will be interpreted
            relative to the repository's root. A '.gitignore' entry is
            added inside the config directory to ensure it does not get
            accidentally added to VCS.
          '';
          default = "$HOME/.config/development-tools-config";
        };
      };

      perSystem = mkPerSystemOption perSystem;
    };
  }
