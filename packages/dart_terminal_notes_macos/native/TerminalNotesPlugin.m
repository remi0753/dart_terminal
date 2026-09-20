#import "TerminalNotesPlugin.h"

#include <math.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

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
  uint32_t locale;
  uint32_t body_font_millipoints;
  uint32_t projection_flags;
} DtnParsedProjection;

static const uint32_t kDtnLightSurfaces[6] = {
    0xf5f5f3ffu, 0xfff3a6ffu, 0xdcebffffu,
    0xddf4dcffu, 0xfaddeaffu, 0xe8deffffu,
};
static const uint32_t kDtnLightAccents[6] = {
    0x6b6b66ffu, 0x7a5a00ffu, 0x245b9effu,
    0x2e6b37ffu, 0x9a365effu, 0x6240a0ffu,
};
static const uint32_t kDtnDarkSurfaces[6] = {
    0x343432ffu, 0x4a401fffu, 0x24384effu,
    0x233e2bffu, 0x4a2938ffu, 0x382d4cffu,
};
static const uint32_t kDtnDarkAccents[6] = {
    0xb8b8b2ffu, 0xf1cd5affu, 0x85b6e8ffu,
    0x83c98cffu, 0xe49ab8ffu, 0xb9a2e8ffu,
};

static NSColor* DtnColor(uint32_t rgba) {
  return [NSColor colorWithSRGBRed:((rgba >> 24u) & 0xffu) / 255.0
                             green:((rgba >> 16u) & 0xffu) / 255.0
                              blue:((rgba >> 8u) & 0xffu) / 255.0
                             alpha:(rgba & 0xffu) / 255.0];
}

static uint32_t DtnSurfaceRgba(uint32_t color, bool dark) {
  return dark ? kDtnDarkSurfaces[color] : kDtnLightSurfaces[color];
}

static uint32_t DtnAccentRgba(uint32_t color, bool dark) {
  return dark ? kDtnDarkAccents[color] : kDtnLightAccents[color];
}

@interface DtnCardModel : NSObject
@property(nonatomic) uint64_t token;
@property(nonatomic, copy) NSString* body;
@property(nonatomic) uint32_t color;
@property(nonatomic) uint32_t status;
@property(nonatomic) uint32_t triggerKind;
@property(nonatomic) uint32_t triggerPhase;
@property(nonatomic) uint32_t order;
@property(nonatomic) BOOL due;
@end

@implementation DtnCardModel
@end

@interface DtnFlippedView : NSView
@end

@implementation DtnFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface DtnNoteBadgeButton : NSButton
@property(nonatomic) BOOL readyCue;
@property(nonatomic) BOOL darkAppearance;
@end

@implementation DtnNoteBadgeButton

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    self.bordered = NO;
    self.title = @"";
    self.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.focusRingType = NSFocusRingTypeExterior;
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityButtonRole];
    [self setAccessibilityHelp:@"Show Notes"];
  }
  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect visual = NSMakeRect(0, 8, self.bounds.size.width, 28);
  NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:visual
                                                      xRadius:14
                                                      yRadius:14];
  [DtnColor(self.darkAppearance ? 0x343432ffu : 0xf5f5f3ffu) setFill];
  [path fill];
  [DtnColor(self.darkAppearance ? 0xb8b8b2ffu : 0x6b6b66ffu) setStroke];
  path.lineWidth = 1;
  [path stroke];
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  NSDictionary* attributes = @{
    NSFontAttributeName : self.font,
    NSForegroundColorAttributeName :
        DtnColor(self.darkAppearance ? 0xf5f5f5ffu : 0x1f1f1fffu),
    NSParagraphStyleAttributeName : style,
  };
  [self.title drawInRect:NSInsetRect(visual, 4, 6) withAttributes:attributes];
  if (self.readyCue) {
    [DtnColor(self.darkAppearance ? 0xf1cd5affu : 0x7a5a00ffu) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4, 18, 6, 6)] fill];
  }
}

@end

@interface DtnOpaqueRailView : DtnFlippedView
@property(nonatomic) BOOL darkAppearance;
@property(nonatomic) BOOL increaseContrast;
@end

@implementation DtnOpaqueRailView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [DtnColor(self.darkAppearance ? 0x202124ffu : 0xf7f7f8ffu) setFill];
  NSRectFill(self.bounds);
  [DtnColor(self.darkAppearance ? 0xb8b8b2ffu : 0x6b6b66ffu) setStroke];
  NSBezierPath* border = [NSBezierPath bezierPathWithRoundedRect:
                                        NSInsetRect(self.bounds, 0.5, 0.5)
                                                       xRadius:12
                                                       yRadius:12];
  border.lineWidth = self.increaseContrast ? 2 : 1;
  [border stroke];
}
@end

@interface DtnNoteCardView : DtnFlippedView
@property(nonatomic, strong) NSTextField* bodyLabel;
@property(nonatomic, strong) NSTextField* chipLabel;
@property(nonatomic, strong) DtnCardModel* model;
@property(nonatomic) uint32_t surfaceRgba;
@property(nonatomic) uint32_t accentRgba;
@property(nonatomic) uint32_t bodyRgba;
@property(nonatomic) BOOL increaseContrast;
- (void)applyModel:(DtnCardModel*)model
              dark:(BOOL)dark
     bodyFontPoints:(CGFloat)bodyFontPoints
  increaseContrast:(BOOL)increaseContrast
     japaneseLocale:(BOOL)japaneseLocale;
@end

@implementation DtnNoteCardView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = NO;
    _bodyLabel = [NSTextField wrappingLabelWithString:@""];
    _bodyLabel.maximumNumberOfLines = 8;
    _bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _bodyLabel.selectable = NO;
    [_bodyLabel setAccessibilityElement:YES];
    [_bodyLabel setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self addSubview:_bodyLabel];
    _chipLabel = [NSTextField labelWithString:@""];
    _chipLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    [_chipLabel setAccessibilityElement:YES];
    [_chipLabel setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self addSubview:_chipLabel];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
  }
  return self;
}

- (BOOL)isOpaque { return YES; }

- (void)applyModel:(DtnCardModel*)model
              dark:(BOOL)dark
     bodyFontPoints:(CGFloat)bodyFontPoints
  increaseContrast:(BOOL)increaseContrast
     japaneseLocale:(BOOL)japaneseLocale {
  self.model = model;
  self.surfaceRgba = DtnSurfaceRgba(model.color, dark);
  self.accentRgba = DtnAccentRgba(model.color, dark);
  self.bodyRgba = dark ? 0xf5f5f5ffu : 0x1f1f1fffu;
  self.increaseContrast = increaseContrast;
  self.layer.backgroundColor = DtnColor(self.surfaceRgba).CGColor;
  self.layer.borderColor = DtnColor(self.accentRgba).CGColor;
  self.layer.borderWidth = increaseContrast ? 2 : 1;
  self.layer.shadowOpacity = increaseContrast ? 0 : 0.16;
  self.layer.shadowOffset = NSMakeSize(0, 2);
  self.layer.shadowRadius = increaseContrast ? 0 : 8;
  self.bodyLabel.stringValue = model.body;
  self.bodyLabel.font = [NSFont systemFontOfSize:bodyFontPoints];
  self.bodyLabel.textColor = DtnColor(self.bodyRgba);
  NSString* chip = nil;
  if (model.status == 1u) {
    chip = japaneseLocale ? @"✓ 解決済み" : @"✓ Resolved";
  } else if (model.due) {
    chip = japaneseLocale ? @"● 準備完了" : @"● Ready";
  } else if (model.triggerKind == 1u) {
    chip = japaneseLocale ? @"◆ Return時" : @"◆ On Return";
  } else if (model.triggerKind == 2u) {
    chip = japaneseLocale ? @"▶ 次のプロンプト" : @"▶ Next Prompt";
  } else {
    chip = japaneseLocale ? @"○ 有効" : @"○ Active";
  }
  self.chipLabel.stringValue = chip;
  self.chipLabel.textColor = DtnColor(self.accentRgba);
  [self setNeedsDisplay:YES];
}

- (void)layout {
  [super layout];
  const CGFloat padding = 12;
  const CGFloat chipHeight = 16;
  self.chipLabel.frame = NSMakeRect(
      padding, self.bounds.size.height - padding - chipHeight,
      fmax(0, self.bounds.size.width - 2 * padding), chipHeight);
  self.bodyLabel.frame = NSMakeRect(
      padding, padding, fmax(0, self.bounds.size.width - 2 * padding),
      fmax(0, self.bounds.size.height - 3 * padding - chipHeight));
}

@end

@interface DtnNoteSurfaceView : DtnFlippedView
@property(nonatomic, strong) DtnNoteBadgeButton* badge;
@property(nonatomic, strong) DtnOpaqueRailView* rail;
@property(nonatomic, strong) DtnFlippedView* toolbar;
@property(nonatomic, strong) NSTextField* titleLabel;
@property(nonatomic, strong) NSSegmentedControl* sectionControl;
@property(nonatomic, strong) NSScrollView* scrollView;
@property(nonatomic, strong) DtnFlippedView* cardList;
@property(nonatomic, copy) NSArray<DtnCardModel*>* models;
@property(nonatomic, copy) NSArray<DtnNoteCardView*>* cardViews;
@property(nonatomic) DtnParsedProjection projection;
@property(nonatomic) CGFloat requestedRailWidth;
@property(nonatomic) CGFloat backingScale;
@property(nonatomic) BOOL smallPane;
@property(nonatomic) uint32_t accessibilityNodeCount;
@property(nonatomic) uint32_t accessibilityBodyCount;
@property(nonatomic) uint32_t animationMilliseconds;
@property(nonatomic) uint64_t visibleAcknowledgementEligibleGeneration;
@property(nonatomic) uint64_t lastAnnouncedGeneration;
@property(nonatomic) uint64_t accessibilityAnnouncementCount;
- (void)applyProjection:(DtnParsedProjection)projection
                  cards:(NSArray<DtnCardModel*>*)cards;
- (void)applyLayout:(DtnLayoutV1)layout;
- (void)layoutPresentation;
- (void)reconcileReadyAnnouncement;
@end

@implementation DtnNoteSurfaceView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    _backingScale = 1;
    _requestedRailWidth = 320;
    _models = @[];
    _cardViews = @[];
    _badge = [[DtnNoteBadgeButton alloc] initWithFrame:NSZeroRect];
    [self addSubview:_badge];
    _rail = [[DtnOpaqueRailView alloc] initWithFrame:NSZeroRect];
    [_rail setAccessibilityElement:YES];
    [_rail setAccessibilityRole:NSAccessibilityGroupRole];
    [_rail setAccessibilityLabel:@"Notes"];
    [self addSubview:_rail];
    _toolbar = [[DtnFlippedView alloc] initWithFrame:NSZeroRect];
    [_toolbar setAccessibilityElement:YES];
    [_toolbar setAccessibilityRole:NSAccessibilityToolbarRole];
    [_rail addSubview:_toolbar];
    _titleLabel = [NSTextField labelWithString:@"Notes"];
    _titleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    [_toolbar addSubview:_titleLabel];
    _sectionControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _sectionControl.segmentCount = 2;
    [_sectionControl setLabel:@"Current" forSegment:0];
    [_sectionControl setLabel:@"Detached" forSegment:1];
    _sectionControl.selectedSegment = 0;
    [_toolbar addSubview:_sectionControl];
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.drawsBackground = NO;
    [_scrollView setAccessibilityElement:YES];
    [_scrollView setAccessibilityRole:NSAccessibilityScrollAreaRole];
    _cardList = [[DtnFlippedView alloc] initWithFrame:NSZeroRect];
    [_cardList setAccessibilityElement:YES];
    [_cardList setAccessibilityRole:NSAccessibilityListRole];
    _scrollView.documentView = _cardList;
    [_rail addSubview:_scrollView];
    [self setAccessibilityElement:NO];
  }
  return self;
}

- (NSView*)hitTest:(NSPoint)point {
  if ((!self.badge.hidden && NSPointInRect(point, self.badge.frame)) ||
      (!self.rail.hidden && NSPointInRect(point, self.rail.frame))) {
    return [super hitTest:point];
  }
  return nil;
}

- (NSArray*)accessibilityChildren {
  if (!self.rail.hidden) return @[ self.rail ];
  if (!self.badge.hidden) return @[ self.badge ];
  return @[];
}

- (void)applyProjection:(DtnParsedProjection)projection
                  cards:(NSArray<DtnCardModel*>*)cards {
  self.projection = projection;
  self.models = cards;
  for (NSView* view in self.cardList.subviews.copy) {
    [view removeFromSuperview];
  }
  NSMutableArray<DtnNoteCardView*>* card_views =
      [[NSMutableArray alloc] init];
  const NSUInteger materialized =
      cards.count < DTN_MAX_MATERIALIZED_CARDS
          ? cards.count
          : DTN_MAX_MATERIALIZED_CARDS;
  const BOOL dark = (projection.projection_flags & (1u << 2)) != 0u;
  const BOOL contrast = (projection.projection_flags & (1u << 3)) != 0u;
  const BOOL japanese = projection.locale == 1u;
  const CGFloat font_points = projection.body_font_millipoints / 1000.0;
  for (NSUInteger index = 0; index < materialized; ++index) {
    DtnNoteCardView* card =
        [[DtnNoteCardView alloc] initWithFrame:NSZeroRect];
    [card applyModel:cards[index]
                dark:dark
       bodyFontPoints:font_points
    increaseContrast:contrast
       japaneseLocale:japanese];
    card.layer.contentsScale = self.backingScale;
    [card setAccessibilityLabel:japanese
              ? [NSString stringWithFormat:@"ノート %lu / %u",
                                           (unsigned long)index + 1,
                                           projection.total_count]
              : [NSString stringWithFormat:@"Note %lu of %u",
                                           (unsigned long)index + 1,
                                           projection.total_count]];
    [self.cardList addSubview:card];
    [card_views addObject:card];
  }
  self.cardViews = card_views;
  self.badge.readyCue = (projection.projection_flags & (1u << 1)) != 0u;
  self.badge.darkAppearance = dark;
  self.badge.title = projection.active_count > 99u
                         ? @"99+"
                         : [NSString stringWithFormat:@"%u",
                                                       projection.active_count];
  [self.badge setAccessibilityHelp:japanese ? @"ノートを表示" : @"Show Notes"];
  [self.badge setAccessibilityLabel:japanese
                  ? [NSString stringWithFormat:@"ノート、有効%u件、準備完了%u件",
                                               projection.active_count,
                                               projection.due_count]
                  : [NSString stringWithFormat:@"Notes, %u active, %u ready",
                                               projection.active_count,
                                               projection.due_count]];
  self.rail.darkAppearance = dark;
  self.rail.increaseContrast = contrast;
  [self.rail setAccessibilityLabel:japanese ? @"ノート" : @"Notes"];
  self.titleLabel.stringValue = japanese ? @"ノート" : @"Notes";
  [self.sectionControl setLabel:japanese ? @"現在" : @"Current" forSegment:0];
  [self.sectionControl setLabel:japanese ? @"切り離し" : @"Detached"
                     forSegment:1];
  self.titleLabel.textColor =
      DtnColor(dark ? 0xf5f5f5ffu : 0x1f1f1fffu);
  self.sectionControl.selectedSegment = projection.section;
  self.animationMilliseconds =
      (projection.projection_flags & (1u << 5)) != 0u ? 0u : 140u;
  self.visibleAcknowledgementEligibleGeneration = 0u;
  [self layoutPresentation];
}

- (void)applyLayout:(DtnLayoutV1)layout {
  self.frame = NSMakeRect(0, 0, layout.pane_width, layout.pane_height);
  self.backingScale = layout.backing_scale;
  self.layer.contentsScale = layout.backing_scale;
  self.badge.layer.contentsScale = layout.backing_scale;
  self.rail.layer.contentsScale = layout.backing_scale;
  for (DtnNoteCardView* card in self.cardViews) {
    card.layer.contentsScale = layout.backing_scale;
  }
  self.requestedRailWidth = layout.requested_rail_width == 0
                                ? 320
                                : layout.requested_rail_width;
  [self layoutPresentation];
}

- (void)layout {
  [super layout];
  [self layoutPresentation];
}

- (void)layoutPresentation {
  const CGFloat width = self.bounds.size.width;
  const CGFloat height = self.bounds.size.height;
  self.smallPane = width < 264 || height < 184;
  const BOOL available =
      self.projection.feature_state == DTN_FEATURE_AVAILABLE;
  const BOOL badge_visible =
      self.projection.active_count > 0u || !available || self.smallPane;
  const BOOL eligible = self.projection.presentation_eligible != 0u;
  const BOOL rail_visible =
      available && eligible && !self.smallPane &&
      self.projection.visibility == DTN_VISIBILITY_EXPANDED;
  self.badge.hidden = !badge_visible;
  if (self.smallPane) {
    self.badge.title = @"!";
    [self.badge setAccessibilityLabel:self.projection.locale == 1u
                    ? @"ノート、ペインが小さすぎます"
                    : @"Notes, pane too small"];
  } else if (!available) {
    self.badge.title = @"!";
    [self.badge setAccessibilityLabel:self.projection.locale == 1u
                    ? @"ノートを利用できません"
                    : @"Notes unavailable"];
  } else {
    self.badge.title = self.projection.active_count > 99u
                           ? @"99+"
                           : [NSString
                                 stringWithFormat:@"%u",
                                                  self.projection.active_count];
    [self.badge setAccessibilityLabel:self.projection.locale == 1u
                    ? [NSString stringWithFormat:@"ノート、有効%u件、準備完了%u件",
                                                 self.projection.active_count,
                                                 self.projection.due_count]
                    : [NSString stringWithFormat:@"Notes, %u active, %u ready",
                                                 self.projection.active_count,
                                                 self.projection.due_count]];
  }
  self.badge.frame = NSMakeRect(fmax(0, width - 8 - 44),
                                fmax(0, (height - 44) / 2), 44, 44);
  [self.badge setAccessibilityElement:badge_visible && !rail_visible];
  const BOOL system_badge =
      (self.projection.projection_flags & (1u << 6)) != 0u;
  const CGFloat top = 12 + (system_badge ? 48 : 0);
  const CGFloat maximum = fmin(360, fmax(0, width - 24));
  const CGFloat rail_width =
      fmin(maximum, fmax(240, self.requestedRailWidth));
  self.rail.frame = NSMakeRect(fmax(12, width - 12 - rail_width), top,
                               rail_width, fmax(0, height - top - 12));
  self.rail.hidden = !rail_visible;
  self.toolbar.frame = NSMakeRect(12, 10, fmax(0, rail_width - 24), 44);
  self.titleLabel.frame = NSMakeRect(0, 0, 72, 20);
  self.sectionControl.frame =
      NSMakeRect(fmax(76, rail_width - 24 - 160), 0, 160, 24);
  self.scrollView.frame =
      NSMakeRect(12, 62, fmax(0, rail_width - 24),
                 fmax(0, self.rail.bounds.size.height - 74));
  CGFloat card_y = 0;
  const CGFloat card_width = fmax(0, self.scrollView.bounds.size.width - 12);
  for (DtnNoteCardView* card in self.cardViews) {
    const CGFloat font_points = self.projection.body_font_millipoints / 1000.0;
    NSDictionary* attributes = @{
      NSFontAttributeName : [NSFont systemFontOfSize:font_points],
    };
    NSRect measured = [card.model.body
        boundingRectWithSize:NSMakeSize(fmax(1, card_width - 24),
                                         font_points * 8 * 1.35)
                    options:NSStringDrawingUsesLineFragmentOrigin |
                            NSStringDrawingTruncatesLastVisibleLine
                 attributes:attributes];
    const CGFloat card_height =
        fmin(220, fmax(88, ceil(measured.size.height) + 52));
    card.frame = NSMakeRect(0, card_y, card_width, card_height);
    [card setNeedsLayout:YES];
    card_y += card_height + 12;
  }
  self.cardList.frame = NSMakeRect(
      0, 0, card_width, fmax(self.scrollView.bounds.size.height, card_y));
  self.accessibilityBodyCount = rail_visible ? (uint32_t)self.cardViews.count : 0;
  self.accessibilityNodeCount =
      rail_visible ? 5u + (uint32_t)self.cardViews.count * 3u
                   : (badge_visible ? 1u : 0u);
  [self reconcileReadyAnnouncement];
  [self.badge setNeedsDisplay:YES];
  [self.rail setNeedsDisplay:YES];
}

- (void)reconcileReadyAnnouncement {
  const BOOL visible_ready = !self.rail.hidden &&
      self.projection.due_count > 0u &&
      (self.projection.projection_flags & (1u << 1)) != 0u;
  if (!visible_ready) {
    self.visibleAcknowledgementEligibleGeneration = 0u;
    return;
  }
  self.visibleAcknowledgementEligibleGeneration =
      self.projection.projection_generation;
  if (self.lastAnnouncedGeneration == self.projection.projection_generation) {
    return;
  }
  self.lastAnnouncedGeneration = self.projection.projection_generation;
  ++self.accessibilityAnnouncementCount;
  NSString* announcement = self.projection.locale == 1u
      ? [NSString stringWithFormat:@"%u件のノートが準備できました",
                                   self.projection.due_count]
      : [NSString stringWithFormat:@"%u notes ready",
                                   self.projection.due_count];
  NSAccessibilityPostNotificationWithUserInfo(
      self, NSAccessibilityAnnouncementRequestedNotification,
      @{NSAccessibilityAnnouncementKey : announcement,
        NSAccessibilityPriorityKey : @(NSAccessibilityPriorityMedium)});
}

@end

struct DtnSurface {
  NSLock* lock;
  DtnNoteSurfaceView* view;
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

static NSArray<DtnCardModel*>* dtn_build_card_models(const uint8_t* bytes,
                                                      size_t length) {
  if (bytes == NULL || length < DTN_PROJECTION_HEADER_BYTES) return nil;
  const uint32_t card_count = dtn_read_u32(bytes + 64u);
  const uint32_t body_offset = dtn_read_u32(bytes + 76u);
  NSMutableArray<DtnCardModel*>* models =
      [[NSMutableArray alloc] initWithCapacity:card_count];
  for (uint32_t index = 0; index < card_count; ++index) {
    const uint8_t* record =
        bytes + DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    const uint32_t relative_offset = dtn_read_u32(record + 8u);
    const uint32_t body_length = dtn_read_u32(record + 12u);
    if ((size_t)body_offset + relative_offset + body_length > length) return nil;
    NSString* body = [[NSString alloc]
        initWithBytes:bytes + body_offset + relative_offset
               length:body_length
             encoding:NSUTF8StringEncoding];
    if (body == nil) return nil;
    DtnCardModel* model = [[DtnCardModel alloc] init];
    model.token = dtn_read_u64(record);
    model.body = body;
    model.order = dtn_read_u32(record + 16u);
    model.color = record[20u];
    model.status = record[21u];
    model.triggerKind = record[22u];
    model.triggerPhase = record[23u];
    model.due = (dtn_read_u32(record + 24u) & kDtnCardFlagDue) != 0u;
    [models addObject:model];
  }
  return models;
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
  const uint16_t locale = dtn_read_u16(bytes + 86u);
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
      message_key > 5u || locale > 1u ||
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
  output->locale = locale;
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
  if (![NSThread isMainThread]) return NULL;
  DtnSurface* surface = calloc(1u, sizeof(DtnSurface));
  if (surface == NULL) return NULL;
  surface->lock = [[NSLock alloc] init];
  surface->view = [[DtnNoteSurfaceView alloc] initWithFrame:NSZeroRect];
  if (surface->lock == nil || surface->view == nil) {
    surface->lock = nil;
    surface->view = nil;
    free(surface);
    return NULL;
  }
  atomic_fetch_add_explicit(&g_live_surfaces, 1u, memory_order_relaxed);
  return surface;
}

int32_t dtn_surface_apply_projection(DtnSurface* surface, const uint8_t* bytes,
                                     size_t length) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  DtnParsedProjection parsed = {0};
  const int32_t status = dtn_parse_projection(bytes, length, &parsed);
  NSArray<DtnCardModel*>* card_models =
      status == DTN_STATUS_OK ? dtn_build_card_models(bytes, length) : nil;
  [surface->lock lock];
  if (status != DTN_STATUS_OK || card_models == nil) {
    ++surface->rejected_projection_count;
    [surface->lock unlock];
    return status == DTN_STATUS_OK ? DTN_STATUS_INTERNAL : status;
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
  [surface->view applyProjection:parsed cards:card_models];
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
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
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
      (uint32_t)surface->view.cardViews.count;
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

int32_t dtn_surface_update_layout(DtnSurface* surface,
                                  const DtnLayoutV1* layout) {
  if (surface == NULL || layout == NULL ||
      layout->struct_size != sizeof(DtnLayoutV1) ||
      layout->version != DTN_LAYOUT_VERSION ||
      !isfinite(layout->pane_width) || !isfinite(layout->pane_height) ||
      !isfinite(layout->backing_scale) ||
      !isfinite(layout->requested_rail_width) || layout->pane_width <= 0 ||
      layout->pane_width > 4096 || layout->pane_height <= 0 ||
      layout->pane_height > 4096 ||
      (layout->backing_scale != 1.0 && layout->backing_scale != 2.0) ||
      (layout->requested_rail_width != 0 &&
       (layout->requested_rail_width < 240 ||
        layout->requested_rail_width > 360))) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  for (size_t index = 0; index < 8u; ++index) {
    if (layout->reserved[index] != 0u) return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  [surface->view applyLayout:*layout];
  return DTN_STATUS_OK;
}

int32_t dtn_surface_presentation_snapshot(
    DtnSurface* surface, DtnPresentationSnapshotV1* snapshot) {
  if (surface == NULL || snapshot == NULL ||
      snapshot->struct_size != sizeof(DtnPresentationSnapshotV1)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (snapshot->version != DTN_PRESENTATION_SNAPSHOT_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  DtnNoteSurfaceView* view = surface->view;
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->struct_size = sizeof(*snapshot);
  snapshot->version = DTN_PRESENTATION_SNAPSHOT_VERSION;
  snapshot->projection_generation = view.projection.projection_generation;
  snapshot->pane_width = view.bounds.size.width;
  snapshot->pane_height = view.bounds.size.height;
  snapshot->backing_scale = view.backingScale;
  const NSRect badge_hit = view.badge.frame;
  snapshot->badge_hit_x = badge_hit.origin.x;
  snapshot->badge_hit_y = badge_hit.origin.y;
  snapshot->badge_hit_width = badge_hit.size.width;
  snapshot->badge_hit_height = badge_hit.size.height;
  const NSRect badge_visual = NSMakeRect(badge_hit.origin.x,
                                         badge_hit.origin.y + 8,
                                         badge_hit.size.width, 28);
  snapshot->badge_visual_x = badge_visual.origin.x;
  snapshot->badge_visual_y = badge_visual.origin.y;
  snapshot->badge_visual_width = badge_visual.size.width;
  snapshot->badge_visual_height = badge_visual.size.height;
  const NSRect rail = view.rail.frame;
  snapshot->rail_x = rail.origin.x;
  snapshot->rail_y = rail.origin.y;
  snapshot->rail_width = rail.size.width;
  snapshot->rail_height = rail.size.height;
  if (view.cardViews.count > 0) {
    DtnNoteCardView* first = view.cardViews.firstObject;
    NSRect frame = [view convertRect:first.bounds fromView:first];
    snapshot->first_card_x = frame.origin.x;
    snapshot->first_card_y = frame.origin.y;
    snapshot->first_card_width = frame.size.width;
    snapshot->first_card_height = frame.size.height;
  }
  uint32_t flags = DTN_PRESENTATION_OPAQUE_CARDS;
  if (!view.badge.hidden) flags |= DTN_PRESENTATION_BADGE_VISIBLE;
  if (!view.rail.hidden) flags |= DTN_PRESENTATION_RAIL_VISIBLE;
  if (view.smallPane) flags |= DTN_PRESENTATION_SMALL_PANE;
  if ((view.projection.projection_flags & (1u << 1)) != 0u) {
    flags |= DTN_PRESENTATION_READY_CUE;
  }
  if ((view.projection.projection_flags & (1u << 3)) == 0u) {
    flags |= DTN_PRESENTATION_CARD_SHADOWS;
  } else {
    flags |= DTN_PRESENTATION_INCREASE_CONTRAST;
  }
  if ((view.projection.projection_flags & (1u << 2)) != 0u) {
    flags |= DTN_PRESENTATION_DARK;
  }
  if ((view.projection.projection_flags & (1u << 4)) != 0u) {
    flags |= DTN_PRESENTATION_DIFFERENTIATE_WITHOUT_COLOR;
  }
  if ((view.projection.projection_flags & (1u << 5)) != 0u) {
    flags |= DTN_PRESENTATION_REDUCED_MOTION;
  }
  if ((view.projection.projection_flags & (1u << 6)) != 0u) {
    flags |= DTN_PRESENTATION_SYSTEM_BADGE_VISIBLE;
  }
  if (view.projection.active_count > 99u) {
    flags |= DTN_PRESENTATION_BADGE_COUNT_CAPPED;
  }
  snapshot->flags = flags;
  snapshot->materialized_card_count = (uint32_t)view.cardViews.count;
  snapshot->accessibility_node_count = view.accessibilityNodeCount;
  snapshot->accessibility_body_count = view.accessibilityBodyCount;
  snapshot->visible_acknowledgement_eligible_generation =
      view.visibleAcknowledgementEligibleGeneration;
  snapshot->accessibility_announcement_count =
      view.accessibilityAnnouncementCount;
  snapshot->animation_milliseconds = view.animationMilliseconds;
  snapshot->body_font_millipoints = view.projection.body_font_millipoints;
  snapshot->badge_display_count =
      view.projection.active_count > 99u ? 99u : view.projection.active_count;
  return DTN_STATUS_OK;
}

void* dtn_surface_native_view(DtnSurface* surface) {
  if (surface == NULL || ![NSThread isMainThread]) return NULL;
  return (__bridge void*)surface->view;
}

int32_t dtn_surface_attach_to_host(DtnSurface* surface, void* host_view) {
  if (surface == NULL || host_view == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  id candidate = (__bridge id)host_view;
  if (![candidate isKindOfClass:NSView.class]) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  NSView* host = (NSView*)candidate;
  surface->view.frame = host.bounds;
  surface->view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [host addSubview:surface->view positioned:NSWindowAbove relativeTo:nil];
  [surface->view layoutPresentation];
  return DTN_STATUS_OK;
}

int32_t dtn_surface_detach_from_host(DtnSurface* surface) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  [surface->view removeFromSuperview];
  return DTN_STATUS_OK;
}

void dtn_surface_destroy(DtnSurface* surface) {
  if (surface == NULL) return;
  if ([NSThread isMainThread]) [surface->view removeFromSuperview];
  [surface->lock lock];
  uint8_t* packet = surface->packet;
  surface->packet = NULL;
  surface->packet_length = 0;
  [surface->lock unlock];
  free(packet);
  surface->view = nil;
  surface->lock = nil;
  free(surface);
  atomic_fetch_sub_explicit(&g_live_surfaces, 1u, memory_order_relaxed);
}

uint64_t dtn_debug_live_surfaces(void) {
  return atomic_load_explicit(&g_live_surfaces, memory_order_relaxed);
}
