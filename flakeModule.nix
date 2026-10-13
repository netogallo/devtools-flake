{ self, lib, flake-parts-lib, ... }:
let
  imports = [
    ./presets/flakeModule.nix
    ./neovim/default.nix
    ./llm-netogallo/config.nix
    ./lite-llm/config.nix
  ];
in
{
  inherit imports;
}
