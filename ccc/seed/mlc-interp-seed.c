/* mlc-interp-seed - tree-walking interpreter for the core ML bootstrap
 * dialect (plan.md §5). This is the weak C root that runs the first ML
 * bootstrap stages; it must stay a tiny strict core:
 *
 *   - variables, int/char/string literals, true/false, ()
 *   - fun x y -> e (curried), application
 *   - if/then/else, e1; e2
 *   - let / let rec ... and ... (both top-level and "in" form)
 *   - tuples (e1, e2) with fst/snd only
 *   - bytes and arrays via builtin functions (no a.(i) syntax)
 *   - primitive I/O: open_in/open_out/close_chan/read_byte/write_byte,
 *     exit, arg_count/arg_get
 *
 * No ADT declarations, no pattern matching, no records, no modules, no
 * type inference. The dialect is a subset of OCaml so stage sources can be
 * cross-checked under a real OCaml with a small prelude.
 *
 * Written in a conservative M2-Planet-friendly C subset: while loops,
 * switch, malloc-only arena, no designated initializers, no varargs use
 * beyond stdio.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- arena ---- */

static char *arena_ptr;
static long arena_left;

static void *xalloc(long n) {
  void *p;
  n = (n + 15) & ~15L;
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
static char *tok_text;   /* ident or punct spelling */
static char *tok_str;    /* string literal bytes */
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
  if (srcpos >= srclen) {
    return -1;
  }
  return 255 & (int)(unsigned char)src[srcpos];
}

static int peekc2(void) {
  if (srcpos + 1 >= srclen) {
    return -1;
  }
  return 255 & (int)(unsigned char)src[srcpos + 1];
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
  int h;
  int v;
  if (e == 'n') return 10;
  if (e == 't') return 9;
  if (e == 'r') return 13;
  if (e == '\\') return 92;
  if (e == '\'') return 39;
  if (e == '"') return 34;
  if (e == 'x') {
    v = 0;
    h = 0;
    while (h < 2) {
      int d = nextc();
      if (d >= '0' && d <= '9') {
        v = v * 16 + (d - '0');
      } else if (d >= 'a' && d <= 'f') {
        v = v * 16 + (d - 'a' + 10);
      } else if (d >= 'A' && d <= 'F') {
        v = v * 16 + (d - 'A' + 10);
      } else {
        lex_error("bad hex escape");
      }
      h = h + 1;
    }
    return v;
  }
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
    if (c == '0' && (peekc2() == 'x' || peekc2() == 'X')) {
      nextc();
      nextc();
      c = peekc();
      if (!is_digit(c) && !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F')) {
        lex_error("empty hex literal");
      }
      while (1) {
        c = peekc();
        if (is_digit(c)) {
          v = v * 16 + (c - '0');
        } else if (c >= 'a' && c <= 'f') {
          v = v * 16 + (c - 'a' + 10);
        } else if (c >= 'A' && c <= 'F') {
          v = v * 16 + (c - 'A' + 10);
        } else {
          break;
        }
        nextc();
      }
    } else {
      while (is_digit(peekc())) {
        v = v * 10 + (nextc() - '0');
      }
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
  if (c == '\'') {
    /* char literal: 'c' or escape; identifiers never start with ' */
    nextc();
    c = nextc();
    if (c == '\\') {
      c = read_escape();
    }
    if (nextc() != '\'') {
      lex_error("unterminated char literal");
    }
    tok_kind = T_INT;
    tok_int = c;
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
    if (c == ';' && peekc() == ';') two = ";;";
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
  A_OR = 11,    /* short-circuit || */
  A_TUPLE = 12
};

enum {
  B_ADD = 1, B_SUB = 2, B_MUL = 3, B_DIV = 4, B_MOD = 5,
  B_EQ = 6, B_NE = 7, B_LT = 8, B_LE = 9, B_GT = 10, B_GE = 11,
  B_LAND = 12, B_LOR = 13, B_LXOR = 14, B_LSL = 15, B_LSR = 16, B_ASR = 17
};

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
  Ast **exprs;     /* A_LET binding exprs; A_TUPLE elements */
  long nbind;
  long lineno;
};

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
  if (strcmp(s, "and") == 0) return 1;
  if (strcmp(s, "in") == 0) return 1;
  if (strcmp(s, "if") == 0) return 1;
  if (strcmp(s, "then") == 0) return 1;
  if (strcmp(s, "else") == 0) return 1;
  if (strcmp(s, "fun") == 0) return 1;
  if (strcmp(s, "true") == 0) return 1;
  if (strcmp(s, "false") == 0) return 1;
  if (strcmp(s, "mod") == 0) return 1;
  if (strcmp(s, "land") == 0) return 1;
  if (strcmp(s, "lor") == 0) return 1;
  if (strcmp(s, "lxor") == 0) return 1;
  if (strcmp(s, "lsl") == 0) return 1;
  if (strcmp(s, "lsr") == 0) return 1;
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

/* atom := int | string | ident | true | false | ( ) | ( expr ) | (e1, e2) */
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
    if (tok_is_punct(",")) {
      Ast *t = new_ast(A_TUPLE);
      t->exprs = xalloc(8 * (long)sizeof(Ast *));
      t->exprs[0] = n;
      t->nbind = 1;
      while (tok_is_punct(",")) {
        next_token();
        if (t->nbind >= 8) {
          parse_error("tuple too wide for seed dialect");
        }
        t->exprs[t->nbind] = parse_expr();
        t->nbind = t->nbind + 1;
      }
      expect_punct(")");
      return t;
    }
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

static Ast *parse_unary(void) {
  if (tok_is_punct("-")) {
    Ast *z;
    next_token();
    z = new_ast(A_INT);
    z->ival = 0;
    return mk_binop(B_SUB, z, parse_unary());
  }
  return parse_app();
}

static Ast *parse_mul(void) {
  Ast *l = parse_unary();
  while (1) {
    long op = 0;
    if (tok_is_punct("*")) op = B_MUL;
    else if (tok_is_punct("/")) op = B_DIV;
    else if (tok_is_ident("mod")) op = B_MOD;
    else if (tok_is_ident("land")) op = B_LAND;
    else if (tok_is_ident("lor")) op = B_LOR;
    else if (tok_is_ident("lxor")) op = B_LXOR;
    else if (tok_is_ident("lsl")) op = B_LSL;
    else if (tok_is_ident("lsr")) op = B_LSR;
    else if (tok_is_ident("asr")) op = B_ASR;
    else return l;
    next_token();
    l = mk_binop(op, l, parse_unary());
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
    n = new_ast(isand ? A_AND : A_OR);
    n->a = l;
    n->b = parse_cmp();
    l = n;
  }
}

/* binding := name param* = expr | () = expr | _ = expr */
static void parse_binding(char **name_out, Ast **expr_out) {
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
  *name_out = name;
  *expr_out = body;
}

static Ast *parse_let_common(void) {
  /* caller consumed "let"; returns A_LET with body NULL (filled by caller
   * for the "in" form, or left NULL at top level). */
  Ast *n = new_ast(A_LET);
  long cap = 16;
  n->names = xalloc(cap * (long)sizeof(char *));
  n->exprs = xalloc(cap * (long)sizeof(Ast *));
  n->nbind = 0;
  n->ival = 0;
  if (tok_is_ident("rec")) {
    n->ival = 1;
    next_token();
  }
  while (1) {
    char *name;
    Ast *e;
    if (n->nbind >= cap) {
      parse_error("too many and-bindings");
    }
    parse_binding(&name, &e);
    n->names[n->nbind] = name;
    n->exprs[n->nbind] = e;
    n->nbind = n->nbind + 1;
    if (tok_is_ident("and")) {
      next_token();
    } else {
      break;
    }
  }
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
      n->c = new_ast(A_INT);
      n->c->ival = 0;
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
static Ast **toplevels;
static long ntoplevels;

static void parse_program(void) {
  long cap = 1024;
  toplevels = xalloc(cap * (long)sizeof(Ast *));
  ntoplevels = 0;
  next_token();
  while (tok_kind != T_EOF) {
    if (tok_is_punct(";;")) {
      next_token();
      continue;
    }
    if (!tok_is_ident("let")) {
      parse_error("expected top-level let");
    }
    next_token();
    if (ntoplevels >= cap) {
      parse_error("too many top-level declarations");
    }
    toplevels[ntoplevels] = parse_let_common();
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

struct Val {
  int tag;
  long ival;        /* V_INT */
  char *bdata;      /* V_BYTES */
  long blen;
  Val **fields;     /* V_BLOCK */
  long nfields;
  char *param;      /* V_CLOSURE */
  Ast *body;
  Env *env;
  long prim;        /* V_PRIM: id */
  long arity;       /* V_PRIM: remaining args */
  Val **pargs;      /* V_PRIM: collected args */
  long npargs;
};

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
  P_FST = 13,
  P_SND = 14,
  P_NOT = 15,
  P_ARRAY_MAKE = 16,
  P_ARRAY_GET = 17,
  P_ARRAY_SET = 18,
  P_ARRAY_LENGTH = 19,
  P_BYTES_OF_STRING = 20
};

enum { NCHANS = 256 };
static FILE **chans;
static int vm_argc;
static char **vm_argv;

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
  memcpy(buf, b->bdata, (size_t)b->blen);
  buf[b->blen] = 0;
  return buf;
}

static Val *apply_prim(long prim, Val **a) {
  FILE *f;
  long slot;
  long h;
  long i;
  int c;
  Val *v;
  switch (prim) {
  case P_EXIT:
    fflush(stdout);
    exit((int)val_int(a[0]));
  case P_OPEN_IN:
    f = fopen(path_buf(a[0]), "rb");
    if (f == NULL) {
      return mk_int(-1);
    }
    slot = find_chan_slot();
    chans[slot] = f;
    return mk_int(slot);
  case P_OPEN_OUT:
    f = fopen(path_buf(a[0]), "wb");
    if (f == NULL) {
      return mk_int(-1);
    }
    slot = find_chan_slot();
    chans[slot] = f;
    return mk_int(slot);
  case P_CLOSE_CHAN:
    h = val_int(a[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      run_error("close_chan: bad handle");
    }
    if (h > 2) {
      fclose(chans[h]);
      chans[h] = NULL;
    }
    return val_unit;
  case P_READ_BYTE:
    h = val_int(a[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      run_error("read_byte: bad handle");
    }
    c = fgetc(chans[h]);
    if (c == EOF) {
      return mk_int(-1);
    }
    return mk_int(c & 255);
  case P_WRITE_BYTE:
    h = val_int(a[0]);
    if (h < 0 || h >= NCHANS || chans[h] == NULL) {
      run_error("write_byte: bad handle");
    }
    fputc((int)(val_int(a[1]) & 255), chans[h]);
    return val_unit;
  case P_BYTES_CREATE:
    h = val_int(a[0]);
    if (h < 0) {
      run_error("bytes_create: negative length");
    }
    return mk_bytes(h);
  case P_BYTES_LENGTH:
    if (a[0]->tag != V_BYTES) {
      run_error("bytes_length: not bytes");
    }
    return mk_int(a[0]->blen);
  case P_BYTES_GET:
    if (a[0]->tag != V_BYTES) {
      run_error("bytes_get: not bytes");
    }
    i = val_int(a[1]);
    if (i < 0 || i >= a[0]->blen) {
      run_error("bytes_get: out of bounds");
    }
    return mk_int(255 & (long)(unsigned char)a[0]->bdata[i]);
  case P_BYTES_SET:
    if (a[0]->tag != V_BYTES) {
      run_error("bytes_set: not bytes");
    }
    i = val_int(a[1]);
    if (i < 0 || i >= a[0]->blen) {
      run_error("bytes_set: out of bounds");
    }
    a[0]->bdata[i] = (char)(val_int(a[2]) & 255);
    return val_unit;
  case P_ARG_COUNT:
    return mk_int(vm_argc);
  case P_ARG_GET:
    i = val_int(a[0]);
    if (i < 0 || i >= vm_argc) {
      run_error("arg_get: out of range");
    }
    v = mk_bytes((long)strlen(vm_argv[i]));
    memcpy(v->bdata, vm_argv[i], strlen(vm_argv[i]));
    return v;
  case P_FST:
    if (a[0]->tag != V_BLOCK || a[0]->nfields < 2) {
      run_error("fst: not a pair");
    }
    return a[0]->fields[0];
  case P_SND:
    if (a[0]->tag != V_BLOCK || a[0]->nfields < 2) {
      run_error("snd: not a pair");
    }
    return a[0]->fields[1];
  case P_NOT:
    if (val_int(a[0]) == 0) {
      return val_true;
    }
    return val_false;
  case P_ARRAY_MAKE:
    h = val_int(a[0]);
    if (h < 1) {
      run_error("array_make: length must be positive");
    }
    v = new_val(V_BLOCK);
    v->nfields = h;
    v->fields = xalloc((h + 1) * (long)sizeof(Val *));
    i = 0;
    while (i < h) {
      v->fields[i] = a[1];
      i = i + 1;
    }
    return v;
  case P_ARRAY_GET:
    if (a[0]->tag != V_BLOCK) {
      run_error("array_get: not an array");
    }
    i = val_int(a[1]);
    if (i < 0 || i >= a[0]->nfields) {
      run_error("array_get: out of bounds");
    }
    return a[0]->fields[i];
  case P_ARRAY_SET:
    if (a[0]->tag != V_BLOCK) {
      run_error("array_set: not an array");
    }
    i = val_int(a[1]);
    if (i < 0 || i >= a[0]->nfields) {
      run_error("array_set: out of bounds");
    }
    a[0]->fields[i] = a[2];
    return val_unit;
  case P_ARRAY_LENGTH:
    if (a[0]->tag != V_BLOCK) {
      run_error("array_length: not an array");
    }
    return mk_int(a[0]->nfields);
  case P_BYTES_OF_STRING:
    if (a[0]->tag != V_BYTES) {
      run_error("bytes_of_string: not a string");
    }
    v = mk_bytes(a[0]->blen);
    memcpy(v->bdata, a[0]->bdata, (size_t)a[0]->blen);
    return v;
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
      continue;
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
      continue;
    case A_AND:
      if (val_int(eval(ast->a, env)) == 0) {
        return val_false;
      }
      ast = ast->b;
      continue;
    case A_OR:
      if (val_int(eval(ast->a, env)) != 0) {
        return val_true;
      }
      ast = ast->b;
      continue;
    case A_TUPLE: {
      Val *v = new_val(V_BLOCK);
      long i = 0;
      v->nfields = ast->nbind;
      v->fields = xalloc(ast->nbind * (long)sizeof(Val *));
      while (i < ast->nbind) {
        v->fields[i] = eval(ast->exprs[i], env);
        i = i + 1;
      }
      return v;
    }
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
      case B_EQ: return l == r ? val_true : val_false;
      case B_NE: return l != r ? val_true : val_false;
      case B_LT: return l < r ? val_true : val_false;
      case B_LE: return l <= r ? val_true : val_false;
      case B_GT: return l > r ? val_true : val_false;
      case B_GE: return l >= r ? val_true : val_false;
      case B_LAND: return mk_int(l & r);
      case B_LOR: return mk_int(l | r);
      case B_LXOR: return mk_int(l ^ r);
      case B_LSL: return mk_int((long)(((unsigned long)l) << r));
      case B_LSR: return mk_int((long)(((unsigned long)l) >> r));
      case B_ASR: return mk_int(l >> r);
      default: run_error("bad operator");
      }
      return NULL;
    }
    case A_LET: {
      long i;
      if (ast->ival == 0) {
        i = 0;
        while (i < ast->nbind) {
          env = env_bind(env, ast->names[i], eval(ast->exprs[i], env));
          i = i + 1;
        }
      } else {
        Env *base = env;
        i = 0;
        while (i < ast->nbind) {
          env = env_bind(env, ast->names[i], NULL);
          i = i + 1;
        }
        {
          /* evaluate in the extended env, then patch */
          Env *cell = env;
          i = ast->nbind - 1;
          while (i >= 0) {
            (void)base;
            cell->val = eval(ast->exprs[i], env);
            cell = cell->next;
            i = i - 1;
          }
        }
      }
      ast = ast->c;
      continue;
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
            Val *args[4];
            i = 0;
            while (i < f->npargs) {
              args[i] = f->pargs[i];
              i = i + 1;
            }
            args[f->npargs] = arg;
            return apply_prim(f->prim, args);
          }
          np = new_val(V_PRIM);
          np->prim = f->prim;
          np->arity = f->arity - 1;
          np->npargs = f->npargs + 1;
          np->pargs = xalloc(np->npargs * (long)sizeof(Val *));
          i = 0;
          while (i < f->npargs) {
            np->pargs[i] = f->pargs[i];
            i = i + 1;
          }
          np->pargs[f->npargs] = arg;
          return np;
        }
        run_error("application of a non-function");
      }
      continue;
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
  env = env_bind(env, "fst", mk_prim(P_FST));
  env = env_bind(env, "snd", mk_prim(P_SND));
  env = env_bind(env, "not", mk_prim(P_NOT));
  env = env_bind(env, "array_make", mk_prim(P_ARRAY_MAKE));
  env = env_bind(env, "array_get", mk_prim(P_ARRAY_GET));
  env = env_bind(env, "array_set", mk_prim(P_ARRAY_SET));
  env = env_bind(env, "array_length", mk_prim(P_ARRAY_LENGTH));
  env = env_bind(env, "string_length", mk_prim(P_BYTES_LENGTH));
  env = env_bind(env, "string_get", mk_prim(P_BYTES_GET));
  env = env_bind(env, "bytes_of_string", mk_prim(P_BYTES_OF_STRING));
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

  chans = xalloc(NCHANS * (long)sizeof(FILE *));
  memset(chans, 0, NCHANS * sizeof(FILE *));
  chans[0] = stdin;
  chans[1] = stdout;
  chans[2] = stderr;
  vm_argc = argc - 2;
  vm_argv = argv + 2;

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
    Ast *d = toplevels[t];
    long i;
    if (d->ival == 0) {
      i = 0;
      while (i < d->nbind) {
        env = env_bind(env, d->names[i], eval(d->exprs[i], env));
        i = i + 1;
      }
    } else {
      Env *cell;
      i = 0;
      while (i < d->nbind) {
        env = env_bind(env, d->names[i], NULL);
        i = i + 1;
      }
      cell = env;
      i = d->nbind - 1;
      while (i >= 0) {
        cell->val = eval(d->exprs[i], env);
        cell = cell->next;
        i = i - 1;
      }
    }
    t = t + 1;
  }
  fflush(stdout);
  return 0;
}
