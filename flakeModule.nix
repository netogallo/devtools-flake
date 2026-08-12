{ self, lib, flake-parts-lib, ... }:
let
  imports = [
    ./presets/flakeModule.nix
    ./neovim/default.nix
  ];
in
{
  inherit imports;
}
