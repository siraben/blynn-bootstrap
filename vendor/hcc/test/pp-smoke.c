#define VALUE 42
#define TCC_STATE_VAR(sym) state->sym
#define text_section TCC_STATE_VAR(text_section)
#define write_byte(sec, byte) sink((sec), (byte))
#ifdef VALUE
int kept = VALUE;
#else
int dropped = 0;
#endif
int used = text_section;
int wrote = write_byte(text_section, 1);
