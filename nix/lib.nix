{ lib }:

rec {
  bootstrapVersion = "0-unstable-2026-05-06";

  skipPatchConfigure = {
    dontPatch = true;
    dontConfigure = true;
    dontUpdateAutotoolsGnuConfigScripts = true;
  };

  skipFixup = {
    dontFixup = true;
    dontPatchELF = true;
  };

  scriptOnly = {
    dontUnpack = true;
  }
  // skipPatchConfigure
  // skipFixup;

  shellHelpers =
    {
      name,
      timestamps ? false,
      timed ? false,
      fileStats ? false,
    }:
    ''
      log_step() {
        ${
          if timestamps then
            ''
              printf '${name}: [%s] %s\n' "$(date -u +%H:%M:%S)" "$1"
            ''
          else
            ''
              printf '${name}: %s\n' "$1"
            ''
        }
      }

      run_step() {
        label="$1"
        shift
        log_step "START $label"
        ${lib.optionalString timed ''start="$(date +%s)"''}
        "$@"
        ${
          if timed then
            ''
              end="$(date +%s)"
              log_step "DONE  $label ($((end - start))s)"
            ''
          else
            ''
              log_step "DONE  $label"
            ''
        }
      }

      run_step_shell() {
        label="$1"
        command="$2"
        log_step "START $label"
        ${lib.optionalString timed ''start="$(date +%s)"''}
        eval "$command"
        ${
          if timed then
            ''
              end="$(date +%s)"
              log_step "DONE  $label ($((end - start))s)"
            ''
          else
            ''
              log_step "DONE  $label"
            ''
        }
      }

      log_file() {
        file="$1"
        ${
          if fileStats then
            ''
              bytes="$(wc -c < "$file")"
              lines="$(wc -l < "$file")"
              log_step "FILE  $file: $lines lines, $bytes bytes"
            ''
          else
            ''
              log_step "FILE  $file"
            ''
        }
      }
    '';
}
