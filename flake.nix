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
        mzvmSrc = ./mzvm;
        mlcSrc = ./mlc;
        cccSrc = ./ccc;
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
          let
            libcSources = builtins.filter (rel:
              !(builtins.elem rel [
                "lib/mes/abtod.c"
                "lib/stdlib/strtod.c"
                "lib/stdlib/strtof.c"
                "lib/stdlib/strtold.c"
                "lib/stub/ldexp.c"
              ])) mesLibcSources.libc_gnu_SOURCES;
          in
          map (rel: "$out/${rel}") (lib.take 100 libcSources)
          ++ [
            "${./nix/sources/mes-libc/strtod.c}"
            "${./nix/sources/mes-libc/ldexp-ldexpl.c}"
          ]
          ++ map (rel: "$out/${rel}") (lib.drop 100 libcSources);
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
            (upstreamPatches + "/blynn-compiler-crossly-perf.patch")
            (upstreamPatches + "/blynn-compiler-rts2-vm-speed.patch")
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
        minimalShell = pkgs.callPackage ./nix/minimal-shell.nix {
          stdenvNoCC = pkgs.stdenvNoCC;
        };
        rawDerivation = import ./nix/raw-mk-derivation.nix {
          inherit lib system;
          bootstrapShell = minimalShell;
          inherit (pkgs)
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
              ${prev}/bin/${prevBin} < ${name}.input.hs > ${name}.c
            ''}
            ${lib.optionalString (top != null) ''
              substituteInPlace ${name}.c \
                --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString top}};' \
                --replace-fail 'enum{TOP=16777216,' 'enum{TOP=${toString top},'
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

        blynnPhaseBin = rawStdenvNoCC.mkDerivation {
          pname = "blynn-phase-bin";
          version = "0-unstable-2026-05-06";
          dontUnpack = true;
          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;
          dontFixup = true;
          dontPatchELF = true;
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/share/blynn-phase-bin"
            install -Dm555 ${blynnUpstreamStages.party}/bin/party "$out/bin/party"
            install -Dm555 ${blynnUpstreamStages.multiparty}/bin/multiparty "$out/bin/multiparty"
            install -Dm555 ${blynnUpstreamStages.party1}/bin/party1 "$out/bin/party1"
            install -Dm555 ${blynnUpstreamStages.party2}/bin/party2 "$out/bin/party2"
            install -Dm555 ${blynnUpstreamStages.crossly_up}/bin/crossly_up "$out/bin/crossly_up"
            install -Dm555 ${blynnUpstreamStages.crossly1}/bin/crossly1 "$out/bin/crossly1"
            cp ${blynnShare blynnUpstreamStages.party "party.c"} "$out/share/blynn-phase-bin/party.c"
            cp ${blynnShare blynnUpstreamStages.multiparty "multiparty.c"} "$out/share/blynn-phase-bin/multiparty.c"
            cp ${blynnShare blynnUpstreamStages.party1 "party1.c"} "$out/share/blynn-phase-bin/party1.c"
            cp ${blynnShare blynnUpstreamStages.party2 "party2.c"} "$out/share/blynn-phase-bin/party2.c"
            cp ${blynnShare blynnUpstreamStages.crossly_up "crossly_up.c"} "$out/share/blynn-phase-bin/crossly_up.c"
            cp ${blynnShare blynnUpstreamStages.crossly1 "crossly1.c"} "$out/share/blynn-phase-bin/crossly1.c"
            runHook postInstall
          '';
        };

        preciselyGcc = pname: preciselyStage: shareName: description:
        rawStdenvCC.mkDerivation {
          inherit pname;
          version = "0-unstable-2026-05-06";

          dontUnpack = true;
          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;

          buildPhase = ''
            runHook preBuild
            sed -E 's/enum\{TOP=[0-9]+\};/enum{TOP=33554432};/' \
              ${blynnShare preciselyStage "precisely_up.c"} > precisely_up.c
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
          blynnUpstreamStages.precisely_up
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

        mzvmHost = pkgs.stdenv.mkDerivation {
          pname = "mzvm-host";
          version = "0-unstable-2026-05-06";
          src = mzvmSrc;

          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;

          buildPhase = ''
            runHook preBuild
            $CC -O2 -Wall -Wextra mzvm.c -o mzvm
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            sh ${./scripts/mzvm-write-ok-bytecode.sh} ok.mzbc
            ./mzvm ok.mzbc > actual.txt
            printf 'OK\n' > expected.txt
            cmp expected.txt actual.txt
            $CC -O2 -Wall -Wextra -DMZVM_HEAP_LIMIT=16 mzvm.c -o mzvm-gc
            sh ${./scripts/mzvm-write-gc-bytecode.sh} gc.mzbc
            ./mzvm-gc gc.mzbc > gc-actual.txt
            cmp expected.txt gc-actual.txt
            sh ${./scripts/mzvm-write-signed-bytecode.sh} signed.mzbc
            ./mzvm signed.mzbc > signed-actual.txt
            cmp expected.txt signed-actual.txt
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 mzvm "$out/bin/mzvm"
            install -Dm644 mzvm.c "$out/share/mzvm/mzvm.c"
            install -Dm644 mzvm-seed.c "$out/share/mzvm/mzvm-seed.c"
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Host-built development ZINC-style VM for CCC bootstrap bytecode";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
          };
        };

        mzvmSeedM2 = stageRun {
          pname = "mzvm-seed-m2";
          nativeBuildInputs = [
            minimalBootstrap.stage0-posix.mescc-tools
          ];
          description = "M2-Planet-built seed ZINC-style VM for CCC bootstrap bytecode";
          buildScript = ''
            . ${./scripts/lib/bootstrap.sh}
            cp ${mzvmSrc}/mzvm-seed.c mzvm-seed.c
            compile_m2 mzvm-seed.c mzvm-seed
            printf '%b' '\115\132\102\103\001\000\000\000\060\000\000\000\003\000\000\000\000\000\000\000' > ok.mzbc
            printf '%b' '\001\117\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
            printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
            printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
            printf '%b' '\001\000\000\000\000\000' >> ok.mzbc
            ./mzvm-seed ok.mzbc > actual.txt
            IFS= read -r actual < actual.txt
            test "$actual" = OK
            printf '%b' '\115\132\102\103\001\000\000\000\143\000\000\000\003\000\000\000\000\000\000\000' > block.mzbc
            printf '%b' '\001\117\000\000\000\017\001\000\000\000\001\000\000\000\022\002\001\001\000\000\000\011\015\053\000\000\000' >> block.mzbc
            printf '%b' '\001\117\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
            printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
            printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> block.mzbc
            printf '%b' '\001\130\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
            printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> block.mzbc
            ./mzvm-seed block.mzbc > actual.txt
            IFS= read -r actual < actual.txt
            test "$actual" = OK
            printf '%b' '\115\132\102\103\001\000\000\000\106\000\000\000\003\000\000\000\000\000\000\000' > signed.mzbc
            printf '%b' '\001\377\377\377\377\002\001\000\000\000\000\012\015\012\000\000\000' >> signed.mzbc
            printf '%b' '\001\117\000\000\000\013\005\000\000\000\001\130\000\000\000' >> signed.mzbc
            printf '%b' '\016\001\000\000\000\001\000\000\000' >> signed.mzbc
            printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> signed.mzbc
            printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> signed.mzbc
            ./mzvm-seed signed.mzbc > actual.txt
            IFS= read -r actual < actual.txt
            test "$actual" = OK
          '';
          installScript = ''
            install -Dm755 mzvm-seed "$out/bin/mzvm-seed"
            install -Dm644 mzvm-seed.c "$out/share/mzvm/mzvm-seed.c"
            install -Dm644 ok.mzbc "$out/share/mzvm/tests/ok.mzbc"
            install -Dm644 block.mzbc "$out/share/mzvm/tests/block.mzbc"
            install -Dm644 signed.mzbc "$out/share/mzvm/tests/signed.mzbc"
          '';
        };

        mzvmHostVsSeed = pkgs.runCommand "mzvm-host-vs-seed" { } ''
          sh ${./scripts/mzvm-write-ok-bytecode.sh} ok.mzbc
          ${mzvmHost}/bin/mzvm ok.mzbc > host.txt
          ${mzvmSeedM2}/bin/mzvm-seed ok.mzbc > seed.txt
          cmp host.txt seed.txt
          printf 'OK\n' > expected.txt
          cmp expected.txt host.txt
          sh ${./scripts/mzvm-write-block-bytecode.sh} block.mzbc
          ${mzvmHost}/bin/mzvm block.mzbc > host-block.txt
          ${mzvmSeedM2}/bin/mzvm-seed block.mzbc > seed-block.txt
          cmp host-block.txt seed-block.txt
          cmp expected.txt host-block.txt
          sh ${./scripts/mzvm-write-signed-bytecode.sh} signed.mzbc
          ${mzvmHost}/bin/mzvm signed.mzbc > host-signed.txt
          ${mzvmSeedM2}/bin/mzvm-seed signed.mzbc > seed-signed.txt
          cmp host-signed.txt seed-signed.txt
          cmp expected.txt host-signed.txt
          install -Dm644 host.txt "$out/ok-output.txt"
          install -Dm644 host-block.txt "$out/block-output.txt"
          install -Dm644 host-signed.txt "$out/signed-output.txt"
        '';

        mlcFixtures = [
          "ok"
          "arithmetic"
          "conditional"
          "comparison"
          "negative"
          "let-binding"
          "array"
          "bytes"
          "string-value"
          "dynamic-index"
          "dynamic-create"
          "length"
          "function"
          "function-tuple"
          "function-nested"
          "function-string"
          "function-and"
          "identifiers"
          "string"
          "exit"
          "tuple"
          "sequence"
        ];
        mlcInputFixtures = [
          "read-byte"
        ];

        mlcInterpSeedHost = pkgs.stdenv.mkDerivation {
          pname = "mlc-interp-seed-host";
          version = "0-unstable-2026-05-17";
          src = mlcSrc;

          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;

          buildPhase = ''
            runHook preBuild
            $CC -O2 -Wall -Wextra mlc-interp-seed.c -o mlc-interp-seed
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            ./mlc-interp-seed stages/00-core.ml > 00-core.out
            printf 'OOK\n' > 00-core.expected
            cmp 00-core.expected 00-core.out
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 mlc-interp-seed "$out/bin/mlc-interp-seed"
            install -Dm644 mlc-interp-seed.c "$out/share/mlc/mlc-interp-seed.c"
            install -Dm644 stages/00-core.ml "$out/share/mlc/stages/00-core.ml"
            install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Host-built tree-walking mini-OCaml bootstrap interpreter";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
          };
        };

        mlcInterpSeedM2 = stageRun {
          pname = "mlc-interp-seed-m2";
          nativeBuildInputs = [
            minimalBootstrap.stage0-posix.mescc-tools
          ];
          description = "M2-Planet-built tree-walking mini-OCaml bootstrap interpreter";
          buildScript = ''
            . ${./scripts/lib/bootstrap.sh}
            cp ${mlcSrc}/mlc-interp-seed.c mlc-interp-seed.c
            cp ${mlcSrc}/stages/00-core.ml 00-core.ml
            compile_m2 mlc-interp-seed.c mlc-interp-seed
            actual="$(./mlc-interp-seed 00-core.ml)"
            test "$actual" = OOK
            ./mlc-interp-seed 00-core.ml > 00-core.out
          '';
          installScript = ''
            install -Dm755 mlc-interp-seed "$out/bin/mlc-interp-seed"
            install -Dm644 mlc-interp-seed.c "$out/share/mlc/mlc-interp-seed.c"
            install -Dm644 00-core.ml "$out/share/mlc/stages/00-core.ml"
            install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
          '';
        };

        mlcInterpSeedHostVsM2 = pkgs.runCommand "mlc-interp-seed-host-vs-m2" { } ''
          cmp ${mlcInterpSeedHost}/share/mlc/stages/00-core.out ${mlcInterpSeedM2}/share/mlc/stages/00-core.out
          install -Dm644 ${mlcInterpSeedHost}/share/mlc/stages/00-core.out "$out/00-core.out"
        '';

        mlcStage00Core = stageRun {
          pname = "mlc-stage-00-core";
          nativeBuildInputs = [
            mlcInterpSeedM2
          ];
          description = "First named MLC core-language bootstrap stage";
          buildScript = ''
            cp ${mlcSrc}/stages/00-core.ml 00-core.ml
            actual="$(${mlcInterpSeedM2}/bin/mlc-interp-seed 00-core.ml)"
            test "$actual" = OOK
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 00-core.ml > 00-core.out
          '';
          installScript = ''
            install -Dm644 00-core.ml "$out/share/mlc/stages/00-core.ml"
            install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
          '';
        };

        mlcStage01Parenthetical = stageRun {
          pname = "mlc-stage-01-parenthetical";
          nativeBuildInputs = [
            mlcInterpSeedM2
            mzvmSeedM2
          ];
          description = "First MLC handoff stage: parenthesized MZBC assembly to bytecode";
          buildScript = ''
            cp ${mlcSrc}/stages/01-parenthetical.ml 01-parenthetical.ml
            cp ${mlcSrc}/stages/02-ok.mzp 02-ok.mzp
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 01-parenthetical.ml < 02-ok.mzp > 02-ok.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed 02-ok.mzbc)"
            test "$actual" = OK
          '';
          installScript = ''
            install -Dm644 01-parenthetical.ml "$out/share/mlc/stages/01-parenthetical.ml"
            install -Dm644 02-ok.mzp "$out/share/mlc/stages/02-ok.mzp"
            install -Dm644 02-ok.mzbc "$out/share/mlc/stages/02-ok.mzbc"
          '';
        };

        mlcStage02Ml0Compiler = stageRun {
          pname = "mlc-stage-02-ml0-compiler";
          nativeBuildInputs = [
            mlcInterpSeedM2
            mzvmSeedM2
          ];
          description = "First MLC stage that compiles an ML source subset to MZBC";
          buildScript = ''
            ulimit -s unlimited || true
            cp ${mlcSrc}/stages/02-ml0-compiler.ml 02-ml0-compiler.ml
            cp ${mlcSrc}/stages/03-ok.ml0 03-ok.ml0
            cp ${mlcSrc}/stages/03-char-string.ml0 03-char-string.ml0
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 03-ok.ml0 > 03-ok.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-ok.mzbc)"
            test "$actual" = OK
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 03-char-string.ml0 > 03-char-string.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed 03-char-string.mzbc)"
            test "$actual" = OK
            printf 'let f = fun x -> write_byte x in f 79' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed closure.mzbc > closure.out
            printf 'let f = fun x -> let f2 = fun y -> write_byte (x + y) in f2 39 in f 40' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure-capture.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed closure-capture.mzbc > closure-capture.out
            printf 'let f = fun x -> write_byte x in let elsewhere = 79 in let thenable = 75 in let input = 10 in let _ = f elsewhere in let _ = f thenable in f input' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > closure-lookahead.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed closure-lookahead.mzbc > closure-lookahead.out
            printf 'let rec k x = x in let rec apply f = fun x -> f x in write_byte (apply k 79)' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > function-value.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed function-value.mzbc > function-value.out
            printf 'let x = 79 in let rec f y = write_byte (x + y) in f 0' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > letrec-capture.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed letrec-capture.mzbc > letrec-capture.out
            printf 'let rec f ch = if ch = 79 then write_byte ch else write_byte 88 in f 79' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > single-eq.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed single-eq.mzbc > single-eq.out
            printf 'write_byte -1' | ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml > negative-immediate.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed negative-immediate.mzbc > negative-immediate.out
            for name in ok arithmetic conditional comparison let-binding sequence negative identifiers keyword-prefix-infix string string-value length exit tuple bytes array dynamic-create dynamic-index function function-tuple function-nested function-string; do
              ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${./tests/mlc}/$name.ml > $name.mzbc
              ${mzvmSeedM2}/bin/mzvm-seed $name.mzbc > $name.out
            done
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${./tests/mlc}/read-byte.ml > read-byte.mzbc
            printf O | ${mzvmSeedM2}/bin/mzvm-seed read-byte.mzbc > read-byte.out
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < ${mlcSrc}/mlc.ml > mlc-stage.mzbc
            printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-compiled.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-compiled.mzbc > mlc-stage.out
            printf "write_byte 'O'" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-char.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-char.mzbc > mlc-stage-char.out
            printf 'write_string "OK"' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-string.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-string.mzbc > mlc-stage-string.out
            printf 'let x = 40 in write_byte (x + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let.mzbc > mlc-stage-let.out
            printf 'let x = 40 in let y = 39 in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let2.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let2.mzbc > mlc-stage-let2.out
            printf 'let x = 40 in let y = 20 in let z = 19 in write_byte (x + y + z)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-let3.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-let3.mzbc > mlc-stage-let3.out
            printf 'let x = (40 + 39) in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-paren-let.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-paren-let.mzbc > mlc-stage-paren-let.out
            printf 'let x = 88 in let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-shadow.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-shadow.mzbc > mlc-stage-shadow.out
            printf 'write_byte (80 - 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-sub.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-sub.mzbc > mlc-stage-sub.out
            printf 'write_byte (79 * 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-mul.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-mul.mzbc > mlc-stage-mul.out
            printf 'write_byte (158 / 2)' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-div.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-div.mzbc > mlc-stage-div.out
            printf "write_byte (if 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-true.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-true.mzbc > mlc-stage-if-true.out
            printf "write_byte (if 0 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-false.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-false.mzbc > mlc-stage-if-false.out
            printf "write_byte (if 40 < 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-lt-true.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-lt-true.mzbc > mlc-stage-if-lt-true.out
            printf "write_byte (if 41 < 40 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-lt-false.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-lt-false.mzbc > mlc-stage-if-lt-false.out
            printf "write_byte (if 40 == 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-eq-true.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-eq-true.mzbc > mlc-stage-if-eq-true.out
            printf "write_byte (if 40 == 41 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-eq-false.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-eq-false.mzbc > mlc-stage-if-eq-false.out
            printf "write_byte (if 40 != 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-ne.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-ne.mzbc > mlc-stage-if-ne.out
            printf "write_byte (if 40 <= 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-le.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-le.mzbc > mlc-stage-if-le.out
            printf "write_byte (if 41 > 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-gt.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-gt.mzbc > mlc-stage-if-gt.out
            printf "write_byte (if 41 >= 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage.mzbc > mlc-stage-if-ge.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-if-ge.mzbc > mlc-stage-if-ge.out
            ${mlcInterpSeedM2}/bin/mlc-interp-seed 02-ml0-compiler.ml < 02-ml0-compiler.ml > 02-self.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed 02-self.mzbc < 02-ml0-compiler.ml > 02-self-again.mzbc
            printf 'write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed 02-self-again.mzbc > 02-self-smoke.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed 02-self-smoke.mzbc > 02-self-smoke.out
            ${mzvmSeedM2}/bin/mzvm-seed 02-self.mzbc < ${mlcSrc}/mlc.ml > mlc-stage-from-02-self.mzbc
            printf 'write_byte 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-from-02-self.mzbc > mlc-stage-from-02-self-smoke.mzbc
            ${mzvmSeedM2}/bin/mzvm-seed mlc-stage-from-02-self-smoke.mzbc > mlc-stage-from-02-self-smoke.out
            test "$(cat ok.out)" = OK
            test "$(cat arithmetic.out)" = H-
            test "$(cat conditional.out)" = OK
            test "$(cat comparison.out)" = "OK
OK"
            test "$(cat let-binding.out)" = OK
            test "$(cat closure.out)" = O
            test "$(cat closure-capture.out)" = O
            test "$(cat closure-lookahead.out)" = "OK"
            test "$(cat function-value.out)" = O
            test "$(cat letrec-capture.out)" = O
            test "$(cat single-eq.out)" = O
            printf '\377' > negative-immediate.expected
            test "$(cat negative-immediate.out)" = "$(cat negative-immediate.expected)"
            test "$(cat sequence.out)" = OK
            test "$(cat negative.out)" = OK
            test "$(cat identifiers.out)" = O
            test "$(cat keyword-prefix-infix.out)" = O
            test "$(cat string.out)" = "O	K"
            test "$(cat string-value.out)" = OK
            test "$(cat length.out)" = OK
            test "$(cat exit.out)" = OK
            test "$(cat tuple.out)" = OK
            test "$(cat bytes.out)" = OK
            test "$(cat array.out)" = OK
            test "$(cat dynamic-create.out)" = OK
            test "$(cat dynamic-index.out)" = OK
            test "$(cat function.out)" = OK
            test "$(cat function-tuple.out)" = OK
            test "$(cat function-nested.out)" = OK
            test "$(cat function-string.out)" = OK
            test "$(cat read-byte.out)" = OK
            test "$(cat mlc-stage.out)" = O
            test "$(cat mlc-stage-char.out)" = O
            test "$(cat mlc-stage-string.out)" = OK
            test "$(cat mlc-stage-let.out)" = O
            test "$(cat mlc-stage-let2.out)" = O
            test "$(cat mlc-stage-let3.out)" = O
            test "$(cat mlc-stage-paren-let.out)" = O
            test "$(cat mlc-stage-shadow.out)" = O
            test "$(cat mlc-stage-sub.out)" = O
            test "$(cat mlc-stage-mul.out)" = O
            test "$(cat mlc-stage-div.out)" = O
            test "$(cat mlc-stage-if-true.out)" = O
            test "$(cat mlc-stage-if-false.out)" = O
            test "$(cat mlc-stage-if-lt-true.out)" = O
            test "$(cat mlc-stage-if-lt-false.out)" = O
            test "$(cat mlc-stage-if-eq-true.out)" = O
            test "$(cat mlc-stage-if-eq-false.out)" = O
            test "$(cat mlc-stage-if-ne.out)" = O
            test "$(cat mlc-stage-if-le.out)" = O
            test "$(cat mlc-stage-if-gt.out)" = O
            test "$(cat mlc-stage-if-ge.out)" = O
            test "$(cat 02-self-smoke.out)" = O
            test "$(cat mlc-stage-from-02-self-smoke.out)" = O
          '';
          installScript = ''
            install -Dm644 02-ml0-compiler.ml "$out/share/mlc/stages/02-ml0-compiler.ml"
            install -Dm644 03-ok.ml0 "$out/share/mlc/stages/03-ok.ml0"
            install -Dm644 03-char-string.ml0 "$out/share/mlc/stages/03-char-string.ml0"
            install -Dm644 03-ok.mzbc "$out/share/mlc/stages/03-ok.mzbc"
            install -Dm644 03-char-string.mzbc "$out/share/mlc/stages/03-char-string.mzbc"
            install -Dm644 closure.mzbc "$out/share/mlc/stages/closure.mzbc"
            install -Dm644 closure.out "$out/share/mlc/stages/closure.out"
            install -Dm644 closure-capture.mzbc "$out/share/mlc/stages/closure-capture.mzbc"
            install -Dm644 closure-capture.out "$out/share/mlc/stages/closure-capture.out"
            install -Dm644 closure-lookahead.mzbc "$out/share/mlc/stages/closure-lookahead.mzbc"
            install -Dm644 closure-lookahead.out "$out/share/mlc/stages/closure-lookahead.out"
            install -Dm644 function-value.mzbc "$out/share/mlc/stages/function-value.mzbc"
            install -Dm644 function-value.out "$out/share/mlc/stages/function-value.out"
            install -Dm644 letrec-capture.mzbc "$out/share/mlc/stages/letrec-capture.mzbc"
            install -Dm644 letrec-capture.out "$out/share/mlc/stages/letrec-capture.out"
            install -Dm644 single-eq.mzbc "$out/share/mlc/stages/single-eq.mzbc"
            install -Dm644 single-eq.out "$out/share/mlc/stages/single-eq.out"
            install -Dm644 negative-immediate.mzbc "$out/share/mlc/stages/negative-immediate.mzbc"
            install -Dm644 negative-immediate.out "$out/share/mlc/stages/negative-immediate.out"
            install -Dm644 02-self.mzbc "$out/share/mlc/stages/02-self.mzbc"
            install -Dm644 02-self-again.mzbc "$out/share/mlc/stages/02-self-again.mzbc"
            install -Dm644 02-self-smoke.mzbc "$out/share/mlc/stages/02-self-smoke.mzbc"
            install -Dm644 02-self-smoke.out "$out/share/mlc/stages/02-self-smoke.out"
            install -Dm644 mlc-stage-from-02-self.mzbc "$out/share/mlc/stages/mlc-stage-from-02-self.mzbc"
            install -Dm644 mlc-stage-from-02-self-smoke.mzbc "$out/share/mlc/stages/mlc-stage-from-02-self-smoke.mzbc"
            install -Dm644 mlc-stage-from-02-self-smoke.out "$out/share/mlc/stages/mlc-stage-from-02-self-smoke.out"
            install -Dm644 string-value.mzbc "$out/share/mlc/stages/string-value.mzbc"
            install -Dm644 length.mzbc "$out/share/mlc/stages/length.mzbc"
            install -Dm644 keyword-prefix-infix.mzbc "$out/share/mlc/stages/keyword-prefix-infix.mzbc"
            install -Dm644 read-byte.mzbc "$out/share/mlc/stages/read-byte.mzbc"
            install -Dm644 exit.mzbc "$out/share/mlc/stages/exit.mzbc"
            install -Dm644 tuple.mzbc "$out/share/mlc/stages/tuple.mzbc"
            install -Dm644 bytes.mzbc "$out/share/mlc/stages/bytes.mzbc"
            install -Dm644 array.mzbc "$out/share/mlc/stages/array.mzbc"
            install -Dm644 dynamic-create.mzbc "$out/share/mlc/stages/dynamic-create.mzbc"
            install -Dm644 dynamic-index.mzbc "$out/share/mlc/stages/dynamic-index.mzbc"
            install -Dm644 function.mzbc "$out/share/mlc/stages/function.mzbc"
            install -Dm644 function-tuple.mzbc "$out/share/mlc/stages/function-tuple.mzbc"
            install -Dm644 function-nested.mzbc "$out/share/mlc/stages/function-nested.mzbc"
            install -Dm644 function-string.mzbc "$out/share/mlc/stages/function-string.mzbc"
            install -Dm644 mlc-stage.mzbc "$out/share/mlc/stages/mlc-stage.mzbc"
            install -Dm644 mlc-stage-compiled.mzbc "$out/share/mlc/stages/mlc-stage-compiled.mzbc"
            install -Dm644 mlc-stage.out "$out/share/mlc/stages/mlc-stage.out"
            install -Dm644 mlc-stage-char.mzbc "$out/share/mlc/stages/mlc-stage-char.mzbc"
            install -Dm644 mlc-stage-char.out "$out/share/mlc/stages/mlc-stage-char.out"
            install -Dm644 mlc-stage-string.mzbc "$out/share/mlc/stages/mlc-stage-string.mzbc"
            install -Dm644 mlc-stage-string.out "$out/share/mlc/stages/mlc-stage-string.out"
            install -Dm644 mlc-stage-let.mzbc "$out/share/mlc/stages/mlc-stage-let.mzbc"
            install -Dm644 mlc-stage-let.out "$out/share/mlc/stages/mlc-stage-let.out"
            install -Dm644 mlc-stage-let2.mzbc "$out/share/mlc/stages/mlc-stage-let2.mzbc"
            install -Dm644 mlc-stage-let2.out "$out/share/mlc/stages/mlc-stage-let2.out"
            install -Dm644 mlc-stage-let3.mzbc "$out/share/mlc/stages/mlc-stage-let3.mzbc"
            install -Dm644 mlc-stage-let3.out "$out/share/mlc/stages/mlc-stage-let3.out"
            install -Dm644 mlc-stage-paren-let.mzbc "$out/share/mlc/stages/mlc-stage-paren-let.mzbc"
            install -Dm644 mlc-stage-paren-let.out "$out/share/mlc/stages/mlc-stage-paren-let.out"
            install -Dm644 mlc-stage-shadow.mzbc "$out/share/mlc/stages/mlc-stage-shadow.mzbc"
            install -Dm644 mlc-stage-shadow.out "$out/share/mlc/stages/mlc-stage-shadow.out"
            install -Dm644 mlc-stage-sub.mzbc "$out/share/mlc/stages/mlc-stage-sub.mzbc"
            install -Dm644 mlc-stage-sub.out "$out/share/mlc/stages/mlc-stage-sub.out"
            install -Dm644 mlc-stage-mul.mzbc "$out/share/mlc/stages/mlc-stage-mul.mzbc"
            install -Dm644 mlc-stage-mul.out "$out/share/mlc/stages/mlc-stage-mul.out"
            install -Dm644 mlc-stage-div.mzbc "$out/share/mlc/stages/mlc-stage-div.mzbc"
            install -Dm644 mlc-stage-div.out "$out/share/mlc/stages/mlc-stage-div.out"
            install -Dm644 mlc-stage-if-true.mzbc "$out/share/mlc/stages/mlc-stage-if-true.mzbc"
            install -Dm644 mlc-stage-if-true.out "$out/share/mlc/stages/mlc-stage-if-true.out"
            install -Dm644 mlc-stage-if-false.mzbc "$out/share/mlc/stages/mlc-stage-if-false.mzbc"
            install -Dm644 mlc-stage-if-false.out "$out/share/mlc/stages/mlc-stage-if-false.out"
            install -Dm644 mlc-stage-if-lt-true.mzbc "$out/share/mlc/stages/mlc-stage-if-lt-true.mzbc"
            install -Dm644 mlc-stage-if-lt-true.out "$out/share/mlc/stages/mlc-stage-if-lt-true.out"
            install -Dm644 mlc-stage-if-lt-false.mzbc "$out/share/mlc/stages/mlc-stage-if-lt-false.mzbc"
            install -Dm644 mlc-stage-if-lt-false.out "$out/share/mlc/stages/mlc-stage-if-lt-false.out"
            install -Dm644 mlc-stage-if-eq-true.mzbc "$out/share/mlc/stages/mlc-stage-if-eq-true.mzbc"
            install -Dm644 mlc-stage-if-eq-true.out "$out/share/mlc/stages/mlc-stage-if-eq-true.out"
            install -Dm644 mlc-stage-if-eq-false.mzbc "$out/share/mlc/stages/mlc-stage-if-eq-false.mzbc"
            install -Dm644 mlc-stage-if-eq-false.out "$out/share/mlc/stages/mlc-stage-if-eq-false.out"
            install -Dm644 mlc-stage-if-ne.mzbc "$out/share/mlc/stages/mlc-stage-if-ne.mzbc"
            install -Dm644 mlc-stage-if-ne.out "$out/share/mlc/stages/mlc-stage-if-ne.out"
            install -Dm644 mlc-stage-if-le.mzbc "$out/share/mlc/stages/mlc-stage-if-le.mzbc"
            install -Dm644 mlc-stage-if-le.out "$out/share/mlc/stages/mlc-stage-if-le.out"
            install -Dm644 mlc-stage-if-gt.mzbc "$out/share/mlc/stages/mlc-stage-if-gt.mzbc"
            install -Dm644 mlc-stage-if-gt.out "$out/share/mlc/stages/mlc-stage-if-gt.out"
            install -Dm644 mlc-stage-if-ge.mzbc "$out/share/mlc/stages/mlc-stage-if-ge.mzbc"
            install -Dm644 mlc-stage-if-ge.out "$out/share/mlc/stages/mlc-stage-if-ge.out"
          '';
        };

        mlcSeedHost = pkgs.stdenv.mkDerivation {
          pname = "mlc-seed-host";
          version = "0-unstable-2026-05-06";
          src = mlcSrc;

          dontConfigure = true;
          dontUpdateAutotoolsGnuConfigScripts = true;

          buildPhase = ''
            runHook preBuild
            $CC -O2 -Wall -Wextra mlc-seed.c -o mlc-seed
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            for name in ${lib.concatStringsSep " " mlcFixtures}; do
              ./mlc-seed ${./tests/mlc}/$name.ml $name.mzbc
              ${mzvmHost}/bin/mzvm $name.mzbc > $name.out
            done
            for name in ${lib.concatStringsSep " " mlcInputFixtures}; do
              ./mlc-seed ${./tests/mlc}/$name.ml $name.mzbc
            done
            printf 'O' | ${mzvmHost}/bin/mzvm read-byte.mzbc > read-byte.out
            printf 'OK\n' > ok.expected
            printf 'H-\n' > arithmetic.expected
            printf 'OK\n' > conditional.expected
            printf 'OK\nOK\n' > comparison.expected
            printf 'OK\n' > negative.expected
            printf 'OK\n' > let-binding.expected
            printf 'OK\n' > array.expected
            printf 'OK\n' > bytes.expected
            printf 'OK\n' > string-value.expected
            printf 'OK\n' > dynamic-index.expected
            printf 'OK\n' > dynamic-create.expected
            printf 'OK\n' > length.expected
            printf 'OK\n' > function.expected
            printf 'OK\n' > function-tuple.expected
            printf 'OK\n' > function-nested.expected
            printf 'OK\n' > function-string.expected
            printf 'OK\n' > function-and.expected
            printf 'O\n' > identifiers.expected
            printf 'O\tK\n' > string.expected
            printf 'OK\n' > exit.expected
            printf 'OK\n' > tuple.expected
            printf 'OK\n' > sequence.expected
            printf 'OK\n' > read-byte.expected
            for name in ${lib.concatStringsSep " " mlcFixtures}; do
              cmp $name.expected $name.out
            done
            cmp read-byte.expected read-byte.out
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 mlc-seed "$out/bin/mlc-seed"
            install -Dm644 mlc-seed.c "$out/share/mlc/mlc-seed.c"
            for name in ${lib.concatStringsSep " " mlcFixtures}; do
              install -Dm644 $name.mzbc "$out/share/mlc/tests/$name.mzbc"
            done
            install -Dm644 read-byte.mzbc "$out/share/mlc/tests/read-byte.mzbc"
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Host-built seed mini-OCaml compiler for CCC bootstrap bytecode";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
          };
        };

        mlcSeedM2 = stageRun {
          pname = "mlc-seed-m2";
          nativeBuildInputs = [
            minimalBootstrap.stage0-posix.mescc-tools
          ];
          description = "M2-Planet-built seed mini-OCaml compiler for CCC bootstrap bytecode";
          buildScript = ''
            . ${./scripts/lib/bootstrap.sh}
            cp ${mlcSrc}/mlc-seed.c mlc-seed.c
            cp ${./tests/mlc/ok.ml} ok.ml
            cp ${./tests/mlc/arithmetic.ml} arithmetic.ml
            cp ${./tests/mlc/conditional.ml} conditional.ml
            cp ${./tests/mlc/comparison.ml} comparison.ml
            cp ${./tests/mlc/negative.ml} negative.ml
            cp ${./tests/mlc/let-binding.ml} let-binding.ml
            cp ${./tests/mlc/array.ml} array.ml
            cp ${./tests/mlc/bytes.ml} bytes.ml
            cp ${./tests/mlc/string-value.ml} string-value.ml
            cp ${./tests/mlc/dynamic-index.ml} dynamic-index.ml
            cp ${./tests/mlc/dynamic-create.ml} dynamic-create.ml
            cp ${./tests/mlc/length.ml} length.ml
            cp ${./tests/mlc/function.ml} function.ml
            cp ${./tests/mlc/function-tuple.ml} function-tuple.ml
            cp ${./tests/mlc/function-nested.ml} function-nested.ml
            cp ${./tests/mlc/function-string.ml} function-string.ml
            cp ${./tests/mlc/function-and.ml} function-and.ml
            cp ${./tests/mlc/identifiers.ml} identifiers.ml
            cp ${./tests/mlc/string.ml} string.ml
            cp ${./tests/mlc/exit.ml} exit.ml
            cp ${./tests/mlc/tuple.ml} tuple.ml
            cp ${./tests/mlc/sequence.ml} sequence.ml
            cp ${./tests/mlc/read-byte.ml} read-byte.ml
            compile_m2 mlc-seed.c mlc-seed
            ./mlc-seed ok.ml ok.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed ok.mzbc)"
            test "$actual" = OK
            ./mlc-seed arithmetic.ml arithmetic.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed arithmetic.mzbc)"
            test "$actual" = H-
            ./mlc-seed conditional.ml conditional.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed conditional.mzbc)"
            test "$actual" = OK
            ./mlc-seed comparison.ml comparison.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed comparison.mzbc)"
            test "$actual" = "OK
OK"
            ./mlc-seed negative.ml negative.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed negative.mzbc)"
            test "$actual" = OK
            ./mlc-seed let-binding.ml let-binding.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed let-binding.mzbc)"
            test "$actual" = OK
            ./mlc-seed array.ml array.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed array.mzbc)"
            test "$actual" = OK
            ./mlc-seed bytes.ml bytes.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed bytes.mzbc)"
            test "$actual" = OK
            ./mlc-seed string-value.ml string-value.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed string-value.mzbc)"
            test "$actual" = OK
            ./mlc-seed dynamic-index.ml dynamic-index.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed dynamic-index.mzbc)"
            test "$actual" = OK
            ./mlc-seed dynamic-create.ml dynamic-create.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed dynamic-create.mzbc)"
            test "$actual" = OK
            ./mlc-seed length.ml length.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed length.mzbc)"
            test "$actual" = OK
            ./mlc-seed function.ml function.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed function.mzbc)"
            test "$actual" = OK
            ./mlc-seed function-tuple.ml function-tuple.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed function-tuple.mzbc)"
            test "$actual" = OK
            ./mlc-seed function-nested.ml function-nested.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed function-nested.mzbc)"
            test "$actual" = OK
            ./mlc-seed function-string.ml function-string.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed function-string.mzbc)"
            test "$actual" = OK
            ./mlc-seed function-and.ml function-and.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed function-and.mzbc)"
            test "$actual" = OK
            ./mlc-seed identifiers.ml identifiers.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed identifiers.mzbc)"
            test "$actual" = O
            ./mlc-seed string.ml string.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed string.mzbc)"
            test "$actual" = "O	K"
            ./mlc-seed exit.ml exit.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed exit.mzbc)"
            test "$actual" = OK
            ./mlc-seed tuple.ml tuple.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed tuple.mzbc)"
            test "$actual" = OK
            ./mlc-seed sequence.ml sequence.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed sequence.mzbc)"
            test "$actual" = OK
            ./mlc-seed read-byte.ml read-byte.mzbc
            printf 'O' > input.txt
            actual="$(${mzvmSeedM2}/bin/mzvm-seed read-byte.mzbc < input.txt)"
            test "$actual" = OK
          '';
          installScript = ''
            install -Dm755 mlc-seed "$out/bin/mlc-seed"
            install -Dm644 mlc-seed.c "$out/share/mlc/mlc-seed.c"
            install -Dm644 ok.mzbc "$out/share/mlc/tests/ok.mzbc"
            install -Dm644 arithmetic.mzbc "$out/share/mlc/tests/arithmetic.mzbc"
            install -Dm644 conditional.mzbc "$out/share/mlc/tests/conditional.mzbc"
            install -Dm644 comparison.mzbc "$out/share/mlc/tests/comparison.mzbc"
            install -Dm644 negative.mzbc "$out/share/mlc/tests/negative.mzbc"
            install -Dm644 let-binding.mzbc "$out/share/mlc/tests/let-binding.mzbc"
            install -Dm644 array.mzbc "$out/share/mlc/tests/array.mzbc"
            install -Dm644 bytes.mzbc "$out/share/mlc/tests/bytes.mzbc"
            install -Dm644 string-value.mzbc "$out/share/mlc/tests/string-value.mzbc"
            install -Dm644 dynamic-index.mzbc "$out/share/mlc/tests/dynamic-index.mzbc"
            install -Dm644 dynamic-create.mzbc "$out/share/mlc/tests/dynamic-create.mzbc"
            install -Dm644 length.mzbc "$out/share/mlc/tests/length.mzbc"
            install -Dm644 function.mzbc "$out/share/mlc/tests/function.mzbc"
            install -Dm644 function-tuple.mzbc "$out/share/mlc/tests/function-tuple.mzbc"
            install -Dm644 function-nested.mzbc "$out/share/mlc/tests/function-nested.mzbc"
            install -Dm644 function-string.mzbc "$out/share/mlc/tests/function-string.mzbc"
            install -Dm644 function-and.mzbc "$out/share/mlc/tests/function-and.mzbc"
            install -Dm644 identifiers.mzbc "$out/share/mlc/tests/identifiers.mzbc"
            install -Dm644 string.mzbc "$out/share/mlc/tests/string.mzbc"
            install -Dm644 exit.mzbc "$out/share/mlc/tests/exit.mzbc"
            install -Dm644 tuple.mzbc "$out/share/mlc/tests/tuple.mzbc"
            install -Dm644 sequence.mzbc "$out/share/mlc/tests/sequence.mzbc"
            install -Dm644 read-byte.mzbc "$out/share/mlc/tests/read-byte.mzbc"
          '';
        };

        mlcSeedHostVsM2 = pkgs.runCommand "mlc-seed-host-vs-m2" { } ''
          for name in ${lib.concatStringsSep " " mlcFixtures}; do
            cmp ${mlcSeedHost}/share/mlc/tests/$name.mzbc ${mlcSeedM2}/share/mlc/tests/$name.mzbc
          done
          for name in ${lib.concatStringsSep " " mlcInputFixtures}; do
            cmp ${mlcSeedHost}/share/mlc/tests/$name.mzbc ${mlcSeedM2}/share/mlc/tests/$name.mzbc
          done
          install -Dm644 ${mlcSeedHost}/share/mlc/tests/ok.mzbc "$out/ok.mzbc"
        '';

        mlcByteSeed = stageRun {
          pname = "mlc-byte-seed";
          nativeBuildInputs = [
            pkgs.diffutils
            mzvmSeedM2
          ];
          description = "Current mlc.ml compiled to fixed-point MZBC by the staged ML0 compiler";
          buildScript = ''
            cp ${mlcStage02Ml0Compiler}/share/mlc/stages/mlc-stage-from-02-self.mzbc mlc.bootstrap.byte
            ${mzvmSeedM2}/bin/mzvm-seed mlc.bootstrap.byte < ${mlcSrc}/mlc.ml > mlc.byte
            printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled.mzbc)"
            test "$actual" = O
            printf "write_byte 'O'" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-char.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-char.mzbc)"
            test "$actual" = O
            printf 'write_string "OK"' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-string.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-string.mzbc)"
            test "$actual" = OK
            printf 'let x = 40 in write_byte (x + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let.mzbc)"
            test "$actual" = O
            printf 'let x = 40 in let y = 39 in write_byte (x + y)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let2.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let2.mzbc)"
            test "$actual" = O
            printf 'let x = 40 in let y = 20 in let z = 19 in write_byte (x + y + z)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-let3.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-let3.mzbc)"
            test "$actual" = O
            printf 'let x = (40 + 39) in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-paren-let.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-paren-let.mzbc)"
            test "$actual" = O
            printf 'let x = 88 in let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-shadow.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-shadow.mzbc)"
            test "$actual" = O
            printf 'let iffy = 79 in write_byte iffy' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-keyword-prefix-if.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-if.mzbc)"
            test "$actual" = O
            printf 'let lhs = 79 in write_byte lhs' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-keyword-prefix-let.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-let.mzbc)"
            test "$actual" = O
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/keyword-prefix-infix.ml} > compiled-keyword-prefix-infix.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-keyword-prefix-infix.mzbc)"
            test "$actual" = O
            printf 'write_byte (80 - 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-sub.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-sub.mzbc)"
            test "$actual" = O
            printf 'write_byte (79 * 1)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-mul.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-mul.mzbc)"
            test "$actual" = O
            printf 'write_byte (158 / 2)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-div.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-div.mzbc)"
            test "$actual" = O
            printf "write_byte (if 1 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-true.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-true.mzbc)"
            test "$actual" = O
            printf "write_byte (if 0 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-false.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-false.mzbc)"
            test "$actual" = O
            printf "write_byte (if 40 < 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-lt-true.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-lt-true.mzbc)"
            test "$actual" = O
            printf "write_byte (if 41 < 40 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-lt-false.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-lt-false.mzbc)"
            test "$actual" = O
            printf "write_byte (if 40 == 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-eq-true.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-eq-true.mzbc)"
            test "$actual" = O
            printf "write_byte (if 40 == 41 then 'X' else 'O')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-eq-false.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-eq-false.mzbc)"
            test "$actual" = O
            printf "write_byte (if 40 != 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-ne.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-ne.mzbc)"
            test "$actual" = O
            printf "write_byte (if 40 <= 41 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-le.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-le.mzbc)"
            test "$actual" = O
            printf "write_byte (if 41 > 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-gt.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-gt.mzbc)"
            test "$actual" = O
            printf "write_byte (if 41 >= 40 then 'O' else 'X')" | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-if-ge.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-if-ge.mzbc)"
            test "$actual" = O
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/adt.ml} > compiled-adt.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/match.ml} > compiled-match.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/wildcard-match.ml} > compiled-wildcard-match.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-wildcard-match.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/multi-adt.ml} > compiled-multi-adt.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-multi-adt.mzbc)"
            test "$actual" = OK
            printf 'type letter = A | B | C\nwrite_byte (match C with A -> 88 | B -> 88 | C -> 79)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-match-three-direct.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-three-direct.mzbc)"
            test "$actual" = O
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/match-three.ml} > compiled-match-three.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-match-three.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/adt-tuple-payload.ml} > compiled-adt-tuple-payload.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-tuple-payload.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/adt-recursion.ml} > compiled-adt-recursion.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-adt-recursion.mzbc)"
            test "$actual" = OK
            printf 'let rec out ch = write_byte ch in out 79' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-final-call.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-final-call.mzbc)"
            test "$actual" = O
            printf 'let rec id x = x in write_byte (id 40 + 39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-call-precedence.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-call-precedence.mzbc)"
            test "$actual" = O
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${./tests/mlc/read-byte.ml} > compiled-read-byte.mzbc
            actual="$(printf O | ${mzvmSeedM2}/bin/mzvm-seed compiled-read-byte.mzbc)"
            test "$actual" = OK
            printf 'let bytes = Bytes.create 3 in let zero = 0 in let _ = bytes.[zero] <- 79 in let _ = bytes.(zero + 1) <- 75 in let _ = bytes.[2] <- 10 in let _ = write_byte bytes.[0] in let _ = write_byte bytes.(1) in write_byte bytes.[2]' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-dynamic-bytes.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-dynamic-bytes.mzbc)"
            test "$actual" = OK
            ${mzvmSeedM2}/bin/mzvm-seed mlc.byte < ${mlcSrc}/mlc.ml > compiled-selfhost.mzbc
            cmp mlc.byte compiled-selfhost.mzbc
            printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed compiled-selfhost.mzbc > compiled-selfhost-smoke.mzbc
            actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-selfhost-smoke.mzbc)"
            test "$actual" = O
          '';
          installScript = ''
            install -Dm644 mlc.bootstrap.byte "$out/share/mlc/mlc.bootstrap.byte"
            install -Dm644 mlc.byte "$out/share/mlc/mlc.byte"
            install -Dm644 compiled.mzbc "$out/share/mlc/compiled.mzbc"
            install -Dm644 compiled-char.mzbc "$out/share/mlc/compiled-char.mzbc"
            install -Dm644 compiled-string.mzbc "$out/share/mlc/compiled-string.mzbc"
            install -Dm644 compiled-let.mzbc "$out/share/mlc/compiled-let.mzbc"
            install -Dm644 compiled-let2.mzbc "$out/share/mlc/compiled-let2.mzbc"
            install -Dm644 compiled-let3.mzbc "$out/share/mlc/compiled-let3.mzbc"
            install -Dm644 compiled-paren-let.mzbc "$out/share/mlc/compiled-paren-let.mzbc"
            install -Dm644 compiled-shadow.mzbc "$out/share/mlc/compiled-shadow.mzbc"
            install -Dm644 compiled-keyword-prefix-if.mzbc "$out/share/mlc/compiled-keyword-prefix-if.mzbc"
            install -Dm644 compiled-keyword-prefix-let.mzbc "$out/share/mlc/compiled-keyword-prefix-let.mzbc"
            install -Dm644 compiled-keyword-prefix-infix.mzbc "$out/share/mlc/compiled-keyword-prefix-infix.mzbc"
            install -Dm644 compiled-sub.mzbc "$out/share/mlc/compiled-sub.mzbc"
            install -Dm644 compiled-mul.mzbc "$out/share/mlc/compiled-mul.mzbc"
            install -Dm644 compiled-div.mzbc "$out/share/mlc/compiled-div.mzbc"
            install -Dm644 compiled-if-true.mzbc "$out/share/mlc/compiled-if-true.mzbc"
            install -Dm644 compiled-if-false.mzbc "$out/share/mlc/compiled-if-false.mzbc"
            install -Dm644 compiled-if-lt-true.mzbc "$out/share/mlc/compiled-if-lt-true.mzbc"
            install -Dm644 compiled-if-lt-false.mzbc "$out/share/mlc/compiled-if-lt-false.mzbc"
            install -Dm644 compiled-if-eq-true.mzbc "$out/share/mlc/compiled-if-eq-true.mzbc"
            install -Dm644 compiled-if-eq-false.mzbc "$out/share/mlc/compiled-if-eq-false.mzbc"
            install -Dm644 compiled-if-ne.mzbc "$out/share/mlc/compiled-if-ne.mzbc"
            install -Dm644 compiled-if-le.mzbc "$out/share/mlc/compiled-if-le.mzbc"
            install -Dm644 compiled-if-gt.mzbc "$out/share/mlc/compiled-if-gt.mzbc"
            install -Dm644 compiled-if-ge.mzbc "$out/share/mlc/compiled-if-ge.mzbc"
            install -Dm644 compiled-adt.mzbc "$out/share/mlc/compiled-adt.mzbc"
            install -Dm644 compiled-match.mzbc "$out/share/mlc/compiled-match.mzbc"
            install -Dm644 compiled-wildcard-match.mzbc "$out/share/mlc/compiled-wildcard-match.mzbc"
            install -Dm644 compiled-multi-adt.mzbc "$out/share/mlc/compiled-multi-adt.mzbc"
            install -Dm644 compiled-match-three-direct.mzbc "$out/share/mlc/compiled-match-three-direct.mzbc"
            install -Dm644 compiled-match-three.mzbc "$out/share/mlc/compiled-match-three.mzbc"
            install -Dm644 compiled-adt-tuple-payload.mzbc "$out/share/mlc/compiled-adt-tuple-payload.mzbc"
            install -Dm644 compiled-adt-recursion.mzbc "$out/share/mlc/compiled-adt-recursion.mzbc"
            install -Dm644 compiled-final-call.mzbc "$out/share/mlc/compiled-final-call.mzbc"
            install -Dm644 compiled-call-precedence.mzbc "$out/share/mlc/compiled-call-precedence.mzbc"
            install -Dm644 compiled-read-byte.mzbc "$out/share/mlc/compiled-read-byte.mzbc"
            install -Dm644 compiled-dynamic-bytes.mzbc "$out/share/mlc/compiled-dynamic-bytes.mzbc"
            install -Dm644 compiled-selfhost.mzbc "$out/share/mlc/compiled-selfhost.mzbc"
            install -Dm644 compiled-selfhost-smoke.mzbc "$out/share/mlc/compiled-selfhost-smoke.mzbc"
          '';
        };

        mlcByteCommitted = pkgs.runCommand "mlc-byte-committed" { } ''
          cmp ${./mlc/mlc.byte} ${mlcByteSeed}/share/mlc/mlc.byte
          install -Dm644 ${./mlc/mlc.byte} "$out/share/mlc/mlc.byte"
        '';

        mlcByteSelfhost = pkgs.runCommand "mlc-byte-selfhost" { } ''
          cmp ${mlcByteSeed}/share/mlc/mlc.byte ${mlcByteSeed}/share/mlc/compiled-selfhost.mzbc
          install -Dm644 ${mlcByteSeed}/share/mlc/mlc.byte "$out/share/mlc/mlc.byte"
          install -Dm644 ${mlcByteSeed}/share/mlc/compiled-selfhost.mzbc "$out/share/mlc/compiled-selfhost.mzbc"
        '';

        cccByteSeed = stageRun {
          pname = "ccc-byte-seed";
          nativeBuildInputs = [
            mzvmSeedM2
          ];
          description = "Current ccc.ml compiled to MZBC by fixed-point mlc.byte";
          buildScript = ''
            cp ${cccSrc}/ccc.ml ccc.ml
            ${mzvmSeedM2}/bin/mzvm-seed ${mlcByteCommitted}/share/mlc/mlc.byte < ccc.ml > ccc.byte
            check_return() {
              actual="$(${mzvmSeedM2}/bin/mzvm-seed ccc.byte < "$1")"
              expected="DEFINE LOADI32_RDI 48C7C7
DEFINE LOADI32_RAX 48C7C0
DEFINE SYSCALL 0F05

:_start
	LOADI32_RDI %$2
	LOADI32_RAX %60
	SYSCALL"
              test "$actual" = "$expected"
            }
            check_return ${./tests/mescc/scaffold/01-return-0.c} 0
            check_return ${./tests/mescc/scaffold/02-return-1.c} 1
            check_return ${./tests/mescc/scaffold/03-call.c} 0
            check_return ${./tests/mescc/scaffold/04-call-0.c} 0
            check_return ${./tests/mescc/scaffold/05-call-1.c} 1
            check_return ${./tests/mescc/scaffold/06-call-2.c} 0
            check_return ${./tests/mescc/scaffold/06-call-not-1.c} 0
            check_return ${./tests/mescc/scaffold/06-not-call-1.c} 0
            check_return ${./tests/mescc/scaffold/06-return-void.c} 0
            check_return ${./tests/mescc/scaffold/08-assign.c} 0
            check_return ${./tests/mescc/scaffold/08-assign-negative.c} 0
            check_return ${./tests/mescc/scaffold/10-if-0.c} 0
            check_return ${./tests/mescc/scaffold/11-if-1.c} 0
            check_return ${./tests/mescc/scaffold/12-if-eq.c} 0
            check_return ${./tests/mescc/scaffold/13-if-neq.c} 0
            check_return ${./tests/mescc/scaffold/14-if-goto.c} 0
            check_return ${./tests/mescc/scaffold/15-if-not-f.c} 0
            check_return ${./tests/mescc/scaffold/16-cast.c} 0
            check_return ${./tests/mescc/scaffold/16-if-t.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-char.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-assign.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-call.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-ge.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-gt.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-le.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-lt.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-and.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-or.c} 0
            check_return ${./tests/mescc/scaffold/17-compare-rotated.c} 0
            check_return ${./tests/mescc/scaffold/18-assign-shadow.c} 0
            check_return ${./tests/mescc/scaffold/20-while.c} 0
            check_return ${./tests/mescc/scaffold/21-char-array-simple.c} 0
            check_return ${./tests/mescc/scaffold/21-char-array.c} 0
            check_return ${./tests/mescc/scaffold/22-while-char-array.c} 0
            check_return ${./tests/mescc/scaffold/30-exit-0.c} 0
            check_return ${./tests/mescc/scaffold/30-exit-42.c} 42
            check_return ${./tests/mescc/scaffold/33-and-or.c} 0
            check_return ${./tests/mescc/scaffold/34-pre-post.c} 0
            check_return ${./tests/mescc/scaffold/36-compare-arithmetic.c} 0
            check_return ${./tests/mescc/scaffold/36-compare-arithmetic-negative.c} 0
            check_return ${./tests/mescc/scaffold/37-compare-assign.c} 0
            check_return ${./tests/mescc/scaffold/40-if-else.c} 0
            check_return ${./tests/mescc/scaffold/42-goto-label.c} 0
            check_return ${./tests/mescc/scaffold/45-void-call.c} 0
            check_return ${./tests/mescc/scaffold/70-function-modulo.c} 0
            check_return ${./tests/hcc/m1-smoke/examples/ret13.c} 13
            check_return ${./tests/hcc/m1-smoke/examples/short-circuit.c} 42
            check_return ${./tests/hcc/m1-smoke/examples/call-arg-immediate.c} 42
            check_return ${./tests/hcc/m1-smoke/examples/signed-char-cast.c} 0
            check_return ${./tests/hcc/m1-smoke/examples/return-coercion.c} 0
            printf 'int main(){return 42;}' > return-42.c
            check_return return-42.c 42
          '';
          installScript = ''
            install -Dm644 ccc.byte "$out/share/ccc/ccc.byte"
          '';
        };

        cccByteCommitted = pkgs.runCommand "ccc-byte-committed" { } ''
          cmp ${./ccc/ccc.byte} ${cccByteSeed}/share/ccc/ccc.byte
          install -Dm644 ${./ccc/ccc.byte} "$out/share/ccc/ccc.byte"
        '';

        tccM1CccSeed = pkgs.runCommand "tcc-m1-ccc-seed" { } ''
          ${mzvmSeedM2}/bin/mzvm-seed ${cccByteCommitted}/share/ccc/ccc.byte < ${./tests/mescc/scaffold/01-return-0.c} > tcc.M1
          printf 'DEFINE LOADI32_RDI 48C7C7\nDEFINE LOADI32_RAX 48C7C0\nDEFINE SYSCALL 0F05\n\n:_start\n\tLOADI32_RDI %%0\n\tLOADI32_RAX %%60\n\tSYSCALL\n' > expected.M1
          cmp expected.M1 tcc.M1
          install -Dm644 tcc.M1 "$out/share/ccc/tcc.M1"
        '';

        tccBinCccSeed = pkgs.runCommand "tcc-bin-ccc-seed" {
          nativeBuildInputs = [ minimalBootstrap.stage0-posix.mescc-tools ];
        } ''
          build_and_run() {
            src="$1"
            expected="$2"
            name="$3"

            ${mzvmSeedM2}/bin/mzvm-seed ${cccByteCommitted}/share/ccc/ccc.byte < "$src" > "$name.M1"
            M1 --architecture amd64 --little-endian \
              -f ${minimalBootstrap.stage0-posix.src}/M2libc/amd64/amd64_defs.M1 \
              -f "$name.M1" \
              --output "$name.hex2"
            printf ':ELF_end\n' > "$name-end.hex2"
            hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
              --file ${minimalBootstrap.stage0-posix.src}/M2libc/amd64/ELF-amd64.hex2 \
              --file "$name.hex2" \
              --file "$name-end.hex2" \
              --output "$name"
            chmod 555 "$name"
            set +e
            "./$name"
            actual="$?"
            set -e
            test "$actual" = "$expected"
            install -Dm644 "$name.M1" "$out/share/ccc/scaffold/$name.M1"
            install -Dm644 "$name.hex2" "$out/share/ccc/scaffold/$name.hex2"
          }

          cp ${tccM1CccSeed}/share/ccc/tcc.M1 tcc.M1
          M1 --architecture amd64 --little-endian \
            -f ${minimalBootstrap.stage0-posix.src}/M2libc/amd64/amd64_defs.M1 \
            -f tcc.M1 \
            --output tcc.hex2
          printf ':ELF_end\n' > tcc-end.hex2
          hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
            --file ${minimalBootstrap.stage0-posix.src}/M2libc/amd64/ELF-amd64.hex2 \
            --file tcc.hex2 \
            --file tcc-end.hex2 \
            --output tcc
          chmod 555 tcc
          ./tcc
          install -Dm555 tcc "$out/bin/tcc"
          install -Dm644 tcc.M1 "$out/share/ccc/tcc.M1"
          install -Dm644 tcc.hex2 "$out/share/ccc/tcc.hex2"

          build_and_run ${./tests/mescc/scaffold/01-return-0.c} 0 01-return-0
          build_and_run ${./tests/mescc/scaffold/02-return-1.c} 1 02-return-1
          build_and_run ${./tests/mescc/scaffold/03-call.c} 0 03-call
          build_and_run ${./tests/mescc/scaffold/04-call-0.c} 0 04-call-0
          build_and_run ${./tests/mescc/scaffold/05-call-1.c} 1 05-call-1
          build_and_run ${./tests/mescc/scaffold/06-call-2.c} 0 06-call-2
          build_and_run ${./tests/mescc/scaffold/06-call-not-1.c} 0 06-call-not-1
          build_and_run ${./tests/mescc/scaffold/06-not-call-1.c} 0 06-not-call-1
          build_and_run ${./tests/mescc/scaffold/06-return-void.c} 0 06-return-void
          build_and_run ${./tests/mescc/scaffold/08-assign.c} 0 08-assign
          build_and_run ${./tests/mescc/scaffold/08-assign-negative.c} 0 08-assign-negative
          build_and_run ${./tests/mescc/scaffold/10-if-0.c} 0 10-if-0
          build_and_run ${./tests/mescc/scaffold/11-if-1.c} 0 11-if-1
          build_and_run ${./tests/mescc/scaffold/12-if-eq.c} 0 12-if-eq
          build_and_run ${./tests/mescc/scaffold/13-if-neq.c} 0 13-if-neq
          build_and_run ${./tests/mescc/scaffold/14-if-goto.c} 0 14-if-goto
          build_and_run ${./tests/mescc/scaffold/15-if-not-f.c} 0 15-if-not-f
          build_and_run ${./tests/mescc/scaffold/16-cast.c} 0 16-cast
          build_and_run ${./tests/mescc/scaffold/16-if-t.c} 0 16-if-t
          build_and_run ${./tests/mescc/scaffold/17-compare-char.c} 0 17-compare-char
          build_and_run ${./tests/mescc/scaffold/17-compare-assign.c} 0 17-compare-assign
          build_and_run ${./tests/mescc/scaffold/17-compare-call.c} 0 17-compare-call
          build_and_run ${./tests/mescc/scaffold/17-compare-ge.c} 0 17-compare-ge
          build_and_run ${./tests/mescc/scaffold/17-compare-gt.c} 0 17-compare-gt
          build_and_run ${./tests/mescc/scaffold/17-compare-le.c} 0 17-compare-le
          build_and_run ${./tests/mescc/scaffold/17-compare-lt.c} 0 17-compare-lt
          build_and_run ${./tests/mescc/scaffold/17-compare-and.c} 0 17-compare-and
          build_and_run ${./tests/mescc/scaffold/17-compare-or.c} 0 17-compare-or
          build_and_run ${./tests/mescc/scaffold/17-compare-rotated.c} 0 17-compare-rotated
          build_and_run ${./tests/mescc/scaffold/18-assign-shadow.c} 0 18-assign-shadow
          build_and_run ${./tests/mescc/scaffold/20-while.c} 0 20-while
          build_and_run ${./tests/mescc/scaffold/21-char-array-simple.c} 0 21-char-array-simple
          build_and_run ${./tests/mescc/scaffold/21-char-array.c} 0 21-char-array
          build_and_run ${./tests/mescc/scaffold/22-while-char-array.c} 0 22-while-char-array
          build_and_run ${./tests/mescc/scaffold/30-exit-0.c} 0 30-exit-0
          build_and_run ${./tests/mescc/scaffold/30-exit-42.c} 42 30-exit-42
          build_and_run ${./tests/mescc/scaffold/33-and-or.c} 0 33-and-or
          build_and_run ${./tests/mescc/scaffold/34-pre-post.c} 0 34-pre-post
          build_and_run ${./tests/mescc/scaffold/36-compare-arithmetic.c} 0 36-compare-arithmetic
          build_and_run ${./tests/mescc/scaffold/36-compare-arithmetic-negative.c} 0 36-compare-arithmetic-negative
          build_and_run ${./tests/mescc/scaffold/37-compare-assign.c} 0 37-compare-assign
          build_and_run ${./tests/mescc/scaffold/40-if-else.c} 0 40-if-else
          build_and_run ${./tests/mescc/scaffold/42-goto-label.c} 0 42-goto-label
          build_and_run ${./tests/mescc/scaffold/45-void-call.c} 0 45-void-call
          build_and_run ${./tests/mescc/scaffold/70-function-modulo.c} 0 70-function-modulo
          build_and_run ${./tests/hcc/m1-smoke/examples/ret13.c} 13 hcc-ret13
          build_and_run ${./tests/hcc/m1-smoke/examples/short-circuit.c} 42 hcc-short-circuit
          build_and_run ${./tests/hcc/m1-smoke/examples/call-arg-immediate.c} 42 hcc-call-arg-immediate
          build_and_run ${./tests/hcc/m1-smoke/examples/signed-char-cast.c} 0 hcc-signed-char-cast
          build_and_run ${./tests/hcc/m1-smoke/examples/return-coercion.c} 0 hcc-return-coercion
        '';

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
          kaem = minimalBootstrap.stage0-posix.kaem;
          bootstrapShell = minimalShell;
        };

        hccBlynnObjsFromPrecisely = pname: precisely:
          pkgs.callPackage ./nix/hcc-blynn-objs.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely minimalBootstrap;
            sourceBundle = hccBlynnSources;
            shareName = pname;
          };

        hccBlynnObjsFromCompiler = pname: precisely: blynnCompiler:
          pkgs.callPackage ./nix/hcc-blynn-objs.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely minimalBootstrap;
            inherit blynnCompiler;
            sourceBundle = hccBlynnSources;
            shareName = pname;
          };

        hccBlynnCFromPrecisely = pname: precisely: commonObjects:
          pkgs.callPackage ./nix/hcc-blynn-c.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely commonObjects;
            sourceBundle = hccBlynnSources;
            kaem = minimalBootstrap.stage0-posix.kaem;
            bootstrapShell = minimalShell;
            shareName = pname;
          };

        hccBlynnCFromCompiler = pname: precisely: blynnCompiler: commonObjects:
          pkgs.callPackage ./nix/hcc-blynn-c.nix {
            stdenvNoCC = rawStdenvNoCC;
            inherit pname precisely commonObjects;
            inherit blynnCompiler;
            sourceBundle = hccBlynnSources;
            kaem = minimalBootstrap.stage0-posix.kaem;
            bootstrapShell = minimalShell;
            shareName = pname;
          };

        preciselyBy = {
          m2.stage0 = blynnPhaseBin;
          gcc.host = preciselyGccHost;
          ghc.debug = preciselyGhcDebug;
        };

        hccM2BlynnCompiler = "${blynnUpstreamStages.crossly1}/bin/crossly1";

        hccBlynnCBy = {
          ghc.precisely = hccBlynnCFromPrecisely "hcc-blynn-c-ghc-precisely" preciselyBy.ghc.debug hccBlynnObjsBy.ghc.precisely;
          gcc.precisely = hccBlynnCFromPrecisely "hcc-blynn-c-gcc-precisely" preciselyBy.gcc.host hccBlynnObjsBy.gcc.precisely;
          m2.precisely = hccBlynnCFromCompiler "hcc-blynn-c-m2-precisely" preciselyBy.m2.stage0 hccM2BlynnCompiler hccBlynnObjsBy.m2.precisely;
        };

        hccBlynnObjsBy = {
          ghc.precisely = hccBlynnObjsFromPrecisely "hcc-blynn-objs-ghc-precisely" preciselyBy.ghc.debug;
          gcc.precisely = hccBlynnObjsFromPrecisely "hcc-blynn-objs-gcc-precisely" preciselyBy.gcc.host;
          m2.precisely = hccBlynnObjsFromCompiler "hcc-blynn-objs-m2-precisely" preciselyBy.m2.stage0 hccM2BlynnCompiler;
        };

        hccFromPrecisely = {
          pname,
          generatedC,
          cBackend,
        }:
          pkgs.callPackage ./nix/hcc-blynn-bin.nix ({
            inherit pname generatedC;
            src = hccSrc;
            kaem = minimalBootstrap.stage0-posix.kaem;
            bootstrapShell = minimalShell;
            shareName = pname;
          } // cBackend);

        hccCBackends = {
          gcc = {
            mkDerivation = rawStdenvCC.mkDerivation;
            runtimeFile = "cbits/hcc_runtime.c";
            scriptEnv = ''HCC_C_BACKEND=gcc HOST_CC="$CC"'';
            top = 536870912;
            hcppTop = 134217728;
            hcc1Top = 134217728;
            description = "HCC compiled from Blynn output by the normal GCC C toolchain";
          };

          # Same as gcc, but lowers HCC_RTS_ADAPTIVE_MAJOR_WORDS so the Blynn
          # RTS collects more often. Trades ~2x runtime for ~60% peak-RSS cut
          # on hcc1 against tcc-expanded.c; see docs/hcc_memory_audit.md.
          gccLowmem = {
            mkDerivation = rawStdenvCC.mkDerivation;
            runtimeFile = "cbits/hcc_runtime.c";
            compileCommand = ''
              echo "hcc-blynn: gcc cc hcpp-blynn.c (low-mem GC) -> hcpp"
              $CC -O2 -DHCC_RTS_ADAPTIVE_MAJOR_WORDS=16777216 hcpp-blynn.c cbits/hcc_runtime.c -o hcpp
              echo "hcc-blynn: gcc cc hcc1-blynn.c (low-mem GC) -> hcc1"
              $CC -O2 -DHCC_RTS_ADAPTIVE_MAJOR_WORDS=16777216 hcc1-blynn.c cbits/hcc_runtime.c -o hcc1
              echo "hcc-blynn: gcc cc cbits/hcc_m1.c -> hcc-m1"
              $CC -O2 cbits/hcc_m1.c -o hcc-m1
            '';
            top = 536870912;
            hcppTop = 134217728;
            hcc1Top = 134217728;
            description = "HCC compiled from Blynn output by GCC with a low-memory adaptive-major GC threshold";
          };

          tcc = tcc: {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [ tcc ];
            runtimeFile = "cbits/hcc_runtime.c";
            scriptEnv = ''HCC_C_BACKEND=tcc TCC=${tcc}/bin/tcc TCC_FLAGS="-B ${tcc}/lib -I ${tcc}/include"'';
            top = 536870912;
            hcppTop = 134217728;
            hcc1Top = 134217728;
            description = "HCC compiled from Blynn output by HCC-built TinyCC";
          };

          m2 = {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            scriptEnv = ''HCC_C_BACKEND=m2 M2LIBC_PATH=${m2libcSrc}'';
            top = 134217728;
            hcppTop = 134217728;
            hcc1Top = 134217728;
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by stage0 M2-Mesoplanet";
            metaPlatforms = [ "x86_64-linux" ];
          };

          # Same as m2, but with HCC_RTS_ADAPTIVE_MAJOR_WORDS lowered so the
          # Blynn RTS collects more often AND with a smaller TOP so each of
          # the two heap arenas is 4× smaller (8 GiB virtual → 1 GiB virtual).
          # The smaller TOP is what makes the m2-compiled binary's RSS
          # actually drop — the GC trigger alone doesn't help on m2 because
          # M2-Mesoplanet's compiled code dirties roughly the whole arena.
          # See docs/hcc_memory_audit.md for the trade-off curve.
          m2Lowmem = {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            compileCommand = ''
              . ${./scripts/lib/bootstrap.sh}
              cat hcpp-blynn.c > hcpp-body.c
              cat hcc1-blynn.c > hcc1-body.c
              {
                printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1'
                printf '%s\n' '#define HCC_RTS_ADAPTIVE_MAJOR_WORDS 33554432'
              } > hcpp-blynn.c
              cat hcpp-body.c >> hcpp-blynn.c
              {
                printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1'
                printf '%s\n' '#define HCC_RTS_ADAPTIVE_MAJOR_WORDS 33554432'
              } > hcc1-blynn.c
              cat hcc1-body.c >> hcc1-blynn.c
              compile_m2 hcpp-blynn.c hcpp -f cbits/hcc_runtime_m2.c
              compile_m2 hcc1-blynn.c hcc1 -f cbits/hcc_runtime_m2.c
              compile_m2 cbits/hcc_m1.c hcc-m1
            '';
            top = 67108864;
            hcppTop = 67108864;
            hcc1Top = 67108864;
            m2Arch = minimalBootstrap.stage0-posix.m2libcArch;
            m2Os = minimalBootstrap.stage0-posix.m2libcOS;
            description = "HCC compiled from Blynn output by stage0 M2-Mesoplanet with a low-memory adaptive-major GC threshold and smaller heap arenas";
            metaPlatforms = [ "x86_64-linux" ];
          };

          gccm2 = {
            mkDerivation = rawStdenvNoCC.mkDerivation;
            nativeBuildInputs = [
              m2MesoplanetGcc
              minimalBootstrap.stage0-posix.mescc-tools
            ];
            runtimeFile = "cbits/hcc_runtime_m2.c";
            scriptEnv = ''HCC_C_BACKEND=m2 M2_MESOPLANET=${m2MesoplanetGcc}/bin/M2-Mesoplanet M2LIBC_PATH=${minimalBootstrap.stage0-posix.src}/M2libc PATH=${minimalBootstrap.stage0-posix.mescc-tools}/bin:$PATH'';
            top = 134217728;
            hcppTop = 134217728;
            hcc1Top = 134217728;
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
          host.microhs.native = hccHostMicrohsNative;

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

          m2.precisely.m2Lowmem = hccFromPrecisely {
            pname = "hcc-m2-precisely-m2-lowmem";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.m2Lowmem // {
              description = "HCC compiled by the stage0-built Blynn precisely and M2-Mesoplanet with a low-memory GC trigger";
            };
          };

          m2.precisely.gcc = hccFromPrecisely {
            pname = "hcc-m2-precisely-gcc";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.gcc // {
              description = "HCC compiled by the stage0-built Blynn precisely and GCC";
            };
          };

          m2.precisely.gccLowmem = hccFromPrecisely {
            pname = "hcc-m2-precisely-gcc-lowmem";
            generatedC = hccBlynnCBy.m2.precisely;
            cBackend = hccCBackends.gccLowmem // {
              description = "HCC compiled by the stage0-built Blynn precisely and GCC with a low-memory GC trigger";
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
          stdenvNoCC = rawStdenvNoCC;
          inherit pname hcc minimalBootstrap target;
          binutils = if target == "riscv64" then pkgs.pkgsCross.riscv64.buildPackages.binutils else pkgs.binutils;
          diffutils = pkgs.diffutils;
          gnugrep = pkgs.gnugrep;
          qemu = pkgs.qemu;
          mesLibc = mesLibcSrc;
          m2libc = m2libcSrc;
          patchTool = pkgs.patch;
        };

        tinyccFromHcc = pname: hcc: tinyccFromHccForTarget pname hcc nativeM1Target;

        tinyccM1FromHccForTarget = pname: hcc: target: pkgs.callPackage ./nix/tinycc-boot-hcc.nix {
          stdenvNoCC = rawStdenvNoCC;
          inherit pname hcc minimalBootstrap target;
          binutils = if target == "riscv64" then pkgs.pkgsCross.riscv64.buildPackages.binutils else pkgs.binutils;
          diffutils = pkgs.diffutils;
          gnugrep = pkgs.gnugrep;
          qemu = pkgs.qemu;
          mesLibc = mesLibcSrc;
          m2libc = m2libcSrc;
          patchTool = pkgs.patch;
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
          m2.precisely.m2Lowmem = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-m2-lowmem" hccBy.m2.precisely.m2Lowmem;
          m2.precisely.gcc = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gcc" hccBy.m2.precisely.gcc;
          m2.precisely.gccLowmem = tinyccFromHcc "tinycc-boot-hcc-m2-precisely-gcc-lowmem" hccBy.m2.precisely.gccLowmem;
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
            };
            tinycc-musl-intermediate = lib.recurseIntoAttrs (final.callPackage ./nix/minimal-bootstrap/tinycc-musl.nix {
              stdenvNoCC = pkgs.stdenvNoCC;
              fetchgit = pkgs.fetchgit;
              bash = final.bash_2_05;
              tinycc = final.tinycc-mes;
              musl = final.musl-tcc-intermediate;
            });
            musl-tcc = final.callPackage ./nix/minimal-bootstrap/musl-tcc.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl-intermediate;
              gnused = final.gnused-mes;
            };
            tinycc-musl = lib.recurseIntoAttrs (final.callPackage ./nix/minimal-bootstrap/tinycc-musl.nix {
              stdenvNoCC = pkgs.stdenvNoCC;
              fetchgit = pkgs.fetchgit;
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl-intermediate;
              musl = final.musl-tcc;
            });
            musl-tcc-dynamic = final.callPackage ./nix/minimal-bootstrap/musl-tcc.nix {
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl;
              gnused = final.gnused-mes;
              enableShared = true;
            };
            tinycc-musl-dynamic = lib.recurseIntoAttrs (final.callPackage ./nix/minimal-bootstrap/tinycc-musl.nix {
              stdenvNoCC = pkgs.stdenvNoCC;
              fetchgit = pkgs.fetchgit;
              bash = final.bash_2_05;
              tinycc = final.tinycc-musl;
              musl = final.musl-tcc-dynamic;
              staticByDefault = false;
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

        hugsRunhugsMuslFromTinycc = pname: tinyccMusl:
          pkgs.callPackage ./nix/hugs-runhugs-tcc-musl.nix {
            stdenvNoCC = pkgs.stdenvNoCC;
            inherit pname tinyccMusl;
          };

        hugsRunhugsMuslDynamic =
          hugsRunhugsMuslFromTinycc "hugs98-runhugs-host-ghc-native-tcc-musl-dynamic"
            minimalBootstrapBy.host.ghc.native.tinycc-musl-dynamic;

        microhsNixpkgsPatchDir = pkgs.path + "/pkgs/development/compilers/microhs/patches";
        microhsPatches = [
          (microhsNixpkgsPatchDir + "/hugs.patch")
          (microhsNixpkgsPatchDir + "/hugs-viewpatterns.patch")
          (microhsNixpkgsPatchDir + "/link-math.patch")
        ];

        microhsHugsBootFromHugs = pname: hugs:
          pkgs.callPackage ./nix/microhs-hugs-boot.nix {
            inherit pname hugs;
            patches = microhsPatches;
          };

        microhsHugsBoot =
          microhsHugsBootFromHugs "microhs-hugs-boot-host-ghc-native-tcc-musl-dynamic"
            hugsRunhugsMuslDynamic;

        microhsStage1FromBoot = pname: microhsBoot:
          pkgs.callPackage ./nix/microhs-stage1.nix {
            inherit pname microhsBoot;
            patches = microhsPatches ++ [
              (microhsNixpkgsPatchDir + "/simple-unicode.patch")
            ];
          };

        microhsStage1 =
          microhsStage1FromBoot "microhs-stage1-host-ghc-native-tcc-musl-dynamic"
            microhsHugsBoot;

        hccHostMicrohsNative = pkgs.callPackage ./nix/hcc-microhs.nix {
          stdenv = pkgs.stdenv;
          pname = "hcc-host-microhs-native";
          microhs = microhsStage1;
          src = hccSrc;
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
        packageTree = {
          default = blynnPhaseBin;

          blynn = {
            compiler = blynnCompiler;
            phase-bin = blynnPhaseBin;
            stage = blynnRootStages;
            upstream.stage = blynnUpstreamStages;
          };

          precisely = preciselyBy;

          m2.mesoplanet.gcc = m2MesoplanetGcc;

          mzvm = {
            host = mzvmHost;
            seed.m2 = mzvmSeedM2;
          };
          mzvm-seed.m2 = mzvmSeedM2;

          mlc = {
            interp-seed.host = mlcInterpSeedHost;
            interp-seed.m2 = mlcInterpSeedM2;
            stage.core00 = mlcStage00Core;
            stage.parenthetical01 = mlcStage01Parenthetical;
            stage.ml0Compiler02 = mlcStage02Ml0Compiler;
            seed.host = mlcSeedHost;
            seed.m2 = mlcSeedM2;
            byte.seed = mlcByteSeed;
            byte.committed = mlcByteCommitted;
            byte.selfhost = mlcByteSelfhost;
          };
          mlc-interp-seed.host = mlcInterpSeedHost;
          mlc-interp-seed.m2 = mlcInterpSeedM2;
          mlc-stage-00-core = mlcStage00Core;
          mlc-stage-01-parenthetical = mlcStage01Parenthetical;
          mlc-stage-02-ml0-compiler = mlcStage02Ml0Compiler;
          mlc-seed.host = mlcSeedHost;
          mlc-seed.m2 = mlcSeedM2;

          ccc = {
            byte.seed = cccByteSeed;
            byte.committed = cccByteCommitted;
          };

          tcc.m1.ccc.seed = tccM1CccSeed;
          tcc.bin.ccc.seed = tccBinCccSeed;

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
            mzvm.host-vs-seed = mzvmHostVsSeed;
            mlc.interp-seed.host-vs-m2 = mlcInterpSeedHostVsM2;
            mlc.stage.core00 = mlcStage00Core;
            mlc.stage.parenthetical01 = mlcStage01Parenthetical;
            mlc.stage.ml0Compiler02 = mlcStage02Ml0Compiler;
            mlc.seed.host-vs-m2 = mlcSeedHostVsM2;
            mlc.byte.seed = mlcByteSeed;
            mlc.byte.committed = mlcByteCommitted;
            mlc.byte.selfhost = mlcByteSelfhost;
            ccc.byte.seed = cccByteSeed;
            ccc.byte.committed = cccByteCommitted;
            tcc.m1.ccc.seed = tccM1CccSeed;
            tcc.bin.ccc.seed = tccBinCccSeed;
          };
        };
      in {
        packages = {
          default = packageTree.default;
        };

        checks = {
          mzvm-host-vs-seed = mzvmHostVsSeed;
          mlc-interp-seed-m2 = mlcInterpSeedM2;
          mlc-interp-seed-host-vs-m2 = mlcInterpSeedHostVsM2;
          mlc-stage-00-core = mlcStage00Core;
          mlc-stage-01-parenthetical = mlcStage01Parenthetical;
          mlc-stage-02-ml0-compiler = mlcStage02Ml0Compiler;
          mlc-seed-m2 = mlcSeedM2;
          mlc-seed-host-vs-m2 = mlcSeedHostVsM2;
          mlc-byte-seed = mlcByteSeed;
          mlc-byte-committed = mlcByteCommitted;
          mlc-byte-selfhost = mlcByteSelfhost;
          ccc-byte-seed = cccByteSeed;
          ccc-byte-committed = cccByteCommitted;
          tcc-m1-ccc-seed = tccM1CccSeed;
          tcc-bin-ccc-seed = tccBinCccSeed;
        };

        legacyPackages = packageTree;

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
