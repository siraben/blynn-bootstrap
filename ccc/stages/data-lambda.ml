(* data-lambda: Lambda-1 -> binary MZBC image, written in Lambda-0.
   Second rung of the lambda ladder (ccc/docs/lambda-ladder.md); a fork
   of core-lambda whose delta extends the *input* dialect from Lambda-0
   to Lambda-1.  Its own source stays Lambda-0, so core-lambda compiles
   it and it recompiles itself to the same bytes (Lambda-0 inputs get
   byte-identical code from both compilers).

   Usage: mlc-interp core-lambda.ml data-lambda.ml data-lambda.mzbc
          mzvm data-lambda.mzbc in.ml out.mzbc

   The delta over Lambda-0 (each form compiles to byte-for-byte the
   ZINC shapes ml0-compiler emits, so the diverse-double-compilation
   anchor keeps comparing images directly):
     - string literals are first-class atoms anywhere (not only after
       `err_str`); each compiles to a data-section global (a GETGLOBAL
       of slots 0..4095), read with the `string_length`/`string_get`
       builtin aliases of `bytes_length`/`bytes_get`.
     - arrays: `array_make n v` (C primitive 10), `array_get a i`
       (GETVECTITEM), `array_set a i v` (SETVECTITEM) and
       `array_length a` (VECTLENGTH).
     - multi-parameter functions with curried semantics: `let f x y = e`
       and `let rec f x y = e` (top level and local) and `fun x y -> e`
       compile as nested unary closures, each inner closure RETURNed by
       its enclosing one, exactly as ml0-compiler's compile_fun.
     - `()` is accepted as a parameter and binds nothing.

   Grammar decisions carried over from core-lambda:
     - `()` is an atom (the unit value, compiled as the integer 0).
     - `true`/`false` are atoms (integers 1/0).
     - `if c then e` without `else` is accepted (the missing branch is
       unit), since Lambda-1 needs conditional side effects.
     - integer literals are decimal only: no hex, no char literals, no
       unary minus (write `0 - 1`).
     - identifiers are at most 64 bytes long; `_` is rejected as a
       binder (`let _ = e in` is not Lambda-1; sequence with `;`).
     - reserved words of fuller MLs (and, match, with, land, ...) are
       rejected so non-Lambda-1 sources fail loudly: still no tuples,
       ADTs, match, refs or records.

   Compilation model: single pass, parse-and-emit, no AST; the ZINC code
   shapes are byte-for-byte those of ml0-compiler + parenthetical, so the
   diverse-double-compilation anchor can compare images directly.  All
   mutable state lives in byte buffers (Lambda-0 has no refs or arrays):
   scalar registers are 32-bit little-endian slots of `st`, the code is
   built in `code` and backpatched with bytes_set, and capture lists and
   the global table live in byte pools.  Compile-time environments are
   closures from name to an encoded resolution (kind * 2^20 + index),
   extended functionally at binders; each `fun` boundary threads captured
   names into its level's pool, which is replayed after the body to push
   the CLOSURE captures. *)

(* ---- mutable state: byte buffers and 32-bit registers ---- *)

let st = bytes_create 4096          (* scalar registers, 4-byte LE slots *)
let src = bytes_create 1048576      (* source text *)
let code = bytes_create 4194304     (* emitted code words, 4-byte LE *)
let dat = bytes_create 262144       (* data section, ready-to-write records *)
let gpool = bytes_create 65536      (* global names: [flag][len][bytes] *)
let gofs = bytes_create 8192        (* per-global offset into gpool *)
let cpool = bytes_create 266240     (* capture names: 64 levels * 64 * 65 *)
let tbuf = bytes_create 256         (* current token text *)

let rg = fun i ->
  bytes_get st (4 * i) + 256 * bytes_get st (4 * i + 1)
  + 65536 * bytes_get st (4 * i + 2) + 16777216 * bytes_get st (4 * i + 3)

let rs = fun i -> fun v ->
  bytes_set st (4 * i) v;
  bytes_set st (4 * i + 1) (v / 256);
  bytes_set st (4 * i + 2) (v / 65536);
  bytes_set st (4 * i + 3) (v / 16777216)

let r_pos = 0                       (* scanner position *)
let r_line = 1                      (* current line *)
let r_srclen = 2                    (* source length *)
let r_tk = 3                        (* token kind: 0 eof 1 int 2 str 3 ident 4 punct *)
let r_tint = 4                      (* int value / packed punct chars *)
let r_tlen = 5                      (* token text length *)
let r_ik0 = 6                       (* ident chars 0-5, base-28 packed *)
let r_ik1 = 7                       (* ident chars 6-11 *)
let r_ik2 = 8                       (* ident chars 12-17 *)
let r_clen = 9                      (* code length in words *)
let r_datlen = 10                   (* data section length in bytes *)
let r_datcount = 11                 (* number of data records *)
let r_gplen = 12                    (* global name pool length *)
let r_gcount = 13                   (* number of globals *)
let r_depth = 14                    (* current stack depth *)
let r_lev = 15                      (* current function nesting level *)
let r_exited = 16                   (* 1 after RETURN/APPTERM in tail pos *)
let r_outh = 17                     (* output channel *)
let r_svpos = 19                    (* scanner save for tail lookahead *)
let r_svline = 20
let r_ccount0 = 32                  (* capture counts: slot 32+level *)
let r_sdepth0 = 96                  (* saved depths: slot 96+level *)

let gbase = 4096                    (* first non-data global *)

(* ---- tiny helpers ---- *)

let ign = fun v -> ()
let bnot = fun b -> if b then false else true

(* ---- diagnostics ---- *)

let rec err_str_from s = fun i ->
  if i < string_length s then
    (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str = fun s -> err_str_from s 0

let rec err_bytes_from b = fun i ->
  if i < bytes_length b then
    (write_byte 2 (bytes_get b i); err_bytes_from b (i + 1))

let err_bytes = fun b -> err_bytes_from b 0

let rec err_int_rec n =
  (if n > 9 then err_int_rec (n / 10));
  write_byte 2 (48 + n mod 10)

let err_int = fun n ->
  if n < 0 then (write_byte 2 45; err_int_rec (0 - n)) else err_int_rec n

(* finish a diagnostic: caller has already err_str'd the message *)
let die = fun u ->
  err_str " at line ";
  err_int (rg r_line);
  write_byte 2 10;
  exit 1

(* ---- bytes equality and base-28 identifier packing ---- *)

let bytes_eq = fun a -> fun b ->
  let n = bytes_length a in
  if bytes_length b = n then
    (let rec cmp i =
       if i >= n then true
       else if bytes_get a i = bytes_get b i then cmp (i + 1)
       else false in
     cmp 0)
  else false

(* a-z -> 1..26, _ -> 27, anything else 0 (never matches a name code) *)
let chv = fun c ->
  if c = 95 then 27
  else if c >= 97 && c <= 122 then c - 96
  else 0

let rec limbg b = fun stop -> fun i -> fun acc -> fun m ->
  if i >= stop then acc
  else limbg b stop (i + 1) (acc + chv (bytes_get b i) * m) (m * 28)

(* limb p of a name: chars [6p, 6p+6) packed little-endian in base 28 *)
let limbn = fun b -> fun n -> fun p ->
  let s = p * 6 + 6 in
  limbg b (if n < s then n else s) (p * 6) 0 1

(* ---- input ---- *)

let rec read_all h =
  let b = read_byte h in
  if b >= 0 then
    ((if rg r_srclen >= 1048576 then (err_str "data-lambda: source too large"; die 0));
     bytes_set src (rg r_srclen) b;
     rs r_srclen (rg r_srclen + 1);
     read_all h)

(* ---- scanner ---- *)

let peekc = fun u ->
  if rg r_pos >= rg r_srclen then 0 - 1 else bytes_get src (rg r_pos)

let peekc2 = fun u ->
  if rg r_pos + 1 >= rg r_srclen then 0 - 1 else bytes_get src (rg r_pos + 1)

let nextc = fun u ->
  let c = peekc 0 in
  rs r_pos (rg r_pos + 1);
  (if c = 10 then rs r_line (rg r_line + 1));
  c

let is_digit = fun c -> c >= 48 && c <= 57
let is_istart = fun c -> (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c = 95
let is_ichar = fun c -> is_istart c || is_digit c || c = 39

let rec skip_comment depth =
  if depth > 0 then
    (let c = nextc 0 in
     (if c < 0 then (err_str "data-lambda: unterminated comment"; die 0));
     if c = 40 && peekc 0 = 42 then (ign (nextc 0); skip_comment (depth + 1))
     else if c = 42 && peekc 0 = 41 then (ign (nextc 0); skip_comment (depth - 1))
     else skip_comment depth)

let rec skip_ws u =
  let c = peekc 0 in
  if c = 32 || c = 9 || c = 13 || c = 10 then (ign (nextc 0); skip_ws 0)
  else if c = 40 && peekc2 0 = 42 then
    (ign (nextc 0); ign (nextc 0); skip_comment 1; skip_ws 0)

let read_escape = fun u ->
  let e = nextc 0 in
  if e = 110 then 10
  else if e = 116 then 9
  else if e = 114 then 13
  else if e = 92 then 92
  else if e = 34 then 34
  else if e = 39 then 39
  else (err_str "data-lambda: bad escape"; die 0)

let tpush = fun b ->
  let n = rg r_tlen in
  (if n >= 250 then (err_str "data-lambda: token too long"; die 0));
  bytes_set tbuf n b;
  rs r_tlen (n + 1)

(* two-character punctuation, packed c + 256*d; 0 = not a pair *)
let pair2 = fun c -> fun d ->
  if c = 45 && d = 62 then 15917          (* -> *)
  else if c = 60 && d = 62 then 15932     (* <> *)
  else if c = 60 && d = 61 then 15676     (* <= *)
  else if c = 62 && d = 61 then 15678     (* >= *)
  else if c = 38 && d = 38 then 9766      (* && *)
  else if c = 124 && d = 124 then 31868   (* || *)
  else 0

let next_token = fun u ->
  skip_ws 0;
  let c = peekc 0 in
  if c < 0 then rs r_tk 0
  else if is_digit c then
    (let rec dec acc =
       if is_digit (peekc 0) then dec (acc * 10 + (nextc 0 - 48))
       else acc in
     let v = dec 0 in
     (if is_ichar (peekc 0) then (err_str "data-lambda: bad number"; die 0));
     rs r_tint v;
     rs r_tk 1)
  else if is_istart c then
    (rs r_tlen 0;
     let rec idloop u2 =
       if is_ichar (peekc 0) then
         ((if rg r_tlen >= 64 then (err_str "data-lambda: identifier too long"; die 0));
          tpush (nextc 0);
          idloop 0) in
     idloop 0;
     rs r_ik0 (limbn tbuf (rg r_tlen) 0);
     rs r_ik1 (limbn tbuf (rg r_tlen) 1);
     rs r_ik2 (limbn tbuf (rg r_tlen) 2);
     rs r_tk 3)
  else if c = 34 then
    (ign (nextc 0);
     rs r_tlen 0;
     let rec sloop u2 =
       let d = peekc 0 in
       if d < 0 then (err_str "data-lambda: unterminated string"; die 0)
       else if d = 34 then ign (nextc 0)
       else if d = 92 then (ign (nextc 0); tpush (read_escape 0); sloop 0)
       else (ign (nextc 0); tpush d; sloop 0) in
     sloop 0;
     rs r_tk 2)
  else
    (ign (nextc 0);
     let two = pair2 c (peekc 0) in
     (if two > 0 then (ign (nextc 0); rs r_tint two) else rs r_tint c);
     rs r_tk 4)

(* ---- token predicates ----
   Keywords are matched by their base-28 packed code; every keyword is at
   most 6 chars so limbs 1 and 2 are zero, which no longer identifier can
   fake (present chars always pack nonzero). *)

let t_punct = fun p -> rg r_tk = 4 && rg r_tint = p

let kw_at = fun k ->
  rg r_tk = 3 && rg r_ik1 = 0 && rg r_ik2 = 0 && rg r_ik0 = k

(* Lambda-0 keywords plus rejected reserved words of fuller MLs *)
let is_kw_tok = fun u ->
  if rg r_tk = 3 && rg r_ik1 = 0 && rg r_ik2 = 0 then
    (let k = rg r_ik0 in
     k = 15832 (* let *) || k = 2510 (* rec *) || k = 401 (* in *)
     || k = 177 (* if *) || k = 311492 (* then *) || k = 124997 (* else *)
     || k = 11570 (* fun *) || k = 126748 (* true *) || k = 3499810 (* false *)
     || k = 3569 (* mod *)
     || k = 3529 (* and *) || k = 4998825 (* match *) || k = 191571 (* with *)
     || k = 123024 (* type *) || k = 8808382 (* begin *) || k = 3533 (* end *)
     || k = 3344007 (* while *) || k = 424 (* do *) || k = 121160 (* done *)
     || k = 98824 (* land *) || k = 14544 (* lor *) || k = 407580 (* lxor *)
     || k = 9952 (* lsl *) || k = 14656 (* lsr *) || k = 14645 (* asr *)
     || k = 20124 (* try *) || k = 311495 (* when *) || k = 533 (* as *)
     || k = 183 (* of *) || k = 311711 (* open *) || k = 93892273 (* module *)
     || k = 440 (* to *) || k = 270774424 (* downto *) || k = 14538 (* for *)
     || k = 4862 (* ref *))
  else false

let at_ident = fun u -> rg r_tk = 3 && bnot (is_kw_tok 0)

let starts_atom = fun u ->
  let k = rg r_tk in
  if k = 1 || k = 2 then true
  else if k = 3 then
    (if kw_at 126748 (* true *) || kw_at 3499810 (* false *) then true
     else bnot (is_kw_tok 0))
  else t_punct 40

(* does the current token continue the enclosing expression as an infix
   operator or sequence separator? used to veto tail calls *)
let op_follows = fun u ->
  if rg r_tk = 4 then
    (let p = rg r_tint in
     p = 43 || p = 45 || p = 42 || p = 47          (* + - * / *)
     || p = 61 || p = 15932 || p = 60 || p = 15676 (* = <> < <= *)
     || p = 62 || p = 15678                        (* > >= *)
     || p = 9766 || p = 31868 || p = 59)           (* && || ; *)
  else kw_at 3569 (* mod *)

(* fresh copy of the current identifier's text, then advance *)
let take_ident = fun u ->
  let n = rg r_tlen in
  let b = bytes_create n in
  let rec cp i = if i < n then (bytes_set b i (bytes_get tbuf i); cp (i + 1)) in
  cp 0;
  next_token 0;
  b

let need_ident = fun u ->
  if at_ident 0 then
    ((if rg r_tlen = 1 && bytes_get tbuf 0 = 95 then
        (err_str "data-lambda: _ is not a Lambda-1 binder; sequence with ; instead"; die 0));
     take_ident 0)
  else (err_str "data-lambda: expected an identifier"; die 0)

(* write a (possibly two-char) punctuation spelling to stderr *)
let wp2 = fun c ->
  write_byte 2 (c mod 256);
  if c > 255 then write_byte 2 (c / 256)

let expect_p = fun c ->
  if t_punct c then next_token 0
  else (err_str "data-lambda: expected "; wp2 c; die 0)

(* one formal parameter: an identifier, or `()` which binds nothing (the
   empty name can never collide with a source identifier) *)
let param_ident = fun u ->
  if t_punct 40 then (next_token 0; expect_p 41; bytes_create 0)
  else need_ident 0

(* does another parameter follow? *)
let at_param = fun u -> at_ident 0 || t_punct 40

(* ---- tail lookahead ----
   Decides whether a parenthesized expression in tail position can be
   compiled as a tail expression: scan to the matching close paren and
   require that no operator or atom follows.  Only the scanner position
   needs saving; the current token is the open paren and is re-made. *)

let ptc = fun u ->
  rs r_svpos (rg r_pos);
  rs r_svline (rg r_line);
  next_token 0;
  let r =
    if t_punct 41 then 0
    else
      (let rec scan depth =
         if rg r_tk = 0 then 0
         else if t_punct 40 then (next_token 0; scan (depth + 1))
         else if t_punct 41 then
           (if depth = 1 then
              (next_token 0;
               if op_follows 0 || starts_atom 0 then 0 else 1)
            else (next_token 0; scan (depth - 1)))
         else (next_token 0; scan depth) in
       scan 1) in
  rs r_pos (rg r_svpos);
  rs r_line (rg r_svline);
  rs r_tk 4;
  rs r_tint 40;
  r

(* ---- code emission ---- *)

let emitw = fun v ->
  let n = rg r_clen in
  (if n >= 1048575 then (err_str "data-lambda: code too large"; die 0));
  bytes_set code (4 * n) v;
  bytes_set code (4 * n + 1) (v / 256);
  bytes_set code (4 * n + 2) (v / 65536);
  bytes_set code (4 * n + 3) (v / 16777216);
  rs r_clen (n + 1)

let emit1 = fun op -> fun a -> (emitw op; emitw a)
let emit2 = fun op -> fun a -> fun b -> (emitw op; emitw a; emitw b)

(* emit a branch opcode with a hole; returns the hole's word index *)
let hole = fun op -> (emitw op; emitw 0; rg r_clen - 1)

(* point a hole at the current address *)
let patch_here = fun h ->
  let v = rg r_clen in
  bytes_set code (4 * h) v;
  bytes_set code (4 * h + 1) (v / 256);
  bytes_set code (4 * h + 2) (v / 65536);
  bytes_set code (4 * h + 3) (v / 16777216)

let bump = fun n -> rs r_depth (rg r_depth + n)

(* current string token -> data record + GETGLOBAL of its slot *)
let emit_strlit = fun u ->
  let i = rg r_datcount in
  (if i >= gbase then (err_str "data-lambda: too many string literals"; die 0));
  let n = rg r_tlen in
  let o = rg r_datlen in
  (if o + 4 + n > 262144 then (err_str "data-lambda: data section too large"; die 0));
  bytes_set dat o n;
  bytes_set dat (o + 1) (n / 256);
  bytes_set dat (o + 2) 0;
  bytes_set dat (o + 3) 0;
  let rec cp j = if j < n then (bytes_set dat (o + 4 + j) (bytes_get tbuf j); cp (j + 1)) in
  cp 0;
  rs r_datlen (o + 4 + n);
  rs r_datcount (i + 1);
  emit1 45 i

(* ---- global table: [defined-flag][len][name] entries in gpool ---- *)

let gofs_get = fun i ->
  bytes_get gofs (4 * i) + 256 * bytes_get gofs (4 * i + 1)
  + 65536 * bytes_get gofs (4 * i + 2)

let gname_eq = fun i -> fun q ->
  let o = gofs_get i in
  let n = bytes_get gpool (o + 1) in
  if bytes_length q = n then
    (let rec cmp j =
       if j >= n then true
       else if bytes_get gpool (o + 2 + j) = bytes_get q j then cmp (j + 1)
       else false in
     cmp 0)
  else false

(* newest first so later definitions shadow earlier ones *)
let find_global = fun q ->
  let rec go i =
    if i < 0 then 0 - 1
    else if gname_eq i q then i
    else go (i - 1) in
  go (rg r_gcount - 1)

let add_global = fun q ->
  let i = rg r_gcount in
  (if i >= 2048 then (err_str "data-lambda: too many globals"; die 0));
  let n = bytes_length q in
  let o = rg r_gplen in
  (if o + 2 + n > 65536 then (err_str "data-lambda: global name pool full"; die 0));
  bytes_set gofs (4 * i) o;
  bytes_set gofs (4 * i + 1) (o / 256);
  bytes_set gofs (4 * i + 2) (o / 65536);
  bytes_set gofs (4 * i + 3) 0;
  bytes_set gpool o 0;
  bytes_set gpool (o + 1) n;
  let rec cp j = if j < n then (bytes_set gpool (o + 2 + j) (bytes_get q j); cp (j + 1)) in
  cp 0;
  rs r_gplen (o + 2 + n);
  rs r_gcount (i + 1);
  i

let gdefined = fun i -> bytes_get gpool (gofs_get i)
let set_gdefined = fun i -> bytes_set gpool (gofs_get i) 1

let mark_defined = fun q ->
  let g = find_global q in
  if g >= 0 then
    (if gdefined g = 1 then
       (* already defined: shadow with a fresh global *)
       (let g2 = add_global q in set_gdefined g2; g2)
     else (set_gdefined g; g))
  else (let g2 = add_global q in set_gdefined g2; g2)

let check_all_defined = fun u ->
  let n = rg r_gcount in
  let rec go i =
    if i < n then
      ((if gdefined i = 0 then
          (let o = gofs_get i in
           err_str "data-lambda: undefined name ";
           let len = bytes_get gpool (o + 1) in
           let rec wr j = if j < len then (write_byte 2 (bytes_get gpool (o + 2 + j)); wr (j + 1)) in
           wr 0;
           ign (die 0)));
       go (i + 1)) in
  go 0

(* ---- capture pools: per level, [len][name bytes] in 65-byte slots ---- *)

let cap_eq = fun l -> fun j -> fun q ->
  let a = l * 4160 + j * 65 in
  let n = bytes_get cpool a in
  if bytes_length q = n then
    (let rec cmp i =
       if i >= n then true
       else if bytes_get cpool (a + 1 + i) = bytes_get q i then cmp (i + 1)
       else false in
     cmp 0)
  else false

let cap_find = fun l -> fun q ->
  let n = rg (r_ccount0 + l) in
  let rec go j =
    if j >= n then 0 - 1
    else if cap_eq l j q then j
    else go (j + 1) in
  go 0

let cap_add = fun l -> fun q ->
  let n = rg (r_ccount0 + l) in
  (if n >= 64 then (err_str "data-lambda: too many captured variables"; die 0));
  let a = l * 4160 + n * 65 in
  let len = bytes_length q in
  bytes_set cpool a len;
  let rec cp i = if i < len then (bytes_set cpool (a + 1 + i) (bytes_get q i); cp (i + 1)) in
  cp 0;
  rs (r_ccount0 + l) (n + 1);
  n

let cap_name = fun l -> fun j ->
  let a = l * 4160 + j * 65 in
  let n = bytes_get cpool a in
  let b = bytes_create n in
  let rec cp i = if i < n then (bytes_set b i (bytes_get cpool (a + 1 + i)); cp (i + 1)) in
  cp 0;
  b

(* ---- name resolution ----
   An environment is a closure from name to an encoded resolution
   kind * 2^20 + index.  Kinds: 0 stack slot, 1 capture index, 2 global
   (absolute), 3 builtin descriptor.  The bottom environment resolves
   globals and builtins and turns unknown names into forward globals. *)

let mk_res = fun k -> fun i -> k * 1048576 + i

(* builtin descriptor: ckind * 256 + arity * 16 + index.
   ckind 0 = C primitive (all args pushed, CCALL), 1 = opcode (last arg
   stays in acc), 2 = arg_count (unit argument compiled but not passed).
   Names are matched by length plus base-28 limbs (see limbn). *)
let bi_desc = fun q ->
  let n = bytes_length q in
  if n > 13 then 0 - 1
  else
    (let a = limbn q n 0 in
     let b = limbn q n 1 in
     let c = limbn q n 2 in
     if n = 4 && a = 446773 then 16                            (* exit *)
     else if n = 7 && a = 171800735 && b = 14 then 17          (* open_in *)
     else if n = 8 && a = 275062943 && b = 581 then 18         (* open_out *)
     else if n = 10 && a = 468182403 && b = 308339 then 19     (* close_chan *)
     else if n = 9 && a = 51105198 && b = 4505 then 20         (* read_byte *)
     else if n = 10 && a = 468199839 && b = 126142 then 37     (* write_byte *)
     else if n = 12 && a = 476484542 && b = 98371339 then 22   (* bytes_create *)
     else if n = 12 && a = 476484542 && b = 150140856 then 23  (* bytes_length *)
     else if n = 13 && a = 129290019 && b = 348821563 && c = 8 then 23 (* string_length *)
     else if n = 9 && a = 260598185 && b = 16093 then 536      (* arg_count *)
     else if n = 7 && a = 90953129 && b = 20 then 25           (* arg_get *)
     else if n = 9 && a = 476484542 && b = 15827 then 289      (* bytes_get *)
     else if n = 10 && a = 129290019 && b = 443183 then 289    (* string_get *)
     else if n = 9 && a = 476484542 && b = 15839 then 306      (* bytes_set *)
     else if n = 10 && a = 480082905 && b = 118425 then 42     (* array_make *)
     else if n = 9 && a = 480082905 && b = 15827 then 291      (* array_get *)
     else if n = 9 && a = 480082905 && b = 15839 then 308      (* array_set *)
     else if n = 12 && a = 480082905 && b = 150140856 then 277 (* array_length *)
     else 0 - 1)

let genv = fun q ->
  let g = find_global q in
  if g >= 0 then mk_res 2 (gbase + g)
  else
    (let d = bi_desc q in
     if d >= 0 then mk_res 3 d
     else
       (* forward reference: assume a later top-level binding *)
       mk_res 2 (gbase + add_global q))

let env_bind = fun n -> fun r -> fun outer ->
  fun q -> if bytes_eq q n then r else outer q

(* function boundary at level l: names bound outside become captures *)
let boundary = fun l -> fun outer ->
  fun q ->
    let c = cap_find l q in
    if c >= 0 then mk_res 1 c
    else
      (let r = outer q in
       if r / 1048576 >= 2 then r
       else mk_res 1 (cap_add l q))

let load_res = fun r ->
  let k = r / 1048576 in
  let i = r mod 1048576 in
  if k = 0 then emit1 2 (rg r_depth - 1 - i)       (* acc *)
  else if k = 1 then emit1 6 (i + 1)               (* envacc *)
  else if k = 2 then emit1 45 i                    (* getglobal *)
  else (err_str "data-lambda: builtin used as a value"; die 0)

(* a plain value sits in acc; in tail position emit its RETURN unless an
   appterm already exited or a sequence semicolon follows *)
let value_done = fun t ->
  if t = 1 && rg r_exited = 0 then
    (if t_punct 59 then ()
     else (emit1 10 (rg r_depth); rs r_exited 1))

(* ---- parser / code generator ----
   The expression compiler is one mutually recursive family; Lambda-0 has
   no `and`, so each helper takes the single recursive entry point `re`
   as its first argument: `re 0 env t` compiles a full expression
   (sequences included), `re 1 env t` one sequence element. *)

let c_atom = fun re -> fun env ->
  let k = rg r_tk in
  if k = 1 then (emit1 1 (rg r_tint); next_token 0)
  else if k = 2 then (emit_strlit 0; next_token 0)
  else if k = 3 then
    (if kw_at 126748 (* true *) then (emit1 1 1; next_token 0)
     else if kw_at 3499810 (* false *) then (emit1 1 0; next_token 0)
     else if is_kw_tok 0 then (err_str "data-lambda: unexpected keyword"; die 0)
     else (let name = take_ident 0 in load_res (env name)))
  else if t_punct 40 then
    (next_token 0;
     if t_punct 41 then (emit1 1 0; next_token 0)
     else (ign (re 0 env 0); expect_p 41))
  else (err_str "data-lambda: unexpected token"; die 0)

let c_builtin = fun re -> fun env -> fun d ->
  let kind = d / 256 in
  let ar = d / 16 mod 16 in
  let idx = d mod 16 in
  let rec args j =
    if j < ar then
      ((if bnot (starts_atom 0) then
          (err_str "data-lambda: builtin applied to too few arguments"; die 0));
       c_atom re env;
       (if kind = 0 || j < ar - 1 then (emitw 3; bump 1));
       args (j + 1)) in
  args 0;
  if kind = 0 then (emit2 47 ar idx; bump (0 - ar))
  else if kind = 2 then emit2 47 0 idx
  else
    ((if idx = 1 then emitw 43                   (* getbytes *)
      else if idx = 2 then emitw 44              (* setbytes *)
      else if idx = 3 then emitw 41              (* getvectitem *)
      else if idx = 4 then emitw 42              (* setvectitem *)
      else emitw 40);                            (* vectlength *)
     bump (0 - (ar - 1)))

let c_app = fun re -> fun env -> fun t ->
  if t = 1 && t_punct 40 && ptc 0 = 1 then
    (* tail expression through parentheses: (effects; call args) *)
    (next_token 0; ign (re 0 env 1); expect_p 41)
  else
    (let was_builtin =
       if at_ident 0 && bnot (kw_at 126748) && bnot (kw_at 3499810) then
         (let name = take_ident 0 in
          let r = env name in
          if r / 1048576 = 3 then (c_builtin re env (r mod 1048576); 1)
          else (load_res r; 0))
       else (c_atom re env; 0) in
     (if was_builtin = 1 && starts_atom 0 then
        (err_str "data-lambda: builtin result cannot be applied"; die 0));
     let rec app_args u =
       if starts_atom 0 then
         (emitw 3; bump 1;                        (* push the callee *)
          c_atom re env;
          emitw 3; bump 1;                        (* push the argument *)
          if starts_atom 0 then
            (emit1 2 1; emit1 8 1; emit1 4 1;     (* acc 1; apply 1; pop 1 *)
             bump (0 - 2);
             app_args 0)
          else if t = 1 && bnot (op_follows 0) then
            (emit1 2 1;
             emit2 9 1 (rg r_depth - 1);          (* appterm 1, depth-1 *)
             rs r_exited 1;
             bump (0 - 2))
          else
            (emit1 2 1; emit1 8 1; emit1 4 1;
             bump (0 - 2))) in
     app_args 0)

(* one left-associative binary level; opcode 0 = token is not this level *)
let mul_op = fun u ->
  if t_punct 42 then 20                            (* mulint *)
  else if t_punct 47 then 21                       (* divint *)
  else if kw_at 3569 then 22                       (* modint *)
  else 0

let add_op = fun u ->
  if t_punct 43 then 18                            (* addint *)
  else if t_punct 45 then 19                       (* subint *)
  else 0

let cmp_op = fun u ->
  if t_punct 61 then 31                            (* eq *)
  else if t_punct 15932 then 32                    (* neq *)
  else if t_punct 60 then 33                       (* ltint *)
  else if t_punct 15676 then 34                    (* leint *)
  else if t_punct 62 then 35                       (* gtint *)
  else if t_punct 15678 then 36                    (* geint *)
  else 0

let c_mul = fun re -> fun env -> fun t ->
  c_app re env t;
  let rec more u =
    let op = mul_op 0 in
    if op > 0 then
      (next_token 0; emitw 3; bump 1;
       c_app re env 0;
       emitw op; bump (0 - 1);
       more 0) in
  more 0

let c_add = fun re -> fun env -> fun t ->
  c_mul re env t;
  let rec more u =
    let op = add_op 0 in
    if op > 0 then
      (next_token 0; emitw 3; bump 1;
       c_mul re env 0;
       emitw op; bump (0 - 1);
       more 0) in
  more 0

let c_cmp = fun re -> fun env -> fun t ->
  c_add re env t;
  let rec more u =
    let op = cmp_op 0 in
    if op > 0 then
      (next_token 0; emitw 3; bump 1;
       c_add re env 0;
       emitw op; bump (0 - 1);
       more 0) in
  more 0

let c_and = fun re -> fun env -> fun t ->
  c_cmp re env t;
  let rec more u =
    if t_punct 9766 then                           (* && *)
      (next_token 0;
       let hf = hole 16 in                         (* branchifnot *)
       c_cmp re env 0;
       let he = hole 14 in                         (* branch *)
       patch_here hf;
       emit1 1 0;
       patch_here he;
       more 0) in
  more 0

let c_or = fun re -> fun env -> fun t ->
  c_and re env t;
  let rec more u =
    if t_punct 31868 then                          (* || *)
      (next_token 0;
       let ht = hole 15 in                         (* branchif *)
       c_and re env 0;
       let he = hole 14 in                         (* branch *)
       patch_here ht;
       emit1 1 1;
       patch_here he;
       more 0) in
  more 0

(* compile `fun pname .. -> body` (term 15917) or `pname .. = body`
   (term 61) into a closure value; pname is already taken, the remaining
   parameters and the terminator are still in the token stream.  The body
   is emitted first (behind a branch) so its free variables are
   discovered, then the captured values are pushed and CLOSURE built.
   Each extra parameter nests one more unary closure, RETURNed by its
   enclosing one, exactly as ml0-compiler's compile_fun. *)
let rec compile_fun re = fun env -> fun pname -> fun term ->
  let hs = hole 14 in                              (* branch over the body *)
  let lf = rg r_clen in
  let saved_ex = rg r_exited in
  let l = rg r_lev in
  (if l + 1 >= 64 then (err_str "data-lambda: functions nested too deeply"; die 0));
  rs (r_sdepth0 + l) (rg r_depth);
  rs (r_ccount0 + l + 1) 0;
  rs r_lev (l + 1);
  rs r_depth 1;
  rs r_exited 0;
  let env2 = env_bind pname (mk_res 0 0) (boundary (l + 1) env) in
  (if at_param 0 then
     (let p2 = param_ident 0 in
      compile_fun re env2 p2 term;
      emit1 10 (rg r_depth))
   else
     (expect_p term;
      ign (re 0 env2 1)));
  rs r_exited saved_ex;
  let fl = rg r_lev in
  rs r_lev (fl - 1);
  rs r_depth (rg (r_sdepth0 + fl - 1));
  patch_here hs;
  (* push the captured values in the enclosing frame, then build *)
  let nc = rg (r_ccount0 + fl) in
  let rec caps j =
    if j < nc then
      (load_res (env (cap_name fl j));
       emitw 3; bump 1;
       caps (j + 1)) in
  caps 0;
  emit2 7 lf nc;
  bump (0 - nc)

let c_funexpr = fun re -> fun env ->
  next_token 0;
  let pname = param_ident 0 in
  compile_fun re env pname 15917

let c_if = fun re -> fun env -> fun t ->
  next_token 0;
  ign (re 0 env 0);
  (if bnot (kw_at 311492) then (err_str "data-lambda: expected then"; die 0));
  next_token 0;
  if t = 1 then
    (* arms are tail expressions; an arm that exits needs no join, a live
       arm joins after the else.  One exited arm plus a following
       sequence semicolon is rejected (the live path would run the rest
       of the sequence while the exited one skipped it). *)
    (let d0 = rg r_depth in
     let ha = hole 16 in                           (* branchifnot *)
     rs r_exited 0;
     ign (re 1 env 1);
     let then_ex = rg r_exited in
     let hb = if then_ex = 0 then hole 14 else 0 - 1 in
     patch_here ha;
     rs r_depth d0;
     rs r_exited 0;
     (if kw_at 124997 (* else *) then (next_token 0; ign (re 1 env 1))
      else emit1 1 0);
     let else_ex = rg r_exited in
     (if hb >= 0 then patch_here hb);
     rs r_depth d0;
     if then_ex = 1 && else_ex = 1 then rs r_exited 1
     else
       ((if (then_ex = 1 || else_ex = 1) && t_punct 59 then
           (err_str "data-lambda: one branch of this if exits in tail position but the other falls into a sequence; parenthesize"; die 0));
        rs r_exited 0))
  else
    (let ha = hole 16 in
     ign (re 1 env 0);
     let hb = hole 14 in
     patch_here ha;
     (if kw_at 124997 then (next_token 0; ign (re 1 env 0))
      else emit1 1 0);
     patch_here hb)

let c_let = fun re -> fun env -> fun t ->
  next_token 0;
  if kw_at 2510 (* rec *) then
    (next_token 0;
     (* single self-recursive local function *)
     let name = need_ident 0 in
     let slot = rg r_depth in
     emit1 1 0;
     emitw 3;
     bump 1;
     let env2 = env_bind name (mk_res 0 slot) env in
     let pname = param_ident 0 in
     compile_fun re env2 pname 61;
     (* store the closure in its slot, then patch self captures *)
     let fidx = rg r_depth - 1 - slot in
     emit1 5 fidx;                                 (* assign *)
     let fl = rg r_lev + 1 in
     let nc = rg (r_ccount0 + fl) in
     let rec patch j =
       if j < nc then
         ((if cap_eq fl j name then
             (emit1 2 fidx;                        (* acc fidx *)
              emitw 3;                             (* push *)
              emit1 2 0;                           (* acc 0 *)
              emit1 13 (j + 1)));                  (* setfield j+1 *)
          patch (j + 1)) in
     patch 0;
     (if bnot (kw_at 401) then (err_str "data-lambda: expected in"; die 0));
     next_token 0;
     ign (re 0 env2 t);
     if t = 0 then (emit1 4 1; bump (0 - 1))
     else rs r_depth slot)
  else
    (* single non-recursive binding: a value or a function *)
    (let name = need_ident 0 in
     let start = rg r_depth in
     (if at_param 0 then
        (let pname = param_ident 0 in
         compile_fun re env pname 61)
      else
        (expect_p 61;
         ign (re 0 env 0)));
     emitw 3;
     bump 1;
     let env2 = env_bind name (mk_res 0 start) env in
     (if bnot (kw_at 401) then (err_str "data-lambda: expected in"; die 0));
     next_token 0;
     ign (re 0 env2 t);
     if t = 0 then (emit1 4 1; bump (0 - 1))
     else rs r_depth start)

(* the single recursive entry point: mode 0 = expression with sequencing,
   mode 1 = one sequence element *)
let rec cexp m = fun env -> fun t ->
  if m = 1 then
    ((if kw_at 177 (* if *) then c_if cexp env t
      else if kw_at 15832 (* let *) then c_let cexp env t
      else if kw_at 11570 (* fun *) then c_funexpr cexp env
      else c_or cexp env t);
     value_done t)
  else
    (cexp 1 env t;
     let rec seq u =
       if t_punct 59 then
         ((if rg r_exited = 1 then
             (err_str "data-lambda: tail branch followed by a sequence; parenthesize the if/let"; die 0));
          next_token 0;
          cexp 1 env t;
          seq 0) in
     seq 0)

(* ---- top level ---- *)

let rec top_loop u =
  if rg r_tk = 0 then ()
  else
    ((if bnot (kw_at 15832) then
        (err_str "data-lambda: expected a top-level let"; die 0));
     next_token 0;
     (if kw_at 2510 (* rec *) then
        (next_token 0;
         let name = need_ident 0 in
         let pname = param_ident 0 in
         let g = mark_defined name in
         compile_fun cexp genv pname 61;
         emit1 46 (gbase + g))
      else if t_punct 40 then
        (* let () = expr *)
        (next_token 0;
         expect_p 41;
         expect_p 61;
         cexp 0 genv 0)
      else
        (let name = need_ident 0 in
         let g = mark_defined name in
         (if at_param 0 then
            (let pname = param_ident 0 in
             compile_fun cexp genv pname 61)
          else
            (expect_p 61;
             cexp 0 genv 0));
         emit1 46 (gbase + g)));
     top_loop 0)

(* ---- output ---- *)

let wb = fun b -> write_byte (rg r_outh) b

let w32 = fun v ->
  wb v; wb (v / 256); wb (v / 65536); wb (v / 16777216)

let rec wseg b = fun i -> fun n ->
  if i < n then (wb (bytes_get b i); wseg b (i + 1) n)

let () =
  (if arg_count () < 2 then
     (err_str "usage: data-lambda in.ml out.mzbc";
      write_byte 2 10;
      exit 1));
  rs r_line 1;
  let h = open_in (arg_get 0) in
  (if h < 0 then (err_str "data-lambda: cannot open input"; die 0));
  read_all h;
  close_chan h;
  next_token 0;
  top_loop 0;
  check_all_defined 0;
  emit1 1 0;                                       (* const 0 *)
  emitw 0;                                         (* stop *)
  let o = open_out (arg_get 1) in
  (if o < 0 then (err_str "data-lambda: cannot open output"; die 0));
  rs r_outh o;
  wb 77; wb 90; wb 66; wb 67;                      (* M Z B C *)
  w32 1;                                           (* version *)
  w32 (rg r_clen);
  w32 12;                                          (* primcount *)
  w32 (gbase + rg r_gcount);
  w32 (rg r_datcount);
  wseg code 0 (4 * rg r_clen);
  wseg dat 0 (rg r_datlen);
  close_chan o;
  exit 0
