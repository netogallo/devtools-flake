{ self, inputs, lib, flake-parts-lib, ... }:
let
  imports = [
    ./presets/flakeModule.nix
    ./neovim/default.nix
    ./llm-netogallo/config.nix
    ./opencode/config.nix
    ./lite-llm/config.nix
    ./prelude/config.nix
    ./llm-providers/config.nix
    ./llm-providers/prelude.nix
    ./llm-agent/config.nix
  ];
  inherit (flake-parts-lib) mkPerSystemOption;
  perSystem = { pkgs, ... }:
  {
    config._module.args = { inherit (inputs) nixpkgs; };
  }
  ;
in
{
  inherit imports;
  options.perSystem = mkPerSystemOption perSystem;
}
