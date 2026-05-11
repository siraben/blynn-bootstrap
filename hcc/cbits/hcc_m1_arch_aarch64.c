static void aarch64_emit_insn(FILE *out, unsigned long word)
{
  fprintf(out, "  ");
  emit_word_le(out, word);
  fputc('\n', out);
}

static void aarch64_emit_mov_reg(FILE *out, int dst, int src)
{
  aarch64_emit_insn(out, 0xAA0003E0UL | ((unsigned long)src << 16) | (unsigned long)dst);
}

static void aarch64_emit_add_imm_reg(FILE *out, int dst, int src, int imm)
{
  int remaining = imm;
  int first = 1;
  if (remaining == 0) {
    if (dst != src) aarch64_emit_mov_reg(out, dst, src);
    return;
  }
  while (remaining > 0) {
    int chunk = remaining;
    int base = dst;
    if (chunk > 4095) chunk = 4095;
    if (first) base = src;
    aarch64_emit_insn(out,
      0x91000000UL |
      ((unsigned long)chunk << 10) |
      ((unsigned long)base << 5) |
      (unsigned long)dst);
    remaining = remaining - chunk;
    first = 0;
  }
}

static void aarch64_emit_sub_imm_reg(FILE *out, int reg, int imm)
{
  int remaining = imm;
  while (remaining > 0) {
    int chunk = remaining;
    if (chunk > 4095) chunk = 4095;
    aarch64_emit_insn(out,
      0xD1000000UL |
      ((unsigned long)chunk << 10) |
      ((unsigned long)reg << 5) |
      (unsigned long)reg);
    remaining = remaining - chunk;
  }
}

static void aarch64_emit_load_literal_prefix(FILE *out, int reg)
{
  aarch64_emit_insn(out, 0x58000040UL | (unsigned long)reg);
  aarch64_emit_insn(out, 0x14000003UL);
}

static void aarch64_emit_data64(FILE *out, unsigned long value)
{
  emit_data64_le(out, value);
}

static void aarch64_emit_load_label(FILE *out, int reg, const char *label)
{
  aarch64_emit_load_literal_prefix(out, reg);
  fprintf(out, "  &%s '00' '00' '00' '00'\n", label);
}

static void aarch64_emit_load_store(FILE *out, int is_load, int size, int is_signed, int base, int offset)
{
  unsigned long op;
  int scale = 0;
  if (size == 8) scale = 3;
  else if (size == 4) scale = 2;
  else if (size == 2) scale = 1;
  if (offset >= 0 && (offset & ((1 << scale) - 1)) == 0 && (offset >> scale) < 4096) {
    unsigned long imm = (unsigned long)(offset >> scale);
    if (is_load) {
      if (size == 8) op = 0xF9400000UL;
      else if (size == 4 && is_signed) op = 0xB9800000UL;
      else if (size == 4) op = 0xB9400000UL;
      else if (size == 2 && is_signed) op = 0x79800000UL;
      else if (size == 2) op = 0x79400000UL;
      else if (is_signed) op = 0x39800000UL;
      else op = 0x39400000UL;
    } else {
      if (size == 8) op = 0xF9000000UL;
      else if (size == 4) op = 0xB9000000UL;
      else if (size == 2) op = 0x79000000UL;
      else op = 0x39000000UL;
    }
    aarch64_emit_insn(out, op | (imm << 10) | ((unsigned long)base << 5));
    return;
  }
  aarch64_emit_add_imm_reg(out, 16, base, offset);
  aarch64_emit_load_store(out, is_load, size, is_signed, 16, 0);
}

static void aarch64_emit_header(FILE *out)
{
  fprintf(out, "## target: stage0-posix aarch64 M1\n");
  fprintf(out, "\n");
  fprintf(out, "DEFINE BR_X16 00021fd6\n");
  fprintf(out, "DEFINE BLR_X16 00023fd6\n");
  fprintf(out, "DEFINE RETURN c0035fd6\n");
  fprintf(out, "DEFINE HCC_CBZ_X0_PAST_BR 400000b4\n");
  fprintf(out, "DEFINE HCC_CBNZ_X0_PAST_BR 400000b5\n");
  fprintf(out, "DEFINE SKIP_INST_EQ 40000054\n");
  fprintf(out, "DEFINE SKIP_INST_NE 41000054\n");
  fprintf(out, "DEFINE SKIP_INST_LT 4b000054\n");
  fprintf(out, "DEFINE SKIP_INST_LE 4d000054\n");
  fprintf(out, "DEFINE SKIP_INST_GT 4c000054\n");
  fprintf(out, "DEFINE SKIP_INST_GE 4a000054\n");
  fprintf(out, "DEFINE SKIP_INST_LO 43000054\n");
  fprintf(out, "DEFINE SKIP_INST_LS 49000054\n");
  fprintf(out, "DEFINE SKIP_INST_HS 42000054\n");
  fprintf(out, "DEFINE SKIP_INST_HI 48000054\n");
  fprintf(out, "DEFINE PUSH_X0 408e1ff8\n");
  fprintf(out, "DEFINE PUSH_LR 5e8e1ff8\n");
  fprintf(out, "DEFINE POP_LR 5e8640f8\n");
  fprintf(out, "DEFINE SET_X0_TO_0 000080d2\n");
  fprintf(out, "DEFINE SET_X0_TO_1 200080d2\n");
  fprintf(out, "DEFINE SET_X1_FROM_X0 e10300aa\n");
  fprintf(out, "DEFINE SET_X2_FROM_X0 e20300aa\n");
  fprintf(out, "DEFINE SET_X3_FROM_X0 e30300aa\n");
  fprintf(out, "DEFINE SET_X4_FROM_X0 e40300aa\n");
  fprintf(out, "DEFINE SET_X5_FROM_X0 e50300aa\n");
  fprintf(out, "DEFINE SET_X6_FROM_X0 e60300aa\n");
  fprintf(out, "DEFINE SET_X16_FROM_X0 f00300aa\n");
  fprintf(out, "DEFINE ADD_X0_X1_X0 2000008b\n");
  fprintf(out, "DEFINE SUB_X0_X1_X0 200000cb\n");
  fprintf(out, "DEFINE MUL_X0_X1_X0 207c009b\n");
  fprintf(out, "DEFINE SDIV_X0_X1_X0 200cc09a\n");
  fprintf(out, "DEFINE SDIV_X2_X1_X0 220cc09a\n");
  fprintf(out, "DEFINE UDIV_X0_X1_X0 2008c09a\n");
  fprintf(out, "DEFINE MSUB_X0_X0_X2_X1 0084029b\n");
  fprintf(out, "DEFINE LSHIFT_X0_X1_X0 2020c09a\n");
  fprintf(out, "DEFINE LOGICAL_RSHIFT_X0_X1_X0 2024c09a\n");
  fprintf(out, "DEFINE ARITH_RSHIFT_X0_X1_X0 2028c09a\n");
  fprintf(out, "DEFINE AND_X0_X1_X0 2000008a\n");
  fprintf(out, "DEFINE OR_X0_X1_X0 200000aa\n");
  fprintf(out, "DEFINE XOR_X0_X1_X0 000001ca\n");
  fprintf(out, "DEFINE CMP_X1_X0 3f0000eb\n");
  fprintf(out, "DEFINE SYSCALL 010000d4\n");
  fprintf(out, "\n");
}

static void aarch64_emit_load_immediate(FILE *out, unsigned long value)
{
  aarch64_emit_load_literal_prefix(out, 0);
  aarch64_emit_data64(out, value);
}

static void aarch64_emit_load_stack(FILE *out, int offset)
{
  aarch64_emit_load_store(out, 1, 8, 0, 18, offset);
}

static void aarch64_emit_address_stack(FILE *out, int offset)
{
  aarch64_emit_add_imm_reg(out, 0, 18, offset);
}

static void aarch64_emit_store_stack(FILE *out, int offset)
{
  aarch64_emit_load_store(out, 0, 8, 0, 18, offset);
}

static void aarch64_emit_binop(FILE *out, int op)
{
  switch (op) {
    case BK_ADD: fprintf(out, "  ADD_X0_X1_X0\n"); break;
    case BK_SUB: fprintf(out, "  SUB_X0_X1_X0\n"); break;
    case BK_MUL: fprintf(out, "  MUL_X0_X1_X0\n"); break;
    case BK_DIV: fprintf(out, "  SDIV_X0_X1_X0\n"); break;
    case BK_MOD: fprintf(out, "  SDIV_X2_X1_X0\n  MSUB_X0_X0_X2_X1\n"); break;
    case BK_SHL: fprintf(out, "  LSHIFT_X0_X1_X0\n"); break;
    case BK_SHR: fprintf(out, "  LOGICAL_RSHIFT_X0_X1_X0\n"); break;
    case BK_SAR: fprintf(out, "  ARITH_RSHIFT_X0_X1_X0\n"); break;
    case BK_EQ: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_EQ\n  SET_X0_TO_0\n"); break;
    case BK_NE: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_NE\n  SET_X0_TO_0\n"); break;
    case BK_LT: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_LT\n  SET_X0_TO_0\n"); break;
    case BK_LE: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_LE\n  SET_X0_TO_0\n"); break;
    case BK_GT: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_GT\n  SET_X0_TO_0\n"); break;
    case BK_GE: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_GE\n  SET_X0_TO_0\n"); break;
    case BK_ULT: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_LO\n  SET_X0_TO_0\n"); break;
    case BK_ULE: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_LS\n  SET_X0_TO_0\n"); break;
    case BK_UGT: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_HI\n  SET_X0_TO_0\n"); break;
    case BK_UGE: fprintf(out, "  CMP_X1_X0\n  SET_X0_TO_1\n  SKIP_INST_HS\n  SET_X0_TO_0\n"); break;
    case BK_AND: fprintf(out, "  AND_X0_X1_X0\n"); break;
    case BK_OR: fprintf(out, "  OR_X0_X1_X0\n"); break;
    case BK_XOR: fprintf(out, "  XOR_X0_X1_X0\n"); break;
  }
}

static const char *aarch64_skip_name_for_binop(int op)
{
  switch (op) {
    case BK_EQ: return "SKIP_INST_EQ";
    case BK_NE: return "SKIP_INST_NE";
    case BK_LT: return "SKIP_INST_LT";
    case BK_LE: return "SKIP_INST_LE";
    case BK_GT: return "SKIP_INST_GT";
    case BK_GE: return "SKIP_INST_GE";
    case BK_ULT: return "SKIP_INST_LO";
    case BK_ULE: return "SKIP_INST_LS";
    case BK_UGT: return "SKIP_INST_HI";
    case BK_UGE: return "SKIP_INST_HS";
  }
  die("bad AArch64 branch comparison");
  return "SKIP_INST_NE";
}

static void aarch64_emit_jump(FILE *out, const char *fn_name, int target)
{
  aarch64_emit_load_literal_prefix(out, 16);
  fprintf(out, "  &HCC_BLOCK_%s_%d '00' '00' '00' '00'\n", fn_name, target);
  fprintf(out, "  BR_X16\n");
}

static void aarch64_emit_compare_jump(FILE *out, const char *fn_name, int op, int target)
{
  aarch64_emit_load_literal_prefix(out, 16);
  fprintf(out, "  &HCC_BLOCK_%s_%d '00' '00' '00' '00'\n", fn_name, target);
  fprintf(out, "  %s\n  BR_X16\n", aarch64_skip_name_for_binop(invert_binop(op)));
}

static void aarch64_emit_truth_jump(FILE *out, const char *fn_name, int jump_if_true, int target)
{
  aarch64_emit_load_literal_prefix(out, 16);
  fprintf(out, "  &HCC_BLOCK_%s_%d '00' '00' '00' '00'\n", fn_name, target);
  if (jump_if_true) fprintf(out, "  HCC_CBZ_X0_PAST_BR\n");
  else fprintf(out, "  HCC_CBNZ_X0_PAST_BR\n");
  fprintf(out, "  BR_X16\n");
}
