typedef char T;
enum { x = 3, count = 2 };
struct T { int T; int x; };

/* Prototype and nested function-declarator parameters must not leak. */
int parser_scope_parameters(int T, int x);
typedef int (*parser_scope_callback)(int T, int x);
T parser_scope_global;

int parser_scope_parameters(int T, int x) {
    if (sizeof(T) != sizeof(int)) return 1;
    if (T != 7 || x != 8) return 2;
    return 0;
}

int parser_scope_function(void) { return 11; }

int parser_scope_nested(int (*callback)(int T, int x), T value) {
    return sizeof(value) != sizeof(char);
}

/* Enumerators introduced in a definition's parameters last through its body,
   but are not file-scope declarations (even when named like the function). */
int parser_scope_same(enum { parser_scope_same = 4 } value) {
    return parser_scope_same;
}

int main(void) {
    int total = 0;
    if (parser_scope_parameters(7, 8)) return 1;
    if (parser_scope_nested(0, 7)) return 17;
    if (parser_scope_same(0) != 4) return 18;
    if (sizeof(T) != sizeof(char) || x != 3) return 2;
    {
        /* Binding begins after the declarator, before its initializer. */
        int T = sizeof(T), next = sizeof(T);
        int x = 9;
        if (T != sizeof(int) || next != sizeof(int) || x != 9) return 3;
        {
            typedef char T;
            enum { x = 5 };
            T small;
            if (sizeof(small) != 1 || x != 5) return 4;
        }
        if (sizeof(T) != sizeof(int) || x != 9) return 5;
    }
    if (sizeof(T) != 1 || x != 3) return 6;
    {
        /* An array bound precedes the new object's point of declaration. */
        int count[count];
        if (sizeof(count) != 2 * sizeof(int)) return 7;
    }
    for (int T = 0, x = 0; T < 2; ++T) {
        x = T + 1;
        total += x;
    }
    if (total != 3 || sizeof(T) != 1 || x != 3) return 8;
    {
        /* A block function declaration masks an outer typedef. */
        typedef char parser_scope_function;
        {
            int parser_scope_function(void);
            if (parser_scope_function() != 11) return 9;
        }
        if (sizeof(parser_scope_function) != 1) return 10;
    }
    {
        /* The same rule applies when the outer name is an enumerator. */
        enum { parser_scope_function = 6 };
        {
            int parser_scope_function(void);
            if (parser_scope_function() != 11) return 11;
        }
        if (parser_scope_function != 6) return 12;
    }
    {
        /* A typedef is visible to subsequent declarators in its declaration. */
        enum { Alias = 9 };
        {
            typedef int Alias, Array[sizeof(Alias)];
            Array a;
            if (sizeof(a) != sizeof(int) * sizeof(int)) return 13;
        }
        if (Alias != 9) return 14;
    }
    {
        int T = 0;
        struct T tagged;
        tagged.T = 12;
        tagged.x = 13;
        if (tagged.T != 12 || tagged.x != 13 || T != 0) return 15;
    }
    /* Members and tags never hide ordinary typedef/enumerator bindings. */
    if (sizeof(T) != 1 || x != 3 || count != 2) return 16;
    {
        /* An enumerator's own initializer still sees the outer enumerator. */
        enum { x = x + 1 };
        if (x != 4) return 19;
    }
    /* A selection statement has its own scope, including its condition. */
    if (sizeof(enum { x = 7 })) {
        if (x != 7) return 20;
    }
    if (x != 3) return 21;
    return 0;
}
