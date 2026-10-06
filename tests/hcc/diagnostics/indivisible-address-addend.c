int value;
union Object { int *pointer; char bytes[8]; } object = { &value };
int first(void) { return 1; }
int second(void) { static char *bad = &object.bytes[1]; return *bad; }
