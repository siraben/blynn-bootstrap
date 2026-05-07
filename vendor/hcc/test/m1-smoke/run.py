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
]


def run(argv):
    subprocess.run(argv, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hcc", default="hcc")
    parser.add_argument("--m2libc", required=True)
    parser.add_argument("--source-dir", default=str(pathlib.Path(__file__).parent))
    parser.add_argument("--work-dir", default=".")
    args = parser.parse_args()

    source_dir = pathlib.Path(args.source_dir)
    work_dir = pathlib.Path(args.work_dir)
    examples_dir = source_dir / "examples"
    m2libc = pathlib.Path(args.m2libc)

    work_dir.mkdir(parents=True, exist_ok=True)
    for name, expected in CASES:
        src = examples_dir / f"{name}.c"
        m1 = work_dir / f"{name}.M1"
        hex2 = work_dir / f"{name}.hex2"
        end = work_dir / f"{name}-end.hex2"
        exe = work_dir / name

        run([args.hcc, "-S", "-o", str(m1), str(src)])
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
        result = subprocess.run([str(exe.resolve())])
        if result.returncode != expected:
            raise SystemExit(f"{name}: got exit {result.returncode}, expected {expected}")


if __name__ == "__main__":
    main()
