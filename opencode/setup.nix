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
  lib,
  pkgs,
  nixpkgs,
  opencode-container,
  opencode-container-name,
  ...
}:
let
  inherit (lib) mkIf mkOption types;

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
    "2606:4700:4700::1111"
    "9.9.9.9"
    "2620:fe::fe"
  ];

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

          users.users.nixos = {
            group = "users";
            extraGroups = [ "wheel" ];
            isNormalUser = true;
            hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
          };
          users.groups.nixos = { };
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

          virtualisation.systemd-nspawn.options = [
            "--bind=.:/home/nixos/workspace"
          ];

          # Attach 'eth1' to the configured vlan. Addresses are
          # assigned manually below.
          virtualisation.interfaces.eth1 = {
            inherit vlan;
            assignIP = false;
          };

          networking.useHostResolvConf = false;
          services.resolved.enable = true;

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
                  {
                    Address = "2001:db8:${toString iface.vlan}::${toString node-number}/64";
                  }
                ];
                routes = [
                  {
                    Gateway = "192.168.${toString iface.vlan}.254";
                  }
                  {
                    Gateway = "2001:db8:${toString iface.vlan}::fe";
                  }
                ];
              })
              all-interfaces;
          };
        };
      })
    ];
  };

  launch-opencode-container = pkgs.writeShellApplication {
    name = "launch-${opencode-container-name}";

    runtimeInputs = with pkgs; [
      coreutils
      docopts
      iptables
      procps
    ];

    meta.description = "Manage the '${opencode-container-name}' opencode container.";

    text = ''
      usage="
      Usage: launch-${opencode-container-name} run
             launch-${opencode-container-name} setup activate
             launch-${opencode-container-name} setup deactivate
             launch-${opencode-container-name} (-h | --help)

      Modes:
        run               Boot the nspawn container.
        setup activate    Ensure the host is configured to run the
                          container: ip forwarding is active and the
                          firewall forwards the container's traffic
                          between the container's bridge
                          ('${bridge}') and the system's network
                          interfaces.
        setup deactivate  Undo the configuration created by
                          'setup activate'.
      "

      # The mode flags read below, pre-initialized so that they are
      # always defined; docopts assigns the real values below.
      run=false
      activate=false
      deactivate=false

      # Parse the mode flags; docopts turns the usage text into the
      # 'run', 'setup', 'activate' and 'deactivate' shell variables.
      eval "$(docopts -h "$usage" : "$@")"

      # Every mode requires root privileges: booting the container,
      # enabling ip forwarding and installing firewall rules all
      # operate on host resources. Re-run the script through the
      # host's 'sudo' (its setuid wrapper) if it was launched as a
      # regular user.
      if [ "$(id -u)" != "0" ]; then
        exec sudo "$0" "$@"
      fi

      # Idempotently ensure ('-C' checks the rule, '-I' inserts it at
      # the top of the chain) or remove ('-D' deletes it) an
      # iptables/ip6tables rule.
      ensure-rule() {
        local tool=$1
        shift
        if ! "$tool" -C "$@" > /dev/null 2>&1; then
          "$tool" -I "$@"
        fi
      }

      remove-rule() {
        local tool=$1
        shift
        if "$tool" -C "$@" > /dev/null 2>&1; then
          "$tool" -D "$@"
        fi
      }

      if [ "$run" = "true" ]; then
        # The container needs ip forwarding to reach the network
        # through the host.
        if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
          echo "Warning: ip forwarding is not active on the host." >&2
          echo "Run '$0 setup activate' to configure the host system." >&2
        fi
        exec ${lib.getExe nixos.config.system.build.nspawn}
      fi

      if [ "$activate" = "true" ]; then
        echo "Enabling ip forwarding..."
        sysctl -w net.ipv4.ip_forward=1
        sysctl -w net.ipv6.conf.all.forwarding=1

        echo "Ensuring firewall rules for the container's bridge '${bridge}'..."
        # Let the container's traffic leave through the host's
        # interfaces and let the replies come back in.
        ensure-rule iptables FORWARD -i ${bridge} -j ACCEPT
        ensure-rule iptables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        # Masquerade the container's traffic so that replies find
        # their way back through the host.
        ensure-rule iptables -t nat POSTROUTING -s ${ipv4-subnet} ! -o ${bridge} -j MASQUERADE

        ensure-rule ip6tables FORWARD -i ${bridge} -j ACCEPT
        ensure-rule ip6tables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        ensure-rule ip6tables -t nat POSTROUTING -s ${ipv6-subnet} ! -o ${bridge} -j MASQUERADE
      fi

      if [ "$deactivate" = "true" ]; then
        echo "Removing firewall rules for the container's bridge '${bridge}'..."
        remove-rule iptables FORWARD -i ${bridge} -j ACCEPT
        remove-rule iptables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        remove-rule iptables -t nat POSTROUTING -s ${ipv4-subnet} ! -o ${bridge} -j MASQUERADE

        remove-rule ip6tables FORWARD -i ${bridge} -j ACCEPT
        remove-rule ip6tables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        remove-rule ip6tables -t nat POSTROUTING -s ${ipv6-subnet} ! -o ${bridge} -j MASQUERADE

        echo "Disabling ip forwarding..."
        sysctl -w net.ipv4.ip_forward=0
        sysctl -w net.ipv6.conf.all.forwarding=0
      fi
    '';
  };
in
{
  options.apps = mkOption {
    type = types.lazyAttrsOf types.anything;
  };

  config.apps."devtools/${opencode-container-name}" = mkIf opencode-container.enable {
    type = "app";
    program = lib.getExe launch-opencode-container;
    meta.description = "Launch and manage the '${opencode-container-name}' opencode container.";
  };
}
