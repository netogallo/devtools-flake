{ config, lib, ... }:
let
  ibl-colors = [
    { name = "RainbowRed"; fg = "#E06C75"; }
    { name = "RainbowYellow"; fg ="#E5C07B"; }
    { name = "RainbowBlue"; fg = "#61AFEF"; }
  ];
in
  {
    # Enable neovim using the 'prelude' preset.
    # Use the name 'prelude-nvim' for this setup
    config.development-tools.presets.prelude.neovim.prelude-nvim.enable = true;

    # Customize the telescope exclusions of the
    # 'prelude-nvim' setup
    config.development-tools.neovim.prelude-nvim = {
      plugins.telescope.globals.file-ignore-patterns = ["flake.lock"];
    };


    #config.development-tools.llm-netogallo.prelude-llm = {
    #  enable = true;
    #  task-branch-prefix = "feature";
    #};

    # Two opencode configurations. Each is exposed as its own app
    # ('devtools/opencode' and 'devtools/opencode-2') that runs
    # opencode directly on the host, and contributes a NixOS module
    # that can be imported by a sandbox container (see below).
    config.development-tools.opencode.opencode.enable = true;
    config.development-tools.opencode.opencode-2.enable = true;

    # A sandbox container running the 'opencode' configuration. The
    # sandbox owns the container host setup (networking, user, bind
    # mounts); the opencode 'nixos-module' installs opencode and git
    # inside it. The resulting app is 'devtools/opencode-sandbox'.
    config.development-tools.sandbox.opencode-sandbox = {
      enable = true;
      nixos-modules = [
        config.development-tools.opencode.opencode.nixos-module
      ];
    };

    config.development-tools.neovim.neovim-example1 = {
      enable = true;
      plugins.telescope = {
        enable = true;
        globals.file-ignore-patterns = ["flake.lock"];
      };
      plugins.indent-blankline = {
        enable = true;
        colors = ibl-colors;
      };
      keymaps = with config.development-tools.neovim.neovim-example1.commands.telescope; [
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

    config.development-tools.lite-llm.prelude-lite-llm = {
      enable = true;
      users = {
        alice = {};
      };
      models = {
        "master" = {
          model = "openrouter/mistralai/devstral-2512";
        };
      };
    };

    config.development-tools.llm-agent.prelude-llm-agent = {
      enable = true;
      provider = with config.development-tools.llm-providers.prelude-lite-llm; {
        endpoint = endpoint;
        user = users.alice;
        models = {
          main = models.master;
        };
      };
      git = {
        enable = true;
        authorized-keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvWsBQT8JJe7UckvF2+zdsVbgtof2jhenQqQgdC6oOS neto@nixos"
        ];
      };
    };
  }
