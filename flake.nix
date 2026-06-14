{
  description = "Zapret - DPI bypass tool for Discord and YouTube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zapret-flowseal = {
      url = "github:Flowseal/zapret-discord-youtube";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      zapret-flowseal,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        zapret = pkgs.callPackage ./nixos/package.nix {
          inherit zapret-flowseal;
        };
        default = zapret;
      });

      nixosModules = {
        zapret-discord-youtube = import ./nixos/module.nix inputs;
        withTestTools =
          { lib, ... }:
          {
            imports = [ self.nixosModules.zapret-discord-youtube ];
            services.zapret-discord-youtube.testTools.enable = lib.mkDefault true;
          };
        default = self.nixosModules.zapret-discord-youtube;
      };
    };
}
