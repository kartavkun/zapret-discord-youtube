{
  description = "Zapret - DPI bypass tool for Discord and YouTube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zapret-flowseal = {
      url = "github:Flowseal/zapret-discord-youtube";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, zapret-flowseal }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          zapret = pkgs.callPackage ./nixos/packages/zapret-discord-youtube.nix { inherit zapret-flowseal; };
          default = self.packages.${system}.zapret;
        };
      }
    ) // {
      nixosModules = {
        zapret-discord-youtube = import ./nixos/modules/zapret-discord-youtube.nix;
        default = self.nixosModules.zapret-discord-youtube;
      };
    };
}
