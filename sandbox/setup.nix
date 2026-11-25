/**
This module is responsible for generating all the flake attributes
that result from a sandbox configuration: a 'devtools/<name>'
application which manages and launches a systemd-nspawn container
running the NixOS configuration defined below.

The directory the application is launched from is bind-mounted as
the container's workspace ('/home/nixos/workspace') and the 'nixos'
user logs in automatically on the console. The 'nixos' user can power
the container off without a password. The container's home directory
is kept outside of the root filesystem so that it survives container
rebuilds; the launch script ensures it exists before booting.

The application has two modes (the mode flags are parsed with
docopt):

  run               Boot the container.
  setup nat activate   Ensure the host is configured to run the
                    container: ip forwarding is active and the
                    firewall forwards (and masquerades) the
                    container's traffic between the container's
                    bridge and the system's network interfaces.
  setup nat deactivate Undo the configuration created by
                    'setup nat activate'.

Additional NixOS modules contributed by the tools that should run
inside the container are imported through 'sandbox.nixos-modules'
(see sandbox/config.nix).
*/
{
  sandbox-name,
  sandbox-config
}:
{
  config,
  lib,
  pkgs,
  nixpkgs,
  devtools-prelude,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  inherit (pkgs.tikal.prelude.template) template;
  inherit (devtools-prelude.get-config sandbox-name) source-config stable-config-path;

  # The system the container is built for; the application is
  # evaluated per system.
  host-system = pkgs.stdenv.hostPlatform.system;

  # Networking parameters, following the static ip assignment scheme
  # of the nspawn-container module (the host side of a vlan is a
  # bridge named 'br<vlan>' which plays the role of the network
  # gateway):
  #   container:  192.168.<vlan>.<node-number>/24
  #               2001:db8:<vlan>::<node-number>/64
  #   bridge:     192.168.<vlan>.254/24
  #               2001:db8:<vlan>::fe/64
  vlan = sandbox-config.vlan;
  node-number = sandbox-config.node-number;

  bridge = "br${toString vlan}";
  ipv4-subnet = "192.168.${toString vlan}.0/24";
  ipv6-subnet = "2001:db8:${toString vlan}::/64";

  # Public resolvers used by the container. They are reachable
  # through the forwarding/masquerading configured by the
  # 'setup nat activate' mode.
  dns-servers = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  # This hack will definetely earn me prision time, but I have no choice.
  # The goal is to have the root filesystem of the container to reside
  # in the devtools configuration directory under this tool's directory.
  # The fool might believe this can be achived by simply setting the 'virtualisation.rootDir'
  # of the container to the desired path. Unfortunately, this dosen't work because
  # nixpkgs is using the 'toCommandLineShellGNU' function to construct the 'systemd-nspawn'
  # invokation, which results in all parameters passed to the shell using single quotes
  # (ie. systemd-nspawn --rootDir '<virtualisation.rootDir>'). When this is done, variables
  # are note expanded so there is no way to reference the desired directory as it relies in
  # the "$HOME" variable.
  container-config = stable-config-path;
  container-root-dir = "${container-config}/root";

  # The container's home directory is kept outside of the root
  # filesystem so that it survives container rebuilds. The launch
  # script ensures it exists before booting (see 'launch-sandbox').
  container-home-dir = "${container-config}/home";

  # The container's user. Only the uid, gid and password are
  # configurable (see sandbox/config.nix); the user name and the rest
  # of the account setup are hardcoded here as they were in the
  # original 'opencode-container' implementation.
  user = sandbox-config.user;
  user-name = "nixos";

  # The portable part of the container's NixOS configuration: the
  # user account, the console autologin, the polkit power-off rule,
  # the installed packages, the hostname and the networking setup
  # (eth1 vlan, static addresses, dns).
  #
  # This module is deliberately independent of the nspawn wrapping
  # (it does not import the 'nspawn-container' module, nor does it set
  # 'virtualisation.rootDir' or 'virtualisation.systemd-nspawn.options'):
  # those are host-launch specifics provided by the real build below
  # and, in tests, by the NixOS test framework's 'containers.<name>'
  # machinery. Keeping the portable config separate allows the same
  # module to be imported both by the real container and by the
  # integration test, so the test exercises the actual container
  # configuration rather than a re-implementation.
  container-module = { config, pkgs, ... }:
  let
    # All network interfaces defined for the container (see
    # guest-networking-options.nix); the address configuration
    # below is derived from these definitions.
    all-interfaces = config.virtualisation.allInterfaces;
  in
  {
    # The container name determines the machine name given to
    # systemd-nspawn, the name of the network namespace and the
    # default root directory ('./<name>-root'); it is unique
    # per configured container instance.
    networking.hostName = sandbox-name;

    # Packages configured by the instance plus any contributed
    # by the imported 'nixos-modules'. The option function
    # receives the package set of the container, so the
    # configuration does not rely on a nixpkgs instance of its
    # own.
    environment.systemPackages = sandbox-config.packages pkgs;

    users.users.${user-name} = {
      group = "users";
      extraGroups = [ "wheel" ];
      isNormalUser = true;
      inherit (user) hashedPassword uid;
    };
    users.groups.${user-name} = {
      inherit (user) gid;
    };
    services.getty.autologinUser = user-name;

    # 'poweroff' is authorized through polkit: without the rule
    # below, a non-root user would be required to authenticate.
    security.polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (subject.isInGroup("wheel") &&
              (action.id == "org.freedesktop.login1.power-off" ||
               action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
               action.id == "org.freedesktop.login1.power-off-ignore-inhibit")) {
            return polkit.Result.YES;
          }
        });
      '';
    };

    # Attach 'eth1' to the configured vlan. Addresses are
    # assigned manually below.
    virtualisation.interfaces.eth1 = {
      inherit vlan;
      assignIP = false;
    };

    networking.useHostResolvConf = false;
    services.resolved.enable = true;

    nix.settings.experimental-features = [ "flakes" "nix-command" ];

    # The addresses are configured statically; do not let
    # dhcpcd touch the interfaces.
    networking.useDHCP = false;

    systemd.network = {
      enable = true;

      # Address configuration derived from the vlans of the
      # defined interfaces (see the scheme above).
      networks = lib.mapAttrs
        (name: iface: {
          enable = true;
          matchConfig.Name = name;
          dns = dns-servers;
          addresses = [
            {
              Address = "192.168.${toString iface.vlan}.${toString node-number}/24";
            }
          ];
          routes = [
            {
              Gateway = "192.168.${toString iface.vlan}.254";
            }
          ];
        })
        all-interfaces;
    };
  };

  # Host-launch specifics that only apply to the real (non-test)
  # container: the target platform, the root directory of the
  # container's filesystem and the bind mounts that expose the user's
  # persistent home and the launch directory as the workspace. The
  # NixOS test framework provides its own root directory and nspawn
  # options for test containers, so these are not part of
  # 'container-module'.
  host-launch-module = {
    nixpkgs.hostPlatform = host-system;

    # The container's root filesystem lives in the devtools
    # configuration directory (see the note on 'container-config'
    # above for why this path is used).
    virtualisation.rootDir = container-root-dir;

    # Bind the launch directory as the user's workspace and the
    # persistent home directory (outside of the root filesystem)
    # as the user's home. The workspace bind takes precedence
    # over the home bind for that subtree.
    virtualisation.systemd-nspawn.options = [
      "--bind=${container-home-dir}:/home/${user-name}"
      "--bind=.:/home/${user-name}/workspace"
    ];
  };

  nixos = nixpkgs.lib.nixosSystem {
    modules = [
      "${nixpkgs}/nixos/modules/virtualisation/nspawn-container/default.nix"
      "${nixpkgs}/nixos/modules/virtualisation/guest-networking-options.nix"
      container-module
      host-launch-module
    ] ++ sandbox-config.nixos-modules;
  };

  # The nat setup helper. It is not exposed as an app on its own; the
  # launcher invokes it through 'setup nat <activate|deactivate>'. It
  # is a 'writeShellApplication' (a directory with 'bin/<name>'), so
  # it is referenced by absolute path inside the launcher script rather
  # than as an 'app.program' (which must be a single store path).
  setup-sandbox = pkgs.writeShellApplication {
    name = "setup-${sandbox-name}";
    runtimeInputs = with pkgs; [
      coreutils
      docopts
    ];
    meta.description = "Setup scripts for the '${sandbox-name}' sandbox container.";
    text = template ./setup.sh {
      inherit sandbox-name bridge ipv4-subnet;
    };
  };
  setup-app = lib.getExe setup-sandbox;

  # The launcher is a 'writeScript' (its store path is the executable
  # itself) so that 'app.program = "${launch-sandbox}"' is a valid
  # single-path placeholder, matching the pattern used by the
  # 'lite-llm' and 'llm-agent' apps. Runtime tools are referenced by
  # absolute store path inside the script instead of through
  # 'runtimeInputs' (which is a 'writeShellApplication' feature).
  launch-sandbox = pkgs.writeScript "launch-${sandbox-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    usage="
    Usage: launch-${sandbox-name} run
           launch-${sandbox-name} setup nat activate
           launch-${sandbox-name} setup nat deactivate
           launch-${sandbox-name} (-h | --help)

    Modes:
      run                   Boot the nspawn container.
      setup nat activate    Ensure the host is configured to run the
                            container: ip forwarding is active and the
                            firewall forwards the container's traffic
                            between the container's bridge
                            ('${bridge}') and the system's network
                            interfaces.
      setup nat deactivate  Undo the configuration created by
                            'setup activate'.
    "

    # The mode flags read below, pre-initialized so that they are
    # always defined; docopts assigns the real values below.
    run=false
    setup=false

    # shellcheck disable=SC1091
    source ${source-config}

    # Parse the mode flags; docopts turns the usage text into the
    # 'run', 'setup', 'activate' and 'deactivate' shell variables.
    eval "$(${pkgs.docopts}/bin/docopts -h "$usage" : "$@")"

    if [ "$run" = "true" ]; then
      # The container keeps the user's home directory outside of the
      # root filesystem so that it survives rebuilds; make sure it
      # exists before booting (the home bind mount below would
      # otherwise fail).
      mkdir -p "${container-home-dir}"

      # The container needs ip forwarding to reach the network
      # through the host.
      if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        echo "Warning: ip forwarding is not active on the host." >&2
        echo "Run '$0 setup nat activate' to configure the host system." >&2
      fi
      exec sudo ${lib.getExe nixos.config.system.build.nspawn}
    fi

    if [[ "$setup" = "true" ]]; then
      shift
      sudo "${setup-app}" "$@"
    fi
  '';

  # Integration test: boot the sandbox container inside a NixOS test
  # VM and verify it reaches 'multi-user.target' and shuts down
  # cleanly. The test uses the NixOS test framework's 'containers'
  # support, which wraps 'container-module' with the same
  # nspawn-container machinery used by the real launch path; the same
  # 'nixos-modules' (e.g. an opencode configuration) are imported, so
  # the test exercises the actual container configuration.
  #
  # The test driver exposes each container as a Python variable named
  # after the 'pythonized' container name (non-identifier characters
  # such as '-' become '_'), so the variable name used in the test
  # script is derived from 'sandbox-name' the same way.
  machine-var = lib.stringAsChars
    (c: if builtins.match "[A-Za-z0-9_]" c != null then c else "_")
    sandbox-name;

  sandbox-test = pkgs.testers.runNixOSTest {
    name = "sandbox-${sandbox-name}";
    containers.${sandbox-name} = {
      imports = [ container-module ] ++ sandbox-config.nixos-modules;
    };
    testScript = ''
      ${machine-var}.start()
      with subtest("the sandbox container boots to multi-user.target"):
          ${machine-var}.wait_for_unit("multi-user.target")
      with subtest("the sandbox container shuts down cleanly"):
          ${machine-var}.shutdown()
    '';
  };
in
{
  config.apps."devtools/${sandbox-name}" = mkIf sandbox-config.enable {
    type = "app";
    program = "${launch-sandbox}";
    meta.description = "Launch and manage the '${sandbox-name}' sandbox container.";
  };

  config.checks."tests/devtools/${sandbox-name}" = mkIf sandbox-config.enable sandbox-test;
}
