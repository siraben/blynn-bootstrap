static void expect_line(Input *file, char *line, const char *expected) {
  if (!read_line(file, line, LINE_CAP)) die("unexpected eof");
  if (strcmp(line, expected)) die("unexpected section marker");
}

static void parse_ir_operand(char **cursor, Operand *op) {
  char *tok = need_token(cursor);
  int i;
  memset(op, 0, sizeof(Operand));
  if (tok[0] == 'T') {
    op->kind = OP_TEMP;
    op->value = parse_long_text(tok + 1);
  } else if (tok[0] == 'I') {
    op->kind = OP_IMM;
    op->value = parse_long_text(tok + 1);
  } else if (tok[0] == 'B') {
    op->kind = OP_BYTES;
    op->count = (int)parse_long_text(tok + 1);
    if (op->count > 0) op->bytes = xrealloc(0, sizeof(int) * op->count);
    i = 0;
    while (i < op->count) {
      op->bytes[i] = parse_int_token(cursor);
      i = i + 1;
    }
  } else if (tok[0] == 'G') {
    op->kind = OP_GLOBAL;
    op->name = xstrdup(tok + 1);
  } else if (tok[0] == 'F') {
    op->kind = OP_FUNC;
    op->name = xstrdup(tok + 1);
  } else {
    die_token("unknown IR operand kind", tok);
  }
}

static int parse_ir_result(char **cursor) {
  char *tok = need_token(cursor);
  if (str_eq(tok, "-")) return -1;
  return (int)parse_long_text(tok);
}

static void parse_ir_prefixed_operand(char *line, const char *prefix, Operand *op) {
  char *cursor = line;
  char *tok = need_token(&cursor);
  if (strcmp(tok, prefix)) die("unexpected IR operand prefix");
  parse_ir_operand(&cursor, op);
}

/* The parser borrows one line buffer. Consume or copy every token before
   reading again or descending recursively; no cursor survives descent. */
static void parse_ir_instrs_until_end(Input *file, char *line, InstrList *list);

static void parse_ir_instr_line(Input *file, char *line, Instr *instr) {
  char *cursor = line;
  char *tok;
  int i;
  memset(instr, 0, sizeof(Instr));
  instr->result = -1;
  tok = need_token(&cursor);
  instr->kind = (int)parse_long_text(tok);
  switch (instr->kind) {
  case IK_PARAM:
  case IK_ALLOCA:
  case IK_CONST:
    instr->temp = parse_int_token(&cursor);
    instr->value = parse_long_token(&cursor);
    break;
  case IK_COPY:
  case IK_LOAD64:
  case IK_LOAD32:
  case IK_LOADS32:
  case IK_LOAD16:
  case IK_LOADS16:
  case IK_LOAD8:
  case IK_LOADS8:
    instr->temp = parse_int_token(&cursor);
    parse_ir_operand(&cursor, instr_a_ptr(instr));
    break;
  case IK_SEXT:
  case IK_ZEXT:
  case IK_TRUNC:
    instr->temp = parse_int_token(&cursor);
    instr->value = parse_long_token(&cursor);
    parse_ir_operand(&cursor, instr_a_ptr(instr));
    break;
  case IK_ADDROF:
    instr->temp = parse_int_token(&cursor);
    instr->temp2 = parse_int_token(&cursor);
    break;
  case IK_STORE64:
  case IK_STORE32:
  case IK_STORE16:
  case IK_STORE8:
    parse_ir_operand(&cursor, instr_a_ptr(instr));
    parse_ir_operand(&cursor, instr_b_ptr(instr));
    break;
  case IK_BIN:
    instr->temp = parse_int_token(&cursor);
    instr->binop = parse_int_token(&cursor);
    parse_ir_operand(&cursor, instr_a_ptr(instr));
    parse_ir_operand(&cursor, instr_b_ptr(instr));
    break;
  case IK_CALL:
    instr->result = parse_ir_result(&cursor);
    instr->name = xstrdup(need_token(&cursor));
    instr->argc = parse_int_token(&cursor);
    if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
    i = 0;
    while (i < instr->argc) {
      parse_ir_operand(&cursor, operand_at(instr->args, i));
      i = i + 1;
    }
    break;
  case IK_CALLI:
    instr->result = parse_ir_result(&cursor);
    parse_ir_operand(&cursor, instr_callee_ptr(instr));
    instr->argc = parse_int_token(&cursor);
    if (instr->argc > 0) instr->args = xrealloc(0, sizeof(Operand) * instr->argc);
    i = 0;
    while (i < instr->argc) {
      parse_ir_operand(&cursor, operand_at(instr->args, i));
      i = i + 1;
    }
    break;
  case IK_COND:
    instr->temp = parse_int_token(&cursor);
    expect_line(file, line, "[");
    parse_ir_instrs_until_end(file, line, instr_cond_instrs_ptr(instr));
    if (!read_line(file, line, LINE_CAP)) die("missing IR CONDOP");
    parse_ir_prefixed_operand(line, "O", instr_cond_op_ptr(instr));
    expect_line(file, line, "[");
    parse_ir_instrs_until_end(file, line, instr_true_instrs_ptr(instr));
    if (!read_line(file, line, LINE_CAP)) die("missing IR TRUEOP");
    parse_ir_prefixed_operand(line, "O", instr_true_op_ptr(instr));
    expect_line(file, line, "[");
    parse_ir_instrs_until_end(file, line, instr_false_instrs_ptr(instr));
    if (!read_line(file, line, LINE_CAP)) die("missing IR FALSEOP");
    parse_ir_prefixed_operand(line, "O", instr_false_op_ptr(instr));
    expect_line(file, line, "Q");
    break;
  default:
    die("unknown IR instruction");
  }
}

static void parse_ir_instrs_until_end(Input *file, char *line, InstrList *list) {
  Instr instr;
  memset(list, 0, sizeof(InstrList));
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "]")) return;
    parse_ir_instr_line(file, line, &instr);
    append_instr(list, &instr);
  }
  die("unexpected eof in IR nested instructions");
}

static void parse_ir_term(Block *block, char *line) {
  char *cursor = line;
  char *tok = need_token(&cursor);
  if (str_eq(tok, "R")) {
    block->term_kind = TK_RET;
    while (*cursor == ' ' || *cursor == '\t') cursor = cursor + 1;
    if (*cursor != 0) {
      parse_ir_operand(&cursor, block_term_op_ptr(block));
    } else {
      block->term_op.kind = 0;
    }
  } else if (str_eq(tok, "J")) {
    block->term_kind = TK_JUMP;
    block->yes = parse_int_token(&cursor);
  } else if (str_eq(tok, "B")) {
    block->term_kind = TK_BRANCH;
    parse_ir_operand(&cursor, block_term_op_ptr(block));
    block->yes = parse_int_token(&cursor);
    block->no = parse_int_token(&cursor);
  } else if (str_eq(tok, "C")) {
    block->term_kind = TK_BRANCH_CMP;
    block->term_binop = parse_int_token(&cursor);
    parse_ir_operand(&cursor, block_term_op_ptr(block));
    parse_ir_operand(&cursor, block_term_b_ptr(block));
    block->yes = parse_int_token(&cursor);
    block->no = parse_int_token(&cursor);
  } else {
    die("unknown IR terminator");
  }
}

static void parse_ir_block(Input *file, char *line, Block *block) {
  char *cursor = line;
  char *tok;
  Instr instr;
  memset(block, 0, sizeof(Block));
  tok = need_token(&cursor);
  if (strcmp(tok, "L")) die("expected IR block");
  block->id = parse_int_token(&cursor);
  while (read_line(file, line, LINE_CAP)) {
    if (str_prefix_n(line, "R", 1) || str_prefix_n(line, "J ", 2) || str_prefix_n(line, "B ", 2) ||
        str_prefix_n(line, "C ", 2)) {
      parse_ir_term(block, line);
      return;
    }
    parse_ir_instr_line(file, line, &instr);
    append_instr(block_instrs_ptr(block), &instr);
  }
  die("unexpected eof in IR block");
}

static void parse_ir_function(Input *file, char *line, Function *fn) {
  char *cursor = line;
  char *tok;
  Block block;
  memset(fn, 0, sizeof(Function));
  tok = need_token(&cursor);
  if (strcmp(tok, "F")) die("expected IR function");
  fn->name = xstrdup(need_token(&cursor));
  while (read_line(file, line, LINE_CAP)) {
    if (str_eq(line, "E")) return;
    parse_ir_block(file, line, &block);
    append_block(fn, &block);
  }
  die("unexpected eof in IR function");
}

static void parse_ir_data_item(Input *file, char *line, DataItem *item) {
  char *cursor = line;
  char *tok;
  memset(item, 0, sizeof(DataItem));
  tok = need_token(&cursor);
  if (strcmp(tok, "D")) die_token("expected IR data item", tok);
  item->label = xstrdup(need_token(&cursor));
  while (read_line(file, line, LINE_CAP)) {
    DataValue value;
    if (str_eq(line, "E")) return;
    cursor = line;
    tok = need_token(&cursor);
    if (str_eq(tok, "z")) {
      append_zero_data_values(item, parse_int_token(&cursor));
      continue;
    }
    memset(&value, 0, sizeof(value));
    if (str_eq(tok, "b")) {
      value.kind = 1;
      value.byte = parse_int_token(&cursor);
    } else if (str_eq(tok, "a")) {
      value.kind = 2;
      value.label = xstrdup(need_token(&cursor));
    } else {
      die("unknown IR data value");
    }
    append_data_value(item, &value);
  }
  die("unexpected eof in IR data");
}

static void emit_byte(FILE *out, int byte);
static void emit_header(FILE *out);
static void emit_data_item(FILE *out, DataItem *item);
static void emit_function(FILE *out, Function *fn);

#if !defined(__M2__)
static void free_operand(Operand *op) {
  if (op->bytes) free(op->bytes);
  if (op->name) free(op->name);
}

static void free_instr_list(InstrList *list);

static void free_instr(Instr *in) {
  int i;
  free_operand(instr_a_ptr(in));
  free_operand(instr_b_ptr(in));
  free_operand(instr_callee_ptr(in));
  if (in->name) free(in->name);
  i = 0;
  while (i < in->argc) {
    free_operand(operand_at(in->args, i));
    i = i + 1;
  }
  if (in->args) free(in->args);
  free_instr_list(instr_cond_instrs_ptr(in));
  free_instr_list(instr_true_instrs_ptr(in));
  free_instr_list(instr_false_instrs_ptr(in));
  free_operand(instr_cond_op_ptr(in));
  free_operand(instr_true_op_ptr(in));
  free_operand(instr_false_op_ptr(in));
}

static void free_instr_list(InstrList *list) {
  int i = 0;
  while (i < list->len) {
    free_instr(instr_at(list->items, i));
    i = i + 1;
  }
  if (list->items) free(list->items);
}

static void free_block(Block *block) {
  free_instr_list(block_instrs_ptr(block));
  free_operand(block_term_op_ptr(block));
  free_operand(block_term_b_ptr(block));
}

static void free_function(Function *fn) {
  int i = 0;
  if (fn->name) free(fn->name);
  while (i < fn->len) {
    free_block(block_at(fn->blocks, i));
    i = i + 1;
  }
  if (fn->blocks) free(fn->blocks);
}

static void free_data_item(DataItem *item) {
  int i = 0;
  if (item->label) free(item->label);
  while (i < item->len) {
    DataValue *value = data_value_at(item->values, i);
    if (value->label) free(value->label);
    i = i + 1;
  }
  if (item->values) free(item->values);
}
#else
static void free_function(Function *fn) {
  (void)fn;
}
static void free_data_item(DataItem *item) {
  (void)item;
}
#endif

static void translate_ir_module(Input *file, FILE *out, char *line) {
  DataItem item;
  Function fn;
  emit_header(out);
  while (read_line(file, line, LINE_CAP)) {
#if defined(__M2__)
    /* Parsed items and emission scratch die together; keep the line buffer. */
    long item_heap = hcc_heap_cur;
#endif
    if (str_prefix_n(line, "D ", 2)) {
      parse_ir_data_item(file, line, &item);
      emit_data_item(out, &item);
      free_data_item(&item);
    } else if (str_prefix_n(line, "F ", 2)) {
      parse_ir_function(file, line, &fn);
      emit_function(out, &fn);
      free_function(&fn);
    } else if (line[0] != 0)
      die("unexpected IR top-level line");
#if defined(__M2__)
    hcc_heap_cur = item_heap;
#endif
  }
}
