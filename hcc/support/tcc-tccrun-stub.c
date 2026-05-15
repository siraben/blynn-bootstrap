/* Stub for tinycc's tccrun.c. The bootstrap never executes user code
   via tcc -run, so every entry point either no-ops or returns failure.
   Signatures must match the prototypes in tcc.h. */

ST_FUNC void tcc_run_free(TCCState *s1) { }

LIBTCCAPI int tcc_relocate(TCCState *s1) { return -1; }

LIBTCCAPI int tcc_run(TCCState *s1, int argc, char **argv) { return -1; }

LIBTCCAPI void *_tcc_setjmp(TCCState *s1, void *p_jmp_buf, void *func, void *p_longjmp) { return 0; }

LIBTCCAPI void tcc_set_backtrace_func(TCCState *s1, void *data, TCCBtFunc *func) { }

ST_FUNC void *dlopen(const char *filename, int flag) { return 0; }
ST_FUNC void dlclose(void *p) { }
ST_FUNC const char *dlerror(void) { return "dlerror: unsupported in bootstrap"; }
ST_FUNC void *dlsym(void *handle, const char *symbol) { return 0; }
