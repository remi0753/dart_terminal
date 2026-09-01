#import <CoreText/CoreText.h>

#include <pthread.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <set>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kSummaryMagic = 0x54435444;  // "DTCT" little-endian.
constexpr uint16_t kSummaryVersion = 1;
constexpr size_t kFontNamesBytes = 256;

enum ShapeFlags : uint32_t {
  kHadFallback = 1U << 0,
  kHadColorGlyph = 1U << 1,
  kHadLigatureCluster = 1U << 2,
  kNoMissingGlyph = 1U << 3,
  kFiniteGeometry = 1U << 4,
  kValidStringIndices = 1U << 5,
  kRequestedFontResolved = 1U << 6,
  kRanOffMainThread = 1U << 7,
};

#pragma pack(push, 1)
struct ShapeSummary {
  uint32_t magic;
  uint16_t version;
  uint16_t summary_bytes;
  uint32_t case_id;
  uint32_t flags;
  uint32_t utf16_units;
  uint32_t scalar_count;
  uint32_t run_count;
  uint32_t glyph_count;
  uint32_t unique_font_count;
  uint32_t fallback_run_count;
  uint32_t color_glyph_run_count;
  uint32_t ligature_cluster_count;
  uint32_t zero_glyph_count;
  uint32_t nonzero_advance_count;
  uint32_t nonmonotonic_index_count;
  uint32_t reserved;
  uint64_t shape_micros;
  double typographic_width;
  double ascent;
  double descent;
  double leading;
  uint64_t glyph_hash;
  uint64_t font_hash;
  uint32_t main_thread_violation;
  uint32_t error_code;
  char font_names[kFontNamesBytes];
};
#pragma pack(pop)

static_assert(sizeof(ShapeSummary) == 384);

constexpr uint64_t kFnvOffset = 1469598103934665603ULL;
constexpr uint64_t kFnvPrime = 1099511628211ULL;

void HashBytes(uint64_t* hash, const void* bytes, size_t length) {
  const auto* input = static_cast<const uint8_t*>(bytes);
  for (size_t index = 0; index < length; ++index) {
    *hash ^= input[index];
    *hash *= kFnvPrime;
  }
}

std::string CopyUtf8(CFStringRef value) {
  if (value == nullptr) {
    return {};
  }
  const CFIndex length = CFStringGetLength(value);
  const CFIndex capacity =
      CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
  if (capacity <= 1) {
    return {};
  }
  std::vector<char> buffer(static_cast<size_t>(capacity));
  if (!CFStringGetCString(value, buffer.data(), capacity,
                          kCFStringEncodingUTF8)) {
    return {};
  }
  return std::string(buffer.data());
}

uint32_t CountScalars(CFStringRef value) {
  const CFIndex length = CFStringGetLength(value);
  uint32_t count = 0;
  for (CFIndex index = 0; index < length; ++index) {
    const UniChar unit = CFStringGetCharacterAtIndex(value, index);
    if (CFStringIsSurrogateHighCharacter(unit) && index + 1 < length &&
        CFStringIsSurrogateLowCharacter(
            CFStringGetCharacterAtIndex(value, index + 1))) {
      ++index;
    }
    ++count;
  }
  return count;
}

CFStringRef FontNameForCase(uint32_t case_id) {
  return case_id == 3 ? CFSTR("Times-Roman")
                      : CFSTR("Menlo-Regular");
}

CTFontRef CreateFontForCase(uint32_t case_id) {
  CTFontRef base =
      CTFontCreateWithName(FontNameForCase(case_id), 18.0, nullptr);
  if (base == nullptr || case_id != 3) {
    return base;
  }

  int enabled = 1;
  CFNumberRef enabled_value =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &enabled);
  const void* setting_keys[] = {kCTFontOpenTypeFeatureTag,
                                kCTFontOpenTypeFeatureValue};
  const void* setting_values[] = {CFSTR("liga"), enabled_value};
  CFDictionaryRef setting = CFDictionaryCreate(
      kCFAllocatorDefault, setting_keys, setting_values, 2,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void* settings_values[] = {setting};
  CFArrayRef settings = CFArrayCreate(kCFAllocatorDefault, settings_values, 1,
                                      &kCFTypeArrayCallBacks);
  const void* attribute_keys[] = {kCTFontFeatureSettingsAttribute};
  const void* attribute_values[] = {settings};
  CFDictionaryRef attributes = CFDictionaryCreate(
      kCFAllocatorDefault, attribute_keys, attribute_values, 1,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(base);
  CTFontDescriptorRef featured_descriptor =
      CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes);
  CTFontRef featured =
      CTFontCreateWithFontDescriptor(featured_descriptor, 18.0, nullptr);

  CFRelease(featured_descriptor);
  CFRelease(descriptor);
  CFRelease(attributes);
  CFRelease(settings);
  CFRelease(setting);
  CFRelease(enabled_value);
  if (featured == nullptr) {
    return base;
  }
  CFRelease(base);
  return featured;
}

int32_t Shape(const uint8_t* bytes, uint64_t length, uint32_t case_id,
              ShapeSummary* summary) {
  const auto started = std::chrono::steady_clock::now();
  summary->magic = kSummaryMagic;
  summary->version = kSummaryVersion;
  summary->summary_bytes = sizeof(ShapeSummary);
  summary->case_id = case_id;
  summary->glyph_hash = kFnvOffset;
  summary->font_hash = kFnvOffset;
  summary->main_thread_violation = pthread_main_np() != 0 ? 1U : 0U;
  if (summary->main_thread_violation == 0) {
    summary->flags |= kRanOffMainThread;
  }

  CFStringRef string = CFStringCreateWithBytes(
      kCFAllocatorDefault, bytes, static_cast<CFIndex>(length),
      kCFStringEncodingUTF8, false);
  if (string == nullptr) {
    summary->error_code = 1;
    return 1;
  }
  summary->utf16_units = static_cast<uint32_t>(CFStringGetLength(string));
  summary->scalar_count = CountScalars(string);

  CTFontRef requested_font = CreateFontForCase(case_id);
  if (requested_font == nullptr) {
    summary->error_code = 2;
    CFRelease(string);
    return 2;
  }
  CFStringRef requested_name = CTFontCopyPostScriptName(requested_font);
  if (requested_name != nullptr && CFStringGetLength(requested_name) != 0) {
    summary->flags |= kRequestedFontResolved;
  }

  CFMutableAttributedStringRef attributed =
      CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
  CFAttributedStringReplaceString(attributed, CFRangeMake(0, 0), string);
  const CFRange full_range = CFRangeMake(0, CFStringGetLength(string));
  CFAttributedStringSetAttribute(attributed, full_range, kCTFontAttributeName,
                                 requested_font);
  CFNumberRef ligature_value = nullptr;
  if (case_id == 3) {
    int ligature_level = 2;
    ligature_value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType,
                                    &ligature_level);
    CFAttributedStringSetAttribute(attributed, full_range,
                                   kCTLigatureAttributeName, ligature_value);
  }

  CTLineRef line = CTLineCreateWithAttributedString(attributed);
  if (line == nullptr) {
    summary->error_code = 3;
    if (ligature_value != nullptr) {
      CFRelease(ligature_value);
    }
    CFRelease(attributed);
    if (requested_name != nullptr) {
      CFRelease(requested_name);
    }
    CFRelease(requested_font);
    CFRelease(string);
    return 3;
  }

  double line_ascent = 0;
  double line_descent = 0;
  double line_leading = 0;
  summary->typographic_width = CTLineGetTypographicBounds(
      line, &line_ascent, &line_descent, &line_leading);
  summary->ascent = line_ascent;
  summary->descent = line_descent;
  summary->leading = line_leading;

  bool finite_geometry = std::isfinite(summary->typographic_width) &&
                         std::isfinite(summary->ascent) &&
                         std::isfinite(summary->descent) &&
                         std::isfinite(summary->leading);
  bool valid_indices = true;
  std::set<std::string> font_names;
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  const CFIndex run_count = CFArrayGetCount(runs);
  summary->run_count = static_cast<uint32_t>(run_count);

  for (CFIndex run_index = 0; run_index < run_count; ++run_index) {
    CTRunRef run = static_cast<CTRunRef>(
        const_cast<void*>(CFArrayGetValueAtIndex(runs, run_index)));
    const CFIndex glyph_count = CTRunGetGlyphCount(run);
    if (glyph_count <= 0) {
      continue;
    }
    summary->glyph_count += static_cast<uint32_t>(glyph_count);

    std::vector<CGGlyph> glyphs(static_cast<size_t>(glyph_count));
    std::vector<CGPoint> positions(static_cast<size_t>(glyph_count));
    std::vector<CGSize> advances(static_cast<size_t>(glyph_count));
    std::vector<CFIndex> indices(static_cast<size_t>(glyph_count));
    CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs.data());
    CTRunGetPositions(run, CFRangeMake(0, 0), positions.data());
    CTRunGetAdvances(run, CFRangeMake(0, 0), advances.data());
    CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.data());

    const CFRange string_range = CTRunGetStringRange(run);
    for (CFIndex glyph_index = 0; glyph_index < glyph_count; ++glyph_index) {
      const size_t index = static_cast<size_t>(glyph_index);
      HashBytes(&summary->glyph_hash, &glyphs[index], sizeof(glyphs[index]));
      HashBytes(&summary->glyph_hash, &indices[index], sizeof(indices[index]));
      if (glyphs[index] == 0) {
        ++summary->zero_glyph_count;
      }
      if (std::abs(advances[index].width) > 0.000001 ||
          std::abs(advances[index].height) > 0.000001) {
        ++summary->nonzero_advance_count;
      }
      finite_geometry = finite_geometry &&
                        std::isfinite(positions[index].x) &&
                        std::isfinite(positions[index].y) &&
                        std::isfinite(advances[index].width) &&
                        std::isfinite(advances[index].height);
      if (indices[index] < string_range.location ||
          indices[index] >= string_range.location + string_range.length) {
        valid_indices = false;
      }
      if (glyph_index > 0 && indices[index] < indices[index - 1] &&
          (CTRunGetStatus(run) & kCTRunStatusRightToLeft) == 0) {
        ++summary->nonmonotonic_index_count;
      }
      if (case_id == 3) {
        const CFIndex next =
            glyph_index + 1 < glyph_count
                ? indices[index + 1]
                : string_range.location + string_range.length;
        if (next - indices[index] > 1) {
          ++summary->ligature_cluster_count;
        }
      }
    }

    CFDictionaryRef attributes = CTRunGetAttributes(run);
    CTFontRef run_font = static_cast<CTFontRef>(
        const_cast<void*>(CFDictionaryGetValue(attributes,
                                               kCTFontAttributeName)));
    if (run_font == nullptr) {
      valid_indices = false;
      continue;
    }
    CFStringRef run_name = CTFontCopyPostScriptName(run_font);
    const std::string run_name_utf8 = CopyUtf8(run_name);
    if (!run_name_utf8.empty()) {
      font_names.insert(run_name_utf8);
      HashBytes(&summary->font_hash, run_name_utf8.data(),
                run_name_utf8.size());
    }
    if (requested_name == nullptr || run_name == nullptr ||
        !CFEqual(requested_name, run_name)) {
      ++summary->fallback_run_count;
    }
    if ((CTFontGetSymbolicTraits(run_font) & kCTFontTraitColorGlyphs) != 0) {
      ++summary->color_glyph_run_count;
    }
    if (run_name != nullptr) {
      CFRelease(run_name);
    }
  }

  summary->unique_font_count = static_cast<uint32_t>(font_names.size());
  std::string joined_names;
  for (const std::string& name : font_names) {
    if (!joined_names.empty()) {
      joined_names.append(",");
    }
    joined_names.append(name);
  }
  std::snprintf(summary->font_names, sizeof(summary->font_names), "%s",
                joined_names.c_str());

  if (summary->fallback_run_count != 0) {
    summary->flags |= kHadFallback;
  }
  if (summary->color_glyph_run_count != 0) {
    summary->flags |= kHadColorGlyph;
  }
  if (summary->ligature_cluster_count != 0) {
    summary->flags |= kHadLigatureCluster;
  }
  if (summary->zero_glyph_count == 0) {
    summary->flags |= kNoMissingGlyph;
  }
  if (finite_geometry) {
    summary->flags |= kFiniteGeometry;
  }
  if (valid_indices && summary->nonmonotonic_index_count == 0) {
    summary->flags |= kValidStringIndices;
  }

  summary->shape_micros = static_cast<uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - started)
          .count());

  CFRelease(line);
  if (ligature_value != nullptr) {
    CFRelease(ligature_value);
  }
  CFRelease(attributed);
  if (requested_name != nullptr) {
    CFRelease(requested_name);
  }
  CFRelease(requested_font);
  CFRelease(string);
  return 0;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_coretext_shape(const uint8_t* bytes, uint64_t length,
                         uint32_t case_id, uint8_t* output,
                         uint64_t output_length) {
  if (bytes == nullptr || length == 0 || case_id > 3 || output == nullptr ||
      output_length != sizeof(ShapeSummary)) {
    return 10;
  }
  std::memset(output, 0, static_cast<size_t>(output_length));
  @autoreleasepool {
    return Shape(bytes, length, case_id,
                 reinterpret_cast<ShapeSummary*>(output));
  }
}
