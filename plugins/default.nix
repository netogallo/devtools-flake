{ lib, callPackage, ... }:
let
  plugins = {
    imports = [
      ./telescope.nix
    ]
  ;
in
  {
    module = types.submodule plugins;
  }
