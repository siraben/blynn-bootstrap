{
  description = "Nix-based bootstrap using blynn-compiler in place of mes (live-bootstrap-style)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        minimalBootstrap = pkgs.minimal-bootstrap;

        blynn-compiler = pkgs.callPackage ./nix/blynn-compiler.nix {
          inherit minimalBootstrap;
          src = ./vendor/blynn-compiler;
        };

        blynn-precisely = pkgs.callPackage ./nix/blynn-precisely.nix {
          inherit blynn-compiler minimalBootstrap;
          src = ./vendor/blynn-compiler/upstream;
        };
      in {
        packages = {
          inherit blynn-compiler blynn-precisely;
          default = blynn-precisely;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            minimalBootstrap.stage0-posix.mescc-tools
            pkgs.coreutils
          ];
          shellHook = ''
            echo "blynn-bootstrap dev shell — sources are in ./vendor/blynn-compiler"
          '';
        };
      });
}
