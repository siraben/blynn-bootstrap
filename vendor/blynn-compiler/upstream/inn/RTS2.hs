-- Export lists.
module RTS where

import Base
import Ast
import Kiselyov
import Map
import Parser

import_qq_here = import_qq_here

libcHost = [r|#include<stdio.h>
static int env_argc;
int getargcount() { return env_argc; }
static char **env_argv;
int getargchar(int n, int k) { return env_argv[n][k]; }
static int nextCh, isAhead;
int eof_shim() {
  if (!isAhead) {
    isAhead = 1;
    nextCh = getchar();
  }
  return nextCh == -1;
}
void exit(int);
void putchar_shim(int c) { putchar(c); fflush(stdout); }
int getchar_shim() {
  if (!isAhead) nextCh = getchar();
  if (nextCh == -1) exit(1);
  isAhead = 0;
  return nextCh;
}
void errchar(int c) { fputc(c, stderr); }
void errexit() { fputc('\n', stderr); }
|]

libcWasm = [r|
extern u __heap_base;
void* malloc(unsigned long n) {
  static u bump = (u) &__heap_base;
  return (void *) ((bump += n) - n);
}
void errchar(int c) {}
void errexit() {}
|]

preamble = [r|#define EXPORT(f, sym) void f() asm(sym) __attribute__((export_name(sym)));
void *malloc(unsigned long);
enum { FORWARD = 127, REDUCING = 126 };
static u *mem, *altmem, *sp, *spTop, hp;
static inline u isAddr(u n) { return n>=128; }
static u evac(u n) {
  if (!isAddr(n)) return n;
  u *pn = mem + n * sizeof(u);
  u x = *pn;
  while (isAddr(x)) {
    u *px = mem + x * sizeof(u);
    if (*px != _T) break;
    u *pn1 = mem + (n + 1) * sizeof(u);
    u *px1 = mem + (x + 1) * sizeof(u);
    *pn = *pn1;
    *pn1 = *px1;
    x = *pn;
  }
  if (isAddr(x)) {
    u *px = mem + x * sizeof(u);
    if (*px == _K) {
      u *pn1 = mem + (n + 1) * sizeof(u);
      u *px1 = mem + (x + 1) * sizeof(u);
      *pn1 = *px1;
      x = _I;
      *pn = x;
    }
  }
  u *pn1 = mem + (n + 1) * sizeof(u);
  u y = *pn1;
  switch(x) {
    case FORWARD: return y;
    case REDUCING:
      *pn = FORWARD;
      *pn1 = hp;
      hp += 2;
      return *pn1;
    case _I:
      *pn = REDUCING;
      y = evac(y);
      if (*pn == FORWARD) {
        u *pa = altmem + *pn1 * sizeof(u);
        *pa = _I;
        pa = altmem + (*pn1 + 1) * sizeof(u);
        *pa = y;
      } else {
        *pn = FORWARD;
        *pn1 = y;
      }
      return *pn1;
    default: break;
  }
  u z = hp;
  hp += 2;
  *pn = FORWARD;
  *pn1 = z;
  u *pa = altmem + z * sizeof(u);
  *pa = x;
  pa = altmem + (z + 1) * sizeof(u);
  *pa = y;
  return z;
}

static void gc() {
  hp = 128;
  u di = hp;
  sp = altmem + (TOP - 1) * sizeof(u);
  for(u *r = root; *r; r = r + sizeof(u)) *r = evac(*r);
  *sp = evac(*spTop);
  while (di < hp) {
    u *pd = altmem + di * sizeof(u);
    u x = evac(*pd);
    *pd = x;
    di = di + 1;
    if (x != _NUM) {
      pd = altmem + di * sizeof(u);
      *pd = evac(*pd);
    }
    di = di + 1;
  }
  spTop = sp;
  u *tmp = mem;
  mem = altmem;
  altmem = tmp;
}

static inline u app(u f, u x) {
  u *p = mem + hp * sizeof(u);
  *p = f;
  p = mem + (hp + 1) * sizeof(u);
  *p = x;
  hp += 2;
  return hp - 2;
}
static inline u arg(u n) {
  u *p = sp + n * sizeof(u);
  p = mem + (*p + 1) * sizeof(u);
  return *p;
}
static inline int num(u n) {
  u a = arg(n);
  u *p = mem + (a + 1) * sizeof(u);
  return *p;
}
static inline void lazy2(u height, u f, u x) {
  u *p = sp + height * sizeof(u);
  p = mem + *p * sizeof(u);
  *p = f;
  p = p + sizeof(u);
  *p = x;
  sp = sp + (height - 1) * sizeof(u);
  *sp = f;
}
static void lazy3(u height,u x1,u x2,u x3){
  u *p = sp + height * sizeof(u);
  p = mem + *p * sizeof(u);
  u *ps = sp + (height - 1) * sizeof(u);
  *ps = app(x1, x2);
  *p = *ps;
  p = p + sizeof(u);
  *p = x3;
  sp = sp + (height - 2) * sizeof(u);
  *sp = x1;
}
typedef unsigned long long uu;
static inline u app64uu(uu n) {
  u *p = mem + hp * sizeof(u);
  *p = _NUM64;
  p = mem + (hp + 1) * sizeof(u);
  *p = 0;
  p = mem + (hp + 2) * sizeof(u);
  uu *q = (uu*) p;
  *q = n;
  hp += 4;
  return hp - 4;
}
static inline u app64d(uu n) { return app64uu(n); }
static inline uu flo(u n) {
  u a = arg(n);
  u *p = mem + (a + 2) * sizeof(u);
  uu *q = (uu*) p;
  return *q;
}
static inline void lazyDub(uu n) { lazy3(4, _V, app(_NUM, n), app(_NUM, n >> 32)); }
static inline uu dub(u lo, u hi) { return ((uu)num(hi) << 32) + (u)num(lo); }
static inline u ite(int cond) { if (cond) return _K; return _KI; }
static inline u fle(uu x, uu y) { return ite(x <= y); }
static inline u feq(uu x, uu y) { return ite(x == y); }
static inline u ule(int x, int y) { return ite((u)x <= (u)y); }
static inline int ashr(int x, int y) { if (x < 0) return ~(~x >> y); return x >> y; }
|]

-- Main VM loop.
comdefsrc = [r|
F x = "foreign(num(1));"
Y x = "{u *p = sp + sizeof(u); lazy2(1, arg(1), *p);}"
Q x y z = z(y x)
QQ f a b c d = d(c(b(a(f))))
S x y z = x z(y z)
B x y z = x (y z)
BK x y z = x y
C x y z = x z y
R x y z = y z x
V x y z = z x y
T x y = y x
K x y = "_I" x
KI x y = "_I" y
I x = "{u *p = sp + sizeof(u); *p = arg(1); sp = sp + sizeof(u);}"
LEFT x y z = y x
CONS x y z w = w x y
NUM x y = "{u *p = sp + sizeof(u); lazy2(2, arg(2), *p);}"
NUM64 x y = "{u *p = sp + sizeof(u); lazy2(2, arg(2), *p);}"
FLO x = "lazy2(1, _I, app64d((u) num(1)));"
FLW x = "lazy2(1, _I, app64d((u) num(1)));"
OLF x = "_NUM" "((int) flo(1))"
FADD x y = "lazy2(2, _I, app64d(flo(1) + flo(2)));"
FSUB x y = "lazy2(2, _I, app64d(flo(1) - flo(2)));"
FMUL x y = "lazy2(2, _I, app64d(flo(1) * flo(2)));"
FDIV x y = "lazy2(2, _I, app64d(flo(1) / flo(2)));"
FLE x y = "lazy2(2, _I, fle(flo(1), flo(2)));"
FEQ x y = "lazy2(2, _I, feq(flo(1), flo(2)));"
PAIR64 x = "{u *p = mem + (arg(1) + 2) * sizeof(u); uu *q = (uu*) p; uu n = *q; lazy2(1, app(_V, app(_NUM, n)), app(_NUM, n >> 32));}"
DADD x y = "lazyDub(dub(1,2) + dub(3,4));"
DSUB x y = "lazyDub(dub(1,2) - dub(3,4));"
DMUL x y = "lazyDub(dub(1,2) * dub(3,4));"
DDIV x y = "lazyDub(dub(1,2) / dub(3,4));"
DMOD x y = "lazyDub(dub(1,2) % dub(3,4));"
DSHL x y = "lazyDub(dub(1,2) << dub(3,4));"
DSHR x y = "lazyDub(dub(1,2) >> dub(3,4));"
ADD x y = "_NUM" "num(1) + num(2)"
SUB x y = "_NUM" "num(1) - num(2)"
MUL x y = "_NUM" "num(1) * num(2)"
QUOT x y = "_NUM" "num(1) / num(2)"
REM x y = "_NUM" "num(1) % num(2)"
DIV x y = "_NUM" "div(num(1), num(2))"
MOD x y = "_NUM" "mod(num(1), num(2))"
XOR x y = "_NUM" "num(1) ^ num(2)"
AND x y = "_NUM" "num(1) & num(2)"
OR x y = "_NUM" "num(1) | num(2)"
SHL x y = "_NUM" "num(1) << num(2)"
SHR x y = "_NUM" "ashr(num(1), num(2))"
U_SHR x y = "_NUM" "(u) num(1) >> (u) num(2)"
EQ x y = "lazy2(2, _I, ite(num(1) == num(2)));"
LE x y = "lazy2(2, _I, ite(num(1) <= num(2)));"
U_DIV x y = "_NUM" "(u) num(1) / (u) num(2)"
U_MOD x y = "_NUM" "(u) num(1) % (u) num(2)"
U_LE x y = "lazy2(2, _I, ule(num(1), num(2)));"
REF x y = "{u *p = sp + sizeof(u); lazy2(2, arg(2), *p);}"
NEWREF x y z = z ("_REF" x) y
READREF x y z = z "num(1)" y
WRITEREF x y z w = "{u *p = mem + (arg(2) + 1) * sizeof(u); *p = arg(1); lazy3(4, arg(4), _K, arg(3));}"
END = "return;"
ERR = "{u *p = sp + sizeof(u); *p = app(app(arg(1), _ERREND), _ERR2); sp = sp + sizeof(u);}"
ERR2 = "lazy3(2, arg(1), _ERROUT, arg(2));"
ERROUT = "errchar(num(1)); lazy2(2, _ERR, arg(2));"
ERREND = "errexit(); return;"
|]

argList t = case t of
  TC s -> [TC s]
  TV s -> [TV s]
  TAp (TC "IO") (TC u) -> [TC u]
  TAp (TAp (TC "->") x) y -> x : argList y
  _ -> [t]

cTypeName (TC "()") = "void"
cTypeName (TC "Int") = "int"
cTypeName (TC "Char") = "int"
cTypeName _ = "int"

ffiDeclare (name, t) = let tys = argList t in (concat
  [cTypeName $ last tys, " ", name, "(", intercalate "," $ cTypeName <$> init tys, ");\n"]++)

ffiArgs n t = case t of
  TAp (TC "IO") u -> ("", ((False, u), n))
  TAp (TAp (TC "->") _) y -> first (((if 3 <= n then ", " else "") ++ "num(" ++ shows n ")") ++) $ ffiArgs (n + 1) y
  _ -> ("", ((True, t), n))

needsNum t = case t of
  TC "Int" -> True
  TC "Char" -> True
  _ -> False

ffiDefine n (name, t) = ("case " ++) . shows n . (": " ++) . if ret == TC "()"
  then longDistanceCall . cont ("_K"++) . ("); break;"++)
  else ("{u r = "++) . longDistanceCall . cont ((if needsNum ret then "app(_NUM, r)" else "r") ++) . ("); break;}\n"++)
  where
  (args, ((isPure, ret), count)) = ffiArgs 2 t
  lazyn = ("lazy2(" ++) . shows (if isPure then count - 1 else count + 1) . (", " ++)
  cont tgt = if isPure then ("_I, "++) . tgt else ("app(arg("++) . shows (count + 1) . ("), "++) . tgt . ("), arg("++) . shows count . (")"++)
  longDistanceCall = (name++) . ("("++) . (args++) . ("); "++) . lazyn

genExport ourType n = ("void f"++) . shows n . ("("++)
  . foldr (.) id (intersperse (',':) $ map declare txs)
  . ("){rts_reduce("++)
  . foldl (\s tx -> ("app("++) . s . (',':) . heapify tx . (')':)) rt txs
  . (");}\n"++)
  where
  txs = go 0 ourType
  go n = \case
    TAp (TAp (TC "->") t) rest -> (t, ('x':) . shows n) : go (n + 1) rest
    _ -> []
  rt = ("root["++) . shows n . ("]"++)
  declare (t, x) = ("u "++) . x
  heapify (t, x) = ("app(_NUM,"++) . x . (')':)

genArg m a = case a of
  V s -> ("arg("++) . (maybe undefined shows $ lookup s m) . (')':)
  E (StrCon s) -> (s++)
  A x y -> ("app("++) . genArg m x . (',':) . genArg m y . (')':)
genArgs m as = foldl1 (.) $ map (\a -> (","++) . genArg m a) as
genComb (s, (args, body)) = let
  argc = ('(':) . shows (length args)
  m = zip args [1..]
  in ("case _"++) . (s++) . (':':) . (case body of
    A (A x y) z -> ("lazy3"++) . argc . genArgs m [x, y, z] . (");"++)
    A x y -> ("lazy2"++) . argc . genArgs m [x, y] . (");"++)
    E (StrCon s) -> (s++)
  ) . ("break;\n"++)

comb = (,) <$> conId <*> ((,) <$> many varId <*> (res "=" *> combExpr))
combExpr = foldl1 A <$> some
  (V <$> varId <|> E . StrCon <$> lexeme tokStr <|> paren combExpr)
comdefs = case parse (lexemePrelude *> braceSep comb <* eof) comdefsrc of
  Left e -> error e
  Right (cs, _) -> cs
comEnum s = maybe (error s) id $ lookup s $ zip (fst <$> comdefs) [1..]
comName i = maybe undefined id $ lookup i $ zip [1..] (fst <$> comdefs)

runFun = ([r|
static int div(int a, int b) { int q = a/b; return q - (((u)(a^b)) >> 31)*(q*b!=a); }
static int mod(int a, int b) { int r = a%b; return r + (((u)(a^b)) >> 31)*(!!r)*b; }

static void run() {
  while(1) {
    if (mem + hp * sizeof(u) > sp - 8 * sizeof(u)) gc();
    u x = *sp;
    if (isAddr(x)) { u *p = mem + x * sizeof(u); sp = sp - sizeof(u); *sp = *p; } else switch(x) {
|]++)
  . foldr (.) id (genComb <$> comdefs)
  . ([r|
    }
  }
}
|]++)

rtsAPI opts = ([r|
void rts_init() {
  mem = malloc(TOP * sizeof(u)); altmem = malloc(TOP * sizeof(u));
  hp = 128;
  for (u i = 0; i < prog_size; i = i + 1) { u *p = mem + hp * sizeof(u); *p = prog[i]; hp = hp + 1; }
  spTop = mem + (TOP - 1) * sizeof(u);
}
|]++)
  . rtsReduce opts

-- Hash consing.
data Obj = Local String | Global String String | Code Int deriving Eq

instance Ord Obj where
  x <= y = case x of
    Local a -> case y of
      Local b -> a <= b
      _ -> True
    Global m a -> case y of
      Local _ -> False
      Global n b -> if m == n then a <= b else m <= n
      _ -> True
    Code a -> case y of
      Code b -> a <= b
      _ -> False

memget k@(a, b) = get >>= \(tab, (hp, f)) -> case mlookup k tab of
  Nothing -> put (insert k hp tab, (hp + 2, f . (a:) . (b:))) >> pure hp
  Just v -> pure v

enc t = case t of
  Lf n -> case n of
    Basic c -> pure $ Code $ comEnum c
    Const n -> Code <$> memget (Code $ comEnum "NUM", Code n)
    ChrCon c -> Code <$> memget (Code $ comEnum "NUM", Code $ ord c)
    StrCon s -> enc $ foldr (\h t -> Nd (Nd (lf "CONS") (Lf $ ChrCon h)) t) (lf "K") s
    Link m s _ -> pure $ Global m s
    _ -> error $ "BUG! " ++ show t
  LfVar s -> pure $ Local s
  Nd x y -> enc x >>= \hx -> enc y >>= \hy -> Code <$> memget (hx, hy)

asm combs = foldM
  (\symtab (s, t) -> (flip (insert s) symtab) <$> enc t)
  Tip combs

rewriteCombs tab = optim . go where
  go = \case
    LfVar v -> let t = follow [v] v in case t of
      Lf (Basic _) -> t
      LfVar w -> if v == w then Nd (lf "Y") (lf "I") else t
      _ -> LfVar v
    Nd a b -> Nd (go a) (go b)
    t -> t
  follow seen v = case tab ! v of
    LfVar w | w `elem` seen -> LfVar $ last seen
            | True -> follow (w:seen) w
    t -> t

codegenLocal (name, neat) (bigmap, (hp, f)) =
  (insert name localmap bigmap, (hp', f . (mem++)))
  where
  rawCombs = optim . nolam . snd <$> typedAsts neat
  combs = toAscList $ rewriteCombs rawCombs <$> rawCombs
  (symtab, (_, (hp', memF))) = runState (asm combs) (Tip, (hp, id))
  localmap = resolveLocal <$> symtab
  mem = resolveLocal <$> memF []
  resolveLocal = \case
    Code n -> Right n
    Local s -> resolveLocal $ symtab ! s
    Global m s -> Left (m, s)

codegen ffiMap mods = (bigmap', mem) where
  (bigmap, (_, memF)) = foldr codegenLocal (ffiMap, (128, id)) $ toAscList mods
  bigmap' = (resolveGlobal <$>) <$> bigmap
  mem = resolveGlobal <$> memF []
  resolveGlobal = \case
    Left (m, s) -> resolveGlobal $ (bigmap ! m) ! s
    Right n -> n

getIOType (Qual [] (TAp (TC "IO") t)) = Right t
getIOType q = Left $ "main : " ++ show q

compileWith topSize libc opts mods = do
  let
    ffis = foldr (\(k, v) m -> insertWith (error $ "duplicate import: " ++ k) k v m) Tip $ concatMap (toAscList . ffiImports) $ elems mods
    ffiMap = singleton "{foreign}" $ fromList $ zip (keys ffis) $ Right <$> [0..]
    (bigmap, mem) = codegen ffiMap mods
    ffes = foldr (\(expName, v) m -> insertWith (error $ "duplicate export: " ++ expName) expName v m) Tip
      [ (expName, (addr, mustType modName ourName))
      | (modName, neat) <- toAscList mods
      , (expName, ourName) <- toAscList $ ffiExports neat
      , let addr = maybe (error $ "missing: " ++ ourName) id $ mlookup ourName $ bigmap ! modName
      ]
    mustType modName s = case mlookup s $ typedAsts $ mods ! modName of
      Just (Qual [] t, _) -> t
      _ -> error $ "TODO: bad export: " ++ s
    mayMain = do
      mainAddr <- mlookup "main" =<< mlookup "Main" bigmap
      mainType <- fst <$> mlookup "main" (typedAsts $ mods ! "Main")
      pure (mainAddr, mainType)
  mainStr <- case mayMain of
    Nothing -> pure ""
    Just (a, q) -> do
      getIOType q
      pure $ if "no-main" `elem` opts then "" else "int main(int argc,char**argv){env_argc=argc;env_argv=argv;rts_reduce(" ++ shows a ");return 0;}\n"

  pure
    $ ("typedef unsigned u;\n"++)
    . ("enum{TOP="++)
    . (topSize++)
    . (",_UNDEFINED=0,"++)
    . foldr (.) id (map (\(s, _) -> ('_':) . (s++) . (',':)) comdefs)
    . ("};\n"++)
    . ("static const u prog[]={" ++)
    . foldr (.) id (map (\n -> shows n . (',':)) mem)
    . ("};\nstatic const u prog_size="++) . shows (length mem) . (";\nstatic u root[]={"++)
    . foldr (.) id (map (\(addr, _) -> shows addr . (',':)) $ elems ffes)
    . ("0};\n" ++)
    . (preamble++)
    . (libc++)
    . foldr (.) id (ffiDeclare <$> toAscList ffis)
    . ("static void foreign(u n) {\n  switch(n) {\n" ++)
    . foldr (.) id (zipWith ffiDefine [0..] $ toAscList ffis)
    . ("\n  }\n}\n" ++)
    . runFun
    . rtsAPI opts
    . foldr (.) id (zipWith (\(expName, (_, ourType)) n -> ("EXPORT(f"++) . shows n . (", \""++) . (expName++) . ("\")\n"++) . genExport ourType n) (toAscList ffes) [0..])
    $ mainStr

compile = compileWith "16777216" libcHost []

declWarts = ([r|#define IMPORT(m,n) __attribute__((import_module(m))) __attribute__((import_name(n)));
enum {
  ROOT_BASE = 512,  // 0-terminated array of exported functions
  // HEAP_BASE - 4: program size
  HEAP_BASE = 1048576 - 128 * sizeof(u),  // program
  TOP = 4194304
};
static u *root = (u*) ROOT_BASE;
void errchar(int c) {}
void errexit() {}
|]++)

rtsAPIWarts opts = ([r|
static inline void rts_init() {
  mem = (u*) HEAP_BASE; altmem = (u*) (HEAP_BASE + (TOP - 128) * sizeof(u));
  { u *p = mem + 127 * sizeof(u); hp = 128 + *p; }
  spTop = mem + (TOP - 1) * sizeof(u);
}

// Export so we can later find it in the wasm binary.
void rts_reduce(u) __attribute__((export_name("reduce")));
|]++) . rtsReduce opts

rtsReduce opts =
  (if "pre-post-run" `elem` opts then ("void pre_run(void); void post_run(void);\n"++) else id)
  . ([r|
void rts_reduce(u n) {
  static u ready;if (!ready){ready=1;rts_init();}
  sp = spTop;
  *sp = app(app(n, _UNDEFINED), _END);
|]++)
  . (if "pre-post-run" `elem` opts then ("pre_run();run();post_run();"++) else ("run();"++))
  . ("\n}\n"++)

ffiDeclareWarts (name, t) = let tys = argList t in (concat
  [cTypeName $ last tys, " ", name, "(", intercalate "," $ cTypeName <$> init tys, ") IMPORT(\"env\", \"", name, "\");\n"]++)

warts opts mods =
  ("typedef unsigned u;\n"++)
  . ("enum{_UNDEFINED=0,"++)
  . foldr (.) id (map (\(s, _) -> ('_':) . (s++) . (',':)) comdefs)
  . ("};\n"++)
  . declWarts
  . (preamble++)
  . (if "no-import" `elem` opts then ("#undef IMPORT\n#define IMPORT(m,n)\n"++) else id)
  . foldr (.) id (ffiDeclareWarts <$> toAscList ffis)
  . ([r|void foreign(u n) asm("foreign");|]++)
  . ("void foreign(u n) {\n  switch(n) {\n" ++)
  . foldr (.) id (zipWith ffiDefine [0..] $ toAscList ffis)
  . ("\n  }\n}\n" ++)
  . runFun
  . rtsAPIWarts opts
  $ ""
  where
  ffis = foldr (\(k, v) m -> insertWith (error $ "duplicate import: " ++ k) k v m) Tip $ concatMap (toAscList . ffiImports) $ elems mods
