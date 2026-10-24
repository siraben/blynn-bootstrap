# Select metadata before touching drv: even evaluating an unsupported derivation
# can fail (for example the portable TinyCC selfhost's architecture assertion).
{ lib, system, registry }:
lib.mapAttrs (_: test: test.drv)
  (lib.filterAttrs (_: test:
    test.gating && builtins.elem system test.systems
  ) registry)
