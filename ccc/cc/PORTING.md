# ccc porting contract (Haskell → ML2)

ccc is HCC ported to ML2, the dialect compiled by ccc/stages/pattern-compiler.ml.
The parts in ccc/cc/*.ml are concatenated in the order given by the
PARTS-cc1 / PARTS-ccpp manifests in this directory; the result must ALSO
typecheck as host OCaml when prefixed with ccc/tests/prelude-ocaml.ml
(that is the dev loop). Read these foundation files before porting anything:
util.ml, prim.ml, lexer.ml, symtab.ml, literal.ml, ast.ml,
constexpr.ml, parser.ml (for show_quoted), ir.ml.

## Output-parity rule (the prime directive)

ccc1's HCCIR text output must equal `hcc1 --m1-ir` byte-for-byte. That means:
- The ORDER of effects must be preserved exactly: every `freshTemp`,
  `freshBlock`, `freshLabel`, `addDataItem`, bind* in a Haskell do-block
  happens in the same order in ML2. Sequence them with `let x = f () in ...`.
  Never reorder. `mapM`/`mapM_`/`traverse` become explicit left-to-right
  recursion. Watch out for applicative style (`f <$> a <*> b`): effects run
  left to right.
- Diagnostic strings must match the reference character for character
  (including `show` quoting via show_quoted, ints via buf_add_int).
- Haskell `div`/`mod` are FLOORING: use hdiv/hmod from prim.ml, never the
  native `/`/`mod` (which truncate) unless both operands are provably >= 0.
- Bitwise/shift helpers come from literal.ml (bit_and_int etc.), never
  native land/lor/lsl.

## ML2 dialect restrictions (the stage 04 compiler rejects violations)

- No exceptions; fatal errors via cc_throw/cc_throw_str (they exit).
- No local `let rec ... and ...` (mutual recursion is TOP-LEVEL only).
  Local single self-recursive `let rec f x = ... in` is fine.
- Records exist, restricted: monomorphic (no type parameters), field
  names globally unique across all record types, literals must list
  every field in declaration order. `e.f` projects, `e.f <- v` assigns
  to a `mutable` field (rhs parsed at the `:=` level). At most ONE
  effectful field expression per literal (see the evaluation-order
  rule). No record patterns and no `{ e with ... }`; project instead.
- No `function`, no `when` guards, no `as` patterns, no or-patterns `p1|p2`,
  no `begin/end`, no `if ... then ... else` without else when a value is
  needed, no labels/optional args, no partial application of these builtins:
  write_byte, bytes_get/set, array_get/set/make, string_get, etc.
- `match` arms: nested patterns of constructors/tuples/lists/literals/_/vars
  only. Bind-and-test (`as`) must be rewritten.
- Strings are bytes. Literals "..." are immutable; build text with the buf_*
  API from util.ml. Compare with bytes_eq / bytes_eq_str.
- `'a option` (None/Some) and lists ([], ::, [a; b]) are available.
- Type declarations: `type a = ... and b = ...` groups are supported,
  parameters like 'a allowed; types are erased on the VM but must typecheck
  under host OCaml.
- Integer literals only (chars as 'c' ok). No floats anywhere.
- Sequencing with `;` works; parenthesize `(if ...);` inside sequences.

## Name mapping

Haskell camelCase → ML2 snake_case mechanically (lowerExpr → lower_expr,
typeSize → type_size, registerTypeAggregates → register_type_aggregates).
This must be applied consistently so independently ported segments link.

Foundation API (already written):
- CompileM disappears: `CompileM a` functions become plain `... -> a`
  functions that touch the cs_* refs from ir.ml. `pure x` → `x`.
- throwC msg → cc_throw_str "..." (or cc_throw for built byte strings).
  withErrorContext ctx act → with_error_context ctx (fun () -> ...).
- freshTemp/freshBlock/freshLabel/freshDataLabel → fresh_temp () etc.
  Temp/BlockId are plain ints.
- bindVar/bindStruct/bindGlobal/bindConstant/bindFunction/bindFunctionType,
  lookupVarMaybe/lookupVarType/lookupGlobalType/lookupConstant/
  lookupFunction/lookupFunctionType/lookupStruct, lookupStructSizeCache/
  cacheStructSize, lookupStructMemberCache/cacheStructMember,
  targetWordSize, currentFunctionName/currentReturnType,
  withCurrentFunction/withFunctionScope/withVarScope/withLoopTargets/
  withBreakTarget, currentBreakTarget/currentContinueTarget, labelBlock,
  addDataItem → snake_case versions in ir.ml (with_* take thunks:
  `with_var_scope (fun () -> ...)`).
- TypesIr: Operand → operand (OTemp/OImm/OImmBytes/OGlobal/OFunction),
  Instr → instr (same constructor names, Temp fields are ints),
  BinOp constructors → the irop_* integer codes from ir.ml
  (IAdd → irop_add, IULt → irop_ult, ...). `IBin t op a b` →
  `IBin (t, op_code, a, b)`. Terminator → terminator, BasicBlock,
  DataValue (DByte/DAddress), DataItem, FunctionIr as in ir.ml.
- TypesLower: LValue → lvalue (LLocal/LAddress), SwitchClause.
- TypesAst: see ast.ml (TopDecl ctors are prefixed D: DFunction, ...).
- Literal: see literal.ml (parseInt → parse_int on bytes, charValue →
  char_value, stringBytes → string_bytes returns int list incl. trailing 0,
  naturalLiteralBytes → natural_literal_bytes, intBytes size v →
  int_bytes size v, takeInts → take_ints, shiftLeftInt → shift_left_int,
  boolToInt → bool_to_int, evalConstBinOp op a b with op : bytes).
- Utilities: list_rev, list_append, list_length, list_iter, list_map,
  list_iteri (and list_iteri_from), list_filter, list_exists,
  list_for_all, list_fold_left, list_find, list_concat_map, iter_range,
  buf_new/buf_push/buf_add_bytes/buf_add_str/buf_add_int/buf_take,
  str_to_bytes, int_to_bytes, bytes_eq, bytes_eq_str, bytes_eq_any,
  assoc_bytes, opt_or, is_some, imax, imin, bytes_prefix_of (in ir.ml),
  show_quoted (in parser.ml).
- `mapM_`/`mapM` → list_iter/list_map (left-to-right: each head value is
  bound before the recursive call); `concatMap` → list_concat_map.
- `lookup k assoclist` on bytes keys → assoc_bytes (returns an option).
- `elem x list-of-strings` on operator strings → bytes_eq_any.

## Mutually recursive group layout

Lower.hs becomes ONE ML2 `let rec ... and ...` group spanning files:
- lower-a.ml — starts with `let rec ...`; everything after is `and ...`.
- lower-b.ml, lower-c.ml, lower-d.ml — contain ONLY `and ...`
  definitions continuing that same group (no plain `let` at top level).
Helper modules with no calls into Lower (LowerBuiltins, LowerDataValues,
LowerLiterals, LowerParams, LowerTypeInfo, LowerSwitchHelpers,
LowerImplicit, LowerBootstrap) live in lower-help.ml as ordinary
top-level lets/let recs BEFORE the group.
New private helpers you invent must be prefixed (la_, lb_, lc_, ld_) to
avoid collisions between segments. Functions from OTHER segments are
called by their mechanical snake_case names; do not redefine them.

## Evaluation-order rule (host-OCaml equivalence)

ML2 evaluates operator operands, application arguments, and constructor
arguments left-to-right; host OCaml evaluates them right-to-left. The two
agree only when at most ONE operand of any operator/application/constructor
performs side effects. Never combine two effectful calls in a single
expression — bind them with `let` in the intended order first:

    let a = effectful_one () in
    let b = effectful_two () in
    a + b

## Style

Match the existing parts: two-space indent, parenthesized multi-statement
branches, comments only where the reference is subtle. Keep one ML2
function per Haskell function; do not merge or inline functions, do not
"optimize" — the port must be reviewable side by side.
