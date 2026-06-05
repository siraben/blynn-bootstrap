{
  stdenv,
  lib,
  ghc,
  perl,
  src,
}:

stdenv.mkDerivation {
  pname = "blynn-precisely-debug-ghc";
  version = "0-unstable-2026-05-06";

  inherit src;

  nativeBuildInputs = [
    ghc
    perl
  ];

  buildPhase = ''
    runHook preBuild

    mkdir ghc-src
    cp \
      inn/Base.hs \
      inn/System.hs \
      inn/AstPrecisely.hs \
      inn/Map1.hs \
      inn/ParserPrecisely.hs \
      inn/KiselyovPrecisely.hs \
      inn/Unify1.hs \
      inn/RTSPrecisely.hs \
      inn/TyperPrecisely.hs \
      inn/Obj.hs \
      inn/Charser.hs \
      inn/precisely.hs \
      ghc-src/

    cd ghc-src
    mv AstPrecisely.hs Ast.hs
    mv Map1.hs Map.hs
    mv ParserPrecisely.hs Parser.hs
    mv KiselyovPrecisely.hs Kiselyov.hs
    mv Unify1.hs Unify.hs
    mv RTSPrecisely.hs RTS.hs
    mv TyperPrecisely.hs Typer.hs
    mv precisely.hs Main.hs

    export PRELUDE_IMPORT='import Prelude hiding (getChar, putChar, getContents, putStr, putStrLn, interact, liftA2, many, some)'
    perl -0pi -e 's/(module Base where\n)/$1$ENV{PRELUDE_IMPORT}\n/' Base.hs
    for f in *.hs; do
      if [ "$f" != Base.hs ]; then
        perl -0pi -e 's/import Base/$ENV{PRELUDE_IMPORT}\nimport Base/' "$f"
      fi
    done
    perl -0pi -e 's/(module Obj where\n)/$1import Text.RawString.QQ\n/' Obj.hs

    sed -i '$r ${./precisely-debug-ghc/base-compat.hs}' Base.hs
    install -m 644 ${./precisely-debug-ghc/System.hs} System.hs

    perl -0pi -e 's/\n-- Hash consing\.\ninstance \(Ord a, Ord b\) => Ord \(Either a b\) where\n.*?\nmemget /\n-- Hash consing.\nmemget /s' RTS.hs
    perl -0pi -e "s/Basic \[chr \\\$ intFromWord h\]/Basic (\"#num\" ++ show h)/" RTS.hs
    perl -0pi -e "s/Basic \[h\] -> Right <\\\$> memget \(Right \\\$ comEnum \"NUM\", Right \\\$ ord h\)/Basic ('#':'n':'u':'m':digits) -> Right <\\\$> memget (Right \\\$ comEnum \"NUM\", Right \\\$ fromInteger \\\$ readInteger digits)\\n    Basic [h] -> Right <\\\$> memget (Right \\\$ comEnum \"NUM\", Right \\\$ ord h)/" RTS.hs

    ghc \
      -cpp \
      -D'hide_prelude_here=--' \
      -D'import_qq_here=import Text.RawString.QQ --' \
      -XNoImplicitPrelude \
      -XQuasiQuotes \
      -XBlockArguments \
      -XLambdaCase \
      -XTupleSections \
      -XNoMonomorphismRestriction \
      -XMonoLocalBinds \
      -package raw-strings-qq \
      -O0 \
      -g \
      -i. \
      Main.hs \
      -o precisely_up

    cd ..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ghc-src/precisely_up $out/bin/precisely_up
    mkdir -p $out/share/blynn-precisely-debug-ghc
    cp ghc-src/*.hs $out/share/blynn-precisely-debug-ghc/
    runHook postInstall
  '';

  meta = with lib; {
    description = "GHC-built Blynn precisely with fail#/join# debug traps";
    homepage = "https://github.com/blynn/compiler";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
