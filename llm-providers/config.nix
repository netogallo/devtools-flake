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
  The spec of an llm provider is meant to outline what
  attributes are expected from an llm provider.
  */
  spec = types.submodule {
    endpoint = endpoint-type;

    users = mkOption {
      type = types.attrsOf user-type;
      description = ''
        This field is used to specify what users are offered
        by the llm provider. Clients wishing to use the llm
        provider should rely on items from this field in
        order to authenticate with the llm provider.
      '';
      default = {};
    };

    models = mkOption {
      type = types.attrsOf model-type;
      description = ''
        This field is used by the provider to indicate what llm
        models are available through the provider. The information
        in this field will be used by clients to indicate which
        model they wish to use.
      '';
      default = {};
    };
  };
in
  {
    config._module.args = {
      llm-providers = {
        inherit endpoint-type model-type user-type;
      };
    };
    options.development-tools.llm-providers = {
      type = mkOption {
        type = types.attrsOf spec;
        description = ''
          This group is meant to collect the configurations corresponding to llm
          providers in a consloidated and agnostic way. Tools acting as llm providers
          may fill the attributes in this section so other tools can use them to
          access llm models.
        '';
        default = {};
      };
    };
  }
