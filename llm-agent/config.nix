{ lib, ... }:
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

      provider = {
      };
    };
  };
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
