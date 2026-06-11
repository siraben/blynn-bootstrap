(* dev driver: lex a file and render tokens like hcpp's renderTokens
   (token texts separated by single spaces, trailing newline). On inputs
   with no directives and no macros this must match hcpp byte-for-byte. *)

let () =
  (if arg_count () < 1 then die "usage: ccc-lex input.c");
  let src = read_file (arg_get 0) in
  let toks = lex_plain_source src in
  let out = buf_new 65536 in
  list_iter
    (fun t ->
      (buf_add_bytes out (token_text (tok_kind t)); buf_push out ch_space))
    toks;
  buf_push out ch_nl;
  write_buf out;
  exit 0
