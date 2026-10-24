#include <stdio.h>
#include <stdlib.h>

#define LINE_CAP 262144
#define PATH_CAP 4096

#define CH_NUL 0
#define CH_LF 10
#define CH_CR 13
#define CH_SPACE 32
#define CH_GT 62
#define CH_DOT 46
#define CH_SLASH 47
#define CH_BACKSLASH 92
#define CH_A 97
#define CH_B 98
#define CH_C 99
#define CH_O_LOWER 111
#define CH_T 116

static char *line;
static char *name;
static char *path;

static int str_len(const char *s) {
  int len = 0;
  while (s[len]) len++;
  return len;
}

static int str_eq(const char *a, const char *b) {
  int i = 0;
  while (a[i] && b[i]) {
    if (a[i] != b[i]) return 0;
    i++;
  }
  return a[i] == b[i];
}

static void copy_bytes(char *dest, const char *src, int len) {
  int i;
  for (i = 0; i < len; i++) {
    dest[i] = src[i];
  }
}

static void die_line(const char *message, int line_no) {
  fprintf(stderr, "materialize-object-script: line %d: %s\n", line_no, message);
  exit(1);
}

static void die_unexpected(const char *message, const char *text, int line_no) {
  fprintf(stderr, "materialize-object-script: line %d: %s: ", line_no, message);
  fputs(text, stderr);
  if (text[0] == CH_NUL || text[str_len(text) - 1] != CH_LF) {
    fputc(CH_LF, stderr);
  }
  exit(1);
}

static void trim_line_end(char *s) {
  int len = str_len(s);
  if (len && s[len - 1] == CH_LF) {
    s[--len] = CH_NUL;
  }
  if (len && s[len - 1] == CH_CR) {
    s[--len] = CH_NUL;
  }
}

static int is_eof_line(const char *s) {
  return str_eq(s, "EOF\n") || str_eq(s, "EOF\r\n") || str_eq(s, "EOF");
}

static int parse_header(char *s) {
  int i;
  int j;
  char c;

  trim_line_end(s);
  if (s[0] == 0) return 0;
  if (s[0] != CH_C) return -1;
  if (s[1] != CH_A) return -1;
  if (s[2] != CH_T) return -1;
  if (s[3] != CH_SPACE) return -1;
  if (s[4] != CH_GT) return -1;
  if (s[5] != CH_SPACE) return -1;

  i = 6;
  j = 0;
  while (s[i]) {
    if (s[i] == CH_SPACE) {
      name[j] = CH_NUL;
      if (j < 4) return -1;
      if (name[0] == CH_DOT) return -1;
      if (name[j - 3] != CH_DOT) return -1;
      if (name[j - 2] != CH_O_LOWER) return -1;
      if (name[j - 1] != CH_B) return -1;
      return 1;
    }
    if (j >= PATH_CAP - 1) return -1;
    c = s[i++];
    if (c == CH_SLASH) return -1;
    if (c == CH_BACKSLASH) return -1;
    if (c == CH_LF) return -1;
    if (c == CH_CR) return -1;
    if (c == CH_DOT) {
      if (j) {
        if (name[j - 1] == CH_DOT) return -1;
      }
    }
    name[j++] = c;
  }
  return -1;
}

static void make_path(const char *dir, const char *file) {
  int dir_len = str_len(dir);
  int file_len = str_len(file);
  if (dir_len + file_len + 2 >= PATH_CAP) {
    fprintf(stderr, "materialize-object-script: output path too long: %s/%s\n", dir, file);
    exit(1);
  }
  copy_bytes(path, dir, dir_len);
  path[dir_len] = CH_SLASH;
  dir_len++;
  copy_bytes(path + dir_len, file, file_len);
  path[dir_len + file_len] = CH_NUL;
}

static int read_line(FILE *in, int *line_no) {
  int c;
  int len;

  len = 0;
  while ((c = fgetc(in)) != EOF) {
    if (len >= LINE_CAP - 1) {
      die_line("input line is too long", *line_no + 1);
    }
    line[len++] = c;
    if (c == CH_LF) break;
  }
  if (len == 0 && c == EOF) return 0;
  line[len] = CH_NUL;
  *line_no = *line_no + 1;
  return 1;
}

int main(int argc, char **argv) {
  FILE *in;
  FILE *out;
  int line_no;
  int header;
  int wrote_any;

  if (argc != 3) {
    fprintf(stderr, "usage: materialize-object-script INPUT_SCRIPT OUTPUT_DIR\n");
    return 2;
  }

  /* M2-Planet mishandles indexed writes to static char arrays on amd64. */
  line = calloc(LINE_CAP, 1);
  name = calloc(PATH_CAP, 1);
  path = calloc(PATH_CAP, 1);
  if (!line || !name || !path) {
    fprintf(stderr, "materialize-object-script: out of memory\n");
    return 1;
  }

  in = fopen(argv[1], "r");
  if (!in) {
    fprintf(stderr, "materialize-object-script: cannot open input: %s\n", argv[1]);
    return 1;
  }

  line_no = 0;
  wrote_any = 0;
  while (read_line(in, &line_no)) {
    header = parse_header(line);
    if (header == 0) continue;
    if (header < 0) die_unexpected("unexpected object script command", line, line_no);

    make_path(argv[2], name);
    out = fopen(path, "w");
    if (!out) {
      fprintf(stderr, "materialize-object-script: cannot open output: %s\n", path);
      fclose(in);
      return 1;
    }

    while (read_line(in, &line_no)) {
      if (is_eof_line(line)) break;
      if (fputs(line, out) < 0) {
        fprintf(stderr, "materialize-object-script: write failed: %s\n", path);
        fclose(out);
        fclose(in);
        return 1;
      }
    }
    if (!is_eof_line(line)) {
      fclose(out);
      die_line("unterminated object payload", line_no);
    }
    if (fclose(out) != 0) {
      fprintf(stderr, "materialize-object-script: close failed: %s\n", path);
      fclose(in);
      return 1;
    }
    wrote_any = 1;
  }

  if (fclose(in) != 0) {
    fprintf(stderr, "materialize-object-script: close failed: %s\n", argv[1]);
    return 1;
  }
  if (!wrote_any) {
    fprintf(stderr, "materialize-object-script: no object payloads found\n");
    return 1;
  }
  return 0;
}
