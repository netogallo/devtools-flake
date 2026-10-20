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
    name = mkOption {
      type = types.str;
      description = ''
        The username to be used for authentication purposes. This should
        match the key under which this field is stored.
      '';
    };
  };

  endpoint-type = types.submodule {
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

  /**
  The provider type is meant to be used by tools which need access to
  an llm model. It defines the general interface used in this project
  for llm clients to obtain the endpoints and credentials needed
  to use an llm model offered by an llm provider.
  */
  provider-type = types.submodule {
    endpoint = endpoint-type;
    user = user-type;
    models = {
      main = model-type;
    };
  };
in
  {
    config._module.args = {
      llm-providers = {
        inherit endpoint-type model-type user-type provider-type;
      };
    };
  }
