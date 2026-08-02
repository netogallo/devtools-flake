{ lib, ... }:
let
  modes = ["n" "i" "v" "x" "s" "o" "t" "c" "l"];
in
  {
    inherit modes;
  }
