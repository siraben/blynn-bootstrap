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
  IK_CONSTB = 4,
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
  IK_COND = 21
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
  BK_XOR = 21
};

enum {
  TK_RET = 1,
  TK_JUMP = 2,
  TK_BRANCH = 3
};

enum {
  TOP_DATA = 1,
  TOP_FUNC = 2
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
typedef struct Module Module;
typedef struct Loc Loc;
typedef struct LocArray LocArray;

struct Operand {
  int kind;
  long value;
  int count;
  int *bytes;
  char *name;
};

struct InstrList {
  Instr *items;
  int len;
  int cap;
};

struct Instr {
  int kind;
  int temp;
  int temp2;
  long value;
  int binop;
  Operand a;
  Operand b;
  Operand callee;
  int result;
  char *name;
  Operand *args;
  int argc;
  InstrList cond_instrs;
  InstrList true_instrs;
  InstrList false_instrs;
  Operand cond_op;
  Operand true_op;
  Operand false_op;
};

struct Block {
  int id;
  InstrList instrs;
  int term_kind;
  Operand term_op;
  int yes;
  int no;
};

struct Function {
  char *name;
  Block *blocks;
  int len;
  int cap;
};

struct DataValue {
  int kind;
  int byte;
  char *label;
};

struct DataItem {
  char *label;
  DataValue *values;
  int len;
  int cap;
};

struct Module {
  DataItem *data_items;
  int data_len;
  int data_cap;
  Function *functions;
  int fn_len;
  int fn_cap;
  int *top_kinds;
  int *top_indices;
  int top_len;
  int top_cap;
};

struct Loc {
  int kind;
  int slot;
  int slots;
};

struct LocArray {
  Loc *items;
  int cap;
};

static void die(const char *msg)
{
  fputs("hcc-m1: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

static void die_token(const char *msg, const char *tok)
{
  fputs("hcc-m1: ", stderr);
  fputs(msg, stderr);
  fputs(": ", stderr);
  if (tok) fputs(tok, stderr);
  else fputs("<none>", stderr);
  fputc('\n', stderr);
  exit(1);
}

#if defined(__M2__)
static long hcc_heap_cur;
static long hcc_heap_end;

static long hcc_sys_brk(long addr)
{
  return (long)brk((void *)addr);
}

static void *xrealloc(void *ptr, unsigned long size)
{
  unsigned long old_size;
  unsigned long copy_size;
  unsigned long total;
  unsigned long aligned;
  long new_end;
  long got;
  char *raw;
  char *out;
  char *old;
  unsigned long i;
  long *slot;
  if (size == 0) size = 1;
  total = size + sizeof(long);
  aligned = ((total + 7) / 8) * 8;
  if (hcc_heap_cur == 0) {
    hcc_heap_cur = hcc_sys_brk(0);
    hcc_heap_end = hcc_heap_cur;
  }
  if (hcc_heap_cur + aligned > hcc_heap_end) {
    new_end = hcc_heap_cur + aligned;
    if (new_end < hcc_heap_end + 1048576) new_end = hcc_heap_end + 1048576;
    got = hcc_sys_brk(new_end);
    if (got < new_end) die("out of memory");
    hcc_heap_end = got;
  }
  raw = (char *)hcc_heap_cur;
  hcc_heap_cur = hcc_heap_cur + aligned;
  slot = (long *)raw;
  *slot = size;
  out = raw + sizeof(long);
  if (ptr) {
    old = (char *)ptr;
    slot = (long *)(old - sizeof(long));
    old_size = (unsigned long)*slot;
    copy_size = size;
    if (old_size < copy_size) copy_size = old_size;
    i = 0;
    while (i < copy_size) {
      out[i] = old[i];
      i = i + 1;
    }
  }
  return out;
}
#else
static void *xrealloc(void *ptr, unsigned long size)
{
  void *out = realloc(ptr, size);
  if (!out) die("out of memory");
  return out;
}
#endif

static char *xstrdup(const char *text)
{
  unsigned long len = strlen(text);
  char *out = xrealloc(0, len + 1);
  memcpy(out, text, len + 1);
  return out;
}

static void copy_bytes(void *dst, void *src, int count)
{
  char *d = dst;
  char *s = src;
  int i = 0;
  while (i < count) {
    d[i] = s[i];
    i = i + 1;
  }
}

static Instr *instr_at(Instr *items, int index)
{
  return (Instr *)((char *)items + sizeof(Instr) * index);
}

static Block *block_at(Block *items, int index)
{
  return (Block *)((char *)items + sizeof(Block) * index);
}

static Function *function_at(Function *items, int index)
{
  return (Function *)((char *)items + sizeof(Function) * index);
}

static DataValue *data_value_at(DataValue *items, int index)
{
  return (DataValue *)((char *)items + sizeof(DataValue) * index);
}

static DataItem *data_item_at(DataItem *items, int index)
{
  return (DataItem *)((char *)items + sizeof(DataItem) * index);
}

static Operand *operand_at(Operand *items, int index)
{
  return (Operand *)((char *)items + sizeof(Operand) * index);
}

static Loc *loc_at(Loc *items, int index)
{
  return (Loc *)((char *)items + sizeof(Loc) * index);
}

static Operand *instr_a_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 40);
#else
  return &in->a;
#endif
}

static Operand *instr_b_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 80);
#else
  return &in->b;
#endif
}

static Operand *instr_callee_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 120);
#else
  return &in->callee;
#endif
}

static InstrList *instr_cond_instrs_ptr(Instr *in)
{
#if defined(__M2__)
  return (InstrList *)((char *)in + 192);
#else
  return &in->cond_instrs;
#endif
}

static InstrList *instr_true_instrs_ptr(Instr *in)
{
#if defined(__M2__)
  return (InstrList *)((char *)in + 216);
#else
  return &in->true_instrs;
#endif
}

static InstrList *instr_false_instrs_ptr(Instr *in)
{
#if defined(__M2__)
  return (InstrList *)((char *)in + 240);
#else
  return &in->false_instrs;
#endif
}

static Operand *instr_cond_op_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 264);
#else
  return &in->cond_op;
#endif
}

static Operand *instr_true_op_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 304);
#else
  return &in->true_op;
#endif
}

static Operand *instr_false_op_ptr(Instr *in)
{
#if defined(__M2__)
  return (Operand *)((char *)in + 344);
#else
  return &in->false_op;
#endif
}

static InstrList *block_instrs_ptr(Block *block)
{
#if defined(__M2__)
  return (InstrList *)((char *)block + 8);
#else
  return &block->instrs;
#endif
}

static Operand *block_term_op_ptr(Block *block)
{
#if defined(__M2__)
  return (Operand *)((char *)block + 40);
#else
  return &block->term_op;
#endif
}

static int read_line(FILE *file, char *buf, int cap)
{
  int len = 0;
  int c;
  while (1) {
    c = fgetc(file);
    if (c < 0) {
      if (len == 0) return 0;
      break;
    }
    if (c == '\n') break;
    if (c != '\r') {
      if (len + 1 >= cap) die("input line too long");
      buf[len] = c;
      len = len + 1;
    }
  }
  buf[len] = 0;
  return 1;
}

static char *next_token(char **cursor)
{
  char *p = *cursor;
  char *start;
  while (*p == ' ' || *p == '\t') p = p + 1;
  if (*p == 0) {
    *cursor = p;
    return 0;
  }
  start = p;
  while (*p != 0 && *p != ' ' && *p != '\t') p = p + 1;
  if (*p != 0) {
    *p = 0;
    p = p + 1;
  }
  *cursor = p;
  return start;
}

static char *need_token(char **cursor)
{
  char *tok = next_token(cursor);
  if (!tok) die("truncated input line");
  return tok;
}

static long parse_long_text(char *text)
{
  long sign = 1;
  long value = 0;
  if (*text == '-') {
    sign = -1;
    text = text + 1;
  }
  while (*text >= '0' && *text <= '9') {
    value = value * 10 + (*text - '0');
    text = text + 1;
  }
  if (*text != 0) die_token("bad integer token", text);
  return sign * value;
}

static int parse_int_token(char **cursor)
{
  return (int)parse_long_text(need_token(cursor));
}

static long parse_long_token(char **cursor)
{
  return parse_long_text(need_token(cursor));
}

static int str_eq(const char *a, const char *b)
{
  return strcmp(a, b) == 0;
}

static int str_prefix_n(const char *a, const char *b, int count)
{
  return strncmp(a, b, count) == 0;
}

static void parse_operand(char **cursor, Operand *op)
{
  char *kind = need_token(cursor);
  int i;
  op->kind = 0;
  op->value = 0;
  op->count = 0;
  op->bytes = 0;
  op->name = 0;
  if (str_eq(kind, "T")) {
    op->kind = OP_TEMP;
    op->value = parse_int_token(cursor);
  } else if (str_eq(kind, "I")) {
    op->kind = OP_IMM;
    op->value = parse_long_token(cursor);
  } else if (str_eq(kind, "B")) {
    op->kind = OP_BYTES;
    op->count = parse_int_token(cursor);
    if (op->count > 0) op->bytes = xrealloc(0, sizeof(int) * op->count);
    i = 0;
    while (i < op->count) {
      op->bytes[i] = parse_int_token(cursor);
      i = i + 1;
    }
  } else if (str_eq(kind, "G")) {
    op->kind = OP_GLOBAL;
    op->name = xstrdup(need_token(cursor));
  } else if (str_eq(kind, "F")) {
    op->kind = OP_FUNC;
    op->name = xstrdup(need_token(cursor));
  } else {
    die_token("unknown operand kind", kind);
  }
}

static int parse_binop(char *tok)
{
  if (str_eq(tok, "ADD")) return BK_ADD;
  if (str_eq(tok, "SUB")) return BK_SUB;
  if (str_eq(tok, "MUL")) return BK_MUL;
  if (str_eq(tok, "DIV")) return BK_DIV;
  if (str_eq(tok, "MOD")) return BK_MOD;
  if (str_eq(tok, "SHL")) return BK_SHL;
  if (str_eq(tok, "SHR")) return BK_SHR;
  if (str_eq(tok, "SAR")) return BK_SAR;
  if (str_eq(tok, "EQ")) return BK_EQ;
  if (str_eq(tok, "NE")) return BK_NE;
  if (str_eq(tok, "LT")) return BK_LT;
  if (str_eq(tok, "LE")) return BK_LE;
  if (str_eq(tok, "GT")) return BK_GT;
  if (str_eq(tok, "GE")) return BK_GE;
  if (str_eq(tok, "ULT")) return BK_ULT;
  if (str_eq(tok, "ULE")) return BK_ULE;
  if (str_eq(tok, "UGT")) return BK_UGT;
  if (str_eq(tok, "UGE")) return BK_UGE;
  if (str_eq(tok, "AND")) return BK_AND;
  if (str_eq(tok, "OR")) return BK_OR;
  if (str_eq(tok, "XOR")) return BK_XOR;
  die("unknown binop");
  return 0;
}

static void append_instr(InstrList *list, Instr *instr)
{
  if (list->len >= list->cap) {
    if (list->cap) list->cap = list->cap * 2;
    else list->cap = 16;
    list->items = xrealloc(list->items, sizeof(Instr) * list->cap);
  }
  copy_bytes(instr_at(list->items, list->len), instr, sizeof(Instr));
  list->len = list->len + 1;
}

static void append_block(Function *fn, Block *block)
{
  if (fn->len >= fn->cap) {
    if (fn->cap) fn->cap = fn->cap * 2;
    else fn->cap = 16;
    fn->blocks = xrealloc(fn->blocks, sizeof(Block) * fn->cap);
  }
  copy_bytes(block_at(fn->blocks, fn->len), block, sizeof(Block));
  fn->len = fn->len + 1;
}

static void append_function(Module *module, Function *fn)
{
  if (module->fn_len >= module->fn_cap) {
    if (module->fn_cap) module->fn_cap = module->fn_cap * 2;
    else module->fn_cap = 16;
    module->functions = xrealloc(module->functions, sizeof(Function) * module->fn_cap);
  }
  copy_bytes(function_at(module->functions, module->fn_len), fn, sizeof(Function));
  module->fn_len = module->fn_len + 1;
}

static void append_top(Module *module, int kind, int index)
{
  if (module->top_len >= module->top_cap) {
    if (module->top_cap) module->top_cap = module->top_cap * 2;
    else module->top_cap = 32;
    module->top_kinds = xrealloc(module->top_kinds, sizeof(int) * module->top_cap);
    module->top_indices = xrealloc(module->top_indices, sizeof(int) * module->top_cap);
  }
  module->top_kinds[module->top_len] = kind;
  module->top_indices[module->top_len] = index;
  module->top_len = module->top_len + 1;
}

static void append_data_value(DataItem *item, DataValue *value)
{
  if (item->len >= item->cap) {
    if (item->cap) item->cap = item->cap * 2;
    else item->cap = 32;
    item->values = xrealloc(item->values, sizeof(DataValue) * item->cap);
  }
  copy_bytes(data_value_at(item->values, item->len), value, sizeof(DataValue));
  item->len = item->len + 1;
}

static void append_data_item(Module *module, DataItem *item)
{
  if (module->data_len >= module->data_cap) {
    if (module->data_cap) module->data_cap = module->data_cap * 2;
    else module->data_cap = 16;
    module->data_items = xrealloc(module->data_items, sizeof(DataItem) * module->data_cap);
  }
  copy_bytes(data_item_at(module->data_items, module->data_len), item, sizeof(DataItem));
  module->data_len = module->data_len + 1;
}

static void parse_instrs_until_end(FILE *file, InstrList *list);

static void expect_line(FILE *file, const char *expected)
{
  char *line;
  line = xrealloc(0, LINE_CAP);
  if (!read_line(file, line, LINE_CAP)) die("unexpected eof");
  if (strcmp(line, expected)) die("unexpected section marker");
}

static void parse_prefixed_operand(char *line, const char *prefix, Operand *op)
{
  char *cursor = line;
  char *tok = need_token(&cursor);
  if (strcmp(tok, prefix)) die("unexpected operand prefix");
  parse_operand(&cursor, op);
}

static void parse_instr_line(FILE *file, char *line, Instr *instr)
{
  char *cursor = line;
  char *tok;
  char *section;
  int i;
  memset(instr, 0, sizeof(Instr));
  instr->result = -1;
  tok = need_token(&cursor);
  if (strcmp(tok, "I")) die("expected instruction");
  tok = need_token(&cursor);
  if (str_eq(tok, "PARAM")) {
    instr->kind = IK_PARAM;
    instr->temp = parse_int_token(&cursor);
    instr->value = parse_int_token(&cursor);
  } else if (str_eq(tok, "ALLOCA")) {
    instr->kind = IK_ALLOCA;
    instr->temp = parse_int_token(&cursor);
    instr->value = parse_int_token(&cursor);
  } else if (str_eq(tok, "CONST")) {
    instr->kind = IK_CONST;
    instr->temp = parse_int_token(&cursor);
    instr->value = parse_long_token(&cursor);
  } else if (str_eq(tok, "CONSTB")) {
    instr->kind = IK_CONSTB;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
    if (instr->a.kind != OP_BYTES) die("CONSTB needs bytes");
  } else if (str_eq(tok, "COPY")) {
    instr->kind = IK_COPY;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "ADDROF")) {
    instr->kind = IK_ADDROF;
    instr->temp = parse_int_token(&cursor);
    instr->temp2 = parse_int_token(&cursor);
  } else if (str_eq(tok, "LOAD64")) {
    instr->kind = IK_LOAD64;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOAD32")) {
    instr->kind = IK_LOAD32;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOADS32")) {
    instr->kind = IK_LOADS32;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOAD16")) {
    instr->kind = IK_LOAD16;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOADS16")) {
    instr->kind = IK_LOADS16;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOAD8")) {
    instr->kind = IK_LOAD8;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "LOADS8")) {
    instr->kind = IK_LOADS8;
    instr->temp = parse_int_token(&cursor);
    parse_operand(&cursor, instr_a_ptr(instr));
  } else if (str_eq(tok, "STORE64")) {
    instr->kind = IK_STORE64;
    parse_operand(&cursor, instr_a_ptr(instr));
    parse_operand(&cursor, instr_b_ptr(instr));
  } else if (str_eq(tok, "STORE32")) {
    instr->kind = IK_STORE32;
    parse_operand(&cursor, instr_a_ptr(instr));
    parse_operand(&cursor, instr_b_ptr(instr));
  } else if (str_eq(tok, "STORE16")) {
    instr->kind = IK_STORE16;
    parse_operand(&cursor, instr_a_ptr(instr));
    parse_operand(&cursor, instr_b_ptr(instr));
  } else if (str_eq(tok, "STORE8")) {
    instr->kind = IK_STORE8;
    parse_operand(&cursor, instr_a_ptr(instr));
    parse_operand(&cursor, instr_b_ptr(instr));
  } else if (str_eq(tok, "BIN")) {
    instr->kind = IK_BIN;
    instr->temp = parse_int_token(&cursor);
    instr->binop = parse_binop(need_token(&cursor));
    parse_operand(&cursor, instr_a_ptr(instr));
    parse_operand(&cursor, instr_b_ptr(instr));
  } else if (str_eq(tok, "CALL")) {
    instr->kind = IK_CALL;
    tok = need_token(&cursor);
    if (strcmp(tok, "-")) instr->result = (int)parse_long_text(tok);
    instr->name = xstrdup(need_token(&cursor));
    instr->argc = parse_int_token(&cursor);
    if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
    i = 0;
    while (i < instr->argc) {
      parse_operand(&cursor, operand_at(instr->args, i));
      i = i + 1;
    }
  } else if (str_eq(tok, "CALLI")) {
    instr->kind = IK_CALLI;
    tok = need_token(&cursor);
    if (strcmp(tok, "-")) instr->result = (int)parse_long_text(tok);
    parse_operand(&cursor, instr_callee_ptr(instr));
    instr->argc = parse_int_token(&cursor);
    if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
    i = 0;
    while (i < instr->argc) {
      parse_operand(&cursor, operand_at(instr->args, i));
      i = i + 1;
    }
  } else if (str_eq(tok, "COND")) {
    section = xrealloc(0, LINE_CAP);
    instr->kind = IK_COND;
    instr->temp = parse_int_token(&cursor);
    expect_line(file, "BEGIN");
    parse_instrs_until_end(file, instr_cond_instrs_ptr(instr));
    if (!read_line(file, section, LINE_CAP)) die("missing CONDOP");
    parse_prefixed_operand(section, "CONDOP", instr_cond_op_ptr(instr));
    expect_line(file, "BEGIN");
    parse_instrs_until_end(file, instr_true_instrs_ptr(instr));
    if (!read_line(file, section, LINE_CAP)) die("missing TRUEOP");
    parse_prefixed_operand(section, "TRUEOP", instr_true_op_ptr(instr));
    expect_line(file, "BEGIN");
    parse_instrs_until_end(file, instr_false_instrs_ptr(instr));
    if (!read_line(file, section, LINE_CAP)) die("missing FALSEOP");
    parse_prefixed_operand(section, "FALSEOP", instr_false_op_ptr(instr));
    expect_line(file, "ENDCOND");
  } else {
    die("unknown instruction");
  }
}

static void parse_instrs_until_end(FILE *file, InstrList *list)
{
  Instr instr;
  char *line;
  memset(list, 0, sizeof(InstrList));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "END")) {
      return;
    }
    parse_instr_line(file, line, &instr);
    append_instr(list, &instr);
  }
  die("unexpected eof in nested instructions");
}

static void parse_term(Block *block, char *line)
{
  char *cursor = line;
  char *tok;
  tok = need_token(&cursor);
  if (strcmp(tok, "TERM")) die("expected terminator");
  tok = need_token(&cursor);
  if (str_eq(tok, "RET")) {
    block->term_kind = TK_RET;
    tok = need_token(&cursor);
    if (str_eq(tok, "Y")) parse_operand(&cursor, block_term_op_ptr(block));
    else block->term_op.kind = 0;
  } else if (str_eq(tok, "JUMP")) {
    block->term_kind = TK_JUMP;
    block->yes = parse_int_token(&cursor);
  } else if (str_eq(tok, "BRANCH")) {
    block->term_kind = TK_BRANCH;
    parse_operand(&cursor, block_term_op_ptr(block));
    block->yes = parse_int_token(&cursor);
    block->no = parse_int_token(&cursor);
  } else {
    die("unknown terminator");
  }
}

static void parse_block(FILE *file, char *first_line, Block *block)
{
  char *cursor = first_line;
  char *tok;
  Instr instr;
  char *line;
  memset(block, 0, sizeof(Block));
  tok = need_token(&cursor);
  if (strcmp(tok, "BLOCK")) die("expected block");
  block->id = parse_int_token(&cursor);
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_prefix_n(line, "TERM ", 5)) {
      parse_term(block, line);
      return;
    }
    parse_instr_line(file, line, &instr);
    append_instr(block_instrs_ptr(block), &instr);
  }
  die("unexpected eof in block");
}

static void parse_function(FILE *file, char *first_line, Function *fn)
{
  char *cursor = first_line;
  char *tok;
  Block block;
  char *line;
  memset(fn, 0, sizeof(Function));
  tok = need_token(&cursor);
  if (strcmp(tok, "FUNC")) die("expected function");
  fn->name = xstrdup(need_token(&cursor));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "ENDFUNC")) {
      return;
    }
    parse_block(file, line, &block);
    append_block(fn, &block);
  }
  die("unexpected eof in function");
}

static void parse_data_item(FILE *file, char *first_line, DataItem *item)
{
  char *cursor = first_line;
  char *tok;
  char *line;
  memset(item, 0, sizeof(DataItem));
  tok = need_token(&cursor);
  if (strcmp(tok, "DATA")) die_token("expected data item", tok);
  item->label = xstrdup(need_token(&cursor));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    DataValue value;
    if (str_eq(line, "ENDDATA")) {
      return;
    }
    cursor = line;
    tok = need_token(&cursor);
    if (strcmp(tok, "DV")) die("expected data value");
    tok = need_token(&cursor);
    memset(&value, 0, sizeof(value));
    if (str_eq(tok, "B")) {
      value.kind = 1;
      value.byte = parse_int_token(&cursor);
    } else if (str_eq(tok, "A")) {
      value.kind = 2;
      value.label = xstrdup(need_token(&cursor));
    } else {
      die("unknown data value");
    }
    append_data_value(item, &value);
  }
  die("unexpected eof in data");
}

static void parse_module(FILE *file, Module *module)
{
  DataItem item;
  Function fn;
  char *line;
  memset(module, 0, sizeof(Module));
  line = xrealloc(0, LINE_CAP);
  if (!read_line(file, line, LINE_CAP)) die("empty input");
  if (strcmp(line, "HCCM1IR 1")) die("bad input header");
  while (read_line(file, line, LINE_CAP)) {
    if (str_prefix_n(line, "DATA ", 5)) {
      parse_data_item(file, line, &item);
      append_data_item(module, &item);
      append_top(module, TOP_DATA, module->data_len - 1);
    } else if (str_prefix_n(line, "FUNC ", 5)) {
      parse_function(file, line, &fn);
      append_function(module, &fn);
      append_top(module, TOP_FUNC, module->fn_len - 1);
    }
    else if (line[0] != 0) die("unexpected top-level line");
  }
}

static void ensure_loc(LocArray *locs, int temp)
{
  int old;
  if (temp < locs->cap) return;
  old = locs->cap;
  if (!locs->cap) locs->cap = 64;
  while (temp >= locs->cap) locs->cap = locs->cap * 2;
  locs->items = xrealloc(locs->items, sizeof(Loc) * locs->cap);
  while (old < locs->cap) {
    Loc *loc = loc_at(locs->items, old);
    loc->kind = LOC_NONE;
    loc->slot = 0;
    loc->slots = 0;
    old = old + 1;
  }
}

static void alloc_def(LocArray *locs, int *next_slot, int temp)
{
  Loc *loc;
  ensure_loc(locs, temp);
  loc = loc_at(locs->items, temp);
  if (loc->kind != LOC_NONE) return;
  loc->kind = LOC_STACK;
  loc->slot = *next_slot;
  loc->slots = 1;
  *next_slot = *next_slot + 1;
}

static void alloc_object(LocArray *locs, int *next_slot, int temp, int size)
{
  int slots;
  Loc *loc;
  ensure_loc(locs, temp);
  loc = loc_at(locs->items, temp);
  if (loc->kind != LOC_NONE) return;
  if (size < 1) size = 1;
  slots = (size + 7) / 8;
  loc->kind = LOC_OBJECT;
  loc->slot = *next_slot;
  loc->slots = slots;
  *next_slot = *next_slot + slots;
}

static void allocate_instrs(InstrList *list, LocArray *locs, int *next_slot)
{
  int i = 0;
  while (i < list->len) {
    Instr *in = instr_at(list->items, i);
    switch (in->kind) {
      case IK_ALLOCA: alloc_object(locs, next_slot, in->temp, in->value); break;
      case IK_PARAM:
      case IK_CONST:
      case IK_CONSTB:
      case IK_COPY:
      case IK_ADDROF:
      case IK_LOAD64:
      case IK_LOAD32:
      case IK_LOADS32:
      case IK_LOAD16:
      case IK_LOADS16:
      case IK_LOAD8:
      case IK_LOADS8:
      case IK_BIN:
        alloc_def(locs, next_slot, in->temp);
        break;
      case IK_CALL:
      case IK_CALLI:
        if (in->result >= 0) alloc_def(locs, next_slot, in->result);
        break;
      case IK_COND:
        allocate_instrs(instr_cond_instrs_ptr(in), locs, next_slot);
        allocate_instrs(instr_true_instrs_ptr(in), locs, next_slot);
        allocate_instrs(instr_false_instrs_ptr(in), locs, next_slot);
        alloc_def(locs, next_slot, in->temp);
        break;
    }
    i = i + 1;
  }
}

static int allocate_function(Function *fn, LocArray *locs)
{
  int next_slot = 0;
  int i = 0;
  locs->items = 0;
  locs->cap = 0;
  while (i < fn->len) {
    Block *block = block_at(fn->blocks, i);
    allocate_instrs(block_instrs_ptr(block), locs, &next_slot);
    i = i + 1;
  }
  return next_slot;
}

static Loc *lookup_loc(LocArray *locs, int temp)
{
  Loc *loc;
  if (temp < 0 || temp >= locs->cap) die("missing allocation");
  loc = loc_at(locs->items, temp);
  if (loc->kind == LOC_NONE) die("missing allocation");
  return loc;
}

static void emit_header(FILE *out)
{
  fprintf(out, "## hcc M1 output\n");
  fprintf(out, "## target: stage0-posix amd64 M1\n");
  fprintf(out, "\n");
  fprintf(out, "DEFINE HCC_ADD_IMMEDIATE_to_rsp 4881C4\n");
  fprintf(out, "DEFINE HCC_SUB_IMMEDIATE_from_rsp 4881EC\n");
  fprintf(out, "DEFINE HCC_STORE_RSP_IMMEDIATE_from_rax 48898424\n");
  fprintf(out, "DEFINE HCC_LOAD_EFFECTIVE_ADDRESS_rax 488D8424\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rsi 4889C6\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rdx 4889C2\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rcx 4889C1\n");
  fprintf(out, "DEFINE HCC_M_RAX_RBX 4889C3\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_r8 4989C0\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_r9 4989C1\n");
  fprintf(out, "DEFINE HCC_M_RDI_RAX 4889F8\n");
  fprintf(out, "DEFINE HCC_COPY_rsi_to_rax 4889F0\n");
  fprintf(out, "DEFINE HCC_COPY_rdx_to_rax 4889D0\n");
  fprintf(out, "DEFINE HCC_COPY_rcx_to_rax 4889C8\n");
  fprintf(out, "DEFINE HCC_COPY_r8_to_rax 4C89C0\n");
  fprintf(out, "DEFINE HCC_COPY_r9_to_rax 4C89C8\n");
  fprintf(out, "DEFINE HCC_PUSH_RSI 56\n");
  fprintf(out, "DEFINE HCC_PUSH_RDX 52\n");
  fprintf(out, "DEFINE HCC_LOAD_IMMEDIATE64_rax 48B8\n");
  fprintf(out, "DEFINE HCC_LI64_80000000 48B80000008000000000\n");
  fprintf(out, "DEFINE HCC_LI64_FFFFFFFF 48B8FFFFFFFF00000000\n");
  fprintf(out, "DEFINE HCC_SHL_rax_cl 48D3E0\n");
  fprintf(out, "DEFINE HCC_SHR_rax_cl 48D3E8\n");
  fprintf(out, "DEFINE HCC_SAR_rax_cl 48D3F8\n");
  fprintf(out, "DEFINE HCC_LOAD_INTEGER 488B00\n");
  fprintf(out, "DEFINE HCC_STORE_INTEGER 488903\n");
  fprintf(out, "DEFINE HCC_LOAD_WORD 8B00\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_WORD 486300\n");
  fprintf(out, "DEFINE HCC_LOAD_HALF 0FB700\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_HALF 480FBF00\n");
  fprintf(out, "DEFINE HCC_STORE_WORD 8903\n");
  fprintf(out, "DEFINE HCC_STORE_HALF 668903\n");
  fprintf(out, "DEFINE HCC_STORE_CHAR 8803\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_CHAR 480FBE00\n");
  fprintf(out, "DEFINE HCC_XOR_rbx_rax_into_rax 4831D8\n");
  fprintf(out, "DEFINE HCC_CALL_rax FFD0\n");
  fprintf(out, "\n");
}

static int hex_digit(int value)
{
  if (value == 0) return '0';
  if (value == 1) return '1';
  if (value == 2) return '2';
  if (value == 3) return '3';
  if (value == 4) return '4';
  if (value == 5) return '5';
  if (value == 6) return '6';
  if (value == 7) return '7';
  if (value == 8) return '8';
  if (value == 9) return '9';
  if (value == 10) return 'A';
  if (value == 11) return 'B';
  if (value == 12) return 'C';
  if (value == 13) return 'D';
  if (value == 14) return 'E';
  return 'F';
}

static void emit_byte(FILE *out, int byte)
{
  int b = byte % 256;
  if (b < 0) b = b + 256;
  fputc('\'', out);
  fputc(hex_digit(b / 16), out);
  fputc(hex_digit(b % 16), out);
  fputc('\'', out);
}

static void emit_data_item(FILE *out, DataItem *item)
{
  int j = 0;
  fprintf(out, ":%s\n", item->label);
  while (j < item->len) {
    int count = 0;
    fprintf(out, "  ");
    while (j < item->len && count < 16) {
      DataValue *v = data_value_at(item->values, j);
      if (count) fputc(' ', out);
      if (v->kind == 1) {
        emit_byte(out, v->byte);
      } else {
        fprintf(out, "&%s '00' '00' '00' '00'", v->label);
      }
      count = count + 1;
      j = j + 1;
    }
    fputc('\n', out);
  }
  fputc('\n', out);
}

static void emit_load_immediate(FILE *out, long value)
{
  if (value == 2147483648L) {
    fprintf(out, "  HCC_LI64_80000000\n");
  } else if (value == 4294967295L) {
    fprintf(out, "  HCC_LI64_FFFFFFFF\n");
  } else if (value >= -2147483648L && value <= 2147483647L) {
    fprintf(out, "  LOAD_IMMEDIATE_rax %%%ld\n", value);
  } else {
    unsigned long u = (unsigned long)value;
    int i = 0;
    fprintf(out, "  HCC_LOAD_IMMEDIATE64_rax ");
    while (i < 8) {
      if (i) fputc(' ', out);
      emit_byte(out, (int)(u & 255));
      u = u >> 8;
      i = i + 1;
    }
    fputc('\n', out);
  }
}

static void emit_load_immediate_bytes(FILE *out, Operand *op)
{
  int bytes[8];
  int i = 0;
  while (i < 8) {
    if (i < op->count) bytes[i] = op->bytes[i];
    else bytes[i] = 0;
    i = i + 1;
  }
  if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 128 &&
      bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 0 && bytes[7] == 0) {
    fprintf(out, "  HCC_LI64_80000000\n");
  } else if (bytes[0] == 255 && bytes[1] == 255 && bytes[2] == 255 && bytes[3] == 255 &&
             bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 0 && bytes[7] == 0) {
    fprintf(out, "  HCC_LI64_FFFFFFFF\n");
  } else {
    fprintf(out, "  HCC_LOAD_IMMEDIATE64_rax ");
    i = 0;
    while (i < 8) {
      if (i) fputc(' ', out);
      emit_byte(out, bytes[i]);
      i = i + 1;
    }
    fputc('\n', out);
  }
}

static void emit_load_location(FILE *out, Loc *loc, int rsp_bias)
{
  if (loc->kind == LOC_STACK) {
    fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%d\n", 8 * loc->slot + rsp_bias);
  } else if (loc->kind == LOC_OBJECT) {
    fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot + rsp_bias);
  }
}

static void emit_load_operand(FILE *out, LocArray *locs, int rsp_bias, Operand *op)
{
  Loc *loc;
  if (op->kind == OP_IMM) emit_load_immediate(out, op->value);
  else if (op->kind == OP_BYTES) emit_load_immediate_bytes(out, op);
  else if (op->kind == OP_GLOBAL) fprintf(out, "  LOAD_IMMEDIATE_rax &%s\n", op->name);
  else if (op->kind == OP_FUNC) fprintf(out, "  LOAD_IMMEDIATE_rax &FUNCTION_%s\n", op->name);
  else if (op->kind == OP_TEMP) {
    loc = lookup_loc(locs, op->value);
    emit_load_location(out, loc, rsp_bias);
  }
}

static void emit_store_temp(FILE *out, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  if (loc->kind == LOC_STACK) {
    fprintf(out, "  HCC_STORE_RSP_IMMEDIATE_from_rax %%%d\n", 8 * loc->slot);
  } else if (loc->kind == LOC_OBJECT) {
    die("cannot assign stack object");
  }
}

static void emit_address_of(FILE *out, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  if (loc->kind == LOC_STACK || loc->kind == LOC_OBJECT) {
    fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot);
  } else {
    die("cannot take address");
  }
}

static void emit_binop(FILE *out, int op)
{
  switch (op) {
    case BK_ADD: fprintf(out, "  ADD_rbx_to_rax\n"); break;
    case BK_SUB: fprintf(out, "  SUBTRACT_rax_from_rbx_into_rbx\n  MOVE_rbx_to_rax\n"); break;
    case BK_MUL: fprintf(out, "  MULTIPLY_rax_by_rbx_into_rax\n"); break;
    case BK_DIV: fprintf(out, "  XCHG_rax_rbx\n  CQTO\n  DIVIDES_rax_by_rbx_into_rax\n"); break;
    case BK_MOD: fprintf(out, "  XCHG_rax_rbx\n  CQTO\n  MODULUSS_rax_from_rbx_into_rbx\n  MOVE_rdx_to_rax\n"); break;
    case BK_SHL: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SHL_rax_cl\n"); break;
    case BK_SHR: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SHR_rax_cl\n"); break;
    case BK_SAR: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SAR_rax_cl\n"); break;
    case BK_EQ: fprintf(out, "  CMP\n  SETE\n  MOVEZX\n"); break;
    case BK_NE: fprintf(out, "  CMP\n  SETNE\n  MOVEZX\n"); break;
    case BK_LT: fprintf(out, "  CMP\n  SETL\n  MOVEZX\n"); break;
    case BK_LE: fprintf(out, "  CMP\n  SETLE\n  MOVEZX\n"); break;
    case BK_GT: fprintf(out, "  CMP\n  SETG\n  MOVEZX\n"); break;
    case BK_GE: fprintf(out, "  CMP\n  SETGE\n  MOVEZX\n"); break;
    case BK_ULT: fprintf(out, "  CMP\n  SETB\n  MOVEZX\n"); break;
    case BK_ULE: fprintf(out, "  CMP\n  SETBE\n  MOVEZX\n"); break;
    case BK_UGT: fprintf(out, "  CMP\n  SETA\n  MOVEZX\n"); break;
    case BK_UGE: fprintf(out, "  CMP\n  SETAE\n  MOVEZX\n"); break;
    case BK_AND: fprintf(out, "  AND_rax_rbx\n"); break;
    case BK_OR: fprintf(out, "  OR_rax_rbx\n"); break;
    case BK_XOR: fprintf(out, "  HCC_XOR_rbx_rax_into_rax\n"); break;
  }
}

static int call_stack_bytes(int argc)
{
  int stack_args = argc - 6;
  if (stack_args <= 0) return 0;
  return stack_args * 8;
}

static void emit_call_cleanup(FILE *out, int argc)
{
  int bytes = call_stack_bytes(argc);
  if (bytes > 0) fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", bytes);
}

static void emit_argument_move(FILE *out, int index)
{
  if (index == 0) fprintf(out, "  COPY_rax_to_rdi\n");
  else if (index == 1) fprintf(out, "  HCC_COPY_rax_to_rsi\n");
  else if (index == 2) fprintf(out, "  HCC_COPY_rax_to_rdx\n");
  else if (index == 3) fprintf(out, "  HCC_COPY_rax_to_rcx\n");
  else if (index == 4) fprintf(out, "  HCC_COPY_rax_to_r8\n");
  else if (index == 5) fprintf(out, "  HCC_COPY_rax_to_r9\n");
  else die("bad argument register");
}

static void emit_arguments(FILE *out, LocArray *locs, Operand *args, int argc)
{
  int i = argc - 1;
  int pushed = 0;
  while (i >= 6) {
    emit_load_operand(out, locs, pushed * 8, operand_at(args, i));
    fprintf(out, "  PUSH_RAX\n");
    pushed = pushed + 1;
    i = i - 1;
  }
  i = 0;
  while (i < argc && i < 6) {
    emit_load_operand(out, locs, call_stack_bytes(argc), operand_at(args, i));
    emit_argument_move(out, i);
    i = i + 1;
  }
}

static void emit_instrs(FILE *out, const char *fn_name, LocArray *locs, int total_slots, InstrList *list);

static void emit_instr(FILE *out, const char *fn_name, LocArray *locs, int total_slots, Instr *in)
{
  switch (in->kind) {
    case IK_PARAM:
      if (in->value == 0) fprintf(out, "  HCC_M_RDI_RAX\n");
      else if (in->value == 1) fprintf(out, "  HCC_COPY_rsi_to_rax\n");
      else if (in->value == 2) fprintf(out, "  HCC_COPY_rdx_to_rax\n");
      else if (in->value == 3) fprintf(out, "  HCC_COPY_rcx_to_rax\n");
      else if (in->value == 4) fprintf(out, "  HCC_COPY_r8_to_rax\n");
      else if (in->value == 5) fprintf(out, "  HCC_COPY_r9_to_rax\n");
      else fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%ld\n", total_slots * 8L + 8 + (in->value - 6) * 8);
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_ALLOCA:
      break;
    case IK_CONST:
      emit_load_immediate(out, in->value);
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_CONSTB:
      emit_load_immediate_bytes(out, instr_a_ptr(in));
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_COPY:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_ADDROF:
      emit_address_of(out, locs, in->temp2);
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOAD64:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_INTEGER\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOAD32:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_WORD\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOADS32:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_SIGNED_WORD\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOAD16:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_HALF\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOADS16:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_SIGNED_HALF\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOAD8:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  LOAD_BYTE\n  MOVEZX\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_LOADS8:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_LOAD_SIGNED_CHAR\n");
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_STORE64:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, locs, 0, instr_b_ptr(in));
      fprintf(out, "  HCC_STORE_INTEGER\n");
      break;
    case IK_STORE32:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, locs, 0, instr_b_ptr(in));
      fprintf(out, "  HCC_STORE_WORD\n");
      break;
    case IK_STORE16:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, locs, 0, instr_b_ptr(in));
      fprintf(out, "  HCC_STORE_HALF\n");
      break;
    case IK_STORE8:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, locs, 0, instr_b_ptr(in));
      fprintf(out, "  HCC_STORE_CHAR\n");
      break;
    case IK_BIN:
      emit_load_operand(out, locs, 0, instr_a_ptr(in));
      fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, locs, 0, instr_b_ptr(in));
      emit_binop(out, in->binop);
      emit_store_temp(out, locs, in->temp);
      break;
    case IK_CALL:
      emit_arguments(out, locs, in->args, in->argc);
      fprintf(out, "  CALL_IMMEDIATE %%FUNCTION_%s\n", in->name);
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, locs, in->result);
      break;
    case IK_CALLI:
      emit_arguments(out, locs, in->args, in->argc);
      emit_load_operand(out, locs, call_stack_bytes(in->argc), instr_callee_ptr(in));
      fprintf(out, "  HCC_CALL_rax\n");
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, locs, in->result);
      break;
    case IK_COND:
      emit_instrs(out, fn_name, locs, total_slots, instr_cond_instrs_ptr(in));
      emit_load_operand(out, locs, 0, instr_cond_op_ptr(in));
      fprintf(out, "  TEST\n  JUMP_EQ %%HCC_COND_ELSE_%s_%d\n", fn_name, in->temp);
      emit_instrs(out, fn_name, locs, total_slots, instr_true_instrs_ptr(in));
      emit_load_operand(out, locs, 0, instr_true_op_ptr(in));
      emit_store_temp(out, locs, in->temp);
      fprintf(out, "  JUMP %%HCC_COND_DONE_%s_%d\n:HCC_COND_ELSE_%s_%d\n", fn_name, in->temp, fn_name, in->temp);
      emit_instrs(out, fn_name, locs, total_slots, instr_false_instrs_ptr(in));
      emit_load_operand(out, locs, 0, instr_false_op_ptr(in));
      emit_store_temp(out, locs, in->temp);
      fprintf(out, ":HCC_COND_DONE_%s_%d\n", fn_name, in->temp);
      break;
  }
}

static void emit_instrs(FILE *out, const char *fn_name, LocArray *locs, int total_slots, InstrList *list)
{
  int i = 0;
  while (i < list->len) {
    emit_instr(out, fn_name, locs, total_slots, instr_at(list->items, i));
    i = i + 1;
  }
}

static void emit_block_ref(FILE *out, const char *fn_name, int id)
{
  fprintf(out, "HCC_BLOCK_%s_%d", fn_name, id);
}

static void emit_cleanup_stack(FILE *out, int total_slots)
{
  if (total_slots > 0) fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", total_slots * 8);
}

static void emit_terminator(FILE *out, Function *fn, int block_index, LocArray *locs, int total_slots, Block *block)
{
  int next_id = -1;
  if (block_index + 1 < fn->len) {
    Block *next_block = block_at(fn->blocks, block_index + 1);
    next_id = next_block->id;
  }
  if (block->term_kind == TK_RET) {
    if (block->term_op.kind == 0) emit_load_immediate(out, 0);
    else emit_load_operand(out, locs, 0, block_term_op_ptr(block));
    emit_cleanup_stack(out, total_slots);
    fprintf(out, "  RETURN\n");
  } else if (block->term_kind == TK_JUMP) {
    if (next_id != block->yes) {
      fprintf(out, "  JUMP %%");
      emit_block_ref(out, fn->name, block->yes);
      fputc('\n', out);
    }
  } else if (block->term_kind == TK_BRANCH) {
    emit_load_operand(out, locs, 0, block_term_op_ptr(block));
    if (next_id == block->yes) {
      fprintf(out, "  TEST\n  JUMP_EQ %%");
      emit_block_ref(out, fn->name, block->no);
      fputc('\n', out);
    } else if (next_id == block->no) {
      fprintf(out, "  TEST\n  JUMP_NE %%");
      emit_block_ref(out, fn->name, block->yes);
      fputc('\n', out);
    } else {
      fprintf(out, "  TEST\n  JUMP_NE %%");
      emit_block_ref(out, fn->name, block->yes);
      fprintf(out, "\n  JUMP %%");
      emit_block_ref(out, fn->name, block->no);
      fputc('\n', out);
    }
  }
}

static void emit_function(FILE *out, Function *fn)
{
  LocArray locs;
  int total_slots;
  int i;
  total_slots = allocate_function(fn, &locs);
  fprintf(out, ":FUNCTION_%s\n", fn->name);
  if (total_slots > 0) fprintf(out, "  HCC_SUB_IMMEDIATE_from_rsp %%%d\n", total_slots * 8);
  i = 0;
  while (i < fn->len) {
    Block *block = block_at(fn->blocks, i);
    if (block->id != 0) {
      fprintf(out, ":");
      emit_block_ref(out, fn->name, block->id);
      fputc('\n', out);
    }
    emit_instrs(out, fn->name, &locs, total_slots, block_instrs_ptr(block));
    emit_terminator(out, fn, i, &locs, total_slots, block);
    i = i + 1;
  }
  fputc('\n', out);
}

static void emit_module(FILE *out, Module *module)
{
  int i = 0;
  emit_header(out);
  while (i < module->top_len) {
    if (module->top_kinds[i] == TOP_DATA) {
      emit_data_item(out, data_item_at(module->data_items, module->top_indices[i]));
    } else {
      emit_function(out, function_at(module->functions, module->top_indices[i]));
    }
    i = i + 1;
  }
}

int main(int argc, char **argv)
{
  FILE *in;
  FILE *out;
  Module module;
  if (argc != 3) {
    fputs("usage: hcc-m1 INPUT.hccir OUTPUT.M1\n", stderr);
    return 2;
  }
  in = fopen(argv[1], "r");
  if (!in) die("cannot open input");
  out = fopen(argv[2], "w");
  if (!out) die("cannot open output");
  parse_module(in, &module);
  fclose(in);
  emit_module(out, &module);
  fclose(out);
  return 0;
}
