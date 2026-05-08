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
        hccHsSrc = lib.cleanSourceWith {
          src = hccSrc;
          filter = path: type:
            type == "directory" || lib.hasSuffix ".hs" (baseNameOf path);
        };
        blynnSrc = ./vendor/blynn-compiler;
        blynnUpstreamSrc = ./vendor/blynn-compiler/upstream;
        m2libcSrc = ./vendor/blynn-compiler/M2libc;

        minimalBootstrap = pkgs.minimal-bootstrap;

        stageRun = args: pkgs.callPackage ./nix/blynn-stage-run.nix ({
          inherit minimalBootstrap;
        } // args);

        pathName = rel: lib.replaceStrings [ "/" "." "_" ] [ "-" "-" "-" ] rel;
        blynnFile = rel: builtins.path {
          path = blynnSrc + "/${rel}";
          name = "blynn-${pathName rel}";
        };
        upstreamFile = rel: builtins.path {
          path = blynnUpstreamSrc + "/${rel}";
          name = "blynn-upstream-${pathName rel}";
        };
        blynnShare = drv: name: "${drv}/share/blynn/${name}";

        blynnRootStages = let
          packBlob = name: file: stageRun {
            pname = "blynn-blob-${name}";
            nativeBuildInputs = [ blynnRootStages.pack-blobs ];
            description = "Packed Blynn bootstrap blob ${name}";
            buildScript = ''
              ${blynnRootStages.pack-blobs}/bin/pack_blobs -f ${file} -o ${name}
            '';
            installScript = ''
              install -Dm644 ${name} "$out/share/blynn/${name}"
            '';
          };

          rawStep = name: rawInput: parseLabel: levelFile: stageRun {
            pname = "blynn-raw-${name}";
            nativeBuildInputs = [ blynnRootStages.vm ];
            description = "Blynn raw VM image ${name}";
            buildScript = ''
              ${blynnRootStages.vm}/bin/vm --raw ${rawInput} -pb ${parseLabel} -lf ${levelFile} -o ${name}
            '';
            installScript = ''
              install -Dm644 ${name} "$out/share/blynn/${name}"
            '';
          };

          rawCompileLoad = name: rawInput: levelFiles: extraFlags: stageRun {
            pname = "blynn-raw-${name}";
            nativeBuildInputs = [ blynnRootStages.vm ];
            description = "Blynn raw compiler stage ${name}";
            buildScript = ''
              ${blynnRootStages.vm}/bin/vm -l ${rawInput} ${lib.concatMapStringsSep " " (f: "-lf ${f}") levelFiles} ${extraFlags} -o ${name}
            '';
            installScript = ''
              install -Dm644 ${name} "$out/share/blynn/${name}"
            '';
          };

          rawCompile = name: prevRaw: sourceFile: foreignFlag: stageRun {
            pname = "blynn-raw-${name}";
            nativeBuildInputs = [ blynnRootStages.vm ];
            description = "Blynn raw compiler stage ${name}";
            buildScript = ''
              ${blynnRootStages.vm}/bin/vm -f ${sourceFile} ${foreignFlag} --raw ${prevRaw} --rts_c run -o ${name}
            '';
            installScript = ''
              install -Dm644 ${name} "$out/share/blynn/${name}"
            '';
          };

          vmCStage = name: prevRaw: sourceFile: stageRun {
            pname = "blynn-${name}";
            nativeBuildInputs = [ blynnRootStages.vm ];
            description = "Blynn compiler stage ${name}";
            buildScript = ''
              ${blynnRootStages.vm}/bin/vm -f ${sourceFile} --foreign 2 --raw ${prevRaw} --rts_c run -o ${name}.c
              compile_m2 ${name}.c ${name}
            '';
            installScript = ''
              install -Dm755 ${name} "$out/bin/${name}"
              install -Dm644 ${name}.c "$out/share/blynn/${name}.c"
            '';
          };

          fileArgCStage = name: prev: prevBin: sourceFile: stageRun {
            pname = "blynn-${name}";
            nativeBuildInputs = [ prev ];
            description = "Blynn compiler stage ${name}";
            buildScript = ''
              ${prev}/bin/${prevBin} ${sourceFile} ${name}.c
              compile_m2 ${name}.c ${name}
            '';
            installScript = ''
              install -Dm755 ${name} "$out/bin/${name}"
              install -Dm644 ${name}.c "$out/share/blynn/${name}.c"
            '';
          };
        in rec {
          pack-blobs = stageRun {
            pname = "blynn-pack-blobs";
            description = "Blynn bootstrap blob packer";
            buildScript = ''
              mkdir -p M2libc
              cp ${blynnFile "pack_blobs.c"} pack_blobs.c
              cp ${blynnFile "gcc_req.h"} gcc_req.h
              cp ${blynnFile "M2libc/bootstrappable.h"} M2libc/bootstrappable.h
              cp ${blynnFile "M2libc/bootstrappable.c"} M2libc/bootstrappable.c
              compile_m2 pack_blobs.c pack_blobs
            '';
            installScript = ''
              install -Dm755 pack_blobs "$out/bin/pack_blobs"
            '';
          };

          parenthetically = packBlob "parenthetically" (blynnFile "blob/parenthetically.source");
          exponentially = packBlob "exponentially" (blynnFile "blob/exponentially.source");
          practically = packBlob "practically" (blynnFile "blob/practically.source");
          singularity-blob = packBlob "singularity_blob" (blynnFile "blob/singularity.source");

          vm = stageRun {
            pname = "blynn-vm";
            description = "Blynn bootstrap virtual machine";
            buildScript = ''
              mkdir -p M2libc
              cp ${blynnFile "vm.c"} vm.c
              cp ${blynnFile "gcc_req.h"} gcc_req.h
              cp ${blynnFile "M2libc/bootstrappable.h"} M2libc/bootstrappable.h
              cp ${blynnFile "M2libc/bootstrappable.c"} M2libc/bootstrappable.c
              compile_m2 vm.c vm
            '';
            installScript = ''
              install -Dm755 vm "$out/bin/vm"
            '';
          };

          raw-l = rawStep "raw_l" (blynnFile "blob/root") "bootstrap" (blynnShare parenthetically "parenthetically");
          raw-m = rawStep "raw_m" (blynnShare raw-l "raw_l") (blynnShare parenthetically "parenthetically") (blynnShare exponentially "exponentially");
          raw-n = rawStep "raw_n" (blynnShare raw-m "raw_m") (blynnShare exponentially "exponentially") (blynnShare practically "practically");
          raw-o = rawStep "raw_o" (blynnShare raw-n "raw_n") (blynnShare practically "practically") (blynnShare singularity-blob "singularity_blob");
          raw-p = rawStep "raw_p" (blynnShare raw-o "raw_o") (blynnShare singularity-blob "singularity_blob") (blynnFile "singularity");
          raw-q = rawStep "raw_q" (blynnShare raw-p "raw_p") "singularity" (blynnFile "semantically");
          raw-r = rawStep "raw_r" (blynnShare raw-q "raw_q") "semantically" (blynnFile "stringy");
          raw-s = rawStep "raw_s" (blynnShare raw-r "raw_r") "stringy" (blynnFile "binary");
          raw-t = rawStep "raw_t" (blynnShare raw-s "raw_s") "binary" (blynnFile "algebraically");
          raw-u = rawStep "raw_u" (blynnShare raw-t "raw_t") "algebraically" (blynnFile "parity.hs");
          raw-v = rawStep "raw_v" (blynnShare raw-u "raw_u") "parity.hs" (blynnFile "fixity.hs");
          raw-w = rawStep "raw_w" (blynnShare raw-v "raw_v") "fixity.hs" (blynnFile "typically.hs");
          raw-x = rawStep "raw_x" (blynnShare raw-w "raw_w") "typically.hs" (blynnFile "classy.hs");
          raw-y = rawStep "raw_y" (blynnShare raw-x "raw_x") "classy.hs" (blynnFile "barely.hs");
          raw-z = rawStep "raw_z" (blynnShare raw-y "raw_y") "barely.hs" (blynnFile "barely.hs");
          raw = rawCompileLoad "raw" (blynnShare raw-z "raw_z") [ (blynnFile "barely.hs") ] "";

          lonely-raw = stageRun {
            pname = "blynn-raw-lonely_raw.txt";
            nativeBuildInputs = [ blynnRootStages.vm ];
            description = "Blynn raw compiler stage lonely";
            buildScript = ''
              ${blynnRootStages.vm}/bin/vm -l ${blynnShare raw "raw"} -lf ${blynnFile "effectively.hs"} --redo -lf ${blynnFile "lonely.hs"} -o lonely_raw.txt
            '';
            installScript = ''
              install -Dm644 lonely_raw.txt "$out/share/blynn/lonely_raw.txt"
            '';
          };
          patty-raw = rawCompile "patty_raw.txt" (blynnShare lonely-raw "lonely_raw.txt") (blynnFile "patty.hs") "";
          guardedly-raw = rawCompile "guardedly_raw.txt" (blynnShare patty-raw "patty_raw.txt") (blynnFile "guardedly.hs") "";
          assembly-raw = rawCompile "assembly_raw.txt" (blynnShare guardedly-raw "guardedly_raw.txt") (blynnFile "assembly.hs") "";
          mutually-raw = rawCompile "mutually_raw.txt" (blynnShare assembly-raw "assembly_raw.txt") (blynnFile "mutually.hs") "--foreign 2";
          uniquely-raw = rawCompile "uniquely_raw.txt" (blynnShare mutually-raw "mutually_raw.txt") (blynnFile "uniquely.hs") "--foreign 2";
          virtually-raw = rawCompile "virtually_raw.txt" (blynnShare uniquely-raw "uniquely_raw.txt") (blynnFile "virtually.hs") "--foreign 2";

          marginally = vmCStage "marginally" (blynnShare virtually-raw "virtually_raw.txt") (blynnFile "marginally.hs");
          methodically = fileArgCStage "methodically" marginally "marginally" (blynnFile "methodically.hs");
          crossly = fileArgCStage "crossly" methodically "methodically" (blynnFile "crossly.hs");
          precisely = fileArgCStage "precisely" crossly "crossly" (blynnFile "precisely.hs");
        };

        blynnCompiler = pkgs.runCommand "blynn-compiler-0-unstable-2026-05-06" { } ''
          mkdir -p "$out/bin" "$out/share/blynn-compiler/generated"
          ln -s ${blynnRootStages.pack-blobs}/bin/pack_blobs "$out/bin/pack_blobs"
          ln -s ${blynnRootStages.vm}/bin/vm "$out/bin/vm"
          ln -s ${blynnRootStages.marginally}/bin/marginally "$out/bin/marginally"
          ln -s ${blynnRootStages.methodically}/bin/methodically "$out/bin/methodically"
          ln -s ${blynnRootStages.crossly}/bin/crossly "$out/bin/crossly"
          ln -s ${blynnRootStages.precisely}/bin/precisely "$out/bin/precisely"
          ln -s ${blynnShare blynnRootStages.raw "raw"} "$out/share/blynn-compiler/raw"
          ln -s ${blynnShare blynnRootStages.lonely-raw "lonely_raw.txt"} "$out/share/blynn-compiler/generated/lonely_raw.txt"
          ln -s ${blynnShare blynnRootStages.patty-raw "patty_raw.txt"} "$out/share/blynn-compiler/generated/patty_raw.txt"
          ln -s ${blynnShare blynnRootStages.guardedly-raw "guardedly_raw.txt"} "$out/share/blynn-compiler/generated/guardedly_raw.txt"
          ln -s ${blynnShare blynnRootStages.assembly-raw "assembly_raw.txt"} "$out/share/blynn-compiler/generated/assembly_raw.txt"
          ln -s ${blynnShare blynnRootStages.mutually-raw "mutually_raw.txt"} "$out/share/blynn-compiler/generated/mutually_raw.txt"
          ln -s ${blynnShare blynnRootStages.uniquely-raw "uniquely_raw.txt"} "$out/share/blynn-compiler/generated/uniquely_raw.txt"
          ln -s ${blynnShare blynnRootStages.virtually-raw "virtually_raw.txt"} "$out/share/blynn-compiler/generated/virtually_raw.txt"
        '';

        upstreamModules = names: map (moduleName: upstreamFile ("inn/" + moduleName + ".hs")) names;
        upstreamInput = modules: leaf: upstreamModules modules ++ [ (upstreamFile ("inn/" + leaf + ".hs")) ];
        upstreamStage = {
          name,
          prev,
          prevBin,
          inputFiles,
          prevIsParty ? false,
          top ? null,
        }: stageRun {
          pname = "blynn-upstream-${name}";
          nativeBuildInputs = [ prev ];
          description = "Upstream Blynn compiler stage ${name}";
          buildScript = ''
            cat ${lib.concatStringsSep " " inputFiles} > ${name}.input.hs
            ${if prevIsParty then ''
              ${prev}/bin/party /dev/null /dev/null < ${name}.input.hs > ${name}.c
            '' else ''
              ${prev}/bin/${prevBin} < ${name}.input.hs > ${name}.c
            ''}
            ${lib.optionalString (top != null) ''
              sed -i -E 's/enum\{TOP=[0-9]+\};/enum{TOP=${toString top}};/' ${name}.c
            ''}
            compile_m2 ${name}.c ${name}
          '';
          installScript = ''
            install -Dm755 ${name} "$out/bin/${name}"
            install -Dm644 ${name}.c "$out/share/blynn/${name}.c"
          '';
        };

        blynnUpstreamStages = rec {
          party = stageRun {
            pname = "blynn-upstream-party";
            nativeBuildInputs = [ blynnRootStages.methodically ];
            description = "Upstream Blynn party stage";
            buildScript = ''
              ${blynnRootStages.methodically}/bin/methodically ${upstreamFile "party.hs"} party.c
              compile_m2 party.c party -f ${upstreamFile "party_shims.c"}
            '';
            installScript = ''
              install -Dm755 party "$out/bin/party"
              install -Dm644 party.c "$out/share/blynn/party.c"
            '';
          };

          multiparty = upstreamStage {
            name = "multiparty";
            prev = party;
            prevBin = "party";
            prevIsParty = true;
            inputFiles = upstreamInput [ "Base0" "System" "Ast" "Map" "Parser" "Kiselyov" "Unify" "RTS" "Typer" ] "party";
          };
          party1 = upstreamStage {
            name = "party1";
            prev = multiparty;
            prevBin = "multiparty";
            inputFiles = upstreamInput [ "Base0" "System" "Ast1" "Map" "Parser1" "Kiselyov" "Unify1" "RTS" "Typer1" ] "party";
          };
          party2 = upstreamStage {
            name = "party2";
            prev = party1;
            prevBin = "party1";
            inputFiles = upstreamInput [ "Base1" "System" "Ast2" "Map" "Parser2" "Kiselyov" "Unify1" "RTS1" "Typer2" ] "party1";
          };
          crossly_up = upstreamStage {
            name = "crossly_up";
            prev = party2;
            prevBin = "party2";
            inputFiles = upstreamInput [ "Base1" "System" "Ast3" "Map" "Parser3" "Kiselyov" "Unify1" "RTS2" "Typer3" ] "party2";
          };
          crossly1 = upstreamStage {
            name = "crossly1";
            prev = crossly_up;
            prevBin = "crossly_up";
            inputFiles = upstreamInput [ "Base2" "System" "AstPrecisely" "Map1" "ParserPrecisely" "KiselyovPrecisely" "Unify1" "RTSPrecisely" "TyperPrecisely" "Obj" "Charser" ] "precisely";
          };
          precisely_up = upstreamStage {
            name = "precisely_up";
            prev = crossly1;
            prevBin = "crossly1";
            top = 33554432;
            inputFiles = upstreamInput [ "BasePrecisely" "System" "AstPrecisely" "Map1" "ParserPrecisely" "KiselyovPrecisely" "Unify1" "RTSPrecisely" "TyperPrecisely" "Obj" "Charser" ] "precisely";
          };
        };

        preciselyM2Stage0 = pkgs.runCommand "blynn-precisely-0-unstable-2026-05-06" { } ''
          mkdir -p "$out/bin" "$out/share/blynn-precisely"
          ln -s ${blynnUpstreamStages.party}/bin/party "$out/bin/party"
          ln -s ${blynnUpstreamStages.multiparty}/bin/multiparty "$out/bin/multiparty"
          ln -s ${blynnUpstreamStages.party1}/bin/party1 "$out/bin/party1"
          ln -s ${blynnUpstreamStages.party2}/bin/party2 "$out/bin/party2"
          ln -s ${blynnUpstreamStages.crossly_up}/bin/crossly_up "$out/bin/crossly_up"
          ln -s ${blynnUpstreamStages.crossly1}/bin/crossly1 "$out/bin/crossly1"
          ln -s ${blynnUpstreamStages.precisely_up}/bin/precisely_up "$out/bin/precisely_up"
          ln -s ${blynnShare blynnUpstreamStages.party "party.c"} "$out/share/blynn-precisely/party.c"
          ln -s ${blynnShare blynnUpstreamStages.multiparty "multiparty.c"} "$out/share/blynn-precisely/multiparty.c"
          ln -s ${blynnShare blynnUpstreamStages.party1 "party1.c"} "$out/share/blynn-precisely/party1.c"
          ln -s ${blynnShare blynnUpstreamStages.party2 "party2.c"} "$out/share/blynn-precisely/party2.c"
          ln -s ${blynnShare blynnUpstreamStages.crossly_up "crossly_up.c"} "$out/share/blynn-precisely/crossly_up.c"
          ln -s ${blynnShare blynnUpstreamStages.crossly1 "crossly1.c"} "$out/share/blynn-precisely/crossly1.c"
          ln -s ${blynnShare blynnUpstreamStages.precisely_up "precisely_up.c"} "$out/share/blynn-precisely/precisely_up.c"
        '';

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

        hccBlynnSources = pkgs.callPackage ./nix/hcc-blynn-sources.nix {
          src = hccHsSrc;
          blynnSrc = blynnUpstreamSrc;
        };

        hccBlynnCFromPrecisely = pname: precisely:
          pkgs.callPackage ./nix/hcc-blynn-c.nix {
            inherit pname precisely;
            sourceBundle = hccBlynnSources;
            shareName = pname;
          };

        hccBlynnCByPrecisely = {
          ghc = hccBlynnCFromPrecisely "hcc-blynn-c-ghc-precisely" preciselyGhcDebug;
          gcc = hccBlynnCFromPrecisely "hcc-blynn-c-gcc-precisely" preciselyGccHost;
          m2 = hccBlynnCFromPrecisely "hcc-blynn-c-m2-precisely" preciselyM2Stage0;
        };

        hccFromPrecisely = {
          pname,
          generatedC,
          cBackend,
        }:
          pkgs.callPackage ./nix/hcc-blynn-bin.nix ({
            inherit pname generatedC;
            src = hccSrc;
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
            hcc1Top = 268435456;
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
            hcc1Top = 268435456;
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
            hcppTop = 134217728;
            hcc1Top = 536870912;
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
            hcppTop = 134217728;
            hcc1Top = 536870912;
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
            generatedC = hccBlynnCByPrecisely.ghc;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GHC-built Blynn precisely debug compiler and GCC";
            };
          };

          gcc-precisely-gcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-gcc";
            generatedC = hccBlynnCByPrecisely.gcc;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and GCC";
            };
          };

          gcc-precisely-tcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-tcc";
            generatedC = hccBlynnCByPrecisely.gcc;
            cBackend = hccCBackends.tcc tinyccByTriple.gcc-precisely-gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and HCC-built TinyCC";
            };
          };

          m2-precisely-m2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-m2";
            generatedC = hccBlynnCByPrecisely.m2;
            cBackend = hccCBackends.m2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
            };
          };

          m2-precisely-gcc = hccFromPrecisely {
            pname = "hcc-m2-precisely-gcc";
            generatedC = hccBlynnCByPrecisely.m2;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the stage0-built Blynn precisely and GCC";
            };
          };

          m2-precisely-gccm2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-gccm2";
            generatedC = hccBlynnCByPrecisely.m2;
            cBackend = hccCBackends.gccm2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and a GCC-built M2-Mesoplanet";
            };
          };
        };

        hccGccPreciselyGccStatsWith = {
          pname,
          extraCFlags,
          description,
        }: hccFromPrecisely {
          inherit pname;
          generatedC = hccBlynnCByPrecisely.gcc;
          cBackend = hccCBackends.gcc // {
            compileCommand = ''
              echo "hcc-blynn: gcc stats cc hcpp-blynn.c -> hcpp"
              $CC -O0 -DHCC_RTS_STATS ${extraCFlags} hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: gcc stats cc hcc1-blynn.c -> hcc1"
              $CC -O0 -DHCC_RTS_STATS ${extraCFlags} hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
            '';
            inherit description;
          };
        };

        hccGccPreciselyGccStatsCopying = hccGccPreciselyGccStatsWith {
          pname = "hcc-gcc-precisely-gcc-stats-copying";
          extraCFlags = "";
          description = "Stats-enabled semispace HCC compiled by the GCC-built Blynn precisely compiler and GCC";
        };

        hccGccPreciselyGccStatsGenerational = hccGccPreciselyGccStatsWith {
          pname = "hcc-gcc-precisely-gcc-stats-generational";
          extraCFlags = "-DHCC_RTS_GENERATIONAL -DHCC_RTS_NURSERY_WORDS=16777216";
          description = "Stats-enabled generational HCC compiled by the GCC-built Blynn precisely compiler and GCC";
        };

        tinyccFromHcc = pname: hcc: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          inherit pname hcc minimalBootstrap;
          mesLibc = minimalBootstrap.mes-libc;
          m2libc = m2libcSrc;
        };

        tinyccGccPreciselyGccStatsCopying =
          tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-gcc-stats-copying" hccGccPreciselyGccStatsCopying;

        tinyccGccPreciselyGccStatsGenerational =
          tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-gcc-stats-generational" hccGccPreciselyGccStatsGenerational;

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
          hcc-blynn-sources = hccBlynnSources;
          hcc-blynn-c-ghc-precisely = hccBlynnCByPrecisely.ghc;
          hcc-blynn-c-gcc-precisely = hccBlynnCByPrecisely.gcc;
          hcc-blynn-c-m2-precisely = hccBlynnCByPrecisely.m2;
          hcc-gcc-precisely-gcc-stats = hccGccPreciselyGccStatsGenerational;
          hcc-gcc-precisely-gcc-stats-copying = hccGccPreciselyGccStatsCopying;
          hcc-gcc-precisely-gcc-stats-generational = hccGccPreciselyGccStatsGenerational;
          tinycc-boot-hcc-gcc-precisely-gcc-stats = tinyccGccPreciselyGccStatsGenerational;
          tinycc-boot-hcc-gcc-precisely-gcc-stats-copying = tinyccGccPreciselyGccStatsCopying;
          tinycc-boot-hcc-gcc-precisely-gcc-stats-generational = tinyccGccPreciselyGccStatsGenerational;
          inherit hcc-m1-smoke hcc-mescc-tests mutable-io-proof precisely-dialect-tests;
          default = preciselyM2Stage0;
        } // lib.mapAttrs' (name: value: {
          name = "blynn-stage-${name}";
          inherit value;
        }) blynnRootStages // lib.mapAttrs' (name: value: {
          name = "blynn-upstream-stage-${name}";
          inherit value;
        }) blynnUpstreamStages // lib.mapAttrs' (name: value: {
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
