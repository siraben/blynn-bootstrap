/* Host-controlled syscall/allocator fault injection, not a libc replacement
 * in a bootstrap route. Compile with -I hcc/support (GCC: -fno-builtin).
 * The same production source is separately exercised with real target syscalls.
 */
#define read support_test_read
#define write support_test_write
#define open support_test_open
#define close support_test_close
#define malloc support_test_malloc
#include "tcc-bootstrap-support.c"

static char arena[4096];
static int allocated;
static int fail_alloc;
static int next_fd = 3;
static int close_result;
static int closed_fd;
static int read_result;
static int write_limit = 2;
static int write_fail_after = -1;
static int write_failure = -5;
static int written;
static char captured[64];

void* support_test_malloc(unsigned size)
{
    char* p;
    if (fail_alloc || allocated + size > sizeof(arena)) return 0;
    p = arena + allocated;
    allocated = allocated + size;
    return p;
}
int support_test_open(char* path, int flags, int mode) { return next_fd; }
int support_test_close(int fd) { closed_fd = fd; return close_result; }
int support_test_read(int fd, void* data, size_t size)
{
    if (read_result > 0) *(char*)data = 'r';
    return read_result;
}
int support_test_write(int fd, void* data, size_t size)
{
    int n = size;
    if (write_fail_after >= 0 && written >= write_fail_after) return write_failure;
    if (n > write_limit) n = write_limit;
    memcpy(captured + written, data, n);
    written = written + n;
    return n;
}

#define CHECK(x) if (!(x)) return __LINE__
int main(void)
{
    void* a;
    void* b;
    char data[8];
    int storage;
    a = fopen("a", "w");
    CHECK(a && !ferror(a));
    next_fd = 4;
    b = fopen("b", "w");
    CHECK(b && !ferror(b));
    CHECK(!ferror(stdin) && !ferror(stdout) && !ferror(stderr));
    CHECK(fputs("abcdef", a) == 0);
    CHECK(written == 6 && !memcmp(captured, "abcdef", 6));
    CHECK(!ferror(a));
    written = 0;
    write_fail_after = 2;
    CHECK(fputs("abcdef", a) < 0 && ferror(a));
    CHECK(written == 2 && !ferror(b) && !ferror(stdout));
    CHECK(fflush(a) == 0 && ferror(a));
    write_fail_after = -1;
    CHECK(fputc('x', a) == 'x' && ferror(a));
    clearerr(a);
    CHECK(!ferror(a));
    written = 0;
    write_fail_after = 2;
    write_failure = 0;
    CHECK(fwrite("abcdef", 3, 2, a) == 0 && ferror(a));
    clearerr(a);
    written = 0;
    write_fail_after = 4;
    CHECK(fwrite("abcdef", 3, 2, a) == 1 && ferror(a));
    clearerr(a);
    written = 0;
    write_fail_after = -1;
    CHECK(fwrite("abcdef", 3, 2, a) == 2 && !ferror(a));
    CHECK(written == 6 && !memcmp(captured, "abcdef", 6));
    written = 0;
    write_fail_after = 0;
    write_failure = -5;
    CHECK(fputc('x', stdout) < 0 && ferror(stdout));
    CHECK(!ferror(stderr) && !ferror(a));
    CHECK(fprintf(a, "%s", (long)"abc", 0, 0) < 0 && ferror(a));
    clearerr(a);
    CHECK(fwrite(data, 0, 8, a) == 0 && !ferror(a));
    CHECK(fwrite(data, 8, 0, a) == 0 && !ferror(a));
    CHECK(fwrite(data, (size_t)-1, 2, a) == 0 && ferror(a));
    clearerr(a);
    read_result = 0;
    CHECK(fgetc(a) < 0 && !ferror(a)); /* EOF is not an error. */
    CHECK(fread(data, 1, 8, a) == 0 && !ferror(a));
    read_result = -5;
    CHECK(fgetc(a) < 0 && ferror(a));
    clearerr(a);
    CHECK(fread(data, 1, 8, a) == 0 && ferror(a));
    read_result = 1;
    CHECK(fgetc(a) == 'r' && ferror(a));
    CHECK(!ferror(b) && !ferror(stderr));
    CHECK(fclose(a) == 0 && closed_fd == 3);
    storage = allocated;
    next_fd = 3;
    a = fopen("a", "w");
    CHECK(a && !ferror(a) && allocated == storage);
    CHECK(fputc('x', a) < 0 && ferror(a));
    close_result = -5;
    CHECK(fclose(a) < 0); /* Never hide a real close failure. */
    close_result = 0;
    a = fdopen(3, "w");
    CHECK(a && !ferror(a));
    CHECK(fputc('x', a) < 0 && ferror(a));
    next_fd = 5;
    a = freopen("new", "w", a);
    CHECK(a && !ferror(a) && closed_fd == 3);
    a = fdopen(3, "w");
    CHECK(a && !ferror(a));
    next_fd = 6;
    fail_alloc = 1;
    CHECK(!fopen("oom", "w") && closed_fd == 6);
    CHECK(!fdopen(7, "w"));
    CHECK(!ferror(b) && ferror(stdout));
    return 0;
}
