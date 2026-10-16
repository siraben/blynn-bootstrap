/* Real errors, stream isolation and descriptor reuse in the reduced libc. */
#include <stdio.h>
void clearerr(FILE* stream);
int close(int fd);
#define CHECK(x) if (!(x)) return __LINE__
int main(void)
{
    FILE* bad = fopen("/dev/full", "w");
    FILE* good = fopen("/dev/null", "w");
    FILE* old = bad;
    CHECK(bad && good && !ferror(bad) && !ferror(good));
    CHECK(fprintf(bad, "%s", "output") < 0 && ferror(bad));
    CHECK(fputs("ok", good) == 0 && !ferror(good));
    CHECK(fflush(bad) == 0 && ferror(bad));
    clearerr(bad);
    CHECK(!ferror(bad));
    CHECK(fwrite("output", 2, 3, bad) == 0 && ferror(bad));
    CHECK(fclose(bad) == 0);
    bad = fopen("/dev/null", "w");
    CHECK(bad == old && !ferror(bad));
    CHECK(fclose(good) == 0);
    CHECK(close((int)(long)bad) == 0);
    CHECK(fclose(bad) != 0);
    return 0;
}
