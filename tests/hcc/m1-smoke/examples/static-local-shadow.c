int parameter(int x) {
    int *outer = &x;
    {
        static long x = 2;
        long *p = &x;
        if (sizeof(x) != sizeof(long) || *p != 2) return 1;
        *p = 3;
        if (x != 3) return 2;
        {
            char x = 5;
            char *p = &x;
            if (sizeof(x) != 1 || *p != 5) return 3;
            *p = 6;
            if (x != 6) return 4;
        }
        if (x != 3) return 5;
    }
    return x != 11 || *outer != 11;
}
int main(void) {
    int x = 1;
    {
        static int x = 2;
        if (x != 2 || *(&x) != 2) return 7;
        {
            int x = 9;
            {
                static int x = 13;
                if (x != 13 || *(&x) != 13) return 8;
            }
            if (x != 9 || *(&x) != 9) return 9;
        }
        if (x != 2) return 10;
    }
    if (x != 1) return 11;
    return parameter(11);
}
