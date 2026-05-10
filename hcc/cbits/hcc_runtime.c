#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define HCC_MAX_HANDLES 256
#define HCC_MAX_OBUFS 256

static char *buffer;
static size_t buffer_len;
static size_t buffer_cap;

static char *result;
static size_t result_len;
static size_t result_cap;

static FILE *handles[HCC_MAX_HANDLES];

struct hcc_obuf {
  char *data;
  size_t len;
  size_t cap;
};

static struct hcc_obuf *obufs[HCC_MAX_OBUFS];

static void *checked_realloc(void *ptr, size_t size) {
  void *out = realloc(ptr, size);
  if (!out) {
    fputs("hcc runtime: out of memory\n", stderr);
    exit(1);
  }
  return out;
}

static void ensure_chars(char **ptr, size_t *cap, size_t needed) {
  if (*cap >= needed) return;
  size_t next = *cap ? *cap : 64;
  while (next < needed) next *= 2;
  *ptr = checked_realloc(*ptr, next);
  *cap = next;
}

void hcc_buffer_clear(void) {
  buffer_len = 0;
  ensure_chars(&buffer, &buffer_cap, 1);
  buffer[0] = 0;
}

void hcc_buffer_put(int c) {
  ensure_chars(&buffer, &buffer_cap, buffer_len + 2);
  buffer[buffer_len++] = (char)c;
  buffer[buffer_len] = 0;
}

void hcc_buffer_put4(int c1, int c2, int c3, int c4) {
  ensure_chars(&buffer, &buffer_cap, buffer_len + 5);
  buffer[buffer_len++] = (char)c1;
  buffer[buffer_len++] = (char)c2;
  buffer[buffer_len++] = (char)c3;
  buffer[buffer_len++] = (char)c4;
  buffer[buffer_len] = 0;
}

void hcc_buffer_put8(
    int c1, int c2, int c3, int c4,
    int c5, int c6, int c7, int c8) {
  ensure_chars(&buffer, &buffer_cap, buffer_len + 9);
  buffer[buffer_len++] = (char)c1;
  buffer[buffer_len++] = (char)c2;
  buffer[buffer_len++] = (char)c3;
  buffer[buffer_len++] = (char)c4;
  buffer[buffer_len++] = (char)c5;
  buffer[buffer_len++] = (char)c6;
  buffer[buffer_len++] = (char)c7;
  buffer[buffer_len++] = (char)c8;
  buffer[buffer_len] = 0;
}

static const char *current_buffer(void) {
  if (!buffer) hcc_buffer_clear();
  return buffer;
}

void hcc_stdout_buffer(void) {
  fputs(current_buffer(), stdout);
}

static void set_result(const char *text) {
  size_t len = strlen(text);
  ensure_chars(&result, &result_cap, len + 1);
  memcpy(result, text, len + 1);
  result_len = len;
}

int hcc_read_file(void) {
  FILE *file = fopen(current_buffer(), "rb");
  if (!file) return 0;
  result_len = 0;
  ensure_chars(&result, &result_cap, 1);
  int c = fgetc(file);
  while (c != EOF) {
    ensure_chars(&result, &result_cap, result_len + 2);
    result[result_len++] = (char)c;
    c = fgetc(file);
  }
  result[result_len] = 0;
  fclose(file);
  return 1;
}

int hcc_result_len(void) {
  return (int)result_len;
}

int hcc_result_at(int index) {
  if (index < 0 || (size_t)index >= result_len) return 0;
  return (unsigned char)result[index];
}

void hcc_stderr_char(int c) {
  fputc(c, stderr);
  fflush(stderr);
}

void hcc_exit_success(void) {
  exit(0);
}

void hcc_exit_failure(void) {
  exit(1);
}

static int alloc_handle(FILE *file) {
  if (!file) return 0;
  for (int i = 0; i < HCC_MAX_HANDLES; i++) {
    if (!handles[i]) {
      handles[i] = file;
      return i + 1;
    }
  }
  fclose(file);
  return 0;
}

static FILE *get_handle(int handle) {
  if (handle <= 0 || handle > HCC_MAX_HANDLES) return NULL;
  return handles[handle - 1];
}

int hcc_open_write(void) {
  return alloc_handle(fopen(current_buffer(), "wb"));
}

void hcc_handle_flush(int handle) {
  FILE *file = get_handle(handle);
  if (file) fflush(file);
}

static unsigned long alloc_obuf(struct hcc_obuf *out) {
  if (!out) return 0;
  for (int i = 0; i < HCC_MAX_OBUFS; i++) {
    if (!obufs[i]) {
      obufs[i] = out;
      return (unsigned long)(i + 1);
    }
  }
  free(out->data);
  free(out);
  return 0;
}

unsigned long hcc_obuf_new(int initial_cap) {
  struct hcc_obuf *out = checked_realloc(NULL, sizeof(struct hcc_obuf));
  size_t cap = initial_cap > 0 ? (size_t)initial_cap : 64;
  out->data = checked_realloc(NULL, cap);
  out->len = 0;
  out->cap = cap;
  return alloc_obuf(out);
}

static struct hcc_obuf *get_obuf(unsigned long handle) {
  if (handle == 0 || handle > HCC_MAX_OBUFS) return NULL;
  return obufs[handle - 1];
}

void hcc_obuf_free(unsigned long handle) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  free(out->data);
  free(out);
  obufs[handle - 1] = NULL;
}

void hcc_obuf_clear(unsigned long handle) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  out->len = 0;
}

int hcc_obuf_len(unsigned long handle) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return 0;
  return (int)out->len;
}

void hcc_obuf_put(unsigned long handle, int c) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  ensure_chars(&out->data, &out->cap, out->len + 1);
  out->data[out->len++] = (char)c;
}

void hcc_obuf_put4(unsigned long handle, int c1, int c2, int c3, int c4) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  ensure_chars(&out->data, &out->cap, out->len + 4);
  out->data[out->len++] = (char)c1;
  out->data[out->len++] = (char)c2;
  out->data[out->len++] = (char)c3;
  out->data[out->len++] = (char)c4;
}

void hcc_obuf_put8(
    unsigned long handle,
    int c1, int c2, int c3, int c4,
    int c5, int c6, int c7, int c8) {
  struct hcc_obuf *out = get_obuf(handle);
  if (!out) return;
  ensure_chars(&out->data, &out->cap, out->len + 8);
  out->data[out->len++] = (char)c1;
  out->data[out->len++] = (char)c2;
  out->data[out->len++] = (char)c3;
  out->data[out->len++] = (char)c4;
  out->data[out->len++] = (char)c5;
  out->data[out->len++] = (char)c6;
  out->data[out->len++] = (char)c7;
  out->data[out->len++] = (char)c8;
}

void hcc_obuf_write(int handle, unsigned long obuf_handle) {
  FILE *file = get_handle(handle);
  struct hcc_obuf *out = get_obuf(obuf_handle);
  if (!file || !out || out->len == 0) return;
  fwrite(out->data, 1, out->len, file);
}

void hcc_close(int handle) {
  if (handle <= 0 || handle > HCC_MAX_HANDLES) return;
  FILE *file = handles[handle - 1];
  if (!file) return;
  fclose(file);
  handles[handle - 1] = NULL;
}

void hcc_canonicalize(void) {
  char resolved[PATH_MAX];
  if (realpath(current_buffer(), resolved)) {
    set_result(resolved);
  } else {
    set_result(current_buffer());
  }
}

int hcc_does_file_exist(void) {
  struct stat st;
  return stat(current_buffer(), &st) == 0 && S_ISREG(st.st_mode);
}
