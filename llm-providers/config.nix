{ lib, llm-providers, ... }:
let
  inherit (lib) mkOption types mkPerSystemOptions;
  inherit (llm-providers) model-type user-type endpoint-type provider-system-type;
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

  perSystem = _:
  let
    x = 42;
  in
    {
      options.development-tools.llm-providers = mkOption {
        type = types.attrsOf provider-system-type;
        description = ''
          This option set holds all the attributes that an llm-provider
          will make available on a per-system basis. Theese attribtues
          are used by the consumers of an llm provider to setup the
          configuration to the provider.
        '';
        default = {};
      };
    }
  ;
in
  {
    options.development-tools.llm-providers = mkOption {
      type = types.attrsOf spec;
      description = ''
        This group is meant to collect the configurations corresponding to llm
        providers in a consloidated and agnostic way. Tools acting as llm providers
        may fill the attributes in this section so other tools can use them to
        access llm models.
      '';
      default = {};
    };

    options.perSystem = mkPerSystemOptions perSystem;
  }
