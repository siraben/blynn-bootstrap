#if -5 / 2 != -2 || -5 % 2 != -1 || 5 / -2 != -2 || 5 % -2 != 1
#error truncation toward zero
#endif
#if (0x80000000U & 0x80000000U) == 0
#error bit 31 lost
#endif
#if -1 < 1U || !(-1 > 1U)
#error unsigned comparison
#endif
#if (0x8000000000000000ULL & 0xffffffffffffffffULL) != 0x8000000000000000ULL
#error bit 63 lost
#endif
#if (0x8000000000000000ULL >> 63) != 1 || (1ULL << 63) != 0x8000000000000000ULL
#error full width shifts
#endif
#if 18446744073709551615ULL / 3 != 6148914691236517205ULL || 18446744073709551615ULL % 7 != 1
#error unsigned division
#endif
#if 0xffffffffffffffffULL + 1 != 0 || 0xffffffffffffffffULL * 3 != 0xfffffffffffffffdULL
#error unsigned wrap
#endif
#if (1 ? -1 : 1U) < 0 || (1 ? -1 : 1U/0) < 0
#error conditional common type
#endif
/* These differ from ordinary 32-bit unsigned int arithmetic. */
#if ~0U != 18446744073709551615ULL || 0xffffffff == -1
#error preprocessing intmax model
#endif
#if 0xffffffffU + 1 != 4294967296 || (1 == 1) << 40 != 1099511627776
#error preprocessing widths
#endif
#if (-9223372036854775807LL - 1) / 2 != -4611686018427387904LL
#error signed minimum division
#endif
#if ((-9223372036854775807LL - 1) >> 63) != -1
#error signed right shift
#endif
int pp_contract_arithmetic;
_Static_assert(~0U == 0xffffffffU, "ordinary unsigned int is 32 bits");
_Static_assert(0xffffffffU + 1 == 0, "ordinary wrap");
_Static_assert(0xffffffff == -1, "hexadecimal candidate type");
_Static_assert(2147483648 > 0, "decimal candidate type");
_Static_assert(-1 < 1ULL == 0, "ordinary mixed comparison");
_Static_assert(-5 / 2 == -2 && -5 % 2 == -1, "ordinary quotient/remainder");
_Static_assert((0x80000000U & 0x80000000U) != 0, "ordinary bit 31");
_Static_assert((0x8000000000000000ULL >> 63) == 1, "ordinary bit 63");
_Static_assert((1 ? -1 : 1U) > 0, "ordinary conditional conversion");
