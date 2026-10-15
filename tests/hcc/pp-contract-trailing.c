#define S(x) #x
#define E(x) S(x)
#define EMPTY
#define PASS(x) x
#define F(x) a x
#define ADJ(x) a+x
#define BOTH(x) a x##x
#define LEFT(x) a x##b
#define CHAIN(x,y) a x##y##b
#define FUNC(x) x
#define RETURNS(x) FUNC x
#define TWO(x) x x
#define LEADING(x) x b
#define LEADING_PASTE(x,y) x##y b
#define REPEAT(x) x+x
const char *pp_trailing = E(F()b);
const char *pp_trailing_macro = E(F(EMPTY)b);
const char *pp_trailing_nested = E(PASS(F(PASS()))b);
const char *pp_trailing_adjacent = E(ADJ()b);
const char *pp_trailing_both = E(BOTH()b);
const char *pp_trailing_left = E(LEFT()b);
const char *pp_trailing_chain = E(CHAIN(,)b);
const char *pp_trailing_call = E(RETURNS()(b));
const char *pp_empty_adjacent = E(z(PASS())b);
const char *pp_empty_prescan = E(a+PASS(TWO())b);
const char *pp_empty_leading = E(a+PASS( EMPTY)b);
const char *pp_leading_empty = E(a+LEADING());
const char *pp_leading_paste = E(a+LEADING_PASTE(,));
const char *pp_leading_prescan = E(REPEAT(EMPTY b));
