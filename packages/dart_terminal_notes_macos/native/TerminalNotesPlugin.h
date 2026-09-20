#ifndef DART_TERMINAL_NOTES_MACOS_NATIVE_TERMINAL_NOTES_PLUGIN_H_
#define DART_TERMINAL_NOTES_MACOS_NATIVE_TERMINAL_NOTES_PLUGIN_H_

#include <stddef.h>
#include <stdint.h>

#define DTN_ABI_VERSION 1u
#define DTN_PROJECTION_VERSION 1u
#define DTN_SNAPSHOT_VERSION 1u
#define DTN_PROJECTION_MAGIC 0x31504e44u
#define DTN_PROJECTION_HEADER_BYTES 128u
#define DTN_CARD_RECORD_BYTES 32u
#define DTN_MAX_CARDS 64u
#define DTN_MAX_MATERIALIZED_CARDS 32u
#define DTN_MAX_CARD_BODY_BYTES 4096u
#define DTN_MAX_BODY_BYTES (256u * 1024u)
#define DTN_MAX_CONTEXT_NOTES 128u
#define DTN_MAX_PACKET_BYTES \
  (DTN_PROJECTION_HEADER_BYTES + DTN_MAX_CARDS * DTN_CARD_RECORD_BYTES + \
   DTN_MAX_BODY_BYTES)

typedef enum DtnStatus {
  DTN_STATUS_OK = 0,
  DTN_STATUS_INVALID_ARGUMENT = 1,
  DTN_STATUS_UNSUPPORTED_VERSION = 2,
  DTN_STATUS_STALE = 3,
  DTN_STATUS_INTERNAL = 4,
} DtnStatus;

typedef enum DtnVisibility {
  DTN_VISIBILITY_COLLAPSED = 0,
  DTN_VISIBILITY_EXPANDED = 1,
} DtnVisibility;

typedef enum DtnFeatureState {
  DTN_FEATURE_DISABLED = 0,
  DTN_FEATURE_STARTING = 1,
  DTN_FEATURE_AVAILABLE = 2,
  DTN_FEATURE_IN_USE_BY_OTHER_PROCESS = 3,
  DTN_FEATURE_RECOVERY_REQUIRED = 4,
  DTN_FEATURE_INCOMPATIBLE_STORE = 5,
  DTN_FEATURE_UNAVAILABLE = 6,
} DtnFeatureState;

typedef enum DtnSurfaceState {
  DTN_SURFACE_ATTACHING = 0,
  DTN_SURFACE_READY = 1,
  DTN_SURFACE_TOO_SMALL = 2,
  DTN_SURFACE_NATIVE_UNAVAILABLE = 3,
  DTN_SURFACE_DISPOSED = 4,
} DtnSurfaceState;

typedef enum DtnCollectionSection {
  DTN_SECTION_CURRENT = 0,
  DTN_SECTION_DETACHED = 1,
} DtnCollectionSection;

typedef enum DtnEditorMode {
  DTN_EDITOR_INACTIVE = 0,
  DTN_EDITOR_CREATING = 1,
  DTN_EDITOR_EDITING = 2,
} DtnEditorMode;

typedef enum DtnMessageKey {
  DTN_MESSAGE_NONE = 0,
  DTN_MESSAGE_PANE_TOO_SMALL = 1,
  DTN_MESSAGE_NATIVE_UNAVAILABLE = 2,
  DTN_MESSAGE_PROJECTION_REJECTED = 3,
  DTN_MESSAGE_STORE_UNAVAILABLE = 4,
  DTN_MESSAGE_RECOVERY_REQUIRED = 5,
} DtnMessageKey;

typedef struct DtnSurface DtnSurface;

typedef struct DtnSurfaceSnapshotV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t pane_id;
  uint64_t surface_generation;
  uint64_t projection_generation;
  uint64_t store_revision_low;
  uint64_t store_revision_high;
  uint64_t accepted_projection_count;
  uint64_t rejected_projection_count;
  uint32_t active_count;
  uint32_t due_count;
  uint32_t projected_card_count;
  uint32_t materialized_card_count;
  uint32_t packet_bytes;
  uint32_t visibility;
  uint32_t presentation_eligible;
  uint32_t initialized;
  uint32_t projection_flags;
  uint32_t feature_state;
  uint32_t surface_state;
  uint32_t section;
  uint32_t editor_mode;
  uint32_t message_key;
  uint32_t page_start;
  uint32_t total_count;
  uint32_t body_font_millipoints;
  uint32_t reserved[7];
} DtnSurfaceSnapshotV1;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtn_abi_version(void);

__attribute__((visibility("default"))) DtnSurface* dtn_surface_create(void);

__attribute__((visibility("default"))) int32_t dtn_surface_apply_projection(
    DtnSurface* surface, const uint8_t* bytes, size_t length);

__attribute__((visibility("default"))) int32_t dtn_surface_snapshot(
    DtnSurface* surface, DtnSurfaceSnapshotV1* snapshot);

__attribute__((visibility("default"))) void dtn_surface_destroy(
    DtnSurface* surface);

__attribute__((visibility("default"))) uint64_t dtn_debug_live_surfaces(void);

#if defined(__cplusplus)
}
#endif

#endif
