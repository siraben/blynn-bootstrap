#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
  MZBC_VERSION = 1,
  STACK_CAP = 65536,
  HEAP_LIMIT = 1048576,

  OP_HALT = 0,
  OP_CONST = 1,
  OP_PUSH = 2,
  OP_POP = 3,
  OP_ACC = 4,
  OP_ADDINT = 5,
  OP_SUBINT = 6,
  OP_MULINT = 7,
  OP_DIVINT = 8,
  OP_EQ = 9,
  OP_LT = 10,
  OP_BRANCH = 11,
  OP_BRANCHIF = 12,
  OP_BRANCHIFNOT = 13,
  OP_C_CALL = 14,
  OP_MAKEBLOCK = 15,
  OP_GETFIELD = 16,
  OP_SETFIELD = 17
};

typedef long value_t;

struct Block {
  long tag;
  long size;
  value_t field[1];
};

static char *code;
static long code_len;
static long pc;
static value_t acc;
static value_t stack[STACK_CAP];
static long sp;
static long prim_count;
static long global_count;
static long heap_words;

static void die(const char *msg)
{
  fputs("mzvm: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

static value_t val_int(long x)
{
  return (x << 1) | 1;
}

static long int_val(value_t x)
{
  if ((x & 1) == 0) die("expected int");
  return x >> 1;
}

static struct Block *block_val(value_t x)
{
  if ((x & 1) != 0) die("expected block");
  if (x == 0) die("null block");
  return (struct Block *)x;
}

static long byte_at(char *bytes, long off)
{
  long out = bytes[off];
  if (out < 0) out = out + 256;
  return out;
}

static unsigned read_u8(void)
{
  long out;
  if (pc >= code_len) die("truncated instruction");
  pc = pc + 1;
  out = byte_at(code, pc - 1);
  return (unsigned)out;
}

static long read_u32(void)
{
  unsigned long b0 = read_u8();
  unsigned long b1 = read_u8();
  unsigned long b2 = read_u8();
  unsigned long b3 = read_u8();
  return (long)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
}

static long read_s32(void)
{
  unsigned long u = (unsigned long)read_u32();
  if (u >= 2147483648UL) return (long)(u - 4294967296UL);
  return (long)u;
}

static long file_u32(char *bytes, long off)
{
  long b0 = byte_at(bytes, off);
  long b1 = byte_at(bytes, off + 1);
  long b2 = byte_at(bytes, off + 2);
  long b3 = byte_at(bytes, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

static void stack_push(value_t x)
{
  if (sp >= STACK_CAP) die("stack overflow");
  stack[sp] = x;
  sp = sp + 1;
}

static value_t stack_pop(void)
{
  if (sp <= 0) die("stack underflow");
  sp = sp - 1;
  return stack[sp];
}

static value_t stack_acc(long n)
{
  if (n < 0 || n >= sp) die("stack access out of range");
  return stack[sp - 1 - n];
}

static void stack_drop(long n)
{
  if (n < 0 || n > sp) die("stack pop out of range");
  sp = sp - n;
}

static struct Block *alloc_block(long tag, long size)
{
  struct Block *block;
  long words = 2 + size;
  if (size < 0) die("negative block size");
  if (heap_words + words > HEAP_LIMIT) die("heap exhausted");
  block = (struct Block *)malloc(sizeof(struct Block) + sizeof(value_t) * size);
  if (!block) die("out of memory");
  block->tag = tag;
  block->size = size;
  heap_words = heap_words + words;
  return block;
}

static void prim_write_byte(void)
{
  fputc((int)(int_val(acc) & 255), stdout);
  acc = val_int(0);
}

static void prim_exit(void)
{
  exit((int)int_val(acc));
}

static void prim_read_byte(void)
{
  int c = fgetc(stdin);
  if (c == EOF) acc = val_int(-1);
  else acc = val_int(c);
}

static void call_prim(long argc, long prim)
{
  if (argc != 1) die("only one-argument primitives are implemented");
  if (prim >= prim_count) die("primitive index out of bytecode range");
  if (prim == 0) prim_read_byte();
  else if (prim == 1) prim_write_byte();
  else if (prim == 2) prim_exit();
  else die("unknown primitive");
}

static int truthy(value_t x)
{
  return int_val(x) != 0;
}

static void branch_relative(long offset)
{
  long target = pc + offset;
  if (target < 0 || target > code_len) die("branch target out of range");
  pc = target;
}

static void run(void)
{
  int running = 1;
  while (running) {
    unsigned op = read_u8();
    if (op == OP_HALT) {
      running = 0;
    } else if (op == OP_CONST) {
      acc = val_int(read_s32());
    } else if (op == OP_PUSH) {
      stack_push(acc);
    } else if (op == OP_POP) {
      stack_drop(read_u32());
    } else if (op == OP_ACC) {
      acc = stack_acc(read_u32());
    } else if (op == OP_ADDINT) {
      acc = val_int(int_val(stack_pop()) + int_val(acc));
    } else if (op == OP_SUBINT) {
      acc = val_int(int_val(stack_pop()) - int_val(acc));
    } else if (op == OP_MULINT) {
      acc = val_int(int_val(stack_pop()) * int_val(acc));
    } else if (op == OP_DIVINT) {
      long rhs = int_val(acc);
      if (rhs == 0) die("division by zero");
      acc = val_int(int_val(stack_pop()) / rhs);
    } else if (op == OP_EQ) {
      acc = val_int(stack_pop() == acc);
    } else if (op == OP_LT) {
      acc = val_int(int_val(stack_pop()) < int_val(acc));
    } else if (op == OP_BRANCH) {
      branch_relative(read_s32());
    } else if (op == OP_BRANCHIF) {
      long offset = read_s32();
      if (truthy(acc)) branch_relative(offset);
    } else if (op == OP_BRANCHIFNOT) {
      long offset = read_s32();
      if (!truthy(acc)) branch_relative(offset);
    } else if (op == OP_C_CALL) {
      long argc = read_u32();
      long prim = read_u32();
      call_prim(argc, prim);
    } else if (op == OP_MAKEBLOCK) {
      long tag = read_u32();
      long size = read_u32();
      struct Block *block = alloc_block(tag, size);
      long i = size - 1;
      if (size > 0) {
        block->field[0] = acc;
        while (i > 0) {
          block->field[i] = stack_pop();
          i = i - 1;
        }
      }
      acc = (value_t)block;
    } else if (op == OP_GETFIELD) {
      long index = read_u32();
      struct Block *block = block_val(acc);
      if (index < 0 || index >= block->size) die("field access out of range");
      acc = block->field[index];
    } else if (op == OP_SETFIELD) {
      long index = read_u32();
      struct Block *block = block_val(stack_pop());
      if (index < 0 || index >= block->size) die("field write out of range");
      block->field[index] = acc;
      acc = val_int(0);
    } else {
      die("unknown opcode");
    }
  }
}

static char *read_file(const char *path, long *len_out)
{
  FILE *file = fopen(path, "rb");
  char *buf = 0;
  long len = 0;
  long cap = 0;
  int c;
  if (!file) die("cannot open bytecode file");
  c = fgetc(file);
  while (c != EOF) {
    if (len == cap) {
      char *next;
      if (cap == 0) cap = 4096;
      else cap = cap * 2;
      next = (char *)realloc(buf, cap);
      if (!next) die("out of memory");
      buf = next;
    }
    buf[len] = (char)c;
    len = len + 1;
    c = fgetc(file);
  }
  fclose(file);
  *len_out = len;
  return buf;
}

static void load_bytecode(const char *path)
{
  long file_len;
  char *bytes = read_file(path, &file_len);
  if (file_len < 20) die("bytecode header is truncated");
  if (bytes[0] != 'M' || bytes[1] != 'Z' || bytes[2] != 'B' || bytes[3] != 'C') {
    die("bad bytecode magic");
  }
  if (file_u32(bytes, 4) != MZBC_VERSION) die("unsupported bytecode version");
  code_len = file_u32(bytes, 8);
  prim_count = file_u32(bytes, 12);
  global_count = file_u32(bytes, 16);
  if (code_len < 0) die("negative code length");
  if (file_len != 20 + code_len) die("bytecode length mismatch");
  code = (char *)malloc(code_len);
  if (!code) die("out of memory");
  memcpy(code, bytes + 20, code_len);
  free(bytes);
}

int main(int argc, char **argv)
{
  if (argc != 2) {
    fputs("usage: mzvm-seed FILE.mzbc\n", stderr);
    return 2;
  }
  load_bytecode(argv[1]);
  pc = 0;
  sp = 0;
  acc = val_int(0);
  run();
  return 0;
}
