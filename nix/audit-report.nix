{
  lib,
  stdenvNoCC,
  coreutils,
  findutils,
  gnused,
  inputInfo ? [ ],
  upstreamSourceInfo ? [ ],
  patches ? [ ],
  hccSrc,
  hccSupport ? "${hccSrc}/support",
  hccBlynnGeneratedC ? [ ],
  tinyccM1Artifacts ? [ ],
}:

let
  line = text: ''
    printf '%s\n' ${lib.escapeShellArg text} >> "$report"
  '';

  inputInfoLines = lib.concatMapStringsSep "\n" (input:
    line "  - ${input.name}: rev=${input.rev or "unknown"} narHash=${input.narHash or "unknown"} lastModifiedDate=${input.lastModifiedDate or "unknown"} outPath=${input.outPath or "unknown"}")
    inputInfo;

  upstreamSourceInfoLines = lib.concatMapStringsSep "\n" (source:
    line "  - ${source.name}: url=${source.url} rev=${source.rev} hash=${source.hash} outPath=${source.outPath or "unknown"}")
    upstreamSourceInfo;

  patchLines = lib.concatMapStringsSep "\n" (patch: ''
    report_file ${lib.escapeShellArg patch.name} ${lib.escapeShellArg "${patch.path}"}
  '') patches;

  hccBlynnGeneratedCLines = lib.concatMapStringsSep "\n" (generated: ''
    report_generated_c ${lib.escapeShellArg generated.name} ${lib.escapeShellArg generated.path}
  '') hccBlynnGeneratedC;

  tinyccM1ArtifactLines = lib.concatMapStringsSep "\n" (artifact: ''
    report_tinycc_m1 ${lib.escapeShellArg artifact.name} ${lib.escapeShellArg artifact.path}
  '') tinyccM1Artifacts;
in
stdenvNoCC.mkDerivation {
  pname = "blynn-bootstrap-audit-report";
  version = "0-unstable";

  dontUnpack = true;
  dontConfigure = true;
  dontPatch = true;
  dontFixup = true;
  dontPatchELF = true;

  nativeBuildInputs = [
    coreutils
    findutils
    gnused
  ];

  buildPhase = ''
    runHook preBuild

    report="$PWD/audit-report.txt"

    hash_file() {
      file="$1"
      if [ -f "$file" ]; then
        sha256sum "$file" | cut -d ' ' -f 1
      else
        printf 'unavailable'
      fi
    }

    report_file() {
      label="$1"
      file="$2"
      if [ -f "$file" ]; then
        hash="$(hash_file "$file")"
        lines="$(wc -l < "$file")"
        bytes="$(wc -c < "$file")"
        printf '  - %s: sha256=%s lines=%s bytes=%s path=%s\n' "$label" "$hash" "$lines" "$bytes" "$file" >> "$report"
      else
        printf '  - %s: unavailable path=%s\n' "$label" "$file" >> "$report"
      fi
    }

    count_tree_lines() {
      label="$1"
      dir="$2"
      shift 2
      files=0
      lines=0
      if [ -d "$dir" ]; then
        while IFS= read -r -d "" file; do
          file_lines="$(wc -l < "$file" || printf 0)"
          files=$((files + 1))
          lines=$((lines + file_lines))
        done < <(find "$dir" "$@" -type f -print0 2>/dev/null || true)
        printf '  - %s: files=%s lines=%s path=%s\n' "$label" "$files" "$lines" "$dir" >> "$report"
      else
        printf '  - %s: unavailable path=%s\n' "$label" "$dir" >> "$report"
      fi
    }

    report_generated_c() {
      label="$1"
      dir="$2"
      printf '  - %s: path=%s\n' "$label" "$dir" >> "$report"
      if [ -d "$dir" ]; then
        found=0
        while IFS= read -r -d "" file; do
          found=1
          base="$(basename "$file")"
          hash="$(hash_file "$file")"
          lines="$(wc -l < "$file")"
          bytes="$(wc -c < "$file")"
          printf '      %s sha256=%s lines=%s bytes=%s\n' "$base" "$hash" "$lines" "$bytes" >> "$report"
        done < <(find "$dir" -maxdepth 1 -type f -name '*-blynn.c' -print0 | sort -z)
        if [ "$found" -eq 0 ]; then
          printf '      no generated *-blynn.c files found\n' >> "$report"
        fi
      else
        printf '      unavailable\n' >> "$report"
      fi
    }

    report_tinycc_m1() {
      label="$1"
      dir="$2"
      printf '  - %s: path=%s\n' "$label" "$dir" >> "$report"
      if [ -f "$dir/SHA256SUMS" ]; then
        sed 's/^/      /' "$dir/SHA256SUMS" >> "$report"
      elif [ -d "$dir" ]; then
        found=0
        while IFS= read -r -d "" file; do
          found=1
          base="$(basename "$file")"
          hash="$(hash_file "$file")"
          bytes="$(wc -c < "$file")"
          printf '      %s sha256=%s bytes=%s\n' "$base" "$hash" "$bytes" >> "$report"
        done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)
        if [ "$found" -eq 0 ]; then
          printf '      no TinyCC M1 artifacts found\n' >> "$report"
        fi
      else
        printf '      unavailable\n' >> "$report"
      fi
    }

    : > "$report"
    ${line "Blynn Bootstrap HCC Audit Report"}
    ${line ""}
    ${line "Inputs"}
    ${if inputInfo == [ ] then line "  - none provided" else inputInfoLines}
    ${line ""}
    ${line "Upstream Fetches"}
    ${if upstreamSourceInfo == [ ] then line "  - none provided" else upstreamSourceInfoLines}
    ${line ""}
    ${line "Patches"}
    ${if patches == [ ] then line "  - none provided" else patchLines}
    ${line ""}
    ${line "HCC Source LOC"}
    count_tree_lines "HCC Haskell source" ${lib.escapeShellArg "${hccSrc}/src"} -name '*.hs'
    count_tree_lines "HCC C runtime/support source" ${lib.escapeShellArg "${hccSrc}/cbits"} -name '*.[ch]'
    count_tree_lines "HCC support files" ${lib.escapeShellArg "${hccSupport}"} '!' -name '*.md'
    ${line ""}
    ${line "Generated HCC C Hashes"}
    ${if hccBlynnGeneratedC == [ ] then line "  - none provided" else hccBlynnGeneratedCLines}
    ${line ""}
    ${line "TinyCC M1 Artifact Hashes"}
    ${if tinyccM1Artifacts == [ ] then line "  - none provided" else tinyccM1ArtifactLines}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 audit-report.txt "$out/audit-report.txt"
    install -Dm644 audit-report.txt "$out/share/blynn-bootstrap/audit-report.txt"
    runHook postInstall
  '';

  meta = {
    description = "Report-only audit summary for the Blynn/HCC bootstrap path";
    platforms = lib.platforms.linux;
  };
}
