{
  stdenv,
  lib,
  ocaml,
  cccSrc,
  testsRoot,
}:

stdenv.mkDerivation {
  pname = "ccc-host-ocaml";
  version = "0-unstable-2026-05-27";

  src = cccSrc;
  nativeBuildInputs = [ ocaml ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    portable_ml_pattern='= function|-> function|let [^=]*\?[A-Za-z_]|(^|[^A-Za-z0-9_])(assert|class|functor|land|lazy|lor|lsl|lsr|lxor|method|object|private|when)([^A-Za-z0-9_]|$)|^[[:space:]]*(external|include|module|open)[[:space:]]+|~[A-Za-z_][A-Za-z0-9_]*:|Bigarray\.|Buffer\.|Bytes\.|Digest\.|Format\.|Hashtbl\.|Lazy\.|List\.find_opt|Map\.|Marshal\.|Obj\.|Option\.is_some|Printf\.|Queue\.|Result\.|Scanf\.|Seq\.|Set\.|Stack\.|Stream\.|Unix\.|\( let\* \)'
    if grep -nE "$portable_ml_pattern" host/ccc_host.ml; then
      echo "ccc-host-ocaml should stay within the portable host-ML subset" >&2
      exit 1
    fi
    host_api_pattern='Sys\.|open_in_bin|open_out_bin|close_in|close_in_noerr|close_out|close_out_noerr|input_char|output_string|(^|[^A-Za-z_])stdin([^A-Za-z_]|$)|(^|[^A-Za-z_])stdout([^A-Za-z_]|$)|(^|[^A-Za-z_])stderr([^A-Za-z_]|$)|print_string|prerr_endline|(^|[^A-Za-z_])exit[[:space:]]'
    if grep -nE "$host_api_pattern" host/ccc_host.ml | grep -v 'HOST-ML-BOUNDARY'; then
      echo "ccc-host-ocaml should keep direct host APIs behind HOST-ML-BOUNDARY wrappers" >&2
      exit 1
    fi

    ocamlc host/ccc_host.ml -o ccc-host-ocaml

    check_return() {
      src="$1"
      expected_code="$2"
      shift 2
      actual="$(./ccc-host-ocaml "$@" < "$src")"
      expected="DEFINE LOADI32_RDI 48C7C7
DEFINE LOADI32_RAX 48C7C0
DEFINE SYSCALL 0F05

:_start
	LOADI32_RDI %$expected_code
	LOADI32_RAX %60
	SYSCALL"
      if [ "$actual" != "$expected" ]; then
        echo "unexpected ccc-host-ocaml output for $src; expected exit $expected_code" >&2
        printf '%s\n' "$actual" >&2
        exit 1
      fi
    }

    check_return_file() {
      src="$1"
      expected_code="$2"
      shift 2
      actual_stdout="$(./ccc-host-ocaml -c "$src" -o file-output.M1 "$@")"
      if [ -n "$actual_stdout" ]; then
        echo "ccc-host-ocaml -o should not write M1 to stdout" >&2
        printf '%s\n' "$actual_stdout" >&2
        exit 1
      fi
      expected="DEFINE LOADI32_RDI 48C7C7
DEFINE LOADI32_RAX 48C7C0
DEFINE SYSCALL 0F05

:_start
	LOADI32_RDI %$expected_code
	LOADI32_RAX %60
	SYSCALL"
      actual="$(cat file-output.M1)"
      if [ "$actual" != "$expected" ]; then
        echo "unexpected ccc-host-ocaml file output for $src; expected exit $expected_code" >&2
        printf '%s\n' "$actual" >&2
        exit 1
      fi
    }

    reject_compile() {
      src="$1"
      if ./ccc-host-ocaml < "$src" > rejected.M1; then
        echo "expected ccc-host-ocaml to reject $src" >&2
        exit 1
      else
        :
      fi
    }

    check_return ${testsRoot}/mescc/scaffold/01-return-0.c 0
    check_return_file ${testsRoot}/mescc/scaffold/01-return-0.c 0
    check_return ${testsRoot}/mescc/scaffold/02-return-1.c 1
    check_return ${testsRoot}/mescc/scaffold/03-call.c 0
    check_return ${testsRoot}/mescc/scaffold/04-call-0.c 0
    check_return ${testsRoot}/mescc/scaffold/05-call-1.c 1
    check_return ${testsRoot}/mescc/scaffold/06-call-2.c 0
    check_return ${testsRoot}/mescc/scaffold/06-call-not-1.c 0
    check_return ${testsRoot}/mescc/scaffold/06-not-call-1.c 0
    check_return ${testsRoot}/mescc/scaffold/06-return-void.c 0
    check_return ${testsRoot}/mescc/scaffold/08-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/08-assign-negative.c 0
    check_return ${testsRoot}/mescc/scaffold/10-if-0.c 0
    check_return ${testsRoot}/mescc/scaffold/11-if-1.c 0
    check_return ${testsRoot}/mescc/scaffold/12-if-eq.c 0
    check_return ${testsRoot}/mescc/scaffold/13-if-neq.c 0
    check_return ${testsRoot}/mescc/scaffold/14-if-goto.c 0
    check_return ${testsRoot}/mescc/scaffold/15-if-not-f.c 0
    check_return ${testsRoot}/mescc/scaffold/16-cast.c 0
    check_return ${testsRoot}/mescc/scaffold/16-if-t.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-char.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-call.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-ge.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-gt.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-le.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-lt.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-and.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-or.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-rotated.c 0
    check_return ${testsRoot}/mescc/scaffold/18-assign-shadow.c 0
    check_return ${testsRoot}/mescc/scaffold/20-while.c 0
    check_return ${testsRoot}/mescc/scaffold/21-char-array-simple.c 0
    check_return ${testsRoot}/mescc/scaffold/21-char-array.c 0
    check_return ${testsRoot}/mescc/scaffold/22-while-char-array.c 0
    check_return ${testsRoot}/mescc/scaffold/30-exit-0.c 0
    check_return ${testsRoot}/mescc/scaffold/30-exit-42.c 42
    check_return ${testsRoot}/mescc/scaffold/33-and-or.c 0
    check_return ${testsRoot}/mescc/scaffold/34-pre-post.c 0
    check_return ${testsRoot}/mescc/scaffold/36-compare-arithmetic.c 0
    check_return ${testsRoot}/mescc/scaffold/36-compare-arithmetic-negative.c 0
    check_return ${testsRoot}/mescc/scaffold/37-compare-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/40-if-else.c 0
    check_return ${testsRoot}/mescc/scaffold/42-goto-label.c 0
    check_return ${testsRoot}/mescc/scaffold/45-void-call.c 0
    check_return ${testsRoot}/mescc/scaffold/70-function-modulo.c 0
    check_return ${testsRoot}/mescc/scaffold/80-for-loop.c 10
    check_return ${testsRoot}/hcc/m1-smoke/examples/ret13.c 13
    check_return ${testsRoot}/hcc/m1-smoke/examples/short-circuit.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/call-arg-immediate.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/signed-char-cast.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/return-coercion.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/wide-integer-types.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/scoped-typedef-enum.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/case-cmp-ternary.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/address-written-scalar.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/escaped-string-magic.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/local-aggregate.c 3
    check_return ${testsRoot}/hcc/m1-smoke/examples/function-pointer-call-type.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/dynamic-aggregate.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/conditional-aggregate-copy.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/archive-header-layout.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/pointer-to-pointer-callback.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/bootstrap-qsort-pointer.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/sizeof-member-array-bound.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/do-while.c 3
    check_return ${testsRoot}/hcc/m1-smoke/examples/continue.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/switch.c 42
    printf '%s\n' 'int main(void) { switch (3) { case 1: target: return 42; case 2: return 2; default: goto target; } return 1; }' > switch-goto-label.c
    check_return switch-goto-label.c 42
    printf '%s\n' 'int main(void) { int x = 0; goto target; if (1) { return 1; } else { target: x = 42; } return x; }' > nested-goto-label.c
    check_return nested-goto-label.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/enum-shift.c 42
    check_return ${testsRoot}/hcc/scalar-immediate-smoke.c 0
    check_return ${testsRoot}/hcc/parse-smoke.c 0
    check_return ${testsRoot}/hcc/pp-smoke.c 0
    printf '%s\n' \
      "int accept(int ch) { return ch == 'A' || ch == 'B' || ch == 'C'; }" \
      "int main(void) {" \
      "  if (!accept('A')) return 1;" \
      "  if (!accept('B')) return 2;" \
      "  if (!accept('C')) return 3;" \
      "  if (accept('D')) return 4;" \
      "  return 0;" \
      "}" > param-eq-three.c
    check_return param-eq-three.c 0
    printf '%s\n' '#define VALUE 42' 'int main(void) { return VALUE; }' > define-return.c
    check_return define-return.c 42
    printf '%s\n' "#define LETTER 'A'" 'int main(void) { return LETTER; }' > define-char-return.c
    check_return define-char-return.c 65
    printf '%s\n' '#define VALUE 42' 'int main(void) { int VALUE = 7; return VALUE; }' > define-shadow.c
    check_return define-shadow.c 7
    printf '%s\n' '#define VALUE 42' 'int value_func(void) { return VALUE; }' 'int main(void) { return value_func(); }' > define-helper-return.c
    check_return define-helper-return.c 42
    printf '%s\n' "int letter_func(void) { return 'A'; }" 'int main(void) { return letter_func(); }' > helper-char-return.c
    check_return helper-char-return.c 65
    printf '%s\n' 'int first(char const *s) { return s[0]; }' 'int main(void) { return first("A"); }' > postfix-const-param.c
    check_return postfix-const-param.c 65
    printf '%s\n' 'int logf(char const *fmt, ...);' 'int main(void) { return 42; }' > varargs-prototype.c
    check_return varargs-prototype.c 42
    printf '%s\n' 'int run(char * const argv[]);' 'int main(void) { return 42; }' > array-param-prototype.c
    check_return array-param-prototype.c 42
    printf '%s\n' 'typedef struct { int tag; union { int word; char *ptr; } value; } Node;' 'int main(void) { return sizeof(Node) > 0 ? 42 : 1; }' > typedef-anon-union.c
    check_return typedef-anon-union.c 42
    printf '%s\n' 'typedef struct { int tag; union { struct { int yes, no; }; int value; }; } Node;' 'int main(void) { return sizeof(Node) > 0 ? 42 : 1; }' > typedef-unnamed-anon-union.c
    check_return typedef-unnamed-anon-union.c 42
    printf '%s\n' 'typedef struct { unsigned short aligned:5, packed:1; } Flags;' 'int main(void) { return sizeof(Flags) > 0 ? 42 : 1; }' > typedef-bitfield-list.c
    check_return typedef-bitfield-list.c 42
    printf '%s\n' 'typedef struct { void (*error_func)(void *opaque, const char *msg); } Hooks;' 'int main(void) { return sizeof(Hooks) > 0 ? 42 : 1; }' > typedef-function-pointer-field.c
    check_return typedef-function-pointer-field.c 42
    printf '%s\n' 'typedef struct Section Section;' 'typedef struct { Section *text, *data, *bss; } Sections;' 'int main(void) { return sizeof(Sections) > 0 ? 42 : 1; }' > typedef-comma-pointer-fields.c
    check_return typedef-comma-pointer-fields.c 42
    printf '%s\n' 'int logf(const char *fmt, ...) __attribute__((format(printf, (1), (2))));' 'int main(void) { return 42; }' > attributed-prototype.c
    check_return attributed-prototype.c 42
    printf '%s\n' 'int main(void) { return ((1 | 2) == 3 && (7 & 3) == 3 && (7 ^ 3) == 4) ? 42 : 1; }' > bitwise-expr.c
    check_return bitwise-expr.c 42
    printf '%s\n' 'int main(void) { int x = 1; x |= 2; x <<= 1; x &= 6; x ^= 2; return x == 4 ? 42 : 1; }' > compound-bitwise-assign.c
    check_return compound-bitwise-assign.c 42
    printf '%s\n' 'typedef struct { int n; } Box;' 'int main(void) { Box b = { 2 }; Box *p = &b; p->n--; return b.n == 1 ? 42 : 1; }' > member-postfix-update.c
    check_return member-postfix-update.c 42
    printf '%s\n' 'int main(void) { int a[2]; a[1] = 41; a[1]++; return a[1]; }' > index-postfix-update.c
    check_return index-postfix-update.c 42
    printf '%s\n' 'int main(void) { int x = 41; int *p = &x; (*p)++; return x; }' > deref-postfix-update.c
    check_return deref-postfix-update.c 42
    printf '%s\n' 'int main(void) { return ((~0 & 255) == 255) ? 42 : 1; }' > bitwise-not.c
    check_return bitwise-not.c 42
    printf '%s\n' 'typedef struct { int n; } Box;' 'int main(void) { Box b = { 2 }; Box *p = &b; p->n += 40; return b.n; }' > member-compound-assign.c
    check_return member-compound-assign.c 42
    printf '%s\n' 'int main(void) { int a = 1, *p = &a, b = 41; return *p + b; }' > local-decl-list.c
    check_return local-decl-list.c 42
    printf '%s\n' 'typedef struct TinyAlloc TinyAlloc;' 'int main(void) { TinyAlloc *al = 0; TinyAlloc *bottom = al, *next = al; return bottom == next ? 42 : 1; }' > local-pointer-decl-list.c
    check_return local-pointer-decl-list.c 42
    printf '%s\n' 'int main(void) { int a = 1; int b = 0; a = 2, b = 40; return a + b; }' > comma-expression.c
    check_return comma-expression.c 42
    printf '%s\n' 'typedef int va_list;' 'int main(void) { va_list v; int len, size = 40; len = 2; return len + size; }' > va-list-local.c
    check_return va-list-local.c 42
    printf '%s\n' 'int main(void) { int _t = 0xc1; return (_t >= 0xc0 && _t <= 0xcf) ? 42 : 1; }' > suffix-typedef-heuristic-paren.c
    check_return suffix-typedef-heuristic-paren.c 42
    printf '%s\n' 'int warn(int x) { return x + 40; }' 'int main(void) { return (0, warn)(2); }' > expression-callee-call.c
    check_return expression-callee-call.c 42
    printf '%s\n' 'long double unused(void) { return 79228162514264337593543950336.0L; }' 'int main(void) { return 42; }' > long-double-literal-parse.c
    check_return long-double-literal-parse.c 42
    printf '%s\n' 'int main(void) { int d = 42; float f = (float)d; return sizeof(float) == 4 ? d : 1; }' > float-type-cast.c
    check_return float-type-cast.c 42
    printf '%s\n' 'int strlen2(char *s) { return s[0] + s[1]; }' 'int main(void) { return strlen2("!" "\011"); }' > adjacent-string-literals.c
    check_return adjacent-string-literals.c 42
    printf '%s\n' 'int main(void) { static char const names[2][4] = { "Jan", "Feb" }; return sizeof(names) == 8 ? 42 : 1; }' > multidim-local-array.c
    check_return multidim-local-array.c 42
    printf '%s\n' 'typedef struct { int x; } init_params;' 'int main(void) { init_params p = { 42 }; return p.x; }' > lowercase-typedef-local.c
    check_return lowercase-typedef-local.c 42
    printf '%s\n' 'int main(void) { union { float f; unsigned u; } x1, x2, y; return 42; }' > local-anonymous-union.c
    check_return local-anonymous-union.c 42
    printf '%s\n' 'int PUT_R_RET(int x, int y) { return x + y; }' 'int main(void) { return PUT_R_RET(40, 2); }' > uppercase-call-not-typedef.c
    check_return uppercase-call-not-typedef.c 42
    printf '%s\n' 'struct outer { int tag; struct inner { int value; } *ptr; };' 'int main(void) { return sizeof(struct outer) > 0 ? 42 : 1; }' > nested-struct-field-type.c
    check_return nested-struct-field-type.c 42
    printf '%s\n' 'int main(void) { int ret_t = 0; ret_t = 42; return ret_t; }' > suffix-name-assignment.c
    check_return suffix-name-assignment.c 42
    printf '%s\n' 'int main(void) { char a[2]; return a <= a && a < a + 1 ? 42 : 1; }' > same-pointer-order.c
    check_return same-pointer-order.c 42
    printf '%s\n' 'int main(void) { char a[2]; char b[2]; return (a < b) || (a <= 0) ? 1 : 42; }' > unrelated-pointer-order.c
    check_return unrelated-pointer-order.c 42
    printf '%s\n' 'int main(int argc) { return argc == 0 ? 42 : 1; }' > argc-main.c
    check_return argc-main.c 42
    printf '%s\n' 'int main(int argc, char **argv) { return argc == 0 && argv == 0 ? 42 : 1; }' > argc-argv-main.c
    check_return argc-argv-main.c 42
    printf '%s\n' 'int main(int argc, char *argv[]) { return argc == 0 && argv == 0 ? 42 : 1; }' > argc-argv-array-main.c
    check_return argc-argv-array-main.c 42
    printf '%s\n' 'int main(int argc, char **argv) { return argc == 3 && argv[1][0] == 45 && argv[2][0] == 120 ? 42 : 1; }' > host-argv-index.c
    check_return host-argv-index.c 42 --host-arg tcc --host-arg -c --host-arg x.c
    printf '%s\n' 'int strcmp(char *, char *);' 'int main(int argc, char **argv) { return argc == 3 && strcmp(argv[1], "-c") == 0 && strcmp(argv[2], "x.c") == 0 ? 42 : 1; }' > host-argv-strcmp.c
    check_return host-argv-strcmp.c 42 --host-arg tcc --host-arg -c --host-arg x.c
    printf '%s\n' 'int first(int x, ...) { return x; }' 'int main(void) { return first(42, 1, 2); }' > variadic-function-call.c
    check_return variadic-function-call.c 42
    printf '%s\n' 'int vsnprintf(char *, unsigned long, char *, void *);' 'int strcmp(char *, char *);' 'int main(void) { char buf[8]; return vsnprintf(buf, 8, "abc", 0) == 3 && strcmp(buf, "abc") == 0 ? 42 : 1; }' > builtin-vsnprintf.c
    check_return builtin-vsnprintf.c 42
    printf '%s\n' 'int sprintf(char *, char *, ...);' 'int strcmp(char *, char *);' 'int main(void) { char buf[32]; sprintf(buf, "%s:%d:%.*s", "x", 42, 2, "abcd"); return strcmp(buf, "x:42:ab") == 0 ? 42 : 1; }' > builtin-sprintf-format.c
    check_return builtin-sprintf-format.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'void *realloc(void *, unsigned long);' 'int main(void) { char *p = malloc(2); p[0] = 40; p[1] = 0; p = realloc(p, 4); p[2] = 2; return p[0] + p[2]; }' > realloc-growth.c
    check_return realloc-growth.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef unsigned long size_t;' 'typedef struct { size_t size; } H;' 'int main(void) { char *raw = malloc(32); H *h = (H *)raw; h->size = 42; char *p = raw + sizeof(H); H *back = ((H *)p) - 1; return back->size; }' > cast-pointer-arith.c
    check_return cast-pointer-arith.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef unsigned char uint8_t;' 'typedef struct H { unsigned size; } H;' 'typedef struct A { uint8_t *p; } A;' 'int main(void) { A a; H *h; H *old; uint8_t *p; a.p = malloc(128); h = (H *)a.p; h->size = 16; p = a.p + sizeof(H); p[0] = 42; old = ((H *)p) - 1; return old->size == 16 && p[0] == 42 ? 42 : old->size; }' > uint8-pointer-header.c
    check_return uint8-pointer-header.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct TokenSym { int tok; struct TokenSym *hash_next; int len; char str[1]; } TokenSym;' 'int tok_ident;' 'int main(void) { TokenSym *ts = malloc(sizeof(TokenSym) + 4); tok_ident = 40; ts->tok = tok_ident++; ts->len = 1; ts->str[0] = 1; return ts->tok + ts->len + ts->str[0]; }' > struct-pointer-field-layout.c
    check_return struct-pointer-field-layout.c 42
    printf '%s\n' "int main(void) { return '\\f' == 12 && '\\v' == 11 ? 42 : 1; }" > escaped-control-chars.c
    check_return escaped-control-chars.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct Box { int x; char name[4]; } Box;' 'int main(void) { char *raw = malloc(128); Box *b = (Box *)(raw + 64); b->name[0] = 79; b->name[1] = 75; return b->name[0] == 79 && b->name[1] == 75 ? 42 : 1; }' > heap-struct-offset-array-field.c
    check_return heap-struct-offset-array-field.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct Node { struct Node *next; int value; } Node;' 'int main(void) { Node *a = malloc(sizeof(Node)); Node *b = malloc(sizeof(Node)); Node **p; a->next = 0; b->value = 42; p = &(a->next); *p = b; return a->next->value; }' > heap-struct-field-pointer-assign.c
    check_return heap-struct-field-pointer-assign.c 42
    printf '%s\n' 'int main(void) { int x = 0; if (0) bad: x = 1; return x == 0 ? 42 : 1; }' > if-labeled-statement.c
    check_return if-labeled-statement.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'int main(void) { char *raw = malloc(16); int *p = (int *)raw; p[0] = 40; p[1] = 2; return p[0] + p[1]; }' > raw-int-pointer.c
    check_return raw-int-pointer.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'int main(void) { char *raw = malloc(16); int *p = (int *)raw; *p++ = 40; *p = 2; p = (int *)raw; return p[0] + p[1]; }' > raw-int-postinc.c
    check_return raw-int-postinc.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'int main(void) { int *p; p = malloc(2 * sizeof(int)); p[0] = -1; p[1] = 42; return p[0] == -1 && *p++ == -1 && *p == 42 ? 42 : p[0]; }' > raw-int-negative.c
    check_return raw-int-negative.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'void *memset(void *, int, unsigned long);' 'typedef struct Sym { int v; struct Sym *next; } Sym;' 'int main(void) { Sym *s = malloc(sizeof(Sym)); s->v = 7; s->next = s; memset(s, 0, sizeof(Sym)); return s->v == 0 && s->next == 0 ? 42 : 1; }' > raw-struct-memset-clears-overlay.c
    check_return raw-struct-memset-clears-overlay.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'int main(void) { void **pp = malloc(2 * sizeof(void *)); int x = 42; pp[0] = &x; return pp[0] == &x ? 42 : 1; }' > raw-pointer-array.c
    check_return raw-pointer-array.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'void *realloc(void *, unsigned long);' 'int main(void) { void **pp = malloc(sizeof(void *)); int x = 42; pp[0] = &x; pp = realloc(pp, 4 * sizeof(void *)); return pp[0] == &x ? 42 : 1; }' > raw-pointer-realloc.c
    check_return raw-pointer-realloc.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'void *realloc(void *, unsigned long);' 'typedef struct Section Section;' 'typedef struct State { Section **sections; int nb_sections; } State;' 'struct Section { int value; };' 'void dynarray_add(void *ptab, int *nb_ptr, void *data) { int nb; void **pp; nb = *(int *)nb_ptr; pp = *(void ***)ptab; if (nb == 0) { pp = realloc(pp, 8); *(void ***)ptab = pp; } pp[nb++] = data; *(int *)nb_ptr = nb; }' 'int main(void) { State *s = malloc(sizeof(State)); Section *sec = malloc(sizeof(Section)); sec->value = 42; dynarray_add(&s->sections, &s->nb_sections, sec); return s->sections[0]->value; }' > raw-struct-pointer-field-array.c
    check_return raw-struct-pointer-field-array.c 42
    printf '%s\n' 'int main(void) { int i = 0; while (i < 3) { redo: i++; if (i < 3) goto redo; } return i == 3 ? 42 : i; }' > loop-local-goto-label.c
    check_return loop-local-goto-label.c 42
    printf '%s\n' 'int main(void) { int p = 0; int t = 0; while (p) { redo: t++; p = 0; continue; return 1; } if (t == 0) { p = 1; goto redo; } return t == 1 ? 42 : 2; }' > goto-into-loop-label.c
    check_return goto-into-loop-label.c 42
    printf '%s\n' 'typedef union { int i; int tab[4]; } CValue;' 'int main(void) { CValue cv; CValue *p = &cv; p->i = 42; return p->tab[0]; }' > cvalue-tab-alias.c
    check_return cvalue-tab-alias.c 42
    printf '%s\n' 'typedef enum { TOK_A = 40, TOK_B, TOK_C } Token;' 'static int value = TOK_C;' 'int main(void) { return value; }' > typedef-enum-global.c
    check_return typedef-enum-global.c 42
    printf '%s\n' 'enum TokenTag { TAG_A = 40, TAG_B, TAG_C };' 'static int value = TAG_C;' 'int main(void) { return value; }' > tagged-enum-global.c
    check_return tagged-enum-global.c 42
    printf '%s\n' 'static int left, right;' 'int main(void) { left = 19; right = 23; return left + right; }' > global-decl-list.c
    check_return global-decl-list.c 42
    printf '%s\n' 'typedef struct { char *name; int code; int flags; } Opt;' 'static Opt opts[] = { { "c", 3, 0 }, { 0, 0, 0 } };' 'int main(void) { Opt *p = opts; return p->name[0] == 99 && p->code == 3 && (p + 1)->name == 0 ? 42 : 1; }' > global-struct-array-init.c
    check_return global-struct-array-init.c 42
    printf '%s\n' 'typedef unsigned long size_t;' 'typedef struct { int a; int b; } Box;' 'static int off = (size_t)&((Box *)0)->b;' 'int main(void) { return off == 4 ? 42 : 1; }' > offsetof-member.c
    check_return offsetof-member.c 42
    printf '%s\n' 'typedef struct { union { int symtab_section; int symtab; }; } State;' 'int main(void) { State s; s.symtab_section = 42; return s.symtab; }' > anonymous-union-section-alias.c
    check_return anonymous-union-section-alias.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'struct Box { int x; char name[1]; };' 'int main(void) { struct Box *f = malloc(sizeof *f + 2); f->x = 42; return f->x; }' > self-sizeof-pointer-decl.c
    check_return self-sizeof-pointer-decl.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'char *strcpy(char *, char *);' 'struct Box { int x; char name[4]; };' 'int main(void) { struct Box *f = malloc(sizeof *f); strcpy(f->name, "OK"); return f->name[0] == 79 && f->name[1] == 75 ? 42 : 1; }' > heap-struct-array-field.c
    check_return heap-struct-array-field.c 42
    printf '%s\n' 'char *getenv(char *);' 'int main(void) { return getenv("MISSING") == 0 ? 42 : 1; }' > builtin-getenv.c
    check_return builtin-getenv.c 42
    printf '%s\n' 'char *strchr(char *, int);' 'char *strrchr(char *, int);' 'int main(void) { char *s = "a/b.c"; char *p = strchr(s, 47); char *q = strrchr(s, 46); return p[1] == 98 && q[1] == 99 ? 42 : 1; }' > builtin-strchr.c
    check_return builtin-strchr.c 42
    printf '%s\n' 'static const char keywords[] = "if" "\0" "else" "\0";' 'int main(void) { const char *p = keywords; if (sizeof(keywords) != 9) return 1; if (p[0] != 105 || p[1] != 102 || p[2] != 0) return 2; while (*p) p++; p++; return p[0] == 101 && p[4] == 0 ? 42 : 3; }' > string-array-concat-nul.c
    check_return string-array-concat-nul.c 42
    printf 'OK' > host-file.txt
    printf '%s\n' 'int open(char *, int);' 'int read(int, char *, int);' 'int close(int);' 'int main(void) { char b[3]; int fd = open("host-file.txt", 0); int n = read(fd, b, 2); close(fd); return n == 2 && b[0] == 79 && b[1] == 75 ? 42 : 1; }' > builtin-open-read.c
    check_return builtin-open-read.c 42
    printf '%s\n' 'void *memset(void *, int, unsigned long);' 'int main(void) { int *slots[4]; slots[0] = (int *)1; memset(slots, 0, sizeof(slots)); return slots[0] == 0 && slots[3] == 0 ? 42 : 1; }' > memset-pointer-array.c
    check_return memset-pointer-array.c 42
    printf '%s\n' 'int main(void) { return (1 >> 99) == 0 ? 42 : 1; }' > large-shift-right.c
    check_return large-shift-right.c 42
    printf '%s\n' 'int main(void) { return 8 >= 0x8000000000000000ULL ? 1 : 42; }' > large-saturated-constant.c
    check_return large-saturated-constant.c 42
    printf '%s\n' 'int main(void) { int t = 205; int parsed = 0; goto convert; return 1; convert: if (t == 205) { if (1) parsed = parsed + 1; } else if (t == 206) { if (1) parsed = 99; } return parsed == 1 ? 42 : parsed; }' > goto-shallow-label-branch.c
    check_return goto-shallow-label-branch.c 42
    printf '%s\n' 'typedef union { int i; int tab[4]; } CValue;' 'void set(CValue *cv, int x) { int *tab; tab = cv->tab; *tab++ = x; }' 'int main(void) { CValue cv; set(&cv, 42); return cv.i; }' > cvalue-tab-pointer.c
    check_return cvalue-tab-pointer.c 42
    printf '%s\n' 'typedef union { int i; int tab[4]; } CValue;' 'typedef struct { CValue c; } SValue;' 'void copy(SValue *vtop, CValue *vc) { vtop->c = *vc; }' 'int main(void) { CValue cv; SValue sv; cv.i = 42; copy(&sv, &cv); return sv.c.i; }' > prefixed-union-copy.c
    check_return prefixed-union-copy.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct State State;' 'struct State { int enabled; };' 'State *global;' 'void set(State *s) { s->enabled = 1; global = s; }' 'int main(void) { State *s = malloc(sizeof(State)); set(s); return global->enabled ? 42 : 1; }' > raw-overlay-struct-global.c
    check_return raw-overlay-struct-global.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'int tok;' 'int tokc_i;' 'int *macro_ptr;' 'void tok_get(int *t, int **pp) { int *p; p = *pp; *t = *p++; tokc_i = *p++; *pp = p; }' 'int main(void) { int *p; p = malloc(4 * sizeof(int)); p[0] = 0xc4; p[1] = 8; macro_ptr = p; tok_get(&tok, &macro_ptr); return tok == 0xc4 && tokc_i == 8 ? 42 : tok; }' > raw-tok-get-postinc.c
    check_return raw-tok-get-postinc.c 42
    printf '%s\n' 'void step(int **pp) { ++*pp; }' 'int main(void) { int raw[2]; int *p; raw[0] = 1; raw[1] = 42; p = raw; step(&p); return *p; }' > pointer-to-pointer-preinc.c
    check_return pointer-to-pointer-preinc.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct CString { int size; char *data; } CString;' 'typedef union CValue { int i; int tab[4]; CString str; } CValue;' 'void tok_get(int *t, const int **pp, CValue *cv) { const int *p; p = *pp; switch (*t = *p++) { case 0xcd: cv->str.size = *p++; cv->str.data = (char *)p; p += (cv->str.size + sizeof(int) - 1) / sizeof(int); break; default: break; } *pp = p; }' 'int main(void) { int *raw; const int *p; int t; CValue cv; raw = malloc(4 * sizeof(int)); raw[0] = 0xcd; raw[1] = 2; raw[2] = 56; raw[3] = 0; p = raw; tok_get(&t, &p, &cv); return t == 0xcd && cv.str.size == 2 && p == raw + 3 ? 42 : cv.str.size; }' > cvalue-string-token-postinc.c
    check_return cvalue-string-token-postinc.c 42
    printf '%s\n' 'int setjmp(void *);' 'void longjmp(void *, int);' 'int main(void) { return setjmp(0) == 0 ? 42 : 1; }' > builtin-setjmp.c
    check_return builtin-setjmp.c 42
    printf '%s\n' 'int setjmp(void *);' 'void longjmp(void *, int);' 'int main(void) { int x = 0; if (setjmp(0) == 0) { x = 1; longjmp(0, 1); x = 2; } return x == 1 ? 42 : x; }' > builtin-longjmp.c
    check_return builtin-longjmp.c 42
    printf '%s\n' 'int setjmp(void *);' 'void longjmp(void *, int);' 'void fail(void) { longjmp(0, 1); }' 'int main(void) { int x = 0; if (setjmp(0) == 0) { x = 1; fail(); x = 2; } return x == 1 ? 42 : x; }' > builtin-longjmp-function.c
    check_return builtin-longjmp-function.c 42
    printf '%s\n' 'void exit(int);' 'int main(void) { exit(7); return 42; }' > builtin-exit.c
    check_return builtin-exit.c 7
    printf '%s\n' 'int ELF64_ST_INFO(int, int);' 'int ELF64_ST_BIND(int);' 'int ELF64_ST_TYPE(int);' 'int ELF64_ST_VISIBILITY(int);' 'int main(void) { int info = ELF64_ST_INFO(2, 3); return ELF64_ST_BIND(info) == 2 && ELF64_ST_TYPE(info) == 3 && ELF64_ST_VISIBILITY(7) == 3 ? 42 : 1; }' > builtin-elf64-st-info.c
    check_return builtin-elf64-st-info.c 42
    printf '%s\n' 'int forty_two(void) { return 42; }' 'static int (*entry)(void) = forty_two;' 'int main(void) { return entry(); }' > global-function-pointer.c
    check_return global-function-pointer.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'void *memset(void *, int, unsigned long);' 'unsigned long strlen(char *);' 'int main(void) { char *p = malloc(4); memset(p, 65, 3); p[3] = 0; return strlen(p) == 3 && p[0] == 65 ? 42 : 1; }' > libc-byte-allocation.c
    check_return libc-byte-allocation.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct { int x; } Box;' 'int main(void) { Box *p = malloc(sizeof(Box)); p->x = 42; return p->x; }' > heap-struct-pointer.c
    check_return heap-struct-pointer.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct Sym { int v; struct Sym *next; } Sym;' 'int main(void) { Sym *p = malloc(sizeof(Sym) * 2); p->v = 1; p++; p->v = 42; return p->v; }' > heap-struct-pointer-increment.c
    check_return heap-struct-pointer-increment.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct { int t; } CType;' 'typedef struct Sym { CType type; } Sym;' 'int main(void) { Sym *s = malloc(sizeof(Sym)); s->type.t = 42; return s->type.t; }' > nested-heap-member.c
    check_return nested-heap-member.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct { int t; } CType;' 'typedef struct SValue { CType type; } SValue;' 'int main(void) { SValue *vtop; vtop = malloc(sizeof(SValue) * 2); vtop[1].type.t = 42; return vtop[1].type.t; }' > indexed-struct-pointer-member.c
    check_return indexed-struct-pointer-member.c 42
    printf '%s\n' 'typedef struct CType { int t; void *ref; } CType;' 'typedef union CValue { int i; int tab[4]; } CValue;' 'typedef struct SValue { CType type; int r; CValue c; } SValue;' 'int combine_types(CType *dest, SValue *op1, SValue *op2, int op) { CType *type1, *type2, type; int t1, t2, bt1, bt2; int ret = 1; if (op == '"'"'S'"'"') op2 = op1; type1 = &op1->type, type2 = &op2->type; t1 = type1->t, t2 = type2->t; bt1 = t1 & 0x000f, bt2 = t2 & 0x000f; type.t = 0; type.ref = 0; if (bt1 == 0 || bt2 == 0) { ret = op == '"'"'?'"'"' ? 1 : 0; type.t = 0; } else if (bt1 == 4 || bt2 == 4) { type.t = 4 | 0x0800; if (bt1 == 4) type.t &= t1; if (bt2 == 4) type.t &= t2; if ((t1 & (0x000f | 0x0010)) == (4 | 0x0010) || (t2 & (0x000f | 0x0010)) == (4 | 0x0010)) type.t |= 0x0010; } else { ret = 0; } if (dest) *dest = type; return ret; }' 'int main(void) { CType dest; SValue a; SValue b; a.type.t = 4; b.type.t = 4; a.r = 48; b.r = 48; a.c.i = 8; b.c.i = 4; return combine_types(&dest, &a, &b, '"'"'C'"'"') == 1 && dest.t == 4 ? 42 : 1; }' > combine-types-struct-field-pointer.c
    check_return combine-types-struct-field-pointer.c 42
    printf '%s\n' 'typedef struct Sym Sym;' 'struct Sym { int v; Sym *prev_tok; };' 'typedef struct TokenSym { Sym *sym_struct; } TokenSym;' 'void link(Sym *s, TokenSym *ts) { Sym **ps; ps = &ts->sym_struct; s->prev_tok = *ps, *ps = s; }' 'int main(void) { Sym s; TokenSym ts; s.v = 42; s.prev_tok = 0; ts.sym_struct = 0; link(&s, &ts); if (s.prev_tok != 0) return 2; if (ts.sym_struct != &s) return 3; return 42; }' > struct-pointer-field-link.c
    check_return struct-pointer-field-link.c 42
    printf '%s\n' 'typedef struct Sym Sym;' 'typedef struct CType { int t; Sym *ref; } CType;' 'struct Sym { int v; CType type; };' 'int main(void) { CType type, btype; Sym sym; type.t = 0; type.ref = 0; btype.t = 7; btype.ref = &sym; type = btype; return type.t == 7 && type.ref == &sym ? 42 : type.t; }' > struct-variable-copy.c
    check_return struct-variable-copy.c 42
    printf '%s\n' 'struct FuncAttr { unsigned func_call : 3, func_type : 2; };' 'typedef struct Sym { union { int c; struct FuncAttr f; }; } Sym;' 'void merge(struct FuncAttr *fa, struct FuncAttr *fa1) { if (fa1->func_call && !fa->func_call) fa->func_call = fa1->func_call; }' 'int main(void) { Sym sym; struct FuncAttr fa; sym.f.func_call = 3; fa.func_call = 0; merge(&fa, &sym.f); return fa.func_call == 3 ? 42 : fa.func_call; }' > anonymous-union-struct-field-pointer.c
    check_return anonymous-union-struct-field-pointer.c 42
    printf '%s\n' 'typedef struct Sym { int v; union { int c; int *d; }; union { struct Sym *next; int *e; }; } Sym;' 'int main(void) { int raw[2]; Sym s; Sym n; raw[0] = 42; s.c = 0; s.d = raw; if (s.d[0] != 42) return 1; s.next = &n; if (s.e != (int *)&n) return 2; return 42; }' > anonymous-union-field-alias.c
    check_return anonymous-union-field-alias.c 42
    printf '%s\n' 'void *malloc(unsigned long);' 'typedef struct { int x; } Box;' 'int main(void) { Box *p = malloc(sizeof(Box)); int *q = &p->x; *q = 42; return p->x; }' > heap-struct-field-address.c
    check_return heap-struct-field-address.c 42
    printf '%s\n' '#ifdef MISSING' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' > ifdef-missing-else.c
    check_return ifdef-missing-else.c 42
    printf '%s\n' '#define VALUE 42' '#ifndef VALUE' 'int main(void) { return 1; }' '#else' 'int main(void) { return VALUE; }' '#endif' > ifndef-defined-else.c
    check_return ifndef-defined-else.c 42
    printf '%s\n' '#ifdef LATER' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' '#define LATER 1' > define-after-ifdef.c
    check_return define-after-ifdef.c 42
    printf '%s\n' '#define VALUE 1' '#undef VALUE' '#ifdef VALUE' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' > undef-before-ifdef.c
    check_return undef-before-ifdef.c 42
    printf '%s\n' '#define VALUE 1' '#undef VALUE' '#define VALUE 42' 'int main(void) { return VALUE; }' > undef-redefine.c
    check_return undef-redefine.c 42
    printf '%s\n' '#if 0' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' > if-zero-else.c
    check_return if-zero-else.c 42
    printf '%s\n' '#if 1' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-one-else.c
    check_return if-one-else.c 42
    printf '%s\n' '#define VALUE 1' '#if VALUE' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-define-value.c
    check_return if-define-value.c 42
    printf '%s\n' '#define VALUE 1' '#if defined(VALUE)' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-defined-value.c
    check_return if-defined-value.c 42
    printf '%s\n' '#if !defined(MISSING)' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-not-defined-missing.c
    check_return if-not-defined-missing.c 42
    printf '%s\n' '#define A 1' '#define B 1' '#if defined(A) && defined(B)' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-defined-and.c
    check_return if-defined-and.c 42
    printf '%s\n' '#define A 1' '#if defined(MISSING) || defined(A)' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-defined-or.c
    check_return if-defined-or.c 42
    printf '%s\n' '#define A 1' '#if !(defined(MISSING) && defined(A))' 'int main(void) { return 42; }' '#else' 'int main(void) { return 1; }' '#endif' > if-paren-not-and.c
    check_return if-paren-not-and.c 42
    printf '%s\n' '#define A 1' '#if 0' 'int main(void) { return 1; }' '#elif defined(A)' 'int main(void) { return 42; }' '#else' 'int main(void) { return 2; }' '#endif' > elif-defined.c
    check_return elif-defined.c 42
    printf '%s\n' '#if 1' 'int main(void) { return 42; }' '#elif 1' 'int main(void) { return 1; }' '#else' 'int main(void) { return 2; }' '#endif' > elif-after-active.c
    check_return elif-after-active.c 42
    printf '%s\n' '#if 0' 'int main(void) { return 1; }' '#elif 0' 'int main(void) { return 2; }' '#else' 'int main(void) { return 42; }' '#endif' > elif-fallthrough-else.c
    check_return elif-fallthrough-else.c 42
    printf '%s\n' 'int main(voidx) { return 0; }' > keyword-prefix-param.c
    reject_compile keyword-prefix-param.c
    printf '%s\n' 'int main(void) { return sizeof(shorter); }' > keyword-prefix-sizeof.c
    reject_compile keyword-prefix-sizeof.c
    reject_compile ${testsRoot}/hcc/diagnostics/unknown-identifier.c
    reject_compile ${testsRoot}/hcc/diagnostics/unknown-global-initializer.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ccc-host-ocaml "$out/bin/ccc-host-ocaml"
    runHook postInstall
  '';

  meta = {
    description = "OCaml-hosted development build of the CCC bootstrap C compiler";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
