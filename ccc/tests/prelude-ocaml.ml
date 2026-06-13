(* Prelude that maps the core bootstrap dialect's builtins onto OCaml's
   standard library, so stage sources and fixtures can be cross-checked
   under a real OCaml: ocaml <(cat prelude-ocaml.ml program.ml) args...
   Channel handles are small ints; 0 = stdin, 1 = stdout, 2 = stderr. *)

let in_chans : in_channel option array = Array.make 256 None
let out_chans : out_channel option array = Array.make 256 None
let () = in_chans.(0) <- Some stdin
let () = out_chans.(1) <- Some stdout
let () = out_chans.(2) <- Some stderr
let chan_next = ref 3

let open_in (p : string) : int =
  try
    let c = Stdlib.open_in_bin p in
    let h = !chan_next in
    chan_next := h + 1;
    in_chans.(h) <- Some c;
    h
  with _ -> -1

let open_out (p : string) : int =
  try
    let c = Stdlib.open_out_bin p in
    let h = !chan_next in
    chan_next := h + 1;
    out_chans.(h) <- Some c;
    h
  with _ -> -1

let close_chan (h : int) : unit =
  (match in_chans.(h) with
   | Some c -> close_in c; in_chans.(h) <- None
   | None -> ());
  (match out_chans.(h) with
   | Some c -> close_out c; out_chans.(h) <- None
   | None -> ())

let read_byte (h : int) : int =
  match in_chans.(h) with
  | Some c -> (try input_byte c with End_of_file -> -1)
  | None -> failwith "read_byte: bad handle"

let write_byte (h : int) (b : int) : unit =
  match out_chans.(h) with
  | Some c -> output_byte c b
  | None -> failwith "write_byte: bad handle"

let bytes_create (n : int) : bytes = Bytes.make n '\000'
let bytes_length = Bytes.length
let bytes_get (b : bytes) (i : int) : int = Char.code (Bytes.get b i)
let bytes_set (b : bytes) (i : int) (v : int) : unit =
  Bytes.set b i (Char.chr (v land 255))
let bytes_of_string = Bytes.of_string
(* host-only bridge: dialect strings ARE bytes, so constructed paths can
   be passed straight to open_in on the VM; under host OCaml the
   conversion must be explicit. The VM build supplies the identity. *)
let bytes_to_string : bytes -> string = Bytes.to_string
let _ = bytes_to_string

let string_length = String.length
let string_get (s : string) (i : int) : int = Char.code (String.get s i)

let array_make = Array.make
let array_get = Array.get
let array_set = Array.set
let array_length = Array.length

let arg_count () : int = max 0 (Array.length Sys.argv - 1)
let arg_get (i : int) : string = Sys.argv.(i + 1)

(* lists and pairs as builtins (Lambda-0 v2): cons cells and pairs are
   2-field blocks on the chain; under OCaml they are real lists/tuples.
   fst/snd come from Stdlib. *)
let cons h t = h :: t
let nil = []
let null l = match l with [] -> true | _ -> false
let hd l = match l with x :: _ -> x | [] -> failwith "hd: empty list"
let tl l = match l with _ :: t -> t | [] -> failwith "tl: empty list"
let pair a b = (a, b)

(* silence unused-prelude warnings in programs that use only part of it *)
let _ = (open_in, open_out, close_chan, read_byte, write_byte,
         bytes_create, bytes_length, bytes_get, bytes_set, bytes_of_string,
         string_length, string_get, array_make, array_get, array_set,
         array_length, arg_count, arg_get)
let _ = (cons, null, hd, tl, pair, nil)
