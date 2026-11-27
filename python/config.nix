/** This file holds the flake configuration spec for the
*   'python' development tool. A python configuration defines a
*   python interpreter bundled with a set of packages and exposes:
*   - A runnable flake app ('devtools/<name>') that dispatches to the
*     interpreter (mode 'python'), pip (mode 'pip') or activates and
*     deactivates the environment in the current shell (modes
*     'activate'/'deactivate').
*   - A NixOS module ('nixos-module') that installs the python
*     interpreter and the applications exposed by the bundled
*     python modules inside a sandbox container (see
*     'development-tools.sandbox').
*
*   Multiple named python configurations can coexist in the same
*   flake; each is exposed as its own app and its own NixOS module,
*   following the same style used by 'opencode' (see
*   opencode/config.nix).
*
*   The 'packages' option is a function from the python package set
*   to a list of packages, directly compatible with
*   'python.withPackages'. Multiple declarations of 'packages' are
*   merged by calling every declared function with the package set
*   and concatenating the resulting lists, so 'mkMerge' can be used
*   to compose environments incrementally.
*/
top@{ self, inputs, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption literalExpression;
  inherit (flake-parts-lib) mkPerSystemOption;
  flake-config = config;

  # A function from the python package set to a list of packages,
  # merged by calling every declared function and concatenating the
  # results. The merged value is still a function, so it can be
  # passed straight to 'python.withPackages' regardless of how many
  # 'packages' declarations were merged into the option.
  package-function-type = types.functionTo (types.listOf types.package) // {
    merge = loc: defs: py: lib.concatMap (def: def.value py) defs;
  };

  python-spec = types.submodule ({ config, name, ... }:
  let
    # The NixOS module contributed by this python instance. It
    # installs the configured interpreter (with its bundled
    # packages, which already expose every binary shipped by the
    # python modules) and the 'devtools/<name>' launcher itself, so
    # both the interpreter and the application modes are available
    # inside a sandbox container. The module is pkgs-independent (it
    # receives the container's package set through its own arguments)
    # and is derived solely from the readonly options below, so it
    # does not introduce a self-reference cycle.
    nixos-module = { pkgs, ... }: {
      environment.systemPackages =
        [ (config.python-instance pkgs) ] ++
        [ (config.application pkgs) ];
    };

    # A shell-safe identifier used for the PATH backup variable
    # emitted by the 'activate'/'deactivate' modes.
    backup-var = "_DEVTOOLS_PYTHON_${
      lib.strings.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)
    }_PATH";
  in
  {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable this python configuration. This triggers the
          creation of the application used to dispatch to the
          interpreter, pip and the activate/deactivate shell
          helpers. The 'nixos-module' is always available,
          regardless of this flag, so that a sandbox can import it
          even when the host-side app is not built.
        '';
        default = false;
      };

      packages = mkOption {
        type = package-function-type;
        description = ''
          Packages to bundle with this python environment. The
          option takes a function which receives the python package
          set used to build the app (or the container, when imported
          as a NixOS module) and returns the list of packages to
          install. The function is passed straight to
          'python.withPackages'.

          Multiple declarations of this option are merged by
          calling every declared function with the package set and
          concatenating the resulting lists, so 'mkMerge' can be
          used to compose environments incrementally.
        '';
        default = py: [ ];
        defaultText = literalExpression "py: [ ]";
        example = literalExpression ''
          py: with py; [ py.ipython py.requests ]
        '';
      };

      python-instance = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        description = ''
          The python interpreter with the configured 'packages'
          bundled through 'withPackages'. This is a function from the
          package set to the resulting derivation, so the same
          configuration can be built against both the host's and a
          container's package set.
        '';
      };

      application = mkOption {
        type = types.functionTo types.package;
        readOnly = true;
        description = ''
          The 'devtools/<name>' launcher exposed by this python
          configuration, as a function from the package set to the
          resulting derivation. The launcher dispatches to the
          interpreter (mode 'python'), pip (mode 'pip') or emits the
          shell snippets that add or remove the environment from
          PATH (modes 'activate'/'deactivate').
        '';
      };

      nixos-module = mkOption {
        type = types.deferredModule;
        readOnly = true;
        description = ''
          A NixOS module that installs this python configuration
          inside a sandbox container. The module is computed from
          the readonly options above and is read-only; pass it to a
          sandbox's 'nixos-modules' to run the environment inside the
          container, e.g.

            development-tools.sandbox.<name>.nixos-modules = [
              development-tools.python.<name>.nixos-module
            ];
        '';
      };
    };

    config = {
      # The interpreter bundled with the configured packages. Built
      # against whatever package set it is eventually evaluated with,
      # so the same configuration works on the host and inside a
      # container.
      python-instance = pkgs:
        pkgs.python3.withPackages (config.packages);

      # The 'devtools/<name>' launcher. 'python' and 'pip' forward to
      # the interpreter; 'activate' and 'deactivate' are meant to be
      # evaluated by the shell
      # ('eval "$(devtools/<name> activate)"') so they emit the
      # relevant environment mutations instead of performing them
      # directly.
      #
      # The script body is kept in a separate file ('launch.sh') and
      # instantiated with the 'template' helper from 'tikal-prelude',
      # following the same pattern used by the 'sandbox' launcher (see
      # sandbox/setup.nix and sandbox/launch.sh). Only the
      # placeholders listed below are substituted; the script uses
      # shell '$var'/'$0'/'$(...)'  syntax for non-template variables
      # and '''${...}' to emit literal '${...}' in the output (for
      # the shell snippets produced by 'activate'/'deactivate').
      #
      # The mode ('python'/'pip'/'activate'/'deactivate') is parsed
      # with 'docopts' from the usage text embedded in the script;
      # only the first argument is passed to 'docopts' so the
      # remaining arguments are forwarded verbatim to the selected
      # mode instead of being interpreted as 'docopts' options.
      #
      # A 'writeScript' is used (instead of 'writeShellApplication')
      # so the derivation's out path is the executable itself: this
      # makes 'app.program = "${application ...}"' a valid
      # single-path placeholder, matching the pattern used by the
      # 'opencode' app.
      application = pkgs:
        let
          inherit (pkgs.tikal.prelude.template) template;
          python-env = config.python-instance pkgs;
        in
          pkgs.writeScript "devtools-${name}" (template ./launch.sh {
            inherit name;
            bash = pkgs.bash;
            docopts = pkgs.docopts;
            python-env = python-env;
            backup-var = backup-var;
          });

      nixos-module = nixos-module;
    };
  });

  perSystem = { pkgs, ... }:
  let
    # One module per configured python instance.
    to-python = name: python:
      {
        imports = [
          (import ./setup.nix { python-name = name; python-config = python; })
        ];
      }
    ;
    imports = lib.attrValues (
      lib.mapAttrs to-python flake-config.development-tools.python
    );
  in
  {
    inherit imports;
  };
in
{
  options = {
    development-tools.python = mkOption {
      type = types.attrsOf python-spec;
      description = ''
        The 'python' development tool configures python interpreters
        bundled with a set of packages. Each attribute becomes an
        individual configuration exposed as its own app
        ('devtools/<name>') that dispatches to the interpreter, pip
        and the activate/deactivate shell helpers, and contributes a
        NixOS module ('nixos-module') that can be imported by a
        'sandbox' container to install the environment inside it.
      '';
      default = { };
    };
    perSystem = mkPerSystemOption perSystem;
  };
}
