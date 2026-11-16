/* HCC's integer-valued floating representation must preserve the sign. */
float global;
struct Cell { float value; };

int main(void) {
    float values[1];
    struct Cell cell;
    struct Cell *ptr = &cell;

    values[0] = -5.0f;
    ptr->value = -7.0f;
    global = -3.0f;
    if (values[0] != -5.0f || ptr->value != -7.0f || global != -3.0f) return 1;
    if ((long)values[0] != -5 || !(cell.value < global)) return 2;

    return 0;
}
