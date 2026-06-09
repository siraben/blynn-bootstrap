# MZBC — mzvm bytecode format and instruction set (version 1)

This document locks the `.mzbc` container layout and the instruction set
executed by `mzvm` (see plan.md §4). The format is fully reproducible: no
timestamps, no path-dependent strings.

## Container

All multi-byte integers are **little-endian**. The header is six u32 fields:

| offset | field       | meaning                                            |
|-------:|-------------|----------------------------------------------------|
| 0      | magic       | bytes `M` `Z` `B` `C` (0x43425A4D as u32 LE)       |
| 4      | version     | 1                                                  |
| 8      | codelen     | number of 32-bit code words that follow            |
| 12     | primcount   | number of primitives the code assumes (must equal the VM's table length) |
| 16     | globalcount | size of the global table                           |
| 20     | datacount   | number of byte-data records (≤ globalcount)        |

Then `codelen` signed 32-bit code words. Then `datacount` records, each
`u32 bytelen` followed by `bytelen` raw bytes; record *i* is loaded into
global *i* as a fresh `bytes` block before execution. Globals from
`datacount` to `globalcount-1` start as the integer 0.

Execution starts at code word 0 and ends at `STOP`; the accumulator's
integer value at `STOP` is the process exit code (prim `exit` also ends
the program).

## Values

Machine words are pointer-sized. Low bit 1 = immediate integer `n`,
encoded `(n << 1) | 1`. Low bit 0 = pointer to a heap block.

Block layout: one header word `(wosize << 8) | tag`, then `wosize` fields.
Tags 0–249 are ordinary scanned blocks (tuples, records, ADT constructors,
arrays). Tag 250 = closure (`field 0` is the code address stored as a
tagged integer; fields 1.. are the captured environment; closures are
scanned). Tag 251 = bytes (`field 0` is the byte length as a raw word;
remaining words hold the bytes; never scanned). Tag 255 is reserved by the
GC for forwarding.

Unit, `false`, and constant constructors are immediate integers
(`false` = 0, `true` = 1).

## Machine state

- `acc` — accumulator.
- an argument/local stack (`sp`), grows upward; `ACC n` reads `stack[sp-1-n]`.
- a return stack of `(pc, env)` frames.
- `env` — current closure (or 0 outside any closure).
- `globals` — the global table.

## Calling convention

Functions are **uncurried**: a call site pushes the `n` arguments
left-to-right (so the last argument is `ACC 0` on entry) and `APPLY n`
jumps through the closure in `acc`, pushing a return frame. `RETURN n`
pops the `n` words of arguments/locals still owned by the frame, then pops
the return frame. `APPTERM n, s` is the tail call: the top `n` words are
the new arguments; the `s` words below them (the caller's arguments and
locals) are discarded by sliding the arguments down.

Mutual recursion uses closure backpatching instead of `CLOSUREREC`/infix
blocks: the compiler allocates the closures with dummy environment slots
and patches them with `SETFIELD`.

## Instructions

One opcode word, then operand words. `a` = absolute code-word address.
Binary operations take their **left operand from the stack** (popped) and
their right operand in `acc`; the result is left in `acc`. Aggregate
builders (`MAKEBLOCK`, `CLOSURE`, `APPLY`) take all their values from the
stack, pushed left-to-right.

| op | name        | operands  | action |
|---:|-------------|-----------|--------|
| 0  | STOP        |           | halt; exit code = `acc` |
| 1  | CONST       | n         | `acc = int(n)` |
| 2  | ACC         | n         | `acc = stack[sp-1-n]` |
| 3  | PUSH        |           | push `acc` |
| 4  | POP         | n         | `sp -= n` |
| 5  | ASSIGN      | n         | `stack[sp-1-n] = acc`; `acc = 0` |
| 6  | ENVACC      | n         | `acc = env.field[n]` (env starts at field 1) |
| 7  | CLOSURE     | a, n      | pop `n` captured values; `acc` = new closure `{code=a, fields}` |
| 8  | APPLY       | n         | call closure in `acc` with top `n` stack words as args |
| 9  | APPTERM     | n, s      | tail call: slide top `n` words over `s`, jump |
| 10 | RETURN      | n         | `sp -= n`; pop return frame |
| 11 | MAKEBLOCK   | tag, n    | pop `n` values into a new block (n ≥ 1) |
| 12 | GETFIELD    | n         | `acc = acc.field[n]` |
| 13 | SETFIELD    | n         | pop block `b`; `b.field[n] = acc`; `acc = 0` |
| 14 | BRANCH      | a         | `pc = a` |
| 15 | BRANCHIF    | a         | if `acc != int(0)` jump |
| 16 | BRANCHIFNOT | a         | if `acc == int(0)` jump |
| 17 | SWITCH      | ni, nt, a×(ni+nt) | int `v` → table1[v]; block tag `t` → table2[t]; out of range traps |
| 18 | ADDINT      |           | `acc = pop() + acc` |
| 19 | SUBINT      |           | `acc = pop() - acc` |
| 20 | MULINT      |           | `acc = pop() * acc` |
| 21 | DIVINT      |           | `acc = pop() / acc` (trap on 0; C-style truncation) |
| 22 | MODINT      |           | `acc = pop() % acc` (trap on 0) |
| 23 | ANDINT      |           | bitwise |
| 24 | ORINT       |           | bitwise |
| 25 | XORINT      |           | bitwise |
| 26 | LSLINT      |           | `acc = pop() << acc` |
| 27 | LSRINT      |           | logical shift right |
| 28 | ASRINT      |           | arithmetic shift right |
| 29 | NEGINT      |           | `acc = -acc` |
| 30 | BOOLNOT     |           | `acc = (acc == int(0))` |
| 31 | EQ          |           | `acc = pop() == acc` (word equality) |
| 32 | NEQ         |           | |
| 33 | LTINT       |           | signed compare, left = popped |
| 34 | LEINT       |           | |
| 35 | GTINT       |           | |
| 36 | GEINT       |           | |
| 37 | ULTINT      |           | unsigned compare |
| 38 | UGEINT      |           | |
| 39 | OFFSETINT   | n         | `acc += n` |
| 40 | VECTLENGTH  |           | `acc = wosize(acc)` (array length) |
| 41 | GETVECTITEM |           | pop array `v`; `acc = v.field[acc]` (bounds-checked) |
| 42 | SETVECTITEM |           | pop index, pop array; `v.field[i] = acc`; `acc = 0` |
| 43 | GETBYTES    |           | pop bytes `b`; `acc = b[acc]` (bounds-checked) |
| 44 | SETBYTES    |           | pop index, pop bytes; `b[i] = acc & 255`; `acc = 0` |
| 45 | GETGLOBAL   | n         | `acc = globals[n]` |
| 46 | SETGLOBAL   | n         | `globals[n] = acc`; `acc = 0` |
| 47 | CCALL       | n, p      | call primitive `p`: pops `n` args (pushed left-to-right), result in `acc` |

## Primitives (version 1 table, primcount = 12)

Channel handles are small integers into a VM-side table; handles 0, 1, 2
are preopened as stdin, stdout, stderr.

| #  | name         | args            | result |
|---:|--------------|-----------------|--------|
| 0  | exit         | code            | does not return |
| 1  | open_in      | path:bytes      | handle, or −1 |
| 2  | open_out     | path:bytes      | handle, or −1 |
| 3  | close_chan   | handle          | 0 |
| 4  | read_byte    | handle          | byte, or −1 at EOF |
| 5  | write_byte   | handle, byte    | 0 |
| 6  | bytes_create | n               | fresh zeroed bytes |
| 7  | bytes_length | b               | length |
| 8  | arg_count    |                 | number of program args (after the .mzbc path) |
| 9  | arg_get      | i               | program arg i as bytes |
| 10 | array_make   | n, init         | fresh tag-0 block of n fields, all = init; n ≥ 1 (zero-size blocks have no field for the GC forwarding pointer) |
| 11 | bytes_of_string | b            | fresh mutable copy of b |
