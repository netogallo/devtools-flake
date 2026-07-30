{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  module = types.submodule ({ config, ... }:
    
in
  {
    options.plugins.telescope = {
      enable = true;
    };
  }
