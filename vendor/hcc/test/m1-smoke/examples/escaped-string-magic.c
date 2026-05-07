int memcmp(void *a, void *b, unsigned long n) {
    unsigned char *x;
    unsigned char *y;
    x = a;
    y = b;
    while (n) {
        if (*x != *y) return *x - *y;
        x++;
        y++;
        n--;
    }
    return 0;
}

int main() {
    unsigned char elf[4];
    elf[0] = 127;
    elf[1] = 'E';
    elf[2] = 'L';
    elf[3] = 'F';
    if (memcmp(elf, "\177ELF", 4) != 0) return 1;
    if ('\177' != 127) return 2;
    if ("\x7f"[0] != 127) return 3;
    return 0;
}
