int add(int a, int b) {
  __asm ("" : "+r" (a));
  return a + b;
}

typedef int *SmokeRtx;
SmokeRtx smoke_move(SmokeRtx, SmokeRtx);

void local_function_pointer_declaration(SmokeRtx left, SmokeRtx right) {
  SmokeRtx (*move)(SmokeRtx, SmokeRtx) = smoke_move;
  move(left, right);
  (*smoke_move)(left, right);
}

void local_function_pointer_array_declaration(SmokeRtx left, SmokeRtx right) {
  SmokeRtx (*const moves[])(SmokeRtx, SmokeRtx) = {smoke_move, smoke_move};
  moves[0](left, right);
}

typedef struct {
  int field;
} Item;

struct FunctionFields {
  void *(*alloc)(long);
  void (*release)(void *);
  unsigned char (*error)(char *, int) __attribute__((__format__(__printf__, 1, 0))) __attribute__((__nonnull__(1)));
};

typedef struct {
  int value;
} ArrayTypedef[1];

typedef struct {
  int value;
} GmpConstStruct;

typedef __gmp_const GmpConstStruct *GmpConstPtr;

enum shadow_constants {
  no_shadow,
  loop
};

enum cast_enum_constants {
  cast_enum_first = 3,
  cast_enum_second = 1 + ((int) cast_enum_first),
  cast_enum_short_circuit_or = 1 || (1 / 0),
  cast_enum_short_circuit_and = 0 && (1 / 0)
};

typedef int partition;
typedef struct ShadowEdge *edge;

asm ("file scope asm is ignored by hcc");

struct ShadowLoop {
  char *aux;
};

struct ShadowEdge {
  int prev_caller;
};

struct SourceLocation {
  char *file;
  int line;
};

struct ConditionalPointer {
  int value;
};

struct ParenthesizedArrayField {
  int (values[2][3]);
};

struct GTY(()) GtyAnnotatedStruct {
  int GTY((skip)) field;
};

static void *(*reallocator)(void *, unsigned long);
static const char *const templates[] = { "x", "y" };
extern unsigned const char incomplete_extern_array[];
void global_default_lock(void);
static void (*global_lock_pointer)(void) = *global_default_lock;
int short_circuit_array_bound[1 || (1 / 0)];
static int global_address_array[2];
void *global_address_array_start = &global_address_array[0];
int width = sizeof ((Item*)0)->field;
int alignof_type_value = __alignof__(ArrayTypedef);
_Static_assert(1 || (1 / 0), "constant logical-or should short-circuit");
_Static_assert(!(0 && (1 / 0)), "constant logical-and should short-circuit");

static int parameter_attribute(int a __attribute__((__unused__))) {
  return 0;
}

extern __inline__ int gnu_inline_identity(int x) {
  return x;
}

char *file_macro_value(void) {
  return __FILE__;
}

int array_typedef_parameter(ArrayTypedef value) {
  return value->value;
}

int array_typedef_arrow_local(void) {
  ArrayTypedef local;
  local->value = 9;
  return local->value;
}

int alignof_expr_value(ArrayTypedef value) {
  return __alignof__(*value);
}

int extension_cast(long value) {
  return __extension__ (int) value;
}

char *enum_constant_shadow_parameter(struct ShadowLoop *loop) {
  return loop->aux;
}

int enum_constant_expression_value(void) {
  return loop;
}

int local_enum_initializer_value(void) {
  enum { LOCAL_ENUM_A = 5, LOCAL_ENUM_B = LOCAL_ENUM_A + 2 } value = LOCAL_ENUM_B;
  return value;
}

struct SourceLocation make_source_location(char *file) {
  struct SourceLocation loc;
  loc.file = file;
  loc.line = 17;
  return loc;
}

char *aggregate_call_member(char *file) {
  return make_source_location(file).file;
}

int typed_va_arg_value(int marker, ...) {
  va_list ap;
  va_start(ap, marker);
  return va_arg(ap, int);
}

long long unsigned typed_va_arg_long_long_unsigned(int marker, ...) {
  va_list ap;
  va_start(ap, marker);
  return va_arg(ap, long long unsigned);
}

int statement_expression_value(int value) {
  return __extension__ ({ int local = value + 5; local; });
}

int statement_expression_if_side_effect(int value) {
  return __extension__ ({ int local = value; if (local < 3) local = 3; local; });
}

int conditional_null_pointer_member(struct ConditionalPointer *ptr) {
  return (0 ? 0 : ptr)->value;
}

int parenthesized_array_field_size(void) {
  return sizeof(struct ParenthesizedArrayField);
}

int parenthesized_typedef_shadow_compare(int partition) {
  return (partition >= 0);
}

int parenthesized_typedef_shadow_arrow(struct ShadowEdge *edge) {
  return (edge)->prev_caller;
}

long unsigned int long_unsigned_spelling(long unsigned int value) {
  return value + 1;
}

signed long int signed_long_spelling(signed long int value) {
  long signed int also_signed = value;
  return also_signed + 1;
}

int switch_decl_before_case(int tag) {
  switch (tag) {
    int result;
  case 1:
    result = 7;
    return result;
  default:
    result = 3;
    return result;
  }
}

int switch_nested_case_label(int tag, int flag) {
  int result = 0;
  switch (tag) {
  case 1:
    result = 10;
    break;
  default:
    if (flag) {
    case 2:
      result = 20;
    }
    result = result + 1;
    break;
  }
  return result;
}

int label_attribute_before_statement(int flag) {
  if (flag)
    goto used_label;
  return 0;
used_label: __attribute__((unused)) return 1;
}

double leading_dot_float_literal(double value) {
  return value + .5;
}

union trailing_attr_union {
  void *p;
  unsigned i;
} __attribute__((packed));

union function_shadowed_union_tag {
  void *p;
};

int local_union_tag_shadow_does_not_escape(void) {
  union function_shadowed_union_tag {
    int q;
  };
  union function_shadowed_union_tag local;
  local.q = 3;
  return local.q;
}

void *global_union_tag_after_local_shadow(const union function_shadowed_union_tag *up) {
  return up->p;
}

void *trailing_attr_union_member(const union trailing_attr_union *up) {
  return up->p;
}

int dollar$identifier(int dollar$value) {
  return dollar$value + 1;
}

void *function_pointer_cast(void *callee) {
  return ((void *(*)(long)) callee)(4);
}

extern int abstract_function_pointer_parameter(void *(*)(long), void (*)(void *));
extern int gnu_restrict_pointer_parameter(int *__restrict value, const char *__restrict__ text);

int global = 7;
