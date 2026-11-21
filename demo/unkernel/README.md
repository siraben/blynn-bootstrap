# TinyCC bootstrap on unkernel

```sh
nix build .#unkernel-blynn-demo
python3 -m http.server 8000 --directory result
```

Open <http://localhost:8000/> to boot into an interactive AArch64 Linux terminal. Type `bootstrap` at the prompt or click **Run bootstrap**. The pinned unkernel SDK boots its bundled environment without a distro image. The page loads the kernel, terminal assets, and checkpoint from the same server.

The checkpoint contains HCC-built TinyCC stage 1, sources, headers, and prebuilt startup and support objects. Inside the guest, stage 1 builds stage 2, which builds stage 3, which builds stage 4. The demo compares stages 3 and 4 byte-for-byte and prints their hashes. This tests self-hosting from the TinyCC checkpoint, not the compiler ladder from seed. It does not replace the RV64 JSLinux demo or deploy a Pages site.

For the seed path, open <http://localhost:8000/?stage0> and type `bootstrap-stage0`. This mode downloads a separate source archive, not the TinyCC checkpoint. It starts with the pinned 526-byte AArch64 `hex0-seed` and verifies `kaem`, `hex2`, `M1`, `blood-elf`, `M2-Planet`, and `M2-Mesoplanet` against upstream `aarch64.answers`. It stops at the verified stage0 toolchain; it does not yet feed those tools into the Blynn/HCC/TinyCC ladder.
