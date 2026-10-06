extern int external_data_7[3];
extern char external_string[4];
int external_helper(void);
int *middle = &external_data_7[1];
int *end = &external_data_7[3];
char *letter = &external_string[2];
int main(void) {
    static int *last = &external_data_7[2];
    if (external_helper() != 17 || *middle != 23 || *last != 29 || *letter != 'c') return 1;
    if (end != external_data_7 + 3) return 2;
    *middle = 31;
    return external_data_7[1] != 31;
}
