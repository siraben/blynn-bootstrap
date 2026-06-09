(* dev driver: lex a file and render tokens like hcpp's renderTokens
   (token texts separated by single spaces, trailing newline). On inputs
   with no directives and no macros this must match hcpp byte-for-byte. *)

let () =
  (if arg_count () < 1 then die "usage: ccc-lex input.c");
  let src = read_file (arg_get 0) in
  let toks = lex_plain_source src in
  let out = buf_new 65536 in
  let rec render ts =
    match ts with
    | [] -> buf_push out 10
    | t :: rest ->
        buf_add_bytes out (token_text (tok_kind t));
        buf_push out 32;
        render rest in
  render toks;
  write_buf out;
  exit 0
