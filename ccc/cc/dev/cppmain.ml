(* dev driver: ccpp, hcpp's CLI. Port of Hcc.MainCpp plus the option
   parsing from Hcc.DriverCommon (assemblyArgs over ("-S":args),
   parseDefine/unescapeDefineValue/renderDefines). Output tokens go to
   stdout like hcpp's renderTokens: token text + single space each,
   trailing newline. Errors go to stderr in the reference formats and
   exit 1. *)

let cm_unescape_define_value value =
  let n = bytes_length value in
  let out = buf_new n in
  let rec go i =
    if i < n then
      (let c = bytes_get value i in
       if c = 92 && i + 1 < n && bytes_get value (i + 1) = 34 then
         (buf_push out 34; go (i + 2))
       else (buf_push out c; go (i + 1))) in
  go 0;
  buf_take out

let cm_parse_define def =
  let n = bytes_length def in
  let rec find_eq i =
    if i >= n then 0 - 1
    else if bytes_get def i = 61 then i
    else find_eq (i + 1) in
  let eq = find_eq 0 in
  if eq < 0 then (def, str_to_bytes "1")
  else
    (bytes_sub def 0 eq,
     cm_unescape_define_value (bytes_sub def (eq + 1) (n - eq - 1)))

let cm_parse_target_bits target =
  if bytes_eq_str target "amd64" || bytes_eq_str target "x86_64" ||
     bytes_eq_str target "aarch64" || bytes_eq_str target "arm64" ||
     bytes_eq_str target "riscv64" then Some 64
  else if bytes_eq_str target "i386" || bytes_eq_str target "x86" then Some 32
  else None

let cm_ignored_flag flag =
  bytes_eq_str flag "-c" || bytes_eq_str flag "-pipe" ||
  bytes_eq_str flag "-nostdinc" || bytes_eq_str flag "-nostdlib" ||
  bytes_eq_str flag "-static" || bytes_eq_str flag "--m1-ir" ||
  bytes_eq_str flag "--trace"

(* assemblyArgs; returns (input, include dirs, defines) *)
let rec cm_assembly_args args out input includes defines target =
  match args with
  | [] ->
      (match input with
       | None -> die "hcc: no input files"
       | Some path -> (path, list_rev includes, list_rev defines))
  | a :: rest ->
      if bytes_eq_str a "-S" then
        cm_assembly_args rest out input includes defines target
      else if bytes_eq_str a "-o" then
        (match rest with
         | [] -> die "hcc: option -o requires an argument"
         | p :: xs -> cm_assembly_args xs (Some p) input includes defines target)
      else if bytes_eq_str a "-I" then
        (match rest with
         | [] -> die "hcc: option -I requires an argument"
         | p :: xs -> cm_assembly_args xs out input (p :: includes) defines target)
      else if bytes_eq_str a "-D" then
        (match rest with
         | [] -> die "hcc: option -D requires an argument"
         | d :: xs ->
             cm_assembly_args xs out input includes
               (cm_parse_define d :: defines) target)
      else if bytes_eq_str a "--target" then
        (match rest with
         | [] -> die "hcc: option --target requires an argument"
         | t :: xs ->
             (match cm_parse_target_bits t with
              | Some bits -> cm_assembly_args xs out input includes defines bits
              | None ->
                  (let b = buf_new 48 in
                   buf_add_str b "hcc: unsupported target: ";
                   buf_add_bytes b t;
                   die_bytes (buf_take b))))
      else if bytes_length a > 2 && bytes_get a 0 = 45 && bytes_get a 1 = 73 then
        cm_assembly_args rest out input
          (bytes_sub a 2 (bytes_length a - 2) :: includes) defines target
      else if bytes_length a > 2 && bytes_get a 0 = 45 && bytes_get a 1 = 68 then
        cm_assembly_args rest out input includes
          (cm_parse_define (bytes_sub a 2 (bytes_length a - 2)) :: defines) target
      else if cm_ignored_flag a then
        cm_assembly_args rest out input includes defines target
      else if bytes_length a >= 1 && bytes_get a 0 = 45 then
        (let b = buf_new 48 in
         buf_add_str b "hcc: unsupported option: ";
         buf_add_bytes b a;
         die_bytes (buf_take b))
      else cm_assembly_args rest out (Some a) includes defines target

let rec cm_render_defines out defines =
  match defines with
  | [] -> ()
  | (name, value) :: rest ->
      buf_add_str out "#define ";
      buf_add_bytes out name;
      buf_push out 32;
      buf_add_bytes out value;
      buf_push out 10;
      cm_render_defines out rest

let cm_usage () =
  let b = buf_new 64 in
  buf_add_str b "usage: hcpp [CC-ARGS...] INPUT.c";
  buf_push b 10;
  write_buf b

let cm_preprocess_file args =
  let (input, includes, defines) =
    cm_assembly_args (str_to_bytes "-S" :: args) None None [] [] 64 in
  pp_input := input;
  let source = read_source_with_includes includes defines input in
  let full = buf_new (bytes_length source + 256) in
  cm_render_defines full defines;
  buf_add_bytes full source;
  let toks = lex_plain_source (buf_take full) in
  let out_toks = preprocess toks in
  let out = buf_new 65536 in
  let rec render ts =
    match ts with
    | [] -> buf_push out 10
    | t :: rest ->
        buf_add_bytes out (token_text (tok_kind t));
        buf_push out 32;
        render rest in
  render out_toks;
  write_buf out;
  exit 0

let () =
  let rec gather i acc =
    if i < arg_count () then gather (i + 1) (bytes_of_string (arg_get i) :: acc)
    else list_rev acc in
  let args = gather 0 [] in
  match args with
  | [] -> die "hcpp: no input files"
  | [a] ->
      if bytes_eq_str a "--help" then (cm_usage (); exit 0)
      else cm_preprocess_file [a]
  | _ -> cm_preprocess_file args
