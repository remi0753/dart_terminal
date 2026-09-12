#include <type_traits>

#include "dart_pty_macos.h"

static_assert(std::is_standard_layout_v<DptySessionConfigV1>);
static_assert(std::is_standard_layout_v<DptySessionStatsV1>);
static_assert(std::is_standard_layout_v<DptyProcessSnapshotV1>);
static_assert(std::is_standard_layout_v<DptyError>);

int main() {
  auto* create = &dpty_session_create;
  auto* force_close = &dpty_session_force_close;
  auto* get_process_snapshot = &dpty_session_get_process_snapshot;
  auto* destroy = &dpty_session_destroy;
  return create == nullptr || force_close == nullptr ||
         get_process_snapshot == nullptr || destroy == nullptr;
}
