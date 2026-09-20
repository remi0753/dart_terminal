#include "TerminalNotesPlugin.h"

#import <AppKit/AppKit.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

void write_u16(std::vector<uint8_t>& bytes, size_t offset, uint16_t value) {
  bytes[offset] = static_cast<uint8_t>(value);
  bytes[offset + 1u] = static_cast<uint8_t>(value >> 8u);
}

void write_u32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
  for (size_t byte = 0; byte < 4u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

void write_u64(std::vector<uint8_t>& bytes, size_t offset, uint64_t value) {
  for (size_t byte = 0; byte < 8u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

std::vector<uint8_t> packet(uint64_t projection_generation,
                            uint64_t store_revision,
                            const std::vector<std::string>& bodies = {"hello"},
                            uint8_t flags = 1u) {
  size_t aggregate_body_bytes = 0;
  for (const std::string& body : bodies) aggregate_body_bytes += body.size();
  const size_t body_offset =
      DTN_PROJECTION_HEADER_BYTES + bodies.size() * DTN_CARD_RECORD_BYTES;
  std::vector<uint8_t> bytes(body_offset + aggregate_body_bytes, 0u);
  write_u32(bytes, 0u, DTN_PROJECTION_MAGIC);
  write_u32(bytes, 4u, static_cast<uint32_t>(bytes.size()));
  write_u16(bytes, 8u, DTN_PROJECTION_VERSION);
  write_u16(bytes, 10u, DTN_PROJECTION_HEADER_BYTES);
  write_u16(bytes, 12u, DTN_CARD_RECORD_BYTES);
  bytes[14u] = DTN_VISIBILITY_EXPANDED;
  bytes[15u] = flags;
  write_u64(bytes, 16u, 11u);
  write_u64(bytes, 24u, 7u);
  write_u64(bytes, 32u, projection_generation);
  write_u64(bytes, 40u, store_revision);
  if (!bodies.empty()) write_u64(bytes, 48u, 1u);
  write_u32(bytes, 56u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 64u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 68u, static_cast<uint32_t>(aggregate_body_bytes));
  write_u32(bytes, 72u, DTN_PROJECTION_HEADER_BYTES);
  write_u32(bytes, 76u, static_cast<uint32_t>(body_offset));
  bytes[80u] = DTN_FEATURE_AVAILABLE;
  bytes[81u] = DTN_SURFACE_READY;
  bytes[82u] = DTN_SECTION_CURRENT;
  bytes[83u] = DTN_EDITOR_INACTIVE;
  write_u32(bytes, 92u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 96u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 104u, 15000u);
  uint32_t running_body_offset = 0;
  for (size_t index = 0; index < bodies.size(); ++index) {
    const size_t record =
        DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    write_u64(bytes, record, static_cast<uint64_t>(index + 1u));
    write_u32(bytes, record + 8u, running_body_offset);
    write_u32(bytes, record + 12u,
              static_cast<uint32_t>(bodies[index].size()));
    bytes[record + 20u] = static_cast<uint8_t>(index % 6u);
    std::memcpy(bytes.data() + body_offset + running_body_offset,
                bodies[index].data(), bodies[index].size());
    running_body_offset += static_cast<uint32_t>(bodies[index].size());
  }
  return bytes;
}

bool expect(bool condition, const char* message) {
  if (!condition) std::fprintf(stderr, "FAIL: %s\n", message);
  return condition;
}

bool bitmap_contains(NSView* view, uint32_t rgba) {
  [view layoutSubtreeIfNeeded];
  [view setNeedsDisplay:YES];
  [view displayIfNeeded];
  NSBitmapImageRep* bitmap =
      [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  if (bitmap == nil) return false;
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  const double expected_red = ((rgba >> 24u) & 0xffu) / 255.0;
  const double expected_green = ((rgba >> 16u) & 0xffu) / 255.0;
  const double expected_blue = ((rgba >> 8u) & 0xffu) / 255.0;
  NSUInteger matches = 0;
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y += 2) {
    for (NSInteger x = 0; x < bitmap.pixelsWide; x += 2) {
      NSColor* color = [[bitmap colorAtX:x y:y]
          colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      if (color != nil && std::abs(color.redComponent - expected_red) < 0.01 &&
          std::abs(color.greenComponent - expected_green) < 0.01 &&
          std::abs(color.blueComponent - expected_blue) < 0.01) {
        if (++matches >= 16u) return true;
      }
    }
  }
  return false;
}

}  // namespace

int main() {
  @autoreleasepool {
  bool ok = true;
  ok &= expect(dtn_abi_version() == 1u, "ABI version");
  ok &= expect(dtn_debug_live_surfaces() == 0u, "initial owner count");
  DtnSurface* surface = dtn_surface_create();
  ok &= expect(surface != nullptr, "surface creation");
  ok &= expect(dtn_debug_live_surfaces() == 1u, "live owner count");

  DtnSurfaceSnapshotV1 snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.initialized == 0u,
               "empty snapshot");

  std::vector<uint8_t> valid = packet(1u, 4u);
  ok &= expect(dtn_surface_apply_projection(surface, valid.data(), valid.size()) ==
                   DTN_STATUS_OK,
               "valid projection");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.projection_generation == 1u &&
                   snapshot.projected_card_count == 1u &&
                   snapshot.accepted_projection_count == 1u &&
                   snapshot.feature_state == DTN_FEATURE_AVAILABLE &&
                   snapshot.surface_state == DTN_SURFACE_READY,
               "accepted snapshot");

  std::vector<uint8_t> stale = packet(1u, 4u);
  ok &= expect(dtn_surface_apply_projection(surface, stale.data(), stale.size()) ==
                   DTN_STATUS_STALE,
               "stale generation rejection");
  std::vector<uint8_t> older_store = packet(2u, 3u);
  ok &= expect(dtn_surface_apply_projection(surface, older_store.data(),
                                            older_store.size()) ==
                   DTN_STATUS_STALE,
               "stale store revision rejection");
  std::vector<uint8_t> other_surface = packet(2u, 5u);
  write_u64(other_surface, 24u, 8u);
  ok &= expect(dtn_surface_apply_projection(surface, other_surface.data(),
                                            other_surface.size()) ==
                   DTN_STATUS_STALE,
               "cross-surface rejection");

  std::vector<uint8_t> unsupported = packet(2u, 5u);
  write_u16(unsupported, 8u, 2u);
  ok &= expect(dtn_surface_apply_projection(surface, unsupported.data(),
                                            unsupported.size()) ==
                   DTN_STATUS_UNSUPPORTED_VERSION,
               "version rejection");
  std::vector<uint8_t> unknown_flag = packet(2u, 5u);
  unknown_flag[15u] = 0x80u;
  ok &= expect(dtn_surface_apply_projection(surface, unknown_flag.data(),
                                            unknown_flag.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "unknown flag rejection");
  std::vector<uint8_t> collapsed_body = packet(2u, 5u);
  collapsed_body[14u] = DTN_VISIBILITY_COLLAPSED;
  ok &= expect(dtn_surface_apply_projection(surface, collapsed_body.data(),
                                            collapsed_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "collapsed body rejection");
  std::vector<uint8_t> duplicate = packet(2u, 5u, {"one", "two"});
  write_u64(duplicate, DTN_PROJECTION_HEADER_BYTES + DTN_CARD_RECORD_BYTES,
            1u);
  ok &= expect(dtn_surface_apply_projection(surface, duplicate.data(),
                                            duplicate.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "duplicate token rejection");
  std::vector<uint8_t> invalid_utf8 = packet(2u, 5u, {"x"});
  invalid_utf8.back() = 0xffu;
  ok &= expect(dtn_surface_apply_projection(surface, invalid_utf8.data(),
                                            invalid_utf8.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "invalid UTF-8 rejection");
  std::vector<uint8_t> oversized_body =
      packet(2u, 5u, {std::string(DTN_MAX_CARD_BODY_BYTES + 1u, 'x')});
  ok &= expect(dtn_surface_apply_projection(surface, oversized_body.data(),
                                            oversized_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "card body +1 rejection");
  std::vector<uint8_t> empty_body = packet(2u, 5u, {""});
  ok &= expect(dtn_surface_apply_projection(surface, empty_body.data(),
                                            empty_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "empty card body rejection");
  std::vector<uint8_t> control_body = packet(2u, 5u, {std::string("x\0y", 3)});
  ok &= expect(dtn_surface_apply_projection(surface, control_body.data(),
                                            control_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "control body rejection");

  const std::string maximum_body(DTN_MAX_CARD_BODY_BYTES, 'x');
  std::vector<std::string> maximum_bodies(DTN_MAX_CARDS, maximum_body);
  std::vector<uint8_t> maximum = packet(2u, 5u, maximum_bodies);
  ok &= expect(dtn_surface_apply_projection(surface, maximum.data(),
                                            maximum.size()) == DTN_STATUS_OK,
               "maximum packet acceptance");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.projection_generation == 2u &&
                   snapshot.projected_card_count == DTN_MAX_CARDS &&
                   snapshot.materialized_card_count ==
                       DTN_MAX_MATERIALIZED_CARDS &&
                   snapshot.rejected_projection_count == 11u,
               "atomic last-good state and materialization bound");

  DtnLayoutV1 normal_layout = {};
  normal_layout.struct_size = sizeof(normal_layout);
  normal_layout.version = DTN_LAYOUT_VERSION;
  normal_layout.pane_width = 640;
  normal_layout.pane_height = 480;
  normal_layout.backing_scale = 1;
  normal_layout.requested_rail_width = 320;
  ok &= expect(dtn_surface_update_layout(surface, &normal_layout) ==
                   DTN_STATUS_OK,
               "normal layout acceptance");
  DtnPresentationSnapshotV1 presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(
      dtn_surface_presentation_snapshot(surface, &presentation) ==
              DTN_STATUS_OK &&
          presentation.pane_width == 640 && presentation.pane_height == 480 &&
          presentation.backing_scale == 1 &&
          presentation.badge_hit_width == 44 &&
          presentation.badge_hit_height == 44 &&
          presentation.badge_visual_height == 28 &&
          presentation.rail_width == 320 && presentation.rail_y == 12 &&
          presentation.rail_height == 456 &&
          presentation.materialized_card_count == 32u &&
          presentation.accessibility_body_count == 32u &&
          presentation.first_surface_rgba == 0xf5f5f3ffu &&
          (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) != 0u &&
          (presentation.flags & DTN_PRESENTATION_OPAQUE_CARDS) != 0u &&
          (presentation.flags & DTN_PRESENTATION_CARD_SHADOWS) != 0u,
      "normal light presentation geometry");

  NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
  NSView* note_view =
      (__bridge NSView*)dtn_surface_native_view(surface);
  ok &= expect(note_view != nil &&
                   dtn_surface_attach_to_host(surface, (__bridge void*)host) ==
                       DTN_STATUS_OK &&
                   host.subviews.lastObject == note_view,
               "native child surface attachment and layer order");
  NSArray* expanded_children = [note_view accessibilityChildren];
  ok &= expect(expanded_children.count == 1u &&
                   [[[expanded_children firstObject] accessibilityRole]
                       isEqualToString:NSAccessibilityGroupRole] &&
                   [note_view hitTest:NSMakePoint(1, 1)] == nil &&
                   [note_view hitTest:NSMakePoint(presentation.rail_x + 4,
                                                 presentation.rail_y + 4)] != nil,
               "expanded accessibility and bounded hit region");
  ok &= expect(bitmap_contains(note_view, 0xf5f5f3ffu),
               "light card bitmap token");

  std::vector<uint8_t> narrow = packet(
      3u, 6u, {"neutral", "yellow", "blue", "green", "pink", "purple"});
  write_u32(narrow, 104u, 12000u);
  ok &= expect(dtn_surface_apply_projection(surface, narrow.data(),
                                            narrow.size()) == DTN_STATUS_OK,
               "12 point narrow projection");
  DtnLayoutV1 narrow_layout = normal_layout;
  narrow_layout.pane_width = 264;
  narrow_layout.pane_height = 300;
  narrow_layout.requested_rail_width = 240;
  ok &= expect(dtn_surface_update_layout(surface, &narrow_layout) ==
                   DTN_STATUS_OK,
               "minimum usable rail layout");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_presentation_snapshot(surface, &presentation) ==
                       DTN_STATUS_OK &&
                   presentation.rail_width == 240 &&
                   presentation.body_font_millipoints == 12000u &&
                   (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) != 0u,
               "narrow 12 point presentation");

  std::vector<uint8_t> dark =
      packet(4u, 7u, {"neutral", "yellow", "blue", "green", "pink", "purple"},
             0x7fu);
  write_u32(dark, 104u, 24000u);
  ok &= expect(dtn_surface_apply_projection(surface, dark.data(), dark.size()) ==
                   DTN_STATUS_OK,
               "dark appearance projection");
  DtnLayoutV1 wide_layout = normal_layout;
  wide_layout.pane_width = 900;
  wide_layout.pane_height = 600;
  wide_layout.backing_scale = 2;
  wide_layout.requested_rail_width = 360;
  ok &= expect(dtn_surface_update_layout(surface, &wide_layout) ==
                   DTN_STATUS_OK,
               "wide 2x layout acceptance");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(
      dtn_surface_presentation_snapshot(surface, &presentation) ==
              DTN_STATUS_OK &&
          presentation.backing_scale == 2 && presentation.rail_width == 360 &&
          note_view.layer.contentsScale == 2 &&
          presentation.rail_y == 60 && presentation.rail_height == 528 &&
          presentation.materialized_card_count == 6u &&
          presentation.accessibility_body_count == 6u &&
          presentation.first_surface_rgba == 0x343432ffu &&
          presentation.first_accent_rgba == 0xb8b8b2ffu &&
          presentation.body_text_rgba == 0xf5f5f5ffu &&
          presentation.animation_milliseconds == 0u &&
          presentation.body_font_millipoints == 24000u &&
          (presentation.flags & DTN_PRESENTATION_DARK) != 0u &&
          (presentation.flags & DTN_PRESENTATION_INCREASE_CONTRAST) != 0u &&
          (presentation.flags & DTN_PRESENTATION_CARD_SHADOWS) == 0u &&
          (presentation.flags & DTN_PRESENTATION_REDUCED_MOTION) != 0u &&
          (presentation.flags &
           DTN_PRESENTATION_DIFFERENTIATE_WITHOUT_COLOR) != 0u &&
          (presentation.flags & DTN_PRESENTATION_SYSTEM_BADGE_VISIBLE) != 0u,
      "dark contrast motion and system-badge presentation");
  const uint32_t dark_surfaces[6] = {
      0x343432ffu, 0x4a401fffu, 0x24384effu,
      0x233e2bffu, 0x4a2938ffu, 0x382d4cffu,
  };
  for (uint32_t index = 0; index < 6u; ++index) {
    DtnCardPresentationSnapshotV1 card = {};
    card.struct_size = sizeof(card);
    card.version = DTN_CARD_PRESENTATION_SNAPSHOT_VERSION;
    ok &= expect(dtn_surface_card_presentation_snapshot(surface, index, &card) ==
                         DTN_STATUS_OK &&
                     card.color == index && card.surface_rgba == dark_surfaces[index] &&
                     card.non_color_cue == 1u && card.visible_line_limit == 8u &&
                     card.width > 0 && card.height >= 88,
                 "six-color card presentation");
  }
  ok &= expect(bitmap_contains(note_view, 0x343432ffu),
               "dark card bitmap token");

  DtnLayoutV1 small_layout = wide_layout;
  small_layout.pane_width = 263;
  small_layout.pane_height = 183;
  small_layout.requested_rail_width = 240;
  ok &= expect(dtn_surface_update_layout(surface, &small_layout) ==
                   DTN_STATUS_OK,
               "small layout acceptance");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_presentation_snapshot(surface, &presentation) ==
                       DTN_STATUS_OK &&
                   (presentation.flags & DTN_PRESENTATION_SMALL_PANE) != 0u &&
                   (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) == 0u &&
                   (presentation.flags & DTN_PRESENTATION_BADGE_VISIBLE) != 0u &&
                   presentation.accessibility_body_count == 0u,
               "small-pane badge fallback");

  std::vector<uint8_t> collapsed = packet(5u, 7u, {}, 0x02u);
  collapsed[14u] = DTN_VISIBILITY_COLLAPSED;
  write_u32(collapsed, 56u, 6u);
  write_u32(collapsed, 60u, 1u);
  ok &= expect(dtn_surface_apply_projection(surface, collapsed.data(),
                                            collapsed.size()) == DTN_STATUS_OK,
               "collapsed read-only projection");
  ok &= expect(dtn_surface_update_layout(surface, &normal_layout) ==
                   DTN_STATUS_OK,
               "restore normal layout");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  NSArray* collapsed_children = [note_view accessibilityChildren];
  ok &= expect(dtn_surface_presentation_snapshot(surface, &presentation) ==
                       DTN_STATUS_OK &&
                   (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) == 0u &&
                   presentation.accessibility_body_count == 0u &&
                   presentation.accessibility_node_count == 1u &&
                   collapsed_children.count == 1u &&
                   [[[collapsed_children firstObject] accessibilityRole]
                       isEqualToString:NSAccessibilityButtonRole],
               "collapsed accessibility exposes only Notes button");

  std::vector<uint8_t> background =
      packet(6u, 7u, {"hidden body"}, 0x00u);
  ok &= expect(dtn_surface_apply_projection(surface, background.data(),
                                            background.size()) == DTN_STATUS_OK,
               "background projection retention");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_presentation_snapshot(surface, &presentation) ==
                       DTN_STATUS_OK &&
                   (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) == 0u &&
                   presentation.accessibility_body_count == 0u,
               "background body excluded from accessibility");
  ok &= expect(dtn_surface_detach_from_host(surface) == DTN_STATUS_OK &&
                   note_view.superview == nil,
               "native child surface detach");

  dtn_surface_destroy(surface);
  ok &= expect(dtn_debug_live_surfaces() == 0u, "final owner count");
  if (!ok) return 1;
  std::puts("terminal Notes native codec tests passed");
  return 0;
  }
}
