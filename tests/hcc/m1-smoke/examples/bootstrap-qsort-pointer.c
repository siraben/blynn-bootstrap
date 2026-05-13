typedef unsigned long uint64_t;

struct case_t {
    uint64_t v1;
    uint64_t v2;
};

static void swap_bytes(char *left, char *right, unsigned size)
{
    char tmp;
    while (size) {
        tmp = *left;
        *left = *right;
        *right = tmp;
        left = left + 1;
        right = right + 1;
        size = size - 1;
    }
}

static void bootstrap_qsort(void *base, unsigned count, unsigned size,
                            int (*compar)(void *, void *))
{
    char *bytes = base;
    unsigned i;
    unsigned j;
    if (!base || !compar)
        return;
    for (i = 0; i < count; i = i + 1) {
        for (j = i + 1; j < count; j = j + 1) {
            if (compar(bytes + i * size, bytes + j * size) > 0)
                swap_bytes(bytes + i * size, bytes + j * size, size);
        }
    }
}

static int case_cmp(uint64_t a, uint64_t b)
{
    return a < b ? -1 : a > b;
}

static int case_cmp_qs(void *pa, void *pb)
{
    return case_cmp((*(struct case_t **)pa)->v1, (*(struct case_t **)pb)->v1);
}

int main(void)
{
    struct case_t low;
    struct case_t high;
    struct case_t *items[2];

    low.v1 = 37;
    low.v2 = 37;
    high.v1 = 99;
    high.v2 = 99;

    items[0] = &low;
    items[1] = &high;
    bootstrap_qsort(items, 2, sizeof items[0], case_cmp_qs);
    if (items[0]->v1 != 37)
        return 1;
    if (items[1]->v1 != 99)
        return 2;

    items[0] = &high;
    items[1] = &low;

    bootstrap_qsort(items, 2, sizeof items[0], case_cmp_qs);
    if (items[0]->v1 != 37)
        return 3;
    if (items[1]->v1 != 99)
        return 4;
    return 0;
}
