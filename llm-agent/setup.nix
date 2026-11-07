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
  /**
  The dbus signal emitted by the 'post-receive' hook of the agent
  git repository on every push. The value of the signal is the hash
  of the latest commit of the pushed branch.

  The definition is cascaded into the agent python programs through
  the 'devtools_flake.agent.env' module (exposed as
  'env.push_signal'), which the agent manager uses to subscribe to
  the signal; the hook and the dbus policy below use the same
  values.
  */
  push-signal = {
    interface = "org.devtools_flake.events.git";
    name = "notify_push";
  };

  agent-env = pkgs.tikal.prelude.python.to-definitions-package {
    pname = "devtools_agent_env";
    vars = {
      "devtools_flake.agent.env" = {
        git = "${pkgs.git}/bin/git";
        repo_path = repo-path;
        push_signal = push-signal;
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
        devtools-agent = pyfinal.callPackage ./devtools_agent/python-agent.nix {};
      };
    };
  in
    python.withPackages (ps: [ ps.devtools-agent ])
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
  Guest-side paths of the git repository and the working directories
  the agent is spawned in.
  */
  repo-path = "/var/lib/agent/repo.git";
  work-root = "/var/lib/agent/work";

  /**
  Port on the host through which the guest's sshd is reachable.
  The launch script forwards the host port to the guest's ssh
  port so that 'git push' can reach the repository.
  */
  git-ssh-port = 2222;

  /**
  The 'post-receive' hook installed in the bare repository. For
  every pushed branch it emits the dbus signal
  'org.devtools_flake.events.git.notify_push' (with the hash of the
  latest commit of the pushed branch as value), which the agent
  manager service subscribes to. The hook does not run the agent
  itself: the push should return quickly and the agent should run
  under its own (systemd) privileges.

  Every action is logged to journald under the identifier
  'agent-post-receive' (filterable with 'journalctl -t
  agent-post-receive' inside the VM) and mirrored to stderr,
  which git forwards to the pushing client as 'remote: ...'
  lines.
  */
  post-receive-hook = pkgs.writeScript "post-receive" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # All zeros: the ref update deletes a branch.
    zero=0000000000000000000000000000000000000000

    # Log an action to journald, tagged so it can be filtered with
    #   journalctl -t agent-post-receive
    # inside the VM. Also write to stderr: git forwards hook stderr
    # to the pushing client as 'remote: ...'.
    log() {
      echo "$*" | ${pkgs.systemd}/bin/systemd-cat -t agent-post-receive -p info
      echo "$*" >&2
    }

    # Log failures before 'set -e' terminates the hook.
    trap 'echo "post-receive failed at: $BASH_COMMAND" | ${pkgs.systemd}/bin/systemd-cat -t agent-post-receive -p err' ERR

    log "post-receive started"

    # One line per ref: <old> <new> <refname>
    while read -r old new refname; do
      log "ref update: $old -> $new $refname"
      case "$refname" in
        refs/heads/*)
          if [ "$new" = "$zero" ]; then
            log "branch deleted, not notifying the agent manager: $refname"
            continue
          fi
          # Notify the agent manager of the push. The value of the
          # signal is the hash of the latest commit of the branch.
          ${pkgs.dbus}/bin/dbus-send \
            --system \
            --type=signal \
            /org/devtools_flake/events/git \
            ${push-signal.interface}.${push-signal.name} \
            string:"$new"
          log "notified agent manager of push: $refname at $new"
          ;;
        *)
          log "ignoring non-branch ref: $refname"
          ;;
      esac
    done

    log "post-receive finished"
  '';

  /**
  The script run by the templated 'agent-run@' service. The
  instance name (the canonicalized branch name, expanded by systemd
  from the '%i' specifier in the unit's ExecStart) is passed as
  the first argument; the script prepares the working directory
  for the instance and spawns the agent there.
  */
  agent-run-script = pkgs.writeText "agent-run.sh" ''
    #!${pkgs.bash}/bin/bash
    set -e

    work_root="${work-root}"

    # The systemd unit's template parameter: the canonicalized
    # name of the branch to run the agent on.
    unit_id="$1"

    # Create the work dir for this instance from the template
    # parameter.
    work="$work_root/$unit_id"
    mkdir -p "$work"

    # Run the agent in the working directory. The agent checks
    # out (or updates) the branch itself and writes its summary
    # next to the checkout.
    cd "$work"
    exec ${agent-python}/bin/python -m devtools_agent.agent --unit-id "$unit_id"
  '';

  /**
  The NixOS configuration modules of the agent machine, shared by
  the QEMU VM booted by the launch script and by the integration
  test defined below.

  In 'test-mode' the machine runs the 'test' implementation of
  the agent (see 'devtools_agent/agents.py'), which provides mock
  responses to specific test prompts: no llm provider is
  contacted. Therefore the 9p share of the provider keys (and
  its mount unit) is omitted, and the agent unit selects the test
  implementation through the 'DEVTOOLS_LLM_AGENT_MODE'
  environment variable.
  */
  guest-modules = { test-mode ? false }:
    [
      {
        imports = [
          "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        ];
        config = {
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
          virtualisation.qemu.options = lib.optionals (!test-mode) [
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
          # depended upon by the agent service. In test mode the
          # share (and its mount) is omitted: the test
          # implementation of the agent reads no keys.
          systemd.mounts = lib.optionals (!test-mode) [
            {
              what = "devtools-config";
              where = "/run/agent_keys";
              type = "9p";
              options = "trans=virtio,version=9p2000.L,ro";
              wantedBy = [ "multi-user.target" ];
            }
          ];

          environment.systemPackages = [ pkgs.git ];

          # The agent git repository is owned by the 'git' user but
          # is also accessed by other principals (the manager
          # service runs as root, and pushes performed inside the
          # machine are not done as the repository owner). Declare
          # the repository a safe directory in the system-wide git
          # configuration so git does not reject the access with
          # 'detected dubious ownership'; the exceptions in
          # 'devtools_agent/common.py' cover the direct
          # invocations, this covers the client and receive-pack
          # processes of a push.
          environment.etc."gitconfig" = lib.mkIf git-enable {
            text = ''
              [safe]
                  directory = ${repo-path}
            '';
          };

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

          # Allow any user to emit the push notification signal
          # consumed by the agent manager (the hook runs as the
          # 'git' user). The policy file is merged into the dbus
          # configuration by the NixOS dbus module.
          services.dbus.packages = [
            (pkgs.writeTextDir "etc/dbus-1/system.d/devtools-flake.conf" ''
              <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
                "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
              <busconfig>
                <policy context="default">
                  <allow send_interface="${push-signal.interface}"/>
                </policy>
              </busconfig>
            '')
          ];

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
              ln -sfn ${post-receive-hook} "${repo-path}/hooks/post-receive"
            '';
          };

          # The agent manager. It subscribes to the dbus push signal
          # emitted by the 'post-receive' hook and starts one
          # instance of the templated agent unit per branch of the
          # repository.
          systemd.services.agent-manager = {
            description = "Agent manager (push-triggered agent instance starter)";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "dbus.service"
              "git-repo-init.service"
            ];
            wants = [ "network-online.target" ];
            script = ''
              exec ${agent-python}/bin/python -m devtools_agent.agent_manager
            '';
          };

          # The templated agent service. Non-secret parameters are
          # baked in; the api key is read from the shared directory
          # at runtime. The service requires the 9p mount (holding
          # the api key) to be up before it starts. One instance is
          # started per branch by the agent manager, with the
          # canonicalized branch name as the template parameter.
          systemd.services."agent-run@" = {
            description = "LangChain deep agent for branch '%i'";
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
              # The '%i' specifier (the canonicalized branch name,
              # i.e. the unit's template parameter) is expanded by
              # systemd here and passed to the script.
              ExecStart = "${pkgs.bash}/bin/bash ${agent-run-script} %i";
            };
          };
        };
      }
    ]
    ++ lib.optionals (!test-mode) [
      {
        # The platform of the guest; the test framework provides
        # the nixpkgs of the nodes itself (read-only), so this is
        # only set for the VM booted by the launch script.
        nixpkgs.hostPlatform = pkgs.system;
      }
    ]
    ++ lib.optionals test-mode [
      {
        # Test mode: select the 'test' implementation of the
        # agent, which provides mock responses to specific test
        # prompts. The journal is not forwarded to the console
        # (the test inspects it with journalctl instead), keeping
        # the serial console of the test driver clean.
        services.journald.extraConfig = lib.mkForce "";
        systemd.services."agent-run@" = {
          environment = {
            DEVTOOLS_LLM_AGENT_MODE = "test";
          };
        };
      }
    ]
  ;

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
    modules = guest-modules {};
  };

  /**
  The integration test of the agent machine, exposed as a flake
  check. It uses the integration testing NixOS virtual machines
  available in nixpkgs to spawn the agent machine in test mode
  (the agent provides mock responses; no llm provider is
  contacted), pushes a change to the git repository and checks
  that the push correctly triggers the start of the agent for
  the corresponding git branch.
  */
  agent-vm-test = pkgs.testers.runNixOSTest {
    name = "llm-agent-${llm-agent-name}";

    nodes.machine = {
      imports = guest-modules { test-mode = true; };
    };

    testScript = ''
      start_all()

      machine.wait_for_unit("git-repo-init.service")
      machine.wait_for_unit("agent-manager.service")
      machine.wait_until_succeeds(
          "journalctl -u agent-manager.service | grep -q 'subscribed to'"
      )

      with subtest("push a change to the agent repository"):
          machine.succeed("git init -q /tmp/src")
          machine.succeed("git -C /tmp/src config user.name tester")
          machine.succeed("git -C /tmp/src config user.email tester@example.com")
          machine.succeed("echo change > /tmp/src/change.txt")
          machine.succeed("git -C /tmp/src add change.txt")
          machine.succeed("git -C /tmp/src commit -m change")
          machine.succeed("git -C /tmp/src push ${repo-path} HEAD:refs/heads/main")

      with subtest("the push triggers the agent for the pushed branch"):
          machine.wait_for_unit("agent-run@main.service")
          machine.succeed("test -f ${work-root}/main/change.txt")
          machine.wait_until_succeeds(
              "journalctl -u agent-run@main.service | grep -q 'mock response'"
          )
    '';
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

  # The integration test of the push-triggered agent pipeline,
  # only defined when the git pipeline is enabled.
  config.checks = lib.mkIf git-enable {
    "tests/devtools/${llm-agent-name}" = agent-vm-test;
  };
}
