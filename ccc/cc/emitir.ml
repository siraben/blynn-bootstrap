(* ccc part 60: textual HCCIR emission; port of Hcc.M1Ir (the emit half).
   The reference's `write` callback (one line per call) becomes appending
   to a byte buffer; every emit_* that corresponds to a write call ends
   the line with a newline byte. Field helpers (operand_ir_fields and
   friends) append text without a newline, like the Haskell functions
   that return strings. Binary operators already carry their HCCIR code
   (the irop_ constants), so the reference's binOpCode table disappears. *)

let temp_text out temp = buf_add_int out temp

let block_id_text out bid = buf_add_int out bid

let rec int_list_fields_rest out values =
  match values with
  | [] -> ()
  | value :: rest ->
      (buf_push out ch_space;
       buf_add_int out value;
       int_list_fields_rest out rest)

let int_list_fields out values =
  buf_add_int out (list_length values);
  int_list_fields_rest out values

let operand_ir_fields out op =
  match op with
  | OTemp temp -> (buf_push out ch_T; temp_text out temp)        (* T *)
  | OImm value -> (buf_push out ch_I; buf_add_int out value)     (* I *)
  | OImmBytes bs -> (buf_push out ch_B; int_list_fields out bs)  (* B *)
  | OGlobal name -> (buf_push out ch_G; buf_add_bytes out name)  (* G *)
  | OFunction name -> (buf_push out ch_F; buf_add_bytes out name) (* F *)

let rec operands_ir_fields_rest out ops =
  match ops with
  | [] -> ()
  | op :: rest ->
      (buf_push out ch_space;
       operand_ir_fields out op;
       operands_ir_fields_rest out rest)

let operands_ir_fields out ops =
  buf_add_int out (list_length ops);
  operands_ir_fields_rest out ops

let maybe_temp_text out maybe_temp =
  match maybe_temp with
  | None -> buf_push out ch_minus   (* - *)
  | Some temp -> temp_text out temp

let data_value_ir_line out value =
  match value with
  | DByte byte -> (buf_add_str out "b "; buf_add_int out byte)
  | DAddress label -> (buf_add_str out "a "; buf_add_bytes out label)

let rec zero_run values =
  match values with
  | DByte 0 :: rest ->
      let (count, tail_values) = zero_run rest in
      (count + 1, tail_values)
  | _ -> (0, values)

let rec emit_data_values_ir out values =
  match values with
  | [] -> ()
  | DByte 0 :: _ ->
      (let (count, rest) = zero_run values in
       buf_add_str out "z ";
       buf_add_int out count;
       buf_push out ch_nl;
       emit_data_values_ir out rest)
  | value :: rest ->
      (data_value_ir_line out value;
       buf_push out ch_nl;
       emit_data_values_ir out rest)

let emit_data_item_ir out item =
  match item with
  | DataItem (label, values) ->
      (buf_add_str out "D ";
       buf_add_bytes out label;
       buf_push out ch_nl;
       emit_data_values_ir out values;
       buf_push out ch_E;   (* E *)
       buf_push out ch_nl)

(* line content without the trailing newline, like the reference *)
let terminator_ir_line out term =
  match term with
  | TRet None -> buf_push out ch_R   (* R *)
  | TRet (Some op) ->
      (buf_add_str out "R ";
       operand_ir_fields out op)
  | TJump bid ->
      (buf_add_str out "J ";
       block_id_text out bid)
  | TBranch (op, yes, no) ->
      (buf_add_str out "B ";
       operand_ir_fields out op;
       buf_push out ch_space;
       block_id_text out yes;
       buf_push out ch_space;
       block_id_text out no)
  | TBranchCmp (op, a, b, yes, no) ->
      (buf_add_str out "C ";
       buf_add_int out op;
       buf_push out ch_space;
       operand_ir_fields out a;
       buf_push out ch_space;
       operand_ir_fields out b;
       buf_push out ch_space;
       block_id_text out yes;
       buf_push out ch_space;
       block_id_text out no)

let emit_temp_op out code temp op =
  buf_add_int out code;
  buf_push out ch_space;
  temp_text out temp;
  buf_push out ch_space;
  operand_ir_fields out op;
  buf_push out ch_nl

let emit_op_op out code a b =
  buf_add_int out code;
  buf_push out ch_space;
  operand_ir_fields out a;
  buf_push out ch_space;
  operand_ir_fields out b;
  buf_push out ch_nl

let emit_ext out code temp size op =
  buf_add_int out code;
  buf_push out ch_space;
  temp_text out temp;
  buf_push out ch_space;
  buf_add_int out size;
  buf_push out ch_space;
  operand_ir_fields out op;
  buf_push out ch_nl

let rec emit_instr_ir out instr =
  match instr with
  | IParam (temp, index) ->
      (buf_add_str out "1 ";
       temp_text out temp;
       buf_push out ch_space;
       buf_add_int out index;
       buf_push out ch_nl)
  | IAlloca (temp, size) ->
      (buf_add_str out "2 ";
       temp_text out temp;
       buf_push out ch_space;
       buf_add_int out size;
       buf_push out ch_nl)
  | IConst (temp, value) ->
      (buf_add_str out "3 ";
       temp_text out temp;
       buf_push out ch_space;
       buf_add_int out value;
       buf_push out ch_nl)
  | IConstBytes (temp, bs) ->
      (buf_add_str out "4 ";
       temp_text out temp;
       buf_add_str out " B";
       int_list_fields out bs;
       buf_push out ch_nl)
  | ICopy (temp, op) -> emit_temp_op out 5 temp op
  | IAddrOf (temp, source) ->
      (buf_add_str out "6 ";
       temp_text out temp;
       buf_push out ch_space;
       temp_text out source;
       buf_push out ch_nl)
  | ILoad64 (temp, op) -> emit_temp_op out 7 temp op
  | ILoad32 (temp, op) -> emit_temp_op out 8 temp op
  | ILoadS32 (temp, op) -> emit_temp_op out 9 temp op
  | ILoad16 (temp, op) -> emit_temp_op out 10 temp op
  | ILoadS16 (temp, op) -> emit_temp_op out 11 temp op
  | ILoad8 (temp, op) -> emit_temp_op out 12 temp op
  | ILoadS8 (temp, op) -> emit_temp_op out 13 temp op
  | IStore64 (addr, value) -> emit_op_op out 14 addr value
  | IStore32 (addr, value) -> emit_op_op out 15 addr value
  | IStore16 (addr, value) -> emit_op_op out 16 addr value
  | IStore8 (addr, value) -> emit_op_op out 17 addr value
  | ISExt (temp, size, op) -> emit_ext out 22 temp size op
  | IZExt (temp, size, op) -> emit_ext out 23 temp size op
  | ITrunc (temp, size, op) -> emit_ext out 24 temp size op
  | IBin (temp, op, left, right) ->
      (buf_add_str out "18 ";
       temp_text out temp;
       buf_push out ch_space;
       buf_add_int out op;
       buf_push out ch_space;
       operand_ir_fields out left;
       buf_push out ch_space;
       operand_ir_fields out right;
       buf_push out ch_nl)
  | ICall (result, name, args) ->
      (buf_add_str out "19 ";
       maybe_temp_text out result;
       buf_push out ch_space;
       buf_add_bytes out name;
       buf_push out ch_space;
       operands_ir_fields out args;
       buf_push out ch_nl)
  | ICallIndirect (result, callee, args) ->
      (buf_add_str out "20 ";
       maybe_temp_text out result;
       buf_push out ch_space;
       operand_ir_fields out callee;
       buf_push out ch_space;
       operands_ir_fields out args;
       buf_push out ch_nl)
  | ICond (temp, cond_instrs, cond_op, true_instrs, true_op,
           false_instrs, false_op) ->
      (buf_add_str out "21 ";
       temp_text out temp;
       buf_push out ch_nl;
       buf_push out ch_lbracket;   (* [ *)
       buf_push out ch_nl;
       emit_instrs_ir out cond_instrs;
       buf_push out ch_rbracket;   (* ] *)
       buf_push out ch_nl;
       buf_add_str out "O ";
       operand_ir_fields out cond_op;
       buf_push out ch_nl;
       buf_push out ch_lbracket;   (* [ *)
       buf_push out ch_nl;
       emit_instrs_ir out true_instrs;
       buf_push out ch_rbracket;   (* ] *)
       buf_push out ch_nl;
       buf_add_str out "O ";
       operand_ir_fields out true_op;
       buf_push out ch_nl;
       buf_push out ch_lbracket;   (* [ *)
       buf_push out ch_nl;
       emit_instrs_ir out false_instrs;
       buf_push out ch_rbracket;   (* ] *)
       buf_push out ch_nl;
       buf_add_str out "O ";
       operand_ir_fields out false_op;
       buf_push out ch_nl;
       buf_push out ch_Q;   (* Q *)
       buf_push out ch_nl)

and emit_instrs_ir out instrs =
  match instrs with
  | [] -> ()
  | instr :: rest ->
      (emit_instr_ir out instr;
       emit_instrs_ir out rest)

let emit_block_ir out block =
  match block with
  | BasicBlock (bid, instrs, term) ->
      (buf_add_str out "L ";
       block_id_text out bid;
       buf_push out ch_nl;
       emit_instrs_ir out instrs;
       terminator_ir_line out term;
       buf_push out ch_nl)

let rec emit_blocks_ir out blocks =
  match blocks with
  | [] -> ()
  | block :: rest ->
      (emit_block_ir out block;
       emit_blocks_ir out rest)

let emit_function_ir out fn =
  match fn with
  | FunctionIr (name, blocks) ->
      (buf_add_str out "F ";
       buf_add_bytes out name;
       buf_push out ch_nl;
       emit_blocks_ir out blocks;
       buf_push out ch_E;   (* E *)
       buf_push out ch_nl)

let emit_top_item_ir out item =
  match item with
  | TopData data_item -> emit_data_item_ir out data_item
  | TopFunction fn -> emit_function_ir out fn

let rec emit_top_items_ir out items =
  match items with
  | [] -> ()
  | item :: rest ->
      (emit_top_item_ir out item;
       emit_top_items_ir out rest)

let emit_module_ir out items = emit_top_items_ir out items

let emit_m1ir_module items =
  let out = buf_new 65536 in
  emit_module_ir out items;
  out

(* port of emitM1IrWithDataPrefixTarget, into a buffer *)
let emit_hccir prefix target decls =
  let items = build_m1ir_module prefix target decls in
  let out = buf_new 65536 in
  buf_add_str out "HCCIR 1";
  buf_push out ch_nl;
  emit_module_ir out items;
  out
