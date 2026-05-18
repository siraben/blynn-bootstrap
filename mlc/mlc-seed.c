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
  OP_GETTAG = 18
};

static FILE *out_file;
static long out_len;
static char *src;
static long src_len;
static long pos;
static int env_has_x;
static long env_names[64];
static long env_depth;

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

static void skip_space(void)
{
  while (pos < src_len && is_space(src[pos])) pos = pos + 1;
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

static long take_ident1(void)
{
  long c;
  skip_space();
  if (pos >= src_len) die("expected identifier");
  c = src[pos];
  if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')) die("expected identifier");
  pos = pos + 1;
  if (pos < src_len && is_ident_char(src[pos])) die("only one-character identifiers are supported in mlc-seed");
  return c;
}

static long lookup_var(long name)
{
  long i = env_depth - 1;
  long stack_index = 0;
  while (i >= 0) {
    if (env_names[i] == name) return stack_index;
    i = i - 1;
    stack_index = stack_index + 1;
  }
  return -1;
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

static void emit_const(long n)
{
  emit_byte(OP_CONST);
  emit_u32(n);
}

static void emit_call_write_byte(void)
{
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(1);
}

static void emit_pop(long count)
{
  emit_byte(OP_POP);
  emit_u32(count);
}

static void emit_acc(long index)
{
  emit_byte(OP_ACC);
  emit_u32(index);
}

static void emit_branch(long offset)
{
  emit_byte(OP_BRANCH);
  emit_u32(offset);
}

static void emit_branchifnot(long offset)
{
  emit_byte(OP_BRANCHIFNOT);
  emit_u32(offset);
}

static void emit_makeblock(long tag, long size)
{
  emit_byte(OP_MAKEBLOCK);
  emit_u32(tag);
  emit_u32(size);
}

static void emit_getfield(long index)
{
  emit_byte(OP_GETFIELD);
  emit_u32(index);
}

static void emit_gettag(void)
{
  emit_byte(OP_GETTAG);
}

static void parse_expr(void);

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
  skip_space();
  if (take_char('(')) {
    parse_expr();
    expect_char(')');
  } else if (keyword_at("None")) {
    take_keyword("None");
    emit_makeblock(0, 0);
  } else if (keyword_at("Some")) {
    take_keyword("Some");
    parse_atom();
    emit_makeblock(1, 1);
  } else if (env_has_x && keyword_at("x")) {
    take_keyword("x");
    emit_acc(0);
  } else if (pos < src_len && ((src[pos] >= 'a' && src[pos] <= 'z') || (src[pos] >= 'A' && src[pos] <= 'Z'))) {
    long name = take_ident1();
    var_index = lookup_var(name);
    if (var_index < 0) die("unknown variable");
    emit_acc(var_index);
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
      emit_byte(OP_PUSH);
      parse_atom();
      emit_byte(OP_MULINT);
    } else if (take_char('/')) {
      emit_byte(OP_PUSH);
      parse_atom();
      emit_byte(OP_DIVINT);
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
      emit_byte(OP_PUSH);
      parse_mul();
      emit_byte(OP_ADDINT);
    } else if (take_char('-')) {
      emit_byte(OP_PUSH);
      parse_mul();
      emit_byte(OP_SUBINT);
    } else {
      more = 0;
    }
  }
}

static void parse_cmp(void)
{
  parse_add();
  if (take_char('<')) {
    emit_byte(OP_PUSH);
    parse_add();
    emit_byte(OP_LT);
  } else if (take_char('=')) {
    expect_char('=');
    emit_byte(OP_PUSH);
    parse_add();
    emit_byte(OP_EQ);
  }
}

static void parse_write(void)
{
  if (!take_keyword("write_byte")) die("expected write_byte");
  parse_cmp();
  emit_call_write_byte();
}

static long measure_expr(long start, long *end_out)
{
  FILE *saved_file = out_file;
  long saved_len = out_len;
  long saved_pos = pos;
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

static void parse_match(void)
{
  long some_start;
  long some_end;
  long none_start;
  long none_end;
  long some_len;
  long none_len;
  int saved_env;
  if (!take_keyword("match")) die("expected match");
  parse_expr();
  expect_keyword("with");
  expect_keyword("Some");
  expect_keyword("x");
  expect_arrow();
  some_start = pos;
  saved_env = env_has_x;
  env_has_x = 1;
  some_len = measure_expr(some_start, &some_end) + 21;
  env_has_x = saved_env;
  pos = some_end;
  expect_char('|');
  expect_keyword("None");
  expect_arrow();
  none_start = pos;
  none_len = measure_expr(none_start, &none_end) + 5;
  pos = some_start;

  emit_byte(OP_PUSH);
  emit_acc(0);
  emit_gettag();
  emit_byte(OP_PUSH);
  emit_const(1);
  emit_byte(OP_EQ);
  emit_branchifnot(some_len);

  emit_acc(0);
  emit_getfield(0);
  emit_byte(OP_PUSH);
  env_has_x = 1;
  parse_expr();
  env_has_x = saved_env;
  emit_pop(2);
  emit_branch(none_len);

  expect_char('|');
  expect_keyword("None");
  expect_arrow();
  emit_pop(1);
  parse_expr();
  if (pos != none_end) die("internal match parse mismatch");
}

static void parse_let(void)
{
  long name;
  int binds = 0;
  if (!take_keyword("let")) die("expected let");
  name = take_ident1();
  expect_char('=');
  parse_expr();
  if (name != '_') {
    if (env_depth >= 64) die("too many local bindings");
    emit_byte(OP_PUSH);
    env_names[env_depth] = name;
    env_depth = env_depth + 1;
    binds = 1;
  }
  if (!take_keyword("in")) die("expected in");
  parse_expr();
  if (binds) {
    env_depth = env_depth - 1;
    emit_pop(1);
  }
}

static void parse_expr(void)
{
  if (keyword_at("let")) parse_let();
  else if (keyword_at("match")) parse_match();
  else if (keyword_at("if")) parse_if();
  else if (keyword_at("write_byte")) parse_write();
  else parse_cmp();
}

static long compile_len(void)
{
  out_file = 0;
  out_len = 0;
  pos = 0;
  env_depth = 0;
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
