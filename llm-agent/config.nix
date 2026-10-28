top@{ inputs, flake-parts-lib, lib, llm-providers, ... }:
let
  inherit (llm-providers) provider-type;
  inherit (flake-parts-lib) mkPerSystemOption;
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

      provider = mkOption {
        type = provider-type;
        description = ''
          This option is used to specify the provider that
          will be used to communicate with the llm agent.
        '';
      };

      git = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              description = ''
                Enable the git repository inside the agent VM.
                Pushes to the repository trigger the agent: the
                pushed branch is checked out into a working
                directory and the agent is spawned there.
              '';
              default = false;
            };

            authorizedKeys = mkOption {
              type = types.listOf types.str;
              description = ''
                SSH public keys authorized to push to the
                agent VM's git repository. The corresponding
                private keys must be available on the host
                pushing to the VM.
              '';
              default = [ ];
            };
          };
        };
        description = ''
          Configuration of the git repository hosted inside
          the agent VM.
        '';
        default = { };
      };
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
  {
    inherit imports;
    config._module.args = { inherit (inputs) nixpkgs; };
  };
in
  {
    options = {
      development-tools.llm-agent = mkOption {
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
      perSystem = mkPerSystemOption perSystem;
    };
  }
