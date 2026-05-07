Mes libc reference
==================

This directory vendors the generated Mes libc sources used by the
`nixpkgs#minimal-bootstrap.mes-libc` package.  They are kept here as the
reference surface for replacing `mescc` in the TinyCC bootstrap path.

Source package: GNU Mes 0.27.1
Nix output: `nixpkgs#minimal-bootstrap.mes-libc`

The TinyCC bootstrap in nixpkgs links the first compiler with `-l c+tcc`;
that library behavior comes from these Mes libc and support sources.
