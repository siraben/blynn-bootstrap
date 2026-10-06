int external_data_7[3] = { 17, 23, 29 };
char external_string[4] = "abc";
/* Force a function before the deferred globals in M1. The globals must still
   be emitted in the writable ELF data section. */
int external_helper(void) { return external_data_7[0]; }
