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
        lib = pkgs.lib;
        hccSrc = ./vendor/hcc;
        blynnSrc = ./vendor/blynn-compiler;
        blynnUpstreamSrc = ./vendor/blynn-compiler/upstream;
        m2libcSrc = ./vendor/blynn-compiler/M2libc;

        minimalBootstrap = pkgs.minimal-bootstrap;

        blynnCompiler = pkgs.callPackage ./nix/blynn-compiler.nix {
          inherit minimalBootstrap;
          src = blynnSrc;
        };

        preciselyM2Stage0 = pkgs.callPackage ./nix/blynn-precisely.nix {
          blynn-compiler = blynnCompiler;
          inherit minimalBootstrap;
          src = blynnUpstreamSrc;
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

        preciselyStdenvHost = preciselyStdenv
          "precisely-stdenv-host"
          preciselyM2Stage0
          "precisely-stdenv-host"
          "Upstream Blynn precisely binary compiled with the normal stdenv C toolchain";

        preciselyGhcDebug = pkgs.callPackage ./nix/blynn-precisely-debug-ghc.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: [
            hpkgs.raw-strings-qq
          ]);
          src = blynnUpstreamSrc;
        };

        hccHostGhcNative = pkgs.callPackage ./nix/hcc-ghc.nix {
          pname = "hcc-host-ghc-native";
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = hccSrc;
        };

        hccProfileHostGhcNative = pkgs.callPackage ./nix/hcc-ghc-profile.nix {
          pname = "hcc-profile-host-ghc-native";
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = hccSrc;
        };

        hccFromPrecisely = {
          pname,
          precisely,
          cBackend,
        }:
          pkgs.callPackage ./nix/hcc-blynn.nix ({
            inherit pname precisely;
            src = hccSrc;
            blynnSrc = blynnUpstreamSrc;
            shareName = pname;
          } // cBackend);

        hccCBackends = {
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

        # Bootstrap triple: <precisely-cc>-<hcc-hs>-<hcc-cc>.
        # - precisely-cc: how the precisely binary was compiled.
        # - hcc-hs: the Haskell compiler used to compile HCC's Haskell source.
        # - hcc-cc: how HCC's generated/native code becomes an executable.
        #
        # `host-ghc-native` is the dev escape hatch: no precisely stage is used,
        # and host GHC compiles HCC directly.
        hccByTriple = {
          host-ghc-native = hccHostGhcNative;

          ghc-precisely-stdenv = hccFromPrecisely {
            pname = "hcc-ghc-precisely-stdenv";
            precisely = preciselyGhcDebug;
            cBackend = hccCBackends.stdenv // {
              description = "HCC compiled by the GHC-built Blynn precisely debug compiler and stdenv C";
            };
          };

          m2-precisely-m2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-m2";
            precisely = preciselyM2Stage0;
            cBackend = hccCBackends.m2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
            };
          };

          m2-precisely-stdenv = hccFromPrecisely {
            pname = "hcc-m2-precisely-stdenv";
            precisely = preciselyM2Stage0;
            cBackend = hccCBackends.stdenv // {
              description = "HCC compiled by the stage0-built Blynn precisely and stdenv C";
            };
          };
        };

        tinyccFromHcc = pname: hcc: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          inherit pname hcc minimalBootstrap;
          mesLibc = minimalBootstrap.mes-libc;
          m2libc = m2libcSrc;
        };

        tinyccByTriple = {
          host-ghc-native = tinyccFromHcc "tinycc-boot-hcc-host-ghc-native" hccByTriple.host-ghc-native;
          ghc-precisely-stdenv = tinyccFromHcc "tinycc-boot-hcc-ghc-precisely-stdenv" hccByTriple.ghc-precisely-stdenv;
          m2-precisely-m2 = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-m2" hccByTriple.m2-precisely-m2;
          m2-precisely-stdenv = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-stdenv" hccByTriple.m2-precisely-stdenv;
        };

        hcc-m1-smoke = pkgs.callPackage ./nix/hcc-m1-smoke.nix {
          hcc = hccByTriple.m2-precisely-m2;
          inherit minimalBootstrap;
          m2libc = m2libcSrc;
        };

        hcc-mescc-tests = pkgs.callPackage ./nix/hcc-mescc-tests.nix {
          hcc = hccByTriple.m2-precisely-m2;
          inherit minimalBootstrap;
          m2libc = m2libcSrc;
          mesTests = ./vendor/mes-tests;
        };

        mutable-io-proof = pkgs.callPackage ./nix/mutable-io-proof.nix {
          blynn-precisely-debug-ghc = preciselyGhcDebug;
          inherit minimalBootstrap;
          src = hccSrc;
          blynnSrc = blynnUpstreamSrc;
        };
      in {
        packages = {
          blynn-compiler = blynnCompiler;
          precisely-m2-stage0 = preciselyM2Stage0;
          precisely-stdenv-host = preciselyStdenvHost;
          precisely-ghc-debug = preciselyGhcDebug;
          hcc-profile-host-ghc-native = hccProfileHostGhcNative;
          inherit hcc-m1-smoke hcc-mescc-tests mutable-io-proof;
          default = preciselyM2Stage0;
        } // lib.mapAttrs' (name: value: {
          name = "hcc-${name}";
          inherit value;
        }) hccByTriple // lib.mapAttrs' (name: value: {
          name = "tinycc-boot-hcc-${name}";
          inherit value;
        }) tinyccByTriple;

        apps.blynn-precisely-stdenv = {
          type = "app";
          program = "${preciselyStdenvHost}/bin/precisely_up";
        };

        apps.blynn-precisely-debug-ghc = {
          type = "app";
          program = "${preciselyGhcDebug}/bin/precisely_up";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            minimalBootstrap.stage0-posix.mescc-tools
            pkgs.coreutils
            pkgs.gcc
            preciselyGhcDebug
            hccByTriple.host-ghc-native
            hccProfileHostGhcNative
            hccByTriple.ghc-precisely-stdenv
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
