#!/usr/bin/env python3
import argparse
import pathlib
import shutil
import subprocess


TARGETS = {
    "amd64": {
        "m1_arch": "amd64",
        "m2_dir": "amd64",
        "defs": "amd64_defs.M1",
        "elf": "ELF-amd64.hex2",
        "base": "0x00600000",
        "support": [
            "amd64-compat.M1",
            "amd64-start.M1",
            "amd64-memory.M1",
            "{support}",
            "{test}",
            "amd64-syscalls.M1",
        ],
    },
    "i386": {
        "m1_arch": "x86",
        "m2_dir": "x86",
        "defs": "x86_defs.M1",
        "elf": "ELF-x86.hex2",
        "base": "0x08048000",
        "support": [
            "i386-start.M1",
            "i386-memory.M1",
            "{support}",
            "{test}",
            "i386-syscalls.M1",
        ],
    },
    "aarch64": {
        "m1_arch": "aarch64",
        "m2_dir": "aarch64",
        "defs": "aarch64_defs.M1",
        "elf": "ELF-aarch64.hex2",
        "base": "0x00600000",
        "support": [
            "aarch64-start.M1",
            "aarch64-memory.M1",
            "{support}",
            "{test}",
            "aarch64-syscalls.M1",
        ],
    },
}

ARGS = {
    "31_args": ["arg1", "arg2", "arg3", "arg4", "arg5"],
    "46_grep": [r"[^* ]*[:a:d: ]+\:\*-/: $$", "46_grep.c"],
}

FLAGS = {
    "76_dollars_in_identifiers": ["-fdollars-in-identifiers"],
}

ALWAYS_SKIP = {
    "34_array_assignment": "array assignment is not in C standard",
}

STAGES = ["pass", "preprocess", "hcc", "assemble", "run", "output", "skip"]


def decode_output(exc):
    out = exc.stdout or ""
    if isinstance(out, bytes):
        out = out.decode(errors="replace")
    return out


def run_step(cmd, log, timeout, **kwargs):
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=timeout,
            **kwargs,
        )
    except subprocess.TimeoutExpired as exc:
        out = decode_output(exc) + f"\nTIMEOUT after {timeout} seconds\n"
        log.write_text("$ " + " ".join(str(x) for x in cmd) + "\n" + out)
        return 124, out
    if result.returncode != 0:
        log.write_text("$ " + " ".join(str(x) for x in cmd) + "\n" + result.stdout)
    return result.returncode, result.stdout


def compile_m1(args, src, name, out_m1):
    work = args.work_dir
    preprocessed = work / f"{name}.i"
    ir = work / f"{name}.hccir"
    flags = FLAGS.get(name, [])

    code, out = run_step(
        [
            args.hcpp,
            "-I",
            str(args.source_dir),
            "-I",
            str(args.source_dir.parents[1] / "include"),
            *flags,
            str(src),
        ],
        work / f"{name}.hcpp.err",
        args.tool_timeout,
        cwd=work,
    )
    (work / f"{name}.hcpp.out").write_text(out)
    if code:
        return "preprocess"
    preprocessed.write_text(out)

    code, out = run_step(
        [
            args.hcc1,
            "--target",
            args.target,
            "--m1-ir",
            "-o",
            str(ir),
            str(preprocessed),
        ],
        work / f"{name}.hcc1.err",
        args.tool_timeout,
        cwd=work,
    )
    (work / f"{name}.hcc1.out").write_text(out)
    if code:
        return "hcc"

    code, out = run_step(
        [args.hcc_m1, "--target", args.target, str(ir), str(out_m1)],
        work / f"{name}.hcc-m1.err",
        args.tool_timeout,
        cwd=work,
    )
    (work / f"{name}.hcc-m1.out").write_text(out)
    if code:
        return "hcc"
    return None


def assemble(args, name, test_m1):
    work = args.work_dir
    target = TARGETS[args.target]
    hex2 = work / f"{name}.hex2"
    end = work / f"{name}-end.hex2"
    exe = work / f"{name}.exe"
    support_m1 = work / "support.M1"
    inputs = []
    for item in target["support"]:
        if item == "{support}":
            inputs += ["-f", str(support_m1)]
        elif item == "{test}":
            inputs += ["-f", str(test_m1)]
        else:
            inputs += ["-f", str(args.support_dir / item)]

    code, out = run_step(
        [
            args.m1,
            "--architecture",
            target["m1_arch"],
            "--little-endian",
            "-f",
            str(args.m2libc / target["m2_dir"] / target["defs"]),
            *inputs,
            "--output",
            str(hex2),
        ],
        work / f"{name}.m1.err",
        args.tool_timeout,
        cwd=work,
    )
    (work / f"{name}.m1.out").write_text(out)
    if code:
        return "assemble", None

    end.write_text(":ELF_end\n")
    code, out = run_step(
        [
            args.hex2,
            "--architecture",
            target["m1_arch"],
            "--little-endian",
            "--base-address",
            target["base"],
            "--file",
            str(args.m2libc / target["m2_dir"] / target["elf"]),
            "--file",
            str(hex2),
            "--file",
            str(end),
            "--output",
            str(exe),
        ],
        work / f"{name}.hex2.err",
        args.tool_timeout,
        cwd=work,
    )
    (work / f"{name}.hex2.out").write_text(out)
    if code:
        return "assemble", None

    exe.chmod(0o755)
    return None, exe


def case_args(source_dir, name):
    args = ARGS.get(name, [])
    if name == "46_grep":
        return [args[0], str(source_dir / args[1])]
    return args


def run_case(args, name):
    test_m1 = args.work_dir / f"{name}.M1"
    src = args.source_dir / f"{name}.c"

    failed = compile_m1(args, src, name, test_m1)
    if failed:
        return failed, ""

    failed, exe = assemble(args, name, test_m1)
    if failed:
        return failed, ""

    try:
        result = subprocess.run(
            [*args.runner, str(exe), *case_args(args.source_dir, name)],
            cwd=args.work_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=args.run_timeout,
        )
    except subprocess.TimeoutExpired as exc:
        out = decode_output(exc) + f"\nTIMEOUT after {args.run_timeout} seconds\n"
        (args.work_dir / f"{name}.run.err").write_text(out)
        return "run", out

    out = result.stdout.replace(str(args.source_dir) + "/", "")
    (args.work_dir / f"{name}.output").write_text(out)
    if result.returncode:
        (args.work_dir / f"{name}.run.err").write_text(out)
        return "run", out
    return "output", out


def save_failure(work_dir, fail_dir, name):
    out = fail_dir / name
    out.mkdir(parents=True, exist_ok=True)
    for path in work_dir.glob(f"{name}.*"):
        if path.is_file():
            shutil.copy2(path, out / path.name)


def write_summary(path, stages):
    total = sum(len(stages[name]) for name in STAGES)
    attempted = total - len(stages["skip"])
    lines = [
        f"total={total}",
        f"attempted={attempted}",
        f"pass={len(stages['pass'])}",
        f"preprocess_fail={len(stages['preprocess'])}",
        f"hcc_fail={len(stages['hcc'])}",
        f"assemble_fail={len(stages['assemble'])}",
        f"run_fail={len(stages['run'])}",
        f"output_fail={len(stages['output'])}",
        f"skip={len(stages['skip'])}",
    ]
    lines += [name + "=" + " ".join(stages[name]) for name in STAGES]
    path.write_text("\n".join(lines) + "\n")
    print("hcc-tinycc-tests2-stat: " + " ".join(lines[:9]))


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hcpp", required=True)
    parser.add_argument("--hcc1", required=True)
    parser.add_argument("--hcc-m1", dest="hcc_m1", required=True)
    parser.add_argument("--m1", default="M1")
    parser.add_argument("--hex2", default="hex2")
    parser.add_argument("--target", choices=sorted(TARGETS), default="amd64")
    parser.add_argument("--runner", action="append", default=[])
    parser.add_argument("--m2libc", type=pathlib.Path, required=True)
    parser.add_argument("--support-dir", type=pathlib.Path, required=True)
    parser.add_argument("--source-dir", type=pathlib.Path, required=True)
    parser.add_argument("--work-dir", type=pathlib.Path, required=True)
    parser.add_argument("--summary", type=pathlib.Path, required=True)
    parser.add_argument("--fail-dir", type=pathlib.Path, required=True)
    parser.add_argument("--tool-timeout", type=int, default=30)
    parser.add_argument("--run-timeout", type=int, default=5)
    return parser.parse_args()


def main():
    args = parse_args()
    args.source_dir = args.source_dir.resolve()
    args.support_dir = args.support_dir.resolve()
    args.m2libc = args.m2libc.resolve()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    args.fail_dir.mkdir(parents=True, exist_ok=True)

    support_failed = compile_m1(
        args,
        args.support_dir / "tcc-bootstrap-support.c",
        "support",
        args.work_dir / "support.M1",
    )
    if support_failed:
        raise SystemExit(f"HCC support runtime failed at {support_failed}")

    stages = {name: [] for name in STAGES}
    for src in sorted(args.source_dir.glob("*.c")):
        name = src.stem
        if not src.with_suffix(".expect").exists():
            continue
        if name in ALWAYS_SKIP:
            stages["skip"].append(name)
            print(f"SKIP {name}: {ALWAYS_SKIP[name]}")
            continue
        if name == "73_arm64" and args.target != "aarch64":
            stages["skip"].append(name)
            print(f"SKIP {name}: not a {args.target} test")
            continue

        print(f"TEST {name}")
        stage, out = run_case(args, name)
        if stage != "output":
            stages[stage].append(name)
            save_failure(args.work_dir, args.fail_dir, name)
            print(f"FAIL {name}: {stage}")
            continue

        expect = (args.source_dir / f"{name}.expect").read_text()
        if out == expect:
            stages["pass"].append(name)
            print(f"PASS {name}")
        else:
            stages["output"].append(name)
            save_failure(args.work_dir, args.fail_dir, name)
            print(f"FAIL {name}: output")

    write_summary(args.summary, stages)


if __name__ == "__main__":
    main()
