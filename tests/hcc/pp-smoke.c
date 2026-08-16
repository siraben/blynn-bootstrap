#define VALUE 42
#define FLAG 0
#define HDR "pp-include-value.h"
#define EMPTY_ARG(x) 0
#define A a
#define CAT(x,y) x ## y
#define CAT4(a,b,c,d) a ## b ## c ## d
#define TCC_STATE_VAR(sym) state->sym
#define text_section TCC_STATE_VAR(text_section)
#define write_byte(sec, byte) sink((sec), (byte))
#define FIELD_TYPE(NODE) ((NODE)->common.type)
#define NESTED_FIELD_TYPE(NODE) (FIELD_TYPE(FIELD_TYPE(NODE))->common.type)
#define HOOK_CALL hook_table.hook_call
#define WRAP_HOOK(MODE, VALUE) wrap_stat((MODE), HOOK_CALL((MODE), (VALUE)))
#define NESTED_WRAP_HOOK(MODE, VALUE) nested_wrap_stat((MODE), WRAP_HOOK((MODE), HOOK_CALL((MODE), (VALUE))))
#define HCC_CYCLE_A HCC_CYCLE_B
#define HCC_CYCLE_B HCC_CYCLE_A
#define EMPTY_ARG_VALUE(ARG) 73
#define STANDARD_VARIADIC(first, ...) first + __VA_ARGS__
#define NAMED_VARIADIC(first, rest...) first + rest
#define NESTED_JOIN(type) NESTED_JOIN_I(type)
#define NESTED_JOIN_I(type) NESTED_##type
#define NESTED_KIND(value) ((value) & 15)
#define NESTED_INFO(bind, type) (((bind) << 4) + ((type) & 15))

#define RESCAN_LESS(result, left, right) ((result) < (right))
#define RESCAN_APPLY(callback) callback(1, 2, 3)
#if RESCAN_APPLY(RESCAN_LESS) != 1
#error function-like macro arguments must be rescanned beside replacement punctuation
#endif
#define SELF_MEMBER object.SELF_MEMBER
int self_member_rescan = SELF_MEMBER;
/*
  #include "missing-comment-only.h"
 */
#pragma hcc_smoke /* comment with EMPTY_ARG_VALUE
  and EMPTY_ARG_VALUE. */

#ifndef __STDC__
#define signed
#endif

int stdc_signed_cast(int (*read_value)(void)) {
  return (signed) read_value();
}
struct MacroNode;
struct MacroCommon {
  struct MacroNode *type;
};
struct MacroNode {
  struct MacroCommon common;
};
#if FLAG
#include "pp-missing-disabled.h"
#endif
#include HDR
#if 5 % 2 ? 1 : 0
int pp_if_mod = 1;
#else
int pp_if_mod = 0;
#endif
#ifdef VALUE
int kept = VALUE;
#else
int dropped = 0;
#endif
int Ab = 11;
int paste_left_raw = CAT(A,b);
int ATTR_PRINTF_1_0 = 17;
int paste_pp_number = CAT4(ATTR_,PRINTF,_,1_0);
int empty_arg = EMPTY_ARG();
int used = text_section;
int wrote = write_byte(text_section, 1);
int nested_macro_field(struct MacroNode *node) {
  return NESTED_FIELD_TYPE(node) != 0;
}
int nested_hook_macro(int mode, int value) {
  return NESTED_WRAP_HOOK(mode, value);
}
int HCC_CYCLE_A;
int *mutual_object_macro_cycle(void) {
  return &HCC_CYCLE_A;
}
int empty_arg_macro = EMPTY_ARG_VALUE();
int standard_variadic = STANDARD_VARIADIC(1, 2);
int named_variadic = NAMED_VARIADIC(3, 4);
int nested_invocation_hide_set = NESTED_JOIN(INFO)(1, NESTED_JOIN(KIND)(2));
int after_directive_block_comment = VALUE;
#if defined(VALUE) ? 1 : 0
int conditional_true = 1;
#else
int conditional_true = missing_true_branch;
#endif
#if defined(MISSING_VALUE) ? 1 : 0
int conditional_false = missing_false_branch;
#else
int conditional_false = 0;
#endif
#if ((9 / 3) == 3) && ((10 % 4) == 2)
int div_mod_true = 1;
#else
int div_mod_true = missing_div_mod_branch;
#endif
#if (1 || (1 / 0)) && !(0 && (1 / 0))
int short_circuit_if = 1;
#else
int short_circuit_if = missing_short_circuit_if;
#endif
