{ lib, ... }:
let
  inherit (lib) types mkOption;

  model-type = types.submodule {
    name = mkOption {
      type = types.str;
      description = ''
        A name used to identify the llm model. Clients wishing to
        send requests via this model will use this name as reference
        to the model.
      '';
    };
  };

  /**
  This submodule specifies the information that llm clients
  can use in order to establish what user to use when connecting
  to the llm provider.
  */
  user-type = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          The username to be used for authentication purposes. This should
          match the key under which this field is stored.
        '';
      };
      provider = mkOption {
        type = types.str;
        description = ''
          The name of the provider that defines this user. This is used
          by client applications to locate the right user attributes in
          the per-system components.
        '';
      };
    };
  };

  endpoint-type = types.submodule {
    options = {
      type = mkOption {
        type = types.str;
        description = ''
          This field can be used by the llm provider to indicate
          its identity. This is mainly used to determine what
          type of API is offered by the provider.
        '';
      };
      url = mkOption {
        type = types.str;
        description = ''
          This field is used to spacify how the llm provider
          can be located.
        '';
      };
    };
  };

  /**
  The provider type is meant to be used by tools which need access to
  an llm model. It defines the general interface used in this project
  for llm clients to obtain the endpoints and credentials needed
  to use an llm model offered by an llm provider.
  */
  provider-type = types.submodule {
    options = {
      endpoint = mkOption {
        type = endpoint-type;
        description = ''
          Specifies the endpoint to be used to reach the
          llm provider.
        '';
      };
      user = mkOption {
        type = user-type;
        description = ''
          Specifies the user that should be used to authenticate
          with the endpoint.
        '';
      };
      models = {
        main = mkOption {
          type = model-type;
          description = ''
            Specify what is the main llm model to be used by the
            llm agent. This model may spawn workers if needed.
            The models that will be available as workers are
            specified in this section as well.
          '';
        };
      };
    };
  };

  user-system-type = types.submodule {
    options = {
      key-script = mkOption {
        type = types.str;
        description = ''
          A shell script that can be used to print the user's key
          to the standard output. This script will be run by the
          client during startup in order to obtain the key that
          is to be used to authenticate with the llm provider.
        '';
      };
    };
  };

  provider-system-type = types.submodule {
    options = {
      users = mkOption {
        type = types.attrsOf user-system-type;
        description = ''
          This field exposes all the attributes that llm clients
          will use in order to create applications that connect
          to the llm provider as a given user.
        '';
        default = {};
      };
    };
  };
in
  {
    config._module.args = {
      llm-providers = {
        inherit endpoint-type model-type user-type provider-type
          provider-system-type user-system-type;
      };
    };
  }
