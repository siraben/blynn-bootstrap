self_build() {
  compiler="$1"
  output="$2"
  run_target "$compiler" $bootstrap_link_prefix \
    -I . \
    -I "$tcc_include_src" \
    -I "$mes_include_src" \
    -D__linux__=1 \
    -DBOOTSTRAP=1 \
    -DHAVE_LONG_LONG=1 \
    -DHAVE_SETJMP=1 \
    -DHAVE_BITFIELD=1 \
    -DHAVE_FLOAT=1 \
    "$tcc_target_define_arg" \
    $tcc_riscv64_no_asm_define_arg \
    -Dinline= \
    -DCONFIG_TCCDIR=\"\" \
    -DCONFIG_SYSROOT=\"\" \
    -DCONFIG_TCC_CRTPREFIX=\"{B}\" \
    -DCONFIG_TCC_ELFINTERP=\"/mes/loader\" \
    -DCONFIG_TCC_LIBPATHS=\"{B}\" \
    -DCONFIG_TCC_SYSINCLUDEPATHS=\"$tcc_sysinclude_path\" \
    -DTCC_LIBGCC=\"libc.a\" \
    -DTCC_LIBTCC1=\"libtcc1.a\" \
    -DCONFIG_TCC_LIBTCC1_MES=0 \
    -DCONFIG_TCC_STATIC=1 \
    -DCONFIG_USE_LIBGCC=1 \
    -DTCC_MES_LIBC=1 \
    -DTCC_VERSION=\"0.9.28-$tcc_version\" \
    -DONE_SOURCE=1 \
    -DCONFIG_TCC_SEMLOCK=0 \
    tcc.c \
    $bootstrap_link_suffix \
    -o "$output"
}
