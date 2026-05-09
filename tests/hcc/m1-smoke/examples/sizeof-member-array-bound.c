int streq(char *a, char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++;
        b++;
    }
    return *a == *b;
}

int strlen2(char *s) {
    int len;
    len = 0;
    while (s[len]) len++;
    return len;
}

struct BufferedFile {
    char *buf_ptr;
    char filename[1024];
    char filename2[1024];
};

struct BufferedFile file_obj;
struct BufferedFile *file;
int ch;

void inp(void) {
    ch = *(++file->buf_ptr);
}

void skip_spaces(void) {
    while (ch == ' ' || ch == 9) inp();
}

char *tcc_basename(char *name) {
    char *p;
    p = name;
    while (*p) p++;
    while (p > name && p[-1] != '/') --p;
    return p;
}

char *pstrcpy(char *buf, int buf_size, char *s) {
    char *q;
    char *q_end;
    int c;
    if (buf_size > 0) {
        q = buf;
        q_end = buf + buf_size - 1;
        while (q < q_end) {
            c = *s++;
            if (c == 0) break;
            *q++ = c;
        }
        *q = 0;
    }
    return buf;
}

char *pstrcat(char *buf, int buf_size, char *s) {
    int len;
    len = strlen2(buf);
    if (len < buf_size) pstrcpy(buf + len, buf_size - len, s);
    return buf;
}

char *pstrncpy(char *out, char *in, int num) {
    int i;
    i = 0;
    while (i < num) {
        out[i] = in[i];
        i++;
    }
    out[num] = 0;
    return out;
}

int main() {
    char line[128];
    char buf[sizeof file->filename];
    char *q;
    int c;

    pstrcpy(line, 128, " \"include-smoke-header.h\"");
    file = &file_obj;
    file->buf_ptr = line;
    pstrcpy(file->filename2, sizeof file->filename2, "/tmp/include-smoke-main.c");

    ch = file->buf_ptr[0];
    skip_spaces();
    if (ch != '"') return 2;
    c = ch;
    inp();
    q = buf;
    while (ch != c && ch != 10 && ch != -1) {
        if ((q - buf) < sizeof(buf) - 1) *q++ = ch;
        inp();
    }
    *q = 0;
    if (!streq(buf, "include-smoke-header.h")) return 3;

    {
        char buf1[sizeof file->filename];
        char *path;
        path = file->filename2;
        pstrncpy(buf1, path, tcc_basename(path) - path);
        pstrcat(buf1, sizeof(buf1), buf);
        return streq(buf1, "/tmp/include-smoke-header.h") ? 0 : 4;
    }
}
