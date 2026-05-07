struct Section {
  int value;
};

struct State {
  struct Section *rodata;
};

struct Params {
  struct Section *sec;
  int align;
};

struct Section ro = { 13 };
struct State state = { &ro };
struct State *tcc_state = &state;

int main() {
  struct Params p = { tcc_state->rodata, 7 };
  if (p.sec != &ro) return 1;
  if (p.align != 7) return 2;
  return p.sec->value == 13 ? 0 : 3;
}
