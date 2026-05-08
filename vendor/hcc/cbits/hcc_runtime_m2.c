#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HCC_MAX_HANDLES 256
#define HCC_MAX_IARRAYS 1024
#define HCC_MAX_OBUFS 256

static char *buffer;
static unsigned buffer_len;
static unsigned buffer_cap;

static char *result;
static unsigned result_len;
static unsigned result_cap;
static unsigned result_pos;

static FILE *handles[HCC_MAX_HANDLES];
static int *iarrays[HCC_MAX_IARRAYS];
static int iarray_lens[HCC_MAX_IARRAYS];

struct hcc_obuf {
  char *data;
  unsigned len;
  unsigned cap;
};

static struct hcc_obuf *obufs[HCC_MAX_OBUFS];

static void *hcc_alloc(unsigned size)
{
  void *out = malloc(size);
  if (!out) {
    fputs("hcc runtime: out of memory\n", stderr);
    exit(1);
  }
  return out;
}

static void *hcc_realloc(void *ptr, unsigned old_size, unsigned new_size)
{
  char *out = hcc_alloc(new_size);
  char *in = ptr;
  unsigned i = 0;
  while (i < old_size && i < new_size) {
    out[i] = in[i];
    i = i + 1;
  }
  if (ptr) free(ptr);
  return out;
}

static void ensure_chars(char **ptr, unsigned *cap, unsigned needed)
{
  unsigned next;
  if (*cap >= needed) return;
  next = *cap;
  if (!next) next = 64;
  while (next < needed) next = next * 2;
  *ptr = hcc_realloc(*ptr, *cap, next);
  *cap = next;
}

void hcc_buffer_clear(void)
{
  buffer_len = 0;
  ensure_chars(&buffer, &buffer_cap, 1);
  buffer[0] = 0;
}

void hcc_buffer_put(int c)
{
  ensure_chars(&buffer, &buffer_cap, buffer_len + 2);
  buffer[buffer_len] = c;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = 0;
}

static char *current_buffer(void)
{
  if (!buffer) hcc_buffer_clear();
  return buffer;
}

void hcc_stdout_buffer(void)
{
  fputs(current_buffer(), stdout);
}

static void set_result(char *text)
{
  unsigned len = strlen(text);
  ensure_chars(&result, &result_cap, len + 1);
  memcpy(result, text, len + 1);
  result_len = len;
  result_pos = 0;
}

int hcc_read_file(void)
{
  FILE *file = fopen(current_buffer(), "r");
  int c;
  if (!file) return 0;
  result_len = 0;
  result_pos = 0;
  ensure_chars(&result, &result_cap, 1);
  c = fgetc(file);
  while (c != EOF) {
    ensure_chars(&result, &result_cap, result_len + 2);
    result[result_len] = c;
    result_len = result_len + 1;
    c = fgetc(file);
  }
  result[result_len] = 0;
  fclose(file);
  return 1;
}

int hcc_result_eof(void)
{
  return result_pos >= result_len;
}

int hcc_result_char(void)
{
  if (result_pos >= result_len) return 0;
  result_pos = result_pos + 1;
  return result[result_pos - 1];
}

int hcc_result_len(void)
{
  return result_len;
}

int hcc_result_at(int index)
{
  if (index < 0) return 0;
  if (index >= result_len) return 0;
  return result[index];
}

void hcc_stderr_char(int c)
{
  fputc(c, stderr);
  fflush(stderr);
}

void hcc_exit_success(void)
{
  exit(0);
}

void hcc_exit_failure(void)
{
  exit(1);
}

static int alloc_handle(FILE *file)
{
  int i = 0;
  if (!file) return 0;
  while (i < HCC_MAX_HANDLES) {
    if (!handles[i]) {
      handles[i] = file;
      return i + 1;
    }
    i = i + 1;
  }
  fclose(file);
  return 0;
}

static FILE *get_handle(int handle)
{
  if (handle <= 0) return 0;
  if (handle > HCC_MAX_HANDLES) return 0;
  return handles[handle - 1];
}

int hcc_open_read(void)
{
  return alloc_handle(fopen(current_buffer(), "r"));
}

int hcc_open_write(void)
{
  return alloc_handle(fopen(current_buffer(), "w"));
}

int hcc_handle_eof(int handle)
{
  FILE *file = get_handle(handle);
  int c;
  if (!file) return 1;
  c = fgetc(file);
  if (c == EOF) return 1;
  ungetc(c, file);
  return 0;
}

int hcc_handle_read_char(int handle)
{
  FILE *file = get_handle(handle);
  int c;
  if (!file) return 0;
  c = fgetc(file);
  if (c == EOF) return 0;
  return c;
}

void hcc_handle_write_char(int handle, int c)
{
  FILE *file = get_handle(handle);
  if (file) fputc(c, file);
}

void hcc_handle_write_buffer(int handle)
{
  FILE *file = get_handle(handle);
  if (file) fputs(current_buffer(), file);
}

void hcc_handle_flush(int handle)
{
  FILE *file = get_handle(handle);
  if (file) fflush(file);
}

static unsigned long alloc_obuf(struct hcc_obuf *out)
{
  int i = 0;
  if (!out) return 0;
  while (i < HCC_MAX_OBUFS) {
    if (!obufs[i]) {
      obufs[i] = out;
      return i + 1;
    }
    i = i + 1;
  }
  free(out->data);
  free(out);
  return 0;
}

unsigned long hcc_obuf_new(int initial_cap)
{
  struct hcc_obuf *out = hcc_alloc(sizeof(struct hcc_obuf));
  unsigned cap = initial_cap;
  if (!cap) cap = 64;
  out->data = hcc_alloc(cap);
  out->len = 0;
  out->cap = cap;
  return alloc_obuf(out);
}

static struct hcc_obuf *get_obuf(unsigned long handle)
{
  if (!handle) return 0;
  if (handle > HCC_MAX_OBUFS) return 0;
  return obufs[handle - 1];
}

void hcc_obuf_free(unsigned long handle)
{
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  free(out->data);
  free(out);
  obufs[handle - 1] = 0;
}

void hcc_obuf_clear(unsigned long handle)
{
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  out->len = 0;
}

int hcc_obuf_len(unsigned long handle)
{
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return 0;
  return out->len;
}

void hcc_obuf_put(unsigned long handle, int c)
{
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  ensure_chars(&out->data, &out->cap, out->len + 1);
  out->data[out->len] = c;
  out->len = out->len + 1;
}

void hcc_obuf_write(int handle, unsigned long obuf_handle)
{
  FILE *file = get_handle(handle);
  struct hcc_obuf *out = get_obuf(obuf_handle);
  if (!file) return;
  if (!out) return;
  if (!out->len) return;
  fwrite(out->data, 1, out->len, file);
}

void hcc_close(int handle)
{
  FILE *file;
  if (handle <= 0) return;
  if (handle > HCC_MAX_HANDLES) return;
  file = handles[handle - 1];
  if (!file) return;
  fclose(file);
  handles[handle - 1] = 0;
}

int hcc_lookup_env(void)
{
  return 0;
}

int hcc_find_executable(void)
{
  return 0;
}

void hcc_canonicalize(void)
{
  set_result(current_buffer());
}

int hcc_does_file_exist(void)
{
  FILE *file = fopen(current_buffer(), "r");
  if (!file) return 0;
  fclose(file);
  return 1;
}

void hcc_process_clear(void)
{
}

void hcc_process_push(void)
{
}

int hcc_process_run(void)
{
  return 1;
}

int hcc_iarray_new(int size, int initial)
{
  int i = 0;
  int j;
  int alloc_size;
  int *values;
  if (size < 0) return 0;
  while (i < HCC_MAX_IARRAYS) {
    if (!iarrays[i]) {
      alloc_size = size;
      if (!alloc_size) alloc_size = 1;
      values = hcc_alloc(alloc_size * sizeof(int));
      j = 0;
      while (j < size) {
        values[j] = initial;
        j = j + 1;
      }
      iarrays[i] = values;
      iarray_lens[i] = size;
      return i + 1;
    }
    i = i + 1;
  }
  return 0;
}

int hcc_iarray_read(int ident, int index)
{
  int slot;
  if (ident <= 0) return 0;
  if (ident > HCC_MAX_IARRAYS) return 0;
  slot = ident - 1;
  if (!iarrays[slot]) return 0;
  if (index < 0) return 0;
  if (index >= iarray_lens[slot]) return 0;
  return iarrays[slot][index];
}

void hcc_iarray_write(int ident, int index, int value)
{
  int slot;
  if (ident <= 0) return;
  if (ident > HCC_MAX_IARRAYS) return;
  slot = ident - 1;
  if (!iarrays[slot]) return;
  if (index < 0) return;
  if (index >= iarray_lens[slot]) return;
  iarrays[slot][index] = value;
}
