{ config, lib, callPackage, neovim-spec, ... }:
let
  inherit (lib) mkOption types;
  inherit (callPackage ./prelude.nix {}) modes;

  /** The "keymap" config allows specifying modes
  *   as strings or lists for convenience. Furhtermore,
  *   modes specified as list can have any order. To
  *   merge all keymaps into a single command, one must
  *   group all specs with equivalent mode definition so
  *   they can be registered as a single function.
  */
  normalize-mode = keymaps:
  let
    mode =
      lib.naturalSort (
        if lib.isString keymaps.mode
        then [ keymaps.mode ]
        else mode
      )
    ;
  in
    keymaps // { inherit mode; }
  ;
  by-mode = f: keymaps:
    lib.attrValues (
      lib.mapAttrs f (
          lib.groupBy (s: s.mode) (
            lib.map normalize-mode keymaps
        )
      )
    )
  ;
  by-keymap = f: keymaps:
    lib.attrValues (
      lib.mapAttrs f (
        lib.groupBy (s: s.keymap) keymaps
      );
    )
  ;
  keymap-lua = { mode, keymap }: specs:
  let
    modes-str = lib.concatStringsSep "," (lib.map (m: ''"${m}"'') mode);
    commands = lib.concatStringsSep "\n" (lib.map (s.action) specs);
    descriptions = lib.concatStringsSep ". " (lib.map (s.desc) specs);
  in
    ''
    vim.keymap.set(
      { ${modes-str} },
      "${keymap}",
      function ()
        ${commands}
      end,
      { desc = "${descriptions}" }
    )
    ''
  ;
  keymaps-lua =
  let
    by-keymap-fn = mode: keymap: specs: keymap-lua { inherit mode keymap; } specs;
    by-mode-fn = mode: keymaps: lib.concat (by-keymap (by-keymap-fn mode) keymaps);
  in
    lib.concatStringsSep "\n" (by-mode by-mode-fn neovim-spec.keymaps)
  ;
  msg = lib.toString (lib.length neovim-spec.keymaps);
  customLuaRC = ''
    vim.notify("Keymaps defined: ${msg}", vim.log.levels.INFO)
    ${keymaps-lua}
  '';
in
  { config = { inherit customLuaRC; }; }

