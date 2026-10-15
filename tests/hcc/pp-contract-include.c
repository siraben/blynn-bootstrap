#define LEVEL 2
#define PLUS(x) ((x)+1)
#define HEADER(x) x
#define NAME "pp-contract-enabled.h"
#if defined(LEVEL) && PLUS(LEVEL) == 3
#include HEADER(NAME)
#endif
#if FROM_HEADER != 7
#error missing active header
#endif
#undef PP_CONTRACT_GUARD
#define PASS_TWO
#include NAME
#ifndef SECOND_PASS
#error guard incorrectly cached
#endif
#if 0
#include "pp-contract-nonexistent.h"
#if 1/0
#endif
#elif PLUS(FROM_HEADER) == 8
int pp_contract_include;
#else
#error wrong conditional context
#endif
/*
#if 0
*/
#if PLUS(\
  2) == 3
int pp_contract_continued;
#endif
