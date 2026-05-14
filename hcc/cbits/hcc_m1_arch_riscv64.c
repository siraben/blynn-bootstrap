static const char *riscv64_rd(int reg)
{
  switch (reg) {
    case 0: return "rd_x0";
    case 1: return "rd_ra";
    case 2: return "rd_sp";
    case 5: return "rd_t0";
    case 6: return "rd_t1";
    case 7: return "rd_t2";
    case 10: return "rd_a0";
    case 11: return "rd_a1";
    case 12: return "rd_a2";
    case 13: return "rd_a3";
    case 14: return "rd_a4";
    case 15: return "rd_a5";
    case 16: return "rd_a6";
    case 17: return "rd_a7";
  }
  die("bad riscv64 destination register");
  return "rd_x0";
}

static const char *riscv64_rs1(int reg)
{
  switch (reg) {
    case 0: return "rs1_x0";
    case 1: return "rs1_ra";
    case 2: return "rs1_sp";
    case 5: return "rs1_t0";
    case 6: return "rs1_t1";
    case 7: return "rs1_t2";
    case 10: return "rs1_a0";
    case 11: return "rs1_a1";
    case 12: return "rs1_a2";
    case 13: return "rs1_a3";
    case 14: return "rs1_a4";
    case 15: return "rs1_a5";
    case 16: return "rs1_a6";
    case 17: return "rs1_a7";
  }
  die("bad riscv64 first source register");
  return "rs1_x0";
}

static const char *riscv64_rs2(int reg)
{
  switch (reg) {
    case 0: return "rs2_x0";
    case 1: return "rs2_ra";
    case 2: return "rs2_sp";
    case 5: return "rs2_t0";
    case 6: return "rs2_t1";
    case 7: return "rs2_t2";
    case 10: return "rs2_a0";
    case 11: return "rs2_a1";
    case 12: return "rs2_a2";
    case 13: return "rs2_a3";
    case 14: return "rs2_a4";
    case 15: return "rs2_a5";
    case 16: return "rs2_a6";
    case 17: return "rs2_a7";
  }
  die("bad riscv64 second source register");
  return "rs2_x0";
}

static int riscv64_arg_reg(int index)
{
  if (index < 0 || index > 7) die("bad riscv64 argument register");
  return index + 10;
}

static void riscv64_emit_mov_reg(FILE *out, int dst, int src)
{
  if (dst == src) return;
  fprintf(out, "  %s %s mv\n", riscv64_rd(dst), riscv64_rs1(src));
}

static void riscv64_emit_add_imm_reg(FILE *out, int dst, int src, int imm)
{
  int remaining = imm;
  int first = 1;
  int base;
  if (remaining == 0) {
    riscv64_emit_mov_reg(out, dst, src);
    return;
  }
  while (remaining > 2047) {
    base = dst;
    if (first) base = src;
    fprintf(out, "  %s %s !2047 addi\n", riscv64_rd(dst), riscv64_rs1(base));
    remaining = remaining - 2047;
    first = 0;
  }
  while (remaining < -2048) {
    base = dst;
    if (first) base = src;
    fprintf(out, "  %s %s !-2048 addi\n", riscv64_rd(dst), riscv64_rs1(base));
    remaining = remaining + 2048;
    first = 0;
  }
  base = dst;
  if (first) base = src;
  fprintf(out, "  %s %s !%d addi\n", riscv64_rd(dst), riscv64_rs1(base), remaining);
}

static void riscv64_emit_local_ref(FILE *out, const char *kind, int id)
{
  fputs("HCC_RV_", out);
  fputs(riscv64_label_namespace, out);
  fputc('_', out);
  fputs(kind, out);
  fputc('_', out);
  fprintf(out, "%d", id);
}

static void riscv64_emit_load_literal(FILE *out, int reg, unsigned long value)
{
  static int literal_id = 0;
  int id = literal_id;
  literal_id = literal_id + 1;
  fprintf(out, "  rd_t1 ~");
  riscv64_emit_local_ref(out, "LITERAL", id);
  fprintf(out, " auipc\n");
  fprintf(out, "  rd_t1 rs1_t1 !");
  riscv64_emit_local_ref(out, "LITERAL", id);
  fprintf(out, " addi\n");
  fprintf(out, "  %s rs1_t1 ld\n", riscv64_rd(reg));
  fprintf(out, "  rd_x0 $");
  riscv64_emit_local_ref(out, "LITERAL_DONE", id);
  fprintf(out, " jal\n");
  fputc(':', out);
  riscv64_emit_local_ref(out, "LITERAL", id);
  fputc('\n', out);
  emit_data64_le(out, value);
  fputc(':', out);
  riscv64_emit_local_ref(out, "LITERAL_DONE", id);
  fputc('\n', out);
}

static void riscv64_emit_load_label(FILE *out, int reg, const char *label)
{
  fprintf(out, "  %s ~%s auipc\n", riscv64_rd(reg), label);
  fprintf(out, "  %s %s !%s addi\n", riscv64_rd(reg), riscv64_rs1(reg), label);
}

static void riscv64_emit_load_label_parts(FILE *out, int reg, const char *prefix, const char *fn_name, int id)
{
  fprintf(out, "  %s ~", riscv64_rd(reg));
  emit_named_ref(out, prefix, fn_name, id);
  fprintf(out, " auipc\n");
  fprintf(out, "  %s %s !", riscv64_rd(reg), riscv64_rs1(reg));
  emit_named_ref(out, prefix, fn_name, id);
  fprintf(out, " addi\n");
}

static void riscv64_emit_load_function_label(FILE *out, int reg, const char *name)
{
  fprintf(out, "  %s ~FUNCTION_%s auipc\n", riscv64_rd(reg), name);
  fprintf(out, "  %s %s !FUNCTION_%s addi\n", riscv64_rd(reg), riscv64_rs1(reg), name);
}

static void riscv64_emit_load_store_from(FILE *out, int is_load, int size, int is_signed, int base, int offset, int src)
{
  const char *op = "ld";
  if (is_load) {
    if (size == 8) op = "ld";
    else if (size == 4 && is_signed) op = "lw";
    else if (size == 4) op = "lwu";
    else if (size == 2 && is_signed) op = "lh";
    else if (size == 2) op = "lhu";
    else if (is_signed) op = "lb";
    else op = "lbu";
  } else {
    if (size == 8) op = "sd";
    else if (size == 4) op = "sw";
    else if (size == 2) op = "sh";
    else op = "sb";
  }
  if (is_load && offset >= -2048 && offset <= 2047) {
    fprintf(out, "  rd_a0 %s !%d %s\n", riscv64_rs1(base), offset, op);
    return;
  }
  if (!is_load && offset == 0) {
    fprintf(out, "  %s %s %s\n", riscv64_rs1(base), riscv64_rs2(src), op);
    return;
  }
  riscv64_emit_load_literal(out, 5, (unsigned long)offset);
  fprintf(out, "  rd_t0 %s rs2_t0 add\n", riscv64_rs1(base));
  if (is_load) fprintf(out, "  rd_a0 rs1_t0 %s\n", op);
  else fprintf(out, "  rs1_t0 %s %s\n", riscv64_rs2(src), op);
}

static void riscv64_emit_load_store(FILE *out, int is_load, int size, int is_signed, int base, int offset)
{
  riscv64_emit_load_store_from(out, is_load, size, is_signed, base, offset, 10);
}

static void riscv64_emit_header(FILE *out)
{
  fprintf(out, "## target: stage0-posix riscv64 M1\n");
  fprintf(out, "\n");
  fprintf(out, "DEFINE addi 13000000\n");
  fprintf(out, "DEFINE auipc 17000000\n");
  fprintf(out, "DEFINE jal 6F000000\n");
  fprintf(out, "DEFINE jalr 67000000\n");
  fprintf(out, "DEFINE beq 63000000\n");
  fprintf(out, "DEFINE bne 63100000\n");
  fprintf(out, "DEFINE blt 63400000\n");
  fprintf(out, "DEFINE bge 63500000\n");
  fprintf(out, "DEFINE bltu 63600000\n");
  fprintf(out, "DEFINE bgeu 63700000\n");
  fprintf(out, "DEFINE lb 03000000\n");
  fprintf(out, "DEFINE lh 03100000\n");
  fprintf(out, "DEFINE lw 03200000\n");
  fprintf(out, "DEFINE lbu 03400000\n");
  fprintf(out, "DEFINE lhu 03500000\n");
  fprintf(out, "DEFINE lwu 03600000\n");
  fprintf(out, "DEFINE ld 03300000\n");
  fprintf(out, "DEFINE sb 23000000\n");
  fprintf(out, "DEFINE sh 23100000\n");
  fprintf(out, "DEFINE sw 23200000\n");
  fprintf(out, "DEFINE sd 23300000\n");
  fprintf(out, "DEFINE sltiu 13300000\n");
  fprintf(out, "DEFINE xori 13400000\n");
  fprintf(out, "DEFINE add 33000000\n");
  fprintf(out, "DEFINE sub 33000040\n");
  fprintf(out, "DEFINE sll 33100000\n");
  fprintf(out, "DEFINE slt 33200000\n");
  fprintf(out, "DEFINE sltu 33300000\n");
  fprintf(out, "DEFINE xor 33400000\n");
  fprintf(out, "DEFINE srl 33500000\n");
  fprintf(out, "DEFINE sra 33500040\n");
  fprintf(out, "DEFINE or 33600000\n");
  fprintf(out, "DEFINE and 33700000\n");
  fprintf(out, "DEFINE mul 33000002\n");
  fprintf(out, "DEFINE div 33400002\n");
  fprintf(out, "DEFINE rem 33600002\n");
  fprintf(out, "DEFINE ecall 73000000\n");
  fprintf(out, "DEFINE mv 13000000\n");
  fprintf(out, "DEFINE beqz 63000000\n");
  fprintf(out, "DEFINE bnez 63100000\n");
  fprintf(out, "DEFINE ret 67800000\n");
  fprintf(out, "DEFINE rd_x0 .00000000\n");
  fprintf(out, "DEFINE rd_ra .80000000\n");
  fprintf(out, "DEFINE rd_sp .00010000\n");
  fprintf(out, "DEFINE rd_t0 .80020000\n");
  fprintf(out, "DEFINE rd_t1 .00030000\n");
  fprintf(out, "DEFINE rd_t2 .80030000\n");
  fprintf(out, "DEFINE rd_a0 .00050000\n");
  fprintf(out, "DEFINE rd_a1 .80050000\n");
  fprintf(out, "DEFINE rd_a2 .00060000\n");
  fprintf(out, "DEFINE rd_a3 .80060000\n");
  fprintf(out, "DEFINE rd_a4 .00070000\n");
  fprintf(out, "DEFINE rd_a5 .80070000\n");
  fprintf(out, "DEFINE rd_a6 .00080000\n");
  fprintf(out, "DEFINE rd_a7 .80080000\n");
  fprintf(out, "DEFINE rs1_x0 .00000000\n");
  fprintf(out, "DEFINE rs1_ra .00800000\n");
  fprintf(out, "DEFINE rs1_sp .00000100\n");
  fprintf(out, "DEFINE rs1_t0 .00800200\n");
  fprintf(out, "DEFINE rs1_t1 .00000300\n");
  fprintf(out, "DEFINE rs1_t2 .00800300\n");
  fprintf(out, "DEFINE rs1_a0 .00000500\n");
  fprintf(out, "DEFINE rs1_a1 .00800500\n");
  fprintf(out, "DEFINE rs1_a2 .00000600\n");
  fprintf(out, "DEFINE rs1_a3 .00800600\n");
  fprintf(out, "DEFINE rs1_a4 .00000700\n");
  fprintf(out, "DEFINE rs1_a5 .00800700\n");
  fprintf(out, "DEFINE rs1_a6 .00000800\n");
  fprintf(out, "DEFINE rs1_a7 .00800800\n");
  fprintf(out, "DEFINE rs2_x0 .00000000\n");
  fprintf(out, "DEFINE rs2_ra .00001000\n");
  fprintf(out, "DEFINE rs2_sp .00002000\n");
  fprintf(out, "DEFINE rs2_t0 .00005000\n");
  fprintf(out, "DEFINE rs2_t1 .00006000\n");
  fprintf(out, "DEFINE rs2_t2 .00007000\n");
  fprintf(out, "DEFINE rs2_a0 .0000A000\n");
  fprintf(out, "DEFINE rs2_a1 .0000B000\n");
  fprintf(out, "DEFINE rs2_a2 .0000C000\n");
  fprintf(out, "DEFINE rs2_a3 .0000D000\n");
  fprintf(out, "DEFINE rs2_a4 .0000E000\n");
  fprintf(out, "DEFINE rs2_a5 .0000F000\n");
  fprintf(out, "DEFINE rs2_a6 .00000001\n");
  fprintf(out, "DEFINE rs2_a7 .00001001\n");
  fprintf(out, "\n");
}

static void riscv64_emit_load_stack(FILE *out, int offset)
{
  riscv64_emit_load_store(out, 1, 8, 0, 2, offset);
}

static void riscv64_emit_address_stack(FILE *out, int offset)
{
  riscv64_emit_add_imm_reg(out, 10, 2, offset);
}

static void riscv64_emit_store_stack(FILE *out, int offset)
{
  riscv64_emit_load_store(out, 0, 8, 0, 2, offset);
}

static void riscv64_emit_binop(FILE *out, int op)
{
  switch (op) {
    case BK_ADD: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 add\n"); break;
    case BK_SUB: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 sub\n"); break;
    case BK_MUL: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 mul\n"); break;
    case BK_DIV: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 div\n"); break;
    case BK_MOD: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 rem\n"); break;
    case BK_SHL: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 sll\n"); break;
    case BK_SHR: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 srl\n"); break;
    case BK_SAR: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 sra\n"); break;
    case BK_EQ: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 xor\n  rd_a0 rs1_a0 !1 sltiu\n"); break;
    case BK_NE: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 xor\n  rd_a0 rs1_x0 rs2_a0 sltu\n"); break;
    case BK_LT: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 slt\n"); break;
    case BK_LE: fprintf(out, "  rd_a0 rs1_a0 rs2_a1 slt\n  rd_a0 rs1_a0 !1 xori\n"); break;
    case BK_GT: fprintf(out, "  rd_a0 rs1_a0 rs2_a1 slt\n"); break;
    case BK_GE: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 slt\n  rd_a0 rs1_a0 !1 xori\n"); break;
    case BK_ULT: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 sltu\n"); break;
    case BK_ULE: fprintf(out, "  rd_a0 rs1_a0 rs2_a1 sltu\n  rd_a0 rs1_a0 !1 xori\n"); break;
    case BK_UGT: fprintf(out, "  rd_a0 rs1_a0 rs2_a1 sltu\n"); break;
    case BK_UGE: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 sltu\n  rd_a0 rs1_a0 !1 xori\n"); break;
    case BK_AND: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 and\n"); break;
    case BK_OR: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 or\n"); break;
    case BK_XOR: fprintf(out, "  rd_a0 rs1_a1 rs2_a0 xor\n"); break;
    default: die("bad riscv64 binary operation");
  }
}

static void riscv64_emit_jump_label_parts(FILE *out, const char *prefix, const char *fn_name, int id)
{
  riscv64_emit_load_label_parts(out, 7, prefix, fn_name, id);
  fprintf(out, "  rd_x0 rs1_t2 !0 jalr\n");
}

static int riscv64_truth_skip_id = 0;

static const char *riscv64_truth_skip_op(int jump_if_true)
{
  if (jump_if_true) return "beqz";
  return "bnez";
}

static int riscv64_next_truth_skip_id(void)
{
  int id = riscv64_truth_skip_id;
  riscv64_truth_skip_id = riscv64_truth_skip_id + 1;
  return id;
}

static void riscv64_emit_truth_skip(FILE *out, int jump_if_true, int id)
{
  fprintf(out, "  rs1_a0 @");
  riscv64_emit_local_ref(out, "TRUTH_SKIP", id);
  fputc(' ', out);
  fputs(riscv64_truth_skip_op(jump_if_true), out);
  fputc('\n', out);
}

static void riscv64_emit_truth_skip_label(FILE *out, int id)
{
  fputc(':', out);
  riscv64_emit_local_ref(out, "TRUTH_SKIP", id);
  fputc('\n', out);
}

static int riscv64_false_branch_kind(int op)
{
  switch (op) {
    case BK_EQ: return 2;
    case BK_NE: return 1;
    case BK_LT: return 4;
    case BK_LE: return 3;
    case BK_GT: return 4;
    case BK_GE: return 3;
    case BK_ULT: return 6;
    case BK_ULE: return 5;
    case BK_UGT: return 6;
    case BK_UGE: return 5;
  }
  die("bad riscv64 branch comparison");
  return 1;
}

static int riscv64_false_branch_swaps_args_for_binop(int op)
{
  switch (op) {
    case BK_LE:
    case BK_GT:
    case BK_ULE:
    case BK_UGT:
      return 1;
  }
  return 0;
}

static const char *riscv64_branch_op(int kind)
{
  switch (kind) {
    case 1: return "beq";
    case 2: return "bne";
    case 3: return "blt";
    case 4: return "bge";
    case 5: return "bltu";
    case 6: return "bgeu";
  }
  die("bad riscv64 branch opcode");
  return "beq";
}

static void riscv64_emit_compare_jump(FILE *out, const char *fn_name, int op, int target)
{
  static int skip_id = 0;
  int id = skip_id;
  int branch_kind = 0;
  const char *lhs = "rs1_a1";
  const char *rhs = "rs2_a0";
  skip_id = skip_id + 1;
  branch_kind = riscv64_false_branch_kind(op);
  if (riscv64_false_branch_swaps_args_for_binop(op)) {
    lhs = "rs1_a0";
    rhs = "rs2_a1";
  }
  fprintf(out, "  %s %s @", lhs, rhs);
  riscv64_emit_local_ref(out, "BRANCH_SKIP", id);
  fputc(' ', out);
  fputs(riscv64_branch_op(branch_kind), out);
  fputc('\n', out);
  riscv64_emit_jump_label_parts(out, "HCC_BLOCK", fn_name, target);
  fputc(':', out);
  riscv64_emit_local_ref(out, "BRANCH_SKIP", id);
  fputc('\n', out);
}

static void riscv64_emit_truth_jump_label_parts(FILE *out, const char *prefix, const char *fn_name, int target, int jump_if_true)
{
  int id = riscv64_next_truth_skip_id();
  riscv64_emit_truth_skip(out, jump_if_true, id);
  riscv64_emit_jump_label_parts(out, prefix, fn_name, target);
  riscv64_emit_truth_skip_label(out, id);
}
