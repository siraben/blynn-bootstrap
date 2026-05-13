typedef unsigned long uint64_t;

static int cmp_u(uint64_t a, uint64_t b)
{
    return a < b ? -1 : a > b;
}

static int cmp_s(uint64_t a, uint64_t b)
{
    return (long)a < (long)b ? -1 : (long)a > (long)b;
}

int main(void)
{
    if (cmp_u(37, 99) != -1)
        return 1;
    if (cmp_u(99, 37) != 1)
        return 2;
    if (cmp_u(99, 99) != 0)
        return 3;
    if (cmp_s(37, 99) != -1)
        return 4;
    if (cmp_s(99, 37) != 1)
        return 5;
    if (cmp_s(99, 99) != 0)
        return 6;
    return 0;
}
