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

Heap allocation uses two fixed semispaces, defaulting to 33,554,432 value
words each in the seed VM. Allocation is bump-pointer within
the active semispace; when it fills, `mzvm` performs a Cheney-style copying
collection from the VM roots (`acc` and stack) into the reserve semispace.
The seed stack defaults to 33,554,432 value slots so continuation-heavy staged
compiler runs can compile their own source before later tail-call and
environment optimizations reduce stack pressure.

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
28  MAKEBLOCK_DYN tag:u32
29  CLOSURE target:u32
30  APPLY
31  RETURN_FRAME
32  FUNCTION target:u32
33  CLOSURE_N target:u32 captures:u32
34  CLOSURE_SKIP target:u32 captures:u32 skip:u32
```

Branches are relative to the program counter after the branch operand has
been read.

`CALL` encodes an absolute bytecode offset. It pushes the return program
counter onto the VM return stack and jumps to direct function code emitted
earlier in the stream. `RETURN` pops that return address. This is the current
seed path for unary `let rec` functions.

`CLOSURE` creates a closure block whose first field is the absolute bytecode
target and whose remaining fields are the whole current stack, copied from
nearest to farthest lexical depth. `CLOSURE_N` is the bounded form used by the
staged compiler: it captures only the requested number of nearest stack slots.
`CLOSURE_SKIP` is the bounded non-top form: it skips the requested number of
nearest stack slots and then captures the next `captures` slots, preserving
the same nearest-to-farthest order in the closure block.
`APPLY` expects the closure on the stack and the argument in the accumulator;
for closure blocks it pushes captured values followed by the argument, saves
the return program counter and dynamic frame size, and jumps to the closure
target. Generated closure bodies use `RETURN_FRAME` to drop their argument and
captured values before returning.

`FUNCTION` creates a first-class wrapper for direct `let rec` function code.
When `APPLY` sees a function wrapper, it leaves the argument in the accumulator
and jumps using the direct `CALL` / `RETURN` calling convention. This lets
staged compilers pass named functions such as environments and continuations
without forcing every syntactic call through a heap closure.

`MAKEBLOCK` consumes fields from the stack plus the accumulator in source
order: earlier fields have already been pushed, and the accumulator is the
last field. `GETFIELD 0` therefore returns the first source-level field.
`GETFIELD_DYN` consumes the block from the stack and the integer index from
the accumulator. `SETFIELD_DYN` consumes the value from the accumulator and
the integer index and block from the stack.
`BLOCKSIZE` returns the number of fields in the block currently in the
accumulator.
`MAKEBLOCK_DYN` consumes a runtime size from the stack, fills every field with
the accumulator, and leaves the new block in the accumulator.

## Seed Primitive Table

The seed ABI reserves primitive indices in the bytecode header. Version 1
implements the minimal table needed by the first `mlc-seed` fixtures:

```text
0  read_byte  : unit -> int
1  write_byte : int -> unit
2  exit       : int -> never
3  debug_byte : int -> unit, writes one byte to stderr
4  debug_int  : int -> unit, writes a decimal integer to stderr
```

`C_CALL` currently accepts one argument. Multi-argument primitives should be
lowered by passing a tuple block until the compiler grows a stronger calling
convention.
The source-level `debug_printf "label=%d" expr` debugging form is compiler
syntax; it lowers to `debug_byte` calls around one `debug_int` call and does
not add a VM primitive.
