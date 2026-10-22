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

  /**
  The names of the users defined in the configuration. The names
  are used as file names for the generated authentication keys,
  so they are validated to only contain file-name-safe characters.
  */
  user-names =
  let
    names = lib.attrNames lite-llm.users;
    invalid = lib.filter (name: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" name == null) names;
  in
    if invalid == [ ]
    then names
    else throw "lite-llm user names must be file-name-safe, invalid: ${toString invalid}"
  ;

  /**
  A litellm custom authenticator that validates the bearer token
  of each request against the keys of the users defined in the
  configuration. litellm 1.89.0 no longer ships the class based
  'CustomAuth' interface; the supported interface is the module
  level 'user_api_key_auth' coroutine. litellm calls it with the
  incoming request and the presented api key: raising an exception
  rejects the request, returning a key allows it. The keys are
  stored in the tool's configuration directory, one file per user,
  under the directory pointed to by the 'LITE_LLM_USERS_DIR'
  environmental variable, which is exported by the launch script
  before litellm starts. Only the user names are embedded in the
  module, so removing a user from the configuration revokes their
  access even if their key file still exists.
  */
  custom-auth = pkgs.writeText "custom_auth.py" ''
    import os
    from typing import Union

    from fastapi import Request

    from litellm.proxy._types import ProxyException, UserAPIKeyAuth

    USERS = ${builtins.toJSON user-names}

    def invalid_api_key() -> ProxyException:
        return ProxyException(
            message="Invalid API key",
            type="invalid_request_error",
            param="api_key",
            code=401,
        )

    async def user_api_key_auth(
        request: Request, api_key: str
    ) -> Union[UserAPIKeyAuth, str]:
        users_dir = os.environ.get("LITE_LLM_USERS_DIR", "")
        if not api_key or not users_dir:
            raise invalid_api_key()
        for user in USERS:
            try:
                with open(os.path.join(users_dir, user + ".key")) as key_file:
                    if key_file.read().strip() == api_key:
                        return UserAPIKeyAuth(api_key=api_key)
            except OSError:
                continue
        raise invalid_api_key()
  '';

  master-key-name = "LITELLM_MASTER_KEY";

  lite-llm-config = {
    model_list = lib.attrValues (lib.mapAttrs to-model-config lite-llm.models);
    master_key = "os.environ/${master-key-name}";
  } // lib.optionalAttrs (user-names != [ ]) {
    general_settings.custom_auth = "custom_auth.user_api_key_auth";
  };

  lite-llm-config-yml =
    pkgs.writeText "config.yml" (lib.generators.toYAML {} lite-llm-config)
  ;

  /**
  A directory that bundles the lite-llm yaml configuration together
  with the custom authenticator module. litellm resolves the custom
  authenticator relative to the directory that contains the yaml
  configuration, so both files need to reside in the same directory.
  */
  lite-llm-config-dir = pkgs.runCommand "litellm-config-${lite-llm-name}" {} ''
    mkdir -p "$out"
    cp "${lite-llm-config-yml}" "$out/config.yml"
    cp "${custom-auth}" "$out/custom_auth.py"
  '';

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
  Generate the shell commands that ensure that the given user has
  an authentication key. The key is stored in a file named after
  the user, located in the users directory of the tool's
  configuration directory. If the file does not exist, a random
  key is generated and saved there. Existing keys are never
  overwritten, so keys are re-used across launches.
  */
  to-user-key-setup = user:
  ''
  if [[ ! -f "$users_dir/${user}.key" ]]; then
    ${pkgs.openssl}/bin/openssl rand -hex 32 > "$users_dir/${user}.key"
    chmod 600 "$users_dir/${user}.key"
    echo "Generated the authentication key of '${user}': $users_dir/${user}.key"
  fi
  ''
  ;

  /**
  Set the lite-llm master key. This key will be generated if
  missing. Afterwards it will be loaded into the environment.
  */
  master-key-setup =
  ''
  master_key="$DEVTOOLS_CONFIG/${master-key-name}.key"

  if [[ ! -f "$master_key" ]]; then
    ${pkgs.openssl}/bin/openssl rand -hex 32 > "$master_key"
    chmod 600 "$users_dir/$master_key"
    echo "Generated the master authentication key at $master_key"
  fi

  export ${master-key-name}="$(<$master_key)"
  ''
  ;

  /**
  Binding that contains the script text resposible for
  defining the variables used to locate directories
  where user setup is stored.
  */
  users-env = ''users_dir="$DEVTOOLS_CONFIG/users"'';

  /**
  The shell commands that prepare the authentication keys of all
  the users defined in the configuration. The directory holding
  the keys is exported through the 'LITE_LLM_USERS_DIR'
  environmental variable so that the custom authenticator can
  locate it. When no users are defined the commands are empty and
  no authentication is enabled.
  */
  users-setup =
    if user-names == [ ]
    then ""
    else
    ''
    ${users-env}
    mkdir -p "$users_dir"
    export LITE_LLM_USERS_DIR="$users_dir"
    ${lib.concatStrings (map to-user-key-setup user-names)}
    ''
  ;

  /**
  This wrapper script runs lite-llm with the configuration
  defined by the 'lite-llm-config-dir' derivation. The
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
    3. Based on the users defined in the config, ensure
      that each user has an authentication key. A random
      key is generated for users that do not have one
      yet; existing keys are re-used. The directory
      holding the keys is exported through the
      'LITE_LLM_USERS_DIR' environmental variable, which
      is read by the custom authenticator.
    4. Launch litellm with the settings specified by
      the config coming from the 'lite-llm' value.
      The structure of this object is specified
      in the ./config.nix file.
  */
  launch-lite-llm = pkgs.writeScript "launch-${lite-llm-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    source "${devtools-prelude.get-config lite-llm-name}"

    ${master-key-setup}

    ${api-key-setup}

    ${users-setup}

    exec ${litellm}/bin/litellm \
      --config "${lite-llm-config-dir}/config.yml" \
      --port "${toString lite-llm.port}"
  '';

  to-provider-user = user-name: _:
  let
    key-script-text = ''
      #!${pkgs.bash}/bin/bash
      set -e
      source "${devtools-prelude.get-config lite-llm-name}"
      ${users-env}
      user_key="$users_dir/${user}.key"

      if [[ ! -f "$user_key" ]]; then
        echo -e "\033[31mError: Key for '${user}' not available, did you launch the llm-provider?\033[0m" >&2
        exit 1
      else
        cat "$user_key"
      fi
    '';
    key-script = pkgs.writeScript "key-script-${user-name}" key-script-text;
  in
    { inherit key-script; }
  ;
in
{
  config.apps."devtools/${lite-llm-name}" = {
    type = "app";
    program = "${launch-lite-llm}";
  };

  config.development-tools.llm-providers.${lite-llm-name} = {
    users = lib.foldAttrs to-provider-user {} (lib.map (name: { ${name} = name; }) user-names);
  };
}
