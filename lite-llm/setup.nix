{ pkgs, lib, lite-llm-name, lite-llm, ... }:
let
  what = lib.concatStringsSep "," (lib.attrNames lite-llm.models);
  dummy = pkgs.writeScript "dummy" ''
    #!${pkgs.bash}/bin/bash
    echo "${what}" | ${pkgs.cowsay}/bin/cowsay
  '';

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

  to-model-config = model-spec@{ model, model-name, ... }:
  let
    provider-params = get-provider-params model;
    provider-config = { inherit (provider-params) api_key; };

    result = {
      model_name = if model-name == null then model else model-name;
      litellm_params = {
        inherit model;
      } // provider-config;
    };
  in
    result
  ;

  # This function generates the config that will be used to
  # launch llm-lite. The config is saved as a derivation.
  # All keys will be read from environmental variables, with
  # a specific name per provider
  llmlite-config = llm-lite-spec: {
    model_list = lib.mapAttrs to-model-config llm-lite-spec.models;
  };

in
{
  config.apps."devtools/${lite-llm-name}" = {
    type = "app";
    program = "${dummy}";
  };
}
