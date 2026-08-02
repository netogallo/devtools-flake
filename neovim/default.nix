{ self, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib)
    mkPerSystemOption;
  neovim-prelude = lib.callPackageWith { inherit lib; } ./prelude.nix {};
  neovim-spec = types.submodule {
    imports = [ ./neovim.nix ];
    config._module.args = { inherit neovim-prelude; };
  };
  flake-config = config;
  perSystem = { pkgs, config, ... }:
  let
    to-neovim-config = name: spec: {
      # If 'callPackage' is used, one must expliclity
      # extract the required attributes. Otherwise we
      # run into infinite recursion when folding
      # over the attribute set
      inherit (
        pkgs.callPackage
        ./to-neovim-config.nix
        { inherit name spec lib pkgs; }
      ) apps;
    };
    neovim-configs =
      lib.mapAttrs
        to-neovim-config
        flake-config.development-tools.neovim
    ;
  in
    {
      config =
        lib.foldAttrs
        (attrs: state: lib.attrsets.unionOfDisjoint state attrs)
        {}
        ( lib.attrValues neovim-configs ++
          [ { apps = {}; } ]
        )
      ;
    }
  ;
in
  {
    options = {
      development-tools.neovim = mkOption {
        type = types.attrsOf neovim-spec;
        description = ''
          Neovim configurations are specified here. Each
          key corresponds to an individual configuration allowing
          multiple neovim configurations to coexist together.
        '';
        default = {};
      };
      perSystem = mkPerSystemOption perSystem;
    };
  }
