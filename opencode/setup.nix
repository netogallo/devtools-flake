/**
This module is responsible for generating all the flake attributes
that result from an opencode-container configuration: a
'devtools/<name>' application which manages and launches a
systemd-nspawn container running the NixOS configuration defined
below.

The directory the application is launched from is bind-mounted as
the container's workspace ('/home/nixos/workspace') and the 'nixos'
user logs in automatically on the console. The 'nixos' user can power
the container off without a password.

The application has three modes (the mode flags are parsed with
docopt):

  run               Boot the container.
  setup activate    Ensure the host is configured to run the
                    container: ip forwarding is active and the
                    firewall forwards (and masquerades) the
                    container's traffic between the container's
                    bridge and the system's network interfaces.
  setup deactivate  Undo the configuration created by
                    'setup activate'.
*/
{
  opencode-container,
  opencode-container-name
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
  inherit (devtools-prelude.get-config opencode-container-name) source-config stable-config-path;

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
  vlan = opencode-container.vlan;
  node-number = opencode-container.node-number;

  bridge = "br${toString vlan}";
  ipv4-subnet = "192.168.${toString vlan}.0/24";
  ipv6-subnet = "2001:db8:${toString vlan}::/64";

  # Public resolvers used by the container. They are reachable
  # through the forwarding/masquerading configured by the
  # 'setup activate' mode.
  dns-servers = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  # This hack will definetely earn me prision time, but I have no choice.
  # The goal is to have the root filesystem of the container to reside
  # in the devtools configuration directory under this tool's directory.
  # The fool might believe this can achived by simply setting the 'virtualisation.rootDir'
  # of the container to the desired path. Unfortunately, this dosen't work because
  # nixpkgs is using the 'toCommandLineShellGNU' function to construct the 'systemd-nspawn'
  # invokation, which results in all parameters passed to the shell using single quotes
  # (ie. systemd-nspawn --rootDir '<virtualisation.rootDir>'). When this is done, variables
  # are note expanded so there is no way to reference the desired directory as it relies in
  # the "$HOME" variable.
  container-config = stable-config-path;
  container-root-dir = "${container-config}/root";

  # Todo: setup scripts need to create this directory
  container-home-dir = "${container-config}/home";

  # Todo: this module should no longer expose a container
  # instead it should expose a nixos module that can then
  # be imported by configurations of sandbox/config.nix
  nixos = nixpkgs.lib.nixosSystem {
    modules = [
      ({ config, pkgs, ... }:
      let
        # All network interfaces defined for the container (see
        # guest-networking-options.nix); the address configuration
        # below is derived from these definitions.
        all-interfaces = config.virtualisation.allInterfaces;
      in
      {
        imports = [
          "${nixpkgs}/nixos/modules/virtualisation/nspawn-container/default.nix"
          "${nixpkgs}/nixos/modules/virtualisation/guest-networking-options.nix"
        ];

        config = {
          nixpkgs.hostPlatform = host-system;

          # The container name determines the machine name given to
          # systemd-nspawn, the name of the network namespace and the
          # default root directory ('./<name>-root'); it is unique
          # per configured container instance.
          networking.hostName = opencode-container-name;

          # Packages configured by the instance. The option function
          # receives the package set of the container, so the
          # configuration does not rely on a nixpkgs instance of
          # its own.
          environment.systemPackages = opencode-container.packages pkgs;

          # todo: the user should be configurable in the sandbox/config.nix code
          # Offer a simplified set of options that allow setting the uid, gid and
          # password. All other values should be hardcoded as they are now
          users.users.nixos = {
            group = "users";
            extraGroups = [ "wheel" ];
            isNormalUser = true;
            hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
            uid = 60375;
          };
          users.groups.nixos = {
            gid = 60375;
          };
          services.getty.autologinUser = "nixos";

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

          # Todo: Also bind the home directory of the container's user
          # to the container-home-dir
          virtualisation.systemd-nspawn.options = [
            "--bind=.:/home/nixos/workspace"
          ];

          # Attach 'eth1' to the configured vlan. Addresses are
          # assigned manually below.
          virtualisation.interfaces.eth1 = {
            inherit vlan;
            assignIP = false;
          };

          virtualisation.rootDir = container-root-dir;

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
      })
    ];
  };

  setup-app = lib.getExe setup-opencode-container;

  setup-opencode-container = pkgs.writeShellApplication {
    name = "setup-${opencode-container-name}";
    runtimeInputs = with pkgs; [
      coreutils
      docopts
    ];
    meta.description = "Setup scripts for the '${opencode-container-name}' opencode container.";
    text = template ./setup.sh {
      inherit opencode-container-name bridge ipv4-subnet;
    };
  };

  # Todo: this run and setup code should be generalized to
  # all containers once this gets moved to sandbox/setup.nix
  launch-opencode-container = pkgs.writeShellApplication {
    name = "launch-${opencode-container-name}";

    runtimeInputs = with pkgs; [
      coreutils
      docopts
      procps
      setup-opencode-container
    ];

    meta.description = "Manage the '${opencode-container-name}' opencode container.";

    text = ''
      usage="
      Usage: launch-${opencode-container-name} run
             launch-${opencode-container-name} setup nat activate
             launch-${opencode-container-name} setup nat deactivate
             launch-${opencode-container-name} (-h | --help)

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
      eval "$(docopts -h "$usage" : "$@")"

      if [ "$run" = "true" ]; then
        # The container needs ip forwarding to reach the network
        # through the host.
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
          echo "Warning: ip forwarding is not active on the host." >&2
          echo "Run '$0 setup activate' to configure the host system." >&2
        fi
        exec sudo ${lib.getExe nixos.config.system.build.nspawn}
      fi

      if [[ "$setup" = "true" ]]; then
        shift
        sudo "${setup-app}" "$@"
      fi
    '';
  };
in
{

  # Todo: no longer expose the app wrapped as a container. Instead this should launch
  # opencode as a regular program, not a nspawn container
  config.apps."devtools/${opencode-container-name}" = mkIf opencode-container.enable {
    type = "app";
    program = lib.getExe launch-opencode-container;
    meta.description = "Launch and manage the '${opencode-container-name}' opencode container.";
  };
}
