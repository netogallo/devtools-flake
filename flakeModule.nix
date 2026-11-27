{ self, inputs, lib, flake-parts-lib, ... }:
let
  imports = [
    ./presets/flakeModule.nix
    ./neovim/default.nix
    ./llm-netogallo/config.nix
    ./opencode/config.nix
    ./python/config.nix
    ./lite-llm/config.nix
    ./prelude/config.nix
    ./llm-providers/config.nix
    ./llm-providers/prelude.nix
    ./llm-agent/config.nix
    ./sandbox/config.nix
  ];
  inherit (flake-parts-lib) mkPerSystemOption;
  perSystem = { system, ... }:
  let
    inherit (inputs) nixpkgs tikal-prelude;
  in
    {
      config._module.args = {
        inherit (inputs) nixpkgs;
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ tikal-prelude.overlays.tikal-prelude ];
        };
      };
    }
  ;
in
{
  inherit imports;
  options.perSystem = mkPerSystemOption perSystem;
}
