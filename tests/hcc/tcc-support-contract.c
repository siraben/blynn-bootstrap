/* Only short/zero writes need injection; other I/O uses real descriptors. */
#define write support_test_write
#include "tcc-bootstrap-support.c"

static int written, stop = -1;
static char captured[8];
int support_test_write(int fd, void* data, size_t size)
{
    int n = size > 2 ? 2 : size;
    if (stop >= 0 && written >= stop) return 0;
    memcpy(captured + written, data, n);
    written += n;
    return n;
}

#define CHECK(x) if (!(x)) return __LINE__
int main(void)
{
    void* stream = fopen("/dev/null", "w");
    CHECK(stream && !ferror(stream));
    CHECK(fwrite("abcdef", 3, 2, stream) == 2 && written == 6);
    CHECK(!memcmp(captured, "abcdef", 6));
    written = 0;
    stop = 4;
    CHECK(fwrite("abcdef", 3, 2, stream) == 1 && written == 4 && ferror(stream));
    return fclose(stream) != 0;
}
