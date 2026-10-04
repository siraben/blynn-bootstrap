(* ccc part 10: C lexer. Faithful port of Hcc.Lexer plus the
   spliceContinuations / stripComments passes from Hcc.DriverCommon
   (lexPlainSource = lexC . stripComments . spliceContinuations).
   Tokens carry their start position; HCC's spans' end positions are
   unused by diagnostics. *)

type tkind =
  | TkIdent of bytes
  | TkInt of bytes
  | TkFloat of bytes
  | TkChar of bytes
  | TkString of bytes
  | TkPunct of bytes
  | TkDirective of bytes

(* line, column, kind *)
type token = Tok of int * int * tkind

let token_text k =
  match k with
  | TkIdent s -> s
  | TkInt s -> s
  | TkFloat s -> s
  | TkChar s -> s
  | TkString s -> s
  | TkPunct s -> s
  | TkDirective s -> s

let tok_kind t = match t with Tok (_, _, k) -> k

(* ---- spliceContinuations: remove backslash-newline (and CR) pairs ---- *)

let splice_continuations src =
  let n = bytes_length src in
  let out = buf_new (n + 1) in
  let rec go i =
    if i < n then
      (let c = bytes_get src i in
       if c = ch_bslash && i + 2 < n && bytes_get src (i + 1) = ch_cr &&
          bytes_get src (i + 2) = ch_nl then go (i + 3)
       else if c = ch_bslash && i + 1 < n && bytes_get src (i + 1) = ch_nl then go (i + 2)
       else (buf_push out c; go (i + 1))) in
  go 0;
  buf_take out

(* ---- stripComments: // and nested block comments outside literals ----
   Top-level mutual recursion (ML2 has no local "let rec ... and"); the
   shared cursor state lives in globals. *)

let sc_src = ref (bytes_create 1)
let sc_n = ref 0
let sc_out = ref (buf_new 1)

let rec sc_normal i =
  if i < !sc_n then
    (let c = bytes_get !sc_src i in
     if c = ch_slash && i + 1 < !sc_n && bytes_get !sc_src (i + 1) = ch_slash then sc_line (i + 2)
     else if c = ch_slash && i + 1 < !sc_n && bytes_get !sc_src (i + 1) = ch_star then sc_block 1 (i + 2)
     else if c = ch_dquote then (buf_push !sc_out c; sc_strlit (i + 1))
     else if c = ch_squote then (buf_push !sc_out c; sc_chrlit (i + 1))
     else (buf_push !sc_out c; sc_normal (i + 1)))

and sc_line i =
  if i < !sc_n then
    (if bytes_get !sc_src i = ch_nl then (buf_push !sc_out ch_nl; sc_normal (i + 1))
     else sc_line (i + 1))

and sc_block depth i =
  if i < !sc_n then
    (let c = bytes_get !sc_src i in
     if c = ch_slash && i + 1 < !sc_n && bytes_get !sc_src (i + 1) = ch_star then sc_block (depth + 1) (i + 2)
     else if c = ch_star && i + 1 < !sc_n && bytes_get !sc_src (i + 1) = ch_slash then
       (if depth = 1 then (buf_push !sc_out ch_space; sc_normal (i + 2))
        else sc_block (depth - 1) (i + 2))
     else if c = ch_nl then (buf_push !sc_out ch_nl; sc_block depth (i + 1))
     else sc_block depth (i + 1))

and sc_strlit i =
  if i < !sc_n then
    (let c = bytes_get !sc_src i in
     if c = ch_bslash && i + 1 < !sc_n then
       (buf_push !sc_out c; buf_push !sc_out (bytes_get !sc_src (i + 1)); sc_strlit (i + 2))
     else if c = ch_dquote then (buf_push !sc_out c; sc_normal (i + 1))
     else (buf_push !sc_out c; sc_strlit (i + 1)))

and sc_chrlit i =
  if i < !sc_n then
    (let c = bytes_get !sc_src i in
     if c = ch_bslash && i + 1 < !sc_n then
       (buf_push !sc_out c; buf_push !sc_out (bytes_get !sc_src (i + 1)); sc_chrlit (i + 2))
     else if c = ch_squote then (buf_push !sc_out c; sc_normal (i + 1))
     else (buf_push !sc_out c; sc_chrlit (i + 1)))

let strip_comments src =
  sc_src := src;
  sc_n := bytes_length src;
  sc_out := buf_new (bytes_length src + 1);
  sc_normal 0;
  buf_take !sc_out

(* ---- lexC ---- *)

(* lexer state: input bytes + index, line, col, beginning-of-line flag *)
let lx_src = ref (bytes_create 1)
let lx_n = ref 0
let lx_i = ref 0
let lx_line = ref 1
let lx_col = ref 1
let lx_bol = ref true

let lex_die_at line col msg =
  err_str "ccc: ";
  err_str msg;
  err_str " at ";
  let b = buf_new 24 in
  buf_add_int b line;
  buf_push b ch_colon;
  buf_add_int b col;
  err_bytes (buf_take b);
  write_byte 2 ch_nl;
  exit 1

let lx_peek () = if !lx_i < !lx_n then bytes_get !lx_src !lx_i else 0 - 1
let lx_peek2 () = if !lx_i + 1 < !lx_n then bytes_get !lx_src (!lx_i + 1) else 0 - 1

let lx_peek_at k =
  if !lx_i + k < !lx_n then bytes_get !lx_src (!lx_i + k) else 0 - 1

(* does the input at the cursor start with this literal? *)
let lx_looking_at s =
  let n = string_length s in
  let rec go i =
    if i >= n then true
    else if lx_peek_at i = string_get s i then go (i + 1)
    else false in
  go 0

let char_in_str c s =
  let n = string_length s in
  let rec go i =
    if i >= n then false
    else string_get s i = c || go (i + 1) in
  go 0

let cc_is_space_no_nl c = c = ch_tab || c = ch_cr || c = ch_vt || c = ch_ff
let cc_is_space c = c = ch_space || c = ch_nl || cc_is_space_no_nl c
let cc_is_digit c = c >= ch_0 && c <= ch_9
let cc_is_hex_digit c =
  cc_is_digit c || (c >= ch_a && c <= ch_f) || (c >= ch_A && c <= ch_F)
let cc_is_ident_start c =
  (c >= ch_a && c <= ch_z) || (c >= ch_A && c <= ch_Z) || c = ch_uscore
let cc_is_ident_char c = cc_is_ident_start c || cc_is_digit c

(* advance over one character as a token constituent: bol clears unless
   the character is a space (Lexer.nextBol) *)
let lx_adv () =
  let c = bytes_get !lx_src !lx_i in
  lx_i := !lx_i + 1;
  (if c = ch_nl then (lx_line := !lx_line + 1; lx_col := 1)
   else lx_col := !lx_col + 1);
  lx_bol := c = ch_nl || (cc_is_space_no_nl c && !lx_bol);
  c

(* advance over whitespace: any space preserves bol (Lexer.advanceSpace) *)
let lx_adv_space () =
  let c = bytes_get !lx_src !lx_i in
  lx_i := !lx_i + 1;
  (if c = ch_nl then (lx_line := !lx_line + 1; lx_col := 1)
   else lx_col := !lx_col + 1);
  lx_bol := c = ch_nl || !lx_bol

let lx_take_while pred =
  let b = buf_new 16 in
  let rec go () =
    if pred (lx_peek ()) then (buf_push b (lx_adv ()); go ()) in
  go ();
  buf_take b

(* numbers, mirroring takeNumber / takeHexNumber / takeDecimalNumber *)

let is_int_suffix c = c = ch_u || c = ch_U || c = ch_l || c = ch_L
let is_number_suffix c = is_int_suffix c || c = ch_f || c = ch_F
let is_float_suffix c = c = ch_f || c = ch_F || c = ch_l || c = ch_L

let rec bytes_has_float_suffix b i =
  if i >= bytes_length b then false
  else if bytes_get b i = ch_f || bytes_get b i = ch_F then true
  else bytes_has_float_suffix b (i + 1)

(* fraction: '.' followed by digits, but not '..' *)
let lx_take_fraction hexmode =
  if lx_peek () = ch_dot && not (lx_peek2 () = ch_dot) then
    (let b = buf_new 8 in
     buf_push b (lx_adv ());
     let rec go () =
       let c = lx_peek () in
       if (if hexmode then cc_is_hex_digit c else cc_is_digit c) then
         (buf_push b (lx_adv ()); go ()) in
     go ();
     buf_take b)
  else bytes_create 0

(* exponent markers: eE or pP; only consumed when digits follow *)
let lx_take_exponent m1 m2 =
  let c = lx_peek () in
  if c = m1 || c = m2 then
    (let c2 = lx_peek2 () in
     let signed = c2 = ch_plus || c2 = ch_minus in
     let digit_at = if signed then !lx_i + 2 else !lx_i + 1 in
     if digit_at < !lx_n && cc_is_digit (bytes_get !lx_src digit_at) then
       (let b = buf_new 8 in
        buf_push b (lx_adv ());
        (if signed then buf_push b (lx_adv ()));
        let rec go () =
          if cc_is_digit (lx_peek ()) then (buf_push b (lx_adv ()); go ()) in
        go ();
        buf_take b)
     else bytes_create 0)
  else bytes_create 0

let lx_number () =
  let line = !lx_line in
  let col = !lx_col in
  let b = buf_new 16 in
  let isfloat =
    if lx_peek () = ch_0 && (lx_peek2 () = ch_x || lx_peek2 () = ch_X) then
      (* hex *)
      (buf_push b (lx_adv ());
       buf_push b (lx_adv ());
       let digits = lx_take_while cc_is_hex_digit in
       buf_add_bytes b digits;
       let fraction = lx_take_fraction true in
       buf_add_bytes b fraction;
       let expo = lx_take_exponent ch_p ch_P in
       buf_add_bytes b expo;
       let isf = bytes_length fraction > 0 || bytes_length expo > 0 in
       let suffix =
         if isf then lx_take_while is_float_suffix
         else lx_take_while is_int_suffix in
       buf_add_bytes b suffix;
       (if bytes_length digits = 0 && bytes_length fraction = 0 then
         lex_die_at line col "hexadecimal constant requires at least one digit");
       isf)
    else
      (let digits = lx_take_while cc_is_digit in
       buf_add_bytes b digits;
       let fraction = lx_take_fraction false in
       buf_add_bytes b fraction;
       let expo = lx_take_exponent ch_e ch_E in
       buf_add_bytes b expo;
       let suffix = lx_take_while is_number_suffix in
       buf_add_bytes b suffix;
       bytes_length fraction > 0 || bytes_length expo > 0 ||
       bytes_has_float_suffix suffix 0) in
  let text = buf_take b in
  if isfloat then Tok (line, col, TkFloat text) else Tok (line, col, TkInt text)

let lx_quoted quote =
  let line = !lx_line in
  let col = !lx_col in
  let b = buf_new 16 in
  buf_push b (lx_adv ());
  let rec go () =
    let c = lx_peek () in
    if c < 0 then lex_die_at line col "unterminated literal"
    else if c = quote then (buf_push b (lx_adv ()); ())
    else if c = ch_bslash then
      (buf_push b (lx_adv ());
       (if lx_peek () < 0 then lex_die_at line col "unterminated literal");
       buf_push b (lx_adv ());
       go ())
    else if c = ch_nl then lex_die_at !lx_line !lx_col "newline in literal"
    else (buf_push b (lx_adv ()); go ()) in
  go ();
  let text = buf_take b in
  if quote = ch_dquote then Tok (line, col, TkString text)
  else Tok (line, col, TkChar text)

(* longest-match punctuation; mirrors Lexer.lexPunct's table.
   Multi-char operators are grouped by leading character (longest first
   within a group, groups ordered by rough frequency), so each token
   inspects at most one small group before the single-char fallback. *)
let multi_punct_groups =
  [("=", ["=="]);
   ("-", ["--"; "->"; "-="]);
   ("+", ["++"; "+="]);
   ("<", ["<<="; "<="; "<<"]);
   (">", [">>="; ">="; ">>"]);
   ("!", ["!="]);
   ("&", ["&&"; "&="]);
   ("|", ["||"; "|="]);
   ("*", ["*="]);
   ("/", ["/="]);
   ("%", ["%="]);
   ("^", ["^="]);
   (".", ["..."]);
   ("#", ["##"])]

let single_char_puncts = "();,{}[]=*.&-+<>!:?~/%^|#"

let lx_punct () =
  let line = !lx_line in
  let col = !lx_col in
  let c1 = lx_peek () in
  let take k =
    let b = buf_new 4 in
    let rec go i = if i < k then (buf_push b (lx_adv ()); go (i + 1)) in
    go 0;
    Tok (line, col, TkPunct (buf_take b)) in
  let single () =
    if char_in_str c1 single_char_puncts then take 1
    else lex_die_at line col "unexpected character" in
  let try_ops ops =
    match list_find (fun s -> lx_looking_at s) ops with
    | Some s -> take (string_length s)
    | None -> single () in
  match
    list_find (fun g -> (let (k, _) = g in string_get k 0 = c1)) multi_punct_groups
  with
  | Some g -> (let (_, ops) = g in try_ops ops)
  | None -> single ()

(* directive: bol '#' through end of line; newline consumed *)
let lx_directive () =
  let line = !lx_line in
  let col = !lx_col in
  let b = buf_new 32 in
  let rec go () =
    let c = lx_peek () in
    if c < 0 then ()
    else if c = ch_nl then (let _ = lx_adv () in ())
    else (buf_push b (lx_adv ()); go ()) in
  go ();
  Tok (line, col, TkDirective (buf_take b))

(* lex a full (already spliced and comment-stripped) source *)
let lex_c src =
  lx_src := src;
  lx_n := bytes_length src;
  lx_i := 0;
  lx_line := 1;
  lx_col := 1;
  lx_bol := true;
  let rec go acc =
    let c = lx_peek () in
    if c < 0 then list_rev acc
    else if cc_is_space c then (lx_adv_space (); go acc)
    else if !lx_bol && c = ch_hash then go (lx_directive () :: acc)
    else if cc_is_ident_start c then
      (let line = !lx_line in
       let col = !lx_col in
       let text = lx_take_while cc_is_ident_char in
       go (Tok (line, col, TkIdent text) :: acc))
    else if cc_is_digit c then go (lx_number () :: acc)
    else if c = ch_squote then go (lx_quoted ch_squote :: acc)
    else if c = ch_dquote then go (lx_quoted ch_dquote :: acc)
    else go (lx_punct () :: acc) in
  go []

let lex_plain_source src = lex_c (strip_comments (splice_continuations src))
