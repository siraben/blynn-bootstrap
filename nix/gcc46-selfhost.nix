{ stdenvNoCC
, lib
, fetchurl
, bash
, binutils
, coreutils
, diffutils
, findutils
, gawk
, gnumake
, gnugrep
, gnupatch
, gnused
, gnutar
, gzip
, seedGcc
, seedLibc
, seedLibcDev ? seedLibc
, wrapSeedFixxfdi ? true
, patchGlibcUcontext ? false
, bootstrap ? true
, pname ? "gcc46-selfhost"
}:

let
  gccCore = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-4.6.4/gcc-core-4.6.4.tar.gz";
    hash = "sha256-5TSlywWrg51897JJb9XfQudjUpJsHPDZTedhhMJqc5w=";
  };
  gccGxx = fetchurl {
    url = "https://ftp.gnu.org/gnu/gcc/gcc-4.6.4/gcc-g++-4.6.4.tar.gz";
    hash = "sha256-aQpdT2ZBgGQNsoB540YUaBksSEw31vZx3eS1On+ZGLs=";
  };
  gmpSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/gmp/gmp-4.3.2.tar.gz";
    hash = "sha256-e+OtFkG5mxf2qL5ql28flU6ZfEHpGa1+DEGP6EjBPJc=";
  };
  mpfrSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpfr/mpfr-2.4.2.tar.gz";
    hash = "sha256-JG1+GEBIsfxI02lt0wLJd04k6SEgQiFUB0XlRkAitjc=";
  };
  mpcSrc = fetchurl {
    url = "https://ftp.gnu.org/gnu/mpc/mpc-1.0.3.tar.gz";
    hash = "sha256-YX3sxuoJiJ+wjt4zCRegCxaAm424jCnDG/u0nL+I7MM=";
  };

  configureFlags = [
    "--build=x86_64-unknown-linux-gnu"
    "--host=x86_64-unknown-linux-gnu"
    "--with-native-system-header-dir=${seedLibcDev}/include"
    "--with-build-sysroot=${seedLibcDev}/include"
    "--disable-decimal-float"
    "--disable-dependency-tracking"
    "--disable-libatomic"
    "--disable-libcilkrts"
    "--disable-libgomp"
    "--disable-libitm"
    "--disable-libmudflap"
    "--disable-libquadmath"
    "--disable-libsanitizer"
    "--disable-libssp"
    "--disable-libvtv"
    "--disable-lto"
    "--disable-lto-plugin"
    "--disable-multilib"
    "--disable-plugin"
    "--disable-threads"
    "--enable-languages=c"
    "--enable-static"
    "--disable-shared"
    "--enable-threads=single"
    "--disable-libstdcxx-pch"
    "--disable-build-with-cxx"
  ] ++ lib.optional (!bootstrap) "--disable-bootstrap";

  buildTarget = if bootstrap then "bootstrap" else "all-gcc";
in
stdenvNoCC.mkDerivation {
  inherit pname;
  version = "4.6.4";

  dontUnpack = true;

  nativeBuildInputs = [
    bash
    binutils
    coreutils
    diffutils
    findutils
    gawk
    gnumake
    gnugrep
    gnupatch
    gnused
    gnutar
    gzip
    seedGcc
  ];

  buildPhase = ''
    runHook preBuild

    echo "gcc46-selfhost: seedGcc=${seedGcc}"
    echo "gcc46-selfhost: seedLibc=${seedLibc}"
    echo "gcc46-selfhost: seedLibcDev=${seedLibcDev}"
    echo "gcc46-selfhost: wrapSeedFixxfdi=${if wrapSeedFixxfdi then "yes" else "no"}"
    echo "gcc46-selfhost: patchGlibcUcontext=${if patchGlibcUcontext then "yes" else "no"}"
    echo "gcc46-selfhost: bootstrap=${if bootstrap then "yes" else "no"}"

    tar xzf ${gccCore}
    tar xzf ${gccGxx}
    tar xzf ${gmpSrc}
    tar xzf ${mpfrSrc}
    tar xzf ${mpcSrc}

    cd gcc-4.6.4
    ln -s ../gmp-4.3.2 gmp
    ln -s ../mpfr-2.4.2 mpfr
    ln -s ../mpc-1.0.3 mpc
    patch -Np1 --fuzz=0 -i ${./patches/gcc46-no-system-headers.patch}
    patch -Np1 --fuzz=0 -i ${./patches/gcc46-libiberty-musl-psignal.patch}
    patch -Np1 --fuzz=0 -i ${./patches/gcc46-libgcc-fixxfdi-compat.patch}
    patch -Np1 --fuzz=0 -i ${./patches/gcc46-host-linux-ssize-max.patch}
    ${lib.optionalString patchGlibcUcontext ''
      patch -Np1 --fuzz=0 -i ${./patches/gcc46-glibc-ucontext-compat.patch}
    ''}
    cd ..

    mkdir obj
    cd obj

    export CC="${seedGcc}/bin/gcc -B ${seedLibc}/lib"
    export CFLAGS="-g -O2"
    export CFLAGS_FOR_BUILD="$CFLAGS"
    export C_INCLUDE_PATH="${seedLibcDev}/include:$(pwd)/../mpfr-2.4.2/src"
    export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
    export LIBRARY_PATH="${seedLibc}/lib"

    ${lib.optionalString wrapSeedFixxfdi ''
      # The seed musl libc was built before GCC is available and references the
      # signed long-double conversion helper under TCC's libgcc-compatible name.
      printf '%s\n' \
        'long long __fixxfdi(long double x) { return (long long)(__int128)x; }' \
        > fixxfdi.c
      $CC -c fixxfdi.c -o fixxfdi.o
      fixxfdi_obj="$PWD/fixxfdi.o"
      printf '%s\n' \
        '#!${bash}/bin/bash' \
        'link=yes' \
        'for arg in "$@"; do' \
        '  case "$arg" in' \
        '    -c|-S|-E|-M|-MM|-print-*|--version|-v|-###|-dump*) link=no ;;' \
        '  esac' \
        'done' \
        'if [ "$link" = yes ]; then' \
        "  exec ${seedGcc}/bin/gcc -B ${seedLibc}/lib \"\$@\" \"$fixxfdi_obj\"" \
        'else' \
        "  exec ${seedGcc}/bin/gcc -B ${seedLibc}/lib \"\$@\"" \
        'fi' \
        > seed-gcc
      chmod +x seed-gcc
      export CC="$PWD/seed-gcc"
    ''}
    export CC_FOR_BUILD="$CC"
    export CPP="$CC -E"
    export CPP_FOR_BUILD="$CPP"

    # Avoid "Link tests are not allowed after GCC_NO_EXECUTABLES".
    export lt_cv_shlibpath_overrides_runpath=yes
    export ac_cv_func_memcpy=yes
    export ac_cv_func_strerror=yes

    bash ../gcc-4.6.4/configure \
      --prefix="$out/gcc46-selfhost-install" \
      ${lib.escapeShellArgs configureFlags}

    metrics_file="$PWD/bootstrap-events.tsv"
    : > "$metrics_file"
    printf 'bootstrap-start\t%s\n' "$(date +%s)" >> "$metrics_file"
    if [ "${if bootstrap then "1" else "0"}" = 1 ]; then
      cat > bootstrap-metrics.mk <<EOF_BOOTSTRAP_METRICS
stage1-start::
	@printf 'stage1-start\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
stage1-end::
	@printf 'stage1-end\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
stage2-start::
	@printf 'stage2-start\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
stage2-end::
	@printf 'stage2-end\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
stage3-start::
	@printf 'stage3-start\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
stage3-end::
	@printf 'stage3-end\\t%s\\n' "\$\$(date +%s)" >> "$metrics_file"
EOF_BOOTSTRAP_METRICS
      MAKEFILES="$PWD/bootstrap-metrics.mk" make -j "$NIX_BUILD_CORES" ${buildTarget}
    else
      make -j "$NIX_BUILD_CORES" ${buildTarget}
    fi
    printf 'bootstrap-end\t%s\n' "$(date +%s)" >> "$metrics_file"

    cd ..
    mkdir -p "$out/share/gcc46-selfhost"
    install -Dm644 "$metrics_file" "$out/share/gcc46-selfhost/bootstrap-events.tsv"
    bootstrap_start=$(gawk '$1 == "bootstrap-start" { print $2; exit }' "$metrics_file")
    bootstrap_end=$(gawk '$1 == "bootstrap-end" { value = $2 } END { print value }' "$metrics_file")
    {
      echo "seedGcc: ${seedGcc}"
      echo "seedLibc: ${seedLibc}"
      echo "seedLibcDev: ${seedLibcDev}"
      echo "seed-fixxfdi-wrapper: ${if wrapSeedFixxfdi then "yes" else "no"}"
      echo "glibc-ucontext-patch: ${if patchGlibcUcontext then "yes" else "no"}"
      echo "gcc: gcc-4.6.4"
      echo "bootstrap: ${if bootstrap then "yes" else "no"}"
      echo "buildTarget: ${buildTarget}"
      echo "bootstrap-seconds: $((bootstrap_end - bootstrap_start))"
      ${lib.optionalString bootstrap ''
        for stage in 1 2 3; do
          stage_start=$(gawk -v event="stage$stage-start" '$1 == event { print $2; exit }' "$metrics_file")
          stage_end=$(gawk -v event="stage$stage-end" '$1 == event { value = $2 } END { print value }' "$metrics_file")
          test -n "$stage_start"
          test -n "$stage_end"
          echo "stage$stage-seconds: $((stage_end - stage_start))"
        done
        echo 'stage2-stage3-comparison: successful'
      ''}
      echo "result: ok"
    } > "$out/share/gcc46-selfhost/summary.txt"

    if [ -x obj/gcc/xgcc ]; then
      obj/gcc/xgcc -B obj/gcc -v > "$out/share/gcc46-selfhost/xgcc-version.txt" 2>&1 || true
    fi

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';

  meta = {
    description = "GCC 4.6.4 self-host/bootstrap smoke seeded by an existing bootstrap GCC 4.6.4";
  };
}
