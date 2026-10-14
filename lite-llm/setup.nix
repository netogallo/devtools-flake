/**
This module is responsible for generating all the flake attributes
that result from a lite-llm configuration. Multiple named lite-llm
configurations can be present in a flake, each will result in
a separate set of attributes in the flake.
*/
{ pkgs, lib, devtools-prelude, lite-llm-name, lite-llm, ... }:
let
  dummy = pkgs.writeScript "dummy" ''
    #!${pkgs.bash}/bin/bash
    source "${devtools-prelude.get-config lite-llm-name}"
    ${pkgs.cowsay}/bin/cowsay < ${lite-llm-config-yml}
  '';

  /**
  Contains llm provider specific parameters
  that are used to build the lite-llm configuration.
  This includes:
    - api_key: The provider API key. For security reasons, the
      key is not saved to the nix store. Instead each provider
      will read it from a specific environmental variable.
      When the lite-llm instance is launched, theese variables
      will be set by reading the keys from a private directory.
  */
  provider-params = {
    openrouter = rec {
      key-env-name = "OPENROUTER_API_KEY";
      api_key = "os.environ/${key-env-name}";
    };
  };

  get-provider-params = model:
  let
    parts = lib.strings.splitString "/" model;
    provider = lib.elemAt parts 0;
  in
    if lib.hasAttr provider provider-params
    then provider-params.${provider}
    else throw "Unsupported model provider '${provider}'"
  ;

  /**
  Create an attribute set matching the configuration that
  lite-llm expects for each model definition.
  */
  to-model-config = model-name: { model, ... }:
  let
    provider-params = get-provider-params model;
    provider-config = { inherit (provider-params) api_key; };
  in
    {
      inherit model-name;
      litellm_params = {
        inherit model;
      } // provider-config;
    }
  ;

  lite-llm-config = {
    model_list = lib.attrValues (lib.mapAttrs to-model-config lite-llm.models);
  };

  lite-llm-config-yml =
    pkgs.writeText "config.yml" (lib.generators.toYAML {} lite-llm-config)
  ;

  /**
  This wrapper script runs lite llm with the configuration
  defined by the 'lite-llm-config-yml' derivation. The
  process proceeds as follows:
    1. Source the tool specific environment using the
      'devtools-prelude.get-config' function. This will
      define the DEVTOOLS_CONFIG environmental variable
      which points to the tool's configuration directory
      that will be used for storing things like provider
      API keys.
    2. Based on the llm models defined in the config,
      define the necessary environmental variables for
      the API keys. The variables will be read from files
      located in the tool's configuration directory. The
      expectation is that the user will put the api keys
      in the right files. If the file does not exist,
      exit and inform the user where to save the key.
      3. Launch litellm with the settings specified by
        the config comming from the 'lite-llm' value.
        The strucutre of this object is speciifed
        in the ./config.nix file.
  */
  launch-lite-llm = null;

in
{
  config.apps."devtools/${lite-llm-name}" = {
    type = "app";
    program = "${dummy}";
  };
}
