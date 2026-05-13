#!/usr/bin/env python3
"""Grammar-directed fuzzer for hcc1.

The generator intentionally mixes complete C fragments with truncated parser
states.  A syntax or codegen error is acceptable; a signal or timeout is not.
Crashers are written to --out-dir with stdout/stderr and a short summary.
"""

from __future__ import annotations

import argparse
import os
import random
import shutil
import signal
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


IDENTS = [
    "main",
    "f",
    "g",
    "x",
    "y",
    "z",
    "p",
    "q",
    "arr",
    "node",
    "next",
    "value",
]

TYPES = [
    "int",
    "char",
    "long",
    "unsigned",
    "unsigned int",
    "void",
]

BINOPS = ["+", "-", "*", "/", "%", "&", "|", "^", "==", "!=", "<", "<=", ">", ">=", "&&", "||"]
UNOPS = ["+", "-", "!", "~", "*", "&"]

TRUNCATION_SUFFIXES = [
    "",
    "return",
    "return ~",
    "if (",
    "if (x)",
    "while (",
    "for (",
    "sizeof(",
    "int",
    "int x[",
    "x[",
    "p->",
    "p->value",
    "asm(",
    "asm(\"x\"",
    "goto",
    "struct S {",
    "struct S { int",
    "enum {",
    "enum { A =",
    "/*",
    "\"",
    "'",
]


@dataclass
class Case:
    text: str
    seed: int
    index: int


def choice(rng: random.Random, xs: list[str]) -> str:
    return xs[rng.randrange(len(xs))]


def ident(rng: random.Random) -> str:
    base = choice(rng, IDENTS)
    if rng.randrange(5) == 0:
        return f"{base}{rng.randrange(8)}"
    return base


def ctype(rng: random.Random, allow_void: bool = False) -> str:
    ty = choice(rng, TYPES if allow_void else [t for t in TYPES if t != "void"])
    while rng.randrange(4) == 0:
        ty += " *"
    return ty


def integer(rng: random.Random) -> str:
    values = ["0", "1", "2", "3", "7", "13", "42", "-1", "127", "255", "1024"]
    return choice(rng, values)


def string_lit(rng: random.Random) -> str:
    parts = ["", "x", "hello", "\\n", "\\0", "\\\\", "\\\"", "abc"]
    return '"' + choice(rng, parts) + '"'


def expr(rng: random.Random, depth: int) -> str:
    if depth <= 0:
        leaf = rng.randrange(7)
        if leaf == 0:
            return integer(rng)
        if leaf == 1:
            return ident(rng)
        if leaf == 2:
            return string_lit(rng)
        if leaf == 3:
            return f"{ident(rng)}[{integer(rng)}]"
        if leaf == 4:
            return f"{ident(rng)}()"
        if leaf == 5:
            return f"sizeof({ctype(rng)})"
        return f"({integer(rng)})"

    kind = rng.randrange(10)
    if kind < 3:
        return expr(rng, 0)
    if kind == 3:
        return f"({expr(rng, depth - 1)} {choice(rng, BINOPS)} {expr(rng, depth - 1)})"
    if kind == 4:
        return f"{choice(rng, UNOPS)}{expr(rng, depth - 1)}"
    if kind == 5:
        return f"{ident(rng)} = {expr(rng, depth - 1)}"
    if kind == 6:
        return f"{ident(rng)}({expr(rng, depth - 1)})"
    if kind == 7:
        return f"{ident(rng)}[{expr(rng, depth - 1)}]"
    if kind == 8:
        return f"{expr(rng, depth - 1)} ? {expr(rng, depth - 1)} : {expr(rng, depth - 1)}"
    return f"({expr(rng, depth - 1)})"


def declaration(rng: random.Random, local: bool) -> str:
    name = ident(rng)
    ty = ctype(rng)
    if rng.randrange(5) == 0:
        return f"{ty} {name}[{rng.randrange(1, 8)}];"
    if rng.randrange(4) == 0 and local:
        return f"{ty} {name} = {expr(rng, 2)};"
    return f"{ty} {name};"


def stmt(rng: random.Random, depth: int) -> str:
    if depth <= 0:
        kind = rng.randrange(5)
        if kind == 0:
            return f"return {expr(rng, 2)};"
        if kind == 1:
            return f"{expr(rng, 2)};"
        if kind == 2:
            return declaration(rng, True)
        if kind == 3:
            label = ident(rng)
            return f"{label}: {expr(rng, 1)};"
        return ";"

    kind = rng.randrange(9)
    if kind < 4:
        return stmt(rng, 0)
    if kind == 4:
        return f"if ({expr(rng, 2)}) {{ {stmt(rng, depth - 1)} }} else {{ {stmt(rng, depth - 1)} }}"
    if kind == 5:
        return f"while ({expr(rng, 2)}) {{ {stmt(rng, depth - 1)} }}"
    if kind == 6:
        return f"for ({expr(rng, 1)}; {expr(rng, 1)}; {expr(rng, 1)}) {{ {stmt(rng, depth - 1)} }}"
    if kind == 7:
        return "{ " + " ".join(stmt(rng, depth - 1) for _ in range(rng.randrange(1, 4))) + " }"
    return f"goto {ident(rng)};"


def struct_decl(rng: random.Random) -> str:
    fields = []
    for _ in range(rng.randrange(1, 5)):
        fields.append(f"{ctype(rng)} {ident(rng)};")
    return "struct " + ident(rng) + " { " + " ".join(fields) + " };"


def enum_decl(rng: random.Random) -> str:
    vals = []
    for n in range(rng.randrange(1, 5)):
        name = ident(rng).upper()
        if rng.randrange(2) == 0:
            vals.append(f"{name} = {n}")
        else:
            vals.append(name)
    return "enum { " + ", ".join(vals) + " };"


def function(rng: random.Random) -> str:
    name = "main" if rng.randrange(4) == 0 else ident(rng)
    ret = ctype(rng, allow_void=True)
    params = []
    for _ in range(rng.randrange(0, 4)):
        params.append(f"{ctype(rng)} {ident(rng)}")
    body = [declaration(rng, True) for _ in range(rng.randrange(0, 4))]
    body += [stmt(rng, 3) for _ in range(rng.randrange(1, 7))]
    if ret == "void":
        body.append("return;")
    else:
        body.append(f"return {expr(rng, 2)};")
    return f"{ret} {name}(" + ", ".join(params) + ") { " + " ".join(body) + " }"


def translation_unit(rng: random.Random) -> str:
    items = []
    for _ in range(rng.randrange(0, 4)):
        kind = rng.randrange(4)
        if kind == 0:
            items.append(declaration(rng, False))
        elif kind == 1:
            items.append(struct_decl(rng))
        elif kind == 2:
            items.append(enum_decl(rng))
        else:
            items.append(f"{ctype(rng)} {ident(rng)}({ctype(rng)} {ident(rng)});")
    for _ in range(rng.randrange(1, 5)):
        items.append(function(rng))
    return "\n".join(items) + "\n"


def maybe_malformed(rng: random.Random, src: str) -> str:
    roll = rng.randrange(100)
    if roll < 20:
        cut = rng.randrange(len(src) + 1)
        return src[:cut]
    if roll < 35:
        return src + choice(rng, TRUNCATION_SUFFIXES)
    if roll < 45:
        return choice(rng, TRUNCATION_SUFFIXES)
    if roll < 55:
        tokens = ["int", "char", "struct", "return", "if", "while", "(", ")", "{", "}", "[", "]", "->", ";"]
        return " ".join(choice(rng, tokens) for _ in range(rng.randrange(1, 20)))
    return src


def generate(seed: int, index: int) -> Case:
    rng = random.Random((seed << 32) ^ index)
    return Case(maybe_malformed(rng, translation_unit(rng)), seed, index)


def run_case(hcc1: str, case: Case, mode: str, timeout: float, workdir: Path) -> tuple[int, bytes, bytes]:
    src = workdir / f"case-{case.index}.c"
    src.write_text(case.text)
    if mode == "check":
        cmd = [hcc1, "--check", str(src)]
    else:
        cmd = [hcc1, "--m1-ir", "-o", str(workdir / f"case-{case.index}.hccir"), str(src)]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or b"", exc.stderr or b""


def bad_status(status: int) -> bool:
    return status == 124 or status < 0 or status >= 128


def status_name(status: int) -> str:
    if status == 124:
        return "timeout"
    if status < 0:
        try:
            return "signal-" + signal.Signals(-status).name
        except ValueError:
            return f"signal-{-status}"
    if status >= 128:
        sig = status - 128
        try:
            return "signal-" + signal.Signals(sig).name
        except ValueError:
            return f"signal-{sig}"
    return f"exit-{status}"


def save_failure(out_dir: Path, case: Case, status: int, stdout: bytes, stderr: bytes) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    base = out_dir / f"id-{case.index:06d}-{status_name(status)}"
    c_path = base.with_suffix(".c")
    c_path.write_text(case.text)
    base.with_suffix(".stdout").write_bytes(stdout)
    base.with_suffix(".stderr").write_bytes(stderr)
    base.with_suffix(".txt").write_text(f"seed={case.seed}\nindex={case.index}\nstatus={status}\n")
    return c_path


def find_hcc1(path: str | None) -> str:
    if path:
        return path
    found = shutil.which("hcc1")
    if not found:
        raise SystemExit("hcc1 not found; pass --hcc1 or put hcc1 in PATH")
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hcc1", help="hcc1 binary to fuzz")
    parser.add_argument("--mode", choices=["check", "m1-ir"], default="check")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--out-dir", default="fuzz/findings/hcc")
    parser.add_argument("--keep-going", action="store_true", help="continue after the first crash/timeout")
    args = parser.parse_args(argv)

    hcc1 = find_hcc1(args.hcc1)
    out_dir = Path(args.out_dir)
    found = 0
    with tempfile.TemporaryDirectory(prefix="hcc-grammar-fuzz.") as tmp:
        workdir = Path(tmp)
        for index in range(args.iterations):
            case = generate(args.seed, index)
            status, stdout, stderr = run_case(hcc1, case, args.mode, args.timeout, workdir)
            if bad_status(status):
                found += 1
                path = save_failure(out_dir, case, status, stdout, stderr)
                print(f"{status_name(status)} seed={args.seed} index={index} {path}", flush=True)
                if not args.keep_going:
                    return 1
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
