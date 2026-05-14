typedef unsigned long size_t;

void* memset(void* ptr, int value, size_t count);

long brk(void* addr);
void _exit(int code);

void __assert_fail(char* expr, char* file, unsigned line, char* function)
{
    _exit(1);
}

static char* hcc_riscv64_brk;
static char* hcc_riscv64_malloc;

void* malloc(unsigned size)
{
    char* out;
    if (!hcc_riscv64_brk) {
        hcc_riscv64_brk = (char*)brk(0);
        hcc_riscv64_malloc = hcc_riscv64_brk;
    }
    if (hcc_riscv64_brk < hcc_riscv64_malloc + size) {
        hcc_riscv64_brk = (char*)brk(hcc_riscv64_malloc + size);
        if ((long)hcc_riscv64_brk < 0) return 0;
    }
    out = hcc_riscv64_malloc;
    hcc_riscv64_malloc = hcc_riscv64_malloc + size;
    return out;
}

void* calloc(unsigned count, unsigned size)
{
    void* out = malloc(count * size);
    if (out) memset(out, 0, count * size);
    return out;
}

void free(void* ptr) {}

void exit(int code)
{
    _exit(code);
}
