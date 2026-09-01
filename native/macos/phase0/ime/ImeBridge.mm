#import <AppKit/AppKit.h>

#include <pthread.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kSummaryMagic = 0x454d4944;  // "DIME" little-endian.
constexpr uint16_t kSummaryVersion = 1;

enum ImeFlags : uint32_t {
  kMarkedStateObserved = 1U << 0,
  kCandidateRectFinite = 1U << 1,
  kCandidateRectRoundTrips = 1U << 2,
  kCandidateRangeMatches = 1U << 3,
  kCommitMatches = 1U << 4,
  kCancelMatches = 1U << 5,
  kRawAndCompositionSeparated = 1U << 6,
  kEventOrderMatches = 1U << 7,
  kValidAttributesPresent = 1U << 8,
  kInputContextConnected = 1U << 9,
};

enum EventCode : uint32_t {
  kRawEvent = 1,
  kPreeditEvent = 2,
  kCandidateEvent = 3,
  kCommitEvent = 4,
  kUnmarkEvent = 5,
};

#pragma pack(push, 1)
struct ImeSummary {
  uint32_t magic;
  uint16_t version;
  uint16_t summary_bytes;
  uint32_t flags;
  uint32_t event_count;
  uint32_t marked_updates;
  uint32_t commits;
  uint32_t unmarks;
  uint32_t candidate_queries;
  uint32_t raw_delivered;
  uint32_t raw_suppressed;
  uint32_t final_document_utf16;
  uint32_t final_selection_location;
  uint32_t first_marked_location;
  uint32_t first_marked_length;
  uint32_t candidate_actual_location;
  uint32_t candidate_actual_length;
  uint64_t scenario_micros;
  double candidate_screen_x;
  double candidate_screen_y;
  double candidate_screen_width;
  double candidate_screen_height;
  double caret_local_x;
  double caret_local_y;
  double caret_local_width;
  double caret_local_height;
  uint64_t event_hash;
  uint32_t main_thread_violation;
  uint32_t error_code;
  char final_document[64];
  char event_order[40];
};
#pragma pack(pop)

static_assert(sizeof(ImeSummary) == 256);

constexpr uint64_t kFnvOffset = 1469598103934665603ULL;
constexpr uint64_t kFnvPrime = 1099511628211ULL;

bool NearlyEqual(CGFloat first, CGFloat second) {
  return std::abs(first - second) < 0.01;
}

NSString* PlainString(id value) {
  if ([value isKindOfClass:[NSAttributedString class]]) {
    return static_cast<NSAttributedString*>(value).string;
  }
  if ([value isKindOfClass:[NSString class]]) {
    return static_cast<NSString*>(value);
  }
  return @"";
}

}  // namespace

@interface Phase0TextInputView : NSView <NSTextInputClient>

- (void)runScenario:(ImeSummary*)summary;
- (void)recordRawKeyForTest;

@end

@implementation Phase0TextInputView {
  NSMutableAttributedString* document_;
  NSAttributedString* marked_text_;
  NSRange marked_range_;
  NSRange selected_range_;
  NSRect caret_rect_;
  std::vector<uint32_t> events_;
  uint32_t marked_updates_;
  uint32_t commits_;
  uint32_t unmarks_;
  uint32_t candidate_queries_;
  uint32_t raw_delivered_;
  uint32_t raw_suppressed_;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)hasMarkedText {
  return marked_text_ != nil && marked_text_.length != 0;
}

- (NSRange)markedRange {
  return [self hasMarkedText] ? marked_range_ : NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange {
  return selected_range_;
}

- (void)setMarkedText:(id)value
         selectedRange:(NSRange)relative_selection
       replacementRange:(NSRange)replacement_range {
  NSString* plain = PlainString(value);
  NSAttributedString* incoming =
      [[NSAttributedString alloc] initWithString:plain];
  NSUInteger location = selected_range_.location;
  if ([self hasMarkedText]) {
    location = marked_range_.location;
  } else if (replacement_range.location != NSNotFound &&
             NSMaxRange(replacement_range) <= document_.length) {
    [document_ replaceCharactersInRange:replacement_range withString:@""];
    location = replacement_range.location;
  }
  marked_text_ = incoming;
  marked_range_ = NSMakeRange(location, incoming.length);
  const NSUInteger relative_location =
      std::min(relative_selection.location, incoming.length);
  const NSUInteger relative_length = std::min(
      relative_selection.length, incoming.length - relative_location);
  selected_range_ = NSMakeRange(location + relative_location, relative_length);
  ++marked_updates_;
  events_.push_back(kPreeditEvent);
  [self setNeedsDisplay:YES];
}

- (void)unmarkText {
  const NSUInteger location = [self hasMarkedText] ? marked_range_.location
                                                   : selected_range_.location;
  marked_text_ = nil;
  marked_range_ = NSMakeRange(NSNotFound, 0);
  selected_range_ = NSMakeRange(location, 0);
  ++unmarks_;
  events_.push_back(kUnmarkEvent);
  [self setNeedsDisplay:YES];
}

- (void)insertText:(id)value replacementRange:(NSRange)replacement_range {
  NSString* plain = PlainString(value);
  NSRange target = replacement_range;
  if (target.location == NSNotFound) {
    target = [self hasMarkedText] ? marked_range_ : selected_range_;
  }
  if (target.location > document_.length ||
      NSMaxRange(target) > document_.length) {
    target = NSMakeRange(document_.length, 0);
  }
  [document_ replaceCharactersInRange:target withString:plain];
  selected_range_ = NSMakeRange(target.location + plain.length, 0);
  marked_text_ = nil;
  marked_range_ = NSMakeRange(NSNotFound, 0);
  ++commits_;
  events_.push_back(kCommitEvent);
  [self setNeedsDisplay:YES];
}

- (void)doCommandBySelector:(SEL)selector {
  (void)selector;
}

- (void)keyDown:(NSEvent*)event {
  if (![[self inputContext] handleEvent:event]) {
    [self recordRawKeyForTest];
  }
}

- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actual_range {
  NSMutableAttributedString* display = [document_ mutableCopy];
  if ([self hasMarkedText] && marked_range_.location <= display.length) {
    [display insertAttributedString:marked_text_ atIndex:marked_range_.location];
  }
  if (range.location == NSNotFound || range.location >= display.length) {
    if (actual_range != nullptr) {
      *actual_range = NSMakeRange(NSNotFound, 0);
    }
    return nil;
  }
  const NSRange bounded =
      NSIntersectionRange(range, NSMakeRange(0, display.length));
  if (actual_range != nullptr) {
    *actual_range = bounded;
  }
  return [display attributedSubstringFromRange:bounded];
}

- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText {
  return @[ NSMarkedClauseSegmentAttributeName ];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                          actualRange:(NSRangePointer)actual_range {
  ++candidate_queries_;
  events_.push_back(kCandidateEvent);
  if (actual_range != nullptr) {
    if ([self hasMarkedText]) {
      *actual_range = NSIntersectionRange(range, marked_range_);
    } else {
      *actual_range = selected_range_;
    }
  }
  const NSRect window_rect = [self convertRect:caret_rect_ toView:nil];
  return [self.window convertRectToScreen:window_rect];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
  (void)point;
  return selected_range_.location;
}

- (void)recordRawKeyForTest {
  if ([self hasMarkedText]) {
    ++raw_suppressed_;
    return;
  }
  ++raw_delivered_;
  events_.push_back(kRawEvent);
}

- (void)drawRect:(NSRect)dirty_rect {
  (void)dirty_rect;
  [[NSColor colorWithCalibratedRed:0.025 green:0.03 blue:0.045 alpha:1.0]
      setFill];
  NSRectFill(self.bounds);
  NSMutableAttributedString* display = [document_ mutableCopy];
  if ([self hasMarkedText] && marked_range_.location <= display.length) {
    NSMutableAttributedString* marked = [marked_text_ mutableCopy];
    [marked addAttribute:NSUnderlineStyleAttributeName
                   value:@(NSUnderlineStyleSingle)
                   range:NSMakeRange(0, marked.length)];
    [display insertAttributedString:marked atIndex:marked_range_.location];
  }
  [display addAttributes:@{
    NSFontAttributeName : [NSFont monospacedSystemFontOfSize:22
                                                     weight:NSFontWeightRegular],
    NSForegroundColorAttributeName : NSColor.whiteColor,
  }
                    range:NSMakeRange(0, display.length)];
  [display drawAtPoint:NSMakePoint(42, 86)];
  [NSColor.systemYellowColor setFill];
  NSRectFill(caret_rect_);
}

- (void)runScenario:(ImeSummary*)summary {
  const auto started = std::chrono::steady_clock::now();
  document_ = [[NSMutableAttributedString alloc] initWithString:@"prompt> "];
  marked_text_ = nil;
  marked_range_ = NSMakeRange(NSNotFound, 0);
  selected_range_ = NSMakeRange(document_.length, 0);
  caret_rect_ = NSMakeRect(137.0, 121.0, 2.0, 24.0);
  events_.clear();
  marked_updates_ = 0;
  commits_ = 0;
  unmarks_ = 0;
  candidate_queries_ = 0;
  raw_delivered_ = 0;
  raw_suppressed_ = 0;

  [self recordRawKeyForTest];
  NSAttributedString* first_preedit =
      [[NSAttributedString alloc] initWithString:@"にほん"];
  [self setMarkedText:first_preedit
         selectedRange:NSMakeRange(3, 0)
       replacementRange:NSMakeRange(NSNotFound, 0)];
  const NSRange first_marked = [self markedRange];
  if ([self hasMarkedText] && first_marked.location == 8 &&
      first_marked.length == 3 && [self selectedRange].location == 11) {
    summary->flags |= kMarkedStateObserved;
  }

  NSRange candidate_actual = NSMakeRange(NSNotFound, 0);
  const NSRect candidate =
      [self firstRectForCharacterRange:first_marked
                            actualRange:&candidate_actual];
  summary->candidate_screen_x = candidate.origin.x;
  summary->candidate_screen_y = candidate.origin.y;
  summary->candidate_screen_width = candidate.size.width;
  summary->candidate_screen_height = candidate.size.height;
  summary->caret_local_x = caret_rect_.origin.x;
  summary->caret_local_y = caret_rect_.origin.y;
  summary->caret_local_width = caret_rect_.size.width;
  summary->caret_local_height = caret_rect_.size.height;
  summary->candidate_actual_location =
      static_cast<uint32_t>(candidate_actual.location);
  summary->candidate_actual_length =
      static_cast<uint32_t>(candidate_actual.length);
  if (std::isfinite(candidate.origin.x) &&
      std::isfinite(candidate.origin.y) &&
      std::isfinite(candidate.size.width) &&
      std::isfinite(candidate.size.height) && candidate.size.width > 0 &&
      candidate.size.height > 0) {
    summary->flags |= kCandidateRectFinite;
  }
  const NSRect candidate_window = [self.window convertRectFromScreen:candidate];
  const NSRect candidate_local =
      [self convertRect:candidate_window fromView:nil];
  if (NearlyEqual(candidate_local.origin.x, caret_rect_.origin.x) &&
      NearlyEqual(candidate_local.origin.y, caret_rect_.origin.y) &&
      NearlyEqual(candidate_local.size.width, caret_rect_.size.width) &&
      NearlyEqual(candidate_local.size.height, caret_rect_.size.height)) {
    summary->flags |= kCandidateRectRoundTrips;
  }
  if (NSEqualRanges(candidate_actual, first_marked)) {
    summary->flags |= kCandidateRangeMatches;
  }

  [self recordRawKeyForTest];
  [self setMarkedText:@"にほんご"
         selectedRange:NSMakeRange(4, 0)
       replacementRange:NSMakeRange(NSNotFound, 0)];
  NSRange substring_actual = NSMakeRange(NSNotFound, 0);
  NSAttributedString* substring =
      [self attributedSubstringForProposedRange:[self markedRange]
                                     actualRange:&substring_actual];
  const bool substring_matches =
      [substring.string isEqualToString:@"にほんご"] &&
      NSEqualRanges(substring_actual, [self markedRange]);
  [self insertText:@"日本語" replacementRange:NSMakeRange(NSNotFound, 0)];
  const bool commit_matches =
      [document_.string isEqualToString:@"prompt> 日本語"] &&
      ![self hasMarkedText] && [self markedRange].location == NSNotFound &&
      selected_range_.location == document_.length && substring_matches;
  if (commit_matches) {
    summary->flags |= kCommitMatches;
  }

  [self recordRawKeyForTest];
  [self setMarkedText:@"かな"
         selectedRange:NSMakeRange(2, 0)
       replacementRange:NSMakeRange(NSNotFound, 0)];
  [self unmarkText];
  if ([document_.string isEqualToString:@"prompt> 日本語"] &&
      ![self hasMarkedText] && selected_range_.location == document_.length) {
    summary->flags |= kCancelMatches;
  }

  if (raw_delivered_ == 2 && raw_suppressed_ == 1 && commits_ == 1 &&
      marked_updates_ == 3 && unmarks_ == 1) {
    summary->flags |= kRawAndCompositionSeparated;
  }
  const std::vector<uint32_t> expected = {
      kRawEvent,     kPreeditEvent, kCandidateEvent, kPreeditEvent,
      kCommitEvent,  kRawEvent,     kPreeditEvent,   kUnmarkEvent,
  };
  if (events_ == expected) {
    summary->flags |= kEventOrderMatches;
  }
  if ([self validAttributesForMarkedText].count != 0) {
    summary->flags |= kValidAttributesPresent;
  }
  if (self.window.firstResponder == self && self.inputContext != nil) {
    summary->flags |= kInputContextConnected;
  }

  summary->magic = kSummaryMagic;
  summary->version = kSummaryVersion;
  summary->summary_bytes = sizeof(ImeSummary);
  summary->event_count = static_cast<uint32_t>(events_.size());
  summary->marked_updates = marked_updates_;
  summary->commits = commits_;
  summary->unmarks = unmarks_;
  summary->candidate_queries = candidate_queries_;
  summary->raw_delivered = raw_delivered_;
  summary->raw_suppressed = raw_suppressed_;
  summary->final_document_utf16 = static_cast<uint32_t>(document_.length);
  summary->final_selection_location =
      static_cast<uint32_t>(selected_range_.location);
  summary->first_marked_location = static_cast<uint32_t>(first_marked.location);
  summary->first_marked_length = static_cast<uint32_t>(first_marked.length);
  summary->event_hash = kFnvOffset;
  for (uint32_t event : events_) {
    summary->event_hash ^= event;
    summary->event_hash *= kFnvPrime;
  }
  std::snprintf(summary->final_document, sizeof(summary->final_document), "%s",
                document_.string.UTF8String);
  std::snprintf(summary->event_order, sizeof(summary->event_order), "%s",
                "R,P,X,P,C,R,P,U");
  summary->scenario_micros = static_cast<uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - started)
          .count());
  [self setNeedsDisplay:YES];
}

@end

Phase0TextInputView* g_text_input_view = nil;

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_ime_run(uint8_t* output, uint64_t output_length) {
  if (output == nullptr || output_length != sizeof(ImeSummary)) {
    return 1;
  }
  std::memset(output, 0, static_cast<size_t>(output_length));
  auto* summary = reinterpret_cast<ImeSummary*>(output);
  summary->main_thread_violation = pthread_main_np() == 0 ? 1U : 0U;
  if (summary->main_thread_violation != 0) {
    summary->error_code = 2;
    return 2;
  }
  @autoreleasepool {
    if (g_text_input_view == nil) {
      NSWindow* window = NSApp.keyWindow;
      if (window == nil) {
        window = NSApp.windows.firstObject;
      }
      if (window == nil) {
        summary->error_code = 3;
        return 3;
      }
      g_text_input_view =
          [[Phase0TextInputView alloc] initWithFrame:window.contentView.bounds];
      g_text_input_view.autoresizingMask =
          NSViewWidthSizable | NSViewHeightSizable;
      window.contentView = g_text_input_view;
      window.title = @"Dart Terminal — Phase 0 Japanese IME";
      [window makeFirstResponder:g_text_input_view];
    }
    [g_text_input_view runScenario:summary];
  }
  constexpr uint32_t required_flags = (1U << 10) - 1U;
  summary->error_code =
      (summary->flags & required_flags) == required_flags ? 0U : 4U;
  return 0;
}

extern "C" __attribute__((visibility("default"))) void
dt_phase0_native_finalize(void) {
  if (pthread_main_np() != 0) {
    g_text_input_view = nil;
  }
}
