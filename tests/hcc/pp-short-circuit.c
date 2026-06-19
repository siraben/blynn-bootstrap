#if 1 || (1 / 0)
int short_circuit_or = 1;
#endif
#if 0 && (1 / 0)
int dead_and = 1;
#else
int short_circuit_and = 1;
#endif
