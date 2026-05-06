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

        hcc-ghc = pkgs.callPackage ./nix/hcc-ghc.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = ./vendor/hcc;
        };

        tinycc-boot-hcc = pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          hcc = hcc-ghc;
        };
      in {
        packages = {
          inherit blynn-compiler blynn-precisely hcc-ghc tinycc-boot-hcc;
          default = blynn-precisely;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            minimalBootstrap.stage0-posix.mescc-tools
            pkgs.coreutils
            hcc-ghc
            (pkgs.haskellPackages.ghcWithPackages (hpkgs: [
              hpkgs.raw-strings-qq
            ]))
          ];
          shellHook = ''
            echo "blynn-bootstrap dev shell — sources are in ./vendor/blynn-compiler"
          '';
        };
      });
}
