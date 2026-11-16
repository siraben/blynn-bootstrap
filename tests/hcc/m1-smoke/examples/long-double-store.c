/* A long-double store clears all 16 bytes of a zero value. */
union Wide { long double value; unsigned char bytes[16]; };
int main(void) {
    union Wide wide;
    int i;
    for (i = 0; i < 16; i = i + 1) wide.bytes[i] = 99;
    wide.value = 0.0L;
    for (i = 0; i < 16; i = i + 1) if (wide.bytes[i] != 0) return 1;
    return 0;
}
