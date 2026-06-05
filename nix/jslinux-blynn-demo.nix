{
  stdenvNoCC,
  lib,
  fetchurl,
  genext2fs,
  e2fsprogs,
  util-linux,
  coreutils,
  gnutar,
  gzip,
  python3,
  repoSrc,
  oriansjBlynnSrc,
  blynnSrc,
  tinyccSrc,
  gnuMesSrc,
  mesccTools,
  stage0M2libcSrc,
  stage0PosixSrc,
  bootstrapSeedsSrc,
  nixBuiltTinycc,
}:

let
  alpineMinirootfs = fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-minirootfs-3.23.3-x86_64.tar.gz";
    hash = "sha256-QtDm2N5VIee/kuB14DK1aQwdlI+pd176MqUaOLJUYPs=";
  };
  kernel = fetchurl {
    url = "https://bellard.org/jslinux/kernel-x86_64-new.bin";
    hash = "sha256-AtbqOhmwQIbdVhYfihfDQMfiu+1QyiurXJDEA+l4Nec=";
  };
  termJs = fetchurl {
    url = "https://bellard.org/jslinux/term.js";
    hash = "sha256-CZt7++4NIkYYk6JLWAHZCtlxygTGB/yM88wDRnULS58=";
  };
  jslinuxJs = fetchurl {
    url = "https://bellard.org/jslinux/jslinux.js";
    hash = "sha256-UYmdR7PXDdHzU0SNmlQ/fYxeD4p6I31V7W5+NYyXp9w=";
  };
  emulatorJs = fetchurl {
    url = "https://bellard.org/jslinux/x86_64emu-wasm.js";
    hash = "sha256-ueM9l0YIKD1vAM6UWbIyC/zPPNVTzN7QmL/+2lBhQp4=";
  };
  emulatorWasm = fetchurl {
    url = "https://bellard.org/jslinux/x86_64emu-wasm.wasm";
    hash = "sha256-L0GnQ3M9g2nlPb4GiyQ9kdxxNhg+Ml5izW0eiVgk5ls=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "jslinux-blynn-demo";
  version = "0.1.0";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [
    coreutils
    e2fsprogs
    genext2fs
    util-linux
    gnutar
    gzip
    python3
  ];

  installPhase = ''
    set -eu

    root=$TMPDIR/root
    mkdir -p "$root"
    tar --no-same-owner -xzf ${alpineMinirootfs} -C "$root"

    mkdir -p \
      "$root/bootstrap/repo" \
      "$root/bootstrap/upstreams" \
      "$root/bootstrap/tool-wrappers" \
      "$root/bootstrap/stage0-tools" \
      "$root/bootstrap/stage0-m2libc" \
      "$root/bootstrap/source-cache" \
      "$root/bootstrap/nix-built-tcc"

    cp -R ${repoSrc}/. "$root/bootstrap/repo/"
    chmod -R u+w "$root/bootstrap/repo"

    cp -R ${oriansjBlynnSrc} "$root/bootstrap/upstreams/oriansj-blynn-compiler"
    cp -R ${blynnSrc} "$root/bootstrap/upstreams/blynn-compiler"
    cp -R ${tinyccSrc} "$root/bootstrap/upstreams/janneke-tinycc"
    cp -R ${gnuMesSrc} "$root/bootstrap/upstreams/gnu-mes"
    chmod -R u+w "$root/bootstrap/upstreams"

    cp -R ${mesccTools}/. "$root/bootstrap/stage0-tools/"
    cp -R ${stage0M2libcSrc}/. "$root/bootstrap/stage0-m2libc/"
    mkdir -p "$root${builtins.dirOf (toString stage0M2libcSrc)}"
    cp -R ${stage0M2libcSrc} "$root${toString stage0M2libcSrc}"
    cp -R ${nixBuiltTinycc}/. "$root/bootstrap/nix-built-tcc/"
    cp -R ${stage0PosixSrc} "$root/bootstrap/source-cache/stage0-posix"
    chmod -R u+w "$root/bootstrap/source-cache/stage0-posix"
    rm -rf "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds"
    cp -R ${bootstrapSeedsSrc} "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds"
    chmod -R u+w "$root/bootstrap/source-cache/stage0-posix"
    cat > "$root/bootstrap/source-cache/stage0-posix/.bootstrap-rev" <<'EOF'
45d90f5955b6907dc6cdea9ebafce558359edcd3
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/AMD64/.bootstrap-rev" <<'EOF'
82efa0d6be1c9bb993a7a62af1cccd8d2cda91f6
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/M2-Mesoplanet/.bootstrap-rev" <<'EOF'
4b011a85da73a7c97212468d41f17e806ba99547
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/M2-Planet/.bootstrap-rev" <<'EOF'
bd2fe4b0659fd0ad3f476a5ad0ef801bd134665d
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/M2libc/.bootstrap-rev" <<'EOF'
68a23cfd05d5a355ba7a30c770d684cbe86fcc4e
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds/.bootstrap-rev" <<'EOF'
cedec6b8066d1db229b6c77d42d120a23c6980ed
EOF
    cat > "$root/bootstrap/source-cache/stage0-posix/mescc-tools/.bootstrap-rev" <<'EOF'
5adfbf3364261a77109878a56b100aeeb6ef9ac4
EOF

    cat > "$root/bootstrap/tool-wrappers/M2-Mesoplanet" <<'EOF'
#!/bin/sh
for tool in M2-Planet blood-elf M1 hex2; do
  [ -e "./$tool" ] || ln -s "/bootstrap/stage0-tools/bin/$tool" "./$tool" 2>/dev/null || true
done
exec /bootstrap/stage0-tools/bin/M2-Mesoplanet --temp-directory "$PWD" -I /bootstrap/stage0-m2libc "$@"
EOF
    chmod 755 "$root/bootstrap/tool-wrappers/M2-Mesoplanet"

    cat > "$root/bootstrap/run-portable-demo.sh" <<'EOF'
#!/bin/sh
set -eu

export HOME=/root
export ARCH=amd64
export OPERATING_SYSTEM=Linux
export M2_ARCH=amd64
export M2_OS=Linux
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export BOOTSTRAP_LOG_NAME=blynn-jslinux

repo=/bootstrap/repo
build=/work/blynn
mkdir -p "$build"
cd "$repo"

export SOURCE_CACHE_DIR=/bootstrap/source-cache
export BOOTSTRAP_TOOLS_REBUILD=1
export OUT_DIR="$build/bootstrap-tools"
echo "== hex0 seed to stage0-posix tools =="
sh scripts/bootstrap-tools.sh

export PATH="$build/bootstrap-tools/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export STAGE0_M2LIBC="$build/bootstrap-tools/artifact/stage0-posix/M2libc"
export M2LIBC_PATH="$STAGE0_M2LIBC"

export GNU_MES_DIR=/bootstrap/upstreams/gnu-mes
export OUT_DIR="$build/mes-libc"
echo "== prepare Mes libc =="
sh scripts/prepare-mes-libc.sh

export ORIANSJ_BLYNN_DIR=/bootstrap/upstreams/oriansj-blynn-compiler
export OUT_DIR="$build/blynn-root"
echo "== bootstrap original blynn root =="
sh scripts/bootstrap-blynn-root.sh

export BLYNN_DIR=/bootstrap/upstreams/blynn-compiler
export METHODICALLY="$build/blynn-root/bin/methodically"
export OUT_DIR="$build/blynn-precisely"
echo "== bootstrap blynn precisely =="
sh scripts/bootstrap-blynn-precisely.sh

export OUT_DIR="$build/hcc-blynn-sources"
echo "== generate HCC blynn sources =="
sh scripts/hcc-blynn-sources.sh

export PRECISELY_UP="$build/blynn-precisely/bin/precisely_up"
export HCC_BLYNN_SOURCES_DIR="$build/hcc-blynn-sources"
export MATERIALIZE_OBJECT_SCRIPT="$build/hcc-blynn-objs/materialize-object-script"
export OUT_DIR="$build/hcc-blynn-objs"
mkdir -p "$OUT_DIR"
echo "== materialize HCC blynn objects =="
M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
  -f hcc/support/materialize-object-script.c -o "$MATERIALIZE_OBJECT_SCRIPT"
chmod 555 "$MATERIALIZE_OBJECT_SCRIPT"
sh scripts/hcc-blynn-objs.sh

export HCC_BLYNN_OBJECTS_DIR="$build/hcc-blynn-objs"
export OUT_DIR="$build/hcc-blynn-c"
echo "== compile HCC C sources =="
sh scripts/hcc-blynn-c.sh

export HCC_BLYNN_C_DIR="$build/hcc-blynn-c"
export OUT_DIR="$build/hcc-blynn-bin"
echo "== link HCC binary =="
sh scripts/hcc-blynn-bin.sh

export TINYCC_DIR=/bootstrap/upstreams/janneke-tinycc
export HCC_BIN_DIR="$build/hcc-blynn-bin"
export MES_LIBC_DIR="$build/mes-libc"
export HCC_TARGET=amd64
export TINYCC_SELFHOST=''${TINYCC_SELFHOST:-0}
export OUT_DIR="$build/tinycc-boot-hcc"
echo "== build TinyCC with bootstrapped HCC =="
sh scripts/tinycc-boot-hcc.sh

echo "== bootstrapped blynn/HCC TinyCC =="
"$build/tinycc-boot-hcc/bin/tcc" -dumpversion || true
ln -sf "$build/tinycc-boot-hcc/bin/tcc" /usr/local/bin/blynn-tcc
echo "blynn-tcc is available on PATH"
EOF
    chmod 755 "$root/bootstrap/run-portable-demo.sh"

    dd if=/dev/zero of="$root/swapfile" bs=1M count=384
    chmod 600 "$root/swapfile"
    mkswap "$root/swapfile"

    cat > "$root/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sys /sys 2>/dev/null || true
mount -t devtmpfs dev /dev 2>/dev/null || true
mkdir -p /dev /tmp /work /root /usr/local/bin
chmod 1777 /tmp
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
swapon /swapfile 2>/dev/null || true

echo "blynn-bootstrap JSLinux demo: Alpine x86_64"
if grep -qw blynn_shell=1 /proc/cmdline; then
  echo "quick shell requested with blynn_shell=1"
  ln -sf /bootstrap/nix-built-tcc/bin/tcc /usr/local/bin/blynn-tcc
  echo "Nix-built reference TinyCC:"
  blynn-tcc -dumpversion || true
else
  echo "running full portable blynn bootstrap from the hex0 seed"
  echo "log is also written to /bootstrap-demo.log"
  rm -f /tmp/bootstrap-demo.status
  ( /bootstrap/run-portable-demo.sh 2>&1; echo $? >/tmp/bootstrap-demo.status ) | tee /bootstrap-demo.log
  bootstrap_status=$(cat /tmp/bootstrap-demo.status 2>/dev/null || echo 1)
  if [ "$bootstrap_status" = 0 ]; then
    echo "portable bootstrap finished; bootstrapped tcc is /usr/local/bin/blynn-tcc"
  else
    echo "portable bootstrap failed with status $bootstrap_status; dropping to shell"
  fi
fi
exec /bin/sh -l
EOF
    chmod 755 "$root/init"

    cat > "$TMPDIR/devices.txt" <<'EOF'
/dev d 755 0 0 - - - - -
/dev/console c 600 0 0 5 1 0 0 -
/dev/null c 666 0 0 1 3 0 0 -
/dev/zero c 666 0 0 1 5 0 0 -
/dev/tty c 666 0 0 5 0 0 0 -
EOF

    mkdir -p "$out"
    genext2fs -B 1024 -b 786432 -N 200000 -d "$root" -D "$TMPDIR/devices.txt" "$TMPDIR/blynn-root.ext2"
    fsck_status=0
    e2fsck -fy "$TMPDIR/blynn-root.ext2" || fsck_status=$?
    if [ "$fsck_status" -gt 1 ]; then
      exit "$fsck_status"
    fi

    mkdir -p "$out/blynn-root"
    python3 - "$TMPDIR/blynn-root.ext2" "$out/blynn-root" <<'PY'
import math
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
block_size = 256 * 1024
data = src.read_bytes()
n_block = math.ceil(len(data) / block_size)
for i in range(n_block):
    chunk = data[i * block_size:(i + 1) * block_size]
    if len(chunk) < block_size:
        chunk += b"\0" * (block_size - len(chunk))
    (out / f"blk{i:09d}.bin").write_bytes(chunk)
(out / "blk.txt").write_text("{\n  block_size: 256,\n  n_block: %d,\n}\n" % n_block)
PY

    cp ${kernel} "$out/kernel-x86_64-new.bin"
    cp ${termJs} "$out/term.js"
    cp ${jslinuxJs} "$out/jslinux.js"
    cp ${emulatorJs} "$out/x86_64emu-wasm.js"
    cp ${emulatorWasm} "$out/x86_64emu-wasm.wasm"
    cp ${repoSrc}/docs/index.html "$out/index.html"
    cp ${repoSrc}/docs/site.css "$out/site.css"
    cp ${repoSrc}/docs/NOTICE.md "$out/NOTICE.md"

    cat > "$out/blynn-x86_64.cfg" <<'EOF'
/* VM configuration file */
{
  version: 1,
  machine: "pc",
  memory_size: 2048,
  kernel: "kernel-x86_64-new.bin",
  cmdline: "loglevel=3 console=hvc0 root=/dev/vda rw init=/init",
  drive0: { file: "blynn-root/blk.txt" },
}
EOF
  '';
}
