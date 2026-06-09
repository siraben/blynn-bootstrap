(* 01-parenthetical: parenthesized MZBC assembly -> .mzbc image.
   First ML bootstrap stage; runs under mlc-interp-seed. Mirrors Blynn's
   "parenthetically": a tiny parser that fully parses the next stage's
   source language (here: the assembly emitted by 02) and writes the next
   runnable artifact.

   Usage: mlc-interp 01-parenthetical.ml in.mzs out.mzbc

   Core dialect only: no ADTs, no match, no records, no refs; mutable
   state lives in 1-element arrays. The format is described at the top of
   ccc/tools/mzbc_asm.py, which must stay byte-for-byte equivalent. *)

(* ---- diagnostics ---- *)

let rec err_str_from s i =
  if i < string_length s then (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str s = err_str_from s 0

let rec err_bytes_from b i =
  if i < bytes_length b then (write_byte 2 (bytes_get b i); err_bytes_from b (i + 1))

let rec err_int_rec n =
  if n > 9 then err_int_rec (n / 10);
  write_byte 2 (48 + n mod 10)

let err_int n = if n < 0 then (write_byte 2 45; err_int_rec (0 - n)) else err_int_rec n

let line = array_make 1 1

let die msg =
  err_str "01-parenthetical: ";
  err_str msg;
  err_str " at line ";
  err_int (array_get line 0);
  write_byte 2 10;
  exit 1

(* ---- string/bytes helpers ---- *)

let bytes_eq_str b s =
  let n = string_length s in
  let rec cmp i =
    if i >= n then true
    else if bytes_get b i = string_get s i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

(* ---- input: read whole file into a growable byte buffer ---- *)

let src_buf = array_make 1 (bytes_create 65536)
let src_len = array_make 1 0

let rec bytes_blit src dst n i =
  if i < n then (bytes_set dst i (bytes_get src i); bytes_blit src dst n (i + 1))

let src_push b =
  let buf = array_get src_buf 0 in
  let len = array_get src_len 0 in
  (if len >= bytes_length buf then
    (let nb = bytes_create (2 * bytes_length buf) in
     bytes_blit buf nb len 0;
     array_set src_buf 0 nb));
  bytes_set (array_get src_buf 0) len b;
  array_set src_len 0 (len + 1)

let rec read_all h =
  let b = read_byte h in
  if b >= 0 then (src_push b; read_all h)

(* ---- scanner ---- *)

let pos = array_make 1 0

let peekc () =
  if array_get pos 0 >= array_get src_len 0 then 0 - 1
  else bytes_get (array_get src_buf 0) (array_get pos 0)

let nextc () =
  let c = peekc () in
  array_set pos 0 (array_get pos 0 + 1);
  (if c = 10 then array_set line 0 (array_get line 0 + 1));
  c

(* token kinds *)
let tk_eof = 0
let tk_lparen = 1
let tk_rparen = 2
let tk_atom = 3
let tk_int = 4
let tk_string = 5
let tk_label = 6

let tk = array_make 1 0
let tint = array_make 1 0
let tstr = array_make 1 (bytes_create 1)

(* token text accumulator *)
let tbuf = array_make 1 (bytes_create 256)
let tlen = array_make 1 0

let tbuf_push b =
  let buf = array_get tbuf 0 in
  let len = array_get tlen 0 in
  (if len >= bytes_length buf then
    (let nb = bytes_create (2 * bytes_length buf) in
     bytes_blit buf nb len 0;
     array_set tbuf 0 nb));
  bytes_set (array_get tbuf 0) len b;
  array_set tlen 0 (len + 1)

let tbuf_take () =
  let len = array_get tlen 0 in
  let out = bytes_create len in
  bytes_blit (array_get tbuf 0) out len 0;
  out

let is_ws c = c = 32 || c = 9 || c = 13 || c = 10
let is_digit c = c >= 48 && c <= 57

let rec skip_ws () =
  let c = peekc () in
  if is_ws c then (let _ = nextc () in skip_ws ())
  else if c = 59 then
    (* ; comment to end of line *)
    (let rec eat () =
       let d = peekc () in
       if d >= 0 && (not (d = 10)) then (let _ = nextc () in eat ()) in
     eat (); skip_ws ())

let hexval c =
  if is_digit c then c - 48
  else if c >= 97 && c <= 102 then c - 97 + 10
  else if c >= 65 && c <= 70 then c - 65 + 10
  else die "bad hex digit"

let read_escape () =
  let e = nextc () in
  if e = 110 then 10            (* \n *)
  else if e = 116 then 9        (* \t *)
  else if e = 114 then 13       (* \r *)
  else if e = 92 then 92        (* \\ *)
  else if e = 34 then 34        (* double quote *)
  else if e = 39 then 39        (* single quote *)
  else if e = 120 then          (* \xNN *)
    (let h1 = hexval (nextc ()) in
     let h2 = hexval (nextc ()) in
     h1 * 16 + h2)
  else die "bad escape"

let is_atom_char c =
  c >= 0 && not (is_ws c) && not (c = 40) && not (c = 41) &&
  not (c = 59) && not (c = 34)

let next_token () =
  skip_ws ();
  let c = peekc () in
  if c < 0 then array_set tk 0 tk_eof
  else if c = 40 then (let _ = nextc () in array_set tk 0 tk_lparen)
  else if c = 41 then (let _ = nextc () in array_set tk 0 tk_rparen)
  else if c = 34 then
    (* string literal *)
    (let _ = nextc () in
     array_set tlen 0 0;
     let rec str_loop () =
       let d = peekc () in
       if d < 0 then die "unterminated string"
       else if d = 34 then (let _ = nextc () in ())
       else if d = 92 then
         (let _ = nextc () in tbuf_push (read_escape ()); str_loop ())
       else (let _ = nextc () in tbuf_push d; str_loop ()) in
     str_loop ();
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_string)
  else if c = 39 then
    (* char literal 'c' *)
    (let _ = nextc () in
     let d = nextc () in
     let v = if d = 92 then read_escape () else d in
     (if not (nextc () = 39) then die "unterminated char literal");
     array_set tint 0 v;
     array_set tk 0 tk_int)
  else if c = 58 then
    (* :label *)
    (let _ = nextc () in
     array_set tlen 0 0;
     let rec lab_loop () =
       if is_atom_char (peekc ()) then (tbuf_push (nextc ()); lab_loop ()) in
     lab_loop ();
     (if array_get tlen 0 = 0 then die "empty label");
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_label)
  else if is_digit c || c = 45 then
    (* decimal or 0x hex, optionally negative *)
    (let neg = (c = 45) in
     (if neg then let _ = nextc () in ());
     (if not (is_digit (peekc ())) then die "bad number");
     let v =
       if peekc () = 48 && (let _ = nextc () in peekc () = 120 || peekc () = 88) then
         (let _ = nextc () in
          (if not (is_atom_char (peekc ())) then die "empty hex literal");
          let rec hex_loop acc =
            if is_atom_char (peekc ()) then hex_loop (acc * 16 + hexval (nextc ()))
            else acc in
          hex_loop 0)
       else
         (* note: leading 0 already consumed by the hex probe above *)
         (let rec dec_loop acc =
            if is_digit (peekc ()) then dec_loop (acc * 10 + (nextc () - 48))
            else acc in
          dec_loop 0) in
     array_set tint 0 (if neg then 0 - v else v);
     array_set tk 0 tk_int)
  else
    (let rec atom_loop () =
       if is_atom_char (peekc ()) then (tbuf_push (nextc ()); atom_loop ()) in
     array_set tlen 0 0;
     atom_loop ();
     (if array_get tlen 0 = 0 then die "unexpected character");
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_atom)

(* ---- opcode and primitive tables ---- *)

let op_names = array_make 64 ""
let op_codes = array_make 64 0
let op_nops = array_make 64 0
let op_count = array_make 1 0

let add_op name code nops =
  let i = array_get op_count 0 in
  array_set op_names i name;
  array_set op_codes i code;
  array_set op_nops i nops;
  array_set op_count 0 (i + 1)

let () =
  add_op "stop" 0 0; add_op "const" 1 1; add_op "acc" 2 1; add_op "push" 3 0;
  add_op "pop" 4 1; add_op "assign" 5 1; add_op "envacc" 6 1;
  add_op "closure" 7 2; add_op "apply" 8 1; add_op "appterm" 9 2;
  add_op "return" 10 1; add_op "makeblock" 11 2; add_op "getfield" 12 1;
  add_op "setfield" 13 1; add_op "branch" 14 1; add_op "branchif" 15 1;
  add_op "branchifnot" 16 1;
  add_op "addint" 18 0; add_op "subint" 19 0; add_op "mulint" 20 0;
  add_op "divint" 21 0; add_op "modint" 22 0; add_op "andint" 23 0;
  add_op "orint" 24 0; add_op "xorint" 25 0; add_op "lslint" 26 0;
  add_op "lsrint" 27 0; add_op "asrint" 28 0; add_op "negint" 29 0;
  add_op "boolnot" 30 0; add_op "eq" 31 0; add_op "neq" 32 0;
  add_op "ltint" 33 0; add_op "leint" 34 0; add_op "gtint" 35 0;
  add_op "geint" 36 0; add_op "ultint" 37 0; add_op "ugeint" 38 0;
  add_op "offsetint" 39 1; add_op "vectlength" 40 0; add_op "getvectitem" 41 0;
  add_op "setvectitem" 42 0; add_op "getbytes" 43 0; add_op "setbytes" 44 0;
  add_op "getglobal" 45 1; add_op "setglobal" 46 1; add_op "ccall" 47 2;
  add_op "isint" 48 0; add_op "gettag" 49 0

let op_switch = 17
let nprims = 12

let prim_names = array_make 16 ""
let prim_count = array_make 1 0

let add_prim name =
  let i = array_get prim_count 0 in
  array_set prim_names i name;
  array_set prim_count 0 (i + 1)

let () =
  add_prim "exit"; add_prim "open_in"; add_prim "open_out";
  add_prim "close_chan"; add_prim "read_byte"; add_prim "write_byte";
  add_prim "bytes_create"; add_prim "bytes_length"; add_prim "arg_count";
  add_prim "arg_get"; add_prim "array_make"; add_prim "bytes_of_string"

let find_op b =
  let n = array_get op_count 0 in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq_str b (array_get op_names i) then i
    else go (i + 1) in
  go 0

let find_prim b =
  let n = array_get prim_count 0 in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq_str b (array_get prim_names i) then i
    else go (i + 1) in
  go 0

(* ---- label table ---- *)

let lab_names = array_make 1 (array_make 256 (bytes_create 1))
let lab_addrs = array_make 1 (array_make 256 0)
let lab_count = array_make 1 0

let add_label name addr =
  let n = array_get lab_count 0 in
  let names = array_get lab_names 0 in
  (if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let na = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set na i (array_get (array_get lab_addrs 0) i);
          cp (i + 1)) in
     cp 0;
     array_set lab_names 0 nn;
     array_set lab_addrs 0 na));
  array_set (array_get lab_names 0) n name;
  array_set (array_get lab_addrs 0) n addr;
  array_set lab_count 0 (n + 1)

let bytes_eq a b =
  let n = bytes_length a in
  let rec cmp i =
    if i >= n then true
    else if bytes_get a i = bytes_get b i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

let find_label name =
  let n = array_get lab_count 0 in
  let names = array_get lab_names 0 in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i + 1) in
  go 0

(* ---- code buffer and data records ---- *)

let code_buf = array_make 1 (array_make 4096 0)
let code_len = array_make 1 0

let emit w =
  let buf = array_get code_buf 0 in
  let len = array_get code_len 0 in
  (if len >= array_length buf then
    (let nb = array_make (2 * array_length buf) 0 in
     let rec cp i = if i < len then (array_set nb i (array_get buf i); cp (i + 1)) in
     cp 0;
     array_set code_buf 0 nb));
  array_set (array_get code_buf 0) len w;
  array_set code_len 0 (len + 1)

let data_recs = array_make 1 (array_make 256 (bytes_create 1))
let data_count = array_make 1 0

let add_data b =
  let n = array_get data_count 0 in
  let recs = array_get data_recs 0 in
  (if n >= array_length recs then
    (let nr = array_make (2 * array_length recs) (bytes_create 1) in
     let rec cp i = if i < n then (array_set nr i (array_get recs i); cp (i + 1)) in
     cp 0;
     array_set data_recs 0 nr));
  array_set (array_get data_recs 0) n b;
  array_set data_count 0 (n + 1)

let globals_decl = array_make 1 (0 - 1)

(* ---- the two passes ---- *)

(* pass: 1 collects labels/data/globals and counts addresses;
   2 emits code words. addr is tracked in a cell. *)

let addr = array_make 1 0

let bump n = array_set addr 0 (array_get addr 0 + n)

(* read one operand token (already fetched into tk by caller? no: fetches).
   Returns its value; labels resolve only in pass 2 (pass 1 returns 0). *)
let read_operand pass =
  next_token ();
  let k = array_get tk 0 in
  if k = tk_int then array_get tint 0
  else if k = tk_label then
    (if pass = 1 then 0
     else
       (let i = find_label (array_get tstr 0) in
        if i < 0 then
          (err_str "01-parenthetical: undefined label ";
           err_bytes_from (array_get tstr 0) 0;
           write_byte 2 10;
           exit 1)
        else array_get (array_get lab_addrs 0) i))
  else if k = tk_atom then
    (let p = find_prim (array_get tstr 0) in
     if p < 0 then die "expected an operand" else p)
  else die "expected an operand"

let expect_rparen () =
  next_token ();
  if not (array_get tk 0 = tk_rparen) then die "expected )"

let handle_form pass =
  next_token ();
  let k = array_get tk 0 in
  if k = tk_label then
    ((if pass = 1 then add_label (array_get tstr 0) (array_get addr 0));
     expect_rparen ())
  else if k = tk_atom then
    (let name = array_get tstr 0 in
     if bytes_eq_str name "globals" then
       (let v = read_operand pass in
        array_set globals_decl 0 v;
        expect_rparen ())
     else if bytes_eq_str name "data" then
       (next_token ();
        (if not (array_get tk 0 = tk_string) then die "data needs a string");
        (if pass = 1 then add_data (array_get tstr 0));
        expect_rparen ())
     else if bytes_eq_str name "switch" then
       (let ni = read_operand pass in
        let nt = read_operand pass in
        (if pass = 2 then (emit op_switch; emit ni; emit nt));
        let rec ops i =
          if i < ni + nt then
            (let v = read_operand pass in
             (if pass = 2 then emit v);
             ops (i + 1)) in
        ops 0;
        bump (3 + ni + nt);
        expect_rparen ())
     else
       (let i = find_op name in
        (if i < 0 then
          (err_str "01-parenthetical: unknown mnemonic ";
           err_bytes_from name 0;
           write_byte 2 10;
           exit 1));
        let nops = array_get op_nops i in
        (if pass = 2 then emit (array_get op_codes i));
        let rec ops j =
          if j < nops then
            (let v = read_operand pass in
             (if pass = 2 then emit v);
             ops (j + 1)) in
        ops 0;
        bump (1 + nops);
        expect_rparen ()))
  else die "expected a mnemonic or label"

let rec run_pass pass =
  next_token ();
  let k = array_get tk 0 in
  if k = tk_eof then ()
  else if k = tk_lparen then (handle_form pass; run_pass pass)
  else die "expected ("

(* ---- output ---- *)

let out_h = array_make 1 0

let wbyte b = write_byte (array_get out_h 0) (b land 255)

let wu32 v =
  wbyte v;
  wbyte (v asr 8);
  wbyte (v asr 16);
  wbyte (v asr 24)

let () =
  (if arg_count () < 2 then
    (err_str "usage: 01-parenthetical in.mzs out.mzbc"; write_byte 2 10; exit 1));
  let h = open_in (arg_get 0) in
  (if h < 0 then die "cannot open input");
  read_all h;
  close_chan h;
  array_set line 0 1;
  array_set pos 0 0;
  array_set addr 0 0;
  run_pass 1;
  array_set line 0 1;
  array_set pos 0 0;
  array_set addr 0 0;
  run_pass 2;
  let o = open_out (arg_get 1) in
  (if o < 0 then die "cannot open output");
  array_set out_h 0 o;
  (* header *)
  wbyte 77; wbyte 90; wbyte 66; wbyte 67;   (* M Z B C *)
  wu32 1;
  wu32 (array_get code_len 0);
  wu32 nprims;
  let ndata = array_get data_count 0 in
  let nglob = if array_get globals_decl 0 < 0 then ndata else array_get globals_decl 0 in
  (if nglob < ndata then die "globals count smaller than data count");
  wu32 nglob;
  wu32 ndata;
  (* code *)
  let buf = array_get code_buf 0 in
  let n = array_get code_len 0 in
  let rec wcode i = if i < n then (wu32 (array_get buf i); wcode (i + 1)) in
  wcode 0;
  (* data *)
  let recs = array_get data_recs 0 in
  let rec wdata i =
    if i < ndata then
      (let b = array_get recs i in
       wu32 (bytes_length b);
       let rec wb j = if j < bytes_length b then (wbyte (bytes_get b j); wb (j + 1)) in
       wb 0;
       wdata (i + 1)) in
  wdata 0;
  close_chan o;
  exit 0
