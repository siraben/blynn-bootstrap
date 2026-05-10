{
  stdenv,
  lib,
  precisely,
  src,
  blynnSrc,
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenv.mkDerivation {
  pname = "precisely-dialect-tests";
  version = "0-unstable-2026-05-08";

  inherit src;

  nativeBuildInputs = [ precisely ];

  buildPhase = ''
    runHook preBuild

    run_case() {
      name="$1"
      main="$2"
      expected="$3"

      cat \
        ${blynnSrc}/inn/BasePrecisely.hs \
        ${blynnSrc}/inn/System.hs \
        "${../tests/hcc/precisely-dialect}/$main" \
        > "$name.hs"

      precisely_up < "$name.hs" > "$name.c"
      ${nixLib.patchGeneratedTop ''"$name.c"'' 134217728}
      $CC -O0 "$name.c" cbits/hcc_runtime.c -o "$name"
      "./$name" > "$name.out"
      grep -q "^$expected$" "$name.out"
    }

    run_case_stdin() {
      name="$1"
      main="$2"
      input="$3"
      expected="$4"

      cat \
        ${blynnSrc}/inn/BasePrecisely.hs \
        ${blynnSrc}/inn/System.hs \
        "${../tests/hcc/precisely-dialect}/$main" \
        > "$name.hs"

      precisely_up < "$name.hs" > "$name.c"
      ${nixLib.patchGeneratedTop ''"$name.c"'' 134217728}
      $CC -O0 "$name.c" cbits/hcc_runtime.c -o "$name"
      printf '%s' "$input" | "./$name" > "$name.out"
      grep -q "^$expected$" "$name.out"
    }

    run_case where Where.hs "where: ok"
    run_case local-syntax LocalSyntax.hs "local-syntax: ok"
    run_case_stdin reverse-input ReverseInput.hs "stage0" "0egats"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 where.hs $out/share/precisely-dialect-tests/where.hs
    install -Dm644 where.c $out/share/precisely-dialect-tests/where.c
    install -Dm644 where.out $out/share/precisely-dialect-tests/where.out
    install -Dm644 local-syntax.hs $out/share/precisely-dialect-tests/local-syntax.hs
    install -Dm644 local-syntax.c $out/share/precisely-dialect-tests/local-syntax.c
    install -Dm644 local-syntax.out $out/share/precisely-dialect-tests/local-syntax.out
    install -Dm644 reverse-input.hs $out/share/precisely-dialect-tests/reverse-input.hs
    install -Dm644 reverse-input.c $out/share/precisely-dialect-tests/reverse-input.c
    install -Dm644 reverse-input.out $out/share/precisely-dialect-tests/reverse-input.out
    runHook postInstall
  '';

  meta = with lib; {
    description = "Executable probes for Haskell syntax accepted by Blynn precisely";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
