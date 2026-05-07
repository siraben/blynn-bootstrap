typedef unsigned long size_t;
typedef unsigned long uint64_t;
typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef long time_t;
typedef long ssize_t;

void* malloc(unsigned size);
void free(void* ptr);
void _exit(int value);
int open(char* path, int flags, int mode);
int read(int fd, void* data, size_t size);
int write(int fd, void* data, size_t size);
long lseek(int fd, long offset, int whence);
int close(int fd);
int access(char* path, int mode);

int errno;
char** environ;
void* stdin = (void*)0;
void* stdout = (void*)1;
void* stderr = (void*)2;

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

int memcmp(void* s1, void* s2, size_t size)
{
    unsigned char* a = s1;
    unsigned char* b = s2;
    if (size == 0) return 0;
    while (*a == *b && size > 1) {
        a = a + 1;
        b = b + 1;
        size = size - 1;
    }
    return *a - *b;
}

void* memcpy(void* dest, void* src, size_t n)
{
    char* d = dest;
    char* s = src;
    void* out = dest;
    while (n) {
        *d = *s;
        d = d + 1;
        s = s + 1;
        n = n - 1;
    }
    return out;
}

void* memmove(void* dest, void* src, size_t n)
{
    char* d = dest;
    char* s = src;
    if (d < s) return memcpy(dest, src, n);
    d = d + n;
    s = s + n;
    while (n) {
        d = d - 1;
        s = s - 1;
        *d = *s;
        n = n - 1;
    }
    return dest;
}

void* memset(void* s, int c, size_t n)
{
    unsigned char* p = s;
    void* out = s;
    while (n) {
        *p = c;
        p = p + 1;
        n = n - 1;
    }
    return out;
}

int strlen(char* text)
{
    int n = 0;
    while (text[n]) n = n + 1;
    return n;
}

int strcmp(char* left, char* right)
{
    while (*left && *right && *left == *right) {
        left = left + 1;
        right = right + 1;
    }
    return *left - *right;
}

int strncmp(char* left, char* right, size_t n)
{
    if (n == 0) return 0;
    while (*left && *right && *left == *right && n > 1) {
        left = left + 1;
        right = right + 1;
        n = n - 1;
    }
    return *left - *right;
}

char* strcpy(char* dest, char* src)
{
    char* out = dest;
    while (*src) {
        *dest = *src;
        dest = dest + 1;
        src = src + 1;
    }
    *dest = 0;
    return out;
}

char* strncpy(char* dest, char* src, size_t n)
{
    char* out = dest;
    while (*src && n) {
        *dest = *src;
        dest = dest + 1;
        src = src + 1;
        n = n - 1;
    }
    while (n) {
        *dest = 0;
        dest = dest + 1;
        n = n - 1;
    }
    return out;
}

char* strchr(char* text, int c)
{
    while (*text || c == 0) {
        if (*text == c) return text;
        text = text + 1;
    }
    return 0;
}

char* strrchr(char* text, int c)
{
    char* last = 0;
    while (*text) {
        if (*text == c) last = text;
        text = text + 1;
    }
    if (c == 0) return text;
    return last;
}

char* strcat(char* dest, char* src)
{
    char* out = dest;
    dest = strchr(dest, 0);
    while (*src) {
        *dest = *src;
        dest = dest + 1;
        src = src + 1;
    }
    *dest = 0;
    return out;
}

char* strpbrk(char* text, char* stop)
{
    while (*text) {
        if (strchr(stop, *text)) return text;
        text = text + 1;
    }
    return 0;
}

char* strerror(int value)
{
    return "mes-libc error";
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

void* fopen(char* path, char* mode)
{
    int flags = 0;
    int fd;
    if (mode[0] == 'w') {
        flags = 577;
    } else if (mode[0] == 'a') {
        flags = 1089;
    } else {
        flags = 0;
    }
    fd = open(path, flags, 0600);
    if (fd < 0) return 0;
    return (void*)(long)fd;
}

int fclose(void* stream)
{
    int fd = (int)(long)stream;
    if (fd < 3) return 0;
    return close(fd);
}

int fflush(void* stream)
{
    return 0;
}

int fgetc(void* stream)
{
    unsigned char c;
    int fd = (int)(long)stream;
    if (read(fd, &c, 1) == 1) return c;
    return -1;
}

int fputc(int c, void* stream)
{
    unsigned char ch = c;
    int fd = (int)(long)stream;
    if (write(fd, &ch, 1) == 1) return ch;
    return -1;
}

int fputs(char* text, void* stream)
{
    int fd = (int)(long)stream;
    int n = strlen(text);
    if (write(fd, text, n) < 0) return -1;
    return 0;
}

size_t fread(void* data, size_t size, size_t count, void* stream)
{
    int fd = (int)(long)stream;
    int bytes;
    if (!size || !count) return 0;
    bytes = read(fd, data, size * count);
    if (bytes <= 0) return 0;
    return bytes / size;
}

size_t fwrite(void* data, size_t size, size_t count, void* stream)
{
    int fd = (int)(long)stream;
    int bytes;
    if (!size || !count) return 0;
    bytes = write(fd, data, size * count);
    if (bytes <= 0) return 0;
    return bytes / size;
}

int fseek(void* stream, long offset, int whence)
{
    int fd = (int)(long)stream;
    if (lseek(fd, offset, whence) < 0) return -1;
    return 0;
}

long ftell(void* stream)
{
    int fd = (int)(long)stream;
    return lseek(fd, 0, 1);
}

int gettimeofday(struct timeval* tv, void* tz)
{
    if (tv) {
        tv->tv_sec = 0;
        tv->tv_usec = 0;
    }
    return 0;
}

int sem_init(void* sem, int shared, unsigned value)
{
    if (sem) *(int*)sem = value;
    return 0;
}

int sem_wait(void* sem)
{
    return 0;
}

int sem_post(void* sem)
{
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
void* fdopen(int fd, char* mode)
{
    if (fd < 0) return 0;
    return (void*)(long)fd;
}
char* getenv(char* name) { return 0; }
char* realpath(char* path, char* out)
{
    int n;
    if (!path) return 0;
    if (!out) {
        n = strlen(path) + 1;
        out = malloc(n);
        if (!out) return 0;
    }
    strcpy(out, path);
    return out;
}
int remove(char* path) { return -1; }
int unlink(char* path) { return -1; }
int setjmp(void* env) { return 0; }
void longjmp(void* env, int value) { _exit(value); }

static char* hcc_append_char(char* out, char* end, int* total, int c)
{
    if (out < end) {
        *out = c;
        out = out + 1;
    }
    *total = *total + 1;
    return out;
}

static char* hcc_append_string(char* out, char* end, int* total, char* text)
{
    if (!text) text = "(null)";
    while (*text) {
        out = hcc_append_char(out, end, total, *text);
        text = text + 1;
    }
    return out;
}

static char* hcc_append_unsigned(char* out, char* end, int* total, unsigned long value, int base)
{
    char digits[32];
    int n = 0;
    int digit;
    if (value == 0) return hcc_append_char(out, end, total, '0');
    while (value) {
        digit = value % base;
        if (digit < 10) digits[n] = '0' + digit;
        else digits[n] = 'a' + digit - 10;
        n = n + 1;
        value = value / base;
    }
    while (n) {
        n = n - 1;
        out = hcc_append_char(out, end, total, digits[n]);
    }
    return out;
}

static char* hcc_append_signed(char* out, char* end, int* total, long value)
{
    if (value < 0) {
        out = hcc_append_char(out, end, total, '-');
        value = -value;
    }
    return hcc_append_unsigned(out, end, total, value, 10);
}

static long hcc_format_arg(int index, long a, long b, long c)
{
    if (index == 0) return a;
    if (index == 1) return b;
    return c;
}

static int hcc_vformat(char* out, unsigned size, char* fmt, long a, long b, long c)
{
    char* p = out;
    char* end = out;
    int total = 0;
    int arg = 0;
    long value;
    if (size) end = out + size - 1;
    while (*fmt) {
        if (*fmt != '%') {
            p = hcc_append_char(p, end, &total, *fmt);
            fmt = fmt + 1;
            continue;
        }
        fmt = fmt + 1;
        while (*fmt >= '0' && *fmt <= '9') fmt = fmt + 1;
        if (*fmt == 'l') fmt = fmt + 1;
        value = hcc_format_arg(arg, a, b, c);
        arg = arg + 1;
        if (*fmt == 's') p = hcc_append_string(p, end, &total, (char*)value);
        else if (*fmt == 'd') p = hcc_append_signed(p, end, &total, value);
        else if (*fmt == 'i') p = hcc_append_signed(p, end, &total, value);
        else if (*fmt == 'u') p = hcc_append_unsigned(p, end, &total, value, 10);
        else if (*fmt == 'x') p = hcc_append_unsigned(p, end, &total, value, 16);
        else if (*fmt == 'X') p = hcc_append_unsigned(p, end, &total, value, 16);
        else if (*fmt == 'c') p = hcc_append_char(p, end, &total, value);
        else if (*fmt == '%') {
            p = hcc_append_char(p, end, &total, '%');
            arg = arg - 1;
        } else {
            p = hcc_append_char(p, end, &total, '%');
            p = hcc_append_char(p, end, &total, *fmt);
        }
        if (*fmt) fmt = fmt + 1;
    }
    if (size) *p = 0;
    return total;
}

int printf(char* fmt) { return 0; }
int fprintf(void* stream, char* fmt) { return 0; }
int sprintf(char* out, char* fmt, long a, long b, long c) { return hcc_vformat(out, 0xffffffff, fmt, a, b, c); }
int snprintf(char* out, unsigned size, char* fmt, long a, long b, long c) { return hcc_vformat(out, size, fmt, a, b, c); }
int sscanf(char* input, char* fmt) { return 0; }
int vsnprintf(char* out, unsigned size, char* fmt, void* ap) { if (out && size) out[0] = 0; return 0; }
int vfprintf(void* stream, char* fmt, void* ap) { return fputs(fmt, stream); }
void va_start(void* ap, void* last) {}
void va_end(void* ap) {}
void va_copy(void* dest, void* src) {}
long va_arg(void* ap, long type_hint) { return 0; }

int ELF64_ST_BIND(int value) { return (value >> 4) & 15; }
int ELF64_ST_TYPE(int value) { return value & 15; }
int ELF64_ST_INFO(int bind, int type) { return (bind << 4) + (type & 15); }
int ELF64_ST_VISIBILITY(int value) { return value & 3; }
unsigned long ELF64_R_SYM(unsigned long value) { return value >> 32; }
unsigned long ELF64_R_TYPE(unsigned long value) { return value & 0xffffffff; }
unsigned long ELF64_R_INFO(unsigned long sym, unsigned long type) { return (sym << 32) + type; }
