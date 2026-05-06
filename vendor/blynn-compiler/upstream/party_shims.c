/* Upstream blynn/compiler libc shims, minus the env_argv/getargcount/getargchar
 * that orians' methodically already emits as part of its own libc preamble.
 *
 * These are the foreign-call targets named by upstream party.hs's ffi
 * declarations (after rewriting `foreign import ccall` -> `ffi`). They
 * implement upstream's stdin-with-EOF-lookahead protocol that upstream's
 * Haskell code expects.
 */

#include <stdio.h>

static int nextCh, isAhead;

int eof_shim(void) {
  if (!isAhead) {
    isAhead = 1;
    nextCh = getchar();
  }
  return nextCh == -1;
}

void exit(int);

void putchar_shim(int c) { putchar(c); }

int getchar_shim(void) {
  if (!isAhead) nextCh = getchar();
  if (nextCh == -1) exit(1);
  isAhead = 0;
  return nextCh;
}

void errchar(int c) { fputc(c, stderr); }
void errexit(void) { fputc('\n', stderr); }
