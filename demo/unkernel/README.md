# TinyCC bootstrap on unkernel

```sh
nix build .#unkernel-blynn-demo
python3 -m http.server 8000 --directory result
```

Open <http://localhost:8000/> to boot into an interactive AArch64 Linux terminal. Type `bootstrap` at the prompt or click **Run bootstrap**. The pinned unkernel SDK boots its bundled environment without a distro image. The page loads the kernel, terminal assets, and checkpoint from the same server.

The checkpoint contains HCC-built TinyCC stage 1, sources, headers, and prebuilt startup and support objects. Inside the guest, stage 1 builds stage 2, which builds stage 3, which builds stage 4. The demo compares stages 3 and 4 byte-for-byte and prints their hashes. This tests self-hosting from the TinyCC checkpoint, not the compiler ladder from seed. It does not replace the RV64 JSLinux demo or deploy a Pages site.
