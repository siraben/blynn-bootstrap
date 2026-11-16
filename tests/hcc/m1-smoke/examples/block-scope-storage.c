/* A static local keeps its value between calls. A block-scope extern
   declaration names the file-scope object. */
int total = 40;

static int next(void) {
    static int count = 5;
    count = count + 1;
    return count;
}

static char *buffer(void) {
    static char bytes[8];
    return bytes;
}

static const char *name(int index) {
    static const char *const names[] = {"zero", "one", "two"};
    if (sizeof(names) != 3 * sizeof(char *)) return "";
    return names[index];
}

static int shadow(void) {
    static int total = 1;
    total = total + 1;
    {
        extern int total;
        extern int later;
        total = total + later;
    }
    return total;
}

/* A storage class is also valid after the type specifier. */
static int after_type(void) {
    int static count = 5;
    {
        int extern later;
        count = count + later;
    }
    return count;
}

int later = 2;

int main(void) {
    char *bytes;

    if (next() != 6 || next() != 7) return 1;
    bytes = buffer();
    bytes[7] = 'x';
    if (buffer()[7] != 'x') return 2;
    if (name(1)[1] != 'n' || name(2)[0] != 't') return 3;
    if (shadow() != 2 || shadow() != 3) return 4;
    if (total != 44) return 5;
    if (after_type() != 7 || after_type() != 9) return 6;
    return 0;
}
