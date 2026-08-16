{
  stdenv,
  lib,
  fetchurl,
  binutils,
  bzip2,
  gawk,
  glibcStatic,
  gmp,
  gmpStatic,
  gnumake,
  libmpc,
  libmpcStatic,
  m1Artifacts,
  mpfr,
  mpfrStatic,
  perl,
  texinfo,
  zlib,
  zlibStatic,
  pname ? "hcc-gcc46-direct-link",
}:

stdenv.mkDerivation {
  inherit pname;
  version = "4.6.4";

  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-4.6.4/gcc-4.6.4.tar.bz2";
    hash = "sha256-Na8Wr6C2evm46xXK+3bSvF9WhUBVJSL13CyI3UXZd+g=";
  };

  nativeBuildInputs = [
    binutils
    bzip2
    gawk
    gnumake
    perl
    texinfo
  ];

  buildInputs = [
    gmp
    libmpc
    mpfr
    zlib
  ];

  hardeningDisable = [ "all" ];

  unpackPhase = ''
    runHook preUnpack
    tar -xjf "$src"
    runHook postUnpack
  '';

  configurePhase = ''
    runHook preConfigure
    printf 'direct-configure-start\t%s\n' "$(date +%s)" > direct-link-events.tsv
    mkdir obj
    cd obj
    ../gcc-4.6.4/configure \
      --disable-bootstrap \
      --disable-decimal-float \
      --disable-dependency-tracking \
      --disable-libatomic \
      --disable-libcilkrts \
      --disable-libgomp \
      --disable-libitm \
      --disable-libmudflap \
      --disable-libquadmath \
      --disable-libsanitizer \
      --disable-libssp \
      --disable-libvtv \
      --disable-lto \
      --disable-lto-plugin \
      --disable-multilib \
      --disable-plugin \
      --disable-threads \
      --enable-languages=c \
      --enable-static \
      --disable-shared \
      --enable-threads=single \
      --disable-libstdcxx-pch \
      --disable-build-with-cxx \
      --with-gmp-include=${lib.getDev gmp}/include \
      --with-gmp-lib=${lib.getLib gmp}/lib \
      --with-mpfr-include=${lib.getDev mpfr}/include \
      --with-mpfr-lib=${lib.getLib mpfr}/lib \
      --with-mpc-include=${lib.getDev libmpc}/include \
      --with-mpc-lib=${lib.getLib libmpc}/lib
    cd ..

    make -C obj \
      all-build-libiberty \
      configure-gcc \
      configure-libcpp \
      configure-libiberty \
      configure-libdecnumber
    printf 'direct-configure-end\t%s\n' "$(date +%s)" >> direct-link-events.tsv
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    metrics_file="$PWD/direct-link-events.tsv"
    printf 'support-start\t%s\n' "$(date +%s)" >> "$metrics_file"
    support_cflags="-g -O2 -Wno-error=format-security"
    make -C obj/libiberty -j "$NIX_BUILD_CORES" CFLAGS="$support_cflags"
    make -C obj/libcpp -j "$NIX_BUILD_CORES" CFLAGS="$support_cflags"
    make -C obj/libdecnumber -j "$NIX_BUILD_CORES" CFLAGS="$support_cflags"

    objcopy \
      --redefine-sym cpp_interpret_integer=hcc_host_cpp_interpret_integer \
      --redefine-sym cpp_num_sign_extend=hcc_host_cpp_num_sign_extend \
      obj/libcpp/libcpp.a obj/libcpp/libcpp-hcc-abi.a
    cc -O2 -c ${../hcc/support/libcpp-abi-adapter.c} \
      -Iobj/libcpp \
      -Igcc-4.6.4/libcpp \
      -Igcc-4.6.4/libcpp/include \
      -Igcc-4.6.4/include \
      -o libcpp-abi-adapter.o

    cc -std=c89 -pedantic -Wall -Wextra -Werror \
      ${../hcc/cbits/m1_to_gas.c} -o m1-to-gas
    cc -O2 -ffunction-sections -fdata-sections \
      -c ${../hcc/support/direct-link-builtins.c} \
      -I${lib.getDev zlib}/include -o direct-link-builtins.o
    cc -std=c99 -O2 -ffunction-sections -fdata-sections \
      -Wall -Wextra -Werror \
      -c ${../hcc/support/soft-float.c} -o soft-float.o
    objcopy \
      --redefine-sym hcc_builtin_alloca=__builtin_alloca \
      --redefine-sym hcc_builtin_clzl=__builtin_clzl \
      --redefine-sym hcc_builtin_ctzl=__builtin_ctzl \
      --redefine-sym hcc_builtin_ffsl=__builtin_ffsl \
      --redefine-sym hcc_builtin_popcountl=__builtin_popcountl \
      --redefine-sym hcc_deflate_init=deflateInit \
      --redefine-sym hcc_inflate_init=inflateInit \
      direct-link-builtins.o
    ar crs hcc-runtime.a direct-link-builtins.o soft-float.o
    printf 'support-end\t%s\n' "$(date +%s)" >> "$metrics_file"

    artifacts=${m1Artifacts}/share/hcc-gcc46-source-smoke
    make -s -C obj/gcc \
      --eval='.PHONY: hcc-direct-link-lists
      hcc-direct-link-lists:
	@printf "direct %s\n" $(C_OBJS) cc1-checksum.o main.o
	@printf "backend %s\n" $(OBJS)' \
      hcc-direct-link-lists > cc1-link-lists.txt
    mkdir -p elf
    printf 'translate-start\t%s\n' "$(date +%s)" >> "$metrics_file"
    translate_object() {
      object=$1
      input="$artifacts/m1/$object.M1"
      stem="elf/$object"
      mkdir -p "$(dirname "$stem")"

      duplicate=$(gawk '
        /^:/ {
          label = substr($0, 2)
          sub(/^FUNCTION_/, "", label)
          if (++seen[label] == 2) { print label; exit }
        }
      ' "$input")
      test -z "$duplicate" || {
        echo "duplicate normalized M1 definition in $object: $duplicate" >&2
        exit 1
      }

      ./m1-to-gas "$input" "$stem.s"
      as --64 -o "$stem.o" "$stem.s"
    }
    export -f translate_object
    export artifacts
    translate_jobs="$NIX_BUILD_CORES"
    if [ "$translate_jobs" -gt 4 ]; then translate_jobs=4; fi
    xargs -r -n 1 -P "$translate_jobs" \
      bash -c 'set -eu; translate_object "$1"' _ \
      < "$artifacts/stage1-objects.txt"
    unset -f translate_object
    printf 'translate-end\t%s\n' "$(date +%s)" >> "$metrics_file"

    readarray -t backend_objects < <(
      gawk '$1 == "backend" { print $2 }' cc1-link-lists.txt
    )
    backend_args=()
    for object in "''${backend_objects[@]}"; do
      backend_args+=("elf/$object.o")
    done
    ar crs elf/libbackend.a "''${backend_args[@]}"

    link_role() {
      role=$1
      output=$2
      shift 2
      if [ "$role" = cc1 ]; then
        readarray -t role_objects < <(
          gawk '$1 == "direct" { print $2 }' cc1-link-lists.txt
        )
      else
        readarray -t role_objects < <(
          gawk -v role="$role" '$1 == role { print $2 }' \
            "$artifacts/stage1-link-manifest.txt"
        )
      fi
      object_args=()
      for object in "''${role_objects[@]}"; do
        object_args+=("elf/$object.o")
      done
      backend_arg=()
      if [ "$role" = cc1 ]; then backend_arg=(elf/libbackend.a); fi
      cc -static -fno-pie -no-pie -o "$output" \
        "''${object_args[@]}" "''${backend_arg[@]}" \
        hcc-runtime.a \
        libcpp-abi-adapter.o obj/libcpp/libcpp-hcc-abi.a \
        obj/libiberty/libiberty.a obj/libdecnumber/libdecnumber.a \
        -L${glibcStatic}/lib \
        -L${gmpStatic}/lib \
        -L${mpfrStatic}/lib \
        -L${libmpcStatic}/lib \
        -L${zlibStatic}/lib \
        "$@" -lz
    }

    printf 'link-start\t%s\n' "$(date +%s)" >> "$metrics_file"
    link_role xgcc xgcc -ldl
    link_role collect2 collect2 -ldl
    link_role cc1 cc1 \
      -lmpc -lmpfr -lgmp \
      -ldl
    printf 'link-end\t%s\n' "$(date +%s)" >> "$metrics_file"

    ./xgcc --version > xgcc-version.txt

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    gcc_libexec="$out/libexec/gcc/x86_64-pc-linux-gnu/4.6.4"
    gcc_support="$out/lib/gcc/x86_64-pc-linux-gnu/4.6.4"
    mkdir -p \
      "$out/bin" "$gcc_libexec" "$gcc_support" \
      "$out/share/hcc-gcc46-direct-link"
    install -m555 xgcc "$gcc_libexec/xgcc"
    install -m555 cc1 "$gcc_libexec/cc1"
    install -m555 collect2 "$gcc_libexec/collect2"
    install -m555 m1-to-gas "$out/bin/m1-to-gas"

    # The seed compiler supplies its own driver and cc1, but uses the host's
    # target ABI support objects.  Copy them rather than retaining a reference
    # to the host compiler: the resulting compiler route has no TCC compiler
    # bridge in its runtime closure.
    for file in \
      libgcc.a libgcc_eh.a \
      crtbegin.o crtbeginS.o crtbeginT.o crtend.o crtendS.o
    do
      source_path=$(cc -print-file-name="$file")
      test "$source_path" != "$file"
      cp "$source_path" "$gcc_support/$file"
    done
    mkdir "$gcc_support/include"
    cp gcc-4.6.4/gcc/ginclude/* "$gcc_support/include/"
    cat \
      gcc-4.6.4/gcc/limitx.h \
      gcc-4.6.4/gcc/glimits.h \
      gcc-4.6.4/gcc/limity.h \
      > "$gcc_support/include/limits.h"
    cat > "$gcc_support/include/syslimits.h" <<'EOF_SYSLIMITS'
/* Delegate the system-specific limits to the libc header searched next.  */
#define _GCC_NEXT_LIMITS_H
#include_next <limits.h>
#undef _GCC_NEXT_LIMITS_H
EOF_SYSLIMITS
    cp gcc-4.6.4/gcc/ginclude/stdint-wrap.h \
      "$gcc_support/include/stdint.h"
    cat > "$out/bin/gcc" <<EOF_GCC
#!/bin/sh
export PATH="${binutils}/bin:\$PATH"
exec "$gcc_libexec/xgcc" \
  -B"$gcc_libexec/" \
  -B"$gcc_support/" \
  -isystem "$gcc_support/include" \
  -isystem "${lib.getDev stdenv.cc.libc}/include" \
  -B"${stdenv.cc.libc}/lib/" \
  -Wl,-dynamic-linker,"${stdenv.cc.libc}/lib/ld-linux-x86-64.so.2" \
  "\$@"
EOF_GCC
    chmod 555 "$out/bin/gcc"
    ln -s gcc "$out/bin/cc"

    cp xgcc-version.txt "$out/share/hcc-gcc46-direct-link/"

    "$out/bin/gcc" --version
    printf '%s\n' \
      '#include <float.h>' \
      '#include <stddef.h>' \
      '#include <stdio.h>' \
      'static int triple_plus_one(int x) { return x * 3 + 1; }' \
      'static double double_value(double x) { return x * 2.0; }' \
      'static long register_roundtrip(long x) {' \
      '  long y;' \
      '  __asm__("mov %1,%0" : "=r"(y) : "r"(x));' \
      '  return y;' \
      '}' \
      'int main(void) {' \
      '  return sizeof(size_t) != 8 || DBL_MIN <= 0.0 || DBL_EPSILON <= 0.0' \
      '    || double_value(1.5) != 3.0 || triple_plus_one(7) != 22' \
      '    || register_roundtrip(17) != 17;' \
      '}' \
      > direct-smoke.c
    printf 'smoke-compile-start\t%s\n' "$(date +%s)" >> direct-link-events.tsv
    "$out/bin/gcc" -O2 -c direct-smoke.c -o direct-smoke.o
    printf 'smoke-compile-end\t%s\n' "$(date +%s)" >> direct-link-events.tsv
    test -s direct-smoke.o
    printf 'smoke-link-start\t%s\n' "$(date +%s)" >> direct-link-events.tsv
    "$out/bin/gcc" direct-smoke.o -o direct-smoke
    printf 'smoke-link-end\t%s\n' "$(date +%s)" >> direct-link-events.tsv
    ./direct-smoke
    cp direct-link-events.tsv "$out/share/hcc-gcc46-direct-link/"

    event_seconds() {
      start=$(gawk -v event="$1-start" '$1 == event { print $2; exit }' direct-link-events.tsv)
      end=$(gawk -v event="$1-end" '$1 == event { print $2; exit }' direct-link-events.tsv)
      test -n "$start"
      test -n "$end"
      echo "$((end - start))"
    }
    hcc_sweep_seconds=$(sed -n 's/^hcc-source-to-m1-seconds: //p' \
      ${m1Artifacts}/share/hcc-gcc46-source-smoke/summary.txt)
    gcc_configure_seconds=$(sed -n 's/^gcc-configure-seconds: //p' \
      ${m1Artifacts}/share/hcc-gcc46-source-smoke/summary.txt)
    test -n "$hcc_sweep_seconds"
    test -n "$gcc_configure_seconds"
    direct_configure_seconds=$(event_seconds direct-configure)
    support_seconds=$(event_seconds support)
    translate_seconds=$(event_seconds translate)
    link_seconds=$(event_seconds link)
    smoke_compile_seconds=$(event_seconds smoke-compile)
    smoke_link_seconds=$(event_seconds smoke-link)
    translate_jobs="$NIX_BUILD_CORES"
    if [ "$translate_jobs" -gt 4 ]; then translate_jobs=4; fi
    {
      echo 'gcc: 4.6.4'
      echo 'stage1 C objects: HCC -> M1 -> m1-to-gas -> GNU as'
      echo "stage1-object-count: $(wc -l < ${m1Artifacts}/share/hcc-gcc46-source-smoke/stage1-objects.txt)"
      echo 'support: host-assisted soft-float adapter, libcpp, libiberty, libdecnumber, libc, GMP, MPFR, MPC, zlib'
      echo 'headers: GCC 4.6 ginclude plus host glibc development headers'
      echo 'host-library-linkage: static'
      echo 'linker: GNU ld through the host cc driver'
      echo 'tinycc: absent'
      echo 'smoke-optimization: -O2'
      echo 'result: ok'
      echo "gcc-configure-seconds: $gcc_configure_seconds"
      echo "hcc-source-to-m1-seconds: $hcc_sweep_seconds"
      echo "direct-configure-seconds: $direct_configure_seconds"
      echo "support-seconds: $support_seconds"
      echo "translate-jobs: $translate_jobs"
      echo "translate-assemble-seconds: $translate_seconds"
      echo "link-seconds: $link_seconds"
      echo "smoke-compile-seconds: $smoke_compile_seconds"
      echo "smoke-link-seconds: $smoke_link_seconds"
      echo "measured-stage-seconds: $((gcc_configure_seconds + hcc_sweep_seconds + direct_configure_seconds + support_seconds + translate_seconds + link_seconds + smoke_compile_seconds + smoke_link_seconds))"
      echo "xgcc-bytes: $(wc -c < "$gcc_libexec/xgcc")"
      echo "cc1-bytes: $(wc -c < "$gcc_libexec/cc1")"
      echo "collect2-bytes: $(wc -c < "$gcc_libexec/collect2")"
    } > "$out/share/hcc-gcc46-direct-link/summary.txt"

    runHook postInstall
  '';

  meta = {
    description = "Host-assisted direct ELF link of HCC-produced GCC 4.6.4 stage1 objects";
    platforms = lib.platforms.x86_64;
  };
}
