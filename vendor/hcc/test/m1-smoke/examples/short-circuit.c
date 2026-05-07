int boom(int *p){return *p;}
int main(){
  int *p = 0;
  if (0 && boom(p)) return 1;
  if ((0 && boom(p)) || (1 && 42)) return 42;
  return 2;
}
