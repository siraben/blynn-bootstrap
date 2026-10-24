struct File {
    char filename[37];
};

int main(void) {
    struct File *file = 0;
    char buf[sizeof file->filename];
    char *element = buf;
    if (sizeof file->filename != 37) return 1;
    if (sizeof buf != 37) return 2;
    if (sizeof *element != 1) return 3;
    buf[sizeof buf - 1] = 42;
    return buf[36] != 42;
}
