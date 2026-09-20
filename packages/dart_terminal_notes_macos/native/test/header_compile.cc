#include "TerminalNotesPlugin.h"

#include <type_traits>

static_assert(DTN_ABI_VERSION == 1u);
static_assert(sizeof(DtnSurfaceSnapshotV1) == 160u);
static_assert(offsetof(DtnSurfaceSnapshotV1, interaction_flags) == 152u);
static_assert(offsetof(DtnSurfaceSnapshotV1, focus_target) == 156u);
static_assert(sizeof(DtnPresentationSnapshotV1) == 232u);
static_assert(sizeof(DtnSurfaceIntentV1) == 112u);
static_assert(sizeof(DtnSurfaceResultV1) == 88u);
static_assert(std::is_standard_layout_v<DtnSurfaceSnapshotV1>);

int main() {
  auto* attach_renderer = &dtn_surface_attach_to_renderer;
  return dtn_abi_version() == 1u && attach_renderer != nullptr ? 0 : 1;
}
