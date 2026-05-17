typedef unsigned long size_t;
typedef unsigned long uint64_t;
typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef long time_t;
typedef long ssize_t;

#ifdef __TINYC__
#include <stdarg.h>
#endif

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

int asm_parse_regvar(int t)
{
    return -1;
}

int sigaction(int signum, void* act, void* oldact) { return 0; }
int sigaddset(void* set, int signum) { return 0; }
int sigemptyset(void* set) { return 0; }
int sigprocmask(int how, void* set, void* oldset) { return 0; }

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

unsigned long long strtoull(char* nptr, char** endptr, int base)
{
    return parse_unsigned(nptr, endptr, base);
}

long long strtoll(char* nptr, char** endptr, int base)
{
    return strtol(nptr, endptr, base);
}

int atoi(char* nptr)
{
    return strtol(nptr, 0, 10);
}

union hcc_double_bits {
    unsigned long u;
    double d;
};

static double hcc_double_from_bits(unsigned long bits)
{
    union hcc_double_bits out;
    out.u = bits;
    return out.d;
}

static double hcc_double_from_scaled_uint64(unsigned long mantissa, int exp2)
{
    unsigned long hidden = 0x10000000000000UL;
    unsigned long overflow = 0x20000000000000UL;
    unsigned long fraction;
    int exponent;

    if (mantissa == 0) return hcc_double_from_bits(0);
    while (mantissa >= overflow) {
        mantissa = (mantissa + 1) >> 1;
        exp2 = exp2 + 1;
    }
    while (mantissa < hidden) {
        mantissa = mantissa << 1;
        exp2 = exp2 - 1;
    }

    exponent = exp2 + 52;
    if (exponent <= -1023) return hcc_double_from_bits(0);
    if (exponent >= 1024) return hcc_double_from_bits(0x7ff0000000000000UL);

    fraction = mantissa - hidden;
    return hcc_double_from_bits((((unsigned long)(exponent + 1023)) << 52) | fraction);
}

double strtod(char* nptr, char** endptr)
{
    long value = strtol(nptr, endptr, 10);
    if (value < 0) return -hcc_double_from_scaled_uint64((unsigned long)(0 - value), 0);
    return hcc_double_from_scaled_uint64((unsigned long)value, 0);
}

float strtof(char* nptr, char** endptr)
{
    return (float)strtod(nptr, endptr);
}

long double strtold(char* nptr, char** endptr)
{
    return (long double)strtod(nptr, endptr);
}

double ldexp(double value, int exp)
{
    return hcc_double_from_scaled_uint64((unsigned long)value, exp);
}

long double ldexpl(long double value, int exp)
{
    return (long double)hcc_double_from_scaled_uint64((unsigned long)value, exp);
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

static void swap_bytes(char* left, char* right, size_t size)
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

void qsort(void* base, size_t count, size_t size, int (*compar)(const void*, const void*))
{
    char* bytes = base;
    size_t i;
    size_t j;
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
    int update = 0;
    char* p = mode;
    while (*p) {
        if (*p == '+') update = 1;
        p = p + 1;
    }
    if (mode[0] == 'w') {
        if (update) flags = 578;
        else flags = 577;
    } else if (mode[0] == 'a') {
        if (update) flags = 1090;
        else flags = 1089;
    } else {
        flags = 0;
    }
    fd = open(path, flags, 0600);
    while (fd >= 0 && fd < 3) fd = open(path, flags, 0600);
    if (fd < 0) return 0;
    return (void*)(long)fd;
}

void* freopen(char* path, char* mode, void* stream)
{
    void* next = fopen(path, mode);
    if (next && stream && stream != stdin && stream != stdout && stream != stderr)
        close((int)(long)stream);
    return next;
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

static char* hcc_append_string_limit(char* out, char* end, int* total, char* text, int limit)
{
    int n = 0;
    if (!text) text = "(null)";
    while (*text && (limit < 0 || n < limit)) {
        out = hcc_append_char(out, end, total, *text);
        text = text + 1;
        n = n + 1;
    }
    return out;
}

static int hcc_string_len(char* text)
{
    int n = 0;
    if (!text) text = "(null)";
    while (text[n]) n = n + 1;
    return n;
}

static int hcc_string_n_len(char* text, int limit)
{
    int n = 0;
    if (!text) text = "(null)";
    while (text[n] && (limit < 0 || n < limit)) n = n + 1;
    return n;
}

static int hcc_unsigned_len(unsigned long value, int base)
{
    int n = 1;
    while (value >= (unsigned long)base) {
        value = value / base;
        n = n + 1;
    }
    return n;
}

static int hcc_signed_len(long value)
{
    if (value < 0) return 1 + hcc_unsigned_len(-value, 10);
    return hcc_unsigned_len(value, 10);
}

static char* hcc_append_padding(char* out, char* end, int* total, int width, int used)
{
    while (width > used) {
        out = hcc_append_char(out, end, total, ' ');
        width = width - 1;
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
    int left;
    int width;
    int used;
    long value;
    if (size) end = out + size - 1;
    while (*fmt) {
        if (*fmt != '%') {
            p = hcc_append_char(p, end, &total, *fmt);
            fmt = fmt + 1;
            continue;
        }
        fmt = fmt + 1;
        left = 0;
        width = 0;
        if (*fmt == '-') {
            left = 1;
            fmt = fmt + 1;
        }
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + *fmt - '0';
            fmt = fmt + 1;
        }
        if (*fmt == 'l') fmt = fmt + 1;
        value = hcc_format_arg(arg, a, b, c);
        arg = arg + 1;
        if (*fmt == 's') {
            used = hcc_string_len((char*)value);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_string(p, end, &total, (char*)value);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'd' || *fmt == 'i') {
            used = hcc_signed_len(value);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_signed(p, end, &total, value);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'u') {
            used = hcc_unsigned_len(value, 10);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_unsigned(p, end, &total, value, 10);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'x' || *fmt == 'X') {
            used = hcc_unsigned_len(value, 16);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_unsigned(p, end, &total, value, 16);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'c') {
            if (!left) p = hcc_append_padding(p, end, &total, width, 1);
            p = hcc_append_char(p, end, &total, value);
            if (left) p = hcc_append_padding(p, end, &total, width, 1);
        }
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
int fprintf(void* stream, char* fmt, long a, long b, long c)
{
    char buffer[1024];
    int n = hcc_vformat(buffer, 1024, fmt, a, b, c);
    fputs(buffer, stream);
    return n;
}
int sprintf(char* out, char* fmt, long a, long b, long c) { return hcc_vformat(out, 0xffffffff, fmt, a, b, c); }
int snprintf(char* out, unsigned size, char* fmt, long a, long b, long c) { return hcc_vformat(out, size, fmt, a, b, c); }
int sscanf(char* input, char* fmt) { return 0; }
#ifdef __TINYC__
int vsnprintf(char* out, unsigned size, char* fmt, va_list ap)
{
    char* p = out;
    char* end = out;
    int total = 0;
    int left;
    int width;
    int precision;
    int is_long;
    int used;
    long value;
    char* text;
    if (size) end = out + size - 1;
    while (*fmt) {
        if (*fmt != '%') {
            p = hcc_append_char(p, end, &total, *fmt);
            fmt = fmt + 1;
            continue;
        }
        fmt = fmt + 1;
        left = 0;
        width = 0;
        precision = -1;
        is_long = 0;
        if (*fmt == '-') {
            left = 1;
            fmt = fmt + 1;
        }
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + *fmt - '0';
            fmt = fmt + 1;
        }
        if (*fmt == '.') {
            fmt = fmt + 1;
            if (*fmt == '*') {
                precision = va_arg(ap, int);
                fmt = fmt + 1;
            } else {
                precision = 0;
                while (*fmt >= '0' && *fmt <= '9') {
                    precision = precision * 10 + *fmt - '0';
                    fmt = fmt + 1;
                }
            }
        }
        if (*fmt == 'l') {
            is_long = 1;
            fmt = fmt + 1;
            if (*fmt == 'l') fmt = fmt + 1;
        }
        if (*fmt == 's') {
            text = va_arg(ap, char*);
            used = hcc_string_n_len(text, precision);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_string_limit(p, end, &total, text, precision);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'd' || *fmt == 'i') {
            if (is_long) value = va_arg(ap, long);
            else value = va_arg(ap, int);
            used = hcc_signed_len(value);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_signed(p, end, &total, value);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'u') {
            if (is_long) value = va_arg(ap, unsigned long);
            else value = va_arg(ap, unsigned int);
            used = hcc_unsigned_len(value, 10);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_unsigned(p, end, &total, value, 10);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'x' || *fmt == 'X') {
            if (is_long) value = va_arg(ap, unsigned long);
            else value = va_arg(ap, unsigned int);
            used = hcc_unsigned_len(value, 16);
            if (!left) p = hcc_append_padding(p, end, &total, width, used);
            p = hcc_append_unsigned(p, end, &total, value, 16);
            if (left) p = hcc_append_padding(p, end, &total, width, used);
        } else if (*fmt == 'c') {
            value = va_arg(ap, int);
            if (!left) p = hcc_append_padding(p, end, &total, width, 1);
            p = hcc_append_char(p, end, &total, value);
            if (left) p = hcc_append_padding(p, end, &total, width, 1);
        } else if (*fmt == '%') {
            p = hcc_append_char(p, end, &total, '%');
        } else {
            p = hcc_append_char(p, end, &total, '%');
            p = hcc_append_char(p, end, &total, *fmt);
        }
        if (*fmt) fmt = fmt + 1;
    }
    if (out && size) *p = 0;
    return total;
}
#else
int vsnprintf(char* out, unsigned size, char* fmt, void* ap)
{
    int total = 0;
    char* p = out;
    char* end = out;
    if (size) end = out + size - 1;
    while (*fmt) {
        if (*fmt == '%' && fmt[1] && fmt[1] != '%') {
            fmt = fmt + 1;
            while (*fmt >= '0' && *fmt <= '9') fmt = fmt + 1;
            if (*fmt == 'l') fmt = fmt + 1;
        } else {
            if (*fmt == '%' && fmt[1] == '%') fmt = fmt + 1;
            p = hcc_append_char(p, end, &total, *fmt);
        }
        if (*fmt) fmt = fmt + 1;
    }
    if (out && size) *p = 0;
    return total;
}
#endif
#ifdef __TINYC__
int vfprintf(void* stream, char* fmt, va_list ap) { return fputs(fmt, stream); }
int vprintf(char* fmt, va_list ap) { return vfprintf(stdout, fmt, ap); }
int vsprintf(char* out, char* fmt, va_list ap) { return vsnprintf(out, 0xffffffff, fmt, ap); }
int vsscanf(char* input, char* fmt, va_list ap) { return 0; }
int vfscanf(void* stream, char* fmt, va_list ap) { return 0; }
#else
int vfprintf(void* stream, char* fmt, void* ap) { return fputs(fmt, stream); }
int vprintf(char* fmt, void* ap) { return vfprintf(stdout, fmt, ap); }
int vsprintf(char* out, char* fmt, void* ap) { return vsnprintf(out, 0xffffffff, fmt, ap); }
int vsscanf(char* input, char* fmt, void* ap) { return 0; }
int vfscanf(void* stream, char* fmt, void* ap) { return 0; }
void va_start(void* ap, void* last) {}
void va_end(void* ap) {}
void va_copy(void* dest, void* src) {}
long va_arg(void* ap, long type_hint) { return 0; }
#endif

int ELF64_ST_BIND(int value) { return (value >> 4) & 15; }
int ELF64_ST_TYPE(int value) { return value & 15; }
int ELF64_ST_INFO(int bind, int type) { return (bind << 4) + (type & 15); }
int ELF64_ST_VISIBILITY(int value) { return value & 3; }
unsigned long ELF64_R_SYM(unsigned long value) { return value >> 32; }
unsigned long ELF64_R_TYPE(unsigned long value) { return value & 0xffffffff; }
unsigned long ELF64_R_INFO(unsigned long sym, unsigned long type) { return (sym << 32) + type; }
