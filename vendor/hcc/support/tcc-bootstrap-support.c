typedef unsigned long size_t;
typedef unsigned long uint64_t;
typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef long time_t;

void* malloc(unsigned size);
void free(void* ptr);
void _exit(int value);
int strcmp(char* left, char* right);
int strlen(char* text);
void* memcpy(void* dest, void* src, size_t n);

int errno;

struct timeval {
    long tv_sec;
    long tv_usec;
};

struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
};

struct tm hcc_support_tm;

static int digit_value(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'z') return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return -1;
}

static unsigned long parse_unsigned(char* nptr, char** endptr, int base)
{
    char* p = nptr;
    unsigned long value = 0;
    int digit;

    while (*p == ' ' || *p == '\t' || *p == '\n') p = p + 1;
    if (base == 0) {
        base = 10;
        if (p[0] == '0') {
            base = 8;
            p = p + 1;
            if (p[0] == 'x' || p[0] == 'X') {
                base = 16;
                p = p + 1;
            }
        }
    }
    while (1) {
        digit = digit_value(*p);
        if (digit < 0 || digit >= base) break;
        value = value * base + digit;
        p = p + 1;
    }
    if (endptr) *endptr = p;
    return value;
}

long strtol(char* nptr, char** endptr, int base)
{
    char* p = nptr;
    int negative = 0;
    while (*p == ' ' || *p == '\t' || *p == '\n') p = p + 1;
    if (*p == '-') {
        negative = 1;
        p = p + 1;
    } else if (*p == '+') {
        p = p + 1;
    }
    if (negative) return -((long)parse_unsigned(p, endptr, base));
    return (long)parse_unsigned(p, endptr, base);
}

unsigned long strtoul(char* nptr, char** endptr, int base)
{
    return parse_unsigned(nptr, endptr, base);
}

unsigned long strtoull(char* nptr, char** endptr, int base)
{
    return parse_unsigned(nptr, endptr, base);
}

int atoi(char* nptr)
{
    return strtol(nptr, 0, 10);
}

long strtod(char* nptr, char** endptr)
{
    return strtol(nptr, endptr, 10);
}

long strtof(char* nptr, char** endptr)
{
    return strtod(nptr, endptr);
}

long strtold(char* nptr, char** endptr)
{
    return strtod(nptr, endptr);
}

long ldexp(long value, int exp)
{
    while (exp > 0) {
        value = value * 2;
        exp = exp - 1;
    }
    while (exp < 0) {
        value = value / 2;
        exp = exp + 1;
    }
    return value;
}

void abort()
{
    _exit(1);
}

int assert(int value)
{
    if (!value) abort();
    return 0;
}

void* realloc(void* ptr, unsigned size)
{
    void* next = malloc(size);
    if (ptr && next) memcpy(next, ptr, size);
    return next;
}

char* strstr(char* haystack, char* needle)
{
    char* h;
    char* n;
    char* start;
    if (!needle[0]) return haystack;
    while (*haystack) {
        start = haystack;
        h = haystack;
        n = needle;
        while (*h && *n && *h == *n) {
            h = h + 1;
            n = n + 1;
        }
        if (!*n) return start;
        haystack = haystack + 1;
    }
    return 0;
}

static void swap_bytes(char* left, char* right, unsigned size)
{
    char tmp;
    while (size) {
        tmp = *left;
        *left = *right;
        *right = tmp;
        left = left + 1;
        right = right + 1;
        size = size - 1;
    }
}

void qsort(void* base, unsigned count, unsigned size, int (*compar)(void*, void*))
{
    char* bytes = base;
    unsigned i;
    unsigned j;
    if (!base || !compar) return;
    for (i = 0; i < count; i = i + 1) {
        for (j = i + 1; j < count; j = j + 1) {
            if (compar(bytes + i * size, bytes + j * size) > 0)
                swap_bytes(bytes + i * size, bytes + j * size, size);
        }
    }
}

int gettimeofday(struct timeval* tv, void* tz)
{
    if (tv) {
        tv->tv_sec = 0;
        tv->tv_usec = 0;
    }
    return 0;
}

time_t time(time_t* out)
{
    if (out) *out = 0;
    return 0;
}

struct tm* localtime(time_t* value)
{
    hcc_support_tm.tm_mday = 1;
    hcc_support_tm.tm_year = 70;
    return &hcc_support_tm;
}

int execvp(char* file, char** argv) { return -1; }
void* fdopen(int fd, char* mode) { return 0; }
char* getenv(char* name) { return 0; }
int remove(char* path) { return -1; }
int unlink(char* path) { return -1; }
int setjmp(void* env) { return 0; }
void longjmp(void* env, int value) { _exit(value); }

int printf(char* fmt) { return 0; }
int fprintf(void* stream, char* fmt) { return 0; }
int sprintf(char* out, char* fmt) { if (out) out[0] = 0; return 0; }
int snprintf(char* out, unsigned size, char* fmt) { if (out && size) out[0] = 0; return 0; }
int sscanf(char* input, char* fmt) { return 0; }
int vsnprintf(char* out, unsigned size, char* fmt, void* ap) { if (out && size) out[0] = 0; return 0; }
void va_start(void* ap, void* last) {}
void va_end(void* ap) {}

int ELF64_ST_BIND(int value) { return (value >> 4) & 15; }
int ELF64_ST_TYPE(int value) { return value & 15; }
int ELF64_ST_INFO(int bind, int type) { return (bind << 4) + (type & 15); }
int ELF64_ST_VISIBILITY(int value) { return value & 3; }
unsigned long ELF64_R_SYM(unsigned long value) { return value >> 32; }
unsigned long ELF64_R_TYPE(unsigned long value) { return value & 0xffffffff; }
unsigned long ELF64_R_INFO(unsigned long sym, unsigned long type) { return (sym << 32) + type; }
