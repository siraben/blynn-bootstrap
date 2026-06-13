(* core-lambda: Lambda-0 -> binary MZBC image, written in Lambda-0.
   First self-hosting rung of the lambda ladder (ccc/docs/lambda-ladder.md).
   Compiles the Lambda-0 dialect -- unary functions, ints, lists/pairs,
   closures and nothing else -- straight to a runnable .mzbc file (no
   assembler stage), and compiles itself to a fixpoint on the seed
   interpreter.

   Usage: mlc-interp core-lambda.ml in.ml out.mzbc
          mzvm core-lambda.mzbc in.ml out.mzbc

   Lambda-0 (v2) is the SYMBOLIC core: the one compound datum is the
   heap cell (Blynn's uniform cell heap, lambda-ladder.md).  Lists and
   pairs come as builtins -- cons/nil/null/hd/tl and pair/fst/snd -- and
   compile to the same tag-0 blocks the rest of the chain uses (a cons
   cell or pair is MAKEBLOCK 0 2, nil is the integer 0, projections are
   GETFIELD), so symbolic Lambda-0 data and ML0 data are one
   representation.  The byte-buffer builtins of the former Lambda-0,
   the bytes_* family, are gone and explicitly rejected.

   Grammar decisions taken where lambda-ladder.md leaves room (each is a
   strict OCaml subset and runs unchanged on the seed interpreter):
     - `()` is an atom (the unit value, compiled as the integer 0); it is
       needed for `arg_count ()` and accepted anywhere an atom fits.
     - `true`/`false` are atoms (integers 1/0), and so is `nil` (0).
     - `if c then e` without `else` is accepted (the missing branch is
       unit), since Lambda-0 needs conditional side effects.
     - integer literals are decimal only: no hex, no char literals, no
       unary minus (write `0 - 1`).
     - string literals appear only as the immediate argument of a call
       whose head is the identifier `err_str`; they compile to data-
       section globals.  `err_str` itself is an ordinary top-level
       function (defined below via the `string_length`/`string_get`
       builtins, exactly as ml0-compiler reads strings) because neither
       the seed interpreter nor the host-OCaml prelude predefines it.
     - top level accepts `let name = e`, `let rec name x = e` and
       `let () = e`; parameters beyond the single recursive one are
       rejected (multi-argument functions are nested `fun`).
     - `_` is rejected as a binder (`let _ = e in` is not Lambda-0;
       sequence with `;`).
     - reserved words of fuller MLs (and, match, with, land, ...) are
       rejected so non-Lambda-0 sources fail loudly, and any use of a
       `bytes_*` name is rejected with a pointer at lists.

   Compilation model: purely functional, two passes, no mutation and no
   AST.  The source is an int list of bytes; tokens carry their text as
   int lists; every compile-time structure (global table, data section,
   scope levels with their capture lists) is built from pairs and lists
   and threaded through one state value.  Pass 1 (m = 0) parses the
   whole program computing only sizes -- every instruction's width is
   known from the syntax alone -- which fixes the code length, the
   global count and the data section for the header.  Pass 2 (m = 1)
   parses again and writes code words straight to the output; a forward
   branch target is computed by running the size pass over the
   subexpression about to be emitted (the token stream is an immutable
   list, so "rescan from here" is just reusing a value).  The ZINC code
   shapes are byte-for-byte those of ml0-compiler + parenthetical, so
   the diverse-double-compilation anchor can compare images directly. *)

(* ---- tiny helpers ---- *)

let bnot = fun b -> if b then false else true

let rec rev_onto l = fun acc ->
  if null l then acc else rev_onto (tl l) (cons (hd l) acc)

let rev_list = fun l -> rev_onto l nil

let rec cat a = fun b ->
  if null a then b else cons (hd a) (cat (tl a) b)

let rec list_eq a = fun b ->
  if null a then null b
  else if null b then false
  else if hd a = hd b then list_eq (tl a) (tl b)
  else false

let rec len_from l = fun n ->
  if null l then n else len_from (tl l) (n + 1)

let list_len = fun l -> len_from l 0

let rec starts_with p = fun l ->
  if null p then true
  else if null l then false
  else if hd p = hd l then starts_with (tl p) (tl l)
  else false

(* ---- diagnostics ---- *)

let rec err_str_from s = fun i ->
  if i < string_length s then
    (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str = fun s -> err_str_from s 0

let rec err_name l =
  if null l then () else (write_byte 2 (hd l); err_name (tl l))

let rec err_int_rec n =
  (if n > 9 then err_int_rec (n / 10));
  write_byte 2 (48 + n mod 10)

let err_int = fun n ->
  if n < 0 then (write_byte 2 45; err_int_rec (0 - n)) else err_int_rec n

(* finish a diagnostic: caller has already err_str'd the message *)
let die_line = fun line ->
  err_str " at line ";
  err_int line;
  write_byte 2 10;
  exit 1

(* ---- names, spelled from character codes ---- *)

let ch_a = 97
let ch_b = 98
let ch_c = 99
let ch_d = 100
let ch_e = 101
let ch_f = 102
let ch_g = 103
let ch_h = 104
let ch_i = 105
let ch_l = 108
let ch_m = 109
let ch_n = 110
let ch_o = 111
let ch_p = 112
let ch_r = 114
let ch_s = 115
let ch_t = 116
let ch_u = 117
let ch_w = 119
let ch_x = 120
let ch_y = 121
let ch_us = 95                      (* underscore *)

let l1 = fun a -> cons a nil
let l2 = fun a -> fun b -> cons a (l1 b)
let l3 = fun a -> fun b -> fun c -> cons a (l2 b c)
let l4 = fun a -> fun b -> fun c -> fun d -> cons a (l3 b c d)
let l5 = fun a -> fun b -> fun c -> fun d -> fun e -> cons a (l4 b c d e)
let l6 = fun a -> fun b -> fun c -> fun d -> fun e -> fun f -> cons a (l5 b c d e f)

(* the Lambda-0 keywords *)
let n_let = l3 ch_l ch_e ch_t
let n_rec = l3 ch_r ch_e ch_c
let n_in = l2 ch_i ch_n
let n_if = l2 ch_i ch_f
let n_then = l4 ch_t ch_h ch_e ch_n
let n_else = l4 ch_e ch_l ch_s ch_e
let n_fun = l3 ch_f ch_u ch_n
let n_true = l4 ch_t ch_r ch_u ch_e
let n_false = l5 ch_f ch_a ch_l ch_s ch_e
let n_mod = l3 ch_m ch_o ch_d

(* reserved words of fuller MLs, rejected so non-Lambda-0 fails loudly *)
let n_and = l3 ch_a ch_n ch_d
let n_as = l2 ch_a ch_s
let n_asr = l3 ch_a ch_s ch_r
let n_begin = l5 ch_b ch_e ch_g ch_i ch_n
let n_do = l2 ch_d ch_o
let n_done = l4 ch_d ch_o ch_n ch_e
let n_downto = l6 ch_d ch_o ch_w ch_n ch_t ch_o
let n_end = l3 ch_e ch_n ch_d
let n_for = l3 ch_f ch_o ch_r
let n_land = l4 ch_l ch_a ch_n ch_d
let n_lor = l3 ch_l ch_o ch_r
let n_lsl = l3 ch_l ch_s ch_l
let n_lsr = l3 ch_l ch_s ch_r
let n_lxor = l4 ch_l ch_x ch_o ch_r
let n_match = l5 ch_m ch_a ch_t ch_c ch_h
let n_module = l6 ch_m ch_o ch_d ch_u ch_l ch_e
let n_of = l2 ch_o ch_f
let n_open = l4 ch_o ch_p ch_e ch_n
let n_ref = l3 ch_r ch_e ch_f
let n_to = l2 ch_t ch_o
let n_try = l3 ch_t ch_r ch_y
let n_type = l4 ch_t ch_y ch_p ch_e
let n_when = l4 ch_w ch_h ch_e ch_n
let n_while = l5 ch_w ch_h ch_i ch_l ch_e
let n_with = l4 ch_w ch_i ch_t ch_h

(* atoms and builtins *)
let n_us = l1 ch_us
let n_nil = l3 ch_n ch_i ch_l
let n_cons = l4 ch_c ch_o ch_n ch_s
let n_null = l4 ch_n ch_u ch_l ch_l
let n_hd = l2 ch_h ch_d
let n_tl = l2 ch_t ch_l
let n_pair = l4 ch_p ch_a ch_i ch_r
let n_fst = l3 ch_f ch_s ch_t
let n_snd = l3 ch_s ch_n ch_d
let n_exit = l4 ch_e ch_x ch_i ch_t
let n_open_in = cat n_open (l3 ch_us ch_i ch_n)
let n_open_out = cat n_open (l4 ch_us ch_o ch_u ch_t)
let n_close_chan = cat (l5 ch_c ch_l ch_o ch_s ch_e) (l5 ch_us ch_c ch_h ch_a ch_n)
let n_byte = l4 ch_b ch_y ch_t ch_e
let n_read_byte = cat (l4 ch_r ch_e ch_a ch_d) (cons ch_us n_byte)
let n_write_byte = cat (l5 ch_w ch_r ch_i ch_t ch_e) (cons ch_us n_byte)
let n_arg = l3 ch_a ch_r ch_g
let n_arg_count = cat n_arg (l6 ch_us ch_c ch_o ch_u ch_n ch_t)
let n_arg_get = cat n_arg (l4 ch_us ch_g ch_e ch_t)
let n_string = l6 ch_s ch_t ch_r ch_i ch_n ch_g
let n_string_length = cat n_string (cons ch_us (l6 ch_l ch_e ch_n ch_g ch_t ch_h))
let n_string_get = cat n_string (l4 ch_us ch_g ch_e ch_t)
let n_err_str = cat (l3 ch_e ch_r ch_r) (l4 ch_us ch_s ch_t ch_r)
let n_bytes_prefix = cons ch_b (l5 ch_y ch_t ch_e ch_s ch_us)

(* keyword test, dispatched on the first character *)
let is_kw = fun t ->
  if null t then false
  else
    (let c = hd t in
     if c = ch_a then list_eq t n_and || list_eq t n_as || list_eq t n_asr
     else if c = ch_b then list_eq t n_begin
     else if c = ch_d then
       list_eq t n_do || list_eq t n_done || list_eq t n_downto
     else if c = ch_e then list_eq t n_else || list_eq t n_end
     else if c = ch_f then
       list_eq t n_fun || list_eq t n_false || list_eq t n_for
     else if c = ch_i then list_eq t n_if || list_eq t n_in
     else if c = ch_l then
       list_eq t n_let || list_eq t n_land || list_eq t n_lor
       || list_eq t n_lxor || list_eq t n_lsl || list_eq t n_lsr
     else if c = ch_m then
       list_eq t n_mod || list_eq t n_match || list_eq t n_module
     else if c = ch_o then list_eq t n_of || list_eq t n_open
     else if c = ch_r then list_eq t n_rec || list_eq t n_ref
     else if c = ch_t then
       list_eq t n_then || list_eq t n_true || list_eq t n_try
       || list_eq t n_type || list_eq t n_to
     else if c = ch_w then
       list_eq t n_with || list_eq t n_while || list_eq t n_when
     else false)

(* ---- scanner ----
   The source is an int list; scanning is pure: scan_token takes the
   remaining characters and the current line and returns a token state
   pair ((kind/value, text), (rest, line)).  Kinds: 0 eof, 1 int,
   2 string, 3 ident, 4 punct (value = char code, or c + 256*d for the
   two-character operators). *)

let is_digit = fun c -> c >= 48 && c <= 57
let is_istart = fun c -> (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c = 95
let is_ichar = fun c -> is_istart c || is_digit c || c = 39

let rec skip_comment cs = fun line -> fun depth ->
  if null cs then (err_str "core-lambda: unterminated comment"; die_line line)
  else
    (let c = hd cs in
     let r = tl cs in
     if c = 10 then skip_comment r (line + 1) depth
     else if c = 40 && bnot (null r) && hd r = 42 then
       skip_comment (tl r) line (depth + 1)
     else if c = 42 && bnot (null r) && hd r = 41 then
       (if depth = 1 then pair (tl r) line
        else skip_comment (tl r) line (depth - 1))
     else skip_comment r line depth)

let rec skip_ws cs = fun line ->
  if null cs then pair cs line
  else
    (let c = hd cs in
     if c = 32 || c = 9 || c = 13 then skip_ws (tl cs) line
     else if c = 10 then skip_ws (tl cs) (line + 1)
     else if c = 40 && bnot (null (tl cs)) && hd (tl cs) = 42 then
       (let r = skip_comment (tl (tl cs)) line 1 in
        skip_ws (fst r) (snd r))
     else pair cs line)

let rec scan_number cs = fun acc ->
  if bnot (null cs) && is_digit (hd cs) then
    scan_number (tl cs) (acc * 10 + (hd cs - 48))
  else pair acc cs

let rec scan_ident cs = fun acc ->
  if bnot (null cs) && is_ichar (hd cs) then
    scan_ident (tl cs) (cons (hd cs) acc)
  else pair (rev_list acc) cs

let read_escape = fun e -> fun line ->
  if e = 110 then 10
  else if e = 116 then 9
  else if e = 114 then 13
  else if e = 92 then 92
  else if e = 34 then 34
  else if e = 39 then 39
  else (err_str "core-lambda: bad escape"; die_line line)

(* body of a string literal; the opening quote is consumed *)
let rec scan_string cs = fun line -> fun acc ->
  if null cs then (err_str "core-lambda: unterminated string"; die_line line)
  else
    (let d = hd cs in
     if d = 34 then pair (rev_list acc) (pair (tl cs) line)
     else if d = 92 then
       (let r = tl cs in
        let e = read_escape (if null r then 0 - 1 else hd r) line in
        scan_string (tl r) line (cons e acc))
     else if d = 10 then scan_string (tl cs) (line + 1) (cons d acc)
     else scan_string (tl cs) line (cons d acc))

(* two-character punctuation, packed c + 256*d; 0 = not a pair *)
let pair2 = fun c -> fun d ->
  if c = 45 && d = 62 then 15917          (* -> *)
  else if c = 60 && d = 62 then 15932     (* <> *)
  else if c = 60 && d = 61 then 15676     (* <= *)
  else if c = 62 && d = 61 then 15678     (* >= *)
  else if c = 38 && d = 38 then 9766      (* && *)
  else if c = 124 && d = 124 then 31868   (* || *)
  else 0

let mk_ts = fun kind -> fun v -> fun text -> fun cs -> fun line ->
  pair (pair (pair kind v) text) (pair cs line)

(* the (text, (rest, line)) result of scan_string *)
let sr_text = fun r -> fst r
let sr_chars = fun r -> fst (snd r)
let sr_line = fun r -> snd (snd r)

let scan_token = fun cs0 -> fun line0 ->
  let w = skip_ws cs0 line0 in
  let cs = fst w in
  let line = snd w in
  if null cs then mk_ts 0 0 nil cs line
  else
    (let c = hd cs in
     if is_digit c then
       (let r = scan_number cs 0 in
        (if bnot (null (snd r)) && is_ichar (hd (snd r)) then
           (err_str "core-lambda: bad number"; die_line line));
        mk_ts 1 (fst r) nil (snd r) line)
     else if is_istart c then
       (let r = scan_ident cs nil in
        mk_ts 3 0 (fst r) (snd r) line)
     else if c = 34 then
       (let r = scan_string (tl cs) line nil in
        mk_ts 2 0 (sr_text r) (sr_chars r) (sr_line r))
     else
       (let rest = tl cs in
        let two = if null rest then 0 else pair2 c (hd rest) in
        if two > 0 then mk_ts 4 two nil (tl rest) line
        else mk_ts 4 c nil rest line))

(* ---- the compile state ----
   One value threads through the whole compiler:
     s = (ts, (regs, (globs, (dats, levels))))
   ts     = ((kind/value, text), (rest-of-source, line)) -- current token
   regs   = (addr, (depth, (exited, outh))) -- code address in words,
            stack depth, 1 after RETURN/APPTERM in tail position, and
            the output channel (used only when emitting)
   globs  = (count, [(name, defined-flag)]) -- newest first
   dats   = (count, [string]) -- data-section records, newest first
   levels = [(binds, caps)] -- innermost function scope first; binds are
            (name, stack slot) newest first, caps are captured names in
            discovery order.  The bottom of the list is the top level:
            names not found anywhere become forward globals. *)

(* each layer gets named accessors so no use site spells a fst/snd chain *)
let tok_kind = fun tok -> fst (fst tok)
let tok_val = fun tok -> snd (fst tok)
let tok_text = fun tok -> snd tok

let s_ts = fun s -> fst s
let s_tok = fun s -> fst (s_ts s)
let s_rem = fun s -> snd (s_ts s)
let s_kind = fun s -> tok_kind (s_tok s)
let s_ival = fun s -> tok_val (s_tok s)
let s_text = fun s -> tok_text (s_tok s)
let s_chars = fun s -> fst (s_rem s)
let s_line = fun s -> snd (s_rem s)

let s_regs = fun s -> fst (snd s)
let s_addr = fun s -> fst (s_regs s)
let s_depth = fun s -> fst (snd (s_regs s))
let s_exited = fun s -> fst (snd (snd (s_regs s)))
let s_outh = fun s -> snd (snd (snd (s_regs s)))

let s_tables = fun s -> snd (snd s)
let s_globs = fun s -> fst (s_tables s)
let s_dats = fun s -> fst (snd (s_tables s))
let s_levels = fun s -> snd (snd (s_tables s))

let mk_regs = fun a -> fun d -> fun e -> fun outh ->
  pair a (pair d (pair e outh))

let set_ts = fun ts -> fun s -> pair ts (snd s)
let set_regs = fun r -> fun s -> pair (s_ts s) (pair r (s_tables s))
let set_addr = fun a -> fun s ->
  set_regs (mk_regs a (s_depth s) (s_exited s) (s_outh s)) s
let set_depth = fun d -> fun s ->
  set_regs (mk_regs (s_addr s) d (s_exited s) (s_outh s)) s
let set_exited = fun e -> fun s ->
  set_regs (mk_regs (s_addr s) (s_depth s) e (s_outh s)) s
let set_globs = fun g -> fun s ->
  pair (s_ts s) (pair (s_regs s) (pair g (pair (s_dats s) (s_levels s))))
let set_dats = fun d -> fun s ->
  pair (s_ts s) (pair (s_regs s) (pair (s_globs s) (pair d (s_levels s))))
let set_levels = fun l -> fun s ->
  pair (s_ts s) (pair (s_regs s) (pair (s_globs s) (pair (s_dats s) l)))

(* the remaining structures: globals, data records, scope levels *)
let g_count = fun globs -> fst globs
let g_list = fun globs -> snd globs
let gn_name = fun ent -> fst ent
let gn_flag = fun ent -> snd ent

let d_count = fun dats -> fst dats
let d_list = fun dats -> snd dats

let lev_binds = fun lev -> fst lev
let lev_caps = fun lev -> snd lev
let bind_name = fun b -> fst b
let bind_slot = fun b -> snd b

let bump = fun n -> fun s -> set_depth (s_depth s + n) s

let next_token = fun s -> set_ts (scan_token (s_chars s) (s_line s)) s

(* ---- token predicates ---- *)

let t_punct = fun s -> fun p -> s_kind s = 4 && s_ival s = p

let kw_at = fun s -> fun n -> s_kind s = 3 && list_eq (s_text s) n

let at_ident = fun s -> s_kind s = 3 && bnot (is_kw (s_text s))

let is_atom_start = fun s ->
  let k = s_kind s in
  if k = 1 || k = 2 then true
  else if k = 3 then
    (if kw_at s n_true || kw_at s n_false then true
     else bnot (is_kw (s_text s)))
  else t_punct s 40

(* does the current token continue the enclosing expression as an infix
   operator or sequence separator? used to veto tail calls *)
let op_follows = fun s ->
  if s_kind s = 4 then
    (let p = s_ival s in
     p = 43 || p = 45 || p = 42 || p = 47          (* + - * / *)
     || p = 61 || p = 15932 || p = 60 || p = 15676 (* = <> < <= *)
     || p = 62 || p = 15678                        (* > >= *)
     || p = 9766 || p = 31868 || p = 59)           (* && || ; *)
  else kw_at s n_mod

(* write a (possibly two-char) punctuation spelling to stderr *)
let wp2 = fun c ->
  write_byte 2 (c mod 256);
  if c > 255 then write_byte 2 (c / 256)

let expect_p = fun c -> fun s ->
  if t_punct s c then next_token s
  else (err_str "core-lambda: expected "; wp2 c; die_line (s_line s))

(* require an identifier; returns (name, state-after) *)
let need_ident = fun s ->
  if at_ident s then
    ((if list_eq (s_text s) n_us then
        (err_str "core-lambda: _ is not a Lambda-0 binder; sequence with ; instead";
         die_line (s_line s)));
     pair (s_text s) (next_token s))
  else (err_str "core-lambda: expected an identifier"; die_line (s_line s))

(* ---- tail lookahead ----
   Decides whether a parenthesized expression in tail position can be
   compiled as a tail expression: scan to the matching close paren and
   require that no operator or atom follows.  The token stream is a
   value, so the lookahead just walks ahead and drops its state. *)

let ptc = fun s ->
  let s1 = next_token s in
  if t_punct s1 41 then 0
  else
    (let rec scan st = fun depth ->
       if s_kind st = 0 then 0
       else if t_punct st 40 then scan (next_token st) (depth + 1)
       else if t_punct st 41 then
         (if depth = 1 then
            (let st2 = next_token st in
             if op_follows st2 || is_atom_start st2 then 0 else 1)
          else scan (next_token st) (depth - 1))
       else scan (next_token st) depth in
     scan s1 1)

(* ---- code emission ----
   m = 0: size pass, nothing is written, only the address advances.
   m = 1: emit pass, each word goes out as 4 little-endian bytes. *)

let op_stop = 0
let op_const = 1
let op_acc = 2
let op_push = 3
let op_pop = 4
let op_assign = 5
let op_envacc = 6
let op_closure = 7
let op_apply = 8
let op_appterm = 9
let op_return = 10
let op_makeblock = 11
let op_getfield = 12
let op_setfield = 13
let op_branch = 14
let op_branchif = 15
let op_branchifnot = 16
let op_boolnot = 30
let op_getbytes = 43
let op_getglobal = 45
let op_setglobal = 46
let op_ccall = 47

let ew = fun m -> fun v -> fun s ->
  (if m = 1 then
     (write_byte (s_outh s) v;
      write_byte (s_outh s) (v / 256);
      write_byte (s_outh s) (v / 65536);
      write_byte (s_outh s) (v / 16777216)));
  set_addr (s_addr s + 1) s

let em1 = fun m -> fun op -> fun a -> fun s -> ew m a (ew m op s)
let em2 = fun m -> fun op -> fun a -> fun b -> fun s ->
  ew m b (ew m a (ew m op s))

let gbase = 4096                    (* first non-data global *)

(* current string token -> data record + GETGLOBAL of its slot *)
let emit_strlit = fun m -> fun s ->
  let d = s_dats s in
  let i = d_count d in
  (if i >= gbase then
     (err_str "core-lambda: too many string literals"; die_line (s_line s)));
  em1 m op_getglobal i
    (set_dats (pair (i + 1) (cons (s_text s) (d_list d))) s)

(* ---- global table: (count, [(name, defined-flag)]) newest first ---- *)

let rec g_find_from q = fun lst -> fun i ->
  if null lst then 0 - 1
  else if list_eq (gn_name (hd lst)) q then i
  else g_find_from q (tl lst) (i - 1)

(* newest first so later definitions shadow earlier ones *)
let g_find = fun q -> fun globs ->
  g_find_from q (g_list globs) (g_count globs - 1)

(* add a global; returns (index, globs') *)
let g_add = fun q -> fun flag -> fun globs ->
  pair (g_count globs)
    (pair (g_count globs + 1) (cons (pair q flag) (g_list globs)))

let rec g_flag_from lst = fun k ->
  if k = 0 then gn_flag (hd lst) else g_flag_from (tl lst) (k - 1)

let g_defined = fun i -> fun globs ->
  g_flag_from (g_list globs) (g_count globs - 1 - i)

let rec g_set_from lst = fun k ->
  if k = 0 then cons (pair (gn_name (hd lst)) 1) (tl lst)
  else cons (hd lst) (g_set_from (tl lst) (k - 1))

let g_set_defined = fun i -> fun globs ->
  pair (g_count globs) (g_set_from (g_list globs) (g_count globs - 1 - i))

(* define name; returns (index, globs') *)
let mark_defined = fun q -> fun globs ->
  let g = g_find q globs in
  if g >= 0 then
    (if g_defined g globs = 1 then
       (* already defined: shadow with a fresh global *)
       g_add q 1 globs
     else pair g (g_set_defined g globs))
  else g_add q 1 globs

let check_all_defined = fun globs -> fun line ->
  let rec go lst =
    if null lst then ()
    else
      ((if gn_flag (hd lst) = 0 then
          (err_str "core-lambda: undefined name ";
           err_name (gn_name (hd lst));
           die_line line));
       go (tl lst)) in
  go (rev_list (g_list globs))

(* ---- builtins ----
   Descriptor: ckind * 256 + arity * 16 + index, kinds:
     0 = C primitive (all args pushed, CCALL)
     1 = opcode (last arg stays in acc; index selects the opcode)
     2 = arg_count (unit argument compiled but not passed)
     3 = block maker (all args pushed, MAKEBLOCK 0 arity)
   Opcode selectors (kind 1) follow ml0-compiler's numbering:
     1 getbytes, 6 boolnot, 7 getfield 0, 8 getfield 1. *)

let mk_bi = fun kind -> fun ar -> fun idx -> kind * 256 + ar * 16 + idx

let bi_desc = fun q ->
  if null q then 0 - 1
  else
    (let c = hd q in
     if c = ch_a then
       (if list_eq q n_arg_count then mk_bi 2 1 8
        else if list_eq q n_arg_get then mk_bi 0 1 9
        else 0 - 1)
     else if c = ch_c then
       (if list_eq q n_cons then mk_bi 3 2 0
        else if list_eq q n_close_chan then mk_bi 0 1 3
        else 0 - 1)
     else if c = ch_e then
       (if list_eq q n_exit then mk_bi 0 1 0 else 0 - 1)
     else if c = ch_f then
       (if list_eq q n_fst then mk_bi 1 1 7 else 0 - 1)
     else if c = ch_h then
       (if list_eq q n_hd then mk_bi 1 1 7 else 0 - 1)
     else if c = ch_n then
       (if list_eq q n_null then mk_bi 1 1 6 else 0 - 1)
     else if c = ch_o then
       (if list_eq q n_open_in then mk_bi 0 1 1
        else if list_eq q n_open_out then mk_bi 0 1 2
        else 0 - 1)
     else if c = ch_p then
       (if list_eq q n_pair then mk_bi 3 2 0 else 0 - 1)
     else if c = ch_r then
       (if list_eq q n_read_byte then mk_bi 0 1 4 else 0 - 1)
     else if c = ch_s then
       (if list_eq q n_snd then mk_bi 1 1 8
        else if list_eq q n_string_length then mk_bi 0 1 7
        else if list_eq q n_string_get then mk_bi 1 2 1
        else 0 - 1)
     else if c = ch_t then
       (if list_eq q n_tl then mk_bi 1 1 8 else 0 - 1)
     else if c = ch_w then
       (if list_eq q n_write_byte then mk_bi 0 2 5 else 0 - 1)
     else 0 - 1)

(* ---- name resolution ----
   A resolution is kind * 2^20 + index; kinds: 0 stack slot, 1 capture
   index, 2 global (absolute), 3 builtin descriptor.  Resolving may
   extend capture lists (a free name threads through every enclosing
   function boundary) and the global table (an unknown name becomes a
   forward global), so it returns the updated levels and globals. *)

let mk_res = fun k -> fun i -> k * 1048576 + i

let rec assoc_slot q = fun binds ->
  if null binds then 0 - 1
  else if list_eq q (bind_name (hd binds)) then bind_slot (hd binds)
  else assoc_slot q (tl binds)

let rec cap_index q = fun caps -> fun i ->
  if null caps then 0 - 1
  else if list_eq q (hd caps) then i
  else cap_index q (tl caps) (i + 1)

(* the (res, (levels, globs)) result of resolve_in *)
let ri_res = fun r -> fst r
let ri_levels = fun r -> fst (snd r)
let ri_globs = fun r -> snd (snd r)

let rec resolve_in q = fun levels -> fun globs -> fun line ->
  if null levels then
    (* the top level: globals, then builtins, then a forward global *)
    (let g = g_find q globs in
     if g >= 0 then pair (mk_res 2 (gbase + g)) (pair levels globs)
     else
       (let d = bi_desc q in
        if d >= 0 then pair (mk_res 3 d) (pair levels globs)
        else if starts_with n_bytes_prefix q then
          (err_str "core-lambda: bytes_* is not Lambda-0; use lists";
           die_line line)
        else
          (let a = g_add q 0 globs in
           pair (mk_res 2 (gbase + fst a)) (pair levels (snd a)))))
  else
    (let lev = hd levels in
     let slot = assoc_slot q (lev_binds lev) in
     if slot >= 0 then pair (mk_res 0 slot) (pair levels globs)
     else
       (let cj = cap_index q (lev_caps lev) 0 in
        if cj >= 0 then pair (mk_res 1 cj) (pair levels globs)
        else
          (let rr = resolve_in q (tl levels) globs line in
           let r = ri_res rr in
           let outer = ri_levels rr in
           let globs2 = ri_globs rr in
           if r / 1048576 >= 2 then pair r (pair (cons lev outer) globs2)
           else
             (* an outer local: capture it at this boundary *)
             (let nj = list_len (lev_caps lev) in
              pair (mk_res 1 nj)
                (pair
                   (cons (pair (lev_binds lev) (cat (lev_caps lev) (l1 q)))
                      outer)
                   globs2)))))

(* resolve in the current state; returns (res, state') *)
let resolve = fun q -> fun s ->
  let rr = resolve_in q (s_levels s) (s_globs s) (s_line s) in
  pair (ri_res rr) (set_globs (ri_globs rr) (set_levels (ri_levels rr) s))

let load_res = fun m -> fun r -> fun s ->
  let k = r / 1048576 in
  let i = r mod 1048576 in
  if k = 0 then em1 m op_acc (s_depth s - 1 - i) s
  else if k = 1 then em1 m op_envacc (i + 1) s
  else if k = 2 then em1 m op_getglobal i s
  else (err_str "core-lambda: builtin used as a value"; die_line (s_line s))

(* bind a name to a stack slot in the current level *)
let add_bind = fun q -> fun slot -> fun s ->
  let lev = hd (s_levels s) in
  set_levels
    (cons (pair (cons (pair q slot) (lev_binds lev)) (lev_caps lev))
       (tl (s_levels s)))
    s

(* drop the newest binding of the current level (scope exit) *)
let strip_bind = fun s ->
  let lev = hd (s_levels s) in
  set_levels
    (cons (pair (tl (lev_binds lev)) (lev_caps lev)) (tl (s_levels s))) s

(* a plain value sits in acc; in tail position emit its RETURN unless an
   appterm already exited or a sequence semicolon follows *)
let value_done = fun m -> fun t -> fun s ->
  if t = 1 && s_exited s = 0 then
    (if t_punct s 59 then s
     else set_exited 1 (em1 m op_return (s_depth s) s))
  else s

(* ---- parser / code generator ----
   One mutually recursive family; Lambda-0 has no `and`, so each helper
   takes the single recursive entry point `re` as its first argument:
   `re m 0 t s` compiles a full expression (sequences included),
   `re m 1 t s` one sequence element.  In the emit pass (m = 1) a
   forward branch target is found by running the size pass (m = 0) over
   the subexpression about to be emitted; the size pass never needs
   targets, so it stays linear. *)

let c_atom = fun re -> fun m -> fun strok -> fun s ->
  let k = s_kind s in
  if k = 1 then next_token (em1 m op_const (s_ival s) s)
  else if k = 2 then
    (if strok = 1 then next_token (emit_strlit m s)
     else (err_str "core-lambda: string literal outside err_str"; die_line (s_line s)))
  else if k = 3 then
    (if kw_at s n_true then next_token (em1 m op_const 1 s)
     else if kw_at s n_false then next_token (em1 m op_const 0 s)
     else if kw_at s n_nil then next_token (em1 m op_const 0 s)
     else if is_kw (s_text s) then
       (err_str "core-lambda: unexpected keyword"; die_line (s_line s))
     else
       (let q = s_text s in
        let s1 = next_token s in
        let rr = resolve q s1 in
        load_res m (fst rr) (snd rr)))
  else if t_punct s 40 then
    (let s1 = next_token s in
     if t_punct s1 41 then next_token (em1 m op_const 0 s1)
     else expect_p 41 (re m 0 0 s1))
  else (err_str "core-lambda: unexpected token"; die_line (s_line s))

let c_builtin = fun re -> fun m -> fun d -> fun s ->
  let kind = d / 256 in
  let ar = d / 16 mod 16 in
  let idx = d mod 16 in
  let rec args j = fun st ->
    if j < ar then
      ((if bnot (is_atom_start st) then
          (err_str "core-lambda: builtin applied to too few arguments";
           die_line (s_line st)));
       let st1 = c_atom re m 0 st in
       let st2 =
         if kind = 0 || kind = 3 || j < ar - 1 then
           bump 1 (ew m op_push st1)
         else st1 in
       args (j + 1) st2)
    else st in
  let s1 = args 0 s in
  if kind = 0 then bump (0 - ar) (em2 m op_ccall ar idx s1)
  else if kind = 2 then em2 m op_ccall 0 idx s1
  else if kind = 3 then bump (0 - ar) (em2 m op_makeblock 0 ar s1)
  else
    (let s2 =
       if idx = 1 then ew m op_getbytes s1
       else if idx = 6 then ew m op_boolnot s1
       else if idx = 7 then em1 m op_getfield 0 s1
       else em1 m op_getfield 1 s1 in
     bump (0 - (ar - 1)) s2)

let c_app = fun re -> fun m -> fun t -> fun s ->
  if t = 1 && t_punct s 40 && ptc s = 1 then
    (* tail expression through parentheses: (effects; call args) *)
    expect_p 41 (re m 0 1 (next_token s))
  else
    (let rec app_args strok = fun st ->
       if is_atom_start st then
         (let sa = bump 1 (ew m op_push st) in        (* push the callee *)
          let sb = c_atom re m strok sa in
          let sc = bump 1 (ew m op_push sb) in        (* push the argument *)
          if is_atom_start sc then
            app_args 0
              (bump (0 - 2)
                 (em1 m op_pop 1 (em1 m op_apply 1 (em1 m op_acc 1 sc))))
          else if t = 1 && bnot (op_follows sc) then
            set_exited 1
              (bump (0 - 2)
                 (em2 m op_appterm 1 (s_depth sc - 1) (em1 m op_acc 1 sc)))
          else
            bump (0 - 2)
              (em1 m op_pop 1 (em1 m op_apply 1 (em1 m op_acc 1 sc))))
       else st in
     if at_ident s && bnot (kw_at s n_true) && bnot (kw_at s n_false)
        && bnot (kw_at s n_nil) then
       (let q = s_text s in
        let es = if list_eq q n_err_str then 1 else 0 in
        let s1 = next_token s in
        let rr = resolve q s1 in
        let r = fst rr in
        let s2 = snd rr in
        if r / 1048576 = 3 then
          (let s3 = c_builtin re m (r mod 1048576) s2 in
           (if is_atom_start s3 then
              (err_str "core-lambda: builtin result cannot be applied";
               die_line (s_line s3)));
           s3)
        else
          (let s3 = load_res m r s2 in
           app_args (if es = 1 && s_kind s3 = 2 then 1 else 0) s3))
     else app_args 0 (c_atom re m 0 s))

(* one left-associative binary level; opcode 0 = token is not this level *)
let mul_op = fun s ->
  if t_punct s 42 then 20                            (* mulint *)
  else if t_punct s 47 then 21                       (* divint *)
  else if kw_at s n_mod then 22                      (* modint *)
  else 0

let add_op = fun s ->
  if t_punct s 43 then 18                            (* addint *)
  else if t_punct s 45 then 19                       (* subint *)
  else 0

let cmp_op = fun s ->
  if t_punct s 61 then 31                            (* eq *)
  else if t_punct s 15932 then 32                    (* neq *)
  else if t_punct s 60 then 33                       (* ltint *)
  else if t_punct s 15676 then 34                    (* leint *)
  else if t_punct s 62 then 35                       (* gtint *)
  else if t_punct s 15678 then 36                    (* geint *)
  else 0

let c_mul = fun re -> fun m -> fun t -> fun s ->
  let rec more st =
    let op = mul_op st in
    if op > 0 then
      more (bump (0 - 1)
              (ew m op (c_app re m 0 (bump 1 (ew m op_push (next_token st))))))
    else st in
  more (c_app re m t s)

let c_add = fun re -> fun m -> fun t -> fun s ->
  let rec more st =
    let op = add_op st in
    if op > 0 then
      more (bump (0 - 1)
              (ew m op (c_mul re m 0 (bump 1 (ew m op_push (next_token st))))))
    else st in
  more (c_mul re m t s)

let c_cmp = fun re -> fun m -> fun t -> fun s ->
  let rec more st =
    let op = cmp_op st in
    if op > 0 then
      more (bump (0 - 1)
              (ew m op (c_add re m 0 (bump 1 (ew m op_push (next_token st))))))
    else st in
  more (c_add re m t s)

let c_and = fun re -> fun m -> fun t -> fun s ->
  let rec more st =
    if t_punct st 9766 then                          (* && *)
      (let s1 = next_token st in
       let sz = if m = 1 then s_addr (c_cmp re 0 0 s1) - s_addr s1 else 0 in
       (* [branchifnot T1] rhs [branch T2] [const 0]; T1 = the const,
          T2 = after it *)
       let s2 = em1 m op_branchifnot (s_addr s1 + 2 + sz + 2) s1 in
       let s3 = c_cmp re m 0 s2 in
       let s4 = em1 m op_branch (s_addr s3 + 2 + 2) s3 in
       more (em1 m op_const 0 s4))
    else st in
  more (c_cmp re m t s)

let c_or = fun re -> fun m -> fun t -> fun s ->
  let rec more st =
    if t_punct st 31868 then                         (* || *)
      (let s1 = next_token st in
       let sz = if m = 1 then s_addr (c_and re 0 0 s1) - s_addr s1 else 0 in
       let s2 = em1 m op_branchif (s_addr s1 + 2 + sz + 2) s1 in
       let s3 = c_and re m 0 s2 in
       let s4 = em1 m op_branch (s_addr s3 + 2 + 2) s3 in
       more (em1 m op_const 1 s4))
    else st in
  more (c_and re m t s)

(* compile `fun pname -> body` into a closure value: a branch jumps over
   the body, the body runs at depth 1 in a fresh level, and the names it
   captured are pushed afterwards for CLOSURE.  Returns (captures, s')
   because let rec must patch its self-references. *)
let compile_fun = fun re -> fun m -> fun pname -> fun s ->
  let d0 = s_depth s in
  let ex0 = s_exited s in
  let lf = s_addr s + 2 in
  let enter = fun st ->
    set_exited 0
      (set_depth 1
         (set_levels (cons (pair (l1 (pair pname 0)) nil) (s_levels st)) st)) in
  let szb =
    if m = 1 then s_addr (re 0 0 1 (enter s)) - s_addr s else 0 in
  let s1 = re m 0 1 (enter (em1 m op_branch (lf + szb) s)) in
  let caps = lev_caps (hd (s_levels s1)) in
  let s2 = set_exited ex0 (set_depth d0 (set_levels (tl (s_levels s1)) s1)) in
  (* push the captured values in the enclosing frame, then build *)
  let rec push_caps lst = fun st ->
    if null lst then st
    else
      (let rr = resolve (hd lst) st in
       push_caps (tl lst) (bump 1 (ew m op_push (load_res m (fst rr) (snd rr))))) in
  let s3 = push_caps caps s2 in
  let nc = list_len caps in
  pair caps (bump (0 - nc) (em2 m op_closure lf nc s3))

let c_funexpr = fun re -> fun m -> fun s ->
  let nr = need_ident (next_token s) in
  let s1 = snd nr in
  (if at_ident s1 then
     (err_str "core-lambda: functions are unary; nest fun"; die_line (s_line s1)));
  (if bnot (t_punct s1 15917) then
     (err_str "core-lambda: expected ->"; die_line (s_line s1)));
  snd (compile_fun re m (fst nr) (next_token s1))

let c_if = fun re -> fun m -> fun t -> fun s ->
  let s1 = re m 0 0 (next_token s) in
  (if bnot (kw_at s1 n_then) then
     (err_str "core-lambda: expected then"; die_line (s_line s1)));
  let s2 = next_token s1 in
  if t = 1 then
    (* arms are tail expressions; an arm that exits needs no join, a live
       arm joins after the else.  One exited arm plus a following
       sequence semicolon is rejected (the live path would run the rest
       of the sequence while the exited one skipped it). *)
    (let d0 = s_depth s2 in
     let s3 = set_exited 0 s2 in
     let pre = if m = 1 then re 0 1 1 s3 else s3 in
     let szt = s_addr pre - s_addr s3 in
     let tex = s_exited pre in
     let ta =
       if tex = 0 then s_addr s2 + 2 + szt + 2 else s_addr s2 + 2 + szt in
     let s4 = re m 1 1 (em1 m op_branchifnot ta s3) in
     let then_ex = s_exited s4 in
     let s5 = set_exited 0 (set_depth d0 s4) in
     let s6 =
       if then_ex = 0 then
         (let sze =
            if m = 1 then
              (if kw_at s5 n_else then
                 s_addr (re 0 1 1 (next_token s5)) - s_addr s5
               else 2)
            else 0 in
          em1 m op_branch (s_addr s5 + 2 + sze) s5)
       else s5 in
     let s7 =
       if kw_at s6 n_else then re m 1 1 (next_token s6)
       else em1 m op_const 0 s6 in
     let else_ex = s_exited s7 in
     let s8 = set_depth d0 s7 in
     if then_ex = 1 && else_ex = 1 then set_exited 1 s8
     else
       ((if (then_ex = 1 || else_ex = 1) && t_punct s8 59 then
           (err_str "core-lambda: one branch of this if exits in tail position but the other falls into a sequence; parenthesize";
            die_line (s_line s8)));
        set_exited 0 s8))
  else
    (let szt = if m = 1 then s_addr (re 0 1 0 s2) - s_addr s2 else 0 in
     let s4 = re m 1 0 (em1 m op_branchifnot (s_addr s2 + 2 + szt + 2) s2) in
     let sze =
       if m = 1 then
         (if kw_at s4 n_else then
            s_addr (re 0 1 0 (next_token s4)) - s_addr s4
          else 2)
       else 0 in
     let s5 = em1 m op_branch (s_addr s4 + 2 + sze) s4 in
     if kw_at s5 n_else then re m 1 0 (next_token s5)
     else em1 m op_const 0 s5)

let c_let = fun re -> fun m -> fun t -> fun s ->
  let s1 = next_token s in
  if kw_at s1 n_rec then
    (* single self-recursive unary local function *)
    (let nr = need_ident (next_token s1) in
     let name = fst nr in
     let s2 = snd nr in
     let slot = s_depth s2 in
     let s3 = add_bind name slot (bump 1 (ew m op_push (em1 m op_const 0 s2))) in
     let pr = need_ident s3 in
     let s4 = snd pr in
     (if at_ident s4 then
        (err_str "core-lambda: functions are unary; nest fun"; die_line (s_line s4)));
     let cf = compile_fun re m (fst pr) (expect_p 61 s4) in
     let caps = fst cf in
     let s5 = snd cf in
     (* store the closure in its slot, then patch self captures *)
     let fidx = s_depth s5 - 1 - slot in
     let s6 = em1 m op_assign fidx s5 in
     let rec patch lst = fun j -> fun st ->
       if null lst then st
       else
         (let st2 =
            if list_eq (hd lst) name then
              em1 m op_setfield (j + 1)
                (em1 m op_acc 0 (ew m op_push (em1 m op_acc fidx st)))
            else st in
          patch (tl lst) (j + 1) st2) in
     let s7 = patch caps 0 s6 in
     (if bnot (kw_at s7 n_in) then
        (err_str "core-lambda: expected in"; die_line (s_line s7)));
     let s8 = strip_bind (re m 0 t (next_token s7)) in
     if t = 0 then bump (0 - 1) (em1 m op_pop 1 s8)
     else set_depth slot s8)
  else
    (* single non-recursive binding, no parameters *)
    (let nr = need_ident s1 in
     let name = fst nr in
     let s2 = snd nr in
     (if at_ident s2 then
        (err_str "core-lambda: local let takes no parameters; use fun";
         die_line (s_line s2)));
     let start = s_depth s2 in
     let s3 = re m 0 0 (expect_p 61 s2) in
     let s4 = add_bind name start (bump 1 (ew m op_push s3)) in
     (if bnot (kw_at s4 n_in) then
        (err_str "core-lambda: expected in"; die_line (s_line s4)));
     let s5 = strip_bind (re m 0 t (next_token s4)) in
     if t = 0 then bump (0 - 1) (em1 m op_pop 1 s5)
     else set_depth start s5)

(* the single recursive entry point: mode 0 = expression with sequencing,
   mode 1 = one sequence element *)
let rec cexp m = fun mode -> fun t -> fun s ->
  if mode = 1 then
    (let s1 =
       if kw_at s n_if then c_if cexp m t s
       else if kw_at s n_let then c_let cexp m t s
       else if kw_at s n_fun then c_funexpr cexp m s
       else c_or cexp m t s in
     value_done m t s1)
  else
    (let rec seq st =
       if t_punct st 59 then
         ((if s_exited st = 1 then
             (err_str "core-lambda: tail branch followed by a sequence; parenthesize the if/let";
              die_line (s_line st)));
          seq (cexp m 1 t (next_token st)))
       else st in
     seq (cexp m 1 t s))

(* ---- top level ---- *)

let top_one = fun m -> fun s ->
  (if bnot (kw_at s n_let) then
     (err_str "core-lambda: expected a top-level let"; die_line (s_line s)));
  let s1 = next_token s in
  if kw_at s1 n_rec then
    (let nr = need_ident (next_token s1) in
     let pr = need_ident (snd nr) in
     let s2 = snd pr in
     (if at_ident s2 then
        (err_str "core-lambda: functions are unary; nest fun"; die_line (s_line s2)));
     let s3 = expect_p 61 s2 in
     let md = mark_defined (fst nr) (s_globs s3) in
     let s4 = snd (compile_fun cexp m (fst pr) (set_globs (snd md) s3)) in
     em1 m op_setglobal (gbase + fst md) s4)
  else if t_punct s1 40 then
    (* let () = expr *)
    cexp m 0 0 (expect_p 61 (expect_p 41 (next_token s1)))
  else
    (let nr = need_ident s1 in
     let s2 = snd nr in
     (if at_ident s2 then
        (err_str "core-lambda: top-level let takes no parameters; use fun or let rec";
         die_line (s_line s2)));
     let s3 = expect_p 61 s2 in
     let md = mark_defined (fst nr) (s_globs s3) in
     let s4 = cexp m 0 0 (set_globs (snd md) s3) in
     em1 m op_setglobal (gbase + fst md) s4)

let rec top_loop m = fun s ->
  if s_kind s = 0 then s else top_loop m (top_one m s)

(* trailing entry code, part of both passes so the size pass counts it *)
let finish = fun m -> fun s -> ew m op_stop (em1 m op_const 0 s)

(* ---- driver ---- *)

let () =
  if arg_count () < 2 then
    (err_str "usage: core-lambda in.ml out.mzbc";
     write_byte 2 10;
     exit 1)

let inh = open_in (arg_get 0)

let () =
  if inh < 0 then
    (err_str "core-lambda: cannot open input"; die_line 1)

let source =
  let rec rd acc =
    let b = read_byte inh in
    if b >= 0 then rd (cons b acc) else rev_list acc in
  rd nil

let () = close_chan inh

(* both passes start from the same first token and empty tables; the
   bottom (top-level) scope never captures, it only resolves globals *)
let start_state = fun outh ->
  pair (scan_token source 1)
    (pair (pair 0 (pair 0 (pair 0 outh)))
       (pair (pair 0 nil) (pair (pair 0 nil) (l1 (pair nil nil)))))

let w32 = fun h -> fun v ->
  write_byte h v;
  write_byte h (v / 256);
  write_byte h (v / 65536);
  write_byte h (v / 16777216)

let rec write_data h = fun lst ->
  if null lst then ()
  else
    (w32 h (list_len (hd lst));
     let rec wr l2 = if null l2 then () else (write_byte h (hd l2); wr (tl l2)) in
     wr (hd lst);
     write_data h (tl lst))

let () =
  (* pass 1: sizes, global table, data section *)
  let s1 = finish 0 (top_loop 0 (start_state 0)) in
  check_all_defined (s_globs s1) (s_line s1);
  let outh = open_out (arg_get 1) in
  (if outh < 0 then
     (err_str "core-lambda: cannot open output"; die_line 1));
  write_byte outh 77; write_byte outh 90;             (* M Z B C *)
  write_byte outh 66; write_byte outh 67;
  w32 outh 1;                                         (* version *)
  w32 outh (s_addr s1);                               (* code words *)
  w32 outh 12;                                        (* primcount *)
  w32 outh (gbase + g_count (s_globs s1));
  w32 outh (d_count (s_dats s1));
  (* pass 2: emit the code words, then the data records *)
  let s2 = finish 1 (top_loop 1 (start_state outh)) in
  write_data outh (rev_list (d_list (s_dats s2)));
  close_chan outh;
  exit 0
