#include "tcc-final-overrides.c"

/* Fixed backing storage is sufficient for this formatter contract test. */
char storage[128];
int growths;

void cstr_realloc(CString *cstr, int new_size)
{
    cstr->data = storage;
    cstr->size_allocated = new_size;
    growths = growths + 1;
}

int matches(char *a, char *b)
{
    while (*a && *a == *b) { a = a + 1; b = b + 1; }
    return *a == *b;
}

int main(void)
{
    CString text;
    int count;
    text.size = 0;
    text.size_allocated = 0;
    text.data = 0;
    count = cstr_printf(&text, "%.*s:%ld:%%:%X", 3, (long)"hello", -12, 26);
    if (count != 12 || text.size != 12 || !matches(text.data, "hel:-12:%:1a")) return 1;
    count = cstr_printf(&text, "/%.2s/%c/%u", (long)"abcd", 'Z', 0, 0);
    if (count != 7 || !matches(text.data, "hel:-12:%:1a/ab/Z/0")) return 2;
    count = cstr_printf(&text, "%s", 0, 0, 0, 0);
    if (count != 6 || !matches(text.data, "hel:-12:%:1a/ab/Z/0(null)")) return 3;
    if (growths < 2 || text.size != 25 || text.data[text.size] != 0) return 4;
    return 0;
}
