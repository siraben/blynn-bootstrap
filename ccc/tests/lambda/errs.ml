(* Lambda-0 fixture: err_str data-section literals and exit code *)

let rec err_str_from s = fun i ->
  if i < string_length s then
    (write_byte 2 (string_get s i); err_str_from s (i + 1))

let err_str = fun s -> err_str_from s 0

let () =
  err_str "hello from the data section\n";
  err_str "escapes: \"quoted\\\" and a tab\there\n";
  write_byte 1 111;
  write_byte 1 107;
  write_byte 1 10;
  exit 3
