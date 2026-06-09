(* ccc part 12: symbol maps and scope maps; port of Hcc.SymbolTable and
   Hcc.ScopeMap. A red-black tree keyed by (djb2-hash mod 2^31-1, name);
   the tree shape is invisible to output so only lookup semantics
   matter, but the structure is kept for performance parity. *)

(* color: 0 = red, 1 = black *)
type 'a symtree =
  | SymE
  | SymN of int * bytes * int * 'a option * 'a symtree * 'a symtree

let sym_hash k =
  let n = bytes_length k in
  let rec go h i =
    if i >= n then h
    else go (hmod (h * 33 + bytes_get k i) 2147483647) (i + 1) in
  go 5381 0

(* -1 lt, 0 eq, 1 gt *)
let bytes_cmp a b =
  let na = bytes_length a in
  let nb = bytes_length b in
  let rec go i =
    if i >= na && i >= nb then 0
    else if i >= na then 0 - 1
    else if i >= nb then 1
    else
      (let ca = bytes_get a i in
       let cb = bytes_get b i in
       if ca < cb then 0 - 1
       else if ca > cb then 1
       else go (i + 1)) in
  go 0

let sym_cmp k kh x xh =
  if kh < xh then 0 - 1
  else if kh > xh then 1
  else bytes_cmp k x

let rec sym_lookup_h k kh t =
  match t with
  | SymE -> None
  | SymN (_, x, xh, v, l, r) ->
      let c = sym_cmp k kh x xh in
      if c < 0 then sym_lookup_h k kh l
      else if c > 0 then sym_lookup_h k kh r
      else v

let sym_lookup k t = sym_lookup_h k (sym_hash k) t

let sym_member k t = is_some (sym_lookup k t)

(* balancing, port of SymbolTable.balL/balR *)
let sym_bal_r x xh v l r =
  match r with
  | SymN (0, rx, rxh, rv, rl, rr) ->
      (match rl with
       | SymN (0, rlx, rlxh, rlv, rll, rlr) ->
           SymN (0, rlx, rlxh, rlv,
                 SymN (1, x, xh, v, l, rll),
                 SymN (1, rx, rxh, rv, rlr, rr))
       | _ ->
           (match rr with
            | SymN (0, rrx, rrxh, rrv, rrl, rrr) ->
                SymN (0, rx, rxh, rv,
                      SymN (1, x, xh, v, l, rl),
                      SymN (1, rrx, rrxh, rrv, rrl, rrr))
            | _ -> SymN (1, x, xh, v, l, r)))
  | _ -> SymN (1, x, xh, v, l, r)

let sym_bal_l x xh v l r =
  match l with
  | SymN (0, lx, lxh, lv, ll, lr) ->
      (match ll with
       | SymN (0, llx, llxh, llv, lll, llr) ->
           SymN (0, lx, lxh, lv,
                 SymN (1, llx, llxh, llv, lll, llr),
                 SymN (1, x, xh, v, lr, r))
       | _ ->
           (match lr with
            | SymN (0, lrx, lrxh, lrv, lrl, lrr) ->
                SymN (0, lrx, lrxh, lrv,
                      SymN (1, lx, lxh, lv, ll, lrl),
                      SymN (1, x, xh, v, lrr, r))
            | _ -> sym_bal_r x xh v l r))
  | _ -> sym_bal_r x xh v l r

let sym_bal c x xh v l r =
  if c = 0 then SymN (0, x, xh, v, l, r) else sym_bal_l x xh v l r

let rec sym_alter_go k kh v u =
  match u with
  | SymE -> SymN (0, k, kh, v, SymE, SymE)
  | SymN (c, x, xh, old, l, r) ->
      let cm = sym_cmp k kh x xh in
      if cm < 0 then sym_bal c x xh old (sym_alter_go k kh v l) r
      else if cm > 0 then sym_bal c x xh old l (sym_alter_go k kh v r)
      else SymN (c, k, kh, v, l, r)

let sym_blacken t =
  match t with
  | SymE -> SymE
  | SymN (_, x, xh, v, l, r) -> SymN (1, x, xh, v, l, r)

let sym_insert k v t = sym_blacken (sym_alter_go k (sym_hash k) (Some v) t)
let sym_delete k t = sym_blacken (sym_alter_go k (sym_hash k) None t)

(* ---- scope map: a current frame plus parent frames ---- *)

type 'a scopemap = ScopeMap of 'a symtree * 'a symtree list

let scope_empty = ScopeMap (SymE, [])

let scope_enter sm =
  match sm with ScopeMap (cur, parents) -> ScopeMap (SymE, cur :: parents)

let scope_leave sm =
  match sm with
  | ScopeMap (_, []) -> scope_empty
  | ScopeMap (_, p :: ps) -> ScopeMap (p, ps)

let scope_insert k v sm =
  match sm with ScopeMap (cur, parents) -> ScopeMap (sym_insert k v cur, parents)

let rec scope_lookup_parents k kh parents =
  match parents with
  | [] -> None
  | p :: ps ->
      (match sym_lookup_h k kh p with
       | Some v -> Some v
       | None -> scope_lookup_parents k kh ps)

let scope_lookup k sm =
  match sm with
  | ScopeMap (cur, parents) ->
      let kh = sym_hash k in
      (match sym_lookup_h k kh cur with
       | Some v -> Some v
       | None -> scope_lookup_parents k kh parents)
