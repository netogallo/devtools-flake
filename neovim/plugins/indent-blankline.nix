{ lib, pkgs, neovim-spec, ... }:
let
  inherit (pkgs) nix-lua;
  inherit (lib) mkIf;
  inherit (neovim-spec.plugins) indent-blankline;
  enable = indent-blankline.enable;
  setup = {
    indent = {
      highlight = lib.attrNames indent-blankline.colors;
    };
  };
  as-set-hl-expr = name: color:
    ''vim.api.nvim_set_hl(0, "${name}", { fg = "${color}" })''
  ;
  highlight-setup =
    lib.concatStringsSep ";" (
      lib.attrValues (
        lib.mapAttrs as-set-hl-expr indent-blankline.colors
      )
    )
  ;
in
  {
    config = mkIf enable {
      packages.indent-blankline-plugin = {
        start = with pkgs.vimPlugins; [
          indent-blankline-nvim
        ];
      };
      customLuaRC = ''
        do
          local hooks = require("ibl.hooks")
          hooks.register(hooks.type.HIGHLIGHT_SETUP, function() ${highlight-setup} end)
          require("ibl").setup(${nix-lua.as-expr setup})
        end
      '';
    };
  }
