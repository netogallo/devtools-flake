/** This module is responsible suppyling the 'indent-blankline' configuration
* that gets passed to the `wrapNeovim` function. It's responsibility is to
* convert the options selected during the config stage (defined in `./config.nix`
* and translate them into a vim plugin package and the respective configuration
* items that get added to the 'luaRC' file.
*/
{ lib, pkgs, neovim-spec, ... }:
let
  inherit (pkgs) nix-lua;
  inherit (lib) mkIf;
  inherit (pkgs.callPackage ./prelude.nix {}) presets;
  inherit (neovim-spec.plugins) indent-blankline;
  enable = indent-blankline.enable;
  colors =
    if lib.isString indent-blankline.colors
    then presets.${indent-blankline.colors}
    else indent-blankline.colors
  ;
  plugin-setup =
  let
    setup = {} //
      (
        if colors == null
        then {}
        else { indent.highlight = lib.map (c: c.name) colors; }
      )
    ;
  in
    [ ''require("ibl").setup(${nix-lua.as-expr setup})'' ]
  ;

  as-set-hl-expr = { name, fg }:
    ''vim.api.nvim_set_hl(0, "${name}", { fg = "${fg}" })''
  ;
  highlight-hook-setup =
    let
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
      # Null value indicates that no colors have been defined
      # in that case, no extra config is generated in the
      # lua RC file.
      if colors == null
      then []
      else [colors-rc-setup]
  ;
in
  {
    config = mkIf enable {
      packages.indent-blankline-plugin = {
        start = with pkgs.vimPlugins; [
          indent-blankline-nvim
        ];
      };
      customLuaRC = lib.concatStringsSep "\n" (
        lib.concatLists [
          highlight-hook-setup
          plugin-setup
        ]
      );
    };
  }
