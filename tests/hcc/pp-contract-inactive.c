#if 0
#if 1/0
#error inactive nested if
#elif bad tokens (
#error inactive nested elif
#endif
#endif
#if 1
int pp_contract_inactive;
#elif 1/0
#error already taken
#elif bad tokens (
#error already taken too
#endif
