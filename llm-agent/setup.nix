/**
This module is responsible for generating all the flake attributes
that result from an llm-agent configuration. Each configured agent
is run inside a QEMU VM running NixOS; the agent connects to the
llm provider specified in the configuration (e.g. a lite-llm
instance running on the host machine).

When 'llm-agent.git.enable' is set, the VM additionally hosts a
git repository that accepts pushes over ssh. Pushes trigger the
agent: the pushed branch is checked out into a working directory
and the agent is spawned there with the task of summarizing the
changes of the last commit.
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
  agent-env = pkgs.tikal.prelude.python.to-definitions-package {
    pname = "agent-env";
    vars = {
      "devtools_flake.agent.env" = {
        git = "${pkgs.git}/bin/git";
        repo_path = repo-path;
      };
    };
  };

  /**
  The python to run the agent. This python
  contains the 'python-agent' package which
  implements all the functionality concerned
  with the running of the agent with langchain.
  */
  agent-python =
  let
    python = pkgs.python314.override {
      self = python;
      packageOverrides = pyfinal: pyprev: {
        agent-env = pyfinal.callPackage agent-env {};
        devtools-agent = pyfinal.callPackage ./python-agent/python-agent.nix {};
      };
    };
  in
    python.withPackages (ps: [ ps.python-agent ])
  ;

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
  Whether the git repository (and the push-triggered agent
  pipeline) is enabled for this agent.
  */
  git-enable = llm-agent.git.enable;
  git-authorized-keys = llm-agent.git.authorized-keys;

  /**
  Guest-side paths of the git repository, the spool directory
  watched for pushed branches, and the working directories the
  agent is spawned in.
  */
  repo-path = "/var/lib/agent/repo.git";
  inbox-path = "/var/lib/agent/inbox";
  work-root = "/var/lib/agent/work";

  /**
  Port on the host through which the guest's sshd is reachable.
  The launch script forwards the host port to the guest's ssh
  port so that 'git push' can reach the repository.
  */
  git-ssh-port = 2222;

  /**
  The script implementing the agent. All secrets are read
  at runtime from the environment / the shared key directory,
  so nothing here is unsuitable for the nix store.

  The working directory is given as the first argument; the
  agent changes into it so that all tools (and the dummy task
  of summarizing the last commit) operate on the pushed branch.
  */
  agent-script = pkgs.writeText "agent.py" ''

  '';

  /**
  The 'post-receive' hook installed in the bare repository. For
  every pushed branch it drops a file (named after a sanitized
  branch name) into the spool directory, which the systemd path
  unit turns into an agent run. The hook does not run the agent
  itself: the push should return quickly and the agent should
  run under its own (systemd) privileges.

  Every action is logged to journald under the identifier
  'agent-post-receive' (filterable with 'journalctl -t
  agent-post-receive' inside the VM) and mirrored to stderr,
  which git forwards to the pushing client as 'remote: ...'
  lines.
  */
  post-receive-hook = pkgs.writeScript "post-receive" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # Todo:
    # This script should use dbus to emit the signal 'org.devtools_flake.events.git.notify_push' 
    # The signal will contain the hash of the latest commit as value.

    log "post-receive finished"
  '';

  /**
  The script run by the 'agent-run' service. For each spool file
  (i.e. each pushed branch) it checks the branch out into a
  working directory and spawns the agent there, writing its
  summary to 'AGENT_SUMMARY.md' in the working directory.
  */
  agent-run-script = pkgs.writeText "agent-run.sh" ''
    #!${pkgs.bash}/bin/bash
    set -e

    inbox="${inbox-path}"
    work_root="${work-root}"
    mkdir -p "$work_root"

    # Todo: create the work dir by using the
    # systemd unit's template parameter
    work=

    # Run the agent in the working directory, capturing
    # its summary next to the checkout.
    (cd "$work"; ${agent-python}/bin/python -m devtools_agent.agent.py --unit-id=<systemd template parameter>)\
  '';

  /**
  The NixOS configuration of the guest VM. The agent runs as a
  systemd service; the host's private configuration directory
  (holding the provider authentication keys) is shared read-only
  through a 9p mount so that secrets never enter the nix store
  or the QEMU command line.

  When the git pipeline is enabled, the VM additionally hosts
  the git repository (reachable over ssh) and the push-triggered
  agent service.
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
          boot.initrd.availableKernelModules = [ "9p" "9pnet_virtio" ];
          boot.kernelModules = [ "9p" "9pnet_virtio" ];

          users.users.nixos.hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
          users.users.nixos.group = "nixos";
          users.users.nixos.extraGroups = [ "wheel" ];
          users.groups.nixos = { };
          users.users.nixos.isNormalUser = true;

          services.journald.extraConfig = ''
            ForwardToConsole=yes
            MaxLevelConsole=info
          '';

          # The 9p mount of the shared key directory, defined as an
          # explicit systemd mount unit (rather than a fileSystems
          # entry) so it is generated directly as a unit and can be
          # depended upon by the agent service.
          systemd.mounts = [
            {
              what = "devtools-config";
              where = "/run/agent_keys";
              type = "9p";
              options = "trans=virtio,version=9p2000.L,ro";
              wantedBy = [ "multi-user.target" ];
            }
          ];

          environment.systemPackages = [ pkgs.git ];

          # The git repository and the push-triggered agent.
          services.openssh = {
            enable = git-enable;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
            };
          };

          # Forward the guest ssh port so that the host can
          # push to the repository.
          virtualisation.forwardPorts = lib.optionals git-enable [
            { from = "host"; host.port = git-ssh-port; guest.port = 22; }
          ];

          users.users.git = lib.mkIf git-enable {
            isSystemUser = true;
            group = "git";
            home = "/var/lib/agent";
            createHome = true;
            shell = "${pkgs.git}/bin/git-shell";
            openssh.authorizedKeys.keys = git-authorized-keys;
          };
          users.groups.git = lib.mkIf git-enable { };

          # Create the bare repository and install the push hook.
          systemd.services.git-repo-init = {
            description = "Initialize the agent git repository";
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "git";
              Group = "git";
            };
            script = ''
              if [ ! -d "${repo-path}" ]; then
                ${pkgs.git}/bin/git init --bare "${repo-path}"
              fi
              mkdir -p "${inbox-path}"
              ln -sfn ${post-receive-hook} "${repo-path}/hooks/post-receive"
            '';
          };

          # Pushes drop spool files; watch the spool directory and
          # trigger the agent run.
          systemd.paths.agent-inbox = {
            description = "Watch the agent inbox for pushed branches";
            wantedBy = [ "multi-user.target" ];
            pathConfig = {
              PathExistsGlob = "${inbox-path}/*";
              Unit = "agent-run.service";
            };
          };

          # The agent service. Non-secret parameters are baked in;
          # the api key is read from the shared directory at runtime.
          # The service's output is forwarded to the kernel log so
          # that it shows up on the serial console, i.e. in the
          # terminal that launched the VM. The service requires the
          # 9p mount (holding the api key) to be up before it starts.
          systemd.services.agent-run = {
            description = "LangChain deep agent template for branch.";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "run-agent_keys.mount"
              "git-repo-init.service"
            ];
            wants = [ "network-online.target" ];
            environment = {
              OPENAI_BASE_URL = provider-endpoint-url;
              OPENAI_MODEL = provider-model;
              AGENT_USER = provider-user;
              AGENT_KEYS_DIR = "/run/agent_keys";
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "git";
              Group = "git";
              #StandardOutput = "kmsg";
              #StandardError = "kmsg";
            };
            script = ''
              exec ${pkgs.bash}/bin/bash ${agent-run-script}
            '';
            #unitConfig.OnFailure = [ "poweroff.target" ];
          };
        };
      }
    ];
  };

  /**
  The host-side launch script. It exposes two modes:

    run   Boot the agent VM.
    push  Push the current branch (or an explicit refspec) of the
          host repository to the agent VM's git repository.

  The arguments are parsed with docopts. In 'run' mode the script
  sources the tool specific environment (defining DEVTOOLS_CONFIG),
  warns if no llm provider is reachable on the host, provisions the
  provider key into the shared configuration directory and boots
  the VM. In 'push' mode it pushes over ssh to the repository in
  the running VM.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    usage="
    Usage: launch-${llm-agent-name} run
           launch-${llm-agent-name} push [<refspec>]

    Modes:
      run   Boot the agent VM.
      push  Push the current branch (or <refspec>) of the host
            repository to the agent VM's git repository.
    "

    # Parse the arguments; docopts turns the usage text into shell
    # variables ('run', 'push', 'key', 'refspec').
    eval "$(${pkgs.docopts}/bin/docopts -h "$usage" : "$@")"

    if [ "$run" = "true" ]; then
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
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      refspec="''${refspec:-HEAD:refs/heads/$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)}"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}${repo-path}" "$refspec"
    fi
  '';

in
{
  config.apps."devtools/${llm-agent-name}" = {
    type = "app";
    program = "${launch-llm-agent}";
  };
}
