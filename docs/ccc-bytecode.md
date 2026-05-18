# CCC bytecode ABI

CCC bootstrap bytecode files use the `.mzbc` extension. The format is fixed
before `mlc.byte` is checked in so self-hosting can compare byte-for-byte
artifacts without path, timestamp, or host-tool variation.

## Header

All integers are unsigned little-endian 32-bit words.

```text
offset  size  field
0       4     magic: "MZBC"
4       4     version: 1
8       4     code length in bytes
12      4     primitive count
16      4     global count
20      n     bytecode instruction stream
```

The VM rejects files whose length is not exactly `20 + code length`.

## Values

Runtime values use the seed VM's tagged representation:

- low bit `1`: immediate integer, encoded as `(n << 1) | 1`
- low bit `0`: heap block pointer

Heap allocation uses two fixed semispaces. Allocation is bump-pointer within
the active semispace; when it fills, `mzvm` performs a Cheney-style copying
collection from the VM roots (`acc` and stack) into the reserve semispace.

## Instruction Encoding

Opcodes are one byte. Immediate operands are little-endian 32-bit words.

```text
0   HALT
1   CONST s32
2   PUSH
3   POP u32
4   ACC u32
5   ADDINT
6   SUBINT
7   MULINT
8   DIVINT
9   EQ
10  LT
11  BRANCH s32
12  BRANCHIF s32
13  BRANCHIFNOT s32
14  C_CALL argc:u32 prim:u32
15  MAKEBLOCK tag:u32 size:u32
16  GETFIELD u32
17  SETFIELD u32
18  GETTAG
19  NE
20  LE
21  GT
22  GE
23  CALL u32
24  RETURN
25  GETFIELD_DYN
26  SETFIELD_DYN
27  BLOCKSIZE
```

Branches are relative to the program counter after the branch operand has
been read.

`CALL` encodes an absolute bytecode offset. It pushes the return program
counter onto the VM return stack and jumps to direct function code emitted
earlier in the stream. `RETURN` pops that return address. This is the current
seed path for unary `let rec` functions; closure opcodes remain future ABI
work.

`MAKEBLOCK` consumes fields from the stack plus the accumulator in source
order: earlier fields have already been pushed, and the accumulator is the
last field. `GETFIELD 0` therefore returns the first source-level field.
`GETFIELD_DYN` consumes the block from the stack and the integer index from
the accumulator. `SETFIELD_DYN` consumes the value from the accumulator and
the integer index and block from the stack.
`BLOCKSIZE` returns the number of fields in the block currently in the
accumulator.

## Seed Primitive Table

The seed ABI reserves primitive indices in the bytecode header. Version 1
implements the minimal table needed by the first `mlc-seed` fixtures:

```text
0  read_byte  : unit -> int
1  write_byte : int -> unit
2  exit       : int -> never
```

`C_CALL` currently accepts one argument. Multi-argument primitives should be
lowered by passing a tuple block until the compiler grows a stronger calling
convention.
