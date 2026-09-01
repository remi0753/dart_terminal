#ifndef DART_TERMINAL_PHASE0_PTY_SPAWN_H_
#define DART_TERMINAL_PHASE0_PTY_SPAWN_H_

#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DtPtySpawnConfig {
  const char* executable;
  char* const* argv;
  char* const* envp;
  struct winsize initial_size;
} DtPtySpawnConfig;

typedef struct DtPtySpawnResult {
  pid_t child_pid;
  int master_fd;
  int exec_error_fd;
} DtPtySpawnResult;

// All argv/env strings and pointer arrays must be fully prepared before this
// function is called. The child branch calls only dt_pty_exec_child(), whose
// object file is audited separately for async-signal-safe dependencies.
int32_t dt_pty_spawn(const DtPtySpawnConfig* config,
                     DtPtySpawnResult* result,
                     int32_t* out_error_number);

__attribute__((noreturn)) void dt_pty_exec_child(
    int exec_error_read_fd,
    int exec_error_write_fd,
    const char* executable,
    char* const* argv,
    char* const* envp);

#ifdef __cplusplus
}
#endif

#endif  // DART_TERMINAL_PHASE0_PTY_SPAWN_H_
