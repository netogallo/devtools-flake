{ pkgs, lib, ... }:
let
  /** Encode the given nix value into a single-line lua expression which creates
  *   an equivalent lua value.
  */
  as-expr = nix-value:
  let
    json-value =
      pkgs.writeText
      "value"
      ''${lib.toJSON nix-value}''
    ;
  in
    ''(function() local file=io.open("${json-value}");local result = vim.json.decode(file:read("*a"));file.close();return result end)()''
  ;
in
  { inherit as-expr; }
