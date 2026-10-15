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
int main(void) {
  return pp_trailing[1] != ' ' || pp_trailing_macro[1] != ' ' ||
    pp_trailing_nested[1] != ' ' || pp_trailing_adjacent[2] != 'b' ||
    pp_trailing_both[1] != ' ' || pp_trailing_left[1] != ' ' ||
    pp_trailing_chain[1] != ' ' || pp_trailing_call[0] != 'b' ||
    pp_empty_adjacent[2] != ')' || pp_empty_prescan[2] != ' ' ||
    pp_empty_leading[2] != 'b';
}
