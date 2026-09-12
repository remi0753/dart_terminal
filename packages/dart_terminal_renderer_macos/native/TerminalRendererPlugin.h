#ifndef DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
#define DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_

#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTR_ABI_VERSION 11u
#define DTR_FONT_CATALOG_SUMMARY_VERSION 1u
#define DTR_RESOLVED_FONT_VERSION 1u
#define DTR_SHAPE_BUFFER_VERSION 1u
#define DTR_SHAPE_BUFFER_MAGIC 0x48535444u
#define DTR_RASTER_BUFFER_VERSION 1u
#define DTR_RASTER_BUFFER_MAGIC 0x47525444u
#define DTR_MAX_FONT_FAMILY_BYTES 1024u
#define DTR_MAX_RESOLVE_TEXT_BYTES (1024u * 1024u)
#define DTR_MAX_POSTSCRIPT_NAME_BYTES 127u
#define DTR_MAX_SHAPE_RUNS 65536u
#define DTR_MAX_SHAPE_FACES 4096u
#define DTR_MAX_SHAPE_GLYPHS (1024u * 1024u)
#define DTR_MAX_SHAPE_OUTPUT_BYTES (64u * 1024u * 1024u)
#define DTR_MAX_RASTER_GLYPHS 4096u
#define DTR_MAX_RASTER_DIMENSION 4096u
#define DTR_MAX_RASTER_OUTPUT_BYTES (64u * 1024u * 1024u)
#define DTR_METAL_RENDERER_CONFIG_VERSION 1u
#define DTR_METAL_RENDERER_SUMMARY_VERSION 2u
#define DTR_METAL_ATLAS_RESET_VERSION 1u
#define DTR_METAL_ATLAS_UPLOAD_VERSION 1u
#define DTR_METAL_FRAME_VERSION 1u
#define DTR_METAL_VIEW_BINDING_VERSION 1u
#define DTR_METAL_SUBMISSION_VERSION 1u
#define DTR_METAL_RENDERER_STATE_VERSION 3u
#define DTR_METAL_FRAME_MAGIC 0x46525444u
#define DTR_MAX_METAL_DIMENSION 4096u
#define DTR_MAX_METAL_INSTANCES 131072u
#define DTR_MAX_METAL_ATLAS_PAGES 16u
#define DTR_MAX_METAL_ATLAS_BYTES (64u * 1024u * 1024u)
#define DTR_MAX_METAL_FRAME_BYTES (8u * 1024u * 1024u)
#define DTR_TEXT_INPUT_CLIENT_VERSION 1u
#define DTR_TEXT_INPUT_GEOMETRY_VERSION 1u
#define DTR_TEXT_INPUT_EVENT_VERSION 1u
#define DTR_TEXT_INPUT_EVENT_MAGIC 0x49545444u
#define DTR_MAX_TEXT_INPUT_BYTES (64u * 1024u)
#define DTR_MAX_TEXT_INPUT_EVENTS 256u
#define DTR_MAX_TEXT_INPUT_QUEUE_BYTES (1024u * 1024u)
#define DTR_ACCESSIBILITY_SNAPSHOT_VERSION 2u
#define DTR_MAX_ACCESSIBILITY_UTF8_BYTES (4u * 1024u * 1024u)
#define DTR_MAX_ACCESSIBILITY_UTF16_UNITS (2u * 1024u * 1024u)
#define DTR_MAX_ACCESSIBILITY_LINES 4096u
#define DTR_MAX_ACCESSIBILITY_COLUMN_BOUNDARIES (1048576u + 4096u)
#define DTR_MAX_ACCESSIBILITY_PACKET_BYTES (9u * 1024u * 1024u)

typedef enum DtrStatus {
  DTR_STATUS_OK = 0,
  DTR_STATUS_INVALID_ARGUMENT = 1,
  DTR_STATUS_UNSUPPORTED_VERSION = 2,
  DTR_STATUS_NOT_FOUND = 3,
  DTR_STATUS_RESOURCE_EXHAUSTED = 4,
  DTR_STATUS_INVALID_HANDLE = 5,
  DTR_STATUS_INTERNAL = 6,
  DTR_STATUS_BUFFER_TOO_SMALL = 7,
  DTR_STATUS_STALE_GENERATION = 8,
  DTR_STATUS_BACKPRESSURED = 9,
} DtrStatus;

typedef enum DtrFontStyle {
  DTR_FONT_STYLE_REGULAR = 0,
  DTR_FONT_STYLE_BOLD = 1,
  DTR_FONT_STYLE_ITALIC = 2,
  DTR_FONT_STYLE_BOLD_ITALIC = 3,
} DtrFontStyle;

enum {
  DTR_FONT_POLICY_ALLOW_SYNTHETIC = 1u << 0,
  DTR_FONT_POLICY_KNOWN_MASK = DTR_FONT_POLICY_ALLOW_SYNTHETIC,
};

enum {
  DTR_METAL_VIEW_OPERATION_BIND = 1,
  DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH = 2,
  DTR_METAL_VIEW_OPERATION_TEXT_INPUT_GEOMETRY = 3,
  DTR_METAL_VIEW_OPERATION_TEXT_INPUT_DETACH = 4,
  DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ACCEPTANCE = 5,
  DTR_METAL_VIEW_OPERATION_TEXT_INPUT_MATRIX = 6,
  DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_SNAPSHOT = 7,
  DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_ACCEPTANCE = 8,
};

enum {
  DTR_ACCESSIBILITY_HAS_SELECTION = 1u << 0,
  DTR_ACCESSIBILITY_HAS_CURSOR = 1u << 1,
  DTR_ACCESSIBILITY_KNOWN_FLAGS = DTR_ACCESSIBILITY_HAS_SELECTION |
                                  DTR_ACCESSIBILITY_HAS_CURSOR,
};

typedef enum DtrTextInputEventKind {
  DTR_TEXT_INPUT_EVENT_RAW_KEY_DOWN = 1,
  DTR_TEXT_INPUT_EVENT_RAW_KEY_UP = 2,
  DTR_TEXT_INPUT_EVENT_PREEDIT = 3,
  DTR_TEXT_INPUT_EVENT_COMMIT = 4,
  DTR_TEXT_INPUT_EVENT_CANCEL = 5,
  DTR_TEXT_INPUT_EVENT_OVERFLOW = 6,
} DtrTextInputEventKind;

enum {
  DTR_TEXT_INPUT_EVENT_REPEAT = 1u << 0,
};

enum {
  DTR_METAL_RENDERER_STATE_BOUND = 1u << 0,
  DTR_METAL_RENDERER_STATE_ADMITTING = 1u << 1,
  DTR_METAL_RENDERER_STATE_FAULTED = 1u << 2,
};

typedef enum DtrMetalFailureKind {
  DTR_METAL_FAILURE_NONE = 0,
  DTR_METAL_FAILURE_DEVICE_UNAVAILABLE = 1,
  DTR_METAL_FAILURE_SHADER_LIBRARY = 2,
  DTR_METAL_FAILURE_SHADER_FUNCTION = 3,
  DTR_METAL_FAILURE_PIPELINE = 4,
  DTR_METAL_FAILURE_RESOURCE_ALLOCATION = 5,
  DTR_METAL_FAILURE_COMMAND_ENCODING = 6,
  DTR_METAL_FAILURE_COMMAND_EXECUTION = 7,
  DTR_METAL_FAILURE_DEVICE_LOST = 8,
} DtrMetalFailureKind;

// One-shot test-only fault points. Production code never calls the debug
// injection function and no fault setting is retained after it is consumed.
typedef enum DtrMetalTestFailure {
  DTR_METAL_TEST_FAILURE_NONE = 0,
  DTR_METAL_TEST_FAILURE_CREATE_DEVICE = 1,
  DTR_METAL_TEST_FAILURE_CREATE_SHADER_LIBRARY = 2,
  DTR_METAL_TEST_FAILURE_DRAWABLE_UNAVAILABLE = 3,
  DTR_METAL_TEST_FAILURE_COMMAND_ENCODING = 4,
  DTR_METAL_TEST_FAILURE_COMMAND_COMPLETION = 5,
} DtrMetalTestFailure;

enum {
  DTR_FONT_STYLE_BIT_REGULAR = 1u << DTR_FONT_STYLE_REGULAR,
  DTR_FONT_STYLE_BIT_BOLD = 1u << DTR_FONT_STYLE_BOLD,
  DTR_FONT_STYLE_BIT_ITALIC = 1u << DTR_FONT_STYLE_ITALIC,
  DTR_FONT_STYLE_BIT_BOLD_ITALIC = 1u << DTR_FONT_STYLE_BOLD_ITALIC,
};

enum {
  DTR_RESOLVED_FONT_FALLBACK = 1u << 0,
  DTR_RESOLVED_FONT_COLOR_GLYPHS = 1u << 1,
  DTR_RESOLVED_FONT_SYNTHETIC = 1u << 2,
  DTR_RESOLVED_FONT_MISSING_GLYPH = 1u << 3,
  DTR_RESOLVED_FONT_MONOSPACED = 1u << 4,
  DTR_RESOLVED_FONT_KNOWN_MASK =
      DTR_RESOLVED_FONT_FALLBACK | DTR_RESOLVED_FONT_COLOR_GLYPHS |
      DTR_RESOLVED_FONT_SYNTHETIC | DTR_RESOLVED_FONT_MISSING_GLYPH |
      DTR_RESOLVED_FONT_MONOSPACED,
};

typedef struct DtrFontCatalogSummaryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t handle;
  uint64_t generation;
  double point_size;
  double cell_width;
  double cell_height;
  double ascent;
  double descent;
  double leading;
  double baseline;
  double underline_position;
  double underline_thickness;
  double strike_position;
  double strike_thickness;
  uint32_t available_style_bits;
  uint32_t synthetic_style_bits;
  uint32_t regular_face_id;
  uint32_t bold_face_id;
  uint32_t italic_face_id;
  uint32_t bold_italic_face_id;
  uint32_t reserved[4];
} DtrFontCatalogSummaryV1;

typedef struct DtrResolvedFontV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t catalog_generation;
  uint32_t face_id;
  uint32_t flags;
  uint32_t requested_style;
  uint32_t utf16_length;
  uint32_t unicode_scalar_count;
  uint32_t glyph_count;
  uint32_t postscript_name_length;
  uint32_t reserved[4];
  uint8_t postscript_name[DTR_MAX_POSTSCRIPT_NAME_BYTES + 1u];
} DtrResolvedFontV1;

enum {
  DTR_SHAPE_FEATURE_LIGATURES = 1u << 0,
  DTR_SHAPE_FEATURE_KNOWN_MASK = DTR_SHAPE_FEATURE_LIGATURES,
};

enum {
  DTR_SHAPED_RUN_FALLBACK = DTR_RESOLVED_FONT_FALLBACK,
  DTR_SHAPED_RUN_COLOR_GLYPHS = DTR_RESOLVED_FONT_COLOR_GLYPHS,
  DTR_SHAPED_RUN_SYNTHETIC = DTR_RESOLVED_FONT_SYNTHETIC,
  DTR_SHAPED_RUN_MISSING_GLYPH = DTR_RESOLVED_FONT_MISSING_GLYPH,
  DTR_SHAPED_RUN_MONOSPACED = DTR_RESOLVED_FONT_MONOSPACED,
  DTR_SHAPED_RUN_RIGHT_TO_LEFT = 1u << 5,
  DTR_SHAPED_RUN_KNOWN_MASK =
      DTR_RESOLVED_FONT_KNOWN_MASK | DTR_SHAPED_RUN_RIGHT_TO_LEFT,
};

enum {
  DTR_SHAPED_GLYPH_MISSING = 1u << 0,
  DTR_SHAPED_GLYPH_KNOWN_MASK = DTR_SHAPED_GLYPH_MISSING,
};

// Version-one packed shaping output. All integer and IEEE-754 fields use the
// native little-endian representation of supported macOS targets. Sections are
// contiguous in header, run, face, glyph order with no caller-owned pointer.
typedef struct DtrShapeHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t catalog_generation;
  uint32_t requested_style;
  uint32_t feature_flags;
  uint32_t utf8_length;
  uint32_t utf16_length;
  uint32_t unicode_scalar_count;
  uint32_t run_count;
  uint32_t face_count;
  uint32_t glyph_count;
  uint32_t runs_offset;
  uint32_t faces_offset;
  uint32_t glyphs_offset;
  uint32_t reserved[3];
} DtrShapeHeaderV1;

typedef struct DtrShapeRunV1 {
  uint32_t face_id;
  uint32_t flags;
  uint32_t first_glyph;
  uint32_t glyph_count;
  uint32_t utf16_start;
  uint32_t utf16_length;
  double typographic_width;
  uint32_t reserved[2];
} DtrShapeRunV1;

typedef struct DtrShapeFaceV1 {
  uint32_t face_id;
  uint32_t flags;
  uint32_t postscript_name_length;
  uint32_t reserved;
  uint8_t postscript_name[DTR_MAX_POSTSCRIPT_NAME_BYTES + 1u];
} DtrShapeFaceV1;

typedef struct DtrShapeGlyphV1 {
  uint32_t glyph_id;
  uint32_t face_id;
  uint32_t run_index;
  uint32_t flags;
  uint32_t utf16_start;
  uint32_t utf16_length;
  double position_x;
  double position_y;
  double advance;
} DtrShapeGlyphV1;

typedef struct DtrRasterRequestV1 {
  uint32_t face_id;
  uint32_t glyph_id;
} DtrRasterRequestV1;

enum {
  DTR_RASTER_FORMAT_ALPHA8 = 1,
  DTR_RASTER_FORMAT_RGBA8_STRAIGHT = 2,
};

enum {
  DTR_RASTER_GLYPH_COLOR = 1u << 0,
  DTR_RASTER_GLYPH_MISSING = 1u << 1,
  DTR_RASTER_GLYPH_KNOWN_MASK =
      DTR_RASTER_GLYPH_COLOR | DTR_RASTER_GLYPH_MISSING,
};

typedef struct DtrRasterHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t catalog_generation;
  uint32_t scale_16_16;
  uint32_t glyph_count;
  uint32_t records_offset;
  uint32_t pixels_offset;
  uint32_t pixel_bytes;
  uint32_t reserved[5];
} DtrRasterHeaderV1;

// origin_x is the left device-pixel bearing from the glyph position.
// origin_y is the top device-pixel bearing above the CoreText baseline.
// Pixel rows are tightly packed top-to-bottom.
typedef struct DtrRasterGlyphV1 {
  uint32_t face_id;
  uint32_t glyph_id;
  uint32_t format;
  uint32_t flags;
  int32_t origin_x;
  int32_t origin_y;
  uint32_t width;
  uint32_t height;
  uint32_t row_stride;
  uint32_t pixels_offset;
  uint32_t pixel_length;
  uint32_t reserved;
} DtrRasterGlyphV1;

enum {
  DTR_METAL_ATLAS_ALPHA8 = 1,
  DTR_METAL_ATLAS_RGBA8_STRAIGHT = 2,
};

enum {
  DTR_METAL_INSTANCE_CELL_BACKGROUND = 1,
  DTR_METAL_INSTANCE_SELECTION = 2,
  DTR_METAL_INSTANCE_ALPHA_GLYPH = 3,
  DTR_METAL_INSTANCE_COLOR_GLYPH = 4,
  DTR_METAL_INSTANCE_DECORATION = 5,
  DTR_METAL_INSTANCE_CURSOR = 6,
};

typedef struct DtrMetalRendererConfigV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t maximum_viewport_width;
  uint32_t maximum_viewport_height;
  uint32_t maximum_instances;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t maximum_alpha_pages;
  uint32_t maximum_color_pages;
  uint32_t reserved[3];
} DtrMetalRendererConfigV1;

typedef struct DtrMetalRendererSummaryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t handle;
  uint64_t generation;
  uint32_t maximum_viewport_width;
  uint32_t maximum_viewport_height;
  uint32_t maximum_instances;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t maximum_alpha_pages;
  uint32_t maximum_color_pages;
  uint32_t failure_kind;
  uint32_t reserved[2];
} DtrMetalRendererSummaryV1;

typedef struct DtrMetalAtlasUploadV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t renderer_generation;
  uint64_t atlas_generation;
  uint64_t page_generation;
  uint32_t format;
  uint32_t page_index;
  uint32_t x;
  uint32_t y;
  uint32_t width;
  uint32_t height;
  uint32_t row_stride;
  uint32_t byte_length;
  uint32_t reserved[4];
} DtrMetalAtlasUploadV1;

typedef struct DtrMetalAtlasResetV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t renderer_generation;
  uint64_t atlas_generation;
  uint32_t reserved[2];
} DtrMetalAtlasResetV1;

// Version-one packed frame. Coordinates and sizes are device pixels in a
// flipped top-left viewport. Instances are contiguous and ordered by terminal
// layer. Colors are straight-alpha 0xRRGGBBAA.
typedef struct DtrMetalFrameHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t renderer_generation;
  uint64_t frame_generation;
  uint64_t atlas_generation;
  uint32_t viewport_width;
  uint32_t viewport_height;
  uint32_t scale_16_16;
  uint32_t background_rgba;
  uint32_t instance_count;
  uint32_t instance_stride;
  uint32_t instances_offset;
  uint32_t reserved[3];
} DtrMetalFrameHeaderV1;

typedef struct DtrMetalInstanceV1 {
  int32_t x;
  int32_t y;
  uint32_t width;
  uint32_t height;
  uint32_t atlas_x;
  uint32_t atlas_y;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t color_rgba;
  uint32_t kind;
  uint32_t page_index;
  uint32_t page_generation;
} DtrMetalInstanceV1;

// Opaque provider operation payload used to associate one renderer generation
// with the TerminalMetalView that receives the operation. The AppKit view
// handle and Objective-C object never enter this renderer ABI.
typedef struct DtrMetalViewBindingV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t reserved;
  uint64_t renderer_handle;
  uint64_t renderer_generation;
} DtrMetalViewBindingV1;

typedef struct DtrTextInputClientV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t reserved;
  uint64_t client_id;
} DtrTextInputClientV1;

typedef struct DtrTextInputGeometryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t reserved;
  uint64_t client_id;
  uint64_t generation;
  double x;
  double y;
  double width;
  double height;
} DtrTextInputGeometryV1;

// Test-gated staged operation that drives the registered product view through
// its real NSTextInputClient methods. No text or Objective-C object crosses
// this ABI.
typedef struct DtrTextInputAcceptanceV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t stage;
  uint64_t client_id;
  uint64_t reserved;
} DtrTextInputAcceptanceV1;

// Complete copied accessibility document for one physical terminal viewport.
// Text is UTF-8 while every range and column boundary is measured in UTF-16
// code units. Cell metrics and content origin are finite logical View points.
// Sections are canonical and contiguous in header, line, row-relative
// column-boundary, and text order.
typedef struct DtrAccessibilitySnapshotHeaderV2 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t flags;
  uint64_t generation;
  uint32_t rows;
  uint32_t columns;
  uint32_t utf8_length;
  uint32_t utf16_length;
  uint32_t line_count;
  uint32_t column_boundary_count;
  uint32_t selection_location;
  uint32_t selection_length;
  uint32_t cursor_location;
  uint32_t cursor_row;
  uint32_t cursor_column;
  uint32_t reserved0;
  double cell_width;
  double cell_height;
  double content_origin_x;
  double content_origin_y;
  uint32_t lines_offset;
  uint32_t column_boundaries_offset;
  uint32_t text_offset;
  uint32_t total_size;
  uint32_t reserved[4];
} DtrAccessibilitySnapshotHeaderV2;

typedef struct DtrAccessibilityLineV1 {
  uint32_t row;
  uint32_t utf16_start;
  uint32_t utf16_length;
  uint32_t first_column_boundary;
  uint32_t column_boundary_count;
} DtrAccessibilityLineV1;

typedef struct DtrAccessibilityAcceptanceV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t operation;
  uint32_t reserved;
  uint64_t generation;
} DtrAccessibilityAcceptanceV1;

// Immutable copied event. Range locations use UTF-16 code units and UINT32_MAX
// for NSNotFound. Text regions are validated UTF-8 within this same packet.
typedef struct DtrTextInputEventHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t client_id;
  uint64_t event_generation;
  uint64_t monotonic_nanos;
  uint32_t kind;
  uint32_t flags;
  uint32_t key_code;
  uint32_t modifiers;
  uint32_t text_offset;
  uint32_t text_length;
  uint32_t unmodified_text_offset;
  uint32_t unmodified_text_length;
  uint32_t selection_location;
  uint32_t selection_length;
  uint32_t replacement_location;
  uint32_t replacement_length;
  uint32_t reserved[2];
} DtrTextInputEventHeaderV1;

typedef void (*DtrTextInputNotifyV1)(uint64_t client_id);

typedef struct DtrMetalSubmissionV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t renderer_generation;
  uint64_t submission_token;
  uint64_t frame_generation;
  uint32_t reserved[2];
} DtrMetalSubmissionV1;

// A short locked snapshot for completion ownership. Every accepted token at or
// below retired_through_token is no longer READY or IN_FLIGHT and its Dart
// atlas pins may be released.
typedef struct DtrMetalRendererStateV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t renderer_generation;
  uint64_t last_accepted_frame_generation;
  uint64_t last_submission_token;
  uint64_t retired_through_token;
  uint64_t last_presented_frame_generation;
  uint64_t accepted_submission_count;
  uint64_t completed_submission_count;
  uint64_t stale_ready_drop_count;
  uint64_t backpressure_count;
  uint32_t ready_slot_count;
  uint32_t in_flight_slot_count;
  uint32_t flags;
  uint32_t failure_kind;
  uint64_t failure_generation;
  uint64_t last_failed_frame_generation;
  uint64_t drawable_unavailable_count;
  uint64_t command_failure_count;
  uint64_t gpu_timing_sample_count;
  uint64_t gpu_total_time_ns;
  uint64_t gpu_max_time_ns;
  uint64_t accepted_atlas_upload_count;
  uint64_t accepted_atlas_upload_bytes;
  uint32_t reserved[2];
} DtrMetalRendererStateV1;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtr_abi_version(void);

__attribute__((visibility("default"))) int32_t
dtr_initialize(const da_native_extension_services_v1* services);

__attribute__((visibility("default"))) int32_t dtr_debug_live_view_count(void);

// Installs the one process-lifetime scalar notification used by the Dart
// listener. Native owns all event bytes until dtr_text_input_take_event copies
// and removes one packet. The callback must return immediately.
__attribute__((visibility("default"))) int32_t
dtr_text_input_set_notify_callback(DtrTextInputNotifyV1 callback);

// Copies the oldest queued packet for client_id. A null output with zero
// capacity is a non-consuming size query. BUFFER_TOO_SMALL never removes data.
__attribute__((visibility("default"))) int32_t dtr_text_input_take_event(
    uint64_t client_id, uint8_t* output, uint32_t output_capacity,
    uint32_t* output_required);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_text_input_client_count(void);

// Creates an immutable native CoreText catalog. family_utf8 may be null only
// when family_length is zero, which selects the system monospaced font.
// The caller initializes output struct_size/version. On success it owns exactly
// one handle and must call dtr_font_catalog_release once.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_create(
    const uint8_t* family_utf8, uint32_t family_length, double point_size,
    uint32_t policy_flags, DtrFontCatalogSummaryV1* output);

__attribute__((visibility("default"))) int32_t
dtr_font_catalog_release(uint64_t handle);

// NativeFinalizer-compatible fallback. The pointer value is the opaque handle;
// it is never dereferenced. Explicit release remains the deterministic path.
__attribute__((visibility("default"))) void
dtr_font_catalog_release_finalizer(void* handle);

// Resolves the effective first CoreText run for one complete UTF-8 text unit.
// No input pointer is retained. The caller initializes output
// struct_size/version and receives a fixed-size copied result.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_resolve(
    uint64_t handle, uint32_t style, const uint8_t* text_utf8,
    uint32_t text_length, DtrResolvedFontV1* output);

// Shapes one complete UTF-8 run. A null output with zero capacity is a size
// query and returns DTR_STATUS_BUFFER_TOO_SMALL with output_required set. If a
// supplied buffer is too small, no partial output is written. No pointer is
// retained after return.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_shape(
    uint64_t handle, uint32_t style, uint32_t feature_flags,
    const uint8_t* text_utf8, uint32_t text_length, uint8_t* output,
    uint32_t output_capacity, uint32_t* output_required);

// Rasterizes a unique glyph set in request order at an exact unsigned 16.16
// pixels-per-point scale. Null output with zero capacity is a size query. The
// call retains no request/output pointer and publishes no partial output.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_rasterize(
    uint64_t handle, uint32_t scale_16_16,
    const DtrRasterRequestV1* requests, uint32_t request_count,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_font_catalog_count(void);

// Creates a generation-owned Metal resource set. Pipeline/library and bounded
// texture arrays are initialized before success is published. The caller owns
// exactly one returned handle and must release it once.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_create(
    const DtrMetalRendererConfigV1* config,
    DtrMetalRendererSummaryV1* output);

__attribute__((visibility("default"))) int32_t
dtr_metal_renderer_release(uint64_t handle);

// NativeFinalizer-compatible fallback. The pointer value is the opaque handle;
// it is never dereferenced. Explicit release remains the deterministic path.
__attribute__((visibility("default"))) void
dtr_metal_renderer_release_finalizer(void* handle);

// Atomically advances the complete atlas snapshot generation and clears every
// texture slice/page generation. This supports an empty scale/font rebuild
// without inventing a glyph upload. Active frame slots return backpressure.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_reset_atlas(
    uint64_t handle, const DtrMetalAtlasResetV1* reset);

// Copies one tightly packed dirty rectangle into a bounded atlas texture
// slice. No pointer is retained. A higher atlas generation advances the
// complete snapshot identity while preserving unchanged slices; a higher page
// generation clears that reused slice before the new definition is published.
// Any upload is backpressured while a READY/IN_FLIGHT frame owns the texture.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_upload_atlas(
    uint64_t handle, const DtrMetalAtlasUploadV1* upload,
    const uint8_t* pixels);

// Validates and synchronously copies one packed frame into one of three fixed
// native slots. Returns immediately after READY publication; drawable access,
// command encoding, presentation, and GPU completion occur in the native view
// callback. On backpressure or rejection no caller pointer or partial frame is
// retained. The caller initializes output struct_size/version.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_submit(
    uint64_t handle, const uint8_t* frame, uint32_t frame_length,
    DtrMetalSubmissionV1* output);

__attribute__((visibility("default"))) int32_t dtr_metal_renderer_state(
    uint64_t handle, DtrMetalRendererStateV1* output);

// Requests another on-demand draw for retained READY work. This does not
// allocate a frame or retry automatically while a drawable is unavailable.
__attribute__((visibility("default"))) int32_t
dtr_metal_renderer_request_draw(uint64_t handle);

// Synchronous offscreen correctness/readback path. A null output with zero
// capacity is a size query. Production rendering uses submit above; this call
// retains no input/output pointer and never publishes partial output.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_render_rgba(
    uint64_t handle, const uint8_t* frame, uint32_t frame_length,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_metal_renderer_count(void);

// Installs one deterministic fault for the native test suite. A second fault
// cannot be queued while one is pending.
__attribute__((visibility("default"))) int32_t
dtr_debug_metal_fail_next(uint32_t failure);

#if defined(__cplusplus)
}
#endif

#endif  // DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
