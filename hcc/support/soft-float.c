#include <stdlib.h>

/*
 * HCC's M1 ABI carries scalar floating values as IEEE bits in integer
 * registers.  These helpers isolate native floating-point execution behind
 * an integer-only ABI, so an M1 backend does not need target-specific FP
 * instructions or the platform's floating argument convention.
 */

union hcc_soft_f32_bits {
  unsigned int bits;
  float value;
};

union hcc_soft_f64_bits {
  unsigned long bits;
  double value;
};

static float
hcc_soft_f32_value (unsigned long bits)
{
  union hcc_soft_f32_bits value;
  value.bits = (unsigned int) bits;
  return value.value;
}

static unsigned long
hcc_soft_f32_result (float value)
{
  union hcc_soft_f32_bits result;
  result.value = value;
  return (unsigned long) result.bits;
}

static double
hcc_soft_f64_value (unsigned long bits)
{
  union hcc_soft_f64_bits value;
  value.bits = bits;
  return value.value;
}

static unsigned long
hcc_soft_f64_result (double value)
{
  union hcc_soft_f64_bits result;
  result.value = value;
  return result.bits;
}

unsigned long hcc_soft_f32_from_string (const char *text)
{
  return hcc_soft_f32_result (strtof (text, 0));
}

unsigned long hcc_soft_f64_from_string (const char *text)
{
  return hcc_soft_f64_result (strtod (text, 0));
}

#define HCC_SOFT_F32_BINARY(name, op)                                    \
  unsigned long hcc_soft_f32_##name (unsigned long a, unsigned long b)   \
  { return hcc_soft_f32_result (hcc_soft_f32_value (a)                   \
                                op hcc_soft_f32_value (b)); }

#define HCC_SOFT_F64_BINARY(name, op)                                    \
  unsigned long hcc_soft_f64_##name (unsigned long a, unsigned long b)   \
  { return hcc_soft_f64_result (hcc_soft_f64_value (a)                   \
                                op hcc_soft_f64_value (b)); }

#define HCC_SOFT_F32_COMPARE(name, op)                                   \
  unsigned long hcc_soft_f32_##name (unsigned long a, unsigned long b)   \
  { return hcc_soft_f32_value (a) op hcc_soft_f32_value (b); }

#define HCC_SOFT_F64_COMPARE(name, op)                                   \
  unsigned long hcc_soft_f64_##name (unsigned long a, unsigned long b)   \
  { return hcc_soft_f64_value (a) op hcc_soft_f64_value (b); }

HCC_SOFT_F32_BINARY (add, +)
HCC_SOFT_F32_BINARY (sub, -)
HCC_SOFT_F32_BINARY (mul, *)
HCC_SOFT_F32_BINARY (div, /)
HCC_SOFT_F64_BINARY (add, +)
HCC_SOFT_F64_BINARY (sub, -)
HCC_SOFT_F64_BINARY (mul, *)
HCC_SOFT_F64_BINARY (div, /)

HCC_SOFT_F32_COMPARE (eq, ==)
HCC_SOFT_F32_COMPARE (ne, !=)
HCC_SOFT_F32_COMPARE (lt, <)
HCC_SOFT_F32_COMPARE (le, <=)
HCC_SOFT_F32_COMPARE (gt, >)
HCC_SOFT_F32_COMPARE (ge, >=)
HCC_SOFT_F64_COMPARE (eq, ==)
HCC_SOFT_F64_COMPARE (ne, !=)
HCC_SOFT_F64_COMPARE (lt, <)
HCC_SOFT_F64_COMPARE (le, <=)
HCC_SOFT_F64_COMPARE (gt, >)
HCC_SOFT_F64_COMPARE (ge, >=)

unsigned long hcc_soft_f32_neg (unsigned long value)
{
  return hcc_soft_f32_result (-hcc_soft_f32_value (value));
}

unsigned long hcc_soft_f64_neg (unsigned long value)
{
  return hcc_soft_f64_result (-hcc_soft_f64_value (value));
}

unsigned long hcc_soft_f32_truth (unsigned long value)
{
  return hcc_soft_f32_value (value) != 0.0f;
}

unsigned long hcc_soft_f64_truth (unsigned long value)
{
  return hcc_soft_f64_value (value) != 0.0;
}

unsigned long hcc_soft_f32_from_i64 (long value)
{
  return hcc_soft_f32_result ((float) value);
}

unsigned long hcc_soft_f32_from_u64 (unsigned long value)
{
  return hcc_soft_f32_result ((float) value);
}

unsigned long hcc_soft_f64_from_i64 (long value)
{
  return hcc_soft_f64_result ((double) value);
}

unsigned long hcc_soft_f64_from_u64 (unsigned long value)
{
  return hcc_soft_f64_result ((double) value);
}

unsigned long hcc_soft_f32_to_i64 (unsigned long value)
{
  return (unsigned long) (long) hcc_soft_f32_value (value);
}

unsigned long hcc_soft_f32_to_u64 (unsigned long value)
{
  return (unsigned long) hcc_soft_f32_value (value);
}

unsigned long hcc_soft_f64_to_i64 (unsigned long value)
{
  return (unsigned long) (long) hcc_soft_f64_value (value);
}

unsigned long hcc_soft_f64_to_u64 (unsigned long value)
{
  return (unsigned long) hcc_soft_f64_value (value);
}

unsigned long hcc_soft_f32_to_f64 (unsigned long value)
{
  return hcc_soft_f64_result ((double) hcc_soft_f32_value (value));
}

unsigned long hcc_soft_f64_to_f32 (unsigned long value)
{
  return hcc_soft_f32_result ((float) hcc_soft_f64_value (value));
}
