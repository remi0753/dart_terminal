#include "TerminalNotesPlugin.h"

_Static_assert(DTN_ABI_VERSION == 1u, "ABI version changed");
_Static_assert(DTN_PROJECTION_HEADER_BYTES == 128u, "header layout changed");
_Static_assert(DTN_CARD_RECORD_BYTES == 32u, "card layout changed");
_Static_assert(DTN_MAX_CARDS == 64u, "projection card bound changed");
_Static_assert(sizeof(DtnSurfaceSnapshotV1) == 160u,
               "snapshot ABI layout changed");
_Static_assert(offsetof(DtnSurfaceSnapshotV1, interaction_flags) == 152u,
               "interaction flags ABI offset changed");
_Static_assert(offsetof(DtnSurfaceSnapshotV1, focus_target) == 156u,
               "focus target ABI offset changed");
_Static_assert(sizeof(DtnPresentationSnapshotV1) == 232u,
               "presentation snapshot ABI layout changed");
_Static_assert(sizeof(DtnSurfaceIntentV1) == 112u,
               "intent ABI layout changed");
_Static_assert(sizeof(DtnSurfaceResultV1) == 88u,
               "result ABI layout changed");

int main(void) {
  DtnSurface* surface = (DtnSurface*)0;
  int32_t (*attach_renderer)(DtnSurface*, uint64_t, uint64_t) =
      dtn_surface_attach_to_renderer;
  return surface == (DtnSurface*)0 && attach_renderer != 0 ? 0 : 1;
}
