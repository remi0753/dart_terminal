#include "dart_pty_macos.h"

int main(void) {
  DptySessionConfigV1 config = {0};
  DptySessionStatsV1 stats = {0};
  DptyProcessSnapshotV1 process_snapshot = {0};
  DptyWorkingDirectorySnapshotV1 working_directory_snapshot = {0};
  DptyError error = {0};
  uint32_t (*version)(void) = dpty_abi_version;
  int32_t (*force_close)(DptySessionHandle) = dpty_session_force_close;
  int32_t (*get_process_snapshot)(DptySessionHandle,
                                  DptyProcessSnapshotV1*) =
      dpty_session_get_process_snapshot;
  int32_t (*get_working_directory_snapshot)(
      DptySessionHandle, DptyWorkingDirectorySnapshotV1*) =
      dpty_session_get_working_directory_snapshot;
  config.struct_size = sizeof(config);
  stats.struct_size = sizeof(stats);
  process_snapshot.struct_size = sizeof(process_snapshot);
  working_directory_snapshot.struct_size =
      sizeof(working_directory_snapshot);
  return config.struct_size == 0 || stats.struct_size == 0 ||
         process_snapshot.struct_size == 0 ||
         working_directory_snapshot.struct_size == 0 ||
         error.status != DPTY_STATUS_OK || version == NULL ||
         force_close == NULL || get_process_snapshot == NULL ||
         get_working_directory_snapshot == NULL;
}
