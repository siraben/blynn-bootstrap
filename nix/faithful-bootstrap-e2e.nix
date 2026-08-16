{
  runCommand,
  closureInfo,
  faithfulHcc,
  tinycc,
  gcc46,
  gcc46Selfhost,
}:

let
  runtimeClosure = closureInfo {
    rootPaths = [
      faithfulHcc
      tinycc
      gcc46
      gcc46Selfhost
    ];
  };
in
runCommand "faithful-bootstrap-e2e" { } ''
  set -eu

  hcc=${faithfulHcc}
  tinycc=${tinycc}
  gcc46=${gcc46}
  selfhost=${gcc46Selfhost}

  test -x "$hcc/bin/hcpp"
  test -x "$hcc/bin/hcc1"
  test -x "$hcc/bin/hcc-m1"

  tiny_summary="$tinycc/share/tinycc-hcc/summary.txt"
  test -s "$tiny_summary"
  grep -Fx 'stage1-producer: HCC' "$tiny_summary"
  grep -Fx 'stage2-producer: tcc-hcc-stage1' "$tiny_summary"
  grep -Fx 'stage3-producer: tcc-stage2' "$tiny_summary"
  grep -Fx 'stage4-producer: tcc-stage3' "$tiny_summary"
  grep -Fx 'stage3-stage4: identical' "$tiny_summary"
  grep -Fx 'result: ok' "$tiny_summary"

  test -x "$tinycc/bin/tcc-hcc-stage1"
  test -x "$tinycc/bin/tcc-stage2"
  test -x "$tinycc/bin/tcc"
  "$tinycc/bin/tcc-hcc-stage1" -version > tcc-stage1-version.txt 2>&1
  "$tinycc/bin/tcc-stage2" -version > tcc-stage2-version.txt 2>&1
  "$tinycc/bin/tcc" -version > tcc-stage3-version.txt 2>&1

  test -x "$gcc46/bin/gcc"
  "$gcc46/bin/gcc" --version > gcc46-version.txt 2>&1

  gcc_summary="$selfhost/share/gcc46-selfhost/summary.txt"
  test -s "$gcc_summary"
  grep -Fx "seedGcc: $gcc46" "$gcc_summary"
  grep -Fx 'bootstrap: yes' "$gcc_summary"
  grep -Fx 'buildTarget: bootstrap' "$gcc_summary"
  grep -Fx 'result: ok' "$gcc_summary"
  for stage in 1 2 3; do
    grep -E "^stage$stage-seconds: [0-9]+$" "$gcc_summary"
  done

  mkdir -p "$out/share/faithful-bootstrap-e2e"
  cp "$tiny_summary" "$out/share/faithful-bootstrap-e2e/tinycc-summary.txt"
  cp "$tinycc/share/tinycc-hcc/bootstrap-metrics.tsv" \
    "$out/share/faithful-bootstrap-e2e/tinycc-metrics.tsv"
  cp "$gcc_summary" "$out/share/faithful-bootstrap-e2e/gcc46-selfhost-summary.txt"
  cp "$selfhost/share/gcc46-selfhost/bootstrap-events.tsv" \
    "$out/share/faithful-bootstrap-e2e/gcc46-bootstrap-events.tsv"
  cp ${runtimeClosure}/store-paths \
    "$out/share/faithful-bootstrap-e2e/runtime-closure.txt"
  cp tcc-stage1-version.txt tcc-stage2-version.txt tcc-stage3-version.txt \
    gcc46-version.txt "$out/share/faithful-bootstrap-e2e/"

  tiny_metrics="$out/share/faithful-bootstrap-e2e/tinycc-metrics.tsv"
  tiny_measured_seconds=$(awk -F '\t' '{ total += $1 } END { printf "%.2f", total }' "$tiny_metrics")
  hcc_tinycc_seed_seconds=$(awk -F '\t' \
    '$2 ~ /^hcpp / || $2 ~ /^hcc1 / || $2 ~ /^hcc-m1 / { total += $1 } END { printf "%.2f", total }' \
    "$tiny_metrics")
  tiny_self_compile_seconds=$(awk -F '\t' \
    '$2 ~ /self-build stage[234]$/ { total += $1 } END { printf "%.2f", total }' \
    "$tiny_metrics")
  gcc_bootstrap_seconds=$(sed -n 's/^bootstrap-seconds: //p' "$gcc_summary")
  test -n "$gcc_bootstrap_seconds"

  closure="$out/share/faithful-bootstrap-e2e/runtime-closure.txt"
  for forbidden in \
    hcc-host-ghc-native \
    hcc-m2-precisely-gcc- \
    gccm2; do
    if grep -F "$forbidden" "$closure"; then
      echo "faithful-bootstrap-e2e: forbidden alternate bootstrap path: $forbidden" >&2
      exit 1
    fi
  done

  {
    echo 'root: m2.precisely.m2'
    echo "hcc: $hcc"
    echo "tinycc: $tinycc"
    echo "gcc46-stage1: $gcc46"
    echo "gcc46-selfhost: $selfhost"
    echo 'tinycc-fixpoint: stage3 == stage4'
    echo 'gcc46-bootstrap: stage2 == stage3 under GCC comparison rules'
    echo 'runtime-closure-audit: no alternate HCC/GCCM2 ancestry'
    echo "hcc-tinycc-seed-seconds: $hcc_tinycc_seed_seconds"
    echo "tinycc-self-compile-seconds: $tiny_self_compile_seconds"
    echo "tinycc-measured-seconds: $tiny_measured_seconds"
    echo "gcc46-bootstrap-seconds: $gcc_bootstrap_seconds"
    echo 'result: ok'
  } > "$out/share/faithful-bootstrap-e2e/summary.txt"
''
