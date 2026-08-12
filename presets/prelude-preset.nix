{ config, lib, ... }:
let
  inherit (lib) mkOption mkIf types;
  neovim-type = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable a named neovim editor and apply the
          "prelude" preset. This preset contains a
          Baseline setup configured for a wide range
          of generic purposes. Specifically, it
          applies the following:
          * Enable the Telescope plugin.
          * Enable the 'indent-blankline' plugin
            * Configure the plugin with the default indentation colors.
        '';
      };
    };
  };
  ibl-colors = [
    { name = "RainbowRed"; fg = "#E06C75"; }
    { name = "RainbowYellow"; fg = "#E5C07B"; }
    { name = "RainbowBlue"; fg = "#61AFEF"; } 
    { name = "RainbowOrange"; fg = "#D19A66"; }
    { name = "RainbowGreen"; fg = "#98C379"; }
    { name = "RainbowViolet"; fg = "#C678DD"; }
    { name = "RainbowCyan"; fg = "#56B6C2"; }
  ];
  neovim-configs = config.development-tools.presets.prelude.neovim;
  to-neovim-config = name: neovim-value:
  {
    enable = true;
    plugins = {
      telescope.enable = true;
      indent-blankline = {
        enable = true;
        colors = ibl-colors;
      };
    };
    keymaps = with config.development-tools.neovim.${name}.commands.telescope; [
      {
        mode = "n";
        keymap = "<leader>ff";
        action = find-files;
        description = "Find files with telescope";
      }
      {
        mode = "n";
        keymap = "<leader>fg";
        action = live-grep;
        description = "Live grep search using telescope";
      }
    ];
  };
in
  {
    options = {
      development-tools.presets.prelude = {
        neovim = mkOption {
          type = types.attrsOf neovim-type;
        };
      };
    };

    config =  {
      development-tools.neovim = lib.mapAttrs to-neovim-config neovim-configs;
    };
  }
