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

        preciselyGcc = pname: precisely: shareName: description:
        pkgs.stdenv.mkDerivation {
          inherit pname;
          version = "0-unstable-2026-05-06";

          dontUnpack = true;

          buildPhase = ''
            runHook preBuild
            sed -E 's/enum\{TOP=[0-9]+\};/enum{TOP=33554432};/' \
              ${precisely}/share/blynn-precisely/precisely_up.c > precisely_up.c
            $CC -O2 precisely_up.c -o precisely_up
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 precisely_up $out/bin/precisely_up
            install -Dm644 precisely_up.c $out/share/${shareName}/precisely_up.c
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            inherit description;
            homepage = "https://github.com/blynn/compiler";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
          };
        };

        preciselyGccHost = preciselyGcc
          "precisely-gcc-host"
          preciselyM2Stage0
          "precisely-gcc-host"
          "Upstream Blynn precisely binary compiled with the normal GCC C toolchain";

        preciselyGhcDebug = pkgs.callPackage ./nix/blynn-precisely-debug-ghc.nix {
          ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: [
            hpkgs.raw-strings-qq
          ]);
          src = blynnUpstreamSrc;
        };

        m2MesoplanetGcc = pkgs.callPackage ./nix/gcc-m2-mesoplanet.nix {
          inherit minimalBootstrap;
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
          gcc = {
            mkDerivation = pkgs.stdenv.mkDerivation;
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = ''
              echo "hcc-blynn: gcc cc hcpp-blynn.c -> hcpp"
              $CC -O2 hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: gcc cc hcc1-blynn.c -> hcc1"
              $CC -O2 hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
            '';
            top = 536870912;
            hcppTop = 134217728;
            hcc1Top = 536870912;
            description = "HCC compiled from Blynn output by the normal GCC C toolchain";
          };

          tcc = tcc: {
            mkDerivation = pkgs.stdenvNoCC.mkDerivation;
            nativeBuildInputs = [ tcc ];
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = ''
              echo "hcc-blynn: tcc hcpp-blynn.c -> hcpp"
              ${tcc}/bin/tcc -B ${tcc}/lib -I ${tcc}/include hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: tcc hcc1-blynn.c -> hcc1"
              ${tcc}/bin/tcc -B ${tcc}/lib -I ${tcc}/include hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
            '';
            top = 536870912;
            hcppTop = 134217728;
            hcc1Top = 536870912;
            description = "HCC compiled from Blynn output by HCC-built TinyCC";
          };

          m2 = {
            mkDerivation = pkgs.stdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              echo "hcc-blynn: M2-Mesoplanet hcpp-blynn.c -> hcpp"
              M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcpp-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcpp
              chmod 555 hcpp
              echo "hcc-blynn: M2-Mesoplanet hcc1-blynn.c -> hcc1"
              M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcc1-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcc1
              chmod 555 hcc1
            '';
            top = 134217728;
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by stage0 M2-Mesoplanet";
            metaPlatforms = [ "x86_64-linux" ];
          };

          gccm2 = {
            mkDerivation = pkgs.stdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              m2MesoplanetGcc
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              gcc_m2_env="env -i PATH=${minimalBootstrap.stage0-posix.mescc-tools}/bin M2LIBC_PATH=${minimalBootstrap.stage0-posix.src}/M2libc TMPDIR=''${TMPDIR:-/tmp}"
              echo "hcc-blynn: GCC-built M2-Mesoplanet hcpp-blynn.c -> hcpp"
              $gcc_m2_env ${m2MesoplanetGcc}/bin/M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcpp-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcpp
              chmod 555 hcpp
              echo "hcc-blynn: GCC-built M2-Mesoplanet hcc1-blynn.c -> hcc1"
              $gcc_m2_env ${m2MesoplanetGcc}/bin/M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcc1-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcc1
              chmod 555 hcc1
            '';
            top = 134217728;
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by a GCC-built M2-Mesoplanet";
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

          ghc-precisely-gcc = hccFromPrecisely {
            pname = "hcc-ghc-precisely-gcc";
            precisely = preciselyGhcDebug;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GHC-built Blynn precisely debug compiler and GCC";
            };
          };

          gcc-precisely-gcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-gcc";
            precisely = preciselyGccHost;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and GCC";
            };
          };

          gcc-precisely-tcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-tcc";
            precisely = preciselyGccHost;
            cBackend = hccCBackends.tcc tinyccByTriple.gcc-precisely-gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and HCC-built TinyCC";
            };
          };

          m2-precisely-m2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-m2";
            precisely = preciselyM2Stage0;
            cBackend = hccCBackends.m2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
            };
          };

          m2-precisely-gcc = hccFromPrecisely {
            pname = "hcc-m2-precisely-gcc";
            precisely = preciselyM2Stage0;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the stage0-built Blynn precisely and GCC";
            };
          };

          m2-precisely-gccm2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-gccm2";
            precisely = preciselyM2Stage0;
            cBackend = hccCBackends.gccm2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and a GCC-built M2-Mesoplanet";
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
          ghc-precisely-gcc = tinyccFromHcc "tinycc-boot-hcc-ghc-precisely-gcc" hccByTriple.ghc-precisely-gcc;
          gcc-precisely-gcc = tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-gcc" hccByTriple.gcc-precisely-gcc;
          gcc-precisely-tcc = tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-tcc" hccByTriple.gcc-precisely-tcc;
          m2-precisely-m2 = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-m2" hccByTriple.m2-precisely-m2;
          m2-precisely-gcc = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gcc" hccByTriple.m2-precisely-gcc;
          m2-precisely-gccm2 = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gccm2" hccByTriple.m2-precisely-gccm2;
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

        precisely-dialect-tests = pkgs.callPackage ./nix/precisely-dialect-tests.nix {
          precisely = preciselyGhcDebug;
          src = hccSrc;
          blynnSrc = blynnUpstreamSrc;
        };
      in {
        packages = {
          blynn-compiler = blynnCompiler;
          precisely-m2-stage0 = preciselyM2Stage0;
          precisely-gcc-host = preciselyGccHost;
          precisely-ghc-debug = preciselyGhcDebug;
          m2-mesoplanet-gcc = m2MesoplanetGcc;
          hcc-profile-host-ghc-native = hccProfileHostGhcNative;
          inherit hcc-m1-smoke hcc-mescc-tests mutable-io-proof precisely-dialect-tests;
          default = preciselyM2Stage0;
        } // lib.mapAttrs' (name: value: {
          name = "hcc-${name}";
          inherit value;
        }) hccByTriple // lib.mapAttrs' (name: value: {
          name = "tinycc-boot-hcc-${name}";
          inherit value;
        }) tinyccByTriple;

        apps.blynn-precisely-gcc = {
          type = "app";
          program = "${preciselyGccHost}/bin/precisely_up";
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
            hccByTriple.ghc-precisely-gcc
            hccByTriple.gcc-precisely-gcc
            (pkgs.haskellPackages.ghcWithPackages (hpkgs: [
              hpkgs.raw-strings-qq
            ]))
          ];
          shellHook = ''
            echo "blynn-bootstrap dev shell — sources are in ./vendor/blynn-compiler"
          '';
        };

        devShells.bench = pkgs.mkShell {
          packages = [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.procps
            pkgs.time
          ];
        };
      });
}
