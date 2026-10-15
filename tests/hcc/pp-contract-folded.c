/* These initializers exercise Literal's legacy lowering-facing Int API too. */
int pp_contract_quotient = -5 / 2;
int pp_contract_remainder = -5 % 2;
unsigned int pp_contract_bit31 = 0x80000000U & 0x80000000U;
int pp_contract_shift = -1 >> 31;
int main(void) {
  return pp_contract_quotient != -2 || pp_contract_remainder != -1 ||
    pp_contract_bit31 != 0x80000000U || pp_contract_shift != -1;
}
