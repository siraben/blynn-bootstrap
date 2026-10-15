#!/bin/sh
# Source from compiler smoke, or run with HCPP/HCC1/HCC_M1 set to executables.
# Artifacts go in the caller's disposable working directory. Device tests are
# opt-in: HCC_DRIVER_DEV_FULL=1 on Linux, outside a restricted faithful sandbox.
runtime_driver_contracts() (
  set -eu
  HCPP=${HCPP:-hcpp}
  HCC1=${HCC1:-hcc1}
  HCC_M1=${HCC_M1:-hcc-m1}
  printf '%s\n' 'int main(void) { return 13; }' > runtime-driver-valid.i
  "$HCPP" runtime-driver-valid.i > runtime-driver-valid.pp
  "$HCC1" --m1-ir -o runtime-driver-valid.hccir runtime-driver-valid.i
  "$HCC_M1" runtime-driver-valid.hccir runtime-driver-valid.M1
  test -s runtime-driver-valid.pp
  test -s runtime-driver-valid.hccir
  test -s runtime-driver-valid.M1

  # Default names belong to cwd, even for absolute inputs or dotted source
  # directories. Distinct stems must never overwrite the same extension name.
  mkdir -p runtime-driver.dotted/src.dir
  printf '%s\n' 'int main(void) { return 13; }' > runtime-driver.dotted/src.dir/runtime-first.i
  printf '%s\n' 'int main(void) { return 29; }' > runtime-driver.dotted/src.dir/runtime-second.i
  for runtime_name in runtime-multi.part.i runtime-noext .runtime-hidden runtime-tail.; do
    printf '%s\n' 'int main(void) { return 13; }' > "runtime-driver.dotted/src.dir/$runtime_name"
  done
  rm -f runtime-first.hccir runtime-second.hccir runtime-multi.part.hccir runtime-noext.hccir .runtime-hidden.hccir runtime-tail.hccir
  "$HCC1" --m1-ir "$(pwd)/runtime-driver.dotted/src.dir/runtime-first.i"
  "$HCC1" --m1-ir runtime-driver.dotted/src.dir/runtime-second.i
  for runtime_name in runtime-multi.part.i runtime-noext .runtime-hidden runtime-tail.; do
    "$HCC1" --m1-ir "runtime-driver.dotted/src.dir/$runtime_name"
  done
  for runtime_stem in runtime-first runtime-second runtime-multi.part runtime-noext .runtime-hidden runtime-tail; do
    test -s "$runtime_stem.hccir"
    test ! -e "runtime-driver.dotted/src.dir/$runtime_stem.hccir"
  done
  runtime_expect_return() {
    runtime_found_return=0
    while IFS= read -r runtime_line; do
      if test "$runtime_line" = "R I$2"; then runtime_found_return=1; fi
    done < "$1"
    test "$runtime_found_return" = 1
  }
  runtime_expect_return runtime-first.hccir 13
  runtime_expect_return runtime-second.hccir 29
  "$HCC1" --m1-ir -o runtime-driver.dotted/explicit.hccir runtime-driver.dotted/src.dir/runtime-first.i
  test -s runtime-driver.dotted/explicit.hccir
  echo 'runtime-driver: default filename checks passed'

  runtime_expect_output_failure() {
    if "$@" > /dev/full 2> runtime-driver-error.log; then
      echo "runtime-driver: unexpected output success: $*" >&2
      exit 1
    fi
    # A parse error or missing executable must not masquerade as an I/O pass.
    runtime_found_error=0
    while IFS= read -r runtime_line; do
      case $runtime_line in
        *output*error*) runtime_found_error=1 ;;
      esac
    done < runtime-driver-error.log
    test "$runtime_found_error" = 1
  }

  if test "${HCC_DRIVER_DEV_FULL:-0}" = 1; then
    test -c /dev/full || { echo 'runtime-driver: /dev/full unavailable' >&2; exit 1; }
    # Opening succeeds. Small writes detect delayed flush/close errors.
    : > /dev/full
    runtime_expect_output_failure "$HCPP" runtime-driver-valid.i
    runtime_expect_output_failure "$HCC1" --m1-ir -o /dev/full runtime-driver-valid.i
    runtime_expect_output_failure "$HCC_M1" runtime-driver-valid.hccir /dev/full
    # Also exercise automatic buffer flushes rather than only the final tail.
    runtime_i=0
    : > runtime-driver-large.i
    while test "$runtime_i" -lt 160; do
      printf 'int runtime_function_%s(void) { return 13; }\n' "$runtime_i" >> runtime-driver-large.i
      runtime_i=$((runtime_i + 1))
    done
    "$HCPP" runtime-driver-large.i > runtime-driver-large.pp
    "$HCC1" --m1-ir -o runtime-driver-large.hccir runtime-driver-large.i
    "$HCC_M1" runtime-driver-large.hccir runtime-driver-large.M1
    runtime_expect_output_failure "$HCPP" runtime-driver-large.i
    runtime_expect_output_failure "$HCC1" --m1-ir -o /dev/full runtime-driver-large.i
    runtime_expect_output_failure "$HCC_M1" runtime-driver-large.hccir /dev/full
    echo 'runtime-driver: /dev/full small and buffered output checks passed'
  else
    echo 'runtime-driver: SKIP /dev/full (set HCC_DRIVER_DEV_FULL=1 on Linux)'
  fi
)

runtime_driver_contracts
