#import <CoreText/CoreText.h>
#import <MetalKit/MetalKit.h>

#include "TerminalRendererPlugin.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char kProviderIdentifier[] = "dart_terminal.TerminalMetalView";
static _Atomic int32_t g_live_view_count = 0;
static _Atomic int32_t g_live_metal_renderer_count = 0;
static _Atomic uint64_t g_next_font_catalog_handle = 1;
static _Atomic uint64_t g_next_metal_renderer_handle = 1;
static _Atomic uint32_t g_next_metal_test_failure =
    DTR_METAL_TEST_FAILURE_NONE;
static const da_native_extension_services_v1* g_initialized_services = NULL;
static DtrTextInputNotifyV1 g_text_input_notify = NULL;

@interface DtrTextInputQueue : NSObject

@property(nonatomic, strong) NSMutableArray<NSData*>* packets;
@property(nonatomic) uint64_t queuedBytes;

- (BOOL)enqueuePacket:(NSData*)packet kind:(uint32_t)kind;
- (void)replaceWithOverflowPacket:(NSData*)packet;
- (NSData*)peekPacket;
- (void)removeFirstPacket;

@end

@implementation DtrTextInputQueue

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _packets = [[NSMutableArray alloc] init];
  }
  return self;
}

- (BOOL)enqueuePacket:(NSData*)packet kind:(uint32_t)kind {
  if (packet == nil || packet.length > DTR_MAX_TEXT_INPUT_QUEUE_BYTES) {
    return NO;
  }
  if (kind == DTR_TEXT_INPUT_EVENT_PREEDIT && self.packets.count > 0) {
    NSData* previous = self.packets.lastObject;
    if (previous.length >= sizeof(DtrTextInputEventHeaderV1)) {
      DtrTextInputEventHeaderV1 header;
      memcpy(&header, previous.bytes, sizeof(header));
      if (header.kind == DTR_TEXT_INPUT_EVENT_PREEDIT) {
        const uint64_t next_bytes =
            self.queuedBytes - previous.length + packet.length;
        if (next_bytes <= DTR_MAX_TEXT_INPUT_QUEUE_BYTES) {
          [self.packets removeLastObject];
          [self.packets addObject:packet];
          self.queuedBytes = next_bytes;
          return YES;
        }
      }
    }
  }
  if (self.packets.count >= DTR_MAX_TEXT_INPUT_EVENTS ||
      self.queuedBytes >
          DTR_MAX_TEXT_INPUT_QUEUE_BYTES - (uint64_t)packet.length) {
    return NO;
  }
  [self.packets addObject:packet];
  self.queuedBytes += packet.length;
  return YES;
}

- (void)replaceWithOverflowPacket:(NSData*)packet {
  [self.packets removeAllObjects];
  self.queuedBytes = 0;
  if (packet != nil && packet.length <= DTR_MAX_TEXT_INPUT_QUEUE_BYTES) {
    [self.packets addObject:packet];
    self.queuedBytes = packet.length;
  }
}

- (NSData*)peekPacket {
  return self.packets.firstObject;
}

- (void)removeFirstPacket {
  if (self.packets.count == 0) {
    return;
  }
  NSData* packet = self.packets.firstObject;
  [self.packets removeObjectAtIndex:0];
  self.queuedBytes -= packet.length;
}

@end

static NSLock* TextInputQueueLock(void) {
  static NSLock* lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static NSMutableDictionary<NSNumber*, DtrTextInputQueue*>*
TextInputQueues(void) {
  static NSMutableDictionary<NSNumber*, DtrTextInputQueue*>* queues;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    queues = [[NSMutableDictionary alloc] init];
  });
  return queues;
}

static BOOL RegisterTextInputQueue(uint64_t client_id,
                                   DtrTextInputQueue* queue) {
  if (client_id == 0 || client_id > INT64_MAX || queue == nil) {
    return NO;
  }
  NSLock* lock = TextInputQueueLock();
  [lock lock];
  NSNumber* key = @(client_id);
  DtrTextInputQueue* existing = TextInputQueues()[key];
  const BOOL accepted = existing == nil || existing == queue;
  if (accepted) {
    TextInputQueues()[key] = queue;
  }
  [lock unlock];
  return accepted;
}

static void UnregisterTextInputQueue(uint64_t client_id,
                                     DtrTextInputQueue* queue) {
  if (client_id == 0 || queue == nil) {
    return;
  }
  NSLock* lock = TextInputQueueLock();
  [lock lock];
  NSNumber* key = @(client_id);
  if (TextInputQueues()[key] == queue) {
    [TextInputQueues() removeObjectForKey:key];
  }
  [lock unlock];
}

static uint64_t TextInputMonotonicNanos(void) {
  struct timespec now = {0, 0};
  if (clock_gettime(CLOCK_MONOTONIC_RAW, &now) != 0 || now.tv_sec < 0 ||
      now.tv_nsec < 0) {
    return 0;
  }
  const uint64_t seconds = (uint64_t)now.tv_sec;
  if (seconds > (uint64_t)INT64_MAX / 1000000000u) {
    return INT64_MAX;
  }
  const uint64_t value = seconds * 1000000000u + (uint64_t)now.tv_nsec;
  return value > INT64_MAX ? INT64_MAX : value;
}

static uint32_t TextInputStableModifiers(NSEventModifierFlags flags) {
  uint32_t result = 0;
  if ((flags & NSEventModifierFlagCapsLock) != 0) result |= 1u << 0;
  if ((flags & NSEventModifierFlagShift) != 0) result |= 1u << 1;
  if ((flags & NSEventModifierFlagControl) != 0) result |= 1u << 2;
  if ((flags & NSEventModifierFlagOption) != 0) result |= 1u << 3;
  if ((flags & NSEventModifierFlagCommand) != 0) result |= 1u << 4;
  if ((flags & NSEventModifierFlagNumericPad) != 0) result |= 1u << 5;
  if ((flags & NSEventModifierFlagFunction) != 0) result |= 1u << 6;
  return result;
}

static BOOL EncodeTextInputRange(NSRange range, uint32_t* location,
                                 uint32_t* length) {
  if (range.location == NSNotFound) {
    *location = UINT32_MAX;
    *length = 0;
    return YES;
  }
  if (range.location > UINT32_MAX || range.length > UINT32_MAX ||
      range.location > UINT32_MAX - range.length) {
    return NO;
  }
  *location = (uint32_t)range.location;
  *length = (uint32_t)range.length;
  return YES;
}

static NSData* BuildTextInputPacket(
    uint64_t client_id, uint64_t event_generation, uint32_t kind,
    uint32_t flags, uint32_t key_code, uint32_t modifiers, NSString* text,
    NSString* unmodified_text, NSRange selection, NSRange replacement) {
  NSData* text_data = text == nil
                          ? [NSData data]
                          : [text dataUsingEncoding:NSUTF8StringEncoding];
  NSData* unmodified_data =
      unmodified_text == nil
          ? [NSData data]
          : [unmodified_text dataUsingEncoding:NSUTF8StringEncoding];
  if (text_data == nil || unmodified_data == nil ||
      text_data.length > DTR_MAX_TEXT_INPUT_BYTES ||
      unmodified_data.length > DTR_MAX_TEXT_INPUT_BYTES) {
    return nil;
  }
  const uint64_t total = sizeof(DtrTextInputEventHeaderV1) + text_data.length +
                         unmodified_data.length;
  if (total > UINT32_MAX) {
    return nil;
  }
  DtrTextInputEventHeaderV1 header;
  memset(&header, 0, sizeof(header));
  header.magic = DTR_TEXT_INPUT_EVENT_MAGIC;
  header.version = DTR_TEXT_INPUT_EVENT_VERSION;
  header.header_size = sizeof(header);
  header.total_size = (uint32_t)total;
  header.client_id = client_id;
  header.event_generation = event_generation;
  header.monotonic_nanos = TextInputMonotonicNanos();
  header.kind = kind;
  header.flags = flags;
  header.key_code = key_code;
  header.modifiers = modifiers;
  header.text_offset = sizeof(header);
  header.text_length = (uint32_t)text_data.length;
  header.unmodified_text_offset =
      sizeof(header) + (uint32_t)text_data.length;
  header.unmodified_text_length = (uint32_t)unmodified_data.length;
  if (!EncodeTextInputRange(selection, &header.selection_location,
                            &header.selection_length) ||
      !EncodeTextInputRange(replacement, &header.replacement_location,
                            &header.replacement_length)) {
    return nil;
  }
  NSMutableData* packet = [NSMutableData dataWithLength:(NSUInteger)total];
  memcpy(packet.mutableBytes, &header, sizeof(header));
  uint8_t* bytes = packet.mutableBytes;
  if (text_data.length > 0) {
    memcpy(bytes + header.text_offset, text_data.bytes, text_data.length);
  }
  if (unmodified_data.length > 0) {
    memcpy(bytes + header.unmodified_text_offset, unmodified_data.bytes,
           unmodified_data.length);
  }
  return packet;
}

static BOOL ConsumeMetalTestFailure(uint32_t failure) {
  uint32_t expected = failure;
  return atomic_compare_exchange_strong_explicit(
      &g_next_metal_test_failure, &expected, DTR_METAL_TEST_FAILURE_NONE,
      memory_order_relaxed, memory_order_relaxed);
}

static void SaturatingIncrementMetric(uint64_t* value) {
  if (*value < INT64_MAX) {
    ++*value;
  }
}

static void SaturatingAddMetric(uint64_t* value, uint64_t increment) {
  if (*value >= INT64_MAX || increment >= (uint64_t)INT64_MAX - *value) {
    *value = INT64_MAX;
  } else {
    *value += increment;
  }
}

static uint64_t GpuDurationNanoseconds(id<MTLCommandBuffer> command) {
  const CFTimeInterval start = command.GPUStartTime;
  const CFTimeInterval end = command.GPUEndTime;
  if (!isfinite(start) || !isfinite(end) || start < 0.0 || end <= start) {
    return 0;
  }
  const double nanoseconds = (end - start) * 1000000000.0;
  if (!isfinite(nanoseconds) || nanoseconds >= (double)INT64_MAX) {
    return INT64_MAX;
  }
  const uint64_t result = (uint64_t)nanoseconds;
  return result == 0 ? 1 : result;
}

extern const uint8_t dtr_metallib_start[]
    __asm("section$start$__DATA$__dtrlib");
extern const uint8_t dtr_metallib_end[]
    __asm("section$end$__DATA$__dtrlib");

@interface DtrFontCatalog : NSObject

@property(nonatomic, readonly) uint64_t generation;
@property(nonatomic, readonly) double pointSize;
@property(nonatomic, readonly) NSArray* fonts;
@property(nonatomic, readonly) uint32_t availableStyleBits;
@property(nonatomic, readonly) uint32_t syntheticStyleBits;

- (instancetype)initWithFamily:(NSString*)family
                      pointSize:(double)pointSize
                    generation:(uint64_t)generation
                   policyFlags:(uint32_t)policyFlags;
- (NSFont*)fontForStyle:(uint32_t)style synthetic:(BOOL*)synthetic;
- (uint32_t)faceIdForFont:(NSFont*)font;
- (NSFont*)fontForFaceId:(uint32_t)faceId;
- (uint32_t)faceIdForStyle:(uint32_t)style;
- (BOOL)fillSummary:(DtrFontCatalogSummaryV1*)output handle:(uint64_t)handle;

@end

static NSLock* FontCatalogRegistryLock(void) {
  static NSLock* lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static NSMutableDictionary<NSNumber*, DtrFontCatalog*>*
FontCatalogRegistry(void) {
  static NSMutableDictionary<NSNumber*, DtrFontCatalog*>* registry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registry = [[NSMutableDictionary alloc] init];
  });
  return registry;
}

static NSFont* CreateRequestedFont(NSString* family, double point_size) {
  if (family.length == 0) {
    return [NSFont monospacedSystemFontOfSize:point_size
                                      weight:NSFontWeightRegular];
  }
  NSFont* font = [NSFont fontWithName:family size:point_size];
  if (font != nil) {
    return font;
  }
  return [[NSFontManager sharedFontManager]
      fontWithFamily:family
              traits:0
              weight:5
                size:point_size];
}

static NSFont* CreateTraitFont(NSFont* regular, CTFontSymbolicTraits traits) {
  CTFontRef result = CTFontCreateCopyWithSymbolicTraits(
      (__bridge CTFontRef)regular, regular.pointSize, NULL, traits, traits);
  return result == NULL ? nil : CFBridgingRelease(result);
}

static NSString* PostScriptName(NSFont* font) {
  CFStringRef name = CTFontCopyPostScriptName((__bridge CTFontRef)font);
  return name == NULL ? @"" : CFBridgingRelease(name);
}

@implementation DtrFontCatalog {
  NSLock* _faceLock;
  NSMutableDictionary<NSString*, NSNumber*>* _faceIds;
  NSMutableDictionary<NSNumber*, NSFont*>* _fontsByFaceId;
  uint32_t _nextFaceId;
}

- (instancetype)initWithFamily:(NSString*)family
                      pointSize:(double)pointSize
                    generation:(uint64_t)generation
                   policyFlags:(uint32_t)policyFlags {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  NSFont* regular = CreateRequestedFont(family, pointSize);
  if (regular == nil) {
    return nil;
  }
  NSMutableArray* fonts = [[NSMutableArray alloc] initWithCapacity:4];
  [fonts addObject:regular];
  uint32_t available = DTR_FONT_STYLE_BIT_REGULAR;
  uint32_t synthetic = 0;
  const CTFontSymbolicTraits requested_traits[3] = {
      kCTFontBoldTrait,
      kCTFontItalicTrait,
      kCTFontBoldTrait | kCTFontItalicTrait,
  };
  for (uint32_t index = 0; index < 3; index++) {
    NSFont* font = CreateTraitFont(regular, requested_traits[index]);
    const uint32_t style = index + 1;
    if (font != nil) {
      available |= 1u << style;
      [fonts addObject:font];
    } else if ((policyFlags & DTR_FONT_POLICY_ALLOW_SYNTHETIC) != 0) {
      synthetic |= 1u << style;
      [fonts addObject:regular];
    } else {
      [fonts addObject:[NSNull null]];
    }
  }
  _generation = generation;
  _pointSize = pointSize;
  _fonts = [fonts copy];
  _availableStyleBits = available;
  _syntheticStyleBits = synthetic;
  _faceLock = [[NSLock alloc] init];
  _faceIds = [[NSMutableDictionary alloc] init];
  _fontsByFaceId = [[NSMutableDictionary alloc] init];
  _nextFaceId = 1;
  for (id candidate in _fonts) {
    if (candidate != [NSNull null]) {
      [self faceIdForFont:(NSFont*)candidate];
    }
  }
  return self;
}

- (NSFont*)fontForStyle:(uint32_t)style synthetic:(BOOL*)synthetic {
  if (style > DTR_FONT_STYLE_BOLD_ITALIC) {
    return nil;
  }
  id candidate = self.fonts[style];
  if (candidate == [NSNull null]) {
    return nil;
  }
  if (synthetic != NULL) {
    *synthetic = (self.syntheticStyleBits & (1u << style)) != 0;
  }
  return (NSFont*)candidate;
}

- (uint32_t)faceIdForFont:(NSFont*)font {
  NSString* name = PostScriptName(font);
  [_faceLock lock];
  NSNumber* existing = _faceIds[name];
  if (existing != nil) {
    [_faceLock unlock];
    return existing.unsignedIntValue;
  }
  const uint32_t identifier = _nextFaceId++;
  _faceIds[name] = @(identifier);
  _fontsByFaceId[@(identifier)] = font;
  [_faceLock unlock];
  return identifier;
}

- (NSFont*)fontForFaceId:(uint32_t)faceId {
  [_faceLock lock];
  NSFont* font = _fontsByFaceId[@(faceId)];
  [_faceLock unlock];
  return font;
}

- (uint32_t)faceIdForStyle:(uint32_t)style {
  NSFont* font = [self fontForStyle:style synthetic:NULL];
  return font == nil ? 0 : [self faceIdForFont:font];
}

- (BOOL)fillSummary:(DtrFontCatalogSummaryV1*)output handle:(uint64_t)handle {
  NSFont* regular = [self fontForStyle:DTR_FONT_STYLE_REGULAR synthetic:NULL];
  CTFontRef font = (__bridge CTFontRef)regular;
  UniChar character = 'M';
  CGGlyph glyph = 0;
  CGSize advance = CGSizeZero;
  if (!CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) ||
      glyph == 0 || CTFontGetAdvancesForGlyphs(
                        font, kCTFontOrientationHorizontal, &glyph, &advance,
                        1) <= 0) {
    return NO;
  }
  const double ascent = CTFontGetAscent(font);
  const double descent = CTFontGetDescent(font);
  const double leading = CTFontGetLeading(font);
  const double cell_width = ceil(advance.width * 64.0) / 64.0;
  const double cell_height = ceil((ascent + descent + leading) * 64.0) / 64.0;
  const double underline_position = CTFontGetUnderlinePosition(font);
  const double underline_thickness = CTFontGetUnderlineThickness(font);
  const double strike_thickness =
      underline_thickness > 1.0 / 64.0 ? underline_thickness : 1.0 / 64.0;
  const double values[] = {
      self.pointSize,
      cell_width,
      cell_height,
      ascent,
      descent,
      leading,
      ascent,
      underline_position,
      underline_thickness,
      ascent * 0.35,
      strike_thickness,
  };
  for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
    if (!isfinite(values[index])) {
      return NO;
    }
  }
  if (values[0] <= 0.0 || values[1] <= 0.0 || values[2] <= 0.0 ||
      values[3] <= 0.0 || values[4] <= 0.0 || values[5] < 0.0 ||
      values[6] <= 0.0 || values[8] <= 0.0 || values[9] <= 0.0 ||
      values[10] <= 0.0) {
    return NO;
  }
  output->handle = handle;
  output->generation = self.generation;
  output->point_size = values[0];
  output->cell_width = values[1];
  output->cell_height = values[2];
  output->ascent = values[3];
  output->descent = values[4];
  output->leading = values[5];
  output->baseline = values[6];
  output->underline_position = values[7];
  output->underline_thickness = values[8];
  output->strike_position = values[9];
  output->strike_thickness = values[10];
  output->available_style_bits = self.availableStyleBits;
  output->synthetic_style_bits = self.syntheticStyleBits;
  output->regular_face_id = [self faceIdForStyle:DTR_FONT_STYLE_REGULAR];
  output->bold_face_id = [self faceIdForStyle:DTR_FONT_STYLE_BOLD];
  output->italic_face_id = [self faceIdForStyle:DTR_FONT_STYLE_ITALIC];
  output->bold_italic_face_id =
      [self faceIdForStyle:DTR_FONT_STYLE_BOLD_ITALIC];
  return YES;
}

@end

@interface DtrRasterizedGlyph : NSObject

@property(nonatomic) uint32_t faceId;
@property(nonatomic) uint32_t glyphId;
@property(nonatomic) uint32_t format;
@property(nonatomic) uint32_t flags;
@property(nonatomic) int32_t originX;
@property(nonatomic) int32_t originY;
@property(nonatomic) uint32_t width;
@property(nonatomic) uint32_t height;
@property(nonatomic) uint32_t rowStride;
@property(nonatomic, copy) NSData* pixels;

@end

@implementation DtrRasterizedGlyph
@end

static DtrRasterizedGlyph* RasterizeGlyph(NSFont* font, uint32_t face_id,
                                          uint32_t glyph_id, double scale,
                                          int32_t* status) {
  if (status == NULL) {
    return nil;
  }
  *status = DTR_STATUS_INTERNAL;
  const CGGlyph glyph = (CGGlyph)glyph_id;
  CGRect bounds = CGRectZero;
  CTFontGetBoundingRectsForGlyphs((__bridge CTFontRef)font,
                                  kCTFontOrientationHorizontal, &glyph,
                                  &bounds, 1);
  if (CGRectIsNull(bounds) || CGRectIsInfinite(bounds) ||
      !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
      !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) {
    return nil;
  }
  DtrRasterizedGlyph* result = [[DtrRasterizedGlyph alloc] init];
  result.faceId = face_id;
  result.glyphId = glyph_id;
  const CTFontSymbolicTraits traits =
      CTFontGetSymbolicTraits((__bridge CTFontRef)font);
  const BOOL color = (traits & kCTFontColorGlyphsTrait) != 0;
  result.format =
      color ? DTR_RASTER_FORMAT_RGBA8_STRAIGHT : DTR_RASTER_FORMAT_ALPHA8;
  result.flags = (color ? DTR_RASTER_GLYPH_COLOR : 0) |
                 (glyph_id == 0 ? DTR_RASTER_GLYPH_MISSING : 0);
  if (CGRectIsEmpty(bounds) || bounds.size.width == 0.0 ||
      bounds.size.height == 0.0) {
    result.originX = 0;
    result.originY = 0;
    result.width = 0;
    result.height = 0;
    result.rowStride = 0;
    result.pixels = [NSData data];
    *status = DTR_STATUS_OK;
    return result;
  }

  const double scaled_min_x = floor(CGRectGetMinX(bounds) * scale) - 1.0;
  const double scaled_max_x = ceil(CGRectGetMaxX(bounds) * scale) + 1.0;
  const double scaled_min_y = floor(CGRectGetMinY(bounds) * scale) - 1.0;
  const double scaled_max_y = ceil(CGRectGetMaxY(bounds) * scale) + 1.0;
  if (!isfinite(scaled_min_x) || !isfinite(scaled_max_x) ||
      !isfinite(scaled_min_y) || !isfinite(scaled_max_y) ||
      scaled_min_x < INT32_MIN || scaled_min_x > INT32_MAX ||
      scaled_max_y < INT32_MIN || scaled_max_y > INT32_MAX) {
    *status = DTR_STATUS_RESOURCE_EXHAUSTED;
    return nil;
  }
  const int64_t width = (int64_t)(scaled_max_x - scaled_min_x);
  const int64_t height = (int64_t)(scaled_max_y - scaled_min_y);
  const uint32_t bytes_per_pixel = color ? 4u : 1u;
  if (width <= 0 || height <= 0 || width > DTR_MAX_RASTER_DIMENSION ||
      height > DTR_MAX_RASTER_DIMENSION ||
      (uint64_t)width * bytes_per_pixel > UINT32_MAX ||
      (uint64_t)width * (uint64_t)height * bytes_per_pixel >
          DTR_MAX_RASTER_OUTPUT_BYTES) {
    *status = DTR_STATUS_RESOURCE_EXHAUSTED;
    return nil;
  }
  const uint32_t row_stride = (uint32_t)width * bytes_per_pixel;
  const size_t byte_length = (size_t)row_stride * (size_t)height;
  NSMutableData* drawing = [NSMutableData dataWithLength:byte_length];
  NSMutableData* published = [NSMutableData dataWithLength:byte_length];
  if (drawing == nil || published == nil) {
    *status = DTR_STATUS_RESOURCE_EXHAUSTED;
    return nil;
  }
  CGColorSpaceRef color_space =
      color ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray();
  if (color_space == NULL) {
    return nil;
  }
  const CGBitmapInfo bitmap_info =
      color ? (kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big)
            : (CGBitmapInfo)kCGImageAlphaNone;
  CGContextRef context = CGBitmapContextCreate(
      drawing.mutableBytes, (size_t)width, (size_t)height, 8, row_stride,
      color_space, bitmap_info);
  CGColorSpaceRelease(color_space);
  if (context == NULL) {
    return nil;
  }
  CGContextSetShouldAntialias(context, true);
  CGContextSetAllowsFontSmoothing(context, false);
  CGContextSetShouldSmoothFonts(context, false);
  // Bounds are device pixels; CoreText positions and font sizes remain points.
  CGContextScaleCTM(context, scale, scale);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  if (color) {
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
  } else {
    CGContextSetGrayFillColor(context, 1.0, 1.0);
  }
  const CGPoint position = CGPointMake(-scaled_min_x / scale,
                                       -scaled_min_y / scale);
  CTFontDrawGlyphs((__bridge CTFontRef)font, &glyph, &position, 1, context);
  CGContextRelease(context);

  const uint8_t* source = (const uint8_t*)drawing.bytes;
  uint8_t* destination = (uint8_t*)published.mutableBytes;
  for (uint32_t y = 0; y < (uint32_t)height; y++) {
    const uint8_t* source_row = source + y * row_stride;
    uint8_t* destination_row = destination + y * row_stride;
    if (!color) {
      memcpy(destination_row, source_row, row_stride);
      continue;
    }
    for (uint32_t x = 0; x < (uint32_t)width; x++) {
      const uint8_t alpha = source_row[x * 4u + 3u];
      destination_row[x * 4u + 3u] = alpha;
      for (uint32_t channel = 0; channel < 3; channel++) {
        const uint8_t component = source_row[x * 4u + channel];
        const uint32_t straight =
            alpha == 0
                ? 0
                : ((uint32_t)component * 255u + alpha / 2u) / alpha;
        destination_row[x * 4u + channel] =
            (uint8_t)(straight > 255u ? 255u : straight);
      }
    }
  }
  result.originX = (int32_t)scaled_min_x;
  result.originY = (int32_t)scaled_max_y;
  result.width = (uint32_t)width;
  result.height = (uint32_t)height;
  result.rowStride = row_stride;
  result.pixels = published;
  *status = DTR_STATUS_OK;
  return result;
}

@interface DtrMetalPipelineBundle : NSObject

@property(nonatomic, readonly) id<MTLRenderPipelineState> pipeline;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                        failure:(uint32_t*)failure;

@end

@implementation DtrMetalPipelineBundle

- (instancetype)initWithDevice:(id<MTLDevice>)device
                        failure:(uint32_t*)failure {
  self = [super init];
  if (failure == NULL) {
    return nil;
  }
  *failure = DTR_METAL_FAILURE_RESOURCE_ALLOCATION;
  if (self == nil || device == nil) {
    return nil;
  }
  const size_t library_length =
      (size_t)(dtr_metallib_end - dtr_metallib_start);
  if (library_length == 0) {
    *failure = DTR_METAL_FAILURE_SHADER_LIBRARY;
    return nil;
  }
  void* library_copy = malloc(library_length);
  if (library_copy == NULL) {
    return nil;
  }
  memcpy(library_copy, dtr_metallib_start, library_length);
  dispatch_data_t library_data = dispatch_data_create(
      library_copy, library_length,
      dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
      DISPATCH_DATA_DESTRUCTOR_FREE);
  NSError* error = nil;
  id<MTLLibrary> library = ConsumeMetalTestFailure(
                               DTR_METAL_TEST_FAILURE_CREATE_SHADER_LIBRARY)
                               ? nil
                               : [device newLibraryWithData:library_data
                                                      error:&error];
  if (library == nil || error != nil) {
    *failure = DTR_METAL_FAILURE_SHADER_LIBRARY;
    return nil;
  }
  id<MTLFunction> vertex =
      [library newFunctionWithName:@"dtr_terminal_vertex"];
  id<MTLFunction> fragment =
      [library newFunctionWithName:@"dtr_terminal_fragment"];
  if (vertex == nil || fragment == nil) {
    *failure = DTR_METAL_FAILURE_SHADER_FUNCTION;
    return nil;
  }
  MTLRenderPipelineDescriptor* descriptor =
      [[MTLRenderPipelineDescriptor alloc] init];
  descriptor.label = @"Dart Terminal packed pipeline";
  descriptor.vertexFunction = vertex;
  descriptor.fragmentFunction = fragment;
  descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  descriptor.colorAttachments[0].blendingEnabled = YES;
  descriptor.colorAttachments[0].sourceRGBBlendFactor =
      MTLBlendFactorSourceAlpha;
  descriptor.colorAttachments[0].destinationRGBBlendFactor =
      MTLBlendFactorOneMinusSourceAlpha;
  descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
  descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  descriptor.colorAttachments[0].destinationAlphaBlendFactor =
      MTLBlendFactorOneMinusSourceAlpha;
  descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
  _pipeline = [device newRenderPipelineStateWithDescriptor:descriptor
                                                     error:&error];
  if (_pipeline == nil || error != nil) {
    *failure = DTR_METAL_FAILURE_PIPELINE;
    return nil;
  }
  *failure = DTR_METAL_FAILURE_NONE;
  return self;
}

@end

@class DtrMetalRenderer;

@interface DtrTerminalMetalView : MTKView <NSTextInputClient>

@property(nonatomic, strong) DtrMetalPipelineBundle* terminalPipelines;
@property(nonatomic, strong) DtrMetalRenderer* terminalRenderer;
@property(nonatomic) uint64_t terminalRendererGeneration;
@property(nonatomic) uint64_t textInputClientId;
@property(nonatomic) uint64_t textInputEventGeneration;
@property(nonatomic) uint64_t textInputGeometryGeneration;
@property(nonatomic, strong) DtrTextInputQueue* textInputQueue;
@property(nonatomic, strong) NSAttributedString* terminalMarkedText;
@property(nonatomic) NSRange terminalMarkedSelection;
@property(nonatomic) NSRect terminalCaretRect;
@property(nonatomic, strong) NSEvent* terminalActiveKeyEvent;
@property(nonatomic) BOOL terminalRawKeyPosted;
@property(nonatomic, copy) NSString* terminalAccessibilityText;
@property(nonatomic, copy) NSData* terminalAccessibilityLines;
@property(nonatomic, copy) NSData* terminalAccessibilityColumnBoundaries;
@property(nonatomic) uint64_t terminalAccessibilityGeneration;
@property(nonatomic) uint32_t terminalAccessibilityRows;
@property(nonatomic) uint32_t terminalAccessibilityColumns;
@property(nonatomic) NSRange terminalAccessibilitySelection;
@property(nonatomic) BOOL terminalAccessibilityHasSelection;
@property(nonatomic) NSRange terminalAccessibilityCursor;
@property(nonatomic) uint32_t terminalAccessibilityCursorRow;
@property(nonatomic) uint32_t terminalAccessibilityCursorColumn;
@property(nonatomic) double terminalAccessibilityCellWidth;
@property(nonatomic) double terminalAccessibilityCellHeight;
@property(nonatomic) double terminalAccessibilityContentOriginX;
@property(nonatomic) double terminalAccessibilityContentOriginY;
@property(nonatomic) uint64_t terminalAccessibilityValueNotificationCount;
@property(nonatomic) uint64_t terminalAccessibilitySelectionNotificationCount;
@property(nonatomic) uint64_t terminalAccessibilityFocusNotificationCount;

- (BOOL)attachTextInputClient:(uint64_t)clientId;
- (BOOL)updateTextInputGeometry:(DtrTextInputGeometryV1)geometry;
- (void)detachTextInputClient;
- (BOOL)updateAccessibilitySnapshot:
            (DtrAccessibilitySnapshotHeaderV2)header
                           lines:(const DtrAccessibilityLineV1*)lines
                 columnBoundaries:(const uint32_t*)columnBoundaries
                             text:(const uint8_t*)text;
- (BOOL)runAccessibilityAcceptance:(uint64_t)generation;

@end

enum {
  DTR_METAL_SLOT_FREE = 0,
  DTR_METAL_SLOT_READY = 1,
  DTR_METAL_SLOT_IN_FLIGHT = 2,
};

@interface DtrMetalFrameSlot : NSObject

@property(nonatomic, strong) id<MTLBuffer> buffer;
@property(nonatomic) uint32_t state;
@property(nonatomic) uint64_t token;
@property(nonatomic) DtrMetalFrameHeaderV1 header;

@end

@implementation DtrMetalFrameSlot
@end

@interface DtrMetalRenderer : NSObject <MTKViewDelegate>

@property(nonatomic, readonly) uint64_t generation;
@property(nonatomic, readonly) DtrMetalRendererConfigV1 config;
@property(nonatomic, readonly) id<MTLDevice> device;
@property(nonatomic, readonly) DtrMetalPipelineBundle* pipelines;

- (instancetype)initWithConfig:(DtrMetalRendererConfigV1)config
                     generation:(uint64_t)generation
                        failure:(uint32_t*)failure;
- (int32_t)upload:(DtrMetalAtlasUploadV1)upload
            pixels:(const uint8_t*)pixels;
- (int32_t)resetAtlas:(DtrMetalAtlasResetV1)reset;
- (int32_t)bindView:(DtrTerminalMetalView*)view;
- (int32_t)submitFrame:(const uint8_t*)frame
                 length:(uint32_t)frameLength
                 output:(DtrMetalSubmissionV1*)output;
- (int32_t)copyState:(DtrMetalRendererStateV1*)output;
- (int32_t)requestDraw;
- (void)recordFaultLocked:(uint32_t)failure
          frameGeneration:(uint64_t)frameGeneration;
- (void)shutdown;
- (void)viewWillDeallocate:(DtrTerminalMetalView*)view;
- (int32_t)renderFrame:(const uint8_t*)frame
                length:(uint32_t)frameLength
                output:(uint8_t*)output
              capacity:(uint32_t)outputCapacity
              required:(uint32_t*)outputRequired;

@end

@implementation DtrMetalRenderer {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _commandQueue;
  DtrMetalPipelineBundle* _pipelines;
  id<MTLTexture> _alphaAtlas;
  id<MTLTexture> _colorAtlas;
  NSData* _alphaZeroPage;
  NSData* _colorZeroPage;
  uint64_t* _alphaPageGenerations;
  uint64_t* _colorPageGenerations;
  uint64_t _atlasGeneration;
  NSArray<DtrMetalFrameSlot*>* _slots;
  __weak DtrTerminalMetalView* _view;
  uint64_t _nextSubmissionToken;
  uint64_t _lastAcceptedFrameGeneration;
  uint64_t _lastSubmissionToken;
  uint64_t _lastPresentedFrameGeneration;
  uint64_t _acceptedSubmissionCount;
  uint64_t _completedSubmissionCount;
  uint64_t _staleReadyDropCount;
  uint64_t _backpressureCount;
  uint64_t _failureGeneration;
  uint64_t _lastFailedFrameGeneration;
  uint64_t _drawableUnavailableCount;
  uint64_t _commandFailureCount;
  uint64_t _gpuTimingSampleCount;
  uint64_t _gpuTotalTimeNs;
  uint64_t _gpuMaxTimeNs;
  uint64_t _acceptedAtlasUploadCount;
  uint64_t _acceptedAtlasUploadBytes;
  uint32_t _failureKind;
  BOOL _admitting;
  BOOL _shuttingDown;
  BOOL _everBound;
  NSLock* _lock;
  BOOL _counted;
}

- (instancetype)initWithConfig:(DtrMetalRendererConfigV1)config
                     generation:(uint64_t)generation
                        failure:(uint32_t*)failure {
  self = [super init];
  if (failure == NULL) {
    return nil;
  }
  *failure = DTR_METAL_FAILURE_RESOURCE_ALLOCATION;
  if (self == nil) {
    return nil;
  }
  _device = ConsumeMetalTestFailure(DTR_METAL_TEST_FAILURE_CREATE_DEVICE)
                ? nil
                : MTLCreateSystemDefaultDevice();
  if (_device == nil) {
    *failure = DTR_METAL_FAILURE_DEVICE_UNAVAILABLE;
    return nil;
  }
  _commandQueue = [_device newCommandQueue];
  if (_commandQueue == nil) {
    return nil;
  }
  _pipelines = [[DtrMetalPipelineBundle alloc] initWithDevice:_device
                                                      failure:failure];
  if (_pipelines == nil) {
    return nil;
  }
  MTLTextureDescriptor* alpha_descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
                                MTLPixelFormatR8Unorm
                                                         width:config.atlas_width
                                                        height:config.atlas_height
                                                     mipmapped:NO];
  alpha_descriptor.textureType = MTLTextureType2DArray;
  alpha_descriptor.arrayLength = config.maximum_alpha_pages;
  alpha_descriptor.storageMode = MTLStorageModeShared;
  alpha_descriptor.usage = MTLTextureUsageShaderRead;
  MTLTextureDescriptor* color_descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
                                MTLPixelFormatRGBA8Unorm
                                                         width:config.atlas_width
                                                        height:config.atlas_height
                                                     mipmapped:NO];
  color_descriptor.textureType = MTLTextureType2DArray;
  color_descriptor.arrayLength = config.maximum_color_pages;
  color_descriptor.storageMode = MTLStorageModeShared;
  color_descriptor.usage = MTLTextureUsageShaderRead;
  _alphaAtlas = [_device newTextureWithDescriptor:alpha_descriptor];
  _colorAtlas = [_device newTextureWithDescriptor:color_descriptor];
  _alphaPageGenerations = (uint64_t*)calloc(
      config.maximum_alpha_pages, sizeof(uint64_t));
  _colorPageGenerations = (uint64_t*)calloc(
      config.maximum_color_pages, sizeof(uint64_t));
  _alphaZeroPage = [NSMutableData
      dataWithLength:(NSUInteger)config.atlas_width * config.atlas_height];
  _colorZeroPage = [NSMutableData
      dataWithLength:(NSUInteger)config.atlas_width * config.atlas_height * 4u];
  if (_alphaAtlas == nil || _colorAtlas == nil ||
      _alphaPageGenerations == NULL || _colorPageGenerations == NULL ||
      _alphaZeroPage == nil || _colorZeroPage == nil) {
    return nil;
  }
  NSMutableArray<DtrMetalFrameSlot*>* slots =
      [NSMutableArray arrayWithCapacity:3];
  const NSUInteger slot_bytes =
      (NSUInteger)config.maximum_instances * sizeof(DtrMetalInstanceV1);
  for (NSUInteger index = 0; index < 3; index++) {
    DtrMetalFrameSlot* slot = [[DtrMetalFrameSlot alloc] init];
    slot.buffer = [_device newBufferWithLength:slot_bytes
                                       options:MTLResourceStorageModeShared];
    if (slot.buffer == nil) {
      return nil;
    }
    slot.state = DTR_METAL_SLOT_FREE;
    [slots addObject:slot];
  }
  _slots = [slots copy];
  _generation = generation;
  _config = config;
  _lock = [[NSLock alloc] init];
  _nextSubmissionToken = 1;
  _admitting = YES;
  [self clearAllAtlasTextures];
  atomic_fetch_add_explicit(&g_live_metal_renderer_count, 1,
                            memory_order_relaxed);
  _counted = YES;
  *failure = DTR_METAL_FAILURE_NONE;
  return self;
}

- (void)dealloc {
  free(_alphaPageGenerations);
  free(_colorPageGenerations);
  if (_counted) {
    atomic_fetch_sub_explicit(&g_live_metal_renderer_count, 1,
                              memory_order_relaxed);
  }
}

- (id<MTLDevice>)device {
  return _device;
}

- (DtrMetalPipelineBundle*)pipelines {
  return _pipelines;
}

- (BOOL)hasActiveSlotsLocked {
  for (DtrMetalFrameSlot* slot in _slots) {
    if (slot.state != DTR_METAL_SLOT_FREE) {
      return YES;
    }
  }
  return NO;
}

- (int32_t)requestDraw {
  [_lock lock];
  DtrTerminalMetalView* view = _view;
  BOOL has_ready = NO;
  for (DtrMetalFrameSlot* slot in _slots) {
    has_ready |= slot.state == DTR_METAL_SLOT_READY;
  }
  const BOOL should_schedule = _admitting && view != nil && has_ready;
  const int32_t result = !_admitting || view == nil ? DTR_STATUS_NOT_FOUND
                                                     : DTR_STATUS_OK;
  const uint64_t generation = self.generation;
  [_lock unlock];
  if (!should_schedule) {
    return result;
  }
  __weak DtrTerminalMetalView* weak_view = view;
  dispatch_async(dispatch_get_main_queue(), ^{
    DtrTerminalMetalView* strong_view = weak_view;
    if (strong_view != nil &&
        strong_view.terminalRendererGeneration == generation) {
      [strong_view setNeedsDisplay:YES];
    }
  });
  return DTR_STATUS_OK;
}

- (void)recordFaultLocked:(uint32_t)failure
          frameGeneration:(uint64_t)frameGeneration {
  if (_failureKind != DTR_METAL_FAILURE_NONE) {
    return;
  }
  _failureKind = failure;
  _failureGeneration = 1;
  _lastFailedFrameGeneration = frameGeneration;
  SaturatingIncrementMetric(&_commandFailureCount);
  _admitting = NO;
  for (DtrMetalFrameSlot* slot in _slots) {
    if (slot.state == DTR_METAL_SLOT_READY) {
      slot.state = DTR_METAL_SLOT_FREE;
    }
  }
}

- (int32_t)bindView:(DtrTerminalMetalView*)view {
  if (view == nil || ![view isKindOfClass:DtrTerminalMetalView.class]) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  [_lock lock];
  if (!_admitting || _everBound || _view != nil ||
      view.terminalRendererGeneration != 0) {
    [_lock unlock];
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  _view = view;
  _everBound = YES;
  view.device = _device;
  view.colorPixelFormat = MTLPixelFormatRGBA8Unorm;
  view.terminalPipelines = _pipelines;
  view.terminalRenderer = self;
  view.terminalRendererGeneration = self.generation;
  view.delegate = self;
  view.paused = YES;
  view.enableSetNeedsDisplay = YES;
  view.framebufferOnly = YES;
  [_lock unlock];
  return DTR_STATUS_OK;
}

- (void)detachOnMainThread {
  DtrTerminalMetalView* view = _view;
  if (view != nil &&
      view.terminalRendererGeneration == self.generation) {
    view.delegate = nil;
    view.paused = YES;
    view.terminalRendererGeneration = 0;
    view.terminalRenderer = nil;
  }
  [_lock lock];
  if (_view == view) {
    _view = nil;
  }
  [_lock unlock];
}

- (void)shutdown {
  [_lock lock];
  if (_shuttingDown) {
    [_lock unlock];
    return;
  }
  _shuttingDown = YES;
  _admitting = NO;
  for (DtrMetalFrameSlot* slot in _slots) {
    if (slot.state == DTR_METAL_SLOT_READY) {
      slot.state = DTR_METAL_SLOT_FREE;
    }
  }
  [_lock unlock];
  if ([NSThread isMainThread]) {
    [self detachOnMainThread];
  } else {
    DtrMetalRenderer* retained_self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [retained_self detachOnMainThread];
    });
  }
}

- (void)viewWillDeallocate:(DtrTerminalMetalView*)view {
  [_lock lock];
  if (_view == view) {
    _view = nil;
    _admitting = NO;
    for (DtrMetalFrameSlot* slot in _slots) {
      if (slot.state == DTR_METAL_SLOT_READY) {
        slot.state = DTR_METAL_SLOT_FREE;
      }
    }
  }
  [_lock unlock];
}

- (void)clearTexture:(id<MTLTexture>)texture
              slices:(uint32_t)slices
       bytesPerPixel:(uint32_t)bytesPerPixel {
  const NSUInteger row_stride = self.config.atlas_width * bytesPerPixel;
  NSData* zeros = bytesPerPixel == 1 ? _alphaZeroPage : _colorZeroPage;
  const MTLRegion region = MTLRegionMake2D(
      0, 0, self.config.atlas_width, self.config.atlas_height);
  for (uint32_t slice = 0; slice < slices; slice++) {
    [texture replaceRegion:region
               mipmapLevel:0
                     slice:slice
                 withBytes:zeros.bytes
               bytesPerRow:row_stride
             bytesPerImage:zeros.length];
  }
}

- (void)clearAllAtlasTextures {
  [self clearTexture:_alphaAtlas
              slices:self.config.maximum_alpha_pages
       bytesPerPixel:1];
  [self clearTexture:_colorAtlas
              slices:self.config.maximum_color_pages
       bytesPerPixel:4];
  memset(_alphaPageGenerations, 0,
         self.config.maximum_alpha_pages * sizeof(uint64_t));
  memset(_colorPageGenerations, 0,
         self.config.maximum_color_pages * sizeof(uint64_t));
}

- (void)clearTextureSlice:(id<MTLTexture>)texture
                    slice:(uint32_t)slice
            bytesPerPixel:(uint32_t)bytesPerPixel {
  const NSUInteger row_stride = self.config.atlas_width * bytesPerPixel;
  NSData* zeros = bytesPerPixel == 1 ? _alphaZeroPage : _colorZeroPage;
  [texture replaceRegion:MTLRegionMake2D(
                             0, 0, self.config.atlas_width,
                             self.config.atlas_height)
             mipmapLevel:0
                   slice:slice
               withBytes:zeros.bytes
             bytesPerRow:row_stride
           bytesPerImage:zeros.length];
}

- (int32_t)upload:(DtrMetalAtlasUploadV1)upload
            pixels:(const uint8_t*)pixels {
  [_lock lock];
  int32_t result = DTR_STATUS_OK;
  const BOOL is_alpha = upload.format == DTR_METAL_ATLAS_ALPHA8;
  const uint32_t page_limit = is_alpha
                                  ? self.config.maximum_alpha_pages
                                  : self.config.maximum_color_pages;
  const uint32_t bytes_per_pixel = is_alpha ? 1u : 4u;
  uint64_t* page_generations =
      is_alpha ? _alphaPageGenerations : _colorPageGenerations;
  id<MTLTexture> texture = is_alpha ? _alphaAtlas : _colorAtlas;
  if (!_admitting) {
    result = DTR_STATUS_NOT_FOUND;
  } else if (upload.atlas_generation == 0 || upload.page_generation == 0 ||
      upload.page_generation > UINT32_MAX || upload.page_index >= page_limit ||
      upload.width == 0 ||
      upload.height == 0 || upload.x > self.config.atlas_width ||
      upload.y > self.config.atlas_height ||
      upload.width > self.config.atlas_width - upload.x ||
      upload.height > self.config.atlas_height - upload.y ||
      upload.width > UINT32_MAX / bytes_per_pixel ||
      upload.row_stride != upload.width * bytes_per_pixel ||
      upload.height > UINT32_MAX / upload.row_stride ||
      upload.byte_length != upload.row_stride * upload.height ||
      pixels == NULL) {
    result = DTR_STATUS_INVALID_ARGUMENT;
  } else if (upload.renderer_generation != self.generation) {
    result = DTR_STATUS_STALE_GENERATION;
  } else if (upload.atlas_generation < _atlasGeneration ||
             (upload.atlas_generation == _atlasGeneration &&
              page_generations[upload.page_index] > upload.page_generation)) {
    result = DTR_STATUS_STALE_GENERATION;
  } else if ([self hasActiveSlotsLocked]) {
    result = DTR_STATUS_BACKPRESSURED;
  } else {
    if (upload.atlas_generation > _atlasGeneration) {
      _atlasGeneration = upload.atlas_generation;
    }
    if (result == DTR_STATUS_OK &&
        page_generations[upload.page_index] < upload.page_generation) {
      [self clearTextureSlice:texture
                        slice:upload.page_index
                bytesPerPixel:bytes_per_pixel];
      page_generations[upload.page_index] = upload.page_generation;
    }
    if (result == DTR_STATUS_OK) {
      [texture replaceRegion:MTLRegionMake2D(upload.x, upload.y, upload.width,
                                             upload.height)
                 mipmapLevel:0
                       slice:upload.page_index
                   withBytes:pixels
                 bytesPerRow:upload.row_stride
               bytesPerImage:upload.byte_length];
      SaturatingIncrementMetric(&_acceptedAtlasUploadCount);
      SaturatingAddMetric(&_acceptedAtlasUploadBytes, upload.byte_length);
    }
  }
  [_lock unlock];
  return result;
}

- (int32_t)resetAtlas:(DtrMetalAtlasResetV1)reset {
  [_lock lock];
  int32_t result = DTR_STATUS_OK;
  if (!_admitting) {
    result = DTR_STATUS_NOT_FOUND;
  } else if (reset.atlas_generation == 0) {
    result = DTR_STATUS_INVALID_ARGUMENT;
  } else if (reset.renderer_generation != self.generation ||
             reset.atlas_generation <= _atlasGeneration) {
    result = DTR_STATUS_STALE_GENERATION;
  } else if ([self hasActiveSlotsLocked]) {
    result = DTR_STATUS_BACKPRESSURED;
  } else {
    for (uint32_t slice = 0; slice < self.config.maximum_alpha_pages;
         slice++) {
      [self clearTextureSlice:_alphaAtlas slice:slice bytesPerPixel:1u];
      _alphaPageGenerations[slice] = 0;
    }
    for (uint32_t slice = 0; slice < self.config.maximum_color_pages;
         slice++) {
      [self clearTextureSlice:_colorAtlas slice:slice bytesPerPixel:4u];
      _colorPageGenerations[slice] = 0;
    }
    _atlasGeneration = reset.atlas_generation;
  }
  [_lock unlock];
  return result;
}

- (int32_t)validateFrame:(const uint8_t*)frame
                   length:(uint32_t)frameLength
                   header:(DtrMetalFrameHeaderV1*)header {
  if (frame == NULL || header == NULL ||
      frameLength < sizeof(DtrMetalFrameHeaderV1)) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  memcpy(header, frame, sizeof(*header));
  if (header->magic != DTR_METAL_FRAME_MAGIC ||
      header->version != DTR_METAL_FRAME_VERSION ||
      header->header_size != sizeof(DtrMetalFrameHeaderV1) ||
      header->total_size != frameLength || header->frame_generation == 0 ||
      header->viewport_width == 0 ||
      header->viewport_height == 0 ||
      header->viewport_width > self.config.maximum_viewport_width ||
      header->viewport_height > self.config.maximum_viewport_height ||
      header->scale_16_16 == 0 || header->scale_16_16 > (16u << 16) ||
      header->instance_count > self.config.maximum_instances ||
      header->instance_stride != sizeof(DtrMetalInstanceV1) ||
      header->instances_offset != sizeof(DtrMetalFrameHeaderV1) ||
      header->reserved[0] != 0 || header->reserved[1] != 0 ||
      header->reserved[2] != 0 ||
      header->instance_count >
          (DTR_MAX_METAL_FRAME_BYTES - sizeof(DtrMetalFrameHeaderV1)) /
              sizeof(DtrMetalInstanceV1) ||
      frameLength != sizeof(DtrMetalFrameHeaderV1) +
                         header->instance_count *
                             sizeof(DtrMetalInstanceV1)) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (header->renderer_generation != self.generation) {
    return DTR_STATUS_STALE_GENERATION;
  }
  uint32_t previous_layer = 0;
  for (uint32_t index = 0; index < header->instance_count; index++) {
    DtrMetalInstanceV1 instance;
    memcpy(&instance,
           frame + sizeof(DtrMetalFrameHeaderV1) +
               index * sizeof(DtrMetalInstanceV1),
           sizeof(instance));
    const BOOL glyph =
        instance.kind == DTR_METAL_INSTANCE_ALPHA_GLYPH ||
        instance.kind == DTR_METAL_INSTANCE_COLOR_GLYPH;
    const uint32_t layer =
        instance.kind == DTR_METAL_INSTANCE_COLOR_GLYPH
            ? DTR_METAL_INSTANCE_ALPHA_GLYPH
            : instance.kind;
    const int64_t right = (int64_t)instance.x + instance.width;
    const int64_t bottom = (int64_t)instance.y + instance.height;
    if (instance.kind < DTR_METAL_INSTANCE_CELL_BACKGROUND ||
        instance.kind > DTR_METAL_INSTANCE_CURSOR ||
        layer < previous_layer || instance.width == 0 ||
        instance.height == 0 || instance.width > header->viewport_width ||
        instance.height > header->viewport_height || right <= 0 || bottom <= 0 ||
        instance.x >= (int32_t)header->viewport_width ||
        instance.y >= (int32_t)header->viewport_height) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    previous_layer = layer;
    if (!glyph) {
      if (instance.atlas_x != 0 || instance.atlas_y != 0 ||
          instance.atlas_width != 0 || instance.atlas_height != 0 ||
          instance.page_index != 0 || instance.page_generation != 0) {
        return DTR_STATUS_INVALID_ARGUMENT;
      }
      continue;
    }
    const BOOL alpha = instance.kind == DTR_METAL_INSTANCE_ALPHA_GLYPH;
    const uint32_t page_limit = alpha
                                    ? self.config.maximum_alpha_pages
                                    : self.config.maximum_color_pages;
    const uint64_t* page_generations =
        alpha ? _alphaPageGenerations : _colorPageGenerations;
    if (instance.atlas_width == 0 || instance.atlas_height == 0 ||
        instance.atlas_width != instance.width ||
        instance.atlas_height != instance.height ||
        instance.atlas_x > self.config.atlas_width ||
        instance.atlas_y > self.config.atlas_height ||
        instance.atlas_width > self.config.atlas_width - instance.atlas_x ||
        instance.atlas_height > self.config.atlas_height - instance.atlas_y ||
        instance.page_index >= page_limit || instance.page_generation == 0) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    if (header->atlas_generation != _atlasGeneration ||
        page_generations[instance.page_index] != instance.page_generation) {
      return DTR_STATUS_STALE_GENERATION;
    }
  }
  return DTR_STATUS_OK;
}

- (int32_t)submitFrame:(const uint8_t*)frame
                 length:(uint32_t)frameLength
                 output:(DtrMetalSubmissionV1*)output {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  uint32_t output_header[2];
  memcpy(output_header, output, sizeof(output_header));
  if (output_header[0] < sizeof(DtrMetalSubmissionV1) ||
      output_header[1] != DTR_METAL_SUBMISSION_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  DtrMetalSubmissionV1 empty = {0};
  empty.struct_size = sizeof(empty);
  empty.version = DTR_METAL_SUBMISSION_VERSION;
  memcpy(output, &empty, sizeof(empty));

  [_lock lock];
  DtrMetalFrameHeaderV1 header;
  int32_t result = [self validateFrame:frame length:frameLength header:&header];
  if (result != DTR_STATUS_OK) {
    [_lock unlock];
    return result;
  }
  if (!_admitting || _view == nil) {
    [_lock unlock];
    return DTR_STATUS_NOT_FOUND;
  }
  if (header.frame_generation <= _lastAcceptedFrameGeneration) {
    [_lock unlock];
    return DTR_STATUS_STALE_GENERATION;
  }
  DtrMetalFrameSlot* selected = nil;
  for (DtrMetalFrameSlot* slot in _slots) {
    if (slot.state == DTR_METAL_SLOT_FREE) {
      selected = slot;
      break;
    }
  }
  if (selected == nil) {
    SaturatingIncrementMetric(&_backpressureCount);
    [_lock unlock];
    return DTR_STATUS_BACKPRESSURED;
  }
  if (_nextSubmissionToken == 0 || _nextSubmissionToken == UINT64_MAX) {
    [_lock unlock];
    return DTR_STATUS_RESOURCE_EXHAUSTED;
  }
  const uint64_t token = _nextSubmissionToken++;
  const NSUInteger instance_bytes =
      header.instance_count * sizeof(DtrMetalInstanceV1);
  if (instance_bytes > 0) {
    memcpy(selected.buffer.contents, frame + header.instances_offset,
           instance_bytes);
  }
  selected.header = header;
  selected.token = token;
  selected.state = DTR_METAL_SLOT_READY;
  _lastAcceptedFrameGeneration = header.frame_generation;
  _lastSubmissionToken = token;
  SaturatingIncrementMetric(&_acceptedSubmissionCount);
  DtrMetalSubmissionV1 accepted = {0};
  accepted.struct_size = sizeof(accepted);
  accepted.version = DTR_METAL_SUBMISSION_VERSION;
  accepted.renderer_generation = self.generation;
  accepted.submission_token = token;
  accepted.frame_generation = header.frame_generation;
  memcpy(output, &accepted, sizeof(accepted));
  [_lock unlock];
  [self requestDraw];
  return DTR_STATUS_OK;
}

- (int32_t)copyState:(DtrMetalRendererStateV1*)output {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  uint32_t output_header[2];
  memcpy(output_header, output, sizeof(output_header));
  if (output_header[0] < sizeof(DtrMetalRendererStateV1) ||
      output_header[1] != DTR_METAL_RENDERER_STATE_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  [_lock lock];
  uint32_t ready = 0;
  uint32_t in_flight = 0;
  uint64_t first_active_token = UINT64_MAX;
  for (DtrMetalFrameSlot* slot in _slots) {
    if (slot.state == DTR_METAL_SLOT_READY) {
      ++ready;
    } else if (slot.state == DTR_METAL_SLOT_IN_FLIGHT) {
      ++in_flight;
    }
    if (slot.state != DTR_METAL_SLOT_FREE &&
        slot.token < first_active_token) {
      first_active_token = slot.token;
    }
  }
  DtrMetalRendererStateV1 state = {0};
  state.struct_size = sizeof(state);
  state.version = DTR_METAL_RENDERER_STATE_VERSION;
  state.renderer_generation = self.generation;
  state.last_accepted_frame_generation = _lastAcceptedFrameGeneration;
  state.last_submission_token = _lastSubmissionToken;
  state.retired_through_token =
      first_active_token == UINT64_MAX ? _lastSubmissionToken
                                       : first_active_token - 1;
  state.last_presented_frame_generation = _lastPresentedFrameGeneration;
  state.accepted_submission_count = _acceptedSubmissionCount;
  state.completed_submission_count = _completedSubmissionCount;
  state.stale_ready_drop_count = _staleReadyDropCount;
  state.backpressure_count = _backpressureCount;
  state.ready_slot_count = ready;
  state.in_flight_slot_count = in_flight;
  state.flags = (_view == nil ? 0u : DTR_METAL_RENDERER_STATE_BOUND) |
                (_admitting ? DTR_METAL_RENDERER_STATE_ADMITTING : 0u) |
                (_failureKind == DTR_METAL_FAILURE_NONE
                     ? 0u
                     : DTR_METAL_RENDERER_STATE_FAULTED);
  state.failure_kind = _failureKind;
  state.failure_generation = _failureGeneration;
  state.last_failed_frame_generation = _lastFailedFrameGeneration;
  state.drawable_unavailable_count = _drawableUnavailableCount;
  state.command_failure_count = _commandFailureCount;
  state.gpu_timing_sample_count = _gpuTimingSampleCount;
  state.gpu_total_time_ns = _gpuTotalTimeNs;
  state.gpu_max_time_ns = _gpuMaxTimeNs;
  state.accepted_atlas_upload_count = _acceptedAtlasUploadCount;
  state.accepted_atlas_upload_bytes = _acceptedAtlasUploadBytes;
  memcpy(output, &state, sizeof(state));
  [_lock unlock];
  return DTR_STATUS_OK;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

- (void)drawInMTKView:(MTKView*)view {
  @autoreleasepool {
    [_lock lock];
    BOOL has_ready_frame = NO;
    if (_admitting && _view == view) {
      for (DtrMetalFrameSlot* slot in _slots) {
        if (slot.state == DTR_METAL_SLOT_READY) {
          has_ready_frame = YES;
          break;
        }
      }
    }
    [_lock unlock];
    if (!has_ready_frame) {
      return;
    }

    const BOOL injected_drawable_failure = ConsumeMetalTestFailure(
        DTR_METAL_TEST_FAILURE_DRAWABLE_UNAVAILABLE);
    MTLRenderPassDescriptor* pass =
        injected_drawable_failure ? nil : view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable =
        injected_drawable_failure ? nil : view.currentDrawable;
    if (pass == nil || drawable == nil) {
      [_lock lock];
      if (_admitting && _view == view) {
        SaturatingIncrementMetric(&_drawableUnavailableCount);
      }
      [_lock unlock];
      return;
    }
    [_lock lock];
    if (!_admitting || _view != view) {
      [_lock unlock];
      return;
    }
    DtrMetalFrameSlot* selected = nil;
    for (DtrMetalFrameSlot* slot in _slots) {
      if (slot.state == DTR_METAL_SLOT_READY &&
          (selected == nil || slot.header.frame_generation >
                                  selected.header.frame_generation)) {
        selected = slot;
      }
    }
    if (selected == nil) {
      [_lock unlock];
      return;
    }
    for (DtrMetalFrameSlot* slot in _slots) {
      if (slot != selected && slot.state == DTR_METAL_SLOT_READY) {
        slot.state = DTR_METAL_SLOT_FREE;
        SaturatingIncrementMetric(&_staleReadyDropCount);
      }
    }
    selected.state = DTR_METAL_SLOT_IN_FLIGHT;
    const uint64_t selected_token = selected.token;
    const DtrMetalFrameHeaderV1 header = selected.header;
    id<MTLBuffer> instance_buffer = selected.buffer;
    id<MTLTexture> alpha_atlas = _alphaAtlas;
    id<MTLTexture> color_atlas = _colorAtlas;
    [_lock unlock];

    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    const uint32_t background = header.background_rgba;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(
        ((background >> 24) & 0xffu) / 255.0,
        ((background >> 16) & 0xffu) / 255.0,
        ((background >> 8) & 0xffu) / 255.0,
        (background & 0xffu) / 255.0);
    const BOOL injected_encoding_failure = ConsumeMetalTestFailure(
        DTR_METAL_TEST_FAILURE_COMMAND_ENCODING);
    id<MTLCommandBuffer> command =
        injected_encoding_failure ? nil : [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = command == nil
                                                ? nil
                                                : [command
                                                      renderCommandEncoderWithDescriptor:
                                                          pass];
    if (command == nil || encoder == nil) {
      [_lock lock];
      if (selected.state == DTR_METAL_SLOT_IN_FLIGHT &&
          selected.token == selected_token) {
        selected.state = DTR_METAL_SLOT_FREE;
      }
      [self recordFaultLocked:DTR_METAL_FAILURE_COMMAND_ENCODING
              frameGeneration:header.frame_generation];
      [_lock unlock];
      return;
    }
    if (header.instance_count != 0) {
      const float viewport[2] = {(float)header.viewport_width,
                                 (float)header.viewport_height};
      [encoder setRenderPipelineState:_pipelines.pipeline];
      [encoder setVertexBuffer:instance_buffer offset:0 atIndex:0];
      [encoder setVertexBytes:viewport length:sizeof(viewport) atIndex:1];
      [encoder setFragmentTexture:alpha_atlas atIndex:0];
      [encoder setFragmentTexture:color_atlas atIndex:1];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                  vertexStart:0
                  vertexCount:4
                instanceCount:header.instance_count];
    }
    [encoder endEncoding];
    [command presentDrawable:drawable];
    const BOOL injected_completion_failure = ConsumeMetalTestFailure(
        DTR_METAL_TEST_FAILURE_COMMAND_COMPLETION);
    __weak DtrMetalRenderer* weak_self = self;
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
      DtrMetalRenderer* strong_self = weak_self;
      if (strong_self == nil) {
        return;
      }
      [strong_self->_lock lock];
      if (selected.state == DTR_METAL_SLOT_IN_FLIGHT &&
          selected.token == selected_token) {
        selected.state = DTR_METAL_SLOT_FREE;
        if (!injected_completion_failure &&
            completed.status == MTLCommandBufferStatusCompleted) {
          SaturatingIncrementMetric(&strong_self->_completedSubmissionCount);
          const uint64_t gpu_duration = GpuDurationNanoseconds(completed);
          if (gpu_duration != 0) {
            SaturatingIncrementMetric(&strong_self->_gpuTimingSampleCount);
            SaturatingAddMetric(&strong_self->_gpuTotalTimeNs, gpu_duration);
            if (gpu_duration > strong_self->_gpuMaxTimeNs) {
              strong_self->_gpuMaxTimeNs = gpu_duration;
            }
          }
          if (header.frame_generation >
              strong_self->_lastPresentedFrameGeneration) {
            strong_self->_lastPresentedFrameGeneration =
                header.frame_generation;
          }
        } else {
          uint32_t failure = DTR_METAL_FAILURE_COMMAND_EXECUTION;
          NSError* error = completed.error;
          if (error != nil &&
              [error.domain isEqualToString:MTLCommandBufferErrorDomain] &&
              error.code == MTLCommandBufferErrorDeviceRemoved) {
            failure = DTR_METAL_FAILURE_DEVICE_LOST;
          }
          [strong_self recordFaultLocked:failure
                         frameGeneration:header.frame_generation];
        }
      }
      [strong_self->_lock unlock];
      [strong_self requestDraw];
    }];
    [command commit];
  }
}

- (int32_t)renderFrame:(const uint8_t*)frame
                length:(uint32_t)frameLength
                output:(uint8_t*)output
              capacity:(uint32_t)outputCapacity
              required:(uint32_t*)outputRequired {
  if (outputRequired == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  *outputRequired = 0;
  [_lock lock];
  DtrMetalFrameHeaderV1 header;
  int32_t result = [self validateFrame:frame length:frameLength header:&header];
  if (result != DTR_STATUS_OK) {
    [_lock unlock];
    return result;
  }
  const uint64_t required =
      (uint64_t)header.viewport_width * header.viewport_height * 4u;
  if (required > UINT32_MAX) {
    [_lock unlock];
    return DTR_STATUS_RESOURCE_EXHAUSTED;
  }
  *outputRequired = (uint32_t)required;
  if (output == NULL || outputCapacity < required) {
    result = output == NULL && outputCapacity != 0
                 ? DTR_STATUS_INVALID_ARGUMENT
                 : DTR_STATUS_BUFFER_TOO_SMALL;
    [_lock unlock];
    return result;
  }
  MTLTextureDescriptor* target_descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
                                MTLPixelFormatRGBA8Unorm
                                                         width:header.viewport_width
                                                        height:header.viewport_height
                                                     mipmapped:NO];
  target_descriptor.storageMode = MTLStorageModeShared;
  target_descriptor.usage = MTLTextureUsageRenderTarget;
  id<MTLTexture> target = [_device newTextureWithDescriptor:target_descriptor];
  id<MTLCommandBuffer> command = [_commandQueue commandBuffer];
  if (target == nil || command == nil) {
    [_lock unlock];
    return DTR_STATUS_RESOURCE_EXHAUSTED;
  }
  MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture = target;
  pass.colorAttachments[0].loadAction = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  const uint32_t background = header.background_rgba;
  pass.colorAttachments[0].clearColor = MTLClearColorMake(
      ((background >> 24) & 0xffu) / 255.0,
      ((background >> 16) & 0xffu) / 255.0,
      ((background >> 8) & 0xffu) / 255.0, (background & 0xffu) / 255.0);
  id<MTLRenderCommandEncoder> encoder =
      [command renderCommandEncoderWithDescriptor:pass];
  if (encoder == nil) {
    [_lock unlock];
    return DTR_STATUS_INTERNAL;
  }
  if (header.instance_count != 0) {
    const NSUInteger instance_bytes =
        header.instance_count * sizeof(DtrMetalInstanceV1);
    id<MTLBuffer> instances = [_device
        newBufferWithBytes:frame + header.instances_offset
                    length:instance_bytes
                   options:MTLResourceStorageModeShared];
    if (instances == nil) {
      [encoder endEncoding];
      [_lock unlock];
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    const float viewport[2] = {(float)header.viewport_width,
                               (float)header.viewport_height};
    [encoder setRenderPipelineState:_pipelines.pipeline];
    [encoder setVertexBuffer:instances offset:0 atIndex:0];
    [encoder setVertexBytes:viewport length:sizeof(viewport) atIndex:1];
    [encoder setFragmentTexture:_alphaAtlas atIndex:0];
    [encoder setFragmentTexture:_colorAtlas atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4
              instanceCount:header.instance_count];
  }
  [encoder endEncoding];
  [command commit];
  [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted) {
    [_lock unlock];
    return DTR_STATUS_INTERNAL;
  }
  [target getBytes:output
       bytesPerRow:header.viewport_width * 4u
        fromRegion:MTLRegionMake2D(0, 0, header.viewport_width,
                                  header.viewport_height)
       mipmapLevel:0];
  [_lock unlock];
  return DTR_STATUS_OK;
}

@end

static NSLock* MetalRendererRegistryLock(void) {
  static NSLock* lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static NSMutableDictionary<NSNumber*, DtrMetalRenderer*>*
MetalRendererRegistry(void) {
  static NSMutableDictionary<NSNumber*, DtrMetalRenderer*>* registry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registry = [[NSMutableDictionary alloc] init];
  });
  return registry;
}

static void RetainMetalRendererForHandle(
    uint64_t handle, DtrMetalRenderer* __strong* output) {
  *output = nil;
  if (handle == 0) {
    return;
  }
  NSLock* lock = MetalRendererRegistryLock();
  [lock lock];
  *output = MetalRendererRegistry()[@(handle)];
  [lock unlock];
}

@implementation DtrTerminalMetalView

static NSString* TextInputPlainString(id value) {
  if ([value isKindOfClass:NSString.class]) {
    return (NSString*)value;
  }
  if ([value isKindOfClass:NSAttributedString.class]) {
    return ((NSAttributedString*)value).string;
  }
  return nil;
}

- (instancetype)initWithFrame:(NSRect)frame {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) {
    return nil;
  }
  self = [super initWithFrame:frame device:device];
  if (self != nil) {
    uint32_t failure = DTR_METAL_FAILURE_NONE;
    DtrMetalPipelineBundle* pipelines =
        [[DtrMetalPipelineBundle alloc] initWithDevice:device
                                               failure:&failure];
    if (pipelines == nil) {
      return nil;
    }
    self.terminalPipelines = pipelines;
    atomic_fetch_add_explicit(&g_live_view_count, 1, memory_order_relaxed);
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoResizeDrawable = YES;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.framebufferOnly = YES;
    self.delegate = nil;
    self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
    self.terminalMarkedSelection = NSMakeRange(0, 0);
    self.terminalCaretRect = NSMakeRect(0, 0, 2, 20);
    self.terminalAccessibilityText = @"";
    self.terminalAccessibilityLines = [NSData data];
    self.terminalAccessibilityColumnBoundaries = [NSData data];
    self.terminalAccessibilitySelection = NSMakeRange(0, 0);
    self.terminalAccessibilityCursor = NSMakeRange(NSNotFound, 0);
    self.terminalAccessibilityCursorRow = UINT32_MAX;
    self.terminalAccessibilityCursorColumn = UINT32_MAX;
    self.terminalAccessibilityCellWidth = 1;
    self.terminalAccessibilityCellHeight = 1;
  }
  return self;
}

- (void)dealloc {
  [self detachTextInputClient];
  [_terminalRenderer viewWillDeallocate:self];
  atomic_fetch_sub_explicit(&g_live_view_count, 1, memory_order_relaxed);
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
  const BOOL accepted = [super becomeFirstResponder];
  if (accepted) {
    SaturatingIncrementMetric(&_terminalAccessibilityFocusNotificationCount);
    NSAccessibilityPostNotification(
        self, NSAccessibilityFocusedUIElementChangedNotification);
  }
  return accepted;
}

- (BOOL)resignFirstResponder {
  const BOOL accepted = [super resignFirstResponder];
  if (accepted) {
    SaturatingIncrementMetric(&_terminalAccessibilityFocusNotificationCount);
    NSAccessibilityPostNotification(
        self, NSAccessibilityFocusedUIElementChangedNotification);
  }
  return accepted;
}

- (BOOL)isAccessibilityElement {
  return YES;
}

- (NSString*)accessibilityRole {
  return NSAccessibilityTextAreaRole;
}

- (NSString*)accessibilityLabel {
  return @"Terminal";
}

- (id)accessibilityValue {
  return self.terminalAccessibilityText;
}

- (BOOL)isAccessibilityFocused {
  return self.window != nil && self.window.firstResponder == self;
}

- (NSRange)accessibilityVisibleCharacterRange {
  return NSMakeRange(0, self.terminalAccessibilityText.length);
}

- (NSRange)accessibilitySharedCharacterRange {
  return [self accessibilityVisibleCharacterRange];
}

- (NSInteger)accessibilityNumberOfCharacters {
  return (NSInteger)self.terminalAccessibilityText.length;
}

- (NSString*)accessibilitySelectedText {
  const NSRange range = self.terminalAccessibilitySelection;
  return NSMaxRange(range) <= self.terminalAccessibilityText.length
             ? [self.terminalAccessibilityText substringWithRange:range]
             : @"";
}

- (NSRange)accessibilitySelectedTextRange {
  return self.terminalAccessibilitySelection;
}

- (NSArray<NSValue*>*)accessibilitySelectedTextRanges {
  return @[ [NSValue valueWithRange:self.terminalAccessibilitySelection] ];
}

- (NSInteger)accessibilityInsertionPointLineNumber {
  return self.terminalAccessibilityCursor.location == NSNotFound
             ? NSNotFound
             : (NSInteger)self.terminalAccessibilityCursorRow;
}

- (const DtrAccessibilityLineV1*)terminalAccessibilityLineAtIndex:
    (NSUInteger)index {
  if (index >= self.terminalAccessibilityRows ||
      self.terminalAccessibilityLines.length !=
          self.terminalAccessibilityRows * sizeof(DtrAccessibilityLineV1)) {
    return NULL;
  }
  return ((const DtrAccessibilityLineV1*)
              self.terminalAccessibilityLines.bytes) +
         index;
}

- (const uint32_t*)terminalAccessibilityBoundariesForLine:
    (const DtrAccessibilityLineV1*)line {
  if (line == NULL ||
      self.terminalAccessibilityColumnBoundaries.length % sizeof(uint32_t) !=
          0) {
    return NULL;
  }
  const NSUInteger count = self.terminalAccessibilityColumnBoundaries.length /
                           sizeof(uint32_t);
  if (line->first_column_boundary > count ||
      line->column_boundary_count >
          count - line->first_column_boundary) {
    return NULL;
  }
  return ((const uint32_t*)
              self.terminalAccessibilityColumnBoundaries.bytes) +
         line->first_column_boundary;
}

- (NSInteger)terminalAccessibilityLineForUtf16Index:(NSUInteger)index {
  if (index > self.terminalAccessibilityText.length) return NSNotFound;
  for (uint32_t row = 0; row < self.terminalAccessibilityRows; row++) {
    const DtrAccessibilityLineV1* line =
        [self terminalAccessibilityLineAtIndex:row];
    if (line == NULL) return NSNotFound;
    const NSUInteger end =
        (NSUInteger)line->utf16_start + line->utf16_length;
    if (index <= end || row + 1 == self.terminalAccessibilityRows) {
      return row;
    }
  }
  return NSNotFound;
}

- (NSUInteger)terminalAccessibilityColumnForLine:
                  (const DtrAccessibilityLineV1*)line
                                          index:(NSUInteger)index {
  const uint32_t* boundaries =
      [self terminalAccessibilityBoundariesForLine:line];
  if (boundaries == NULL || line->column_boundary_count == 0) return 0;
  const NSUInteger requested_relative =
      index <= line->utf16_start ? 0 : index - line->utf16_start;
  const NSUInteger relative =
      requested_relative < line->utf16_length ? requested_relative
                                              : line->utf16_length;
  NSUInteger group_start = 0;
  for (NSUInteger column = 0;
       column + 1 < line->column_boundary_count; column++) {
    if (boundaries[column] != boundaries[group_start]) group_start = column;
    if (relative < boundaries[column + 1]) return group_start;
    if (relative == boundaries[column]) return group_start;
  }
  return line->column_boundary_count - 1;
}

- (NSString*)accessibilityStringForRange:(NSRange)range {
  if (range.location == NSNotFound ||
      range.location > self.terminalAccessibilityText.length ||
      range.length > self.terminalAccessibilityText.length - range.location) {
    return nil;
  }
  return [self.terminalAccessibilityText substringWithRange:range];
}

- (NSAttributedString*)accessibilityAttributedStringForRange:(NSRange)range {
  NSString* value = [self accessibilityStringForRange:range];
  return value == nil ? nil
                      : [[NSAttributedString alloc] initWithString:value];
}

- (NSInteger)accessibilityLineForIndex:(NSInteger)index {
  if (index < 0) return NSNotFound;
  return [self terminalAccessibilityLineForUtf16Index:(NSUInteger)index];
}

- (NSRange)accessibilityRangeForLine:(NSInteger)lineNumber {
  if (lineNumber < 0 ||
      (NSUInteger)lineNumber >= self.terminalAccessibilityRows) {
    return NSMakeRange(NSNotFound, 0);
  }
  const DtrAccessibilityLineV1* line =
      [self terminalAccessibilityLineAtIndex:(NSUInteger)lineNumber];
  if (line == NULL) return NSMakeRange(NSNotFound, 0);
  const NSUInteger newline =
      (NSUInteger)lineNumber + 1 < self.terminalAccessibilityRows ? 1 : 0;
  return NSMakeRange(line->utf16_start, line->utf16_length + newline);
}

- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
  if (index < 0 || (NSUInteger)index > self.terminalAccessibilityText.length) {
    return NSMakeRange(NSNotFound, 0);
  }
  if ((NSUInteger)index == self.terminalAccessibilityText.length) {
    return NSMakeRange((NSUInteger)index, 0);
  }
  return [self.terminalAccessibilityText
      rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index];
}

- (NSRange)accessibilityStyleRangeForIndex:(NSInteger)index {
  const NSInteger line = [self accessibilityLineForIndex:index];
  return line == NSNotFound ? NSMakeRange(NSNotFound, 0)
                            : [self accessibilityRangeForLine:line];
}

- (NSRange)accessibilityRangeForPosition:(NSPoint)point {
  NSPoint window_point = self.window == nil
                             ? point
                             : [self.window convertPointFromScreen:point];
  const NSPoint local = [self convertPoint:window_point fromView:nil];
  if (!isfinite(local.x) || !isfinite(local.y) || local.x < 0 || local.y < 0 ||
      self.terminalAccessibilityCellWidth <= 0 ||
      self.terminalAccessibilityCellHeight <= 0 ||
      local.x < self.terminalAccessibilityContentOriginX ||
      local.y < self.terminalAccessibilityContentOriginY) {
    return NSMakeRange(NSNotFound, 0);
  }
  const CGFloat content_x =
      local.x - self.terminalAccessibilityContentOriginX;
  const CGFloat content_y =
      local.y - self.terminalAccessibilityContentOriginY;
  if (content_x >= self.terminalAccessibilityColumns *
                       self.terminalAccessibilityCellWidth ||
      content_y >= self.terminalAccessibilityRows *
                       self.terminalAccessibilityCellHeight) {
    return NSMakeRange(NSNotFound, 0);
  }
  const NSUInteger row =
      (NSUInteger)floor(content_y / self.terminalAccessibilityCellHeight);
  if (row >= self.terminalAccessibilityRows) {
    return NSMakeRange(NSNotFound, 0);
  }
  const DtrAccessibilityLineV1* line =
      [self terminalAccessibilityLineAtIndex:row];
  const uint32_t* boundaries =
      [self terminalAccessibilityBoundariesForLine:line];
  if (line == NULL || boundaries == NULL) {
    return NSMakeRange(NSNotFound, 0);
  }
  NSUInteger column =
      (NSUInteger)floor(content_x / self.terminalAccessibilityCellWidth);
  const NSUInteger last_column = line->column_boundary_count - 1;
  if (column > last_column) column = last_column;
  const NSUInteger index = line->utf16_start + boundaries[column];
  return [self accessibilityRangeForIndex:(NSInteger)index];
}

- (NSRect)accessibilityFrameForRange:(NSRange)range {
  if (range.location == NSNotFound ||
      range.location > self.terminalAccessibilityText.length ||
      range.length > self.terminalAccessibilityText.length - range.location ||
      self.terminalAccessibilityRows == 0) {
    return NSZeroRect;
  }
  const NSInteger first_row =
      [self terminalAccessibilityLineForUtf16Index:range.location];
  const NSUInteger terminal_index =
      range.length == 0 ? range.location : NSMaxRange(range) - 1;
  const NSInteger last_row =
      [self terminalAccessibilityLineForUtf16Index:terminal_index];
  if (first_row == NSNotFound || last_row == NSNotFound ||
      last_row < first_row) {
    return NSZeroRect;
  }
  const DtrAccessibilityLineV1* first =
      [self terminalAccessibilityLineAtIndex:(NSUInteger)first_row];
  const DtrAccessibilityLineV1* last =
      [self terminalAccessibilityLineAtIndex:(NSUInteger)last_row];
  if (first == NULL || last == NULL) return NSZeroRect;
  NSUInteger first_column =
      [self terminalAccessibilityColumnForLine:first index:range.location];
  NSUInteger end_column = first_column + 1;
  if (first_row == last_row && range.length > 0) {
    end_column = [self terminalAccessibilityColumnForLine:first
                                                    index:NSMaxRange(range)];
    if (end_column <= first_column) ++end_column;
  }
  const CGFloat x =
      self.terminalAccessibilityContentOriginX +
      (first_row == last_row
           ? first_column * self.terminalAccessibilityCellWidth
           : 0);
  const CGFloat requested_width =
      (end_column - first_column) * self.terminalAccessibilityCellWidth;
  const CGFloat width =
      first_row == last_row
          ? (requested_width > self.terminalAccessibilityCellWidth
                 ? requested_width
                 : self.terminalAccessibilityCellWidth)
          : self.terminalAccessibilityColumns *
                self.terminalAccessibilityCellWidth;
  NSRect local = NSMakeRect(
      x,
      self.terminalAccessibilityContentOriginY +
          first_row * self.terminalAccessibilityCellHeight,
      width,
      (last_row - first_row + 1) * self.terminalAccessibilityCellHeight);
  NSRect window_rect = [self convertRect:local toView:nil];
  return self.window == nil ? window_rect
                            : [self.window convertRectToScreen:window_rect];
}

- (BOOL)updateAccessibilitySnapshot:
            (DtrAccessibilitySnapshotHeaderV2)header
                           lines:(const DtrAccessibilityLineV1*)lines
                 columnBoundaries:(const uint32_t*)columnBoundaries
                             text:(const uint8_t*)text {
  if (header.generation == 0 || header.generation > INT64_MAX ||
      header.generation <= self.terminalAccessibilityGeneration ||
      header.rows == 0 || header.rows > DTR_MAX_ACCESSIBILITY_LINES ||
      header.columns == 0 || header.columns > 4096 ||
      header.line_count != header.rows ||
      header.utf8_length > DTR_MAX_ACCESSIBILITY_UTF8_BYTES ||
      header.utf16_length > DTR_MAX_ACCESSIBILITY_UTF16_UNITS ||
      header.column_boundary_count == 0 ||
      header.column_boundary_count >
          DTR_MAX_ACCESSIBILITY_COLUMN_BOUNDARIES ||
      !isfinite(header.cell_width) || !isfinite(header.cell_height) ||
      header.cell_width <= 0 || header.cell_height <= 0 ||
      !isfinite(header.content_origin_x) ||
      !isfinite(header.content_origin_y) || header.content_origin_x < 0 ||
      header.content_origin_y < 0 ||
      header.content_origin_x > DTR_MAX_METAL_DIMENSION ||
      header.content_origin_y > DTR_MAX_METAL_DIMENSION || lines == NULL ||
      columnBoundaries == NULL || (header.utf8_length > 0 && text == NULL)) {
    return NO;
  }
  NSString* value = [[NSString alloc] initWithBytes:text
                                             length:header.utf8_length
                                           encoding:NSUTF8StringEncoding];
  if (value == nil || value.length != header.utf16_length) return NO;
  NSData* round_trip = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (round_trip == nil || round_trip.length != header.utf8_length ||
      (header.utf8_length > 0 &&
       memcmp(round_trip.bytes, text, header.utf8_length) != 0)) {
    return NO;
  }

  uint32_t expected_start = 0;
  uint32_t expected_boundary = 0;
  BOOL selection_start_matched = NO;
  BOOL selection_end_matched = NO;
  const uint64_t requested_selection_end =
      (uint64_t)header.selection_location + header.selection_length;
  for (uint32_t row = 0; row < header.rows; row++) {
    const DtrAccessibilityLineV1 line = lines[row];
    if (line.row != row || line.utf16_start != expected_start ||
        line.utf16_start > header.utf16_length ||
        line.utf16_length > header.utf16_length - line.utf16_start ||
        line.first_column_boundary != expected_boundary ||
        line.column_boundary_count == 0 ||
        line.column_boundary_count > header.columns + 1 ||
        expected_boundary > header.column_boundary_count ||
        line.column_boundary_count >
            header.column_boundary_count - expected_boundary) {
      return NO;
    }
    const uint32_t* boundaries =
        columnBoundaries + line.first_column_boundary;
    if (boundaries[0] != 0 ||
        boundaries[line.column_boundary_count - 1] != line.utf16_length) {
      return NO;
    }
    uint32_t previous = 0;
    for (uint32_t index = 0; index < line.column_boundary_count; index++) {
      const uint32_t boundary = boundaries[index];
      const uint32_t absolute = line.utf16_start + boundary;
      if (boundary < previous || boundary > line.utf16_length ||
          (absolute > 0 && absolute < header.utf16_length &&
           [value characterAtIndex:absolute - 1] >= 0xd800 &&
           [value characterAtIndex:absolute - 1] <= 0xdbff &&
           [value characterAtIndex:absolute] >= 0xdc00 &&
           [value characterAtIndex:absolute] <= 0xdfff)) {
        return NO;
      }
      if (absolute == header.selection_location) selection_start_matched = YES;
      if (absolute == requested_selection_end) {
        selection_end_matched = YES;
      }
      previous = boundary;
    }
    expected_boundary += line.column_boundary_count;
    const uint32_t end = line.utf16_start + line.utf16_length;
    if (row + 1 < header.rows) {
      if (end >= header.utf16_length || [value characterAtIndex:end] != '\n') {
        return NO;
      }
      expected_start = end + 1;
    } else {
      expected_start = end;
    }
  }
  if (expected_start != header.utf16_length ||
      expected_boundary != header.column_boundary_count ||
      header.selection_location > header.utf16_length ||
      header.selection_length >
          header.utf16_length - header.selection_location ||
      !selection_start_matched || !selection_end_matched ||
      ((header.flags & DTR_ACCESSIBILITY_HAS_SELECTION) != 0) !=
          (header.selection_length > 0)) {
    return NO;
  }

  const BOOL has_cursor =
      (header.flags & DTR_ACCESSIBILITY_HAS_CURSOR) != 0;
  if (has_cursor) {
    if (header.cursor_location > header.utf16_length ||
        header.cursor_row >= header.rows) {
      return NO;
    }
    const DtrAccessibilityLineV1 line = lines[header.cursor_row];
    if (header.cursor_column >= line.column_boundary_count ||
        header.cursor_location !=
            line.utf16_start +
                columnBoundaries[line.first_column_boundary +
                                 header.cursor_column] ||
        ((header.flags & DTR_ACCESSIBILITY_HAS_SELECTION) == 0 &&
         (header.selection_location != header.cursor_location ||
          header.selection_length != 0))) {
      return NO;
    }
  } else if (header.cursor_location != UINT32_MAX ||
             header.cursor_row != UINT32_MAX ||
             header.cursor_column != UINT32_MAX ||
             ((header.flags & DTR_ACCESSIBILITY_HAS_SELECTION) == 0 &&
              (header.selection_location != 0 ||
               header.selection_length != 0))) {
    return NO;
  }

  NSData* line_data =
      [NSData dataWithBytes:lines
                     length:header.line_count *
                            sizeof(DtrAccessibilityLineV1)];
  NSData* boundary_data =
      [NSData dataWithBytes:columnBoundaries
                     length:header.column_boundary_count * sizeof(uint32_t)];
  const NSRange selection =
      NSMakeRange(header.selection_location, header.selection_length);
  const NSRange cursor = has_cursor
                             ? NSMakeRange(header.cursor_location, 0)
                             : NSMakeRange(NSNotFound, 0);
  const BOOL value_changed =
      ![self.terminalAccessibilityText isEqualToString:value] ||
      ![self.terminalAccessibilityLines isEqualToData:line_data] ||
      ![self.terminalAccessibilityColumnBoundaries
          isEqualToData:boundary_data] ||
      self.terminalAccessibilityRows != header.rows ||
      self.terminalAccessibilityColumns != header.columns ||
      self.terminalAccessibilityCellWidth != header.cell_width ||
      self.terminalAccessibilityCellHeight != header.cell_height ||
      self.terminalAccessibilityContentOriginX != header.content_origin_x ||
      self.terminalAccessibilityContentOriginY != header.content_origin_y;
  const BOOL selection_changed =
      !NSEqualRanges(self.terminalAccessibilitySelection, selection) ||
      self.terminalAccessibilityHasSelection !=
          ((header.flags & DTR_ACCESSIBILITY_HAS_SELECTION) != 0) ||
      !NSEqualRanges(self.terminalAccessibilityCursor, cursor) ||
      self.terminalAccessibilityCursorRow !=
          (has_cursor ? header.cursor_row : UINT32_MAX) ||
      self.terminalAccessibilityCursorColumn !=
          (has_cursor ? header.cursor_column : UINT32_MAX);

  self.terminalAccessibilityText = value;
  self.terminalAccessibilityLines = line_data;
  self.terminalAccessibilityColumnBoundaries = boundary_data;
  self.terminalAccessibilityGeneration = header.generation;
  self.terminalAccessibilityRows = header.rows;
  self.terminalAccessibilityColumns = header.columns;
  self.terminalAccessibilitySelection = selection;
  self.terminalAccessibilityHasSelection =
      (header.flags & DTR_ACCESSIBILITY_HAS_SELECTION) != 0;
  self.terminalAccessibilityCursor = cursor;
  self.terminalAccessibilityCursorRow =
      has_cursor ? header.cursor_row : UINT32_MAX;
  self.terminalAccessibilityCursorColumn =
      has_cursor ? header.cursor_column : UINT32_MAX;
  self.terminalAccessibilityCellWidth = header.cell_width;
  self.terminalAccessibilityCellHeight = header.cell_height;
  self.terminalAccessibilityContentOriginX = header.content_origin_x;
  self.terminalAccessibilityContentOriginY = header.content_origin_y;
  if (value_changed) {
    SaturatingIncrementMetric(&_terminalAccessibilityValueNotificationCount);
    NSAccessibilityPostNotification(self,
                                    NSAccessibilityValueChangedNotification);
  }
  if (selection_changed) {
    SaturatingIncrementMetric(
        &_terminalAccessibilitySelectionNotificationCount);
    NSAccessibilityPostNotification(
        self, NSAccessibilitySelectedTextChangedNotification);
  }
  return YES;
}

- (BOOL)runAccessibilityAcceptance:(uint64_t)generation {
  if (generation == 0 || generation != self.terminalAccessibilityGeneration ||
      ![self isAccessibilityElement] ||
      ![[self accessibilityRole] isEqualToString:NSAccessibilityTextAreaRole] ||
      ![[self accessibilityLabel] isEqualToString:@"Terminal"] ||
      ![[self accessibilityValue]
          isEqualToString:self.terminalAccessibilityText] ||
      !NSEqualRanges([self accessibilityVisibleCharacterRange],
                     NSMakeRange(0, self.terminalAccessibilityText.length)) ||
      [self accessibilityNumberOfCharacters] !=
          (NSInteger)self.terminalAccessibilityText.length ||
      !NSEqualRanges([self accessibilitySelectedTextRange],
                     self.terminalAccessibilitySelection) ||
      ![[self accessibilitySelectedText]
          isEqualToString:[self.terminalAccessibilityText
                              substringWithRange:
                                  self.terminalAccessibilitySelection]] ||
      ![self isAccessibilityFocused] ||
      self.terminalAccessibilityRows == 0 ||
      [self accessibilityLineForIndex:0] != 0 ||
      [self accessibilityRangeForLine:0].location != 0 ||
      self.terminalAccessibilityValueNotificationCount == 0 ||
      self.terminalAccessibilitySelectionNotificationCount == 0 ||
      self.terminalAccessibilityFocusNotificationCount == 0 ||
      (self.terminalAccessibilityCursor.location != NSNotFound &&
       [self accessibilityInsertionPointLineNumber] !=
           (NSInteger)self.terminalAccessibilityCursorRow)) {
    return NO;
  }
  const NSRect frame =
      [self accessibilityFrameForRange:self.terminalAccessibilitySelection];
  const NSRect cursor_frame = self.terminalAccessibilityCursor.location ==
                                      NSNotFound
                                  ? frame
                                  : [self accessibilityFrameForRange:
                                              self.terminalAccessibilityCursor];
  return isfinite(frame.origin.x) && isfinite(frame.origin.y) &&
         isfinite(frame.size.width) && isfinite(frame.size.height) &&
         frame.size.width > 0 && frame.size.height > 0 &&
         isfinite(cursor_frame.origin.x) && isfinite(cursor_frame.origin.y) &&
         cursor_frame.size.width > 0 && cursor_frame.size.height > 0;
}

- (BOOL)attachTextInputClient:(uint64_t)clientId {
  if (clientId == 0 || clientId > INT64_MAX) {
    return NO;
  }
  if (self.textInputClientId == clientId && self.textInputQueue != nil) {
    return YES;
  }
  if (self.textInputClientId != 0 || self.textInputQueue != nil) {
    return NO;
  }
  DtrTextInputQueue* queue = [[DtrTextInputQueue alloc] init];
  if (!RegisterTextInputQueue(clientId, queue)) {
    return NO;
  }
  self.textInputQueue = queue;
  self.textInputClientId = clientId;
  self.textInputEventGeneration = 0;
  self.textInputGeometryGeneration = 0;
  self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
  self.terminalMarkedSelection = NSMakeRange(0, 0);
  return YES;
}

- (BOOL)updateTextInputGeometry:(DtrTextInputGeometryV1)geometry {
  if (self.textInputClientId == 0 ||
      geometry.client_id != self.textInputClientId ||
      geometry.generation == 0 || geometry.generation > INT64_MAX ||
      !isfinite(geometry.x) || !isfinite(geometry.y) ||
      !isfinite(geometry.width) || !isfinite(geometry.height) ||
      geometry.width <= 0 || geometry.height <= 0) {
    return NO;
  }
  if (geometry.generation <= self.textInputGeometryGeneration) {
    return YES;
  }
  self.textInputGeometryGeneration = geometry.generation;
  self.terminalCaretRect = NSMakeRect(geometry.x, geometry.y, geometry.width,
                                      geometry.height);
  return YES;
}

- (void)detachTextInputClient {
  const uint64_t client_id = self.textInputClientId;
  DtrTextInputQueue* queue = self.textInputQueue;
  self.textInputClientId = 0;
  self.textInputQueue = nil;
  self.terminalActiveKeyEvent = nil;
  self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
  self.terminalMarkedSelection = NSMakeRange(0, 0);
  UnregisterTextInputQueue(client_id, queue);
}

- (uint64_t)nextTextInputEventGeneration {
  if (self.textInputEventGeneration < INT64_MAX) {
    ++self.textInputEventGeneration;
  }
  return self.textInputEventGeneration;
}

- (void)notifyTextInputQueue {
  DtrTextInputNotifyV1 callback = g_text_input_notify;
  if (callback != NULL && self.textInputClientId != 0) {
    callback(self.textInputClientId);
  }
}

- (void)enqueueTextInputKind:(uint32_t)kind
                       flags:(uint32_t)flags
                     keyCode:(uint32_t)keyCode
                   modifiers:(uint32_t)modifiers
                        text:(NSString*)text
              unmodifiedText:(NSString*)unmodifiedText
                   selection:(NSRange)selection
                  replacement:(NSRange)replacement {
  if (self.textInputClientId == 0 || self.textInputQueue == nil) {
    return;
  }
  const uint64_t generation = [self nextTextInputEventGeneration];
  NSData* packet = BuildTextInputPacket(
      self.textInputClientId, generation, kind, flags, keyCode, modifiers, text,
      unmodifiedText, selection, replacement);
  NSLock* lock = TextInputQueueLock();
  [lock lock];
  BOOL enqueued = packet != nil &&
                  [self.textInputQueue enqueuePacket:packet kind:kind];
  if (!enqueued) {
    self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
    self.terminalMarkedSelection = NSMakeRange(0, 0);
    NSData* overflow = BuildTextInputPacket(
        self.textInputClientId, [self nextTextInputEventGeneration],
        DTR_TEXT_INPUT_EVENT_OVERFLOW, 0, 0, 0, nil, nil,
        NSMakeRange(NSNotFound, 0), NSMakeRange(NSNotFound, 0));
    [self.textInputQueue replaceWithOverflowPacket:overflow];
  }
  [lock unlock];
  [self notifyTextInputQueue];
}

- (void)enqueueRawKeyEvent:(NSEvent*)event kind:(uint32_t)kind {
  if (event == nil || self.terminalRawKeyPosted || [self hasMarkedText]) {
    return;
  }
  self.terminalRawKeyPosted = YES;
  [self enqueueTextInputKind:kind
                       flags:event.isARepeat ? DTR_TEXT_INPUT_EVENT_REPEAT : 0
                     keyCode:event.keyCode
                   modifiers:TextInputStableModifiers(event.modifierFlags)
                        text:event.characters
              unmodifiedText:event.charactersIgnoringModifiers
                   selection:NSMakeRange(NSNotFound, 0)
                  replacement:NSMakeRange(NSNotFound, 0)];
}

- (void)keyDown:(NSEvent*)event {
  if (self.textInputClientId == 0) {
    [super keyDown:event];
    return;
  }
  self.terminalActiveKeyEvent = event;
  self.terminalRawKeyPosted = NO;
  const BOOL handled = [self.inputContext handleEvent:event];
  if (!handled) {
    [self enqueueRawKeyEvent:event kind:DTR_TEXT_INPUT_EVENT_RAW_KEY_DOWN];
  }
  self.terminalActiveKeyEvent = nil;
  self.terminalRawKeyPosted = NO;
}

- (void)keyUp:(NSEvent*)event {
  if (self.textInputClientId == 0) {
    [super keyUp:event];
    return;
  }
  self.terminalRawKeyPosted = NO;
  [self enqueueRawKeyEvent:event kind:DTR_TEXT_INPUT_EVENT_RAW_KEY_UP];
  self.terminalRawKeyPosted = NO;
}

- (void)doCommandBySelector:(SEL)selector {
  (void)selector;
  [self enqueueRawKeyEvent:self.terminalActiveKeyEvent
                       kind:DTR_TEXT_INPUT_EVENT_RAW_KEY_DOWN];
}

- (BOOL)hasMarkedText {
  return self.terminalMarkedText.length > 0;
}

- (NSRange)markedRange {
  return [self hasMarkedText]
             ? NSMakeRange(0, self.terminalMarkedText.length)
             : NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange {
  return [self hasMarkedText] ? self.terminalMarkedSelection
                              : NSMakeRange(0, 0);
}

- (void)setMarkedText:(id)value
        selectedRange:(NSRange)selectedRange
      replacementRange:(NSRange)replacementRange {
  NSString* text = TextInputPlainString(value);
  if (text == nil || selectedRange.location == NSNotFound ||
      selectedRange.location > text.length ||
      selectedRange.length > text.length - selectedRange.location) {
    [self enqueueTextInputKind:DTR_TEXT_INPUT_EVENT_OVERFLOW
                         flags:0
                       keyCode:0
                     modifiers:0
                          text:nil
                unmodifiedText:nil
                     selection:NSMakeRange(NSNotFound, 0)
                    replacement:NSMakeRange(NSNotFound, 0)];
    return;
  }
  if (text.length == 0) {
    [self unmarkText];
    return;
  }
  self.terminalMarkedText = [[NSAttributedString alloc] initWithString:text];
  self.terminalMarkedSelection = selectedRange;
  [self enqueueTextInputKind:DTR_TEXT_INPUT_EVENT_PREEDIT
                       flags:0
                     keyCode:0
                   modifiers:0
                        text:text
              unmodifiedText:nil
                   selection:selectedRange
                  replacement:replacementRange];
}

- (void)unmarkText {
  if (![self hasMarkedText]) {
    return;
  }
  self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
  self.terminalMarkedSelection = NSMakeRange(0, 0);
  [self enqueueTextInputKind:DTR_TEXT_INPUT_EVENT_CANCEL
                       flags:0
                     keyCode:0
                   modifiers:0
                        text:nil
              unmodifiedText:nil
                   selection:NSMakeRange(NSNotFound, 0)
                  replacement:NSMakeRange(NSNotFound, 0)];
}

- (void)insertText:(id)value replacementRange:(NSRange)replacementRange {
  NSString* text = TextInputPlainString(value);
  if (text == nil) {
    return;
  }
  self.terminalMarkedText = [[NSAttributedString alloc] initWithString:@""];
  self.terminalMarkedSelection = NSMakeRange(0, 0);
  [self enqueueTextInputKind:DTR_TEXT_INPUT_EVENT_COMMIT
                       flags:0
                     keyCode:0
                   modifiers:0
                        text:text
              unmodifiedText:nil
                   selection:NSMakeRange(NSNotFound, 0)
                  replacement:replacementRange];
}

- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText {
  return @[];
}

- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                                actualRange:(NSRangePointer)actual {
  const NSRange marked = [self markedRange];
  if (marked.location == NSNotFound || range.location == NSNotFound) {
    if (actual != NULL) *actual = NSMakeRange(NSNotFound, 0);
    return nil;
  }
  const NSRange intersection = NSIntersectionRange(marked, range);
  if (intersection.length == 0) {
    if (actual != NULL) *actual = NSMakeRange(NSNotFound, 0);
    return nil;
  }
  if (actual != NULL) *actual = intersection;
  return [self.terminalMarkedText attributedSubstringFromRange:intersection];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                          actualRange:(NSRangePointer)actual {
  if (actual != NULL) {
    const NSRange marked = [self markedRange];
    if (marked.location == NSNotFound || range.location == NSNotFound) {
      *actual = NSMakeRange(NSNotFound, 0);
    } else {
      *actual = NSIntersectionRange(marked, range);
    }
  }
  NSRect window_rect = [self convertRect:self.terminalCaretRect toView:nil];
  if (self.window != nil) {
    return [self.window convertRectToScreen:window_rect];
  }
  return window_rect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
  (void)point;
  return [self hasMarkedText] ? self.terminalMarkedSelection.location : 0;
}

- (BOOL)acceptanceCandidateGeometryIsCurrent {
  NSRange actual = NSMakeRange(NSNotFound, 0);
  NSRect screen =
      [self firstRectForCharacterRange:NSMakeRange(0, self.markedRange.length)
                           actualRange:&actual];
  NSRect window = [self.window convertRectFromScreen:screen];
  NSRect local = [self convertRect:window fromView:nil];
  return NSEqualRanges(actual, self.markedRange) &&
         isfinite(screen.origin.x) && isfinite(screen.origin.y) &&
         screen.size.width > 0 && screen.size.height > 0 &&
         fabs(local.origin.x - self.terminalCaretRect.origin.x) < 0.01 &&
         fabs(local.origin.y - self.terminalCaretRect.origin.y) < 0.01 &&
         fabs(local.size.width - self.terminalCaretRect.size.width) < 0.01 &&
         fabs(local.size.height - self.terminalCaretRect.size.height) < 0.01;
}

- (BOOL)runTextInputAcceptanceStage:(uint32_t)stage {
  if (self.textInputClientId == 0 || self.textInputQueue == nil ||
      self.window == nil || self.window.firstResponder != self ||
      self.textInputGeometryGeneration == 0) {
    return NO;
  }
  id<NSTextInputClient> input = (id<NSTextInputClient>)self;
  switch (stage) {
    case 1: {
      if ([self hasMarkedText]) return NO;
      NSEvent* navigation =
          [NSEvent keyEventWithType:NSEventTypeKeyDown
                           location:NSZeroPoint
                      modifierFlags:NSEventModifierFlagFunction
                          timestamp:NSProcessInfo.processInfo.systemUptime
                       windowNumber:self.window.windowNumber
                            context:nil
                         characters:@"\uf700"
        charactersIgnoringModifiers:@"\uf700"
                          isARepeat:NO
                            keyCode:126];
      self.terminalActiveKeyEvent = navigation;
      self.terminalRawKeyPosted = NO;
      [self doCommandBySelector:@selector(moveUp:)];
      self.terminalActiveKeyEvent = nil;
      self.terminalRawKeyPosted = NO;
      [input setMarkedText:@"にほん"
             selectedRange:NSMakeRange(3, 0)
           replacementRange:NSMakeRange(NSNotFound, 0)];
      [input setMarkedText:@"にほんご"
             selectedRange:NSMakeRange(4, 0)
           replacementRange:NSMakeRange(NSNotFound, 0)];
      return [self acceptanceCandidateGeometryIsCurrent];
    }
    case 2: {
      if (![[self.terminalMarkedText string] isEqualToString:@"にほんご"])
        return NO;
      if (![self acceptanceCandidateGeometryIsCurrent]) return NO;
      [input insertText:@"日本語"
          replacementRange:NSMakeRange(NSNotFound, 0)];
      [input setMarkedText:@"かな"
             selectedRange:NSMakeRange(2, 0)
           replacementRange:NSMakeRange(NSNotFound, 0)];
      NSEvent* suppressed =
          [NSEvent keyEventWithType:NSEventTypeKeyUp
                           location:NSZeroPoint
                      modifierFlags:NSEventModifierFlagControl
                          timestamp:NSProcessInfo.processInfo.systemUptime
                       windowNumber:self.window.windowNumber
                            context:nil
                         characters:@"\x03"
        charactersIgnoringModifiers:@"c"
                          isARepeat:YES
                            keyCode:8];
      [self keyUp:suppressed];
      return [self hasMarkedText];
    }
    case 3:
      if (![[self.terminalMarkedText string] isEqualToString:@"かな"])
        return NO;
      [input unmarkText];
      return ![self hasMarkedText];
    default:
      return NO;
  }
}

- (BOOL)runTextInputAcceptanceMatrix {
  if (self.textInputClientId == 0 || self.textInputQueue == nil ||
      self.window == nil || self.window.firstResponder != self ||
      [self hasMarkedText]) {
    return NO;
  }
  id<NSTextInputClient> input = (id<NSTextInputClient>)self;
  NSArray<NSString*>* commits = @[
    @"a", @"A", @"¥", @"_", @"é", @"中文", @"日本語", @"한글", @"👩‍💻", @"⌘"
  ];
  for (NSString* text in commits) {
    [input insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
  }
  for (NSUInteger index = 0; index < 3; index++) {
    NSEvent* navigation =
        [NSEvent keyEventWithType:NSEventTypeKeyDown
                         location:NSZeroPoint
                    modifierFlags:NSEventModifierFlagFunction
                        timestamp:NSProcessInfo.processInfo.systemUptime
                     windowNumber:self.window.windowNumber
                          context:nil
                       characters:@"\uf703"
      charactersIgnoringModifiers:@"\uf703"
                        isARepeat:index > 0
                          keyCode:124];
    self.terminalActiveKeyEvent = navigation;
    self.terminalRawKeyPosted = NO;
    [self doCommandBySelector:@selector(moveRight:)];
    self.terminalActiveKeyEvent = nil;
    self.terminalRawKeyPosted = NO;
  }
  return ![self hasMarkedText];
}

@end

static void* CreateTerminalMetalView(void* context) {
  (void)context;
  NSView* view = [[DtrTerminalMetalView alloc] initWithFrame:NSZeroRect];
  return (__bridge_retained void*)view;
}

static int32_t PerformTerminalMetalViewOperation(
    void* context, void* opaque_view, const uint8_t* payload,
    size_t payload_length) {
  (void)context;
  if (opaque_view == NULL || payload == NULL ||
      payload_length < sizeof(DtrTextInputClientV1)) {
    return DA_STATUS_INVALID_ARGUMENT;
  }
  id view = (__bridge id)opaque_view;
  if (![view isKindOfClass:DtrTerminalMetalView.class]) {
    return DA_STATUS_WRONG_HANDLE_TYPE;
  }
  DtrTextInputClientV1 common;
  memcpy(&common, payload, sizeof(common));
  DtrTerminalMetalView* terminal_view = (DtrTerminalMetalView*)view;
  switch (common.operation) {
    case DTR_METAL_VIEW_OPERATION_BIND: {
      if (payload_length != sizeof(DtrMetalViewBindingV1)) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrMetalViewBindingV1 binding;
      memcpy(&binding, payload, sizeof(binding));
      if (binding.struct_size != sizeof(binding) ||
          binding.version != DTR_METAL_VIEW_BINDING_VERSION ||
          binding.reserved != 0 || binding.renderer_handle == 0 ||
          binding.renderer_generation == 0) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrMetalRenderer* renderer = nil;
      RetainMetalRendererForHandle(binding.renderer_handle, &renderer);
      if (renderer == nil ||
          renderer.generation != binding.renderer_generation) {
        return DA_STATUS_INVALID_HANDLE;
      }
      const int32_t status = [renderer bindView:terminal_view];
      if (status == DTR_STATUS_OK) {
        return DA_STATUS_OK;
      }
      return status == DTR_STATUS_INTERNAL ? DA_STATUS_INTERNAL_ERROR
                                           : DA_STATUS_INVALID_ARGUMENT;
    }
    case DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH:
    case DTR_METAL_VIEW_OPERATION_TEXT_INPUT_DETACH: {
      if (payload_length != sizeof(DtrTextInputClientV1) ||
          common.struct_size != sizeof(DtrTextInputClientV1) ||
          common.version != DTR_TEXT_INPUT_CLIENT_VERSION ||
          common.reserved != 0 || common.client_id == 0) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      if (common.operation == DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH) {
        return [terminal_view attachTextInputClient:common.client_id]
                   ? DA_STATUS_OK
                   : DA_STATUS_INVALID_ARGUMENT;
      }
      if (terminal_view.textInputClientId != common.client_id) {
        return DA_STATUS_INVALID_HANDLE;
      }
      [terminal_view detachTextInputClient];
      return DA_STATUS_OK;
    }
    case DTR_METAL_VIEW_OPERATION_TEXT_INPUT_GEOMETRY: {
      if (payload_length != sizeof(DtrTextInputGeometryV1)) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrTextInputGeometryV1 geometry;
      memcpy(&geometry, payload, sizeof(geometry));
      if (geometry.struct_size != sizeof(geometry) ||
          geometry.version != DTR_TEXT_INPUT_GEOMETRY_VERSION ||
          geometry.operation != DTR_METAL_VIEW_OPERATION_TEXT_INPUT_GEOMETRY ||
          geometry.reserved != 0) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      return [terminal_view updateTextInputGeometry:geometry]
                 ? DA_STATUS_OK
                 : DA_STATUS_INVALID_ARGUMENT;
    }
    case DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ACCEPTANCE: {
      if (payload_length != sizeof(DtrTextInputAcceptanceV1)) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrTextInputAcceptanceV1 acceptance;
      memcpy(&acceptance, payload, sizeof(acceptance));
      if (acceptance.struct_size != sizeof(acceptance) ||
          acceptance.version != DTR_TEXT_INPUT_CLIENT_VERSION ||
          acceptance.operation !=
              DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ACCEPTANCE ||
          acceptance.client_id != terminal_view.textInputClientId ||
          acceptance.reserved != 0 || acceptance.stage < 1 ||
          acceptance.stage > 3) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      return [terminal_view runTextInputAcceptanceStage:acceptance.stage]
                 ? DA_STATUS_OK
                 : DA_STATUS_INTERNAL_ERROR;
    }
    case DTR_METAL_VIEW_OPERATION_TEXT_INPUT_MATRIX: {
      if (payload_length != sizeof(DtrTextInputClientV1) ||
          common.struct_size != sizeof(DtrTextInputClientV1) ||
          common.version != DTR_TEXT_INPUT_CLIENT_VERSION ||
          common.operation != DTR_METAL_VIEW_OPERATION_TEXT_INPUT_MATRIX ||
          common.client_id != terminal_view.textInputClientId ||
          common.reserved != 0) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      return [terminal_view runTextInputAcceptanceMatrix]
                 ? DA_STATUS_OK
                 : DA_STATUS_INTERNAL_ERROR;
    }
    case DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_SNAPSHOT: {
      if (payload_length < sizeof(DtrAccessibilitySnapshotHeaderV2) ||
          payload_length > DTR_MAX_ACCESSIBILITY_PACKET_BYTES) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrAccessibilitySnapshotHeaderV2 header;
      memcpy(&header, payload, sizeof(header));
      const uint64_t lines_end =
          (uint64_t)sizeof(header) +
          (uint64_t)header.line_count * sizeof(DtrAccessibilityLineV1);
      const uint64_t boundaries_end =
          lines_end + (uint64_t)header.column_boundary_count * sizeof(uint32_t);
      const uint64_t total = boundaries_end + header.utf8_length;
      if (header.struct_size != sizeof(header) ||
          header.version != DTR_ACCESSIBILITY_SNAPSHOT_VERSION ||
          header.operation !=
              DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_SNAPSHOT ||
          (header.flags & ~DTR_ACCESSIBILITY_KNOWN_FLAGS) != 0 ||
          header.reserved0 != 0 || header.reserved[0] != 0 ||
          header.reserved[1] != 0 || header.reserved[2] != 0 ||
          header.reserved[3] != 0 || header.lines_offset != sizeof(header) ||
          header.column_boundaries_offset != lines_end ||
          header.text_offset != boundaries_end || header.total_size != total ||
          total != payload_length || total > DTR_MAX_ACCESSIBILITY_PACKET_BYTES) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      NSData* line_data =
          [NSData dataWithBytes:payload + header.lines_offset
                         length:header.line_count *
                                sizeof(DtrAccessibilityLineV1)];
      NSData* boundary_data =
          [NSData dataWithBytes:payload + header.column_boundaries_offset
                         length:header.column_boundary_count *
                                sizeof(uint32_t)];
      const DtrAccessibilityLineV1* lines = line_data.bytes;
      const uint32_t* column_boundaries = boundary_data.bytes;
      const uint8_t* text = payload + header.text_offset;
      return [terminal_view updateAccessibilitySnapshot:header
                                                   lines:lines
                                        columnBoundaries:column_boundaries
                                                    text:text]
                 ? DA_STATUS_OK
                 : DA_STATUS_INVALID_ARGUMENT;
    }
    case DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_ACCEPTANCE: {
      if (payload_length != sizeof(DtrAccessibilityAcceptanceV1)) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      DtrAccessibilityAcceptanceV1 acceptance;
      memcpy(&acceptance, payload, sizeof(acceptance));
      if (acceptance.struct_size != sizeof(acceptance) ||
          acceptance.version != DTR_ACCESSIBILITY_SNAPSHOT_VERSION ||
          acceptance.operation !=
              DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_ACCEPTANCE ||
          acceptance.reserved != 0) {
        return DA_STATUS_INVALID_ARGUMENT;
      }
      return [terminal_view runAccessibilityAcceptance:acceptance.generation]
                 ? DA_STATUS_OK
                 : DA_STATUS_INTERNAL_ERROR;
    }
    default:
      return DA_STATUS_INVALID_ARGUMENT;
  }
}

uint32_t dtr_abi_version(void) { return DTR_ABI_VERSION; }

int32_t dtr_initialize(const da_native_extension_services_v1* services) {
  if (services == NULL ||
      services->struct_size < sizeof(da_native_extension_services_v1) ||
      services->abi_version != DA_NATIVE_EXTENSION_ABI_VERSION ||
      services->register_custom_view_provider == NULL ||
      services->register_custom_view_operation == NULL) {
    return DA_STATUS_UNSUPPORTED_VERSION;
  }
  if (g_initialized_services != NULL) {
    return g_initialized_services == services ? DA_STATUS_OK
                                              : DA_STATUS_INVALID_ARGUMENT;
  }
  const int32_t status = services->register_custom_view_provider(
      (const uint8_t*)kProviderIdentifier, strlen(kProviderIdentifier),
      CreateTerminalMetalView, NULL);
  if (status != DA_STATUS_OK) {
    return status;
  }
  const int32_t operation_status = services->register_custom_view_operation(
      (const uint8_t*)kProviderIdentifier, strlen(kProviderIdentifier),
      PerformTerminalMetalViewOperation, NULL);
  if (operation_status == DA_STATUS_OK) {
    g_initialized_services = services;
  }
  return operation_status;
}

int32_t dtr_debug_live_view_count(void) {
  return atomic_load_explicit(&g_live_view_count, memory_order_relaxed);
}

int32_t dtr_text_input_set_notify_callback(DtrTextInputNotifyV1 callback) {
  if (callback == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (g_text_input_notify != NULL && g_text_input_notify != callback) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  g_text_input_notify = callback;
  return DTR_STATUS_OK;
}

int32_t dtr_text_input_take_event(uint64_t client_id, uint8_t* output,
                                  uint32_t output_capacity,
                                  uint32_t* output_required) {
  if (client_id == 0 || client_id > INT64_MAX || output_required == NULL ||
      (output == NULL && output_capacity != 0)) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  *output_required = 0;
  NSLock* lock = TextInputQueueLock();
  [lock lock];
  DtrTextInputQueue* queue = TextInputQueues()[@(client_id)];
  NSData* packet = [queue peekPacket];
  if (packet == nil) {
    [lock unlock];
    return DTR_STATUS_NOT_FOUND;
  }
  *output_required = (uint32_t)packet.length;
  if (output == NULL || output_capacity < packet.length) {
    [lock unlock];
    return DTR_STATUS_BUFFER_TOO_SMALL;
  }
  memcpy(output, packet.bytes, packet.length);
  [queue removeFirstPacket];
  [lock unlock];
  return DTR_STATUS_OK;
}

int32_t dtr_debug_live_text_input_client_count(void) {
  NSLock* lock = TextInputQueueLock();
  [lock lock];
  const NSUInteger count = TextInputQueues().count;
  [lock unlock];
  return count > INT32_MAX ? INT32_MAX : (int32_t)count;
}

static int32_t PrepareFontCatalogSummary(DtrFontCatalogSummaryV1* output) {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (output->struct_size < sizeof(DtrFontCatalogSummaryV1) ||
      output->version != DTR_FONT_CATALOG_SUMMARY_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  memset(output, 0, sizeof(DtrFontCatalogSummaryV1));
  output->struct_size = sizeof(DtrFontCatalogSummaryV1);
  output->version = DTR_FONT_CATALOG_SUMMARY_VERSION;
  return DTR_STATUS_OK;
}

static int32_t PrepareResolvedFont(DtrResolvedFontV1* output) {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (output->struct_size < sizeof(DtrResolvedFontV1) ||
      output->version != DTR_RESOLVED_FONT_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  memset(output, 0, sizeof(DtrResolvedFontV1));
  output->struct_size = sizeof(DtrResolvedFontV1);
  output->version = DTR_RESOLVED_FONT_VERSION;
  return DTR_STATUS_OK;
}

static NSString* DecodeUtf8(const uint8_t* bytes, uint32_t length,
                            BOOL allow_empty) {
  if (length == 0) {
    return allow_empty ? @"" : nil;
  }
  if (bytes == NULL || memchr(bytes, 0, length) != NULL) {
    return nil;
  }
  return [[NSString alloc] initWithBytes:bytes
                                  length:length
                                encoding:NSUTF8StringEncoding];
}

static DtrFontCatalog* FontCatalogForHandle(uint64_t handle) {
  if (handle == 0) {
    return nil;
  }
  NSLock* lock = FontCatalogRegistryLock();
  [lock lock];
  DtrFontCatalog* catalog = FontCatalogRegistry()[@(handle)];
  [lock unlock];
  return catalog;
}

static uint32_t UnicodeScalarCount(NSString* text) {
  const NSUInteger length = text.length;
  uint32_t count = 0;
  for (NSUInteger index = 0; index < length; index++) {
    const unichar current = [text characterAtIndex:index];
    if (CFStringIsSurrogateHighCharacter(current) && index + 1 < length &&
        CFStringIsSurrogateLowCharacter([text characterAtIndex:index + 1])) {
      index++;
    }
    count++;
  }
  return count;
}

static NSFont* FontForRun(CTRunRef run) {
  CFDictionaryRef attributes = CTRunGetAttributes(run);
  if (attributes == NULL) {
    return nil;
  }
  CTFontRef font =
      (CTFontRef)CFDictionaryGetValue(attributes, kCTFontAttributeName);
  return font == NULL ? nil : (__bridge NSFont*)font;
}

static uint32_t ShapedFontFlags(NSFont* requested_font, NSFont* resolved_font,
                                BOOL synthetic, BOOL missing) {
  uint32_t flags = 0;
  if (![PostScriptName(resolved_font)
          isEqualToString:PostScriptName(requested_font)]) {
    flags |= DTR_SHAPED_RUN_FALLBACK;
  }
  const CTFontSymbolicTraits traits =
      CTFontGetSymbolicTraits((__bridge CTFontRef)resolved_font);
  if ((traits & kCTFontColorGlyphsTrait) != 0) {
    flags |= DTR_SHAPED_RUN_COLOR_GLYPHS;
  }
  if ((traits & kCTFontMonoSpaceTrait) != 0) {
    flags |= DTR_SHAPED_RUN_MONOSPACED;
  }
  if (synthetic) {
    flags |= DTR_SHAPED_RUN_SYNTHETIC;
  }
  if (missing) {
    flags |= DTR_SHAPED_RUN_MISSING_GLYPH;
  }
  return flags;
}

int32_t dtr_font_catalog_create(const uint8_t* family_utf8,
                                uint32_t family_length, double point_size,
                                uint32_t policy_flags,
                                DtrFontCatalogSummaryV1* output) {
  @autoreleasepool {
    const int32_t output_status = PrepareFontCatalogSummary(output);
    if (output_status != DTR_STATUS_OK) {
      return output_status;
    }
    if (family_length > DTR_MAX_FONT_FAMILY_BYTES ||
        (policy_flags & ~DTR_FONT_POLICY_KNOWN_MASK) != 0 ||
        !isfinite(point_size) || point_size < 4.0 || point_size > 128.0) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    NSString* family = DecodeUtf8(family_utf8, family_length, YES);
    if (family == nil) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    const uint64_t handle = atomic_fetch_add_explicit(
        &g_next_font_catalog_handle, 1, memory_order_relaxed);
    if (handle == 0 || handle == UINT64_MAX) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    DtrFontCatalog* catalog =
        [[DtrFontCatalog alloc] initWithFamily:family
                                    pointSize:point_size
                                  generation:handle
                                 policyFlags:policy_flags];
    if (catalog == nil) {
      return DTR_STATUS_NOT_FOUND;
    }
    if (![catalog fillSummary:output handle:handle]) {
      return DTR_STATUS_INTERNAL;
    }
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    FontCatalogRegistry()[@(handle)] = catalog;
    [lock unlock];
    return DTR_STATUS_OK;
  }
}

int32_t dtr_font_catalog_release(uint64_t handle) {
  @autoreleasepool {
    if (handle == 0) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    NSNumber* key = @(handle);
    DtrFontCatalog* catalog = FontCatalogRegistry()[key];
    if (catalog != nil) {
      [FontCatalogRegistry() removeObjectForKey:key];
    }
    [lock unlock];
    return catalog == nil ? DTR_STATUS_INVALID_HANDLE : DTR_STATUS_OK;
  }
}

void dtr_font_catalog_release_finalizer(void* handle) {
  (void)dtr_font_catalog_release((uint64_t)(uintptr_t)handle);
}

int32_t dtr_font_catalog_resolve(uint64_t handle, uint32_t style,
                                 const uint8_t* text_utf8,
                                 uint32_t text_length,
                                 DtrResolvedFontV1* output) {
  @autoreleasepool {
    const int32_t output_status = PrepareResolvedFont(output);
    if (output_status != DTR_STATUS_OK) {
      return output_status;
    }
    if (style > DTR_FONT_STYLE_BOLD_ITALIC || text_length == 0 ||
        text_length > DTR_MAX_RESOLVE_TEXT_BYTES) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    NSString* text = DecodeUtf8(text_utf8, text_length, NO);
    if (text == nil) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrFontCatalog* catalog = FontCatalogForHandle(handle);
    if (catalog == nil) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    BOOL synthetic = NO;
    NSFont* requested_font = [catalog fontForStyle:style synthetic:&synthetic];
    if (requested_font == nil) {
      return DTR_STATUS_NOT_FOUND;
    }
    NSDictionary* attributes = @{
      (__bridge NSString*)kCTFontAttributeName : requested_font,
      (__bridge NSString*)kCTLigatureAttributeName : @1,
    };
    NSAttributedString* attributed =
        [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString(
        (__bridge CFAttributedStringRef)attributed);
    if (line == NULL) {
      return DTR_STATUS_INTERNAL;
    }
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    const CFIndex run_count = runs == NULL ? 0 : CFArrayGetCount(runs);
    if (run_count <= 0) {
      CFRelease(line);
      return DTR_STATUS_INTERNAL;
    }
    CTRunRef first_run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
    CFDictionaryRef run_attributes = CTRunGetAttributes(first_run);
    CTFontRef resolved_font = (CTFontRef)CFDictionaryGetValue(
        run_attributes, kCTFontAttributeName);
    if (resolved_font == NULL) {
      CFRelease(line);
      return DTR_STATUS_INTERNAL;
    }
    NSFont* resolved = (__bridge NSFont*)resolved_font;
    uint64_t total_glyphs = 0;
    BOOL missing = NO;
    for (CFIndex run_index = 0; run_index < run_count; run_index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, run_index);
      const CFIndex glyph_count = CTRunGetGlyphCount(run);
      if (glyph_count < 0 || total_glyphs + (uint64_t)glyph_count > UINT32_MAX) {
        CFRelease(line);
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }
      total_glyphs += (uint64_t)glyph_count;
      CGGlyph glyphs[256];
      for (CFIndex start = 0; start < glyph_count; start += 256) {
        const CFIndex remaining = glyph_count - start;
        const CFIndex count = remaining < 256 ? remaining : 256;
        CTRunGetGlyphs(run, CFRangeMake(start, count), glyphs);
        for (CFIndex index = 0; index < count; index++) {
          if (glyphs[index] == 0) {
            missing = YES;
          }
        }
      }
    }
    NSString* resolved_name = PostScriptName(resolved);
    NSData* resolved_name_utf8 =
        [resolved_name dataUsingEncoding:NSUTF8StringEncoding];
    if (resolved_name_utf8 == nil ||
        resolved_name_utf8.length > DTR_MAX_POSTSCRIPT_NAME_BYTES) {
      CFRelease(line);
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    uint32_t flags = 0;
    if (![resolved_name isEqualToString:PostScriptName(requested_font)]) {
      flags |= DTR_RESOLVED_FONT_FALLBACK;
    }
    const CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(resolved_font);
    if ((traits & kCTFontColorGlyphsTrait) != 0) {
      flags |= DTR_RESOLVED_FONT_COLOR_GLYPHS;
    }
    if ((traits & kCTFontMonoSpaceTrait) != 0) {
      flags |= DTR_RESOLVED_FONT_MONOSPACED;
    }
    if (synthetic) {
      flags |= DTR_RESOLVED_FONT_SYNTHETIC;
    }
    if (missing) {
      flags |= DTR_RESOLVED_FONT_MISSING_GLYPH;
    }
    output->catalog_generation = catalog.generation;
    output->face_id = [catalog faceIdForFont:resolved];
    output->flags = flags;
    output->requested_style = style;
    output->utf16_length = (uint32_t)text.length;
    output->unicode_scalar_count = UnicodeScalarCount(text);
    output->glyph_count = (uint32_t)total_glyphs;
    output->postscript_name_length = (uint32_t)resolved_name_utf8.length;
    memcpy(output->postscript_name, resolved_name_utf8.bytes,
           resolved_name_utf8.length);
    output->postscript_name[resolved_name_utf8.length] = 0;
    CFRelease(line);
    return DTR_STATUS_OK;
  }
}

int32_t dtr_font_catalog_shape(uint64_t handle, uint32_t style,
                               uint32_t feature_flags,
                               const uint8_t* text_utf8,
                               uint32_t text_length, uint8_t* output,
                               uint32_t output_capacity,
                               uint32_t* output_required) {
  @autoreleasepool {
    if (output_required == NULL ||
        (output == NULL && output_capacity != 0)) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    *output_required = 0;
    if (style > DTR_FONT_STYLE_BOLD_ITALIC ||
        (feature_flags & ~DTR_SHAPE_FEATURE_KNOWN_MASK) != 0 ||
        text_length == 0 || text_length > DTR_MAX_RESOLVE_TEXT_BYTES) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    NSString* text = DecodeUtf8(text_utf8, text_length, NO);
    if (text == nil || text.length == 0 || text.length > UINT32_MAX) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrFontCatalog* catalog = FontCatalogForHandle(handle);
    if (catalog == nil) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    BOOL synthetic = NO;
    NSFont* requested_font = [catalog fontForStyle:style synthetic:&synthetic];
    if (requested_font == nil) {
      return DTR_STATUS_NOT_FOUND;
    }
    NSDictionary* attributes = @{
      (__bridge NSString*)kCTFontAttributeName : requested_font,
      (__bridge NSString*)kCTLigatureAttributeName :
          @((feature_flags & DTR_SHAPE_FEATURE_LIGATURES) != 0 ? 1 : 0),
    };
    NSAttributedString* attributed =
        [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef created_line = CTLineCreateWithAttributedString(
        (__bridge CFAttributedStringRef)attributed);
    if (created_line == NULL) {
      return DTR_STATUS_INTERNAL;
    }
    id line_owner = CFBridgingRelease(created_line);
    CTLineRef line = (__bridge CTLineRef)line_owner;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    const CFIndex run_count = runs == NULL ? 0 : CFArrayGetCount(runs);
    if (run_count <= 0 || (uint64_t)run_count > DTR_MAX_SHAPE_RUNS) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }

    NSMutableDictionary<NSNumber*, NSNumber*>* face_indexes =
        [[NSMutableDictionary alloc] init];
    NSMutableArray<NSNumber*>* face_ids = [[NSMutableArray alloc] init];
    NSMutableArray<NSNumber*>* face_flags = [[NSMutableArray alloc] init];
    NSMutableArray<NSData*>* face_names = [[NSMutableArray alloc] init];
    uint64_t total_glyphs = 0;
    for (CFIndex run_index = 0; run_index < run_count; run_index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, run_index);
      const CFIndex glyph_count = CTRunGetGlyphCount(run);
      const CFRange string_range = CTRunGetStringRange(run);
      if (glyph_count <= 0 || string_range.location < 0 ||
          string_range.length <= 0 ||
          (uint64_t)string_range.location + (uint64_t)string_range.length >
              (uint64_t)text.length ||
          total_glyphs + (uint64_t)glyph_count > DTR_MAX_SHAPE_GLYPHS) {
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }
      const double width = CTRunGetTypographicBounds(
          run, CFRangeMake(0, 0), NULL, NULL, NULL);
      if (!isfinite(width)) {
        return DTR_STATUS_INTERNAL;
      }
      NSFont* resolved_font = FontForRun(run);
      if (resolved_font == nil) {
        return DTR_STATUS_INTERNAL;
      }
      NSString* name = PostScriptName(resolved_font);
      NSData* name_utf8 = [name dataUsingEncoding:NSUTF8StringEncoding];
      if (name_utf8 == nil || name_utf8.length == 0 ||
          name_utf8.length > DTR_MAX_POSTSCRIPT_NAME_BYTES) {
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }

      BOOL missing = NO;
      CGGlyph glyphs[256];
      CFIndex string_indices[256];
      CGPoint positions[256];
      CGSize advances[256];
      for (CFIndex start = 0; start < glyph_count; start += 256) {
        const CFIndex remaining = glyph_count - start;
        const CFIndex count = remaining < 256 ? remaining : 256;
        const CFRange range = CFRangeMake(start, count);
        CTRunGetGlyphs(run, range, glyphs);
        CTRunGetStringIndices(run, range, string_indices);
        CTRunGetPositions(run, range, positions);
        CTRunGetAdvances(run, range, advances);
        for (CFIndex index = 0; index < count; index++) {
          if (string_indices[index] < string_range.location ||
              string_indices[index] >=
                  string_range.location + string_range.length ||
              !isfinite(positions[index].x) ||
              !isfinite(positions[index].y) ||
              !isfinite(advances[index].width)) {
            return DTR_STATUS_INTERNAL;
          }
          if (glyphs[index] == 0) {
            missing = YES;
          }
        }
      }
      total_glyphs += (uint64_t)glyph_count;
      const uint32_t face_id = [catalog faceIdForFont:resolved_font];
      if (face_id == 0) {
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }
      uint32_t flags = ShapedFontFlags(requested_font, resolved_font,
                                       synthetic, missing);
      NSNumber* face_key = @(face_id);
      NSNumber* face_index_number = face_indexes[face_key];
      if (face_index_number == nil) {
        if (face_ids.count >= DTR_MAX_SHAPE_FACES) {
          return DTR_STATUS_RESOURCE_EXHAUSTED;
        }
        face_indexes[face_key] = @(face_ids.count);
        [face_ids addObject:face_key];
        [face_flags addObject:@(flags)];
        [face_names addObject:name_utf8];
      } else {
        const NSUInteger face_index = face_index_number.unsignedIntegerValue;
        face_flags[face_index] = @([face_flags[face_index] unsignedIntValue] |
                                   flags);
      }
    }
    if (total_glyphs == 0) {
      return DTR_STATUS_INTERNAL;
    }

    const uint64_t runs_offset = sizeof(DtrShapeHeaderV1);
    const uint64_t faces_offset =
        runs_offset + (uint64_t)run_count * sizeof(DtrShapeRunV1);
    const uint64_t glyphs_offset =
        faces_offset + (uint64_t)face_ids.count * sizeof(DtrShapeFaceV1);
    const uint64_t required =
        glyphs_offset + total_glyphs * sizeof(DtrShapeGlyphV1);
    if (required > DTR_MAX_SHAPE_OUTPUT_BYTES || required > UINT32_MAX) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    *output_required = (uint32_t)required;
    if (output == NULL || output_capacity < required) {
      return DTR_STATUS_BUFFER_TOO_SMALL;
    }

    const size_t boundary_count = (size_t)text.length + 1u;
    uint8_t* cluster_boundaries =
        (uint8_t*)calloc(boundary_count, sizeof(uint8_t));
    uint32_t* next_boundaries =
        (uint32_t*)malloc(boundary_count * sizeof(uint32_t));
    uint8_t* packed = (uint8_t*)calloc((size_t)required, sizeof(uint8_t));
    if (cluster_boundaries == NULL || next_boundaries == NULL ||
        packed == NULL) {
      free(cluster_boundaries);
      free(next_boundaries);
      free(packed);
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    cluster_boundaries[text.length] = 1;
    for (CFIndex run_index = 0; run_index < run_count; run_index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, run_index);
      const CFIndex glyph_count = CTRunGetGlyphCount(run);
      const CFRange string_range = CTRunGetStringRange(run);
      cluster_boundaries[string_range.location] = 1;
      cluster_boundaries[string_range.location + string_range.length] = 1;
      CFIndex string_indices[256];
      for (CFIndex start = 0; start < glyph_count; start += 256) {
        const CFIndex remaining = glyph_count - start;
        const CFIndex count = remaining < 256 ? remaining : 256;
        CTRunGetStringIndices(run, CFRangeMake(start, count), string_indices);
        for (CFIndex index = 0; index < count; index++) {
          cluster_boundaries[string_indices[index]] = 1;
        }
      }
    }
    uint32_t next_boundary = (uint32_t)text.length;
    for (size_t index = (size_t)text.length; index-- > 0;) {
      next_boundaries[index] = next_boundary;
      if (cluster_boundaries[index] != 0) {
        next_boundary = (uint32_t)index;
      }
    }
    next_boundaries[text.length] = (uint32_t)text.length;

    DtrShapeHeaderV1* header = (DtrShapeHeaderV1*)packed;
    header->magic = DTR_SHAPE_BUFFER_MAGIC;
    header->version = DTR_SHAPE_BUFFER_VERSION;
    header->header_size = sizeof(DtrShapeHeaderV1);
    header->total_size = (uint32_t)required;
    header->catalog_generation = catalog.generation;
    header->requested_style = style;
    header->feature_flags = feature_flags;
    header->utf8_length = text_length;
    header->utf16_length = (uint32_t)text.length;
    header->unicode_scalar_count = UnicodeScalarCount(text);
    header->run_count = (uint32_t)run_count;
    header->face_count = (uint32_t)face_ids.count;
    header->glyph_count = (uint32_t)total_glyphs;
    header->runs_offset = (uint32_t)runs_offset;
    header->faces_offset = (uint32_t)faces_offset;
    header->glyphs_offset = (uint32_t)glyphs_offset;

    DtrShapeRunV1* output_runs =
        (DtrShapeRunV1*)(packed + header->runs_offset);
    DtrShapeFaceV1* output_faces =
        (DtrShapeFaceV1*)(packed + header->faces_offset);
    DtrShapeGlyphV1* output_glyphs =
        (DtrShapeGlyphV1*)(packed + header->glyphs_offset);
    uint32_t glyph_cursor = 0;
    BOOL fill_valid = YES;
    for (CFIndex run_index = 0; run_index < run_count && fill_valid;
         run_index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, run_index);
      NSFont* resolved_font = FontForRun(run);
      const CFIndex glyph_count = CTRunGetGlyphCount(run);
      const CFRange string_range = CTRunGetStringRange(run);
      BOOL missing = NO;
      CGGlyph glyphs[256];
      CFIndex string_indices[256];
      CGPoint positions[256];
      CGSize advances[256];
      for (CFIndex start = 0; start < glyph_count; start += 256) {
        const CFIndex remaining = glyph_count - start;
        const CFIndex count = remaining < 256 ? remaining : 256;
        const CFRange range = CFRangeMake(start, count);
        CTRunGetGlyphs(run, range, glyphs);
        CTRunGetStringIndices(run, range, string_indices);
        CTRunGetPositions(run, range, positions);
        CTRunGetAdvances(run, range, advances);
        for (CFIndex index = 0; index < count; index++) {
          const uint32_t string_start = (uint32_t)string_indices[index];
          uint32_t string_end = next_boundaries[string_start];
          const uint32_t run_end =
              (uint32_t)(string_range.location + string_range.length);
          if (string_end > run_end) {
            string_end = run_end;
          }
          if (string_end <= string_start) {
            fill_valid = NO;
            break;
          }
          DtrShapeGlyphV1* glyph = &output_glyphs[glyph_cursor++];
          glyph->glyph_id = glyphs[index];
          glyph->face_id = [catalog faceIdForFont:resolved_font];
          glyph->run_index = (uint32_t)run_index;
          glyph->flags = glyphs[index] == 0 ? DTR_SHAPED_GLYPH_MISSING : 0;
          glyph->utf16_start = string_start;
          glyph->utf16_length = string_end - string_start;
          glyph->position_x = positions[index].x;
          glyph->position_y = positions[index].y;
          glyph->advance = advances[index].width;
          if (glyphs[index] == 0) {
            missing = YES;
          }
        }
      }
      if (!fill_valid) {
        break;
      }
      uint32_t flags = ShapedFontFlags(requested_font, resolved_font,
                                       synthetic, missing);
      if ((CTRunGetStatus(run) & kCTRunStatusRightToLeft) != 0) {
        flags |= DTR_SHAPED_RUN_RIGHT_TO_LEFT;
      }
      DtrShapeRunV1* output_run = &output_runs[run_index];
      output_run->face_id = [catalog faceIdForFont:resolved_font];
      output_run->flags = flags;
      output_run->first_glyph = glyph_cursor - (uint32_t)glyph_count;
      output_run->glyph_count = (uint32_t)glyph_count;
      output_run->utf16_start = (uint32_t)string_range.location;
      output_run->utf16_length = (uint32_t)string_range.length;
      output_run->typographic_width = CTRunGetTypographicBounds(
          run, CFRangeMake(0, 0), NULL, NULL, NULL);
    }
    for (NSUInteger face_index = 0; face_index < face_ids.count; face_index++) {
      DtrShapeFaceV1* face = &output_faces[face_index];
      NSData* name = face_names[face_index];
      face->face_id = face_ids[face_index].unsignedIntValue;
      face->flags = face_flags[face_index].unsignedIntValue;
      face->postscript_name_length = (uint32_t)name.length;
      memcpy(face->postscript_name, name.bytes, name.length);
      face->postscript_name[name.length] = 0;
    }
    free(cluster_boundaries);
    free(next_boundaries);
    if (!fill_valid || glyph_cursor != (uint32_t)total_glyphs) {
      free(packed);
      return DTR_STATUS_INTERNAL;
    }
    memcpy(output, packed, (size_t)required);
    free(packed);
    return DTR_STATUS_OK;
  }
}

int32_t dtr_font_catalog_rasterize(
    uint64_t handle, uint32_t scale_16_16,
    const DtrRasterRequestV1* requests, uint32_t request_count,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required) {
  @autoreleasepool {
    if (output_required == NULL ||
        (output == NULL && output_capacity != 0)) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    *output_required = 0;
    if (requests == NULL || request_count == 0 ||
        request_count > DTR_MAX_RASTER_GLYPHS || scale_16_16 < (1u << 15) ||
        scale_16_16 > (4u << 16)) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrFontCatalog* catalog = FontCatalogForHandle(handle);
    if (catalog == nil) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    const double scale = (double)scale_16_16 / 65536.0;
    NSMutableSet<NSNumber*>* unique = [[NSMutableSet alloc] init];
    NSMutableArray<DtrRasterizedGlyph*>* rasterized =
        [[NSMutableArray alloc] initWithCapacity:request_count];
    uint64_t total_pixel_bytes = 0;
    for (uint32_t index = 0; index < request_count; index++) {
      DtrRasterRequestV1 request = {0};
      memcpy(&request,
             (const uint8_t*)requests +
                 (size_t)index * sizeof(DtrRasterRequestV1),
             sizeof(request));
      if (request.face_id == 0 || request.glyph_id > UINT16_MAX) {
        return DTR_STATUS_INVALID_ARGUMENT;
      }
      const uint64_t packed_key =
          ((uint64_t)request.face_id << 32) | request.glyph_id;
      NSNumber* key = @(packed_key);
      if ([unique containsObject:key]) {
        return DTR_STATUS_INVALID_ARGUMENT;
      }
      [unique addObject:key];
      NSFont* font = [catalog fontForFaceId:request.face_id];
      if (font == nil) {
        return DTR_STATUS_NOT_FOUND;
      }
      int32_t raster_status = DTR_STATUS_INTERNAL;
      DtrRasterizedGlyph* glyph = RasterizeGlyph(
          font, request.face_id, request.glyph_id, scale, &raster_status);
      if (glyph == nil || raster_status != DTR_STATUS_OK) {
        return raster_status;
      }
      if (total_pixel_bytes + glyph.pixels.length > UINT32_MAX ||
          total_pixel_bytes + glyph.pixels.length >
              DTR_MAX_RASTER_OUTPUT_BYTES) {
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }
      total_pixel_bytes += glyph.pixels.length;
      [rasterized addObject:glyph];
    }

    const uint64_t records_offset = sizeof(DtrRasterHeaderV1);
    const uint64_t pixels_offset =
        records_offset +
        (uint64_t)request_count * sizeof(DtrRasterGlyphV1);
    const uint64_t required = pixels_offset + total_pixel_bytes;
    if (required > DTR_MAX_RASTER_OUTPUT_BYTES || required > UINT32_MAX) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    *output_required = (uint32_t)required;
    if (output == NULL || output_capacity < required) {
      return DTR_STATUS_BUFFER_TOO_SMALL;
    }
    uint8_t* packed = (uint8_t*)calloc((size_t)required, sizeof(uint8_t));
    if (packed == NULL) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    DtrRasterHeaderV1* header = (DtrRasterHeaderV1*)packed;
    header->magic = DTR_RASTER_BUFFER_MAGIC;
    header->version = DTR_RASTER_BUFFER_VERSION;
    header->header_size = sizeof(DtrRasterHeaderV1);
    header->total_size = (uint32_t)required;
    header->catalog_generation = catalog.generation;
    header->scale_16_16 = scale_16_16;
    header->glyph_count = request_count;
    header->records_offset = (uint32_t)records_offset;
    header->pixels_offset = (uint32_t)pixels_offset;
    header->pixel_bytes = (uint32_t)total_pixel_bytes;
    DtrRasterGlyphV1* records =
        (DtrRasterGlyphV1*)(packed + header->records_offset);
    uint32_t pixel_cursor = header->pixels_offset;
    for (uint32_t index = 0; index < request_count; index++) {
      DtrRasterizedGlyph* glyph = rasterized[index];
      DtrRasterGlyphV1* record = &records[index];
      record->face_id = glyph.faceId;
      record->glyph_id = glyph.glyphId;
      record->format = glyph.format;
      record->flags = glyph.flags;
      record->origin_x = glyph.originX;
      record->origin_y = glyph.originY;
      record->width = glyph.width;
      record->height = glyph.height;
      record->row_stride = glyph.rowStride;
      record->pixels_offset = pixel_cursor;
      record->pixel_length = (uint32_t)glyph.pixels.length;
      if (glyph.pixels.length > 0) {
        memcpy(packed + pixel_cursor, glyph.pixels.bytes,
               glyph.pixels.length);
        pixel_cursor += (uint32_t)glyph.pixels.length;
      }
    }
    if (pixel_cursor != required) {
      free(packed);
      return DTR_STATUS_INTERNAL;
    }
    memcpy(output, packed, (size_t)required);
    free(packed);
    return DTR_STATUS_OK;
  }
}

int32_t dtr_debug_live_font_catalog_count(void) {
  @autoreleasepool {
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    const NSUInteger count = FontCatalogRegistry().count;
    [lock unlock];
    return count > INT32_MAX ? INT32_MAX : (int32_t)count;
  }
}

static BOOL MetalConfigValuesAreValid(DtrMetalRendererConfigV1 config) {
  const uint64_t pixels =
      (uint64_t)config.atlas_width * config.atlas_height;
  const uint64_t atlas_bytes =
      pixels * config.maximum_alpha_pages +
      pixels * 4u * config.maximum_color_pages;
  return config.maximum_viewport_width > 0 &&
         config.maximum_viewport_width <= DTR_MAX_METAL_DIMENSION &&
         config.maximum_viewport_height > 0 &&
         config.maximum_viewport_height <= DTR_MAX_METAL_DIMENSION &&
         config.maximum_instances > 0 &&
         config.maximum_instances <= DTR_MAX_METAL_INSTANCES &&
         config.atlas_width > 0 &&
         config.atlas_width <= DTR_MAX_METAL_DIMENSION &&
         config.atlas_height > 0 &&
         config.atlas_height <= DTR_MAX_METAL_DIMENSION &&
         config.maximum_alpha_pages > 0 &&
         config.maximum_alpha_pages <= DTR_MAX_METAL_ATLAS_PAGES &&
         config.maximum_color_pages > 0 &&
         config.maximum_color_pages <= DTR_MAX_METAL_ATLAS_PAGES &&
         atlas_bytes <= DTR_MAX_METAL_ATLAS_BYTES &&
         config.reserved[0] == 0 && config.reserved[1] == 0 &&
         config.reserved[2] == 0;
}

int32_t dtr_metal_renderer_create(const DtrMetalRendererConfigV1* config,
                                  DtrMetalRendererSummaryV1* output) {
  @autoreleasepool {
    if (config == NULL || output == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    uint32_t config_header[2];
    memcpy(config_header, config, sizeof(config_header));
    uint32_t output_header[2];
    memcpy(output_header, output, sizeof(output_header));
    if (config_header[0] < sizeof(DtrMetalRendererConfigV1) ||
        config_header[1] != DTR_METAL_RENDERER_CONFIG_VERSION ||
        output_header[0] < sizeof(DtrMetalRendererSummaryV1) ||
        output_header[1] != DTR_METAL_RENDERER_SUMMARY_VERSION) {
      return DTR_STATUS_UNSUPPORTED_VERSION;
    }
    DtrMetalRendererSummaryV1 summary = {0};
    summary.struct_size = sizeof(summary);
    summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    memcpy(output, &summary, sizeof(summary));
    DtrMetalRendererConfigV1 copied_config;
    memcpy(&copied_config, config, sizeof(copied_config));
    if (!MetalConfigValuesAreValid(copied_config)) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    const uint64_t handle = atomic_fetch_add_explicit(
        &g_next_metal_renderer_handle, 1, memory_order_relaxed);
    if (handle == 0 || handle == UINT64_MAX) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    uint32_t failure = DTR_METAL_FAILURE_NONE;
    DtrMetalRenderer* renderer =
        [[DtrMetalRenderer alloc] initWithConfig:copied_config
                                      generation:handle
                                         failure:&failure];
    if (renderer == nil) {
      summary.failure_kind = failure == DTR_METAL_FAILURE_NONE
                                 ? DTR_METAL_FAILURE_RESOURCE_ALLOCATION
                                 : failure;
      memcpy(output, &summary, sizeof(summary));
      return summary.failure_kind == DTR_METAL_FAILURE_DEVICE_UNAVAILABLE
                 ? DTR_STATUS_NOT_FOUND
                 : DTR_STATUS_INTERNAL;
    }
    NSLock* lock = MetalRendererRegistryLock();
    [lock lock];
    MetalRendererRegistry()[@(handle)] = renderer;
    [lock unlock];
    summary.handle = handle;
    summary.generation = renderer.generation;
    summary.maximum_viewport_width = copied_config.maximum_viewport_width;
    summary.maximum_viewport_height = copied_config.maximum_viewport_height;
    summary.maximum_instances = copied_config.maximum_instances;
    summary.atlas_width = copied_config.atlas_width;
    summary.atlas_height = copied_config.atlas_height;
    summary.maximum_alpha_pages = copied_config.maximum_alpha_pages;
    summary.maximum_color_pages = copied_config.maximum_color_pages;
    memcpy(output, &summary, sizeof(summary));
    return DTR_STATUS_OK;
  }
}

int32_t dtr_metal_renderer_release(uint64_t handle) {
  @autoreleasepool {
    if (handle == 0) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    NSLock* lock = MetalRendererRegistryLock();
    [lock lock];
    DtrMetalRenderer* renderer = MetalRendererRegistry()[@(handle)];
    if (renderer != nil) {
      [MetalRendererRegistry() removeObjectForKey:@(handle)];
    }
    [lock unlock];
    [renderer shutdown];
    return renderer == nil ? DTR_STATUS_INVALID_HANDLE : DTR_STATUS_OK;
  }
}

void dtr_metal_renderer_release_finalizer(void* handle) {
  (void)dtr_metal_renderer_release((uint64_t)(uintptr_t)handle);
}

int32_t dtr_metal_renderer_reset_atlas(
    uint64_t handle, const DtrMetalAtlasResetV1* reset) {
  @autoreleasepool {
    if (reset == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    uint32_t reset_header[2];
    memcpy(reset_header, reset, sizeof(reset_header));
    if (reset_header[0] < sizeof(DtrMetalAtlasResetV1) ||
        reset_header[1] != DTR_METAL_ATLAS_RESET_VERSION) {
      return DTR_STATUS_UNSUPPORTED_VERSION;
    }
    DtrMetalAtlasResetV1 copied;
    memcpy(&copied, reset, sizeof(copied));
    if (copied.reserved[0] != 0 || copied.reserved[1] != 0) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil ? DTR_STATUS_INVALID_HANDLE
                           : [renderer resetAtlas:copied];
  }
}

int32_t dtr_metal_renderer_upload_atlas(
    uint64_t handle, const DtrMetalAtlasUploadV1* upload,
    const uint8_t* pixels) {
  @autoreleasepool {
    if (upload == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    uint32_t upload_header[2];
    memcpy(upload_header, upload, sizeof(upload_header));
    if (upload_header[0] < sizeof(DtrMetalAtlasUploadV1) ||
        upload_header[1] != DTR_METAL_ATLAS_UPLOAD_VERSION) {
      return DTR_STATUS_UNSUPPORTED_VERSION;
    }
    DtrMetalAtlasUploadV1 copied;
    memcpy(&copied, upload, sizeof(copied));
    if ((copied.format != DTR_METAL_ATLAS_ALPHA8 &&
         copied.format != DTR_METAL_ATLAS_RGBA8_STRAIGHT) ||
        copied.reserved[0] != 0 || copied.reserved[1] != 0 ||
        copied.reserved[2] != 0 || copied.reserved[3] != 0) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil ? DTR_STATUS_INVALID_HANDLE
                           : [renderer upload:copied pixels:pixels];
  }
}

int32_t dtr_metal_renderer_submit(uint64_t handle, const uint8_t* frame,
                                  uint32_t frame_length,
                                  DtrMetalSubmissionV1* output) {
  @autoreleasepool {
    if (output == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    uint32_t output_header[2];
    memcpy(output_header, output, sizeof(output_header));
    if (output_header[0] < sizeof(DtrMetalSubmissionV1) ||
        output_header[1] != DTR_METAL_SUBMISSION_VERSION) {
      return DTR_STATUS_UNSUPPORTED_VERSION;
    }
    DtrMetalSubmissionV1 empty = {0};
    empty.struct_size = sizeof(empty);
    empty.version = DTR_METAL_SUBMISSION_VERSION;
    memcpy(output, &empty, sizeof(empty));
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil
               ? DTR_STATUS_INVALID_HANDLE
               : [renderer submitFrame:frame length:frame_length output:output];
  }
}

int32_t dtr_metal_renderer_state(uint64_t handle,
                                 DtrMetalRendererStateV1* output) {
  @autoreleasepool {
    if (output == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    uint32_t output_header[2];
    memcpy(output_header, output, sizeof(output_header));
    if (output_header[0] < sizeof(DtrMetalRendererStateV1) ||
        output_header[1] != DTR_METAL_RENDERER_STATE_VERSION) {
      return DTR_STATUS_UNSUPPORTED_VERSION;
    }
    DtrMetalRendererStateV1 empty = {0};
    empty.struct_size = sizeof(empty);
    empty.version = DTR_METAL_RENDERER_STATE_VERSION;
    memcpy(output, &empty, sizeof(empty));
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil ? DTR_STATUS_INVALID_HANDLE
                           : [renderer copyState:output];
  }
}

int32_t dtr_metal_renderer_request_draw(uint64_t handle) {
  @autoreleasepool {
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil ? DTR_STATUS_INVALID_HANDLE
                           : [renderer requestDraw];
  }
}

int32_t dtr_metal_renderer_render_rgba(
    uint64_t handle, const uint8_t* frame, uint32_t frame_length,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required) {
  @autoreleasepool {
    if (output_required == NULL) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    *output_required = 0;
    DtrMetalRenderer* renderer = nil;
    RetainMetalRendererForHandle(handle, &renderer);
    return renderer == nil
               ? DTR_STATUS_INVALID_HANDLE
               : [renderer renderFrame:frame
                                 length:frame_length
                                 output:output
                               capacity:output_capacity
                               required:output_required];
  }
}

int32_t dtr_debug_live_metal_renderer_count(void) {
  @autoreleasepool {
    NSLock* lock = MetalRendererRegistryLock();
    [lock lock];
    const NSUInteger count = MetalRendererRegistry().count;
    [lock unlock];
    return count > INT32_MAX ? INT32_MAX : (int32_t)count;
  }
}

int32_t dtr_debug_metal_fail_next(uint32_t failure) {
  if (failure < DTR_METAL_TEST_FAILURE_CREATE_DEVICE ||
      failure > DTR_METAL_TEST_FAILURE_COMMAND_COMPLETION) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  uint32_t expected = DTR_METAL_TEST_FAILURE_NONE;
  return atomic_compare_exchange_strong_explicit(
             &g_next_metal_test_failure, &expected, failure,
             memory_order_relaxed, memory_order_relaxed)
             ? DTR_STATUS_OK
             : DTR_STATUS_BACKPRESSURED;
}
