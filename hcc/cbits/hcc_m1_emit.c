
static void emit_byte(FILE *out, int byte);
static int invert_binop(int op);

static void emit_named_ref(FILE *out, const char *prefix, const char *fn_name, int id)
{
  fputs(prefix, out);
  fputc('_', out);
  fputs(fn_name, out);
  fputc('_', out);
  fprintf(out, "%d", id);
}

static int target_register_arg_count(void)
{
  if (target_arch == TARGET_I386) return 0;
  if (target_arch == TARGET_AARCH64 || target_arch == TARGET_RISCV64) return 8;
  return 6;
}

static void emit_data64_le(FILE *out, unsigned long value)
{
  int i = 0;
  fprintf(out, "  ");
  while (i < 8) {
    if (i) fputc(' ', out);
    emit_byte(out, (int)(value & 255));
    value = value >> 8;
    i = i + 1;
  }
  fputc('\n', out);
}

#include "hcc_m1_arch_aarch64.c"
#include "hcc_m1_arch_riscv64.c"

static void emit_header(FILE *out)
{
  fprintf(out, "## hcc M1 output\n");
  if (target_arch == TARGET_I386) {
    fprintf(out, "## target: stage0-posix x86 M1\n");
    fprintf(out, "\n");
    fprintf(out, "DEFINE HCC_ADD_IMMEDIATE_to_esp 81C4\n");
    fprintf(out, "DEFINE HCC_STORE_ESP_IMMEDIATE_from_eax 898424\n");
    fprintf(out, "DEFINE HCC_LOAD_EFFECTIVE_ADDRESS_eax 8D8424\n");
    fprintf(out, "DEFINE HCC_LOAD_SIGNED_WORD 8B00\n");
    fprintf(out, "DEFINE HCC_STORE_WORD 8903\n");
    fprintf(out, "DEFINE HCC_STORE_HALF 668903\n");
    fprintf(out, "DEFINE HCC_STORE_CHAR 8803\n");
    fprintf(out, "DEFINE HCC_JUMP_EQ 0F84\n");
    fprintf(out, "DEFINE HCC_JUMP_NE 0F85\n");
    fprintf(out, "DEFINE HCC_JUMP_LT 0F8C\n");
    fprintf(out, "DEFINE HCC_JUMP_LE 0F8E\n");
    fprintf(out, "DEFINE HCC_JUMP_GT 0F8F\n");
    fprintf(out, "DEFINE HCC_JUMP_GE 0F8D\n");
    fprintf(out, "DEFINE HCC_JUMP_ULT 0F82\n");
    fprintf(out, "DEFINE HCC_JUMP_ULE 0F86\n");
    fprintf(out, "DEFINE HCC_JUMP_UGT 0F87\n");
    fprintf(out, "DEFINE HCC_JUMP_UGE 0F83\n");
    fprintf(out, "DEFINE HCC_CALL_eax FFD0\n");
    fprintf(out, "DEFINE CALL_IMMEDIATE E8\n");
    fprintf(out, "\n");
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_header(out);
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    riscv64_emit_header(out);
    return;
  }
  fprintf(out, "## target: stage0-posix amd64 M1\n");
  fprintf(out, "\n");
  fprintf(out, "DEFINE ADD_rbx_to_rax 4801D8\n");
  fprintf(out, "DEFINE AND_rax_rbx 4821D8\n");
  fprintf(out, "DEFINE CALL_IMMEDIATE E8\n");
  fprintf(out, "DEFINE CMP 4839C3\n");
  fprintf(out, "DEFINE COPY_rax_to_rdi 4889C7\n");
  fprintf(out, "DEFINE COPY_rax_to_rcx 4889C1\n");
  fprintf(out, "DEFINE COPY_rsp_to_rbp 4889E5\n");
  fprintf(out, "DEFINE COPY_rbp_to_rax 4889E8\n");
  fprintf(out, "DEFINE CQTO 4899\n");
  fprintf(out, "DEFINE JUMP E9\n");
  fprintf(out, "DEFINE JUMP_EQ 0F84\n");
  fprintf(out, "DEFINE JUMP_NE 0F85\n");
  fprintf(out, "DEFINE HCC_JUMP_EQ 0F84\n");
  fprintf(out, "DEFINE HCC_JUMP_NE 0F85\n");
  fprintf(out, "DEFINE HCC_JUMP_LT 0F8C\n");
  fprintf(out, "DEFINE HCC_JUMP_LE 0F8E\n");
  fprintf(out, "DEFINE HCC_JUMP_GT 0F8F\n");
  fprintf(out, "DEFINE HCC_JUMP_GE 0F8D\n");
  fprintf(out, "DEFINE HCC_JUMP_ULT 0F82\n");
  fprintf(out, "DEFINE HCC_JUMP_ULE 0F86\n");
  fprintf(out, "DEFINE HCC_JUMP_UGT 0F87\n");
  fprintf(out, "DEFINE HCC_JUMP_UGE 0F83\n");
  fprintf(out, "DEFINE LOAD_BASE_ADDRESS_rax 488D85\n");
  fprintf(out, "DEFINE LOAD_BYTE 0FBE00\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rax 48C7C0\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rdi 48C7C7\n");
  fprintf(out, "DEFINE LOAD_IMMEDIATE_rsi 48C7C6\n");
  fprintf(out, "DEFINE LOAD_INTEGER 488B00\n");
  fprintf(out, "DEFINE LOAD_RSP_IMMEDIATE_into_rax 488B8424\n");
  fprintf(out, "DEFINE MOVE_rbx_to_rax 4889D8\n");
  fprintf(out, "DEFINE MOVE_rdx_to_rax 4889D0\n");
  fprintf(out, "DEFINE MOVEZX 480FB6C0\n");
  fprintf(out, "DEFINE DIVIDES_rax_by_rbx_into_rax 48F7FB\n");
  fprintf(out, "DEFINE MODULUSS_rax_from_rbx_into_rbx 48F7FB\n");
  fprintf(out, "DEFINE MULTIPLY_rax_by_rbx_into_rax 48F7EB\n");
  fprintf(out, "DEFINE OR_rax_rbx 4809D8\n");
  fprintf(out, "DEFINE PUSH_RAX 50\n");
  fprintf(out, "DEFINE RETURN C3\n");
  fprintf(out, "DEFINE SETA 0F97C0\n");
  fprintf(out, "DEFINE SETAE 0F93C0\n");
  fprintf(out, "DEFINE SETB 0F92C0\n");
  fprintf(out, "DEFINE SETBE 0F96C0\n");
  fprintf(out, "DEFINE SETE 0F94C0\n");
  fprintf(out, "DEFINE SETG 0F9FC0\n");
  fprintf(out, "DEFINE SETGE 0F9DC0\n");
  fprintf(out, "DEFINE SETL 0F9CC0\n");
  fprintf(out, "DEFINE SETLE 0F9EC0\n");
  fprintf(out, "DEFINE SETNE 0F95C0\n");
  fprintf(out, "DEFINE STORE_INTEGER 488903\n");
  fprintf(out, "DEFINE SUBTRACT_rax_from_rbx_into_rbx 4829C3\n");
  fprintf(out, "DEFINE SYSCALL 0F05\n");
  fprintf(out, "DEFINE TEST 4885C0\n");
  fprintf(out, "DEFINE XCHG_rax_rbx 4893\n");
  fprintf(out, "DEFINE HCC_ADD_IMMEDIATE_to_rsp 4881C4\n");
  fprintf(out, "DEFINE HCC_SUB_IMMEDIATE_from_rsp 4881EC\n");
  fprintf(out, "DEFINE HCC_STORE_RSP_IMMEDIATE_from_rax 48898424\n");
  fprintf(out, "DEFINE HCC_LOAD_EFFECTIVE_ADDRESS_rax 488D8424\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rsi 4889C6\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rdx 4889C2\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_rcx 4889C1\n");
  fprintf(out, "DEFINE HCC_M_RAX_RBX 4889C3\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_r8 4989C0\n");
  fprintf(out, "DEFINE HCC_COPY_rax_to_r9 4989C1\n");
  fprintf(out, "DEFINE HCC_M_RDI_RAX 4889F8\n");
  fprintf(out, "DEFINE HCC_COPY_rsi_to_rax 4889F0\n");
  fprintf(out, "DEFINE HCC_COPY_rdx_to_rax 4889D0\n");
  fprintf(out, "DEFINE HCC_COPY_rcx_to_rax 4889C8\n");
  fprintf(out, "DEFINE HCC_COPY_r8_to_rax 4C89C0\n");
  fprintf(out, "DEFINE HCC_COPY_r9_to_rax 4C89C8\n");
  fprintf(out, "DEFINE HCC_PUSH_RSI 56\n");
  fprintf(out, "DEFINE HCC_PUSH_RDX 52\n");
  fprintf(out, "DEFINE HCC_LOAD_IMMEDIATE64_rax 48B8\n");
  fprintf(out, "DEFINE HCC_LI64_80000000 48B80000008000000000\n");
  fprintf(out, "DEFINE HCC_LI64_FFFFFFFF 48B8FFFFFFFF00000000\n");
  fprintf(out, "DEFINE HCC_SEXT8_RAX 480FBEC0\n");
  fprintf(out, "DEFINE HCC_SEXT16_RAX 480FBFC0\n");
  fprintf(out, "DEFINE HCC_SEXT32_RAX 4863C0\n");
  fprintf(out, "DEFINE HCC_ZEXT16_RAX 480FB7C0\n");
  fprintf(out, "DEFINE HCC_ZEXT32_RAX 89C0\n");
  fprintf(out, "DEFINE HCC_SHL_rax_cl 48D3E0\n");
  fprintf(out, "DEFINE HCC_SHR_rax_cl 48D3E8\n");
  fprintf(out, "DEFINE HCC_SAR_rax_cl 48D3F8\n");
  fprintf(out, "DEFINE HCC_LOAD_INTEGER 488B00\n");
  fprintf(out, "DEFINE HCC_STORE_INTEGER 488903\n");
  fprintf(out, "DEFINE HCC_LOAD_WORD 8B00\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_WORD 486300\n");
  fprintf(out, "DEFINE HCC_LOAD_HALF 0FB700\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_HALF 480FBF00\n");
  fprintf(out, "DEFINE HCC_STORE_WORD 8903\n");
  fprintf(out, "DEFINE HCC_STORE_HALF 668903\n");
  fprintf(out, "DEFINE HCC_STORE_CHAR 8803\n");
  fprintf(out, "DEFINE HCC_LOAD_SIGNED_CHAR 480FBE00\n");
  fprintf(out, "DEFINE HCC_XOR_rbx_rax_into_rax 4831D8\n");
  fprintf(out, "DEFINE HCC_XOR_rdx_rdx 4831D2\n");
  fprintf(out, "DEFINE HCC_UDIV_rax_by_rbx_into_rax 48F7F3\n");
  fprintf(out, "DEFINE HCC_CALL_rax FFD0\n");
  fprintf(out, "\n");
}

static int hex_digit(int value)
{
  if (value == 0) return '0';
  if (value == 1) return '1';
  if (value == 2) return '2';
  if (value == 3) return '3';
  if (value == 4) return '4';
  if (value == 5) return '5';
  if (value == 6) return '6';
  if (value == 7) return '7';
  if (value == 8) return '8';
  if (value == 9) return '9';
  if (value == 10) return 'A';
  if (value == 11) return 'B';
  if (value == 12) return 'C';
  if (value == 13) return 'D';
  if (value == 14) return 'E';
  return 'F';
}

static void emit_byte(FILE *out, int byte)
{
  int b = byte % 256;
  if (b < 0) b = b + 256;
  fputc('\'', out);
  fputc(hex_digit(b / 16), out);
  fputc(hex_digit(b % 16), out);
  fputc('\'', out);
}

static void emit_data_item(FILE *out, DataItem *item)
{
  int j = 0;
  int emitted = 0;
  fprintf(out, ":%s\n", item->label);
  while (j < item->len) {
    int count = 0;
    fprintf(out, "  ");
    while (j < item->len && count < 16) {
      DataValue *v = data_value_at(item->values, j);
      if (count) fputc(' ', out);
      if (v->kind == 1) {
        emit_byte(out, v->byte);
      } else {
        if (target_arch == TARGET_I386) fprintf(out, "&%s", v->label);
        else fprintf(out, "&%s '00' '00' '00' '00'", v->label);
      }
      count = count + 1;
      j = j + 1;
      if (v->kind == 1) emitted = emitted + 1;
      else if (target_arch == TARGET_I386) emitted = emitted + 4;
      else emitted = emitted + 8;
    }
    fputc('\n', out);
  }
  if ((target_arch == TARGET_AARCH64 || target_arch == TARGET_RISCV64) && emitted % 4 != 0) {
    fprintf(out, "  ");
    while (emitted % 4 != 0) {
      emit_byte(out, 0);
      emitted = emitted + 1;
      if (emitted % 4 != 0) fputc(' ', out);
    }
    fputc('\n', out);
  }
  fputc('\n', out);
}

static void emit_load_immediate(FILE *out, EmitState *state, long value)
{
  int small;
  unsigned long u;
  int i;
  emit_forget_rax(state);
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_load_immediate(out, (unsigned long)value);
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    riscv64_emit_load_immediate(out, 10, value);
    return;
  }
  if (target_arch == TARGET_I386) {
    fprintf(out, "  mov_eax, %%%d\n", (int)value);
    return;
  }
  small = (int)value;
  if ((long)small == value) {
    fprintf(out, "  LOAD_IMMEDIATE_rax %%%d\n", small);
  } else {
    u = (unsigned long)value;
    i = 0;
    fprintf(out, "  HCC_LOAD_IMMEDIATE64_rax ");
    while (i < 8) {
      if (i) fputc(' ', out);
      emit_byte(out, (int)(u & 255));
      u = u >> 8;
      i = i + 1;
    }
    fputc('\n', out);
  }
}

static void emit_load_immediate_bytes(FILE *out, EmitState *state, Operand *op)
{
  int bytes[8];
  int i = 0;
  unsigned long value = 0;
  emit_forget_rax(state);
  while (i < 8) {
    if (i < op->count) bytes[i] = op->bytes[i];
    else bytes[i] = 0;
    i = i + 1;
  }
  if (target_arch == TARGET_I386) {
    i = 3;
    while (i >= 0) {
      value = (value << 8) + (unsigned long)(bytes[i] & 255);
      i = i - 1;
    }
    fprintf(out, "  mov_eax, %%%u\n", (unsigned int)value);
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    i = 7;
    value = 0;
    while (i >= 0) {
      value = (value << 8) + (unsigned long)(bytes[i] & 255);
      i = i - 1;
    }
    aarch64_emit_load_immediate(out, value);
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    i = 7;
    value = 0;
    while (i >= 0) {
      value = (value << 8) + (unsigned long)(bytes[i] & 255);
      i = i - 1;
    }
    riscv64_emit_load_immediate(out, 10, (long)value);
    return;
  }
  if (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 128 &&
      bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 0 && bytes[7] == 0) {
    fprintf(out, "  HCC_LI64_80000000\n");
  } else if (bytes[0] == 255 && bytes[1] == 255 && bytes[2] == 255 && bytes[3] == 255 &&
             bytes[4] == 0 && bytes[5] == 0 && bytes[6] == 0 && bytes[7] == 0) {
    fprintf(out, "  HCC_LI64_FFFFFFFF\n");
  } else {
    fprintf(out, "  HCC_LOAD_IMMEDIATE64_rax ");
    i = 0;
    while (i < 8) {
      if (i) fputc(' ', out);
      emit_byte(out, bytes[i]);
      i = i + 1;
    }
    fputc('\n', out);
  }
}

static void emit_load_location(FILE *out, EmitState *state, Loc *loc, int rsp_bias)
{
  emit_forget_rax(state);
  if (loc->kind == LOC_STACK) {
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax,[esp+DWORD] %%%d\n", 4 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_load_stack(out, 8 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_load_stack(out, 8 * loc->slot + rsp_bias);
    else fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%d\n", 8 * loc->slot + rsp_bias);
  } else if (loc->kind == LOC_OBJECT) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_eax %%%d\n", 4 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_address_stack(out, 8 * loc->slot + rsp_bias);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_address_stack(out, 8 * loc->slot + rsp_bias);
    else fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot + rsp_bias);
  }
}

static void emit_load_operand(FILE *out, EmitState *state, LocArray *locs, int rsp_bias, Operand *op)
{
  Loc *loc;
  if (op->kind == OP_IMM) emit_load_immediate(out, state, op->value);
  else if (op->kind == OP_BYTES) emit_load_immediate_bytes(out, state, op);
  else if (op->kind == OP_GLOBAL) {
    emit_forget_rax(state);
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax, &%s\n", op->name);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_load_label(out, 0, op->name);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_load_label(out, 10, op->name);
    else fprintf(out, "  LOAD_IMMEDIATE_rax &%s\n", op->name);
  } else if (op->kind == OP_FUNC) {
    emit_forget_rax(state);
    if (target_arch == TARGET_I386) fprintf(out, "  mov_eax, &FUNCTION_%s\n", op->name);
    else if (target_arch == TARGET_AARCH64) {
      aarch64_emit_load_literal_prefix(out, 0);
      fprintf(out, "  &FUNCTION_%s '00' '00' '00' '00'\n", op->name);
    }
    else if (target_arch == TARGET_RISCV64) riscv64_emit_load_function_label(out, 10, op->name);
    else fprintf(out, "  LOAD_IMMEDIATE_rax &FUNCTION_%s\n", op->name);
  }
  else if (op->kind == OP_TEMP) {
    loc = lookup_loc(locs, op->value);
    if (rsp_bias == 0 && loc->kind == LOC_STACK && state->rax_temp == op->value) return;
    emit_load_location(out, state, loc, rsp_bias);
    if (rsp_bias == 0 && loc->kind == LOC_STACK) emit_remember_rax_temp(state, op->value);
  }
}

static void emit_store_temp(FILE *out, EmitState *state, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  if (loc->kind == LOC_STACK) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_STORE_ESP_IMMEDIATE_from_eax %%%d\n", 4 * loc->slot);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_store_stack(out, 8 * loc->slot);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_store_stack(out, 8 * loc->slot);
    else fprintf(out, "  HCC_STORE_RSP_IMMEDIATE_from_rax %%%d\n", 8 * loc->slot);
    emit_remember_rax_temp(state, temp);
  } else if (loc->kind == LOC_OBJECT) {
    die("cannot assign stack object");
  }
}

static void emit_address_of(FILE *out, EmitState *state, LocArray *locs, int temp)
{
  Loc *loc = lookup_loc(locs, temp);
  emit_forget_rax(state);
  if (loc->kind == LOC_STACK || loc->kind == LOC_OBJECT) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_eax %%%d\n", 4 * loc->slot);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_address_stack(out, 8 * loc->slot);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_address_stack(out, 8 * loc->slot);
    else fprintf(out, "  HCC_LOAD_EFFECTIVE_ADDRESS_rax %%%d\n", 8 * loc->slot);
  } else {
    die("cannot take address");
  }
}

static void emit_binop(FILE *out, int op)
{
  if (target_arch == TARGET_I386) {
    switch (op) {
      case BK_ADD: fprintf(out, "  add_eax,ebx\n"); break;
      case BK_SUB: fprintf(out, "  sub_ebx,eax\n  mov_eax,ebx\n"); break;
      case BK_MUL: fprintf(out, "  imul_ebx\n"); break;
      case BK_DIV: fprintf(out, "  xchg_ebx,eax\n  cdq\n  idiv_ebx\n"); break;
      case BK_MOD: fprintf(out, "  xchg_ebx,eax\n  cdq\n  idiv_ebx\n  mov_eax,edx\n"); break;
      case BK_UDIV: fprintf(out, "  xchg_ebx,eax\n  xor_edx,edx\n  div_ebx\n"); break;
      case BK_UMOD: fprintf(out, "  xchg_ebx,eax\n  xor_edx,edx\n  div_ebx\n  mov_eax,edx\n"); break;
      case BK_SHL: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  shl_eax,cl\n"); break;
      case BK_SHR: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  shr_eax,cl\n"); break;
      case BK_SAR: fprintf(out, "  mov_ecx,eax\n  mov_eax,ebx\n  sar_eax,cl\n"); break;
      case BK_EQ: fprintf(out, "  cmp_ebx,eax\n  sete_al\n  movzx_eax,al\n"); break;
      case BK_NE: fprintf(out, "  cmp_ebx,eax\n  setne_al\n  movzx_eax,al\n"); break;
      case BK_LT: fprintf(out, "  cmp_ebx,eax\n  setl_al\n  movzx_eax,al\n"); break;
      case BK_LE: fprintf(out, "  cmp_ebx,eax\n  setle_al\n  movzx_eax,al\n"); break;
      case BK_GT: fprintf(out, "  cmp_ebx,eax\n  setg_al\n  movzx_eax,al\n"); break;
      case BK_GE: fprintf(out, "  cmp_ebx,eax\n  setge_al\n  movzx_eax,al\n"); break;
      case BK_ULT: fprintf(out, "  cmp_ebx,eax\n  setb_al\n  movzx_eax,al\n"); break;
      case BK_ULE: fprintf(out, "  cmp_ebx,eax\n  setbe_al\n  movzx_eax,al\n"); break;
      case BK_UGT: fprintf(out, "  cmp_ebx,eax\n  seta_al\n  movzx_eax,al\n"); break;
      case BK_UGE: fprintf(out, "  cmp_ebx,eax\n  setae_al\n  movzx_eax,al\n"); break;
      case BK_AND: fprintf(out, "  and_eax,ebx\n"); break;
      case BK_OR: fprintf(out, "  or_eax,ebx\n"); break;
      case BK_XOR: fprintf(out, "  xor_eax,ebx\n"); break;
    }
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_binop(out, op);
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    riscv64_emit_binop(out, op);
    return;
  }
  switch (op) {
    case BK_ADD: fprintf(out, "  ADD_rbx_to_rax\n"); break;
    case BK_SUB: fprintf(out, "  SUBTRACT_rax_from_rbx_into_rbx\n  MOVE_rbx_to_rax\n"); break;
    case BK_MUL: fprintf(out, "  MULTIPLY_rax_by_rbx_into_rax\n"); break;
    case BK_DIV: fprintf(out, "  XCHG_rax_rbx\n  CQTO\n  DIVIDES_rax_by_rbx_into_rax\n"); break;
    case BK_MOD: fprintf(out, "  XCHG_rax_rbx\n  CQTO\n  MODULUSS_rax_from_rbx_into_rbx\n  MOVE_rdx_to_rax\n"); break;
    case BK_UDIV: fprintf(out, "  XCHG_rax_rbx\n  HCC_XOR_rdx_rdx\n  HCC_UDIV_rax_by_rbx_into_rax\n"); break;
    case BK_UMOD: fprintf(out, "  XCHG_rax_rbx\n  HCC_XOR_rdx_rdx\n  HCC_UDIV_rax_by_rbx_into_rax\n  MOVE_rdx_to_rax\n"); break;
    case BK_SHL: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SHL_rax_cl\n"); break;
    case BK_SHR: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SHR_rax_cl\n"); break;
    case BK_SAR: fprintf(out, "  COPY_rax_to_rcx\n  MOVE_rbx_to_rax\n  HCC_SAR_rax_cl\n"); break;
    case BK_EQ: fprintf(out, "  CMP\n  SETE\n  MOVEZX\n"); break;
    case BK_NE: fprintf(out, "  CMP\n  SETNE\n  MOVEZX\n"); break;
    case BK_LT: fprintf(out, "  CMP\n  SETL\n  MOVEZX\n"); break;
    case BK_LE: fprintf(out, "  CMP\n  SETLE\n  MOVEZX\n"); break;
    case BK_GT: fprintf(out, "  CMP\n  SETG\n  MOVEZX\n"); break;
    case BK_GE: fprintf(out, "  CMP\n  SETGE\n  MOVEZX\n"); break;
    case BK_ULT: fprintf(out, "  CMP\n  SETB\n  MOVEZX\n"); break;
    case BK_ULE: fprintf(out, "  CMP\n  SETBE\n  MOVEZX\n"); break;
    case BK_UGT: fprintf(out, "  CMP\n  SETA\n  MOVEZX\n"); break;
    case BK_UGE: fprintf(out, "  CMP\n  SETAE\n  MOVEZX\n"); break;
    case BK_AND: fprintf(out, "  AND_rax_rbx\n"); break;
    case BK_OR: fprintf(out, "  OR_rax_rbx\n"); break;
    case BK_XOR: fprintf(out, "  HCC_XOR_rbx_rax_into_rax\n"); break;
  }
}

static long mask_for_size(int size)
{
  unsigned long wide;
  if (size <= 1) return 255;
  if (size <= 2) return 65535;
  if (size <= 4) {
    wide = 65535;
    wide = (wide << 16) + 65535;
    return (long)wide;
  }
  return -1;
}

static long sign_bit_for_size(int size)
{
  unsigned long wide;
  if (size <= 1) return 128;
  if (size <= 2) return 32768;
  wide = 1;
  wide = wide << 31;
  return (long)wide;
}

static void emit_copy_acc_to_scratch(FILE *out)
{
  if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
  else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
  else if (target_arch == TARGET_RISCV64) fprintf(out, "  rd_a1 rs1_a0 mv\n");
  else fprintf(out, "  HCC_M_RAX_RBX\n");
}

static void emit_amd64_zext_loaded_rax(FILE *out, int size)
{
  if (size <= 1) fprintf(out, "  MOVEZX\n");
  else if (size <= 2) fprintf(out, "  HCC_ZEXT16_RAX\n");
  else if (size <= 4) fprintf(out, "  HCC_ZEXT32_RAX\n");
}

static void emit_i386_zext_loaded_eax(FILE *out, EmitState *state, int size)
{
  if (size >= 4) return;
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, mask_for_size(size));
  emit_binop(out, BK_AND);
}

static void emit_amd64_sext_loaded_rax(FILE *out, int size)
{
  if (size <= 1) fprintf(out, "  HCC_SEXT8_RAX\n");
  else if (size <= 2) fprintf(out, "  HCC_SEXT16_RAX\n");
  else if (size <= 4) fprintf(out, "  HCC_SEXT32_RAX\n");
}

static void emit_i386_sext_loaded_eax(FILE *out, EmitState *state, int size)
{
  long sign_bit;
  if (size >= 4) return;
  sign_bit = sign_bit_for_size(size);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, mask_for_size(size));
  emit_binop(out, BK_AND);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, sign_bit);
  emit_binop(out, BK_XOR);
  emit_copy_acc_to_scratch(out);
  emit_load_immediate(out, state, sign_bit);
  emit_binop(out, BK_SUB);
}

static void emit_zext_loaded_acc(FILE *out, EmitState *state, int size)
{
  if (target_arch == TARGET_I386) emit_i386_zext_loaded_eax(out, state, size);
  else if (target_arch == TARGET_AARCH64 || target_arch == TARGET_RISCV64) {
    if (target_arch == TARGET_AARCH64 && size == 4) {
      fprintf(out, "  UXTW_X0_W0\n");
    } else if (size < 8) {
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, mask_for_size(size));
      emit_binop(out, BK_AND);
    }
  }
  else emit_amd64_zext_loaded_rax(out, size);
  emit_forget_rax(state);
}

static void emit_sext_loaded_acc(FILE *out, EmitState *state, int size)
{
  if (target_arch == TARGET_I386) emit_i386_sext_loaded_eax(out, state, size);
  else if (target_arch == TARGET_AARCH64 || target_arch == TARGET_RISCV64) {
    long sign_bit;
    if (target_arch == TARGET_AARCH64 && size == 4) {
      fprintf(out, "  SXTW_X0_W0\n");
    } else if (size < 8) {
      sign_bit = sign_bit_for_size(size);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, mask_for_size(size));
      emit_binop(out, BK_AND);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, sign_bit);
      emit_binop(out, BK_XOR);
      emit_copy_acc_to_scratch(out);
      emit_load_immediate(out, state, sign_bit);
      emit_binop(out, BK_SUB);
    }
  }
  else emit_amd64_sext_loaded_rax(out, size);
  emit_forget_rax(state);
}

static int invert_binop(int op)
{
  switch (op) {
    case BK_EQ: return BK_NE;
    case BK_NE: return BK_EQ;
    case BK_LT: return BK_GE;
    case BK_LE: return BK_GT;
    case BK_GT: return BK_LE;
    case BK_GE: return BK_LT;
    case BK_ULT: return BK_UGE;
    case BK_ULE: return BK_UGT;
    case BK_UGT: return BK_ULE;
    case BK_UGE: return BK_ULT;
  }
  die("cannot invert branch comparison");
  return BK_NE;
}

static void emit_compare(FILE *out, EmitState *state, LocArray *locs, Operand *a, Operand *b)
{
  emit_load_operand(out, state, locs, 0, a);
  emit_copy_acc_to_scratch(out);
  emit_load_operand(out, state, locs, 0, b);
  if (target_arch == TARGET_I386) fprintf(out, "  cmp_ebx,eax\n");
  else if (target_arch == TARGET_AARCH64) fprintf(out, "  CMP_X1_X0\n");
  else if (target_arch == TARGET_RISCV64) {
  }
  else fprintf(out, "  CMP\n");
}

static const char *jump_name_for_binop(int op)
{
  switch (op) {
    case BK_EQ: return "HCC_JUMP_EQ";
    case BK_NE: return "HCC_JUMP_NE";
    case BK_LT: return "HCC_JUMP_LT";
    case BK_LE: return "HCC_JUMP_LE";
    case BK_GT: return "HCC_JUMP_GT";
    case BK_GE: return "HCC_JUMP_GE";
    case BK_ULT: return "HCC_JUMP_ULT";
    case BK_ULE: return "HCC_JUMP_ULE";
    case BK_UGT: return "HCC_JUMP_UGT";
    case BK_UGE: return "HCC_JUMP_UGE";
  }
  die("bad branch comparison");
  return "HCC_JUMP_NE";
}

static void emit_named_label(FILE *out, const char *prefix, const char *fn_name, int id)
{
  fputc(':', out);
  emit_named_ref(out, prefix, fn_name, id);
  fputc('\n', out);
}

static void emit_jump_named(FILE *out, const char *prefix, const char *fn_name, int id)
{
  int kind = 0;
  if (target_arch == TARGET_AMD64) kind = 1;
  else if (target_arch == TARGET_I386) kind = 2;
  if (kind) {
    if (kind == 1) fprintf(out, "  JUMP %%");
    else fprintf(out, "  jmp %%");
  }
  else if (target_arch == TARGET_AARCH64) {
    aarch64_emit_jump_label_parts(out, prefix, fn_name, id);
    return;
  }
  else if (target_arch == TARGET_RISCV64) {
    riscv64_emit_jump_label_parts(out, prefix, fn_name, id);
    return;
  }
  else die("bad target jump");
  emit_named_ref(out, prefix, fn_name, id);
  fputc('\n', out);
}

static void emit_truth_jump_named(FILE *out, const char *prefix, const char *fn_name, int id, int jump_if_true)
{
  int kind = 0;
  if (target_arch == TARGET_AMD64) kind = 1;
  else if (target_arch == TARGET_I386) kind = 2;
  if (kind == 1) {
    fprintf(out, "  TEST\n");
    if (jump_if_true) fprintf(out, "  JUMP_NE %%");
    else fprintf(out, "  JUMP_EQ %%");
  } else if (kind == 2) {
    fprintf(out, "  test_eax,eax\n");
    if (jump_if_true) fprintf(out, "  jne %%");
    else fprintf(out, "  je %%");
  } else if (target_arch == TARGET_AARCH64) {
    aarch64_emit_truth_jump_label_parts(out, prefix, fn_name, id, jump_if_true);
    return;
  } else if (target_arch == TARGET_RISCV64) {
    riscv64_emit_truth_jump_label_parts(out, prefix, fn_name, id, jump_if_true);
    return;
  } else die("bad target truth jump");
  emit_named_ref(out, prefix, fn_name, id);
  fputc('\n', out);
}

static void emit_jump(FILE *out, const char *fn_name, int target)
{
  emit_jump_named(out, "HCC_BLOCK", fn_name, target);
}

static void emit_compare_jump(FILE *out, const char *fn_name, int op, int target)
{
  if (target_arch == TARGET_AARCH64) {
    aarch64_emit_compare_jump(out, fn_name, op, target);
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    riscv64_emit_compare_jump(out, fn_name, op, target);
    return;
  }
  fprintf(out, "  %s %%", jump_name_for_binop(op));
  emit_named_ref(out, "HCC_BLOCK", fn_name, target);
  fputc('\n', out);
}

static void emit_truth_jump(FILE *out, const char *fn_name, int jump_if_true, int target)
{
  emit_truth_jump_named(out, "HCC_BLOCK", fn_name, target, jump_if_true);
}

static void emit_truth_branch(FILE *out, const char *fn_name, int yes, int no, int next_id)
{
  if (next_id == yes) {
    emit_truth_jump(out, fn_name, 0, no);
  } else if (next_id == no) {
    emit_truth_jump(out, fn_name, 1, yes);
  } else {
    emit_truth_jump(out, fn_name, 1, yes);
    emit_jump(out, fn_name, no);
  }
}

static void emit_compare_branch(FILE *out, const char *fn_name, int op, int yes, int no, int next_id)
{
  if (next_id == yes) {
    emit_compare_jump(out, fn_name, invert_binop(op), no);
  } else if (next_id == no) {
    emit_compare_jump(out, fn_name, op, yes);
  } else {
    emit_compare_jump(out, fn_name, op, yes);
    emit_jump(out, fn_name, no);
  }
}

static int call_stack_bytes(int argc)
{
  if (target_arch == TARGET_I386) return argc * 4;
  {
    int stack_args = argc - target_register_arg_count();
    if (stack_args <= 0) return 0;
    return stack_args * 8;
  }
}

static void emit_call_cleanup(FILE *out, int argc)
{
  int bytes = call_stack_bytes(argc);
  if (bytes > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_ADD_IMMEDIATE_to_esp %%%d\n", bytes);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_add_imm_reg(out, 18, 18, bytes);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_add_imm_reg(out, 2, 2, bytes);
    else fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", bytes);
  }
}

static void emit_argument_move(FILE *out, int index)
{
  if (target_arch == TARGET_AARCH64) {
    if (index == 0) return;
    if (index == 1) fprintf(out, "  SET_X1_FROM_X0\n");
    else if (index == 2) fprintf(out, "  SET_X2_FROM_X0\n");
    else if (index == 3) fprintf(out, "  SET_X3_FROM_X0\n");
    else if (index == 4) fprintf(out, "  SET_X4_FROM_X0\n");
    else if (index == 5) fprintf(out, "  SET_X5_FROM_X0\n");
    else if (index == 6) fprintf(out, "  SET_X6_FROM_X0\n");
    else if (index == 7) aarch64_emit_mov_reg(out, 7, 0);
    else die("bad argument register");
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    if (index == 0) return;
    riscv64_emit_mov_reg(out, riscv64_arg_reg(index), 10);
    return;
  }
  if (index == 0) fprintf(out, "  COPY_rax_to_rdi\n");
  else if (index == 1) fprintf(out, "  HCC_COPY_rax_to_rsi\n");
  else if (index == 2) fprintf(out, "  HCC_COPY_rax_to_rdx\n");
  else if (index == 3) fprintf(out, "  HCC_COPY_rax_to_rcx\n");
  else if (index == 4) fprintf(out, "  HCC_COPY_rax_to_r8\n");
  else if (index == 5) fprintf(out, "  HCC_COPY_rax_to_r9\n");
  else die("bad argument register");
}

static void emit_arguments(FILE *out, EmitState *state, LocArray *locs, Operand *args, int argc)
{
  int i = argc - 1;
  int pushed = 0;
  if (target_arch == TARGET_I386) {
    while (i >= 0) {
      emit_load_operand(out, state, locs, pushed * 4, operand_at(args, i));
      fprintf(out, "  push_eax\n");
      pushed = pushed + 1;
      i = i - 1;
    }
    return;
  }
  if (target_arch == TARGET_AARCH64) {
    while (i >= 8) {
      emit_load_operand(out, state, locs, pushed * 8, operand_at(args, i));
      fprintf(out, "  PUSH_X0\n");
      pushed = pushed + 1;
      i = i - 1;
    }
    i = argc;
    if (i > 8) i = 8;
    i = i - 1;
    while (i >= 0) {
      emit_load_operand(out, state, locs, call_stack_bytes(argc), operand_at(args, i));
      emit_argument_move(out, i);
      i = i - 1;
    }
    return;
  }
  if (target_arch == TARGET_RISCV64) {
    while (i >= 8) {
      emit_load_operand(out, state, locs, pushed * 8, operand_at(args, i));
      riscv64_emit_add_imm_reg(out, 2, 2, -8);
      fprintf(out, "  rs1_sp rs2_a0 sd\n");
      pushed = pushed + 1;
      i = i - 1;
    }
    i = argc;
    if (i > 8) i = 8;
    i = i - 1;
    while (i >= 0) {
      emit_load_operand(out, state, locs, call_stack_bytes(argc), operand_at(args, i));
      emit_argument_move(out, i);
      i = i - 1;
    }
    return;
  }
  while (i >= 6) {
    emit_load_operand(out, state, locs, pushed * 8, operand_at(args, i));
    fprintf(out, "  PUSH_RAX\n");
    pushed = pushed + 1;
    i = i - 1;
  }
  i = 0;
  while (i < argc && i < 6) {
    emit_load_operand(out, state, locs, call_stack_bytes(argc), operand_at(args, i));
    emit_argument_move(out, i);
    i = i + 1;
  }
}

static void emit_memory_load(FILE *out, EmitState *state, LocArray *locs, Instr *in, int width, int is_signed, const char *i386_op, const char *other_op)
{
  if (width == 8 && target_arch == TARGET_I386) die("i386 M1 backend cannot lower 64-bit load");
  emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
  if (target_arch == TARGET_I386 && i386_op) fprintf(out, "%s", i386_op);
  else if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 1, width, is_signed, 0, 0);
  else if (target_arch == TARGET_RISCV64) riscv64_emit_load_store(out, 1, width, is_signed, 10, 0);
  else fprintf(out, "%s", other_op);
  emit_store_temp(out, state, locs, in->temp);
}

static void emit_memory_store(FILE *out, EmitState *state, LocArray *locs, Instr *in, int width, const char *other_op)
{
  if (width == 8 && target_arch == TARGET_I386) die("i386 M1 backend cannot lower 64-bit store");
  emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
  emit_copy_acc_to_scratch(out);
  emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
  if (target_arch == TARGET_AARCH64) aarch64_emit_load_store(out, 0, width, 0, 1, 0);
  else if (target_arch == TARGET_RISCV64) riscv64_emit_load_store_from(out, 0, width, 0, 11, 0, 10);
  else fprintf(out, "%s", other_op);
}

static void emit_instrs(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, InstrList *list);

static void emit_instr(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, Instr *in)
{
  int param_offset;
  int width;

  if (in->kind == IK_SEXT) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_sext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }
  if (in->kind == IK_ZEXT) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_zext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }
  if (in->kind == IK_TRUNC) {
    width = in->value;
    emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
    emit_zext_loaded_acc(out, state, width);
    emit_store_temp(out, state, locs, in->temp);
    return;
  }

  switch (in->kind) {
    case IK_PARAM:
      if (target_arch == TARGET_I386) {
        param_offset = total_slots * 4 + 4 + in->value * 4;
        fprintf(out, "  mov_eax,[esp+DWORD] %%%d\n", param_offset);
      } else if (target_arch == TARGET_AARCH64) {
        if (in->value < 8) {
          if (in->value == 0) {
          } else {
            aarch64_emit_mov_reg(out, 0, in->value);
          }
        } else {
          param_offset = total_slots * 8 + 8 + (in->value - 8) * 8;
          aarch64_emit_load_store(out, 1, 8, 0, 18, param_offset);
        }
      } else if (target_arch == TARGET_RISCV64) {
        if (in->value < 8) {
          if (in->value != 0) riscv64_emit_mov_reg(out, 10, in->value + 10);
        } else {
          param_offset = total_slots * 8 + 8 + (in->value - 8) * 8;
          riscv64_emit_load_store(out, 1, 8, 0, 2, param_offset);
        }
      } else if (in->value == 0) fprintf(out, "  HCC_M_RDI_RAX\n");
      else if (in->value == 1) fprintf(out, "  HCC_COPY_rsi_to_rax\n");
      else if (in->value == 2) fprintf(out, "  HCC_COPY_rdx_to_rax\n");
      else if (in->value == 3) fprintf(out, "  HCC_COPY_rcx_to_rax\n");
      else if (in->value == 4) fprintf(out, "  HCC_COPY_r8_to_rax\n");
      else if (in->value == 5) fprintf(out, "  HCC_COPY_r9_to_rax\n");
      else {
        param_offset = total_slots * 8 + 8 + (in->value - 6) * 8;
        fprintf(out, "  LOAD_RSP_IMMEDIATE_into_rax %%%d\n", param_offset);
      }
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_ALLOCA:
      break;
    case IK_CONST:
      emit_load_immediate(out, state, in->value);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_COPY:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_ADDROF:
      emit_address_of(out, state, locs, in->temp2);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_LOAD64:
      emit_memory_load(out, state, locs, in, 8, 0, 0, "  HCC_LOAD_INTEGER\n");
      break;
    case IK_LOAD32:
      emit_memory_load(out, state, locs, in, 4, 0, "  mov_eax,[eax]\n", "  HCC_LOAD_WORD\n");
      break;
    case IK_LOADS32:
      emit_memory_load(out, state, locs, in, 4, 1, 0, "  HCC_LOAD_SIGNED_WORD\n");
      break;
    case IK_LOAD16:
      emit_memory_load(out, state, locs, in, 2, 0, "  movzx_eax,WORD_PTR_[eax]\n", "  HCC_LOAD_HALF\n");
      break;
    case IK_LOADS16:
      emit_memory_load(out, state, locs, in, 2, 1, "  movsx_eax,WORD_PTR_[eax]\n", "  HCC_LOAD_SIGNED_HALF\n");
      break;
    case IK_LOAD8:
      emit_memory_load(out, state, locs, in, 1, 0, "  movzx_eax,BYTE_PTR_[eax]\n", "  LOAD_BYTE\n  MOVEZX\n");
      break;
    case IK_LOADS8:
      emit_memory_load(out, state, locs, in, 1, 1, "  movsx_eax,BYTE_PTR_[eax]\n", "  HCC_LOAD_SIGNED_CHAR\n");
      break;
    case IK_STORE64:
      emit_memory_store(out, state, locs, in, 8, "  HCC_STORE_INTEGER\n");
      break;
    case IK_STORE32:
      emit_memory_store(out, state, locs, in, 4, "  HCC_STORE_WORD\n");
      break;
    case IK_STORE16:
      emit_memory_store(out, state, locs, in, 2, "  HCC_STORE_HALF\n");
      break;
    case IK_STORE8:
      emit_memory_store(out, state, locs, in, 1, "  HCC_STORE_CHAR\n");
      break;
    case IK_BIN:
      emit_load_operand(out, state, locs, 0, instr_a_ptr(in));
      if (target_arch == TARGET_I386) fprintf(out, "  mov_ebx,eax\n");
      else if (target_arch == TARGET_AARCH64) fprintf(out, "  SET_X1_FROM_X0\n");
      else if (target_arch == TARGET_RISCV64) riscv64_emit_mov_reg(out, 11, 10);
      else fprintf(out, "  HCC_M_RAX_RBX\n");
      emit_load_operand(out, state, locs, 0, instr_b_ptr(in));
      emit_binop(out, in->binop);
      emit_store_temp(out, state, locs, in->temp);
      break;
    case IK_CALL:
      emit_arguments(out, state, locs, in->args, in->argc);
      if (target_arch == TARGET_AARCH64) {
        aarch64_emit_load_literal_prefix(out, 16);
        fprintf(out, "  &FUNCTION_%s '00' '00' '00' '00'\n", in->name);
        fprintf(out, "  BLR_X16\n");
      } else if (target_arch == TARGET_RISCV64) {
        riscv64_emit_load_function_label(out, 7, in->name);
        fprintf(out, "  rd_ra rs1_t2 !0 jalr\n");
      } else {
        fprintf(out, "  CALL_IMMEDIATE %%FUNCTION_%s\n", in->name);
      }
      emit_forget_rax(state);
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, state, locs, in->result);
      break;
    case IK_CALLI:
      if (target_arch == TARGET_AARCH64) {
        emit_load_operand(out, state, locs, 0, instr_callee_ptr(in));
        fprintf(out, "  SET_X16_FROM_X0\n");
        emit_arguments(out, state, locs, in->args, in->argc);
        fprintf(out, "  BLR_X16\n");
      } else if (target_arch == TARGET_RISCV64) {
        emit_load_operand(out, state, locs, 0, instr_callee_ptr(in));
        riscv64_emit_mov_reg(out, 7, 10);
        emit_arguments(out, state, locs, in->args, in->argc);
        fprintf(out, "  rd_ra rs1_t2 !0 jalr\n");
      } else {
        emit_arguments(out, state, locs, in->args, in->argc);
        emit_load_operand(out, state, locs, call_stack_bytes(in->argc), instr_callee_ptr(in));
        if (target_arch == TARGET_I386) fprintf(out, "  HCC_CALL_eax\n");
        else fprintf(out, "  HCC_CALL_rax\n");
      }
      emit_forget_rax(state);
      emit_call_cleanup(out, in->argc);
      if (in->result >= 0) emit_store_temp(out, state, locs, in->result);
      break;
    case IK_COND:
      emit_instrs(out, fn_name, state, locs, total_slots, instr_cond_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_cond_op_ptr(in));
      emit_truth_jump_named(out, "HCC_COND_ELSE", fn_name, in->temp, 0);
      emit_forget_rax(state);
      emit_instrs(out, fn_name, state, locs, total_slots, instr_true_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_true_op_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      emit_jump_named(out, "HCC_COND_DONE", fn_name, in->temp);
      emit_named_label(out, "HCC_COND_ELSE", fn_name, in->temp);
      emit_forget_rax(state);
      emit_instrs(out, fn_name, state, locs, total_slots, instr_false_instrs_ptr(in));
      emit_load_operand(out, state, locs, 0, instr_false_op_ptr(in));
      emit_store_temp(out, state, locs, in->temp);
      emit_named_label(out, "HCC_COND_DONE", fn_name, in->temp);
      emit_forget_rax(state);
      break;
  }
}

static void emit_instrs(FILE *out, const char *fn_name, EmitState *state, LocArray *locs, int total_slots, InstrList *list)
{
  int i = 0;
  while (i < list->len) {
    emit_instr(out, fn_name, state, locs, total_slots, instr_at(list->items, i));
    i = i + 1;
  }
}

static void emit_block_ref(FILE *out, const char *fn_name, int id)
{
  emit_named_ref(out, "HCC_BLOCK", fn_name, id);
}

static void emit_cleanup_stack(FILE *out, int total_slots)
{
  if (total_slots > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  HCC_ADD_IMMEDIATE_to_esp %%%d\n", total_slots * 4);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_add_imm_reg(out, 18, 18, total_slots * 8);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_add_imm_reg(out, 2, 2, total_slots * 8);
    else fprintf(out, "  HCC_ADD_IMMEDIATE_to_rsp %%%d\n", total_slots * 8);
  }
}

static void emit_terminator(FILE *out, Function *fn, int block_index, EmitState *state, LocArray *locs, int total_slots, Block *block)
{
  int next_id = -1;
  if (block_index + 1 < fn->len) {
    Block *next_block = block_at(fn->blocks, block_index + 1);
    next_id = next_block->id;
  }
  if (block->term_kind == TK_RET) {
    if (block->term_op.kind == 0) emit_load_immediate(out, state, 0);
    else emit_load_operand(out, state, locs, 0, block_term_op_ptr(block));
    emit_cleanup_stack(out, total_slots);
    if (target_arch == TARGET_I386) fprintf(out, "  ret\n");
    else if (target_arch == TARGET_AARCH64) fprintf(out, "  POP_LR\n  RETURN\n");
    else if (target_arch == TARGET_RISCV64) fprintf(out, "  rd_ra rs1_sp ld\n  rd_sp rs1_sp !8 addi\n  ret\n");
    else fprintf(out, "  RETURN\n");
  } else if (block->term_kind == TK_JUMP) {
    if (next_id != block->yes) {
      emit_jump(out, fn->name, block->yes);
    }
  } else if (block->term_kind == TK_BRANCH) {
    emit_load_operand(out, state, locs, 0, block_term_op_ptr(block));
    emit_truth_branch(out, fn->name, block->yes, block->no, next_id);
  } else if (block->term_kind == TK_BRANCH_CMP) {
    emit_compare(out, state, locs, block_term_op_ptr(block), block_term_b_ptr(block));
    emit_compare_branch(out, fn->name, block->term_binop, block->yes, block->no, next_id);
  }
  emit_forget_rax(state);
}

static void emit_function(FILE *out, Function *fn)
{
  LocArray locs;
  EmitState state;
  int total_slots;
  int i;
  total_slots = allocate_function(fn, &locs);
  emit_state_init(&state);
  fprintf(out, ":FUNCTION_%s\n", fn->name);
  if (target_arch == TARGET_AARCH64) fprintf(out, "  PUSH_LR\n");
  else if (target_arch == TARGET_RISCV64) fprintf(out, "  rd_sp rs1_sp !-8 addi\n  rs1_sp rs2_ra sd\n");
  if (total_slots > 0) {
    if (target_arch == TARGET_I386) fprintf(out, "  sub_esp, %%%d\n", total_slots * 4);
    else if (target_arch == TARGET_AARCH64) aarch64_emit_sub_imm_reg(out, 18, total_slots * 8);
    else if (target_arch == TARGET_RISCV64) riscv64_emit_add_imm_reg(out, 2, 2, -total_slots * 8);
    else fprintf(out, "  HCC_SUB_IMMEDIATE_from_rsp %%%d\n", total_slots * 8);
  }
  i = 0;
  while (i < fn->len) {
    Block *block = block_at(fn->blocks, i);
    if (block->id != 0) {
      emit_forget_rax(&state);
      fprintf(out, ":");
      emit_block_ref(out, fn->name, block->id);
      fputc('\n', out);
    }
    emit_instrs(out, fn->name, &state, &locs, total_slots, block_instrs_ptr(block));
    emit_terminator(out, fn, i, &state, &locs, total_slots, block);
    i = i + 1;
  }
  fputc('\n', out);
#if !defined(__M2__)
  if (locs.items) free(locs.items);
#endif
}
