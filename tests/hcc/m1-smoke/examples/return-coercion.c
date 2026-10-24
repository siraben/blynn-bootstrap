unsigned char narrow_return(void)
{
    return 257;
}

_Bool bool_return(void)
{
    return 3;
}

void empty_void_return(void)
{
}

int main(void)
{
    empty_void_return();
    if (narrow_return() != 1) return 1;
    if (bool_return() != 1) return 2;
    return 0;
}
