{ lib, provider-type, ... }:
let
  inherit (lib) mkOption types;

  spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the llm agent. This will trigger the creation
          of the scripts used to launch the agent.
        '';
        default = false;
      };

      provider = provider-type;
    };
  };
  perSystem = _:
  let
    imports = lib.attrValues (
      lib.mapAttrs to-llm-agent top.config.development-tools.llm-agent
    );
    to-llm-agent = llm-agent-name: llm-agent: {
      imports = [ ./setup.nix ];
      config._module.args = { inherit llm-agent-name llm-agent; };
    };
  in
    { inherit imports; }
  ;
in
  {
    options.development-tools.llm-agent = mkOption {
      type = types.attrsOf spec;
      description = ''
        The 'llm-agent' development tool easily allows setting
        up sandboxed environments to run autonomus agents within
        the context of the repository.

        It also provides options to easily enhance the
        agents with MCPs or additional tools.
      '';
      default = {};
    };
  }
