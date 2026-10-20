{ self, lib, flake-parts-lib, ... }:
let
  imports = [
    ./presets/flakeModule.nix
    ./neovim/default.nix
    ./llm-netogallo/config.nix
    ./lite-llm/config.nix
    ./prelude/config.nix
    ./llm-providers/config.nix
    ./llm-providers/prelude.nix
  ];
in
{
  inherit imports;
}
