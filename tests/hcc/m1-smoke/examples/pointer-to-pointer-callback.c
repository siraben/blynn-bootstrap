typedef unsigned long uint64_t;

struct case_t {
    uint64_t v1;
    uint64_t v2;
};

typedef int Cmp(const void *, const void *);

static int case_cmp(uint64_t a, uint64_t b)
{
    return a < b ? -1 : a > b;
}

static int case_cmp_qs(const void *pa, const void *pb)
{
    return case_cmp((*(struct case_t **)pa)->v1, (*(struct case_t **)pb)->v1);
}

static void sort_pair(struct case_t **items, Cmp *cmp)
{
    if (cmp(&items[0], &items[1]) > 0) {
        struct case_t *tmp = items[0];
        items[0] = items[1];
        items[1] = tmp;
    }
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
    items[0] = &high;
    items[1] = &low;

    sort_pair(items, case_cmp_qs);
    if (items[0]->v1 != 37)
        return 1;
    if (items[1]->v1 != 99)
        return 2;
    return 0;
}
