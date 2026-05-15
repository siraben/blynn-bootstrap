/* Stub for tinycc's tccdbg.c. The bootstrap never emits debug info or
   coverage data, so every entry point is a no-op. Signatures must match
   the prototypes in tcc.h. */

ST_FUNC void tcc_debug_new(TCCState *s) { }
ST_FUNC void tcc_debug_start(TCCState *s1) { }
ST_FUNC void tcc_debug_end(TCCState *s1) { }
ST_FUNC void tcc_debug_bincl(TCCState *s1) { }
ST_FUNC void tcc_debug_eincl(TCCState *s1) { }
ST_FUNC void tcc_debug_newfile(TCCState *s1) { }
ST_FUNC void tcc_debug_line(TCCState *s1) { }
ST_FUNC void tcc_debug_funcstart(TCCState *s1, Sym *sym) { }
ST_FUNC void tcc_debug_prolog_epilog(TCCState *s1, int value) { }
ST_FUNC void tcc_debug_funcend(TCCState *s1, int size) { }
ST_FUNC void tcc_debug_extern_sym(TCCState *s1, Sym *sym, int sh_num, int sym_bind, int sym_type) { }
ST_FUNC void tcc_debug_typedef(TCCState *s1, Sym *sym) { }
ST_FUNC void tcc_debug_stabn(TCCState *s1, int type, int value) { }
ST_FUNC void tcc_debug_fix_forw(TCCState *s1, CType *t) { }
ST_FUNC void tcc_add_debug_info(TCCState *s1, Sym *s, Sym *e) { }

ST_FUNC void tcc_eh_frame_start(TCCState *s1) { }
ST_FUNC void tcc_eh_frame_end(TCCState *s1) { }
ST_FUNC void tcc_eh_frame_hdr(TCCState *s1, int final) { }

ST_FUNC void tcc_tcov_start(TCCState *s1) { }
ST_FUNC void tcc_tcov_end(TCCState *s1) { }
ST_FUNC void tcc_tcov_check_line(TCCState *s1, int start) { }
ST_FUNC void tcc_tcov_block_end(TCCState *s1, int line) { }
ST_FUNC void tcc_tcov_block_begin(TCCState *s1) { }
ST_FUNC void tcc_tcov_reset_ind(TCCState *s1) { }
