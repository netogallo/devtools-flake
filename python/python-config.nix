{ self, config, lib, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
in
  {
    enable = mkOption {
      type = types.bool;
      description = ''
        Enable python development. This will install the python interpreter and allows
        the programmer to configure the environment.
      '';
      default = false;
    };

    packages = mkOption {
      type = types.listOf types.str;
      description = ''
        The PyPi packages to install alongside the python installation.
      '';
      default = [];
    };
  };
