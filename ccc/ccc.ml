(* Initial CCC bytecode smoke.

   This is not the C compiler yet. It pins the mlc -> ccc.byte build edge
   while the real C frontend and M1 emitter are ported. For now it emits a
   tiny amd64 M1 program that exits with status 0.
*)

write_string "DEFINE LOADI32_RDI 48C7C7\nDEFINE LOADI32_RAX 48C7C0\nDEFINE SYSCALL 0F05\n\n:_start\n\tLOADI32_RDI %0\n\tLOADI32_RAX %60\n\tSYSCALL\n"
