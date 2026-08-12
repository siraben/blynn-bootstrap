(* dev driver: ccc-cc1, mirroring `hcc1 --m1-ir`.  Target selection is
   deliberately parsed here instead of in the shell wrapper so the same
   bytecode honors --target in both the host and M2-built paths.  The data
   label prefix comes from the INPUT path: port of
   Hcc.DriverCommon.dataLabelPrefix and Hcc.HccSystem.hccTakeFileName. *)

let is_ascii_alpha_num c =
  (c >= ch_0 && c <= ch_9) || (c >= ch_A && c <= ch_Z) || (c >= ch_a && c <= ch_z)

(* everything after the last '/' *)
let hcc_take_file_name path =
  let n = string_length path in
  let rec scan i start =
    if i < n then
      scan (i + 1) (if string_get path i = ch_slash then i + 1 else start)
    else start in
  let start = scan 0 0 in
  let out = buf_new 32 in
  iter_range start n (fun i -> buf_push out (string_get path i));
  buf_take out

let data_label_prefix path =
  let base = hcc_take_file_name path in
  let n = bytes_length base in
  let b = buf_new 64 in
  buf_add_str b "HCC_DATA_";
  (if n = 0 then buf_add_str b "unit"
   else
     iter_range 0 n
       (fun i ->
         (let c = bytes_get base i in
          if is_ascii_alpha_num c then buf_push b c else buf_push b ch_uscore)));
  buf_take b

let parse_target name =
  if bytes_eq_any name ["amd64"; "x86_64"] then
    Some (str_to_bytes "amd64", 64)
  else if bytes_eq_any name ["aarch64"; "arm64"] then
    Some (str_to_bytes "aarch64", 64)
  else if bytes_eq_str name "riscv64" then
    Some (str_to_bytes "riscv64", 64)
  else if bytes_eq_any name ["i386"; "x86"] then
    Some (str_to_bytes "i386", 32)
  else None

let die_target_error prefix value =
  let b = buf_new 64 in
  buf_add_str b prefix;
  buf_add_bytes b value;
  die_bytes (buf_take b)

(* Return (input, output, canonical target name, target word bits). *)
let rec parse_args i input output target_name target_bits =
  if i >= arg_count () then
    (match (input, output) with
     | (Some inp, Some out) -> (inp, out, target_name, target_bits)
     | _ -> die "usage: ccc-cc1 [--target TARGET] --m1-ir -o OUTPUT INPUT.i")
  else
    (let a = arg_get i in
     let b = bytes_of_string a in
     if bytes_eq_str b "--target" then
       (if i + 1 >= arg_count () then die "hcc1: option --target requires an argument"
        else
          (match parse_target (bytes_of_string (arg_get (i + 1))) with
           | Some (name, bits) -> parse_args (i + 2) input output name bits
           | None -> die_target_error "hcc1: unsupported target: "
                         (bytes_of_string (arg_get (i + 1)))))
     else if bytes_eq_str b "-o" then
       (if i + 1 >= arg_count () then die "hcc1: option -o requires an argument"
        else parse_args (i + 2) input (Some (arg_get (i + 1))) target_name target_bits)
     else if bytes_eq_any b ["--m1-ir"; "--trace"; "-S"; "-c"] then
       parse_args (i + 1) input output target_name target_bits
     else if bytes_length b > 0 && bytes_get b 0 = ch_minus then
       die_target_error "hcc1: unsupported option: " b
     else
       (match input with
        | None -> parse_args (i + 1) (Some a) output target_name target_bits
        | Some _ ->
            (match output with
             | None -> parse_args (i + 1) input (Some a) target_name target_bits
             | Some _ -> die "hcc1: too many input files")))

let () =
  let (input, output, target_name, target_bits) =
    parse_args 0 None None (str_to_bytes "amd64") 64 in
  let src = read_file input in
  let toks = lex_plain_source src in
  match parse_program toks with
  | None ->
      (err_str input;
       write_byte 2 ch_colon;
       err_bytes (parse_error_render ());
       write_byte 2 ch_nl;
       exit 1)
  | Some decls ->
      (let out = emit_hccir (data_label_prefix input) target_name target_bits decls in
       let h = open_out output in
       (if h < 0 then (err_str "ccc: cannot write "; die output));
       out_chan := h;
       write_buf out;
       close_chan h;
       exit 0)
