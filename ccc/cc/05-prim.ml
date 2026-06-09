(* ccc part 05: Haskell-compatible primitives.
   HCC's reference semantics are GHC's: div/mod are FLOORING (C-style
   division truncates), and the bitwise helpers in Hcc.Literal are
   bit-folds capped at 2^30 rather than native operators. Anything that
   must match hcc1's output byte-for-byte goes through these. *)

type 'a option = None | Some of 'a

let opt_or o d = match o with | None -> d | Some v -> v

let is_some o = match o with | None -> false | Some _ -> true

(* flooring division and modulus, Haskell div/mod *)
let hdiv a b =
  let q = a / b in
  if a mod b <> 0 && ((a < 0) <> (b < 0)) then q - 1 else q

let hmod a b = a - b * hdiv a b

let imax a b = if a < b then b else a
let imin a b = if a < b then a else b
