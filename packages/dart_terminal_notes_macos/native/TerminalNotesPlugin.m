#import "TerminalNotesPlugin.h"

#include <stdbool.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#import <Foundation/Foundation.h>

static const uint8_t kDtnProjectionFlagPresentationEligible = 1u << 0;
static const uint8_t kDtnProjectionKnownFlags = 0x7fu;
static const uint32_t kDtnCardFlagDue = 1u << 0;

typedef struct DtnParsedProjection {
  uint64_t pane_id;
  uint64_t surface_generation;
  uint64_t projection_generation;
  uint64_t store_revision_low;
  uint64_t selected_token;
  uint32_t active_count;
  uint32_t due_count;
  uint32_t card_count;
  uint32_t visibility;
  uint32_t presentation_eligible;
  uint32_t feature_state;
  uint32_t surface_state;
  uint32_t section;
  uint32_t editor_mode;
  uint32_t message_key;
  uint32_t page_start;
  uint32_t total_count;
  uint32_t body_font_millipoints;
  uint32_t projection_flags;
} DtnParsedProjection;

struct DtnSurface {
  NSLock* lock;
  uint8_t* packet;
  size_t packet_length;
  DtnParsedProjection projection;
  uint64_t accepted_projection_count;
  uint64_t rejected_projection_count;
  bool initialized;
};

static atomic_uint_fast64_t g_live_surfaces = 0;

static uint16_t dtn_read_u16(const uint8_t* bytes) {
  return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8u);
}

static uint32_t dtn_read_u32(const uint8_t* bytes) {
  return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8u) |
         ((uint32_t)bytes[2] << 16u) | ((uint32_t)bytes[3] << 24u);
}

static uint64_t dtn_read_u64(const uint8_t* bytes) {
  return (uint64_t)dtn_read_u32(bytes) |
         ((uint64_t)dtn_read_u32(bytes + 4u) << 32u);
}

static bool dtn_unicode_whitespace(uint32_t scalar) {
  return (scalar >= 0x09u && scalar <= 0x0du) || scalar == 0x20u ||
         scalar == 0x85u || scalar == 0xa0u || scalar == 0x1680u ||
         (scalar >= 0x2000u && scalar <= 0x200au) || scalar == 0x2028u ||
         scalar == 0x2029u || scalar == 0x202fu || scalar == 0x205fu ||
         scalar == 0x3000u;
}

static bool dtn_valid_body_utf8(const uint8_t* bytes, size_t length) {
  size_t index = 0;
  uint32_t line_count = 1u;
  bool has_non_whitespace = false;
  while (index < length) {
    const uint8_t first = bytes[index++];
    uint32_t scalar = 0;
    size_t continuation = 0;
    uint32_t minimum = 0;
    if (first <= 0x7fu) {
      scalar = first;
    } else if (first >= 0xc2u && first <= 0xdfu) {
      scalar = first & 0x1fu;
      continuation = 1;
      minimum = 0x80u;
    } else if (first >= 0xe0u && first <= 0xefu) {
      scalar = first & 0x0fu;
      continuation = 2;
      minimum = 0x800u;
    } else if (first >= 0xf0u && first <= 0xf4u) {
      scalar = first & 0x07u;
      continuation = 3;
      minimum = 0x10000u;
    } else {
      return false;
    }
    if (continuation > length - index) return false;
    for (size_t offset = 0; offset < continuation; ++offset) {
      const uint8_t next = bytes[index++];
      if ((next & 0xc0u) != 0x80u) return false;
      scalar = (scalar << 6u) | (next & 0x3fu);
    }
    if (scalar < minimum || scalar > 0x10ffffu ||
        (scalar >= 0xd800u && scalar <= 0xdfffu)) {
      return false;
    }
    if (scalar == 0x0au) ++line_count;
    const bool spacing_control = scalar == 0x09u || scalar == 0x0au;
    const bool forbidden_control =
        (scalar <= 0x1fu || (scalar >= 0x7fu && scalar <= 0x9fu)) &&
        !spacing_control;
    const bool forbidden_bidi =
        scalar == 0x200eu || scalar == 0x200fu ||
        (scalar >= 0x202au && scalar <= 0x202eu) ||
        (scalar >= 0x2066u && scalar <= 0x2069u);
    if (forbidden_control || forbidden_bidi || line_count > 64u) return false;
    if (!dtn_unicode_whitespace(scalar)) has_non_whitespace = true;
  }
  return has_non_whitespace;
}

static bool dtn_trigger_matches(uint8_t kind, uint8_t phase) {
  if ((kind == 0u) != (phase == 0u)) return false;
  if (kind == 0u) return true;
  if (kind == 1u) {
    return phase == 1u || phase == 2u || phase == 7u || phase == 8u;
  }
  if (kind == 2u) return phase >= 3u && phase <= 8u;
  return false;
}

static bool dtn_zero_bytes(const uint8_t* bytes, size_t length) {
  for (size_t index = 0; index < length; ++index) {
    if (bytes[index] != 0u) return false;
  }
  return true;
}

static int32_t dtn_parse_projection(const uint8_t* bytes, size_t length,
                                    DtnParsedProjection* output) {
  if (bytes == NULL || output == NULL || length < DTN_PROJECTION_HEADER_BYTES ||
      length > DTN_MAX_PACKET_BYTES) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  const uint16_t version = dtn_read_u16(bytes + 8u);
  if (version != DTN_PROJECTION_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  const uint32_t total_bytes = dtn_read_u32(bytes + 4u);
  const uint16_t header_bytes = dtn_read_u16(bytes + 10u);
  const uint16_t card_record_bytes = dtn_read_u16(bytes + 12u);
  const uint8_t visibility = bytes[14u];
  const uint8_t flags = bytes[15u];
  const uint32_t active_count = dtn_read_u32(bytes + 56u);
  const uint32_t due_count = dtn_read_u32(bytes + 60u);
  const uint32_t card_count = dtn_read_u32(bytes + 64u);
  const uint32_t body_bytes = dtn_read_u32(bytes + 68u);
  const uint32_t cards_offset = dtn_read_u32(bytes + 72u);
  const uint32_t body_offset = dtn_read_u32(bytes + 76u);
  const uint8_t feature_state = bytes[80u];
  const uint8_t surface_state = bytes[81u];
  const uint8_t section = bytes[82u];
  const uint8_t editor_mode = bytes[83u];
  const uint16_t message_key = dtn_read_u16(bytes + 84u);
  const uint32_t page_start = dtn_read_u32(bytes + 88u);
  const uint32_t page_length = dtn_read_u32(bytes + 92u);
  const uint32_t total_count = dtn_read_u32(bytes + 96u);
  const uint32_t body_font_millipoints = dtn_read_u32(bytes + 104u);
  if (dtn_read_u32(bytes) != DTN_PROJECTION_MAGIC ||
      total_bytes != length || header_bytes != DTN_PROJECTION_HEADER_BYTES ||
      card_record_bytes != DTN_CARD_RECORD_BYTES || visibility > 1u ||
      (flags & ~kDtnProjectionKnownFlags) != 0u ||
      active_count > DTN_MAX_CONTEXT_NOTES || due_count > active_count ||
      card_count > DTN_MAX_CARDS || body_bytes > DTN_MAX_BODY_BYTES ||
      cards_offset != DTN_PROJECTION_HEADER_BYTES ||
      body_offset != DTN_PROJECTION_HEADER_BYTES +
                         card_count * DTN_CARD_RECORD_BYTES ||
      (size_t)body_offset + body_bytes != length || feature_state > 6u ||
      surface_state > 4u || section > 1u || editor_mode > 2u ||
      message_key > 5u || dtn_read_u16(bytes + 86u) != 0u ||
      page_length != card_count ||
      total_count > (section == DTN_SECTION_CURRENT ? DTN_MAX_CONTEXT_NOTES
                                                    : 2048u) ||
      page_start > total_count || page_length > total_count - page_start ||
      dtn_read_u32(bytes + 100u) != 0u ||
      body_font_millipoints < 12000u || body_font_millipoints > 24000u ||
      !dtn_zero_bytes(bytes + 108u, 20u)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  const uint64_t pane_id = dtn_read_u64(bytes + 16u);
  const uint64_t surface_generation = dtn_read_u64(bytes + 24u);
  const uint64_t projection_generation = dtn_read_u64(bytes + 32u);
  if (pane_id == 0u || pane_id > INT64_MAX || surface_generation == 0u ||
      surface_generation > INT64_MAX || projection_generation == 0u ||
      projection_generation > INT64_MAX) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  const bool presentation_eligible =
      (flags & kDtnProjectionFlagPresentationEligible) != 0u;
  const uint64_t selected_token = dtn_read_u64(bytes + 48u);
  if (visibility == DTN_VISIBILITY_COLLAPSED &&
      (card_count != 0u || body_bytes != 0u || selected_token != 0u)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (feature_state != DTN_FEATURE_AVAILABLE && card_count != 0u) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }

  uint32_t expected_body_offset = 0;
  bool selection_found = selected_token == 0u;
  for (uint32_t index = 0; index < card_count; ++index) {
    const uint8_t* record =
        bytes + DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    const uint64_t token = dtn_read_u64(record);
    const uint32_t relative_body_offset = dtn_read_u32(record + 8u);
    const uint32_t body_length = dtn_read_u32(record + 12u);
    const uint8_t color = record[20u];
    const uint8_t status = record[21u];
    const uint8_t trigger_kind = record[22u];
    const uint8_t trigger_phase = record[23u];
    const uint32_t card_flags = dtn_read_u32(record + 24u);
    const uint32_t reserved = dtn_read_u32(record + 28u);
    if (token == 0u || token > INT64_MAX ||
        relative_body_offset != expected_body_offset || body_length == 0u ||
        body_length > DTN_MAX_CARD_BODY_BYTES ||
        relative_body_offset > body_bytes ||
        body_length > body_bytes - relative_body_offset || color > 5u ||
        status > 1u || trigger_kind > 2u || trigger_phase > 8u ||
        !dtn_trigger_matches(trigger_kind, trigger_phase) ||
        (card_flags & ~kDtnCardFlagDue) != 0u || reserved != 0u ||
        ((card_flags & kDtnCardFlagDue) != 0u) != (trigger_phase == 7u)) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
    for (uint32_t previous = 0; previous < index; ++previous) {
      const uint8_t* previous_record =
          bytes + DTN_PROJECTION_HEADER_BYTES +
          previous * DTN_CARD_RECORD_BYTES;
      if (dtn_read_u64(previous_record) == token) {
        return DTN_STATUS_INVALID_ARGUMENT;
      }
    }
    if (token == selected_token) selection_found = true;
    if (!dtn_valid_body_utf8(bytes + body_offset + relative_body_offset,
                             body_length)) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
    expected_body_offset += body_length;
  }
  if (expected_body_offset != body_bytes) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (!selection_found) return DTN_STATUS_INVALID_ARGUMENT;
  output->pane_id = pane_id;
  output->surface_generation = surface_generation;
  output->projection_generation = projection_generation;
  output->store_revision_low = dtn_read_u64(bytes + 40u);
  output->selected_token = selected_token;
  output->active_count = active_count;
  output->due_count = due_count;
  output->card_count = card_count;
  output->visibility = visibility;
  output->presentation_eligible = presentation_eligible ? 1u : 0u;
  output->feature_state = feature_state;
  output->surface_state = surface_state;
  output->section = section;
  output->editor_mode = editor_mode;
  output->message_key = message_key;
  output->page_start = page_start;
  output->total_count = total_count;
  output->body_font_millipoints = body_font_millipoints;
  output->projection_flags = flags;
  return DTN_STATUS_OK;
}

static int dtn_compare_revision(const DtnParsedProjection* left,
                                const DtnParsedProjection* right) {
  if (left->store_revision_low == right->store_revision_low) return 0;
  return left->store_revision_low < right->store_revision_low ? -1 : 1;
}

uint32_t dtn_abi_version(void) { return DTN_ABI_VERSION; }

DtnSurface* dtn_surface_create(void) {
  DtnSurface* surface = calloc(1u, sizeof(DtnSurface));
  if (surface == NULL) return NULL;
  surface->lock = [[NSLock alloc] init];
  atomic_fetch_add_explicit(&g_live_surfaces, 1u, memory_order_relaxed);
  return surface;
}

int32_t dtn_surface_apply_projection(DtnSurface* surface, const uint8_t* bytes,
                                     size_t length) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  DtnParsedProjection parsed = {0};
  const int32_t status = dtn_parse_projection(bytes, length, &parsed);
  [surface->lock lock];
  if (status != DTN_STATUS_OK) {
    ++surface->rejected_projection_count;
    [surface->lock unlock];
    return status;
  }
  if (surface->initialized &&
      (parsed.pane_id != surface->projection.pane_id ||
       parsed.surface_generation != surface->projection.surface_generation ||
       parsed.projection_generation <=
           surface->projection.projection_generation ||
       dtn_compare_revision(&parsed, &surface->projection) < 0)) {
    ++surface->rejected_projection_count;
    [surface->lock unlock];
    return DTN_STATUS_STALE;
  }
  uint8_t* owned_packet = malloc(length);
  if (owned_packet == NULL) {
    ++surface->rejected_projection_count;
    [surface->lock unlock];
    return DTN_STATUS_INTERNAL;
  }
  memcpy(owned_packet, bytes, length);
  uint8_t* previous_packet = surface->packet;
  surface->packet = owned_packet;
  surface->packet_length = length;
  surface->projection = parsed;
  surface->initialized = true;
  ++surface->accepted_projection_count;
  [surface->lock unlock];
  free(previous_packet);
  return DTN_STATUS_OK;
}

int32_t dtn_surface_snapshot(DtnSurface* surface,
                             DtnSurfaceSnapshotV1* snapshot) {
  if (surface == NULL || snapshot == NULL ||
      snapshot->struct_size != sizeof(DtnSurfaceSnapshotV1)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (snapshot->version != DTN_SNAPSHOT_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  [surface->lock lock];
  const DtnParsedProjection projection = surface->projection;
  const size_t packet_length = surface->packet_length;
  const uint64_t accepted = surface->accepted_projection_count;
  const uint64_t rejected = surface->rejected_projection_count;
  const bool initialized = surface->initialized;
  [surface->lock unlock];

  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->struct_size = sizeof(*snapshot);
  snapshot->version = DTN_SNAPSHOT_VERSION;
  snapshot->pane_id = projection.pane_id;
  snapshot->surface_generation = projection.surface_generation;
  snapshot->projection_generation = projection.projection_generation;
  snapshot->store_revision_low = projection.store_revision_low;
  snapshot->store_revision_high = 0u;
  snapshot->accepted_projection_count = accepted;
  snapshot->rejected_projection_count = rejected;
  snapshot->active_count = projection.active_count;
  snapshot->due_count = projection.due_count;
  snapshot->projected_card_count = projection.card_count;
  snapshot->materialized_card_count =
      projection.card_count < DTN_MAX_MATERIALIZED_CARDS
          ? projection.card_count
          : DTN_MAX_MATERIALIZED_CARDS;
  snapshot->packet_bytes = (uint32_t)packet_length;
  snapshot->visibility = projection.visibility;
  snapshot->presentation_eligible = projection.presentation_eligible;
  snapshot->initialized = initialized ? 1u : 0u;
  snapshot->projection_flags = projection.projection_flags;
  snapshot->feature_state = projection.feature_state;
  snapshot->surface_state = projection.surface_state;
  snapshot->section = projection.section;
  snapshot->editor_mode = projection.editor_mode;
  snapshot->message_key = projection.message_key;
  snapshot->page_start = projection.page_start;
  snapshot->total_count = projection.total_count;
  snapshot->body_font_millipoints = projection.body_font_millipoints;
  return DTN_STATUS_OK;
}

void dtn_surface_destroy(DtnSurface* surface) {
  if (surface == NULL) return;
  [surface->lock lock];
  uint8_t* packet = surface->packet;
  surface->packet = NULL;
  surface->packet_length = 0;
  [surface->lock unlock];
  free(packet);
  surface->lock = nil;
  free(surface);
  atomic_fetch_sub_explicit(&g_live_surfaces, 1u, memory_order_relaxed);
}

uint64_t dtn_debug_live_surfaces(void) {
  return atomic_load_explicit(&g_live_surfaces, memory_order_relaxed);
}
