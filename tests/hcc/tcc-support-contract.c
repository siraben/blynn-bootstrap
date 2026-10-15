/* Inject only short/failed writes. Real descriptor lifecycle/read errors are
 * covered by tcc-support-io.c; this is not a replacement bootstrap libc. */
#define write support_test_write
#include "tcc-bootstrap-support.c"

static int written;
static int fail_after = -1;
static int failure = -5;
static char captured[8];
int support_test_write(int fd, void* data, size_t size)
{
    int n = size > 2 ? 2 : size;
    if (fail_after >= 0 && written >= fail_after) return failure;
    memcpy(captured + written, data, n);
    written = written + n;
    return n;
}

#define CHECK(x) if (!(x)) return __LINE__
int main(void)
{
    void* stream = fopen("/dev/null", "w");
    CHECK(stream && !ferror(stream));
    CHECK(fwrite("abcdef", 3, 2, stream) == 2);
    CHECK(written == 6 && !memcmp(captured, "abcdef", 6));
    written = 0;
    fail_after = 2;
    CHECK(fputs("abcdef", stream) < 0 && ferror(stream) && written == 2);
    fail_after = -1;
    CHECK(fputc('x', stream) == 'x' && ferror(stream));
    CHECK(fflush(stream) == 0 && ferror(stream));
    clearerr(stream);
    written = 0;
    fail_after = 2;
    CHECK(fwrite("abcdef", 3, 2, stream) == 0 && ferror(stream));
    clearerr(stream);
    written = 0;
    fail_after = 4;
    failure = 0;
    CHECK(fwrite("abcdef", 3, 2, stream) == 1 && ferror(stream));
    clearerr(stream);
    written = 0;
    fail_after = 0;
    failure = -5;
    CHECK(fprintf(stream, "%s", (long)"abc", 0, 0) < 0 && ferror(stream));
    CHECK(!ferror(stdout) && !ferror(stderr));
    clearerr(stream);
    CHECK(fwrite(captured, 0, 8, stream) == 0 && !ferror(stream));
    CHECK(fwrite(captured, (size_t)-1 / 2 + 1, 2, stream) == 0 && ferror(stream));
    return fclose(stream) != 0;
}
