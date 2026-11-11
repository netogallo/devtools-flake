{ self, inputs, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib) mkPerSystemOption;
  perSystem = { pkgs, ... }:
  let
    imports = [ ./setup.nix ];
  in
    {
      inherit imports;
      config._module.args = { inherit (inputs) nixpkgs; };
    }
  ;
in
  {
    options.perSystem = mkPerSystemOption perSystem;
  }
