typedef unsigned long size_t;

#include <sys/stat.h>

void* memset(void* ptr, int value, size_t count);
int fgetc(FILE* stream);
int fputc(int c, FILE* stream);

long read(int fd, void* data, size_t size);
long write(int fd, void* data, size_t size);
int close(int fd);
long lseek(int fd, long offset, int whence);
long brk(void* addr);
char* getcwd(char* buf, size_t size);
int open(char* path, int flags, int mode);
int access(char* path, int mode);
void _exit(int code);
int mprotect(void* addr, size_t len, int prot) { return 0; }

int stat(char const* path, struct stat* buf)
{
    int rc = access((char*)path, 0);
    if (rc < 0) return rc;
    memset(buf, 0, sizeof(struct stat));
    buf->st_mode = S_IFREG;
    return 0;
}

int lstat(char const* path, struct stat* buf)
{
    return stat(path, buf);
}

int getchar(void)
{
    return fgetc((FILE*)0);
}

int putchar(int c)
{
    return fputc(c, (FILE*)1);
}

void __assert_fail(char* expr, char* file, unsigned line, char* function)
{
    _exit(1);
}

static char* hcc_aarch64_brk;
static char* hcc_aarch64_malloc;

void* malloc(unsigned size)
{
    char* out;
    if (!hcc_aarch64_brk) {
        hcc_aarch64_brk = (char*)brk(0);
        hcc_aarch64_malloc = hcc_aarch64_brk;
    }
    if (hcc_aarch64_brk < hcc_aarch64_malloc + size) {
        hcc_aarch64_brk = (char*)brk(hcc_aarch64_malloc + size);
        if ((long)hcc_aarch64_brk < 0) return 0;
    }
    out = hcc_aarch64_malloc;
    hcc_aarch64_malloc = hcc_aarch64_malloc + size;
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
