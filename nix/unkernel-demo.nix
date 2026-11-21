{ runCommand, fetchurl, tinycc }:
let
  sdk = fetchurl {
    url = "https://registry.npmjs.org/unkernel/-/unkernel-0.2.0-261119-040e142.tgz";
    hash = "sha256-ABZC9IHZTf1EH8KJsAWTmAbhmLBtarKyf/Tk4H184WE=";
  };
in
runCommand "unkernel-blynn-demo" { } ''
  mkdir -p "$out/sdk" guest
  tar -xzf ${sdk} --strip-components=1 -C "$out/sdk"
  cp ${../demo/unkernel/index.html} "$out/index.html"
  cp ${../demo/unkernel/demo.mjs} "$out/demo.mjs"
  cp -R ${tinycc}/share/tinycc-replay/. guest/
  substituteInPlace guest/source/config.h \
    --replace-fail '${tinycc}/include' /bootstrap/mes-include
  cp ${tinycc}/bin/tcc-hcc-stage1 guest/
  cp ${../demo/unkernel/bootstrap.sh} guest/bootstrap.sh
  tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -czf "$out/checkpoint.tar.gz" -C guest .
''
