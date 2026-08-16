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
      metricsFile ? null,
    }:
    ''
      ${lib.optionalString timed ''
        monotonic_centiseconds() {
          read -r uptime _ < /proc/uptime
          uptime_seconds="''${uptime%%.*}"
          uptime_fraction="''${uptime#*.}"
          uptime_tens="''${uptime_fraction%"''${uptime_fraction#?}"}"
          uptime_ones="''${uptime_fraction#?}"
          printf '%s\n' "$((uptime_seconds * 100 + uptime_tens * 10 + uptime_ones))"
        }
      ''}

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
        ${lib.optionalString timed ''
          start="$(monotonic_centiseconds)"
        ''}
        "$@"
        ${
          if timed then
            ''
              end="$(monotonic_centiseconds)"
              elapsed_centiseconds="$((end - start))"
              elapsed="$(printf '%d.%02d' "$((elapsed_centiseconds / 100))" "$((elapsed_centiseconds % 100))")"
              log_step "DONE  $label (''${elapsed}s)"
              ${lib.optionalString (metricsFile != null) ''printf '%s\t%s\n' "$elapsed" "$label" >> ${lib.escapeShellArg metricsFile}''}
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
        ${lib.optionalString timed ''
          start="$(monotonic_centiseconds)"
        ''}
        eval "$command"
        ${
          if timed then
            ''
              end="$(monotonic_centiseconds)"
              elapsed_centiseconds="$((end - start))"
              elapsed="$(printf '%d.%02d' "$((elapsed_centiseconds / 100))" "$((elapsed_centiseconds % 100))")"
              log_step "DONE  $label (''${elapsed}s)"
              ${lib.optionalString (metricsFile != null) ''printf '%s\t%s\n' "$elapsed" "$label" >> ${lib.escapeShellArg metricsFile}''}
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
