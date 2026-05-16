{
  stdenv,
  lib,
  src,
}:

stdenv.mkDerivation {
  pname = "m2-mesoplanet-gcc";
  version = "1.9.1";

  inherit src;

  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildPhase = ''
    runHook preBuild

    $CC -D_GNU_SOURCE -O2 -std=c99 \
      -Wall -Wextra -Wno-unused-parameter \
      -I. \
      M2libc/bootstrappable.c \
      cc_reader.c \
      cc_strings.c \
      cc_types.c \
      cc_emit.c \
      cc_core.c \
      cc_macro.c \
      cc.c \
      cc_globals.c \
      -o M2-Mesoplanet

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 M2-Mesoplanet "$out/bin/M2-Mesoplanet.real"
    cat > "$out/bin/M2-Mesoplanet" <<EOF
#!${stdenv.shell}
set -e
real="$out/bin/M2-Mesoplanet.real"
args=("--expand-includes" "--debug" "-I" "${src}/M2libc")
arch=amd64
base=0x00600000
output=
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -f|--file)
      shift
      args+=("--file" "\$1")
      shift
      ;;
    --file=*)
      args+=("--file" "\''${1#--file=}")
      shift
      ;;
    -o|--output)
      shift
      output="\$1"
      shift
      ;;
    --output=*)
      output="\''${1#--output=}"
      shift
      ;;
    --operating-system)
      shift 2
      ;;
    --operating-system=*)
      shift
      ;;
    --architecture)
      shift
      arch="\$1"
      case "\$arch" in
        x86_64) arch=amd64; base=0x00600000 ;;
        amd64) base=0x00600000 ;;
        i686) arch=x86; base=0x8048000 ;;
        x86) base=0x8048000 ;;
        aarch64) base=0x400000 ;;
        riscv32|riscv64) base=0x600000 ;;
      esac
      args+=("--architecture" "\$arch")
      shift
      ;;
    --architecture=*)
      arch="\''${1#--architecture=}"
      case "\$arch" in
        x86_64) arch=amd64; base=0x00600000 ;;
        amd64) base=0x00600000 ;;
        i686) arch=x86; base=0x8048000 ;;
        x86) base=0x8048000 ;;
        aarch64) base=0x400000 ;;
        riscv32|riscv64) base=0x600000 ;;
      esac
      args+=("--architecture" "\$arch")
      shift
      ;;
    *)
      args+=("\$1")
      shift
      ;;
    esac
done
if [ -z "\$output" ]; then
  exec "\$real" "\''${args[@]}"
fi
m1="\$output.M1.tmp.\$\$"
hex="\$output.hex2.tmp.\$\$"
blood="\$output.blood.tmp.\$\$"
trap 'rm -f "\$m1" "\$hex" "\$blood"' EXIT INT HUP TERM
if [ -f M2libc/bootstrappable.c ]; then
  args=("\''${args[@]}" --file M2libc/bootstrappable.c)
fi
"\$real" "\''${args[@]}" --output "\$m1"
libc=libc-core.M1
while IFS= read -r line; do
  case "\$line" in
    *:FUNCTION___init_malloc*) libc=libc-full.M1; break ;;
  esac
done < "\$m1"
blood_args=(--file "\$m1" --little-endian --output "\$blood")
case "\$arch" in
  amd64|aarch64|riscv64) blood_args+=("--64") ;;
esac
blood-elf "\''${blood_args[@]}"
M1 --file "${src}/M2libc/\$arch/\''${arch}_defs.M1" \
  --file "${src}/M2libc/\$arch/\$libc" \
  --file "\$m1" \
  --file "\$blood" \
  --output "\$hex" \
  --architecture "\$arch" \
  --little-endian
hex2 --file "${src}/M2libc/\$arch/ELF-\$arch-debug.hex2" \
  --file "\$hex" \
  --output "\$output" \
  --architecture "\$arch" \
  --base-address "\$base" \
  --little-endian
chmod 555 "\$output"
EOF
    chmod 755 "$out/bin/M2-Mesoplanet"
    runHook postInstall
  '';

  meta = {
    description = "M2-Mesoplanet compiled by the normal GCC toolchain for fast bootstrap debugging";
    homepage = "https://github.com/oriansj/stage0-posix";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
