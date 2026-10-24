(* hello: string literal + tail-recursive byte output *)
let stdout_chan = 1

let rec print_from s i =
  if i < string_length s then
    (write_byte stdout_chan (string_get s i); print_from s (i + 1))

let print_string s = print_from s 0

let () = print_string "hello, core\n"
