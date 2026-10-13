/**
This module is responsible for generating all the flake attributes
that result from a lite-llm configuration. Multiple named lite-llm
configurations can be present in a flake, each will result in
a separate set of attributes in the flake.
*/
{ pkgs, lib, lite-llm-name, lite-llm, ... }:
let
  dummy = pkgs.writeScript "dummy" ''
    #!${pkgs.bash}/bin/bash
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
  This wrapper sets up the environmental variables and subsequently
  launches lite llm.
  */

in
{
  config.apps."devtools/${lite-llm-name}" = {
    type = "app";
    program = "${dummy}";
  };
}
