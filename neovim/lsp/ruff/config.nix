{ lib, config, ... }:
let
  inherit (lib) mkOption mkIf types;
in
  {
    options.lsp.ruff = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the [https://docs.astral.sh/ruff/](ruff) python language linter.
        '';
      };
    };
  }
