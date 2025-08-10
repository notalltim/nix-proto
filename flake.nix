{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nix-std.url = "github:chessai/nix-std";
    nix-filter.url = "github:numtide/nix-filter";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      flake =
        let
          lib = (import ./.) {
            nix_lib = inputs.nixpkgs.lib;
            std = inputs.nix-std.lib;
            filter = inputs.nix-filter.lib;
          };
        in
        {
          inherit lib;
          inherit (lib) mkProtoDerivation generateOverlays';
          overlays = import ./test/overlays.nix lib;
        };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        { pkgs, system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = builtins.attrValues self.overlays;
          };
          legacyPackages = pkgs;
          treefmt.programs = {
            nixfmt.enable = true;
            yamlfmt = {
              enable = true;
              settings = {
                formatter.trim_trailing_whitespace = true;
              };
            };
            protolint.enable = true;
          };
        };
    };
}
