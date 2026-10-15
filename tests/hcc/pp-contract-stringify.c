#define S(x) #x
#define V(...) #__VA_ARGS__
#define EXPAND(x) S(x)
#define EXPR a+b
#define WRAP(x) EXPAND(a+x + c)
const char *pp_adjacent = S(a+b);
const char *pp_space = S( a  +
 b );
const char *pp_comment = S(a/**/+b);
const char *pp_expand = EXPAND(EXPR);
#define EMPTY
#define EMPTY_FN()
#define EMPTY_ARG(x) EXPAND(a x+b)
const char *pp_empty_object = EXPAND(a EMPTY+b);
const char *pp_empty_function = EXPAND(a EMPTY_FN()+b);
const char *pp_empty_argument = EMPTY_ARG();
const char *pp_wrap = WRAP(b);
const char *pp_variadic = V(a ,b, c);
const char *pp_escape = S("a\\b");
const char *pp_splice = S(a\
+b);
