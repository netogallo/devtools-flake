/**
This module is responsible for generating the flake attributes that
result from a python configuration: a 'devtools/<name>' application
that dispatches to the interpreter (mode 'python'), pip (mode 'pip')
or the activate/deactivate shell helpers.

The container wrapping itself is owned by 'sandbox' (see
sandbox/config.nix and sandbox/setup.nix): a sandbox imports the
python 'nixos-module' (computed in python/config.nix) through its
'nixos-modules' option to install the environment inside a nspawn
container, following the same pattern used by 'opencode'.
*/
{
  python-name,
  python-config
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;

  # The 'devtools/<name>' launcher, built against the host's package
  # set. The launcher is shared with the 'nixos-module' so the same
  # modes are available on the host and inside a container. Its store
  # path is the executable itself, so 'app.program = "${app}"' is a
  # valid single-path placeholder.
  app = python-config.application pkgs;
in
{
  config.apps."devtools/${python-name}" = mkIf python-config.enable {
    type = "app";
    program = "${app}";
    meta.description = "Run the '${python-name}' python configuration.";
  };
}