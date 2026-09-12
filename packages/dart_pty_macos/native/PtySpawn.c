#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <sys/wait.h>
#include <unistd.h>
#include <util.h>

#include "PtySpawnInternal.h"
#include "dart_pty_macos.h"

static int set_close_on_exec(int fd) {
  const int flags = fcntl(fd, F_GETFD);
  if (flags < 0) {
    return -1;
  }
  return fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

static int move_above_standard_descriptors(int* fd) {
  if (*fd > STDERR_FILENO) {
    return 0;
  }
  const int moved = fcntl(*fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
  if (moved < 0) {
    return -1;
  }
  (void)close(*fd);
  *fd = moved;
  return 0;
}

int32_t dpty_spawn_prepared(const DptyPreparedSpawnConfig* config,
                            DptyPreparedSpawnResult* result,
                            int32_t* out_error_number) {
  if (config == NULL || result == NULL || out_error_number == NULL ||
      config->executable == NULL || config->argv == NULL ||
      config->envp == NULL || config->initial_size.ws_row == 0 ||
      config->initial_size.ws_col == 0) {
    if (out_error_number != NULL) {
      *out_error_number = EINVAL;
    }
    return DPTY_STATUS_INVALID_ARGUMENT;
  }

  result->child_pid = -1;
  result->master_fd = -1;
  result->exec_error_fd = -1;
  *out_error_number = 0;

  int exec_error_pipe[2] = {-1, -1};
  if (pipe(exec_error_pipe) != 0) {
    *out_error_number = errno;
    return DPTY_STATUS_SYSTEM_ERROR;
  }
  if (move_above_standard_descriptors(&exec_error_pipe[0]) != 0 ||
      move_above_standard_descriptors(&exec_error_pipe[1]) != 0 ||
      set_close_on_exec(exec_error_pipe[0]) != 0 ||
      set_close_on_exec(exec_error_pipe[1]) != 0) {
    const int saved_errno = errno;
    if (exec_error_pipe[0] >= 0) {
      (void)close(exec_error_pipe[0]);
    }
    if (exec_error_pipe[1] >= 0) {
      (void)close(exec_error_pipe[1]);
    }
    *out_error_number = saved_errno;
    return DPTY_STATUS_SYSTEM_ERROR;
  }

  int master_fd = -1;
  struct winsize initial_size = config->initial_size;
  const pid_t child_pid = forkpty(&master_fd, NULL, NULL, &initial_size);
  if (child_pid == 0) {
    dpty_exec_child(exec_error_pipe[0], exec_error_pipe[1], config->executable,
                    config->argv, config->envp, config->working_directory);
  }
  if (child_pid < 0) {
    const int saved_errno = errno;
    (void)close(exec_error_pipe[0]);
    (void)close(exec_error_pipe[1]);
    *out_error_number = saved_errno;
    return DPTY_STATUS_SYSTEM_ERROR;
  }

  (void)close(exec_error_pipe[1]);
  const int current_flags = fcntl(master_fd, F_GETFL);
  if (set_close_on_exec(master_fd) != 0 || current_flags < 0 ||
      fcntl(master_fd, F_SETFL, current_flags | O_NONBLOCK) != 0) {
    const int saved_errno = errno;
    (void)kill(child_pid, SIGKILL);
    while (waitpid(child_pid, NULL, 0) < 0 && errno == EINTR) {
    }
    (void)close(master_fd);
    (void)close(exec_error_pipe[0]);
    *out_error_number = saved_errno;
    return DPTY_STATUS_SYSTEM_ERROR;
  }

  result->child_pid = child_pid;
  result->master_fd = master_fd;
  result->exec_error_fd = exec_error_pipe[0];
  return DPTY_STATUS_OK;
}
