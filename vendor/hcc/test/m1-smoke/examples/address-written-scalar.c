void set_int(int *p) {
    *p = -1;
}

void set_char(unsigned char *p) {
    *p = 255;
}

int main() {
    int x;
    unsigned char c;
    set_int(&x);
    set_char(&c);
    if (!(x <= 0)) return 1;
    if (x != -1) return 2;
    if (c != 255) return 3;
    return 0;
}
