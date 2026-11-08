int visible = 7;
int calls;

int original(void) { return 1; }
int replacement(void) { calls = calls + 1; return 9; }

int later_local(void)
{
    if (visible != 7) return 1;
    int visible = 3;
    return visible != 3;
}

int parameter_call(int (*original)(void))
{
    original();
    return original();
}

int nested_labels(void)
{
    int value = 0;
    goto in_block;
    {
        int visible;
    in_block:
        visible = 5;
        value = visible;
    }
    if (visible != 7 || value != 5) return 1;
    goto in_if;
    if (0) {
    in_if:
        value = value + 1;
    }
    goto in_while;
    while (0) {
    in_while:
        value = value + 1;
        break;
    }
    goto in_do;
    do {
    in_do:
        value = value + 1;
        continue;
    } while (0);
    goto in_for;
    for (int visible = 0; visible < 2; visible = visible + 1) {
    in_for:
        visible = 2;
        value = value + 1;
        continue;
    }
    goto in_switch;
    switch (0) {
    case 0:
    in_switch:
        value = value + 1;
        break;
    }
    return value != 10 || visible != 7;
}

int after_return(int enter)
{
    if (enter) goto nested;
    return 4;
    {
    nested:
        return 6;
    }
}

int after_break(void)
{
    int value = 0;
    goto nested_break;
    while (0) {
        break;
        {
        nested_break:
            value = 1;
            break;
        }
    }
    return value != 1;
}

int after_continue(void)
{
    int value = 0;
    goto nested_continue;
    do {
        continue;
        {
        nested_continue:
            value = 1;
            break;
        }
    } while (0);
    return value != 1;
}

int main(void)
{
    if (later_local()) return 1;
    if (parameter_call(replacement) != 9 || calls != 2) return 2;
    {
        int (*original)(void) = replacement;
        original();
        if (original() != 9 || calls != 4) return 3;
    }
    if (original() != 1) return 4;
    if (nested_labels()) return 5;
    if (after_return(0) != 4 || after_return(1) != 6) return 6;
    if (after_break() || after_continue()) return 7;
    return 0;
}
