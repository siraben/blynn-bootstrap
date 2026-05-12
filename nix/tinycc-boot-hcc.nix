{
  stdenvNoCC,
  lib,
  hcc,
  binutils,
  minimalBootstrap,
  mesLibc,
  m2libc,
  pname ? "tinycc-boot-hcc",
  enableTrace ? false,
  m1ArtifactsOnly ? false,
  target ? "amd64",
}:

let
  version = "unstable-2025-12-03";
  rev = "cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341";
  shortRev = builtins.substring 0 7 rev;
  support = ../hcc/support;
  hccTraceArgs = lib.optionalString enableTrace "--trace ";
  targetCfg =
    if target == "aarch64" || target == "arm64" then {
      hcc = "aarch64";
      m1 = "aarch64";
      m2 = "aarch64";
      tccDefine = "TCC_TARGET_ARM64";
      defs = "aarch64_defs.M1";
      elf = "ELF-aarch64.hex2";
      start = "aarch64-start.M1";
      memory = "aarch64-memory.M1";
      syscalls = "aarch64-syscalls.M1";
      compatArg = "";
      base = "0x00600000";
      libtcc1ExtraBootstrap = "bootstrap-libs/lib-arm64.o";
      libtcc1ExtraFinal = "final-libs/lib-arm64.o";
      buildArm64Lib = true;
    } else {
      hcc = "amd64";
      m1 = "amd64";
      m2 = "amd64";
      tccDefine = "TCC_TARGET_X86_64";
      defs = "amd64_defs.M1";
      elf = "ELF-amd64.hex2";
      start = "amd64-start.M1";
      memory = "amd64-memory.M1";
      syscalls = "amd64-syscalls.M1";
      compatArg = "-f ${support}/amd64-compat.M1";
      base = "0x00600000";
      libtcc1ExtraBootstrap = "bootstrap-libs/alloca.o";
      libtcc1ExtraFinal = "final-libs/alloca.o";
      buildArm64Lib = false;
    };
  targetDefineArg = "-D ${targetCfg.tccDefine}=1";
  tccTargetDefineArg = "-D${targetCfg.tccDefine}=1";

in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit version;
  dontPatchELF = true;
  dontFixup = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  src = builtins.fetchurl {
    url = "https://github.com/TinyCC/tinycc/archive/${rev}.tar.gz";
    sha256 = "sha256-c4H5RKqSVc1WDoGSxbAkEkbSyD7qVLjrMXECmS/h4rs=";
  };

  sourceRoot = "tinycc-${rev}";

  patches = [
    ../patches/upstreams/tinycc-mescc-source.patch
  ];

  nativeBuildInputs = [
    hcc
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;

  buildPhase = ''
    runHook preBuild

    ulimit -s unlimited

    log_step() {
      printf 'tinycc-boot-hcc: %s\n' "$1"
    }

    run_step() {
      label="$1"
      shift
      log_step "START $label"
      "$@"
      log_step "DONE  $label"
    }

    run_step_shell() {
      label="$1"
      command="$2"
      log_step "START $label"
      eval "$command"
      log_step "DONE  $label"
    }

    log_file() {
      file="$1"
      log_step "FILE  $file"
    }

    m1_artifacts_only="${if m1ArtifactsOnly then "1" else "0"}"
    target_is_aarch64="${if targetCfg.buildArm64Lib then "1" else "0"}"
    aarch64_as="${lib.optionalString targetCfg.buildArm64Lib "${binutils}/bin/as"}"
    aarch64_objcopy="${lib.optionalString targetCfg.buildArm64Lib "${binutils}/bin/objcopy"}"
    compile_m1() {
      input="$1"
      output="$2"
      base="''${output%.M1}"
      run_step "hcc1 --m1-ir $input" hcc1 ${hccTraceArgs}--target ${targetCfg.hcc} --m1-ir -o "$base.hccir" "$input"
      log_file "$base.hccir"
      run_step "hcc-m1 $base.hccir" hcc-m1 --target ${targetCfg.hcc} "$base.hccir" "$output"
      log_file "$output"
    }

    tcc_include_src="$PWD/include"
    mes_include_src="${mesLibc}/include"
    tcc_sysinclude_path="${if m1ArtifactsOnly then "/hcc-bootstrap/include" else "$out/include"}"

    cat > config.h <<EOF
    #define BOOTSTRAP 1
    #define HAVE_LONG_LONG 1
    #define HAVE_SETJMP 1
    #define HAVE_BITFIELD 1
    #define HAVE_FLOAT 1
    #define ${targetCfg.tccDefine} 1
    #define inline
    #define CONFIG_TCCDIR ""
    #define CONFIG_SYSROOT ""
    #define CONFIG_TCC_CRTPREFIX "{B}"
    #define CONFIG_TCC_ELFINTERP "/mes/loader"
    #define CONFIG_TCC_LIBPATHS "{B}"
    #define CONFIG_TCC_SYSINCLUDEPATHS "$tcc_sysinclude_path"
    #define TCC_LIBGCC "libc.a"
    #define TCC_LIBTCC1 "libtcc1.a"
    #define CONFIG_TCC_LIBTCC1_MES 0
    #define CONFIG_TCCBOOT 1
    #define CONFIG_TCC_STATIC 1
    #define CONFIG_USE_LIBGCC 1
    #define TCC_MES_LIBC 1
    #define TCC_VERSION "0.9.28-${version}"
    #define ONE_SOURCE 1
    ${lib.optionalString targetCfg.buildArm64Lib "#define CONFIG_TCC_BACKTRACE 0"}
    #define CONFIG_TCC_SEMLOCK 0
    EOF

    run_step_shell "hcpp tcc.c > tcc-expanded.c" "hcpp \
      -I . \
      -I \"$tcc_include_src\" \
      -I \"$mes_include_src\" \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      ${targetDefineArg} \
      -D inline= \
      -D CONFIG_TCCDIR=\\\"\\\" \
      -D CONFIG_SYSROOT=\\\"\\\" \
      -D CONFIG_TCC_CRTPREFIX=\\\"{B}\\\" \
      -D CONFIG_TCC_ELFINTERP=\\\"/mes/loader\\\" \
      -D CONFIG_TCC_LIBPATHS=\\\"{B}\\\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\\\"$tcc_sysinclude_path\\\" \
      -D TCC_LIBGCC=\\\"libc.a\\\" \
      -D TCC_LIBTCC1=\\\"libtcc1.a\\\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCCBOOT=1 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\\\"0.9.28-${version}\\\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c > tcc-expanded.c"
    log_file tcc-expanded.c

    run_step_shell "hcpp tcc-bootstrap-support.c > tcc-bootstrap-support.i" "hcpp ${support}/tcc-bootstrap-support.c > tcc-bootstrap-support.i"
    log_file tcc-bootstrap-support.i
    compile_m1 tcc-bootstrap-support.i tcc-bootstrap-support.M1
    run_step_shell "hcpp tcc-final-overrides.c > tcc-final-overrides.i" "hcpp ${support}/tcc-final-overrides.c > tcc-final-overrides.i"
    log_file tcc-final-overrides.i
    compile_m1 tcc-final-overrides.i tcc-final-overrides.M1
    compile_m1 tcc-expanded.c tcc.M1

    if [ "$m1_artifacts_only" != 1 ]; then
    M1 --architecture ${targetCfg.m1} --little-endian \
      -f ${m2libc}/${targetCfg.m2}/${targetCfg.defs} \
      ${targetCfg.compatArg} \
      -f ${support}/${targetCfg.start} \
      -f ${support}/${targetCfg.memory} \
      -f tcc-bootstrap-support.M1 \
      -f tcc.M1 \
      -f tcc-final-overrides.M1 \
      -f ${support}/${targetCfg.syscalls} \
      --output tcc.hex2

    printf ':ELF_end\n' > tcc-end.hex2
    hex2 --architecture ${targetCfg.m1} --little-endian --base-address ${targetCfg.base} \
      --file ${m2libc}/${targetCfg.m2}/${targetCfg.elf} \
      --file tcc.hex2 \
      --file tcc-end.hex2 \
      --output tcc
    chmod 555 tcc

    make_ar() {
      tool="$1"
      shift
      archive="$1"
      shift
      if [ -e "$archive" ]; then
        rm "$archive"
      fi
      "$tool" -ar cr "$archive" "$@"
    }

    assemble_aarch64_support_object() {
      output="$1"
      input="$2"
      tmp="$output.tmp"
      "$aarch64_as" -o "$tmp" "$input"
      "$aarch64_objcopy" \
        --remove-section=.data \
        --remove-section=.bss \
        "$tmp" "$output"
      rm "$tmp"
    }

    mkdir -p bootstrap-libs
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "as bootstrap aarch64 crt1.s" assemble_aarch64_support_object bootstrap-libs/crt1.o ${support}/tcc-aarch64-crt1.s
    run_step "tcc bootstrap aarch64 crti.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crti.o ${support}/tcc-aarch64-empty.c
    run_step "tcc bootstrap aarch64 crtn.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crtn.o ${support}/tcc-aarch64-empty.c
    run_step "tcc bootstrap aarch64 runtime.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/aarch64-runtime.o ${support}/tcc-aarch64-runtime.c
    run_step "as bootstrap aarch64 syscalls.s" assemble_aarch64_support_object bootstrap-libs/aarch64-syscalls.o ${support}/tcc-aarch64-syscalls.s
    run_step "tcc bootstrap support.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/tcc-bootstrap-support.o ${support}/tcc-bootstrap-support.c
    run_step "tcc bootstrap libgetopt.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/libgetopt.o ${mesLibc}/lib/libgetopt.c
    else
    run_step "tcc bootstrap crt1.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crt1.o ${mesLibc}/lib/crt1.c
    run_step "tcc bootstrap crti.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crti.o ${mesLibc}/lib/crti.c
    run_step "tcc bootstrap crtn.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/crtn.o ${mesLibc}/lib/crtn.c
    run_step "tcc bootstrap libc.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/libc.o ${mesLibc}/lib/libc.c
    run_step "tcc bootstrap libgetopt.c" ./tcc -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o bootstrap-libs/libgetopt.o ${mesLibc}/lib/libgetopt.c
    fi
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "tcc bootstrap empty libtcc1.c" ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o bootstrap-libs/libtcc1.o ${support}/tcc-aarch64-empty.c
    else
    run_step "tcc bootstrap libtcc1.c" ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o bootstrap-libs/libtcc1.o lib/libtcc1.c
    fi
    ${lib.optionalString (!targetCfg.buildArm64Lib) ''
    run_step "tcc bootstrap alloca.S" ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o bootstrap-libs/alloca.o lib/alloca.S
    ''}
    ${lib.optionalString targetCfg.buildArm64Lib ''
    run_step "tcc bootstrap lib-arm64.c" ./tcc -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o bootstrap-libs/lib-arm64.o lib/lib-arm64.c
    ''}
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "make bootstrap libc.a" make_ar ./tcc bootstrap-libs/libc.a bootstrap-libs/aarch64-runtime.o bootstrap-libs/aarch64-syscalls.o bootstrap-libs/tcc-bootstrap-support.o
    else
    run_step "make bootstrap libc.a" make_ar ./tcc bootstrap-libs/libc.a bootstrap-libs/libc.o
    fi
    run_step "make bootstrap libgetopt.a" make_ar ./tcc bootstrap-libs/libgetopt.a bootstrap-libs/libgetopt.o
    run_step "make bootstrap libtcc1.a" make_ar ./tcc bootstrap-libs/libtcc1.a bootstrap-libs/libtcc1.o ${targetCfg.libtcc1ExtraBootstrap}

    if [ "$target_is_aarch64" = 1 ]; then
      bootstrap_link_prefix="-nostdlib bootstrap-libs/crt1.o bootstrap-libs/crti.o"
      bootstrap_link_suffix="bootstrap-libs/aarch64-runtime.o bootstrap-libs/aarch64-syscalls.o bootstrap-libs/tcc-bootstrap-support.o bootstrap-libs/libgetopt.o bootstrap-libs/libtcc1.o bootstrap-libs/lib-arm64.o bootstrap-libs/crtn.o"
    else
      bootstrap_link_prefix="-nostdlib bootstrap-libs/crt1.o bootstrap-libs/crti.o"
      bootstrap_link_suffix="bootstrap-libs/libc.o bootstrap-libs/libtcc1.o bootstrap-libs/crtn.o"
    fi

    run_step "tcc self-build stage2" ./tcc $bootstrap_link_prefix \
      -I . \
      -I "$tcc_include_src" \
      -I "$mes_include_src" \
      -D__linux__=1 \
      -DBOOTSTRAP=1 \
      -DHAVE_LONG_LONG=1 \
      -DHAVE_SETJMP=1 \
      -DHAVE_BITFIELD=1 \
      -DHAVE_FLOAT=1 \
      ${tccTargetDefineArg} \
      -Dinline= \
      -DCONFIG_TCCDIR=\"\" \
      -DCONFIG_SYSROOT=\"\" \
      -DCONFIG_TCC_CRTPREFIX=\"{B}\" \
      -DCONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -DCONFIG_TCC_LIBPATHS=\"{B}\" \
      -DCONFIG_TCC_SYSINCLUDEPATHS=\"$out/include\" \
      -DTCC_LIBGCC=\"libc.a\" \
      -DTCC_LIBTCC1=\"libtcc1.a\" \
      -DCONFIG_TCC_LIBTCC1_MES=0 \
      -DCONFIG_TCC_STATIC=1 \
      -DCONFIG_USE_LIBGCC=1 \
      -DTCC_MES_LIBC=1 \
      -DTCC_VERSION=\"0.9.28-${version}\" \
      -DONE_SOURCE=1 \
      -DCONFIG_TCC_SEMLOCK=0 \
      tcc.c \
      $bootstrap_link_suffix \
      -o tcc-stage2

    run_step "tcc-stage2 self-build stage3" ./tcc-stage2 $bootstrap_link_prefix \
      -I . \
      -I "$tcc_include_src" \
      -I "$mes_include_src" \
      -D__linux__=1 \
      -DBOOTSTRAP=1 \
      -DHAVE_LONG_LONG=1 \
      -DHAVE_SETJMP=1 \
      -DHAVE_BITFIELD=1 \
      -DHAVE_FLOAT=1 \
      ${tccTargetDefineArg} \
      -Dinline= \
      -DCONFIG_TCCDIR=\"\" \
      -DCONFIG_SYSROOT=\"\" \
      -DCONFIG_TCC_CRTPREFIX=\"{B}\" \
      -DCONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -DCONFIG_TCC_LIBPATHS=\"{B}\" \
      -DCONFIG_TCC_SYSINCLUDEPATHS=\"$out/include\" \
      -DTCC_LIBGCC=\"libc.a\" \
      -DTCC_LIBTCC1=\"libtcc1.a\" \
      -DCONFIG_TCC_LIBTCC1_MES=0 \
      -DCONFIG_TCC_STATIC=1 \
      -DCONFIG_USE_LIBGCC=1 \
      -DTCC_MES_LIBC=1 \
      -DTCC_VERSION=\"0.9.28-${version}\" \
      -DONE_SOURCE=1 \
      -DCONFIG_TCC_SEMLOCK=0 \
      tcc.c \
      $bootstrap_link_suffix \
      -o tcc-stage3

    mkdir -p final-libs
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "as final aarch64 crt1.s" assemble_aarch64_support_object final-libs/crt1.o ${support}/tcc-aarch64-crt1.s
    run_step "tcc-stage3 final aarch64 crti.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/crti.o ${support}/tcc-aarch64-empty.c
    run_step "tcc-stage3 final aarch64 crtn.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/crtn.o ${support}/tcc-aarch64-empty.c
    run_step "tcc-stage3 final aarch64 runtime.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/aarch64-runtime.o ${support}/tcc-aarch64-runtime.c
    run_step "as final aarch64 syscalls.s" assemble_aarch64_support_object final-libs/aarch64-syscalls.o ${support}/tcc-aarch64-syscalls.s
    run_step "tcc-stage3 final support.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/tcc-bootstrap-support.o ${support}/tcc-bootstrap-support.c
    run_step "tcc-stage3 final libgetopt.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/libgetopt.o ${mesLibc}/lib/libgetopt.c
    else
    run_step "tcc-stage3 final crt1.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/crt1.o ${mesLibc}/lib/crt1.c
    run_step "tcc-stage3 final crti.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/crti.o ${mesLibc}/lib/crti.c
    run_step "tcc-stage3 final crtn.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/crtn.o ${mesLibc}/lib/crtn.c
    run_step "tcc-stage3 final libc.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/libc.o ${mesLibc}/lib/libc.c
    run_step "tcc-stage3 final libgetopt.c" ./tcc-stage3 -c -std=c11 -I "$tcc_include_src" -I "$mes_include_src" -o final-libs/libgetopt.o ${mesLibc}/lib/libgetopt.c
    fi
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "tcc-stage3 final empty libtcc1.c" ./tcc-stage3 -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o final-libs/libtcc1.o ${support}/tcc-aarch64-empty.c
    else
    run_step "tcc-stage3 final libtcc1.c" ./tcc-stage3 -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o final-libs/libtcc1.o lib/libtcc1.c
    fi
    ${lib.optionalString (!targetCfg.buildArm64Lib) ''
    run_step "tcc-stage3 final alloca.S" ./tcc-stage3 -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o final-libs/alloca.o lib/alloca.S
    ''}
    ${lib.optionalString targetCfg.buildArm64Lib ''
    run_step "tcc-stage3 final lib-arm64.c" ./tcc-stage3 -c -I "$tcc_include_src" -I "$mes_include_src" ${tccTargetDefineArg} -o final-libs/lib-arm64.o lib/lib-arm64.c
    ''}
    if [ "$target_is_aarch64" = 1 ]; then
    run_step "make final libc.a" make_ar ./tcc-stage3 final-libs/libc.a final-libs/aarch64-runtime.o final-libs/aarch64-syscalls.o final-libs/tcc-bootstrap-support.o
    else
    run_step "make final libc.a" make_ar ./tcc-stage3 final-libs/libc.a final-libs/libc.o
    fi
    run_step "make final libgetopt.a" make_ar ./tcc-stage3 final-libs/libgetopt.a final-libs/libgetopt.o
    run_step "make final libtcc1.a" make_ar ./tcc-stage3 final-libs/libtcc1.a final-libs/libtcc1.o ${targetCfg.libtcc1ExtraFinal}
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    if [ "${if m1ArtifactsOnly then "1" else "0"}" = 1 ]; then
      mkdir -p $out/share/tinycc-hcc-m1
      install -Dm644 tcc-expanded.c $out/share/tinycc-hcc-m1/tcc-expanded.c
      install -Dm644 tcc-bootstrap-support.i $out/share/tinycc-hcc-m1/tcc-bootstrap-support.i
      install -Dm644 tcc-bootstrap-support.M1 $out/share/tinycc-hcc-m1/tcc-bootstrap-support.M1
      install -Dm644 tcc-final-overrides.i $out/share/tinycc-hcc-m1/tcc-final-overrides.i
      install -Dm644 tcc-final-overrides.M1 $out/share/tinycc-hcc-m1/tcc-final-overrides.M1
      install -Dm644 tcc.M1 $out/share/tinycc-hcc-m1/tcc.M1
      if [ -e tcc.hccir ]; then
        install -Dm644 tcc.hccir $out/share/tinycc-hcc-m1/tcc.hccir
      fi
      if [ -e tcc-bootstrap-support.hccir ]; then
        install -Dm644 tcc-bootstrap-support.hccir $out/share/tinycc-hcc-m1/tcc-bootstrap-support.hccir
      fi
      if [ -e tcc-final-overrides.hccir ]; then
        install -Dm644 tcc-final-overrides.hccir $out/share/tinycc-hcc-m1/tcc-final-overrides.hccir
      fi
      (
        cd $out/share/tinycc-hcc-m1
        sha256sum * > SHA256SUMS
      )
    else
    install -Dm555 tcc-stage3 $out/bin/tcc
    install -Dm555 tcc $out/bin/tcc-hcc-stage1
    install -Dm555 tcc-stage2 $out/bin/tcc-stage2
    mkdir -p $out/lib
    cp final-libs/crt1.o final-libs/crti.o final-libs/crtn.o $out/lib/
    cp final-libs/libc.a final-libs/libgetopt.a final-libs/libtcc1.a $out/lib/
    mkdir -p $out/include
    cp -R ${mesLibc}/include/. $out/include/
    chmod -R u+w $out/include
    cp -R include/. $out/include/
    fi
    runHook postInstall
  '';

  doCheck = !m1ArtifactsOnly;
  checkPhase = ''
    runHook preCheck
    ./tcc -version
    ./tcc-stage2 -version
    ./tcc-stage3 -version
    check_include_flags="-I include -I ${mesLibc}/include"
    if [ "$target_is_aarch64" = 1 ]; then
      bootstrap_link_prefix="-nostdlib bootstrap-libs/crt1.o bootstrap-libs/crti.o"
      bootstrap_link_suffix="bootstrap-libs/aarch64-runtime.o bootstrap-libs/aarch64-syscalls.o bootstrap-libs/tcc-bootstrap-support.o bootstrap-libs/libgetopt.o bootstrap-libs/libtcc1.o bootstrap-libs/lib-arm64.o bootstrap-libs/crtn.o"
    else
      bootstrap_link_prefix="-nostdlib bootstrap-libs/crt1.o bootstrap-libs/crti.o"
      bootstrap_link_suffix="bootstrap-libs/libc.o bootstrap-libs/libtcc1.o bootstrap-libs/crtn.o"
    fi

    cat > include-smoke-header.h <<'EOF'
    #define HCC_INCLUDE_SMOKE 7
    EOF
    cat > include-smoke.c <<'EOF'
    #include "include-smoke-header.h"
    int main(){return HCC_INCLUDE_SMOKE;}
    EOF
    ./tcc $check_include_flags -E include-smoke.c > include-smoke.i
    ./tcc $check_include_flags -c include-smoke.c -o include-smoke.o
    test -s include-smoke.o

    cat > macro-smoke.c <<'EOF'
    #define HCC_MACRO(NAME, CODE, STRING) NAME=CODE,
    enum { HCC_MACRO(HCC_VALUE, 0x20, "value") HCC_LAST };
    EOF
    ./tcc $check_include_flags -E macro-smoke.c > macro-smoke.i
    ./tcc $check_include_flags -c macro-smoke.c -o macro-smoke.o
    test -s macro-smoke.o

    printf '%s\n' 'int main(){return 13;}' > smoke.c
    ./tcc $check_include_flags -c smoke.c -o smoke.o
    test -s smoke.o

    cat > float-const-smoke.c <<'EOF'
    float hcc_float_const = -1.0f;
    double hcc_double_const = -1.0;
    int main(){return 0;}
    EOF
    ./tcc $check_include_flags -c float-const-smoke.c -o float-const-smoke.o
    test -s float-const-smoke.o

    printf '%s\n' 'int f(void){return 17;} int main(void){return f();}' > internal-call-smoke.c
    ./tcc $bootstrap_link_prefix \
      $check_include_flags \
      internal-call-smoke.c \
      $bootstrap_link_suffix \
      -o internal-call-smoke
    set +e
    ./internal-call-smoke
    internal_call_status="$?"
    set -e
    test "$internal_call_status" -eq 17

    printf '%s\n' 'void f(char a[static 10]){a[0]=1;} int main(void){char a[10]; f(a); return a[0];}' > static-array-param.c
    ./tcc-stage3 $check_include_flags -c static-array-param.c -o static-array-param.o
    test -s static-array-param.o

    ./tcc-stage3 -ar rc empty.a
    test -s empty.a

    ./tcc-stage3 -c \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      ${targetDefineArg} \
      -D inline= \
      -D CONFIG_TCCDIR=\"\" \
      -D CONFIG_SYSROOT=\"\" \
      -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
      -D CONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -D CONFIG_TCC_LIBPATHS=\"{B}\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\"$PWD/include:${mesLibc}/include\" \
      -D TCC_LIBGCC=\"libc.a\" \
      -D TCC_LIBTCC1=\"libtcc1.a\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\"0.9.28-${version}\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c -o tcc-stage3-selfhost.o
    test -s tcc-stage3-selfhost.o

    if [ "$target_is_aarch64" = 1 ]; then
    ./tcc-stage3 -c \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      ${targetDefineArg} \
      ${support}/tcc-aarch64-empty.c -o libtcc1.o
    else
    ./tcc-stage3 -c \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      ${targetDefineArg} \
      -D TCC_MES_LIBC=1 \
      lib/libtcc1.c -o libtcc1.o
    fi
    ./tcc-stage3 -ar rcs libtcc1.a libtcc1.o
    test -s libtcc1.a

    ./tcc-stage3 -B final-libs $check_include_flags smoke.c -o smoke-linked
    set +e
    ./smoke-linked
    smoke_status="$?"
    set -e
    test "$smoke_status" -eq 13

    ./tcc-stage2 $bootstrap_link_prefix $check_include_flags internal-call-smoke.c $bootstrap_link_suffix -o internal-call-stage2
    set +e
    ./internal-call-stage2
    stage2_status="$?"
    set -e
    test "$stage2_status" -eq 17

    printf '%s\n' 'int f(void){return 31;} int main(void){return f();}' > internal-call-stage3.c
    ./tcc-stage3 -B final-libs $check_include_flags internal-call-stage3.c -o internal-call-stage3
    set +e
    ./internal-call-stage3
    stage3_status="$?"
    set -e
    test "$stage3_status" -eq 31

    ./tcc-stage3 -B final-libs \
      -I . \
      -I include \
      -I ${mesLibc}/include \
      -D __linux__=1 \
      -D BOOTSTRAP=1 \
      -D HAVE_LONG_LONG=1 \
      -D HAVE_SETJMP=1 \
      -D HAVE_BITFIELD=1 \
      -D HAVE_FLOAT=1 \
      ${targetDefineArg} \
      -D inline= \
      -D CONFIG_TCCDIR=\"\" \
      -D CONFIG_SYSROOT=\"\" \
      -D CONFIG_TCC_CRTPREFIX=\"{B}\" \
      -D CONFIG_TCC_ELFINTERP=\"/mes/loader\" \
      -D CONFIG_TCC_LIBPATHS=\"{B}\" \
      -D CONFIG_TCC_SYSINCLUDEPATHS=\"$out/include\" \
      -D TCC_LIBGCC=\"libc.a\" \
      -D TCC_LIBTCC1=\"libtcc1.a\" \
      -D CONFIG_TCC_LIBTCC1_MES=0 \
      -D CONFIG_TCC_STATIC=1 \
      -D CONFIG_USE_LIBGCC=1 \
      -D TCC_MES_LIBC=1 \
      -D TCC_VERSION=\"0.9.28-${version}\" \
      -D ONE_SOURCE=1 \
      -D CONFIG_TCC_SEMLOCK=0 \
      tcc.c -o tcc-stage4
    ./tcc-stage4 -version
    printf '%s\n' 'int f(void){return 37;} int main(void){return f();}' > internal-call-stage4.c
    ./tcc-stage4 -B final-libs $check_include_flags internal-call-stage4.c -o internal-call-stage4
    set +e
    ./internal-call-stage4
    stage4_status="$?"
    set -e
    test "$stage4_status" -eq 37

    runHook postCheck
  '';

  meta = with lib; {
    description = "Bootstrappable tinycc built through the GHC-backed hcc driver";
    homepage = "https://gitlab.com/janneke/tinycc";
    license = licenses.lgpl21Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
