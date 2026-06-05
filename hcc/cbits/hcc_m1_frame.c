
static void ensure_loc(LocArray *locs, int temp)
{
  int old;
  if (temp < locs->cap) return;
  old = locs->cap;
  if (!locs->cap) locs->cap = 64;
  while (temp >= locs->cap) locs->cap = locs->cap * 2;
  locs->items = xrealloc(locs->items, sizeof(Loc) * locs->cap);
  while (old < locs->cap) {
    Loc *loc = loc_at(locs->items, old);
    loc->kind = LOC_NONE;
    loc->slot = 0;
    loc->slots = 0;
    old = old + 1;
  }
}

static void alloc_def(LocArray *locs, int *next_slot, int temp)
{
  Loc *loc;
  ensure_loc(locs, temp);
  loc = loc_at(locs->items, temp);
  if (loc->kind != LOC_NONE) return;
  loc->kind = LOC_STACK;
  loc->slot = *next_slot;
  loc->slots = 1;
  *next_slot = *next_slot + 1;
}

static void alloc_object(LocArray *locs, int *next_slot, int temp, int size)
{
  int slots;
  Loc *loc;
  ensure_loc(locs, temp);
  loc = loc_at(locs->items, temp);
  if (loc->kind != LOC_NONE) return;
  if (size < 1) size = 1;
  if (target_arch == TARGET_I386) slots = (size + 3) / 4;
  else slots = (size + 7) / 8;
  loc->kind = LOC_OBJECT;
  loc->slot = *next_slot;
  loc->slots = slots;
  *next_slot = *next_slot + slots;
}

static void allocate_instrs(InstrList *list, LocArray *locs, int *next_slot)
{
  int i = 0;
  while (i < list->len) {
    Instr *in = instr_at(list->items, i);
    switch (in->kind) {
      case IK_ALLOCA: alloc_object(locs, next_slot, in->temp, in->value); break;
      case IK_PARAM:
      case IK_CONST:
      case IK_COPY:
      case IK_ADDROF:
      case IK_LOAD64:
      case IK_LOAD32:
      case IK_LOADS32:
      case IK_LOAD16:
      case IK_LOADS16:
      case IK_LOAD8:
      case IK_LOADS8:
      case IK_SEXT:
      case IK_ZEXT:
      case IK_TRUNC:
      case IK_BIN:
        alloc_def(locs, next_slot, in->temp);
        break;
      case IK_CALL:
      case IK_CALLI:
        if (in->result >= 0) alloc_def(locs, next_slot, in->result);
        break;
      case IK_COND:
        allocate_instrs(instr_cond_instrs_ptr(in), locs, next_slot);
        allocate_instrs(instr_true_instrs_ptr(in), locs, next_slot);
        allocate_instrs(instr_false_instrs_ptr(in), locs, next_slot);
        alloc_def(locs, next_slot, in->temp);
        break;
    }
    i = i + 1;
  }
}

static int allocate_function(Function *fn, LocArray *locs)
{
  int next_slot = 0;
  int i = 0;
  locs->items = 0;
  locs->cap = 0;
  while (i < fn->len) {
    Block *block = block_at(fn->blocks, i);
    allocate_instrs(block_instrs_ptr(block), locs, &next_slot);
    i = i + 1;
  }
  return next_slot;
}

static Loc *lookup_loc(LocArray *locs, int temp)
{
  Loc *loc;
  if (temp < 0 || temp >= locs->cap) die("missing allocation");
  loc = loc_at(locs->items, temp);
  if (loc->kind == LOC_NONE) die("missing allocation");
  return loc;
}

static void emit_state_init(EmitState *state)
{
  state->rax_temp = -1;
}

static void emit_forget_rax(EmitState *state)
{
  state->rax_temp = -1;
}

static void emit_remember_rax_temp(EmitState *state, int temp)
{
  state->rax_temp = temp;
}
