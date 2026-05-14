{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  tinycc,
  gnumake,
  gnupatch,
  gnused,
  gnugrep,
  gnutar,
  gzip,
  hccTinyccVaList ? false,
  enableShared ? false,
}:

let
  pname = "musl";
  version = "1.2.6";
  meta = {
    description = "Efficient, small, quality libc implementation";
    homepage = "https://musl.libc.org";
    license = lib.licenses.mit;
    teams = [ lib.teams.minimal-bootstrap ];
    platforms = lib.platforms.unix;
  };

  src = fetchurl {
    url = "https://musl.libc.org/releases/musl-${version}.tar.gz";
    hash = "sha256-1YX9O2E8ZhUfwySejtRPdwIMtebB5jWmFtP5+CRgUSo=";
  };

  liveBootstrap = "https://github.com/fosslinux/live-bootstrap/raw/d98f97e21413efc32c770d0356f1feda66025686/sysa/musl-1.1.24";
  patches = [
    # Reuse live-bootstrap's sigsetjmp fix for TinyCC's jecxz limitation.
    (fetchurl {
      url = "${liveBootstrap}/patches/sigsetjmp.patch";
      hash = "sha256-wd2Aev1zPJXy3q933aiup5p1IMKzVJBquAyl3gbK4PU=";
    })
    ../../patches/upstreams/musl-runtime-shell-path.patch
    ../../patches/upstreams/musl-tinycc-no-plt.patch
  ]
  ++ lib.optional enableShared ../../patches/upstreams/musl-tinycc-dynamic-loader.patch
  ++ lib.optional hccTinyccVaList ../../patches/upstreams/musl-hcc-tinycc-va-list.patch;
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      tinycc.compiler
      gnumake
      gnupatch
      gnused
      gnugrep
      gnutar
      gzip
    ];
  }
  ''
    tcc_command=${if enableShared then "${tinycc.compiler.tinycc-musl}/libexec/tcc" else "tcc"}

    tar xzf ${src}
    cd musl-${version}

    ${lib.concatMapStringsSep "\n" (f: "patch -Np0 -i ${f}") patches}
    # TinyCC does not support C complex types here.
    rm -rf src/complex
    # musl configure expects /dev to exist.
    mkdir -p /dev

    # Avoid impure /bin/sh in helper scripts.
    sed -i 's|/bin/sh|${bash}/bin/bash|' \
      tools/*.sh
    chmod 755 tools/*.sh

    # Drop asm-constraint cases that musl replaces with C fallbacks.
    rm src/math/i386/*.c
    rm src/math/x86_64/*.c

    ${lib.optionalString enableShared ''
      # TinyCC synthesizes these section boundary symbols while linking shared
      # objects, so musl's dynamic loader must not also define them.
      sed -i \
        -e 's|^hidden void (\*const __init_array_start)(void)=0, (\*const __fini_array_start)(void)=0;|#ifndef __TINYC__\n&\n#endif|' \
        -e 's|^weak_alias(__init_array_start, __init_array_end);|#ifndef __TINYC__\n&|' \
        -e 's|^weak_alias(__fini_array_start, __fini_array_end);|&\n#endif|' \
        ldso/dynlink.c

    ''}

    bash ./configure \
      --prefix=$out \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      ${lib.optionalString (!enableShared) "--disable-shared"} \
      CC="$tcc_command"

    # Parallel TinyCC builds have been unstable in this bootstrap path.
    make \
      AR="$tcc_command -ar" \
      RANLIB=true \
      LIBCC="${tinycc.libs}/lib/libtcc1.a" \
      CFLAGS="-DSYSCALL_NO_TLS ${lib.optionalString enableShared "-fno-builtin"} ${lib.optionalString hccTinyccVaList "-D__HCC_TCC_VA_LIST"}"

    make install
    cp ${tinycc.libs}/lib/libtcc1.a $out/lib
  ''
