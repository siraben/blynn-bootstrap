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

  patchGeneratedTop = file: top: ''
    patch_generated_top_file=${file}
    patch_generated_top_tmp="$patch_generated_top_file.tmp"
    patch_generated_top_seen=no
    : > "$patch_generated_top_tmp"
    while IFS= read -r patch_generated_top_line || [ -n "$patch_generated_top_line" ]; do
      case "$patch_generated_top_line" in
        *'enum{TOP='*'};'*)
          patch_generated_top_before=''${patch_generated_top_line%%enum\{TOP=*}
          patch_generated_top_rest=''${patch_generated_top_line#*enum\{TOP=}
          patch_generated_top_after=''${patch_generated_top_rest#*\};}
          patch_generated_top_line="$patch_generated_top_before"'enum{TOP=${toString top}};'"$patch_generated_top_after"
          patch_generated_top_seen=yes
          ;;
      esac
      printf '%s\n' "$patch_generated_top_line" >> "$patch_generated_top_tmp"
    done < "$patch_generated_top_file"
    if [ "$patch_generated_top_seen" != yes ]; then
      printf 'patchGeneratedTop: TOP marker not found in %s\n' "$patch_generated_top_file" >&2
      exit 1
    fi
    chmod u+w "$patch_generated_top_file" 2>/dev/null || :
    cp "$patch_generated_top_tmp" "$patch_generated_top_file"
  '';

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
