{
  description = "Nix flake for OpenCode CLI - AI coding assistant in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      overlay = final: prev: {
        opencode-nix = final.callPackage ./package.nix { };
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.opencode-nix;
          opencode = pkgs.opencode-nix;
        };

        apps = {
          default = {
            type = "app";
            program = "${pkgs.opencode-nix}/bin/opencode";
            meta.description = "AI coding assistant in your terminal";
          };
          opencode = {
            type = "app";
            program = "${pkgs.opencode-nix}/bin/opencode";
            meta.description = "AI coding assistant in your terminal";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            nix-prefetch
            cachix
            gh
            jq
          ];
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
