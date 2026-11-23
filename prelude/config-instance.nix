/**
This module represents a configuration instance for one specific devtool. This instance can be used
by the tool to query contextual information such as the directory where it's configuration is
stored.
*/
{ pkgs, name, global-config, ... }:
let
  inherit (pkgs.tikal.prelude.do) do;
  global-config;
  get-config-base = pkgs.writeScript "get-config-base" ''
    #!${pkgs.bash}/bin/bash
    export DEVTOOLS_CONFIG_ROOT="${global-config.config-dir}"
    export DEVTOOLS_CONFIG_GLOBAL="$DEVTOOLS_CONFIG_ROOT/private"

    mkdir -p "$DEVTOOLS_CONFIG_GLOBAL"
    GITIGNORE="$DEVTOOLS_CONFIG_ROOT/.gitignore"

    if [[ ! -e "$GITIGNORE" ]]; then
      echo "private" >> "$GITIGNORE"
    fi

    if [[ -e "$GITIGNORE" && ! -f "$GITIGNORE" ]]; then
      echo -e "\033[31mWarning: '$GITIGNORE' is not a file. Ensure that '$DEVTOOLS_CONFIG_ROOT/private' is not commited. \033[0m"
    fi
  '';

  stable-config-dir = "/tmp/devtools-flake/config";

  /**
  There are use cases where a stable config path must be supplied to
  a nix derivation. The usual case is that the a nix function uses
  the 'toCommandLineShellGNU' internally, which causes env variables
  in the inputs to be interpreted literally. To work around this
  issue, we create a "stable-path" that gets symlinked with the
  config path upon sourcing the configuration.
  */
  stable-config-path = do [
    lib.toJSON { inherit name; }
    "$>" pkgs.writeText "devtools-stable-path-${name}"
    "|>" (store: lib.strings.removePrefix "/nix/store/" "${store}")
    "|>" (uid: "${stable-config-dir}/${uid}")
  ];

  /**
  This sets the environmental variables that development tools can
  use to locate resources, such as the directory that will
  be used to store user/session specific settings. This
  script is meant to be sourced by the respective tool
  before launching. The tool should provide it's name
  in order to set the variables propertly.
  */
  source-config =
    pkgs.writeScript "get-config-for-${name}" ''
    #!${pkgs.bash}/bin/bash

    source "${get-config-base}"

    export DEVTOOLS_CONFIG="$DEVTOOLS_CONFIG_GLOBAL/${name}"
    mkdir -p "${stable-config-dir}"
    mkdir -p "$DEVTOOLS_CONFIG"
    ln -sfn "$DEVTOOLS_CONFIG" "${stable-config-path}"
    ''
  ;
in
  {
    inherit source-config stable-config-path;
  }
