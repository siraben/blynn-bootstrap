{ runCommand, fetchurl, fetchgit, patch, tinycc, oriansj, blynn, mesLibc }:
let
  pins = import ./source-pins.nix;
  stage0 = fetchgit {
    url = pins.STAGE0_POSIX_URL;
    rev = pins.STAGE0_POSIX_REV;
    fetchSubmodules = true;
    hash = "sha256-7ttlkYWAsVZuQpmxDrcxvnpIkaeGYEFmUY7PdmBtNOI=";
  };
  sdk = fetchurl {
    url = "https://registry.npmjs.org/unkernel/-/unkernel-0.2.0-261121-e69adda.tgz";
    hash = "sha256-BhwFDEvh91oOOUWs80M2Qikgl6Hj0KKUvIfGw1J/ld0=";
  };
  xterm = fetchurl {
    url = "https://registry.npmjs.org/@xterm/xterm/-/xterm-5.5.0.tgz";
    hash = "sha256-vZVPpyGHIXAYjMXX6D6I2zyDyaGKTo0kwng9JkkfWdI=";
  };
  fit = fetchurl {
    url = "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.10.0.tgz";
    hash = "sha256-kXrESXJFPV7tUu3B5QJgx2OYzkjPIpDC5gZxECu6CzM=";
  };
in
runCommand "unkernel-blynn-demo" { nativeBuildInputs = [ patch ]; } ''
  mkdir -p "$out"/{sdk,xterm,fit} guest
  tar -xzf ${sdk} --strip-components=1 -C "$out/sdk"
  tar -xzf ${xterm} --strip-components=1 -C "$out/xterm" package/LICENSE package/css/xterm.css package/lib/xterm.js
  tar -xzf ${fit} --strip-components=1 -C "$out/fit" package/LICENSE package/lib/addon-fit.js
  cp ${../demo/unkernel/index.html} "$out/index.html"
  cp ${../demo/unkernel/demo.mjs} "$out/demo.mjs"
  cp -R ${tinycc}/share/tinycc-replay/. guest/
  substituteInPlace guest/source/config.h \
    --replace-fail '${tinycc}/include' /bootstrap/mes-include
  cp ${tinycc}/bin/tcc-hcc-stage1 guest/
  cp ${../demo/unkernel/bootstrap.sh} guest/bootstrap.sh
  tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf "$out/checkpoint.tar.gz" -C guest .
  mkdir seed
  cp -R ${stage0}/{AArch64,M2libc,M2-Planet,M2-Mesoplanet,mescc-tools,aarch64.answers,after.kaem} seed/
  install -Dm555 ${stage0}/bootstrap-seeds/POSIX/AArch64/hex0-seed seed/hex0-seed
  cp ${../demo/unkernel/stage0.sh} seed/stage0.sh
  cp ${../demo/unkernel/from-seed.sh} seed/from-seed.sh
  mkdir -p seed/repo seed/upstreams
  cp -R ${../scripts} seed/repo/scripts
  cp -R ${../hcc} seed/repo/hcc
  cp -R ${../data} seed/repo/data
  cp -R ${oriansj} seed/upstreams/oriansj
  cp -R ${blynn} seed/upstreams/blynn
  cp -R ${mesLibc} seed/upstreams/mes-libc
  cp -R ${tinycc.src} seed/upstreams/tinycc
  chmod -R u+w seed/upstreams/tinycc
  patch -d seed/upstreams/tinycc -p1 < ${../patches/upstreams/tinycc-mescc-source.patch}
  tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf "$out/stage0.tar.gz" -C seed .
''
