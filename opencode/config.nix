/** This file holds the flake configuration spec for the
*   'opencode' development tool. An opencode configuration defines
*   the packages that make up an opencode setup and exposes:
*   - A runnable flake app ('devtools/<name>') that runs opencode
*     directly on the host (no container).
*   - A NixOS module ('nixos-module') that installs the same
*     packages inside a sandbox container (see
*     'development-tools.sandbox').
*
*   Multiple named opencode configurations can coexist in the same
*   flake; each is exposed as its own app and its own NixOS module.
*   The container wrapping itself is handled by 'sandbox', which
*   imports the module through its 'nixos-modules' option, following
*   the same pattern used by 'llm-agent' to consume 'llm-providers'
*   in 'examples/flakeModule.nix'.
*/
top@{ self, inputs, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption literalExpression;
  inherit (flake-parts-lib) mkPerSystemOption;
  flake-config = config;

  opencode-spec = types.submodule ({ config, ... }:
  let
    # The NixOS module contributed by this opencode instance. It
    # only installs the configured packages; the container host
    # setup (networking, user, bind mounts, ...) is owned by
    # 'sandbox'. The module is pkgs-independent (it receives the
    # container's package set through its own arguments) and is
    # derived solely from 'packages', so it does not introduce a
    # self-reference cycle.
    nixos-module = { pkgs, ... }: {
      environment.systemPackages = config.packages pkgs;
    };
  in
  {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable this opencode configuration. This triggers the
          creation of the application used to run opencode on the
          host. The 'nixos-module' is always available, regardless
          of this flag, so that a sandbox can import it even when
          the host-side app is not built.
        '';
        default = false;
      };

      packages = mkOption {
        type = types.functionTo (types.listOf types.package);
        description = ''
          Packages that make up this opencode configuration. The
          option takes a function which receives the package set
          used to build the app (or the container, when imported as a
          NixOS module) and returns the list of packages to install.
          This way the configuration does not rely on a nixpkgs
          instance of its own.
        '';
        default = ps: [ ps.opencode ps.git ];
        defaultText = literalExpression "ps: [ ps.opencode ps.git ]";
        example = literalExpression ''
          ps: [ ps.opencode ps.git ps.ripgrep ]
        '';
      };

      nixos-module = mkOption {
        type = types.deferredModule;
        readOnly = true;
        description = ''
          A NixOS module that installs this opencode configuration
          inside a sandbox container. The module is computed from
          'packages' and is read-only; pass it to a sandbox's
          'nixos-modules' to run opencode inside the container, e.g.

            development-tools.sandbox.<name>.nixos-modules = [
              development-tools.opencode.<name>.nixos-module
            ];
        '';
      };
    };

    config.nixos-module = nixos-module;
  });

  perSystem = { pkgs, ... }:
  let
    # One module per configured opencode instance.
    to-opencode = name: opencode:
      {
        imports = [
          (import ./setup.nix { opencode-name = name; opencode-config = opencode; })
        ];
      }
    ;
    imports = lib.attrValues (
      lib.mapAttrs to-opencode flake-config.development-tools.opencode
    );
  in
  {
    inherit imports;
  };
in
{
  options = {
    development-tools.opencode = mkOption {
      type = types.attrsOf opencode-spec;
      description = ''
        The 'opencode' development tool installs the 'opencode'
        programming assistant (and any other configured packages).
        Each attribute becomes an individual configuration exposed
        as its own app ('devtools/<name>') that runs opencode
        directly on the host, and contributes a NixOS module
        ('nixos-module') that can be imported by a 'sandbox'
        container to run opencode inside it.
      '';
      default = {};
    };
    perSystem = mkPerSystemOption perSystem;
  };
}
