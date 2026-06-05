{
  lib,
  runCommand,
  closureInfo,
  coreutils,
  selectedName,
  hcc,
  tinycc,
  minimalBootstrap,
  stage0MesccTools,
  stage0MesccToolsExtra,
}:

let
  auditRoots = [
    minimalBootstrap.tinycc-bootstrappable.compiler
    minimalBootstrap.tinycc-bootstrappable.libs
    minimalBootstrap.tinycc-mes.compiler
    minimalBootstrap.tinycc-mes.libs
  ];
  closure = closureInfo {
    rootPaths = auditRoots;
  };
in
runCommand "audit-closure-trust-${lib.replaceStrings [ "." ] [ "-" ] selectedName}"
  {
    nativeBuildInputs = [
      coreutils
    ];
    meta = with lib; {
      description = "Audit selected reduced bootstrap trust path for stale MesCC TinyCC outputs";
      platforms = platforms.linux;
    };
  }
  ''
    set -eu

    report="$PWD/closure-trust-check.txt"
    fail=0

    note() {
      printf '%s\n' "$*" | tee -a "$report"
    }

    check_same() {
      label="$1"
      actual="$2"
      expected="$3"
      if [ "$actual" = "$expected" ]; then
        note "ok: $label -> $actual"
      else
        note "FAIL: $label"
        note "  expected: $expected"
        note "  actual:   $actual"
        fail=1
      fi
    }

    note "closure/trust audit for ${selectedName}"
    note ""
    note "Assumptions:"
    note "- selected path is hcc.${selectedName} feeding tinycc.${selectedName} and minimal-bootstrap override ${selectedName}"
    note "- stage0 mescc-tools and mescc-tools-extra remain legitimate assembler/linker/bootstrap tools"
    note "- tinycc-bootstrappable and tinycc-mes compiler/lib slots in the reduced path must be the HCC-built TinyCC output"
    note "- this is a conservative path audit; it does not reject unrelated MesCC source/libc/tool references"
    note ""
    note "selected hcc: ${hcc}"
    note "selected HCC TinyCC: ${tinycc}"
    note "allowed stage0 mescc-tools: ${stage0MesccTools}"
    note "allowed stage0 mescc-tools-extra: ${stage0MesccToolsExtra}"
    note ""

    check_same "minimal.tinycc-bootstrappable.compiler" \
      "${minimalBootstrap.tinycc-bootstrappable.compiler}" "${tinycc}"
    check_same "minimal.tinycc-bootstrappable.libs" \
      "${minimalBootstrap.tinycc-bootstrappable.libs}" "${tinycc}"
    check_same "minimal.tinycc-mes.compiler" \
      "${minimalBootstrap.tinycc-mes.compiler}" "${tinycc}"
    check_same "minimal.tinycc-mes.libs" \
      "${minimalBootstrap.tinycc-mes.libs}" "${tinycc}"

    note ""
    note "closure roots:"
    for root in ${lib.escapeShellArgs (map toString auditRoots)}; do
      note "- $root"
    done

    note ""
    note "scanning closure for stale TinyCC compiler outputs"
    while IFS= read -r path; do
      case "$path" in
        "${tinycc}"|"${stage0MesccTools}"|"${stage0MesccToolsExtra}")
          continue
          ;;
      esac

      base="''${path##*/}"
      case "$base" in
        *tinycc-bootstrappable*|*tinycc-mes*)
          note "FAIL: suspicious reduced-path TinyCC output in closure: $path"
          fail=1
          ;;
      esac
    done < "${closure}/store-paths"

    if [ "$fail" -ne 0 ]; then
      note ""
      note "policy: failed because the selected reduced path does not exclusively use HCC-built TinyCC in the TinyCC replacement slots."
      exit 1
    fi

    note "policy: passed; selected TinyCC replacement slots are HCC-built TinyCC, with stage0 MesCC tools allowed only as early bootstrap tools."

    mkdir -p "$out/share/audit"
    cp "$report" "$out/share/audit/closure-trust-check.txt"
    cp "${closure}/store-paths" "$out/share/audit/closure-store-paths.txt"
  ''
