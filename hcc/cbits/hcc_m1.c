#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
  OP_TEMP = 1,
  OP_IMM = 2,
  OP_BYTES = 3,
  OP_GLOBAL = 4,
  OP_FUNC = 5
};

enum {
  LOC_NONE = 0,
  LOC_STACK = 1,
  LOC_OBJECT = 2
};

enum {
  IK_PARAM = 1,
  IK_ALLOCA = 2,
  IK_CONST = 3,
  IK_COPY = 5,
  IK_ADDROF = 6,
  IK_LOAD64 = 7,
  IK_LOAD32 = 8,
  IK_LOADS32 = 9,
  IK_LOAD16 = 10,
  IK_LOADS16 = 11,
  IK_LOAD8 = 12,
  IK_LOADS8 = 13,
  IK_STORE64 = 14,
  IK_STORE32 = 15,
  IK_STORE16 = 16,
  IK_STORE8 = 17,
  IK_BIN = 18,
  IK_CALL = 19,
  IK_CALLI = 20,
  IK_COND = 21,
  IK_SEXT = 22,
  IK_ZEXT = 23,
  IK_TRUNC = 24
};

enum {
  BK_ADD = 1,
  BK_SUB = 2,
  BK_MUL = 3,
  BK_DIV = 4,
  BK_MOD = 5,
  BK_SHL = 6,
  BK_SHR = 7,
  BK_SAR = 8,
  BK_EQ = 9,
  BK_NE = 10,
  BK_LT = 11,
  BK_LE = 12,
  BK_GT = 13,
  BK_GE = 14,
  BK_ULT = 15,
  BK_ULE = 16,
  BK_UGT = 17,
  BK_UGE = 18,
  BK_AND = 19,
  BK_OR = 20,
  BK_XOR = 21,
  BK_UDIV = 22,
  BK_UMOD = 23
};

enum {
  TK_RET = 1,
  TK_JUMP = 2,
  TK_BRANCH = 3,
  TK_BRANCH_CMP = 4
};

enum {
  LINE_CAP = 8192
};

typedef struct Operand Operand;
typedef struct Instr Instr;
typedef struct InstrList InstrList;
typedef struct Block Block;
typedef struct Function Function;
typedef struct DataValue DataValue;
typedef struct DataItem DataItem;
typedef struct Loc Loc;
typedef struct LocArray LocArray;
typedef struct EmitState EmitState;

enum {
  TARGET_AMD64 = 1,
  TARGET_I386 = 2,
  TARGET_AARCH64 = 3,
  TARGET_RISCV64 = 4
};

static int target_arch = TARGET_AMD64;
static char riscv64_label_namespace_buf[128];
static const char *riscv64_label_namespace = "out";

#include "hcc_m1_common.c"
#include "hcc_m1_ir.c"
#include "hcc_m1_frame.c"
#include "hcc_m1_emit.c"

int main(int argc, char **argv)
{
  FILE *in;
  FILE *out;
  char *header;
  int argi;
  if (argc == 5 && strcmp(argv[1], "--target") == 0) {
    if (strcmp(argv[2], "amd64") == 0 || strcmp(argv[2], "x86_64") == 0) target_arch = TARGET_AMD64;
    else if (strcmp(argv[2], "i386") == 0 || strcmp(argv[2], "x86") == 0) target_arch = TARGET_I386;
    else if (strcmp(argv[2], "aarch64") == 0 || strcmp(argv[2], "arm64") == 0) target_arch = TARGET_AARCH64;
    else if (strcmp(argv[2], "riscv64") == 0) target_arch = TARGET_RISCV64;
    else die("unknown target");
    argi = 3;
  } else {
    argi = 1;
  }
  if (argc - argi != 2) {
    fputs("usage: hcc-m1 [--target amd64|i386|aarch64|riscv64] INPUT.hccir OUTPUT.M1\n", stderr);
    return 2;
  }
  in = fopen(argv[argi], "r");
  if (!in) die("cannot open input");
  set_label_namespace(argv[argi + 1]);
  out = fopen(argv[argi + 1], "w");
  if (!out) die("cannot open output");
  header = xrealloc(0, LINE_CAP);
  if (!read_line(in, header, LINE_CAP)) die("empty input");
  if (!str_eq(header, "HCCIR 1")) die("bad IR input header");
  translate_ir_module(in, out);
  fclose(in);
  fclose(out);
  return 0;
}
