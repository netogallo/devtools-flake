/** This file holds the flake configuration spec for the
*   'opencode-container' development tool. The tool runs 'opencode'
*   (and any other configured packages) inside a systemd-nspawn
*   container, which provides:
*   - A disposable development environment bound to the directory
*     the container is launched from.
*   - Multiple named container instances.
*   - A network setup which isolates the containers in vlans while
*     still allowing them to reach the network through the host.
*/
{ self, inputs, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption literalExpression;
  inherit (flake-parts-lib) mkPerSystemOption;
  flake-config = config;

  opencode-container-spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable this container instance. This will trigger the
          creation of the application used to launch and manage
          the container.
        '';
        default = false;
      };

      packages = mkOption {
        type = types.functionTo (types.listOf types.package);
        description = ''
          Packages available inside the container. The option takes a
          function which receives the package set used to build the
          container and returns the list of packages to install. This
          way the container configuration does not rely on a
          nixpkgs instance of its own.
        '';
        default = ps: [ ps.opencode ps.git ];
        defaultText = literalExpression "ps: [ ps.opencode ps.git ]";
        example = literalExpression ''
          ps: [ ps.opencode ps.git ps.ripgrep ]
        '';
      };

      vlan = mkOption {
        type = types.ints.between 1 4094;
        description = ''
          The vlan the container is attached to through its 'eth1'
          interface. The host side of the vlan is a bridge which acts
          as the network gateway of the container (see the
          'nspawn-container' nixos module). Containers that run
          simultaneously must either be attached to different vlans
          or use different node numbers.
        '';
        default = 42;
      };

      node-number = mkOption {
        type = types.ints.between 1 253;
        description = ''
          The number of the container within its vlan, following the
          static ip assignment scheme of the 'nspawn-container'
          module: the container takes the addresses
          '192.168.<vlan>.<node-number>' and
          '2001:db8:<vlan>::<node-number>' while the host-side
          bridge takes '.254' and '::fe'.
        '';
        default = 2;
      };
    };
  };

  perSystem = { pkgs, ... }:
  let
    # One configuration per-module. For each container defined in the
    # configuration, a new module is created by fixing the corresponding
    # configuration context.
    to-opencode-container = name: container:
      {
        imports = [
          (import ./setup.nix { opencode-container-name = name; opencode-container = container; })
        ];
      }
    ;
    imports = lib.attrValues (
      lib.mapAttrs to-opencode-container flake-config.development-tools.opencode-container
    );
  in
  {
    inherit imports;
  };
in
  {
    options = {
      development-tools.opencode-container = mkOption {
        type = types.attrsOf opencode-container-spec;
        description = ''
          The 'opencode-container' development tool provides
          sandboxed systemd-nspawn containers to run the opencode
          programming assistant. Each attribute becomes an individual
          container instance with its own application
          ('devtools/<name>').
        '';
        default = {};
      };
      perSystem = mkPerSystemOption perSystem;
    };
  }
