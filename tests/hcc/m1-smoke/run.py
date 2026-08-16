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
    ("global-address-addend", 0),
    ("escaped-string-magic", 0),
    ("archive-header-layout", 0),
    ("scoped-typedef-enum", 0),
    ("wide-integer-types", 0),
    ("return-coercion", 0),
    ("function-pointer-call-type", 0),
    ("function-designator-deref", 0),
    ("aggregate-argument-copy", 0),
    ("bitfield-layout", 0),
    ("enum-bitfield-signedness", 0),
    ("integer-literal-suffixes", 0),
    ("multidimensional-array", 0),
    ("unsigned-compound-shift", 0),
    ("function-typedef-prototype", 0),
    ("union-cast", 0),
    ("inferred-array-size", 0),
    ("sizeof-string-literal", 0),
    ("static-local-storage", 0),
    ("case-cmp-ternary", 0),
    ("pointer-to-pointer-callback", 0),
    ("bootstrap-qsort-pointer", 0),
    ("for-decl-scope", 0),
    ("typedef-shadow", 3),
    ("asm-nop", 0),
    ("variadic-register-stack", 0),
    ("switch-prelude-label", 0),
    ("static-internal-linkage", 0),
]

AMD64_CASES = [
    ("variadic-sysv-forward", 0),
    ("stack-call-alignment", 0),
]

MULTI_TU_CASES = [
    ("static-conflict", ["static-conflict-left", "static-conflict-right", "static-conflict-main"], 0),
    (
        "static-same-basename",
        ["static-same-basename-left/unit", "static-same-basename-right/unit", "static-same-basename-main"],
        0,
    ),
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
        "runner": [],
    },
    "riscv64": {
        "hcc_target": "riscv64",
        "m1_arch": "riscv64",
        "m2_dir": "riscv64",
        "defs": "riscv64_defs.M1",
        "libc_core": "libc-core.M1",
        "elf": "ELF-riscv64.hex2",
        "base": "0x00600000",
        "runner": ["qemu-riscv64"],
    },
}

for target in TARGETS.values():
    target.setdefault("runner", [])


def run(argv):
    subprocess.run(argv, check=True)


def log(message):
    print(f"hcc-m1-smoke: {message}", flush=True)


def assert_static_internal_linkage(m1):
    text = m1.read_text()
    forbidden = [":FUNCTION_helper", ":internal_value"]
    for label in forbidden:
        if label in text:
            raise SystemExit(f"{m1.name}: static label was emitted externally: {label}")
    if ":FUNCTION_HCC_INTERNAL_" not in text:
        raise SystemExit(f"{m1.name}: static function label was not internalized")
    if ":HCC_INTERNAL_" not in text:
        raise SystemExit(f"{m1.name}: static object label was not internalized")


def assert_static_conflict_unit(m1):
    text = m1.read_text()
    forbidden = [":FUNCTION_helper", ":shared"]
    for label in forbidden:
        if label in text:
            raise SystemExit(f"{m1.name}: static label was emitted externally: {label}")
    if ":FUNCTION_HCC_INTERNAL_" not in text:
        raise SystemExit(f"{m1.name}: static function label was not internalized")
    if ":HCC_INTERNAL_" not in text:
        raise SystemExit(f"{m1.name}: static object label was not internalized")


def assert_amd64_macro_namespace(m1):
    text = m1.read_text()
    for macro in ("CMP", "STORE_INTEGER"):
        if f"DEFINE {macro} " in text:
            raise SystemExit(f"{m1.name}: HCC overrides shared M1 macro {macro}")


def compile_to_m1(args, target, examples_dir, work_dir, name):
    src = examples_dir / f"{name}.c"
    preprocessed = work_dir / f"{name}.i"
    hccir = work_dir / f"{name}.hccir"
    m1 = work_dir / f"{name}.M1"
    preprocessed.parent.mkdir(parents=True, exist_ok=True)

    with preprocessed.open("w") as handle:
        log(f"{name}: hcpp {src.name} -> {preprocessed.name}")
        subprocess.run([args.hcpp, str(src)], check=True, stdout=handle)
    log(f"{name}: hcc1 --m1-ir -> {hccir.name}")
    run([
        args.hcc1,
        "--target", target["hcc_target"],
        "--data-prefix", str(hccir),
        "--m1-ir", "-o", str(hccir), str(preprocessed),
    ])
    log(f"{name}: hcc-m1 -> {m1.name}")
    run([args.hcc_m1, "--target", target["hcc_target"], str(hccir), str(m1)])
    if name == "static-internal-linkage":
        assert_static_internal_linkage(m1)
    if name in ("static-conflict-left", "static-conflict-right") or name.endswith("/unit"):
        assert_static_conflict_unit(m1)
    if target["hcc_target"] == "amd64" and name == "ret13":
        assert_amd64_macro_namespace(m1)
    return m1


def assemble_and_run(args, target, m2libc, work_dir, name, m1_files, expected):
    hex2 = work_dir / f"{name}.hex2"
    end = work_dir / f"{name}-end.hex2"
    exe = work_dir / name

    log(f"{name}: M1 -> {hex2.name}")
    m1_argv = [
        "M1",
        "--architecture", target["m1_arch"],
        "--little-endian",
        "-f", str(m2libc / target["m2_dir"] / target["defs"]),
        "-f", str(m2libc / target["m2_dir"] / target["libc_core"]),
    ]
    for m1 in m1_files:
        m1_argv.extend(["-f", str(m1)])
    m1_argv.extend(["--output", str(hex2)])
    run(m1_argv)

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
        return
    log(f"{name}: execute, expect exit {expected}")
    runner = args.runner or target["runner"]
    result = subprocess.run(runner + [str(exe.resolve())])
    if result.returncode != expected:
        raise SystemExit(f"{name}: got exit {result.returncode}, expected {expected}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hcpp", default="hcpp")
    parser.add_argument("--hcc1", default="hcc1")
    parser.add_argument("--hcc-m1", default="hcc-m1")
    parser.add_argument("--m2libc", required=True)
    parser.add_argument("--source-dir", default=str(pathlib.Path(__file__).parent))
    parser.add_argument("--work-dir", default=".")
    parser.add_argument("--target", choices=sorted(TARGETS), default="amd64")
    parser.add_argument("--runner", action="append", default=[])
    parser.add_argument("--no-run", action="store_true")
    args = parser.parse_args()

    target = TARGETS[args.target]
    source_dir = pathlib.Path(args.source_dir)
    work_dir = pathlib.Path(args.work_dir)
    examples_dir = source_dir / "examples"
    m2libc = pathlib.Path(args.m2libc)

    work_dir.mkdir(parents=True, exist_ok=True)
    cases = CASES + (AMD64_CASES if args.target == "amd64" else [])
    log(f"running {len(cases)} cases and {len(MULTI_TU_CASES)} multi-tu cases for {args.target}")
    for name, expected in cases:
        log(f"START {name}")
        m1 = compile_to_m1(args, target, examples_dir, work_dir, name)
        m1_files = [m1]
        if name == "stack-call-alignment":
            m1_files.insert(0, source_dir / "stack-call-alignment.M1")
        assemble_and_run(args, target, m2libc, work_dir, name, m1_files, expected)
        log(f"DONE  {name}")
    for name, units, expected in MULTI_TU_CASES:
        log(f"START {name}")
        m1_files = [compile_to_m1(args, target, examples_dir, work_dir, unit) for unit in units]
        assemble_and_run(args, target, m2libc, work_dir, name, m1_files, expected)
        log(f"DONE  {name}")
    log("all cases passed")


if __name__ == "__main__":
    main()
