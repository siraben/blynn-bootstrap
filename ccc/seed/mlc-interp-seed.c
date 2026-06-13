/* mlc-interp-seed - tree-walking interpreter for the lambda-ladder root
 * (ccc/docs/lambda-ladder.md). This is the weak C root that runs exactly
 * two programs: core-lambda.ml (the Lambda-0 compiler, which self-hosts
 * here) and parenthetical.ml (the MZBC assembler). Its dialect is the
 * union of what those two sources use and nothing more:
 *
 *   - variables, decimal int literals, string literals, true/false, ()
 *   - fun x y -> e (curried), application
 *   - if/then/else (else optional), e1; e2
 *   - let / let rec (both top-level and "in" form), multi-parameter
 *     bindings as nested closures
 *   - bytes and arrays via builtin functions (no a.(i) syntax)
 *   - lists and pairs via builtin functions (cons/nil/null/hd/tl and
 *     pair/fst/snd; a cons cell or pair is a 2-field block, nil is 0,
 *     matching the VM's representation so Lambda-0 programs behave the
 *     same interpreted and compiled)
 *   - operators: + - * / mod, comparisons, && || (short-circuit),
 *     land, asr
 *   - primitive I/O: open_in/open_out/close_chan/read_byte/write_byte,
 *     exit, arg_count/arg_get
 *
 * No tuple syntax, no char or hex literals, no `and` bindings, no ADTs, no
 * pattern matching, no records, no modules, no type inference. The
 * dialect is a subset of OCaml so stage sources can be cross-checked
 * under a real OCaml with a small prelude.
 *
 * Written in the C subset accepted by both gcc and M2-Planet (via
 * M2-Mesoplanet): while loops, switch, malloc-only arena, no designated
 * initializers, no varargs use beyond stdio, no ternary operator, no
 * reliance on short-circuit &&/|| (M2-Planet evaluates both sides
 * bitwise), no pointer-to-pointer-to-struct types (char ** carriers with
 * casts instead), and no pointer +/- integer arithmetic except on char
 * pointers (M2-Planet does not scale it; indexing p[i] is fine).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- arena ---- */

static char *arena_ptr;
static long arena_left;

static void *xalloc(long n) {
  void *p;
  n = (n + 15) & (0 - 16);
  if (arena_left < n) {
    long chunk = 4194304;
    if (chunk < n) {
      chunk = n;
    }
    arena_ptr = malloc((size_t)chunk);
    if (arena_ptr == NULL) {
      fputs("mlc-interp: out of memory\n", stderr);
      exit(2);
    }
    arena_left = chunk;
  }
  p = arena_ptr;
  arena_ptr = arena_ptr + n;
  arena_left = arena_left - n;
  return p;
}

/* ---- diagnostics ---- */

static char errbuf[32];

static void print_err_long(long n) {
  char *buf;
  int i;
  unsigned long u;
  buf = errbuf;
  i = 31;
  buf[i] = 0;
  if (n < 0) {
    fputc('-', stderr);
    u = 0 - ((unsigned long)n);
  } else {
    u = (unsigned long)n;
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

/* ---- lexer ---- */

enum {
  T_EOF = 0,
  T_INT = 1,
  T_STR = 2,
  T_IDENT = 3,
  T_PUNCT = 4
};

static char *src;
static long srclen;
static long srcpos;
static long line;

static long tok_kind;
static long tok_int;
/* initialized to "" so strcmp in tok_is_punct/tok_is_ident is always safe:
 * M2-Planet's && does not short-circuit, so the strcmp runs even when the
 * token kind does not match */
static char *tok_text = "";   /* ident or punct spelling */
static char *tok_str = "";    /* string literal bytes */
static long tok_strlen;

static void lex_error(char *msg) {
  fputs("mlc-interp: lex error at line ", stderr);
  print_err_long(line);
  fputs(": ", stderr);
  fputs(msg, stderr);
  fputs("\n", stderr);
  exit(2);
}

static int peekc(void) {
  int c;
  if (srcpos >= srclen) {
    return -1;
  }
  /* plain byte load, then mask: a cast right next to the subscript makes
   * M2-Planet rescale the index by the cast type's size */
  c = src[srcpos];
  return c & 255;
}

static int peekc2(void) {
  int c;
  if (srcpos + 1 >= srclen) {
    return -1;
  }
  c = src[srcpos + 1];
  return c & 255;
}

static int nextc(void) {
  int c = peekc();
  srcpos = srcpos + 1;
  if (c == '\n') {
    line = line + 1;
  }
  return c;
}

static int is_ident_start(int c) {
  if (c >= 'a' && c <= 'z') return 1;
  if (c >= 'A' && c <= 'Z') return 1;
  if (c == '_') return 1;
  return 0;
}

static int is_ident_char(int c) {
  if (is_ident_start(c)) return 1;
  if (c >= '0' && c <= '9') return 1;
  if (c == '\'') return 1;
  return 0;
}

static int is_digit(int c) {
  return c >= '0' && c <= '9';
}

static void skip_ws_comments(void) {
  int depth;
  while (1) {
    int c = peekc();
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      nextc();
    } else if (c == '(' && peekc2() == '*') {
      nextc();
      nextc();
      depth = 1;
      while (depth > 0) {
        c = nextc();
        if (c == -1) {
          lex_error("unterminated comment");
        }
        if (c == '(' && peekc() == '*') {
          nextc();
          depth = depth + 1;
        } else if (c == '*' && peekc() == ')') {
          nextc();
          depth = depth - 1;
        }
      }
    } else {
      return;
    }
  }
}

static int read_escape(void) {
  int e = nextc();
  if (e == 'n') return 10;
  if (e == 't') return 9;
  if (e == 'r') return 13;
  if (e == '\\') return 92;
  if (e == '\'') return 39;
  if (e == '"') return 34;
  lex_error("bad escape");
  return 0;
}

static void next_token(void) {
  int c;
  long start;
  skip_ws_comments();
  c = peekc();
  if (c == -1) {
    tok_kind = T_EOF;
    return;
  }
  if (is_digit(c)) {
    long v = 0;
    while (is_digit(peekc())) {
      v = v * 10 + (nextc() - '0');
    }
    tok_kind = T_INT;
    tok_int = v;
    return;
  }
  if (is_ident_start(c)) {
    start = srcpos;
    while (is_ident_char(peekc())) {
      nextc();
    }
    tok_kind = T_IDENT;
    tok_text = xalloc(srcpos - start + 1);
    memcpy(tok_text, src + start, (size_t)(srcpos - start));
    tok_text[srcpos - start] = 0;
    return;
  }
  if (c == '"') {
    char *buf;
    long cap = 64;
    long len = 0;
    nextc();
    buf = xalloc(cap);
    while (1) {
      c = peekc();
      if (c == -1) {
        lex_error("unterminated string");
      }
      if (c == '"') {
        nextc();
        break;
      }
      if (c == '\\') {
        nextc();
        c = read_escape();
      } else {
        c = nextc();
      }
      if (len + 1 > cap) {
        char *nb = xalloc(cap * 2);
        memcpy(nb, buf, (size_t)len);
        buf = nb;
        cap = cap * 2;
      }
      buf[len] = (char)c;
      len = len + 1;
    }
    tok_kind = T_STR;
    tok_str = buf;
    tok_strlen = len;
    return;
  }
  /* punctuation, longest match first */
  {
    char *two = NULL;
    nextc();
    if (c == '-' && peekc() == '>') two = "->";
    if (c == '<' && peekc() == '>') two = "<>";
    if (c == '<' && peekc() == '=') two = "<=";
    if (c == '>' && peekc() == '=') two = ">=";
    if (c == '&' && peekc() == '&') two = "&&";
    if (c == '|' && peekc() == '|') two = "||";
    if (two != NULL) {
      nextc();
      tok_kind = T_PUNCT;
      tok_text = two;
      return;
    }
    tok_kind = T_PUNCT;
    tok_text = xalloc(2);
    tok_text[0] = (char)c;
    tok_text[1] = 0;
    return;
  }
}

/* ---- AST ---- */

enum {
  A_INT = 1,
  A_STR = 2,
  A_VAR = 3,
  A_IF = 4,
  A_FUN = 5,
  A_APP = 6,
  A_LET = 7,
  A_SEQ = 8,
  A_BINOP = 9,
  A_AND = 10,   /* short-circuit && */
  A_OR = 11     /* short-circuit || */
};

enum {
  B_ADD = 1, B_SUB = 2, B_MUL = 3, B_DIV = 4, B_MOD = 5,
  B_EQ = 6, B_NE = 7, B_LT = 8, B_LE = 9, B_GT = 10, B_GE = 11,
  B_LAND = 12, B_ASR = 17
};

/* M2-Planet rejects pointer-to-pointer-to-struct types (Ast **), so
 * arrays of Ast pointers are carried as char ** and cast at use sites. */
typedef struct Ast Ast;
struct Ast {
  int tag;
  long ival;       /* A_INT value; A_BINOP op; A_LET recflag */
  char *sval;      /* A_VAR name; A_FUN param; A_STR bytes */
  long slen;       /* A_STR length */
  Ast *a;
  Ast *b;
  Ast *c;
  char **names;    /* A_LET binding names */
  char **exprs;    /* really Ast *: A_LET binding exprs */
  long nbind;
  long lineno;
};

static Ast *ast_at(char **arr, long i) {
  return (Ast *)arr[i];
}

static Ast *new_ast(int tag) {
  Ast *n = xalloc((long)sizeof(Ast));
  memset(n, 0, sizeof(Ast));
  n->tag = tag;
  n->lineno = line;
  return n;
}

/* ---- parser ---- */

static void parse_error(char *msg) {
  fputs("mlc-interp: parse error at line ", stderr);
  print_err_long(line);
  fputs(": ", stderr);
  fputs(msg, stderr);
  fputs("\n", stderr);
  exit(2);
}

static int tok_is_punct(char *s) {
  return tok_kind == T_PUNCT && strcmp(tok_text, s) == 0;
}

static int tok_is_ident(char *s) {
  return tok_kind == T_IDENT && strcmp(tok_text, s) == 0;
}

static void expect_punct(char *s) {
  if (!tok_is_punct(s)) {
    fputs("mlc-interp: parse error at line ", stderr);
    print_err_long(line);
    fputs(": expected ", stderr);
    fputs(s, stderr);
    fputs("\n", stderr);
    exit(2);
  }
  next_token();
}

static int is_keyword(char *s) {
  if (strcmp(s, "let") == 0) return 1;
  if (strcmp(s, "rec") == 0) return 1;
  if (strcmp(s, "in") == 0) return 1;
  if (strcmp(s, "if") == 0) return 1;
  if (strcmp(s, "then") == 0) return 1;
  if (strcmp(s, "else") == 0) return 1;
  if (strcmp(s, "fun") == 0) return 1;
  if (strcmp(s, "true") == 0) return 1;
  if (strcmp(s, "false") == 0) return 1;
  if (strcmp(s, "mod") == 0) return 1;
  if (strcmp(s, "land") == 0) return 1;
  if (strcmp(s, "asr") == 0) return 1;
  return 0;
}

static Ast *parse_expr(void);

static Ast *mk_binop(long op, Ast *l, Ast *r) {
  Ast *n = new_ast(A_BINOP);
  n->ival = op;
  n->a = l;
  n->b = r;
  return n;
}

/* atom := int | string | ident | true | false | ( ) | ( expr ) */
static Ast *parse_atom(void) {
  Ast *n;
  if (tok_kind == T_INT) {
    n = new_ast(A_INT);
    n->ival = tok_int;
    next_token();
    return n;
  }
  if (tok_kind == T_STR) {
    n = new_ast(A_STR);
    n->sval = tok_str;
    n->slen = tok_strlen;
    next_token();
    return n;
  }
  if (tok_kind == T_IDENT) {
    if (tok_is_ident("true")) {
      n = new_ast(A_INT);
      n->ival = 1;
      next_token();
      return n;
    }
    if (tok_is_ident("false")) {
      n = new_ast(A_INT);
      n->ival = 0;
      next_token();
      return n;
    }
    if (is_keyword(tok_text)) {
      parse_error("unexpected keyword");
    }
    n = new_ast(A_VAR);
    n->sval = tok_text;
    next_token();
    return n;
  }
  if (tok_is_punct("(")) {
    next_token();
    if (tok_is_punct(")")) {
      next_token();
      n = new_ast(A_INT);
      n->ival = 0;  /* unit */
      return n;
    }
    n = parse_expr();
    expect_punct(")");
    return n;
  }
  parse_error("unexpected token");
  return NULL;
}

static int starts_atom(void) {
  if (tok_kind == T_INT || tok_kind == T_STR) return 1;
  if (tok_kind == T_IDENT && !is_keyword(tok_text)) return 1;
  if (tok_kind == T_IDENT && (tok_is_ident("true") || tok_is_ident("false"))) return 1;
  if (tok_is_punct("(")) return 1;
  return 0;
}

static Ast *parse_app(void) {
  Ast *f = parse_atom();
  while (starts_atom()) {
    Ast *n = new_ast(A_APP);
    n->a = f;
    n->b = parse_atom();
    f = n;
  }
  return f;
}

static Ast *parse_mul(void) {
  Ast *l = parse_app();
  while (1) {
    long op = 0;
    if (tok_is_punct("*")) op = B_MUL;
    else if (tok_is_punct("/")) op = B_DIV;
    else if (tok_is_ident("mod")) op = B_MOD;
    else if (tok_is_ident("land")) op = B_LAND;
    else if (tok_is_ident("asr")) op = B_ASR;
    else return l;
    next_token();
    l = mk_binop(op, l, parse_app());
  }
}

static Ast *parse_add(void) {
  Ast *l = parse_mul();
  while (1) {
    long op = 0;
    if (tok_is_punct("+")) op = B_ADD;
    else if (tok_is_punct("-")) op = B_SUB;
    else return l;
    next_token();
    l = mk_binop(op, l, parse_mul());
  }
}

static Ast *parse_cmp(void) {
  Ast *l = parse_add();
  while (1) {
    long op = 0;
    if (tok_is_punct("=")) op = B_EQ;
    else if (tok_is_punct("<>")) op = B_NE;
    else if (tok_is_punct("<")) op = B_LT;
    else if (tok_is_punct("<=")) op = B_LE;
    else if (tok_is_punct(">")) op = B_GT;
    else if (tok_is_punct(">=")) op = B_GE;
    else return l;
    next_token();
    l = mk_binop(op, l, parse_add());
  }
}

static Ast *parse_andor(void) {
  Ast *l = parse_cmp();
  while (1) {
    int isand;
    Ast *n;
    if (tok_is_punct("&&")) isand = 1;
    else if (tok_is_punct("||")) isand = 0;
    else return l;
    next_token();
    if (isand) {
      n = new_ast(A_AND);
    } else {
      n = new_ast(A_OR);
    }
    n->a = l;
    n->b = parse_cmp();
    l = n;
  }
}

/* binding := name param* = expr | () = expr | _ = expr
 * Results are returned in bind_name/bind_expr: an Ast ** out-parameter
 * would be a pointer-to-pointer-to-struct, which M2-Planet rejects. */
static char *bind_name;
static Ast *bind_expr;

static void parse_binding(void) {
  char *name;
  char **params;
  long nparams = 0;
  long i;
  Ast *body;
  params = xalloc(32 * (long)sizeof(char *));
  if (tok_is_punct("(")) {
    next_token();
    expect_punct(")");
    name = "_";
  } else if (tok_kind == T_IDENT && !is_keyword(tok_text)) {
    name = tok_text;
    next_token();
  } else {
    parse_error("expected binding name");
    return;
  }
  while (1) {
    if (tok_kind == T_IDENT && !is_keyword(tok_text)) {
      if (nparams >= 32) {
        parse_error("too many parameters");
      }
      params[nparams] = tok_text;
      nparams = nparams + 1;
      next_token();
    } else if (tok_is_punct("(")) {
      /* unit parameter: f () = ... */
      next_token();
      expect_punct(")");
      if (nparams >= 32) {
        parse_error("too many parameters");
      }
      params[nparams] = "_";
      nparams = nparams + 1;
    } else {
      break;
    }
  }
  expect_punct("=");
  body = parse_expr();
  i = nparams;
  while (i > 0) {
    Ast *f = new_ast(A_FUN);
    f->sval = params[i - 1];
    f->a = body;
    body = f;
    i = i - 1;
  }
  bind_name = name;
  bind_expr = body;
}

static Ast *parse_let_common(void) {
  /* caller consumed "let"; returns A_LET with body NULL (filled by caller
   * for the "in" form, or left NULL at top level). Exactly one binding:
   * the dialect has no `and`. */
  Ast *n = new_ast(A_LET);
  n->names = xalloc(1 * (long)sizeof(char *));
  n->exprs = xalloc(1 * (long)sizeof(char *));
  n->ival = 0;
  if (tok_is_ident("rec")) {
    n->ival = 1;
    next_token();
  }
  parse_binding();
  n->names[0] = bind_name;
  n->exprs[0] = (char *)bind_expr;
  n->nbind = 1;
  return n;
}

static Ast *parse_expr_nosemi(void) {
  if (tok_is_ident("fun")) {
    char **params;
    long nparams = 0;
    long i;
    Ast *body;
    params = xalloc(32 * (long)sizeof(char *));
    next_token();
    while (1) {
      if (tok_kind == T_IDENT && !is_keyword(tok_text)) {
        if (nparams >= 32) {
          parse_error("too many parameters");
        }
        params[nparams] = tok_text;
        nparams = nparams + 1;
        next_token();
      } else if (tok_is_punct("(")) {
        next_token();
        expect_punct(")");
        if (nparams >= 32) {
          parse_error("too many parameters");
        }
        params[nparams] = "_";
        nparams = nparams + 1;
      } else {
        break;
      }
    }
    if (nparams == 0) {
      parse_error("fun needs parameters");
    }
    expect_punct("->");
    body = parse_expr();
    i = nparams;
    while (i > 0) {
      Ast *f = new_ast(A_FUN);
      f->sval = params[i - 1];
      f->a = body;
      body = f;
      i = i - 1;
    }
    return body;
  }
  if (tok_is_ident("if")) {
    Ast *n = new_ast(A_IF);
    next_token();
    n->a = parse_expr();
    if (!tok_is_ident("then")) {
      parse_error("expected then");
    }
    next_token();
    n->b = parse_expr_nosemi();
    if (tok_is_ident("else")) {
      next_token();
      n->c = parse_expr_nosemi();
    } else {
      Ast *z = new_ast(A_INT);
      z->ival = 0;
      n->c = z;
    }
    return n;
  }
  if (tok_is_ident("let")) {
    Ast *n;
    next_token();
    n = parse_let_common();
    if (!tok_is_ident("in")) {
      parse_error("expected in");
    }
    next_token();
    n->c = parse_expr();
    return n;
  }
  return parse_andor();
}

static Ast *parse_expr(void) {
  Ast *l = parse_expr_nosemi();
  while (tok_is_punct(";")) {
    Ast *n = new_ast(A_SEQ);
    next_token();
    n->a = l;
    n->b = parse_expr_nosemi();
    l = n;
  }
  return l;
}

/* program := (let [rec] bindings)* */
static char **toplevels; /* really Ast * elements */
static long ntoplevels;

static void parse_program(void) {
  long cap = 1024;
  toplevels = xalloc(cap * (long)sizeof(char *));
  ntoplevels = 0;
  next_token();
  while (tok_kind != T_EOF) {
    if (!tok_is_ident("let")) {
      parse_error("expected top-level let");
    }
    next_token();
    if (ntoplevels >= cap) {
      parse_error("too many top-level declarations");
    }
    toplevels[ntoplevels] = (char *)parse_let_common();
    ntoplevels = ntoplevels + 1;
  }
}

/* ---- values ---- */

enum {
  V_INT = 1,
  V_BYTES = 2,
  V_BLOCK = 3,
  V_CLOSURE = 4,
  V_PRIM = 5
};

typedef struct Val Val;
typedef struct Env Env;

/* fields/pargs hold Val pointers but are typed char ** because M2-Planet
 * rejects pointer-to-pointer-to-struct types; val_at casts them back. */
struct Val {
  int tag;
  long ival;        /* V_INT */
  char *bdata;      /* V_BYTES */
  long blen;
  char **fields;    /* V_BLOCK: really Val * elements */
  long nfields;
  char *param;      /* V_CLOSURE */
  Ast *body;
  Env *env;
  long prim;        /* V_PRIM: id */
  long arity;       /* V_PRIM: remaining args */
  char **pargs;     /* V_PRIM: collected args, really Val * elements */
  long npargs;
};

static Val *val_at(char **arr, long i) {
  return (Val *)arr[i];
}

struct Env {
  char *name;
  Val *val;
  Env *next;
};

static Val *new_val(int tag) {
  Val *v = xalloc((long)sizeof(Val));
  memset(v, 0, sizeof(Val));
  v->tag = tag;
  return v;
}

static Val *val_unit;
static Val *val_true;
static Val *val_false;

static Val *mk_int(long n) {
  Val *v;
  if (n == 0) {
    return val_false;
  }
  if (n == 1) {
    return val_true;
  }
  v = new_val(V_INT);
  v->ival = n;
  return v;
}

static Val *mk_bytes(long len) {
  Val *v = new_val(V_BYTES);
  v->bdata = xalloc(len + 1);
  memset(v->bdata, 0, (size_t)(len + 1));
  v->blen = len;
  return v;
}

static Env *env_bind(Env *env, char *name, Val *v) {
  Env *e = xalloc((long)sizeof(Env));
  e->name = name;
  e->val = v;
  e->next = env;
  return e;
}

static long cur_line;

static void run_error(char *msg) {
  fputs("mlc-interp: runtime error at line ", stderr);
  print_err_long(cur_line);
  fputs(": ", stderr);
  fputs(msg, stderr);
  fputs("\n", stderr);
  exit(2);
}

static Val *env_lookup(Env *env, char *name) {
  while (env != NULL) {
    if (strcmp(env->name, name) == 0) {
      if (env->val == NULL) {
        run_error("use of let-rec binding before definition");
      }
      return env->val;
    }
    env = env->next;
  }
  fputs("mlc-interp: unbound variable ", stderr);
  fputs(name, stderr);
  fputs(" at line ", stderr);
  print_err_long(cur_line);
  fputs("\n", stderr);
  exit(2);
  return NULL;
}

static long val_int(Val *v) {
  if (v->tag != V_INT) {
    run_error("expected an integer");
  }
  return v->ival;
}

/* ---- primitives ---- */

enum {
  P_EXIT = 1,
  P_OPEN_IN = 2,
  P_OPEN_OUT = 3,
  P_CLOSE_CHAN = 4,
  P_READ_BYTE = 5,
  P_WRITE_BYTE = 6,
  P_BYTES_CREATE = 7,
  P_BYTES_LENGTH = 8,
  P_BYTES_GET = 9,
  P_BYTES_SET = 10,
  P_ARG_COUNT = 11,
  P_ARG_GET = 12,
  P_NOT = 15,
  P_ARRAY_MAKE = 16,
  P_ARRAY_GET = 17,
  P_ARRAY_SET = 18,
  P_ARRAY_LENGTH = 19,
  P_CONS = 20,
  P_NULL = 21,
  P_HD = 22,
  P_TL = 23
};

enum { NCHANS = 256 };
/* FILE ** is a pointer-to-pointer-to-struct, which M2-Planet rejects, so
 * the channel slots are stored as char * and cast at use sites. */
static char **chans;
static int vm_argc;
static char **vm_argv; /* full argv; interpreted-program args start at 2 */

static long find_chan_slot(void) {
  long i = 3;
  while (i < NCHANS) {
    if (chans[i] == NULL) {
      return i;
    }
    i = i + 1;
  }
  run_error("out of channel slots");
  return -1;
}

static char pathbuf[4096];

static char *path_buf(Val *b) {
  char *buf;
  buf = pathbuf;
  if (b->tag != V_BYTES) {
    run_error("expected a string path");
  }
  if (b->blen >= 4096) {
    run_error("path too long");
  }
  /* parenthesized: M2-Planet parses (size_t)b->blen as ((size_t)b)->blen */
  memcpy(buf, b->bdata, (size_t)(b->blen));
  buf[b->blen] = 0;
  return buf;
}

/* a holds Val pointers as char * (see struct Val) */
static Val *apply_prim(long prim, char **a) {
  FILE *f;
  long slot;
  long h;
  long i;
  int c;
  Val *v;
  Val *a0;
  Val *a1;
  Val *a2;
  a0 = (Val *)a[0];
  a1 = (Val *)a[1];
  a2 = (Val *)a[2];
  switch (prim) {
  case P_EXIT:
    fflush(stdout);
    exit((int)val_int(a0));
  case P_OPEN_IN:
    f = fopen(path_buf(a0), "rb");
    if (f == NULL) {
      return mk_int(-1);
    }
    slot = find_chan_slot();
    chans[slot] = (char *)f;
    return mk_int(slot);
  case P_OPEN_OUT:
    f = fopen(path_buf(a0), "wb");
    if (f == NULL) {
      return mk_int(-1);
    }
    slot = find_chan_slot();
    chans[slot] = (char *)f;
    return mk_int(slot);
  case P_CLOSE_CHAN:
    h = val_int(a0);
    if (h < 0 || h >= NCHANS) {
      run_error("close_chan: bad handle");
    }
    if (chans[h] == NULL) {
      run_error("close_chan: bad handle");
    }
    if (h > 2) {
      fclose((FILE *)chans[h]);
      chans[h] = NULL;
    }
    return val_unit;
  case P_READ_BYTE:
    h = val_int(a0);
    if (h < 0 || h >= NCHANS) {
      run_error("read_byte: bad handle");
    }
    if (chans[h] == NULL) {
      run_error("read_byte: bad handle");
    }
    c = fgetc((FILE *)chans[h]);
    if (c == EOF) {
      return mk_int(-1);
    }
    return mk_int(c & 255);
  case P_WRITE_BYTE:
    h = val_int(a0);
    if (h < 0 || h >= NCHANS) {
      run_error("write_byte: bad handle");
    }
    if (chans[h] == NULL) {
      run_error("write_byte: bad handle");
    }
    fputc((int)(val_int(a1) & 255), (FILE *)chans[h]);
    return val_unit;
  case P_BYTES_CREATE:
    h = val_int(a0);
    if (h < 0) {
      run_error("bytes_create: negative length");
    }
    return mk_bytes(h);
  case P_BYTES_LENGTH:
    if (a0->tag != V_BYTES) {
      run_error("bytes_length: not bytes");
    }
    return mk_int(a0->blen);
  case P_BYTES_GET:
    if (a0->tag != V_BYTES) {
      run_error("bytes_get: not bytes");
    }
    i = val_int(a1);
    if (i < 0 || i >= a0->blen) {
      run_error("bytes_get: out of bounds");
    }
    /* plain byte load, then mask: a cast right next to the subscript
     * makes M2-Planet rescale the index by the cast type's size */
    h = a0->bdata[i];
    return mk_int(h & 255);
  case P_BYTES_SET:
    if (a0->tag != V_BYTES) {
      run_error("bytes_set: not bytes");
    }
    i = val_int(a1);
    if (i < 0 || i >= a0->blen) {
      run_error("bytes_set: out of bounds");
    }
    a0->bdata[i] = (char)(val_int(a2) & 255);
    return val_unit;
  case P_ARG_COUNT:
    return mk_int(vm_argc);
  case P_ARG_GET:
    i = val_int(a0);
    if (i < 0 || i >= vm_argc) {
      run_error("arg_get: out of range");
    }
    v = mk_bytes((long)strlen(vm_argv[i + 2]));
    memcpy(v->bdata, vm_argv[i + 2], strlen(vm_argv[i + 2]));
    return v;
  case P_NOT:
    if (val_int(a0) == 0) {
      return val_true;
    }
    return val_false;
  case P_ARRAY_MAKE:
    h = val_int(a0);
    if (h < 1) {
      run_error("array_make: length must be positive");
    }
    v = new_val(V_BLOCK);
    v->nfields = h;
    v->fields = xalloc((h + 1) * (long)sizeof(char *));
    i = 0;
    while (i < h) {
      v->fields[i] = (char *)a1;
      i = i + 1;
    }
    return v;
  case P_ARRAY_GET:
    if (a0->tag != V_BLOCK) {
      run_error("array_get: not an array");
    }
    i = val_int(a1);
    if (i < 0 || i >= a0->nfields) {
      run_error("array_get: out of bounds");
    }
    return val_at(a0->fields, i);
  case P_ARRAY_SET:
    if (a0->tag != V_BLOCK) {
      run_error("array_set: not an array");
    }
    i = val_int(a1);
    if (i < 0 || i >= a0->nfields) {
      run_error("array_set: out of bounds");
    }
    a0->fields[i] = (char *)a2;
    return val_unit;
  case P_ARRAY_LENGTH:
    if (a0->tag != V_BLOCK) {
      run_error("array_length: not an array");
    }
    return mk_int(a0->nfields);
  case P_CONS:
    /* a cons cell or pair: a 2-field block, like the VM's MAKEBLOCK 0 2 */
    v = new_val(V_BLOCK);
    v->nfields = 2;
    v->fields = xalloc(2 * (long)sizeof(char *));
    v->fields[0] = (char *)a0;
    v->fields[1] = (char *)a1;
    return v;
  case P_NULL:
    /* nil is the integer 0; any block is a non-empty list */
    if (a0->tag == V_INT) {
      if (a0->ival == 0) {
        return val_true;
      }
    }
    return val_false;
  case P_HD:
    if (a0->tag != V_BLOCK) {
      run_error("hd/fst: not a cons cell or pair");
    }
    if (a0->nfields != 2) {
      run_error("hd/fst: not a cons cell or pair");
    }
    return val_at(a0->fields, 0);
  case P_TL:
    if (a0->tag != V_BLOCK) {
      run_error("tl/snd: not a cons cell or pair");
    }
    if (a0->nfields != 2) {
      run_error("tl/snd: not a cons cell or pair");
    }
    return val_at(a0->fields, 1);
  default:
    run_error("unknown primitive");
    return NULL;
  }
}

static long prim_arity_of(long prim) {
  switch (prim) {
  case P_WRITE_BYTE:
  case P_BYTES_GET:
  case P_ARRAY_MAKE:
  case P_ARRAY_GET:
  case P_CONS:
    return 2;
  case P_BYTES_SET:
  case P_ARRAY_SET:
    return 3;
  default:
    return 1;
  }
}

static Val *mk_prim(long prim) {
  Val *v = new_val(V_PRIM);
  v->prim = prim;
  v->arity = prim_arity_of(prim);
  v->pargs = NULL;
  v->npargs = 0;
  return v;
}

/* ---- evaluator (tail-call optimizing) ---- */

static Val *eval(Ast *ast, Env *env) {
  while (1) {
    cur_line = ast->lineno;
    switch (ast->tag) {
    case A_INT:
      return mk_int(ast->ival);
    case A_STR: {
      Val *v = new_val(V_BYTES);
      v->bdata = ast->sval;
      v->blen = ast->slen;
      return v;
    }
    case A_VAR:
      return env_lookup(env, ast->sval);
    case A_IF:
      if (val_int(eval(ast->a, env)) != 0) {
        ast = ast->b;
      } else {
        ast = ast->c;
      }
      /* M2-Planet rejects continue inside switch; break re-enters the loop */
      break;
    case A_FUN: {
      Val *v = new_val(V_CLOSURE);
      v->param = ast->sval;
      v->body = ast->a;
      v->env = env;
      return v;
    }
    case A_SEQ:
      eval(ast->a, env);
      ast = ast->b;
      break;
    case A_AND:
      if (val_int(eval(ast->a, env)) == 0) {
        return val_false;
      }
      ast = ast->b;
      break;
    case A_OR:
      if (val_int(eval(ast->a, env)) != 0) {
        return val_true;
      }
      ast = ast->b;
      break;
    case A_BINOP: {
      long l = val_int(eval(ast->a, env));
      long r = val_int(eval(ast->b, env));
      switch (ast->ival) {
      case B_ADD: return mk_int(l + r);
      case B_SUB: return mk_int(l - r);
      case B_MUL: return mk_int(l * r);
      case B_DIV:
        if (r == 0) run_error("division by zero");
        return mk_int(l / r);
      case B_MOD:
        if (r == 0) run_error("division by zero");
        return mk_int(l % r);
      case B_EQ:
        if (l == r) { return val_true; }
        return val_false;
      case B_NE:
        if (l != r) { return val_true; }
        return val_false;
      case B_LT:
        if (l < r) { return val_true; }
        return val_false;
      case B_LE:
        if (l <= r) { return val_true; }
        return val_false;
      case B_GT:
        if (l > r) { return val_true; }
        return val_false;
      case B_GE:
        if (l >= r) { return val_true; }
        return val_false;
      case B_LAND: return mk_int(l & r);
      case B_ASR: return mk_int(l >> r);
      default: run_error("bad operator");
      }
      return NULL;
    }
    case A_LET: {
      if (ast->ival == 0) {
        env = env_bind(env, ast->names[0], eval(ast_at(ast->exprs, 0), env));
      } else {
        /* evaluate in the extended env, then patch the cell */
        env = env_bind(env, ast->names[0], NULL);
        env->val = eval(ast_at(ast->exprs, 0), env);
      }
      ast = ast->c;
      break;
    }
    case A_APP: {
      Val *f = eval(ast->a, env);
      Val *arg = eval(ast->b, env);
      while (1) {
        if (f->tag == V_CLOSURE) {
          env = env_bind(f->env, f->param, arg);
          ast = f->body;
          break;
        }
        if (f->tag == V_PRIM) {
          Val *np;
          long i;
          if (f->arity == 1) {
            /* arena-allocated: M2-Planet miscompiles local arrays that
             * decay to a pointer argument */
            char **args;
            args = xalloc(4 * (long)sizeof(char *));
            args[0] = NULL;
            args[1] = NULL;
            args[2] = NULL;
            args[3] = NULL;
            i = 0;
            while (i < f->npargs) {
              args[i] = f->pargs[i];
              i = i + 1;
            }
            args[f->npargs] = (char *)arg;
            return apply_prim(f->prim, args);
          }
          np = new_val(V_PRIM);
          np->prim = f->prim;
          np->arity = f->arity - 1;
          np->npargs = f->npargs + 1;
          np->pargs = xalloc(np->npargs * (long)sizeof(char *));
          i = 0;
          while (i < f->npargs) {
            np->pargs[i] = f->pargs[i];
            i = i + 1;
          }
          np->pargs[f->npargs] = (char *)arg;
          return np;
        }
        run_error("application of a non-function");
      }
      break;
    }
    default:
      run_error("bad AST node");
    }
  }
}

/* ---- driver ---- */

static Env *global_env(void) {
  Env *env = NULL;
  env = env_bind(env, "exit", mk_prim(P_EXIT));
  env = env_bind(env, "open_in", mk_prim(P_OPEN_IN));
  env = env_bind(env, "open_out", mk_prim(P_OPEN_OUT));
  env = env_bind(env, "close_chan", mk_prim(P_CLOSE_CHAN));
  env = env_bind(env, "read_byte", mk_prim(P_READ_BYTE));
  env = env_bind(env, "write_byte", mk_prim(P_WRITE_BYTE));
  env = env_bind(env, "bytes_create", mk_prim(P_BYTES_CREATE));
  env = env_bind(env, "bytes_length", mk_prim(P_BYTES_LENGTH));
  env = env_bind(env, "bytes_get", mk_prim(P_BYTES_GET));
  env = env_bind(env, "bytes_set", mk_prim(P_BYTES_SET));
  env = env_bind(env, "arg_count", mk_prim(P_ARG_COUNT));
  env = env_bind(env, "arg_get", mk_prim(P_ARG_GET));
  env = env_bind(env, "not", mk_prim(P_NOT));
  env = env_bind(env, "array_make", mk_prim(P_ARRAY_MAKE));
  env = env_bind(env, "array_get", mk_prim(P_ARRAY_GET));
  env = env_bind(env, "array_set", mk_prim(P_ARRAY_SET));
  env = env_bind(env, "array_length", mk_prim(P_ARRAY_LENGTH));
  env = env_bind(env, "string_length", mk_prim(P_BYTES_LENGTH));
  env = env_bind(env, "string_get", mk_prim(P_BYTES_GET));
  /* lists and pairs share one block shape: pair/fst/snd are aliases of
   * cons/hd/tl, and nil is the integer 0 */
  env = env_bind(env, "cons", mk_prim(P_CONS));
  env = env_bind(env, "nil", val_unit);
  env = env_bind(env, "null", mk_prim(P_NULL));
  env = env_bind(env, "hd", mk_prim(P_HD));
  env = env_bind(env, "tl", mk_prim(P_TL));
  env = env_bind(env, "pair", mk_prim(P_CONS));
  env = env_bind(env, "fst", mk_prim(P_HD));
  env = env_bind(env, "snd", mk_prim(P_TL));
  return env;
}

int main(int argc, char **argv) {
  FILE *f;
  long n;
  Env *env;
  long t;
  if (argc < 2) {
    fputs("usage: mlc-interp program.ml [args...]\n", stderr);
    return 2;
  }
  f = fopen(argv[1], "rb");
  if (f == NULL) {
    fputs("mlc-interp: cannot open ", stderr);
    fputs(argv[1], stderr);
    fputs("\n", stderr);
    return 2;
  }
  fseek(f, 0, SEEK_END);
  srclen = ftell(f);
  fseek(f, 0, SEEK_SET);
  src = xalloc(srclen + 1);
  n = (long)fread(src, 1, (size_t)srclen, f);
  if (n != srclen) {
    fputs("mlc-interp: read error\n", stderr);
    return 2;
  }
  src[srclen] = 0;
  fclose(f);

  chans = xalloc(NCHANS * (long)sizeof(char *));
  memset(chans, 0, NCHANS * sizeof(char *));
  chans[0] = (char *)stdin;
  chans[1] = (char *)stdout;
  chans[2] = (char *)stderr;
  vm_argc = argc - 2;
  vm_argv = argv;

  val_unit = new_val(V_INT);
  val_unit->ival = 0;
  val_false = val_unit;
  val_true = new_val(V_INT);
  val_true->ival = 1;

  line = 1;
  srcpos = 0;
  parse_program();

  env = global_env();
  t = 0;
  while (t < ntoplevels) {
    Ast *d = ast_at(toplevels, t);
    if (d->ival == 0) {
      env = env_bind(env, d->names[0], eval(ast_at(d->exprs, 0), env));
    } else {
      env = env_bind(env, d->names[0], NULL);
      env->val = eval(ast_at(d->exprs, 0), env);
    }
    t = t + 1;
  }
  fflush(stdout);
  return 0;
}
