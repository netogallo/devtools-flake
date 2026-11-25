/**
This module is responsible for generating the flake attributes that
result from an opencode configuration: a 'devtools/<name>'
application that runs opencode directly on the host (no container).

The container wrapping itself is owned by 'sandbox' (see
sandbox/config.nix and sandbox/setup.nix): a sandbox imports the
opencode 'nixos-module' (computed in opencode/config.nix) through
its 'nixos-modules' option to run opencode inside a nspawn
container, following the same pattern used by 'llm-agent' to
consume 'llm-providers' in 'examples/flakeModule.nix'.

The application sources the tool's environment (defining
DEVTOOLS_CONFIG and friends) and runs opencode with the configured
packages available in PATH.
*/
{
  opencode-name,
  opencode-config
}:
{
  config,
  lib,
  pkgs,
  devtools-prelude,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (devtools-prelude.get-config opencode-name) source-config;

  # The packages that make up this opencode configuration, built
  # against the host's package set.
  packages = opencode-config.packages pkgs;

  # A derivation exposing all the configured packages through a
  # single 'bin' directory, used to populate PATH of the wrapper.
  packages-env = pkgs.buildEnv {
    name = "opencode-${opencode-name}-env";
    paths = packages;
    pathsToLink = [ "/bin" ];
  };

  # The opencode binary, looked up among the configured packages.
  # 'lib.getExe' resolves to the package's main binary; if opencode
  # is not among the configured packages, fall back to the package
  # set's 'opencode' so the app still works with the default value.
  opencode-bin =
    let
      opencode-pkg = lib.findFirst
        (p: p.pname or null == "opencode" || p.meta.mainProgram or null == "opencode")
        pkgs.opencode
        packages;
    in
      lib.getExe opencode-pkg;

  # The launcher is a 'writeScript' (its store path is the executable
  # itself) so that 'app.program = "${launch-opencode}"' is a valid
  # single-path placeholder, matching the pattern used by the
  # 'lite-llm' and 'llm-agent' apps. The configured packages are made
  # available through PATH.
  launch-opencode = pkgs.writeScript "launch-${opencode-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e
    # shellcheck disable=SC1091
    source ${source-config}
    export PATH=${packages-env}/bin:$PATH
    exec ${opencode-bin} "$@"
  '';
in
{
  config.apps."devtools/${opencode-name}" = mkIf opencode-config.enable {
    type = "app";
    program = "${launch-opencode}";
    meta.description = "Run the '${opencode-name}' opencode configuration.";
  };
}
