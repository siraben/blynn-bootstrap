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

        blynn-compiler = pkgs.callPackage ./nix/blynn-compiler.nix {
          src = ./vendor/blynn-compiler;
        };

        blynn-precisely = pkgs.callPackage ./nix/blynn-precisely.nix {
          inherit blynn-compiler;
          src = ./vendor/blynn-compiler/upstream;
        };
      in {
        packages = {
          inherit blynn-compiler blynn-precisely;
          default = blynn-precisely;
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.clang pkgs.gnumake pkgs.coreutils ];
          shellHook = ''
            echo "blynn-bootstrap dev shell — sources are in ./vendor/blynn-compiler"
          '';
        };
      });
}
