#ifndef DART_PTY_MACOS_NATIVE_PTY_SPAWN_INTERNAL_H_
#define DART_PTY_MACOS_NATIVE_PTY_SPAWN_INTERNAL_H_

#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/types.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct DptyPreparedSpawnConfig {
  const char* executable;
  char* const* argv;
  char* const* envp;
  const char* working_directory;
  struct winsize initial_size;
} DptyPreparedSpawnConfig;

typedef struct DptyPreparedSpawnResult {
  pid_t child_pid;
  int master_fd;
  int exec_error_fd;
} DptyPreparedSpawnResult;

int32_t dpty_spawn_prepared(const DptyPreparedSpawnConfig* config,
                            DptyPreparedSpawnResult* result,
                            int32_t* out_error_number);

__attribute__((noreturn)) void dpty_exec_child(
    int exec_error_read_fd, int exec_error_write_fd, const char* executable,
    char* const* argv, char* const* envp, const char* working_directory);

#if defined(__cplusplus)
}
#endif

#endif  // DART_PTY_MACOS_NATIVE_PTY_SPAWN_INTERNAL_H_
