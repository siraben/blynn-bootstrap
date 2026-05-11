#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HCC_MAX_HANDLES 256
#define HCC_MAX_OBUFS 256

static char *buffer;
static unsigned buffer_len;
static unsigned buffer_cap;

static char *result;
static unsigned result_len;
static unsigned result_cap;

static unsigned handles[HCC_MAX_HANDLES];
static unsigned obuf_data[HCC_MAX_OBUFS];
static unsigned obuf_len[HCC_MAX_OBUFS];
static unsigned obuf_cap[HCC_MAX_OBUFS];
static int obuf_used[HCC_MAX_OBUFS];

void *hcc_rts_alloc(unsigned long size)
{
  void *out = malloc(size);
  if (!out) {
    fputs("hcc runtime: out of memory\n", stderr);
    exit(1);
  }
  return out;
}

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
  while (i < old_size) {
    if (i >= new_size) return out;
    out[i] = in[i];
    i = i + 1;
  }
  if (ptr) free(ptr);
  return out;
}

static void ensure_chars(char **ptr, unsigned *cap, unsigned needed)
{
  unsigned next = *cap;
  if (*cap >= needed) return;
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

void hcc_buffer_put4(int c1, int c2, int c3, int c4)
{
  ensure_chars(&buffer, &buffer_cap, buffer_len + 5);
  buffer[buffer_len] = c1;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c2;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c3;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c4;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = 0;
}

void hcc_buffer_put8(int c1, int c2, int c3, int c4, int c5, int c6, int c7, int c8)
{
  ensure_chars(&buffer, &buffer_cap, buffer_len + 9);
  buffer[buffer_len] = c1;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c2;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c3;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c4;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c5;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c6;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c7;
  buffer_len = buffer_len + 1;
  buffer[buffer_len] = c8;
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
}

int hcc_read_file(void)
{
  FILE *file = fopen(current_buffer(), "r");
  if (!file) return 0;
  result_len = 0;
  ensure_chars(&result, &result_cap, 1);
  int c = fgetc(file);
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
      handles[i] = (unsigned)file;
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
  unsigned file = handles[handle - 1];
  return file;
}

int hcc_open_write(void)
{
  return alloc_handle(fopen(current_buffer(), "w"));
}

void hcc_handle_flush(int handle)
{
  FILE *file = get_handle(handle);
  if (file) fflush(file);
}

static int obuf_index(unsigned long handle)
{
  if (!handle) return -1;
  if (handle > HCC_MAX_OBUFS) return -1;
  if (!obuf_used[handle - 1]) return -1;
  return handle - 1;
}

static unsigned long alloc_obuf(void)
{
  int i = 0;
  while (i < HCC_MAX_OBUFS) {
    if (!obuf_used[i]) {
      obuf_used[i] = 1;
      obuf_data[i] = 0;
      obuf_len[i] = 0;
      obuf_cap[i] = 0;
      return i + 1;
    }
    i = i + 1;
  }
  return 0;
}

unsigned long hcc_obuf_new(int initial_cap)
{
  unsigned cap = initial_cap;
  if (!cap) cap = 64;
  unsigned long handle = alloc_obuf();
  if (!handle) return 0;
  int ix = handle - 1;
  obuf_data[ix] = (unsigned)hcc_alloc(cap);
  obuf_cap[ix] = cap;
  return handle;
}

void hcc_obuf_free(unsigned long handle)
{
  int ix = obuf_index(handle);
  if (ix < 0) return;
  char *data = obuf_data[ix];
  free(data);
  obuf_data[ix] = 0;
  obuf_len[ix] = 0;
  obuf_cap[ix] = 0;
  obuf_used[ix] = 0;
}

void hcc_obuf_clear(unsigned long handle)
{
  int ix = obuf_index(handle);
  if (ix < 0) return;
  obuf_len[ix] = 0;
}

int hcc_obuf_len(unsigned long handle)
{
  int ix = obuf_index(handle);
  if (ix < 0) return 0;
  return obuf_len[ix];
}

void hcc_obuf_put(unsigned long handle, int c)
{
  int ix = obuf_index(handle);
  if (ix < 0) return;
  char *data = obuf_data[ix];
  ensure_chars(&data, &obuf_cap[ix], obuf_len[ix] + 1);
  obuf_data[ix] = (unsigned)data;
  data[obuf_len[ix]] = c;
  obuf_len[ix] = obuf_len[ix] + 1;
}

void hcc_obuf_put4(unsigned long handle, int c1, int c2, int c3, int c4)
{
  int ix = obuf_index(handle);
  if (ix < 0) return;
  char *data = obuf_data[ix];
  ensure_chars(&data, &obuf_cap[ix], obuf_len[ix] + 4);
  obuf_data[ix] = (unsigned)data;
  unsigned pos = obuf_len[ix];
  data[pos] = c1;
  data[pos + 1] = c2;
  data[pos + 2] = c3;
  data[pos + 3] = c4;
  obuf_len[ix] = pos + 4;
}

void hcc_obuf_put8(
  unsigned long handle,
  int c1, int c2, int c3, int c4,
  int c5, int c6, int c7, int c8)
{
  int ix = obuf_index(handle);
  if (ix < 0) return;
  char *data = obuf_data[ix];
  ensure_chars(&data, &obuf_cap[ix], obuf_len[ix] + 8);
  obuf_data[ix] = (unsigned)data;
  unsigned pos = obuf_len[ix];
  data[pos] = c1;
  data[pos + 1] = c2;
  data[pos + 2] = c3;
  data[pos + 3] = c4;
  data[pos + 4] = c5;
  data[pos + 5] = c6;
  data[pos + 6] = c7;
  data[pos + 7] = c8;
  obuf_len[ix] = pos + 8;
}

void hcc_obuf_write(int handle, unsigned long obuf_handle)
{
  FILE *file = get_handle(handle);
  int ix = obuf_index(obuf_handle);
  if (!file) return;
  if (ix < 0) return;
  if (!obuf_len[ix]) return;
  char *data = obuf_data[ix];
  fwrite(data, 1, obuf_len[ix], file);
}

void hcc_close(int handle)
{
  if (handle <= 0) return;
  if (handle > HCC_MAX_HANDLES) return;
  FILE *file = handles[handle - 1];
  if (!file) return;
  fclose(file);
  handles[handle - 1] = 0;
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
