#ifndef DART_TERMINAL_NOTES_MACOS_NATIVE_TERMINAL_NOTES_PLUGIN_H_
#define DART_TERMINAL_NOTES_MACOS_NATIVE_TERMINAL_NOTES_PLUGIN_H_

#include <stddef.h>
#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTN_ABI_VERSION 1u
#define DTN_PROJECTION_VERSION 1u
#define DTN_SNAPSHOT_VERSION 1u
#define DTN_LAYOUT_VERSION 1u
#define DTN_PRESENTATION_SNAPSHOT_VERSION 1u
#define DTN_INTENT_VERSION 1u
#define DTN_RESULT_VERSION 1u
#define DTN_PROJECTION_MAGIC 0x31504e44u
#define DTN_PROJECTION_HEADER_BYTES 128u
#define DTN_CARD_RECORD_BYTES 32u
#define DTN_MAX_CARDS 64u
#define DTN_MAX_MATERIALIZED_CARDS 32u
#define DTN_MAX_CARD_BODY_BYTES 4096u
#define DTN_MAX_BODY_BYTES (256u * 1024u)
#define DTN_MAX_CONTEXT_NOTES 128u
#define DTN_MAX_INTENT_PAYLOAD_BYTES 4096u
#define DTN_NO_COLOR 0xffffffffu
#define DTN_MAX_PACKET_BYTES \
  (DTN_PROJECTION_HEADER_BYTES + DTN_MAX_CARDS * DTN_CARD_RECORD_BYTES + \
   DTN_MAX_BODY_BYTES)

typedef enum DtnStatus {
  DTN_STATUS_OK = 0,
  DTN_STATUS_INVALID_ARGUMENT = 1,
  DTN_STATUS_UNSUPPORTED_VERSION = 2,
  DTN_STATUS_STALE = 3,
  DTN_STATUS_INTERNAL = 4,
  DTN_STATUS_WRONG_THREAD = 5,
  DTN_STATUS_NOT_FOUND = 6,
  DTN_STATUS_BUSY = 7,
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

typedef enum DtnIntentKind {
  DTN_INTENT_SAVE = 0,
  DTN_INTENT_CANCEL = 1,
  DTN_INTENT_CHANGE_COLOR = 2,
  DTN_INTENT_MOVE_EARLIER = 3,
  DTN_INTENT_MOVE_LATER = 4,
  DTN_INTENT_RESOLVE = 5,
  DTN_INTENT_REOPEN = 6,
  DTN_INTENT_DELETE = 7,
  DTN_INTENT_REATTACH = 8,
  DTN_INTENT_EXPORT = 9,
  DTN_INTENT_COPY = 10,
} DtnIntentKind;

typedef enum DtnResultDisposition {
  DTN_RESULT_ACCEPTED = 0,
  DTN_RESULT_CONFLICT = 1,
  DTN_RESULT_REJECTED = 2,
  DTN_RESULT_BUSY = 3,
  DTN_RESULT_UNAVAILABLE = 4,
} DtnResultDisposition;

typedef enum DtnFocusTarget {
  DTN_FOCUS_NONE = 0,
  DTN_FOCUS_RAIL = 1,
  DTN_FOCUS_EDITOR = 2,
} DtnFocusTarget;

enum {
  DTN_INTERACTION_EDITOR_DIRTY = 1u << 0,
  DTN_INTERACTION_CONFIRM_DISCARD = 1u << 1,
};

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
  uint64_t draft_generation;
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
  uint32_t outstanding_intent;
  uint32_t emitted_intent_count;
  uint32_t applied_result_count;
  uint32_t interaction_flags;
  uint32_t focus_target;
} DtnSurfaceSnapshotV1;

typedef struct DtnSurfaceIntentV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t surface_generation;
  uint64_t projection_generation;
  uint64_t event_generation;
  uint64_t draft_generation;
  uint64_t card_token;
  uint64_t expected_store_revision;
  uint32_t kind;
  uint32_t payload_bytes;
  uint32_t color;
  uint32_t reserved0;
  uint32_t reserved[10];
} DtnSurfaceIntentV1;

typedef struct DtnSurfaceResultV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t surface_generation;
  uint64_t projection_generation;
  uint64_t event_generation;
  uint64_t draft_generation;
  uint64_t new_store_revision;
  uint64_t new_projection_generation;
  uint32_t disposition;
  uint32_t reserved0;
  uint32_t reserved[6];
} DtnSurfaceResultV1;

enum {
  DTN_PRESENTATION_BADGE_VISIBLE = 1u << 0,
  DTN_PRESENTATION_RAIL_VISIBLE = 1u << 1,
  DTN_PRESENTATION_SMALL_PANE = 1u << 2,
  DTN_PRESENTATION_OPAQUE_CARDS = 1u << 3,
  DTN_PRESENTATION_CARD_SHADOWS = 1u << 4,
  DTN_PRESENTATION_READY_CUE = 1u << 5,
  DTN_PRESENTATION_REDUCED_MOTION = 1u << 6,
  DTN_PRESENTATION_DIFFERENTIATE_WITHOUT_COLOR = 1u << 7,
  DTN_PRESENTATION_INCREASE_CONTRAST = 1u << 8,
  DTN_PRESENTATION_DARK = 1u << 9,
  DTN_PRESENTATION_SYSTEM_BADGE_VISIBLE = 1u << 10,
  DTN_PRESENTATION_BADGE_COUNT_CAPPED = 1u << 11,
};

typedef struct DtnLayoutV1 {
  uint32_t struct_size;
  uint32_t version;
  double pane_width;
  double pane_height;
  double backing_scale;
  double requested_rail_width;
  uint32_t reserved[8];
} DtnLayoutV1;

typedef struct DtnPresentationSnapshotV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t projection_generation;
  double pane_width;
  double pane_height;
  double backing_scale;
  double badge_hit_x;
  double badge_hit_y;
  double badge_hit_width;
  double badge_hit_height;
  double badge_visual_x;
  double badge_visual_y;
  double badge_visual_width;
  double badge_visual_height;
  double rail_x;
  double rail_y;
  double rail_width;
  double rail_height;
  double first_card_x;
  double first_card_y;
  double first_card_width;
  double first_card_height;
  uint32_t flags;
  uint32_t materialized_card_count;
  uint32_t accessibility_node_count;
  uint32_t accessibility_body_count;
  uint64_t visible_acknowledgement_eligible_generation;
  uint64_t accessibility_announcement_count;
  uint32_t animation_milliseconds;
  uint32_t body_font_millipoints;
  uint32_t badge_display_count;
  uint32_t reserved[5];
} DtnPresentationSnapshotV1;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtn_abi_version(void);

__attribute__((visibility("default"))) int32_t dtn_initialize(
    const da_native_extension_services_v1* services);

// Surface lifecycle, projection, layout, snapshot, and composition calls are
// AppKit process-main-thread only. Wrong-thread calls fail without mutation.
__attribute__((visibility("default"))) DtnSurface* dtn_surface_create(void);

__attribute__((visibility("default"))) int32_t dtn_surface_apply_projection(
    DtnSurface* surface, const uint8_t* bytes, size_t length);

__attribute__((visibility("default"))) int32_t dtn_surface_snapshot(
    DtnSurface* surface, DtnSurfaceSnapshotV1* snapshot);

__attribute__((visibility("default"))) int32_t dtn_surface_update_layout(
    DtnSurface* surface, const DtnLayoutV1* layout);

__attribute__((visibility("default"))) int32_t
dtn_surface_presentation_snapshot(
    DtnSurface* surface, DtnPresentationSnapshotV1* snapshot);

// Native interaction entry point. Product UI code and native acceptance use
// this boundary; Dart consumes only take/apply below.
__attribute__((visibility("default"))) int32_t dtn_surface_request_intent(
    DtnSurface* surface, const DtnSurfaceIntentV1* intent,
    const uint8_t* payload);

__attribute__((visibility("default"))) int32_t dtn_surface_take_intent(
    DtnSurface* surface, DtnSurfaceIntentV1* intent, uint8_t* payload,
    size_t payload_capacity);

__attribute__((visibility("default"))) int32_t dtn_surface_apply_result(
    DtnSurface* surface, const DtnSurfaceResultV1* result);

// Moves first responder only within this surface. Product authority must
// confirm its generation-bound transfer only after this call succeeds.
__attribute__((visibility("default"))) int32_t dtn_surface_focus(
    DtnSurface* surface, uint32_t target);

// Native-to-native composition seam. The returned view is unretained and must
// never cross Dart FFI. attach consumes neither object.
__attribute__((visibility("default"))) void* dtn_surface_native_view(
    DtnSurface* surface);

__attribute__((visibility("default"))) int32_t dtn_surface_attach_to_host(
    DtnSurface* surface, void* host_view);

// Resolves one live product renderer generation entirely inside native code
// and attaches the Note surface above that renderer view. Only the renderer's
// opaque registry identity crosses Dart; the AppKit object never does.
__attribute__((visibility("default"))) int32_t dtn_surface_attach_to_renderer(
    DtnSurface* surface, uint64_t renderer_handle,
    uint64_t renderer_generation);

__attribute__((visibility("default"))) int32_t dtn_surface_detach_from_host(
    DtnSurface* surface);

__attribute__((visibility("default"))) void dtn_surface_destroy(
    DtnSurface* surface);

__attribute__((visibility("default"))) uint64_t dtn_debug_live_surfaces(void);

#if defined(__cplusplus)
}
#endif

#endif
