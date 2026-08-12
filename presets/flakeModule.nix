/** Presets are sets of pre-selected options tailored with
*   a specific purpose in mind. You can think of them as configuration
*   templates.
*   If you don't have strong preferences over the configuration of a
*   deveopment tool, you can apply presets which will give you a
*   good selection of defaults (rather than manually specifying all options)
*/
{ ... }:
let
  imports = [ ./prelude-preset.nix ];
in
  { inherit imports; }
