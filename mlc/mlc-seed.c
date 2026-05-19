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
  OP_RETURN = 24,
  OP_GETFIELD_DYN = 25,
  OP_SETFIELD_DYN = 26,
  OP_BLOCKSIZE = 27,
  OP_MAKEBLOCK_DYN = 28
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

static int keyword_at_raw(long at, const char *word)
{
  long i = 0;
  if (at > 0 && is_ident_char(src[at - 1])) return 0;
  while (word[i]) {
    if (at + i >= src_len) return 0;
    if (src[at + i] != word[i]) return 0;
    i = i + 1;
  }
  if (at + i < src_len && is_ident_char(src[at + i])) return 0;
  return 1;
}

static long find_rec_and(long start)
{
  long i = start;
  long depth = 0;
  long comment_depth;
  while (i < src_len) {
    if (src[i] == '"') {
      i = i + 1;
      while (i < src_len && src[i] != '"') {
        if (src[i] == '\\' && i + 1 < src_len) i = i + 2;
        else i = i + 1;
      }
      if (i < src_len) i = i + 1;
    } else if (i + 1 < src_len && src[i] == '(' && src[i + 1] == '*') {
      comment_depth = 1;
      i = i + 2;
      while (i < src_len && comment_depth > 0) {
        if (i + 1 < src_len && src[i] == '(' && src[i + 1] == '*') {
          comment_depth = comment_depth + 1;
          i = i + 2;
        } else if (i + 1 < src_len && src[i] == '*' && src[i + 1] == ')') {
          comment_depth = comment_depth - 1;
          i = i + 2;
        } else {
          i = i + 1;
        }
      }
    } else {
      if ((src[i] == '(' || src[i] == '[') && depth < 64) depth = depth + 1;
      else if ((src[i] == ')' || src[i] == ']') && depth > 0) depth = depth - 1;
      else if (depth == 0 && keyword_at_raw(i, "and")) return i;
      else if (depth == 0 && keyword_at_raw(i, "in")) return -1;
      i = i + 1;
    }
  }
  return -1;
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

static void die_unknown_variable(long start, long len)
{
  long i = 0;
  fputs("mlc-seed: unknown variable: ", stderr);
  while (i < len) {
    fputc(src[start + i], stderr);
    i = i + 1;
  }
  fputc('\n', stderr);
  exit(1);
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

static void emit_call_debug_byte(void)
{
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(3);
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

static void emit_makeblock_dyn(long tag)
{
  emit_byte(OP_MAKEBLOCK_DYN);
  emit_u32(tag);
  stack_depth = stack_depth - 1;
  if (stack_depth < 0) die("internal stack underflow");
}

static void emit_getfield(long index)
{
  emit_byte(OP_GETFIELD);
  emit_u32(index);
}

static void emit_getfield_dyn(void)
{
  emit_byte(OP_GETFIELD_DYN);
  stack_depth = stack_depth - 1;
  if (stack_depth < 0) die("internal stack underflow");
}

static void emit_setfield_dyn(void)
{
  emit_byte(OP_SETFIELD_DYN);
  stack_depth = stack_depth - 2;
  if (stack_depth < 0) die("internal stack underflow");
}

static void emit_blocksize(void)
{
  emit_byte(OP_BLOCKSIZE);
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
  if (src[pos] == '"') return 1;
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
  } else if (keyword_at("Bytes.length")) {
    take_keyword("Bytes.length");
    parse_atom();
    emit_blocksize();
  } else if (keyword_at("String.length")) {
    take_keyword("String.length");
    parse_atom();
    emit_blocksize();
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
    parse_atom();
    emit_push();
    parse_nonseq_expr();
    emit_makeblock_dyn(0);
  } else if (keyword_at("Bytes.create")) {
    take_keyword("Bytes.create");
    parse_atom();
    emit_push();
    emit_const(0);
    emit_makeblock_dyn(0);
  } else if (pos < src_len && ((src[pos] >= 'a' && src[pos] <= 'z') || (src[pos] >= 'A' && src[pos] <= 'Z'))) {
    take_ident_span(&name_start, &name_len);
    func_target_value = lookup_func_target(name_start, name_len);
    if (func_target_value >= 0 && atom_starts()) {
      parse_atom();
      emit_call(func_target_value);
      return;
    }
    var_index = lookup_var(name_start, name_len);
    if (var_index < 0) die_unknown_variable(name_start, name_len);
    emit_acc(var_index);
    if (take_char('.')) {
      if (take_char('(')) {
        emit_push();
        parse_nonseq_expr();
        expect_char(')');
      } else if (take_char('[')) {
        emit_push();
        parse_nonseq_expr();
        expect_char(']');
      } else {
        die("expected field index");
      }
      emit_getfield_dyn();
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

static void parse_debug_byte(void)
{
  if (!take_keyword("debug_byte")) die("expected debug_byte");
  parse_cmp();
  emit_call_debug_byte();
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

static void parse_debug_string(void)
{
  int c;
  int wrote = 0;
  if (!take_keyword("debug_string")) die("expected debug_string");
  skip_space();
  if (pos >= src_len || src[pos] != '"') die("expected string");
  pos = pos + 1;
  c = parse_string_char();
  while (c >= 0) {
    emit_const(c);
    emit_call_debug_byte();
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
  long saved_env_depth = env_depth;
  long saved_func_count = func_count;
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
  env_depth = saved_env_depth;
  func_count = saved_func_count;
  return measured;
}

static long measure_nonseq_expr(long start, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
  long saved_stack_depth = stack_depth;
  long saved_env_depth = env_depth;
  long saved_func_count = func_count;
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
  env_depth = saved_env_depth;
  func_count = saved_func_count;
  return measured;
}

static long measure_function_expr(long start, long param_start, long param_len, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
  long saved_stack_depth = stack_depth;
  long saved_env_depth = env_depth;
  long saved_func_count = func_count;
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
  func_count = saved_func_count;
  return measured;
}

static void emit_function_body(long start, long end, long param_start, long param_len, const char *mismatch)
{
  long saved_stack_depth = stack_depth;
  long saved_env_depth = env_depth;
  stack_depth = 0;
  emit_push();
  bind_var(param_start, param_len);
  pos = start;
  parse_expr();
  unbind_var(param_start, param_len);
  emit_pop(1);
  emit_return();
  if (pos != end) die(mismatch);
  stack_depth = saved_stack_depth;
  env_depth = saved_env_depth;
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

static void parse_let(void)
{
  long name_start;
  long name_len;
  long name2_start;
  long name2_len;
  long param_start;
  long param_len;
  long rec2_start;
  long rec2_len;
  long param2_start;
  long param2_len;
  long fn_body_start;
  long fn_body_end;
  long fn2_body_start;
  long fn2_body_end;
  long fn_len;
  long fn2_len = 0;
  long fn_target;
  long and_pos;
  int binds = 0;
  int has_and = 0;
  if (!take_keyword("let")) die("expected let");
  if (take_keyword("rec")) {
    take_ident_span(&name_start, &name_len);
    take_ident_span(&param_start, &param_len);
    expect_char('=');
    fn_body_start = pos;
    fn_target = out_len + 5;
    add_func(name_start, name_len, fn_target);
    and_pos = find_rec_and(fn_body_start);
    if (and_pos >= 0) {
      has_and = 1;
      pos = and_pos;
      expect_keyword("and");
      take_ident_span(&rec2_start, &rec2_len);
      take_ident_span(&param2_start, &param2_len);
      expect_char('=');
      fn2_body_start = pos;
      add_func(rec2_start, rec2_len, fn_target);
    }
    pos = fn_body_start;
    fn_len = measure_function_expr(fn_body_start, param_start, param_len, &fn_body_end);
    if (has_and) {
      if (fn_body_end != and_pos) die("internal let rec and delimiter mismatch");
      func_target[func_count - 1] = fn_target + fn_len;
      fn2_len = measure_function_expr(fn2_body_start, param2_start, param2_len, &fn2_body_end);
    }
    if (has_and) emit_branch(fn_len + fn2_len);
    else emit_branch(fn_len);
    emit_function_body(fn_body_start, fn_body_end, param_start, param_len, "internal let rec parse mismatch");
    if (has_and) {
      expect_keyword("and");
      take_ident_span(&rec2_start, &rec2_len);
      take_ident_span(&param2_start, &param2_len);
      expect_char('=');
      if (pos != fn2_body_start) die("internal let rec and parse mismatch");
      emit_function_body(fn2_body_start, fn2_body_end, param2_start, param2_len, "internal let rec and body mismatch");
    }
    expect_keyword("in");
    parse_expr();
    unbind_func();
    if (has_and) unbind_func();
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
  long index_start;
  long index_end;
  int close_char;
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
    close_char = ')';
  } else if (take_char('[')) {
    close_char = ']';
  } else {
    pos = saved_pos;
    return 0;
  }
  index_start = pos;
  measure_nonseq_expr(index_start, &index_end);
  pos = index_end;
  expect_char(close_char);
  if (!take_char('<')) {
    pos = saved_pos;
    return 0;
  }
  expect_char('-');
  var_index = lookup_var(name_start, name_len);
  if (var_index < 0) die("unknown array variable");
  emit_acc(var_index);
  emit_push();
  pos = index_start;
  parse_nonseq_expr();
  if (pos != index_end) die("internal index parse mismatch");
  expect_char(close_char);
  expect_char('<');
  expect_char('-');
  emit_push();
  parse_nonseq_expr();
  emit_setfield_dyn();
  return 1;
}

static void parse_nonseq_expr(void)
{
  if (keyword_at("let")) parse_let();
  else if (keyword_at("if")) parse_if();
  else if (keyword_at("exit")) parse_exit();
  else if (keyword_at("debug_string")) parse_debug_string();
  else if (keyword_at("write_string")) parse_write_string();
  else if (keyword_at("debug_byte")) parse_debug_byte();
  else if (keyword_at("write_byte")) parse_write();
  else if (parse_array_set()) {}
  else parse_cmp();
}

static void parse_expr(void)
{
  parse_nonseq_expr();
  if (take_char(';')) parse_expr();
}

static long compile_len(void)
{
  out_file = 0;
  out_len = 0;
  pos = 0;
  env_depth = 0;
  stack_depth = 0;
  func_count = 0;
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
  write_u32_file(file, 4);
  write_u32_file(file, 0);
  out_file = file;
  out_len = 0;
  pos = 0;
  env_depth = 0;
  stack_depth = 0;
  func_count = 0;
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
