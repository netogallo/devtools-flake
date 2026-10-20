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

  # This submodule configures a user that is allowed
  # to authenticate against the llm-lite instance. No
  # options are defined yet; the submodule exists so that
  # per-user settings (e.g. rate limits) can be added
  # later without changing the shape of the configuration.
  # The authentication key is deliberately not an option:
  # keys are generated when the instance is launched and
  # never enter the nix store.
  user-spec = types.submodule {
    options = {};
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

      users = mkOption {
        type = types.attrsOf user-spec;
        default = {};
        description = ''
          The users that are allowed to authenticate against this
          llm-lite instance, keyed by user name. Authentication keys
          are generated when the instance is launched and are stored
          in the tool's private configuration directory; they are not
          part of this configuration. User names are used as file names
          for the keys, so they must be file-name-safe. Authentication
          is enabled only when at least one user is defined.
        '';
      };

      port = mkOption {
        type = types.int;
        description = ''
          The port on which lite-llm will be served.
        '';
        default = 4000;
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

  to-llm-provider = name: llm-config: {
    endpoint = {
      type = "litellm";
      url = "";
    };
  };

  llm-providers = lib.mapAttrs to-llm-provider config.development-tools.lite-llm;
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

    config.development-tools.llm-providers = llm-providers;
  }
