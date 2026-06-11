BEGIN {
  instr["IParam"] = "IK_PARAM"
  instr["IAlloca"] = "IK_ALLOCA"
  instr["IConst"] = "IK_CONST"
  instr["IConstBytes"] = "IK_CONSTB"
  instr["ICopy"] = "IK_COPY"
  instr["IAddrOf"] = "IK_ADDROF"
  instr["ILoad64"] = "IK_LOAD64"
  instr["ILoad32"] = "IK_LOAD32"
  instr["ILoadS32"] = "IK_LOADS32"
  instr["ILoad16"] = "IK_LOAD16"
  instr["ILoadS16"] = "IK_LOADS16"
  instr["ILoad8"] = "IK_LOAD8"
  instr["ILoadS8"] = "IK_LOADS8"
  instr["IStore64"] = "IK_STORE64"
  instr["IStore32"] = "IK_STORE32"
  instr["IStore16"] = "IK_STORE16"
  instr["IStore8"] = "IK_STORE8"
  instr["IBin"] = "IK_BIN"
  instr["ICall"] = "IK_CALL"
  instr["ICallIndirect"] = "IK_CALLI"
  instr["ICond"] = "IK_COND"
  instr["ISExt"] = "IK_SEXT"
  instr["IZExt"] = "IK_ZEXT"
  instr["ITrunc"] = "IK_TRUNC"

  binop["IAdd"] = "BK_ADD"
  binop["ISub"] = "BK_SUB"
  binop["IMul"] = "BK_MUL"
  binop["IDiv"] = "BK_DIV"
  binop["IMod"] = "BK_MOD"
  binop["IShl"] = "BK_SHL"
  binop["IShr"] = "BK_SHR"
  binop["ISar"] = "BK_SAR"
  binop["IEq"] = "BK_EQ"
  binop["INe"] = "BK_NE"
  binop["ILt"] = "BK_LT"
  binop["ILe"] = "BK_LE"
  binop["IGt"] = "BK_GT"
  binop["IGe"] = "BK_GE"
  binop["IULt"] = "BK_ULT"
  binop["IULe"] = "BK_ULE"
  binop["IUGt"] = "BK_UGT"
  binop["IUGe"] = "BK_UGE"
  binop["IAnd"] = "BK_AND"
  binop["IOr"] = "BK_OR"
  binop["IXor"] = "BK_XOR"
  binop["IUDiv"] = "BK_UDIV"
  binop["IUMod"] = "BK_UMOD"
}

function trim(s) {
  sub(/^[ \t]*/, "", s)
  sub(/[ \t]*$/, "", s)
  return s
}

function first_number_after(s, marker, rest, pieces) {
  if (index(s, marker) == 0) return ""
  rest = substr(s, index(s, marker) + length(marker))
  rest = trim(rest)
  split(rest, pieces, /[^0-9]+/)
  return pieces[1]
}

function record_instr(line, cons, code) {
  line = trim(line)
  split(line, parts, /[ \t]+/)
  cons = parts[1]
  if (!(cons in instr)) return

  code = first_number_after(line, "write (\"")
  if (code == "") code = first_number_after(line, "emitTempOp write")
  if (code == "") code = first_number_after(line, "emitOpOp write")
  if (code == "") code = first_number_after(line, "emitExt write")
  if (code == "") {
    pending_instr = instr[cons]
    return
  }
  hs_instr[instr[cons]] = code + 0
  pending_instr = ""
}

function record_binop(line, cons, code) {
  line = trim(line)
  split(line, parts, /[ \t]+/)
  cons = parts[1]
  if (!(cons in binop)) return

  code = first_number_after(line, "->")
  if (code == "") return
  hs_binop[binop[cons]] = code + 0
}

FNR == 1 {
  in_binop = 0
  in_c_enum = 0
}

FILENAME ~ /M1Ir[.]hs$/ {
  if ($0 ~ /^[ \t]*binOpCode op = case op of/) {
    in_binop = 1
    next
  }
  if (in_binop && $0 ~ /^[^ \t]/) in_binop = 0
  if (in_binop) record_binop($0)
  if ($0 ~ /^[ \t]*I[A-Za-z0-9]+[ \t].*->/) {
    record_instr($0)
    next
  }
  if (pending_instr != "") {
    code = first_number_after($0, "write (\"")
    if (code != "") {
      hs_instr[pending_instr] = code + 0
      pending_instr = ""
    }
  }
  next
}

FILENAME ~ /hcc_m1[.]c$/ {
  if ($0 ~ /^[ \t]*enum[ \t]*[{]/) {
    in_c_enum = 1
    next
  }
  if (in_c_enum && $0 ~ /^[ \t]*}[;]/) {
    in_c_enum = 0
    next
  }
  if (!in_c_enum) next

  line = trim($0)
  if (line ~ /^IK_[A-Z0-9_]+[ \t]*=/) {
    name = line
    sub(/[ \t]*=.*/, "", name)
    code = line
    sub(/^[^=]*=/, "", code)
    sub(/,.*/, "", code)
    c_instr[name] = trim(code) + 0
  }
  if (line ~ /^BK_[A-Z0-9_]+[ \t]*=/) {
    name = line
    sub(/[ \t]*=.*/, "", name)
    code = line
    sub(/^[^=]*=/, "", code)
    sub(/,.*/, "", code)
    c_binop[name] = trim(code) + 0
  }
  next
}

END {
  failed = 0

  for (name in instr) {
    c_name = instr[name]
    if (!(c_name in hs_instr)) {
      printf("missing Haskell emitted instruction opcode for %s\n", c_name) > "/dev/stderr"
      failed = 1
    } else if (!(c_name in c_instr)) {
      printf("missing C instruction opcode constant %s\n", c_name) > "/dev/stderr"
      failed = 1
    } else if (hs_instr[c_name] != c_instr[c_name]) {
      printf("instruction opcode mismatch %s: Haskell emits %d, C defines %d\n", c_name, hs_instr[c_name], c_instr[c_name]) > "/dev/stderr"
      failed = 1
    }
  }

  for (c_name in c_instr) {
    if (!(c_name in hs_instr)) {
      printf("C instruction opcode %s has no Haskell emission checked here\n", c_name) > "/dev/stderr"
      failed = 1
    }
  }

  for (name in binop) {
    c_name = binop[name]
    if (!(c_name in hs_binop)) {
      printf("missing Haskell emitted binary opcode for %s\n", c_name) > "/dev/stderr"
      failed = 1
    } else if (!(c_name in c_binop)) {
      printf("missing C binary opcode constant %s\n", c_name) > "/dev/stderr"
      failed = 1
    } else if (hs_binop[c_name] != c_binop[c_name]) {
      printf("binary opcode mismatch %s: Haskell emits %d, C defines %d\n", c_name, hs_binop[c_name], c_binop[c_name]) > "/dev/stderr"
      failed = 1
    }
  }

  for (c_name in c_binop) {
    if (!(c_name in hs_binop)) {
      printf("C binary opcode %s has no Haskell emission checked here\n", c_name) > "/dev/stderr"
      failed = 1
    }
  }

  if (failed) exit 1
  print "hcc-ir-opcodes: Haskell M1Ir opcode emissions match hcc_m1.c constants"
}
