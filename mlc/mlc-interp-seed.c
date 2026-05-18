#include <stdio.h>
#include <stdlib.h>

enum {
  MAX_NODES = 8192,
  INITIAL_ENVS = 65536,
  INITIAL_CLOSURES = 32768,

  N_INT = 1,
  N_VAR = 2,
  N_ADD = 3,
  N_SUB = 4,
  N_MUL = 5,
  N_DIV = 6,
  N_EQ = 7,
  N_NE = 8,
  N_LT = 9,
  N_LE = 10,
  N_GT = 11,
  N_GE = 12,
  N_IF = 13,
  N_LET = 14,
  N_LETREC = 15,
  N_FUN = 16,
  N_CALL = 17,
  N_SEQ = 18,
  N_WRITE_BYTE = 19,
  N_READ_BYTE = 20,
  N_NEG = 21,
  N_EXIT = 22,
  N_WRITE_STRING = 23,
  N_EXPECT_STRING = 24
};

static char *src;
static long src_len;
static long pos;

static long node_count;
static long kind[MAX_NODES];
static long left[MAX_NODES];
static long right[MAX_NODES];
static long third[MAX_NODES];
static long int_value[MAX_NODES];
static long name_start[MAX_NODES];
static long name_len[MAX_NODES];
static long name2_start[MAX_NODES];
static long name2_len[MAX_NODES];

static long env_count;
static long env_cap;
static long *env_name_start;
static long *env_name_len;
static long *env_value;
static long *env_next;

static long closure_count;
static long closure_cap;
static long *closure_param_start;
static long *closure_param_len;
static long *closure_body;
static long *closure_env;

static void die(const char *msg)
{
  fputs("mlc-interp-seed: ", stderr);
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

static int is_alpha(int c)
{
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static int is_digit(int c)
{
  return c >= '0' && c <= '9';
}

static int is_ident_char(int c)
{
  return is_alpha(c) || is_digit(c) || c == '\'';
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

static int span_eq(long start, long len, const char *word)
{
  long i = 0;
  while (i < len && word[i]) {
    if (src[start + i] != word[i]) return 0;
    i = i + 1;
  }
  return i == len && word[i] == 0;
}

static int keyword_span(long start, long len)
{
  return span_eq(start, len, "let") || span_eq(start, len, "rec") ||
    span_eq(start, len, "and") || span_eq(start, len, "in") ||
    span_eq(start, len, "if") || span_eq(start, len, "then") ||
    span_eq(start, len, "else") || span_eq(start, len, "fun") ||
    span_eq(start, len, "true") || span_eq(start, len, "false") ||
    span_eq(start, len, "exit") ||
    span_eq(start, len, "read_byte") || span_eq(start, len, "write_byte") ||
    span_eq(start, len, "write_string") || span_eq(start, len, "expect_string");
}

static int keyword_at(const char *word)
{
  long i = 0;
  skip_space();
  if (pos > 0 && is_ident_char(src[pos - 1])) return 0;
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

static int take_two(int a, int b)
{
  skip_space();
  if (pos + 1 < src_len && src[pos] == a && src[pos + 1] == b) {
    pos = pos + 2;
    return 1;
  }
  return 0;
}

static void expect_char(int c)
{
  if (!take_char(c)) die("unexpected token");
}

static void expect_two(int a, int b)
{
  if (!take_two(a, b)) die("unexpected token");
}

static void parse_ident(long *start_out, long *len_out)
{
  long start;
  skip_space();
  if (pos >= src_len || !is_alpha(src[pos])) die("expected identifier");
  start = pos;
  pos = pos + 1;
  while (pos < src_len && is_ident_char(src[pos])) pos = pos + 1;
  if (keyword_span(start, pos - start)) die("expected identifier");
  *start_out = start;
  *len_out = pos - start;
}

static long new_node(long k)
{
  node_count = node_count + 1;
  if (node_count >= MAX_NODES) die("too many AST nodes");
  kind[node_count] = k;
  left[node_count] = 0;
  right[node_count] = 0;
  third[node_count] = 0;
  int_value[node_count] = 0;
  name_start[node_count] = 0;
  name_len[node_count] = 0;
  name2_start[node_count] = 0;
  name2_len[node_count] = 0;
  return node_count;
}

static long new_binary(long k, long a, long b)
{
  long node = new_node(k);
  left[node] = a;
  right[node] = b;
  return node;
}

static long parse_expr(void);

static long parse_escaped_char(void)
{
  long value;
  int c;
  int c2;
  int c3;
  if (pos >= src_len) die("unterminated escape");
  c = src[pos];
  pos = pos + 1;
  if (c == 'n') return 10;
  if (c == 't') return 9;
  if (is_digit(c)) {
    if (pos + 1 >= src_len) die("bad decimal escape");
    c2 = src[pos];
    c3 = src[pos + 1];
    if (!is_digit(c2) || !is_digit(c3)) die("bad decimal escape");
    pos = pos + 2;
    value = (c - '0') * 100 + (c2 - '0') * 10 + c3 - '0';
    return value;
  }
  return c;
}

static long parse_char_body(void)
{
  int c;
  if (pos >= src_len) die("unterminated char literal");
  c = src[pos];
  pos = pos + 1;
  if (c == 92) return parse_escaped_char();
  return c;
}

static void parse_string_span(long *start_out, long *len_out)
{
  long start;
  expect_char(34);
  start = pos;
  while (pos < src_len && src[pos] != 34) {
    if (src[pos] == 92) {
      pos = pos + 1;
      parse_escaped_char();
    } else {
      pos = pos + 1;
    }
  }
  if (pos >= src_len) die("unterminated string literal");
  *start_out = start;
  *len_out = pos - start;
  pos = pos + 1;
}

static int atom_starts(void)
{
  skip_space();
  if (pos >= src_len) return 0;
  if (is_digit(src[pos])) return 1;
  if (is_alpha(src[pos])) {
    if (keyword_at("in") || keyword_at("then") || keyword_at("else") || keyword_at("rec")) return 0;
    return 1;
  }
  return src[pos] == '(' || src[pos] == 39;
}

static long parse_atom(void)
{
  long node;
  long start;
  long len;
  long value;
  skip_space();
  if (take_char('(')) {
    node = parse_expr();
    expect_char(')');
    return node;
  }
  if (take_keyword("true")) {
    node = new_node(N_INT);
    int_value[node] = 1;
    return node;
  }
  if (take_keyword("false")) {
    node = new_node(N_INT);
    int_value[node] = 0;
    return node;
  }
  if (take_keyword("read_byte")) return new_node(N_READ_BYTE);
  if (take_char(39)) {
    value = parse_char_body();
    expect_char(39);
    node = new_node(N_INT);
    int_value[node] = value;
    return node;
  }
  if (is_digit(src[pos])) {
    value = 0;
    while (pos < src_len && is_digit(src[pos])) {
      value = value * 10 + src[pos] - '0';
      pos = pos + 1;
    }
    node = new_node(N_INT);
    int_value[node] = value;
    return node;
  }
  parse_ident(&start, &len);
  node = new_node(N_VAR);
  name_start[node] = start;
  name_len[node] = len;
  return node;
}

static long parse_prefix(void)
{
  long node;
  long body;
  long start;
  long len;
  long string_start;
  long string_len;
  if (take_keyword("fun")) {
    parse_ident(&start, &len);
    expect_two('-', '>');
    body = parse_expr();
    node = new_node(N_FUN);
    name_start[node] = start;
    name_len[node] = len;
    left[node] = body;
    return node;
  }
  if (take_keyword("write_byte")) {
    node = new_node(N_WRITE_BYTE);
    left[node] = parse_prefix();
    return node;
  }
  if (take_keyword("write_string")) {
    node = new_node(N_WRITE_STRING);
    parse_string_span(&string_start, &string_len);
    name_start[node] = string_start;
    name_len[node] = string_len;
    return node;
  }
  if (take_keyword("expect_string")) {
    node = new_node(N_EXPECT_STRING);
    parse_string_span(&string_start, &string_len);
    name_start[node] = string_start;
    name_len[node] = string_len;
    left[node] = parse_prefix();
    return node;
  }
  if (take_keyword("exit")) {
    node = new_node(N_EXIT);
    left[node] = parse_prefix();
    return node;
  }
  if (take_char('-')) {
    node = new_node(N_NEG);
    left[node] = parse_prefix();
    return node;
  }
  return parse_atom();
}

static long parse_app(void)
{
  long node = parse_prefix();
  while (atom_starts()) {
    node = new_binary(N_CALL, node, parse_prefix());
  }
  return node;
}

static long parse_mul(void)
{
  long node = parse_app();
  while (1) {
    if (take_char('*')) node = new_binary(N_MUL, node, parse_app());
    else if (take_char('/')) node = new_binary(N_DIV, node, parse_app());
    else return node;
  }
}

static long parse_add(void)
{
  long node = parse_mul();
  while (1) {
    if (take_char('+')) node = new_binary(N_ADD, node, parse_mul());
    else if (take_char('-')) node = new_binary(N_SUB, node, parse_mul());
    else return node;
  }
}

static long parse_compare(void)
{
  long node = parse_add();
  if (take_two('<', '>')) return new_binary(N_NE, node, parse_add());
  if (take_two('<', '=')) return new_binary(N_LE, node, parse_add());
  if (take_two('>', '=')) return new_binary(N_GE, node, parse_add());
  if (take_char('=')) return new_binary(N_EQ, node, parse_add());
  if (take_char('<')) return new_binary(N_LT, node, parse_add());
  if (take_char('>')) return new_binary(N_GT, node, parse_add());
  return node;
}

static long parse_sequence(void)
{
  long node = parse_compare();
  if (take_char(';')) node = new_binary(N_SEQ, node, parse_expr());
  return node;
}

static long parse_if(void)
{
  long node;
  long cond;
  long then_node;
  long else_node;
  if (!take_keyword("if")) return parse_sequence();
  cond = parse_expr();
  if (!take_keyword("then")) die("expected then");
  then_node = parse_expr();
  if (!take_keyword("else")) die("expected else");
  else_node = parse_expr();
  node = new_node(N_IF);
  left[node] = cond;
  right[node] = then_node;
  third[node] = else_node;
  return node;
}

static long parse_let(void)
{
  long node;
  long start;
  long len;
  long start2;
  long len2;
  long rhs;
  long body;
  if (!take_keyword("let")) return parse_if();
  if (take_keyword("rec")) {
    parse_ident(&start, &len);
    parse_ident(&start2, &len2);
    expect_char('=');
    rhs = parse_expr();
    if (!take_keyword("in")) die("expected in");
    body = parse_expr();
    node = new_node(N_LETREC);
    name_start[node] = start;
    name_len[node] = len;
    name2_start[node] = start2;
    name2_len[node] = len2;
    left[node] = rhs;
    right[node] = body;
    return node;
  }
  parse_ident(&start, &len);
  expect_char('=');
  rhs = parse_expr();
  if (!take_keyword("in")) die("expected in");
  body = parse_expr();
  node = new_node(N_LET);
  name_start[node] = start;
  name_len[node] = len;
  left[node] = rhs;
  right[node] = body;
  return node;
}

static long parse_expr(void)
{
  return parse_let();
}

static int same_name(long a_start, long a_len, long b_start, long b_len)
{
  long i;
  if (a_len != b_len) return 0;
  i = 0;
  while (i < a_len) {
    if (src[a_start + i] != src[b_start + i]) return 0;
    i = i + 1;
  }
  return 1;
}

static long *grow_long_array(long *old, long new_cap)
{
  long *next = (long *)realloc(old, sizeof(long) * new_cap);
  if (!next) die("out of memory");
  return next;
}

static void ensure_env_capacity(void)
{
  long new_cap;
  if (env_count + 1 < env_cap) return;
  if (env_cap == 0) new_cap = INITIAL_ENVS;
  else new_cap = env_cap * 2;
  env_name_start = grow_long_array(env_name_start, new_cap);
  env_name_len = grow_long_array(env_name_len, new_cap);
  env_value = grow_long_array(env_value, new_cap);
  env_next = grow_long_array(env_next, new_cap);
  env_cap = new_cap;
}

static long push_env(long start, long len, long value, long next)
{
  ensure_env_capacity();
  env_count = env_count + 1;
  env_name_start[env_count] = start;
  env_name_len[env_count] = len;
  env_value[env_count] = value;
  env_next[env_count] = next;
  return env_count;
}

static long lookup_env(long env, long start, long len)
{
  while (env != 0) {
    if (same_name(env_name_start[env], env_name_len[env], start, len)) return env_value[env];
    env = env_next[env];
  }
  die("unbound variable");
  return 0;
}

static long int_val(long value)
{
  if ((value & 1) == 0) die("expected int");
  return value >> 1;
}

static long val_int(long value)
{
  return (value << 1) | 1;
}

static int string_next_char(long *offset, long end)
{
  int c;
  long saved;
  if (*offset >= end) die("string read past end");
  c = src[*offset];
  *offset = *offset + 1;
  if (c != 92) return c;
  saved = pos;
  pos = *offset;
  c = (int)parse_escaped_char();
  *offset = pos;
  pos = saved;
  return c;
}

static void ensure_closure_capacity(void)
{
  long new_cap;
  if (closure_count + 1 < closure_cap) return;
  if (closure_cap == 0) new_cap = INITIAL_CLOSURES;
  else new_cap = closure_cap * 2;
  closure_param_start = grow_long_array(closure_param_start, new_cap);
  closure_param_len = grow_long_array(closure_param_len, new_cap);
  closure_body = grow_long_array(closure_body, new_cap);
  closure_env = grow_long_array(closure_env, new_cap);
  closure_cap = new_cap;
}

static long make_closure(long start, long len, long body, long env)
{
  ensure_closure_capacity();
  closure_count = closure_count + 1;
  closure_param_start[closure_count] = start;
  closure_param_len[closure_count] = len;
  closure_body[closure_count] = body;
  closure_env[closure_count] = env;
  return closure_count << 1;
}

static long eval(long node, long env)
{
  long k = kind[node];
  long a;
  long closure;
  long closure_index;
  long call_env;
  long offset;
  long end;
  int c;
  if (k == N_INT) return val_int(int_value[node]);
  if (k == N_VAR) return lookup_env(env, name_start[node], name_len[node]);
  if (k == N_ADD) return val_int(int_val(eval(left[node], env)) + int_val(eval(right[node], env)));
  if (k == N_SUB) return val_int(int_val(eval(left[node], env)) - int_val(eval(right[node], env)));
  if (k == N_MUL) return val_int(int_val(eval(left[node], env)) * int_val(eval(right[node], env)));
  if (k == N_DIV) return val_int(int_val(eval(left[node], env)) / int_val(eval(right[node], env)));
  if (k == N_EQ) return val_int(int_val(eval(left[node], env)) == int_val(eval(right[node], env)));
  if (k == N_NE) return val_int(int_val(eval(left[node], env)) != int_val(eval(right[node], env)));
  if (k == N_LT) return val_int(int_val(eval(left[node], env)) < int_val(eval(right[node], env)));
  if (k == N_LE) return val_int(int_val(eval(left[node], env)) <= int_val(eval(right[node], env)));
  if (k == N_GT) return val_int(int_val(eval(left[node], env)) > int_val(eval(right[node], env)));
  if (k == N_GE) return val_int(int_val(eval(left[node], env)) >= int_val(eval(right[node], env)));
  if (k == N_NEG) return val_int(0 - int_val(eval(left[node], env)));
  if (k == N_IF) {
    if (int_val(eval(left[node], env)) != 0) return eval(right[node], env);
    return eval(third[node], env);
  }
  if (k == N_LET) {
    a = eval(left[node], env);
    return eval(right[node], push_env(name_start[node], name_len[node], a, env));
  }
  if (k == N_LETREC) {
    closure = make_closure(name2_start[node], name2_len[node], left[node], 0);
    call_env = push_env(name_start[node], name_len[node], closure, env);
    closure_env[closure >> 1] = call_env;
    return eval(right[node], call_env);
  }
  if (k == N_FUN) return make_closure(name_start[node], name_len[node], left[node], env);
  if (k == N_CALL) {
    closure = eval(left[node], env);
    a = eval(right[node], env);
    if ((closure & 1) != 0 || closure == 0) die("expected function");
    closure_index = closure >> 1;
    call_env = push_env(closure_param_start[closure_index], closure_param_len[closure_index], a, closure_env[closure_index]);
    return eval(closure_body[closure_index], call_env);
  }
  if (k == N_SEQ) {
    eval(left[node], env);
    return eval(right[node], env);
  }
  if (k == N_WRITE_BYTE) {
    a = int_val(eval(left[node], env));
    fputc((int)(a & 255), stdout);
    return val_int(0);
  }
  if (k == N_WRITE_STRING) {
    offset = name_start[node];
    end = offset + name_len[node];
    while (offset < end) {
      c = string_next_char(&offset, end);
      fputc((int)(c & 255), stdout);
    }
    return val_int(0);
  }
  if (k == N_EXPECT_STRING) {
    a = int_val(eval(left[node], env));
    offset = name_start[node];
    end = offset + name_len[node];
    while (offset < end) {
      c = string_next_char(&offset, end);
      if (a != c) die("expect_string mismatch");
      a = fgetc(stdin);
      if (a == EOF) a = -1;
    }
    return val_int(a);
  }
  if (k == N_EXIT) {
    a = int_val(eval(left[node], env));
    exit((int)a);
  }
  if (k == N_READ_BYTE) {
    c = fgetc(stdin);
    if (c == EOF) c = -1;
    return val_int((long)c);
  }
  die("bad AST node");
  return 0;
}

int main(int argc, char **argv)
{
  long root;
  if (argc != 2) die("usage: mlc-interp-seed input.ml");
  src = read_file(argv[1], &src_len);
  pos = 0;
  root = parse_expr();
  skip_space();
  if (pos != src_len) die("trailing input");
  eval(root, 0);
  return 0;
}
