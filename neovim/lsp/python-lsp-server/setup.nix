/** This module applies the python-lsp-server configuration to the
 *  neovim startup. It takes care of installing the necessary packages
 *  from nixpkgs, depending on how the lsp is configured.
 */
{ lib, pkgs, neovim-spec, config, ... }:
let
  inherit (pkgs) nix-lua python3;
  inherit (lib) mkIf;
  inherit (neovim-spec.lsp) python-lsp-server;
  enable = python-lsp-server.enable;

  flake8-config = with python-lsp-server; {
    inherit (flake8.enable);
    executable =
      if flake8.exacutable != null
      then flake8.executable
      else "${python-lsp}/bin/flake8"
    ;
    packages = py:
      if flake8.enable && flake8.executable == null
      then [ py.flake8 ]
      else []
    ;
  };

  pylint-config = with python-lsp-server; {
    inherit (pylint) enable;
    executable =
      if pylint.executable != null
      then pylint.executable
      else "${python-lsp}/bin/pylint"
    ;
    packages = py:
      if pylint.enable && pylint.executable == null
      then [ py.pylint ]
      else []
    ;
  };

  python-lsp = python3.withPackages (
    py: [ py.python-lsp-server ]
      ++ flake8-config.packages py
      ++ pylint-config.packages py
  );
  setup = {
    cmd = [ "${python-lsp}/bin/pylsp" ];
    filetypes = [ "python" ];
    root_markers = [
      "pyproject.toml"
      "setup.py"
      "setup.cfg"
      "requirements.txt"
      "Pipfile"
      ".git"
    ];
    inherit (config.lsp-config.python-lsp-server) settings;
  };
in
  {
    config = mkIf enable {
      customLuaRC = ''
        vim.lsp.config['python_lsp_server'] = ${nix-lua.as-expr setup}
        vim.lsp.enable('python_lsp_server')
        vim.lsp.log.set_level 'trace'
      '';
    };
  }

