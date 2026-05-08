#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define HCC_MAX_HANDLES 256
#define HCC_MAX_IARRAYS 1024

static char *buffer;
static size_t buffer_len;
static size_t buffer_cap;

static char *result;
static size_t result_len;
static size_t result_pos;

static FILE *handles[HCC_MAX_HANDLES];
static int *iarrays[HCC_MAX_IARRAYS];
static int iarray_lens[HCC_MAX_IARRAYS];

static char **process_argv;
static size_t process_argc;
static size_t process_cap;

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

static char *copy_string(const char *src) {
  size_t len = strlen(src);
  char *out = checked_realloc(NULL, len + 1);
  memcpy(out, src, len + 1);
  return out;
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

static const char *current_buffer(void) {
  if (!buffer) hcc_buffer_clear();
  return buffer;
}

static void set_result(const char *text) {
  size_t len = strlen(text);
  ensure_chars(&result, &result_len, len + 1);
  memcpy(result, text, len + 1);
  result_len = len;
  result_pos = 0;
}

int hcc_result_eof(void) {
  return result_pos >= result_len;
}

int hcc_result_char(void) {
  if (result_pos >= result_len) return 0;
  return (unsigned char)result[result_pos++];
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

int hcc_open_read(void) {
  return alloc_handle(fopen(current_buffer(), "rb"));
}

int hcc_open_write(void) {
  return alloc_handle(fopen(current_buffer(), "wb"));
}

int hcc_handle_eof(int handle) {
  FILE *file = get_handle(handle);
  if (!file) return 1;
  int c = fgetc(file);
  if (c == EOF) return 1;
  ungetc(c, file);
  return 0;
}

int hcc_handle_read_char(int handle) {
  FILE *file = get_handle(handle);
  if (!file) return 0;
  int c = fgetc(file);
  return c == EOF ? 0 : c;
}

void hcc_handle_write_char(int handle, int c) {
  FILE *file = get_handle(handle);
  if (file) fputc(c, file);
}

void hcc_handle_write_buffer(int handle) {
  FILE *file = get_handle(handle);
  if (file) fputs(current_buffer(), file);
}

void hcc_handle_flush(int handle) {
  FILE *file = get_handle(handle);
  if (file) fflush(file);
}

void hcc_close(int handle) {
  if (handle <= 0 || handle > HCC_MAX_HANDLES) return;
  FILE *file = handles[handle - 1];
  if (!file) return;
  fclose(file);
  handles[handle - 1] = NULL;
}

int hcc_lookup_env(void) {
  const char *value = getenv(current_buffer());
  if (!value) return 0;
  set_result(value);
  return 1;
}

static int is_executable(const char *path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISREG(st.st_mode) && access(path, X_OK) == 0;
}

static int has_slash(const char *text) {
  while (*text) {
    if (*text++ == '/') return 1;
  }
  return 0;
}

int hcc_find_executable(void) {
  const char *name = current_buffer();
  if (has_slash(name)) {
    if (is_executable(name)) {
      set_result(name);
      return 1;
    }
    return 0;
  }

  const char *path = getenv("PATH");
  if (!path) path = "/bin:/usr/bin";
  char *copy = copy_string(path);
  char *save = NULL;
  for (char *dir = strtok_r(copy, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
    size_t len = strlen(dir) + 1 + strlen(name) + 1;
    char *candidate = checked_realloc(NULL, len);
    snprintf(candidate, len, "%s/%s", dir[0] ? dir : ".", name);
    if (is_executable(candidate)) {
      set_result(candidate);
      free(candidate);
      free(copy);
      return 1;
    }
    free(candidate);
  }
  free(copy);
  return 0;
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

void hcc_process_clear(void) {
  for (size_t i = 0; i < process_argc; i++) free(process_argv[i]);
  process_argc = 0;
}

void hcc_process_push(void) {
  if (process_argc + 2 > process_cap) {
    size_t next = process_cap ? process_cap * 2 : 8;
    process_argv = checked_realloc(process_argv, next * sizeof(char *));
    process_cap = next;
  }
  process_argv[process_argc++] = copy_string(current_buffer());
  process_argv[process_argc] = NULL;
}

int hcc_process_run(void) {
  if (!process_argc) return 1;
  pid_t pid = fork();
  if (pid < 0) return 1;
  if (pid == 0) {
    execvp(process_argv[0], process_argv);
    _exit(errno == ENOENT ? 127 : 126);
  }
  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) return 1;
  }
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return 1;
}

int hcc_iarray_new(int size, int initial) {
  if (size < 0) return 0;
  for (int i = 0; i < HCC_MAX_IARRAYS; i++) {
    if (!iarrays[i]) {
      int *values = checked_realloc(NULL, (size_t)(size ? size : 1) * sizeof(int));
      for (int j = 0; j < size; j++) values[j] = initial;
      iarrays[i] = values;
      iarray_lens[i] = size;
      return i + 1;
    }
  }
  return 0;
}

int hcc_iarray_read(int ident, int index) {
  if (ident <= 0 || ident > HCC_MAX_IARRAYS) return 0;
  int slot = ident - 1;
  if (!iarrays[slot]) return 0;
  if (index < 0 || index >= iarray_lens[slot]) return 0;
  return iarrays[slot][index];
}

void hcc_iarray_write(int ident, int index, int value) {
  if (ident <= 0 || ident > HCC_MAX_IARRAYS) return;
  int slot = ident - 1;
  if (!iarrays[slot]) return;
  if (index < 0 || index >= iarray_lens[slot]) return;
  iarrays[slot][index] = value;
}
