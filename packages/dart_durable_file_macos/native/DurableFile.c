#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define DDF_EXPORT __attribute__((visibility("default")))
#define DDF_ABI_VERSION 1u
#define DDF_DIRECTORY_MODE 0700
#define DDF_FILE_MODE 0600
#define DDF_MAX_PATH_BYTES 4096u
#define DDF_MAX_LEAF_BYTES 255u
#define DDF_MAX_PAYLOAD_BYTES (16u * 1024u * 1024u)

enum ddf_failure {
  DDF_OK = 0,
  DDF_INVALID_ARGUMENT = 1,
  DDF_UNSUPPORTED = 2,
  DDF_NOT_FOUND = 3,
  DDF_PERMISSION_DENIED = 4,
  DDF_UNSAFE_TYPE = 5,
  DDF_HARD_LINK = 6,
  DDF_WRONG_OWNER = 7,
  DDF_ALREADY_EXISTS = 8,
  DDF_BUSY = 9,
  DDF_TOO_LARGE = 10,
  DDF_READ_FAILED = 11,
  DDF_WRITE_FAILED = 12,
  DDF_FILE_SYNC_FAILED = 13,
  DDF_RENAME_FAILED = 14,
  DDF_UNLINK_FAILED = 15,
  DDF_DIRECTORY_SYNC_FAILED = 16,
  DDF_RESOURCE_LIMIT = 17,
  DDF_INVALID_STATE = 18,
  DDF_UNKNOWN = 19,
};

typedef struct ddf_session {
  int directory_fd;
  int lock_fd;
} ddf_session;

typedef struct ddf_file_info_v1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t exists;
  uint32_t mode;
  uint64_t length;
  uint64_t link_count;
  uint32_t owner_matches;
  uint32_t reserved;
} ddf_file_info_v1;

static _Atomic uint64_t ddf_open_sessions = 0;

static int32_t ddf_errno_failure(int error, int32_t fallback) {
  switch (error) {
    case EINVAL:
    case ENAMETOOLONG:
      return DDF_INVALID_ARGUMENT;
    case ENOENT:
      return DDF_NOT_FOUND;
    case EACCES:
    case EPERM:
    case EROFS:
      return DDF_PERMISSION_DENIED;
    case EEXIST:
      return DDF_ALREADY_EXISTS;
    case ELOOP:
    case ENOTDIR:
    case EISDIR:
      return DDF_UNSAFE_TYPE;
    case EAGAIN:
      return DDF_BUSY;
    case EMFILE:
    case ENFILE:
    case ENOMEM:
      return DDF_RESOURCE_LIMIT;
    default:
      return fallback;
  }
}

static int ddf_valid_leaf(const char *leaf) {
  if (leaf == NULL) return 0;
  const size_t length = strnlen(leaf, DDF_MAX_LEAF_BYTES + 1u);
  if (length == 0u || length > DDF_MAX_LEAF_BYTES ||
      strcmp(leaf, ".") == 0 || strcmp(leaf, "..") == 0) {
    return 0;
  }
  for (size_t index = 0; index < length; index++) {
    const unsigned char value = (unsigned char)leaf[index];
    const int alpha = (value >= 'A' && value <= 'Z') ||
                      (value >= 'a' && value <= 'z');
    const int digit = value >= '0' && value <= '9';
    if (!alpha && !digit && value != '.' && value != '_' && value != '-') {
      return 0;
    }
  }
  return 1;
}

static int32_t ddf_validate_regular_stat(const struct stat *status) {
  if (!S_ISREG(status->st_mode)) return DDF_UNSAFE_TYPE;
  if (status->st_nlink != 1) return DDF_HARD_LINK;
  if (status->st_uid != geteuid()) return DDF_WRONG_OWNER;
  if (status->st_size < 0) return DDF_TOO_LARGE;
  return DDF_OK;
}

static int ddf_open_regular(ddf_session *session, const char *leaf,
                            int flags, struct stat *status,
                            int32_t *failure) {
  const int descriptor = openat(session->directory_fd, leaf,
                                flags | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (descriptor < 0) {
    *failure = ddf_errno_failure(errno, DDF_READ_FAILED);
    return -1;
  }
  if (fstat(descriptor, status) != 0) {
    *failure = ddf_errno_failure(errno, DDF_READ_FAILED);
    close(descriptor);
    return -1;
  }
  *failure = ddf_validate_regular_stat(status);
  if (*failure != DDF_OK) {
    close(descriptor);
    return -1;
  }
  if (fchmod(descriptor, DDF_FILE_MODE) != 0) {
    *failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
    close(descriptor);
    return -1;
  }
  return descriptor;
}

static int ddf_open_directory_path(const char *path, uint32_t create,
                                   int32_t *failure) {
  if (path == NULL || path[0] != '/' || path[1] == '\0') {
    *failure = DDF_INVALID_ARGUMENT;
    return -1;
  }
  const size_t length = strnlen(path, DDF_MAX_PATH_BYTES + 1u);
  if (length == 0u || length > DDF_MAX_PATH_BYTES) {
    *failure = DDF_INVALID_ARGUMENT;
    return -1;
  }
  char *copy = strdup(path);
  if (copy == NULL) {
    *failure = DDF_RESOURCE_LIMIT;
    return -1;
  }
  int descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (descriptor < 0) {
    free(copy);
    *failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
    return -1;
  }
  char *cursor = NULL;
  char *component = strtok_r(copy, "/", &cursor);
  while (component != NULL) {
    if (strcmp(component, ".") == 0 || strcmp(component, "..") == 0) {
      close(descriptor);
      free(copy);
      *failure = DDF_INVALID_ARGUMENT;
      return -1;
    }
    int next = openat(descriptor, component,
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0 && errno == ENOENT && create != 0u) {
      if (mkdirat(descriptor, component, DDF_DIRECTORY_MODE) != 0 &&
          errno != EEXIST) {
        *failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
        close(descriptor);
        free(copy);
        return -1;
      }
      if (fsync(descriptor) != 0) {
        close(descriptor);
        free(copy);
        *failure = DDF_DIRECTORY_SYNC_FAILED;
        return -1;
      }
      next = openat(descriptor, component,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    }
    if (next < 0) {
      *failure = ddf_errno_failure(errno, DDF_UNSAFE_TYPE);
      close(descriptor);
      free(copy);
      return -1;
    }
    close(descriptor);
    descriptor = next;
    component = strtok_r(NULL, "/", &cursor);
  }
  free(copy);
  struct stat status;
  if (fstat(descriptor, &status) != 0 || !S_ISDIR(status.st_mode)) {
    close(descriptor);
    *failure = DDF_UNSAFE_TYPE;
    return -1;
  }
  if (status.st_uid != geteuid()) {
    close(descriptor);
    *failure = DDF_WRONG_OWNER;
    return -1;
  }
  if (fchmod(descriptor, DDF_DIRECTORY_MODE) != 0) {
    *failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
    close(descriptor);
    return -1;
  }
  *failure = DDF_OK;
  return descriptor;
}

DDF_EXPORT uint32_t ddf_abi_version(void) { return DDF_ABI_VERSION; }

DDF_EXPORT uint64_t ddf_debug_open_session_count(void) {
  return atomic_load_explicit(&ddf_open_sessions, memory_order_relaxed);
}

DDF_EXPORT intptr_t ddf_session_open(const char *path, uint32_t create,
                                     int32_t *failure) {
  if (failure == NULL) return 0;
  const int descriptor = ddf_open_directory_path(path, create, failure);
  if (descriptor < 0) return 0;
  ddf_session *session = (ddf_session *)calloc(1u, sizeof(ddf_session));
  if (session == NULL) {
    close(descriptor);
    *failure = DDF_RESOURCE_LIMIT;
    return 0;
  }
  session->directory_fd = descriptor;
  session->lock_fd = -1;
  atomic_fetch_add_explicit(&ddf_open_sessions, 1u, memory_order_relaxed);
  return (intptr_t)session;
}

DDF_EXPORT int32_t ddf_session_close(intptr_t handle) {
  if (handle == 0) return DDF_INVALID_ARGUMENT;
  ddf_session *session = (ddf_session *)handle;
  int32_t result = DDF_OK;
  if (session->lock_fd >= 0) {
    if (flock(session->lock_fd, LOCK_UN) != 0) result = DDF_UNKNOWN;
    if (close(session->lock_fd) != 0) result = DDF_UNKNOWN;
  }
  if (close(session->directory_fd) != 0) result = DDF_UNKNOWN;
  free(session);
  atomic_fetch_sub_explicit(&ddf_open_sessions, 1u, memory_order_relaxed);
  return result;
}

DDF_EXPORT int32_t ddf_acquire_lock(intptr_t handle, const char *leaf) {
  if (handle == 0 || !ddf_valid_leaf(leaf)) return DDF_INVALID_ARGUMENT;
  ddf_session *session = (ddf_session *)handle;
  if (session->lock_fd >= 0) return DDF_INVALID_STATE;
  const int descriptor = openat(session->directory_fd, leaf,
                                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                                DDF_FILE_MODE);
  if (descriptor < 0) {
    return ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
  }
  struct stat status;
  if (fstat(descriptor, &status) != 0) {
    const int32_t failure = ddf_errno_failure(errno, DDF_READ_FAILED);
    close(descriptor);
    return failure;
  }
  int32_t failure = ddf_validate_regular_stat(&status);
  if (failure == DDF_OK && fchmod(descriptor, DDF_FILE_MODE) != 0) {
    failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
  }
  if (failure == DDF_OK && flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
    failure = ddf_errno_failure(errno, DDF_BUSY);
  }
  if (failure != DDF_OK) {
    close(descriptor);
    return failure;
  }
  session->lock_fd = descriptor;
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_inspect(intptr_t handle, const char *leaf,
                               ddf_file_info_v1 *info) {
  if (handle == 0 || !ddf_valid_leaf(leaf) || info == NULL ||
      info->struct_size != sizeof(ddf_file_info_v1) ||
      info->version != DDF_ABI_VERSION) {
    return DDF_INVALID_ARGUMENT;
  }
  ddf_session *session = (ddf_session *)handle;
  struct stat status;
  int32_t failure = DDF_OK;
  const int descriptor = ddf_open_regular(session, leaf, O_RDONLY,
                                           &status, &failure);
  if (descriptor < 0) {
    if (failure == DDF_NOT_FOUND) {
      info->exists = 0u;
      info->mode = 0u;
      info->length = 0u;
      info->link_count = 0u;
      info->owner_matches = 0u;
      info->reserved = 0u;
      return DDF_OK;
    }
    return failure;
  }
  close(descriptor);
  info->exists = 1u;
  info->mode = (uint32_t)(status.st_mode & 0777);
  info->length = (uint64_t)status.st_size;
  info->link_count = (uint64_t)status.st_nlink;
  info->owner_matches = status.st_uid == geteuid() ? 1u : 0u;
  info->reserved = 0u;
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_read(intptr_t handle, const char *leaf,
                            uint64_t maximum_bytes, uint8_t *output,
                            uint64_t capacity, uint64_t *output_length) {
  if (handle == 0 || !ddf_valid_leaf(leaf) || output == NULL ||
      output_length == NULL || maximum_bytes > DDF_MAX_PAYLOAD_BYTES) {
    return DDF_INVALID_ARGUMENT;
  }
  ddf_session *session = (ddf_session *)handle;
  struct stat status;
  int32_t failure = DDF_OK;
  const int descriptor = ddf_open_regular(session, leaf, O_RDONLY,
                                           &status, &failure);
  if (descriptor < 0) return failure;
  const uint64_t length = (uint64_t)status.st_size;
  if (length > maximum_bytes || length > capacity) {
    close(descriptor);
    return DDF_TOO_LARGE;
  }
  uint64_t offset = 0u;
  while (offset < length) {
    const ssize_t count = read(descriptor, output + offset,
                               (size_t)(length - offset));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      close(descriptor);
      return DDF_READ_FAILED;
    }
    offset += (uint64_t)count;
  }
  struct stat final_status;
  if (fstat(descriptor, &final_status) != 0 ||
      final_status.st_dev != status.st_dev ||
      final_status.st_ino != status.st_ino ||
      final_status.st_size != status.st_size ||
      final_status.st_nlink != status.st_nlink) {
    close(descriptor);
    return DDF_READ_FAILED;
  }
  if (close(descriptor) != 0) return DDF_READ_FAILED;
  *output_length = length;
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_write_exclusive(intptr_t handle, const char *leaf,
                                       const uint8_t *input,
                                       uint64_t length) {
  if (handle == 0 || !ddf_valid_leaf(leaf) || input == NULL) {
    return DDF_INVALID_ARGUMENT;
  }
  if (length > DDF_MAX_PAYLOAD_BYTES) return DDF_TOO_LARGE;
  ddf_session *session = (ddf_session *)handle;
  const int descriptor = openat(session->directory_fd, leaf,
                                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                                    O_NOFOLLOW,
                                DDF_FILE_MODE);
  if (descriptor < 0) {
    return ddf_errno_failure(errno, DDF_WRITE_FAILED);
  }
  if (fchmod(descriptor, DDF_FILE_MODE) != 0) {
    const int32_t failure = ddf_errno_failure(errno, DDF_PERMISSION_DENIED);
    close(descriptor);
    return failure;
  }
  uint64_t offset = 0u;
  while (offset < length) {
    const ssize_t count = write(descriptor, input + offset,
                                (size_t)(length - offset));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      close(descriptor);
      return DDF_WRITE_FAILED;
    }
    offset += (uint64_t)count;
  }
  if (fsync(descriptor) != 0) {
    close(descriptor);
    return DDF_FILE_SYNC_FAILED;
  }
  if (close(descriptor) != 0) return DDF_WRITE_FAILED;
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_rename(intptr_t handle, const char *source,
                              const char *destination) {
  if (handle == 0 || !ddf_valid_leaf(source) ||
      !ddf_valid_leaf(destination) || strcmp(source, destination) == 0) {
    return DDF_INVALID_ARGUMENT;
  }
  ddf_session *session = (ddf_session *)handle;
  struct stat status;
  int32_t failure = DDF_OK;
  int descriptor = ddf_open_regular(session, source, O_RDONLY,
                                    &status, &failure);
  if (descriptor < 0) return failure;
  close(descriptor);
  descriptor = ddf_open_regular(session, destination, O_RDONLY,
                                &status, &failure);
  if (descriptor >= 0) {
    close(descriptor);
  } else if (failure != DDF_NOT_FOUND) {
    return failure;
  }
  if (renameat(session->directory_fd, source,
               session->directory_fd, destination) != 0) {
    return ddf_errno_failure(errno, DDF_RENAME_FAILED);
  }
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_unlink(intptr_t handle, const char *leaf) {
  if (handle == 0 || !ddf_valid_leaf(leaf)) return DDF_INVALID_ARGUMENT;
  ddf_session *session = (ddf_session *)handle;
  struct stat status;
  if (fstatat(session->directory_fd, leaf, &status,
              AT_SYMLINK_NOFOLLOW) != 0) {
    return ddf_errno_failure(errno, DDF_UNLINK_FAILED);
  }
  const int32_t failure = ddf_validate_regular_stat(&status);
  if (failure != DDF_OK) return failure;
  if (unlinkat(session->directory_fd, leaf, 0) != 0) {
    return ddf_errno_failure(errno, DDF_UNLINK_FAILED);
  }
  return DDF_OK;
}

DDF_EXPORT int32_t ddf_sync_directory(intptr_t handle) {
  if (handle == 0) return DDF_INVALID_ARGUMENT;
  ddf_session *session = (ddf_session *)handle;
  if (fsync(session->directory_fd) != 0) return DDF_DIRECTORY_SYNC_FAILED;
  return DDF_OK;
}
