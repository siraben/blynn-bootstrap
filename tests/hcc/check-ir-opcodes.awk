# Compare the two source tables, not a third hard-coded opcode list.
# Constructor names map mechanically, except ICallIndirect -> IK_CALLI.
FNR == 1 { section = ""; pending = "" }

FILENAME ~ /M1Ir[.]hs$/ {
  if (/^emitInstrIr write instr = case instr of/) { section = "IK_"; next }
  if (/^binOpCode op = case op of/) { section = "BK_"; next }
  if (/^[^ \t]/) { section = ""; pending = "" }
  if (!section) next

  if ($1 ~ /^I[A-Za-z0-9]+$/ && /->/) {
    pending = section toupper(substr($1, 2))
    if (pending == "IK_CALLINDIRECT") pending = "IK_CALLI"
    names[pending] = 1
  }
  if (!pending) next
  line = $0
  if (section == "BK_") sub(/^.*->[ \t]*/, "", line)
  else if (match(line, /write [(]"[0-9]+ /))
    line = substr(line, RSTART + 8)
  else if (match(line, /emit(TempOp|OpOp|Ext) write [0-9]+ /)) {
    line = substr(line, RSTART)
    sub(/^[^ ]+ write /, "", line)
  } else next
  if (line ~ /^[0-9]+([ \t]|$)/) {
    hs[pending] = line + 0
    pending = ""
  }
  next
}

FILENAME ~ /hcc_m1[.]c$/ && /^[ \t]*[IB]K_[A-Z0-9_]+[ \t]*=/ {
  name = $1
  names[name] = 1
  line = $0
  sub(/^[^=]*=[ \t]*/, "", line)
  if (line ~ /^[0-9]+[ \t]*,?[ \t]*$/) c[name] = line + 0
}

END {
  for (name in names) {
    count++
    if (!(name in hs) || !(name in c)) {
      printf("missing or unparsed opcode %s: Haskell=%s C=%s\n", name,
             (name in hs ? hs[name] : "missing"),
             (name in c ? c[name] : "missing")) > "/dev/stderr"
      failed = 1
    } else if (hs[name] != c[name]) {
      printf("opcode mismatch %s: Haskell emits %d, C defines %d\n",
             name, hs[name], c[name]) > "/dev/stderr"
      failed = 1
    }
  }
  if (!count) { print "no opcodes found" > "/dev/stderr"; failed = 1 }
  if (failed) exit 1
  print "hcc-ir-opcodes: Haskell M1Ir opcode emissions match hcc_m1.c constants"
}
