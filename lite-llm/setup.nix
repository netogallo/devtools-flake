/**
This module is responsible for generating all the flake attributes
that result from a lite-llm configuration. Multiple named lite-llm
configurations can be present in a flake, each will result in
a separate set of attributes in the flake.
*/
{ pkgs, lib, devtools-prelude, lite-llm-name, lite-llm, ... }:
let
  /**
  Contains llm provider specific parameters
  that are used to build the lite-llm configuration.
  This includes:
    - api_key: The provider API key. For security reasons, the
      key is not saved to the nix store. Instead each provider
      will read it from a specific environmental variable.
      When the lite-llm instance is launched, these variables
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
  to-model-config = model_name: { model, ... }:
  let
    provider-params = get-provider-params model;
    provider-config = { inherit (provider-params) api_key; };
  in
    {
      inherit model_name;
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
  The environment that provides the 'litellm' executable, the
  proxy server that serves the configured models. The nixpkgs
  'litellm' package only propagates the dependencies of the
  core library, but running the proxy server requires the
  dependencies of the 'proxy' extra, i.e. the ones that
  'pip install litellm[proxy]' would install. Those are added
  to the environment explicitly.
  */
  litellm = pkgs.python3.withPackages (ps:
    [ ps.litellm ]
    ++ ps.litellm.optional-dependencies.proxy
  );

  /**
  The list of model providers used by the models configured for
  this lite-llm instance. The list contains no duplicates.
  */
  used-providers = lib.unique (
    lib.mapAttrsToList (_: { model, ... }:
      lib.head (lib.strings.splitString "/" model)
    ) lite-llm.models
  );

  /**
  Generate the shell commands that read the API key of the given
  provider from a file located in the tool's configuration
  directory (DEVTOOLS_CONFIG) and export it as an environmental
  variable. The key is expected to be saved in a file named after
  the environmental variable that lite-llm reads it from. If the
  file does not exist, the commands inform the user where to save
  the key and exit with a non-zero status.
  */
  to-api-key-setup = provider:
  let
    params = get-provider-params provider;
    key-file = "$DEVTOOLS_CONFIG/${params.key-env-name}";
  in
  ''
  if [[ ! -f "${key-file}" ]]; then
    echo -e "\033[31mError: The API key for the '${provider}' provider is missing.\033[0m" >&2
    echo "Save the key in '${key-file}' and launch '${lite-llm-name}' again." >&2
    exit 1
  fi
  export ${params.key-env-name}="$(<"${key-file}")"
  ''
  ;

  api-key-setup = lib.concatStrings (map to-api-key-setup used-providers);

  /**
  This wrapper script runs lite-llm with the configuration
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
      the config coming from the 'lite-llm' value.
      The structure of this object is specified
      in the ./config.nix file.
  */
  launch-lite-llm = pkgs.writeScript "launch-${lite-llm-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    source "${devtools-prelude.get-config lite-llm-name}"

    ${api-key-setup}

    exec ${litellm}/bin/litellm \
      --config "${lite-llm-config-yml}" \
      --port "${toString lite-llm.port}"
  '';

in
{
  config.apps."devtools/${lite-llm-name}" = {
    type = "app";
    program = "${launch-lite-llm}";
  };
}
