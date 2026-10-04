(* records: declaration, literal, projection, mutation, nesting in
   other values, projection of a parenthesized expression *)

type cursor = { mutable cpos : int; mutable cline : int; cdata : bytes }
and span = { s_from : int; s_to : int }

let print_int n =
  let rec go v = ((if v > 9 then go (v / 10)); write_byte 1 (48 + v mod 10)) in
  (if n < 0 then write_byte 1 45);
  go (if n < 0 then 0 - n else n);
  write_byte 1 10

let advance c n =
  c.cpos <- c.cpos + n;
  (if c.cpos > 10 then c.cline <- c.cline + 1)

let width s = s.s_to - s.s_from

let () =
  let c = { cpos = 0; cline = 1; cdata = bytes_create 4 } in
  advance c 7;
  advance c 6;
  print_int (c.cpos * 10 + c.cline);
  let sp = { s_from = c.cpos - 9; s_to = c.cpos } in
  print_int (width sp);
  let stack = [{ s_from = 1; s_to = 3 }; { s_from = 10; s_to = 20 }] in
  (match stack with
   | a :: b :: _ -> print_int (width a + width b)
   | _ -> print_int 0);
  let r = ref { s_from = 2; s_to = 5 } in
  print_int ((!r).s_to + bytes_length c.cdata)
