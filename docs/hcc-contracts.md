# HCC Contracts

This document records the current public contracts around HCC, its textual IR,
and the support files used by the bootstrap path. It describes the behavior that
callers and support code may rely on; it is not a promise that HCC accepts all of
ISO C.

## Pipeline

The stable development pipeline is:

```sh
hcpp [C compiler flags...] input.c > input.i
hcc1 --target TARGET --m1-ir -o input.hccir input.i
hcc-m1 --target TARGET input.hccir out.M1
```

`hcpp` performs include expansion, comment stripping, line-continuation
splicing, conditional preprocessing, and macro expansion. It accepts `-I`,
`-D`, `-S`, `-c`, `-pipe`, `-nostdinc`, `-nostdlib`, `-static`, `--m1-ir`, and
`--trace` through the common argument parser; only include directories, defines,
and the input path affect preprocessing. Quoted includes must be found; missing
system includes are left as inert source lines. Include guards and `#pragma
once` are recognized to avoid re-expanding guarded headers.

`hcc1` consumes the preprocessed token stream printed by `hcpp`. `--check`
lexes and parses files without lowering. `--m1-ir` emits `HCCIR 1`; `-o`
selects the output path; `--target` selects target word size and target-specific
type layout. Unsupported command-line options fail rather than being ignored.

`hcc-m1` consumes exactly `HCCIR 1` and emits stage0-compatible M1 assembly.
It accepts `--target amd64|x86_64|i386|x86|aarch64|arm64|riscv64`; the default
is amd64. The target passed to `hcc1` and `hcc-m1` must match.

The TinyCC bootstrap flow compiles `tcc.c`, `tcc-bootstrap-support.c`, and
`tcc-final-overrides.c` through this pipeline, then invokes stage0 `M1`/`hex2`
with architecture definitions and HCC support M1 files.

## Supported C Subset

HCC is a bootstrap compiler for the TinyCC edge. The supported subset is the
syntax and semantics implemented by the parser and lowerer, plus the small
preprocessor described above.

Preprocessor support:

- Object-like and function-like macros, including variadic macros.
- Macro argument expansion, `#` stringification, and `##` token pasting.
- `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`, and `#endif`, with `defined`.
- `#include` handled before token preprocessing.
- `#line` and `#pragma` are ignored; active unsupported directives are errors.

Declarations and types:

- `typedef`, prototypes, function definitions, local declarations, globals,
  `extern` declarations, and multiple declarators per declaration.
- `void`, `_Bool`, signed and unsigned `char`, `short`, `int`, `long`,
  `long long`, `float`, `double`, `long double`, pointers, arrays, function
  types, structs, unions, and enums.
- Named integer aliases used by the bootstrap, including `size_t`, `ssize_t`,
  `time_t`, `ptrdiff_t`, `intptr_t`, `uintptr_t`, fixed-width integer names,
  and several ELF integer names.
- Inline and named struct/union definitions, anonymous aggregate members, and
  bit-field syntax. Bit-field widths are parsed but not represented as packed
  bit-fields in layout.
- `const`, `volatile`, `restrict`, `static`, `auto`, `register`, `inline`, and
  `extern` are accepted as qualifiers/storage words where the parser allows
  them. `_Atomic` and `_Thread_local` are explicitly unsupported.

Statements:

- Blocks, expression statements, declarations, `return`, `if`/`else`, `while`,
  `do`/`while`, `for`, `switch`, `case`, `default`, `break`, `continue`,
  `goto`, and labels.
- Local function prototypes and local typedef statements are parsed and then
  ignored by lowering.

Expressions:

- Integer, floating, character, and string literals.
- Variables, direct calls, indirect calls, indexing, member access, pointer
  member access, unary `+ - ! ~ * & ++ --`, postfix `++ --`, `sizeof`, casts,
  conditional `?:`, comma expressions, assignment, and compound assignment.
- Binary `|| && | ^ & == != < <= > >= << >> + - * / %`.
- Pointer addition/subtraction, pointer difference, scalar coercions, aggregate
  assignment/copy, and aggregate/string initializers for globals and locals.
- Constant expressions cover integer literals, characters, `sizeof`, enum and
  known constants, casts, unary arithmetic/logical operations, binary constant
  operations, conditionals, and the null-pointer member-offset idiom used by
  `offsetof`.

Known limitations:

- Floating literals are accepted and can initialize data, but the IR and M1
  execution path is integer/pointer oriented; floating arithmetic is not a
  complete C floating-point implementation.
- Variadic calls are lowered as ordinary positional arguments. HCC supplies only
  narrow builtin/stub behavior for `__builtin_va_*` in support files.
- `_Atomic`, `_Thread_local`, full packed bit-field layout, and arbitrary GCC
  extensions are outside the contract.
- Inline assembly-like calls named `asm`, `oputs`, and `eputs` are treated as
  ignored side-effect calls by the lowerer.

## HCCIR 1 Text Format

HCCIR is line-oriented ASCII text. Tokens are separated by spaces or tabs.
Names are emitted as bare labels and therefore must not contain whitespace.
The first line is exactly:

```text
HCCIR 1
```

Top-level items are data items or functions:

```text
module      ::= "HCCIR 1" item*
item        ::= data | function
data        ::= "D" name data-value* "E"
data-value  ::= "b" int | "z" int | "a" name
function    ::= "F" name block* "E"
block       ::= "L" block-id instr* terminator
```

`b` emits one byte. `z` emits a zero-byte run. `a` emits a target-word-sized
address relocation to a label. Data address widths are 4 bytes on i386 and
8 bytes on other targets.

Operands:

```text
operand      ::= "T" temp-id
               | "I" int
               | "B" count int*
               | "G" name
               | "F" name
maybe-temp   ::= "-" | temp-id
operand-list ::= count operand*
```

`T` is a virtual temporary. `I` is an integer immediate. `B` is an inline
little-endian byte sequence used to materialize scalar constants. `G` is a data
label address. `F` is a function label address.

Instructions:

```text
1  dst index                  ; param
2  dst size                   ; alloca stack object
3  dst int                    ; integer constant
4  dst Bcount bytes...        ; byte constant
5  dst operand                ; copy
6  dst source-temp            ; address of local temp/object
7  dst operand                ; load64
8  dst operand                ; load32 unsigned
9  dst operand                ; load32 signed
10 dst operand                ; load16 unsigned
11 dst operand                ; load16 signed
12 dst operand                ; load8 unsigned
13 dst operand                ; load8 signed
14 address value              ; store64
15 address value              ; store32
16 address value              ; store16
17 address value              ; store8
18 dst binop left right       ; binary operation
19 maybe-dst name argc args   ; direct call
20 maybe-dst callee argc args ; indirect call
21 dst                        ; conditional expression, see below
22 dst size operand           ; sign extend from size bytes
23 dst size operand           ; zero extend from size bytes
24 dst size operand           ; truncate/mask to size bytes
```

Instruction `21` is followed by nested instruction lists and result operands:

```text
21 dst
[
  cond-instr*
]
O cond-operand
[
  true-instr*
]
O true-operand
[
  false-instr*
]
O false-operand
Q
```

Terminators:

```text
R [operand]                  ; return, absent operand means void/zero
J block-id                   ; unconditional jump
B cond yes-block no-block    ; branch on nonzero cond
C binop left right yes no    ; compare branch
```

Binary opcodes:

```text
1 add      2 sub      3 mul      4 signed-div   5 signed-mod
6 shl      7 logical-shr         8 arithmetic-shr
9 eq       10 ne      11 signed-lt 12 signed-le 13 signed-gt 14 signed-ge
15 u-lt    16 u-le    17 u-gt     18 u-ge
19 and     20 or      21 xor
22 u-div   23 u-mod
```

## Target And ABI Assumptions

HCC targets stage0-posix M1 output, not a general object-file ABI by itself.
The generated assembly labels functions as `FUNCTION_<name>` and data with the
source/global label name.

Target word size and type layout:

- amd64, aarch64, and riscv64 are 64-bit targets. i386 is a 32-bit target.
- Pointers, functions, `long`, `unsigned long`, `size_t`, `ssize_t`, `time_t`,
  `ptrdiff_t`, `intptr_t`, `uintptr_t`, and `addr_t` are target-word-sized.
- `char`/`unsigned char` are 1 byte, `short`/`unsigned short` are 2 bytes,
  `int`/`unsigned int`/`enum`/`float` are 4 bytes, `long long`/`double` are
  8 bytes, and `long double` is 16 bytes.
- Alignment is 1, 2, 4, or 8 based on size, capped at 8. Struct layout aligns
  each field and rounds the final size to the maximum field alignment. Union
  size is the maximum member size rounded to the maximum member alignment.

Calling convention implemented by `hcc-m1`:

- amd64 follows a small SysV-like integer convention: first six arguments in
  `rdi`, `rsi`, `rdx`, `rcx`, `r8`, and `r9`; remaining arguments on the stack;
  return value in `rax`.
- i386 passes all arguments on the stack in 4-byte slots; return value in `eax`.
  The i386 M1 backend cannot lower 64-bit loads or stores.
- aarch64 passes the first eight arguments in `x0` through `x7`; remaining
  arguments on the stack; return value in `x0`.
- riscv64 passes the first eight arguments in `a0` through `a7`; remaining
  arguments on the stack; return value in `a0`.
- Arguments and virtual temporaries are lowered as word-sized stack slots except
  explicit `alloca` objects, which reserve enough target slots for their size.

The support `*-start.M1` files provide `_start`, call `FUNCTION_main(argc,
argv)`, and route `exit`/`_exit` to the target syscall. The M1 syscall support
files implement the tiny syscall/runtime surface needed by the bootstrap.

## Support-File Layering

Support files are deliberately layered around generated HCC output:

1. Stage0 architecture definitions from M2libc/mescc-tools.
2. Optional compatibility definitions, currently `amd64-compat.M1`, for names
   used by HCC support code but not guaranteed by the stage0 definition file.
3. Target start file: `amd64-start.M1`, `i386-start.M1`, `aarch64-start.M1`, or
   `riscv64-start.M1`.
4. Target memory support: `*-memory.M1`, providing bootstrap allocation helpers
   such as `malloc`, `calloc`, and `free`.
5. Generated support C lowered by HCC, currently `tcc-bootstrap-support.M1`.
6. Generated TinyCC M1, currently `tcc.M1`.
7. Final generated overrides, currently `tcc-final-overrides.M1`.
8. Target syscall overrides: `*-syscalls.M1`; these are kept late so their
   labels override earlier bootstrap libc stubs.
9. `hex2` links the stage0 ELF header, the combined M1 output, and the final
   `:ELF_end` marker.

`tcc-bootstrap-support.c` supplies the libc/runtime surface touched while HCC is
building the seed TinyCC before a normal libc exists. `tcc-final-overrides.c`
supplies small final-stage overrides for routines whose bootstrap behavior needs
to stay narrow and deterministic. Native assembly support files for aarch64 and
riscv64 (`tcc-*-crt1.s`, `tcc-*-syscalls.s`, runtime/empty C files) are used
after the seed TinyCC exists to build later TinyCC support objects and archives.

`materialize-object-script.c` is not part of the C-to-M1 compilation contract;
it materializes serialized Blynn object payloads during HCC's own bootstrap
object generation.
