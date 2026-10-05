/* References discovered after function emission must label earlier data.
   Forward references and pending string/static data share the same contract. */
extern int later[3];
int *forward = &later[2];
static int earlier[3] = { 7, 11, 13 };
char *global_string = &"abcd"[2];
int first(void) {
    static int local[3] = { 17, 19, 23 };
    static int *middle = &local[1];
    static int *prior = &earlier[1];
    static char *string = &"wxyz"[2];
    return *middle == 19 && *prior == 11 && *string == 'y';
}
int second(void) {
    static int *end = &earlier[3];
    static int *next = &later[1];
    return end == earlier + 3 && *next == 29;
}
int later[3] = { 27, 29, 31 };
int main(void) {
    return !(first() && second() && *forward == 31 && *global_string == 'c');
}
