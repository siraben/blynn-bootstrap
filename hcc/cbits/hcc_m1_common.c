static int is_label_char(int c)
{
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static void set_label_namespace(const char *path)
{
  int i = 0;
  int out = 0;
  int start = 0;
  while (path[i]) {
    if (path[i] == '/') start = i + 1;
    i = i + 1;
  }
  i = start;
  while (path[i] && out < 120) {
    if (is_label_char((unsigned char)path[i])) riscv64_label_namespace_buf[out] = path[i];
    else riscv64_label_namespace_buf[out] = '_';
    out = out + 1;
    i = i + 1;
  }
  if (out == 0) {
    riscv64_label_namespace_buf[out] = 'o';
    out = out + 1;
  }
  riscv64_label_namespace_buf[out] = 0;
  riscv64_label_namespace = riscv64_label_namespace_buf;
}

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
