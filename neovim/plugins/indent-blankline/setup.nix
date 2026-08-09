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
    let
      colors =
        if lib.isString indent-blankline.colors
        then presets.${indent-blankline.colors}
        else indent-blankline.colors
      ;
      statements =
        lib.concatStringsSep ";" (
          lib.map as-set-hl-expr colors
        )
      ;
      colors-rc-setup = ''
        do
          local hooks = require("ibl.hooks")
          hooks.register(hooks.type.HIGHLIGHT_SETUP, function() ${statements} end)
        end
        ''
      ;
    in
      if indent-blankline.colors == "none"
      then ""
      else colors-rc-setup
  ;
in
  {
    config = mkIf enable {
      packages.indent-blankline-plugin = {
        start = with pkgs.vimPlugins; [
          indent-blankline-nvim
        ];
      };
      customLuaRC = lib.concatStringsSep "\n" [
        ''require("ibl").setup(${nix-lua.as-expr setup})''
        highlight-setup
      ];
    };
  }
