{ lib, ... }:
let
  presets = {
    ibl-default = [
      { name = "RainbowRed"; fg = "#E06C75"; }
      { name = "RainbowYellow"; fg = "#E5C07B"; }
      { name = "RainbowBlue"; fg = "#61AFEF"; }
      { name = "RainbowOrange"; fg = "#D19A66"; }
      { name = "RainbowGreen"; fg = "#98C379"; }
      { name = "RainbowViolet"; fg = "#C678DD"; }
      { name = "RainbowCyan"; fg = "#56B6C2"; }
    ];
    none = null;
  };
in
  {
    inherit presets;
  }
