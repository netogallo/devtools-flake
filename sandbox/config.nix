/**
This module allows defining development sandboxes that are exposed as
systemd-nspawn containers. A sandbox wraps a NixOS configuration built
with the 'nspawn-container' module and provides an application
('devtools/<name>') used to launch and manage it.

A sandbox is the generic container host: it owns the networking setup,
the container user and the bind mounts. Tools that wish to run inside a
container (for example an 'opencode' instance) expose a NixOS module
that can be added to the sandbox through 'nixos-modules', following the
same pattern used by 'llm-agent' to consume 'llm-providers' in
'examples/flakeModule.nix'.
*/
top@{ self, inputs, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib) mkPerSystemOption;
  flake-config = config;

  # The user that owns the container's home directory and the
  # workspace bind mount. Only the identifying attributes that are
  # expected to vary between setups are exposed; everything else
  # (the user name, the primary group, the wheel membership, the
  # polkit power-off rule) is hardcoded in 'setup.nix' as it was in
  # the original 'opencode-container' implementation.
  user-spec = types.submodule {
    options = {
      uid = mkOption {
        type = types.ints.between 1 65534;
        default = 60375;
        description = ''
          The uid of the container's user.
        '';
      };

      gid = mkOption {
        type = types.ints.between 1 65534;
        default = 60375;
        description = ''
          The gid of the group named after the container's user.
        '';
      };

      hashedPassword = mkOption {
        type = types.str;
        default = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
        description = ''
          The hashed password of the container's user. The default
          matches the password used by the 'llm-agent' virtual
          machines so that the same credentials work everywhere.
        '';
      };
    };
  };

  sandbox-spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable this sandbox instance. This triggers the creation of
          the application used to launch and manage the container.
        '';
      };

      packages = mkOption {
        type = types.functionTo (types.listOf types.package);
        default = ps: [ ];
        defaultText = lib.literalExpression "ps: [ ]";
        description = ''
          Packages available inside the container in addition to those
          contributed by the imported 'nixos-modules'. The option takes
          a function which receives the package set used to build the
          container and returns the list of packages to install.
        '';
      };

      vlan = mkOption {
        type = types.ints.between 1 4094;
        default = 42;
        description = ''
          The vlan the container is attached to through its 'eth1'
          interface. The host side of the vlan is a bridge which acts
          as the network gateway of the container (see the
          'nspawn-container' nixos module). Containers that run
          simultaneously must either be attached to different vlans or
          use different node numbers.
        '';
      };

      node-number = mkOption {
        type = types.ints.between 1 253;
        default = 2;
        description = ''
          The number of the container within its vlan, following the
          static ip assignment scheme of the 'nspawn-container' module:
          the container takes the address
          '192.168.<vlan>.<node-number>' while the host-side bridge
          takes '.254'.
        '';
      };

      user = mkOption {
        type = user-spec;
        default = { };
        description = ''
          The container's user. Only the uid, gid and password are
          configurable; the user name ('nixos') and the rest of the
          account setup are hardcoded in 'setup.nix'.
        '';
      };

      nixos-modules = mkOption {
        type = types.listOf types.deferredModule;
        default = [ ];
        description = ''
          Additional NixOS modules imported into the container's
          configuration. Use this to install tools that expose a NixOS
          module, for example an 'opencode' instance:
            nixos-modules = [
              config.development-tools.opencode.<name>.nixos-module
            ];
        '';
      };
    };
  };

  perSystem = { pkgs, ... }:
  let
    to-sandbox = name: sandbox:
      {
        imports = [
          (import ./setup.nix { sandbox-name = name; sandbox-config = sandbox; })
        ];
      }
    ;
    imports = lib.attrValues (
      lib.mapAttrs to-sandbox flake-config.development-tools.sandbox
    );
  in
  {
    inherit imports;
  };
in
{
  options = {
    development-tools.sandbox = mkOption {
      type = types.attrsOf sandbox-spec;
      description = ''
        Development sandboxes exposed as systemd-nspawn containers.
        Each attribute becomes an individual container instance with
        its own application ('devtools/<name>').
      '';
      default = { };
    };
    perSystem = mkPerSystemOption perSystem;
  };
}
