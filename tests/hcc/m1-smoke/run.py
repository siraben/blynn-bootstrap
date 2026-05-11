#!/usr/bin/env python3
import argparse
import pathlib
import subprocess


CASES = [
    ("ret13", 13),
    ("short-circuit", 42),
    ("local-aggregate", 3),
    ("call-arg-immediate", 42),
    ("dynamic-aggregate", 0),
    ("conditional-aggregate-copy", 0),
    ("signed-char-cast", 0),
    ("sizeof-member-array-bound", 0),
    ("address-written-scalar", 0),
    ("escaped-string-magic", 0),
    ("archive-header-layout", 0),
]


TARGETS = {
    "amd64": {
        "hcc_target": "amd64",
        "m1_arch": "amd64",
        "m2_dir": "amd64",
        "defs": "amd64_defs.M1",
        "libc_core": "libc-core.M1",
        "elf": "ELF-amd64.hex2",
        "base": "0x00600000",
    },
    "i386": {
        "hcc_target": "i386",
        "m1_arch": "x86",
        "m2_dir": "x86",
        "defs": "x86_defs.M1",
        "libc_core": "libc-core.M1",
        "elf": "ELF-x86.hex2",
        "base": "0x08048000",
    },
    "aarch64": {
        "hcc_target": "aarch64",
        "m1_arch": "aarch64",
        "m2_dir": "aarch64",
        "defs": "aarch64_defs.M1",
        "libc_core": "libc-core.M1",
        "elf": "ELF-aarch64.hex2",
        "base": "0x00600000",
    },
}


def run(argv):
    subprocess.run(argv, check=True)


def log(message):
    print(f"hcc-m1-smoke: {message}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hcpp", default="hcpp")
    parser.add_argument("--hcc1", default="hcc1")
    parser.add_argument("--hcc-m1", default="hcc-m1")
    parser.add_argument("--m2libc", required=True)
    parser.add_argument("--source-dir", default=str(pathlib.Path(__file__).parent))
    parser.add_argument("--work-dir", default=".")
    parser.add_argument("--target", choices=sorted(TARGETS), default="amd64")
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args()

    target = TARGETS[args.target]
    source_dir = pathlib.Path(args.source_dir)
    work_dir = pathlib.Path(args.work_dir)
    examples_dir = source_dir / "examples"
    m2libc = pathlib.Path(args.m2libc)

    work_dir.mkdir(parents=True, exist_ok=True)
    log(f"running {len(CASES)} cases for {args.target}")
    for name, expected in CASES:
        log(f"START {name}")
        src = examples_dir / f"{name}.c"
        preprocessed = work_dir / f"{name}.i"
        hccir = work_dir / f"{name}.hccir"
        m1 = work_dir / f"{name}.M1"
        hex2 = work_dir / f"{name}.hex2"
        end = work_dir / f"{name}-end.hex2"
        exe = work_dir / name

        with preprocessed.open("w") as handle:
            log(f"{name}: hcpp {src.name} -> {preprocessed.name}")
            subprocess.run([args.hcpp, str(src)], check=True, stdout=handle)
        log(f"{name}: hcc1 --m1-ir -> {hccir.name}")
        run([args.hcc1, "--target", target["hcc_target"], "--m1-ir", "-o", str(hccir), str(preprocessed)])
        log(f"{name}: hcc-m1 -> {m1.name}")
        run([args.hcc_m1, "--target", target["hcc_target"], str(hccir), str(m1)])
        log(f"{name}: M1 -> {hex2.name}")
        run([
            "M1",
            "--architecture", target["m1_arch"],
            "--little-endian",
            "-f", str(m2libc / target["m2_dir"] / target["defs"]),
            "-f", str(m2libc / target["m2_dir"] / target["libc_core"]),
            "-f", str(m1),
            "--output", str(hex2),
        ])
        end.write_text(":ELF_end\n")
        log(f"{name}: hex2 -> {exe.name}")
        run([
            "hex2",
            "--architecture", target["m1_arch"],
            "--little-endian",
            "--base-address", target["base"],
            "--file", str(m2libc / target["m2_dir"] / target["elf"]),
            "--file", str(hex2),
            "--file", str(end),
            "--output", str(exe),
        ])
        exe.chmod(0o755)
        if args.no_run:
            log(f"{name}: assembled")
            log(f"DONE  {name}")
            continue
        log(f"{name}: execute, expect exit {expected}")
        result = subprocess.run([str(exe.resolve())])
        if result.returncode != expected:
            raise SystemExit(f"{name}: got exit {result.returncode}, expected {expected}")
        log(f"DONE  {name}")
    log("all cases passed")


if __name__ == "__main__":
    main()
