(* 04-pattern-compiler: ML2 -> parenthesized MZBC assembly.
   Fourth ML bootstrap stage; a fork of 03-adt-compiler whose delta makes
   patterns first-class (ML2 = ML1 + nested patterns + list sugar +
   references + tuple/let destructuring). Its own source stays within
   ML1, so stage 03 compiles it and it recompiles itself; for ML1 inputs
   that avoid the new tokens its code generation is byte-identical to
   stage 03's.

   The delta over ML1:
     - patterns nest arbitrarily: constructors, tuples, list cells,
       literals, variables and _ compose; tests jump to the next arm,
       reached values are loaded through getfield paths
     - list sugar: [] / e1 :: e2 / [e1; e2] in expressions, and the same
       forms in patterns (a cons cell is a tag-0 block, [] is 0)
     - references: ref e, !e, e1 := e2 (a one-field tag-0 block)
     - "let (p1, .., pn) = e in" destructures through full patterns
       (refutable ones exit 99, same as a fallen-through match)

   Usage: mlc-interp 04-pattern-compiler.ml in.ml out.mzs *)

(* one-slot mutable cells: ML0 has no ref type, so a one-element array
   stands in; cell/get/set keep call sites readable *)
let cell v = array_make 1 v
let get c = array_get c 0
let set c v = array_set c 0 v

(* ---- diagnostics ---- *)

let rec err_str_from s i =
  if i < string_length s then (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str s = err_str_from s 0

let rec err_bytes_from b i =
  if i < bytes_length b then (write_byte 2 (bytes_get b i); err_bytes_from b (i + 1))

let err_bytes b = err_bytes_from b 0

let rec err_int_rec n =
  if n > 9 then err_int_rec (n / 10);
  write_byte 2 (48 + n mod 10)

let err_int n = if n < 0 then (write_byte 2 45; err_int_rec (0 - n)) else err_int_rec n

let line = cell 1

let die msg =
  err_str "04-pattern-compiler: ";
  err_str msg;
  err_str " at line ";
  err_int (get line);
  write_byte 2 10;
  exit 1

let die_name msg b =
  err_str "04-pattern-compiler: ";
  err_str msg;
  err_str " ";
  err_bytes b;
  err_str " at line ";
  err_int (get line);
  write_byte 2 10;
  exit 1

(* ---- string helpers ---- *)

let bytes_eq_str b s =
  let n = string_length s in
  let rec cmp i =
    if i >= n then true
    else if bytes_get b i = string_get s i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

let bytes_eq a b =
  let n = bytes_length a in
  let rec cmp i =
    if i >= n then true
    else if bytes_get a i = bytes_get b i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

let rec bytes_blit src dst n i =
  if i < n then (bytes_set dst i (bytes_get src i); bytes_blit src dst n (i + 1))

(* ---- input ---- *)

let src_buf = cell (bytes_create 65536)
let src_len = cell 0

(* shared growable byte-buffer push over (bytes cell, length cell) *)
let push_byte bufc lenc b =
  let buf = get bufc in
  let len = get lenc in
  (if len >= bytes_length buf then
    (let nb = bytes_create (2 * bytes_length buf) in
     bytes_blit buf nb len 0;
     set bufc nb));
  bytes_set (get bufc) len b;
  set lenc (len + 1)

let src_push b = push_byte src_buf src_len b

let rec read_all h =
  let b = read_byte h in
  if b >= 0 then (src_push b; read_all h)

(* ---- scanner ---- *)

let pos = cell 0

let peekc () =
  if get pos >= get src_len then 0 - 1
  else bytes_get (get src_buf) (get pos)

let peekc2 () =
  if get pos + 1 >= get src_len then 0 - 1
  else bytes_get (get src_buf) (get pos + 1)

let peekc3 () =
  if get pos + 2 >= get src_len then 0 - 1
  else bytes_get (get src_buf) (get pos + 2)

let nextc () =
  let c = peekc () in
  set pos (get pos + 1);
  (if c = 10 then set line (get line + 1));
  c

let is_digit c = c >= 48 && c <= 57
let is_lower c = c >= 97 && c <= 122
let is_upper c = c >= 65 && c <= 90
let is_ident_start c = is_lower c || is_upper c || c = 95
let is_ident_char c = is_ident_start c || is_digit c || c = 39

(* token kinds *)
let tk_eof = 0
let tk_int = 1
let tk_str = 2
let tk_ident = 3
let tk_punct = 4

let tk = cell 0
let tint = cell 0
let tstr = cell (bytes_create 1)

let tbuf = cell (bytes_create 256)
let tlen = cell 0

let tbuf_push b = push_byte tbuf tlen b

let tbuf_take () =
  let len = get tlen in
  let out = bytes_create len in
  bytes_blit (get tbuf) out len 0;
  out

let rec skip_comment depth =
  if depth > 0 then
    (let c = nextc () in
     (if c < 0 then die "unterminated comment");
     if c = 40 && peekc () = 42 then (let _ = nextc () in skip_comment (depth + 1))
     else if c = 42 && peekc () = 41 then (let _ = nextc () in skip_comment (depth - 1))
     else skip_comment depth)

let rec skip_ws () =
  let c = peekc () in
  if c = 32 || c = 9 || c = 13 || c = 10 then (let _ = nextc () in skip_ws ())
  else if c = 40 && peekc2 () = 42 then
    (let _ = nextc () in
     let _ = nextc () in
     skip_comment 1;
     skip_ws ())

let hexval c =
  if is_digit c then c - 48
  else if c >= 97 && c <= 102 then c - 97 + 10
  else if c >= 65 && c <= 70 then c - 65 + 10
  else die "bad hex digit"

let read_escape () =
  let e = nextc () in
  if e = 110 then 10
  else if e = 116 then 9
  else if e = 114 then 13
  else if e = 92 then 92
  else if e = 39 then 39
  else if e = 34 then 34
  else if e = 120 then
    (let h1 = hexval (nextc ()) in
     let h2 = hexval (nextc ()) in
     h1 * 16 + h2)
  else die "bad escape"

(* two-character punctuation table *)
let punct2 c d =
  if c = 45 && d = 62 then "->"
  else if c = 60 && d = 62 then "<>"
  else if c = 60 && d = 61 then "<="
  else if c = 62 && d = 61 then ">="
  else if c = 38 && d = 38 then "&&"
  else if c = 124 && d = 124 then "||"
  else if c = 59 && d = 59 then ";;"
  else if c = 58 && d = 58 then "::"
  else if c = 58 && d = 61 then ":="
  else ""

let str_to_bytes s =
  let n = string_length s in
  let b = bytes_create n in
  let rec cp i = if i < n then (bytes_set b i (string_get s i); cp (i + 1)) in
  cp 0;
  b

let next_token () =
  skip_ws ();
  let c = peekc () in
  if c < 0 then set tk tk_eof
  else if is_digit c then
    (let v =
       if c = 48 && (peekc2 () = 120 || peekc2 () = 88) then
         (let _ = nextc () in
          let _ = nextc () in
          (if not (is_ident_char (peekc ())) then die "empty hex literal");
          let rec hex_loop acc =
            if is_ident_char (peekc ()) then hex_loop (acc * 16 + hexval (nextc ()))
            else acc in
          hex_loop 0)
       else
         (let rec dec_loop acc =
            if is_digit (peekc ()) then dec_loop (acc * 10 + (nextc () - 48))
            else acc in
          dec_loop 0) in
     set tint v;
     set tk tk_int)
  else if is_ident_start c then
    (set tlen 0;
     let rec id_loop () =
       if is_ident_char (peekc ()) then (tbuf_push (nextc ()); id_loop ()) in
     id_loop ();
     set tstr (tbuf_take ());
     set tk tk_ident)
  else if c = 34 then
    (let _ = nextc () in
     set tlen 0;
     let rec str_loop () =
       let d = peekc () in
       if d < 0 then die "unterminated string"
       else if d = 34 then (let _ = nextc () in ())
       else if d = 92 then (let _ = nextc () in tbuf_push (read_escape ()); str_loop ())
       else (let _ = nextc () in tbuf_push d; str_loop ()) in
     str_loop ();
     set tstr (tbuf_take ());
     set tk tk_str)
  else if c = 39 && is_ident_start (peekc2 ()) && not (peekc3 () = 39) then
    (* type variable like 'a: an identifier-shaped token kept only so
       type declarations can mention parameters; types are never checked *)
    (set tlen 0;
     tbuf_push (nextc ());
     let rec tv_loop () =
       if is_ident_char (peekc ()) then (tbuf_push (nextc ()); tv_loop ()) in
     tv_loop ();
     set tstr (tbuf_take ());
     set tk tk_ident)
  else if c = 39 then
    (let _ = nextc () in
     let d = nextc () in
     let v = if d = 92 then read_escape () else d in
     (if not (nextc () = 39) then die "unterminated char literal");
     set tint v;
     set tk tk_int)
  else
    (let _ = nextc () in
     let two = punct2 c (peekc ()) in
     if string_length two > 0 then
       (let _ = nextc () in
        set tstr (str_to_bytes two);
        set tk tk_punct)
     else
       (let b = bytes_create 1 in
        bytes_set b 0 c;
        set tstr b;
        set tk tk_punct))

let tok_is_punct s = get tk = tk_punct && bytes_eq_str (get tstr) s
let tok_is_ident s = get tk = tk_ident && bytes_eq_str (get tstr) s

let expect_punct s =
  if tok_is_punct s then next_token ()
  else die_name "expected" (str_to_bytes s)


let is_keyword b =
  bytes_eq_str b "let" || bytes_eq_str b "rec" || bytes_eq_str b "and" ||
  bytes_eq_str b "in" || bytes_eq_str b "if" || bytes_eq_str b "then" ||
  bytes_eq_str b "else" || bytes_eq_str b "fun" || bytes_eq_str b "true" ||
  bytes_eq_str b "false" || bytes_eq_str b "mod" || bytes_eq_str b "land" ||
  bytes_eq_str b "lor" || bytes_eq_str b "lxor" || bytes_eq_str b "lsl" ||
  bytes_eq_str b "lsr" || bytes_eq_str b "asr" || bytes_eq_str b "type" ||
  bytes_eq_str b "match" || bytes_eq_str b "with" || bytes_eq_str b "of"

(* current token is a usable identifier (not a keyword) *)
let at_ident () = get tk = tk_ident && not (is_keyword (get tstr))

(* take the current identifier's text and advance *)
let take_ident () =
  let b = get tstr in
  next_token ();
  b

(* skip an optional token *)
let skip_punct s = if tok_is_punct s then next_token ()
let skip_ident s = if tok_is_ident s then next_token ()

(* require an identifier and take it *)
let need_ident msg =
  (if not (at_ident ()) then die msg);
  take_ident ()

let starts_atom () =
  let k = get tk in
  if k = tk_int || k = tk_str then true
  else if k = tk_ident then
    (let b = get tstr in
     if bytes_eq_str b "true" || bytes_eq_str b "false" then true
     else not (is_keyword b))
  else tok_is_punct "(" || tok_is_punct "[" || tok_is_punct "!"

(* does the current token continue the enclosing expression as an infix
   operator (or sequence/tuple separator)? used to veto tail calls *)
let op_follows () =
  let k = get tk in
  if k = tk_punct then
    (let b = get tstr in
     bytes_eq_str b "+" || bytes_eq_str b "-" || bytes_eq_str b "*" ||
     bytes_eq_str b "/" || bytes_eq_str b "=" || bytes_eq_str b "<>" ||
     bytes_eq_str b "<" || bytes_eq_str b "<=" || bytes_eq_str b ">" ||
     bytes_eq_str b ">=" || bytes_eq_str b "&&" || bytes_eq_str b "||" ||
     bytes_eq_str b ";" || bytes_eq_str b "," || bytes_eq_str b "::" ||
     bytes_eq_str b ":=")
  else if k = tk_ident then
    (let b = get tstr in
     bytes_eq_str b "mod" || bytes_eq_str b "land" || bytes_eq_str b "lor" ||
     bytes_eq_str b "lxor" || bytes_eq_str b "lsl" || bytes_eq_str b "lsr" ||
     bytes_eq_str b "asr")
  else false

(* ---- scanner lookahead ----
   Decides whether a parenthesized expression in tail position can be
   compiled as a tail expression: scan ahead to the matching close paren
   and require that no operator, atom, or top-level comma follows (a
   trailing operator/atom means the parens are a subexpression; a
   depth-one comma means a tuple). Saves and restores the token state. *)

let sv_pos = cell 0
let sv_line = cell 0
let sv_tk = cell 0
let sv_tint = cell 0
let sv_tstr = cell (bytes_create 1)

let scan_save () =
  set sv_pos (get pos);
  set sv_line (get line);
  set sv_tk (get tk);
  set sv_tint (get tint);
  set sv_tstr (get tstr)

let scan_restore () =
  set pos (get sv_pos);
  set line (get sv_line);
  set tk (get sv_tk);
  set tint (get sv_tint);
  set tstr (get sv_tstr)

(* current token is the open paren; 1 = compile contents as tail *)
let paren_tail_closed () =
  scan_save ();
  next_token ();
  if get tk = tk_punct && bytes_eq_str (get tstr) ")" then
    (scan_restore (); 0)
  else
    (let rec scan depth tuple =
       if get tk = tk_eof then (scan_restore (); 0)
       else if tok_is_punct "(" then (next_token (); scan (depth + 1) tuple)
       else if tok_is_punct ")" then
         (if depth = 1 then
            (next_token ();
             let cont = op_follows () || starts_atom () in
             scan_restore ();
             if cont || tuple = 1 then 0 else 1)
          else (next_token (); scan (depth - 1) tuple))
       else if depth = 1 && tok_is_punct "," then (next_token (); scan depth 1)
       else (next_token (); scan depth tuple) in
     scan 1 0)

(* ---- output ---- *)

let out = cell 1

let o_byte b = write_byte (get out) b

let rec o_str_from s i =
  if i < string_length s then (o_byte (string_get s i); o_str_from s (i + 1))

let o_str s = o_str_from s 0

let rec o_int_rec n =
  if n > 9 then o_int_rec (n / 10);
  o_byte (48 + n mod 10)

let o_int n = if n < 0 then (o_byte 45; o_int_rec (0 - n)) else o_int_rec n

let e0 name = o_byte 40; o_str name; o_byte 41; o_byte 10

let e1 name a =
  o_byte 40; o_str name; o_byte 32; o_int a; o_byte 41; o_byte 10

let e2 name a b =
  o_byte 40; o_str name; o_byte 32; o_int a; o_byte 32; o_int b;
  o_byte 41; o_byte 10

let elabel l = o_byte 40; o_byte 58; o_byte 76; o_int l; o_byte 41; o_byte 10

let ebranch name l =
  o_byte 40; o_str name; o_str " :L"; o_int l; o_byte 41; o_byte 10

let eclosure l n =
  o_str "(closure :L"; o_int l; o_byte 32; o_int n; o_byte 41; o_byte 10

let edata b =
  o_str "(data \"";
  let n = bytes_length b in
  let rec wr i =
    if i < n then
      (let c = bytes_get b i in
       (if c = 34 then (o_byte 92; o_byte 34)
        else if c = 92 then (o_byte 92; o_byte 92)
        else if c = 10 then (o_byte 92; o_byte 110)
        else if c = 9 then (o_byte 92; o_byte 116)
        else if c = 13 then (o_byte 92; o_byte 114)
        else if c < 32 || c > 126 then
          (o_byte 92; o_byte 120;
           let h1 = c / 16 in
           let h2 = c mod 16 in
           o_byte (if h1 < 10 then 48 + h1 else 97 + h1 - 10);
           o_byte (if h2 < 10 then 48 + h2 else 97 + h2 - 10))
        else o_byte c);
       wr (i + 1)) in
  wr 0;
  o_str "\")";
  o_byte 10

let label_next = cell 0

let new_label () =
  let l = get label_next in
  set label_next (l + 1);
  l

(* ---- global table ---- *)

let gbase = 4096
let gnames = cell (array_make 512 (bytes_create 1))
let gdefined = cell (array_make 512 0)
let gcount = cell 0

let grow_globals () =
  let n = get gcount in
  let names = get gnames in
  if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let nd = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set nd i (array_get (get gdefined) i);
          cp (i + 1)) in
     cp 0;
     set gnames nn;
     set gdefined nd)

(* newest first so later definitions shadow earlier ones *)
let find_global name =
  let n = get gcount in
  let names = get gnames in
  let rec go i =
    if i < 0 then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i - 1) in
  go (n - 1)

let add_global name =
  grow_globals ();
  let n = get gcount in
  array_set (get gnames) n name;
  array_set (get gdefined) n 0;
  set gcount (n + 1);
  n

(* ---- builtins ---- *)

(* kinds: 0 = C primitive (idx = prim number, all args pushed)
          1 = opcode (idx = selector, last arg stays in acc)
          2 = arg_count: one unit argument, compiled but not passed
          3 = ref: one argument, wrapped in a one-field block *)
let bi_names = array_make 32 ""
let bi_kind = array_make 32 0
let bi_arity = array_make 32 0
let bi_idx = array_make 32 0
let bi_count = cell 0

let add_builtin name kind arity idx =
  let i = get bi_count in
  array_set bi_names i name;
  array_set bi_kind i kind;
  array_set bi_arity i arity;
  array_set bi_idx i idx;
  set bi_count (i + 1)

let () =
  add_builtin "exit" 0 1 0;
  add_builtin "open_in" 0 1 1;
  add_builtin "open_out" 0 1 2;
  add_builtin "close_chan" 0 1 3;
  add_builtin "read_byte" 0 1 4;
  add_builtin "write_byte" 0 2 5;
  add_builtin "bytes_create" 0 1 6;
  add_builtin "bytes_length" 0 1 7;
  add_builtin "string_length" 0 1 7;
  add_builtin "arg_count" 2 1 8;
  add_builtin "arg_get" 0 1 9;
  add_builtin "array_make" 0 2 10;
  add_builtin "bytes_of_string" 0 1 11;
  add_builtin "bytes_get" 1 2 1;
  add_builtin "string_get" 1 2 1;
  add_builtin "bytes_set" 1 3 2;
  add_builtin "array_get" 1 2 3;
  add_builtin "array_set" 1 3 4;
  add_builtin "array_length" 1 1 5;
  add_builtin "not" 1 1 6;
  add_builtin "fst" 1 1 7;
  add_builtin "snd" 1 1 8;
  add_builtin "ref" 3 1 0

let find_builtin name =
  let n = get bi_count in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq_str name (array_get bi_names i) then i
    else go (i + 1) in
  go 0

let emit_opcode_builtin sel =
  if sel = 1 then e0 "getbytes"
  else if sel = 2 then e0 "setbytes"
  else if sel = 3 then e0 "getvectitem"
  else if sel = 4 then e0 "setvectitem"
  else if sel = 5 then e0 "vectlength"
  else if sel = 6 then e0 "boolnot"
  else if sel = 7 then e1 "getfield" 0
  else if sel = 8 then e1 "getfield" 1
  else die "bad builtin selector"

(* ---- constructors ---- *)

(* a name starting with an upper-case letter is a constructor *)
let is_ctor_name b = bytes_length b > 0 && is_upper (bytes_get b 0)

let ctor_names = cell (array_make 256 (bytes_create 1))
let ctor_tag = cell (array_make 256 0)
let ctor_arity = cell (array_make 256 0)   (* 0 = constant *)
let ctor_count = cell 0

let add_ctor name tag arity =
  let n = get ctor_count in
  let names = get ctor_names in
  (if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let nt = array_make (2 * cap) 0 in
     let na = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set nt i (array_get (get ctor_tag) i);
          array_set na i (array_get (get ctor_arity) i);
          cp (i + 1)) in
     cp 0;
     set ctor_names nn;
     set ctor_tag nt;
     set ctor_arity na));
  array_set (get ctor_names) n name;
  array_set (get ctor_tag) n tag;
  array_set (get ctor_arity) n arity;
  set ctor_count (n + 1)

let find_ctor name =
  let n = get ctor_count in
  let names = get ctor_names in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i + 1) in
  go 0

(* ---- data strings ---- *)

let dcount = cell 0

let emit_string_literal b =
  let i = get dcount in
  (if i >= gbase then die "too many string literals");
  edata b;
  e1 "getglobal" i;
  set dcount (i + 1)

(* ---- local scopes, levels, captures ---- *)

let maxlev = 64
let cap_per = 64

let vnames = cell (array_make 1024 (bytes_create 1))
let vslot = cell (array_make 1024 0)
let vcount = cell 0

let grow_vars () =
  let n = get vcount in
  let names = get vnames in
  if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let ns = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set ns i (array_get (get vslot) i);
          cp (i + 1)) in
     cp 0;
     set vnames nn;
     set vslot ns)

let lev = cell 0
let lev_vbase = array_make 64 0
let lev_saved_depth = array_make 64 0
let cnames = array_make 4096 (bytes_create 1)   (* level l: slots l*64 .. *)
let ccounts = array_make 64 0
let depth = cell 0

let bind_local name slot =
  grow_vars ();
  let n = get vcount in
  array_set (get vnames) n name;
  array_set (get vslot) n slot;
  set vcount (n + 1)

(* search a level's locals; bounds [lo, hi) scanned newest first *)
let find_var_between name lo hi =
  let names = get vnames in
  let rec go i =
    if i < lo then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i - 1) in
  go (hi - 1)

let find_capture name l =
  let n = array_get ccounts l in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq name (array_get cnames (l * cap_per + i)) then i
    else go (i + 1) in
  go 0

let add_capture name l =
  let n = array_get ccounts l in
  (if n >= cap_per then die "too many captured variables");
  array_set cnames (l * cap_per + n) name;
  array_set ccounts l (n + 1);
  n

(* resolution result cells: kind 0 = stack slot, 1 = env index,
   2 = global (absolute), 3 = builtin (table index) *)
let res_kind = cell 0
let res_idx = cell 0

(* level j's local var region is vnames[vbase j .. vtop j) *)
let vtop j =
  if j + 1 <= get lev then array_get lev_vbase (j + 1)
  else get vcount

let resolve name =
  let l = get lev in
  let i = find_var_between name (array_get lev_vbase l) (get vcount) in
  if i >= 0 then
    (set res_kind 0;
     set res_idx (array_get (get vslot) i))
  else
    (let j = find_capture name l in
     if j >= 0 then (set res_kind 1; set res_idx j)
     else
       (* outer local? walk enclosing levels, threading captures inward *)
       (let rec outer j =
          if j < 0 then 0 - 1
          else if find_var_between name (array_get lev_vbase j) (vtop j) >= 0 then j
          else if find_capture name j >= 0 then j
          else outer (j - 1) in
        let j = outer (l - 1) in
        if j >= 0 then
          (let rec thread k last =
             if k <= l then
               (let e = find_capture name k in
                let e2 = if e >= 0 then e else add_capture name k in
                thread (k + 1) e2)
             else last in
           let idx = thread (j + 1) 0 in
           set res_kind 1;
           set res_idx idx)
        else
          (let g = find_global name in
           if g >= 0 then (set res_kind 2; set res_idx (gbase + g))
           else
             (let b = find_builtin name in
              if b >= 0 then (set res_kind 3; set res_idx b)
              else
                (* forward reference: assume a later top-level binding *)
                (let g2 = add_global name in
                 set res_kind 2;
                 set res_idx (gbase + g2))))))

let emit_var_load () =
  let k = get res_kind in
  let i = get res_idx in
  if k = 0 then e1 "acc" (get depth - 1 - i)
  else if k = 1 then e1 "envacc" (i + 1)
  else if k = 2 then e1 "getglobal" i
  else die "builtin used as a value"

(* ---- compiler state ---- *)

let exited = cell 0

let bump n = set depth (get depth + n)

let enter_level param =
  let l = get lev in
  (if l + 1 >= maxlev then die "functions nested too deeply");
  array_set lev_saved_depth l (get depth);
  array_set lev_vbase (l + 1) (get vcount);
  array_set ccounts (l + 1) 0;
  set lev (l + 1);
  set depth 1;
  bind_local param 0

let exit_level () =
  let l = get lev in
  set vcount (array_get lev_vbase l);
  set lev (l - 1);
  set depth (array_get lev_saved_depth (l - 1))

(* ---- patterns ----
   Patterns are the one place a small AST is built before emitting: the
   left side of "h :: t" is parsed before the :: is seen, so its tests
   must be re-rooted under field 0 of the cell. Field chains of
   constructors and tuples are PSeq/PSeqEnd lists so one declaration
   suffices (stage 03 has no mutually recursive types). *)

type pat =
  | PAny
  | PUnit
  | PVar of bytes
  | PLit of int
  | PCtor0 of int
  | PCtor of int * pat
  | PTup of pat
  | PListCell of pat * pat
  | PSeq of pat * pat
  | PSeqEnd

(* path from the match subject to the value a sub-pattern constrains *)
type ppath = PTop | PFld of int * ppath

(* ---- pattern parser ---- *)

let rec p_pat () =
  let a = p_pat_atom () in
  if tok_is_punct "::" then (next_token (); PListCell (a, p_pat ()))
  else a

(* "(" already consumed: unit, grouped pattern, or tuple *)
and p_pat_paren () =
  if tok_is_punct ")" then (next_token (); PUnit)
  else
    (let p1 = p_pat () in
     if tok_is_punct "," then
       (let rec elems () =
          if tok_is_punct "," then
            (next_token ();
             let p = p_pat () in
             PSeq (p, elems ()))
          else (expect_punct ")"; PSeqEnd) in
        PTup (PSeq (p1, elems ())))
     else (expect_punct ")"; p1))

and p_pat_atom () =
  if get tk = tk_int then
    (let k = get tint in next_token (); PLit k)
  else if tok_is_ident "true" then (next_token (); PLit 1)
  else if tok_is_ident "false" then (next_token (); PLit 0)
  else if tok_is_punct "(" then (next_token (); p_pat_paren ())
  else if tok_is_punct "[" then
    (next_token ();
     if tok_is_punct "]" then (next_token (); PLit 0)
     else
       (let rec elems () =
          let p = p_pat () in
          if tok_is_punct ";" then (next_token (); PListCell (p, elems ()))
          else (expect_punct "]"; PListCell (p, PLit 0)) in
        elems ()))
  else if at_ident () then
    (let name = take_ident () in
     if is_ctor_name name then
       (let c = find_ctor name in
        (if c < 0 then die_name "unknown constructor" name);
        let tag = array_get (get ctor_tag) c in
        let arity = array_get (get ctor_arity) c in
        if arity = 0 then PCtor0 tag
        else if arity = 1 then
          (let arg = p_pat_atom () in
           PCtor (tag, PSeq (arg, PSeqEnd)))
        else
          (expect_punct "(";
           let rec fields i =
             if i < arity then
               ((if i > 0 then expect_punct ",");
                let p = p_pat () in
                PSeq (p, fields (i + 1)))
             else (expect_punct ")"; PSeqEnd) in
           PCtor (tag, fields 0)))
     else if bytes_eq_str name "_" then PAny
     else PVar name)
  else die "expected a pattern"

(* ---- pattern emission ---- *)

let rec load_path p s0 =
  match p with
  | PTop -> e1 "acc" (get depth - 1 - s0)
  | PFld (i, parent) -> (load_path parent s0; e1 "getfield" i)

(* Pattern emission is two-phase: first every test (failures jump to ln
   with the stack untouched, so every arm starts at the same depth), then
   every variable bind. For one-level patterns the resulting code is the
   same as stage 03's. *)

let rec emit_pat_tests p ln s0 path =
  match p with
  | PAny -> ()
  | PUnit -> ()
  | PVar _ -> ()
  | PLit k ->
      load_path path s0;
      e0 "push"; bump 1;
      e1 "const" k; e0 "eq"; bump (0 - 1);
      ebranch "branchifnot" ln
  | PCtor0 v ->
      load_path path s0;
      e0 "push"; bump 1;
      e1 "const" v; e0 "eq"; bump (0 - 1);
      ebranch "branchifnot" ln
  | PCtor (tag, args) ->
      load_path path s0;
      e0 "isint";
      ebranch "branchif" ln;
      load_path path s0;
      e0 "gettag";
      e0 "push"; bump 1;
      e1 "const" tag; e0 "eq"; bump (0 - 1);
      ebranch "branchifnot" ln;
      emit_fields_tests args ln s0 path 0
  | PTup fields -> emit_fields_tests fields ln s0 path 0
  | PListCell (h, t) ->
      load_path path s0;
      e0 "isint";
      ebranch "branchif" ln;
      emit_pat_tests h ln s0 (PFld (0, path));
      emit_pat_tests t ln s0 (PFld (1, path))
  | PSeq (_, _) -> die "internal: stray field chain"
  | PSeqEnd -> die "internal: stray field end"

and emit_fields_tests f ln s0 path i =
  match f with
  | PSeqEnd -> ()
  | PSeq (p, rest) ->
      emit_pat_tests p ln s0 (PFld (i, path));
      emit_fields_tests rest ln s0 path (i + 1)
  | _ -> die "internal: malformed field chain"

let rec emit_pat_binds p s0 path =
  match p with
  | PVar name ->
      load_path path s0;
      e0 "push";
      bind_local name (get depth);
      bump 1;
      1
  | PCtor (_, args) -> emit_fields_binds args s0 path 0
  | PTup fields -> emit_fields_binds fields s0 path 0
  | PListCell (h, t) ->
      (* bind left-to-right explicitly: both sides emit code, and host
         OCaml may evaluate operator operands right-to-left *)
      (let nh = emit_pat_binds h s0 (PFld (0, path)) in
       let nt = emit_pat_binds t s0 (PFld (1, path)) in
       nh + nt)
  | _ -> 0

and emit_fields_binds f s0 path i =
  match f with
  | PSeqEnd -> 0
  | PSeq (p, rest) ->
      (let np = emit_pat_binds p s0 (PFld (i, path)) in
       let nr = emit_fields_binds rest s0 path (i + 1) in
       np + nr)
  | _ -> die "internal: malformed field chain"

let emit_pat p ln s0 path =
  emit_pat_tests p ln s0 path;
  emit_pat_binds p s0 path

(* operator tables for the binary levels *)
let cmp_op () =
  if tok_is_punct "=" then "eq"
  else if tok_is_punct "<>" then "neq"
  else if tok_is_punct "<" then "ltint"
  else if tok_is_punct "<=" then "leint"
  else if tok_is_punct ">" then "gtint"
  else if tok_is_punct ">=" then "geint"
  else ""

let add_op () =
  if tok_is_punct "+" then "addint"
  else if tok_is_punct "-" then "subint"
  else ""

let mul_op () =
  if tok_is_punct "*" then "mulint"
  else if tok_is_punct "/" then "divint"
  else if tok_is_ident "mod" then "modint"
  else if tok_is_ident "land" then "andint"
  else if tok_is_ident "lor" then "orint"
  else if tok_is_ident "lxor" then "xorint"
  else if tok_is_ident "lsl" then "lslint"
  else if tok_is_ident "lsr" then "lsrint"
  else if tok_is_ident "asr" then "asrint"
  else ""

(* ---- parser / code generator ---- *)

(* parameter lists: idents or (), filled into the caller's array (a
   fresh array per binding: nested funs parse params while outer ones
   are still compiling theirs) *)
let rec parse_params_into params np =
  if at_ident () then
    ((if np >= 32 then die "too many parameters");
     array_set params np (get tstr);
     next_token ();
     parse_params_into params (np + 1))
  else if tok_is_punct "(" then
    (next_token (); expect_punct ")";
     (if np >= 32 then die "too many parameters");
     array_set params np (str_to_bytes "_");
     parse_params_into params (np + 1))
  else np


let rec c_expr t =
  c_nosemi t;
  c_seq_rest t

and c_seq_rest t =
  if tok_is_punct ";" then
    ((if get exited = 1 then
       die "tail branch followed by a sequence; parenthesize the if/let");
     next_token ();
     c_nosemi t;
     c_seq_rest t)

and c_nosemi t =
  (if tok_is_ident "if" then c_if t
   else if tok_is_ident "let" then c_let t
   else if tok_is_ident "fun" then c_funexpr ()
   else if tok_is_ident "match" then c_match t
   else c_assign t);
  value_done t

and c_assign t =
  c_or t;
  if tok_is_punct ":=" then
    (next_token ();
     e0 "push";
     bump 1;
     c_or 0;
     e1 "setfield" 0;
     bump (0 - 1))

(* a plain value sits in acc; in tail position emit its RETURN unless an
   appterm already exited or a sequence semicolon follows *)
and value_done t =
  if t = 1 && get exited = 0 && not (tok_is_punct ";") then
    (e1 "return" (get depth);
     set exited 1)

and c_if t =
  next_token ();
  c_expr 0;
  (if not (tok_is_ident "then") then die "expected then");
  next_token ();
  if t = 1 then
    (* arms are compiled as tail expressions; an arm that exits (RETURN or
       APPTERM) needs no join, an arm that stays live joins at lb. If only
       one arm exits and a sequence semicolon follows, the live path would
       run the rest of the sequence while the exited one skipped it, so
       that combination is rejected. *)
    (let la = new_label () in
     let lb = new_label () in
     let d0 = get depth in
     ebranch "branchifnot" la;
     set exited 0;
     c_nosemi 1;
     let then_exited = get exited in
     (if then_exited = 0 then ebranch "branch" lb);
     elabel la;
     set depth d0;
     set exited 0;
     (if tok_is_ident "else" then (next_token (); c_nosemi 1)
      else e1 "const" 0);
     let else_exited = get exited in
     elabel lb;
     set depth d0;
     if then_exited = 1 && else_exited = 1 then set exited 1
     else
       ((if (then_exited = 1 || else_exited = 1) && tok_is_punct ";" then
          die "one branch of this if exits in tail position but the other falls into a sequence; parenthesize");
        set exited 0))
  else
    (let la = new_label () in
     let lb = new_label () in
     ebranch "branchifnot" la;
     c_nosemi 0;
     ebranch "branch" lb;
     elabel la;
     (if tok_is_ident "else" then (next_token (); c_nosemi 0)
      else e1 "const" 0);
     elabel lb)

and c_let t =
  next_token ();
  if tok_is_ident "rec" then
    (next_token ();
     (* single self-recursive local function *)
     let name = need_ident "let rec needs a name" in
     let slot = get depth in
     e1 "const" 0;
     e0 "push";
     bump 1;
     bind_local name slot;
     (* parameters *)
     let params = array_make 32 (bytes_create 1) in
     let nparams = parse_params_into params 0 in
     (if nparams = 0 then die "local let rec must define a function");
     expect_punct "=";
     compile_fun params nparams 0;
     (* store the closure in its slot, then patch self captures *)
     let fidx = get depth - 1 - slot in
     e1 "assign" fidx;
     let fl = get lev + 1 in
     let nc = array_get ccounts fl in
     let rec patch j =
       if j < nc then
         ((if bytes_eq name (array_get cnames (fl * cap_per + j)) then
            (e1 "acc" fidx;
             e0 "push";
             e1 "acc" 0;
             e1 "setfield" (j + 1)));
          patch (j + 1)) in
     patch 0;
     (if not (tok_is_ident "in") then die "expected in");
     next_token ();
     let v0 = get vcount - 1 in
     c_expr t;
     set vcount v0;
     if t = 0 then (e1 "pop" 1; bump (0 - 1))
     else set depth slot)
  else if tok_is_punct "(" && (let _ = next_token () in not (tok_is_punct ")")) then
    (* let (pattern) = e in body: full destructuring; refutable patterns
       exit 99 like a fallen-through match. The open paren is consumed. *)
    (let p = p_pat_paren () in
     expect_punct "=";
     c_expr 0;
     let s0 = get depth in
     e0 "push";
     bump 1;
     let v0 = get vcount in
     let lfail = new_label () in
     let lok = new_label () in
     let nbind = emit_pat p lfail s0 PTop in
     ebranch "branch" lok;
     elabel lfail;
     e1 "const" 99;
     e0 "push";
     bump 1;
     e2 "ccall" 1 0;
     bump (0 - 1);
     elabel lok;
     (if tok_is_ident "and" then die "pattern bindings cannot be in and-groups");
     (if not (tok_is_ident "in") then die "expected in");
     next_token ();
     c_expr t;
     set vcount v0;
     if t = 0 then (e1 "pop" (nbind + 1); bump (0 - (nbind + 1)))
     else set depth s0)
  else
    (* non-recursive bindings; and-group binds after all values; if the
       branch above consumed "( )" the first binding is the unit binding *)
    (let first_unit = if tok_is_punct ")" then (next_token (); 1) else 0 in
     let bnames = array_make 16 (bytes_create 1) in
     let start = get depth in
     let rec bindings n =
       ((if n >= 16 then die "too many and-bindings");
        (* binding name *)
        let name =
          if n = 0 && first_unit = 1 then str_to_bytes "_"
          else if tok_is_punct "(" then
            (next_token (); expect_punct ")"; str_to_bytes "_")
          else if at_ident () then
            take_ident ()
          else die "expected a binding name" in
        array_set bnames n name;
        (* parameters *)
        let params = array_make 32 (bytes_create 1) in
        let np = parse_params_into params 0 in
        expect_punct "=";
        (if np > 0 then compile_fun params np 0 else c_expr 0);
        e0 "push";
        bump 1;
        if tok_is_ident "and" then (next_token (); bindings (n + 1))
        else n + 1) in
     let n = bindings 0 in
     (if not (tok_is_ident "in") then die "expected in");
     next_token ();
     let v0 = get vcount in
     let rec bind_all i =
       if i < n then
         ((if not (bytes_eq_str (array_get bnames i) "_") then
            bind_local (array_get bnames i) (start + i));
          bind_all (i + 1)) in
     bind_all 0;
     c_expr t;
     set vcount v0;
     if t = 0 then (e1 "pop" n; bump (0 - n))
     else set depth start)

and c_funexpr () =
  next_token ();
  let params = array_make 32 (bytes_create 1) in
  let np = parse_params_into params 0 in
  (if np = 0 then die "fun needs parameters");
  (if not (tok_is_punct "->") then die "expected ->");
  next_token ();
  compile_fun params np 0

and compile_fun params nparams i =
  let lf = new_label () in
  let ls = new_label () in
  ebranch "branch" ls;
  elabel lf;
  let saved_exited = get exited in
  enter_level (array_get params i);
  set exited 0;
  (if i + 1 < nparams then
    (compile_fun params nparams (i + 1);
     e1 "return" (get depth))
   else
    c_expr 1);
  set exited saved_exited;
  let fl = get lev in
  exit_level ();
  elabel ls;
  (* push the captured values in the enclosing frame, then build *)
  let nc = array_get ccounts fl in
  let rec caps j =
    if j < nc then
      (resolve (array_get cnames (fl * cap_per + j));
       emit_var_load ();
       e0 "push";
       bump 1;
       caps (j + 1)) in
  caps 0;
  eclosure lf nc;
  bump (0 - nc)

and c_or t =
  c_and t;
  c_or_rest ()

and c_or_rest () =
  if tok_is_punct "||" then
    (next_token ();
     let lt = new_label () in
     let le = new_label () in
     ebranch "branchif" lt;
     c_and 0;
     ebranch "branch" le;
     elabel lt;
     e1 "const" 1;
     elabel le;
     c_or_rest ())

and c_and t =
  c_cmp t;
  c_and_rest ()

and c_and_rest () =
  if tok_is_punct "&&" then
    (next_token ();
     let lf = new_label () in
     let le = new_label () in
     ebranch "branchifnot" lf;
     c_cmp 0;
     ebranch "branch" le;
     elabel lf;
     e1 "const" 0;
     elabel le;
     c_and_rest ())

and c_cmp t = c_binop_level t cmp_op c_cons

(* e1 :: e2, right associative; a cons cell is a tag-0 two-field block *)
and c_cons t =
  c_add t;
  if tok_is_punct "::" then
    (next_token ();
     e0 "push";
     bump 1;
     c_cons 0;
     e0 "push";
     bump 1;
     e2 "makeblock" 0 2;
     bump (0 - 2))

and c_add t = c_binop_level t add_op c_mul

and c_mul t = c_binop_level t mul_op c_unary

(* one left-associative binary-operator level: opof names the opcode
   for the current token (or ""), next parses the tighter level *)
and c_binop_level t opof next =
  next t;
  c_binop_rest opof next

and c_binop_rest opof next =
  let op = opof () in
  if string_length op > 0 then
    (next_token ();
     e0 "push";
     bump 1;
     next 0;
     e0 op;
     bump (0 - 1);
     c_binop_rest opof next)

and c_unary t =
  if tok_is_punct "-" then
    (next_token ();
     e1 "const" 0;
     e0 "push";
     bump 1;
     c_unary 0;
     e0 "subint";
     bump (0 - 1))
  else c_app t

and c_app t =
  if t = 1 && tok_is_punct "(" && paren_tail_closed () = 1 then
    (* tail call through parentheses: (effects; call args) *)
    (next_token ();
     c_expr 1;
     expect_punct ")")
  else c_app_head t

and c_app_head t =
  (* head *)
  let was_builtin =
    if get tk = tk_ident &&
       not (is_keyword (get tstr)) &&
       not (tok_is_ident "true") && not (tok_is_ident "false") then
      (let name = take_ident () in
       if is_ctor_name name then (c_ctor name; 1)
       else
         (resolve name;
          if get res_kind = 3 then
            (c_builtin (get res_idx); 1)
          else (emit_var_load (); 0)))
    else (c_atom (); 0) in
  (if was_builtin = 1 && starts_atom () then
    die "builtin or constructor result cannot be applied");
  c_app_args t

and c_ctor name =
  let c = find_ctor name in
  (if c < 0 then die_name "unknown constructor" name);
  let tag = array_get (get ctor_tag) c in
  let arity = array_get (get ctor_arity) c in
  if arity = 0 then e1 "const" tag
  else if arity = 1 then
    ((if not (starts_atom ()) then die_name "constructor needs an argument" name);
     c_atom ();
     e0 "push";
     bump 1;
     e2 "makeblock" tag 1;
     bump (0 - 1))
  else
    (expect_punct "(";
     let rec fields i =
       if i < arity then
         ((if i > 0 then expect_punct ",");
          c_expr 0;
          e0 "push";
          bump 1;
          fields (i + 1)) in
     fields 0;
     expect_punct ")";
     e2 "makeblock" tag arity;
     bump (0 - arity))

and c_match t =
  next_token ();
  c_expr 0;
  (if not (tok_is_ident "with") then die "expected with");
  next_token ();
  e0 "push";
  let s0 = get depth in
  bump 1;
  skip_punct "|";
  let le = new_label () in
  let rec arms () =
    let ln = new_label () in
    let v0 = get vcount in
    let d0 = get depth in
    let p = p_pat () in
    let nbind = emit_pat p ln s0 PTop in
    (if not (tok_is_punct "->") then die "expected ->");
    next_token ();
    (if t = 1 then
      (set exited 0;
       c_expr 1;
       (if get exited = 0 then
         die "match arm did not exit in tail position; parenthesize the match"))
     else
      (c_expr 0;
       (if nbind > 0 then (e1 "pop" nbind; bump (0 - nbind)));
       ebranch "branch" le));
    elabel ln;
    set vcount v0;
    set depth d0;
    if tok_is_punct "|" then (next_token (); arms ()) in
  arms ();
  (* no arm matched *)
  e1 "const" 99;
  e0 "push";
  bump 1;
  e2 "ccall" 1 0;
  bump (0 - 1);
  elabel le;
  if t = 1 then
    (set depth s0;
     set exited 1)
  else
    (e1 "pop" 1;
     bump (0 - 1))

and c_app_args t =
  if starts_atom () then
    (e0 "push";
     bump 1;
     c_atom ();
     e0 "push";
     bump 1;
     if starts_atom () then
       (e1 "acc" 1;
        e1 "apply" 1;
        e1 "pop" 1;
        bump (0 - 2);
        c_app_args t)
     else if t = 1 && not (op_follows ()) then
       (e1 "acc" 1;
        e2 "appterm" 1 (get depth - 1);
        set exited 1;
        bump (0 - 2))
     else
       (e1 "acc" 1;
        e1 "apply" 1;
        e1 "pop" 1;
        bump (0 - 2)))

and c_builtin b =
  let kind = array_get bi_kind b in
  let arity = array_get bi_arity b in
  let prim = array_get bi_idx b in
  let rec args j =
    if j < arity then
      ((if not (starts_atom ()) then die "builtin applied to too few arguments");
       c_atom ();
       (if kind = 0 || kind = 3 || j < arity - 1 then (e0 "push"; bump 1));
       args (j + 1)) in
  args 0;
  if kind = 0 then (e2 "ccall" arity prim; bump (0 - arity))
  else if kind = 2 then e2 "ccall" 0 prim
  else if kind = 3 then (e2 "makeblock" 0 1; bump (0 - 1))
  else (emit_opcode_builtin prim; bump (0 - (arity - 1)))

and c_atom () =
  let k = get tk in
  if k = tk_int then (e1 "const" (get tint); next_token ())
  else if k = tk_str then (emit_string_literal (get tstr); next_token ())
  else if k = tk_ident then
    (if tok_is_ident "true" then (e1 "const" 1; next_token ())
     else if tok_is_ident "false" then (e1 "const" 0; next_token ())
     else if is_keyword (get tstr) then die "unexpected keyword"
     else if is_ctor_name (get tstr) then
       (let name = take_ident () in
        c_ctor name)
     else
       (let name = take_ident () in
        resolve name;
        emit_var_load ()))
  else if tok_is_punct "(" then
    (next_token ();
     if tok_is_punct ")" then (e1 "const" 0; next_token ())
     else
       (c_expr 0;
        if tok_is_punct "," then
          (let rec elems n =
             if tok_is_punct "," then
               (next_token ();
                e0 "push";
                bump 1;
                c_expr 0;
                elems (n + 1))
             else n in
           let n = elems 1 in
           e0 "push";
           bump 1;
           e2 "makeblock" 0 n;
           bump (0 - n);
           expect_punct ")")
        else expect_punct ")"))
  else if tok_is_punct "!" then
    (* dereference: ! binds to the following atom *)
    (next_token ();
     c_atom ();
     e1 "getfield" 0)
  else if tok_is_punct "[" then
    (* [e1; e2; ..]: push the elements, then fold cons cells from the
       right starting with [] = 0 in acc *)
    (next_token ();
     if tok_is_punct "]" then (e1 "const" 0; next_token ())
     else
       (let rec elems n =
          (c_nosemi 0;
           e0 "push";
           bump 1;
           if tok_is_punct ";" then (next_token (); elems (n + 1))
           else (expect_punct "]"; n + 1)) in
        let n = elems 0 in
        e1 "const" 0;
        let rec fold i =
          if i < n then
            (e0 "push";
             bump 1;
             e2 "makeblock" 0 2;
             bump (0 - 2);
             fold (i + 1)) in
        fold 0))
  else die "unexpected token"

(* ---- top level ---- *)

let mark_defined name =
  let g = find_global name in
  if g >= 0 then
    (if array_get (get gdefined) g = 1 then
       (* already defined: shadow with a fresh global *)
       (let g2 = add_global name in
        array_set (get gdefined) g2 1;
        g2)
     else
       (array_set (get gdefined) g 1;
        g))
  else
    (let g2 = add_global name in
     array_set (get gdefined) g2 1;
     g2)

let top_binding () =
  (* one binding: name params* = expr, or ()/_ = expr *)
  let is_unit =
    if tok_is_punct "(" then (next_token (); expect_punct ")"; 1)
    else if tok_is_ident "_" then (next_token (); 1)
    else 0 in
  if is_unit = 1 then
    (expect_punct "=";
     c_expr 0)
  else
    (let name = need_ident "expected a binding name" in
     let params = array_make 32 (bytes_create 1) in
     let np = parse_params_into params 0 in
     expect_punct "=";
     let g = mark_defined name in
     (if np > 0 then compile_fun params np 0 else c_expr 0);
     e1 "setglobal" (gbase + g))

let rec top_bindings () =
  top_binding ();
  if tok_is_ident "and" then (next_token (); top_bindings ())

(* a type declaration ends at the next top-level keyword *)
let at_decl_end () =
  get tk = tk_eof || tok_is_ident "let" || tok_is_ident "type" ||
  tok_is_punct ";;"

(* skip one constructor-argument type expression, counting its top-level
   components: "of int * t" has arity 2. The expression is never checked. *)
let skip_of_type () =
  let rec go arity pdepth =
    if pdepth = 0 && (at_decl_end () || tok_is_punct "|" || tok_is_ident "and") then arity
    else if tok_is_punct "(" then (next_token (); go arity (pdepth + 1))
    else if tok_is_punct ")" then (next_token (); go arity (pdepth - 1))
    else if pdepth = 0 && tok_is_punct "*" then (next_token (); go (arity + 1) pdepth)
    else (next_token (); go arity pdepth) in
  go 1 0

(* optional type parameters before the type name: 'a or ('a, 'b); the
   parameters are recorded nowhere, types are never checked *)
let skip_type_params () =
  if get tk = tk_ident && bytes_get (get tstr) 0 = 39 then
    next_token ()
  else if tok_is_punct "(" &&
          (let _ = next_token () in
           let rec skip_params () =
             if tok_is_punct ")" then (next_token (); true)
             else (next_token (); skip_params ()) in
           skip_params ()) then ()

let rec top_type () =
  (* "type" or "and" consumed; [params] name = constructors *)
  skip_type_params ();
  let _ = need_ident "expected a type name" in
  expect_punct "=";
  skip_punct "|";
  let rec ctors next_const next_block =
    ((if not (get tk = tk_ident) ||
         not (is_ctor_name (get tstr)) then
       die "expected a constructor name");
     let name = get tstr in
     (if find_ctor name >= 0 then die_name "duplicate constructor" name);
     next_token ();
     if tok_is_ident "of" then
       (next_token ();
        let arity = skip_of_type () in
        add_ctor name next_block arity;
        if tok_is_punct "|" then (next_token (); ctors next_const (next_block + 1)))
     else
       (add_ctor name next_const 0;
        if tok_is_punct "|" then (next_token (); ctors (next_const + 1) next_block))) in
  ctors 0 0;
  if tok_is_ident "and" then (next_token (); top_type ())

let rec top_loop () =
  if get tk = tk_eof then ()
  else if tok_is_punct ";;" then (next_token (); top_loop ())
  else if tok_is_ident "let" then
    (next_token ();
     skip_ident "rec";
     top_bindings ();
     top_loop ())
  else if tok_is_ident "type" then
    (next_token ();
     top_type ();
     top_loop ())
  else die "expected a top-level let"

let check_all_defined () =
  let n = get gcount in
  let rec go i =
    if i < n then
      ((if array_get (get gdefined) i = 0 then
         die_name "undefined name" (array_get (get gnames) i));
       go (i + 1)) in
  go 0

let () =
  (if arg_count () < 2 then
    (err_str "usage: 04-pattern-compiler in.ml out.mzs"; write_byte 2 10; exit 1));
  let h = open_in (arg_get 0) in
  (if h < 0 then die "cannot open input");
  read_all h;
  close_chan h;
  let o = open_out (arg_get 1) in
  (if o < 0 then die "cannot open output");
  set out o;
  set line 1;
  next_token ();
  top_loop ();
  check_all_defined ();
  e1 "const" 0;
  e0 "stop";
  e1 "globals" (gbase + get gcount);
  close_chan o;
  exit 0
