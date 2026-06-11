(* dev driver: ccc-cc1 INPUT.i OUTPUT.hccir, mirroring
   `hcc1 --m1-ir -o OUTPUT INPUT.i` (target 64). The data label prefix
   comes from the INPUT path: port of Hcc.DriverCommon.dataLabelPrefix
   and Hcc.HccSystem.hccTakeFileName. *)

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

let () =
  (if arg_count () < 2 then die "usage: ccc-cc1 INPUT.i OUTPUT.hccir");
  let input = arg_get 0 in
  let output = arg_get 1 in
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
      (let out = emit_hccir (data_label_prefix input) 64 decls in
       let h = open_out output in
       (if h < 0 then (err_str "ccc: cannot write "; die output));
       out_chan := h;
       write_buf out;
       close_chan h;
       exit 0)
