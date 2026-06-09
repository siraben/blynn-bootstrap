(* ccc part 72: include expansion; port of Hcc.IncludeExpand plus the
   path helpers from Hcc.HccSystem. Paths are bytes; the host prelude's
   bytes_to_string bridges to open_in (on the VM strings are bytes and
   the conversion is the identity). hccCanonicalizePath is realpath(3)
   in the reference runtime; ML2 has no equivalent syscall, so paths
   are used as written (divergence only when one file is reached via
   two different spellings). Existence testing is open_in >= 0. *)

let inc_file_exists path =
  let h = open_in (bytes_to_string path) in
  if h < 0 then false
  else (close_chan h; true)

let inc_read_file path =
  let h = open_in (bytes_to_string path) in
  (if h < 0 then
    (let b = buf_new 64 in
     buf_add_str b "hcc: cannot read ";
     buf_add_bytes b path;
     die_bytes (buf_take b)));
  let b = buf_new 65536 in
  let rec go () =
    let c = read_byte h in
    if c >= 0 then (buf_push b c; go ()) in
  go ();
  close_chan h;
  buf_take b

(* ---- path helpers (Hcc.HccSystem) ---- *)

let inc_canonicalize_path path = path

let inc_last_slash path =
  let n = bytes_length path in
  let rec go i best =
    if i >= n then best
    else go (i + 1) (if bytes_get path i = 47 then i else best) in
  go 0 (0 - 1)

let inc_take_directory path =
  let i = inc_last_slash path in
  if i < 0 then str_to_bytes "."
  else if i = 0 then str_to_bytes "/"
  else bytes_sub path 0 i

let inc_take_file_name path =
  let i = inc_last_slash path in
  let n = bytes_length path in
  bytes_sub path (i + 1) (n - i - 1)

let inc_path_join left right =
  if bytes_length left = 0 then right
  else if bytes_length right = 0 then left
  else
    (let b = buf_new (bytes_length left + bytes_length right + 1) in
     buf_add_bytes b left;
     (if not (bytes_get left (bytes_length left - 1) = 47) then buf_push b 47);
     buf_add_bytes b right;
     buf_take b)

(* ---- line and word splitting (Haskell lines / words) ---- *)

let inc_lines b =
  let n = bytes_length b in
  let rec go start i acc =
    if i >= n then
      (if start = n then list_rev acc
       else list_rev (bytes_sub b start (n - start) :: acc))
    else if bytes_get b i = 10 then
      go (i + 1) (i + 1) (bytes_sub b start (i - start) :: acc)
    else go start (i + 1) acc in
  go 0 0 []

let inc_words b =
  let n = bytes_length b in
  let rec go i acc =
    if i >= n then list_rev acc
    else if cc_is_space (bytes_get b i) then go (i + 1) acc
    else
      (let rec scan j = if j < n && not (cc_is_space (bytes_get b j)) then scan (j + 1) else j in
       let j = scan i in
       go j (bytes_sub b i (j - i) :: acc)) in
  go 0 []

let inc_prefix_str b s =
  let sl = string_length s in
  if bytes_length b < sl then false
  else
    (let rec cmp i =
       if i >= sl then true
       else if bytes_get b i = string_get s i then cmp (i + 1)
       else false in
     cmp 0)

(* ---- directive line probing ---- *)

(* does word equal "#" ++ directive? *)
let inc_word_is_hash w directive =
  let dl = string_length directive in
  if not (bytes_length w = dl + 1) then false
  else if not (bytes_get w 0 = 35) then false
  else
    (let rec cmp i =
       if i >= dl then true
       else if bytes_get w (i + 1) = string_get directive i then cmp (i + 1)
       else false in
     cmp 0)

let inc_directive_argument directive line =
  match inc_words line with
  | w1 :: name1 :: rest1 ->
      if inc_word_is_hash w1 directive then Some name1
      else if bytes_eq_str w1 "#" then
        (if bytes_eq_str name1 directive then
           (match rest1 with
            | name2 :: _ -> Some name2
            | [] -> None)
         else None)
      else None
  | _ -> None

let inc_directive_name_from_line line =
  match inc_words line with
  | [] -> None
  | w1 :: rest ->
      if bytes_eq_str w1 "#" then
        (match rest with
         | w2 :: _ -> Some w2
         | [] -> Some (bytes_create 0))
      else if bytes_length w1 > 0 && bytes_get w1 0 = 35 then
        Some (bytes_sub w1 1 (bytes_length w1 - 1))
      else None

let inc_after_directive directive text =
  let trimmed = pp_drop_spaces text in
  if inc_prefix_str trimmed directive then
    (let dl = string_length directive in
     pp_drop_spaces (bytes_sub trimmed dl (bytes_length trimmed - dl)))
  else bytes_create 0

let inc_directive_rest directive line =
  let t = pp_drop_spaces line in
  if bytes_length t > 0 && bytes_get t 0 = 35 then
    inc_after_directive directive (bytes_sub t 1 (bytes_length t - 1))
  else bytes_create 0

let inc_pragma_once_line line =
  match inc_words line with
  | [a; b] -> bytes_eq_str a "#pragma" && bytes_eq_str b "once"
  | [a; b; c] -> bytes_eq_str a "#" && bytes_eq_str b "pragma" && bytes_eq_str c "once"
  | _ -> false

type incform = QuoteInclude | SystemInclude

let inc_take_until term b start =
  let n = bytes_length b in
  let rec go i = if i < n && not (bytes_get b i = term) then go (i + 1) else i in
  let e = go start in
  bytes_sub b start (e - start)

let inc_strip_include_delims raw =
  if bytes_length raw > 0 && bytes_get raw 0 = 34 then
    Some (QuoteInclude, inc_take_until 34 raw 1)
  else if bytes_length raw > 0 && bytes_get raw 0 = 60 then
    Some (SystemInclude, inc_take_until 62 raw 1)
  else None

let inc_include_request line =
  match inc_words line with
  | [] -> None
  | w1 :: rest1 ->
      if bytes_eq_str w1 "#include" then
        (match rest1 with
         | raw :: _ -> inc_strip_include_delims raw
         | [] -> None)
      else if bytes_eq_str w1 "#" then
        (match rest1 with
         | w2 :: rest2 ->
             if bytes_eq_str w2 "include" then
               (match rest2 with
                | raw :: _ -> inc_strip_include_delims raw
                | [] -> None)
             else None
         | [] -> None)
      else None

(* ---- evalIncludeIf: string-level #if for include-time tracking ---- *)

let inc_split_top_level sep text =
  let n = bytes_length text in
  let sl = string_length sep in
  let sep_at i =
    if i + sl > n then false
    else
      (let rec cmp k =
         if k >= sl then true
         else if bytes_get text (i + k) = string_get sep k then cmp (k + 1)
         else false in
       cmp 0) in
  let cur = buf_new 16 in
  let rec go depth i acc =
    if i >= n then list_rev (buf_take cur :: acc)
    else
      (let c = bytes_get text i in
       if c = 40 then (buf_push cur c; go (depth + 1) (i + 1) acc)
       else if c = 41 then (buf_push cur c; go (depth - 1) (i + 1) acc)
       else if depth = 0 && sep_at i then
         (let piece = buf_take cur in
          buf_clear cur;
          go depth (i + sl) (piece :: acc))
       else (buf_push cur c; go depth (i + 1) acc)) in
  go 0 0 []

let rec inc_filter_non_null pieces =
  match pieces with
  | [] -> []
  | p :: rest ->
      if bytes_length p = 0 then inc_filter_non_null rest
      else p :: inc_filter_non_null rest

let inc_read_decimal b =
  let n = bytes_length b in
  let rec go acc i =
    if i >= n then acc else go (acc * 10 + bytes_get b i - 48) (i + 1) in
  go 0 0

let rec inc_eval_include_if macros text =
  inc_eval_or macros text (inc_filter_non_null (inc_split_top_level "||" text))

and inc_eval_or macros text parts =
  match parts with
  | [] -> inc_eval_and macros text (inc_filter_non_null (inc_split_top_level "&&" text))
  | [part] -> inc_eval_and macros text (inc_filter_non_null (inc_split_top_level "&&" part))
  | part :: rest ->
      if inc_eval_include_if macros part then true else inc_eval_or macros text rest

and inc_eval_and macros text parts =
  match parts with
  | [] -> inc_eval_atom macros text
  | [part] -> inc_eval_atom macros part
  | part :: rest -> inc_eval_atom macros part && inc_eval_and macros text rest

and inc_eval_atom macros raw =
  let atom = pp_trim raw in
  let n = bytes_length atom in
  if n > 0 && bytes_get atom 0 = 33 then
    not (inc_eval_atom macros (bytes_sub atom 1 (n - 1)))
  else if inc_prefix_str atom "defined" then
    inc_eval_defined macros (bytes_sub atom 7 (n - 7))
  else if n >= 2 && bytes_get atom 0 = 40 && bytes_get atom (n - 1) = 41 then
    inc_eval_include_if macros (bytes_sub atom 1 (n - 2))
  else if pp_all_digits atom then inc_read_decimal atom <> 0
  else if pp_all_ident_chars atom then sym_member atom macros
  else false

and inc_eval_defined macros raw =
  let rest = pp_trim raw in
  if bytes_length rest > 0 && bytes_get rest 0 = 40 then
    sym_member (pp_take_while_ident (bytes_sub rest 1 (bytes_length rest - 1))) macros
  else sym_member (pp_take_while_ident rest) macros

(* ---- include guard detection ---- *)

type incguard =
  | PragmaOnce of bytes
  | IfndefGuard of bytes * int * int

let rec inc_index_lines i ls =
  match ls with
  | [] -> []
  | l :: rest -> (i, l) :: inc_index_lines (i + 1) rest

let inc_blank_line line =
  bytes_length (pp_drop_spaces line) = 0

let rec inc_drop_blank_lines ls =
  match ls with
  | [] -> []
  | (i, line) :: rest ->
      if inc_blank_line line then inc_drop_blank_lines rest
      else (i, line) :: rest

let rec inc_matching_endif depth ls =
  match ls with
  | [] -> None
  | (line_no, line) :: rest ->
      (match inc_directive_name_from_line line with
       | Some name ->
           if bytes_eq_str name "if" || bytes_eq_str name "ifdef" ||
              bytes_eq_str name "ifndef" then
             inc_matching_endif (depth + 1) rest
           else if bytes_eq_str name "endif" then
             (if depth = 1 then Some line_no else inc_matching_endif (depth - 1) rest)
           else inc_matching_endif depth rest
       | None -> inc_matching_endif depth rest)

let inc_ifndef_guard_end guard lines_after =
  match inc_drop_blank_lines lines_after with
  | (_, line) :: rest ->
      (match inc_directive_argument "define" line with
       | Some name ->
           if bytes_eq name guard then inc_matching_endif 1 rest else None
       | None -> None)
  | [] -> None

let inc_is_name_char c = (c >= 65 && c <= 90) || (c >= 48 && c <= 57)

let inc_to_upper c = if c >= 97 && c <= 122 then c - 32 else c

(* uppercase, then split on non-[A-Z0-9] runs, dropping empties *)
let inc_name_tokens name =
  let n = bytes_length name in
  let cur = buf_new 16 in
  let rec go i acc =
    if i >= n then
      (let last = buf_take cur in
       if bytes_length last = 0 then list_rev acc else list_rev (last :: acc))
    else
      (let c = inc_to_upper (bytes_get name i) in
       if inc_is_name_char c then (buf_push cur c; go (i + 1) acc)
       else
         (let piece = buf_take cur in
          buf_clear cur;
          if bytes_length piece = 0 then go (i + 1) acc
          else go (i + 1) (piece :: acc))) in
  go 0 []

let rec inc_token_list_eq a b =
  match (a, b) with
  | ([], []) -> true
  | (x :: xs, y :: ys) -> bytes_eq x y && inc_token_list_eq xs ys
  | _ -> false

let inc_canonical_guard_name path guard =
  inc_token_list_eq (inc_name_tokens (inc_take_file_name path)) (inc_name_tokens guard)

let inc_include_guard path source =
  let cleaned = inc_lines (strip_comments source) in
  match inc_drop_blank_lines (inc_index_lines 0 cleaned) with
  | [] -> None
  | (start, line) :: rest ->
      if inc_pragma_once_line line then
        (let b = buf_new 64 in
         buf_add_str b "__HCC_PRAGMA_ONCE_";
         buf_add_bytes b path;
         Some (PragmaOnce (buf_take b)))
      else
        (match inc_directive_argument "ifndef" line with
         | Some name ->
             if inc_canonical_guard_name path name then
               (match inc_ifndef_guard_end name rest with
                | Some gend -> Some (IfndefGuard (name, start, gend))
                | None -> None)
             else None
         | None -> None)

let inc_skip_line_range start gend ls =
  let rec kept index rest =
    match rest with
    | [] -> []
    | line :: more ->
        if index >= start && index <= gend then kept (index + 1) more
        else line :: kept (index + 1) more in
  kept 0 ls

(* ---- the expansion driver ---- *)

let inc_out = ref (buf_new 1)

let inc_keep_line line =
  buf_add_bytes !inc_out line;
  buf_push !inc_out 10

(* candidates are probed in order: current dir first, then -I dirs *)
let inc_find_include dirs current_dir name =
  let rec from_dirs ds =
    match ds with
    | [] -> None
    | d :: rest ->
        let cand = inc_path_join d name in
        if inc_file_exists cand then Some cand else from_dirs rest in
  let cand0 = inc_path_join current_dir name in
  if inc_file_exists cand0 then Some cand0 else from_dirs dirs

let inc_die_cannot_find name =
  let b = buf_new 64 in
  buf_add_str b "hcpp: cannot find include file ";
  buf_add_bytes b (pp_show_quoted name);
  die_bytes (buf_take b)

let rec inc_expand_file dirs stack guards macros file =
  let key = inc_canonicalize_path file in
  if pp_name_elem key stack then (guards, macros)
  else
    (let source = inc_read_file key in
     let dir = inc_take_directory key in
     let stack2 = key :: stack in
     match inc_include_guard key source with
     | Some (PragmaOnce g) ->
         if sym_member g guards then (guards, macros)
         else
           inc_expand_lines dirs dir stack2 (sym_insert g true guards) macros []
             (inc_lines source)
     | Some (IfndefGuard (g, gstart, gend)) ->
         if sym_member g guards then
           inc_expand_lines dirs dir stack2 guards macros []
             (inc_skip_line_range gstart gend (inc_lines source))
         else
           inc_expand_lines dirs dir stack2 (sym_insert g true guards) macros []
             (inc_lines source)
     | None -> inc_expand_lines dirs dir stack2 guards macros [] (inc_lines source))

and inc_expand_lines dirs current_dir stack guards macros frames ls =
  match ls with
  | [] -> (guards, macros)
  | line :: rest ->
      let (g2, m2, f2) =
        inc_expand_line dirs current_dir stack guards macros frames line in
      inc_expand_lines dirs current_dir stack g2 m2 f2 rest

and inc_expand_line dirs current_dir stack guards macros frames line =
  let active = if_stack_active frames in
  match inc_directive_name_from_line line with
  | Some dn ->
      if bytes_eq_str dn "ifdef" then
        (inc_keep_line line;
         let cond =
           match inc_directive_argument "ifdef" line with
           | Some nm -> sym_member nm macros
           | None -> false in
         (guards, macros, push_if_frame frames cond))
      else if bytes_eq_str dn "ifndef" then
        (inc_keep_line line;
         let cond =
           match inc_directive_argument "ifndef" line with
           | Some nm -> not (sym_member nm macros)
           | None -> false in
         (guards, macros, push_if_frame frames cond))
      else if bytes_eq_str dn "if" then
        (inc_keep_line line;
         (guards, macros,
          push_if_frame frames
            (inc_eval_include_if macros (inc_directive_rest "if" line))))
      else if bytes_eq_str dn "elif" then
        (inc_keep_line line;
         let cond = inc_eval_include_if macros (inc_directive_rest "elif" line) in
         let frames2 =
           match replace_elif_frame frames cond with
           | Some f -> f
           | None -> frames in
         (guards, macros, frames2))
      else if bytes_eq_str dn "else" then
        (inc_keep_line line;
         let frames2 =
           match replace_else_frame frames with
           | Some f -> f
           | None -> frames in
         (guards, macros, frames2))
      else if bytes_eq_str dn "endif" then
        (inc_keep_line line;
         (guards, macros, (match frames with [] -> [] | _ :: fs -> fs)))
      else if bytes_eq_str dn "define" && active then
        (inc_keep_line line;
         let macros2 =
           match inc_directive_argument "define" line with
           | Some nm -> sym_insert nm true macros
           | None -> macros in
         (guards, macros2, frames))
      else if bytes_eq_str dn "undef" && active then
        (inc_keep_line line;
         let macros2 =
           match inc_directive_argument "undef" line with
           | Some nm -> sym_delete nm macros
           | None -> macros in
         (guards, macros2, frames))
      else inc_expand_line_other dirs current_dir stack guards macros frames active line
  | None -> inc_expand_line_other dirs current_dir stack guards macros frames active line

and inc_expand_line_other dirs current_dir stack guards macros frames active line =
  match inc_include_request line with
  | Some (form, name) ->
      if active then
        (match inc_find_include dirs current_dir name with
         | None ->
             (match form with
              | QuoteInclude -> inc_die_cannot_find name
              | SystemInclude -> (inc_keep_line line; (guards, macros, frames)))
         | Some file ->
             if pp_name_elem file stack then (guards, macros, frames)
             else
               (let (g2, m2) = inc_expand_file dirs stack guards macros file in
                (g2, m2, frames)))
      else (inc_keep_line line; (guards, macros, frames))
  | None -> (inc_keep_line line; (guards, macros, frames))

let read_source_with_includes include_dirs defines path =
  inc_out := buf_new 65536;
  let rec initial ds m =
    match ds with
    | [] -> m
    | (name, _) :: rest -> initial rest (sym_insert name true m) in
  let macros0 = initial defines SymE in
  let _ = inc_expand_file include_dirs [] SymE macros0 path in
  buf_take !inc_out

(* VM self-containment: on the VM strings ARE bytes, so bytes_to_string
   is the identity. This deliberately comes AFTER every use above: under
   host OCaml those uses bind the prelude's Bytes.to_string, while the
   stage 04 compiler resolves them as forward references to this
   definition when the parts are compiled without the host prelude. *)
let bytes_to_string b = b
