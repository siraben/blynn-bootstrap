#include <stdio.h>
#include <stdlib.h>

enum {
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
  OP_RETURN = 24
};

static FILE *out_file;
static long out_len;
static char *src;
static long src_len;
static long pos;
static long env_start[64];
static long env_len[64];
static long env_level[64];
static long env_depth;
static long stack_depth;
static long ctor_start[64];
static long ctor_len[64];
static long ctor_tag[64];
static long ctor_arity[64];
static long ctor_count;
static long func_start[64];
static long func_len[64];
static long func_target[64];
static long func_count;

static void die(const char *msg)
{
  fputs("mlc-seed: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

static char *read_file(const char *path, long *len_out)
{
  FILE *file = fopen(path, "rb");
  char *buf = 0;
  long len = 0;
  long cap = 0;
  int c;
  if (!file) die("cannot open input file");
  c = fgetc(file);
  while (c != EOF) {
    if (len == cap) {
      char *next;
      if (cap == 0) cap = 4096;
      else cap = cap * 2;
      next = (char *)realloc(buf, cap + 1);
      if (!next) die("out of memory");
      buf = next;
    }
    buf[len] = (char)c;
    len = len + 1;
    c = fgetc(file);
  }
  fclose(file);
  if (buf == 0) {
    buf = (char *)malloc(1);
    if (!buf) die("out of memory");
  }
  buf[len] = 0;
  *len_out = len;
  return buf;
}

static int is_space(int c)
{
  return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

static int is_ident_char(int c)
{
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static int at_comment_start(void)
{
  return pos + 1 < src_len && src[pos] == '(' && src[pos + 1] == '*';
}

static void skip_comment(void)
{
  long depth = 1;
  pos = pos + 2;
  while (pos < src_len && depth > 0) {
    if (pos + 1 < src_len && src[pos] == '(' && src[pos + 1] == '*') {
      depth = depth + 1;
      pos = pos + 2;
    } else if (pos + 1 < src_len && src[pos] == '*' && src[pos + 1] == ')') {
      depth = depth - 1;
      pos = pos + 2;
    } else {
      pos = pos + 1;
    }
  }
  if (depth != 0) die("unterminated comment");
}

static void skip_space(void)
{
  int again = 1;
  while (again) {
    again = 0;
    while (pos < src_len && is_space(src[pos])) {
      pos = pos + 1;
      again = 1;
    }
    if (pos < src_len && at_comment_start()) {
      skip_comment();
      again = 1;
    }
  }
}

static int keyword_at(const char *word)
{
  long i = 0;
  skip_space();
  while (word[i]) {
    if (pos + i >= src_len) return 0;
    if (src[pos + i] != word[i]) return 0;
    i = i + 1;
  }
  if (pos + i < src_len && is_ident_char(src[pos + i])) return 0;
  return 1;
}

static int take_keyword(const char *word)
{
  long i = 0;
  if (!keyword_at(word)) return 0;
  while (word[i]) i = i + 1;
  pos = pos + i;
  return 1;
}

static int take_char(int c)
{
  skip_space();
  if (pos < src_len && src[pos] == c) {
    pos = pos + 1;
    return 1;
  }
  return 0;
}

static void expect_char(int c)
{
  if (!take_char(c)) die("unexpected token");
}

static void expect_keyword(const char *word)
{
  if (!take_keyword(word)) die("unexpected keyword");
}

static void take_ident_span(long *start_out, long *len_out)
{
  long start;
  skip_space();
  if (pos >= src_len) die("expected identifier");
  if (!((src[pos] >= 'a' && src[pos] <= 'z') || (src[pos] >= 'A' && src[pos] <= 'Z') || src[pos] == '_')) die("expected identifier");
  start = pos;
  pos = pos + 1;
  while (pos < src_len && is_ident_char(src[pos])) pos = pos + 1;
  *start_out = start;
  *len_out = pos - start;
}

static int span_equal(long a_start, long a_len, long b_start, long b_len)
{
  long i = 0;
  if (a_len != b_len) return 0;
  while (i < a_len) {
    if (src[a_start + i] != src[b_start + i]) return 0;
    i = i + 1;
  }
  return 1;
}

static long lookup_constructor(long start, long len)
{
  long i = 0;
  while (i < ctor_count) {
    if (span_equal(start, len, ctor_start[i], ctor_len[i])) return i;
    i = i + 1;
  }
  return -1;
}

static long lookup_func_target(long start, long len)
{
  long i = func_count - 1;
  while (i >= 0) {
    if (span_equal(start, len, func_start[i], func_len[i])) return func_target[i];
    i = i - 1;
  }
  return -1;
}

static int span_is_char(long start, long len, int c)
{
  return len == 1 && src[start] == c;
}

static void add_constructor(long start, long len, long tag, long arity)
{
  if (ctor_count >= 64) die("too many constructors");
  if (lookup_constructor(start, len) >= 0) die("duplicate constructor");
  ctor_start[ctor_count] = start;
  ctor_len[ctor_count] = len;
  ctor_tag[ctor_count] = tag;
  ctor_arity[ctor_count] = arity;
  ctor_count = ctor_count + 1;
}

static void add_func(long start, long len, long target)
{
  if (func_count >= 64) die("too many functions");
  func_start[func_count] = start;
  func_len[func_count] = len;
  func_target[func_count] = target;
  func_count = func_count + 1;
}

static void unbind_func(void)
{
  if (func_count <= 0) die("internal function stack underflow");
  func_count = func_count - 1;
}

static long lookup_var(long start, long len)
{
  long i = env_depth - 1;
  while (i >= 0) {
    if (span_equal(start, len, env_start[i], env_len[i])) return stack_depth - 1 - env_level[i];
    i = i - 1;
  }
  return -1;
}

static void bind_var(long start, long len)
{
  if (span_is_char(start, len, '_')) return;
  if (env_depth >= 64) die("too many local bindings");
  if (stack_depth <= 0) die("internal binding stack underflow");
  env_start[env_depth] = start;
  env_len[env_depth] = len;
  env_level[env_depth] = stack_depth - 1;
  env_depth = env_depth + 1;
}

static void unbind_var(long start, long len)
{
  if (!span_is_char(start, len, '_')) env_depth = env_depth - 1;
}

static long low_byte(long x)
{
  long q = x / 256;
  long out = x - q * 256;
  if (out < 0) out = out + 256;
  return out;
}

static void emit_byte(int c)
{
  if (out_file) fputc(c, out_file);
  out_len = out_len + 1;
}

static void emit_u32(long x)
{
  emit_byte((int)low_byte(x));
  emit_byte((int)low_byte(x / 256));
  emit_byte((int)low_byte(x / 65536));
  emit_byte((int)low_byte(x / 16777216));
}

static void emit_s32(long x)
{
  if (x >= 0) {
    emit_u32(x);
  } else {
    x = -x - 1;
    emit_byte((int)(255 - low_byte(x)));
    emit_byte((int)(255 - low_byte(x / 256)));
    emit_byte((int)(255 - low_byte(x / 65536)));
    emit_byte((int)(255 - low_byte(x / 16777216)));
  }
}

static void emit_const(long n)
{
  emit_byte(OP_CONST);
  emit_s32(n);
}

static void emit_call_write_byte(void)
{
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(1);
}

static void emit_call_read_byte(void)
{
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(0);
}

static void emit_call_exit(void)
{
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(2);
}

static void emit_push(void)
{
  emit_byte(OP_PUSH);
  stack_depth = stack_depth + 1;
}

static void emit_pop(long count)
{
  emit_byte(OP_POP);
  emit_u32(count);
  stack_depth = stack_depth - count;
  if (stack_depth < 0) die("internal stack underflow");
}

static void emit_acc(long index)
{
  emit_byte(OP_ACC);
  emit_u32(index);
}

static void emit_branch(long offset)
{
  emit_byte(OP_BRANCH);
  emit_s32(offset);
}

static void emit_branchifnot(long offset)
{
  emit_byte(OP_BRANCHIFNOT);
  emit_s32(offset);
}

static void emit_call(long target)
{
  emit_byte(OP_CALL);
  emit_u32(target);
}

static void emit_return(void)
{
  emit_byte(OP_RETURN);
}

static void emit_makeblock(long tag, long size)
{
  emit_byte(OP_MAKEBLOCK);
  emit_u32(tag);
  emit_u32(size);
  if (size > 1) {
    stack_depth = stack_depth - (size - 1);
    if (stack_depth < 0) die("internal stack underflow");
  }
}

static void emit_getfield(long index)
{
  emit_byte(OP_GETFIELD);
  emit_u32(index);
}

static void emit_setfield(long index)
{
  emit_byte(OP_SETFIELD);
  emit_u32(index);
  stack_depth = stack_depth - 1;
  if (stack_depth < 0) die("internal stack underflow");
}

static void emit_gettag(void)
{
  emit_byte(OP_GETTAG);
}

static void emit_binary_op(int op)
{
  emit_byte(op);
  stack_depth = stack_depth - 1;
  if (stack_depth < 0) die("internal stack underflow");
}

static void parse_expr(void);
static void parse_nonseq_expr(void);
static long measure_expr(long start, long *end_out);
static long measure_nonseq_expr(long start, long *end_out);
static int parse_string_char(void);

static int atom_starts(void)
{
  skip_space();
  if (pos >= src_len) return 0;
  if (src[pos] == '(') return 1;
  if (src[pos] == '-') return 1;
  if (src[pos] >= '0' && src[pos] <= '9') return 1;
  if (src[pos] >= 'a' && src[pos] <= 'z') return 1;
  if (src[pos] >= 'A' && src[pos] <= 'Z') return 1;
  return 0;
}

static long parse_int_literal(void)
{
  long sign = 1;
  long out = 0;
  int seen = 0;
  skip_space();
  if (pos < src_len && src[pos] == '-') {
    sign = -1;
    pos = pos + 1;
  }
  while (pos < src_len && src[pos] >= '0' && src[pos] <= '9') {
    out = out * 10 + (src[pos] - '0');
    seen = 1;
    pos = pos + 1;
  }
  if (!seen) die("expected integer");
  return out * sign;
}

static void parse_atom(void)
{
  long var_index;
  long name_start;
  long name_len;
  long ctor;
  long index;
  long size;
  long init_start;
  long init_end;
  long i;
  int ch;
  long func_target_value;
  skip_space();
  if (take_char('(')) {
    parse_expr();
    if (take_char(',')) {
      emit_push();
      parse_expr();
      expect_char(')');
      emit_makeblock(0, 2);
      return;
    }
    expect_char(')');
  } else if (keyword_at("read_byte")) {
    take_keyword("read_byte");
    emit_const(0);
    emit_call_read_byte();
  } else if (pos < src_len && src[pos] == '"') {
    pos = pos + 1;
    i = 0;
    ch = parse_string_char();
    if (ch < 0) {
      emit_const(0);
    } else {
      emit_const(ch);
      i = 1;
      ch = parse_string_char();
      while (ch >= 0) {
        emit_push();
        emit_const(ch);
        i = i + 1;
        ch = parse_string_char();
      }
    }
    emit_makeblock(0, i);
  } else if (keyword_at("Array.create")) {
    take_keyword("Array.create");
    size = parse_int_literal();
    if (size < 0) die("negative array size");
    init_start = pos;
    measure_nonseq_expr(init_start, &init_end);
    pos = init_start;
    parse_nonseq_expr();
    i = 1;
    while (i < size) {
      emit_push();
      i = i + 1;
    }
    if (pos != init_end) die("internal array parse mismatch");
    emit_makeblock(0, size);
  } else if (keyword_at("Bytes.create")) {
    take_keyword("Bytes.create");
    size = parse_int_literal();
    if (size < 0) die("negative bytes size");
    emit_const(0);
    i = 1;
    while (i < size) {
      emit_push();
      i = i + 1;
    }
    emit_makeblock(0, size);
  } else if (pos < src_len && src[pos] >= 'A' && src[pos] <= 'Z') {
    take_ident_span(&name_start, &name_len);
    ctor = lookup_constructor(name_start, name_len);
    if (ctor < 0) die("unknown constructor");
    if (ctor_arity[ctor] == 1) parse_atom();
    else if (ctor_arity[ctor] != 0) die("unsupported constructor arity");
    emit_makeblock(ctor_tag[ctor], ctor_arity[ctor]);
  } else if (pos < src_len && ((src[pos] >= 'a' && src[pos] <= 'z') || (src[pos] >= 'A' && src[pos] <= 'Z'))) {
    take_ident_span(&name_start, &name_len);
    func_target_value = lookup_func_target(name_start, name_len);
    if (func_target_value >= 0 && atom_starts()) {
      parse_atom();
      emit_call(func_target_value);
      return;
    }
    var_index = lookup_var(name_start, name_len);
    if (var_index < 0) die("unknown variable");
    emit_acc(var_index);
    if (take_char('.')) {
      if (take_char('(')) {
        index = parse_int_literal();
        if (index < 0) die("negative array index");
        expect_char(')');
      } else if (take_char('[')) {
        index = parse_int_literal();
        if (index < 0) die("negative bytes index");
        expect_char(']');
      } else {
        die("expected field index");
      }
      emit_getfield(index);
    }
  } else {
    emit_const(parse_int_literal());
  }
}

static void parse_mul(void)
{
  int more = 1;
  parse_atom();
  while (more) {
    if (take_char('*')) {
      emit_push();
      parse_atom();
      emit_binary_op(OP_MULINT);
    } else if (take_char('/')) {
      emit_push();
      parse_atom();
      emit_binary_op(OP_DIVINT);
    } else {
      more = 0;
    }
  }
}

static void parse_add(void)
{
  int more = 1;
  parse_mul();
  while (more) {
    if (take_char('+')) {
      emit_push();
      parse_mul();
      emit_binary_op(OP_ADDINT);
    } else if (take_char('-')) {
      emit_push();
      parse_mul();
      emit_binary_op(OP_SUBINT);
    } else {
      more = 0;
    }
  }
}

static void parse_cmp(void)
{
  parse_add();
  if (take_char('<')) {
    int has_eq = take_char('=');
    emit_push();
    parse_add();
    if (has_eq) emit_binary_op(OP_LE);
    else emit_binary_op(OP_LT);
  } else if (take_char('>')) {
    int has_eq = take_char('=');
    emit_push();
    parse_add();
    if (has_eq) emit_binary_op(OP_GE);
    else emit_binary_op(OP_GT);
  } else if (take_char('!')) {
    expect_char('=');
    emit_push();
    parse_add();
    emit_binary_op(OP_NE);
  } else if (take_char('=')) {
    expect_char('=');
    emit_push();
    parse_add();
    emit_binary_op(OP_EQ);
  }
}

static void parse_write(void)
{
  if (!take_keyword("write_byte")) die("expected write_byte");
  parse_cmp();
  emit_call_write_byte();
}

static void parse_exit(void)
{
  if (!take_keyword("exit")) die("expected exit");
  parse_cmp();
  emit_call_exit();
}

static int parse_string_char(void)
{
  int c;
  int out;
  if (pos >= src_len) die("unterminated string");
  c = src[pos];
  pos = pos + 1;
  if (c == '\\') {
    if (pos >= src_len) die("unterminated string escape");
    c = src[pos];
    pos = pos + 1;
    if (c == 'n') return 10;
    if (c == 't') return 9;
    if (c == '\\') return 92;
    if (c == '"') return 34;
    if (c >= '0' && c <= '9') {
      out = c - '0';
      if (pos >= src_len || src[pos] < '0' || src[pos] > '9') die("short numeric string escape");
      out = out * 10 + (src[pos] - '0');
      pos = pos + 1;
      if (pos >= src_len || src[pos] < '0' || src[pos] > '9') die("short numeric string escape");
      out = out * 10 + (src[pos] - '0');
      pos = pos + 1;
      if (out > 255) die("numeric string escape out of range");
      return out;
    }
    die("unsupported string escape");
  }
  if (c == '"') return -1;
  return c;
}

static void parse_write_string(void)
{
  int c;
  int wrote = 0;
  if (!take_keyword("write_string")) die("expected write_string");
  skip_space();
  if (pos >= src_len || src[pos] != '"') die("expected string");
  pos = pos + 1;
  c = parse_string_char();
  while (c >= 0) {
    emit_const(c);
    emit_call_write_byte();
    wrote = 1;
    c = parse_string_char();
  }
  if (!wrote) emit_const(0);
}

static long measure_expr(long start, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
  long saved_stack_depth = stack_depth;
  long measured;
  out_file = 0;
  out_len = 0;
  pos = start;
  parse_expr();
  measured = out_len;
  *end_out = pos;
  out_file = saved_file;
  out_len = saved_len;
  pos = saved_pos;
  stack_depth = saved_stack_depth;
  return measured;
}

static long measure_nonseq_expr(long start, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
  long saved_stack_depth = stack_depth;
  long measured;
  out_file = 0;
  out_len = 0;
  pos = start;
  parse_nonseq_expr();
  measured = out_len;
  *end_out = pos;
  out_file = saved_file;
  out_len = saved_len;
  pos = saved_pos;
  stack_depth = saved_stack_depth;
  return measured;
}

static long measure_function_expr(long start, long param_start, long param_len, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
  long saved_stack_depth = stack_depth;
  long saved_env_depth = env_depth;
  long measured;
  out_file = 0;
  out_len = 0;
  pos = start;
  stack_depth = 0;
  emit_push();
  bind_var(param_start, param_len);
  parse_expr();
  unbind_var(param_start, param_len);
  emit_pop(1);
  emit_return();
  measured = out_len;
  *end_out = pos;
  out_file = saved_file;
  out_len = saved_len;
  pos = saved_pos;
  stack_depth = saved_stack_depth;
  env_depth = saved_env_depth;
  return measured;
}

static void parse_if(void)
{
  long then_start;
  long then_end;
  long else_start;
  long else_end;
  long then_len;
  long else_len;
  if (!take_keyword("if")) die("expected if");
  parse_expr();
  expect_keyword("then");
  then_start = pos;
  then_len = measure_expr(then_start, &then_end);
  pos = then_end;
  expect_keyword("else");
  else_start = pos;
  else_len = measure_expr(else_start, &else_end);
  pos = then_start;
  emit_branchifnot(then_len + 5);
  parse_expr();
  expect_keyword("else");
  emit_branch(else_len);
  parse_expr();
  if (pos != else_end) die("internal if parse mismatch");
}

static void expect_arrow(void)
{
  expect_char('-');
  expect_char('>');
}

static void parse_pattern(long *tag_out, long *arity_out, long *binder_start_out, long *binder_len_out)
{
  long name_start;
  long name_len;
  long ctor;
  take_ident_span(&name_start, &name_len);
  if (span_is_char(name_start, name_len, '_')) {
    *tag_out = -1;
    *arity_out = 0;
    *binder_start_out = 0;
    *binder_len_out = 0;
    return;
  }
  ctor = lookup_constructor(name_start, name_len);
  if (ctor < 0) die("unknown pattern constructor");
  *tag_out = ctor_tag[ctor];
  *arity_out = ctor_arity[ctor];
  *binder_start_out = 0;
  *binder_len_out = 0;
  if (*arity_out == 1) {
    take_ident_span(binder_start_out, binder_len_out);
  } else if (*arity_out != 0) {
    die("unsupported pattern constructor arity");
  }
}

static void bind_pattern_var(long arity, long binder_start, long binder_len)
{
  if (arity == 1) bind_var(binder_start, binder_len);
}

static void unbind_pattern_var(long arity, long binder_start, long binder_len)
{
  if (arity == 1) unbind_var(binder_start, binder_len);
}

static long match_arm_overhead(long arity, int has_fallthrough_branch)
{
  long out = 5;
  if (arity == 1) out = 16;
  if (has_fallthrough_branch) out = out + 5;
  return out;
}

static void parse_match(void)
{
  long arm1_tag;
  long arm1_arity;
  long arm1_binder_start;
  long arm1_binder_len;
  long arm1_start;
  long arm1_end;
  long arm1_len;
  long arm2_tag;
  long arm2_arity;
  long arm2_binder_start;
  long arm2_binder_len;
  long arm2_start;
  long arm2_end;
  long arm2_len;
  long branch_stack_depth;
  if (!take_keyword("match")) die("expected match");
  parse_expr();
  expect_keyword("with");
  parse_pattern(&arm1_tag, &arm1_arity, &arm1_binder_start, &arm1_binder_len);
  if (arm1_tag < 0) die("wildcard first match arm is unsupported");
  expect_arrow();
  arm1_start = pos;
  stack_depth = stack_depth + 1;
  if (arm1_arity == 1) stack_depth = stack_depth + 1;
  bind_pattern_var(arm1_arity, arm1_binder_start, arm1_binder_len);
  arm1_len = measure_expr(arm1_start, &arm1_end) + match_arm_overhead(arm1_arity, 1);
  unbind_pattern_var(arm1_arity, arm1_binder_start, arm1_binder_len);
  if (arm1_arity == 1) stack_depth = stack_depth - 1;
  stack_depth = stack_depth - 1;
  pos = arm1_end;
  expect_char('|');
  parse_pattern(&arm2_tag, &arm2_arity, &arm2_binder_start, &arm2_binder_len);
  if (arm2_tag >= 0 && arm1_tag == arm2_tag) die("duplicate match arm");
  expect_arrow();
  arm2_start = pos;
  stack_depth = stack_depth + 1;
  if (arm2_arity == 1) stack_depth = stack_depth + 1;
  bind_pattern_var(arm2_arity, arm2_binder_start, arm2_binder_len);
  arm2_len = measure_expr(arm2_start, &arm2_end) + match_arm_overhead(arm2_arity, 0);
  unbind_pattern_var(arm2_arity, arm2_binder_start, arm2_binder_len);
  if (arm2_arity == 1) stack_depth = stack_depth - 1;
  stack_depth = stack_depth - 1;
  pos = arm1_start;

  emit_push();
  branch_stack_depth = stack_depth;
  emit_acc(0);
  emit_gettag();
  emit_push();
  emit_const(arm1_tag);
  emit_binary_op(OP_EQ);
  emit_branchifnot(arm1_len);

  if (arm1_arity == 1) {
    emit_acc(0);
    emit_getfield(0);
    emit_push();
    bind_pattern_var(arm1_arity, arm1_binder_start, arm1_binder_len);
  }
  parse_expr();
  unbind_pattern_var(arm1_arity, arm1_binder_start, arm1_binder_len);
  if (arm1_arity == 1) emit_pop(2);
  else emit_pop(1);
  emit_branch(arm2_len);
  stack_depth = branch_stack_depth;

  expect_char('|');
  parse_pattern(&arm2_tag, &arm2_arity, &arm2_binder_start, &arm2_binder_len);
  expect_arrow();
  if (arm2_arity == 1) {
    emit_acc(0);
    emit_getfield(0);
    emit_push();
    bind_pattern_var(arm2_arity, arm2_binder_start, arm2_binder_len);
  }
  parse_expr();
  unbind_pattern_var(arm2_arity, arm2_binder_start, arm2_binder_len);
  if (arm2_arity == 1) emit_pop(2);
  else emit_pop(1);
  if (pos != arm2_end) die("internal match parse mismatch");
}

static void parse_let(void)
{
  long name_start;
  long name_len;
  long name2_start;
  long name2_len;
  long param_start;
  long param_len;
  long fn_body_start;
  long fn_body_end;
  long fn_len;
  long fn_target;
  long saved_stack_depth;
  long saved_env_depth;
  int binds = 0;
  if (!take_keyword("let")) die("expected let");
  if (take_keyword("rec")) {
    take_ident_span(&name_start, &name_len);
    take_ident_span(&param_start, &param_len);
    expect_char('=');
    fn_body_start = pos;
    fn_target = out_len + 5;
    add_func(name_start, name_len, fn_target);
    fn_len = measure_function_expr(fn_body_start, param_start, param_len, &fn_body_end);
    emit_branch(fn_len);
    saved_stack_depth = stack_depth;
    saved_env_depth = env_depth;
    stack_depth = 0;
    emit_push();
    bind_var(param_start, param_len);
    pos = fn_body_start;
    parse_expr();
    unbind_var(param_start, param_len);
    emit_pop(1);
    emit_return();
    if (pos != fn_body_end) die("internal let rec parse mismatch");
    stack_depth = saved_stack_depth;
    env_depth = saved_env_depth;
    expect_keyword("in");
    parse_expr();
    unbind_func();
    return;
  }
  if (take_char('(')) {
    take_ident_span(&name_start, &name_len);
    expect_char(',');
    take_ident_span(&name2_start, &name2_len);
    expect_char(')');
    expect_char('=');
    parse_expr();
    emit_push();
    emit_acc(0);
    emit_getfield(0);
    emit_push();
    bind_var(name_start, name_len);
    emit_acc(1);
    emit_getfield(1);
    emit_push();
    bind_var(name2_start, name2_len);
    binds = 3;
  } else {
    take_ident_span(&name_start, &name_len);
    expect_char('=');
    parse_expr();
    if (!span_is_char(name_start, name_len, '_')) {
      emit_push();
      bind_var(name_start, name_len);
      binds = 1;
    }
  }
  if (!take_keyword("in")) die("expected in");
  parse_expr();
  if (binds == 3) {
    unbind_var(name2_start, name2_len);
    unbind_var(name_start, name_len);
    emit_pop(3);
  } else if (binds) {
    env_depth = env_depth - 1;
    emit_pop(1);
  }
}

static int parse_array_set(void)
{
  long saved_pos;
  long name_start;
  long name_len;
  long var_index;
  long index;
  saved_pos = pos;
  skip_space();
  if (pos >= src_len || !((src[pos] >= 'a' && src[pos] <= 'z') || src[pos] == '_')) {
    pos = saved_pos;
    return 0;
  }
  take_ident_span(&name_start, &name_len);
  if (!take_char('.')) {
    pos = saved_pos;
    return 0;
  }
  if (take_char('(')) {
    index = parse_int_literal();
    if (index < 0) die("negative array index");
    expect_char(')');
  } else if (take_char('[')) {
    index = parse_int_literal();
    if (index < 0) die("negative bytes index");
    expect_char(']');
  } else {
    pos = saved_pos;
    return 0;
  }
  if (!take_char('<')) {
    pos = saved_pos;
    return 0;
  }
  expect_char('-');
  var_index = lookup_var(name_start, name_len);
  if (var_index < 0) die("unknown array variable");
  emit_acc(var_index);
  emit_push();
  parse_nonseq_expr();
  emit_setfield(index);
  return 1;
}

static void parse_nonseq_expr(void)
{
  if (keyword_at("let")) parse_let();
  else if (keyword_at("match")) parse_match();
  else if (keyword_at("if")) parse_if();
  else if (keyword_at("exit")) parse_exit();
  else if (keyword_at("write_string")) parse_write_string();
  else if (keyword_at("write_byte")) parse_write();
  else if (parse_array_set()) {}
  else parse_cmp();
}

static void parse_expr(void)
{
  parse_nonseq_expr();
  if (take_char(';')) parse_expr();
}

static void parse_type_decls(void)
{
  long type_start;
  long type_len;
  long ctor_name_start;
  long ctor_name_len;
  long field_start;
  long field_len;
  long tag;
  while (keyword_at("type")) {
    take_keyword("type");
    take_ident_span(&type_start, &type_len);
    if (type_start < 0 || type_len <= 0) die("empty type name");
    expect_char('=');
    tag = 0;
    while (1) {
      take_ident_span(&ctor_name_start, &ctor_name_len);
      if (keyword_at("of")) {
        take_keyword("of");
        take_ident_span(&field_start, &field_len);
        if (field_start < 0 || field_len <= 0) die("empty field type");
        add_constructor(ctor_name_start, ctor_name_len, tag, 1);
      } else {
        add_constructor(ctor_name_start, ctor_name_len, tag, 0);
      }
      tag = tag + 1;
      if (!take_char('|')) break;
    }
  }
}

static long compile_len(void)
{
  out_file = 0;
  out_len = 0;
  pos = 0;
  env_depth = 0;
  stack_depth = 0;
  ctor_count = 0;
  func_count = 0;
  parse_type_decls();
  parse_expr();
  skip_space();
  if (pos != src_len) die("unexpected trailing input");
  emit_byte(OP_HALT);
  return out_len;
}

static void write_u32_file(FILE *file, long x)
{
  fputc((int)low_byte(x), file);
  fputc((int)low_byte(x / 256), file);
  fputc((int)low_byte(x / 65536), file);
  fputc((int)low_byte(x / 16777216), file);
}

static void write_bytecode(const char *path)
{
  FILE *file;
  long code_len = compile_len();
  long actual_len;
  file = fopen(path, "wb");
  if (!file) die("cannot open output file");
  fputc('M', file);
  fputc('Z', file);
  fputc('B', file);
  fputc('C', file);
  write_u32_file(file, 1);
  write_u32_file(file, code_len);
  write_u32_file(file, 3);
  write_u32_file(file, 0);
  out_file = file;
  out_len = 0;
  pos = 0;
  env_depth = 0;
  stack_depth = 0;
  ctor_count = 0;
  func_count = 0;
  parse_type_decls();
  parse_expr();
  emit_byte(OP_HALT);
  actual_len = out_len;
  fclose(file);
  if (actual_len != code_len) die("internal bytecode length mismatch");
}

int main(int argc, char **argv)
{
  if (argc != 3) {
    fputs("usage: mlc-seed INPUT.ml OUTPUT.mzbc\n", stderr);
    return 2;
  }
  src = read_file(argv[1], &src_len);
  write_bytecode(argv[2]);
  return 0;
}
