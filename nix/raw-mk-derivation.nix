{
  lib,
  system,
  bash,
  coreutils,
  gnused,
  gnugrep,
  gawk,
  gnutar,
  gzip,
  xz,
  bzip2,
  patch,
  findutils,
  diffutils,
  gcc ? null,
  bootstrapTools ? [ ],
}:

let
  mkRaw =
    {
      withCC ? false,
    }:
    args:
    let
      pname = args.pname or args.name;
      version = args.version or null;
      name =
        args.name or (
          if version == null then
            pname
          else
            "${pname}-${version}"
        );
      nativeBuildInputs = args.nativeBuildInputs or [ ];
      baseTools =
        if withCC then
          [
            bash
            coreutils
            gnused
            gnugrep
            gawk
            gnutar
            gzip
            xz
            bzip2
            patch
            findutils
            diffutils
            gcc
          ]
        else
          bootstrapTools;
      path = lib.makeBinPath (baseTools ++ nativeBuildInputs);
      shell = if withCC then "${bash}/bin/bash" else "/bin/sh";
      src = args.src or null;
      sourceRoot = args.sourceRoot or "";
      envAttrs = lib.filterAttrs (_: value:
        builtins.isString value
        || builtins.isPath value
        || lib.isDerivation value
        || builtins.isInt value
      ) (removeAttrs args [
        "buildPhase"
        "checkPhase"
        "doCheck"
        "dontConfigure"
        "dontFixup"
        "dontPatch"
        "dontPatchELF"
        "dontUnpack"
        "dontUpdateAutotoolsGnuConfigScripts"
        "installPhase"
        "meta"
        "name"
        "nativeBuildInputs"
        "passthru"
        "pname"
        "postPatch"
        "src"
        "sourceRoot"
        "version"
      ]);
      buildScript = ''
        set -eu

        export PATH=${path}
        export SHELL=${shell}
        export NIX_BUILD_TOP="''${NIX_BUILD_TOP:-$TMPDIR}"
        ${lib.optionalString withCC ''
          export CC=${gcc}/bin/gcc
        ''}

        runHook() {
          hook="$1"
          eval "hook_value=\''${$hook-}"
          if [ -n "$hook_value" ]; then
            eval "$hook_value"
          fi
        }

        ${lib.optionalString (!withCC) ''
        cp() {
          if [ "$#" -lt 2 ]; then
            echo "cp: missing operand" >&2
            exit 1
          fi
          dst=""
          for arg in "$@"; do
            dst="$arg"
          done
          while [ "$#" -gt 1 ]; do
            src_file="$1"
            shift
            if [ -d "$dst" ]; then
              out_file="$dst/''${src_file##*/}"
            else
              out_file="$dst"
            fi
            if [ -e "$out_file" ]; then
              rm "$out_file"
            fi
            catm "$out_file" "$src_file"
          done
        }

        cat() {
          if [ "$#" -eq 0 ]; then
            while IFS= read -r line; do
              printf '%s\n' "$line"
            done
          else
            catm /dev/stdout "$@"
          fi
        }
        ''}

        ${lib.optionalString withCC ''
        _escape_sed_replacement() {
          printf '%s' "$1" | sed 's/[\/&]/\\&/g'
        }
        ''}

        substituteInPlace() {
          file="$1"
          shift
          while [ "$#" -gt 0 ]; do
            case "$1" in
              --replace-fail)
                old="$2"
                new="$3"
                shift 3
                ${if withCC then ''
                old_escaped="$(_escape_sed_replacement "$old")"
                new_escaped="$(_escape_sed_replacement "$new")"
                if ! grep -Fq "$old" "$file"; then
                  echo "substituteInPlace: pattern not found in $file: $old" >&2
                  exit 1
                fi
                sed -i "s/$old_escaped/$new_escaped/g" "$file"
                '' else ''
                replace --file "$file" --match-on "$old" --replace-with "$new" --output "$file.subst"
                cp "$file.subst" "$file"
                rm "$file.subst"
                ''}
                ;;
              *)
                echo "substituteInPlace: unsupported option $1" >&2
                exit 1
                ;;
            esac
          done
        }

        install() {
          mode=555
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -Dm*)
                mode="''${1#-Dm}"
                shift
                ;;
              *)
                break
                ;;
            esac
          done
          src_file="$1"
          dst_file="$2"
          dst_dir="''${dst_file%/*}"
          mkdir -p "$dst_dir"
          cp "$src_file" "$dst_file"
          chmod "$mode" "$dst_file"
        }

        copyTree() {
          src_dir="$1"
          dst_dir="$2"
          mkdir -p "$dst_dir"
          for entry in "$src_dir"/*; do
            [ -e "$entry" ] || continue
            base="''${entry##*/}"
            if [ -d "$entry" ]; then
              copyTree "$entry" "$dst_dir/$base"
            else
              cp "$entry" "$dst_dir/$base"
            fi
          done
        }

        unpackPhase() {
          runHook preUnpack
          if [ -z "''${src:-}" ]; then
            return 0
          fi
          if [ -d "$src" ]; then
            copyTree "$src" source
            cd source
          else
            case "$src" in
              *.tar.gz|*.tgz)
                ungz --file "$src" --output source.tar
                untar --file source.tar
                ;;
              *.tar.xz)
                unxz --file "$src" --output source.tar
                untar --file source.tar
                ;;
              *.tar.bz2)
                unbz2 --file "$src" --output source.tar
                untar --file source.tar
                ;;
              *.tar)
                untar --file "$src"
                ;;
              *)
                echo "unpackPhase: unsupported source archive $src" >&2
                exit 1
                ;;
            esac
            if [ -n "${sourceRoot}" ]; then
              cd "${sourceRoot}"
            else
              echo "unpackPhase: sourceRoot is required for archive sources" >&2
              exit 1
            fi
          fi
          runHook postUnpack
        }

        patchPhase() {
          runHook prePatch
          ${args.postPatch or ""}
          runHook postPatch
        }

        configurePhase() {
          runHook preConfigure
          runHook postConfigure
        }

        buildPhase() {
          :
          ${args.buildPhase or ""}
        }

        installPhase() {
          :
          ${args.installPhase or ""}
        }

        checkPhase() {
          :
          ${args.checkPhase or ""}
        }

        ${lib.optionalString (!(args.dontUnpack or false)) "unpackPhase"}
        ${lib.optionalString (!(args.dontPatch or false)) "patchPhase"}
        ${lib.optionalString (!(args.dontConfigure or false)) "configurePhase"}
        buildPhase
        ${lib.optionalString (args.doCheck or false) "checkPhase"}
        installPhase
      '';
      drv = derivation (
        envAttrs
        // {
          inherit name system buildScript;
          builder = shell;
          args = [
            "-e"
            "-c"
            ". \"$buildScriptPath\""
          ];
          passAsFile = [ "buildScript" ];
          PATH = path;
        }
        // lib.optionalAttrs (src != null) { inherit src; }
      );
    in
    drv // {
      inherit pname;
      meta = args.meta or { };
      passthru = args.passthru or { };
    } // lib.optionalAttrs (version != null) { inherit version; };
in
{
  noCC = {
    mkDerivation = mkRaw { withCC = false; };
  };
  cc = {
    mkDerivation = mkRaw { withCC = true; };
  };
}
