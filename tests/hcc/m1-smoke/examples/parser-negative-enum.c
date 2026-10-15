enum {
    parser_negative_first = -3,
    parser_negative_next,
    parser_negative_last,
    parser_negative_zero,
    parser_negative_positive,
    parser_negative_reference = parser_negative_first + 1,
    parser_negative_min = -2147483647 - 1
};

int parser_negative_global = parser_negative_last;
int parser_negative_data[] = {
    parser_negative_first, parser_negative_next, parser_negative_min
};
int parser_negative_array[parser_negative_last + 3];

int main(void) {
    int local = parser_negative_reference;
    if (parser_negative_first != -3 || parser_negative_next != -2) return 1;
    if (parser_negative_last != -1 || parser_negative_zero != 0) return 2;
    if (parser_negative_positive != 1 || local != -2) return 3;
    if (parser_negative_global != -1) return 4;
    if (parser_negative_data[0] != -3 || parser_negative_data[1] != -2) return 5;
    if (parser_negative_data[2] != -2147483647 - 1) return 6;
    if (parser_negative_min != -2147483647 - 1) return 7;
    if (sizeof(parser_negative_min) != sizeof(int)) return 8;
    if (sizeof(parser_negative_array) != 2 * sizeof(int)) return 9;
    switch (local) {
    case parser_negative_next: return 0;
    default: return 10;
    }
}
