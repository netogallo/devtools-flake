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
    to-neovim-config = name: spec:
    let
      # If 'callPackage' is used, one must expliclity
      # extract the required attributes. Otherwise we
      # run into infinite recursion when folding
      # over the attribute set
      inherit (
        pkgs.callPackage
        ./to-neovim-config.nix
        { inherit name spec lib pkgs neovim-prelude; }
      ) apps;
    in
      {
        value = apps;
        file = ./default.nix;
      }
    ;
    neovim-configs =
      lib.attrValues (
        lib.mapAttrs
          to-neovim-config
          flake-config.development-tools.neovim
      )
    ;
  in
    {
      config.apps =
        # Todo: Do not call the police.
        # The option mergeing is using "attrsOf anything" as the type for
        # mergeing. This should not be an issue as each app definition should
        # be independent and are created programatically (not by user).
        (lib.mergeDefinitions [ "development-tools" "neovim" ] (types.attrsOf types.anything)
        ( neovim-configs ++
          [ { value = {}; file = ./default.nix; } ]
        )).mergedValue
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
