#define VALUE 42
#define TCC_STATE_VAR(sym) state->sym
#define text_section TCC_STATE_VAR(text_section)
#define write_byte(sec, byte) sink((sec), (byte))
#define FIELD_TYPE(NODE) ((NODE)->common.type)
#define NESTED_FIELD_TYPE(NODE) (FIELD_TYPE(FIELD_TYPE(NODE))->common.type)
#define HOOK_CALL hook_table.hook_call
#define WRAP_HOOK(MODE, VALUE) wrap_stat((MODE), HOOK_CALL((MODE), (VALUE)))
#define NESTED_WRAP_HOOK(MODE, VALUE) nested_wrap_stat((MODE), WRAP_HOOK((MODE), HOOK_CALL((MODE), (VALUE))))
#define EMPTY_ARG_VALUE(ARG) 73
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
#ifdef VALUE
int kept = VALUE;
#else
int dropped = 0;
#endif
int used = text_section;
int wrote = write_byte(text_section, 1);
int nested_macro_field(struct MacroNode *node) {
  return NESTED_FIELD_TYPE(node) != 0;
}
int nested_hook_macro(int mode, int value) {
  return NESTED_WRAP_HOOK(mode, value);
}
int empty_arg_macro = EMPTY_ARG_VALUE();
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
