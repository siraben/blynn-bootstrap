/* mzvm - ZINC-style bytecode VM for the mini-OCaml bootstrap chain.
 *
 * See ccc/docs/mzbc.md for the locked .mzbc container layout and
 * instruction set. This file is written in a conservative C subset so the
 * seed split (mzvm-seed.c for M2-Planet) stays mechanical: while loops,
 * switch dispatch, no struct passing, no designated initializers.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef long word;
typedef unsigned long uword;

enum {
  OP_STOP = 0,
  OP_CONST = 1,
  OP_ACC = 2,
  OP_PUSH = 3,
  OP_POP = 4,
  OP_ASSIGN = 5,
  OP_ENVACC = 6,
  OP_CLOSURE = 7,
  OP_APPLY = 8,
  OP_APPTERM = 9,
  OP_RETURN = 10,
  OP_MAKEBLOCK = 11,
  OP_GETFIELD = 12,
  OP_SETFIELD = 13,
  OP_BRANCH = 14,
  OP_BRANCHIF = 15,
  OP_BRANCHIFNOT = 16,
  OP_SWITCH = 17,
  OP_ADDINT = 18,
  OP_SUBINT = 19,
  OP_MULINT = 20,
  OP_DIVINT = 21,
  OP_MODINT = 22,
  OP_ANDINT = 23,
  OP_ORINT = 24,
  OP_XORINT = 25,
  OP_LSLINT = 26,
  OP_LSRINT = 27,
  OP_ASRINT = 28,
  OP_NEGINT = 29,
  OP_BOOLNOT = 30,
  OP_EQ = 31,
  OP_NEQ = 32,
  OP_LTINT = 33,
  OP_LEINT = 34,
  OP_GTINT = 35,
  OP_GEINT = 36,
  OP_ULTINT = 37,
  OP_UGEINT = 38,
  OP_OFFSETINT = 39,
  OP_VECTLENGTH = 40,
  OP_GETVECTITEM = 41,
  OP_SETVECTITEM = 42,
  OP_GETBYTES = 43,
  OP_SETBYTES = 44,
  OP_GETGLOBAL = 45,
  OP_SETGLOBAL = 46,
  OP_CCALL = 47
};

enum {
  PRIM_EXIT = 0,
  PRIM_OPEN_IN = 1,
  PRIM_OPEN_OUT = 2,
  PRIM_CLOSE_CHAN = 3,
  PRIM_READ_BYTE = 4,
  PRIM_WRITE_BYTE = 5,
  PRIM_BYTES_CREATE = 6,
  PRIM_BYTES_LENGTH = 7,
  PRIM_ARG_COUNT = 8,
  PRIM_ARG_GET = 9
};

enum {
  NPRIMS = 10,
  TAG_CLOSURE = 250,
  TAG_BYTES = 251,
  TAG_FWD = 255,
  MZBC_VERSION = 1,
  NCHANS = 256
};

enum {
  DEFAULT_HEAP_WORDS = 8388608,  /* 1 << 23 per semispace */
  STACK_WORDS = 1048576,         /* 1 << 20 */
  RET_SLOTS = 524288             /* 1 << 19 */
};

/* ---- machine state ---- */

static word *code;
static word codelen;
static word nglobals;
static word *globals;

static word *stack;
static word sp;
static word *ret_pc;
static word *ret_env;
static word rsp;

static word acc;
static word env;
static word pc;

static word heap_words;
static word *space_a;
static word *space_b;
static word *alloc_ptr;
static word *alloc_end;
static word *from_start;
static word *to_start;

static FILE **chans;

static int vm_argc;
static char **vm_argv;

/* ---- diagnostics ---- */

static void print_err(char *s) {
  fputs(s, stderr);
}

static void print_err_int(word n) {
  char buf[32];
  int i;
  uword u;
  i = 31;
  buf[i] = 0;
  if (n < 0) {
    fputc('-', stderr);
    u = 0 - ((uword)n);
  } else {
    u = (uword)n;
  }
  if (u == 0) {
    i = i - 1;
    buf[i] = '0';
  }
  while (u != 0) {
    i = i - 1;
    buf[i] = (char)('0' + (u % 10));
    u = u / 10;
  }
  fputs(buf + i, stderr);
}

static void die(char *msg) {
  print_err("mzvm: ");
  print_err(msg);
  print_err(" at pc=");
  print_err_int(pc);
  print_err("\n");
  exit(2);
}

/* ---- value layout ---- */

static word mkint(word n) {
  return (word)((((uword)n) << 1) | 1);
}

static word untag(word v) {
  return v >> 1;
}

static word is_int(word v) {
  return v & 1;
}

static word block_header(word v) {
  word *p = (word *)v;
  return p[-1];
}

static word block_tag(word v) {
  return block_header(v) & 255;
}

static word block_wosize(word v) {
  return (word)(((uword)block_header(v)) >> 8);
}

static word block_field(word v, word i) {
  word *p = (word *)v;
  return p[i];
}

static void block_set_field(word v, word i, word x) {
  word *p = (word *)v;
  p[i] = x;
}

static char *bytes_data(word v) {
  word *p = (word *)v;
  return (char *)(p + 1);
}

static word bytes_len(word v) {
  return block_field(v, 0);
}

/* ---- garbage collection (Cheney) ---- */

static word gc_copy(word v) {
  word *p;
  word hdr;
  word wosize;
  word *np;
  word i;
  word nv;
  if (v & 1) {
    return v;
  }
  if (v == 0) {
    return v;
  }
  p = (word *)v;
  hdr = p[-1];
  if ((hdr & 255) == TAG_FWD) {
    return p[0];
  }
  wosize = (word)(((uword)hdr) >> 8);
  np = alloc_ptr;
  alloc_ptr = alloc_ptr + wosize + 1;
  np[0] = hdr;
  i = 0;
  while (i < wosize) {
    np[i + 1] = p[i];
    i = i + 1;
  }
  nv = (word)(np + 1);
  p[-1] = TAG_FWD;
  p[0] = nv;
  return nv;
}

static void gc(void) {
  word *tmp;
  word *scan;
  word i;
  word hdr;
  word wosize;
  word tag;
  tmp = from_start;
  from_start = to_start;
  to_start = tmp;
  alloc_ptr = from_start;
  alloc_end = from_start + heap_words;

  acc = gc_copy(acc);
  env = gc_copy(env);
  i = 0;
  while (i < nglobals) {
    globals[i] = gc_copy(globals[i]);
    i = i + 1;
  }
  i = 0;
  while (i < sp) {
    stack[i] = gc_copy(stack[i]);
    i = i + 1;
  }
  i = 0;
  while (i < rsp) {
    ret_env[i] = gc_copy(ret_env[i]);
    i = i + 1;
  }

  scan = from_start;
  while (scan < alloc_ptr) {
    hdr = scan[0];
    wosize = (word)(((uword)hdr) >> 8);
    tag = hdr & 255;
    if (tag < TAG_BYTES) {
      i = 0;
      while (i < wosize) {
        scan[i + 1] = gc_copy(scan[i + 1]);
        i = i + 1;
      }
    }
    scan = scan + wosize + 1;
  }
}

static word alloc_block(word wosize, word tag) {
  word *p;
  if (alloc_ptr + wosize + 1 > alloc_end) {
    gc();
    if (alloc_ptr + wosize + 1 > alloc_end) {
      die("heap overflow");
    }
  }
  p = alloc_ptr;
  alloc_ptr = alloc_ptr + wosize + 1;
  p[0] = (word)((((uword)wosize) << 8) | (uword)tag);
  return (word)(p + 1);
}

static word alloc_bytes(word len) {
  word wosize;
  word v;
  word i;
  word nwords;
  if (len < 0) {
    die("bytes_create: negative length");
  }
  nwords = (len + (word)sizeof(word) - 1) / (word)sizeof(word);
  wosize = nwords + 1;
  v = alloc_block(wosize, TAG_BYTES);
  block_set_field(v, 0, len);
  i = 0;
  while (i < nwords) {
    block_set_field(v, i + 1, 0);
    i = i + 1;
  }
  return v;
}

static word bytes_of_cstr(char *s) {
  word len;
  word v;
  len = (word)strlen(s);
  v = alloc_bytes(len);
  memcpy(bytes_data(v), s, (size_t)len);
  return v;
}

/* ---- stack helpers ---- */

static void push(word v) {
  if (sp >= STACK_WORDS) {
    die("stack overflow");
  }
  stack[sp] = v;
  sp = sp + 1;
}

static word pop(void) {
  if (sp <= 0) {
    die("stack underflow");
  }
  sp = sp - 1;
  return stack[sp];
}

/* ---- primitives ---- */

static char *chan_path_buf(word b) {
  /* NUL-terminate a copy of a bytes value for fopen. */
  static char buf[4096];
  word len;
  len = bytes_len(b);
  if (len >= 4096) {
    die("path too long");
  }
  memcpy(buf, bytes_data(b), (size_t)len);
  buf[len] = 0;
  return buf;
}

static word find_chan_slot(void) {
  word i;
  i = 3;
  while (i < NCHANS) {
    if (chans[i] == NULL) {
      return i;
    }
    i = i + 1;
  }
  die("out of channel slots");
  return -1;
}

static word prim_arity(word prim) {
  if (prim == PRIM_ARG_COUNT) {
    return 0;
  }
  if (prim == PRIM_WRITE_BYTE) {
    return 2;
  }
  return 1;
}

static word do_prim(word prim, word nargs, word *args) {
  word h;
  word slot;
  FILE *f;
  int c;
  word i;
  if (prim < 0 || prim >= NPRIMS) {
    die("unknown primitive");
  }
  if (nargs != prim_arity(prim)) {
    die("primitive arity mismatch");
  }
  if (prim == PRIM_EXIT) {
    exit((int)untag(args[0]));
  }
  if (prim == PRIM_OPEN_IN) {
    f = fopen(chan_path_buf(args[0]), "rb");
    if (f == NULL) {
      return mkint(-1);
    }
    slot = find_chan_slot();
    chans[slot] = f;
    return mkint(slot);
  }
  if (prim == PRIM_OPEN_OUT) {
    f = fopen(chan_path_buf(args[0]), "wb");
    if (f == NULL) {
      return mkint(-1);
    }
    slot = find_chan_slot();
    chans[slot] = f;
    return mkint(slot);
  }
  if (prim == PRIM_CLOSE_CHAN) {
    h = untag(args[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      die("close_chan: bad handle");
    }
    if (h > 2) {
      fclose(chans[h]);
      chans[h] = NULL;
    }
    return mkint(0);
  }
  if (prim == PRIM_READ_BYTE) {
    h = untag(args[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      die("read_byte: bad handle");
    }
    c = fgetc(chans[h]);
    if (c == EOF) {
      return mkint(-1);
    }
    return mkint(c & 255);
  }
  if (prim == PRIM_WRITE_BYTE) {
    h = untag(args[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      die("write_byte: bad handle");
    }
    fputc((int)(untag(args[1]) & 255), chans[h]);
    return mkint(0);
  }
  if (prim == PRIM_BYTES_CREATE) {
    return alloc_bytes(untag(args[0]));
  }
  if (prim == PRIM_BYTES_LENGTH) {
    return mkint(bytes_len(args[0]));
  }
  if (prim == PRIM_ARG_COUNT) {
    return mkint(vm_argc);
  }
  if (prim == PRIM_ARG_GET) {
    i = untag(args[0]);
    if (i < 0 || i >= vm_argc) {
      die("arg_get: out of range");
    }
    return bytes_of_cstr(vm_argv[i]);
  }
  die("unknown primitive");
  return 0;
}

/* ---- loader ---- */

static word read_u32(FILE *f, char *what) {
  int b0;
  int b1;
  int b2;
  int b3;
  b0 = fgetc(f);
  b1 = fgetc(f);
  b2 = fgetc(f);
  b3 = fgetc(f);
  if (b3 == EOF) {
    print_err("mzvm: truncated file reading ");
    print_err(what);
    print_err("\n");
    exit(2);
  }
  return (word)b0 + ((word)b1 << 8) + ((word)b2 << 16) + ((word)b3 << 24);
}

static word read_i32(FILE *f, char *what) {
  word v;
  v = read_u32(f, what);
  if (v > 2147483647) {
    v = v - 4294967296;
  }
  return v;
}

static void load_file(char *path) {
  FILE *f;
  word version;
  word primcount;
  word datacount;
  word i;
  word len;
  word g;
  word n;
  int c;
  f = fopen(path, "rb");
  if (f == NULL) {
    print_err("mzvm: cannot open ");
    print_err(path);
    print_err("\n");
    exit(2);
  }
  if (fgetc(f) != 'M' || fgetc(f) != 'Z' || fgetc(f) != 'B' || fgetc(f) != 'C') {
    print_err("mzvm: bad magic\n");
    exit(2);
  }
  version = read_u32(f, "version");
  if (version != MZBC_VERSION) {
    print_err("mzvm: unsupported version\n");
    exit(2);
  }
  codelen = read_u32(f, "codelen");
  primcount = read_u32(f, "primcount");
  if (primcount != NPRIMS) {
    print_err("mzvm: primitive table mismatch\n");
    exit(2);
  }
  nglobals = read_u32(f, "globalcount");
  datacount = read_u32(f, "datacount");
  if (datacount > nglobals) {
    print_err("mzvm: datacount exceeds globalcount\n");
    exit(2);
  }
  code = calloc((size_t)(codelen + 1), sizeof(word));
  if (code == NULL) {
    print_err("mzvm: out of memory\n");
    exit(2);
  }
  i = 0;
  while (i < codelen) {
    code[i] = read_i32(f, "code");
    i = i + 1;
  }
  globals = calloc((size_t)(nglobals + 1), sizeof(word));
  if (globals == NULL) {
    print_err("mzvm: out of memory\n");
    exit(2);
  }
  i = 0;
  while (i < nglobals) {
    globals[i] = mkint(0);
    i = i + 1;
  }
  i = 0;
  while (i < datacount) {
    len = read_u32(f, "data length");
    g = alloc_bytes(len);
    n = 0;
    while (n < len) {
      c = fgetc(f);
      if (c == EOF) {
        print_err("mzvm: truncated data record\n");
        exit(2);
      }
      bytes_data(g)[n] = (char)c;
      n = n + 1;
    }
    globals[i] = g;
    i = i + 1;
  }
  fclose(f);
}

/* ---- interpreter ---- */

static void check_code_addr(word a) {
  if (a < 0 || a >= codelen) {
    die("branch out of code");
  }
}

static word run(void) {
  word op;
  word n;
  word s;
  word t;
  word v;
  word i;
  word left;
  word ni;
  word nt;
  uword ul;
  uword ur;
  while (1) {
    if (pc < 0 || pc >= codelen) {
      die("pc out of code");
    }
    op = code[pc];
    pc = pc + 1;
    switch (op) {
    case OP_STOP:
      return untag(acc);
    case OP_CONST:
      acc = mkint(code[pc]);
      pc = pc + 1;
      break;
    case OP_ACC:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n >= sp) {
        die("ACC out of stack");
      }
      acc = stack[sp - 1 - n];
      break;
    case OP_PUSH:
      push(acc);
      break;
    case OP_POP:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n > sp) {
        die("POP out of stack");
      }
      sp = sp - n;
      break;
    case OP_ASSIGN:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n >= sp) {
        die("ASSIGN out of stack");
      }
      stack[sp - 1 - n] = acc;
      acc = mkint(0);
      break;
    case OP_ENVACC:
      n = code[pc];
      pc = pc + 1;
      if (env == 0 || is_int(env)) {
        die("ENVACC outside closure");
      }
      acc = block_field(env, n);
      break;
    case OP_CLOSURE:
      t = code[pc];
      n = code[pc + 1];
      pc = pc + 2;
      check_code_addr(t);
      v = alloc_block(n + 1, TAG_CLOSURE);
      block_set_field(v, 0, mkint(t));
      i = 0;
      while (i < n) {
        block_set_field(v, i + 1, stack[sp - n + i]);
        i = i + 1;
      }
      sp = sp - n;
      acc = v;
      break;
    case OP_APPLY:
      n = code[pc];
      pc = pc + 1;
      if (is_int(acc) || block_tag(acc) != TAG_CLOSURE) {
        die("APPLY of non-closure");
      }
      if (rsp >= RET_SLOTS) {
        die("return stack overflow");
      }
      ret_pc[rsp] = pc;
      ret_env[rsp] = env;
      rsp = rsp + 1;
      env = acc;
      pc = untag(block_field(acc, 0));
      break;
    case OP_APPTERM:
      n = code[pc];
      s = code[pc + 1];
      pc = pc + 2;
      if (is_int(acc) || block_tag(acc) != TAG_CLOSURE) {
        die("APPTERM of non-closure");
      }
      if (s < 0 || n < 0 || sp - n - s < 0) {
        die("APPTERM out of stack");
      }
      i = 0;
      while (i < n) {
        stack[sp - n - s + i] = stack[sp - n + i];
        i = i + 1;
      }
      sp = sp - s;
      env = acc;
      pc = untag(block_field(acc, 0));
      break;
    case OP_RETURN:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n > sp) {
        die("RETURN out of stack");
      }
      sp = sp - n;
      if (rsp <= 0) {
        die("RETURN with empty return stack");
      }
      rsp = rsp - 1;
      pc = ret_pc[rsp];
      env = ret_env[rsp];
      break;
    case OP_MAKEBLOCK:
      t = code[pc];
      n = code[pc + 1];
      pc = pc + 2;
      if (n < 1 || t < 0 || t >= TAG_CLOSURE) {
        die("MAKEBLOCK bad operands");
      }
      if (n > sp) {
        die("MAKEBLOCK out of stack");
      }
      v = alloc_block(n, t);
      i = 0;
      while (i < n) {
        block_set_field(v, i, stack[sp - n + i]);
        i = i + 1;
      }
      sp = sp - n;
      acc = v;
      break;
    case OP_GETFIELD:
      n = code[pc];
      pc = pc + 1;
      if (is_int(acc)) {
        die("GETFIELD of integer");
      }
      acc = block_field(acc, n);
      break;
    case OP_SETFIELD:
      n = code[pc];
      pc = pc + 1;
      v = pop();
      if (is_int(v)) {
        die("SETFIELD of integer");
      }
      block_set_field(v, n, acc);
      acc = mkint(0);
      break;
    case OP_BRANCH:
      t = code[pc];
      check_code_addr(t);
      pc = t;
      break;
    case OP_BRANCHIF:
      t = code[pc];
      pc = pc + 1;
      if (acc != mkint(0)) {
        check_code_addr(t);
        pc = t;
      }
      break;
    case OP_BRANCHIFNOT:
      t = code[pc];
      pc = pc + 1;
      if (acc == mkint(0)) {
        check_code_addr(t);
        pc = t;
      }
      break;
    case OP_SWITCH:
      ni = code[pc];
      nt = code[pc + 1];
      if (is_int(acc)) {
        v = untag(acc);
        if (v < 0 || v >= ni) {
          die("SWITCH int out of range");
        }
        t = code[pc + 2 + v];
      } else {
        v = block_tag(acc);
        if (v < 0 || v >= nt) {
          die("SWITCH tag out of range");
        }
        t = code[pc + 2 + ni + v];
      }
      check_code_addr(t);
      pc = t;
      break;
    case OP_ADDINT:
      left = pop();
      acc = mkint(untag(left) + untag(acc));
      break;
    case OP_SUBINT:
      left = pop();
      acc = mkint(untag(left) - untag(acc));
      break;
    case OP_MULINT:
      left = pop();
      acc = mkint(untag(left) * untag(acc));
      break;
    case OP_DIVINT:
      left = pop();
      if (untag(acc) == 0) {
        die("division by zero");
      }
      acc = mkint(untag(left) / untag(acc));
      break;
    case OP_MODINT:
      left = pop();
      if (untag(acc) == 0) {
        die("division by zero");
      }
      acc = mkint(untag(left) % untag(acc));
      break;
    case OP_ANDINT:
      left = pop();
      acc = mkint(untag(left) & untag(acc));
      break;
    case OP_ORINT:
      left = pop();
      acc = mkint(untag(left) | untag(acc));
      break;
    case OP_XORINT:
      left = pop();
      acc = mkint(untag(left) ^ untag(acc));
      break;
    case OP_LSLINT:
      left = pop();
      acc = mkint((word)(((uword)untag(left)) << untag(acc)));
      break;
    case OP_LSRINT:
      left = pop();
      acc = mkint((word)(((uword)untag(left)) >> untag(acc)));
      break;
    case OP_ASRINT:
      left = pop();
      acc = mkint(untag(left) >> untag(acc));
      break;
    case OP_NEGINT:
      acc = mkint(0 - untag(acc));
      break;
    case OP_BOOLNOT:
      if (acc == mkint(0)) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_EQ:
      left = pop();
      if (left == acc) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_NEQ:
      left = pop();
      if (left != acc) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_LTINT:
      left = pop();
      if (untag(left) < untag(acc)) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_LEINT:
      left = pop();
      if (untag(left) <= untag(acc)) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_GTINT:
      left = pop();
      if (untag(left) > untag(acc)) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_GEINT:
      left = pop();
      if (untag(left) >= untag(acc)) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_ULTINT:
      left = pop();
      ul = (uword)untag(left);
      ur = (uword)untag(acc);
      if (ul < ur) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_UGEINT:
      left = pop();
      ul = (uword)untag(left);
      ur = (uword)untag(acc);
      if (ul >= ur) {
        acc = mkint(1);
      } else {
        acc = mkint(0);
      }
      break;
    case OP_OFFSETINT:
      n = code[pc];
      pc = pc + 1;
      acc = mkint(untag(acc) + n);
      break;
    case OP_VECTLENGTH:
      if (is_int(acc)) {
        die("VECTLENGTH of integer");
      }
      acc = mkint(block_wosize(acc));
      break;
    case OP_GETVECTITEM:
      v = pop();
      if (is_int(v)) {
        die("GETVECTITEM of integer");
      }
      i = untag(acc);
      if (i < 0 || i >= block_wosize(v)) {
        die("array index out of bounds");
      }
      acc = block_field(v, i);
      break;
    case OP_SETVECTITEM:
      i = untag(pop());
      v = pop();
      if (is_int(v)) {
        die("SETVECTITEM of integer");
      }
      if (i < 0 || i >= block_wosize(v)) {
        die("array index out of bounds");
      }
      block_set_field(v, i, acc);
      acc = mkint(0);
      break;
    case OP_GETBYTES:
      v = pop();
      if (is_int(v) || block_tag(v) != TAG_BYTES) {
        die("GETBYTES of non-bytes");
      }
      i = untag(acc);
      if (i < 0 || i >= bytes_len(v)) {
        die("bytes index out of bounds");
      }
      acc = mkint(255 & (word)(unsigned char)bytes_data(v)[i]);
      break;
    case OP_SETBYTES:
      i = untag(pop());
      v = pop();
      if (is_int(v) || block_tag(v) != TAG_BYTES) {
        die("SETBYTES of non-bytes");
      }
      if (i < 0 || i >= bytes_len(v)) {
        die("bytes index out of bounds");
      }
      bytes_data(v)[i] = (char)(untag(acc) & 255);
      acc = mkint(0);
      break;
    case OP_GETGLOBAL:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n >= nglobals) {
        die("GETGLOBAL out of range");
      }
      acc = globals[n];
      break;
    case OP_SETGLOBAL:
      n = code[pc];
      pc = pc + 1;
      if (n < 0 || n >= nglobals) {
        die("SETGLOBAL out of range");
      }
      globals[n] = acc;
      acc = mkint(0);
      break;
    case OP_CCALL:
      n = code[pc];
      t = code[pc + 1];
      pc = pc + 2;
      if (n < 0 || n > sp) {
        die("CCALL out of stack");
      }
      acc = do_prim(t, n, stack + sp - n);
      sp = sp - n;
      break;
    default:
      die("unknown opcode");
    }
  }
}

int main(int argc, char **argv) {
  char *heap_env;
  word i;
  if (argc < 2) {
    print_err("usage: mzvm file.mzbc [args...]\n");
    return 2;
  }
  heap_words = DEFAULT_HEAP_WORDS;
  heap_env = getenv("MZVM_HEAP_WORDS");
  if (heap_env != NULL) {
    heap_words = atol(heap_env);
    if (heap_words < 4096) {
      heap_words = 4096;
    }
  }
  space_a = calloc((size_t)heap_words, sizeof(word));
  space_b = calloc((size_t)heap_words, sizeof(word));
  stack = calloc(STACK_WORDS, sizeof(word));
  ret_pc = calloc(RET_SLOTS, sizeof(word));
  ret_env = calloc(RET_SLOTS, sizeof(word));
  chans = calloc(NCHANS, sizeof(FILE *));
  if (space_a == NULL || space_b == NULL || stack == NULL || ret_pc == NULL ||
      ret_env == NULL || chans == NULL) {
    print_err("mzvm: out of memory\n");
    return 2;
  }
  from_start = space_a;
  to_start = space_b;
  alloc_ptr = from_start;
  alloc_end = from_start + heap_words;
  chans[0] = stdin;
  chans[1] = stdout;
  chans[2] = stderr;
  vm_argc = argc - 2;
  vm_argv = argv + 2;
  acc = mkint(0);
  env = 0;
  sp = 0;
  rsp = 0;
  pc = 0;
  load_file(argv[1]);
  i = (word)run();
  fflush(stdout);
  return (int)i;
}
