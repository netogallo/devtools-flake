{ ... }:
let
  imports = [
    ./python-lsp-server/config.nix
  ];
in
  {
    inherit imports;
  }
