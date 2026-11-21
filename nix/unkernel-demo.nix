{ runCommand, fetchurl, tinycc }:
let
  sdk = fetchurl {
    url = "https://registry.npmjs.org/unkernel/-/unkernel-0.2.0-261119-040e142.tgz";
    hash = "sha256-ABZC9IHZTf1EH8KJsAWTmAbhmLBtarKyf/Tk4H184WE=";
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
runCommand "unkernel-blynn-demo" { } ''
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
''
