#include <errno.h>
#include <unistd.h>

#include "PtySpawnInternal.h"

__attribute__((noreturn, noinline)) void dpty_exec_child(
    int exec_error_read_fd, int exec_error_write_fd, const char* executable,
    char* const* argv, char* const* envp, const char* working_directory) {
  (void)close(exec_error_read_fd);
  if (working_directory != NULL && chdir(working_directory) != 0) {
    const int saved_errno = errno;
    (void)write(exec_error_write_fd, &saved_errno, sizeof(saved_errno));
    _exit(126);
  }
  (void)execve(executable, argv, envp);

  const int saved_errno = errno;
  (void)write(exec_error_write_fd, &saved_errno, sizeof(saved_errno));
  _exit(127);
}
