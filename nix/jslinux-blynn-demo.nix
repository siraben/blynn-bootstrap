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
  stage0Riscv64Src,
  bootstrapSeedsSrc,
  nixBuiltTinycc,
}:

let
  alpineMinirootfs = fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/riscv64/alpine-minirootfs-3.23.3-riscv64.tar.gz";
    hash = "sha256-7uAM6bt5XjctBUsFnmHD8lhgiSJ0VFYcLg8voEVOBMU=";
  };
  bios = fetchurl {
    url = "https://bellard.org/jslinux/bbl64.bin";
    hash = "sha256-KTYQzqevbHXkqDN+FsDWKDS+y/Mf/ZzKNeDCEWAjSds=";
  };
  kernel = fetchurl {
    url = "https://bellard.org/jslinux/kernel-riscv64.bin";
    hash = "sha256-ZcpwplYKcwOWq2FIjRz0YImzLaWvflNeA8GAzVvMjnU=";
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
    url = "https://bellard.org/jslinux/riscvemu64-wasm.js";
    hash = "sha256-xmE2x7b1LfZSyys7UfYLW2JPteyVeDfDh7rrn/LIOYE=";
  };
  emulatorWasm = fetchurl {
    url = "https://bellard.org/jslinux/riscvemu64-wasm.wasm";
    hash = "sha256-X6nb8Wnv9EdSXPmMU40Go/CO6q735Mczglrln8XJJU4=";
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
    : > "$root/init"
    chmod 755 "$root/init"

    mkdir -p \
      "$root/bootstrap/repo" \
      "$root/bootstrap/upstreams" \
      "$root/bootstrap/tool-wrappers" \
      "$root/bootstrap/stage0-tools" \
      "$root/bootstrap/stage0-m2libc" \
      "$root/bootstrap/source-cache"

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
    cp -R ${stage0PosixSrc} "$root/bootstrap/source-cache/stage0-posix"
    chmod -R u+w "$root/bootstrap/source-cache/stage0-posix"
    rm -rf "$root/bootstrap/source-cache/stage0-posix/riscv64"
    cp -R ${stage0Riscv64Src} "$root/bootstrap/source-cache/stage0-posix/riscv64"
    rm -rf "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds"
    cp -R ${bootstrapSeedsSrc} "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds"
    chmod -R u+w "$root/bootstrap/source-cache/stage0-posix"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/stage0-posix.rev "$root/bootstrap/source-cache/stage0-posix/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/AMD64.rev "$root/bootstrap/source-cache/stage0-posix/AMD64/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/riscv64.rev "$root/bootstrap/source-cache/stage0-posix/riscv64/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/M2-Mesoplanet.rev "$root/bootstrap/source-cache/stage0-posix/M2-Mesoplanet/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/M2-Planet.rev "$root/bootstrap/source-cache/stage0-posix/M2-Planet/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/M2libc.rev "$root/bootstrap/source-cache/stage0-posix/M2libc/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/bootstrap-seeds.rev "$root/bootstrap/source-cache/stage0-posix/bootstrap-seeds/.bootstrap-rev"
    install -Dm644 ${repoSrc}/nix/jslinux/bootstrap-revs/mescc-tools.rev "$root/bootstrap/source-cache/stage0-posix/mescc-tools/.bootstrap-rev"

    install -Dm755 ${repoSrc}/nix/jslinux/guest/M2-Mesoplanet "$root/bootstrap/tool-wrappers/M2-Mesoplanet"
    install -Dm755 ${repoSrc}/nix/jslinux/guest/run-portable-demo.sh "$root/bootstrap/run-portable-demo.sh"
    install -Dm644 ${repoSrc}/nix/jslinux/help/bootstrap.txt "$root/bootstrap/help/bootstrap.txt"
    install -Dm644 ${repoSrc}/nix/jslinux/help/lowmem.txt "$root/bootstrap/help/lowmem.txt"
    install -Dm644 ${repoSrc}/nix/jslinux/help/banner.txt "$root/bootstrap/help/banner.txt"

    mkdir -p "$root/usr/local/bin"
    install -Dm755 ${repoSrc}/nix/jslinux/guest/blynn-tcc "$root/usr/local/bin/blynn-tcc"
    install -Dm755 ${repoSrc}/nix/jslinux/guest/bootstrap "$root/usr/local/bin/bootstrap"
    install -Dm755 ${repoSrc}/nix/jslinux/guest/init "$root/init"

    mkdir -p "$out"
    genext2fs -B 1024 -b 393216 -N 200000 -d "$root" -D ${repoSrc}/nix/jslinux/devices.txt "$TMPDIR/blynn-root.ext2"
    tune2fs -O large_file "$TMPDIR/blynn-root.ext2"
    fsck_status=0
    e2fsck -fy "$TMPDIR/blynn-root.ext2" || fsck_status=$?
    if [ "$fsck_status" -gt 1 ]; then
      exit "$fsck_status"
    fi

    disk_hash=$(sha256sum "$TMPDIR/blynn-root.ext2" | cut -c1-12)
    disk_dir="blynn-root-$disk_hash"
    cfg_file="blynn-riscv64-$disk_hash.cfg"
    mkdir -p "$out/$disk_dir"
    python3 ${repoSrc}/nix/jslinux/split-image.py "$TMPDIR/blynn-root.ext2" "$out/$disk_dir"

    install -m 644 ${repoSrc}/nix/jslinux/blynn-riscv64.cfg "$out/$cfg_file"
    substituteInPlace "$out/$cfg_file" \
      --replace-fail @drive_dir@ "$disk_dir"
    cp "$out/$cfg_file" "$out/blynn-riscv64.cfg"

    cp ${bios} "$out/bbl64.bin"
    cp ${kernel} "$out/kernel-riscv64.bin"
    cp ${termJs} "$out/term.js"
    cp ${jslinuxJs} "$out/jslinux.js"
    # Upstream hardcodes 10000 lines of terminal scrollback; the bootstrap build
    # emits a lot of output, so cap the DOM-backed buffer to bound memory.
    substituteInPlace "$out/jslinux.js" \
      --replace-fail "scrollback: 10000" "scrollback: 5000"
    cp ${emulatorJs} "$out/riscvemu64-wasm.js"
    cp ${emulatorWasm} "$out/riscvemu64-wasm.wasm"
    css_hash=$(sha256sum ${repoSrc}/docs/site.css | cut -c1-12)
    css_file="site-$css_hash.css"

    cp ${repoSrc}/docs/index.html "$out/index.html"
    substituteInPlace "$out/index.html" \
      --replace-fail blynn-riscv64.cfg "$cfg_file" \
      --replace-fail site.css "$css_file"
    cp ${repoSrc}/docs/site.css "$out/$css_file"
    cp "$out/$css_file" "$out/site.css"
    cp ${repoSrc}/docs/NOTICE.md "$out/NOTICE.md"
  '';
}
