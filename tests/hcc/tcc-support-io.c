/* Real Linux descriptors, linked to the reduced AArch64/RISC-V libc.a. */
#include <stdio.h>
void clearerr(FILE* stream);
FILE* freopen(char const* path, char const* mode, FILE* stream);
int close(int fd);

#define CHECK(x) if (!(x)) return __LINE__
int main(void)
{
    FILE* bad = fopen("/dev/full", "w");
    FILE* good = fopen("/dev/null", "w");
    FILE* old;
    FILE* input;
    char data[4];
    CHECK(bad && good && !ferror(bad) && !ferror(good));
    CHECK(fputs("output", bad) < 0 && ferror(bad));
    CHECK(!ferror(good) && !ferror(stderr));
    CHECK(fflush(bad) == 0 && ferror(bad));
    clearerr(bad);
    CHECK(!ferror(bad));
    CHECK(fprintf(bad, "%s", "output") < 0 && ferror(bad));
    clearerr(bad);
    CHECK(fwrite("output", 2, 3, bad) == 0 && ferror(bad));
    CHECK(fputc('x', bad) < 0 && ferror(bad));
    CHECK(fputs("ok", good) == 0 && !ferror(good));
    /* A read error sets the same stream's indicator; a successful write does
     * not erase it. EOF on a readable descriptor must not set the indicator. */
    CHECK(fgetc(good) < 0 && ferror(good));
    CHECK(fputc('x', good) == 'x' && ferror(good));
    clearerr(good);
    CHECK(fread(data, 1, 4, good) == 0 && ferror(good));
    input = fopen("/dev/null", "r");
    CHECK(input && !ferror(input));
    CHECK(fgetc(input) < 0 && !ferror(input));
    CHECK(fread(data, 1, 4, input) == 0 && !ferror(input));
    CHECK(fclose(input) == 0);
    old = bad;
    CHECK(fclose(bad) == 0);
    bad = fopen("/dev/null", "w");
    CHECK(bad == old && !ferror(bad));
    CHECK(fputs("ok", bad) == 0 && !ferror(bad));
    good = freopen("/dev/null", "w", good);
    CHECK(good && !ferror(good));
    CHECK(fclose(good) == 0);
    /* Real EBADF at close, not a mock or an earlier write failure. */
    CHECK(close((int)(long)bad) == 0);
    CHECK(fclose(bad) != 0);
    return 0;
}
