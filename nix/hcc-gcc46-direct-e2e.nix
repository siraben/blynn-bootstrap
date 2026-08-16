{
  runCommand,
  closureInfo,
  coreutils,
  gawk,
  gnugrep,
  faithfulHcc,
  m1Artifacts,
  directGcc,
  gcc46Selfhost,
}:

let
  runtimeClosure = closureInfo {
    rootPaths = [
      faithfulHcc
      m1Artifacts
      directGcc
      gcc46Selfhost
    ];
  };
in
runCommand "hcc-gcc46-direct-e2e" {
  nativeBuildInputs = [
    coreutils
    gawk
    gnugrep
  ];
} ''
  hcc=${faithfulHcc}
  artifacts=${m1Artifacts}/share/hcc-gcc46-source-smoke
  direct=${directGcc}/share/hcc-gcc46-direct-link
  selfhost=${gcc46Selfhost}/share/gcc46-selfhost

  test -x "$hcc/bin/hcpp"
  test -x "$hcc/bin/hcc1"
  test -x "$hcc/bin/hcc-m1"
  grep -Fx 'mode: make-derived stage1 source-to-M1 manifest' "$artifacts/summary.txt"
  grep -Fx 'soft-float-runtime: enabled' "$artifacts/summary.txt"
  grep -Fx 'artifacts: kept' "$artifacts/summary.txt"
  grep -Fx 'tinycc: absent' "$direct/summary.txt"
  grep -Fx 'smoke-optimization: -O2' "$direct/summary.txt"
  grep -Fx 'result: ok' "$direct/summary.txt"
  grep -Fx 'bootstrap: yes' "$selfhost/summary.txt"
  grep -Fx 'buildTarget: bootstrap' "$selfhost/summary.txt"
  grep -Fx 'stage2-stage3-comparison: successful' "$selfhost/summary.txt"
  grep -Fx 'result: ok' "$selfhost/summary.txt"
  grep -Fx "seedGcc: ${directGcc}" "$selfhost/summary.txt"

  mkdir -p "$out/share/hcc-gcc46-direct-e2e"
  cp "$artifacts/summary.txt" "$out/share/hcc-gcc46-direct-e2e/m1-summary.txt"
  cp "$artifacts/source-events.tsv" "$out/share/hcc-gcc46-direct-e2e/m1-events.tsv"
  cp "$direct/summary.txt" "$out/share/hcc-gcc46-direct-e2e/direct-summary.txt"
  cp "$direct/direct-link-events.tsv" "$out/share/hcc-gcc46-direct-e2e/direct-events.tsv"
  cp "$selfhost/summary.txt" "$out/share/hcc-gcc46-direct-e2e/selfhost-summary.txt"
  cp "$selfhost/bootstrap-events.tsv" "$out/share/hcc-gcc46-direct-e2e/selfhost-events.tsv"
  cp ${runtimeClosure}/store-paths \
    "$out/share/hcc-gcc46-direct-e2e/runtime-closure.txt"

  closure="$out/share/hcc-gcc46-direct-e2e/runtime-closure.txt"
  if grep -E '/[a-z0-9]{32}-[^/]*(tinycc|tcc)' "$closure"; then
    echo 'hcc-gcc46-direct-e2e: TinyCC remains in the runtime closure' >&2
    exit 1
  fi
  for forbidden in \
    hcc-host-ghc-native \
    hcc-m2-precisely-gcc- \
    gccm2; do
    if grep -F "$forbidden" "$closure"; then
      echo "hcc-gcc46-direct-e2e: forbidden bootstrap path: $forbidden" >&2
      exit 1
    fi
  done

  summary_value() {
    key=$1
    file=$2
    value=$(gawk -F ': ' -v key="$key" '$1 == key { print $2; exit }' "$file")
    test -n "$value"
    printf '%s\n' "$value"
  }
  source_to_m1_seconds=$(summary_value hcc-source-to-m1-seconds "$direct/summary.txt")
  direct_seconds=$(summary_value measured-stage-seconds "$direct/summary.txt")
  bootstrap_seconds=$(summary_value bootstrap-seconds "$selfhost/summary.txt")

  {
    echo "faithful-hcc: ${faithfulHcc}"
    echo "m1-artifacts: ${m1Artifacts}"
    echo "direct-gcc: ${directGcc}"
    echo "gcc46-selfhost: ${gcc46Selfhost}"
    echo 'compiler-route: HCC -> M1 -> GNU assembler/linker -> GCC 4.6 -> GCC 4.6 bootstrap'
    echo 'host-assistance: GNU assembler/linker plus static support libraries and glibc headers/runtime'
    echo 'tinycc: absent'
    echo 'runtime-closure-audit: no TinyCC or alternate HCC/GCCM2 ancestry'
    echo 'bootstrap-comparison: stages 2 and 3 compare successfully'
    echo "hcc-source-to-m1-seconds: $source_to_m1_seconds"
    echo "direct-stage-seconds: $direct_seconds"
    echo "gcc-bootstrap-seconds: $bootstrap_seconds"
    echo "measured-route-seconds: $((direct_seconds + bootstrap_seconds))"
    echo 'result: ok'
  } > "$out/share/hcc-gcc46-direct-e2e/summary.txt"
''
