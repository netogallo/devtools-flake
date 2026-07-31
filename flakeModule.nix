{ self, lib, flake-parts-lib, ... }:
let
  imports = [
    ./neovim/default.nix
  ];
in
{
  inherit imports;
}
