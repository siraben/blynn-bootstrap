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
    args = parser.parse_args()

    source_dir = pathlib.Path(args.source_dir)
    work_dir = pathlib.Path(args.work_dir)
    examples_dir = source_dir / "examples"
    m2libc = pathlib.Path(args.m2libc)

    work_dir.mkdir(parents=True, exist_ok=True)
    log(f"running {len(CASES)} cases")
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
        run([args.hcc1, "--m1-ir", "-o", str(hccir), str(preprocessed)])
        log(f"{name}: hcc-m1 -> {m1.name}")
        run([args.hcc_m1, str(hccir), str(m1)])
        log(f"{name}: M1 -> {hex2.name}")
        run([
            "M1",
            "--architecture", "amd64",
            "--little-endian",
            "-f", str(m2libc / "amd64" / "amd64_defs.M1"),
            "-f", str(m2libc / "amd64" / "libc-core.M1"),
            "-f", str(m1),
            "--output", str(hex2),
        ])
        end.write_text(":ELF_end\n")
        log(f"{name}: hex2 -> {exe.name}")
        run([
            "hex2",
            "--architecture", "amd64",
            "--little-endian",
            "--base-address", "0x00600000",
            "--file", str(m2libc / "amd64" / "ELF-amd64.hex2"),
            "--file", str(hex2),
            "--file", str(end),
            "--output", str(exe),
        ])
        exe.chmod(0o755)
        log(f"{name}: execute, expect exit {expected}")
        result = subprocess.run([str(exe.resolve())])
        if result.returncode != expected:
            raise SystemExit(f"{name}: got exit {result.returncode}, expected {expected}")
        log(f"DONE  {name}")
    log("all cases passed")


if __name__ == "__main__":
    main()
