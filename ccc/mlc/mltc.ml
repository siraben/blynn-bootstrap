(* mltc: a Hindley-Milner type checker (algorithm W, let-polymorphism
   with the value restriction) for ML2, the dialect compiled by
   ccc/stages/04-pattern-compiler.ml. Written in ML2 itself, so stage 04
   compiles it and it can typecheck itself; it also typechecks as host
   OCaml when prefixed with ccc/tests/prelude-ocaml.ml.

   Usage: mltc file.ml
   Exits 0 silently when the program is well-typed; otherwise prints
   "file:line: message" to stderr and exits 1. *)

(* stage 04 has no built-in option type; declare it here (under host
   OCaml this shadows Stdlib's option, which is fine: mltc uses its own
   consistently) *)
type 'a option = None | Some of 'a

(* ---- byte/string helpers ---- *)

let rec mt_bytes_blit src dst n i =
  if i < n then (bytes_set dst i (bytes_get src i); mt_bytes_blit src dst n (i + 1))

let bytes_sub b start len =
  let out = bytes_create len in
  let rec cp i =
    if i < len then (bytes_set out i (bytes_get b (start + i)); cp (i + 1)) in
  cp 0;
  out

let bytes_eq a b =
  let n = bytes_length a in
  let rec cmp i =
    if i >= n then true
    else if bytes_get a i = bytes_get b i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

let bytes_eq_str b s =
  let n = string_length s in
  let rec cmp i =
    if i >= n then true
    else if bytes_get b i = string_get s i then cmp (i + 1)
    else false in
  if bytes_length b = n then cmp 0 else false

let str_to_bytes s =
  let n = string_length s in
  let out = bytes_create n in
  let rec cp i = if i < n then (bytes_set out i (string_get s i); cp (i + 1)) in
  cp 0;
  out

(* ---- growable byte buffers: (bytes ref, length ref) ---- *)

type buf = { mutable bdata : bytes; mutable blen : int }

let buf_new n = { bdata = bytes_create n; blen = 0 }

let buf_reserve b extra =
  if b.blen + extra > bytes_length b.bdata then
    (let rec newcap c = if c >= b.blen + extra then c else newcap (2 * c) in
     let nb = bytes_create (newcap (2 * bytes_length b.bdata)) in
     mt_bytes_blit b.bdata nb b.blen 0;
     b.bdata <- nb)

let buf_push b c =
  buf_reserve b 1;
  bytes_set b.bdata b.blen c;
  b.blen <- b.blen + 1

let buf_add_bytes b s =
  let n = bytes_length s in
  buf_reserve b n;
  let rec cp i =
    if i < n then (bytes_set b.bdata (b.blen + i) (bytes_get s i); cp (i + 1)) in
  cp 0;
  b.blen <- b.blen + n

let buf_add_str b s =
  let n = string_length s in
  buf_reserve b n;
  let rec cp i =
    if i < n then (bytes_set b.bdata (b.blen + i) (string_get s i); cp (i + 1)) in
  cp 0;
  b.blen <- b.blen + n

let buf_add_int b n =
  let rec go v =
    (if v > 9 then go (v / 10));
    buf_push b (48 + v mod 10) in
  if n < 0 then (buf_push b 45; go (0 - n)) else go n

let buf_take b = bytes_sub b.bdata 0 b.blen

(* ---- list helpers ---- *)

let rec list_rev_append a b =
  match a with
  | [] -> b
  | h :: t -> list_rev_append t (h :: b)

let list_rev l = list_rev_append l []

let rec list_length_from l n =
  match l with
  | [] -> n
  | _ :: t -> list_length_from t (n + 1)

let list_length l = list_length_from l 0

let rec list_append a b =
  match a with
  | [] -> b
  | h :: t -> h :: list_append t b

(* generic assoc lookup on bytes keys *)
let rec assoc_find name l =
  match l with
  | [] -> None
  | (k, v) :: t -> if bytes_eq k name then Some v else assoc_find name t

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

let err_nl () = write_byte 2 10

let file_str = ref ""

let err_pos ln =
  err_str !file_str;
  write_byte 2 58;
  err_int ln;
  write_byte 2 58;
  write_byte 2 32

let fail ln msg =
  err_pos ln;
  err_str msg;
  err_nl ();
  exit 1

let fail_name ln msg b =
  err_pos ln;
  err_str msg;
  write_byte 2 32;
  err_bytes b;
  err_nl ();
  exit 1

(* ---- input ---- *)

let src = ref (bytes_create 65536)
let src_len = ref 0

let src_push b =
  (if !src_len >= bytes_length !src then
    (let nb = bytes_create (2 * bytes_length !src) in
     mt_bytes_blit !src nb !src_len 0;
     src := nb));
  bytes_set !src !src_len b;
  src_len := !src_len + 1

let rec read_all h =
  let b = read_byte h in
  if b >= 0 then (src_push b; read_all h)

(* ---- scanner ---- *)

let pos = ref 0
let line = ref 1

let peekc () =
  if !pos >= !src_len then 0 - 1 else bytes_get !src !pos

let peekc2 () =
  if !pos + 1 >= !src_len then 0 - 1 else bytes_get !src (!pos + 1)

let peekc3 () =
  if !pos + 2 >= !src_len then 0 - 1 else bytes_get !src (!pos + 2)

let nextc () =
  let c = peekc () in
  pos := !pos + 1;
  (if c = 10 then line := !line + 1);
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

let tk = ref 0
let tint = ref 0
let tstr = ref (bytes_create 1)
let tline = ref 1

let tbuf = buf_new 256

let rec skip_comment depth =
  if depth > 0 then
    (let c = nextc () in
     (if c < 0 then fail !line "unterminated comment");
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
  else fail !line "bad hex digit"

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
  else fail !line "bad escape"

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
  else if c = 60 && d = 45 then "<-"
  else ""

let next_token () =
  skip_ws ();
  tline := !line;
  let c = peekc () in
  if c < 0 then tk := tk_eof
  else if is_digit c then
    (let v =
       if c = 48 && (peekc2 () = 120 || peekc2 () = 88) then
         (let _ = nextc () in
          let _ = nextc () in
          (if not (is_ident_char (peekc ())) then fail !line "empty hex literal");
          let rec hex_loop acc =
            if is_ident_char (peekc ()) then hex_loop (acc * 16 + hexval (nextc ()))
            else acc in
          hex_loop 0)
       else
         (let rec dec_loop acc =
            if is_digit (peekc ()) then dec_loop (acc * 10 + (nextc () - 48))
            else acc in
          dec_loop 0) in
     tint := v;
     tk := tk_int)
  else if is_ident_start c then
    (tbuf.blen <- 0;
     let rec id_loop () =
       if is_ident_char (peekc ()) then (buf_push tbuf (nextc ()); id_loop ()) in
     id_loop ();
     tstr := buf_take tbuf;
     tk := tk_ident)
  else if c = 34 then
    (let _ = nextc () in
     tbuf.blen <- 0;
     let rec str_loop () =
       let d = peekc () in
       if d < 0 then fail !line "unterminated string"
       else if d = 34 then (let _ = nextc () in ())
       else if d = 92 then (let _ = nextc () in buf_push tbuf (read_escape ()); str_loop ())
       else (let _ = nextc () in buf_push tbuf d; str_loop ()) in
     str_loop ();
     tstr := buf_take tbuf;
     tk := tk_str)
  else if c = 39 && is_ident_start (peekc2 ()) && not (peekc3 () = 39) then
    (* type variable like 'a *)
    (tbuf.blen <- 0;
     buf_push tbuf (nextc ());
     let rec tv_loop () =
       if is_ident_char (peekc ()) then (buf_push tbuf (nextc ()); tv_loop ()) in
     tv_loop ();
     tstr := buf_take tbuf;
     tk := tk_ident)
  else if c = 39 then
    (let _ = nextc () in
     let d = nextc () in
     let v = if d = 92 then read_escape () else d in
     (if not (nextc () = 39) then fail !line "unterminated char literal");
     tint := v;
     tk := tk_int)
  else
    (let _ = nextc () in
     let two = punct2 c (peekc ()) in
     if string_length two > 0 then
       (let _ = nextc () in
        tstr := str_to_bytes two;
        tk := tk_punct)
     else
       (let b = bytes_create 1 in
        bytes_set b 0 c;
        tstr := b;
        tk := tk_punct))

let tok_is_punct s = !tk = tk_punct && bytes_eq_str !tstr s
let tok_is_ident s = !tk = tk_ident && bytes_eq_str !tstr s

let expect_punct s =
  if tok_is_punct s then next_token ()
  else
    (err_pos !tline;
     err_str "expected ";
     err_str s;
     err_nl ();
     exit 1)

let expect_kw s =
  if tok_is_ident s then next_token ()
  else
    (err_pos !tline;
     err_str "expected ";
     err_str s;
     err_nl ();
     exit 1)

let is_keyword b =
  bytes_eq_str b "let" || bytes_eq_str b "rec" || bytes_eq_str b "and" ||
  bytes_eq_str b "in" || bytes_eq_str b "if" || bytes_eq_str b "then" ||
  bytes_eq_str b "else" || bytes_eq_str b "fun" || bytes_eq_str b "true" ||
  bytes_eq_str b "false" || bytes_eq_str b "mod" || bytes_eq_str b "land" ||
  bytes_eq_str b "lor" || bytes_eq_str b "lxor" || bytes_eq_str b "lsl" ||
  bytes_eq_str b "lsr" || bytes_eq_str b "asr" || bytes_eq_str b "type" ||
  bytes_eq_str b "match" || bytes_eq_str b "with" || bytes_eq_str b "of"

let starts_atom () =
  let k = !tk in
  if k = tk_int || k = tk_str then true
  else if k = tk_ident then
    (let b = !tstr in
     if bytes_eq_str b "true" || bytes_eq_str b "false" then true
     else not (is_keyword b))
  else tok_is_punct "(" || tok_is_punct "[" || tok_is_punct "!" ||
       tok_is_punct "{"

(* a name starting with an upper-case letter is a constructor *)
let is_ctor_name b = bytes_length b > 0 && is_upper (bytes_get b 0)

(* ---- syntax trees ---- *)

(* types: TMeta = unification variable (index into the meta store),
   TQVar = variable quantified in a scheme, TCon = named type with a
   unique declaration id (so shadowing redeclarations stay distinct) *)
type ty =
  | TMeta of int
  | TQVar of int
  | TFun of ty * ty
  | TTup of ty list
  | TCon of int * bytes * ty list

(* type expressions as written in declarations, resolved after the whole
   "and" group of type declarations is registered *)
type texpr =
  | TxVar of int * bytes
  | TxApp of int * bytes * texpr list
  | TxTup of int * texpr list

type pat =
  | PAny of int
  | PUnit of int
  | PVar of int * bytes
  | PInt of int * int
  | PBool of int * bool
  | PNil of int
  | PCons of int * pat * pat
  | PTup of int * pat list
  | PCtor of int * bytes * pat list

type expr =
  | EInt of int * int
  | EStr of int * bytes
  | EBool of int * bool
  | EUnit of int
  | EVar of int * bytes
  | ECtor of int * bytes * expr list
  | EApp of int * expr * expr
  | EFun of int * pat list * expr
  | EIf of int * expr * expr * expr option
  | EMatch of int * expr * (pat * expr) list
  | ELetAnd of int * (pat * expr) list * expr
  | ELetRec of int * bytes * expr * expr
  | ESeq of int * expr * expr
  | ETuple of int * expr list
  | ENil of int
  | ECons of int * expr * expr
  | EDeref of int * expr
  | EAssign of int * expr * expr
  | EBinop of int * int * expr * expr
  | ERecord of int * (bytes * expr) list
  | EProj of int * expr * bytes
  | ESetField of int * expr * bytes * expr

(* ---- meta variable store ---- *)

let mt_link = ref (array_make 1024 None)
let mt_level = ref (array_make 1024 0)
let mt_count = ref 0
let cur_level = ref 0

let mt_grow () =
  let cap = array_length !mt_link in
  if !mt_count >= cap then
    (let nl = array_make (2 * cap) None in
     let nv = array_make (2 * cap) 0 in
     let rec cp i =
       if i < cap then
         (array_set nl i (array_get !mt_link i);
          array_set nv i (array_get !mt_level i);
          cp (i + 1)) in
     cp 0;
     mt_link := nl;
     mt_level := nv)

let fresh_meta () =
  mt_grow ();
  let i = !mt_count in
  mt_count := i + 1;
  array_set !mt_level i !cur_level;
  array_set !mt_link i None;
  TMeta i

(* follow links with path compression *)
let rec repr t =
  match t with
  | TMeta i ->
      (match array_get !mt_link i with
       | None -> t
       | Some u ->
           (let r = repr u in
            array_set !mt_link i (Some r);
            r))
  | _ -> t

(* occurs check plus level adjustment; id < 0 means clamp-only *)
let rec occurs_adjust id lvl t ln =
  let r = repr t in
  match r with
  | TMeta j ->
      ((if j = id then fail ln "occurs check: cannot construct an infinite type");
       if array_get !mt_level j > lvl then array_set !mt_level j lvl)
  | TQVar _ -> fail ln "internal: quantified variable in unification"
  | TFun (a, b) -> (occurs_adjust id lvl a ln; occurs_adjust id lvl b ln)
  | TTup l -> occurs_adjust_list id lvl l ln
  | TCon (_, _, args) -> occurs_adjust_list id lvl args ln

and occurs_adjust_list id lvl l ln =
  match l with
  | [] -> ()
  | h :: t -> (occurs_adjust id lvl h ln; occurs_adjust_list id lvl t ln)

(* ---- type printing (for diagnostics) ---- *)

let rec ty_to_buf b t =
  let r = repr t in
  match r with
  | TMeta i -> (buf_add_str b "'_"; buf_add_int b i)
  | TQVar i -> (buf_add_str b "'g"; buf_add_int b i)
  | TFun (a, rt) ->
      (buf_push b 40; ty_to_buf b a; buf_add_str b " -> "; ty_to_buf b rt; buf_push b 41)
  | TTup l -> (buf_push b 40; ty_tuple_to_buf b l; buf_push b 41)
  | TCon (_, name, args) ->
      (match args with
       | [] -> buf_add_bytes b name
       | [a] -> (ty_to_buf b a; buf_push b 32; buf_add_bytes b name)
       | _ -> (buf_push b 40; ty_args_to_buf b args; buf_add_str b ") "; buf_add_bytes b name))

and ty_tuple_to_buf b l =
  match l with
  | [] -> ()
  | [x] -> ty_to_buf b x
  | h :: t -> (ty_to_buf b h; buf_add_str b " * "; ty_tuple_to_buf b t)

and ty_args_to_buf b l =
  match l with
  | [] -> ()
  | [x] -> ty_to_buf b x
  | h :: t -> (ty_to_buf b h; buf_add_str b ", "; ty_args_to_buf b t)

let fail_types ln t1 t2 =
  err_pos ln;
  err_str "type mismatch: ";
  let b = buf_new 64 in
  ty_to_buf b t1;
  buf_add_str b " vs ";
  ty_to_buf b t2;
  err_bytes (buf_take b);
  err_nl ();
  exit 1

(* ---- unification ---- *)

let rec unify ln x y =
  let a = repr x in
  let b = repr y in
  match (a, b) with
  | (TMeta i, TMeta j) ->
      if i = j then ()
      else
        (occurs_adjust i (array_get !mt_level i) b ln;
         array_set !mt_link i (Some b))
  | (TMeta i, _) ->
      (occurs_adjust i (array_get !mt_level i) b ln;
       array_set !mt_link i (Some b))
  | (_, TMeta j) ->
      (occurs_adjust j (array_get !mt_level j) a ln;
       array_set !mt_link j (Some a))
  | (TFun (a1, r1), TFun (a2, r2)) -> (unify ln a1 a2; unify ln r1 r2)
  | (TTup l1, TTup l2) ->
      if list_length l1 = list_length l2 then unify_list ln l1 l2
      else fail_types ln a b
  | (TCon (i1, _, x1), TCon (i2, _, x2)) ->
      if i1 = i2 then unify_list ln x1 x2 else fail_types ln a b
  | (_, _) -> fail_types ln a b

and unify_list ln l1 l2 =
  match (l1, l2) with
  | ([], []) -> ()
  | (h1 :: t1, h2 :: t2) -> (unify ln h1 h2; unify_list ln t1 t2)
  | (_, _) -> ()

(* ---- instantiation and generalization ---- *)

let rec inst_ty marr t =
  let r = repr t in
  match r with
  | TQVar k -> array_get marr k
  | TMeta _ -> r
  | TFun (a, rt) -> TFun (inst_ty marr a, inst_ty marr rt)
  | TTup l -> TTup (inst_list marr l)
  | TCon (id, name, args) -> TCon (id, name, inst_list marr args)

and inst_list marr l =
  match l with
  | [] -> []
  | h :: t -> inst_ty marr h :: inst_list marr t

let new_meta_array n =
  let marr = array_make (if n > 0 then n else 1) (TQVar 0) in
  let rec fill i = if i < n then (array_set marr i (fresh_meta ()); fill (i + 1)) in
  fill 0;
  marr

(* a scheme is (number of quantified variables, body) *)
let instantiate sch =
  let (n, body) = sch in
  if n = 0 then body
  else inst_ty (new_meta_array n) body

(* turn metas deeper than the current level into quantified variables *)
let rec gen_walk counter t =
  let r = repr t in
  match r with
  | TMeta i ->
      if array_get !mt_level i > !cur_level then
        (let k = !counter in
         counter := k + 1;
         array_set !mt_link i (Some (TQVar k)))
  | TQVar _ -> ()
  | TFun (a, b) -> (gen_walk counter a; gen_walk counter b)
  | TTup l -> gen_walk_list counter l
  | TCon (_, _, args) -> gen_walk_list counter args

and gen_walk_list counter l =
  match l with
  | [] -> ()
  | h :: t -> (gen_walk counter h; gen_walk_list counter t)

(* keep a type monomorphic: clamp its metas to the current level *)
let clamp_ty ln t = occurs_adjust (0 - 1) !cur_level t ln

let enter_level () = cur_level := !cur_level + 1
let leave_level () = cur_level := !cur_level - 1

(* ---- name tables (hash buckets of assoc lists; newest first) ---- *)

let nbuckets = 1024

let hash_bytes b =
  let n = bytes_length b in
  let rec go h i =
    if i >= n then h
    else go ((h * 33 + bytes_get b i) land 1073741823) (i + 1) in
  (go 5381 0) mod nbuckets

(* globals: name -> scheme *)
let glob_tab = ref (array_make 1024 [])

let glob_add name n t =
  let h = hash_bytes name in
  array_set !glob_tab h ((name, (n, t)) :: array_get !glob_tab h)

let glob_find name = assoc_find name (array_get !glob_tab (hash_bytes name))

(* constructors: name -> (quantified count, argument types, result type) *)
let ctor_tab = ref (array_make 1024 [])

let ctor_add name nq args res =
  let h = hash_bytes name in
  array_set !ctor_tab h ((name, (nq, args, res)) :: array_get !ctor_tab h)

let ctor_find name = assoc_find name (array_get !ctor_tab (hash_bytes name))

(* record fields: globally unique; name -> (record type, field type,
   mutable). Records are monomorphic. *)
let field_tab = ref (array_make 1024 [])

let field_add name info =
  let h = hash_bytes name in
  array_set !field_tab h ((name, info) :: array_get !field_tab h)

let field_find name = assoc_find name (array_get !field_tab (hash_bytes name))

(* record type name -> ordered (field, type, mutable) list, for checking
   literals for completeness and declaration order *)
let recfields_tab = ref (array_make 1024 [])

let recfields_add name fields =
  let h = hash_bytes name in
  array_set !recfields_tab h ((name, fields) :: array_get !recfields_tab h)

let recfields_find name = assoc_find name (array_get !recfields_tab (hash_bytes name))

(* type names: name -> (unique id, arity) *)
let type_tab = ref (array_make 1024 [])

let type_add name id arity =
  let h = hash_bytes name in
  array_set !type_tab h ((name, (id, arity)) :: array_get !type_tab h)

let type_find name = assoc_find name (array_get !type_tab (hash_bytes name))

let type_next_id = ref 10

let fresh_type_id () =
  let i = !type_next_id in
  type_next_id := i + 1;
  i

(* ---- primitive types and builtin signatures ---- *)

let t_int = TCon (1, str_to_bytes "int", [])
let t_bool = TCon (2, str_to_bytes "bool", [])
let t_unit = TCon (3, str_to_bytes "unit", [])
let t_string = TCon (4, str_to_bytes "string", [])
let t_bytes = TCon (5, str_to_bytes "bytes", [])
let t_list a = TCon (6, str_to_bytes "list", [a])
let t_ref a = TCon (7, str_to_bytes "ref", [a])
let t_array a = TCon (8, str_to_bytes "array", [a])
let t_option a = TCon (9, str_to_bytes "option", [a])

let init_builtins () =
  type_add (str_to_bytes "int") 1 0;
  type_add (str_to_bytes "bool") 2 0;
  type_add (str_to_bytes "unit") 3 0;
  type_add (str_to_bytes "string") 4 0;
  type_add (str_to_bytes "bytes") 5 0;
  type_add (str_to_bytes "list") 6 1;
  type_add (str_to_bytes "ref") 7 1;
  type_add (str_to_bytes "array") 8 1;
  type_add (str_to_bytes "option") 9 1;
  ctor_add (str_to_bytes "None") 1 [] (t_option (TQVar 0));
  ctor_add (str_to_bytes "Some") 1 [TQVar 0] (t_option (TQVar 0));
  glob_add (str_to_bytes "write_byte") 0 (TFun (t_int, TFun (t_int, t_unit)));
  glob_add (str_to_bytes "read_byte") 0 (TFun (t_int, t_int));
  glob_add (str_to_bytes "open_in") 0 (TFun (t_string, t_int));
  glob_add (str_to_bytes "open_out") 0 (TFun (t_string, t_int));
  glob_add (str_to_bytes "close_chan") 0 (TFun (t_int, t_unit));
  glob_add (str_to_bytes "bytes_create") 0 (TFun (t_int, t_bytes));
  glob_add (str_to_bytes "bytes_length") 0 (TFun (t_bytes, t_int));
  glob_add (str_to_bytes "bytes_get") 0 (TFun (t_bytes, TFun (t_int, t_int)));
  glob_add (str_to_bytes "bytes_set") 0
    (TFun (t_bytes, TFun (t_int, TFun (t_int, t_unit))));
  glob_add (str_to_bytes "bytes_of_string") 0 (TFun (t_string, t_bytes));
  glob_add (str_to_bytes "bytes_to_string") 0 (TFun (t_bytes, t_string));
  glob_add (str_to_bytes "string_length") 0 (TFun (t_string, t_int));
  glob_add (str_to_bytes "string_get") 0 (TFun (t_string, TFun (t_int, t_int)));
  glob_add (str_to_bytes "array_make") 1
    (TFun (t_int, TFun (TQVar 0, t_array (TQVar 0))));
  glob_add (str_to_bytes "array_get") 1
    (TFun (t_array (TQVar 0), TFun (t_int, TQVar 0)));
  glob_add (str_to_bytes "array_set") 1
    (TFun (t_array (TQVar 0), TFun (t_int, TFun (TQVar 0, t_unit))));
  glob_add (str_to_bytes "array_length") 1 (TFun (t_array (TQVar 0), t_int));
  glob_add (str_to_bytes "arg_count") 0 (TFun (t_unit, t_int));
  glob_add (str_to_bytes "arg_get") 0 (TFun (t_int, t_string));
  glob_add (str_to_bytes "exit") 1 (TFun (t_int, TQVar 0));
  glob_add (str_to_bytes "fst") 2 (TFun (TTup [TQVar 0; TQVar 1], TQVar 0));
  glob_add (str_to_bytes "snd") 2 (TFun (TTup [TQVar 0; TQVar 1], TQVar 1));
  glob_add (str_to_bytes "not") 0 (TFun (t_bool, t_bool));
  glob_add (str_to_bytes "ref") 1 (TFun (TQVar 0, t_ref (TQVar 0)))

(* ---- pattern parser ---- *)

let pat_line p =
  match p with
  | PAny ln -> ln
  | PUnit ln -> ln
  | PVar (ln, _) -> ln
  | PInt (ln, _) -> ln
  | PBool (ln, _) -> ln
  | PNil ln -> ln
  | PCons (ln, _, _) -> ln
  | PTup (ln, _) -> ln
  | PCtor (ln, _, _) -> ln

let rec p_pat () =
  let a = p_pat_atom () in
  if tok_is_punct "::" then
    (let ln = !tline in
     next_token ();
     PCons (ln, a, p_pat ()))
  else a

(* "(" already consumed: unit, grouped pattern, or tuple *)
and p_pat_paren () =
  if tok_is_punct ")" then
    (let ln = !tline in
     next_token ();
     PUnit ln)
  else
    (let p1 = p_pat () in
     if tok_is_punct "," then
       (let ln = !tline in
        let rec elems acc =
          if tok_is_punct "," then
            (next_token ();
             let p = p_pat () in
             elems (p :: acc))
          else (expect_punct ")"; list_rev acc) in
        PTup (ln, p1 :: elems []))
     else (expect_punct ")"; p1))

and p_pat_atom () =
  if !tk = tk_int then
    (let ln = !tline in
     let v = !tint in
     next_token ();
     PInt (ln, v))
  else if tok_is_ident "true" then (let ln = !tline in next_token (); PBool (ln, true))
  else if tok_is_ident "false" then (let ln = !tline in next_token (); PBool (ln, false))
  else if tok_is_punct "(" then (next_token (); p_pat_paren ())
  else if tok_is_punct "[" then
    (let ln = !tline in
     next_token ();
     if tok_is_punct "]" then (next_token (); PNil ln)
     else
       (let rec elems () =
          let p = p_pat () in
          let l2 = !tline in
          if tok_is_punct ";" then (next_token (); PCons (l2, p, elems ()))
          else (expect_punct "]"; PCons (l2, p, PNil l2)) in
        elems ()))
  else if !tk = tk_ident && not (is_keyword !tstr) then
    (let ln = !tline in
     let name = !tstr in
     next_token ();
     if is_ctor_name name then
       (match ctor_find name with
        | None -> fail_name ln "unknown constructor" name
        | Some info ->
            (let (_, argtys, _) = info in
             let arity = list_length argtys in
             if arity = 0 then PCtor (ln, name, [])
             else if arity = 1 then
               (let arg = p_pat_atom () in
                PCtor (ln, name, [arg]))
             else
               (expect_punct "(";
                let rec fields i acc =
                  if i < arity then
                    ((if i > 0 then expect_punct ",");
                     let p = p_pat () in
                     fields (i + 1) (p :: acc))
                  else (expect_punct ")"; list_rev acc) in
                PCtor (ln, name, fields 0 []))))
     else if bytes_eq_str name "_" then PAny ln
     else PVar (ln, name))
  else fail !tline "expected a pattern"

(* ---- type expression parser ---- *)

let rec p_tx_postfix () =
  let base =
    if tok_is_punct "(" then
      (next_token ();
       let t1 = p_tx_full () in
       if tok_is_punct "," then
         (let rec elems acc =
            if tok_is_punct "," then
              (next_token ();
               let t = p_tx_full () in
               elems (t :: acc))
            else (expect_punct ")"; list_rev acc) in
          let args = t1 :: elems [] in
          let ln = !tline in
          if !tk = tk_ident && not (is_keyword !tstr) && is_lower (bytes_get !tstr 0) then
            (let name = !tstr in
             next_token ();
             TxApp (ln, name, args))
          else fail ln "expected a type name")
       else (expect_punct ")"; t1))
    else if !tk = tk_ident && bytes_get !tstr 0 = 39 then
      (let ln = !tline in
       let name = !tstr in
       next_token ();
       TxVar (ln, name))
    else if !tk = tk_ident && not (is_keyword !tstr) && is_lower (bytes_get !tstr 0) then
      (let ln = !tline in
       let name = !tstr in
       next_token ();
       TxApp (ln, name, []))
    else fail !tline "expected a type" in
  p_tx_loop base

and p_tx_loop t =
  if !tk = tk_ident && not (is_keyword !tstr) && is_lower (bytes_get !tstr 0) then
    (let ln = !tline in
     let name = !tstr in
     next_token ();
     p_tx_loop (TxApp (ln, name, [t])))
  else t

and p_tx_full () =
  let c1 = p_tx_postfix () in
  if tok_is_punct "*" then
    (let ln = !tline in
     let rec comps acc =
       if tok_is_punct "*" then
         (next_token ();
          let c = p_tx_postfix () in
          comps (c :: acc))
       else list_rev acc in
     TxTup (ln, c1 :: comps []))
  else c1

(* constructor argument list: components split on top-level "*" *)
let rec p_of_type () =
  let c = p_tx_postfix () in
  if tok_is_punct "*" then (next_token (); c :: p_of_type ())
  else [c]

(* resolve a parsed type expression; params maps 'a names to TQVar slots *)
let rec tx_to_ty params tx =
  match tx with
  | TxVar (ln, b) ->
      (match assoc_find b params with
       | Some i -> TQVar i
       | None -> fail_name ln "unbound type parameter" b)
  | TxApp (ln, name, args) ->
      (match type_find name with
       | None -> fail_name ln "unknown type" name
       | Some info ->
           (let (id, arity) = info in
            (if not (list_length args = arity) then
              fail_name ln "wrong number of type arguments for" name);
            TCon (id, name, tx_to_ty_list params args)))
  | TxTup (_, l) -> TTup (tx_to_ty_list params l)

and tx_to_ty_list params l =
  match l with
  | [] -> []
  | h :: t -> tx_to_ty params h :: tx_to_ty_list params t

(* ---- expression parser ---- *)

(* binary operator codes: 1 + | 2 - | 3 * | 4 / | 5 mod | 6 land | 7 lor
   | 8 lxor | 9 lsl | 10 lsr | 11 asr | 20 = | 21 <> | 22 < | 23 <=
   | 24 > | 25 >= | 30 && | 31 || *)

let rec p_expr () =
  let a = p_nosemi () in
  p_seq_rest a

and p_seq_rest a =
  if tok_is_punct ";" then
    (let ln = !tline in
     next_token ();
     let b = p_nosemi () in
     p_seq_rest (ESeq (ln, a, b)))
  else a

and p_nosemi () =
  if tok_is_ident "if" then p_if ()
  else if tok_is_ident "let" then p_let ()
  else if tok_is_ident "fun" then p_fun ()
  else if tok_is_ident "match" then p_match ()
  else p_assign ()

and p_assign () =
  let a = p_or () in
  if tok_is_punct ":=" then
    (let ln = !tline in
     next_token ();
     let b = p_or () in
     EAssign (ln, a, b))
  else if tok_is_punct "<-" then
    (let ln = !tline in
     next_token ();
     let b = p_or () in
     match a with
     | EProj (_, e, f) -> ESetField (ln, e, f, b)
     | _ -> fail ln "left-hand side of <- must be a record field")
  else a

and p_or () = p_or_rest (p_and ())

and p_or_rest a =
  if tok_is_punct "||" then
    (let ln = !tline in
     next_token ();
     let b = p_and () in
     p_or_rest (EBinop (ln, 31, a, b)))
  else a

and p_and () = p_and_rest (p_cmp ())

and p_and_rest a =
  if tok_is_punct "&&" then
    (let ln = !tline in
     next_token ();
     let b = p_cmp () in
     p_and_rest (EBinop (ln, 30, a, b)))
  else a

and p_cmp () = p_cmp_rest (p_cons ())

and p_cmp_rest a =
  let code =
    if tok_is_punct "=" then 20
    else if tok_is_punct "<>" then 21
    else if tok_is_punct "<" then 22
    else if tok_is_punct "<=" then 23
    else if tok_is_punct ">" then 24
    else if tok_is_punct ">=" then 25
    else 0 in
  if code > 0 then
    (let ln = !tline in
     next_token ();
     let b = p_cons () in
     p_cmp_rest (EBinop (ln, code, a, b)))
  else a

and p_cons () =
  let a = p_add () in
  if tok_is_punct "::" then
    (let ln = !tline in
     next_token ();
     let b = p_cons () in
     ECons (ln, a, b))
  else a

and p_add () = p_add_rest (p_mul ())

and p_add_rest a =
  let code =
    if tok_is_punct "+" then 1
    else if tok_is_punct "-" then 2
    else 0 in
  if code > 0 then
    (let ln = !tline in
     next_token ();
     let b = p_mul () in
     p_add_rest (EBinop (ln, code, a, b)))
  else a

and p_mul () = p_mul_rest (p_unary ())

and p_mul_rest a =
  let code =
    if tok_is_punct "*" then 3
    else if tok_is_punct "/" then 4
    else if tok_is_ident "mod" then 5
    else if tok_is_ident "land" then 6
    else if tok_is_ident "lor" then 7
    else if tok_is_ident "lxor" then 8
    else if tok_is_ident "lsl" then 9
    else if tok_is_ident "lsr" then 10
    else if tok_is_ident "asr" then 11
    else 0 in
  if code > 0 then
    (let ln = !tline in
     next_token ();
     let b = p_unary () in
     p_mul_rest (EBinop (ln, code, a, b)))
  else a

and p_unary () =
  if tok_is_punct "-" then
    (let ln = !tline in
     next_token ();
     let a = p_unary () in
     EBinop (ln, 2, EInt (ln, 0), a))
  else p_app ()

and p_app () = p_app_args (p_app_head ())

and p_app_args h =
  if starts_atom () then
    (let ln = !tline in
     let a = p_postfix (p_atom ()) in
     p_app_args (EApp (ln, h, a)))
  else h

and p_app_head () =
  if !tk = tk_ident && not (is_keyword !tstr) &&
     not (tok_is_ident "true") && not (tok_is_ident "false") then
    (let ln = !tline in
     let name = !tstr in
     next_token ();
     if is_ctor_name name then p_ctor ln name
     else p_postfix (EVar (ln, name)))
  else p_postfix (p_atom ())

(* .field projection chains bind tighter than application *)
and p_postfix a =
  if tok_is_punct "." then
    (let ln = !tline in
     next_token ();
     ((if not (!tk = tk_ident) || is_keyword !tstr then
        fail !tline "expected a field name");
      let f = !tstr in
      next_token ();
      p_postfix (EProj (ln, a, f))))
  else a

and p_ctor ln name =
  match ctor_find name with
  | None -> fail_name ln "unknown constructor" name
  | Some info ->
      (let (_, argtys, _) = info in
       let arity = list_length argtys in
       if arity = 0 then ECtor (ln, name, [])
       else if arity = 1 then
         ((if not (starts_atom ()) then
            fail_name ln "constructor needs an argument:" name);
          let arg = p_atom () in
          ECtor (ln, name, [arg]))
       else
         ((if not (tok_is_punct "(") then
            fail_name ln "wrong number of constructor arguments for" name);
          next_token ();
          let rec fields i acc =
            if i < arity then
              ((if i > 0 then expect_punct ",");
               let e = p_expr () in
               fields (i + 1) (e :: acc))
            else (expect_punct ")"; list_rev acc) in
          ECtor (ln, name, fields 0 [])))

and p_if () =
  let ln = !tline in
  next_token ();
  let c = p_expr () in
  expect_kw "then";
  let a = p_nosemi () in
  if tok_is_ident "else" then
    (next_token ();
     let b = p_nosemi () in
     EIf (ln, c, a, Some b))
  else EIf (ln, c, a, None)

and p_match () =
  let ln = !tline in
  next_token ();
  let subj = p_expr () in
  expect_kw "with";
  (if tok_is_punct "|" then next_token ());
  let arms = p_match_arms () in
  EMatch (ln, subj, arms)

and p_match_arms () =
  let p = p_pat () in
  (if not (tok_is_punct "->") then fail !tline "expected ->");
  next_token ();
  let body = p_expr () in
  if tok_is_punct "|" then (next_token (); (p, body) :: p_match_arms ())
  else [(p, body)]

and p_fun () =
  let ln = !tline in
  next_token ();
  let params = p_params [] in
  (if list_length params = 0 then fail ln "fun needs parameters");
  (if not (tok_is_punct "->") then fail !tline "expected ->");
  next_token ();
  let body = p_expr () in
  EFun (ln, params, body)

and p_params acc =
  if !tk = tk_ident && not (is_keyword !tstr) then
    (let ln = !tline in
     let name = !tstr in
     next_token ();
     let p = if bytes_eq_str name "_" then PAny ln else PVar (ln, name) in
     p_params (p :: acc))
  else if tok_is_punct "(" then
    (let ln = !tline in
     next_token ();
     expect_punct ")";
     p_params (PUnit ln :: acc))
  else list_rev acc

and p_let_binder () =
  if tok_is_punct "(" then
    (let ln = !tline in
     next_token ();
     expect_punct ")";
     PUnit ln)
  else
    ((if not (!tk = tk_ident) || is_keyword !tstr then
       fail !tline "expected a binding name");
     let ln = !tline in
     let name = !tstr in
     next_token ();
     if bytes_eq_str name "_" then PAny ln else PVar (ln, name))

and p_let_after_binder ln0 binder acc =
  let params = p_params [] in
  expect_punct "=";
  let rhs0 = p_expr () in
  let rhs =
    if list_length params > 0 then EFun (pat_line binder, params, rhs0)
    else rhs0 in
  let acc2 = (binder, rhs) :: acc in
  if tok_is_ident "and" then
    (next_token ();
     let binder2 = p_let_binder () in
     p_let_after_binder ln0 binder2 acc2)
  else
    (expect_kw "in";
     let body = p_expr () in
     ELetAnd (ln0, list_rev acc2, body))

and p_let () =
  let ln0 = !tline in
  next_token ();
  if tok_is_ident "rec" then
    (next_token ();
     (if not (!tk = tk_ident) || is_keyword !tstr then
       fail !tline "let rec needs a name");
     let name = !tstr in
     let lnf = !tline in
     next_token ();
     let params = p_params [] in
     (if list_length params = 0 then fail lnf "local let rec must define a function");
     expect_punct "=";
     let rhs = p_expr () in
     expect_kw "in";
     let body = p_expr () in
     ELetRec (ln0, name, EFun (lnf, params, rhs), body))
  else if tok_is_punct "(" then
    (next_token ();
     if tok_is_punct ")" then
       (let lnu = !tline in
        next_token ();
        p_let_after_binder ln0 (PUnit lnu) [])
     else
       (let p = p_pat_paren () in
        expect_punct "=";
        let rhs = p_expr () in
        (if tok_is_ident "and" then
          fail !tline "pattern bindings cannot be in and-groups");
        expect_kw "in";
        let body = p_expr () in
        ELetAnd (ln0, [(p, rhs)], body)))
  else
    (let binder = p_let_binder () in
     p_let_after_binder ln0 binder [])

and p_atom () =
  let k = !tk in
  if k = tk_int then
    (let ln = !tline in
     let v = !tint in
     next_token ();
     EInt (ln, v))
  else if k = tk_str then
    (let ln = !tline in
     let s = !tstr in
     next_token ();
     EStr (ln, s))
  else if k = tk_ident then
    (if tok_is_ident "true" then (let ln = !tline in next_token (); EBool (ln, true))
     else if tok_is_ident "false" then (let ln = !tline in next_token (); EBool (ln, false))
     else if is_keyword !tstr then fail !tline "unexpected keyword"
     else
       (let ln = !tline in
        let name = !tstr in
        next_token ();
        if is_ctor_name name then p_ctor ln name
        else EVar (ln, name)))
  else if tok_is_punct "(" then
    (let ln = !tline in
     next_token ();
     if tok_is_punct ")" then (next_token (); EUnit ln)
     else
       (let e = p_expr () in
        if tok_is_punct "," then
          (let rec elems acc =
             if tok_is_punct "," then
               (next_token ();
                let e2 = p_expr () in
                elems (e2 :: acc))
             else (expect_punct ")"; list_rev acc) in
           ETuple (ln, e :: elems []))
        else (expect_punct ")"; e)))
  else if tok_is_punct "!" then
    (let ln = !tline in
     next_token ();
     let a = p_postfix (p_atom ()) in
     EDeref (ln, a))
  else if tok_is_punct "{" then
    (let ln = !tline in
     next_token ();
     let rec rfields acc =
       ((if not (!tk = tk_ident) || is_keyword !tstr then
          fail !tline "expected a field name");
        let f = !tstr in
        next_token ();
        expect_punct "=";
        let e = p_nosemi () in
        let acc2 = (f, e) :: acc in
        if tok_is_punct ";" then
          (next_token ();
           if tok_is_punct "}" then (next_token (); list_rev acc2)
           else rfields acc2)
        else (expect_punct "}"; list_rev acc2)) in
     ERecord (ln, rfields []))
  else if tok_is_punct "[" then
    (let ln = !tline in
     next_token ();
     if tok_is_punct "]" then (next_token (); ENil ln)
     else
       (let rec elems () =
          let e = p_nosemi () in
          let l2 = !tline in
          if tok_is_punct ";" then (next_token (); ECons (l2, e, elems ()))
          else (expect_punct "]"; ECons (l2, e, ENil l2)) in
        elems ()))
  else fail !tline "unexpected token"

(* ---- syntactic values (the value restriction) ---- *)

let rec is_value e =
  match e with
  | EInt (_, _) -> true
  | EStr (_, _) -> true
  | EBool (_, _) -> true
  | EUnit _ -> true
  | EVar (_, _) -> true
  | EFun (_, _, _) -> true
  | ECtor (_, _, args) -> is_value_list args
  | ETuple (_, l) -> is_value_list l
  | ENil _ -> true
  | ECons (_, a, b) -> is_value a && is_value b
  | _ -> false

and is_value_list l =
  match l with
  | [] -> true
  | h :: t -> is_value h && is_value_list t

(* ---- pattern checking ----
   check_pat acc p subject extends acc with monomorphic bindings
   (name, (0, ty)) and constrains subject to the pattern's shape. *)

let rec check_pat acc p subject =
  match p with
  | PAny _ -> acc
  | PUnit ln -> (unify ln subject t_unit; acc)
  | PVar (_, name) -> (name, (0, subject)) :: acc
  | PInt (ln, _) -> (unify ln subject t_int; acc)
  | PBool (ln, _) -> (unify ln subject t_bool; acc)
  | PNil ln -> (unify ln subject (t_list (fresh_meta ())); acc)
  | PCons (ln, h, t) ->
      (let m = fresh_meta () in
       unify ln subject (t_list m);
       let acc2 = check_pat acc h m in
       check_pat acc2 t (t_list m))
  | PTup (ln, ps) ->
      (let ms = fresh_meta_list ps in
       unify ln subject (TTup ms);
       check_pat_list acc ps ms)
  | PCtor (ln, name, args) ->
      (match ctor_find name with
       | None -> fail_name ln "unknown constructor" name
       | Some info ->
           (let (nq, argtys, res) = info in
            (if not (list_length args = list_length argtys) then
              fail_name ln "wrong number of constructor arguments for" name);
            let marr = new_meta_array nq in
            unify ln subject (inst_ty marr res);
            check_pat_args acc args argtys marr))

and check_pat_list acc ps ms =
  match (ps, ms) with
  | (p :: pt, m :: mt) -> check_pat_list (check_pat acc p m) pt mt
  | (_, _) -> acc

and check_pat_args acc args argtys marr =
  match (args, argtys) with
  | (p :: pt, t :: tt) -> check_pat_args (check_pat acc p (inst_ty marr t)) pt tt marr
  | (_, _) -> acc

and fresh_meta_list ps =
  match ps with
  | [] -> []
  | _ :: t -> fresh_meta () :: fresh_meta_list t

(* ---- generalization of binding groups ---- *)

(* checked binding: (line, bindings, rhs-was-a-syntactic-value) *)

let gen_binds binds =
  let counter = ref 0 in
  let rec walk l =
    match l with
    | [] -> ()
    | (_, (_, t)) :: rest -> (gen_walk counter t; walk rest) in
  walk binds;
  let n = !counter in
  let rec remap l =
    match l with
    | [] -> []
    | (name, (_, t)) :: rest -> (name, (n, t)) :: remap rest in
  remap binds

let rec clamp_binds ln binds =
  match binds with
  | [] -> ()
  | (_, (_, t)) :: rest -> (clamp_ty ln t; clamp_binds ln rest)

(* clamp every non-value binding before any value binding generalizes *)
let rec clamp_pass checked =
  match checked with
  | [] -> ()
  | (ln, bs, isv) :: rest ->
      ((if not isv then clamp_binds ln bs);
       clamp_pass rest)

let rec build_env env checked =
  match checked with
  | [] -> env
  | (_, bs, isv) :: rest ->
      (let bs2 = if isv then gen_binds bs else bs in
       build_env (list_append bs2 env) rest)

(* ---- expression checking ---- *)

let rec check_expr env e =
  match e with
  | EInt (_, _) -> t_int
  | EStr (_, _) -> t_string
  | EBool (_, _) -> t_bool
  | EUnit _ -> t_unit
  | EVar (ln, name) ->
      (match assoc_find name env with
       | Some sch -> instantiate sch
       | None ->
           (match glob_find name with
            | Some sch -> instantiate sch
            | None -> fail_name ln "unbound value" name))
  | ECtor (ln, name, args) ->
      (match ctor_find name with
       | None -> fail_name ln "unknown constructor" name
       | Some info ->
           (let (nq, argtys, res) = info in
            (if not (list_length args = list_length argtys) then
              fail_name ln "wrong number of constructor arguments for" name);
            let marr = new_meta_array nq in
            check_ctor_args env ln args argtys marr;
            inst_ty marr res))
  | EApp (ln, f, a) ->
      (let tf = check_expr env f in
       let ta = check_expr env a in
       let tr = fresh_meta () in
       unify ln tf (TFun (ta, tr));
       tr)
  | EFun (_, params, body) -> check_fun env params body
  | EIf (ln, c, a, b) ->
      (let tc = check_expr env c in
       unify ln tc t_bool;
       let ta = check_expr env a in
       match b with
       | Some e2 ->
           (let tb = check_expr env e2 in
            unify ln ta tb;
            ta)
       | None -> (unify ln ta t_unit; t_unit))
  | EMatch (_, subj, arms) ->
      (let ts = check_expr env subj in
       let tr = fresh_meta () in
       check_arms env arms ts tr;
       tr)
  | ELetAnd (_, binds, body) ->
      (enter_level ();
       let checked = check_bindings env binds in
       leave_level ();
       clamp_pass checked;
       check_expr (build_env env checked) body)
  | ELetRec (ln, name, rhs, body) ->
      (enter_level ();
       let m = fresh_meta () in
       let t = check_expr ((name, (0, m)) :: env) rhs in
       unify ln m t;
       leave_level ();
       let counter = ref 0 in
       gen_walk counter m;
       check_expr ((name, (!counter, m)) :: env) body)
  | ESeq (ln, a, b) ->
      (let ta = check_expr env a in
       unify ln ta t_unit;
       check_expr env b)
  | ETuple (_, l) -> TTup (check_list env l)
  | ENil _ -> t_list (fresh_meta ())
  | ECons (ln, h, t) ->
      (let th = check_expr env h in
       let tt = check_expr env t in
       unify ln tt (t_list th);
       t_list th)
  | EDeref (ln, a) ->
      (let t = check_expr env a in
       let m = fresh_meta () in
       unify ln t (t_ref m);
       m)
  | EAssign (ln, a, b) ->
      (let ta = check_expr env a in
       let m = fresh_meta () in
       unify ln ta (t_ref m);
       let tb = check_expr env b in
       unify ln tb m;
       t_unit)
  | EBinop (ln, code, a, b) ->
      (let ta = check_expr env a in
       let tb = check_expr env b in
       if code < 20 then (unify ln ta t_int; unify ln tb t_int; t_int)
       else if code < 22 then (unify ln ta tb; t_bool)
       else if code < 30 then (unify ln ta t_int; unify ln tb t_int; t_bool)
       else (unify ln ta t_bool; unify ln tb t_bool; t_bool))
  | ERecord (ln, fields) ->
      (match fields with
       | [] -> fail ln "record literal needs at least one field"
       | (f0, _) :: _ ->
           (match field_find f0 with
            | None -> fail_name ln "unknown record field" f0
            | Some info ->
                (let (rty, _, _) = info in
                 let rname = (match rty with TCon (_, n, _) -> n | _ -> f0) in
                 (match recfields_find rname with
                  | None -> fail_name ln "not a record type" rname
                  | Some decl ->
                      (check_record_fields env ln fields decl;
                       rty)))))
  | EProj (ln, e, f) ->
      (match field_find f with
       | None -> fail_name ln "unknown record field" f
       | Some info ->
           (let (rty, fty, _) = info in
            let t = check_expr env e in
            unify ln t rty;
            fty))
  | ESetField (ln, e, f, v) ->
      (match field_find f with
       | None -> fail_name ln "unknown record field" f
       | Some info ->
           (let (rty, fty, ismut) = info in
            (if not ismut then fail_name ln "record field is not mutable" f);
            let t = check_expr env e in
            unify ln t rty;
            let tv = check_expr env v in
            unify ln tv fty;
            t_unit))

and check_record_fields env ln fields decl =
  match (fields, decl) with
  | ([], []) -> ()
  | ((fname, e) :: frest, (dname, fty, _) :: drest) ->
      ((if not (bytes_eq fname dname) then
         fail_name ln "record fields must be complete and in declaration order" fname);
       let t = check_expr env e in
       unify ln t fty;
       check_record_fields env ln frest drest)
  | ((fname, _) :: _, _) -> fail_name ln "unknown or repeated record field" fname
  | (_, (dname, _, _) :: _) ->
      fail_name ln "record literal must define every field" dname

and check_fun env params body =
  match params with
  | [] -> check_expr env body
  | p :: rest ->
      (match p with
       | PUnit _ -> TFun (t_unit, check_fun env rest body)
       | PAny _ ->
           (let m = fresh_meta () in
            TFun (m, check_fun env rest body))
       | PVar (_, name) ->
           (let m = fresh_meta () in
            TFun (m, check_fun ((name, (0, m)) :: env) rest body))
       | _ -> fail (pat_line p) "invalid parameter")

and check_ctor_args env ln args argtys marr =
  match (args, argtys) with
  | (a :: at, t :: tt) ->
      (let ta = check_expr env a in
       unify ln ta (inst_ty marr t);
       check_ctor_args env ln at tt marr)
  | (_, _) -> ()

and check_arms env arms ts tr =
  match arms with
  | [] -> ()
  | (p, body) :: rest ->
      (let binds = check_pat [] p ts in
       let t = check_expr (list_append binds env) body in
       unify (pat_line p) t tr;
       check_arms env rest ts tr)

and check_list env l =
  match l with
  | [] -> []
  | h :: t -> check_expr env h :: check_list env t

and check_bindings env binds =
  match binds with
  | [] -> []
  | (p, rhs) :: rest ->
      (let t = check_expr env rhs in
       let bs = check_pat [] p t in
       (pat_line p, bs, is_value rhs) :: check_bindings env rest)

(* ---- type declarations ---- *)

let p_type_params () =
  if !tk = tk_ident && bytes_get !tstr 0 = 39 then
    (let name = !tstr in
     next_token ();
     [name])
  else if tok_is_punct "(" then
    (next_token ();
     let rec params acc =
       ((if not (!tk = tk_ident) || not (bytes_get !tstr 0 = 39) then
          fail !tline "expected a type parameter");
        let name = !tstr in
        next_token ();
        if tok_is_punct "," then (next_token (); params (name :: acc))
        else (expect_punct ")"; list_rev (name :: acc))) in
     params [])
  else []

let rec p_ctor_decls acc =
  ((if not (!tk = tk_ident) || not (is_ctor_name !tstr) then
     fail !tline "expected a constructor name");
   let name = !tstr in
   let ln = !tline in
   next_token ();
   let args =
     if tok_is_ident "of" then (next_token (); p_of_type ())
     else [] in
   let acc2 = (ln, name, args) :: acc in
   if tok_is_punct "|" then (next_token (); p_ctor_decls acc2)
   else list_rev acc2)

(* { mutable? field : type ; ... }: the open brace is consumed *)
let p_record_decl () =
  let rec rfdecls acc =
    let ismut = (if tok_is_ident "mutable" then (next_token (); true) else false) in
    ((if not (!tk = tk_ident) || is_keyword !tstr then
       fail !tline "expected a field name");
     let fname = !tstr in
     let fln = !tline in
     next_token ();
     expect_punct ":";
     let tx = p_tx_full () in
     let acc2 = (fln, fname, ismut, tx) :: acc in
     if tok_is_punct ";" then
       (next_token ();
        if tok_is_punct "}" then (next_token (); list_rev acc2)
        else rfdecls acc2)
     else (expect_punct "}"; list_rev acc2)) in
  rfdecls []

let rec p_type_decls acc =
  let params = p_type_params () in
  ((if not (!tk = tk_ident) || is_keyword !tstr then
     fail !tline "expected a type name");
   let name = !tstr in
   let ln = !tline in
   next_token ();
   expect_punct "=";
   if tok_is_punct "{" then
     (next_token ();
      let rf = p_record_decl () in
      let acc2 = (ln, name, params, [], rf) :: acc in
      if tok_is_ident "and" then (next_token (); p_type_decls acc2)
      else list_rev acc2)
   else
     ((if tok_is_punct "|" then next_token ());
      let ctors = p_ctor_decls [] in
      let acc2 = (ln, name, params, ctors, []) :: acc in
      if tok_is_ident "and" then (next_token (); p_type_decls acc2)
      else list_rev acc2))

let check_type_group () =
  let decls = p_type_decls [] in
  (* register every head first: the group may be mutually recursive *)
  let rec reg l =
    match l with
    | [] -> []
    | (ln, name, params, ctors, rf) :: rest ->
        (let id = fresh_type_id () in
         type_add name id (list_length params);
         (ln, name, params, ctors, rf, id) :: reg rest) in
  let regd = reg decls in
  let rec do_decl l =
    match l with
    | [] -> ()
    | (ln, name, params, ctors, rf, id) :: rest ->
        (let rec param_assoc ps i =
           match ps with
           | [] -> []
           | h :: pt -> (h, i) :: param_assoc pt (i + 1) in
         let passoc = param_assoc params 0 in
         let nq = list_length params in
         let rec qargs i =
           if i >= nq then [] else TQVar i :: qargs (i + 1) in
         let res = TCon (id, name, qargs 0) in
         (match rf with
          | [] ->
              (let rec do_ctors cs =
                 match cs with
                 | [] -> ()
                 | (_, cname, txargs) :: ct ->
                     (ctor_add cname nq (tx_to_ty_list passoc txargs) res;
                      do_ctors ct) in
               do_ctors ctors)
          | _ ->
              ((if nq > 0 then fail ln "record types cannot take parameters");
               let rec do_fields fs acc =
                 match fs with
                 | [] -> recfields_add name (list_rev acc)
                 | (fln, fname, ismut, tx) :: ft ->
                     ((match field_find fname with
                       | Some _ -> fail_name fln "duplicate record field" fname
                       | None -> ());
                      let fty = tx_to_ty [] tx in
                      field_add fname (res, fty, ismut);
                      do_fields ft ((fname, fty, ismut) :: acc)) in
               do_fields rf []));
         do_decl rest) in
  do_decl regd

(* ---- top-level bindings ---- *)

let rec p_top_bindings_after binder acc =
  let params = p_params [] in
  expect_punct "=";
  let rhs0 = p_expr () in
  let rhs =
    if list_length params > 0 then EFun (pat_line binder, params, rhs0)
    else rhs0 in
  let acc2 = (binder, rhs) :: acc in
  if tok_is_ident "and" then
    (next_token ();
     let b2 = p_let_binder () in
     p_top_bindings_after b2 acc2)
  else list_rev acc2

let rec add_globals checked =
  match checked with
  | [] -> ()
  | (_, bs, isv) :: rest ->
      (let bs2 = if isv then gen_binds bs else bs in
       let rec add l =
         match l with
         | [] -> ()
         | (name, sch) :: lt ->
             (let (n, t0) = sch in
              glob_add name n t0;
              add lt) in
       add bs2;
       add_globals rest)

let check_top_group binds =
  enter_level ();
  let rec go l =
    match l with
    | [] -> []
    | (p, rhs) :: rest ->
        (let t = check_expr [] rhs in
         let bs = check_pat [] p t in
         (pat_line p, bs, is_value rhs) :: go rest) in
  let checked = go binds in
  leave_level ();
  clamp_pass checked;
  add_globals checked

let check_top_rec () =
  let binds = p_top_bindings_after (p_let_binder ()) [] in
  enter_level ();
  let rec mk l =
    match l with
    | [] -> []
    | (p, rhs) :: rest ->
        (match p with
         | PVar (ln, name) -> (ln, name, fresh_meta (), rhs) :: mk rest
         | _ -> fail (pat_line p) "let rec needs a name") in
  let group = mk binds in
  let rec menv l =
    match l with
    | [] -> []
    | (_, name, m, _) :: rest -> (name, (0, m)) :: menv rest in
  let env = menv group in
  let rec chk l =
    match l with
    | [] -> ()
    | (ln, _, m, rhs) :: rest ->
        (let t = check_expr env rhs in
         unify ln m t;
         chk rest) in
  chk group;
  leave_level ();
  (* clamp non-value right-hand sides first, then generalize the rest *)
  let rec clamp1 l =
    match l with
    | [] -> ()
    | (ln, _, m, rhs) :: rest ->
        ((if not (is_value rhs) then clamp_ty ln m);
         clamp1 rest) in
  clamp1 group;
  let counter = ref 0 in
  let rec gen1 l =
    match l with
    | [] -> ()
    | (_, _, m, rhs) :: rest ->
        ((if is_value rhs then gen_walk counter m);
         gen1 rest) in
  gen1 group;
  let n = !counter in
  let rec add l =
    match l with
    | [] -> ()
    | (_, name, m, _) :: rest -> (glob_add name n m; add rest) in
  add group

(* ---- driver ---- *)

let rec top_loop () =
  if !tk = tk_eof then ()
  else if tok_is_punct ";;" then (next_token (); top_loop ())
  else if tok_is_ident "let" then
    (next_token ();
     (if tok_is_ident "rec" then
       (next_token ();
        check_top_rec ())
      else if tok_is_punct "(" then
       (next_token ();
        if tok_is_punct ")" then
          (let lnu = !tline in
           next_token ();
           check_top_group (p_top_bindings_after (PUnit lnu) []))
        else
          (let p = p_pat_paren () in
           expect_punct "=";
           let rhs = p_expr () in
           (if tok_is_ident "and" then
             fail !tline "pattern bindings cannot be in and-groups");
           check_top_group [(p, rhs)]))
      else check_top_group (p_top_bindings_after (p_let_binder ()) []));
     top_loop ())
  else if tok_is_ident "type" then
    (next_token ();
     check_type_group ();
     top_loop ())
  else fail !tline "expected a top-level declaration"

let () =
  (if arg_count () < 1 then
    (err_str "usage: mltc file.ml";
     err_nl ();
     exit 1));
  file_str := arg_get 0;
  let h = open_in (arg_get 0) in
  (if h < 0 then
    (err_str "mltc: cannot open ";
     err_str (arg_get 0);
     err_nl ();
     exit 1));
  read_all h;
  close_chan h;
  init_builtins ();
  next_token ();
  top_loop ()
