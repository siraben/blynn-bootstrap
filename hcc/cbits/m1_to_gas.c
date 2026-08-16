/* Translate the amd64 subset of stage0 M1 emitted by hcc-m1 to GNU as.
 *
 * HCC's M1 files are whole-program-linkable text.  Keeping each translation
 * unit as an ELF object is useful for large programs: the system assembler
 * records unresolved C symbols as ordinary relocations and the final link can
 * use archives without teaching HCC about ELF.  This translator deliberately
 * implements the small, architecture-independent M1 token grammar rather than
 * recognizing any GCC source names.
 */

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct macro {
  char *name;
  char *value;
  struct macro *next;
};

struct reader {
  FILE *file;
  const char *name;
  unsigned long line;
  int pushed;
};

static struct macro *macros;

static void fail_at(struct reader *reader, const char *message, const char *token)
{
  fprintf(stderr, "%s:%lu: %s", reader->name, reader->line, message);
  if (token) fprintf(stderr, ": %s", token);
  fputc('\n', stderr);
  exit(1);
}

static void *xmalloc(size_t size)
{
  void *result = malloc(size);
  if (!result) {
    fputs("m1-to-gas: out of memory\n", stderr);
    exit(1);
  }
  return result;
}

static char *xstrdup(const char *text)
{
  size_t size = strlen(text) + 1;
  char *result = xmalloc(size);
  memcpy(result, text, size);
  return result;
}

static int read_char(struct reader *reader)
{
  int c;
  if (reader->pushed != -1) {
    c = reader->pushed;
    reader->pushed = -1;
  } else {
    c = fgetc(reader->file);
  }
  if (c == '\n') reader->line++;
  return c;
}

static void unread_char(struct reader *reader, int c)
{
  if (c == EOF) return;
  if (reader->pushed != -1) fail_at(reader, "internal pushback overflow", 0);
  if (c == '\n') reader->line--;
  reader->pushed = c;
}

static char *next_token(struct reader *reader)
{
  size_t capacity = 64;
  size_t length = 0;
  char *token;
  int c;
  int quote = 0;

  for (;;) {
    c = read_char(reader);
    if (c == EOF) return 0;
    if (c == '#') {
      while (c != EOF && c != '\n') c = read_char(reader);
      continue;
    }
    if (!isspace((unsigned char)c)) break;
  }

  token = xmalloc(capacity);
  if (c == '\'' || c == '"') {
    quote = c;
    token[length++] = (char)c;
    for (;;) {
      c = read_char(reader);
      if (c == EOF || c == '\n') fail_at(reader, "unterminated quoted M1 token", token);
      if (length + 2 >= capacity) {
        char *larger;
        capacity *= 2;
        larger = xmalloc(capacity);
        memcpy(larger, token, length);
        free(token);
        token = larger;
      }
      token[length++] = (char)c;
      if (c == quote) break;
    }
  } else {
    token[length++] = (char)c;
    for (;;) {
      c = read_char(reader);
      if (c == EOF || isspace((unsigned char)c) || c == '#') break;
      if (length + 1 >= capacity) {
        char *larger;
        capacity *= 2;
        larger = xmalloc(capacity);
        memcpy(larger, token, length);
        free(token);
        token = larger;
      }
      token[length++] = (char)c;
    }
    if (c == '#') {
      while (c != EOF && c != '\n') c = read_char(reader);
    } else {
      unread_char(reader, c);
    }
  }
  token[length] = 0;
  return token;
}

static void define_macro(const char *name, const char *value)
{
  struct macro *item = xmalloc(sizeof(*item));
  item->name = xstrdup(name);
  item->value = xstrdup(value);
  item->next = macros;
  macros = item;
}

static const char *find_macro(const char *name)
{
  struct macro *item;
  for (item = macros; item; item = item->next) {
    if (strcmp(item->name, name) == 0) return item->value;
  }
  return 0;
}

static int hex_digit(int c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int is_hex_bytes(const char *text)
{
  size_t i;
  size_t length = strlen(text);
  if (length == 0 || (length & 1) != 0) return 0;
  for (i = 0; i < length; i++) {
    if (hex_digit((unsigned char)text[i]) < 0) return 0;
  }
  return 1;
}

static void emit_hex_bytes(struct reader *reader, FILE *out, const char *text)
{
  size_t i;
  size_t length = strlen(text);
  if (!is_hex_bytes(text)) fail_at(reader, "invalid hexadecimal M1 byte string", text);
  fputs("\t.byte ", out);
  for (i = 0; i < length; i += 2) {
    int value = (hex_digit((unsigned char)text[i]) << 4)
      | hex_digit((unsigned char)text[i + 1]);
    if (i) fputc(',', out);
    fprintf(out, "0x%02x", value);
  }
  fputc('\n', out);
}

static const char *elf_symbol(const char *m1_symbol)
{
  static const char function_prefix[] = "FUNCTION_";
  size_t prefix_length = sizeof(function_prefix) - 1;
  if (strncmp(m1_symbol, function_prefix, prefix_length) == 0)
    return m1_symbol + prefix_length;
  return m1_symbol;
}

static int is_external_definition(const char *m1_symbol)
{
  const char *symbol = elf_symbol(m1_symbol);
  if (strncmp(symbol, "HCC_", 4) == 0) return 0;
  return 1;
}

static int parse_number(const char *text, long *value)
{
  char *end;
  errno = 0;
  *value = strtol(text, &end, 0);
  return errno == 0 && end != text && *end == 0;
}

static int parse_data_addend(const char *symbol, const char **base,
                             size_t *base_length, long *offset)
{
  static const char prefix[] = "HCC_DATA_";
  const char *separator;
  const char *start;

  if (strncmp(symbol, prefix, sizeof(prefix) - 1) != 0) return 0;
  start = symbol + sizeof(prefix) - 1;
  separator = strrchr(start, '_');
  if (!separator || separator == start || !parse_number(separator + 1, offset))
    return 0;
  *base = start;
  *base_length = (size_t)(separator - start);
  return 1;
}

static void emit_symbol_expression(FILE *out, const char *symbol)
{
  const char *base;
  size_t base_length;
  long offset;

  if (parse_data_addend(symbol, &base, &base_length, &offset))
    fprintf(out, "%.*s + %ld", (int)base_length, base, offset);
  else
    fputs(symbol, out);
}

static void emit_numeric_pointer(struct reader *reader, FILE *out, int prefix,
                                 const char *text)
{
  long value;
  if (!parse_number(text, &value)) fail_at(reader, "invalid numeric M1 pointer", text);
  switch (prefix) {
    case '!': fprintf(out, "\t.byte %ld\n", value); break;
    case '@':
    case '$': fprintf(out, "\t.short %ld\n", value); break;
    case '~':
      fprintf(out, "\t.byte %ld,%ld,%ld\n",
              value & 255, (value >> 8) & 255, (value >> 16) & 255);
      break;
    case '%':
    case '&': fprintf(out, "\t.long %ld\n", value); break;
    default: fail_at(reader, "unsupported numeric M1 pointer width", text);
  }
}

static void emit_symbol_pointer(struct reader *reader, FILE *out, int prefix,
                                const char *text)
{
  const char *symbol = elf_symbol(text);
  if (strchr(symbol, '>')) fail_at(reader, "M1 alternate relative bases are unsupported", text);
  switch (prefix) {
    case '!':
      fputs("\t.byte ", out); emit_symbol_expression(out, symbol);
      fputs(" - . - 1\n", out); break;
    case '@':
      fputs("\t.short ", out); emit_symbol_expression(out, symbol);
      fputs(" - . - 2\n", out); break;
    case '$':
      fputs("\t.short ", out); emit_symbol_expression(out, symbol);
      fputc('\n', out); break;
    case '~': fail_at(reader, "24-bit symbolic M1 relocations are unsupported", text); break;
    case '%':
      fputs("\t.long ", out); emit_symbol_expression(out, symbol);
      fputs(" - . - 4\n", out); break;
    case '&':
      fputs("\t.long ", out); emit_symbol_expression(out, symbol);
      fputc('\n', out);
      break;
    default: fail_at(reader, "unknown M1 pointer prefix", text);
  }
}

static void emit_pointer(struct reader *reader, FILE *out, const char *token)
{
  long ignored;
  if (!token[1]) fail_at(reader, "empty M1 pointer", token);
  if (parse_number(token + 1, &ignored))
    emit_numeric_pointer(reader, out, token[0], token + 1);
  else
    emit_symbol_pointer(reader, out, token[0], token + 1);
}

static void emit_quoted(struct reader *reader, FILE *out, const char *token)
{
  size_t length = strlen(token);
  char *contents;
  size_t i;
  if (length < 2 || token[length - 1] != token[0])
    fail_at(reader, "malformed quoted M1 token", token);
  contents = xmalloc(length - 1);
  memcpy(contents, token + 1, length - 2);
  contents[length - 2] = 0;
  if (token[0] == '\'') {
    emit_hex_bytes(reader, out, contents);
  } else {
    fputs("\t.byte ", out);
    for (i = 0; i < length - 2; i++) {
      if (i) fputc(',', out);
      fprintf(out, "0x%02x", (unsigned char)contents[i]);
    }
    if (length == 2) fputs("0", out);
    fputc('\n', out);
  }
  free(contents);
}

static void emit_label(FILE *out, const char *m1_symbol)
{
  const char *symbol = elf_symbol(m1_symbol);
  if (is_external_definition(m1_symbol)) fprintf(out, "\t.globl %s\n", symbol);
  if (strncmp(m1_symbol, "FUNCTION_", 9) == 0)
    fprintf(out, "\t.type %s,@function\n", symbol);
  fprintf(out, "%s:\n", symbol);
}

static void translate(struct reader *reader, FILE *out)
{
  char *token;
  int in_text = 0;
  fputs("\t.section .hcc.data,\"aw\",@progbits\n\t.balign 1\n", out);
  while ((token = next_token(reader)) != 0) {
    const char *expansion;
    if (strcmp(token, "DEFINE") == 0) {
      char *name = next_token(reader);
      char *value = next_token(reader);
      if (!name || !value) fail_at(reader, "incomplete M1 DEFINE", token);
      if (value[0] == '\'' && value[strlen(value) - 1] == '\'')
        value[strlen(value) - 1] = 0;
      define_macro(name, value[0] == '\'' ? value + 1 : value);
      free(name);
      free(value);
    } else if (token[0] == ':' && token[1]) {
      if (!in_text && strncmp(token + 1, "FUNCTION_", 9) == 0) {
        fputs("\t.section .hcc.text,\"ax\",@progbits\n\t.balign 1\n", out);
        in_text = 1;
      } else if (in_text && strncmp(token + 1, "HCC_DATA_", 9) == 0) {
        fputs("\t.section .hcc.data,\"aw\",@progbits\n\t.balign 1\n", out);
        in_text = 0;
      }
      emit_label(out, token + 1);
    } else if (strchr("!@$~%&", token[0]) && token[1]) {
      emit_pointer(reader, out, token);
    } else if (token[0] == '<' && token[1]) {
      long count;
      if (!parse_number(token + 1, &count) || count < 0)
        fail_at(reader, "invalid M1 zero padding", token);
      fprintf(out, "\t.zero %ld\n", count);
    } else if (token[0] == '^') {
      /* Hex2 metadata marker: intentionally emits no bytes. */
    } else if (token[0] == '\'' || token[0] == '"') {
      emit_quoted(reader, out, token);
    } else if ((expansion = find_macro(token)) != 0) {
      emit_hex_bytes(reader, out, expansion);
    } else if (is_hex_bytes(token)) {
      emit_hex_bytes(reader, out, token);
    } else {
      fail_at(reader, "unknown M1 token", token);
    }
    free(token);
  }
  fputs("\t.section .note.GNU-stack,\"\",@progbits\n", out);
}

int main(int argc, char **argv)
{
  struct reader reader;
  FILE *input;
  FILE *output;
  if (argc != 3) {
    fputs("usage: m1-to-gas INPUT.M1 OUTPUT.s\n", stderr);
    return 2;
  }
  input = fopen(argv[1], "r");
  if (!input) {
    fprintf(stderr, "m1-to-gas: cannot open %s: %s\n", argv[1], strerror(errno));
    return 1;
  }
  output = fopen(argv[2], "w");
  if (!output) {
    fprintf(stderr, "m1-to-gas: cannot create %s: %s\n", argv[2], strerror(errno));
    fclose(input);
    return 1;
  }
  reader.file = input;
  reader.name = argv[1];
  reader.line = 1;
  reader.pushed = -1;
  translate(&reader, output);
  if (fclose(output) != 0) {
    fprintf(stderr, "m1-to-gas: failed to write %s\n", argv[2]);
    fclose(input);
    return 1;
  }
  fclose(input);
  return 0;
}
