#!/usr/bin/env python3
r"""Dev-only assembler for the parenthesized MZBC assembly format.

This is the same source language that the first ML bootstrap stage
(ccc/stages/01-parenthetical.ml) accepts; this Python copy exists so the VM
can be tested before any ML stage runs, and so the two implementations can
be diffed against each other on the test corpus.

Format (s-expression tokens, ';' comments to end of line):

  (globals N)            total global count (default: number of data records)
  (data "...")           next data global, in order, starting at global 0
  (:label)               define a code label at the current address
  (const 42) (push) ...  instructions, in order
  (branch :label)        label operands written as absolute word addresses
  (closure :f 0)
  (switch ni nt :a :b ...)

String escapes: \n \t \r \\ \" and \xNN.
"""

import sys

OPS = {
    # name: (opcode, operand count); switch is variadic and special-cased
    "stop": (0, 0), "const": (1, 1), "acc": (2, 1), "push": (3, 0),
    "pop": (4, 1), "assign": (5, 1), "envacc": (6, 1), "closure": (7, 2),
    "apply": (8, 1), "appterm": (9, 2), "return": (10, 1),
    "makeblock": (11, 2), "getfield": (12, 1), "setfield": (13, 1),
    "branch": (14, 1), "branchif": (15, 1), "branchifnot": (16, 1),
    "switch": (17, -1),
    "addint": (18, 0), "subint": (19, 0), "mulint": (20, 0),
    "divint": (21, 0), "modint": (22, 0), "andint": (23, 0),
    "orint": (24, 0), "xorint": (25, 0), "lslint": (26, 0),
    "lsrint": (27, 0), "asrint": (28, 0), "negint": (29, 0),
    "boolnot": (30, 0), "eq": (31, 0), "neq": (32, 0), "ltint": (33, 0),
    "leint": (34, 0), "gtint": (35, 0), "geint": (36, 0),
    "ultint": (37, 0), "ugeint": (38, 0), "offsetint": (39, 1),
    "vectlength": (40, 0), "getvectitem": (41, 0), "setvectitem": (42, 0),
    "getbytes": (43, 0), "setbytes": (44, 0), "getglobal": (45, 1),
    "setglobal": (46, 1), "ccall": (47, 2),
}

NPRIMS = 10
PRIMS = {
    "exit": 0, "open_in": 1, "open_out": 2, "close_chan": 3,
    "read_byte": 4, "write_byte": 5, "bytes_create": 6, "bytes_length": 7,
    "arg_count": 8, "arg_get": 9,
}


def tokenize(src):
    toks = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c in "()":
            toks.append(c)
            i += 1
        elif c == '"':
            i += 1
            out = bytearray()
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 1
                    e = src[i]
                    if e == "n":
                        out.append(10)
                    elif e == "t":
                        out.append(9)
                    elif e == "r":
                        out.append(13)
                    elif e == "\\":
                        out.append(92)
                    elif e == '"':
                        out.append(34)
                    elif e == "x":
                        out.append(int(src[i + 1:i + 3], 16))
                        i += 2
                    else:
                        raise SystemExit(f"bad escape \\{e}")
                    i += 1
                else:
                    out.append(ord(src[i]))
                    i += 1
            i += 1
            toks.append(("str", bytes(out)))
        else:
            j = i
            while j < n and src[j] not in " \t\r\n();\"":
                j += 1
            toks.append(src[i:j])
            i = j
    return toks


def parse_forms(toks):
    forms = []
    i = 0
    while i < len(toks):
        if toks[i] != "(":
            raise SystemExit(f"expected ( at token {toks[i]!r}")
        j = i + 1
        form = []
        while toks[j] != ")":
            form.append(toks[j])
            j += 1
        forms.append(form)
        i = j + 1
    return forms


def assemble(src):
    forms = parse_forms(tokenize(src))
    data = []
    globals_decl = None
    labels = {}
    # First pass: compute addresses.
    addr = 0
    for form in forms:
        head = form[0]
        if isinstance(head, tuple):
            raise SystemExit("string cannot head a form")
        if head == "globals":
            globals_decl = int(form[1])
        elif head == "data":
            data.append(form[1][1])
        elif head.startswith(":"):
            labels[head[1:]] = addr
        elif head == "switch":
            addr += 3 + (len(form) - 3)
        else:
            op, nops = OPS[head]
            addr += 1 + nops
    # Second pass: emit.
    code = []

    def operand(tok):
        if isinstance(tok, tuple):
            raise SystemExit("string operand not allowed")
        if tok.startswith(":"):
            return labels[tok[1:]]
        if tok in PRIMS:
            return PRIMS[tok]
        if tok.startswith("'") and tok.endswith("'") and len(tok) == 3:
            return ord(tok[1])
        return int(tok, 0)

    for form in forms:
        head = form[0]
        if head in ("globals", "data") or head.startswith(":"):
            continue
        op, nops = OPS[head]
        code.append(op)
        if head == "switch":
            ni, nt = int(form[1]), int(form[2])
            if len(form) - 3 != ni + nt:
                raise SystemExit("switch table size mismatch")
            code.append(ni)
            code.append(nt)
            for t in form[3:]:
                code.append(operand(t))
        else:
            if len(form) - 1 != nops:
                raise SystemExit(f"{head}: expected {nops} operands")
            for t in form[1:]:
                code.append(operand(t))

    nglobals = globals_decl if globals_decl is not None else len(data)
    if nglobals < len(data):
        raise SystemExit("globals count smaller than data count")
    out = bytearray()
    out += b"MZBC"
    for v in (1, len(code), NPRIMS, nglobals, len(data)):
        out += v.to_bytes(4, "little")
    for w in code:
        out += (w & 0xFFFFFFFF).to_bytes(4, "little")
    for d in data:
        out += len(d).to_bytes(4, "little")
        out += d
    return bytes(out)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: mzbc_asm.py in.mzs out.mzbc")
    with open(sys.argv[1]) as f:
        src = f.read()
    blob = assemble(src)
    with open(sys.argv[2], "wb") as f:
        f.write(blob)


if __name__ == "__main__":
    main()
