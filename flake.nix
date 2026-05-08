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

        hccFromBlynn = {
          pname,
          precisely,
          cCompiler,
        }:
          pkgs.callPackage ./nix/hcc-blynn.nix ({
            inherit pname precisely;
            src = ./vendor/hcc;
            blynnSrc = ./vendor/blynn-compiler/upstream;
            shareName = pname;
          } // cCompiler);

        hccCCompilers = {
          stdenv = {
            mkDerivation = pkgs.stdenv.mkDerivation;
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = "$CC -O2 hcc-blynn.c cbits/hcc_runtime.c -o hcc";
            top = 536870912;
            description = "HCC compiled from Blynn output by the normal stdenv C toolchain";
          };

          m2 = {
            mkDerivation = pkgs.stdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcc-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcc
              chmod 555 hcc
            '';
            top = 134217728;
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by stage0 M2-Mesoplanet";
            metaPlatforms = [ "x86_64-linux" ];
          };
        };

        hccMatrix = {
          ghc-ghc = hcc-ghc;

          precisely-ghc-stdenv = hccFromBlynn {
            pname = "hcc-blynn-debug";
            precisely = blynn-precisely-debug-ghc;
            cCompiler = hccCCompilers.stdenv // {
              description = "HCC compiled by the GHC-built Blynn precisely debug compiler and stdenv C";
            };
          };

          precisely-stage0-m2 = hccFromBlynn {
            pname = "hcc-blynn-stage0";
            precisely = blynn-precisely;
            cCompiler = hccCCompilers.m2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
            };
          };

          precisely-stage0-stdenv = hccFromBlynn {
            pname = "hcc-blynn-stage0-stdenv";
            precisely = blynn-precisely;
            cCompiler = hccCCompilers.stdenv // {
              description = "HCC compiled by the stage0-built Blynn precisely and stdenv C";
            };
          };
        };

        hcc-blynn-debug = hccMatrix.precisely-ghc-stdenv;
        hcc-blynn-stage0 = hccMatrix.precisely-stage0-m2;
        hcc-blynn-stage0-stdenv = hccMatrix.precisely-stage0-stdenv;

        tinyccWithHcc = pname: hcc: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          inherit pname hcc minimalBootstrap;
          mesLibc = minimalBootstrap.mes-libc;
          m2libc = ./vendor/blynn-compiler/M2libc;
        };

        tinyccMatrix = {
          hcc-ghc = tinyccWithHcc "tinycc-boot-hcc-ghc" hccMatrix.ghc-ghc;
          hcc-precisely-ghc-stdenv = tinyccWithHcc "tinycc-boot-hcc-blynn-debug" hccMatrix.precisely-ghc-stdenv;
          hcc-precisely-stage0-m2 = tinyccWithHcc "tinycc-boot-hcc" hccMatrix.precisely-stage0-m2;
          hcc-precisely-stage0-stdenv = tinyccWithHcc "tinycc-boot-hcc-stage0-stdenv" hccMatrix.precisely-stage0-stdenv;
        };

        tinycc-boot-hcc = tinyccMatrix.hcc-precisely-stage0-m2;
        tinycc-boot-hcc-ghc = tinyccMatrix.hcc-ghc;
        tinycc-boot-hcc-blynn-debug = tinyccMatrix.hcc-precisely-ghc-stdenv;
        tinycc-boot-hcc-stage0-stdenv = tinyccMatrix.hcc-precisely-stage0-stdenv;

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

        mutable-io-proof = pkgs.callPackage ./nix/mutable-io-proof.nix {
          inherit blynn-precisely-debug-ghc minimalBootstrap;
          src = ./vendor/hcc;
          blynnSrc = ./vendor/blynn-compiler/upstream;
        };
      in {
        packages = {
          inherit blynn-compiler blynn-precisely blynn-precisely-stdenv blynn-precisely-debug-ghc hcc-ghc hcc-ghc-profile hcc-blynn-debug hcc-blynn-stage0 hcc-blynn-stage0-stdenv hcc-m1-smoke hcc-mescc-tests mutable-io-proof tinycc-boot-hcc tinycc-boot-hcc-ghc tinycc-boot-hcc-blynn-debug tinycc-boot-hcc-stage0-stdenv;
          default = blynn-precisely;
        } // pkgs.lib.mapAttrs' (name: value: {
          name = "hcc-matrix-${name}";
          inherit value;
        }) hccMatrix // pkgs.lib.mapAttrs' (name: value: {
          name = "tinycc-matrix-${name}";
          inherit value;
        }) tinyccMatrix;

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
            pkgs.gcc
            blynn-precisely-debug-ghc
            hcc-ghc
            hcc-ghc-profile
            hcc-blynn-debug
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
