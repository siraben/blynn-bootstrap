typedef unsigned long size_t;

typedef struct CString {
    int size;
    int size_allocated;
    char *data;
} CString;

void cstr_realloc(CString *cstr, int new_size);

static void hcc_cstr_need(CString *cstr, int extra)
{
    int need = cstr->size + extra + 1;
    if (need > cstr->size_allocated)
        cstr_realloc(cstr, need * 2);
}

static void hcc_cstr_char(CString *cstr, int ch)
{
    hcc_cstr_need(cstr, 1);
    cstr->data[cstr->size] = ch;
    cstr->size = cstr->size + 1;
    cstr->data[cstr->size] = 0;
}

static int hcc_cstr_string(CString *cstr, char *text, int limit)
{
    int n = 0;
    if (!text) text = "(null)";
    while (*text && (limit < 0 || n < limit)) {
        hcc_cstr_char(cstr, *text);
        text = text + 1;
        n = n + 1;
    }
    return n;
}

static int hcc_cstr_unsigned(CString *cstr, unsigned long value, int base)
{
    char digits[32];
    int n = 0;
    int count = 0;
    int digit;
    if (value == 0) {
        hcc_cstr_char(cstr, '0');
        return 1;
    }
    while (value) {
        digit = value % base;
        if (digit < 10) digits[n] = '0' + digit;
        else digits[n] = 'a' + digit - 10;
        n = n + 1;
        value = value / base;
    }
    while (n) {
        n = n - 1;
        hcc_cstr_char(cstr, digits[n]);
        count = count + 1;
    }
    return count;
}

static int hcc_cstr_signed(CString *cstr, long value)
{
    if (value < 0) {
        hcc_cstr_char(cstr, '-');
        return 1 + hcc_cstr_unsigned(cstr, -value, 10);
    }
    return hcc_cstr_unsigned(cstr, value, 10);
}

static long hcc_arg(int index, long a, long b, long c, long d)
{
    if (index == 0) return a;
    if (index == 1) return b;
    if (index == 2) return c;
    return d;
}

int cstr_printf(CString *cstr, char *fmt, long a, long b, long c, long d)
{
    int count = 0;
    int arg = 0;
    int precision;
    long value;
    while (*fmt) {
        if (*fmt != '%') {
            hcc_cstr_char(cstr, *fmt);
            fmt = fmt + 1;
            count = count + 1;
            continue;
        }
        fmt = fmt + 1;
        precision = -1;
        if (*fmt == '.') {
            fmt = fmt + 1;
            if (*fmt == '*') {
                precision = hcc_arg(arg, a, b, c, d);
                arg = arg + 1;
                fmt = fmt + 1;
            } else {
                precision = 0;
                while (*fmt >= '0' && *fmt <= '9') {
                    precision = precision * 10 + *fmt - '0';
                    fmt = fmt + 1;
                }
            }
        } else {
            while (*fmt >= '0' && *fmt <= '9') fmt = fmt + 1;
        }
        if (*fmt == 'l') fmt = fmt + 1;
        value = hcc_arg(arg, a, b, c, d);
        arg = arg + 1;
        if (*fmt == 's') count = count + hcc_cstr_string(cstr, (char*)value, precision);
        else if (*fmt == 'd' || *fmt == 'i') count = count + hcc_cstr_signed(cstr, value);
        else if (*fmt == 'u') count = count + hcc_cstr_unsigned(cstr, value, 10);
        else if (*fmt == 'x' || *fmt == 'X') count = count + hcc_cstr_unsigned(cstr, value, 16);
        else if (*fmt == 'c') {
            hcc_cstr_char(cstr, value);
            count = count + 1;
        } else if (*fmt == '%') {
            hcc_cstr_char(cstr, '%');
            count = count + 1;
            arg = arg - 1;
        } else {
            hcc_cstr_char(cstr, '%');
            hcc_cstr_char(cstr, *fmt);
            count = count + 2;
        }
        if (*fmt) fmt = fmt + 1;
    }
    return count;
}
