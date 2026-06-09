(* 03-adt-compiler: ML1 -> parenthesized MZBC assembly.
   Third ML bootstrap stage; a fork of 02-ml0-compiler whose delta adds
   algebraic data types and shallow pattern matching to the *input*
   dialect (ML1 = ML0 + type declarations + constructors + one-level
   match). Its own source stays within ML0, so stage 02 compiles it and
   it recompiles itself; for ML0 inputs that avoid the new keywords its
   code generation is byte-identical to stage 02's.

   The delta:
     - "type t = A | B of int * int" declarations; constant constructors
       number from 0 per type, constructors with arguments take block
       tags from 0 per type (OCaml-style); type expressions after "of"
       are only counted for arity (monomorphic, no type parameters)
     - constructor expressions: A, B (e1, e2), C e
     - "match e with | p -> e | ..." with one-level patterns: integer and
       character literals, true/false, constant constructors,
       C (x, y, _), variables, and _ (nesting arrives with stage 04)
     - a fallen-through match exits with code 99

   Usage: mlc-interp 03-adt-compiler.ml in.ml out.mzs *)

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

let line = array_make 1 1

let die msg =
  err_str "03-adt-compiler: ";
  err_str msg;
  err_str " at line ";
  err_int (array_get line 0);
  write_byte 2 10;
  exit 1

let die_name msg b =
  err_str "03-adt-compiler: ";
  err_str msg;
  err_str " ";
  err_bytes b;
  err_str " at line ";
  err_int (array_get line 0);
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

let src_buf = array_make 1 (bytes_create 65536)
let src_len = array_make 1 0

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

let peekc2 () =
  if array_get pos 0 + 1 >= array_get src_len 0 then 0 - 1
  else bytes_get (array_get src_buf 0) (array_get pos 0 + 1)

let peekc3 () =
  if array_get pos 0 + 2 >= array_get src_len 0 then 0 - 1
  else bytes_get (array_get src_buf 0) (array_get pos 0 + 2)

let nextc () =
  let c = peekc () in
  array_set pos 0 (array_get pos 0 + 1);
  (if c = 10 then array_set line 0 (array_get line 0 + 1));
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

let tk = array_make 1 0
let tint = array_make 1 0
let tstr = array_make 1 (bytes_create 1)

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
  if c < 0 then array_set tk 0 tk_eof
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
     array_set tint 0 v;
     array_set tk 0 tk_int)
  else if is_ident_start c then
    (array_set tlen 0 0;
     let rec id_loop () =
       if is_ident_char (peekc ()) then (tbuf_push (nextc ()); id_loop ()) in
     id_loop ();
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_ident)
  else if c = 34 then
    (let _ = nextc () in
     array_set tlen 0 0;
     let rec str_loop () =
       let d = peekc () in
       if d < 0 then die "unterminated string"
       else if d = 34 then (let _ = nextc () in ())
       else if d = 92 then (let _ = nextc () in tbuf_push (read_escape ()); str_loop ())
       else (let _ = nextc () in tbuf_push d; str_loop ()) in
     str_loop ();
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_str)
  else if c = 39 && is_ident_start (peekc2 ()) && not (peekc3 () = 39) then
    (* type variable like 'a: an identifier-shaped token kept only so
       type declarations can mention parameters; types are never checked *)
    (array_set tlen 0 0;
     tbuf_push (nextc ());
     let rec tv_loop () =
       if is_ident_char (peekc ()) then (tbuf_push (nextc ()); tv_loop ()) in
     tv_loop ();
     array_set tstr 0 (tbuf_take ());
     array_set tk 0 tk_ident)
  else if c = 39 then
    (let _ = nextc () in
     let d = nextc () in
     let v = if d = 92 then read_escape () else d in
     (if not (nextc () = 39) then die "unterminated char literal");
     array_set tint 0 v;
     array_set tk 0 tk_int)
  else
    (let _ = nextc () in
     let two = punct2 c (peekc ()) in
     if string_length two > 0 then
       (let _ = nextc () in
        array_set tstr 0 (str_to_bytes two);
        array_set tk 0 tk_punct)
     else
       (let b = bytes_create 1 in
        bytes_set b 0 c;
        array_set tstr 0 b;
        array_set tk 0 tk_punct))

let tok_is_punct s = array_get tk 0 = tk_punct && bytes_eq_str (array_get tstr 0) s
let tok_is_ident s = array_get tk 0 = tk_ident && bytes_eq_str (array_get tstr 0) s

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

let starts_atom () =
  let k = array_get tk 0 in
  if k = tk_int || k = tk_str then true
  else if k = tk_ident then
    (let b = array_get tstr 0 in
     if bytes_eq_str b "true" || bytes_eq_str b "false" then true
     else not (is_keyword b))
  else tok_is_punct "("

(* does the current token continue the enclosing expression as an infix
   operator (or sequence/tuple separator)? used to veto tail calls *)
let op_follows () =
  let k = array_get tk 0 in
  if k = tk_punct then
    (let b = array_get tstr 0 in
     bytes_eq_str b "+" || bytes_eq_str b "-" || bytes_eq_str b "*" ||
     bytes_eq_str b "/" || bytes_eq_str b "=" || bytes_eq_str b "<>" ||
     bytes_eq_str b "<" || bytes_eq_str b "<=" || bytes_eq_str b ">" ||
     bytes_eq_str b ">=" || bytes_eq_str b "&&" || bytes_eq_str b "||" ||
     bytes_eq_str b ";" || bytes_eq_str b ",")
  else if k = tk_ident then
    (let b = array_get tstr 0 in
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

let sv_pos = array_make 1 0
let sv_line = array_make 1 0
let sv_tk = array_make 1 0
let sv_tint = array_make 1 0
let sv_tstr = array_make 1 (bytes_create 1)

let scan_save () =
  array_set sv_pos 0 (array_get pos 0);
  array_set sv_line 0 (array_get line 0);
  array_set sv_tk 0 (array_get tk 0);
  array_set sv_tint 0 (array_get tint 0);
  array_set sv_tstr 0 (array_get tstr 0)

let scan_restore () =
  array_set pos 0 (array_get sv_pos 0);
  array_set line 0 (array_get sv_line 0);
  array_set tk 0 (array_get sv_tk 0);
  array_set tint 0 (array_get sv_tint 0);
  array_set tstr 0 (array_get sv_tstr 0)

(* current token is the open paren; 1 = compile contents as tail *)
let paren_tail_closed () =
  scan_save ();
  next_token ();
  if array_get tk 0 = tk_punct && bytes_eq_str (array_get tstr 0) ")" then
    (scan_restore (); 0)
  else
    (let rec scan depth tuple =
       if array_get tk 0 = tk_eof then (scan_restore (); 0)
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

let out = array_make 1 1

let o_byte b = write_byte (array_get out 0) b

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

let label_next = array_make 1 0

let new_label () =
  let l = array_get label_next 0 in
  array_set label_next 0 (l + 1);
  l

(* ---- global table ---- *)

let gbase = 4096
let gnames = array_make 1 (array_make 512 (bytes_create 1))
let gdefined = array_make 1 (array_make 512 0)
let gcount = array_make 1 0

let grow_globals () =
  let n = array_get gcount 0 in
  let names = array_get gnames 0 in
  if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let nd = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set nd i (array_get (array_get gdefined 0) i);
          cp (i + 1)) in
     cp 0;
     array_set gnames 0 nn;
     array_set gdefined 0 nd)

(* newest first so later definitions shadow earlier ones *)
let find_global name =
  let n = array_get gcount 0 in
  let names = array_get gnames 0 in
  let rec go i =
    if i < 0 then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i - 1) in
  go (n - 1)

let add_global name =
  grow_globals ();
  let n = array_get gcount 0 in
  array_set (array_get gnames 0) n name;
  array_set (array_get gdefined 0) n 0;
  array_set gcount 0 (n + 1);
  n

(* ---- builtins ---- *)

(* kinds: 0 = C primitive (idx = prim number, all args pushed)
          1 = opcode (idx = selector, last arg stays in acc)
          2 = arg_count: one unit argument, compiled but not passed *)
let bi_names = array_make 32 ""
let bi_kind = array_make 32 0
let bi_arity = array_make 32 0
let bi_idx = array_make 32 0
let bi_count = array_make 1 0

let add_builtin name kind arity idx =
  let i = array_get bi_count 0 in
  array_set bi_names i name;
  array_set bi_kind i kind;
  array_set bi_arity i arity;
  array_set bi_idx i idx;
  array_set bi_count 0 (i + 1)

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
  add_builtin "snd" 1 1 8

let find_builtin name =
  let n = array_get bi_count 0 in
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

let ctor_names = array_make 1 (array_make 256 (bytes_create 1))
let ctor_tag = array_make 1 (array_make 256 0)
let ctor_arity = array_make 1 (array_make 256 0)   (* 0 = constant *)
let ctor_count = array_make 1 0

let add_ctor name tag arity =
  let n = array_get ctor_count 0 in
  let names = array_get ctor_names 0 in
  (if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let nt = array_make (2 * cap) 0 in
     let na = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set nt i (array_get (array_get ctor_tag 0) i);
          array_set na i (array_get (array_get ctor_arity 0) i);
          cp (i + 1)) in
     cp 0;
     array_set ctor_names 0 nn;
     array_set ctor_tag 0 nt;
     array_set ctor_arity 0 na));
  array_set (array_get ctor_names 0) n name;
  array_set (array_get ctor_tag 0) n tag;
  array_set (array_get ctor_arity 0) n arity;
  array_set ctor_count 0 (n + 1)

let find_ctor name =
  let n = array_get ctor_count 0 in
  let names = array_get ctor_names 0 in
  let rec go i =
    if i >= n then 0 - 1
    else if bytes_eq name (array_get names i) then i
    else go (i + 1) in
  go 0

(* ---- data strings ---- *)

let dcount = array_make 1 0

let emit_string_literal b =
  let i = array_get dcount 0 in
  (if i >= gbase then die "too many string literals");
  edata b;
  e1 "getglobal" i;
  array_set dcount 0 (i + 1)

(* ---- local scopes, levels, captures ---- *)

let maxlev = 64
let cap_per = 64

let vnames = array_make 1 (array_make 1024 (bytes_create 1))
let vslot = array_make 1 (array_make 1024 0)
let vcount = array_make 1 0

let grow_vars () =
  let n = array_get vcount 0 in
  let names = array_get vnames 0 in
  if n >= array_length names then
    (let cap = array_length names in
     let nn = array_make (2 * cap) (bytes_create 1) in
     let ns = array_make (2 * cap) 0 in
     let rec cp i =
       if i < n then
         (array_set nn i (array_get names i);
          array_set ns i (array_get (array_get vslot 0) i);
          cp (i + 1)) in
     cp 0;
     array_set vnames 0 nn;
     array_set vslot 0 ns)

let lev = array_make 1 0
let lev_vbase = array_make 64 0
let lev_saved_depth = array_make 64 0
let cnames = array_make 4096 (bytes_create 1)   (* level l: slots l*64 .. *)
let ccounts = array_make 64 0
let depth = array_make 1 0

let bind_local name slot =
  grow_vars ();
  let n = array_get vcount 0 in
  array_set (array_get vnames 0) n name;
  array_set (array_get vslot 0) n slot;
  array_set vcount 0 (n + 1)

(* search a level's locals; bounds [lo, hi) scanned newest first *)
let find_var_between name lo hi =
  let names = array_get vnames 0 in
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
let res_kind = array_make 1 0
let res_idx = array_make 1 0

(* level j's local var region is vnames[vbase j .. vtop j) *)
let vtop j =
  if j + 1 <= array_get lev 0 then array_get lev_vbase (j + 1)
  else array_get vcount 0

let resolve name =
  let l = array_get lev 0 in
  let i = find_var_between name (array_get lev_vbase l) (array_get vcount 0) in
  if i >= 0 then
    (array_set res_kind 0 0;
     array_set res_idx 0 (array_get (array_get vslot 0) i))
  else
    (let j = find_capture name l in
     if j >= 0 then (array_set res_kind 0 1; array_set res_idx 0 j)
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
           array_set res_kind 0 1;
           array_set res_idx 0 idx)
        else
          (let g = find_global name in
           if g >= 0 then (array_set res_kind 0 2; array_set res_idx 0 (gbase + g))
           else
             (let b = find_builtin name in
              if b >= 0 then (array_set res_kind 0 3; array_set res_idx 0 b)
              else
                (* forward reference: assume a later top-level binding *)
                (let g2 = add_global name in
                 array_set res_kind 0 2;
                 array_set res_idx 0 (gbase + g2))))))

let emit_var_load () =
  let k = array_get res_kind 0 in
  let i = array_get res_idx 0 in
  if k = 0 then e1 "acc" (array_get depth 0 - 1 - i)
  else if k = 1 then e1 "envacc" (i + 1)
  else if k = 2 then e1 "getglobal" i
  else die "builtin used as a value"

(* ---- compiler state ---- *)

let exited = array_make 1 0

let bump n = array_set depth 0 (array_get depth 0 + n)

let enter_level param =
  let l = array_get lev 0 in
  (if l + 1 >= maxlev then die "functions nested too deeply");
  array_set lev_saved_depth l (array_get depth 0);
  array_set lev_vbase (l + 1) (array_get vcount 0);
  array_set ccounts (l + 1) 0;
  array_set lev 0 (l + 1);
  array_set depth 0 1;
  bind_local param 0

let exit_level () =
  let l = array_get lev 0 in
  array_set vcount 0 (array_get lev_vbase l);
  array_set lev 0 (l - 1);
  array_set depth 0 (array_get lev_saved_depth (l - 1))

(* ---- parser / code generator ---- *)

(* parse a parameter name: ident, or () treated as "_" *)
let parse_param () =
  if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
    (let b = array_get tstr 0 in next_token (); b)
  else if tok_is_punct "(" then
    (next_token (); expect_punct ")"; str_to_bytes "_")
  else die "expected a parameter"

let rec c_expr t =
  c_nosemi t;
  c_seq_rest t

and c_seq_rest t =
  if tok_is_punct ";" then
    ((if array_get exited 0 = 1 then
       die "tail branch followed by a sequence; parenthesize the if/let");
     next_token ();
     c_nosemi t;
     c_seq_rest t)

and c_nosemi t =
  (if tok_is_ident "if" then c_if t
   else if tok_is_ident "let" then c_let t
   else if tok_is_ident "fun" then c_funexpr ()
   else if tok_is_ident "match" then c_match t
   else c_or t);
  value_done t

(* a plain value sits in acc; in tail position emit its RETURN unless an
   appterm already exited or a sequence semicolon follows *)
and value_done t =
  if t = 1 && array_get exited 0 = 0 && not (tok_is_punct ";") then
    (e1 "return" (array_get depth 0);
     array_set exited 0 1)

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
     let d0 = array_get depth 0 in
     ebranch "branchifnot" la;
     array_set exited 0 0;
     c_nosemi 1;
     let then_exited = array_get exited 0 in
     (if then_exited = 0 then ebranch "branch" lb);
     elabel la;
     array_set depth 0 d0;
     array_set exited 0 0;
     (if tok_is_ident "else" then (next_token (); c_nosemi 1)
      else e1 "const" 0);
     let else_exited = array_get exited 0 in
     elabel lb;
     array_set depth 0 d0;
     if then_exited = 1 && else_exited = 1 then array_set exited 0 1
     else
       ((if (then_exited = 1 || else_exited = 1) && tok_is_punct ";" then
          die "one branch of this if exits in tail position but the other falls into a sequence; parenthesize");
        array_set exited 0 0))
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
     let name =
       (if not (array_get tk 0 = tk_ident) || is_keyword (array_get tstr 0) then
         die "let rec needs a name");
       let b = array_get tstr 0 in
       next_token ();
       b in
     let slot = array_get depth 0 in
     e1 "const" 0;
     e0 "push";
     bump 1;
     bind_local name slot;
     (* parameters *)
     let params = array_make 32 (bytes_create 1) in
     let rec parse_params n =
       if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
         ((if n >= 32 then die "too many parameters");
          array_set params n (array_get tstr 0);
          next_token ();
          parse_params (n + 1))
       else if tok_is_punct "(" then
         (next_token (); expect_punct ")";
          (if n >= 32 then die "too many parameters");
          array_set params n (str_to_bytes "_");
          parse_params (n + 1))
       else n in
     let nparams = parse_params 0 in
     (if nparams = 0 then die "local let rec must define a function");
     expect_punct "=";
     compile_fun params nparams 0;
     (* store the closure in its slot, then patch self captures *)
     let fidx = array_get depth 0 - 1 - slot in
     e1 "assign" fidx;
     let fl = array_get lev 0 + 1 in
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
     let v0 = array_get vcount 0 - 1 in
     c_expr t;
     array_set vcount 0 v0;
     if t = 0 then (e1 "pop" 1; bump (0 - 1))
     else array_set depth 0 slot)
  else
    (* non-recursive bindings; and-group binds after all values *)
    (let bnames = array_make 16 (bytes_create 1) in
     let start = array_get depth 0 in
     let rec bindings n =
       ((if n >= 16 then die "too many and-bindings");
        (* binding name *)
        let name =
          if tok_is_punct "(" then
            (next_token (); expect_punct ")"; str_to_bytes "_")
          else if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
            (let b = array_get tstr 0 in next_token (); b)
          else die "expected a binding name" in
        array_set bnames n name;
        (* parameters *)
        let params = array_make 32 (bytes_create 1) in
        let rec parse_params np =
          if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
            ((if np >= 32 then die "too many parameters");
             array_set params np (array_get tstr 0);
             next_token ();
             parse_params (np + 1))
          else if tok_is_punct "(" then
            (next_token (); expect_punct ")";
             (if np >= 32 then die "too many parameters");
             array_set params np (str_to_bytes "_");
             parse_params (np + 1))
          else np in
        let np = parse_params 0 in
        expect_punct "=";
        (if np > 0 then compile_fun params np 0 else c_expr 0);
        e0 "push";
        bump 1;
        if tok_is_ident "and" then (next_token (); bindings (n + 1))
        else n + 1) in
     let n = bindings 0 in
     (if not (tok_is_ident "in") then die "expected in");
     next_token ();
     let v0 = array_get vcount 0 in
     let rec bind_all i =
       if i < n then
         ((if not (bytes_eq_str (array_get bnames i) "_") then
            bind_local (array_get bnames i) (start + i));
          bind_all (i + 1)) in
     bind_all 0;
     c_expr t;
     array_set vcount 0 v0;
     if t = 0 then (e1 "pop" n; bump (0 - n))
     else array_set depth 0 start)

and c_funexpr () =
  next_token ();
  let params = array_make 32 (bytes_create 1) in
  let rec parse_params np =
    if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
      ((if np >= 32 then die "too many parameters");
       array_set params np (array_get tstr 0);
       next_token ();
       parse_params (np + 1))
    else if tok_is_punct "(" then
      (next_token (); expect_punct ")";
       (if np >= 32 then die "too many parameters");
       array_set params np (str_to_bytes "_");
       parse_params (np + 1))
    else np in
  let np = parse_params 0 in
  (if np = 0 then die "fun needs parameters");
  (if not (tok_is_punct "->") then die "expected ->");
  next_token ();
  compile_fun params np 0

and compile_fun params nparams i =
  let lf = new_label () in
  let ls = new_label () in
  ebranch "branch" ls;
  elabel lf;
  let saved_exited = array_get exited 0 in
  enter_level (array_get params i);
  array_set exited 0 0;
  (if i + 1 < nparams then
    (compile_fun params nparams (i + 1);
     e1 "return" (array_get depth 0))
   else
    c_expr 1);
  array_set exited 0 saved_exited;
  let fl = array_get lev 0 in
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

and c_cmp t =
  c_add t;
  c_cmp_rest ()

and c_cmp_rest () =
  let op =
    if tok_is_punct "=" then "eq"
    else if tok_is_punct "<>" then "neq"
    else if tok_is_punct "<" then "ltint"
    else if tok_is_punct "<=" then "leint"
    else if tok_is_punct ">" then "gtint"
    else if tok_is_punct ">=" then "geint"
    else "" in
  if string_length op > 0 then
    (next_token ();
     e0 "push";
     bump 1;
     c_add 0;
     e0 op;
     bump (0 - 1);
     c_cmp_rest ())

and c_add t =
  c_mul t;
  c_add_rest ()

and c_add_rest () =
  let op =
    if tok_is_punct "+" then "addint"
    else if tok_is_punct "-" then "subint"
    else "" in
  if string_length op > 0 then
    (next_token ();
     e0 "push";
     bump 1;
     c_mul 0;
     e0 op;
     bump (0 - 1);
     c_add_rest ())

and c_mul t =
  c_unary t;
  c_mul_rest ()

and c_mul_rest () =
  let op =
    if tok_is_punct "*" then "mulint"
    else if tok_is_punct "/" then "divint"
    else if tok_is_ident "mod" then "modint"
    else if tok_is_ident "land" then "andint"
    else if tok_is_ident "lor" then "orint"
    else if tok_is_ident "lxor" then "xorint"
    else if tok_is_ident "lsl" then "lslint"
    else if tok_is_ident "lsr" then "lsrint"
    else if tok_is_ident "asr" then "asrint"
    else "" in
  if string_length op > 0 then
    (next_token ();
     e0 "push";
     bump 1;
     c_unary 0;
     e0 op;
     bump (0 - 1);
     c_mul_rest ())

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
    if array_get tk 0 = tk_ident &&
       not (is_keyword (array_get tstr 0)) &&
       not (tok_is_ident "true") && not (tok_is_ident "false") then
      (let name = array_get tstr 0 in
       next_token ();
       if is_ctor_name name then (c_ctor name; 1)
       else
         (resolve name;
          if array_get res_kind 0 = 3 then
            (c_builtin (array_get res_idx 0); 1)
          else (emit_var_load (); 0)))
    else (c_atom (); 0) in
  (if was_builtin = 1 && starts_atom () then
    die "builtin or constructor result cannot be applied");
  c_app_args t

and c_ctor name =
  let c = find_ctor name in
  (if c < 0 then die_name "unknown constructor" name);
  let tag = array_get (array_get ctor_tag 0) c in
  let arity = array_get (array_get ctor_arity 0) c in
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
  let s0 = array_get depth 0 in
  bump 1;
  (if tok_is_punct "|" then next_token ());
  let le = new_label () in
  let subj () = e1 "acc" (array_get depth 0 - 1 - s0) in
  let rec arms () =
    let ln = new_label () in
    let v0 = array_get vcount 0 in
    let d0 = array_get depth 0 in
    (* ---- one-level pattern ---- *)
    let nbind =
      if array_get tk 0 = tk_int then
        (let k = array_get tint 0 in
         next_token ();
         subj (); e0 "push"; bump 1;
         e1 "const" k; e0 "eq"; bump (0 - 1);
         ebranch "branchifnot" ln;
         0)
      else if tok_is_ident "true" || tok_is_ident "false" then
        (let k = if tok_is_ident "true" then 1 else 0 in
         next_token ();
         subj (); e0 "push"; bump 1;
         e1 "const" k; e0 "eq"; bump (0 - 1);
         ebranch "branchifnot" ln;
         0)
      else if tok_is_punct "(" then
        (next_token (); expect_punct ")"; 0)   (* unit: always matches *)
      else if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
        (let name = array_get tstr 0 in
         next_token ();
         if is_ctor_name name then
           (let c = find_ctor name in
            (if c < 0 then die_name "unknown constructor" name);
            let tag = array_get (array_get ctor_tag 0) c in
            let arity = array_get (array_get ctor_arity 0) c in
            if arity = 0 then
              (subj (); e0 "push"; bump 1;
               e1 "const" tag; e0 "eq"; bump (0 - 1);
               ebranch "branchifnot" ln;
               0)
            else
              (subj (); e0 "isint"; ebranch "branchif" ln;
               subj (); e0 "gettag"; e0 "push"; bump 1;
               e1 "const" tag; e0 "eq"; bump (0 - 1);
               ebranch "branchifnot" ln;
               (* field binders: x, _, comma-separated; arity 1 may skip
                  the parentheses *)
               let bind_field i =
                 if tok_is_ident "_" then (next_token (); 0)
                 else if array_get tk 0 = tk_ident &&
                         not (is_keyword (array_get tstr 0)) &&
                         not (is_ctor_name (array_get tstr 0)) then
                   (let v = array_get tstr 0 in
                    next_token ();
                    subj ();
                    e1 "getfield" i;
                    e0 "push";
                    bind_local v (array_get depth 0);
                    bump 1;
                    1)
                 else die "patterns are one-level: expected a variable or _" in
               if arity = 1 && not (tok_is_punct "(") then bind_field 0
               else
                 (expect_punct "(";
                  let rec fields i nb =
                    if i < arity then
                      ((if i > 0 then expect_punct ",");
                       fields (i + 1) (nb + bind_field i))
                    else nb in
                  let nb = fields 0 0 in
                  expect_punct ")";
                  nb)))
         else if bytes_eq_str name "_" then 0
         else
           (* variable pattern: always matches, binds the subject *)
           (subj ();
            e0 "push";
            bind_local name (array_get depth 0);
            bump 1;
            1))
      else die "expected a pattern" in
    (if not (tok_is_punct "->") then die "expected ->");
    next_token ();
    (if t = 1 then
      (array_set exited 0 0;
       c_expr 1;
       (if array_get exited 0 = 0 then
         die "match arm did not exit in tail position; parenthesize the match"))
     else
      (c_expr 0;
       (if nbind > 0 then (e1 "pop" nbind; bump (0 - nbind)));
       ebranch "branch" le));
    elabel ln;
    array_set vcount 0 v0;
    array_set depth 0 d0;
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
    (array_set depth 0 s0;
     array_set exited 0 1)
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
        e2 "appterm" 1 (array_get depth 0 - 1);
        array_set exited 0 1;
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
       (if kind = 0 || j < arity - 1 then (e0 "push"; bump 1));
       args (j + 1)) in
  args 0;
  if kind = 0 then (e2 "ccall" arity prim; bump (0 - arity))
  else if kind = 2 then e2 "ccall" 0 prim
  else (emit_opcode_builtin prim; bump (0 - (arity - 1)))

and c_atom () =
  let k = array_get tk 0 in
  if k = tk_int then (e1 "const" (array_get tint 0); next_token ())
  else if k = tk_str then (emit_string_literal (array_get tstr 0); next_token ())
  else if k = tk_ident then
    (if tok_is_ident "true" then (e1 "const" 1; next_token ())
     else if tok_is_ident "false" then (e1 "const" 0; next_token ())
     else if is_keyword (array_get tstr 0) then die "unexpected keyword"
     else if is_ctor_name (array_get tstr 0) then
       (let name = array_get tstr 0 in
        next_token ();
        c_ctor name)
     else
       (let name = array_get tstr 0 in
        next_token ();
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
  else die "unexpected token"

(* ---- top level ---- *)

let mark_defined name =
  let g = find_global name in
  if g >= 0 then
    (if array_get (array_get gdefined 0) g = 1 then
       (* already defined: shadow with a fresh global *)
       (let g2 = add_global name in
        array_set (array_get gdefined 0) g2 1;
        g2)
     else
       (array_set (array_get gdefined 0) g 1;
        g))
  else
    (let g2 = add_global name in
     array_set (array_get gdefined 0) g2 1;
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
    ((if not (array_get tk 0 = tk_ident) || is_keyword (array_get tstr 0) then
       die "expected a binding name");
     let name = array_get tstr 0 in
     next_token ();
     let params = array_make 32 (bytes_create 1) in
     let rec parse_params np =
       if array_get tk 0 = tk_ident && not (is_keyword (array_get tstr 0)) then
         ((if np >= 32 then die "too many parameters");
          array_set params np (array_get tstr 0);
          next_token ();
          parse_params (np + 1))
       else if tok_is_punct "(" then
         (next_token (); expect_punct ")";
          (if np >= 32 then die "too many parameters");
          array_set params np (str_to_bytes "_");
          parse_params (np + 1))
       else np in
     let np = parse_params 0 in
     expect_punct "=";
     let g = mark_defined name in
     (if np > 0 then compile_fun params np 0 else c_expr 0);
     e1 "setglobal" (gbase + g))

let rec top_bindings () =
  top_binding ();
  if tok_is_ident "and" then (next_token (); top_bindings ())

(* a type declaration ends at the next top-level keyword *)
let at_decl_end () =
  array_get tk 0 = tk_eof || tok_is_ident "let" || tok_is_ident "type" ||
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
  if array_get tk 0 = tk_ident && bytes_get (array_get tstr 0) 0 = 39 then
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
  (if not (array_get tk 0 = tk_ident) || is_keyword (array_get tstr 0) then
    die "expected a type name");
  next_token ();
  expect_punct "=";
  (if tok_is_punct "|" then next_token ());
  let rec ctors next_const next_block =
    ((if not (array_get tk 0 = tk_ident) ||
         not (is_ctor_name (array_get tstr 0)) then
       die "expected a constructor name");
     let name = array_get tstr 0 in
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
  if array_get tk 0 = tk_eof then ()
  else if tok_is_punct ";;" then (next_token (); top_loop ())
  else if tok_is_ident "let" then
    (next_token ();
     (if tok_is_ident "rec" then next_token ());
     top_bindings ();
     top_loop ())
  else if tok_is_ident "type" then
    (next_token ();
     top_type ();
     top_loop ())
  else die "expected a top-level let"

let check_all_defined () =
  let n = array_get gcount 0 in
  let rec go i =
    if i < n then
      ((if array_get (array_get gdefined 0) i = 0 then
         die_name "undefined name" (array_get (array_get gnames 0) i));
       go (i + 1)) in
  go 0

let () =
  (if arg_count () < 2 then
    (err_str "usage: 03-adt-compiler in.ml out.mzs"; write_byte 2 10; exit 1));
  let h = open_in (arg_get 0) in
  (if h < 0 then die "cannot open input");
  read_all h;
  close_chan h;
  let o = open_out (arg_get 1) in
  (if o < 0 then die "cannot open output");
  array_set out 0 o;
  array_set line 0 1;
  next_token ();
  top_loop ();
  check_all_defined ();
  e1 "const" 0;
  e0 "stop";
  e1 "globals" (gbase + array_get gcount 0);
  close_chan o;
  exit 0
