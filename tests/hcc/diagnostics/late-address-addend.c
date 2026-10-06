int data[2];
int first(void) { return 1; }
int second(void) { static int *bad = &data[3]; return *bad; }
