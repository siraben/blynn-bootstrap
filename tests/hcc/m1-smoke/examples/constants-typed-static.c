/* Read wide stored values as bytes: i386 wide loads are not supported. */
unsigned long constants_uint = ~0U;
unsigned long long constants_div = 18446744073709551615ULL / 3ULL;
unsigned long long constants_rem = 18446744073709551615ULL % 7ULL;
unsigned long long constants_wrap = 18446744073709551615ULL + 2ULL;
unsigned long long constants_cond = 1 ? -1 : 0ULL;
unsigned long constants_cond32 = 1 ? -1 : 0U;
long constants_promote = ~(unsigned char)255;
long constants_cast = (signed char)255;
unsigned long long constants_extend = (unsigned int)-1;
unsigned long constants_shift = (unsigned int)-1 >> 31;
int constants_compare = 18446744073709551615ULL > 1ULL;
int constants_dead = 1 ? 7 : 1 / 0;
_Bool constants_bool = (_Bool)256;
int constants_bounds[(4294967295U + 4U)];
enum { constants_model = -1L < 1U };
int constants_enum = constants_model;
long long constants_long = 4294967296L;
unsigned long long constants_top = 1ULL << 63;
unsigned long long constants_literal = 18446744073709551615ULL;
unsigned long constants_narrow = (unsigned char)511;
unsigned long constants_size = sizeof(1ULL) + sizeof(1L);
unsigned long constants_size_expr = sizeof(1 ? 0 : 1ULL) + sizeof(1U << 1ULL);
int constants_never(void);
int constants_dead_call = 1 ? 5 : constants_never();
int constants_short = (0 && 1 / 0) || (1 || 1 / 0);
/* TinyCC's DWARF header uses these extended enumerator values. */
enum { constants_boot32 = 0xffffffffU, constants_boot64 = 0xffffffffffffffffULL };
unsigned long long constants_enum64 = constants_boot64 / 3ULL;
unsigned long long constants_enum32 = constants_boot32;

int main(void) {
  unsigned char *p;
  int i;
  p = (unsigned char *)&constants_uint;
  for (i = 0; i < sizeof(unsigned long); i++)
    if (p[i] != (i < 4 ? 255 : 0)) return 1;
  p = (unsigned char *)&constants_div;
  for (i = 0; i < 8; i++) if (p[i] != 85) return 2;
  p = (unsigned char *)&constants_cond;
  for (i = 0; i < 8; i++) if (p[i] != 255) return 3;
  p = (unsigned char *)&constants_cond32;
  for (i = 0; i < sizeof(unsigned long); i++)
    if (p[i] != (i < 4 ? 255 : 0)) return 4;
  p = (unsigned char *)&constants_extend;
  for (i = 0; i < 8; i++) if (p[i] != (i < 4 ? 255 : 0)) return 5;
  p = (unsigned char *)&constants_rem;
  for (i = 0; i < 8; i++) if (p[i] != (i == 0 ? 1 : 0)) return 6;
  p = (unsigned char *)&constants_wrap;
  for (i = 0; i < 8; i++) if (p[i] != (i == 0 ? 1 : 0)) return 7;
  if (constants_promote != -256 || constants_cast != -1) return 8;
  if (constants_shift != 1 || constants_compare != 1) return 9;
  if (constants_dead != 7 || constants_bool != 1) return 10;
  if (sizeof(constants_bounds) != 12) return 11;
  if (constants_enum != (sizeof(long) == 8)) return 12;
  p = (unsigned char *)&constants_long;
  for (i = 0; i < 8; i++) if (p[i] != (i == 4 ? 1 : 0)) return 13;
  p = (unsigned char *)&constants_top;
  for (i = 0; i < 8; i++) if (p[i] != (i == 7 ? 128 : 0)) return 14;
  p = (unsigned char *)&constants_literal;
  for (i = 0; i < 8; i++) if (p[i] != 255) return 15;
  if (constants_narrow != 255) return 16;
  if (constants_size != 8 + sizeof(long) || constants_size_expr != 12) return 17;
  if (constants_dead_call != 5 || constants_short != 1) return 18;
  p = (unsigned char *)&constants_enum64;
  for (i = 0; i < 8; i++) if (p[i] != 85) return 19;
  p = (unsigned char *)&constants_enum32;
  for (i = 0; i < 8; i++) if (p[i] != (i < 4 ? 255 : 0)) return 20;
  return 0;
}
