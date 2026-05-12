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
  BK_XOR = 21
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
  TARGET_AARCH64 = 3
};

static int target_arch = TARGET_AMD64;

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
  Operand term_b;
  int term_binop;
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

struct Loc {
  int kind;
  int slot;
  int slots;
};

struct LocArray {
  Loc *items;
  int cap;
};

struct EmitState {
  int rax_temp;
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

static DataValue *data_value_at(DataValue *items, int index)
{
  return (DataValue *)((char *)items + sizeof(DataValue) * index);
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

static Operand *block_term_b_ptr(Block *block)
{
#if defined(__M2__)
  return (Operand *)((char *)block + 80);
#else
  return &block->term_b;
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

static void append_zero_data_values(DataItem *item, int count)
{
  DataValue value;
  if (count < 0) die("negative zero data run");
  memset(&value, 0, sizeof(value));
  value.kind = 1;
  value.byte = 0;
  while (count > 0) {
    append_data_value(item, &value);
    count = count - 1;
  }
}

static void expect_line(FILE *file, const char *expected)
{
  char *line;
  line = xrealloc(0, LINE_CAP);
  if (!read_line(file, line, LINE_CAP)) die("unexpected eof");
  if (strcmp(line, expected)) die("unexpected section marker");
}

static void parse_ir_operand(char **cursor, Operand *op)
{
  char *tok = need_token(cursor);
  int i;
  memset(op, 0, sizeof(Operand));
  if (tok[0] == 'T') {
    op->kind = OP_TEMP;
    op->value = parse_long_text(tok + 1);
  } else if (tok[0] == 'I') {
    op->kind = OP_IMM;
    op->value = parse_long_text(tok + 1);
  } else if (tok[0] == 'B') {
    op->kind = OP_BYTES;
    op->count = (int)parse_long_text(tok + 1);
    if (op->count > 0) op->bytes = xrealloc(0, sizeof(int) * op->count);
    i = 0;
    while (i < op->count) {
      op->bytes[i] = parse_int_token(cursor);
      i = i + 1;
    }
  } else if (tok[0] == 'G') {
    op->kind = OP_GLOBAL;
    op->name = xstrdup(tok + 1);
  } else if (tok[0] == 'F') {
    op->kind = OP_FUNC;
    op->name = xstrdup(tok + 1);
  } else {
    die_token("unknown IR operand kind", tok);
  }
}

static int parse_ir_result(char **cursor)
{
  char *tok = need_token(cursor);
  if (str_eq(tok, "-")) return -1;
  return (int)parse_long_text(tok);
}

static void parse_ir_prefixed_operand(char *line, const char *prefix, Operand *op)
{
  char *cursor = line;
  char *tok = need_token(&cursor);
  if (strcmp(tok, prefix)) die("unexpected IR operand prefix");
  parse_ir_operand(&cursor, op);
}

static void parse_ir_instrs_until_end(FILE *file, InstrList *list);

static void parse_ir_instr_line(FILE *file, char *line, Instr *instr)
{
  char *cursor = line;
  char *tok;
  char *section;
  int i;
  memset(instr, 0, sizeof(Instr));
  instr->result = -1;
  tok = need_token(&cursor);
  instr->kind = (int)parse_long_text(tok);
  switch (instr->kind) {
    case IK_PARAM:
    case IK_ALLOCA:
    case IK_CONST:
      instr->temp = parse_int_token(&cursor);
      instr->value = parse_long_token(&cursor);
      break;
    case IK_CONSTB:
      instr->temp = parse_int_token(&cursor);
      parse_ir_operand(&cursor, instr_a_ptr(instr));
      if (instr->a.kind != OP_BYTES) die("IR CONSTB needs bytes");
      break;
    case IK_COPY:
    case IK_LOAD64:
    case IK_LOAD32:
    case IK_LOADS32:
    case IK_LOAD16:
    case IK_LOADS16:
    case IK_LOAD8:
    case IK_LOADS8:
      instr->temp = parse_int_token(&cursor);
      parse_ir_operand(&cursor, instr_a_ptr(instr));
      break;
    case IK_SEXT:
    case IK_ZEXT:
    case IK_TRUNC:
      instr->temp = parse_int_token(&cursor);
      instr->value = parse_long_token(&cursor);
      parse_ir_operand(&cursor, instr_a_ptr(instr));
      break;
    case IK_ADDROF:
      instr->temp = parse_int_token(&cursor);
      instr->temp2 = parse_int_token(&cursor);
      break;
    case IK_STORE64:
    case IK_STORE32:
    case IK_STORE16:
    case IK_STORE8:
      parse_ir_operand(&cursor, instr_a_ptr(instr));
      parse_ir_operand(&cursor, instr_b_ptr(instr));
      break;
    case IK_BIN:
      instr->temp = parse_int_token(&cursor);
      instr->binop = parse_int_token(&cursor);
      parse_ir_operand(&cursor, instr_a_ptr(instr));
      parse_ir_operand(&cursor, instr_b_ptr(instr));
      break;
    case IK_CALL:
      instr->result = parse_ir_result(&cursor);
      instr->name = xstrdup(need_token(&cursor));
      instr->argc = parse_int_token(&cursor);
      if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
      i = 0;
      while (i < instr->argc) {
        parse_ir_operand(&cursor, operand_at(instr->args, i));
        i = i + 1;
      }
      break;
    case IK_CALLI:
      instr->result = parse_ir_result(&cursor);
      parse_ir_operand(&cursor, instr_callee_ptr(instr));
      instr->argc = parse_int_token(&cursor);
      if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
      i = 0;
      while (i < instr->argc) {
        parse_ir_operand(&cursor, operand_at(instr->args, i));
        i = i + 1;
      }
      break;
    case IK_COND:
      section = xrealloc(0, LINE_CAP);
      instr->temp = parse_int_token(&cursor);
      expect_line(file, "[");
      parse_ir_instrs_until_end(file, instr_cond_instrs_ptr(instr));
      if (!read_line(file, section, LINE_CAP)) die("missing IR CONDOP");
      parse_ir_prefixed_operand(section, "O", instr_cond_op_ptr(instr));
      expect_line(file, "[");
      parse_ir_instrs_until_end(file, instr_true_instrs_ptr(instr));
      if (!read_line(file, section, LINE_CAP)) die("missing IR TRUEOP");
      parse_ir_prefixed_operand(section, "O", instr_true_op_ptr(instr));
      expect_line(file, "[");
      parse_ir_instrs_until_end(file, instr_false_instrs_ptr(instr));
      if (!read_line(file, section, LINE_CAP)) die("missing IR FALSEOP");
      parse_ir_prefixed_operand(section, "O", instr_false_op_ptr(instr));
      expect_line(file, "Q");
      break;
    default:
      die("unknown IR instruction");
  }
}

static void parse_ir_instrs_until_end(FILE *file, InstrList *list)
{
  Instr instr;
  char *line;
  memset(list, 0, sizeof(InstrList));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "]")) return;
    parse_ir_instr_line(file, line, &instr);
    append_instr(list, &instr);
  }
  die("unexpected eof in IR nested instructions");
}

static void parse_ir_term(Block *block, char *line)
{
  char *cursor = line;
  char *tok = need_token(&cursor);
  if (str_eq(tok, "R")) {
    block->term_kind = TK_RET;
    tok = next_token(&cursor);
    if (tok) {
      cursor = tok;
      parse_ir_operand(&cursor, block_term_op_ptr(block));
    } else {
      block->term_op.kind = 0;
    }
  } else if (str_eq(tok, "J")) {
    block->term_kind = TK_JUMP;
    block->yes = parse_int_token(&cursor);
  } else if (str_eq(tok, "B")) {
    block->term_kind = TK_BRANCH;
    parse_ir_operand(&cursor, block_term_op_ptr(block));
    block->yes = parse_int_token(&cursor);
    block->no = parse_int_token(&cursor);
  } else if (str_eq(tok, "C")) {
    block->term_kind = TK_BRANCH_CMP;
    block->term_binop = parse_int_token(&cursor);
    parse_ir_operand(&cursor, block_term_op_ptr(block));
    parse_ir_operand(&cursor, block_term_b_ptr(block));
    block->yes = parse_int_token(&cursor);
    block->no = parse_int_token(&cursor);
  } else {
    die("unknown IR terminator");
  }
}

static void parse_ir_block(FILE *file, char *first_line, Block *block)
{
  char *cursor = first_line;
  char *tok;
  Instr instr;
  char *line;
  memset(block, 0, sizeof(Block));
  tok = need_token(&cursor);
  if (strcmp(tok, "L")) die("expected IR block");
  block->id = parse_int_token(&cursor);
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_prefix_n(line, "R", 1) || str_prefix_n(line, "J ", 2) || str_prefix_n(line, "B ", 2) || str_prefix_n(line, "C ", 2)) {
      parse_ir_term(block, line);
      return;
    }
    parse_ir_instr_line(file, line, &instr);
    append_instr(block_instrs_ptr(block), &instr);
  }
  die("unexpected eof in IR block");
}

static void parse_ir_function(FILE *file, char *first_line, Function *fn)
{
  char *cursor = first_line;
  char *tok;
  Block block;
  char *line;
  memset(fn, 0, sizeof(Function));
  tok = need_token(&cursor);
  if (strcmp(tok, "F")) die("expected IR function");
  fn->name = xstrdup(need_token(&cursor));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "E")) return;
    parse_ir_block(file, line, &block);
    append_block(fn, &block);
  }
  die("unexpected eof in IR function");
}

static void parse_ir_data_item(FILE *file, char *first_line, DataItem *item)
{
  char *cursor = first_line;
  char *tok;
  char *line;
  memset(item, 0, sizeof(DataItem));
  tok = need_token(&cursor);
  if (strcmp(tok, "D")) die_token("expected IR data item", tok);
  item->label = xstrdup(need_token(&cursor));
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    DataValue value;
    if (str_eq(line, "E")) return;
    cursor = line;
    tok = need_token(&cursor);
    if (str_eq(tok, "z")) {
      append_zero_data_values(item, parse_int_token(&cursor));
      continue;
    }
    memset(&value, 0, sizeof(value));
    if (str_eq(tok, "b")) {
      value.kind = 1;
      value.byte = parse_int_token(&cursor);
    } else if (str_eq(tok, "a")) {
      value.kind = 2;
      value.label = xstrdup(need_token(&cursor));
    } else {
      die("unknown IR data value");
    }
    append_data_value(item, &value);
  }
  die("unexpected eof in IR data");
}

static void emit_byte(FILE *out, int byte);
static void emit_header(FILE *out);
static void emit_data_item(FILE *out, DataItem *item);
static void emit_function(FILE *out, Function *fn);

#if !defined(__M2__)
static void free_operand(Operand *op)
{
  if (op->bytes) free(op->bytes);
  if (op->name) free(op->name);
}

static void free_instr_list(InstrList *list);

static void free_instr(Instr *in)
{
  int i;
  free_operand(instr_a_ptr(in));
  free_operand(instr_b_ptr(in));
  free_operand(instr_callee_ptr(in));
  if (in->name) free(in->name);
  i = 0;
  while (i < in->argc) {
    free_operand(operand_at(in->args, i));
    i = i + 1;
  }
  if (in->args) free(in->args);
  free_instr_list(instr_cond_instrs_ptr(in));
  free_instr_list(instr_true_instrs_ptr(in));
  free_instr_list(instr_false_instrs_ptr(in));
  free_operand(instr_cond_op_ptr(in));
  free_operand(instr_true_op_ptr(in));
  free_operand(instr_false_op_ptr(in));
}

static void free_instr_list(InstrList *list)
{
  int i = 0;
  while (i < list->len) {
    free_instr(instr_at(list->items, i));
    i = i + 1;
  }
  if (list->items) free(list->items);
}

static void free_block(Block *block)
{
  free_instr_list(block_instrs_ptr(block));
  free_operand(block_term_op_ptr(block));
  free_operand(block_term_b_ptr(block));
}

static void free_function(Function *fn)
{
  int i = 0;
  if (fn->name) free(fn->name);
  while (i < fn->len) {
    free_block(block_at(fn->blocks, i));
    i = i + 1;
  }
  if (fn->blocks) free(fn->blocks);
}

static void free_data_item(DataItem *item)
{
  int i = 0;
  if (item->label) free(item->label);
  while (i < item->len) {
    DataValue *value = data_value_at(item->values, i);
    if (value->label) free(value->label);
    i = i + 1;
  }
  if (item->values) free(item->values);
}
#else
static void free_function(Function *fn) { (void)fn; }
static void free_data_item(DataItem *item) { (void)item; }
#endif

static void translate_ir_module(FILE *file, FILE *out)
{
  DataItem item;
  Function fn;
  char *line;
  emit_header(out);
  line = xrealloc(0, LINE_CAP);
  while (read_line(file, line, LINE_CAP)) {
    if (str_prefix_n(line, "D ", 2)) {
      parse_ir_data_item(file, line, &item);
      emit_data_item(out, &item);
      free_data_item(&item);
    } else if (str_prefix_n(line, "F ", 2)) {
      parse_ir_function(file, line, &fn);
      emit_function(out, &fn);
      free_function(&fn);
    } else if (line[0] != 0) die("unexpected IR top-level line");
  }
#if !defined(__M2__)
  free(line);
#endif
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
  if (target_arch == TARGET_I386) slots = (size + 3) / 4;
  else slots = (size + 7) / 8;
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
      case IK_SEXT:
      case IK_ZEXT:
      case IK_TRUNC:
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

static void emit_state_init(EmitState *state)
{
  state->rax_temp = -1;
}

static void emit_forget_rax(EmitState *state)
{
  state->rax_temp = -1;
}

static void emit_remember_rax_temp(EmitState *state, int temp)
{
  state->rax_temp = temp;
}

static void emit_byte(FILE *out, int byte);
static void emit_block_ref(FILE *out, const char *fn_name, int id);
static int invert_binop(int op);

static int target_register_arg_count(void)
{
  if (target_arch == TARGET_I386) return 0;
  if (target_arch == TARGET_AARCH64) return 8;
  return 6;
}

static void emit_word_le(FILE *out, unsigned long word)
{
  int i = 0;
  while (i < 4) {
    if (i) fputc(' ', out);
    emit_byte(out, (int)(word & 255));
    word = word >> 8;
    i = i + 1;
  }
}

static void emit_data64_le(FILE *out, unsigned long value)
{
  int i = 0;
  fprintf(out, "  ");
  while (i < 8) {
    if (i) fputc(' ', out);
    emit_byte(out, (int)(value & 255));
    value = value >> 8;
    i = i + 1;
  }
  fputc('\n', out);
}

#include "hcc_m1_arch_aarch64.c"

static void emit_header(FILE *out)
{
  fprintf(out, "## hcc M1 output\n");
  if (target_arch == TARGET_I386) {
    fprintf(out, "## target: stage0-posix x86 M1\n");
    fprintf(out, "\n");
    fprintf(out, "DEFINE HCC_ADD_IMMEDIATE_to_esp 81C4\n");
    fprintf(out, "DEFINE HCC_STORE_ESP_IMMEDIATE_from_eax 898424\n");
    fprintf(out, "DEFINE HCC_LOAD_EFFECTIVE_ADDRESS_eax 8D8424\n");
    fprintf(out, "DEFINE HCC_LOAD_SIGNED_WORD 8B00\n");
    fprintf(out, "DEFINE HCC_STORE_WORD 8903\n");
    fprintf(out, "DEFINE HCC_STORE_HALF 668903\n");
    fprintf(out, "DEFINE HCC_STORE_CHAR 8803\n");
    fprintf(out, "DEFINE HCC_JUMP_EQ 0F84\n");
    fprintf(out, "DEFINE HCC_JUMP_NE 0F85\n");
    fprintf(out, "DEFINE HCC_JUMP_LT 0F8C\n");
    fprintf(out, "DEFINE HCC_JUMP_LE 0F8E\n");
    fprintf(out, "DEFINE HCC_JUMP_GT 0F8F\n");
    fprintf(out, "DEFINE HCC_JUMP_GE 0F8D\n");
    fprintf(out, "DEFINE HCC_JUMP_ULT 0F82\n");
    fprintf(out, "DEFINE HCC_JUMP_ULE 0F86\n");
    fprintf(out, "DEFINE HCC_JUMP_UGT 0F87\n");
    fprintf(out, "DEFINE HCC_JUMP_UGE 0F83\n");
    fprintf(out, "DEFINE HCC_CALL_eax FFD0\n");
    fprintf(out, "DEFINE CALL_IMMEDIATE E8\n");
    fprintf(out, "\n");
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_header(out);
    return;
  }
  fprintf(out, "## target: stage0-posix amd64 M1\n");
  fprintf(out, "\n");
  fprintf(out, "DEFINE ADD_rbx_to_rax 4801D8\n");
  fprintf(out, "DEFINE AND_rax_rbx 4821D8\n");
  fprintf(out, "DEFINE CALL_IMMEDIATE E8\n");
  fprintf(out, "DEFINE CMP 4839C3\n");
  fprintf(out, "DEFINE COPY_rax_to_rdi 4889C7\n");
  fprintf(out, "DEFINE COPY_rax_to_rcx 4889C1\n");
  fprintf(out, "DEFINE COPY_rsp_to_rbp 4889E5\n");
  fprintf(out, "DEFINE COPY_rbp_to_rax 4889E8\n");
  fprintf(out, "DEFINE CQTO 4899\n");
  fprintf(out, "DEFINE JUMP E9\n");
  fprintf(out, "DEFINE JUMP_EQ 0F84\n");
  fprintf(out, "DEFINE JUMP_NE 0F85\n");
  fprintf(out, "DEFINE HCC_JUMP_EQ 0F84\n");
  fprintf(out, "DEFINE HCC_JUMP_NE 0F85\n");
  fprintf(out, "DEFINE HCC_JUMP_LT 0F8C\n");
  fprintf(out, "DEFINE HCC_JUMP_LE 0F8E\n");
  fprintf(out, "DEFINE HCC_JUMP_GT 0F8F\n");
  fprintf(out, "DEFINE HCC_JUMP_GE 0F8D\n");
  fprintf(out, "DEFINE HCC_JUMP_ULT 0F82\n");
  fprintf(out, "DEFINE HCC_JUMP_ULE 0F86\n");
  fprintf(out, "DEFINE HCC_JUMP_UGT 0F87\n");
  fprintf(out, "DEFINE HCC_JUMP_UGE 0F83\n");
  fprintf(out, "DEFINE LOAD_BASE_ADDRESS_rax 488D85\n");
  fprintf(out, "DEFINE LOAD_BYTE 0FBE00\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rax 48C7C0\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rdi 48C7C7\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rsi 48C7C6\n");
  fprintf(out, "DEFINE LOAD_INTEGER 488B00\n");
  fprintf(out, "DEFINE LOAD_RSP_IMMEDIATE_into_rax 488B8424\n");
  fprintf(out, "DEFINE MOVE_rbx_to_rax 4889D8\n");
  fprintf(out, "DEFINE MOVE_rdx_to_rax 4889D0\n");
  fprintf(out, "DEFINE MOVEZX 480FB6C0\n");
  fprintf(out, "DEFINE DIVIDES_rax_by_rbx_into_rax 48F7FB\n");
  fprintf(out, "DEFINE MODULUSS_rax_from_rbx_into_rbx 48F7FB\n");
  fprintf(out, "DEFINE MULTIPLY_rax_by_rbx_into_rax 48F7EB\n");
  fprintf(out, "DEFINE OR_rax_rbx 4809D8\n");
  fprintf(out, "DEFINE PUSH_RAX 50\n");
  fprintf(out, "DEFINE RETURN C3\n");
  fprintf(out, "DEFINE SETA 0F97C0\n");
  fprintf(out, "DEFINE SETAE 0F93C0\n");
  fprintf(out, "DEFINE SETB 0F92C0\n");
  fprintf(out, "DEFINE SETBE 0F96C0\n");
  fprintf(out, "DEFINE SETE 0F94C0\n");
  fprintf(out, "DEFINE SETG 0F9FC0\n");
  fprintf(out, "DEFINE SETGE 0F9DC0\n");
  fprintf(out, "DEFINE SETL 0F9CC0\n");
  fprintf(out, "DEFINE SETLE 0F9EC0\n");
  fprintf(out, "DEFINE SETNE 0F95C0\n");
  fprintf(out, "DEFINE STORE_INTEGER 488903\n");
  fprintf(out, "DEFINE SUBTRACT_rax_from_rbx_into_rbx 4829C3\n");
  fprintf(out, "DEFINE SYSCALL 0F05\n");
  fprintf(out, "DEFINE TEST 4885C0\n");
  fprintf(out, "DEFINE XCHG_rax_rbx 4893\n");
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
  fprintf(out, "DEFINE HCC_SEXT8_RAX 480FBEC0\n");
  fprintf(out, "DEFINE HCC_SEXT16_RAX 480FBFC0\n");
  fprintf(out, "DEFINE HCC_SEXT32_RAX 4863C0\n");
  fprintf(out, "DEFINE HCC_ZEXT16_RAX 480FB7C0\n");
  fprintf(out, "DEFINE HCC_ZEXT32_RAX 89C0\n");
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
  int emitted = 0;
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
        if (target_arch == TARGET_I386) fprintf(out, "&%s", v->label);
        else fprintf(out, "&%s '00' '00' '00' '00'", v->label);
      }
      count = count + 1;
      j = j + 1;
      if (v->kind == 1) emitted = emitted + 1;
      else if (target_arch == TARGET_I386) emitted = emitted + 4;
      else emitted = emitted + 8;
    }
    fputc('\n', out);
  }
  if (target_arch == TARGET_AARCH64 && emitted % 4 != 0) {
    fprintf(out, "  ");
    while (emitted % 4 != 0) {
      emit_byte(out, 0);
      emitted = emitted + 1;
      if (emitted % 4 != 0) fputc(' ', out);
    }
    fputc('\n', out);
  }
  fputc('\n', out);
}

static void emit_load_immediate(FILE *out, EmitState *state, long value)
{
  int small;
  unsigned long u;
  int i;
  emit_forget_rax(state);
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_load_immediate(out, (unsigned long)value);
    return;
  }
  if (target_arch == TARGET_I386) {
    fprintf(out, "  mov_eax, %%%d\n", (int)value);
    return;
  }
  small = (int)value;
  if ((long)small == value) {
    fprintf(out, "  LOAD_IMMEDIATE_rax %%%d\n", small);
  } else {
    u = (unsigned long)value;
    i = 0;
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

static void emit_load_immediate_bytes(FILE *out, EmitState *state, Operand *op)
{
  int bytes[8];
  int i = 0;
  unsigned long value = 0;
  emit_forget_rax(state);
  while (i < 8) {
    if (i < op->count) bytes[i] = op->bytes[i];
    else bytes[i] = 0;
    i = i + 1;
  }
  if (target_arch == TARGET_I386) {
    i = 3;
    while (i >= 0) {
      value = (value << 8) + (unsigned long)(bytes[i] & 255);
      i = i - 1;
    }
    fprintf(out, "  mov_eax, %%%u\n", (unsigned int)value);
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    i = 7;
    value = 0;
    while (i >= 0) {
      value = (value << 8) + (unsigned long)(bytes[i] & 255);
      i = i - 1;
    }
    aarch64_emit_load_immediate(out, value);
    return;
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

static void emit_load_location(FILE *out, EmitState *state, Loc *loc, int rsp_bias)
{
  emit_forget_rax(state);
  if (loc->kind == LOC_STACK) {
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax,[esp+DWORD] %%%d\n", 4 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_load_stack(out, 8 * loc->slot + rsp_bias);
    else fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%d\n", 8 * loc->slot + rsp_bias);
  } else if (loc->kind == LOC_OBJECT) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_eax %%%d\n", 4 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_address_stack(out, 8 * loc->slot + rsp_bias);
    else fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot + rsp_bias);
  }
}

static void emit_load_operand(FILE *out, EmitState *state, LocArray *locs, int rsp_bias, Operand *op)
{
  Loc *loc;
  if (op->kind == OP_IMM) emit_load_immediate(out, state, op->value);
  else if (op->kind == OP_BYTES) emit_load_immediate_bytes(out, state, op);
  else if (op->kind == OP_GLOBAL) {
    emit_forget_rax(state);
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax, &%s\n", op->name);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_load_label(out, 0, op->name);
    else fprintf(out, "  LOAD_IMMEDIATE_rax &%s\n", op->name);
  } else if (op->kind == OP_FUNC) {
    emit_forget_rax(state);
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax, &FUNCTION_%s\n", op->name);
    else if (target_arch == TARGET_AARCH64) {
      aarch64_emit_load_literal_prefix(out, 0);
      fprintf(out, "  &FUNCTION_%s '00' '00' '00' '00'\n", op->name);
    }
    else fprintf(out, "  LOAD_IMMEDIATE_rax &FUNCTION_%s\n", op->name);
  }
  else if (op->kind == OP_TEMP) {
    loc = lookup_loc(locs, op->value);
    if (rsp_bias == 0 && loc->kind == LOC_STACK && state->rax_temp == op->value) return;
    emit_load_location(out, state, loc, rsp_bias);
    if (rsp_bias == 0 && loc->kind == LOC_STACK) emit_remember_rax_temp(state, op->value);
  }
}

static void emit_store_temp(FILE *out, EmitState *state, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  if (loc->kind == LOC_STACK) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_STORE_ESP_IMMEDIATE_from_eax %%%d\n", 4 * loc->slot);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_store_stack(out, 8 * loc->slot);
    else fprintf(out, "  HCC_STORE_RSP_IMMEDIATE_from_rax %%%d\n", 8 * loc->slot);
    emit_remember_rax_temp(state, temp);
  } else if (loc->kind == LOC_OBJECT) {
    die("cannot assign stack object");
  }
}

static void emit_address_of(FILE *out, EmitState *state, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  emit_forget_rax(state);
  if (loc->kind == LOC_STACK || loc->kind == LOC_OBJECT) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_eax %%%d\n", 4 * loc->slot);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_address_stack(out, 8 * loc->slot);
    else fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot);
  } else {
    die("cannot take address");
  }
}

static void emit_binop(FILE *out, int op)
{
  if (target_arch == TARGET_I386) {
    switch (op) {
      case BK_ADD: fprintf(out, "  add_eax,ebx\n"); break;
      case BK_SUB: fprintf(out, "  sub_ebx,eax\n  mov_eax,ebx\n"); break;
      case BK_MUL: fprintf(out, "  imul_ebx\n"); break;
      case BK_DIV: fprintf(out, "  xchg_ebx,eax\n  cdq\n  idiv_ebx\n"); break;
      case BK_MOD: fprintf(out, "  xchg_ebx,eax\n  cdq\n  idiv_ebx\n  mov_eax,edx\n"); break;
      case BK_SHL: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  shl_eax,cl\n"); break;
      case BK_SHR: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  shr_eax,cl\n"); break;
      case BK_SAR: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  sar_eax,cl\n"); break;
      case BK_EQ: fprintf(out, "  cmp_ebx,eax\n  sete_al\n  movzx_eax,al\n"); break;
      case BK_NE: fprintf(out, "  cmp_ebx,eax\n  setne_al\n  movzx_eax,al\n"); break;
      case BK_LT: fprintf(out, "  cmp_ebx,eax\n  setl_al\n  movzx_eax,al\n"); break;
      case BK_LE: fprintf(out, "  cmp_ebx,eax\n  setle_al\n  movzx_eax,al\n"); break;
      case BK_GT: fprintf(out, "  cmp_ebx,eax\n  setg_al\n  movzx_eax,al\n"); break;
      case BK_GE: fprintf(out, "  cmp_ebx,eax\n  setge_al\n  movzx_eax,al\n"); break;
      case BK_ULT: fprintf(out, "  cmp_ebx,eax\n  setb_al\n  movzx_eax,al\n"); break;
      case BK_ULE: fprintf(out, "  cmp_ebx,eax\n  setbe_al\n  movzx_eax,al\n"); break;
      case BK_UGT: fprintf(out, "  cmp_ebx,eax\n  seta_al\n  movzx_eax,al\n"); break;
      case BK_UGE: fprintf(out, "  cmp_ebx,eax\n  setae_al\n  movzx_eax,al\n"); break;
      case BK_AND: fprintf(out, "  and_eax,ebx\n"); break;
      case BK_OR: fprintf(out, "  or_eax,ebx\n"); break;
      case BK_XOR: fprintf(out, "  xor_eax,ebx\n"); break;
    }
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_binop(out, op);
    return;
  }
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

static long mask_for_size(int size)
{
  if (size <= 1) return 255;
  if (size <= 2) return 65535;
  if (size <= 4) return 4294967295L;
  return -1;
}

static long sign_bit_for_size(int size)
{
  if (size <= 1) return 128;
  if (size <= 2) return 32768;
  return 2147483648L;
}

static void emit_copy_acc_to_scratch(FILE *out)
{
  if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
  else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
  else fprintf(out, "  HCC_M_RAX_RBX\n");
}

static void emit_amd64_zext_loaded_rax(FILE *out, int size)
{
  if (size <= 1) fprintf(out, "  MOVEZX\n");
  else if (size <= 2) fprintf(out, "  HCC_ZEXT16_RAX\n");
  else if (size <= 4) fprintf(out, "  HCC_ZEXT32_RAX\n");
}

static void emit_i386_zext_loaded_eax(FILE *out, EmitState *state, int size)
{
  if (size >= 4) return;
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, mask_for_size(size));
  emit_binop(out, BK_AND);
}

static void emit_amd64_sext_loaded_rax(FILE *out, int size)
{
  if (size <= 1) fprintf(out, "  HCC_SEXT8_RAX\n");
  else if (size <= 2) fprintf(out, "  HCC_SEXT16_RAX\n");
  else if (size <= 4) fprintf(out, "  HCC_SEXT32_RAX\n");
}

static void emit_i386_sext_loaded_eax(FILE *out, EmitState *state, int size)
{
  long sign_bit;
  if (size >= 4) return;
  sign_bit = sign_bit_for_size(size);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, mask_for_size(size));
  emit_binop(out, BK_AND);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, sign_bit);
  emit_binop(out, BK_XOR);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, sign_bit);
  emit_binop(out, BK_SUB);
}

static void emit_zext_loaded_acc(FILE *out, EmitState *state, int size)
{
  if (target_arch == TARGET_I386) emit_i386_zext_loaded_eax(out, state, size);
  else if (target_arch == TARGET_AARCH64) {
    if (size == 4) {
      fprintf(out, "  ");
      emit_byte(out, 224);
      fputc(' ', out);
      emit_byte(out, 3);
      fputc(' ', out);
      emit_byte(out, 0);
      fputc(' ', out);
      emit_byte(out, 42);
      fputc('\n', out);
    } else if (size < 8) {
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, mask_for_size(size));
      emit_binop(out, BK_AND);
    }
  }
  else emit_amd64_zext_loaded_rax(out, size);
  emit_forget_rax(state);
}

static void emit_sext_loaded_acc(FILE *out, EmitState *state, int size)
{
  if (target_arch == TARGET_I386) emit_i386_sext_loaded_eax(out, state, size);
  else if (target_arch == TARGET_AARCH64) {
    long sign_bit;
    if (size == 4) {
      fprintf(out, "  ");
      emit_byte(out, 0);
      fputc(' ', out);
      emit_byte(out, 124);
      fputc(' ', out);
      emit_byte(out, 64);
      fputc(' ', out);
      emit_byte(out, 147);
      fputc('\n', out);
    } else if (size < 8) {
      sign_bit = sign_bit_for_size(size);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, mask_for_size(size));
      emit_binop(out, BK_AND);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, sign_bit);
      emit_binop(out, BK_XOR);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, sign_bit);
      emit_binop(out, BK_SUB);
    }
  }
  else emit_amd64_sext_loaded_rax(out, size);
  emit_forget_rax(state);
}

static int invert_binop(int op)
{
  switch (op) {
    case BK_EQ: return BK_NE;
    case BK_NE: return BK_EQ;
    case BK_LT: return BK_GE;
    case BK_LE: return BK_GT;
    case BK_GT: return BK_LE;
    case BK_GE: return BK_LT;
    case BK_ULT: return BK_UGE;
    case BK_ULE: return BK_UGT;
    case BK_UGT: return BK_ULE;
    case BK_UGE: return BK_ULT;
  }
  die("cannot invert branch comparison");
  return BK_NE;
}

static void emit_compare(FILE *out, EmitState *state, LocArray *locs, Operand *a, Operand *b)
{
  emit_load_operand(out, state, locs, 0, a);
  emit_copy_acc_to_scratch(out);
  emit_load_operand(out, state, locs, 0, b);
  if (target_arch == TARGET_I386) fprintf(out, "  cmp_ebx,eax\n");
  else if (target_arch == TARGET_AARCH64) fprintf(out, "  CMP_X1_X0\n");
  else fprintf(out, "  CMP\n");
}

static const char *jump_name_for_binop(int op)
{
  switch (op) {
    case BK_EQ: return "HCC_JUMP_EQ";
    case BK_NE: return "HCC_JUMP_NE";
    case BK_LT: return "HCC_JUMP_LT";
    case BK_LE: return "HCC_JUMP_LE";
    case BK_GT: return "HCC_JUMP_GT";
    case BK_GE: return "HCC_JUMP_GE";
    case BK_ULT: return "HCC_JUMP_ULT";
    case BK_ULE: return "HCC_JUMP_ULE";
    case BK_UGT: return "HCC_JUMP_UGT";
    case BK_UGE: return "HCC_JUMP_UGE";
  }
  die("bad branch comparison");
  return "HCC_JUMP_NE";
}

static void emit_block_ref(FILE *out, const char *fn_name, int id);

static void emit_jump(FILE *out, const char *fn_name, int target)
{
  if (target_arch == TARGET_I386) fprintf(out, "  jmp %%");
  else if (target_arch == TARGET_AARCH64) {
    aarch64_emit_jump(out, fn_name, target);
    return;
  }
  else fprintf(out, "  JUMP %%");
  emit_block_ref(out, fn_name, target);
  fputc('\n', out);
}

static void emit_compare_jump(FILE *out, const char *fn_name, int op, int target)
{
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_compare_jump(out, fn_name, op, target);
    return;
  }
  fprintf(out, "  %s %%", jump_name_for_binop(op));
  emit_block_ref(out, fn_name, target);
  fputc('\n', out);
}

static void emit_truth_jump(FILE *out, const char *fn_name, int jump_if_true, int target)
{
  if (target_arch == TARGET_I386) {
    if (jump_if_true) fprintf(out, "  test_eax,eax\n  jne %%");
    else fprintf(out, "  test_eax,eax\n  je %%");
  } else if (target_arch == TARGET_AARCH64) {
    aarch64_emit_truth_jump(out, fn_name, jump_if_true, target);
    return;
  } else {
    if (jump_if_true) fprintf(out, "  TEST\n  JUMP_NE %%");
    else fprintf(out, "  TEST\n  JUMP_EQ %%");
  }
  emit_block_ref(out, fn_name, target);
  fputc('\n', out);
}

static void emit_truth_branch(FILE *out, const char *fn_name, int yes, int no, int next_id)
{
  if (next_id == yes) {
    emit_truth_jump(out, fn_name, 0, no);
  } else if (next_id == no) {
    emit_truth_jump(out, fn_name, 1, yes);
  } else {
    emit_truth_jump(out, fn_name, 1, yes);
    emit_jump(out, fn_name, no);
  }
}

static void emit_compare_branch(FILE *out, const char *fn_name, int op, int yes, int no, int next_id)
{
  if (next_id == yes) {
    emit_compare_jump(out, fn_name, invert_binop(op), no);
  } else if (next_id == no) {
    emit_compare_jump(out, fn_name, op, yes);
  } else {
    emit_compare_jump(out, fn_name, op, yes);
    emit_jump(out, fn_name, no);
  }
}

static int call_stack_bytes(int argc)
{
  if (target_arch == TARGET_I386) return argc * 4;
  {
    int stack_args = argc - target_register_arg_count();
    if (stack_args <= 0) return 0;
    return stack_args * 8;
  }
}

static void emit_call_cleanup(FILE *out, int argc)
{
  int bytes = call_stack_bytes(argc);
  if (bytes > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_ADD_IMMEDIATE_to_esp %%%d\n", bytes);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_add_imm_reg(out, 18, 18, bytes);
    else fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", bytes);
  }
}

static void emit_argument_move(FILE *out, int index)
{
  if (target_arch == TARGET_AARCH64) {
    if (index == 0) return;
    if (index == 1) fprintf(out, "  SET_X1_FROM_X0\n");
    else if (index == 2) fprintf(out, "  SET_X2_FROM_X0\n");
    else if (index == 3) fprintf(out, "  SET_X3_FROM_X0\n");
    else if (index == 4) fprintf(out, "  SET_X4_FROM_X0\n");
    else if (index == 5) fprintf(out, "  SET_X5_FROM_X0\n");
    else if (index == 6) fprintf(out, "  SET_X6_FROM_X0\n");
    else if (index == 7) aarch64_emit_mov_reg(out, 7, 0);
    else die("bad argument register");
    return;
  }
  if (index == 0) fprintf(out, "  COPY_rax_to_rdi\n");
  else if (index == 1) fprintf(out, "  HCC_COPY_rax_to_rsi\n");
  else if (index == 2) fprintf(out, "  HCC_COPY_rax_to_rdx\n");
  else if (index == 3) fprintf(out, "  HCC_COPY_rax_to_rcx\n");
  else if (index == 4) fprintf(out, "  HCC_COPY_rax_to_r8\n");
  else if (index == 5) fprintf(out, "  HCC_COPY_rax_to_r9\n");
  else die("bad argument register");
}

static void emit_arguments(FILE *out, EmitState *state, LocArray *locs, Operand *args, int argc)
{
  int i = argc - 1;
  int pushed = 0;
  if (target_arch == TARGET_I386) {
    while (i >= 0) {
      emit_load_operand(out, state, locs, pushed * 4, operand_at(args, i));
      fprintf(out, "  push_eax\n");
      pushed = pushed + 1;
      i = i - 1;
    }
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    while (i >= 8) {
      emit_load_operand(out, state, locs, pushed * 8, operand_at(args, i));
      fprintf(out, "  PUSH_X0\n");
      pushed = pushed + 1;
      i = i - 1;
    }
    i = argc;
    if (i > 8) i = 8;
    i = i - 1;
    while (i >= 0) {
      emit_load_operand(out, state, locs, call_stack_bytes(argc), operand_at(args, i));
      emit_argument_move(out, i);
      i = i - 1;
    }
    return;
  }
  while (i >= 6) {
    emit_load_operand(out, state, locs, pushed * 8, operand_at(args, i));
    fprintf(out, "  PUSH_RAX\n");
    pushed = pushed + 1;
    i = i - 1;
  }
  i = 0;
  while (i < argc && i < 6) {
    emit_load_operand(out, state, locs, call_stack_bytes(argc), operand_at(args, i));
    emit_argument_move(out, i);
    i = i + 1;
  }
}

static void emit_instrs(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, InstrList *list);

static void emit_instr(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, Instr *in)
{
  int param_offset;
  int width;

  if (in->kind == IK_SEXT) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_sext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }
  if (in->kind == IK_ZEXT) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_zext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }
  if (in->kind == IK_TRUNC) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_zext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }

  switch (in->kind) {
    case IK_PARAM:
      if (target_arch == TARGET_I386) {
        param_offset = total_slots * 4 + 4 + in->value * 4;
        fprintf(out, "  mov_eax,[esp+DWORD] %%%d\n", param_offset);
      } else if (target_arch == TARGET_AARCH64) {
        if (in->value < 8) {
          if (in->value == 0) {
          } else {
            aarch64_emit_mov_reg(out, 0, in->value);
          }
        } else {
          param_offset = total_slots * 8 + 8 + (in->value - 8) * 8;
          aarch64_emit_load_store(out, 1, 8, 0, 18, param_offset);
        }
      } else if (in->value == 0) fprintf(out, "  HCC_M_RDI_RAX\n");
      else if (in->value == 1) fprintf(out, "  HCC_COPY_rsi_to_rax\n");
      else if (in->value == 2) fprintf(out, "  HCC_COPY_rdx_to_rax\n");
      else if (in->value == 3) fprintf(out, "  HCC_COPY_rcx_to_rax\n");
      else if (in->value == 4) fprintf(out, "  HCC_COPY_r8_to_rax\n");
      else if (in->value == 5) fprintf(out, "  HCC_COPY_r9_to_rax\n");
      else {
        param_offset = total_slots * 8 + 8 + (in->value - 6) * 8;
        fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%d\n", param_offset);
      }
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_ALLOCA:
      break;
    case IK_CONST:
      emit_load_immediate(out, state, in->value);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_CONSTB:
      emit_load_immediate_bytes(out, state, instr_a_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_COPY:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_ADDROF:
      emit_address_of(out, state, locs, in->temp2);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOAD64:
      if (target_arch == TARGET_I386) die("i386 M1 backend cannot lower 64-bit load");
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 8, 0, 0, 0);
      else fprintf(out, "  HCC_LOAD_INTEGER\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOAD32:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_eax,[eax]\n");
      else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 4, 0, 0, 0);
      else fprintf(out, "  HCC_LOAD_WORD\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOADS32:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 4, 1, 0, 0);
      else fprintf(out, "  HCC_LOAD_SIGNED_WORD\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOAD16:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  movzx_eax,WORD_PTR_[eax]\n");
      else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 2, 0, 0, 0);
      else fprintf(out, "  HCC_LOAD_HALF\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOADS16:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  movsx_eax,WORD_PTR_[eax]\n");
      else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 2, 1, 0, 0);
      else fprintf(out, "  HCC_LOAD_SIGNED_HALF\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOAD8:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  movzx_eax,BYTE_PTR_[eax]\n");
      else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 1, 0, 0, 0);
      else fprintf(out, "  LOAD_BYTE\n  MOVEZX\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOADS8:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  movsx_eax,BYTE_PTR_[eax]\n");
      else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, 1, 1, 0, 0);
      else fprintf(out, "  HCC_LOAD_SIGNED_CHAR\n");
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_STORE64:
      if (target_arch == TARGET_I386) die("i386 M1 backend cannot lower 64-bit store");
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 0, 8, 0, 1, 0);
      else fprintf(out, "  HCC_STORE_INTEGER\n");
      break;
    case IK_STORE32:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
      else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 0, 4, 0, 1, 0);
      else fprintf(out, "  HCC_STORE_WORD\n");
      break;
    case IK_STORE16:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
      else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 0, 2, 0, 1, 0);
      else fprintf(out, "  HCC_STORE_HALF\n");
      break;
    case IK_STORE8:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
      else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 0, 1, 0, 1, 0);
      else fprintf(out, "  HCC_STORE_CHAR\n");
      break;
    case IK_BIN:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
      else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      emit_binop(out, in->binop);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_CALL:
      emit_arguments(out, state, locs, in->args, in->argc);
      if (target_arch == TARGET_AARCH64) {
        aarch64_emit_load_literal_prefix(out, 16);
        fprintf(out, "  &FUNCTION_%s '00' '00' '00' '00'\n", in->name);
        fprintf(out, "  BLR_X16\n");
      } else {
        fprintf(out, "  CALL_IMMEDIATE %%FUNCTION_%s\n", in->name);
      }
      emit_forget_rax(state);
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, state, locs, in->result);
      break;
    case IK_CALLI:
      if (target_arch == TARGET_AARCH64) {
        emit_load_operand(out, state, locs, 0, instr_callee_ptr(in));
        fprintf(out, "  SET_X16_FROM_X0\n");
        emit_arguments(out, state, locs, in->args, in->argc);
        fprintf(out, "  BLR_X16\n");
      } else {
        emit_arguments(out, state, locs, in->args, in->argc);
        emit_load_operand(out, state, locs, call_stack_bytes(in->argc), instr_callee_ptr(in));
        if (target_arch == TARGET_I386) fprintf(out, "  HCC_CALL_eax\n");
        else fprintf(out, "  HCC_CALL_rax\n");
      }
      emit_forget_rax(state);
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, state, locs, in->result);
      break;
    case IK_COND:
      emit_instrs(out, fn_name, state, locs, total_slots, instr_cond_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_cond_op_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  test_eax,eax\n  je %%HCC_COND_ELSE_%s_%d\n", fn_name, in->temp);
      else if (target_arch == TARGET_AARCH64) {
        aarch64_emit_load_literal_prefix(out, 16);
        fprintf(out, "  &HCC_COND_ELSE_%s_%d '00' '00' '00' '00'\n", fn_name, in->temp);
        fprintf(out, "  HCC_CBNZ_X0_PAST_BR\n  BR_X16\n");
      }
      else fprintf(out, "  TEST\n  JUMP_EQ %%HCC_COND_ELSE_%s_%d\n", fn_name, in->temp);
      emit_forget_rax(state);
      emit_instrs(out, fn_name, state, locs, total_slots, instr_true_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_true_op_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      if (target_arch == TARGET_I386) fprintf(out, "  jmp %%HCC_COND_DONE_%s_%d\n:HCC_COND_ELSE_%s_%d\n", fn_name, in->temp, fn_name, in->temp);
      else if (target_arch == TARGET_AARCH64) {
        aarch64_emit_load_literal_prefix(out, 16);
        fprintf(out, "  &HCC_COND_DONE_%s_%d '00' '00' '00' '00'\n", fn_name, in->temp);
        fprintf(out, "  BR_X16\n:HCC_COND_ELSE_%s_%d\n", fn_name, in->temp);
      }
      else fprintf(out, "  JUMP %%HCC_COND_DONE_%s_%d\n:HCC_COND_ELSE_%s_%d\n", fn_name, in->temp, fn_name, in->temp);
      emit_forget_rax(state);
      emit_instrs(out, fn_name, state, locs, total_slots, instr_false_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_false_op_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      fprintf(out, ":HCC_COND_DONE_%s_%d\n", fn_name, in->temp);
      emit_forget_rax(state);
      break;
  }
}

static void emit_instrs(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, InstrList *list)
{
  int i = 0;
  while (i < list->len) {
    emit_instr(out, fn_name, state, locs, total_slots, instr_at(list->items, i));
    i = i + 1;
  }
}

static void emit_block_ref(FILE *out, const char *fn_name, int id)
{
  fprintf(out, "HCC_BLOCK_%s_%d", fn_name, id);
}

static void emit_cleanup_stack(FILE *out, int total_slots)
{
  if (total_slots > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_ADD_IMMEDIATE_to_esp %%%d\n", total_slots * 4);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_add_imm_reg(out, 18, 18, total_slots * 8);
    else fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", total_slots * 8);
  }
}

static void emit_terminator(FILE *out, Function *fn, int block_index, EmitState *state, LocArray *locs, int total_slots, Block *block)
{
  int next_id = -1;
  if (block_index + 1 < fn->len) {
    Block *next_block = block_at(fn->blocks, block_index + 1);
    next_id = next_block->id;
  }
  if (block->term_kind == TK_RET) {
    if (block->term_op.kind == 0) emit_load_immediate(out, state, 0);
    else emit_load_operand(out, state, locs, 0, block_term_op_ptr(block));
    emit_cleanup_stack(out, total_slots);
    if (target_arch == TARGET_I386) fprintf(out, "  ret\n");
    else if (target_arch == TARGET_AARCH64) fprintf(out, "  POP_LR\n  RETURN\n");
    else fprintf(out, "  RETURN\n");
  } else if (block->term_kind == TK_JUMP) {
    if (next_id != block->yes) {
      emit_jump(out, fn->name, block->yes);
    }
  } else if (block->term_kind == TK_BRANCH) {
    emit_load_operand(out, state, locs, 0, block_term_op_ptr(block));
    emit_truth_branch(out, fn->name, block->yes, block->no, next_id);
  } else if (block->term_kind == TK_BRANCH_CMP) {
    emit_compare(out, state, locs, block_term_op_ptr(block), block_term_b_ptr(block));
    emit_compare_branch(out, fn->name, block->term_binop, block->yes, block->no, next_id);
  }
  emit_forget_rax(state);
}

static void emit_function(FILE *out, Function *fn)
{
  LocArray locs;
  EmitState state;
  int total_slots;
  int i;
  total_slots = allocate_function(fn, &locs);
  emit_state_init(&state);
  fprintf(out, ":FUNCTION_%s\n", fn->name);
  if (target_arch == TARGET_AARCH64) fprintf(out, "  PUSH_LR\n");
  if (total_slots > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  sub_esp, %%%d\n", total_slots * 4);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_sub_imm_reg(out, 18, total_slots * 8);
    else fprintf(out, "  HCC_SUB_IMMEDIATE_from_rsp %%%d\n", total_slots * 8);
  }
  i = 0;
  while (i < fn->len) {
    Block *block = block_at(fn->blocks, i);
    if (block->id != 0) {
      emit_forget_rax(&state);
      fprintf(out, ":");
      emit_block_ref(out, fn->name, block->id);
      fputc('\n', out);
    }
    emit_instrs(out, fn->name, &state, &locs, total_slots, block_instrs_ptr(block));
    emit_terminator(out, fn, i, &state, &locs, total_slots, block);
    i = i + 1;
  }
  fputc('\n', out);
#if !defined(__M2__)
  if (locs.items) free(locs.items);
#endif
}

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
    else die("unknown target");
    argi = 3;
  } else {
    argi = 1;
  }
  if (argc - argi != 2) {
    fputs("usage: hcc-m1 [--target amd64|i386|aarch64] INPUT.hccir OUTPUT.M1\n", stderr);
    return 2;
  }
  in = fopen(argv[argi], "r");
  if (!in) die("cannot open input");
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
