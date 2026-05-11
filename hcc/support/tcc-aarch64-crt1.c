int main(int argc, char** argv);
void _exit(int code);

void _start(void)
{
    _exit(main(0, 0));
}
