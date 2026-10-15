#define F(x) ((x)+1)
#define G(x) F(x)
#define RET() F
int pp_contract_nested = G(F(1));
int pp_contract_suffix = RET()(1);
#define A B
#define B A
int A;
#define ID(x) x
#define SELF(x) SELF(x)
ID(SELF(1))
#define f(a) a*g
#define g(a) f(a)
f(2)(9)
#define CAT(a,b) a##b
CAT(one two,three four)
#define RAW(x) #x
RAW(F(1,2))
