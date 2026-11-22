# TinyCC bootstrap on unkernel

[Open the live terminal](https://siraben.github.io/blynn-bootstrap/) or serve the static site locally:

```sh
nix build .#unkernel-blynn-demo
python3 -m http.server 8000 --directory result
```

Open <http://localhost:8000/> to boot into an interactive AArch64 Linux terminal. Type `bootstrap` at the prompt or click **Run bootstrap**. The pinned unkernel SDK boots its bundled environment without a distro image. The page loads the kernel, terminal assets, and checkpoint from the same server.

The checkpoint contains HCC-built TinyCC stage 1, sources, headers, and prebuilt startup and support objects. Inside the guest, stage 1 builds stage 2, which builds stage 3, which builds stage 4. The demo compares stages 3 and 4 byte-for-byte and prints their hashes. This tests self-hosting from the TinyCC checkpoint, not the compiler ladder from seed.

Open the [seed terminal](https://siraben.github.io/blynn-bootstrap/?stage0) (locally, <http://localhost:8000/?stage0>). `bootstrap-stage0` starts from the pinned 526-byte AArch64 `hex0-seed` and verifies six tools against upstream `aarch64.answers`. The experimental `bootstrap-from-seed` command then uses those tools to build Blynn and HCC, and asks that HCC to build a runnable TinyCC stage 1. It downloads a separate source archive, not the TinyCC checkpoint. The full browser run is not yet verified and requests 2 GiB of guest memory.

The monitor reports guest CPU utilization, virtual block I/O, and console output. Block I/O excludes RAM-backed files and the host mount; zeros are normal in the bundled environment.

The Pages workflow builds `.#unkernel-blynn-demo` and publishes its output at <https://siraben.github.io/blynn-bootstrap/>.
