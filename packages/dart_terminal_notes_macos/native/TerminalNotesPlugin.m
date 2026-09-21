#import "TerminalNotesPlugin.h"

#include <math.h>
#include <stdbool.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

static const uint8_t kDtnProjectionFlagPresentationEligible = 1u << 0;
static const uint8_t kDtnProjectionFlagOnReturnEnabled = 1u << 7;
static const uint8_t kDtnProjectionKnownFlags = 0xffu;
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
  uint64_t draft_generation;
  uint32_t projection_flags;
} DtnParsedProjection;

static bool dtn_valid_editor_string(NSString* value,
                                    bool require_non_whitespace);
static int32_t dtn_emit_view_intent(DtnSurface* surface, uint32_t kind,
                                    NSString* body, uint32_t color,
                                    uint64_t token);
static void dtn_notify_surface(DtnSurface* surface);
static bool dtn_intent_kind_commits(uint32_t kind);
static bool dtn_intent_kind_projects(uint32_t kind);
static const da_native_extension_services_v1* g_dtn_services = NULL;
static DtnSurfaceNotifyV1 g_dtn_surface_notify = NULL;

typedef void* (*DtnRendererNativeViewV1)(uint64_t handle,
                                         uint64_t generation);

static DtnRendererNativeViewV1 DtnRendererNativeViewResolver(void) {
  void* symbol = dlsym(RTLD_DEFAULT, "dtr_metal_renderer_native_view");
  if (symbol == NULL) {
    const uint32_t image_count = _dyld_image_count();
    for (uint32_t index = 0; index < image_count && symbol == NULL; ++index) {
      const char* path = _dyld_get_image_name(index);
      if (path == NULL) continue;
      const char* leaf = strrchr(path, '/');
      leaf = leaf == NULL ? path : leaf + 1;
      if (strcmp(leaf, "libdart_terminal_renderer_macos.dylib") != 0) {
        continue;
      }
      void* image = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_NOLOAD);
      if (image == NULL) continue;
      symbol = dlsym(image, "dtr_metal_renderer_native_view");
      dlclose(image);
    }
  }
  DtnRendererNativeViewV1 resolver = NULL;
  if (symbol != NULL) {
    memcpy(&resolver, &symbol, sizeof(resolver));
  }
  return resolver;
}

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
@property(nonatomic, strong) NSButton* editButton;
@property(nonatomic, strong) DtnCardModel* model;
@property(nonatomic, copy) void (^onSelect)(uint64_t token);
@property(nonatomic, copy) void (^onEdit)(uint64_t token);
@property(nonatomic) uint32_t surfaceRgba;
@property(nonatomic) uint32_t accentRgba;
@property(nonatomic) uint32_t bodyRgba;
@property(nonatomic) BOOL increaseContrast;
@property(nonatomic) BOOL interactionEnabled;
- (void)applyModel:(DtnCardModel*)model
              dark:(BOOL)dark
     bodyFontPoints:(CGFloat)bodyFontPoints
  increaseContrast:(BOOL)increaseContrast
     japaneseLocale:(BOOL)japaneseLocale
     reattachAction:(BOOL)reattachAction
            selected:(BOOL)selected;
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
    _editButton = [NSButton buttonWithTitle:@"Edit"
                                     target:self
                                     action:@selector(onEditPressed:)];
    [_editButton setAccessibilityElement:YES];
    [_editButton setAccessibilityRole:NSAccessibilityButtonRole];
    [self addSubview:_editButton];
    _interactionEnabled = YES;
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
  }
  return self;
}

- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSView*)hitTest:(NSPoint)point {
  NSView* hit = [super hitTest:point];
  if (hit == self.editButton || [hit isDescendantOf:self.editButton]) {
    return hit;
  }
  return NSPointInRect(point, self.bounds) ? self : nil;
}

- (void)mouseDown:(NSEvent*)event {
  (void)event;
  if (self.interactionEnabled && self.onSelect != nil && self.model != nil) {
    self.onSelect(self.model.token);
  }
}

- (void)keyDown:(NSEvent*)event {
  NSString* characters = event.charactersIgnoringModifiers;
  if (self.interactionEnabled && self.onSelect != nil && self.model != nil &&
      ([characters isEqualToString:@" "] ||
       [characters isEqualToString:@"\r"])) {
    self.onSelect(self.model.token);
    return;
  }
  [super keyDown:event];
}

- (BOOL)accessibilityPerformPress {
  if (!self.interactionEnabled || self.onSelect == nil || self.model == nil) {
    return NO;
  }
  self.onSelect(self.model.token);
  return YES;
}

- (NSArray*)accessibilityChildren {
  return @[ self.bodyLabel, self.chipLabel, self.editButton ];
}

- (void)onEditPressed:(id)sender {
  (void)sender;
  if (self.interactionEnabled && self.onEdit != nil && self.model != nil) {
    self.onEdit(self.model.token);
  }
}

- (void)applyModel:(DtnCardModel*)model
              dark:(BOOL)dark
     bodyFontPoints:(CGFloat)bodyFontPoints
  increaseContrast:(BOOL)increaseContrast
     japaneseLocale:(BOOL)japaneseLocale
     reattachAction:(BOOL)reattachAction
            selected:(BOOL)selected {
  self.model = model;
  self.surfaceRgba = DtnSurfaceRgba(model.color, dark);
  self.accentRgba = DtnAccentRgba(model.color, dark);
  self.bodyRgba = dark ? 0xf5f5f5ffu : 0x1f1f1fffu;
  self.increaseContrast = increaseContrast;
  self.layer.backgroundColor = DtnColor(self.surfaceRgba).CGColor;
  self.layer.borderColor = DtnColor(self.accentRgba).CGColor;
  self.layer.borderWidth = selected ? 3 : (increaseContrast ? 2 : 1);
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
  self.editButton.title = reattachAction
                              ? (japaneseLocale ? @"このターミナルへ接続"
                                                : @"Attach to This Terminal")
                              : (japaneseLocale ? @"編集" : @"Edit");
  [self.editButton setAccessibilityLabel:self.editButton.title];
  [self setNeedsDisplay:YES];
}

- (void)layout {
  [super layout];
  const CGFloat padding = 12;
  const CGFloat chipHeight = 16;
  const CGFloat buttonWidth = fmin(
      160, fmax(58, self.editButton.intrinsicContentSize.width + 16));
  self.chipLabel.frame = NSMakeRect(
      padding, self.bounds.size.height - padding - chipHeight,
      fmax(0, self.bounds.size.width - 2 * padding - buttonWidth - 6),
      chipHeight);
  self.editButton.frame = NSMakeRect(
      fmax(padding, self.bounds.size.width - padding - buttonWidth),
      self.bounds.size.height - padding - 24, buttonWidth, 24);
  self.bodyLabel.frame = NSMakeRect(
      padding, padding, fmax(0, self.bounds.size.width - 2 * padding),
      fmax(0, self.bounds.size.height - 3 * padding - chipHeight));
}

@end

@interface DtnPlainTextView : NSTextView
@property(nonatomic, copy) NSString* markedBaseline;
@property(nonatomic) NSRange markedBaselineSelection;
@property(nonatomic) NSRange markedReplacementRange;
- (BOOL)cancelMarkedTextRestoringBaseline;
- (void)commitMarkedText;
@end

@implementation DtnPlainTextView

- (NSArray<NSPasteboardType>*)readablePasteboardTypes {
  return @[ NSPasteboardTypeString ];
}

- (NSArray<NSPasteboardType>*)acceptableDragTypes {
  return @[ NSPasteboardTypeString ];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard*)pasteboard
                                type:(NSPasteboardType)type {
  if (![type isEqualToString:NSPasteboardTypeString]) return NO;
  return [super readSelectionFromPasteboard:pasteboard type:type];
}

- (void)setMarkedText:(id)string
         selectedRange:(NSRange)selectedRange
      replacementRange:(NSRange)replacementRange {
  if (!self.hasMarkedText) {
    self.markedBaseline = self.string;
    self.markedBaselineSelection = self.selectedRange;
    self.markedReplacementRange =
        replacementRange.location == NSNotFound ? self.selectedRange
                                                 : replacementRange;
  }
  [self.undoManager disableUndoRegistration];
  [super setMarkedText:string
         selectedRange:selectedRange
      replacementRange:replacementRange];
  [self.undoManager enableUndoRegistration];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
  if (self.markedBaseline != nil) {
    NSString* baseline = self.markedBaseline;
    const NSRange baseline_selection = self.markedBaselineSelection;
    const NSRange baseline_replacement = self.markedReplacementRange;
    [self.undoManager disableUndoRegistration];
    [super unmarkText];
    self.string = baseline;
    self.selectedRange = baseline_selection;
    [self.undoManager enableUndoRegistration];
    self.markedBaseline = nil;
    replacementRange = baseline_replacement;
  }
  [super insertText:string replacementRange:replacementRange];
}

- (void)unmarkText {
  if (self.markedBaseline != nil && self.hasMarkedText) {
    [self commitMarkedText];
    return;
  }
  [super unmarkText];
}

- (BOOL)cancelMarkedTextRestoringBaseline {
  if (!self.hasMarkedText || self.markedBaseline == nil) return NO;
  NSString* baseline = self.markedBaseline;
  const NSRange selection = self.markedBaselineSelection;
  [self.undoManager disableUndoRegistration];
  [super unmarkText];
  self.string = baseline;
  self.selectedRange = selection;
  [self.undoManager enableUndoRegistration];
  self.markedBaseline = nil;
  return YES;
}

- (void)commitMarkedText {
  if (!self.hasMarkedText || self.markedBaseline == nil) return;
  const NSRange marked = self.markedRange;
  NSString* committed = [self.string substringWithRange:marked];
  [self insertText:committed replacementRange:marked];
}

@end

@interface DtnNoteEditorView : DtnFlippedView <NSTextViewDelegate>
@property(nonatomic, strong) NSScrollView* textScrollView;
@property(nonatomic, strong) NSTextView* textView;
@property(nonatomic, strong) NSSegmentedControl* colorControl;
@property(nonatomic, strong) NSSegmentedControl* showControl;
@property(nonatomic, strong) NSButton* saveButton;
@property(nonatomic, strong) NSButton* cancelButton;
@property(nonatomic, strong) DtnFlippedView* discardConfirmation;
@property(nonatomic, strong) NSTextField* confirmationLabel;
@property(nonatomic, strong) NSButton* discardButton;
@property(nonatomic, strong) NSButton* keepEditingButton;
@property(nonatomic, strong) NSTextField* errorLabel;
@property(nonatomic, copy) void (^onInteractionChanged)(void);
@property(nonatomic, copy) NSString* baselineBody;
@property(nonatomic) uint32_t baselineColor;
@property(nonatomic) uint32_t baselineShowTiming;
@property(nonatomic) uint64_t draftGeneration;
@property(nonatomic) BOOL japaneseLocale;
- (void)beginDraft:(NSString*)body
             color:(uint32_t)color
        showTiming:(uint32_t)showTiming
   onReturnEnabled:(BOOL)onReturnEnabled
   draftGeneration:(uint64_t)draftGeneration
    bodyFontPoints:(CGFloat)bodyFontPoints
    japaneseLocale:(BOOL)japaneseLocale;
- (BOOL)isDirty;
- (BOOL)validateForSave;
- (void)showFixedError;
- (void)showDiscardConfirmation;
- (void)hideDiscardConfirmation;
- (void)clearDraft;
@end

@implementation DtnNoteEditorView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 1;
    _baselineBody = @"";
    _baselineColor = 1u;
    _textScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _textScrollView.hasVerticalScroller = YES;
    _textScrollView.drawsBackground = YES;
    _textView = [[DtnPlainTextView alloc] initWithFrame:NSZeroRect];
    _textView.richText = NO;
    _textView.importsGraphics = NO;
    _textView.allowsUndo = YES;
    _textView.automaticQuoteSubstitutionEnabled = NO;
    _textView.automaticDashSubstitutionEnabled = NO;
    _textView.automaticTextReplacementEnabled = NO;
    _textView.delegate = self;
    [_textView setAccessibilityLabel:@"Note body"];
    _textScrollView.documentView = _textView;
    [self addSubview:_textScrollView];

    _colorControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _colorControl.segmentCount = 6;
    NSArray<NSString*>* swatches = @[ @"N", @"Y", @"B", @"G", @"P", @"V" ];
    for (NSInteger index = 0; index < 6; ++index) {
      [_colorControl setLabel:swatches[index] forSegment:index];
      [_colorControl setWidth:30 forSegment:index];
    }
    [_colorControl setAccessibilityLabel:@"Note color"];
    [_colorControl setAccessibilityElement:YES];
    [_colorControl setAccessibilityRole:NSAccessibilityRadioGroupRole];
    [self addSubview:_colorControl];

    _showControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _showControl.segmentCount = 2;
    [_showControl setLabel:@"Always" forSegment:0];
    [_showControl setLabel:@"On Return" forSegment:1];
    _showControl.selectedSegment = 0;
    [_showControl setAccessibilityLabel:@"Show note"];
    [_showControl setAccessibilityElement:YES];
    [_showControl setAccessibilityRole:NSAccessibilityRadioGroupRole];
    [self addSubview:_showControl];

    _saveButton = [NSButton buttonWithTitle:@"Save" target:nil action:nil];
    _saveButton.keyEquivalent = @"\r";
    _saveButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [_saveButton setAccessibilityElement:YES];
    [_saveButton setAccessibilityRole:NSAccessibilityButtonRole];
    [self addSubview:_saveButton];
    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:nil action:nil];
    [_cancelButton setAccessibilityElement:YES];
    [_cancelButton setAccessibilityRole:NSAccessibilityButtonRole];
    [self addSubview:_cancelButton];
    _errorLabel = [NSTextField labelWithString:@""];
    _errorLabel.textColor = NSColor.systemRedColor;
    _errorLabel.hidden = YES;
    [_errorLabel setAccessibilityElement:YES];
    [_errorLabel setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self addSubview:_errorLabel];

    _discardConfirmation = [[DtnFlippedView alloc] initWithFrame:NSZeroRect];
    _discardConfirmation.wantsLayer = YES;
    _discardConfirmation.layer.cornerRadius = 8;
    _discardConfirmation.layer.backgroundColor =
        NSColor.windowBackgroundColor.CGColor;
    [_discardConfirmation setAccessibilityElement:YES];
    [_discardConfirmation setAccessibilityRole:NSAccessibilityGroupRole];
    _confirmationLabel = [NSTextField labelWithString:@"Discard changes?"];
    [_discardConfirmation addSubview:_confirmationLabel];
    _discardButton =
        [NSButton buttonWithTitle:@"Discard" target:nil action:nil];
    [_discardButton setAccessibilityElement:YES];
    [_discardButton setAccessibilityRole:NSAccessibilityButtonRole];
    [_discardConfirmation addSubview:_discardButton];
    _keepEditingButton =
        [NSButton buttonWithTitle:@"Keep Editing" target:nil action:nil];
    [_keepEditingButton setAccessibilityElement:YES];
    [_keepEditingButton setAccessibilityRole:NSAccessibilityButtonRole];
    [_discardConfirmation addSubview:_keepEditingButton];
    _discardConfirmation.hidden = YES;
    [self addSubview:_discardConfirmation];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
    [self setAccessibilityLabel:@"Note editor"];
  }
  return self;
}

- (BOOL)isOpaque { return YES; }

- (void)beginDraft:(NSString*)body
             color:(uint32_t)color
        showTiming:(uint32_t)showTiming
   onReturnEnabled:(BOOL)onReturnEnabled
   draftGeneration:(uint64_t)draftGeneration
    bodyFontPoints:(CGFloat)bodyFontPoints
    japaneseLocale:(BOOL)japaneseLocale {
  if (self.textView.hasMarkedText) {
    [(DtnPlainTextView*)self.textView cancelMarkedTextRestoringBaseline];
  }
  self.japaneseLocale = japaneseLocale;
  self.baselineBody = body;
  self.baselineColor = color;
  self.baselineShowTiming = showTiming;
  self.draftGeneration = draftGeneration;
  [self.textView.undoManager disableUndoRegistration];
  self.textView.string = body;
  [self.textView.undoManager enableUndoRegistration];
  [self.textView.undoManager removeAllActions];
  self.textView.font = [NSFont systemFontOfSize:bodyFontPoints];
  self.colorControl.selectedSegment = color;
  self.showControl.hidden = !onReturnEnabled;
  self.showControl.selectedSegment = showTiming;
  self.textView.selectedRange = NSMakeRange(body.length, 0);
  self.errorLabel.hidden = YES;
  [self hideDiscardConfirmation];
  if (japaneseLocale) {
    [self setAccessibilityLabel:@"ノートエディタ"];
    [self.textView setAccessibilityLabel:@"ノート本文"];
    [self.colorControl setAccessibilityLabel:@"ノートの色"];
    [self.showControl setAccessibilityLabel:@"ノートを表示するタイミング"];
    [self.showControl setLabel:@"常に表示" forSegment:0];
    [self.showControl setLabel:@"Return時" forSegment:1];
    self.saveButton.title = @"保存";
    self.cancelButton.title = @"キャンセル";
    self.confirmationLabel.stringValue = @"変更を破棄しますか？";
    self.discardButton.title = @"破棄";
    self.keepEditingButton.title = @"編集を続ける";
  } else {
    [self setAccessibilityLabel:@"Note editor"];
    [self.textView setAccessibilityLabel:@"Note body"];
    [self.colorControl setAccessibilityLabel:@"Note color"];
    [self.showControl setAccessibilityLabel:@"Show note"];
    [self.showControl setLabel:@"Always" forSegment:0];
    [self.showControl setLabel:@"On Return" forSegment:1];
    self.saveButton.title = @"Save";
    self.cancelButton.title = @"Cancel";
    self.confirmationLabel.stringValue = @"Discard changes?";
    self.discardButton.title = @"Discard";
    self.keepEditingButton.title = @"Keep Editing";
  }
}

- (BOOL)isDirty {
  return ![self.textView.string isEqualToString:self.baselineBody] ||
         self.colorControl.selectedSegment != self.baselineColor ||
         (!self.showControl.hidden &&
          self.showControl.selectedSegment != self.baselineShowTiming);
}

- (BOOL)validateForSave {
  if ([self.textView hasMarkedText]) {
    [(DtnPlainTextView*)self.textView commitMarkedText];
  }
  if (!dtn_valid_editor_string(self.textView.string, true)) {
    [self showFixedError];
    return NO;
  }
  return YES;
}

- (void)showFixedError {
  self.errorLabel.stringValue = self.japaneseLocale
                                    ? @"ノート本文を保存できません"
                                    : @"Note body cannot be saved";
  self.errorLabel.hidden = NO;
}

- (void)showDiscardConfirmation {
  self.discardConfirmation.hidden = NO;
  self.textView.editable = NO;
}

- (void)hideDiscardConfirmation {
  self.discardConfirmation.hidden = YES;
  self.textView.editable = YES;
}

- (void)clearDraft {
  if (self.textView.hasMarkedText) {
    [(DtnPlainTextView*)self.textView cancelMarkedTextRestoringBaseline];
  }
  [self.textView.undoManager disableUndoRegistration];
  self.textView.string = @"";
  [self.textView.undoManager enableUndoRegistration];
  [self.textView.undoManager removeAllActions];
  self.baselineBody = @"";
  self.baselineShowTiming = 0u;
  self.showControl.selectedSegment = 0;
  self.draftGeneration = 0u;
  self.errorLabel.hidden = YES;
  [self hideDiscardConfirmation];
}

- (BOOL)textView:(NSTextView*)textView
    shouldChangeTextInRange:(NSRange)affectedCharRange
          replacementString:(NSString*)replacementString {
  (void)textView;
  if (replacementString == nil ||
      NSMaxRange(affectedCharRange) > self.textView.string.length) {
    [self showFixedError];
    return NO;
  }
  NSString* candidate =
      [self.textView.string stringByReplacingCharactersInRange:affectedCharRange
                                                    withString:replacementString];
  if (!dtn_valid_editor_string(candidate, false)) {
    [self showFixedError];
    return NO;
  }
  self.errorLabel.hidden = YES;
  return YES;
}

- (void)textDidChange:(NSNotification*)notification {
  (void)notification;
  self.errorLabel.hidden = YES;
  if (self.onInteractionChanged != nil) self.onInteractionChanged();
}

- (BOOL)textView:(NSTextView*)textView
    doCommandBySelector:(SEL)commandSelector {
  if (commandSelector != @selector(cancelOperation:)) return NO;
  if (textView.hasMarkedText) {
    [(DtnPlainTextView*)textView cancelMarkedTextRestoringBaseline];
    return YES;
  }
  [self.cancelButton performClick:nil];
  return YES;
}

- (NSArray*)accessibilityChildren {
  if (!self.discardConfirmation.hidden) {
    return @[
      self.confirmationLabel, self.keepEditingButton, self.discardButton
    ];
  }
  NSMutableArray* children = [NSMutableArray
      arrayWithObjects:self.textScrollView, self.showControl,
                       self.colorControl, self.saveButton, self.cancelButton,
                       nil];
  if (self.showControl.hidden) [children removeObject:self.showControl];
  if (!self.errorLabel.hidden) [children addObject:self.errorLabel];
  return children;
}

- (void)layout {
  [super layout];
  const CGFloat width = self.bounds.size.width;
  const CGFloat height = self.bounds.size.height;
  self.showControl.frame = NSMakeRect(10, 10, fmax(0, width - 20), 26);
  self.colorControl.frame = NSMakeRect(10, self.showControl.hidden ? 10 : 40,
                                       fmax(0, width - 20), 26);
  const CGFloat editor_top = self.showControl.hidden ? 44 : 74;
  self.textScrollView.frame =
      NSMakeRect(10, editor_top, fmax(0, width - 20),
                 fmax(60, height - editor_top - 68));
  self.errorLabel.frame =
      NSMakeRect(10, fmax(44, height - 62), fmax(0, width - 20), 18);
  self.cancelButton.frame =
      NSMakeRect(fmax(10, width - 174), fmax(44, height - 36), 76, 26);
  self.saveButton.frame =
      NSMakeRect(fmax(92, width - 92), fmax(44, height - 36), 82, 26);
  self.discardConfirmation.frame =
      NSMakeRect(10, fmax(44, height - 112), fmax(0, width - 20), 102);
  self.confirmationLabel.frame =
      NSMakeRect(10, 10, fmax(0, width - 20), 20);
  self.keepEditingButton.frame =
      NSMakeRect(10, 50, fmax(92, width / 2 - 15), 28);
  self.discardButton.frame =
      NSMakeRect(width / 2 + 5, 50, fmax(76, width / 2 - 15), 28);
}

@end

@interface DtnNoteSurfaceView : DtnFlippedView
@property(nonatomic, strong) DtnNoteBadgeButton* badge;
@property(nonatomic, strong) DtnOpaqueRailView* rail;
@property(nonatomic, strong) DtnFlippedView* toolbar;
@property(nonatomic, strong) NSTextField* titleLabel;
@property(nonatomic, strong) NSSegmentedControl* sectionControl;
@property(nonatomic, strong) NSButton* createButton;
@property(nonatomic, strong) NSButton* closeButton;
@property(nonatomic, strong) DtnFlippedView* pagingBar;
@property(nonatomic, strong) NSButton* previousPageButton;
@property(nonatomic, strong) NSTextField* pageRangeLabel;
@property(nonatomic, strong) NSButton* nextPageButton;
@property(nonatomic, strong) DtnFlippedView* actionBar;
@property(nonatomic, copy) NSArray<NSButton*>* actionButtons;
@property(nonatomic, strong) NSSegmentedControl* cardColorControl;
@property(nonatomic, strong) NSSegmentedControl* cardShowControl;
@property(nonatomic, strong) NSButton* rearmButton;
@property(nonatomic, strong) NSScrollView* scrollView;
@property(nonatomic, strong) DtnFlippedView* cardList;
@property(nonatomic, strong) DtnNoteEditorView* editor;
@property(nonatomic, assign) DtnSurface* nativeSurface;
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
@property(nonatomic) BOOL locallyClosedEditor;
@property(nonatomic) BOOL deleteConfirmationArmed;
- (void)applyProjection:(DtnParsedProjection)projection
                  cards:(NSArray<DtnCardModel*>*)cards;
- (void)applyLayout:(DtnLayoutV1)layout;
- (void)layoutPresentation;
- (void)reconcileReadyAnnouncement;
- (void)applySemanticResult:(DtnSurfaceResultV1)result
                 intentKind:(uint32_t)intentKind;
- (void)setSemanticControlsEnabled:(BOOL)enabled;
- (uint32_t)focusTarget;
- (int32_t)focusInsideSurface:(uint32_t)target;
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
    _sectionControl.target = self;
    _sectionControl.action = @selector(onSection:);
    [_toolbar addSubview:_sectionControl];
    _createButton = [NSButton buttonWithTitle:@"New"
                                       target:self
                                       action:@selector(onNew:)];
    [_createButton setAccessibilityElement:YES];
    [_createButton setAccessibilityRole:NSAccessibilityButtonRole];
    [_toolbar addSubview:_createButton];
    _closeButton = [NSButton buttonWithTitle:@"Close"
                                      target:self
                                      action:@selector(onClose:)];
    [_closeButton setAccessibilityElement:YES];
    [_closeButton setAccessibilityRole:NSAccessibilityButtonRole];
    [_toolbar addSubview:_closeButton];
    [_toolbar setAccessibilityChildren:@[
      _titleLabel, _sectionControl, _createButton, _closeButton
    ]];
    _pagingBar = [[DtnFlippedView alloc] initWithFrame:NSZeroRect];
    [_pagingBar setAccessibilityElement:YES];
    [_pagingBar setAccessibilityRole:NSAccessibilityGroupRole];
    [_rail addSubview:_pagingBar];
    _previousPageButton = [NSButton buttonWithTitle:@"Previous"
                                             target:self
                                             action:@selector(onPreviousPage:)];
    _pageRangeLabel = [NSTextField labelWithString:@"0–0 of 0"];
    _pageRangeLabel.alignment = NSTextAlignmentCenter;
    [_pageRangeLabel setAccessibilityElement:YES];
    [_pageRangeLabel setAccessibilityRole:NSAccessibilityStaticTextRole];
    _nextPageButton = [NSButton buttonWithTitle:@"Next"
                                         target:self
                                         action:@selector(onNextPage:)];
    for (NSButton* button in @[ _previousPageButton, _nextPageButton ]) {
      [button setAccessibilityElement:YES];
      [button setAccessibilityRole:NSAccessibilityButtonRole];
      [_pagingBar addSubview:button];
    }
    [_pagingBar addSubview:_pageRangeLabel];
    [_pagingBar setAccessibilityChildren:@[
      _previousPageButton, _pageRangeLabel, _nextPageButton
    ]];
    _badge.target = self;
    _badge.action = @selector(onOpen:);
    _actionBar = [[DtnFlippedView alloc] initWithFrame:NSZeroRect];
    [_actionBar setAccessibilityElement:YES];
    [_actionBar setAccessibilityRole:NSAccessibilityToolbarRole];
    [_rail addSubview:_actionBar];
    NSButton* earlier =
        [NSButton buttonWithTitle:@"Earlier" target:self action:@selector(onEarlier:)];
    NSButton* later =
        [NSButton buttonWithTitle:@"Later" target:self action:@selector(onLater:)];
    NSButton* resolve =
        [NSButton buttonWithTitle:@"Resolve" target:self action:@selector(onResolve:)];
    NSButton* reopen =
        [NSButton buttonWithTitle:@"Reopen" target:self action:@selector(onReopen:)];
    NSButton* delete_note =
        [NSButton buttonWithTitle:@"Delete…" target:self action:@selector(onDelete:)];
    NSButton* reattach =
        [NSButton buttonWithTitle:@"Reattach" target:self action:@selector(onReattach:)];
    NSButton* export_notes =
        [NSButton buttonWithTitle:@"Export" target:self action:@selector(onExport:)];
    NSButton* copy_note =
        [NSButton buttonWithTitle:@"Copy" target:self action:@selector(onCopy:)];
    _actionButtons = @[ earlier, later, resolve, reopen, delete_note,
                        reattach, export_notes, copy_note ];
    for (NSButton* button in _actionButtons) {
      [button setAccessibilityElement:YES];
      [button setAccessibilityRole:NSAccessibilityButtonRole];
      [_actionBar addSubview:button];
    }
    _cardColorControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _cardColorControl.segmentCount = 6;
    NSArray<NSString*>* card_swatches = @[ @"N", @"Y", @"B", @"G", @"P", @"V" ];
    for (NSInteger index = 0; index < 6; ++index) {
      [_cardColorControl setLabel:card_swatches[index] forSegment:index];
      [_cardColorControl setWidth:30 forSegment:index];
    }
    [_cardColorControl setAccessibilityLabel:@"Note color"];
    [_cardColorControl setAccessibilityElement:YES];
    [_cardColorControl setAccessibilityRole:NSAccessibilityRadioGroupRole];
    _cardColorControl.target = self;
    _cardColorControl.action = @selector(onCardColor:);
    [_actionBar addSubview:_cardColorControl];
    _cardShowControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _cardShowControl.segmentCount = 2;
    [_cardShowControl setLabel:@"Always" forSegment:0];
    [_cardShowControl setLabel:@"On Return" forSegment:1];
    _cardShowControl.selectedSegment = 0;
    [_cardShowControl setAccessibilityLabel:@"Show selected note"];
    [_cardShowControl setAccessibilityElement:YES];
    [_cardShowControl setAccessibilityRole:NSAccessibilityRadioGroupRole];
    _cardShowControl.target = self;
    _cardShowControl.action = @selector(onCardShow:);
    [_actionBar addSubview:_cardShowControl];
    _rearmButton = [NSButton buttonWithTitle:@"Re-arm"
                                      target:self
                                      action:@selector(onRearm:)];
    [_rearmButton setAccessibilityElement:YES];
    [_rearmButton setAccessibilityRole:NSAccessibilityButtonRole];
    [_actionBar addSubview:_rearmButton];
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
    _editor = [[DtnNoteEditorView alloc] initWithFrame:NSZeroRect];
    _editor.hidden = YES;
    _editor.saveButton.target = self;
    _editor.saveButton.action = @selector(onSave:);
    _editor.cancelButton.target = self;
    _editor.cancelButton.action = @selector(onCancel:);
    _editor.colorControl.target = self;
    _editor.colorControl.action = @selector(onDraftColor:);
    _editor.showControl.target = self;
    _editor.showControl.action = @selector(onDraftShow:);
    _editor.discardButton.target = self;
    _editor.discardButton.action = @selector(onDiscard:);
    _editor.keepEditingButton.target = self;
    _editor.keepEditingButton.action = @selector(onKeepEditing:);
    __weak DtnNoteSurfaceView* weak_self = self;
    _editor.onInteractionChanged = ^{
      dtn_notify_surface(weak_self.nativeSurface);
    };
    [_rail addSubview:_editor];
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

- (DtnCardModel*)selectedModel {
  for (DtnCardModel* model in self.models) {
    if (model.token == self.projection.selected_token) return model;
  }
  return nil;
}

- (void)onOpen:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_OPEN body:nil color:DTN_NO_COLOR token:0u];
}

- (void)onClose:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_CLOSE body:nil color:DTN_NO_COLOR token:0u];
}

- (void)onNew:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_BEGIN_CREATE
               body:nil
              color:DTN_NO_COLOR
              token:0u];
}

- (void)onSection:(id)sender {
  (void)sender;
  const NSInteger requested = self.sectionControl.selectedSegment;
  self.sectionControl.selectedSegment = self.projection.section;
  if (requested == (NSInteger)self.projection.section) return;
  [self emitIntent:requested == DTN_SECTION_DETACHED
                       ? DTN_INTENT_SHOW_DETACHED
                       : DTN_INTENT_SHOW_CURRENT
               body:nil
              color:DTN_NO_COLOR
              token:0u];
}

- (void)onPreviousPage:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_PREVIOUS_PAGE
               body:nil
              color:DTN_NO_COLOR
              token:0u];
}

- (void)onNextPage:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_NEXT_PAGE
               body:nil
              color:DTN_NO_COLOR
              token:0u];
}

- (void)onSelectCardToken:(uint64_t)token {
  [self emitIntent:DTN_INTENT_SELECT_CARD
               body:nil
              color:DTN_NO_COLOR
              token:token];
}

- (void)onEditCardToken:(uint64_t)token {
  [self emitIntent:DTN_INTENT_BEGIN_EDIT
               body:nil
              color:DTN_NO_COLOR
              token:token];
}

- (void)resetDeleteConfirmation {
  self.deleteConfirmationArmed = NO;
  NSButton* button = self.actionButtons[4];
  button.title = self.projection.locale == 1u ? @"削除…" : @"Delete…";
}

- (int32_t)emitIntent:(uint32_t)kind
                 body:(NSString*)body
                color:(uint32_t)color
                token:(uint64_t)token {
  [self resetDeleteConfirmation];
  const int32_t status =
      dtn_emit_view_intent(self.nativeSurface, kind, body, color, token);
  if (status == DTN_STATUS_OK) {
    [self setSemanticControlsEnabled:NO];
    dtn_notify_surface(self.nativeSurface);
  } else {
    [self.editor showFixedError];
  }
  return status;
}

- (void)onSave:(id)sender {
  (void)sender;
  if (![self.editor validateForSave]) return;
  uint32_t kind = DTN_INTENT_SAVE;
  if (!self.editor.showControl.hidden) {
    kind = self.editor.showControl.selectedSegment == 1
               ? DTN_INTENT_SAVE_ON_RETURN
               : DTN_INTENT_SAVE_ALWAYS_AVAILABLE;
  }
  [self emitIntent:kind
               body:self.editor.textView.string
              color:(uint32_t)self.editor.colorControl.selectedSegment
              token:self.projection.selected_token];
}

- (void)onCancel:(id)sender {
  (void)sender;
  if (self.editor.isDirty) {
    [self.editor showDiscardConfirmation];
    dtn_notify_surface(self.nativeSurface);
    return;
  }
  [self emitIntent:DTN_INTENT_CANCEL
               body:nil
              color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onDiscard:(id)sender {
  (void)sender;
  [self.editor hideDiscardConfirmation];
  [self emitIntent:DTN_INTENT_CANCEL
               body:nil
              color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onKeepEditing:(id)sender {
  (void)sender;
  [self.editor hideDiscardConfirmation];
  [self.editor.textView.window makeFirstResponder:self.editor.textView];
  dtn_notify_surface(self.nativeSurface);
}

- (void)onDraftColor:(id)sender {
  (void)sender;
  self.editor.errorLabel.hidden = YES;
  const BOOL dark =
      (self.projection.projection_flags & (1u << 2)) != 0u;
  const uint32_t color =
      (uint32_t)self.editor.colorControl.selectedSegment;
  self.editor.layer.backgroundColor =
      DtnColor(DtnSurfaceRgba(color, dark)).CGColor;
  self.editor.layer.borderColor =
      DtnColor(DtnAccentRgba(color, dark)).CGColor;
  dtn_notify_surface(self.nativeSurface);
}

- (void)onDraftShow:(id)sender {
  (void)sender;
  self.editor.errorLabel.hidden = YES;
  dtn_notify_surface(self.nativeSurface);
}

- (void)onCardColor:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_CHANGE_COLOR
               body:nil
              color:(uint32_t)self.cardColorControl.selectedSegment
              token:self.projection.selected_token];
}

- (void)onCardShow:(id)sender {
  (void)sender;
  DtnCardModel* model = [self selectedModel];
  const NSInteger current = model != nil && model.triggerKind == 1u ? 1 : 0;
  const NSInteger requested = self.cardShowControl.selectedSegment;
  self.cardShowControl.selectedSegment = current;
  if (model == nil || model.status != 0u || model.triggerKind == 2u ||
      (self.projection.projection_flags &
       kDtnProjectionFlagOnReturnEnabled) == 0u ||
      requested == current) {
    return;
  }
  [self emitIntent:requested == 1 ? DTN_INTENT_ARM_ON_RETURN
                                  : DTN_INTENT_MAKE_ALWAYS_AVAILABLE
               body:nil
              color:DTN_NO_COLOR
              token:model.token];
}

- (void)onRearm:(id)sender {
  (void)sender;
  DtnCardModel* model = [self selectedModel];
  if (model == nil || model.status != 0u || model.triggerKind != 1u ||
      !model.due ||
      (self.projection.projection_flags &
       kDtnProjectionFlagOnReturnEnabled) == 0u) {
    return;
  }
  [self emitIntent:DTN_INTENT_ARM_ON_RETURN
               body:nil
              color:DTN_NO_COLOR
              token:model.token];
}

- (void)onEarlier:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_MOVE_EARLIER body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onLater:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_MOVE_LATER body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onResolve:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_RESOLVE body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onReopen:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_REOPEN body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onDelete:(id)sender {
  (void)sender;
  if (!self.deleteConfirmationArmed) {
    self.deleteConfirmationArmed = YES;
    NSButton* button = self.actionButtons[4];
    button.title = self.projection.locale == 1u ? @"削除を確認" : @"Confirm Delete";
    return;
  }
  [self emitIntent:DTN_INTENT_DELETE body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onReattach:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_REATTACH body:nil color:DTN_NO_COLOR
              token:self.projection.selected_token];
}

- (void)onExport:(id)sender {
  (void)sender;
  [self emitIntent:DTN_INTENT_EXPORT body:nil color:DTN_NO_COLOR token:0u];
}

- (void)onCopy:(id)sender {
  (void)sender;
  DtnCardModel* model = [self selectedModel];
  if (model == nil) return;
  [self emitIntent:DTN_INTENT_COPY body:model.body color:DTN_NO_COLOR
              token:model.token];
}

- (void)setSemanticControlsEnabled:(BOOL)enabled {
  self.badge.enabled = enabled;
  const BOOL navigation_enabled =
      enabled && self.projection.editor_mode == DTN_EDITOR_INACTIVE;
  self.sectionControl.enabled = navigation_enabled;
  self.createButton.enabled =
      navigation_enabled && self.projection.section == DTN_SECTION_CURRENT;
  self.closeButton.enabled = navigation_enabled;
  self.previousPageButton.enabled =
      navigation_enabled && self.projection.section == DTN_SECTION_DETACHED &&
      self.projection.page_start > 0u;
  self.nextPageButton.enabled =
      navigation_enabled && self.projection.section == DTN_SECTION_DETACHED &&
      self.projection.page_start + DTN_MAX_CARDS <
          self.projection.total_count;
  for (DtnNoteCardView* card in self.cardViews) {
    card.interactionEnabled = enabled;
    card.editButton.enabled = navigation_enabled;
  }
  if (!enabled) {
    for (NSButton* button in self.actionButtons) button.enabled = NO;
    self.cardColorControl.enabled = NO;
    self.cardShowControl.enabled = NO;
    self.rearmButton.enabled = NO;
  } else {
    DtnCardModel* selected = [self selectedModel];
    const BOOL has_selection = selected != nil;
    const BOOL current = self.projection.section == DTN_SECTION_CURRENT;
    self.actionButtons[0].enabled =
        has_selection && (current || selected.order > 0u);
    self.actionButtons[1].enabled =
        has_selection &&
        (current || selected.order < self.projection.total_count - 1u);
    self.actionButtons[2].enabled = current && has_selection && selected.status == 0u;
    self.actionButtons[3].enabled = current && has_selection && selected.status == 1u;
    self.actionButtons[4].enabled = current && has_selection;
    self.actionButtons[5].enabled =
        has_selection && self.projection.section == DTN_SECTION_DETACHED;
    self.actionButtons[6].enabled = YES;
    self.actionButtons[7].enabled = has_selection;
    self.cardColorControl.enabled = current && has_selection;
    const BOOL on_return_enabled =
        (self.projection.projection_flags &
         kDtnProjectionFlagOnReturnEnabled) != 0u;
    self.cardShowControl.enabled =
        on_return_enabled && current && has_selection &&
        selected.status == 0u && selected.triggerKind != 2u;
    self.rearmButton.enabled =
        self.cardShowControl.enabled && selected.triggerKind == 1u &&
        selected.due;
  }
  self.editor.saveButton.enabled = enabled;
  self.editor.cancelButton.enabled = enabled;
  self.editor.colorControl.enabled = enabled;
  self.editor.showControl.enabled = enabled;
  self.editor.discardButton.enabled = enabled;
  self.editor.keepEditingButton.enabled = enabled;
}

- (void)applySemanticResult:(DtnSurfaceResultV1)result
                 intentKind:(uint32_t)intentKind {
  (void)intentKind;
  [self setSemanticControlsEnabled:YES];
  if (result.disposition != DTN_RESULT_ACCEPTED) {
    if (!self.editor.hidden) [self.editor showFixedError];
  }
}

- (void)applyProjection:(DtnParsedProjection)projection
                  cards:(NSArray<DtnCardModel*>*)cards {
  const uint64_t previous_draft = self.editor.draftGeneration;
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
       japaneseLocale:japanese
       reattachAction:projection.section == DTN_SECTION_DETACHED
              selected:cards[index].token == projection.selected_token];
    __weak DtnNoteSurfaceView* weak_self = self;
    card.onSelect = ^(uint64_t token) {
      [weak_self onSelectCardToken:token];
    };
    card.onEdit = ^(uint64_t token) {
      if (projection.section == DTN_SECTION_DETACHED) {
        [weak_self emitIntent:DTN_INTENT_REATTACH
                         body:nil
                        color:DTN_NO_COLOR
                        token:token];
      } else {
        [weak_self onEditCardToken:token];
      }
    };
    card.layer.contentsScale = self.backingScale;
    [card setAccessibilityLabel:japanese
              ? [NSString stringWithFormat:@"ノート %lu / %u",
                                           (unsigned long)projection.page_start +
                                               index + 1,
                                           projection.total_count]
              : [NSString stringWithFormat:@"Note %lu of %u",
                                           (unsigned long)projection.page_start +
                                               index + 1,
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
  self.createButton.title = japanese ? @"新規" : @"New";
  self.closeButton.title = japanese ? @"閉じる" : @"Close";
  [self.createButton setAccessibilityLabel:self.createButton.title];
  [self.closeButton setAccessibilityLabel:self.closeButton.title];
  self.titleLabel.textColor =
      DtnColor(dark ? 0xf5f5f5ffu : 0x1f1f1fffu);
  self.sectionControl.selectedSegment = projection.section;
  self.pagingBar.hidden = projection.section != DTN_SECTION_DETACHED;
  self.previousPageButton.title = japanese ? @"前へ" : @"Previous";
  self.nextPageButton.title = japanese ? @"次へ" : @"Next";
  const uint32_t range_start = projection.total_count == 0u
                                   ? 0u
                                   : projection.page_start + 1u;
  const uint32_t range_end =
      projection.page_start + (uint32_t)cards.count < projection.total_count
          ? projection.page_start + (uint32_t)cards.count
          : projection.total_count;
  self.pageRangeLabel.stringValue = japanese
      ? [NSString stringWithFormat:@"%u〜%u / %u", range_start, range_end,
                                   projection.total_count]
      : [NSString stringWithFormat:@"%u–%u of %u", range_start, range_end,
                                   projection.total_count];
  [self.pageRangeLabel setAccessibilityLabel:self.pageRangeLabel.stringValue];
  NSArray<NSString*>* english_actions = @[
    @"Earlier", @"Later", @"Resolve", @"Reopen", @"Delete…", @"Reattach",
    @"Export", @"Copy"
  ];
  NSArray<NSString*>* japanese_actions = @[
    @"前へ", @"後へ", @"解決", @"再開", @"削除…", @"再接続", @"書き出す",
    @"コピー"
  ];
  NSArray<NSString*>* action_titles =
      japanese ? japanese_actions : english_actions;
  for (NSUInteger index = 0; index < self.actionButtons.count; ++index) {
    self.actionButtons[index].title = action_titles[index];
  }
  [self.cardShowControl setLabel:japanese ? @"常に表示" : @"Always"
                       forSegment:0];
  [self.cardShowControl setLabel:japanese ? @"Return時" : @"On Return"
                       forSegment:1];
  [self.cardShowControl
      setAccessibilityLabel:japanese ? @"選択したノートを表示するタイミング"
                                     : @"Show selected note"];
  self.rearmButton.title = japanese ? @"再設定" : @"Re-arm";
  [self.rearmButton setAccessibilityLabel:self.rearmButton.title];
  DtnCardModel* selected_model = [self selectedModel];
  const BOOL has_selection = selected_model != nil;
  const BOOL current = projection.section == DTN_SECTION_CURRENT;
  const BOOL on_return_enabled =
      (projection.projection_flags & kDtnProjectionFlagOnReturnEnabled) != 0u;
  self.actionButtons[0].enabled =
      has_selection && (current || selected_model.order > 0u);
  self.actionButtons[1].enabled =
      has_selection &&
      (current || selected_model.order < projection.total_count - 1u);
  self.actionButtons[2].enabled = current && has_selection && selected_model.status == 0u;
  self.actionButtons[3].enabled = current && has_selection && selected_model.status == 1u;
  self.actionButtons[4].enabled = current && has_selection;
  self.actionButtons[5].enabled =
      has_selection && projection.section == DTN_SECTION_DETACHED;
  self.actionButtons[6].enabled = YES;
  self.actionButtons[7].enabled = has_selection;
  self.cardColorControl.enabled = current && has_selection;
  self.cardShowControl.hidden = !on_return_enabled || !current;
  self.rearmButton.hidden =
      !on_return_enabled || !current || !has_selection ||
      selected_model.triggerKind != 1u || !selected_model.due;
  self.cardShowControl.enabled =
      on_return_enabled && current && has_selection &&
      selected_model.status == 0u && selected_model.triggerKind != 2u;
  self.rearmButton.enabled = !self.rearmButton.hidden;
  if (has_selection) {
    self.cardColorControl.selectedSegment = (NSInteger)selected_model.color;
    self.cardShowControl.selectedSegment =
        selected_model.triggerKind == 1u ? 1 : 0;
  } else {
    for (NSInteger index = 0; index < self.cardColorControl.segmentCount;
         ++index) {
    [self.cardColorControl setSelected:NO forSegment:index];
    }
    self.cardShowControl.selectedSegment = 0;
  }
  [self.cardColorControl setAccessibilityLabel:japanese ? @"ノートの色"
                                                    : @"Note color"];
  self.deleteConfirmationArmed = NO;

  const BOOL editor_active = projection.editor_mode != DTN_EDITOR_INACTIVE;
  if (!editor_active) {
    self.locallyClosedEditor = NO;
    self.editor.hidden = YES;
    self.scrollView.hidden = NO;
    [self.editor clearDraft];
  } else {
    if (projection.draft_generation != previous_draft) {
      self.locallyClosedEditor = NO;
      NSString* baseline = selected_model == nil ? @"" : selected_model.body;
      const uint32_t color = selected_model == nil ? 1u : selected_model.color;
      const uint32_t show_timing =
          selected_model != nil && selected_model.triggerKind == 1u ? 1u : 0u;
      [self.editor beginDraft:baseline
                        color:color
                   showTiming:show_timing
              onReturnEnabled:on_return_enabled
              draftGeneration:projection.draft_generation
               bodyFontPoints:font_points
               japaneseLocale:japanese];
    } else {
      self.editor.textView.font = [NSFont systemFontOfSize:font_points];
    }
    self.editor.hidden = self.locallyClosedEditor;
    self.scrollView.hidden = !self.locallyClosedEditor;
    self.editor.layer.backgroundColor =
        DtnColor(DtnSurfaceRgba(
                     (uint32_t)self.editor.colorControl.selectedSegment, dark))
            .CGColor;
    self.editor.layer.borderColor =
        DtnColor(DtnAccentRgba(
                     (uint32_t)self.editor.colorControl.selectedSegment, dark))
            .CGColor;
    self.editor.textView.textColor =
        DtnColor(dark ? 0xf5f5f5ffu : 0x1f1f1fffu);
  }
  self.animationMilliseconds =
      (projection.projection_flags & (1u << 5)) != 0u ? 0u : 140u;
  self.visibleAcknowledgementEligibleGeneration = 0u;
  [self setSemanticControlsEnabled:YES];
  [self layoutPresentation];
}

- (uint32_t)focusTarget {
  NSResponder* responder = self.window.firstResponder;
  if (![responder isKindOfClass:NSView.class]) return DTN_FOCUS_NONE;
  NSView* focused = (NSView*)responder;
  if (focused == self.editor || [focused isDescendantOf:self.editor]) {
    return DTN_FOCUS_EDITOR;
  }
  if (focused == self.badge || focused == self.rail ||
      [focused isDescendantOf:self.rail]) {
    return DTN_FOCUS_RAIL;
  }
  return DTN_FOCUS_NONE;
}

- (int32_t)focusInsideSurface:(uint32_t)target {
  if (self.window == nil) return DTN_STATUS_NOT_FOUND;
  NSView* responder = nil;
  if (target == DTN_FOCUS_RAIL) {
    responder = self.rail.hidden ? self.badge : self.sectionControl;
    if (responder.hidden) return DTN_STATUS_NOT_FOUND;
  } else if (target == DTN_FOCUS_EDITOR) {
    if (self.editor.hidden ||
        self.projection.editor_mode == DTN_EDITOR_INACTIVE) {
      return DTN_STATUS_NOT_FOUND;
    }
    responder = self.editor.textView;
  } else {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  return [self.window makeFirstResponder:responder] ? DTN_STATUS_OK
                                                    : DTN_STATUS_INTERNAL;
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
  const CGFloat toolbar_width = fmax(0, rail_width - 24);
  self.titleLabel.frame = NSMakeRect(0, 0, 44, 20);
  self.sectionControl.frame = NSMakeRect(46, 0, fmax(80, toolbar_width - 142), 24);
  self.createButton.frame =
      NSMakeRect(fmax(128, toolbar_width - 92), 0, 44, 24);
  self.closeButton.frame = NSMakeRect(fmax(174, toolbar_width - 46), 0, 46, 24);
  const BOOL detached = self.projection.section == DTN_SECTION_DETACHED;
  self.pagingBar.hidden = !detached;
  self.pagingBar.frame = NSMakeRect(12, 60, fmax(0, rail_width - 24), 28);
  self.previousPageButton.frame = NSMakeRect(0, 0, 82, 24);
  self.nextPageButton.frame =
      NSMakeRect(fmax(82, self.pagingBar.bounds.size.width - 82), 0, 82, 24);
  self.pageRangeLabel.frame =
      NSMakeRect(86, 3, fmax(0, self.pagingBar.bounds.size.width - 172), 18);
  const BOOL editor_visible = !self.editor.hidden;
  const BOOL show_timing = !self.cardShowControl.hidden;
  self.actionBar.hidden = editor_visible;
  self.actionBar.frame =
      NSMakeRect(12, detached ? 94 : 60, fmax(0, rail_width - 24),
                 show_timing ? 118 : 88);
  const CGFloat action_width =
      fmax(0, (self.actionBar.bounds.size.width - 18) / 4);
  for (NSUInteger index = 0; index < self.actionButtons.count; ++index) {
    const NSUInteger row = index / 4;
    const NSUInteger column = index % 4;
    self.actionButtons[index].frame =
        NSMakeRect(column * (action_width + 6), row * 28, action_width, 24);
  }
  self.cardColorControl.frame =
      NSMakeRect(0, show_timing ? 88 : 58,
                 self.actionBar.bounds.size.width, 26);
  const CGFloat rearm_width = self.rearmButton.hidden ? 0 : 76;
  self.cardShowControl.frame =
      NSMakeRect(0, 58,
                 fmax(0, self.actionBar.bounds.size.width - rearm_width -
                              (rearm_width > 0 ? 6 : 0)),
                 26);
  self.rearmButton.frame =
      NSMakeRect(fmax(0, self.actionBar.bounds.size.width - rearm_width), 58,
                 rearm_width, 26);
  const CGFloat content_y =
      editor_visible ? 62 : (detached ? 188 : 154) + (show_timing ? 30 : 0);
  const NSRect content_frame =
      NSMakeRect(12, content_y, fmax(0, rail_width - 24),
                 fmax(0, self.rail.bounds.size.height - content_y - 12));
  self.scrollView.frame = content_frame;
  self.editor.frame = content_frame;
  if (editor_visible) {
    [self.rail setAccessibilityChildren:@[ self.toolbar, self.editor ]];
    self.sectionControl.nextKeyView = self.editor.textView;
    self.editor.textView.nextKeyView = self.editor.colorControl;
    self.editor.colorControl.nextKeyView = self.editor.showControl.hidden
        ? self.editor.saveButton
        : self.editor.showControl;
    self.editor.showControl.nextKeyView = self.editor.saveButton;
    self.editor.saveButton.nextKeyView = self.editor.cancelButton;
    self.editor.cancelButton.nextKeyView = self.sectionControl;
    self.editor.keepEditingButton.nextKeyView = self.editor.discardButton;
    self.editor.discardButton.nextKeyView = self.editor.keepEditingButton;
  } else {
    [self.rail setAccessibilityChildren:
                   detached
                       ? @[ self.toolbar, self.pagingBar, self.scrollView,
                            self.actionBar ]
                       : @[ self.toolbar, self.scrollView, self.actionBar ]];
    NSMutableArray* action_children =
        [NSMutableArray arrayWithObject:self.cardColorControl];
    if (!self.cardShowControl.hidden) {
      [action_children addObject:self.cardShowControl];
    }
    if (!self.rearmButton.hidden) [action_children addObject:self.rearmButton];
    [action_children addObjectsFromArray:self.actionButtons];
    [self.actionBar setAccessibilityChildren:action_children];
    self.sectionControl.nextKeyView =
        detached ? self.previousPageButton : self.createButton;
    self.previousPageButton.nextKeyView = self.nextPageButton;
    self.nextPageButton.nextKeyView = self.closeButton;
    self.createButton.nextKeyView = self.closeButton;
    self.closeButton.nextKeyView = self.cardColorControl;
    self.cardColorControl.nextKeyView = self.cardShowControl.hidden
        ? self.actionButtons.firstObject
        : self.cardShowControl;
    self.cardShowControl.nextKeyView = self.rearmButton.hidden
        ? self.actionButtons.firstObject
        : self.rearmButton;
    self.rearmButton.nextKeyView = self.actionButtons.firstObject;
    for (NSUInteger index = 0; index + 1 < self.actionButtons.count; ++index) {
      self.actionButtons[index].nextKeyView = self.actionButtons[index + 1];
    }
    self.actionButtons.lastObject.nextKeyView = self.sectionControl;
  }
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
  if (!editor_visible) {
    self.closeButton.nextKeyView =
        self.cardViews.count == 0 ? self.cardColorControl
                                  : self.cardViews.firstObject;
    for (NSUInteger index = 0; index < self.cardViews.count; ++index) {
      DtnNoteCardView* card = self.cardViews[index];
      card.nextKeyView = card.editButton;
      card.editButton.nextKeyView =
          index + 1 < self.cardViews.count ? self.cardViews[index + 1]
                                           : self.cardColorControl;
    }
  }
  self.cardList.frame = NSMakeRect(
      0, 0, card_width, fmax(self.scrollView.bounds.size.height, card_y));
  self.accessibilityBodyCount =
      rail_visible ? (editor_visible ? 1u : (uint32_t)self.cardViews.count)
                   : 0u;
  self.accessibilityNodeCount =
      rail_visible ? (editor_visible
                          ? 10u
                          : 16u + (uint32_t)self.cardViews.count * 4u)
                   : (badge_visible ? 1u : 0u);
  [self reconcileReadyAnnouncement];
  [self.badge setNeedsDisplay:YES];
  [self.rail setNeedsDisplay:YES];
}

- (void)reconcileReadyAnnouncement {
  DtnCardModel* first_model = self.models.firstObject;
  DtnNoteCardView* first_card = self.cardViews.firstObject;
  const NSRect first_visible = first_card == nil ? NSZeroRect
                                                  : first_card.visibleRect;
  const BOOL visible_ready = self.superview != nil && !self.rail.hidden &&
      !self.scrollView.hidden && self.editor.hidden &&
      self.projection.presentation_eligible != 0u &&
      self.projection.section == DTN_SECTION_CURRENT &&
      self.projection.editor_mode == DTN_EDITOR_INACTIVE &&
      self.projection.due_count > 0u && first_model != nil &&
      first_card != nil && first_model.due && !first_card.hidden &&
      first_card.bounds.size.width > 0 && first_card.bounds.size.height > 0 &&
      first_visible.size.width > 0 && first_visible.size.height > 0;
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
  dtn_notify_surface(self.nativeSurface);
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
  DtnSurfaceIntentV1 pending_intent;
  uint8_t pending_payload[DTN_MAX_INTENT_PAYLOAD_BYTES];
  uint64_t last_event_generation;
  uint32_t emitted_intent_count;
  uint32_t applied_result_count;
  uint64_t notification_id;
  bool has_pending_intent;
  bool pending_intent_delivered;
  bool initialized;
};

static atomic_uint_fast64_t g_live_surfaces = 0;

static void dtn_notify_surface(DtnSurface* surface) {
  if (surface == NULL || surface->notification_id == 0u ||
      g_dtn_surface_notify == NULL) {
    return;
  }
  g_dtn_surface_notify(surface->notification_id);
}

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

static bool dtn_valid_editor_string(NSString* value,
                                    bool require_non_whitespace) {
  if (value == nil) return false;
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding
                     allowLossyConversion:NO];
  if (data == nil || data.length > DTN_MAX_INTENT_PAYLOAD_BYTES) return false;
  if (data.length == 0u) return !require_non_whitespace;
  if (dtn_valid_body_utf8(data.bytes, data.length)) return true;
  if (require_non_whitespace) return false;

  // The shared persisted-body validator deliberately rejects whitespace-only
  // bodies. Such text is a valid intermediate draft, so append one safe scalar
  // only for structural validation; the original byte bound remains decisive.
  NSMutableData* structural = [data mutableCopy];
  const uint8_t non_whitespace = 'x';
  [structural appendBytes:&non_whitespace length:1u];
  return dtn_valid_body_utf8(structural.bytes, structural.length);
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
  const uint64_t draft_generation = dtn_read_u64(bytes + 108u);
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
      draft_generation > INT64_MAX || !dtn_zero_bytes(bytes + 116u, 12u)) {
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
  if ((editor_mode == DTN_EDITOR_INACTIVE) != (draft_generation == 0u) ||
      (editor_mode == DTN_EDITOR_CREATING && selected_token != 0u) ||
      (editor_mode == DTN_EDITOR_EDITING && selected_token == 0u)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
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
  output->draft_generation = draft_generation;
  output->projection_flags = flags;
  return DTN_STATUS_OK;
}

static int dtn_compare_revision(const DtnParsedProjection* left,
                                const DtnParsedProjection* right) {
  if (left->store_revision_low == right->store_revision_low) return 0;
  return left->store_revision_low < right->store_revision_low ? -1 : 1;
}

uint32_t dtn_abi_version(void) { return DTN_ABI_VERSION; }

int32_t dtn_initialize(const da_native_extension_services_v1* services) {
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (services == NULL ||
      services->struct_size <
          offsetof(da_native_extension_services_v1,
                   register_custom_view_provider) +
              sizeof(services->register_custom_view_provider) ||
      services->abi_version != DA_NATIVE_EXTENSION_ABI_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  if (g_dtn_services != NULL) {
    return g_dtn_services == services ? DTN_STATUS_OK
                                      : DTN_STATUS_INVALID_ARGUMENT;
  }
  g_dtn_services = services;
  return DTN_STATUS_OK;
}

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
  surface->view.nativeSurface = surface;
  atomic_fetch_add_explicit(&g_live_surfaces, 1u, memory_order_relaxed);
  return surface;
}

int32_t dtn_set_surface_notify_callback(DtnSurfaceNotifyV1 callback) {
  if (callback == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (g_dtn_surface_notify != NULL && g_dtn_surface_notify != callback) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  g_dtn_surface_notify = callback;
  return DTN_STATUS_OK;
}

int32_t dtn_surface_set_notification_id(DtnSurface* surface,
                                        uint64_t notification_id) {
  if (surface == NULL || notification_id == 0u || notification_id > INT64_MAX) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (surface->notification_id != 0u &&
      surface->notification_id != notification_id) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  surface->notification_id = notification_id;
  return DTN_STATUS_OK;
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
  if (surface->has_pending_intent) {
    [surface->view setSemanticControlsEnabled:NO];
  }
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
  snapshot->draft_generation = projection.draft_generation;
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
  snapshot->outstanding_intent = surface->has_pending_intent ? 1u : 0u;
  snapshot->emitted_intent_count = surface->emitted_intent_count;
  snapshot->applied_result_count = surface->applied_result_count;
  uint32_t interaction_flags = 0u;
  if (!surface->view.editor.hidden && surface->view.editor.isDirty) {
    interaction_flags |= DTN_INTERACTION_EDITOR_DIRTY;
  }
  if (!surface->view.editor.discardConfirmation.hidden) {
    interaction_flags |= DTN_INTERACTION_CONFIRM_DISCARD;
  }
  snapshot->interaction_flags = interaction_flags;
  snapshot->focus_target = surface->view.focusTarget;
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

static bool dtn_surface_has_card_token(DtnSurface* surface, uint64_t token) {
  if (token == 0u) return false;
  for (DtnCardModel* model in surface->view.models) {
    if (model.token == token) return true;
  }
  return false;
}

static bool dtn_intent_reserved_zero(const DtnSurfaceIntentV1* intent) {
  if (intent->reserved0 != 0u) return false;
  for (size_t index = 0; index < 10u; ++index) {
    if (intent->reserved[index] != 0u) return false;
  }
  return true;
}

static bool dtn_result_reserved_zero(const DtnSurfaceResultV1* result) {
  if (result->reserved0 != 0u) return false;
  for (size_t index = 0; index < 6u; ++index) {
    if (result->reserved[index] != 0u) return false;
  }
  return true;
}

static bool dtn_intent_kind_commits(uint32_t kind) {
  return kind == DTN_INTENT_SAVE ||
         kind == DTN_INTENT_SAVE_ALWAYS_AVAILABLE ||
         kind == DTN_INTENT_SAVE_ON_RETURN ||
         kind == DTN_INTENT_ARM_ON_RETURN ||
         kind == DTN_INTENT_MAKE_ALWAYS_AVAILABLE ||
         kind == DTN_INTENT_CHANGE_COLOR ||
         kind == DTN_INTENT_MOVE_EARLIER ||
         kind == DTN_INTENT_MOVE_LATER || kind == DTN_INTENT_RESOLVE ||
         kind == DTN_INTENT_REOPEN || kind == DTN_INTENT_DELETE ||
         kind == DTN_INTENT_REATTACH;
}

static bool dtn_intent_kind_projects(uint32_t kind) {
  return dtn_intent_kind_commits(kind) || kind == DTN_INTENT_CANCEL ||
         kind == DTN_INTENT_OPEN || kind == DTN_INTENT_CLOSE ||
         kind == DTN_INTENT_SELECT_CARD || kind == DTN_INTENT_BEGIN_CREATE ||
         kind == DTN_INTENT_BEGIN_EDIT || kind == DTN_INTENT_SHOW_CURRENT ||
         kind == DTN_INTENT_SHOW_DETACHED ||
         kind == DTN_INTENT_PREVIOUS_PAGE || kind == DTN_INTENT_NEXT_PAGE;
}

int32_t dtn_surface_request_intent(DtnSurface* surface,
                                   const DtnSurfaceIntentV1* intent,
                                   const uint8_t* payload) {
  if (surface == NULL || intent == NULL ||
      intent->struct_size != sizeof(DtnSurfaceIntentV1)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (intent->version != DTN_INTENT_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (!surface->initialized || !dtn_intent_reserved_zero(intent) ||
      intent->kind > DTN_INTENT_MAKE_ALWAYS_AVAILABLE ||
      intent->event_generation == 0u || intent->event_generation > INT64_MAX ||
      intent->payload_bytes > DTN_MAX_INTENT_PAYLOAD_BYTES ||
      (intent->payload_bytes == 0u) != (payload == NULL) ||
      intent->surface_generation != surface->projection.surface_generation ||
      intent->projection_generation !=
          surface->projection.projection_generation ||
      intent->expected_store_revision !=
          surface->projection.store_revision_low ||
      intent->event_generation <= surface->last_event_generation ||
      intent->draft_generation != surface->projection.draft_generation) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (surface->has_pending_intent) return DTN_STATUS_BUSY;

  const bool payload_kind = intent->kind == DTN_INTENT_SAVE ||
                            intent->kind ==
                                DTN_INTENT_SAVE_ALWAYS_AVAILABLE ||
                            intent->kind == DTN_INTENT_SAVE_ON_RETURN ||
                            intent->kind == DTN_INTENT_COPY;
  if (payload_kind != (intent->payload_bytes > 0u) ||
      (payload_kind &&
       !dtn_valid_body_utf8(payload, intent->payload_bytes))) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  const bool color_kind = intent->kind == DTN_INTENT_SAVE ||
                          intent->kind ==
                              DTN_INTENT_SAVE_ALWAYS_AVAILABLE ||
                          intent->kind == DTN_INTENT_SAVE_ON_RETURN ||
                          intent->kind == DTN_INTENT_CHANGE_COLOR;
  if ((color_kind && intent->color > 5u) ||
      (!color_kind && intent->color != DTN_NO_COLOR)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  const bool timing_save =
      intent->kind == DTN_INTENT_SAVE_ALWAYS_AVAILABLE ||
      intent->kind == DTN_INTENT_SAVE_ON_RETURN;
  if (timing_save &&
      (surface->projection.projection_flags &
       kDtnProjectionFlagOnReturnEnabled) == 0u) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }

  const uint32_t editor_mode = surface->projection.editor_mode;
  const uint64_t selected = surface->projection.selected_token;
  if (intent->kind == DTN_INTENT_SAVE ||
      intent->kind == DTN_INTENT_SAVE_ALWAYS_AVAILABLE ||
      intent->kind == DTN_INTENT_SAVE_ON_RETURN ||
      intent->kind == DTN_INTENT_CANCEL) {
    if (editor_mode == DTN_EDITOR_INACTIVE ||
        intent->draft_generation == 0u ||
        intent->card_token != selected) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_OPEN) {
    if (surface->projection.visibility != DTN_VISIBILITY_COLLAPSED ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        intent->card_token != 0u) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_CLOSE) {
    if (surface->projection.visibility != DTN_VISIBILITY_EXPANDED ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        intent->card_token != 0u) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_BEGIN_CREATE) {
    if (surface->projection.visibility != DTN_VISIBILITY_EXPANDED ||
        surface->projection.section != DTN_SECTION_CURRENT ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        intent->card_token != 0u) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_SELECT_CARD ||
             intent->kind == DTN_INTENT_BEGIN_EDIT) {
    if (surface->projection.visibility != DTN_VISIBILITY_EXPANDED ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        (intent->kind == DTN_INTENT_BEGIN_EDIT &&
         surface->projection.section != DTN_SECTION_CURRENT) ||
        !dtn_surface_has_card_token(surface, intent->card_token)) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_SHOW_CURRENT ||
             intent->kind == DTN_INTENT_SHOW_DETACHED) {
    const uint32_t requested = intent->kind == DTN_INTENT_SHOW_CURRENT
                                   ? DTN_SECTION_CURRENT
                                   : DTN_SECTION_DETACHED;
    if (surface->projection.visibility != DTN_VISIBILITY_EXPANDED ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        intent->card_token != 0u || surface->projection.section == requested) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_PREVIOUS_PAGE ||
             intent->kind == DTN_INTENT_NEXT_PAGE) {
    const bool can_page = intent->kind == DTN_INTENT_PREVIOUS_PAGE
                              ? surface->projection.page_start > 0u
                              : surface->projection.page_start + DTN_MAX_CARDS <
                                    surface->projection.total_count;
    if (surface->projection.visibility != DTN_VISIBILITY_EXPANDED ||
        surface->projection.section != DTN_SECTION_DETACHED ||
        editor_mode != DTN_EDITOR_INACTIVE || intent->draft_generation != 0u ||
        intent->card_token != 0u || !can_page) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_EXPORT) {
    if (intent->card_token != 0u) return DTN_STATUS_INVALID_ARGUMENT;
  } else if (intent->kind == DTN_INTENT_REATTACH) {
    if (surface->projection.section != DTN_SECTION_DETACHED ||
        !dtn_surface_has_card_token(surface, intent->card_token)) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (intent->kind == DTN_INTENT_ARM_ON_RETURN ||
             intent->kind == DTN_INTENT_MAKE_ALWAYS_AVAILABLE) {
    if ((surface->projection.projection_flags &
         kDtnProjectionFlagOnReturnEnabled) == 0u ||
        surface->projection.section != DTN_SECTION_CURRENT ||
        surface->projection.editor_mode != DTN_EDITOR_INACTIVE ||
        !dtn_surface_has_card_token(surface, intent->card_token)) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else if (!dtn_surface_has_card_token(surface, intent->card_token)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }

  surface->pending_intent = *intent;
  if (intent->payload_bytes > 0u) {
    memcpy(surface->pending_payload, payload, intent->payload_bytes);
  }
  surface->has_pending_intent = true;
  surface->pending_intent_delivered = false;
  if (surface->emitted_intent_count != UINT32_MAX) {
    ++surface->emitted_intent_count;
  }
  return DTN_STATUS_OK;
}

static int32_t dtn_emit_view_intent(DtnSurface* surface, uint32_t kind,
                                    NSString* body, uint32_t color,
                                    uint64_t token) {
  if (surface == NULL || surface->last_event_generation >= INT64_MAX) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  NSData* payload = nil;
  if (body != nil) {
    payload = [body dataUsingEncoding:NSUTF8StringEncoding
                 allowLossyConversion:NO];
    if (payload == nil || payload.length > DTN_MAX_INTENT_PAYLOAD_BYTES) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  }
  DtnSurfaceIntentV1 intent = {0};
  intent.struct_size = sizeof(intent);
  intent.version = DTN_INTENT_VERSION;
  intent.surface_generation = surface->projection.surface_generation;
  intent.projection_generation = surface->projection.projection_generation;
  intent.event_generation = surface->last_event_generation + 1u;
  intent.draft_generation = surface->projection.draft_generation;
  intent.card_token = token;
  intent.expected_store_revision = surface->projection.store_revision_low;
  intent.kind = kind;
  intent.payload_bytes = (uint32_t)payload.length;
  intent.color = color;
  return dtn_surface_request_intent(
      surface, &intent, payload.length == 0u ? NULL : payload.bytes);
}

int32_t dtn_surface_take_intent(DtnSurface* surface,
                                DtnSurfaceIntentV1* intent,
                                uint8_t* payload,
                                size_t payload_capacity) {
  if (surface == NULL || intent == NULL ||
      intent->struct_size != sizeof(DtnSurfaceIntentV1)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (intent->version != DTN_INTENT_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (!surface->has_pending_intent || surface->pending_intent_delivered) {
    return DTN_STATUS_NOT_FOUND;
  }
  const size_t payload_bytes = surface->pending_intent.payload_bytes;
  if (payload_capacity < payload_bytes ||
      (payload_bytes > 0u && payload == NULL)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  *intent = surface->pending_intent;
  if (payload_bytes > 0u) {
    memcpy(payload, surface->pending_payload, payload_bytes);
  }
  surface->pending_intent_delivered = true;
  return DTN_STATUS_OK;
}

int32_t dtn_surface_apply_result(DtnSurface* surface,
                                 const DtnSurfaceResultV1* result) {
  if (surface == NULL || result == NULL ||
      result->struct_size != sizeof(DtnSurfaceResultV1)) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (result->version != DTN_RESULT_VERSION) {
    return DTN_STATUS_UNSUPPORTED_VERSION;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (!surface->has_pending_intent || !surface->pending_intent_delivered) {
    return DTN_STATUS_STALE;
  }
  const DtnSurfaceIntentV1 pending = surface->pending_intent;
  if (!dtn_result_reserved_zero(result) ||
      result->disposition > DTN_RESULT_UNAVAILABLE ||
      result->surface_generation != pending.surface_generation ||
      result->projection_generation != pending.projection_generation ||
      result->event_generation != pending.event_generation ||
      result->draft_generation != pending.draft_generation) {
    return DTN_STATUS_STALE;
  }
  const bool commits = dtn_intent_kind_commits(pending.kind);
  const bool projects = dtn_intent_kind_projects(pending.kind);
  if (result->disposition == DTN_RESULT_ACCEPTED) {
    if (commits) {
      if (result->new_store_revision <= pending.expected_store_revision ||
          result->new_projection_generation <= pending.projection_generation ||
          surface->projection.store_revision_low !=
              result->new_store_revision ||
          surface->projection.projection_generation !=
              result->new_projection_generation) {
        return DTN_STATUS_INVALID_ARGUMENT;
      }
    } else if (projects) {
      if (result->new_store_revision != pending.expected_store_revision ||
          result->new_projection_generation <= pending.projection_generation ||
          surface->projection.store_revision_low !=
              result->new_store_revision ||
          surface->projection.projection_generation !=
              result->new_projection_generation) {
        return DTN_STATUS_INVALID_ARGUMENT;
      }
    } else if (result->new_store_revision !=
                   pending.expected_store_revision ||
               result->new_projection_generation !=
                   pending.projection_generation) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  } else {
    if ((result->disposition == DTN_RESULT_CONFLICT &&
         pending.kind != DTN_INTENT_SAVE &&
         pending.kind != DTN_INTENT_SAVE_ALWAYS_AVAILABLE &&
         pending.kind != DTN_INTENT_SAVE_ON_RETURN) ||
        result->new_store_revision != pending.expected_store_revision ||
        result->new_projection_generation != pending.projection_generation) {
      return DTN_STATUS_INVALID_ARGUMENT;
    }
  }

  [surface->view applySemanticResult:*result intentKind:pending.kind];
  surface->last_event_generation = pending.event_generation;
  memset(&surface->pending_intent, 0, sizeof(surface->pending_intent));
  memset(surface->pending_payload, 0, sizeof(surface->pending_payload));
  surface->has_pending_intent = false;
  surface->pending_intent_delivered = false;
  if (surface->applied_result_count != UINT32_MAX) {
    ++surface->applied_result_count;
  }
  return DTN_STATUS_OK;
}

int32_t dtn_surface_focus(DtnSurface* surface, uint32_t target) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  return [surface->view focusInsideSurface:target];
}

int32_t dtn_surface_present_discard_confirmation(DtnSurface* surface) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  if (!surface->initialized ||
      surface->projection.editor_mode == DTN_EDITOR_INACTIVE ||
      surface->view.editor.hidden || !surface->view.editor.isDirty) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  [surface->view.editor showDiscardConfirmation];
  dtn_notify_surface(surface);
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
  if (surface->view.superview != nil && surface->view.superview != host) {
    return DTN_STATUS_BUSY;
  }
  surface->view.frame = host.bounds;
  surface->view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  if (surface->view.superview == nil) {
    [host addSubview:surface->view positioned:NSWindowAbove relativeTo:nil];
  }
  [surface->view layoutPresentation];
  return DTN_STATUS_OK;
}

int32_t dtn_surface_attach_to_renderer(DtnSurface* surface,
                                       uint64_t renderer_handle,
                                       uint64_t renderer_generation) {
  if (surface == NULL || renderer_handle == 0 || renderer_generation == 0) {
    return DTN_STATUS_INVALID_ARGUMENT;
  }
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  DtnRendererNativeViewV1 resolve = DtnRendererNativeViewResolver();
  if (resolve == NULL) return DTN_STATUS_NOT_FOUND;
  void* host_view = resolve(renderer_handle, renderer_generation);
  if (host_view == NULL) return DTN_STATUS_NOT_FOUND;
  return dtn_surface_attach_to_host(surface, host_view);
}

int32_t dtn_surface_detach_from_host(DtnSurface* surface) {
  if (surface == NULL) return DTN_STATUS_INVALID_ARGUMENT;
  if (![NSThread isMainThread]) return DTN_STATUS_WRONG_THREAD;
  [surface->view removeFromSuperview];
  return DTN_STATUS_OK;
}

void dtn_surface_destroy(DtnSurface* surface) {
  if (surface == NULL) return;
  if ([NSThread isMainThread]) {
    surface->view.nativeSurface = NULL;
    surface->view.editor.onInteractionChanged = nil;
    surface->view.editor.textView.delegate = nil;
    [surface->view.editor.textView.undoManager removeAllActions];
    [surface->view removeFromSuperview];
  }
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
