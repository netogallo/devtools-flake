/** This module accepts a neovim spec alongside the
    coontext and produces an attribute set containing
    the various parts that become part of the flake.
**/
{
  name,
  spec,
  pkgs,
  lib,
  neovim-prelude,
  ...
}:
let
  inherit (lib) mkIf mkOverride;
  config-base = {
    config = {
      _module.args = {
        pkgs = pkgs.extend neovim-prelude.overlay;
        neovim-spec = spec;
      };
      customLuaRC = ''
        vim.notify("LUARC: " .. debug.getinfo(1, "S").source, vim.log.levels.INFO)
        vim.g.mapleader = "${spec.globals.mapleader}"
        vim.notify("Setting leader to '${spec.globals.mapleader}'", vim.log.levels.INFO)
      '';
    };
  };
  config-module =
    lib.evalModules {
      modules = [
        ./configuration-spec.nix
        ./keymaps/keymaps.nix
        ./plugins/telescope.nix
        config-base
      ];
    }
  ;
  neovim = pkgs.wrapNeovim pkgs.neovim-unwrapped {
    configure = config-module.config;
  };
  neovim-qt = pkgs.neovim-qt.override { inherit neovim; };
  app-name = "devtools-neovim-${name}";
  app-name-qt = "devtools-neovim-${name}-qt";
in
  {
    apps = mkIf spec.enable {
      ${app-name} = {
        type = "app";
        program = "${neovim}/bin/nvim";
      };
      ${app-name-qt} = {
        type = "app";
        program = "${neovim-qt}/bin/nvim-qt";
      };
    };
  }

