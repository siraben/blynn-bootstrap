let
  lines = builtins.filter builtins.isString (
    builtins.split "\n" (builtins.readFile ../data/bootstrap-sources.env)
  );
  assignments = builtins.filter (line: line != "" && builtins.substring 0 1 line != "#") lines;
  entries = map (line:
    let match = builtins.match "([A-Z][A-Z0-9_]*)=([^[:space:]]+)" line;
    in
    if match == null then
      throw "invalid bootstrap source pin: ${line}"
    else {
      name = builtins.elemAt match 0;
      value = builtins.elemAt match 1;
    }
  ) assignments;
  pins = builtins.listToAttrs entries;
in
assert builtins.length entries == builtins.length (builtins.attrNames pins);
pins
