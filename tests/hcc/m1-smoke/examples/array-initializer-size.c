/* An array without a bound takes its element count from the initializer. */
struct Pair {
    int key;
    char tag[4];
};
char gtext[] = "hello";
int gints[] = {1, 2, 3};
struct Pair gpairs[] = {{1, "a"}, {2, "b"}, {3, "c"}};
int gafter = 77;
/* An array with the length of the text has no terminator. */
char gexact[3] = "abc";
int gguard = 55;

static int three(void) {
    return 3;
}

int main(void) {
    int before = 11;
    int computed[] = {three(), three() + 1, three() + 2};
    char text[] = "abcdefghijklmnop";
    int after = 33;
    int fixed[6];

    if (sizeof(gtext) != 6 || sizeof(gints) != 12 || sizeof(gpairs) != 24) return 1;
    if (gints[2] != 3 || gpairs[2].key != 3 || gafter != 77) return 2;
    if (sizeof(computed) != 12 || sizeof(text) != 17) return 3;
    computed[2] = 1;
    text[15] = 'z';
    if (before != 11 || after != 33 || text[16] != 0) return 4;
    if (computed[0] + computed[1] + computed[2] != 8) return 5;
    if (sizeof("abc") != 4 || sizeof(fixed + 1) != sizeof(int *)) return 6;
    if (gexact[2] != 'c' || gguard != 55) return 7;
    return 0;
}
