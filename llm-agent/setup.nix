/**
This module is responsible for generating all the flake attributes
that result from an llm-agent configuration. Each configured agent
is run inside a QEMU VM running NixOS; the agent connects to the
llm provider specified in the configuration (e.g. a lite-llm
instance running on the host machine).
*/
{
  config,
  pkgs,
  lib,
  devtools-prelude,
  llm-agent-name,
  llm-agent,
  nixpkgs,
  ...
}:
let
  /**
  The python environment that runs the agent. The 'langchain'
  package provides the agent machinery while 'langchain-openai'
  provides the OpenAI-compatible client used to connect to the
  llm provider (lite-llm exposes an OpenAI-compatible API).
  */
  agent-python = pkgs.python314.withPackages (ps: [
    ps.langchain
    ps.langchain-openai
  ]);

  /**
  Non-secret agent parameters, baked into the guest configuration.
  The endpoint url comes from the provider configuration (for
  lite-llm providers it points at the QEMU host alias so that
  requests are forwarded to the instance running on the host).
  */
  provider-endpoint-url = llm-agent.provider.endpoint.url;
  provider-model = llm-agent.provider.models.main.name;
  provider-user = llm-agent.provider.user.name;
  key-script =
    with llm-agent.provider.user;
    config.development-tools.llm-providers.${provider}.users.${name}.key-script
  ; 

  /**
  The script implementing the deep agent. All secrets are read
  at runtime from the environment / the shared key directory,
  so nothing here is unsuitable for the nix store.
  */
  agent-script = pkgs.writeText "agent.py" ''
    import os

    from langchain_openai import ChatOpenAI
    from langchain_core.tools import tool
    from langgraph.prebuilt import create_react_agent

    # --- Configuration (injected by the systemd service) ---
    base_url = os.environ["OPENAI_BASE_URL"]
    model = os.environ["OPENAI_MODEL"]
    user = os.environ["AGENT_USER"]

    # --- API key: read at runtime from the shared config dir ---
    key_file = os.path.join(os.environ["AGENT_KEYS_DIR"], "users", user + ".key")
    with open(key_file) as f:
        api_key = f.read().strip()

    # --- LLM client via the provider's OpenAI-compatible API ---
    llm = ChatOpenAI(
        model=model,
        base_url=base_url,
        api_key=api_key,
    )

    # --- Dummy task tools ---
    @tool
    def list_files(directory: str) -> str:
        """List the files in the given directory."""
        return "\n".join(sorted(os.listdir(directory)))

    tools = [list_files]

    # --- The deep agent, given a dummy task ---
    agent = create_react_agent(llm, tools)

    result = agent.invoke({
        "messages": [
            ("user",
             "List the files in /tmp and briefly summarize what you find.")
        ]
    })

    for message in result["messages"]:
        content = getattr(message, "content", None)
        if content:
            print(content)
  '';

  /**
  The NixOS configuration of the guest VM. The agent runs as a
  systemd service; the host's private configuration directory
  (holding the provider authentication keys) is shared read-only
  through a 9p mount so that secrets never enter the nix store
  or the QEMU command line.
  */
  vm = nixpkgs.lib.nixosSystem {
    modules = [
      {
        imports = [
          "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        ];
        config = {
          nixpkgs.hostPlatform = pkgs.system;
          virtualisation.memorySize = 2048;
          virtualisation.cores = 2;

          # Run the VM without a graphical display; the guest's
          # serial port (ttyS0) is connected directly to the
          # terminal that launched the VM, and the kernel console
          # is placed on that serial line.
          virtualisation.graphics = false;
          boot.kernelParams = [ "console=ttyS0" ];

          # Share the host's private configuration directory with
          # the guest through 9p. The mount is read-only; the agent
          # only needs to read its authentication key.
          virtualisation.qemu.options = [
            ''-virtfs local,path="$DEVTOOLS_CONFIG",mount_tag=devtools-config,security_model=none,readonly=on''
          ];
          fileSystems."/run/agent-keys" = {
            device = "devtools-config";
            fsType = "9p";
            options = [ "trans=virtio" "version=9p2000.L" "ro" ];
          };
          users.users.nixos.hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
          users.users.nixos.group = "nixos";
          users.groups.nixos = {};
          users.users.nixos.isNormalUser = true;

          # The agent service. Non-secret parameters are baked in;
          # the api key is read from the shared directory at runtime.
          # The service's output is forwarded to the kernel log so
          # that it shows up on the serial console, i.e. in the
          # terminal that launched the VM.
          systemd.services.llm-agent = {
            description = "LangChain deep agent";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              OPENAI_BASE_URL = provider-endpoint-url;
              OPENAI_MODEL = provider-model;
              AGENT_USER = provider-user;
              AGENT_KEYS_DIR = "/run/agent-keys";
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              StandardOutput = "kmsg";
              StandardError = "kmsg";
            };
            script = ''
              exec ${agent-python}/bin/python ${agent-script}
            '';
          };
        };
      }
    ];
  };

  /**
  The host-side launch script. It sources the tool specific
  environment (defining DEVTOOLS_CONFIG), warns if no llm
  provider is reachable on the host, and boots the VM with
  the private configuration directory shared through 9p.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    source "${devtools-prelude.get-config llm-agent-name}"

    if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
      echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
      echo "If a lite-llm instance provides this model, launch it on the host first." >&2
    fi

    user_key=$(${key-script})
    user_key_dir="$DEVTOOLS_CONFIG/users/"
    mkdir -p "$user_key_dir"
    echo "$user_key" > "$user_key_dir/${provider-user}.key"
    export DEVTOOLS_CONFIG
    exec ${vm.config.system.build.vm}/bin/run-nixos-vm
  '';

in
{
  config.apps."devtools/${llm-agent-name}" = {
    type = "app";
    program = "${launch-llm-agent}";
  };
}
