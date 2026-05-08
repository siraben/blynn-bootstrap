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

        preciselyStdenv = pname: precisely: shareName: description:
        pkgs.stdenv.mkDerivation {
          inherit pname;
          version = "0-unstable-2026-05-06";

          dontUnpack = true;

          buildPhase = ''
            runHook preBuild
            $CC -O2 ${precisely}/share/blynn-precisely/precisely_up.c -o precisely_up
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 precisely_up $out/bin/precisely_up
            install -Dm644 ${precisely}/share/blynn-precisely/precisely_up.c \
              $out/share/${shareName}/precisely_up.c
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            inherit description;
            homepage = "https://github.com/blynn/compiler";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
          };
        };

        blynn-precisely-stdenv = preciselyStdenv
          "blynn-precisely-stdenv"
          blynn-precisely
          "blynn-precisely-stdenv"
          "Upstream Blynn precisely binary compiled with the normal stdenv C toolchain";

        blynn-precisely-debug-ghc = pkgs.callPackage ./nix/blynn-precisely-debug-ghc.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: [
            hpkgs.raw-strings-qq
          ]);
          src = ./vendor/blynn-compiler/upstream;
        };

        hcc-ghc = pkgs.callPackage ./nix/hcc-ghc.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = ./vendor/hcc;
        };

        hcc-ghc-profile = pkgs.callPackage ./nix/hcc-ghc-profile.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = ./vendor/hcc;
        };

        hcc-blynn-debug = pkgs.callPackage ./nix/hcc-blynn-debug.nix {
          inherit blynn-precisely-debug-ghc;
          src = ./vendor/hcc;
          blynnSrc = ./vendor/blynn-compiler/upstream;
        };

        hcc-blynn-stage0 = pkgs.callPackage ./nix/hcc-blynn-stage0.nix {
          inherit blynn-precisely minimalBootstrap;
          src = ./vendor/hcc;
          blynnSrc = ./vendor/blynn-compiler/upstream;
        };

        tinycc-boot-hcc = pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          hcc = hcc-blynn-stage0;
          inherit minimalBootstrap;
          mesLibc = minimalBootstrap.mes-libc;
          m2libc = ./vendor/blynn-compiler/M2libc;
        };

        hcc-m1-smoke = pkgs.callPackage ./nix/hcc-m1-smoke.nix {
          hcc = hcc-blynn-stage0;
          inherit minimalBootstrap;
          m2libc = ./vendor/blynn-compiler/M2libc;
        };

        hcc-mescc-tests = pkgs.callPackage ./nix/hcc-mescc-tests.nix {
          hcc = hcc-blynn-stage0;
          inherit minimalBootstrap;
          m2libc = ./vendor/blynn-compiler/M2libc;
          mesTests = ./vendor/mes-tests;
        };
      in {
        packages = {
          inherit blynn-compiler blynn-precisely blynn-precisely-stdenv blynn-precisely-debug-ghc hcc-ghc hcc-ghc-profile hcc-blynn-debug hcc-blynn-stage0 hcc-m1-smoke hcc-mescc-tests tinycc-boot-hcc;
          default = blynn-precisely;
        };

        apps.blynn-precisely-stdenv = {
          type = "app";
          program = "${blynn-precisely-stdenv}/bin/precisely_up";
        };

        apps.blynn-precisely-debug-ghc = {
          type = "app";
          program = "${blynn-precisely-debug-ghc}/bin/precisely_up";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            minimalBootstrap.stage0-posix.mescc-tools
            pkgs.coreutils
            hcc-ghc
            hcc-ghc-profile
            hcc-blynn-debug
            hcc-blynn-stage0
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
