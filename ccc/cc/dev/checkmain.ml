(* dev driver: parse-check files like hcc1 --check; exit 0 if all parse,
   else print path:line:col: message and exit 1. *)

let check_file path =
  let src = read_file path in
  let toks = lex_plain_source src in
  match parse_program toks with
  | Some _ -> ()
  | None ->
      (err_str path;
       write_byte 2 ch_colon;
       err_bytes (parse_error_render ());
       write_byte 2 ch_nl;
       exit 1)

let () =
  let n = arg_count () in
  (if n < 1 then die "usage: ccc-check FILE...");
  iter_range 0 n (fun i -> check_file (arg_get i));
  exit 0
