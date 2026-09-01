#include "PtySpawn.h"

#include <errno.h>
#include <unistd.h>

__attribute__((noreturn, noinline)) void dt_pty_exec_child(
    int exec_error_read_fd,
    int exec_error_write_fd,
    const char* executable,
    char* const* argv,
    char* const* envp) {
  (void)close(exec_error_read_fd);
  (void)execve(executable, argv, envp);

  const int saved_errno = errno;
  (void)write(exec_error_write_fd, &saved_errno, sizeof(saved_errno));
  _exit(127);
}
