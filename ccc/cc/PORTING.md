# ccc porting contract (Haskell → ML2)

ccc is HCC ported to ML2, the dialect compiled by ccc/stages/04-pattern-compiler.ml.
The parts in ccc/cc/*.ml are concatenated in lexical filename order; the result
must ALSO typecheck as host OCaml when prefixed with ccc/tests/prelude-ocaml.ml
(that is the dev loop). Read these foundation files before porting anything:
00-util.ml, 05-prim.ml, 10-lexer.ml, 12-symtab.ml, 18-literal.ml, 20-ast.ml,
22-constexpr.ml, 30-parser.ml (for show_quoted), 40-ir.ml.

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
- Haskell `div`/`mod` are FLOORING: use hdiv/hmod from 05-prim.ml, never the
  native `/`/`mod` (which truncate) unless both operands are provably >= 0.
- Bitwise/shift helpers come from 18-literal.ml (bit_and_int etc.), never
  native land/lor/lsl.

## ML2 dialect restrictions (the stage 04 compiler rejects violations)

- No exceptions; fatal errors via cc_throw/cc_throw_str (they exit).
- No local `let rec ... and ...` (mutual recursion is TOP-LEVEL only).
  Local single self-recursive `let rec f x = ... in` is fine.
- No records; use tuples + let-pattern destructuring `let (a, b) = ... in`.
- No `function`, no `when` guards, no `as` patterns, no or-patterns `p1|p2`,
  no `begin/end`, no `if ... then ... else` without else when a value is
  needed, no labels/optional args, no partial application of these builtins:
  write_byte, bytes_get/set, array_get/set/make, string_get, etc.
- `match` arms: nested patterns of constructors/tuples/lists/literals/_/vars
  only. Bind-and-test (`as`) must be rewritten.
- Strings are bytes. Literals "..." are immutable; build text with the buf_*
  API from 00-util.ml. Compare with bytes_eq / bytes_eq_str.
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
  functions that touch the cs_* refs from 40-ir.ml. `pure x` → `x`.
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
  addDataItem → snake_case versions in 40-ir.ml (with_* take thunks:
  `with_var_scope (fun () -> ...)`).
- TypesIr: Operand → operand (OTemp/OImm/OImmBytes/OGlobal/OFunction),
  Instr → instr (same constructor names, Temp fields are ints),
  BinOp constructors → the irop_* integer codes from 40-ir.ml
  (IAdd → irop_add, IULt → irop_ult, ...). `IBin t op a b` →
  `IBin (t, op_code, a, b)`. Terminator → terminator, BasicBlock,
  DataValue (DByte/DAddress), DataItem, FunctionIr as in 40-ir.ml.
- TypesLower: LValue → lvalue (LLocal/LAddress), SwitchClause.
- TypesAst: see 20-ast.ml (TopDecl ctors are prefixed D: DFunction, ...).
- Literal: see 18-literal.ml (parseInt → parse_int on bytes, charValue →
  char_value, stringBytes → string_bytes returns int list incl. trailing 0,
  naturalLiteralBytes → natural_literal_bytes, intBytes size v →
  int_bytes size v, takeInts → take_ints, shiftLeftInt → shift_left_int,
  boolToInt → bool_to_int, evalConstBinOp op a b with op : bytes).
- Utilities: list_rev, list_append, list_length, buf_new/buf_push/
  buf_add_bytes/buf_add_str/buf_add_int/buf_take, str_to_bytes,
  int_to_bytes, bytes_eq, bytes_eq_str, opt_or, is_some, imax, imin,
  bytes_prefix_of (in 40-ir.ml), show_quoted (in 30-parser.ml).
- `lookup k assoclist` → write a small local helper or explicit recursion.
- `elem x list-of-strings` on operator strings → chains of bytes_eq_str.

## Mutually recursive group layout

Lower.hs becomes ONE ML2 `let rec ... and ...` group spanning files:
- 50-lower-a.ml — starts with `let rec ...`; everything after is `and ...`.
- 52-lower-b.ml, 54-lower-c.ml, 56-lower-d.ml — contain ONLY `and ...`
  definitions continuing that same group (no plain `let` at top level).
Helper modules with no calls into Lower (LowerBuiltins, LowerDataValues,
LowerLiterals, LowerParams, LowerTypeInfo, LowerSwitchHelpers,
LowerImplicit, LowerBootstrap) live in 45-lower-help.ml as ordinary
top-level lets/let recs BEFORE the group.
New private helpers you invent must be prefixed (la_, lb_, lc_, ld_) to
avoid collisions between segments. Functions from OTHER segments are
called by their mechanical snake_case names; do not redefine them.

## Style

Match the existing parts: two-space indent, parenthesized multi-statement
branches, comments only where the reference is subtle. Keep one ML2
function per Haskell function; do not merge or inline functions, do not
"optimize" — the port must be reviewable side by side.
