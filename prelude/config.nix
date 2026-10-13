top@{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  perSystem = { pkgs, ... }:
  let
    inherit (top.config.development-tools) global-config;
    get-config-base = pkgs.writeScript "get-config-base" ''
      #!${pkgs.bash}/bin/bash
      export DEVTOOLS_CONFIG_ROOT="${global-config.config-dir}"
      export DEVTOOLS_CONFIG_GLOBAL="$DEVTOOLS_CONFIG_ROOT/private"

      mkdir -p "$DEVTOOLS_CONFIG_GLOBAL"
      GITIGNORE="$DEVTOOLS_CONFIG_GLOBAL/.gitignore"

      if [[ ! -e "$GITIGNORE" ]]; then
        echo "private" >> "$GITIGNORE"
      fi

      if [[ -e "$GITIGNORE" && ! -f "$GITIGNORE" ]]; then
        echo -e "\033[31mWarning: '$GITIGNORE' is not a file. Ensure that '$DEVTOOLS_CONFIG_ROOT/private' is not commited. \033[0m"
      fi
    '';
    get-config = name:
      pkgs.writeScript "get-config-for-${name}" ''
      #!${pkgs.bash}/bin/bash

      source "${get-config-base}"

      export DEVTOOLS_CONFIG="$DEVTOOLS_CONFIG_GLOBAL/${name}"

      mkdir -p "$DEVTOOLS_CONFIG"
      ''
    ;
  in
    {
      options.development-tools.global-config = {
        get-config-directory
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
          default = ".development-tools-config";
        };
      };

      perSystem = mkPerSystemOption perSystem;
    };
  }
