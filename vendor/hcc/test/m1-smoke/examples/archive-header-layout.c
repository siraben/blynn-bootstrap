typedef struct ArchiveHeader {
    char ar_name[16];
    char ar_date[12];
    char ar_uid[6];
    char ar_gid[6];
    char ar_mode[8];
    char ar_size[10];
    char ar_fmag[2];
} ArchiveHeader;

struct WithArray {
    char tag;
    char name[16];
    int value;
};

int main() {
    struct WithArray item;
    if (sizeof(ArchiveHeader) != 60) return sizeof(ArchiveHeader);
    if ((char *)&item.name - (char *)&item != 1) return 70;
    if ((char *)&item.value - (char *)&item != 20) return 71;
    return 0;
}
