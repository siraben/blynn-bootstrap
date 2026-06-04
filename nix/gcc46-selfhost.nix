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
    "--with-native-system-header-dir=${seedLibc}/include"
    "--with-build-sysroot=${seedLibc}/include"
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
    patch -Np1 -i ${./patches/gcc46-no-system-headers.patch}
    patch -Np1 -i ${./patches/gcc46-libiberty-musl-psignal.patch}
    patch -Np1 -i ${./patches/gcc46-libgcc-fixxfdi-compat.patch}
    patch -Np1 -i ${./patches/gcc46-host-linux-ssize-max.patch}
    cd ..

    mkdir obj
    cd obj

    export CC="${seedGcc}/bin/gcc -B ${seedLibc}/lib"
    export CFLAGS="-g -O2"
    export CFLAGS_FOR_BUILD="$CFLAGS"
    export C_INCLUDE_PATH="${seedLibc}/include:$(pwd)/../mpfr-2.4.2/src"
    export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
    export LIBRARY_PATH="${seedLibc}/lib"

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
    export CC_FOR_BUILD="$CC"

    # Avoid "Link tests are not allowed after GCC_NO_EXECUTABLES".
    export lt_cv_shlibpath_overrides_runpath=yes
    export ac_cv_func_memcpy=yes
    export ac_cv_func_strerror=yes

    bash ../gcc-4.6.4/configure \
      --prefix="$out/gcc46-selfhost-install" \
      ${lib.escapeShellArgs configureFlags}

    make -j "$NIX_BUILD_CORES" ${buildTarget}

    cd ..
    mkdir -p "$out/share/gcc46-selfhost"
    {
      echo "seedGcc: ${seedGcc}"
      echo "seedLibc: ${seedLibc}"
      echo "gcc: gcc-4.6.4"
      echo "bootstrap: ${if bootstrap then "yes" else "no"}"
      echo "buildTarget: ${buildTarget}"
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
