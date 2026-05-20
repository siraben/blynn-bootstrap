#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef MZVM_HEAP_LIMIT
#define MZVM_HEAP_LIMIT 2097152
#endif

#ifndef MZVM_STACK_CAP
#define MZVM_STACK_CAP 2097152
#endif

enum {
  MZBC_VERSION = 1,
  STACK_CAP = MZVM_STACK_CAP,

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
  OP_SETFIELD = 17,
  OP_GETTAG = 18,
  OP_NE = 19,
  OP_LE = 20,
  OP_GT = 21,
  OP_GE = 22,
  OP_CALL = 23,
  OP_RETURN = 24,
  OP_GETFIELD_DYN = 25,
  OP_SETFIELD_DYN = 26,
  OP_BLOCKSIZE = 27,
  OP_MAKEBLOCK_DYN = 28,
  OP_CLOSURE = 29,
  OP_APPLY = 30,
  OP_RETURN_FRAME = 31,
  OP_FUNCTION = 32,
  OP_CLOSURE_N = 33,
  OP_CLOSURE_SKIP = 34
};

typedef long value_t;

static char *code;
static long code_len;
static long pc;
static long last_pc;
static long current_op;
static value_t acc;
static value_t *stack;
static long *return_stack;
static long sp;
static long rp;
static long prim_count;
static long global_count;
static value_t *space_a;
static value_t *space_b;
static value_t *heap;
static value_t *reserve_heap;
static long heap_words;
static value_t *gc_from;
static value_t *gc_to;
static long gc_to_words;

static void fput_long(FILE *out, long n)
{
  char buf[32];
  long i;
  unsigned long value;
  if (n < 0) {
    fputc('-', out);
    value = (unsigned long)(0 - n);
  } else {
    value = (unsigned long)n;
  }
  i = 0;
  if (value == 0) {
    fputc('0', out);
    return;
  }
  while (value > 0) {
    buf[i] = (char)('0' + (value % 10));
    value = value / 10;
    i = i + 1;
  }
  while (i > 0) {
    i = i - 1;
    fputc(buf[i], out);
  }
}

static void die(const char *msg)
{
  fputs("mzvm: ", stderr);
  fputs(msg, stderr);
  fputs(" pc=", stderr);
  fput_long(stderr, last_pc);
  fputs(" op=", stderr);
  fput_long(stderr, current_op);
  fputs(" sp=", stderr);
  fput_long(stderr, sp);
  fputs(" rp=", stderr);
  fput_long(stderr, rp);
  fputs(" heap=", stderr);
  fput_long(stderr, heap_words);
  fputs("/", stderr);
  fput_long(stderr, MZVM_HEAP_LIMIT);
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

static value_t *block_val(value_t x)
{
  if ((x & 1) != 0) die("expected block");
  if (x == 0) die("null block");
  return (value_t *)x;
}

static value_t *space_word(value_t *base, long index)
{
  return (value_t *)((char *)base + index * sizeof(value_t));
}

static int ptr_in_space(value_t *ptr, value_t *base)
{
  unsigned long p = (unsigned long)ptr;
  unsigned long lo = (unsigned long)base;
  unsigned long hi = (unsigned long)space_word(base, MZVM_HEAP_LIMIT);
  return p >= lo && p < hi;
}

static value_t copy_value(value_t value)
{
  value_t *block;
  value_t *out;
  long size;
  long words;
  long i;
  if ((value & 1) != 0 || value == 0) return value;
  block = (value_t *)value;
  if (!ptr_in_space(block, gc_from)) return value;
  if (block[0] == -1) return block[1];
  size = block[1];
  if (size < 0) die("bad block during gc");
  words = 2 + size;
  if (gc_to_words + words > MZVM_HEAP_LIMIT) die("heap exhausted after gc");
  out = space_word(gc_to, gc_to_words);
  i = 0;
  while (i < words) {
    out[i] = block[i];
    i = i + 1;
  }
  gc_to_words = gc_to_words + words;
  block[0] = -1;
  block[1] = (value_t)out;
  return (value_t)out;
}

static void collect(long needed_words)
{
  value_t *old_heap;
  value_t *new_heap;
  long scan;
  long i;
  long size;
  if (needed_words > MZVM_HEAP_LIMIT) die("block too large");
  old_heap = heap;
  new_heap = reserve_heap;
  gc_from = old_heap;
  gc_to = new_heap;
  gc_to_words = 0;
  acc = copy_value(acc);
  i = 0;
  while (i < sp) {
    stack[i] = copy_value(stack[i]);
    i = i + 1;
  }
  scan = 0;
  while (scan < gc_to_words) {
    size = gc_to[scan + 1];
    i = 0;
    while (i < size) {
      gc_to[scan + 2 + i] = copy_value(gc_to[scan + 2 + i]);
      i = i + 1;
    }
    scan = scan + 2 + size;
  }
  heap = new_heap;
  reserve_heap = old_heap;
  heap_words = gc_to_words;
}

static void init_heap(void)
{
  space_a = (value_t *)malloc(sizeof(value_t) * MZVM_HEAP_LIMIT);
  space_b = (value_t *)malloc(sizeof(value_t) * MZVM_HEAP_LIMIT);
  if (!space_a || !space_b) die("out of memory");
  heap = space_a;
  reserve_heap = space_b;
  heap_words = 0;
}

static void init_stacks(void)
{
  stack = (value_t *)malloc(sizeof(value_t) * STACK_CAP);
  return_stack = (long *)malloc(sizeof(long) * STACK_CAP);
  if (!stack || !return_stack) die("out of memory");
}

static long byte_at(char *bytes, long off)
{
  return bytes[off] & 255;
}

static unsigned read_u8(void)
{
  long out;
  out = code[pc] & 255;
  pc = pc + 1;
  return (unsigned)out;
}

static long read_u32(void)
{
  long b0;
  long b1;
  long b2;
  long b3;
  b0 = code[pc] & 255;
  b1 = code[pc + 1] & 255;
  b2 = code[pc + 2] & 255;
  b3 = code[pc + 3] & 255;
  pc = pc + 4;
  return (long)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
}

static long read_s32(void)
{
  long b0;
  long b1;
  long b2;
  long b3;
  long u;
  long max = 2147483647;
  b0 = code[pc] & 255;
  b1 = code[pc + 1] & 255;
  b2 = code[pc + 2] & 255;
  b3 = code[pc + 3] & 255;
  pc = pc + 4;
  u = (long)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
  if (u > max) return (u - max) - max - 2;
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
  long index;
  if (n < 0 || n >= sp) die("stack access out of range");
  index = sp - 1 - n;
  return stack[index];
}

static void stack_drop(long n)
{
  if (n < 0 || n > sp) die("stack pop out of range");
  sp = sp - n;
}

static void return_push(long x)
{
  if (rp >= STACK_CAP) die("return stack overflow");
  return_stack[rp] = x;
  rp = rp + 1;
}

static long return_pop(void)
{
  if (rp <= 0) die("return stack underflow");
  rp = rp - 1;
  return return_stack[rp];
}

static value_t *alloc_block(long tag, long size)
{
  value_t *block;
  long words = 2 + size;
  if (size < 0) die("negative block size");
  if (heap_words + words > MZVM_HEAP_LIMIT) collect(words);
  if (heap_words + words > MZVM_HEAP_LIMIT) die("heap exhausted");
  block = space_word(heap, heap_words);
  block[0] = tag;
  block[1] = size;
  heap_words = heap_words + words;
  return block;
}

static void prim_write_byte(void)
{
  fputc((int)(int_val(acc) & 255), stdout);
  acc = val_int(0);
}

static void prim_debug_byte(void)
{
  fputc((int)(int_val(acc) & 255), stderr);
  acc = val_int(0);
}

static void prim_debug_int(void)
{
  fput_long(stderr, int_val(acc));
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
  else if (prim == 3) prim_debug_byte();
  else if (prim == 4) prim_debug_int();
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
    long raw_op;
    unsigned op;
    raw_op = code[pc] & 255;
    op = (unsigned)raw_op;
    pc = pc + 1;
    last_pc = pc - 1;
    current_op = op;
    /* Hot paths trust compiler-generated bytecode; loader and opcode checks stay explicit. */
    if (op == OP_PUSH) {
      stack[sp] = acc;
      sp = sp + 1;
    } else if (op == OP_ACC) {
      long n = read_u32();
      long index;
      index = sp - 1 - n;
      acc = stack[index];
    } else if (op == OP_CONST) {
      acc = val_int(read_s32());
    } else if (op == OP_POP) {
      long n = read_u32();
      sp = sp - n;
    } else if (op == OP_BRANCHIFNOT) {
      long offset = read_s32();
      if ((acc >> 1) == 0) {
        long target = pc + offset;
        pc = target;
      }
    } else if (op == OP_GETFIELD) {
      long index = read_u32();
      value_t *block;
      block = (value_t *)acc;
      acc = block[2 + index];
    } else if (op == OP_EQ) {
      value_t lhs;
      sp = sp - 1;
      lhs = stack[sp];
      acc = val_int(lhs == acc);
    } else if (op == OP_LE) {
      value_t lhs;
      sp = sp - 1;
      lhs = stack[sp];
      acc = val_int((lhs >> 1) <= (acc >> 1));
    } else if (op == OP_MAKEBLOCK) {
      long tag = read_u32();
      long size = read_u32();
      value_t *block = alloc_block(tag, size);
      long i = size - 1;
      if (size > 0) {
        block[2 + i] = acc;
        while (i > 0) {
          i = i - 1;
          block[2 + i] = stack_pop();
        }
      }
      acc = (value_t)block;
    } else if (op == OP_CALL) {
      long target = read_u32();
      return_stack[rp] = pc;
      rp = rp + 1;
      pc = target;
    } else if (op == OP_RETURN) {
      rp = rp - 1;
      pc = return_stack[rp];
    } else if (op == OP_BRANCH) {
      long offset = read_s32();
      long target = pc + offset;
      pc = target;
    } else if (op == OP_GETFIELD_DYN) {
      long index = acc >> 1;
      value_t block_value;
      value_t *block;
      sp = sp - 1;
      block_value = stack[sp];
      block = (value_t *)block_value;
      acc = block[2 + index];
    } else if (op == OP_ADDINT) {
      value_t lhs;
      sp = sp - 1;
      lhs = stack[sp];
      acc = val_int((lhs >> 1) + (acc >> 1));
    } else if (op == OP_LT) {
      value_t lhs;
      sp = sp - 1;
      lhs = stack[sp];
      acc = val_int((lhs >> 1) < (acc >> 1));
    } else if (op == OP_BLOCKSIZE) {
      value_t *block = block_val(acc);
      acc = val_int(block[1]);
    } else if (op == OP_C_CALL) {
      long argc = read_u32();
      long prim = read_u32();
      call_prim(argc, prim);
    } else if (op == OP_SETFIELD_DYN) {
      long index = int_val(stack_pop());
      value_t *block = block_val(stack_pop());
      if (index < 0 || index >= block[1]) die("field write out of range");
      block[2 + index] = acc;
      acc = val_int(0);
    } else if (op == OP_SUBINT) {
      acc = val_int(int_val(stack_pop()) - int_val(acc));
    } else if (op == OP_GE) {
      acc = val_int(int_val(stack_pop()) >= int_val(acc));
    } else if (op == OP_GT) {
      acc = val_int(int_val(stack_pop()) > int_val(acc));
    } else if (op == OP_MULINT) {
      acc = val_int(int_val(stack_pop()) * int_val(acc));
    } else if (op == OP_DIVINT) {
      long rhs = int_val(acc);
      if (rhs == 0) die("division by zero");
      acc = val_int(int_val(stack_pop()) / rhs);
    } else if (op == OP_MAKEBLOCK_DYN) {
      long tag = read_u32();
      long size = int_val(stack_pop());
      value_t *block;
      long i = 0;
      if (size < 0) die("negative block size");
      block = alloc_block(tag, size);
      while (i < size) {
        block[2 + i] = acc;
        i = i + 1;
      }
      acc = (value_t)block;
    } else if (op == OP_NE) {
      acc = val_int(stack_pop() != acc);
    } else if (op == OP_HALT) {
      running = 0;
    } else if (op == OP_CLOSURE) {
      long target = read_u32();
      value_t *block;
      long i;
      if (target < 0 || target >= code_len) die("closure target out of range");
      block = alloc_block(1, sp + 1);
      block[2] = val_int(target);
      i = 0;
      while (i < sp) {
        block[3 + i] = stack_acc(i);
        i = i + 1;
      }
      acc = (value_t)block;
    } else if (op == OP_FUNCTION) {
      long target = read_u32();
      value_t *block;
      if (target < 0 || target >= code_len) die("function target out of range");
      block = alloc_block(2, 1);
      block[2] = val_int(target);
      acc = (value_t)block;
    } else if (op == OP_CLOSURE_N) {
      long target = read_u32();
      long count = read_u32();
      value_t *block;
      long i;
      if (target < 0 || target >= code_len) die("closure target out of range");
      if (count < 0 || count > sp) die("closure capture out of range");
      block = alloc_block(1, count + 1);
      block[2] = val_int(target);
      i = 0;
      while (i < count) {
        block[3 + i] = stack_acc(i);
        i = i + 1;
      }
      acc = (value_t)block;
    } else if (op == OP_CLOSURE_SKIP) {
      long target = read_u32();
      long count = read_u32();
      long skip = read_u32();
      value_t *block;
      long i;
      if (target < 0 || target >= code_len) die("closure target out of range");
      if (count < 0 || skip < 0 || skip + count > sp) die("closure capture out of range");
      block = alloc_block(1, count + 1);
      block[2] = val_int(target);
      i = 0;
      while (i < count) {
        block[3 + i] = stack_acc(skip + i);
        i = i + 1;
      }
      acc = (value_t)block;
    } else if (op == OP_APPLY) {
      value_t arg = acc;
      value_t *closure = block_val(stack_pop());
      long tag = closure[0];
      long size = closure[1];
      long target;
      long i;
      if (size < 1) die("bad closure");
      target = int_val(closure[2]);
      if (target < 0 || target >= code_len) die("closure target out of range");
      if (tag == 2) {
        acc = arg;
        return_push(pc);
      } else {
        i = size - 1;
        while (i > 0) {
          stack_push(closure[2 + i]);
          i = i - 1;
        }
        stack_push(arg);
        return_push(pc);
        return_push(size);
      }
      pc = target;
    } else if (op == OP_RETURN_FRAME) {
      long frame = return_pop();
      stack_drop(frame);
      pc = return_pop();
    } else if (op == OP_BRANCHIF) {
      long offset = read_s32();
      if (truthy(acc)) branch_relative(offset);
    } else if (op == OP_SETFIELD) {
      long index = read_u32();
      value_t *block = block_val(stack_pop());
      if (index < 0 || index >= block[1]) die("field write out of range");
      block[2 + index] = acc;
      acc = val_int(0);
    } else if (op == OP_GETTAG) {
      value_t *block = block_val(acc);
      acc = val_int(block[0]);
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
  rp = 0;
  acc = val_int(0);
  init_stacks();
  init_heap();
  run();
  return 0;
}
