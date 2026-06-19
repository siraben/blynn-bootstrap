int oct_values[3] = {0, 017, 0777};
char char_values[5] = {'a', '\n', '\0', '\\'};
int short_circuit_or[(1 || (1 / 0)) ? 2 : 1];
int short_circuit_and[(0 && (1 / 0)) ? 1 : 2];

int literal_acceptance(void) {
  return oct_values[1] + char_values[0] + short_circuit_or[0] + short_circuit_and[0];
}
