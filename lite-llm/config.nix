# This module allows configuring instances of llm lite
top@{ self, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib) mkPerSystemOption;

  # This submodule will be used
  # to configure the settings of the
  # modules that the llm-lite configuration
  # will be serving.
  model-spec = types.submodule {
    options = {
      model = mkOption {
        type = types.str;
        description = ''
          The name of the model. This formatter as '<provider>/<model vendor>/model'. As
          an example 'openrouter/openai/gpt-4'.
        '';
      };
    };
  };
  spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the configuration. This adds an item to the
          set of devtools available to the flake.
        '';
      };

      models = mkOption {
        type = types.attrsOf model-spec;
        description = ''
          Holds the configuration of all the models that will be available
          to the llmlite instance.
        '';
      };
    };
  };
  perSystem = _:
  let
    imports = lib.attrValues (
      lib.mapAttrs to-lite-llm top.config.development-tools.lite-llm
    );
    to-lite-llm = lite-llm-name: lite-llm: {
      imports = [ ./setup.nix ];
      config._module.args = { inherit lite-llm lite-llm-name; };
    };
  in
    { inherit imports; }
  ;
in
  {
    options = {
      development-tools.lite-llm = mkOption {
        type = types.attrsOf spec;
        description = ''
          This property allows configuring instances of llm-lite. These instances
          will be added to the catalogue of tools that can be run through
          the flake.
        '';
        default = {};
      };

      perSystem = mkPerSystemOption perSystem;
    };
  }
