static unsigned char values[3][5];
static unsigned short initialized[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
static unsigned short (*rows)[3];
static unsigned short *row_pointers[2];

static unsigned char last(unsigned char rows[3][5]) {
  return rows[2][4];
}

int main(void) {
  unsigned short local_rows[2][3];

  values[0][0] = 1;
  values[1][0] = 2;
  values[2][4] = 3;

  if (sizeof(values) != 15) return 1;
  if (sizeof(values[0]) != 5) return 2;
  if ((char *)&values[1][0] - (char *)&values[0][0] != 5) return 3;
  if (values[0][0] != 1 || values[1][0] != 2 || values[2][4] != 3) return 4;
  if (last(values) != 3) return 5;
  if (initialized[0][2] != 3 || initialized[1][0] != 4 ||
      initialized[1][2] != 6) return 6;
  rows = local_rows;
  rows[1][2] = 9;
  if (!rows || local_rows[1][2] != 9) return 7;
  row_pointers[1] = local_rows[1];
  row_pointers[1][0] = 8;
  if (local_rows[1][0] != 8) return 8;
  rows = 0;
  if (rows) return 9;
  return 0;
}
