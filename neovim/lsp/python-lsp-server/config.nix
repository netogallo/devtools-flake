{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption types;
  pylsp = types.submodule {
    plugins = mkOption {
      type = types.attrsOf types.any;
      description = ''
        Configuration of the pylsp plugins that are to be used. This
        will be used to construct the lua configuration object that is
        supplied to python-lsp-server upon startup. Information about this
        can be found at: https://github.com/python-lsp/python-lsp-server/blob/develop/CONFIGURATION.md
      '';
      default = {};
    };
  };
in
  {
    options.lsp.python-lsp-server = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the [python-lsp](https://github.com/python-lsp/python-lsp-server) python language server.
        '';
        default = false;
      };

      flake8 = {
        enable = mkOption {
          type = types.bool;
          description = ''
            Enable static analysis using [flake8](https://flake8.pycqa.org/en/latest/).
          '';
          default = false;
        };
      };

      pylint = {
        enable = mkOption {
          type = types.bool;
          description = ''
            Enable analysis provided by [pylint](https://www.pylint.org/).
          '';
          default = false;
        };
      };
    };

    options.lsp-config.python-lsp-server = {
      settings = {
        inherit pylsp;
      };

      python = {
        packages = mkOption {
          type = types.listOf types.any;
          description = ''
            Packages to be installed alongside the python interpreter
            that will support the lsp services. This is a list of functions
            that will be used alongside the 'python.withPackages'
            function to build the final interpreter with required pacakges
            to provide the lsp services.
          '';
          default = [];
        };

        interpreter = mkOption {
          type = types.package;
          readOnly = true;
          default = pkgs.python3.withPackages(py: lib.concatMap (f: f py) config.python.packages);
        };
      };
    };

    config.lsp-config = with config.lsp.python-lsp-server; {

      settings.pylsp.plugins.flake8 = {
        enabled = flake8.enable;
        executable =
          if flake8.executable == null
          then "${config.lsp-config.python-lsp-server.python.interpreter}/bin/flake8"
          else flake8.executable
        ;
      };
    };
  }
