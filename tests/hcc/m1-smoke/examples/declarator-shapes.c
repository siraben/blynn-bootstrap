/* A suffix binds tighter than a pointer. The first array bound is the
   outermost dimension. */
static int inc(int x) {
    return x + 1;
}

static int inc2(int x) {
    return x + 2;
}

typedef int (*unary)(int);

int (*table[2])(int) = {inc, inc2};
int grid[2][3] = {{1, 2, 3}, {4, 5, 6}};
char names[3][4] = {"ab", "cd", "ef"};
int (*row)[3];

struct Ops {
    int (*ops[2])(int);
    int *(*find)(int *base, int index);
    int cells[2][3];
    char (label)[4];
    int tail;
};
struct Ops gops = {{inc, inc2}, 0, {{1, 2, 3}, {4, 5, 6}}, "abc", 7};

static unary pick(int index) {
    return table[index];
}

int main(void) {
    int cube[3][4][5];
    int (*(*choose)(int))(int) = pick;

    if (sizeof(table) != 2 * sizeof(void *)) return 1;
    if (table[0](1) != 2 || table[1](1) != 3) return 2;
    if (sizeof(grid) != 24 || sizeof(grid[0]) != 12) return 3;
    if (grid[0][2] != 3 || grid[1][0] != 4 || grid[1][2] != 6) return 4;
    if (sizeof(names[0]) != 4) return 5;
    if (names[1][0] != 'c' || names[2][1] != 'f') return 6;
    if (sizeof(row) != sizeof(void *) || sizeof(*row) != 12) return 7;
    if (sizeof(struct Ops) != 3 * sizeof(void *) + 32) return 8;
    if (gops.ops[1](1) != 3 || gops.cells[1][1] != 5 || gops.tail != 7) return 9;
    if (sizeof(cube) != 240 || sizeof(cube[0][0]) != 20) return 10;
    row = grid;
    if ((*row)[2] != 3 || row[1][1] != 5) return 11;
    if (choose(0)(1) != 2) return 12;
    return 0;
}
