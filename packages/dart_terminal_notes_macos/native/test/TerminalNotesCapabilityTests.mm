#include "TerminalNotesPlugin.h"

#import <AppKit/AppKit.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
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

NSView* find_view_named(NSView* root, NSString* class_name) {
  if ([NSStringFromClass(root.class) isEqualToString:class_name]) return root;
  for (NSView* child in root.subviews) {
    NSView* match = find_view_named(child, class_name);
    if (match != nil) return match;
  }
  return nil;
}

void find_views_named(NSView* root, NSString* class_name,
                      NSMutableArray<NSView*>* matches) {
  if ([NSStringFromClass(root.class) isEqualToString:class_name]) {
    [matches addObject:root];
  }
  for (NSView* child in root.subviews) {
    find_views_named(child, class_name, matches);
  }
}

bool layer_color_matches(NSView* view, uint32_t rgba) {
  NSColor* color = view.layer.backgroundColor == nullptr
      ? nil
      : [[NSColor colorWithCGColor:view.layer.backgroundColor]
            colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  if (color == nil) return false;
  return std::abs(color.redComponent - ((rgba >> 24u) & 0xffu) / 255.0) <
             0.01 &&
         std::abs(color.greenComponent - ((rgba >> 16u) & 0xffu) / 255.0) <
             0.01 &&
         std::abs(color.blueComponent - ((rgba >> 8u) & 0xffu) / 255.0) <
             0.01;
}

struct TerminalGeometrySentinel {
  uint32_t rows;
  uint32_t columns;
  uint32_t drawable_width;
  uint32_t drawable_height;
  uint32_t winsize_rows;
  uint32_t winsize_columns;
  uint32_t sigwinch_count;
  uint32_t alternate_screen;
  uint64_t input_sequence;
};

void mark_cards_due(std::vector<uint8_t>& bytes, uint32_t count) {
  write_u32(bytes, 60u, count);
  for (uint32_t index = 0u; index < count; ++index) {
    const size_t record =
        DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    bytes[record + 22u] = 1u;
    bytes[record + 23u] = 7u;
    write_u32(bytes, record + 24u, 1u);
  }
}

}  // namespace

int main() {
  @autoreleasepool {
  bool ok = true;
  const TerminalGeometrySentinel terminal_before = {
      24u, 80u, 640u, 480u, 24u, 80u, 0u, 1u, 41u};
  TerminalGeometrySentinel terminal = terminal_before;
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
  mark_cards_due(dark, 1u);
  write_u32(dark, 104u, 24000u);
  ok &= expect(dtn_surface_apply_projection(surface, dark.data(), dark.size()) ==
                   DTN_STATUS_OK,
               "dark appearance projection");
  NSView* first_card_before_reflow =
      find_view_named(note_view, @"DtnNoteCardView");
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
          presentation.rail_x + presentation.rail_width <=
              presentation.pane_width &&
          presentation.first_card_x >= presentation.rail_x &&
          presentation.first_card_x + presentation.first_card_width <=
              presentation.rail_x + presentation.rail_width &&
          note_view.layer.contentsScale == 2 &&
          presentation.rail_y == 60 && presentation.rail_height == 528 &&
          presentation.materialized_card_count == 6u &&
          presentation.accessibility_body_count == 6u &&
          presentation.animation_milliseconds == 0u &&
          presentation.body_font_millipoints == 24000u &&
          (presentation.flags & DTN_PRESENTATION_DARK) != 0u &&
          (presentation.flags & DTN_PRESENTATION_INCREASE_CONTRAST) != 0u &&
          (presentation.flags & DTN_PRESENTATION_CARD_SHADOWS) == 0u &&
          (presentation.flags & DTN_PRESENTATION_REDUCED_MOTION) != 0u &&
          (presentation.flags &
           DTN_PRESENTATION_DIFFERENTIATE_WITHOUT_COLOR) != 0u &&
          (presentation.flags & DTN_PRESENTATION_BADGE_VISIBLE) != 0u &&
          (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) != 0u &&
          (presentation.flags & DTN_PRESENTATION_SYSTEM_BADGE_VISIBLE) != 0u,
      "dark contrast motion and system-badge presentation");
  ok &= expect(first_card_before_reflow != nil &&
                   find_view_named(note_view, @"DtnNoteCardView") ==
                       first_card_before_reflow,
               "split reflow retains card identity");
  const uint32_t dark_surfaces[6] = {
      0x343432ffu, 0x4a401fffu, 0x24384effu,
      0x233e2bffu, 0x4a2938ffu, 0x382d4cffu,
  };
  NSMutableArray<NSView*>* palette_cards = [[NSMutableArray alloc] init];
  find_views_named(note_view, @"DtnNoteCardView", palette_cards);
  for (uint32_t index = 0; index < 6u; ++index) {
    ok &= expect(palette_cards.count == 6u &&
                     layer_color_matches(palette_cards[index],
                                         dark_surfaces[index]),
                 "six-color actual card presentation");
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
                   presentation.accessibility_body_count == 0u &&
                   presentation.visible_acknowledgement_eligible_generation ==
                       0u,
               "small-pane badge fallback");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.due_count == 1u &&
                   snapshot.projected_card_count == 6u,
               "small-pane fallback retains due data");

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
                   presentation.accessibility_body_count == 0u &&
                   presentation.visible_acknowledgement_eligible_generation ==
                       0u,
               "background body excluded from accessibility");

  const uint32_t badge_counts[] = {0u, 1u, 99u, 100u, 128u};
  for (uint32_t index = 0u; index < 5u; ++index) {
    std::vector<uint8_t> badge = packet(7u + index, 8u, {}, 0u);
    badge[14u] = DTN_VISIBILITY_COLLAPSED;
    write_u32(badge, 56u, badge_counts[index]);
    write_u32(badge, 96u, badge_counts[index]);
    ok &= expect(dtn_surface_apply_projection(surface, badge.data(),
                                              badge.size()) == DTN_STATUS_OK,
                 "badge count projection");
    presentation = {};
    presentation.struct_size = sizeof(presentation);
    presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
    const bool capped = badge_counts[index] > 99u;
    ok &= expect(
        dtn_surface_presentation_snapshot(surface, &presentation) ==
                DTN_STATUS_OK &&
            presentation.badge_display_count ==
                (capped ? 99u : badge_counts[index]) &&
            (((presentation.flags & DTN_PRESENTATION_BADGE_VISIBLE) != 0u) ==
             (badge_counts[index] != 0u)) &&
            (((presentation.flags & DTN_PRESENTATION_BADGE_COUNT_CAPPED) !=
              0u) == capped),
        "badge 0/1/99/100/128 display contract");
  }

  const uint64_t announcements_before =
      presentation.accessibility_announcement_count;
  std::vector<uint8_t> foreground_due =
      packet(12u, 9u, {"first", "second", "third"}, 0x03u);
  mark_cards_due(foreground_due, 3u);
  id responder_before = note_view.window.firstResponder;
  ok &= expect(dtn_surface_apply_projection(surface, foreground_due.data(),
                                            foreground_due.size()) ==
                   DTN_STATUS_OK,
               "foreground due projection");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  NSMutableArray<NSView*>* due_cards = [[NSMutableArray alloc] init];
  find_views_named(note_view, @"DtnNoteCardView", due_cards);
  ok &= expect(
      dtn_surface_presentation_snapshot(surface, &presentation) ==
              DTN_STATUS_OK &&
          presentation.visible_acknowledgement_eligible_generation == 12u &&
          presentation.accessibility_announcement_count ==
              announcements_before + 1u &&
          presentation.accessibility_body_count == 3u &&
          due_cards.count == 3u &&
          [[(NSTextField*)due_cards[0].subviews[0] stringValue]
              isEqualToString:@"first"] &&
          [[(NSTextField*)due_cards[1].subviews[0] stringValue]
              isEqualToString:@"second"] &&
          [[(NSTextField*)due_cards[2].subviews[0] stringValue]
              isEqualToString:@"third"] &&
          note_view.window.firstResponder == responder_before,
      "visible due FIFO acknowledges once without moving focus");
  const uint64_t due_announcement_count =
      presentation.accessibility_announcement_count;
  ok &= expect(dtn_surface_update_layout(surface, &normal_layout) ==
                       DTN_STATUS_OK &&
                   dtn_surface_presentation_snapshot(surface, &presentation) ==
                       DTN_STATUS_OK &&
                   presentation.accessibility_announcement_count ==
                       due_announcement_count,
               "ready announcement is not repeated by layout");

  std::vector<uint8_t> hidden_due = packet(13u, 10u, {"private"}, 0x02u);
  mark_cards_due(hidden_due, 1u);
  ok &= expect(dtn_surface_apply_projection(surface, hidden_due.data(),
                                            hidden_due.size()) ==
                   DTN_STATUS_OK,
               "background due projection retention");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(
      dtn_surface_presentation_snapshot(surface, &presentation) ==
              DTN_STATUS_OK &&
          presentation.visible_acknowledgement_eligible_generation == 0u &&
          presentation.accessibility_announcement_count ==
              due_announcement_count &&
          presentation.accessibility_body_count == 0u,
      "hidden due has no acknowledgement or body announcement");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.projection_generation == 13u &&
                   snapshot.projected_card_count == 1u &&
                   snapshot.due_count == 1u,
               "hidden projection retains last data");

  std::vector<uint8_t> japanese = packet(
      14u, 11u, {"日本語の長いノート本文を表示して折り返しを確認します"}, 0x01u);
  write_u16(japanese, 86u, 1u);
  write_u32(japanese, 104u, 24000u);
  ok &= expect(dtn_surface_apply_projection(surface, japanese.data(),
                                            japanese.size()) == DTN_STATUS_OK &&
                   dtn_surface_update_layout(surface, &narrow_layout) ==
                       DTN_STATUS_OK,
               "Japanese 24 point narrow projection");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  NSView* localized_card = find_view_named(note_view, @"DtnNoteCardView");
  ok &= expect(
      dtn_surface_presentation_snapshot(surface, &presentation) ==
              DTN_STATUS_OK &&
          presentation.body_font_millipoints == 24000u &&
          presentation.first_card_width > 0 &&
          presentation.first_card_x >= presentation.rail_x &&
          presentation.first_card_x + presentation.first_card_width <=
              presentation.rail_x + presentation.rail_width &&
          [[[localized_card accessibilityLabel] substringToIndex:3]
              isEqualToString:@"ノート"],
      "localized accessible name and clipped narrow card");

  std::vector<uint8_t> editing = packet(15u, 12u, {"baseline"}, 0x01u);
  editing[83u] = DTN_EDITOR_EDITING;
  write_u64(editing, 108u, 21u);
  ok &= expect(dtn_surface_apply_projection(surface, editing.data(),
                                            editing.size()) == DTN_STATUS_OK,
               "editor projection with draft generation");

  const std::string edited = "edited body";
  DtnSurfaceIntentV1 save = {};
  save.struct_size = sizeof(save);
  save.version = DTN_INTENT_VERSION;
  save.surface_generation = 7u;
  save.projection_generation = 15u;
  save.event_generation = 21u;
  save.draft_generation = 21u;
  save.card_token = 1u;
  save.expected_store_revision = 12u;
  save.kind = DTN_INTENT_SAVE;
  save.payload_bytes = static_cast<uint32_t>(edited.size());
  save.color = 1u;
  ok &= expect(dtn_surface_request_intent(
                   surface, &save,
                   reinterpret_cast<const uint8_t*>(edited.data())) ==
                   DTN_STATUS_OK,
               "semantic Save intent accepted");
  DtnSurfaceIntentV1 busy = save;
  busy.event_generation = 22u;
  ok &= expect(dtn_surface_request_intent(
                   surface, &busy,
                   reinterpret_cast<const uint8_t*>(edited.data())) ==
                   DTN_STATUS_BUSY,
               "one outstanding intent bound");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.draft_generation == 21u &&
                   snapshot.outstanding_intent == 1u &&
                   snapshot.emitted_intent_count == 1u,
               "content-free outstanding intent snapshot");

  DtnSurfaceIntentV1 taken = {};
  taken.struct_size = sizeof(taken);
  taken.version = DTN_INTENT_VERSION;
  uint8_t payload[DTN_MAX_INTENT_PAYLOAD_BYTES] = {};
  ok &= expect(dtn_surface_take_intent(surface, &taken, payload,
                                       edited.size() - 1u) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "undersized take buffer leaves intent pending");
  taken = {};
  taken.struct_size = sizeof(taken);
  taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(surface, &taken, payload,
                                       sizeof(payload)) == DTN_STATUS_OK &&
                   taken.event_generation == 21u &&
                   taken.kind == DTN_INTENT_SAVE &&
                   std::memcmp(payload, edited.data(), edited.size()) == 0,
               "semantic intent take preserves bounded payload");
  DtnSurfaceIntentV1 duplicate_take = {};
  duplicate_take.struct_size = sizeof(duplicate_take);
  duplicate_take.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(surface, &duplicate_take, payload,
                                       sizeof(payload)) ==
                   DTN_STATUS_NOT_FOUND,
               "intent is delivered once");

  DtnSurfaceResultV1 stale_result = {};
  stale_result.struct_size = sizeof(stale_result);
  stale_result.version = DTN_RESULT_VERSION;
  stale_result.surface_generation = 7u;
  stale_result.projection_generation = 15u;
  stale_result.event_generation = 20u;
  stale_result.draft_generation = 21u;
  stale_result.new_store_revision = 12u;
  stale_result.new_projection_generation = 15u;
  stale_result.disposition = DTN_RESULT_CONFLICT;
  ok &= expect(dtn_surface_apply_result(surface, &stale_result) ==
                   DTN_STATUS_STALE,
               "mismatched result fails closed");
  DtnSurfaceResultV1 conflict = stale_result;
  conflict.event_generation = 21u;
  ok &= expect(dtn_surface_apply_result(surface, &conflict) == DTN_STATUS_OK &&
                   dtn_surface_apply_result(surface, &conflict) ==
                       DTN_STATUS_STALE,
               "conflict clears exactly one outstanding intent");

  DtnSurfaceIntentV1 oversized = save;
  oversized.event_generation = 22u;
  oversized.payload_bytes = DTN_MAX_INTENT_PAYLOAD_BYTES + 1u;
  ok &= expect(dtn_surface_request_intent(surface, &oversized, payload) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "oversized intent payload rejected atomically");
  std::string maximum_intent(DTN_MAX_INTENT_PAYLOAD_BYTES, 'x');
  DtnSurfaceIntentV1 maximum_save = save;
  maximum_save.event_generation = 22u;
  maximum_save.payload_bytes = DTN_MAX_INTENT_PAYLOAD_BYTES;
  ok &= expect(dtn_surface_request_intent(
                   surface, &maximum_save,
                   reinterpret_cast<const uint8_t*>(maximum_intent.data())) ==
                   DTN_STATUS_OK,
               "maximum intent payload accepted");
  taken = {};
  taken.struct_size = sizeof(taken);
  taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(surface, &taken, payload,
                                       sizeof(payload)) == DTN_STATUS_OK,
               "maximum intent delivered");
  DtnSurfaceResultV1 accepted = {};
  accepted.struct_size = sizeof(accepted);
  accepted.version = DTN_RESULT_VERSION;
  accepted.surface_generation = 7u;
  accepted.projection_generation = 15u;
  accepted.event_generation = 22u;
  accepted.draft_generation = 21u;
  accepted.new_store_revision = 13u;
  accepted.new_projection_generation = 16u;
  accepted.disposition = DTN_RESULT_ACCEPTED;
  ok &= expect(dtn_surface_apply_result(surface, &accepted) == DTN_STATUS_OK,
               "accepted mutation result advances revision and generation");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.outstanding_intent == 0u &&
                   snapshot.emitted_intent_count == 2u &&
                   snapshot.applied_result_count == 2u,
               "intent/result counters and ownership return to zero");

  ok &= expect(std::memcmp(&terminal, &terminal_before, sizeof(terminal)) == 0,
               "G1-G3/T1 terminal geometry and input sentinel delta zero");
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
