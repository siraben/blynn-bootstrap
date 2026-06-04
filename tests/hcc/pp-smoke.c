#define VALUE 42
#define FLAG 0
#define HDR "pp-include-value.h"
#define EMPTY_ARG(x) 0
#define A a
#define CAT(x,y) x ## y
#define TCC_STATE_VAR(sym) state->sym
#define text_section TCC_STATE_VAR(text_section)
#define write_byte(sec, byte) sink((sec), (byte))
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
int empty_arg = EMPTY_ARG();
int used = text_section;
int wrote = write_byte(text_section, 1);
