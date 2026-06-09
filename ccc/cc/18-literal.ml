(* ccc part 18: literal decoding; port of Hcc.Literal. Unlike the Haskell
   reference (which bit-folded up to 2^30 for the Blynn dialect), the
   bitwise helpers are native operators: the whole stack is ours and the
   VM executes them directly. Shifts are guarded against >= word size,
   where C native shifts are undefined; the reference's multiply/divide
   shifts behaved like these guards for sane inputs. *)

let bool_to_int v = if v then 1 else 0

let rec pow2 n = if n <= 0 then 1 else 2 * pow2 (n - 1)

let bit_not_int v = 0 - v - 1

let bit_and_int a b = a land b
let bit_or_int a b = a lor b
let bit_xor_int a b = a lxor b

let shift_left_int v amount =
  if amount >= 63 then 0 else v lsl amount

let shift_right_int v amount =
  if amount >= 63 then (if v < 0 then 0 - 1 else 0)
  else v asr amount

(* "+","-",... on already-evaluated ints; None on bad op / division by 0 *)
let eval_const_binop op a b =
  if bytes_eq_str op "+" then Some (a + b)
  else if bytes_eq_str op "-" then Some (a - b)
  else if bytes_eq_str op "*" then Some (a * b)
  else if bytes_eq_str op "/" then (if b = 0 then None else Some (hdiv a b))
  else if bytes_eq_str op "%" then (if b = 0 then None else Some (hmod a b))
  else if bytes_eq_str op "<<" then Some (shift_left_int a (imax 0 b))
  else if bytes_eq_str op ">>" then Some (shift_right_int a (imax 0 b))
  else if bytes_eq_str op "&" then Some (bit_and_int a b)
  else if bytes_eq_str op "^" then Some (bit_xor_int a b)
  else if bytes_eq_str op "|" then Some (bit_or_int a b)
  else if bytes_eq_str op "==" then Some (bool_to_int (a = b))
  else if bytes_eq_str op "!=" then Some (bool_to_int (a <> b))
  else if bytes_eq_str op "<" then Some (bool_to_int (a < b))
  else if bytes_eq_str op "<=" then Some (bool_to_int (a <= b))
  else if bytes_eq_str op ">" then Some (bool_to_int (a > b))
  else if bytes_eq_str op ">=" then Some (bool_to_int (a >= b))
  else if bytes_eq_str op "&&" then Some (bool_to_int (a <> 0 && b <> 0))
  else if bytes_eq_str op "||" then Some (bool_to_int (a <> 0 || b <> 0))
  else None

(* ---- digit classes (byte arguments) ---- *)

let lit_is_dec c = c >= 48 && c <= 57
let lit_is_oct c = c >= 48 && c <= 55
let lit_is_hexlc c = c >= 97 && c <= 102
let lit_is_hexuc c = c >= 65 && c <= 70
let lit_is_hex c = lit_is_dec c || lit_is_hexlc c || lit_is_hexuc c

let lit_dec_digit c = c - 48

let lit_hex_digit c =
  if lit_is_dec c then c - 48
  else if lit_is_hexlc c then 10 + c - 97
  else if lit_is_hexuc c then 10 + c - 65
  else 0

let lit_digit_value c =
  if lit_is_dec c then c - 48
  else if lit_is_hexlc c then 10 + c - 97
  else if lit_is_hexuc c then 10 + c - 65
  else 99

(* ---- integer literals ---- *)

let lit_is_int_suffix c = c = 117 || c = 85 || c = 108 || c = 76

let rec int_literal_is_unsigned_from t i =
  if i >= bytes_length t then false
  else if bytes_get t i = 117 || bytes_get t i = 85 then true
  else int_literal_is_unsigned_from t (i + 1)

let int_literal_is_unsigned t = int_literal_is_unsigned_from t 0

(* index one past the last non-suffix character *)
let strip_int_suffix_end t =
  let rec go i =
    if i > 0 && lit_is_int_suffix (bytes_get t (i - 1)) then go (i - 1) else i in
  go (bytes_length t)

let parse_int t =
  let e = strip_int_suffix_end t in
  let rec dec acc i =
    if i < e && lit_is_dec (bytes_get t i) then
      dec (acc * 10 + lit_dec_digit (bytes_get t i)) (i + 1)
    else acc in
  let rec oct acc i =
    if i < e && lit_is_oct (bytes_get t i) then
      oct (acc * 8 + lit_dec_digit (bytes_get t i)) (i + 1)
    else acc in
  let rec hex acc i =
    if i < e then hex (acc * 16 + lit_hex_digit (bytes_get t i)) (i + 1)
    else acc in
  if e >= 2 && bytes_get t 0 = 48 && (bytes_get t 1 = 120 || bytes_get t 1 = 88)
  then hex 0 2
  else if e >= 1 && bytes_get t 0 = 48 then oct 0 1
  else dec 0 0

(* ---- byte words: little-endian lists of byte values ---- *)

let rec take_ints count values =
  if count <= 0 then []
  else
    (match values with
     | [] -> []
     | v :: rest -> v :: take_ints (count - 1) rest)

let rec byteword_mul_small factor carry bytes =
  match bytes with
  | [] -> []
  | b :: rest ->
      let total = b * factor + carry in
      hmod total 256 :: byteword_mul_small factor (hdiv total 256) rest

let rec byteword_add_small carry bytes =
  match bytes with
  | [] -> []
  | b :: rest ->
      let total = b + carry in
      hmod total 256 :: byteword_add_small (hdiv total 256) rest

let zero_byte_word = [0; 0; 0; 0; 0; 0; 0; 0]

let byteword_mul_add base digit bytes =
  take_ints 8 (byteword_add_small digit (byteword_mul_small base 0 bytes))

(* read digits of the given base from index i; stops at the first
   character whose digit value is out of range *)
let read_base_bytes base t i0 =
  let n = bytes_length t in
  let rec go bytes i =
    if i < n && lit_digit_value (bytes_get t i) < base then
      go (byteword_mul_add base (lit_digit_value (bytes_get t i)) bytes) (i + 1)
    else bytes in
  go zero_byte_word i0

let natural_literal_bytes t =
  if bytes_length t >= 2 && bytes_get t 0 = 48 &&
     (bytes_get t 1 = 120 || bytes_get t 1 = 88)
  then read_base_bytes 16 t 2
  else if bytes_length t >= 1 && bytes_get t 0 = 48 then read_base_bytes 8 t 1
  else read_base_bytes 10 t 0

let rec int_bytes_from n count =
  if count <= 0 then []
  else hmod n 256 :: int_bytes_from (hdiv n 256) (count - 1)

let int_bytes size value = int_bytes_from value size

(* ---- float literals (bootstrap-grade: mantissa digits as integer) ---- *)

let lit_is_float_suffix c = c = 102 || c = 70 || c = 108 || c = 76

let strip_float_suffix_end t =
  let rec go i =
    if i > 0 && lit_is_float_suffix (bytes_get t (i - 1)) then go (i - 1) else i in
  go (bytes_length t)

let float_literal_size t =
  let n = bytes_length t in
  if n = 0 then 8
  else
    (let last = bytes_get t (n - 1) in
     if last = 102 || last = 70 then 4
     else if last = 108 || last = 76 then 16
     else 8)

let float_literal_bytes size t =
  let e = strip_float_suffix_end t in
  let stripped = bytes_sub t 0 e in
  let word =
    if bytes_length stripped >= 2 && bytes_get stripped 0 = 48 &&
       (bytes_get stripped 1 = 120 || bytes_get stripped 1 = 88)
    then read_base_bytes 16 stripped 2
    else read_base_bytes 10 stripped 0 in
  take_ints size word

(* ---- escapes, characters and strings ---- *)

(* decode one escape body starting at index i (after the backslash),
   reading no further than index n; returns (value, next index). The
   bound is a parameter so callers can exclude a trailing quote without
   slicing the text (a per-escape copy made this quadratic on long
   escape-heavy literals, which dominated whole-of-TinyCC compiles). *)
let decode_escape_until t n i =
  if i >= n then (0, i)
  else
    (let c = bytes_get t i in
     if c = 110 then (10, i + 1)
     else if c = 116 then (9, i + 1)
     else if c = 114 then (13, i + 1)
     else if c = 102 then (12, i + 1)
     else if c = 118 then (11, i + 1)
     else if c = 97 then (7, i + 1)
     else if c = 98 then (8, i + 1)
     else if c = 92 then (92, i + 1)
     else if c = 39 then (39, i + 1)
     else if c = 34 then (34, i + 1)
     else if c = 120 then
       (* \x...: any number of hex digits; bare x if none *)
       (let rec hexgo v j started =
          if j < n && lit_is_hex (bytes_get t j) then
            hexgo (v * 16 + lit_hex_digit (bytes_get t j)) (j + 1) true
          else (v, j, started) in
        let (v, j, started) = hexgo 0 (i + 1) false in
        if started then (v, j) else (120, i + 1))
     else if lit_is_oct c then
       (let rec octgo count v j =
          if count >= 3 then (v, j)
          else if j < n && lit_is_oct (bytes_get t j) then
            octgo (count + 1) (v * 8 + lit_dec_digit (bytes_get t j)) (j + 1)
          else (v, j) in
        octgo 0 0 i)
     else (c, i + 1))

(* token text like 'a' or '\n' (quotes included) *)
let char_value t =
  let n = bytes_length t in
  if n >= 2 && bytes_get t 0 = 39 && bytes_get t 1 = 92 then
    (* drop the closing quote, then decode from index 2 *)
    (let e = if n >= 3 && bytes_get t (n - 1) = 39 then n - 1 else n in
     let (v, _) = decode_escape_until t e 2 in
     v)
  else if n = 3 && bytes_get t 0 = 39 && bytes_get t 2 = 39 then bytes_get t 1
  else 0

(* token text with surrounding quotes; decoded bytes plus a trailing 0 *)
let string_bytes t =
  let n0 = bytes_length t in
  let s = if n0 >= 1 && bytes_get t 0 = 34 then 1 else 0 in
  let e = if n0 >= s + 1 && bytes_get t (n0 - 1) = 34 then n0 - 1 else n0 in
  let rec go i =
    if i >= e then [0]
    else if bytes_get t i = 92 then
      (let (v, j) = decode_escape_until t e (i + 1) in
       v :: go j)
    else bytes_get t i :: go (i + 1) in
  go s
