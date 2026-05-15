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
        hccSrc = ./hcc;
        hccHsSrc = lib.cleanSourceWith {
          src = hccSrc;
          filter = path: type:
            type == "directory" || lib.hasSuffix ".hs" (baseNameOf path);
        };
        hccBlynnInputSrc = lib.cleanSourceWith {
          src = hccSrc;
          filter = path: type:
            type == "directory"
            || lib.hasSuffix ".hs" (baseNameOf path)
            || lib.hasSuffix ".modules" (baseNameOf path);
        };
        upstreamPatches = ./patches/upstreams;
        upstreamSources = {
          oriansjBlynnCompiler = pkgs.fetchgit {
            url = "https://github.com/OriansJ/blynn-compiler.git";
            rev = "9e46a8da1df90032f1d270a49a6ef5d0cc909658";
            fetchSubmodules = true;
            hash = "sha256-HV0WRV3Q/ToxK4wdGjyfTC1yLFp+hqalZuKMZLdBh2E=";
          };
          blynnCompiler = pkgs.fetchgit {
            url = "https://github.com/blynn/compiler.git";
            rev = "a1f1c47c9bb3ff6a45a0735ced84984396560535";
            hash = "sha256-xDYN3Ern83a5h8liJYpFBJ9BVzD5YyOJjiHGM5Za+X8=";
          };
          gnuMes = pkgs.fetchgit {
            url = "https://git.savannah.gnu.org/git/mes.git";
            rev = "c331d801da386ba752f3fe92d0538102a90e988d";
            hash = "sha256-iw1/MP0dwXOs9gyB7WhnvpCz59zveeoYy85wt0j+fWA=";
          };
        };
        mesLibcArch =
          lib.attrByPath [ system ] (throw "unsupported Mes libc bootstrap platform: ${system}") {
            "x86_64-linux" = "x86_64";
            "aarch64-linux" = "x86_64";
            "i686-linux" = "x86";
          };
        nativeM1Target =
          lib.attrByPath [ system ] "amd64" {
            "aarch64-linux" = "aarch64";
            "x86_64-linux" = "amd64";
            "i686-linux" = "i386";
          };
        mesLibcSources =
          (lib.importJSON "${pkgs.path}/pkgs/os-specific/linux/minimal-bootstrap/mes/sources.json").${mesLibcArch}.linux.gcc;
        mesLibcSourceFiles =
          map (rel: "$out/${rel}") (lib.take 100 mesLibcSources.libc_gnu_SOURCES)
          ++ [ "${pkgs.path}/pkgs/os-specific/linux/minimal-bootstrap/mes/ldexpl.c" ]
          ++ map (rel: "$out/${rel}") (lib.drop 100 mesLibcSources.libc_gnu_SOURCES);
        patchedUpstreamSource = { name, src, patches ? [ ] }:
          pkgs.runCommand name {
            nativeBuildInputs = [ pkgs.coreutils pkgs.patch ];
          } (''
            cp -R --no-preserve=mode,ownership ${src} "$out"
            chmod -R u+w "$out"
            cd "$out"
          '' + lib.concatMapStringsSep "\n" (patchFile: ''
            patch -p1 < ${patchFile}
          '') patches);
        blynnSrc = patchedUpstreamSource {
          name = "oriansj-blynn-compiler-hcc";
          src = upstreamSources.oriansjBlynnCompiler;
        };
        blynnUpstreamSrc = patchedUpstreamSource {
          name = "blynn-compiler-hcc";
          src = upstreamSources.blynnCompiler;
          patches = [
            (upstreamPatches + "/blynn-compiler-local.patch")
          ];
        };
        m2libcSrc = "${blynnSrc}/M2libc";
        mesLibcSrc = pkgs.runCommand "gnu-mes-libc-hcc" {
          nativeBuildInputs = [ pkgs.coreutils ];
        } ''
          cp -R --no-preserve=mode,ownership ${upstreamSources.gnuMes} "$out"
          chmod -R u+w "$out"

          mkdir -p "$out/include/arch" "$out/include/mes" "$out/lib"
          substituteInPlace "$out/include/linux/${mesLibcArch}/syscall.h" \
            --replace-fail '#define SYS_nanosleep 0x33' '#define SYS_nanosleep 0x23'
          substituteInPlace "$out/lib/linux/${mesLibcArch}-mes-gcc/_exit.c" \
            --replace-fail ': "rm" (code)' ': "rm" (code) : "rax", "rdi"'
          substituteInPlace "$out/lib/mes/ntoab.c" \
            --replace-fail 'size_t
__mesabi_uldiv (size_t a, size_t b, size_t *remainder)' 'unsigned long
__mesabi_uldiv (unsigned long a, unsigned long b, unsigned long *remainder)' \
            --replace-fail '  size_t i;
  size_t u;
  size_t b = base;' '  unsigned long i;
  unsigned long u;
  unsigned long b = base;'
          substituteInPlace "$out/lib/linux/ioctl3.c" \
            --replace-fail 'ioctl3 (int filedes, size_t command, long data)' \
                           'ioctl3 (int filedes, unsigned long command, long data)'
          substituteInPlace "$out/lib/linux/link.c" \
            --replace-fail 'return _sys_call4 (SYS_linkat, AT_FDCWD, (long) old_name, AT_FDCWD, (long) new_name);' \
                           'return _sys_call5 (SYS_linkat, AT_FDCWD, (long) old_name, AT_FDCWD, (long) new_name, 0);'
          substituteInPlace "$out/lib/string/strpbrk.c" \
            --replace-fail '  while (*p)
    if (strchr (stopset, *p))
      break;
    else
      p++;
  return p;' '  while (*p)
    if (strchr (stopset, *p))
      return p;
    else
      p++;
  return 0;'
          substituteInPlace "$out/lib/stdio/vfprintf.c" \
            --replace-fail '  int count = 0;
  while (*p)' '  int count = 0;
  int has_l = 0;
  while (*p)' \
            --replace-fail "        if (c == 'l')
          c = *++p;" "        if (c == 'l')
          {
            has_l = 1;
            c = *++p;
          }
        if (c == 'l')
          {
            has_l = 1;
            c = *++p;
          }" \
            --replace-fail '              long d = va_arg (ap, long);' '              long d;
              if (has_l)
                {
                  has_l = 0;
                  d = va_arg (ap, long);
                }
              else if (c != '"'"'d'"'"' && c != '"'"'i'"'"')
                d = (long) (va_arg (ap, unsigned int));
              else
                d = (long) (va_arg (ap, int));' \
            --replace-fail '              double d = va_arg8 (ap, double);' \
                           '              double d = va_arg (ap, double);'
          substituteInPlace "$out/lib/stdio/vsnprintf.c" \
            --replace-fail '  int count = 0;
  char c;' '  int count = 0;
  int has_l = 0;
  char c;' \
            --replace-fail "        if (c == 'l')
          c = *++p;
        if (c == 'l')
          c = *++p;" "        if (c == 'l')
          {
            has_l = 1;
            c = *++p;
          }
        if (c == 'l')
          {
            has_l = 1;
            c = *++p;
          }
        if (c == 'l')
          {
            has_l = 1;
            c = *++p;
          }" \
            --replace-fail '              long d = va_arg (ap, long);' '              long d;
              if (has_l)
                {
                  has_l = 0;
                  d = va_arg (ap, long);
                }
              else if (c != '"'"'d'"'"' && c != '"'"'i'"'"')
                d = (long) (va_arg (ap, unsigned int));
              else
                d = (long) (va_arg (ap, int));' \
            --replace-fail '              double d = va_arg8 (ap, double);' \
                           '              double d = va_arg (ap, double);'
          cp ${./nix/sources/mes-libc/x86_64-setjmp.c} "$out/lib/x86_64-mes-gcc/setjmp.c"

          cp "$out/include/linux/${mesLibcArch}/kernel-stat.h" "$out/include/arch/kernel-stat.h"
          cp "$out/include/linux/${mesLibcArch}/signal.h" "$out/include/arch/signal.h"
          cp "$out/include/linux/${mesLibcArch}/syscall.h" "$out/include/arch/syscall.h"

          cp ${./nix/sources/mes-libc/config.h} "$out/include/mes/config.h"

          cat ${lib.concatStringsSep " " mesLibcSourceFiles} > "$out/lib/libc.c"
          cp "$out/lib/linux/${mesLibcArch}-mes-gcc/crt1.c" "$out/lib/crt1.c"
          cp "$out/lib/linux/${mesLibcArch}-mes-gcc/crti.c" "$out/lib/crti.c"
          cp "$out/lib/linux/${mesLibcArch}-mes-gcc/crtn.c" "$out/lib/crtn.c"
          cp "$out/lib/posix/getopt.c" "$out/lib/libgetopt.c"
        '';

        minimalBootstrap = pkgs.minimal-bootstrap;
        rawDerivation = import ./nix/raw-mk-derivation.nix {
          inherit lib system;
          inherit (pkgs)
            bash
            coreutils
            gnused
            gnugrep
            gawk
            gnutar
            gzip
            xz
            bzip2
            patch
            findutils
            diffutils
            gcc;
          bootstrapTools = [ minimalBootstrap.stage0-posix.mescc-tools-extra ];
        };
        rawStdenvNoCC = rawDerivation.noCC;
        rawStdenvCC = rawDerivation.cc;

        stageRun = args: pkgs.callPackage ./nix/blynn-stage-run.nix ({
          inherit minimalBootstrap;
          stdenvNoCC = rawStdenvNoCC;
        } // args);

        blynnFile = rel: "${blynnSrc}/${rel}";
        upstreamFile = rel: "${blynnUpstreamSrc}/${rel}";
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
              ${prev}/bin/${prevBin} ${lib.optionalString (top != null) "top ${toString top}"} < ${name}.input.hs > ${name}.c
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
            top = 134217728;
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

        preciselyM2Stage0 = rawStdenvNoCC.mkDerivation {
          pname = "blynn-precisely";
          version = "0-unstable-2026-05-06";
          dontUnpack = true;
          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;
          dontFixup = true;
          dontPatchELF = true;
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/share/blynn-precisely"
            install -Dm555 ${blynnUpstreamStages.party}/bin/party "$out/bin/party"
            install -Dm555 ${blynnUpstreamStages.multiparty}/bin/multiparty "$out/bin/multiparty"
            install -Dm555 ${blynnUpstreamStages.party1}/bin/party1 "$out/bin/party1"
            install -Dm555 ${blynnUpstreamStages.party2}/bin/party2 "$out/bin/party2"
            install -Dm555 ${blynnUpstreamStages.crossly_up}/bin/crossly_up "$out/bin/crossly_up"
            install -Dm555 ${blynnUpstreamStages.crossly1}/bin/crossly1 "$out/bin/crossly1"
            install -Dm555 ${blynnUpstreamStages.precisely_up}/bin/precisely_up "$out/bin/precisely_up"
            cp ${blynnShare blynnUpstreamStages.party "party.c"} "$out/share/blynn-precisely/party.c"
            cp ${blynnShare blynnUpstreamStages.multiparty "multiparty.c"} "$out/share/blynn-precisely/multiparty.c"
            cp ${blynnShare blynnUpstreamStages.party1 "party1.c"} "$out/share/blynn-precisely/party1.c"
            cp ${blynnShare blynnUpstreamStages.party2 "party2.c"} "$out/share/blynn-precisely/party2.c"
            cp ${blynnShare blynnUpstreamStages.crossly_up "crossly_up.c"} "$out/share/blynn-precisely/crossly_up.c"
            cp ${blynnShare blynnUpstreamStages.crossly1 "crossly1.c"} "$out/share/blynn-precisely/crossly1.c"
            cp ${blynnShare blynnUpstreamStages.precisely_up "precisely_up.c"} "$out/share/blynn-precisely/precisely_up.c"
            runHook postInstall
          '';
        };

        preciselyGcc = pname: precisely: shareName: description:
        rawStdenvCC.mkDerivation {
          inherit pname;
          version = "0-unstable-2026-05-06";

          dontUnpack = true;
          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;

          buildPhase = ''
            runHook preBuild
            cp ${precisely}/share/blynn-precisely/precisely_up.c precisely_up.c
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
          stdenv = pkgs.stdenv;
          ghc = pkgs.haskellPackages.ghcWithPackages (hpkgs: [
            hpkgs.raw-strings-qq
          ]);
          src = blynnUpstreamSrc;
        };

        m2MesoplanetGcc = pkgs.callPackage ./nix/gcc-m2-mesoplanet.nix {
          stdenv = pkgs.stdenv;
          inherit minimalBootstrap;
        };

        hccHostGhcNative = pkgs.callPackage ./nix/hcc-ghc.nix {
          stdenv = pkgs.stdenv;
          pname = "hcc-host-ghc-native";
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = hccSrc;
        };

        hccProfileHostGhcNative = pkgs.callPackage ./nix/hcc-ghc-profile.nix {
          stdenv = pkgs.stdenv;
          pname = "hcc-profile-host-ghc-native";
          ghc = pkgs.haskellPackages.ghcWithPackages (_: []);
          src = hccSrc;
        };

        hccBlynnSources = pkgs.callPackage ./nix/hcc-blynn-sources.nix {
          stdenvNoCC = rawStdenvNoCC;
          src = hccBlynnInputSrc;
          blynnSrc = blynnUpstreamSrc;
        };

        hccBlynnObjsFromPrecisely = pname: precisely:
          pkgs.callPackage ./nix/hcc-blynn-objs.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely;
            sourceBundle = hccBlynnSources;
            shareName = pname;
          };

        hccBlynnCFromPrecisely = pname: precisely: commonObjects:
          pkgs.callPackage ./nix/hcc-blynn-c.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely commonObjects;
            sourceBundle = hccBlynnSources;
            shareName = pname;
          };

        preciselyBy = {
          m2.stage0 = preciselyM2Stage0;
          gcc.host = preciselyGccHost;
          ghc.debug = preciselyGhcDebug;
        };

        hccBlynnCBy = {
          ghc.precisely = hccBlynnCFromPrecisely "hcc-blynn-c-ghc-precisely" preciselyBy.ghc.debug hccBlynnObjsBy.ghc.precisely;
          gcc.precisely = hccBlynnCFromPrecisely "hcc-blynn-c-gcc-precisely" preciselyBy.gcc.host hccBlynnObjsBy.gcc.precisely;
          m2.precisely = hccBlynnCFromPrecisely "hcc-blynn-c-m2-precisely" preciselyBy.m2.stage0 hccBlynnObjsBy.m2.precisely;
        };

        hccBlynnObjsBy = {
          ghc.precisely = hccBlynnObjsFromPrecisely "hcc-blynn-objs-ghc-precisely" preciselyBy.ghc.debug;
          gcc.precisely = hccBlynnObjsFromPrecisely "hcc-blynn-objs-gcc-precisely" preciselyBy.gcc.host;
          m2.precisely = hccBlynnObjsFromPrecisely "hcc-blynn-objs-m2-precisely" preciselyBy.m2.stage0;
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
            mkDerivation = rawStdenvCC.mkDerivation;
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = ''
              echo "hcc-blynn: gcc cc hcpp-blynn.c -> hcpp"
              $CC -O2 hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: gcc cc hcc1-blynn.c -> hcc1"
              $CC -O2 hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
              echo "hcc-blynn: gcc cc cbits/hcc_m1.c -> hcc-m1"
              $CC -O2 cbits/hcc_m1.c -o hcc-m1
            '';
            description = "HCC compiled from Blynn output by the normal GCC C toolchain";
          };

          tcc = tcc: {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [ tcc ];
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = ''
              echo "hcc-blynn: tcc hcpp-blynn.c -> hcpp"
              ${tcc}/bin/tcc -B ${tcc}/lib -I ${tcc}/include hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: tcc hcc1-blynn.c -> hcc1"
              ${tcc}/bin/tcc -B ${tcc}/lib -I ${tcc}/include hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
              echo "hcc-blynn: tcc cbits/hcc_m1.c -> hcc-m1"
              ${tcc}/bin/tcc -B ${tcc}/lib -I ${tcc}/include cbits/hcc_m1.c -o hcc-m1
            '';
            description = "HCC compiled from Blynn output by HCC-built TinyCC";
          };

          m2 = {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              . ${./scripts/lib/bootstrap.sh}
              cat hcpp-blynn.c > hcpp-body.c
              cat hcc1-blynn.c > hcc1-body.c
              printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' > hcpp-blynn.c
              cat hcpp-body.c >> hcpp-blynn.c
              printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' > hcc1-blynn.c
              cat hcc1-body.c >> hcc1-blynn.c
              compile_m2 hcpp-blynn.c hcpp -f cbits/hcc_runtime_m2.c
              compile_m2 hcc1-blynn.c hcc1 -f cbits/hcc_runtime_m2.c
              compile_m2 cbits/hcc_m1.c hcc-m1
            '';
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by stage0 M2-Mesoplanet";
            metaPlatforms = [ "x86_64-linux" ];
          };

          gccm2 = {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              m2MesoplanetGcc
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              run_gcc_m2() {
                PATH=${minimalBootstrap.stage0-posix.mescc-tools}/bin \
                M2LIBC_PATH=${minimalBootstrap.stage0-posix.src}/M2libc \
                TMPDIR="''${TMPDIR:-/tmp}" \
                "$@"
              }
              cat hcpp-blynn.c > hcpp-body.c
              cat hcc1-blynn.c > hcc1-body.c
              printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' > hcpp-blynn.c
              cat hcpp-body.c >> hcpp-blynn.c
              printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' > hcc1-blynn.c
              cat hcc1-body.c >> hcc1-blynn.c
              echo "hcc-blynn: GCC-built M2-Mesoplanet hcpp-blynn.c -> hcpp"
              run_gcc_m2 ${m2MesoplanetGcc}/bin/M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcpp-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcpp
              echo "hcc-blynn: GCC-built M2-Mesoplanet hcc1-blynn.c -> hcc1"
              run_gcc_m2 ${m2MesoplanetGcc}/bin/M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f hcc1-blynn.c \
                -f cbits/hcc_runtime_m2.c \
                -o hcc1
              echo "hcc-blynn: GCC-built M2-Mesoplanet cbits/hcc_m1.c -> hcc-m1"
              run_gcc_m2 ${m2MesoplanetGcc}/bin/M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
                -f cbits/hcc_m1.c \
                -o hcc-m1
            '';
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by a GCC-built M2-Mesoplanet";
            metaPlatforms = [ "x86_64-linux" ];
          };
        };

        # Bootstrap path shape: hcc.<precisely-cc>.precisely.<hcc-cc>.
        # - precisely-cc: how the precisely binary was compiled.
        # - precisely: the Haskell compiler used to compile HCC's Haskell source.
        # - hcc-cc: how HCC's generated/native code becomes an executable.
        #
        # `hcc.host.ghc.native` is the dev escape hatch: no precisely stage is used,
        # and host GHC compiles HCC directly.
        hccBy = rec {
          host.ghc.native = hccHostGhcNative;

          ghc.precisely.gcc = hccFromPrecisely {
            pname = "hcc-ghc-precisely-gcc";
            generatedC = hccBlynnCBy.ghc.precisely;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GHC-built Blynn precisely debug compiler and GCC";
            };
          };

          gcc.precisely.gcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-gcc";
            generatedC = hccBlynnCBy.gcc.precisely;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and GCC";
            };
          };

          gcc.precisely.tcc = hccFromPrecisely {
            pname = "hcc-gcc-precisely-tcc";
            generatedC = hccBlynnCBy.gcc.precisely;
            cBackend = hccCBackends.tcc tinyccBy.gcc.precisely.gcc // {
              description = "HCC compiled by the GCC-built Blynn precisely compiler and HCC-built TinyCC";
            };
          };

          m2.precisely.m2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-m2";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.m2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet";
            };
          };

          m2.precisely.gcc = hccFromPrecisely {
            pname = "hcc-m2-precisely-gcc";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the stage0-built Blynn precisely and GCC";
            };
          };

          m2.precisely.gccm2 = hccFromPrecisely {
            pname = "hcc-m2-precisely-gccm2";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.gccm2 // {
              description = "HCC compiled by the stage0-built Blynn precisely and a GCC-built M2-Mesoplanet";
            };
          };
        };

        tinyccFromHccForTarget = pname: hcc: target: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          stdenvNoCC = pkgs.stdenvNoCC;
          inherit pname hcc minimalBootstrap target;
          binutils = if target == "riscv64" then pkgs.pkgsCross.riscv64.buildPackages.binutils else pkgs.binutils;
          qemu = pkgs.qemu;
          mesLibc = mesLibcSrc;
          m2libc = m2libcSrc;
        };

        tinyccFromHcc = pname: hcc: tinyccFromHccForTarget pname hcc nativeM1Target;

        tinyccM1FromHccForTarget = pname: hcc: target: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          stdenvNoCC = pkgs.stdenvNoCC;
          inherit pname hcc minimalBootstrap target;
          binutils = if target == "riscv64" then pkgs.pkgsCross.riscv64.buildPackages.binutils else pkgs.binutils;
          qemu = pkgs.qemu;
          mesLibc = mesLibcSrc;
          m2libc = m2libcSrc;
          m1ArtifactsOnly = true;
        };

        tinyccM1FromHcc = pname: hcc: tinyccM1FromHccForTarget pname hcc nativeM1Target;

        tinyccBy = {
          host.ghc.native = tinyccFromHcc "tinycc-boot-hcc-host-ghc-native" hccBy.host.ghc.native;
          riscv64.host.ghc.native =
            tinyccFromHccForTarget "tinycc-boot-hcc-host-ghc-native-riscv64" hccBy.host.ghc.native "riscv64";
          ghc.precisely.gcc = tinyccFromHcc "tinycc-boot-hcc-ghc-precisely-gcc" hccBy.ghc.precisely.gcc;
          gcc.precisely.gcc = tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-gcc" hccBy.gcc.precisely.gcc;
          gcc.precisely.tcc = tinyccFromHcc "tinycc-boot-hcc-gcc-precisely-tcc" hccBy.gcc.precisely.tcc;
          m2.precisely.m2 = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-m2" hccBy.m2.precisely.m2;
          m2.precisely.gcc = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gcc" hccBy.m2.precisely.gcc;
          m2.precisely.gccm2 = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gccm2" hccBy.m2.precisely.gccm2;
        };

        tinyccM1By = {
          host.ghc.native = tinyccM1FromHcc "tinycc-m1-hcc-host-ghc-native" hccBy.host.ghc.native;
          riscv64.host.ghc.native =
            tinyccM1FromHccForTarget "tinycc-m1-hcc-host-ghc-native-riscv64" hccBy.host.ghc.native "riscv64";
          m2.precisely.gcc = tinyccM1FromHcc "tinycc-m1-hcc-m2-precisely-gcc" hccBy.m2.precisely.gcc;
          m2.precisely.m2 = tinyccM1FromHcc "tinycc-m1-hcc-m2-precisely-m2" hccBy.m2.precisely.m2;
        };

        tinyccM1CompareNativeFaithful = pkgs.runCommand "tinycc-m1-compare-native-faithful" { } ''
          mkdir -p $out
          native=${tinyccM1By.host.ghc.native}/share/tinycc-hcc-m1
          faithful=${tinyccM1By.m2.precisely.gcc}/share/tinycc-hcc-m1
          cmp "$native/tcc.M1" "$faithful/tcc.M1"
          cmp "$native/tcc-bootstrap-support.M1" "$faithful/tcc-bootstrap-support.M1"
          cmp "$native/tcc-final-overrides.M1" "$faithful/tcc-final-overrides.M1"
          {
            echo "native:   ${tinyccM1By.host.ghc.native}"
            echo "faithful: ${tinyccM1By.m2.precisely.gcc}"
            sha256sum "$native/tcc.M1" "$faithful/tcc.M1"
            wc -c "$native/tcc.M1" "$faithful/tcc.M1"
          } > $out/summary.txt
        '';

        minimalBootstrapFromTinycc = tinycc:
          minimalBootstrap.overrideScope (final: _prev: {
            tinycc-bootstrappable = lib.recurseIntoAttrs {
              compiler = tinycc;
              libs = tinycc;
            };
            tinycc-mes = lib.recurseIntoAttrs {
              compiler = tinycc;
              libs = tinycc;
            };
            gnumake-musl = final.callPackage ./nix/minimal-bootstrap/gnumake-musl.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl;
              gawk = final.gawk-mes;
              gnumakeBoot = final.gnumake;
              nixpkgsPath = pkgs.path;
            };
            musl = final.callPackage ./nix/minimal-bootstrap/musl-gcc.nix {
              gcc = final.gcc46;
              gnumake = final.gnumake-musl;
            };
            gnused = final.callPackage ./nix/minimal-bootstrap/gnused.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl;
              gnused = final.gnused-mes;
            };
            gnutar = final.callPackage ./nix/minimal-bootstrap/gnutar.nix {
              bash = final.bash_2_05;
              gnumake = final.gnumake;
              gnused = final.gnused-mes;
              gnugrep = final.gnugrep;
              tinycc = {
                compiler = tinycc;
                libs = tinycc;
              };
            };
            musl-tcc-intermediate = final.callPackage ./nix/minimal-bootstrap/musl-tcc.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-mes;
              gnused = final.gnused-mes;
              hccTinyccVaList = true;
            };
            tinycc-musl-intermediate = lib.recurseIntoAttrs (final.callPackage ./nix/minimal-bootstrap/tinycc-musl.nix {
              stdenvNoCC = pkgs.stdenvNoCC;
              bash = final.bash_2_05;
              tinycc = final.tinycc-mes;
              musl = final.musl-tcc-intermediate;
              hccTinyccVaList = true;
            });
            musl-tcc = final.callPackage ./nix/minimal-bootstrap/musl-tcc.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl-intermediate;
              gnused = final.gnused-mes;
            };
            tinycc-musl = lib.recurseIntoAttrs (final.callPackage ./nix/minimal-bootstrap/tinycc-musl.nix {
              stdenvNoCC = pkgs.stdenvNoCC;
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl-intermediate;
              musl = final.musl-tcc;
            });
          });

        minimalBootstrapBy = {
          host.ghc.native = minimalBootstrapFromTinycc tinyccBy.host.ghc.native;
          m2.precisely.m2 = minimalBootstrapFromTinycc tinyccBy.m2.precisely.m2;
          m2.precisely.gccm2 = minimalBootstrapFromTinycc tinyccBy.m2.precisely.gccm2;
        };

        gcc46By = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.gcc46;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.gcc46;
        };

        gcc46CxxBy = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.gcc46-cxx;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.gcc46-cxx;
        };

        gcc10By = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.gcc10;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.gcc10;
        };

        gccLatestBy = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.gcc-latest;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.gcc-latest;
        };

        glibcBy = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.glibc;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.glibc;
        };

        gccGlibcBy = {
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.gcc-glibc;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.gcc-glibc;
        };

        tinyccMuslBy = {
          host.ghc.native = minimalBootstrapBy.host.ghc.native.tinycc-musl;
          m2.precisely.m2 = minimalBootstrapBy.m2.precisely.m2.tinycc-musl;
          m2.precisely.gccm2 = minimalBootstrapBy.m2.precisely.gccm2.tinycc-musl;
        };

        gnuHelloFromBootstrap = pname: bootstrap:
          pkgs.callPackage ./nix/gnu-hello-minboot.nix {
            stdenvNoCC = rawStdenvNoCC;
            buildPlatform = pkgs.stdenv.buildPlatform;
            hostPlatform = pkgs.stdenv.hostPlatform;
            inherit pname bootstrap;
          };

        gnuHelloBy = {
          host.ghc.native =
            gnuHelloFromBootstrap "gnu-hello-host-ghc-native" minimalBootstrapBy.host.ghc.native;
          m2.precisely.m2 =
            gnuHelloFromBootstrap "gnu-hello-m2-precisely-m2" minimalBootstrapBy.m2.precisely.m2;
          m2.precisely.gccm2 =
            gnuHelloFromBootstrap "gnu-hello-m2-precisely-gccm2" minimalBootstrapBy.m2.precisely.gccm2;
        };

        bootstrapBy = {
          host.ghc.native = {
            minimal = minimalBootstrapBy.host.ghc.native;
            tinycc.mes = minimalBootstrapBy.host.ghc.native.tinycc-mes;
            tinycc.musl = minimalBootstrapBy.host.ghc.native.tinycc-musl;
          };
          m2.precisely.m2 = {
            minimal = minimalBootstrapBy.m2.precisely.m2;
            tinycc.mes = minimalBootstrapBy.m2.precisely.m2.tinycc-mes;
            tinycc.musl = minimalBootstrapBy.m2.precisely.m2.tinycc-musl;
            gcc = {
              "4_6" = gcc46By.m2.precisely.m2;
              "4_6-cxx" = gcc46CxxBy.m2.precisely.m2;
              "10" = gcc10By.m2.precisely.m2;
              latest = gccLatestBy.m2.precisely.m2;
              glibc = gccGlibcBy.m2.precisely.m2;
            };
            glibc = glibcBy.m2.precisely.m2;
          };
          m2.precisely.gccm2 = {
            minimal = minimalBootstrapBy.m2.precisely.gccm2;
            tinycc.mes = minimalBootstrapBy.m2.precisely.gccm2.tinycc-mes;
            tinycc.musl = minimalBootstrapBy.m2.precisely.gccm2.tinycc-musl;
            gcc = {
              "4_6" = gcc46By.m2.precisely.gccm2;
              "4_6-cxx" = gcc46CxxBy.m2.precisely.gccm2;
              "10" = gcc10By.m2.precisely.gccm2;
              latest = gccLatestBy.m2.precisely.gccm2;
              glibc = gccGlibcBy.m2.precisely.gccm2;
            };
            glibc = glibcBy.m2.precisely.gccm2;
          };
        };

        hccM1SmokeFor = pname: hcc: target: pkgs.callPackage ./nix/hcc-m1-smoke.nix {
          stdenvNoCC = rawStdenvNoCC;
          inherit pname hcc target;
          inherit minimalBootstrap;
          m2libc = "${minimalBootstrap.stage0-posix.src}/M2libc";
        };

        hccMesccTestsFor = pname: hcc: target: pkgs.callPackage ./nix/hcc-mescc-tests.nix {
          stdenvNoCC = rawStdenvNoCC;
          inherit pname hcc target;
          inherit minimalBootstrap;
          m2libc = m2libcSrc;
          mesTests = ./tests/mescc;
        };

        hcc-m1-smoke = hccM1SmokeFor "hcc-m1-smoke" hccBy.m2.precisely.m2 "amd64";
        hcc-m1-smoke-i386 = hccM1SmokeFor "hcc-m1-smoke-i386" hccBy.m2.precisely.m2 "i386";
        hcc-m1-smoke-aarch64 = hccM1SmokeFor "hcc-m1-smoke-aarch64" hccBy.m2.precisely.m2 "aarch64";
        hcc-m1-smoke-riscv64 = hccM1SmokeFor "hcc-m1-smoke-riscv64" hccBy.m2.precisely.m2 "riscv64";
        hcc-m1-smoke-native = hccM1SmokeFor "hcc-m1-smoke-host-ghc-native" hccBy.host.ghc.native nativeM1Target;
        hcc-m1-smoke-native-aarch64 = hccM1SmokeFor "hcc-m1-smoke-host-ghc-native-aarch64" hccBy.host.ghc.native "aarch64";
        hcc-m1-smoke-native-i386 = hccM1SmokeFor "hcc-m1-smoke-host-ghc-native-i386" hccBy.host.ghc.native "i386";
        hcc-m1-smoke-native-riscv64 = hccM1SmokeFor "hcc-m1-smoke-host-ghc-native-riscv64" hccBy.host.ghc.native "riscv64";

        hcc-mescc-tests = hccMesccTestsFor "hcc-mescc-tests" hccBy.m2.precisely.m2 "amd64";
        hcc-mescc-tests-native = hccMesccTestsFor "hcc-mescc-tests-host-ghc-native" hccBy.host.ghc.native nativeM1Target;

        hcc-tinycc-tests2-stat = pkgs.callPackage ./nix/hcc-tinycc-tests2-stat.nix {
          inherit (pkgs) stdenvNoCC fetchgit python3;
          hcc = hccBy.host.ghc.native;
          inherit minimalBootstrap;
          m2libc = m2libcSrc;
          support = ./hcc/support;
          target = nativeM1Target;
        };

        precisely-dialect-tests = pkgs.callPackage ./nix/precisely-dialect-tests.nix {
          stdenv = pkgs.stdenv;
          precisely = preciselyGhcDebug;
          src = hccSrc;
          blynnSrc = blynnUpstreamSrc;
        };
      in {
        packages = {
          default = preciselyBy.m2.stage0;

          blynn = {
            compiler = blynnCompiler;
            stage = blynnRootStages;
            upstream.stage = blynnUpstreamStages;
          };

          precisely = preciselyBy;

          m2.mesoplanet.gcc = m2MesoplanetGcc;

          hcc = hccBy // {
            profile.host.ghc.native = hccProfileHostGhcNative;
            blynn = {
              sources = hccBlynnSources;
              objs = hccBlynnObjsBy;
              c = hccBlynnCBy;
            };
          };

          tinycc = tinyccBy // {
            m1 = tinyccM1By;
          };

          tinyccMusl = tinyccMuslBy;

          gcc46 = gcc46By;
          gcc46Cxx = gcc46CxxBy;
          gcc10 = gcc10By;
          gccLatest = gccLatestBy;
          gnuHello = gnuHelloBy;
          glibc = glibcBy;
          gccGlibc = gccGlibcBy;

          bootstrap = bootstrapBy;

          tests = {
            smoke.m1 = hcc-m1-smoke;
            smoke.m1-i386 = hcc-m1-smoke-i386;
            smoke.m1-aarch64 = hcc-m1-smoke-aarch64;
            smoke.m1-riscv64 = hcc-m1-smoke-riscv64;
            mescc = hcc-mescc-tests;
            host.ghc.native.smoke.m1 = hcc-m1-smoke-native;
            host.ghc.native.smoke.m1-i386 = hcc-m1-smoke-native-i386;
            host.ghc.native.smoke.m1-aarch64 = hcc-m1-smoke-native-aarch64;
            host.ghc.native.smoke.m1-riscv64 = hcc-m1-smoke-native-riscv64;
            host.ghc.native.mescc = hcc-mescc-tests-native;
            hcc.tinycc-tests2-stat = hcc-tinycc-tests2-stat;
            host.ghc.native.tinycc-riscv64 = tinyccBy.riscv64.host.ghc.native;
            precisely.dialect = precisely-dialect-tests;
            tinyccM1.native-vs-faithful = tinyccM1CompareNativeFaithful;
          };
        };

        apps.blynn-precisely-gcc = {
          type = "app";
          program = "${preciselyGccHost}/bin/precisely_up";
        };

        apps.blynn-precisely-debug-ghc = {
          type = "app";
          program = "${preciselyGhcDebug}/bin/precisely_up";
        };

        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          packages = [
            minimalBootstrap.stage0-posix.mescc-tools
            pkgs.coreutils
            pkgs.gcc
            pkgs.jq
            pkgs.time
            preciselyGhcDebug
            hccBy.host.ghc.native
            hccProfileHostGhcNative
            hccBy.ghc.precisely.gcc
            hccBy.gcc.precisely.gcc
            (pkgs.haskellPackages.ghcWithPackages (hpkgs: [
              hpkgs.raw-strings-qq
            ]))
          ];
          shellHook = ''
            echo "blynn-bootstrap dev shell - upstreams are fetched and patched by flake.nix"
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
