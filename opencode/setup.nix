{ nixpkgs, pkgs, lib, ... }:
let
  nixos = nixpkgs.lib.nixosSystem {
    modules = [
      {
        imports = [
          "${nixpkgs}/nixos/modules/virtualisation/nspawn-container/default.nix"
          "${nixpkgs}/nixos/modules/virtualisation/guest-networking-options.nix"
        ];

        config = {
          nixpkgs.hostPlatform = pkgs.system;

          environment.systemPackages = [
            pkgs.opencode
            pkgs.git
          ];

          users.users.nixos = {
            group = "users";
            extraGroups = [ "wheel" ];
            isNormalUser = true;
            hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
          };

          users.groups.nixos = { };
          services.getty.autologinUser = "nixos";

          virtualisation.systemd-nspawn.options = [
            "--bind=.:/home/nixos/workspace"
          ];

          virtualisation.interfaces.eth1 = {
            vlan = 42;
            assignIP = false;
          };

          networking.useHostResolvConf = false;

          systemd.network = {
            enable = true;

            networks.eth1 = {
              enable = true;
              matchConfig = {
                Name = "eth1";
              };
              addresses = [
                {
                  Address = "192.168.42.2/24";
                }
              ];
              routes = [
                {
                  Gateway = "192.168.42.254";
                }
              ];
            };
          };
        };
      }
    ];
  };
in
  {
    config.apps.opencode-container = {
      type = "app";
      program = lib.getExe nixos.config.system.build.nspawn;
    };
  }
