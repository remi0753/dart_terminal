#include "TerminalNotesPlugin.h"

#import <AppKit/AppKit.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

const da_native_extension_services_v1 kServices = {
    sizeof(da_native_extension_services_v1),
    DA_NATIVE_EXTENSION_ABI_VERSION,
    nullptr,
    nullptr,
};

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

NSButton* find_button_with_title(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [[(NSButton*)root title] isEqualToString:title]) {
    return (NSButton*)root;
  }
  for (NSView* child in root.subviews) {
    NSButton* match = find_button_with_title(child, title);
    if (match != nil) return match;
  }
  return nil;
}

void replace_text(NSTextView* text_view, NSString* replacement) {
  const NSRange all = NSMakeRange(0u, text_view.string.length);
  [text_view breakUndoCoalescing];
  [text_view insertText:replacement replacementRange:all];
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
    if (!expect(dtn_initialize(nullptr) == DTN_STATUS_UNSUPPORTED_VERSION,
                "null initialize services") ||
        !expect(dtn_initialize(&kServices) == DTN_STATUS_OK,
                "initialize") ||
        !expect(dtn_initialize(&kServices) == DTN_STATUS_OK,
                "idempotent initialize")) {
      return 1;
    }
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

  DtnSurface* editor_surface = dtn_surface_create();
  ok &= expect(editor_surface != nullptr &&
                   dtn_debug_live_surfaces() == 2u,
               "isolated editor surface creation");
  NSWindow* editor_window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  NSView* editor_host =
      [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
  editor_window.contentView = editor_host;
  NSView* editor_note_view =
      (__bridge NSView*)dtn_surface_native_view(editor_surface);
  std::vector<uint8_t> editor_packet = packet(1u, 4u, {"baseline"}, 0x01u);
  editor_packet[83u] = DTN_EDITOR_EDITING;
  write_u16(editor_packet, 86u, 1u);
  write_u64(editor_packet, 108u, 1u);
  ok &= expect(dtn_surface_apply_projection(
                   editor_surface, editor_packet.data(), editor_packet.size()) ==
                       DTN_STATUS_OK &&
                   dtn_surface_update_layout(editor_surface, &normal_layout) ==
                       DTN_STATUS_OK &&
                   dtn_surface_attach_to_host(
                       editor_surface, (__bridge void*)editor_host) ==
                       DTN_STATUS_OK,
               "actual AppKit editor projection and attachment");

  NSView* editor_view =
      find_view_named(editor_note_view, @"DtnNoteEditorView");
  NSTextView* text_view =
      editor_view == nil ? nil : [editor_view valueForKey:@"textView"];
  NSSegmentedControl* draft_color =
      editor_view == nil ? nil : [editor_view valueForKey:@"colorControl"];
  NSButton* save_button = find_button_with_title(editor_view, @"保存");
  NSButton* cancel_button =
      find_button_with_title(editor_view, @"キャンセル");
  NSButton* discard_button = find_button_with_title(editor_view, @"破棄");
  NSButton* keep_editing_button =
      find_button_with_title(editor_view, @"編集を続ける");
  NSView* discard_confirmation =
      editor_view == nil ? nil
                         : [editor_view valueForKey:@"discardConfirmation"];
  NSTextField* editor_error =
      editor_view == nil ? nil : [editor_view valueForKey:@"errorLabel"];
  NSArray<NSButton*>* semantic_buttons =
      editor_note_view == nil ? nil
                              : [editor_note_view valueForKey:@"actionButtons"];
  NSSegmentedControl* card_color =
      editor_note_view == nil
          ? nil
          : [editor_note_view valueForKey:@"cardColorControl"];
  ok &= expect(editor_view != nil && !editor_view.hidden && text_view != nil &&
                   [text_view.string isEqualToString:@"baseline"] &&
                   save_button != nil && cancel_button != nil &&
                   discard_button != nil && keep_editing_button != nil &&
                   draft_color.segmentCount == 6 &&
                   semantic_buttons.count == 8u &&
                   card_color.segmentCount == 6 &&
                   [[editor_view accessibilityRole]
                       isEqualToString:NSAccessibilityGroupRole] &&
                   [[text_view accessibilityRole]
                       isEqualToString:NSAccessibilityTextAreaRole] &&
                   [[save_button accessibilityRole]
                       isEqualToString:NSAccessibilityButtonRole],
               "localized editor and actual accessibility controls");
  NSView* editor_rail =
      find_view_named(editor_note_view, @"DtnOpaqueRailView");
  NSArray* editor_rail_children = [editor_rail accessibilityChildren];
  NSArray* editor_children = [editor_view accessibilityChildren];
  ok &= expect(editor_rail_children.count == 2u &&
                   editor_rail_children[1] == editor_view &&
                   editor_children.count == 4u &&
                   text_view.nextKeyView == draft_color &&
                   draft_color.nextKeyView == save_button &&
                   save_button.nextKeyView == cancel_button &&
                   cancel_button.nextKeyView != nil,
               "editor VoiceOver tree and keyboard order are deterministic");
  ok &= expect(dtn_surface_focus(editor_surface, 99u) ==
                       DTN_STATUS_INVALID_ARGUMENT &&
                   dtn_surface_focus(editor_surface, DTN_FOCUS_EDITOR) ==
                       DTN_STATUS_OK,
               "generation adapter can focus only a valid Note target");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(editor_surface, &snapshot) ==
                       DTN_STATUS_OK &&
                   snapshot.focus_target == DTN_FOCUS_EDITOR &&
                   snapshot.interaction_flags == 0u,
               "initial interaction snapshot is content-free and clean");
  presentation = {};
  presentation.struct_size = sizeof(presentation);
  presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_presentation_snapshot(editor_surface,
                                                  &presentation) ==
                       DTN_STATUS_OK &&
                   presentation.accessibility_body_count == 1u,
               "editor exposes one accessible body without card echo");

  [editor_window makeFirstResponder:text_view];
  [text_view setSelectedRange:NSMakeRange(text_view.string.length, 0u)];
  [text_view setMarkedText:@"未確定"
             selectedRange:NSMakeRange(3u, 0u)
          replacementRange:NSMakeRange(NSNotFound, 0u)];
  [text_view doCommandBySelector:@selector(cancelOperation:)];
  ok &= expect(!text_view.hasMarkedText &&
                   [text_view.string isEqualToString:@"baseline"] &&
                   discard_confirmation.hidden,
               "first Escape cancels marked text without closing editor");
  [text_view setMarkedText:@"かな"
             selectedRange:NSMakeRange(2u, 0u)
          replacementRange:NSMakeRange(NSNotFound, 0u)];
  const BOOL had_marked_text = text_view.hasMarkedText;
  [text_view insertText:@"仮名" replacementRange:text_view.markedRange];
  ok &= expect(had_marked_text && !text_view.hasMarkedText &&
                   [text_view.string isEqualToString:@"baseline仮名"] &&
                   text_view.undoManager.canUndo,
               "Japanese marked text commits into volatile Undo draft");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(editor_surface, &snapshot) ==
                       DTN_STATUS_OK &&
                   snapshot.interaction_flags ==
                       DTN_INTERACTION_EDITOR_DIRTY &&
                   snapshot.focus_target == DTN_FOCUS_EDITOR,
               "dirty state mirrors no Note content across the ABI");

  NSString* before_invalid = [text_view.string copy];
  [text_view setSelectedRange:NSMakeRange(3u, 2u)];
  const NSRange selection_before_invalid = text_view.selectedRange;
  const BOOL undo_before_invalid = text_view.undoManager.canUndo;
  NSString* undo_name_before_invalid =
      [text_view.undoManager.undoActionName copy];
  replace_text(text_view,
               [@"x" stringByPaddingToLength:4097u
                                  withString:@"x"
                             startingAtIndex:0u]);
  ok &= expect([text_view.string isEqualToString:before_invalid] &&
                   NSEqualRanges(text_view.selectedRange,
                                 selection_before_invalid) &&
                   text_view.undoManager.canUndo == undo_before_invalid &&
                   [text_view.undoManager.undoActionName
                       isEqualToString:undo_name_before_invalid],
               "4,097-byte operation rejects atomically");

  NSPasteboard* external_text = [NSPasteboard pasteboardWithUniqueName];
  [external_text declareTypes:@[ NSPasteboardTypeString ] owner:nil];
  [external_text setString:[@"p" stringByPaddingToLength:4097u
                                             withString:@"p"
                                        startingAtIndex:0u]
                  forType:NSPasteboardTypeString];
  (void)[text_view readSelectionFromPasteboard:external_text
                                          type:NSPasteboardTypeString];
  ok &= expect([text_view.string isEqualToString:before_invalid] &&
                   NSEqualRanges(text_view.selectedRange,
                                 selection_before_invalid) &&
                   [text_view.readablePasteboardTypes
                       isEqualToArray:@[ NSPasteboardTypeString ]] &&
                   [text_view.acceptableDragTypes
                       isEqualToArray:@[ NSPasteboardTypeString ]],
               "paste drop and Services share bounded plain-text admission");
  (void)[external_text setString:@"file:///tmp/private"
                         forType:NSPasteboardTypeFileURL];
  ok &= expect(![text_view readSelectionFromPasteboard:external_text
                                                  type:NSPasteboardTypeFileURL] &&
                   [text_view.string isEqualToString:before_invalid],
               "file and custom pasteboard types are rejected");

  replace_text(text_view, @"x\u202ey");
  ok &= expect([text_view.string isEqualToString:before_invalid],
               "bidi control operation rejects atomically");
  const unichar unpaired_scalar = 0xd800u;
  NSString* unpaired =
      [NSString stringWithCharacters:&unpaired_scalar length:1u];
  replace_text(text_view, unpaired);
  ok &= expect([text_view.string isEqualToString:before_invalid],
               "unpaired surrogate operation rejects atomically");

  NSString* maximum_draft =
      [@"x" stringByPaddingToLength:4096u
                         withString:@"x"
                    startingAtIndex:0u];
  replace_text(text_view, maximum_draft);
  ok &= expect([text_view.string lengthOfBytesUsingEncoding:NSUTF8StringEncoding] ==
                       4096u &&
                   text_view.undoManager.canUndo,
               "4,096-byte operation is admitted with Undo");
  [text_view.undoManager undo];
  ok &= expect(![text_view.string isEqualToString:maximum_draft],
               "maximum draft replacement is undoable");
  replace_text(text_view, before_invalid);

  NSMutableString* sixty_four_lines = [NSMutableString stringWithString:@"x"];
  for (NSUInteger index = 1u; index < 64u; ++index) {
    [sixty_four_lines appendString:@"\nx"];
  }
  replace_text(text_view, sixty_four_lines);
  ok &= expect([text_view.string isEqualToString:sixty_four_lines],
               "64-line operation is admitted");
  [text_view.undoManager undo];
  replace_text(text_view, before_invalid);
  NSMutableString* sixty_five_lines = [sixty_four_lines mutableCopy];
  [sixty_five_lines appendString:@"\nx"];
  [text_view setSelectedRange:NSMakeRange(1u, 0u)];
  const NSRange selection_before_65 = text_view.selectedRange;
  replace_text(text_view, sixty_five_lines);
  ok &= expect([text_view.string isEqualToString:before_invalid] &&
                   NSEqualRanges(text_view.selectedRange,
                                 selection_before_65),
               "65-line operation rejects atomically");

  replace_text(text_view, @" \t");
  [save_button performClick:nil];
  DtnSurfaceIntentV1 editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  uint8_t editor_payload[DTN_MAX_INTENT_PAYLOAD_BYTES] = {};
  ok &= expect(!editor_error.hidden &&
                   dtn_surface_take_intent(editor_surface, &editor_taken,
                                           editor_payload,
                                           sizeof(editor_payload)) ==
                       DTN_STATUS_NOT_FOUND,
               "whitespace-only Save is rejected before intent emission");

  replace_text(text_view, @"仮名のメモ");
  draft_color.selectedSegment = 2;
  [draft_color sendAction:draft_color.action to:draft_color.target];
  [text_view setSelectedRange:NSMakeRange(2u, 1u)];
  const NSRange saved_selection = text_view.selectedRange;
  const BOOL saved_can_undo = text_view.undoManager.canUndo;
  [save_button performClick:nil];
  NSData* expected_editor_body =
      [text_view.string dataUsingEncoding:NSUTF8StringEncoding];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(editor_surface, &editor_taken,
                                       editor_payload,
                                       sizeof(editor_payload)) ==
                       DTN_STATUS_OK &&
                   editor_taken.kind == DTN_INTENT_SAVE &&
                   editor_taken.event_generation == 1u &&
                   editor_taken.draft_generation == 1u &&
                   editor_taken.color == 2u &&
                   editor_taken.payload_bytes == expected_editor_body.length &&
                   std::memcmp(editor_payload, expected_editor_body.bytes,
                               expected_editor_body.length) == 0,
               "Save emits committed Japanese body and draft color");
  DtnSurfaceResultV1 editor_conflict = {};
  editor_conflict.struct_size = sizeof(editor_conflict);
  editor_conflict.version = DTN_RESULT_VERSION;
  editor_conflict.surface_generation = 7u;
  editor_conflict.projection_generation = 1u;
  editor_conflict.event_generation = 1u;
  editor_conflict.draft_generation = 1u;
  editor_conflict.new_store_revision = 4u;
  editor_conflict.new_projection_generation = 1u;
  editor_conflict.disposition = DTN_RESULT_CONFLICT;
  ok &= expect(dtn_surface_apply_result(editor_surface, &editor_conflict) ==
                       DTN_STATUS_OK &&
                   [text_view.string isEqualToString:@"仮名のメモ"] &&
                   NSEqualRanges(text_view.selectedRange, saved_selection) &&
                   text_view.undoManager.canUndo == saved_can_undo &&
                   !editor_error.hidden && save_button.enabled,
               "conflict preserves draft selection Undo and re-enables editor");

  [text_view doCommandBySelector:@selector(cancelOperation:)];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(!discard_confirmation.hidden && !text_view.editable &&
                   dtn_surface_snapshot(editor_surface, &snapshot) ==
                       DTN_STATUS_OK &&
                   snapshot.interaction_flags ==
                       (DTN_INTERACTION_EDITOR_DIRTY |
                        DTN_INTERACTION_CONFIRM_DISCARD) &&
                   dtn_surface_take_intent(editor_surface, &editor_taken,
                                           editor_payload,
                                           sizeof(editor_payload)) ==
                       DTN_STATUS_NOT_FOUND,
               "dirty Cancel requires explicit discard confirmation");
  [keep_editing_button performClick:nil];
  ok &= expect(discard_confirmation.hidden && text_view.editable,
               "Keep Editing returns to unchanged draft");
  [cancel_button performClick:nil];
  [discard_button performClick:nil];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(editor_surface, &editor_taken,
                                       editor_payload,
                                       sizeof(editor_payload)) ==
                       DTN_STATUS_OK &&
                   editor_taken.kind == DTN_INTENT_CANCEL &&
                   editor_taken.event_generation == 2u &&
                   editor_taken.payload_bytes == 0u,
               "explicit Discard emits body-free Cancel");
  DtnSurfaceResultV1 cancel_accepted = {};
  cancel_accepted.struct_size = sizeof(cancel_accepted);
  cancel_accepted.version = DTN_RESULT_VERSION;
  cancel_accepted.surface_generation = 7u;
  cancel_accepted.projection_generation = 1u;
  cancel_accepted.event_generation = 2u;
  cancel_accepted.draft_generation = 1u;
  cancel_accepted.new_store_revision = 4u;
  cancel_accepted.new_projection_generation = 1u;
  cancel_accepted.disposition = DTN_RESULT_ACCEPTED;
  ok &= expect(dtn_surface_apply_result(editor_surface, &cancel_accepted) ==
                       DTN_STATUS_OK &&
                   editor_view.hidden &&
                   text_view.string.length == 0u &&
                   !text_view.undoManager.canUndo &&
                   dtn_surface_focus(editor_surface, DTN_FOCUS_EDITOR) ==
                       DTN_STATUS_NOT_FOUND &&
                   dtn_surface_focus(editor_surface, DTN_FOCUS_RAIL) ==
                       DTN_STATUS_OK,
               "accepted Cancel closes volatile editor locally");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(editor_surface, &snapshot) ==
                       DTN_STATUS_OK &&
                   snapshot.interaction_flags == 0u &&
                   snapshot.focus_target == DTN_FOCUS_RAIL,
               "rail focus and resolved editor state cross ABI without body");
  NSView* action_bar = [editor_note_view valueForKey:@"actionBar"];
  NSArray* read_rail_children = [editor_rail accessibilityChildren];
  NSArray* action_children = [action_bar accessibilityChildren];
  ok &= expect(read_rail_children.count == 3u &&
                   read_rail_children[2] == action_bar &&
                   action_children.count == 9u &&
                   action_children.firstObject == card_color &&
                   card_color.nextKeyView == semantic_buttons.firstObject &&
                   semantic_buttons.lastObject.nextKeyView != nil,
               "read-mode VoiceOver tree and keyboard actions are ordered");

  BOOL actual_actions = semantic_buttons.count == 8u;
  for (NSButton* button in semantic_buttons) {
    actual_actions = actual_actions && button.target != nil &&
                     button.action != nil &&
                     [[button accessibilityRole]
                         isEqualToString:NSAccessibilityButtonRole];
  }
  ok &= expect(actual_actions && !card_color.hidden && card_color.enabled,
               "all read-mode semantic actions are actual AppKit controls");
  card_color.selectedSegment = 4;
  [card_color sendAction:card_color.action to:card_color.target];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(editor_surface, &editor_taken,
                                       editor_payload,
                                       sizeof(editor_payload)) ==
                       DTN_STATUS_OK &&
                   editor_taken.kind == DTN_INTENT_CHANGE_COLOR &&
                   editor_taken.color == 4u &&
                   editor_taken.event_generation == 3u,
               "read-mode six-color control emits semantic change");
  DtnSurfaceResultV1 color_rejected = {};
  color_rejected.struct_size = sizeof(color_rejected);
  color_rejected.version = DTN_RESULT_VERSION;
  color_rejected.surface_generation = 7u;
  color_rejected.projection_generation = 1u;
  color_rejected.event_generation = 3u;
  color_rejected.draft_generation = 1u;
  color_rejected.new_store_revision = 4u;
  color_rejected.new_projection_generation = 1u;
  color_rejected.disposition = DTN_RESULT_REJECTED;
  ok &= expect(dtn_surface_apply_result(editor_surface, &color_rejected) ==
                       DTN_STATUS_OK &&
                   card_color.enabled,
               "rejected card action restores semantic controls");

  NSButton* copy_button = semantic_buttons[7];
  [copy_button performClick:nil];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(editor_surface, &editor_taken,
                                       editor_payload,
                                       sizeof(editor_payload)) ==
                       DTN_STATUS_OK &&
                   editor_taken.kind == DTN_INTENT_COPY &&
                   editor_taken.event_generation == 4u &&
                   editor_taken.payload_bytes == 8u &&
                   std::memcmp(editor_payload, "baseline", 8u) == 0,
               "explicit Copy is the only non-Save body-bearing action");
  DtnSurfaceResultV1 copy_accepted = {};
  copy_accepted.struct_size = sizeof(copy_accepted);
  copy_accepted.version = DTN_RESULT_VERSION;
  copy_accepted.surface_generation = 7u;
  copy_accepted.projection_generation = 1u;
  copy_accepted.event_generation = 4u;
  copy_accepted.draft_generation = 1u;
  copy_accepted.new_store_revision = 4u;
  copy_accepted.new_projection_generation = 1u;
  copy_accepted.disposition = DTN_RESULT_ACCEPTED;
  ok &= expect(dtn_surface_apply_result(editor_surface, &copy_accepted) ==
                       DTN_STATUS_OK,
               "nonmutating Copy completes without projection advance");

  NSButton* delete_button = semantic_buttons[4];
  [delete_button performClick:nil];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect([delete_button.title isEqualToString:@"削除を確認"] &&
                   dtn_surface_take_intent(editor_surface, &editor_taken,
                                           editor_payload,
                                           sizeof(editor_payload)) ==
                       DTN_STATUS_NOT_FOUND,
               "Delete requires a separate confirmation action");
  [delete_button performClick:nil];
  editor_taken = {};
  editor_taken.struct_size = sizeof(editor_taken);
  editor_taken.version = DTN_INTENT_VERSION;
  ok &= expect(dtn_surface_take_intent(editor_surface, &editor_taken,
                                       editor_payload,
                                       sizeof(editor_payload)) ==
                       DTN_STATUS_OK &&
                   editor_taken.kind == DTN_INTENT_DELETE &&
                   editor_taken.event_generation == 5u,
               "confirmed Delete emits one semantic intent");
  DtnSurfaceResultV1 delete_rejected = color_rejected;
  delete_rejected.event_generation = 5u;
  ok &= expect(dtn_surface_apply_result(editor_surface, &delete_rejected) ==
                   DTN_STATUS_OK,
               "rejected Delete returns action ownership");

  ok &= expect(dtn_surface_detach_from_host(editor_surface) == DTN_STATUS_OK,
               "editor surface detaches before destruction");
  dtn_surface_destroy(editor_surface);
  ok &= expect(dtn_debug_live_surfaces() == 1u,
               "isolated editor surface releases all native ownership");

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
