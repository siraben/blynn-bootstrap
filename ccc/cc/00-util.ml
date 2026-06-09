(* ccc part 00: utilities.
   ccc is built by concatenating the ccc/cc/*.ml parts in lexical order;
   the result is ML2 (the stage 04 dialect) and also a host-OCaml program
   when prefixed with ccc/tests/prelude-ocaml.ml, which is how it is
   typechecked and iterated on during development. *)

(* ---- byte/string helpers ---- *)

let rec bytes_blit_into src dst n i =
  if i < n then (bytes_set dst i (bytes_get src i); bytes_blit_into src dst n (i + 1))

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

(* ---- growable byte buffers: (bytes ref, length ref) ---- *)

let buf_new n = (ref (bytes_create n), ref 0)

let buf_len b = !(snd b)

let buf_reserve b extra =
  let data = fst b in
  let len = snd b in
  if !len + extra > bytes_length !data then
    (let rec newcap c = if c >= !len + extra then c else newcap (2 * c) in
     let nb = bytes_create (newcap (2 * bytes_length !data)) in
     bytes_blit_into !data nb !len 0;
     data := nb)

let buf_push b c =
  buf_reserve b 1;
  bytes_set !(fst b) !(snd b) c;
  (snd b) := !(snd b) + 1

let buf_add_bytes b s =
  let n = bytes_length s in
  buf_reserve b n;
  let data = !(fst b) in
  let len = snd b in
  let rec cp i =
    if i < n then (bytes_set data (!len + i) (bytes_get s i); cp (i + 1)) in
  cp 0;
  len := !len + n

let buf_add_str b s =
  let n = string_length s in
  buf_reserve b n;
  let data = !(fst b) in
  let len = snd b in
  let rec cp i =
    if i < n then (bytes_set data (!len + i) (string_get s i); cp (i + 1)) in
  cp 0;
  len := !len + n

let buf_add_int b n =
  let rec go v =
    (if v > 9 then go (v / 10));
    buf_push b (48 + v mod 10) in
  if n < 0 then (buf_push b 45; go (0 - n)) else go n

let buf_take b = bytes_sub !(fst b) 0 !(snd b)

let buf_get b i = bytes_get !(fst b) i

let buf_clear b = (snd b) := 0

(* string-ish conversions *)

let str_to_bytes s =
  let n = string_length s in
  let out = bytes_create n in
  let rec cp i = if i < n then (bytes_set out i (string_get s i); cp (i + 1)) in
  cp 0;
  out

let int_to_bytes n =
  let b = buf_new 24 in
  buf_add_int b n;
  buf_take b

(* ---- list helpers (polymorphic; erased on the VM) ---- *)

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

(* ---- diagnostics and I/O ---- *)

let rec err_str_from s i =
  if i < string_length s then (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str s = err_str_from s 0

let rec err_bytes_from b i =
  if i < bytes_length b then (write_byte 2 (bytes_get b i); err_bytes_from b (i + 1))

let err_bytes b = err_bytes_from b 0

let die_bytes msg =
  err_bytes msg;
  write_byte 2 10;
  exit 1

let die msg =
  err_str msg;
  write_byte 2 10;
  exit 1

(* read a whole file into bytes *)
let read_file path =
  let h = open_in path in
  (if h < 0 then (err_str "ccc: cannot open "; die path));
  let b = buf_new 65536 in
  let rec go () =
    let c = read_byte h in
    if c >= 0 then (buf_push b c; go ()) in
  go ();
  close_chan h;
  buf_take b

(* buffered output writer *)
let out_chan = ref 1

let write_buf b =
  let data = !(fst b) in
  let n = !(snd b) in
  let rec go i = if i < n then (write_byte !out_chan (bytes_get data i); go (i + 1)) in
  go 0
