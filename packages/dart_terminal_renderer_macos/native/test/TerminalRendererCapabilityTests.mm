#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

#include <dlfcn.h>

#include <atomic>
#include <cmath>
#include <cstring>
#include <iostream>
#include <thread>
#include <vector>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "TerminalRendererPlugin.h"
#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

namespace {

int failures = 0;
std::atomic<uint64_t> notified_text_input_client{0};

void NotifyTextInput(uint64_t client_id) {
  notified_text_input_client.store(client_id);
}

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "TerminalRenderer expectation failed: " << description << '\n';
    ++failures;
  }
}

template <typename Function>
Function Lookup(void* image, const char* symbol) {
  dlerror();
  Function function = reinterpret_cast<Function>(dlsym(image, symbol));
  const char* error = dlerror();
  if (function == nullptr || error != nullptr) {
    std::cerr << "Could not resolve " << symbol << ": "
              << (error == nullptr ? "unknown" : error) << '\n';
    ++failures;
  }
  return function;
}

bool PixelNear(const std::vector<uint8_t>& pixels, uint32_t width,
               uint32_t x, uint32_t y, uint32_t rgba,
               uint8_t tolerance = 1) {
  const size_t offset = ((size_t)y * width + x) * 4;
  const uint8_t expected[4] = {
      static_cast<uint8_t>((rgba >> 24) & 0xffu),
      static_cast<uint8_t>((rgba >> 16) & 0xffu),
      static_cast<uint8_t>((rgba >> 8) & 0xffu),
      static_cast<uint8_t>(rgba & 0xffu),
  };
  if (offset + 4 > pixels.size()) {
    return false;
  }
  for (size_t channel = 0; channel < 4; channel++) {
    const int difference = static_cast<int>(pixels[offset + channel]) -
                           static_cast<int>(expected[channel]);
    if (std::abs(difference) > tolerance) {
      return false;
    }
  }
  return true;
}

struct RasterInkBounds {
  uint32_t width;
  uint32_t height;
  uint64_t coverage;
};

RasterInkBounds MeasureRasterInk(const std::vector<uint8_t>& buffer,
                                  const DtrRasterGlyphV1& glyph) {
  const uint32_t bytes_per_pixel =
      glyph.format == DTR_RASTER_FORMAT_RGBA8_STRAIGHT ? 4u : 1u;
  const uint32_t alpha_offset = bytes_per_pixel == 4 ? 3u : 0u;
  uint32_t left = glyph.width;
  uint32_t top = glyph.height;
  uint32_t right = 0;
  uint32_t bottom = 0;
  uint64_t coverage = 0;
  bool found = false;
  for (uint32_t y = 0; y < glyph.height; y++) {
    for (uint32_t x = 0; x < glyph.width; x++) {
      const size_t offset = glyph.pixels_offset +
                            (size_t)y * glyph.row_stride +
                            (size_t)x * bytes_per_pixel + alpha_offset;
      if (offset >= buffer.size() || buffer[offset] == 0) {
        continue;
      }
      found = true;
      coverage += buffer[offset];
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return {found ? right - left + 1 : 0, found ? bottom - top + 1 : 0,
          coverage};
}

bool LogicalRasterInkMatches(const RasterInkBounds& one,
                             const RasterInkBounds& two,
                             double tolerance) {
  return one.width > 0 && one.height > 0 && two.width > one.width &&
         two.height > one.height && two.coverage > one.coverage * 3 &&
         std::abs(static_cast<double>(two.width) / 2.0 - one.width) <=
             tolerance &&
         std::abs(static_cast<double>(two.height) / 2.0 - one.height) <=
             tolerance;
}

}  // namespace

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    if (argc != 2) {
      std::cerr << "usage: terminal_renderer_tests <plugin.dylib>\n";
      return 64;
    }
    void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == nullptr) {
      std::cerr << "Could not load renderer capability: " << dlerror() << '\n';
      return 1;
    }
    using Version = uint32_t (*)();
    using Initialize = int32_t (*)(const da_native_extension_services_v1*);
    using LiveCount = int32_t (*)();
    using FontCreate = int32_t (*)(const uint8_t*, uint32_t, double, uint32_t,
                                   DtrFontCatalogSummaryV1*);
    using FontRelease = int32_t (*)(uint64_t);
    using FontResolve = int32_t (*)(uint64_t, uint32_t, const uint8_t*,
                                    uint32_t, DtrResolvedFontV1*);
    using FontShape = int32_t (*)(uint64_t, uint32_t, uint32_t,
                                  const uint8_t*, uint32_t, uint8_t*,
                                  uint32_t, uint32_t*);
    using FontRasterize = int32_t (*)(uint64_t, uint32_t,
                                      const DtrRasterRequestV1*, uint32_t,
                                      uint8_t*, uint32_t, uint32_t*);
    using MetalCreate = int32_t (*)(const DtrMetalRendererConfigV1*,
                                    DtrMetalRendererSummaryV1*);
    using MetalRelease = int32_t (*)(uint64_t);
    using MetalFinalizer = void (*)(void*);
    using MetalReset = int32_t (*)(uint64_t,
                                   const DtrMetalAtlasResetV1*);
    using MetalUpload = int32_t (*)(uint64_t,
                                    const DtrMetalAtlasUploadV1*,
                                    const uint8_t*);
    using MetalSubmit = int32_t (*)(uint64_t, const uint8_t*, uint32_t,
                                    DtrMetalSubmissionV1*);
    using MetalState = int32_t (*)(uint64_t, DtrMetalRendererStateV1*);
    using MetalRequestDraw = int32_t (*)(uint64_t);
    using MetalRender = int32_t (*)(uint64_t, const uint8_t*, uint32_t,
                                    uint8_t*, uint32_t, uint32_t*);
    using MetalFailNext = int32_t (*)(uint32_t);
    using TextInputSetNotify = int32_t (*)(DtrTextInputNotifyV1);
    using TextInputTake = int32_t (*)(uint64_t, uint8_t*, uint32_t,
                                      uint32_t*);
    const Version version = Lookup<Version>(image, "dtr_abi_version");
    const Initialize initialize = Lookup<Initialize>(image, "dtr_initialize");
    const LiveCount live_count =
        Lookup<LiveCount>(image, "dtr_debug_live_view_count");
    const FontCreate font_create =
        Lookup<FontCreate>(image, "dtr_font_catalog_create");
    const FontRelease font_release =
        Lookup<FontRelease>(image, "dtr_font_catalog_release");
    const FontResolve font_resolve =
        Lookup<FontResolve>(image, "dtr_font_catalog_resolve");
    const FontShape font_shape =
        Lookup<FontShape>(image, "dtr_font_catalog_shape");
    const FontRasterize font_rasterize =
        Lookup<FontRasterize>(image, "dtr_font_catalog_rasterize");
    const LiveCount live_font_count =
        Lookup<LiveCount>(image, "dtr_debug_live_font_catalog_count");
    const MetalCreate metal_create =
        Lookup<MetalCreate>(image, "dtr_metal_renderer_create");
    const MetalRelease metal_release =
        Lookup<MetalRelease>(image, "dtr_metal_renderer_release");
    const MetalFinalizer metal_finalizer = Lookup<MetalFinalizer>(
        image, "dtr_metal_renderer_release_finalizer");
    const MetalReset metal_reset =
        Lookup<MetalReset>(image, "dtr_metal_renderer_reset_atlas");
    const MetalUpload metal_upload =
        Lookup<MetalUpload>(image, "dtr_metal_renderer_upload_atlas");
    const MetalSubmit metal_submit =
        Lookup<MetalSubmit>(image, "dtr_metal_renderer_submit");
    const MetalState metal_state =
        Lookup<MetalState>(image, "dtr_metal_renderer_state");
    const MetalRequestDraw metal_request_draw = Lookup<MetalRequestDraw>(
        image, "dtr_metal_renderer_request_draw");
    const MetalRender metal_render =
        Lookup<MetalRender>(image, "dtr_metal_renderer_render_rgba");
    const LiveCount live_metal_count =
        Lookup<LiveCount>(image, "dtr_debug_live_metal_renderer_count");
    const MetalFailNext metal_fail_next = Lookup<MetalFailNext>(
        image, "dtr_debug_metal_fail_next");
    const TextInputSetNotify text_input_set_notify = Lookup<TextInputSetNotify>(
        image, "dtr_text_input_set_notify_callback");
    const TextInputTake text_input_take =
        Lookup<TextInputTake>(image, "dtr_text_input_take_event");
    const LiveCount live_text_input_count = Lookup<LiveCount>(
        image, "dtr_debug_live_text_input_client_count");
    Expect(version != nullptr && version() == DTR_ABI_VERSION,
           "renderer ABI version");
    Expect(DTR_ABI_VERSION == 11,
           "terminal accessibility content origin requires renderer ABI v11");

    DtrFontCatalogSummaryV1 unsupported_summary = {};
    unsupported_summary.struct_size = sizeof(unsupported_summary);
    unsupported_summary.version = 99;
    Expect(font_create != nullptr &&
               font_create(nullptr, 0, 14.0,
                           DTR_FONT_POLICY_ALLOW_SYNTHETIC,
                           &unsupported_summary) ==
                   DTR_STATUS_UNSUPPORTED_VERSION,
           "font catalog summary version is mandatory");

    constexpr char kMenlo[] = "Menlo";
    DtrFontCatalogSummaryV1 font_summary = {};
    font_summary.struct_size = sizeof(font_summary);
    font_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create != nullptr &&
               font_create(reinterpret_cast<const uint8_t*>(kMenlo),
                           sizeof(kMenlo) - 1, 14.0,
                           DTR_FONT_POLICY_ALLOW_SYNTHETIC, &font_summary) ==
                   DTR_STATUS_OK,
           "Menlo font catalog is created");
    Expect(font_summary.struct_size == sizeof(font_summary) &&
               font_summary.version == DTR_FONT_CATALOG_SUMMARY_VERSION &&
               font_summary.handle != 0 && font_summary.generation != 0 &&
               font_summary.point_size == 14.0 &&
               std::isfinite(font_summary.cell_width) &&
               font_summary.cell_width > 0.0 &&
               std::isfinite(font_summary.cell_height) &&
               font_summary.cell_height > 0.0 &&
               font_summary.ascent > 0.0 && font_summary.descent > 0.0 &&
               font_summary.leading >= 0.0 &&
               font_summary.baseline == font_summary.ascent &&
               font_summary.underline_thickness > 0.0 &&
               font_summary.strike_position > 0.0 &&
               font_summary.strike_thickness > 0.0,
           "font catalog metrics are finite and usable");
    Expect((font_summary.available_style_bits &
            DTR_FONT_STYLE_BIT_REGULAR) != 0 &&
               font_summary.regular_face_id != 0 &&
               font_summary.bold_face_id != 0 &&
               font_summary.italic_face_id != 0 &&
               font_summary.bold_italic_face_id != 0,
           "catalog exposes explicit style face identities");
    Expect(live_font_count != nullptr && live_font_count() == 1,
           "catalog registry owns one generation");

    auto resolve = [&](uint32_t style, const uint8_t* bytes, uint32_t length,
                       DtrResolvedFontV1* output) {
      memset(output, 0, sizeof(*output));
      output->struct_size = sizeof(*output);
      output->version = DTR_RESOLVED_FONT_VERSION;
      return font_resolve(font_summary.handle, style, bytes, length, output);
    };
    constexpr char kLatin[] = "terminal";
    DtrResolvedFontV1 latin = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR,
                   reinterpret_cast<const uint8_t*>(kLatin),
                   sizeof(kLatin) - 1, &latin) == DTR_STATUS_OK,
           "Latin font resolution succeeds");
    Expect(latin.catalog_generation == font_summary.generation &&
               latin.face_id == font_summary.regular_face_id &&
               (latin.flags & DTR_RESOLVED_FONT_FALLBACK) == 0 &&
               (latin.flags & DTR_RESOLVED_FONT_MONOSPACED) != 0 &&
               (latin.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               latin.utf16_length == 8 && latin.unicode_scalar_count == 8 &&
               latin.glyph_count > 0 && latin.postscript_name_length > 0 &&
               strstr(reinterpret_cast<const char*>(latin.postscript_name),
                      "Menlo") != nullptr,
           "Latin retains requested face and exact text counts");

    const uint8_t kCjk[] = {0xe6, 0x97, 0xa5, 0xe6, 0x9c,
                            0xac, 0xe8, 0xaa, 0x9e};
    DtrResolvedFontV1 cjk = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kCjk, sizeof(kCjk), &cjk) ==
               DTR_STATUS_OK,
           "CJK font resolution succeeds");
    Expect((cjk.flags & DTR_RESOLVED_FONT_FALLBACK) != 0 &&
               (cjk.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               cjk.face_id != latin.face_id && cjk.utf16_length == 3 &&
               cjk.unicode_scalar_count == 3,
           "CJK resolves through a distinct fallback face");

    const uint8_t kEmoji[] = {0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd,
                              0xe2, 0x80, 0x8d, 0xf0, 0x9f, 0x92, 0xbb};
    DtrResolvedFontV1 emoji = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kEmoji, sizeof(kEmoji), &emoji) ==
               DTR_STATUS_OK,
           "emoji font resolution succeeds");
    Expect((emoji.flags & DTR_RESOLVED_FONT_FALLBACK) != 0 &&
               (emoji.flags & DTR_RESOLVED_FONT_COLOR_GLYPHS) != 0 &&
               (emoji.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               emoji.utf16_length == 7 && emoji.unicode_scalar_count == 4 &&
               strstr(reinterpret_cast<const char*>(emoji.postscript_name),
                      "AppleColorEmoji") != nullptr,
           "emoji resolves through the color fallback face");

    const uint8_t kInvalidUtf8[] = {0xff};
    DtrResolvedFontV1 invalid_text = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kInvalidUtf8,
                   sizeof(kInvalidUtf8), &invalid_text) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "invalid UTF-8 is rejected");

    auto shape = [&](uint64_t catalog_handle, uint32_t shape_style,
                     uint32_t features, const uint8_t* bytes,
                     uint32_t length) {
      uint32_t required = 0;
      Expect(font_shape != nullptr &&
                 font_shape(catalog_handle, shape_style, features, bytes,
                            length, nullptr, 0, &required) ==
                     DTR_STATUS_BUFFER_TOO_SMALL,
             "shape size query reports a required buffer");
      Expect(required >= sizeof(DtrShapeHeaderV1) &&
                 required <= DTR_MAX_SHAPE_OUTPUT_BYTES,
             "shape required size is bounded");
      std::vector<uint8_t> result(required, 0xa5);
      uint32_t filled_required = 0;
      Expect(font_shape(catalog_handle, shape_style, features, bytes, length,
                        result.data(), static_cast<uint32_t>(result.size()),
                        &filled_required) == DTR_STATUS_OK &&
                 filled_required == required,
             "shape fills exactly the queried buffer");
      return result;
    };
    auto rasterize = [&](uint64_t catalog_handle, uint32_t scale_16_16,
                         const std::vector<DtrRasterRequestV1>& requests) {
      uint32_t required = 0;
      Expect(font_rasterize != nullptr &&
                 font_rasterize(catalog_handle, scale_16_16, requests.data(),
                                static_cast<uint32_t>(requests.size()), nullptr,
                                0, &required) == DTR_STATUS_BUFFER_TOO_SMALL,
             "raster size query reports a required buffer");
      Expect(required >= sizeof(DtrRasterHeaderV1) &&
                 required <= DTR_MAX_RASTER_OUTPUT_BYTES,
             "raster required size is bounded");
      std::vector<uint8_t> result(required, 0xa5);
      uint32_t filled_required = 0;
      Expect(font_rasterize(catalog_handle, scale_16_16, requests.data(),
                            static_cast<uint32_t>(requests.size()),
                            result.data(),
                            static_cast<uint32_t>(result.size()),
                            &filled_required) == DTR_STATUS_OK &&
                 filled_required == required,
             "raster fills exactly the queried buffer");
      return result;
    };

    const uint8_t kMixed[] = {
        0x41,
        0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac, 0xe8, 0xaa, 0x9e,
        0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd, 0xe2, 0x80, 0x8d,
        0xf0, 0x9f, 0x92, 0xbb,
        0x65, 0xcc, 0x81,
    };
    const std::vector<uint8_t> mixed_buffer = shape(
        font_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed));
    const auto* mixed_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(mixed_buffer.data());
    Expect(mixed_header->magic == DTR_SHAPE_BUFFER_MAGIC &&
               mixed_header->version == DTR_SHAPE_BUFFER_VERSION &&
               mixed_header->header_size == sizeof(DtrShapeHeaderV1) &&
               mixed_header->total_size == mixed_buffer.size() &&
               mixed_header->catalog_generation == font_summary.generation &&
               mixed_header->requested_style == DTR_FONT_STYLE_REGULAR &&
               mixed_header->feature_flags == DTR_SHAPE_FEATURE_LIGATURES &&
               mixed_header->utf8_length == sizeof(kMixed) &&
               mixed_header->utf16_length == 13 &&
               mixed_header->unicode_scalar_count == 10 &&
               mixed_header->run_count >= 3 && mixed_header->face_count >= 3 &&
               mixed_header->glyph_count > 0,
           "mixed shaping header preserves counts and fallback structure");
    Expect(mixed_header->runs_offset == sizeof(DtrShapeHeaderV1) &&
               mixed_header->faces_offset ==
                   mixed_header->runs_offset +
                       mixed_header->run_count * sizeof(DtrShapeRunV1) &&
               mixed_header->glyphs_offset ==
                   mixed_header->faces_offset +
                       mixed_header->face_count * sizeof(DtrShapeFaceV1) &&
               mixed_header->total_size ==
                   mixed_header->glyphs_offset +
                       mixed_header->glyph_count * sizeof(DtrShapeGlyphV1),
           "packed shaping sections are contiguous and exact");
    const auto* mixed_runs = reinterpret_cast<const DtrShapeRunV1*>(
        mixed_buffer.data() + mixed_header->runs_offset);
    const auto* mixed_faces = reinterpret_cast<const DtrShapeFaceV1*>(
        mixed_buffer.data() + mixed_header->faces_offset);
    const auto* mixed_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        mixed_buffer.data() + mixed_header->glyphs_offset);
    bool saw_color_face = false;
    bool saw_cjk_fallback = false;
    bool saw_emoji_cluster = false;
    bool saw_combining_cluster = false;
    uint32_t covered_glyphs = 0;
    for (uint32_t face = 0; face < mixed_header->face_count; face++) {
      saw_color_face |=
          (mixed_faces[face].flags & DTR_SHAPED_RUN_COLOR_GLYPHS) != 0;
      Expect(mixed_faces[face].face_id != 0 &&
                 mixed_faces[face].postscript_name_length > 0 &&
                 mixed_faces[face].postscript_name_length <=
                     DTR_MAX_POSTSCRIPT_NAME_BYTES &&
                 mixed_faces[face].postscript_name
                         [mixed_faces[face].postscript_name_length] == 0,
             "packed face has stable identity and bounded copied name");
    }
    for (uint32_t run = 0; run < mixed_header->run_count; run++) {
      Expect(mixed_runs[run].first_glyph == covered_glyphs &&
                 mixed_runs[run].glyph_count > 0 &&
                 mixed_runs[run].utf16_length > 0 &&
                 mixed_runs[run].utf16_start + mixed_runs[run].utf16_length <=
                     mixed_header->utf16_length &&
                 std::isfinite(mixed_runs[run].typographic_width),
             "packed run covers a finite bounded range");
      saw_cjk_fallback |=
          (mixed_runs[run].flags & DTR_SHAPED_RUN_FALLBACK) != 0 &&
          (mixed_runs[run].flags & DTR_SHAPED_RUN_COLOR_GLYPHS) == 0;
      covered_glyphs += mixed_runs[run].glyph_count;
    }
    for (uint32_t glyph = 0; glyph < mixed_header->glyph_count; glyph++) {
      const DtrShapeGlyphV1& item = mixed_glyphs[glyph];
      Expect(item.run_index < mixed_header->run_count && item.face_id != 0 &&
                 item.utf16_length > 0 &&
                 item.utf16_start + item.utf16_length <=
                     mixed_header->utf16_length &&
                 std::isfinite(item.position_x) &&
                 std::isfinite(item.position_y) &&
                 std::isfinite(item.advance),
             "packed glyph has a finite position and logical cluster");
      saw_emoji_cluster |= item.utf16_start == 4 && item.utf16_length == 7;
      saw_combining_cluster |= item.utf16_start == 11 && item.utf16_length == 2;
    }
    Expect(covered_glyphs == mixed_header->glyph_count && saw_color_face &&
               saw_cjk_fallback && saw_emoji_cluster &&
               saw_combining_cluster,
           "mixed shaping preserves CJK, color emoji, and combining clusters");

    DtrRasterRequestV1 latin_raster = {0, 0};
    DtrRasterRequestV1 cjk_raster = {0, 0};
    DtrRasterRequestV1 emoji_raster = {0, 0};
    DtrRasterRequestV1 combining_raster = {0, 0};
    for (uint32_t glyph = 0; glyph < mixed_header->glyph_count; glyph++) {
      const DtrShapeGlyphV1& item = mixed_glyphs[glyph];
      DtrRasterRequestV1 request = {item.face_id, item.glyph_id};
      if (item.utf16_start == 0 && latin_raster.face_id == 0) {
        latin_raster = request;
      } else if (item.utf16_start == 1 && cjk_raster.face_id == 0) {
        cjk_raster = request;
      } else if (item.utf16_start == 4 && emoji_raster.face_id == 0) {
        emoji_raster = request;
      } else if (item.utf16_start == 11 && combining_raster.face_id == 0) {
        combining_raster = request;
      }
    }
    constexpr char kSpace[] = " ";
    const std::vector<uint8_t> space_shape = shape(
        font_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES,
        reinterpret_cast<const uint8_t*>(kSpace), sizeof(kSpace) - 1);
    const auto* space_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(space_shape.data());
    const auto* space_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        space_shape.data() + space_header->glyphs_offset);
    DtrRasterRequestV1 space_raster = {space_glyphs[0].face_id,
                                       space_glyphs[0].glyph_id};
    Expect(latin_raster.face_id != 0 && cjk_raster.face_id != 0 &&
               emoji_raster.face_id != 0 && combining_raster.face_id != 0 &&
               space_raster.face_id != 0,
           "shaped glyph keys are available for raster requests");
    const std::vector<DtrRasterRequestV1> raster_requests = {
        latin_raster, cjk_raster, emoji_raster, combining_raster, space_raster};
    const std::vector<uint8_t> raster_1x = rasterize(
        font_summary.handle, 1u << 16, raster_requests);
    const auto* raster_header =
        reinterpret_cast<const DtrRasterHeaderV1*>(raster_1x.data());
    const auto* raster_records = reinterpret_cast<const DtrRasterGlyphV1*>(
        raster_1x.data() + raster_header->records_offset);
    Expect(raster_header->magic == DTR_RASTER_BUFFER_MAGIC &&
               raster_header->version == DTR_RASTER_BUFFER_VERSION &&
               raster_header->header_size == sizeof(DtrRasterHeaderV1) &&
               raster_header->total_size == raster_1x.size() &&
               raster_header->catalog_generation == font_summary.generation &&
               raster_header->scale_16_16 == (1u << 16) &&
               raster_header->glyph_count == raster_requests.size() &&
               raster_header->records_offset == sizeof(DtrRasterHeaderV1) &&
               raster_header->pixels_offset ==
                   sizeof(DtrRasterHeaderV1) +
                       raster_requests.size() * sizeof(DtrRasterGlyphV1) &&
               raster_header->pixel_bytes ==
                   raster_header->total_size - raster_header->pixels_offset,
           "raster header preserves generation, scale, and exact sections");
    uint32_t raster_pixel_cursor = raster_header->pixels_offset;
    bool saw_color_pixel = false;
    for (uint32_t index = 0; index < raster_header->glyph_count; index++) {
      const DtrRasterGlyphV1& item = raster_records[index];
      const DtrRasterRequestV1& request = raster_requests[index];
      const uint32_t bytes_per_pixel =
          item.format == DTR_RASTER_FORMAT_RGBA8_STRAIGHT ? 4u : 1u;
      Expect(item.face_id == request.face_id &&
                 item.glyph_id == request.glyph_id &&
                 item.pixels_offset == raster_pixel_cursor &&
                 item.width <= DTR_MAX_RASTER_DIMENSION &&
                 item.height <= DTR_MAX_RASTER_DIMENSION &&
                 ((item.width == 0 && item.height == 0 &&
                   item.row_stride == 0 && item.pixel_length == 0) ||
                  (item.width > 0 && item.height > 0 &&
                   item.row_stride == item.width * bytes_per_pixel &&
                   item.pixel_length == item.row_stride * item.height)),
             "raster record matches request and tight pixel extent");
      bool nonzero_coverage = false;
      for (uint32_t offset = 0; offset < item.pixel_length;
           offset += bytes_per_pixel) {
        const uint8_t* pixel =
            raster_1x.data() + item.pixels_offset + offset;
        const uint8_t alpha = bytes_per_pixel == 1 ? pixel[0] : pixel[3];
        nonzero_coverage |= alpha != 0;
        if (bytes_per_pixel == 4 && alpha != 0 &&
            (pixel[0] != pixel[1] || pixel[1] != pixel[2])) {
          saw_color_pixel = true;
        }
        if (bytes_per_pixel == 4 && alpha == 0) {
          Expect(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0,
                 "straight RGBA clears transparent color channels");
        }
      }
      if (index + 1 < raster_header->glyph_count) {
        Expect(nonzero_coverage,
               "visible Latin/CJK/emoji/combining raster has coverage");
      }
      raster_pixel_cursor += item.pixel_length;
    }
    Expect(raster_records[0].format == DTR_RASTER_FORMAT_ALPHA8 &&
               raster_records[1].format == DTR_RASTER_FORMAT_ALPHA8 &&
               raster_records[2].format ==
                   DTR_RASTER_FORMAT_RGBA8_STRAIGHT &&
               (raster_records[2].flags & DTR_RASTER_GLYPH_COLOR) != 0 &&
               raster_records[3].format == DTR_RASTER_FORMAT_ALPHA8 &&
               raster_records[4].width == 0 &&
               raster_records[4].height == 0 && saw_color_pixel &&
               raster_pixel_cursor == raster_header->total_size,
           "raster distinguishes alpha, color, and zero-area whitespace");
    const std::vector<uint8_t> raster_2x = rasterize(
        font_summary.handle, 2u << 16, raster_requests);
    const auto* raster_2x_header =
        reinterpret_cast<const DtrRasterHeaderV1*>(raster_2x.data());
    const auto* raster_2x_records = reinterpret_cast<const DtrRasterGlyphV1*>(
        raster_2x.data() + raster_2x_header->records_offset);
    Expect(raster_2x_header->scale_16_16 == (2u << 16) &&
               raster_2x_header->pixel_bytes > raster_header->pixel_bytes,
           "2x raster has distinct scale identity and greater pixel storage");
    const RasterInkBounds latin_1x =
        MeasureRasterInk(raster_1x, raster_records[0]);
    const RasterInkBounds latin_2x =
        MeasureRasterInk(raster_2x, raster_2x_records[0]);
    const RasterInkBounds emoji_1x =
        MeasureRasterInk(raster_1x, raster_records[2]);
    const RasterInkBounds emoji_2x =
        MeasureRasterInk(raster_2x, raster_2x_records[2]);
    Expect(LogicalRasterInkMatches(latin_1x, latin_2x, 1.0),
           "2x alpha raster doubles ink while preserving logical size");
    Expect(LogicalRasterInkMatches(emoji_1x, emoji_2x, 3.0),
           "2x color raster doubles ink while preserving logical size");

    uint32_t raster_required = 0;
    std::vector<uint8_t> raster_undersized(raster_1x.size() - 1, 0xa5);
    Expect(font_rasterize(
               font_summary.handle, 1u << 16, raster_requests.data(),
               static_cast<uint32_t>(raster_requests.size()),
               raster_undersized.data(),
               static_cast<uint32_t>(raster_undersized.size()),
               &raster_required) == DTR_STATUS_BUFFER_TOO_SMALL &&
               raster_required == raster_1x.size(),
           "undersized raster output reports exact retry size");
    bool raster_untouched = true;
    for (uint8_t byte : raster_undersized) {
      raster_untouched &= byte == 0xa5;
    }
    Expect(raster_untouched, "undersized raster output remains untouched");
    const std::vector<DtrRasterRequestV1> duplicate_rasters = {
        latin_raster, latin_raster};
    Expect(font_rasterize(font_summary.handle, 1u << 16,
                          duplicate_rasters.data(),
                          static_cast<uint32_t>(duplicate_rasters.size()),
                          nullptr, 0, &raster_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "duplicate raster keys are rejected");
    const DtrRasterRequestV1 unknown_face = {UINT32_MAX, 1};
    Expect(font_rasterize(font_summary.handle, 1u << 16, &unknown_face, 1,
                          nullptr, 0, &raster_required) ==
               DTR_STATUS_NOT_FOUND,
           "unknown raster face is rejected");
    const DtrRasterRequestV1 invalid_glyph = {latin_raster.face_id, 0x10000};
    Expect(font_rasterize(font_summary.handle, 1u << 16, &invalid_glyph, 1,
                          nullptr, 0, &raster_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "out-of-range CoreText glyph ID is rejected");
    Expect(font_rasterize(font_summary.handle, 0, raster_requests.data(),
                          static_cast<uint32_t>(raster_requests.size()),
                          nullptr, 0, &raster_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "invalid fixed-point raster scale is rejected");
    Expect(font_rasterize(font_summary.handle, 1u << 16,
                          raster_requests.data(),
                          DTR_MAX_RASTER_GLYPHS + 1, nullptr, 0,
                          &raster_required) == DTR_STATUS_INVALID_ARGUMENT,
           "over-limit raster batch is rejected before reading requests");

    const uint8_t kEmojiFlag[] = {
        0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd, 0xe2, 0x80, 0x8d,
        0xf0, 0x9f, 0x92, 0xbb, 0xf0, 0x9f, 0x87, 0xaf, 0xf0, 0x9f, 0x87,
        0xb5,
    };
    const std::vector<uint8_t> emoji_flag_buffer = shape(
        font_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES, kEmojiFlag, sizeof(kEmojiFlag));
    const auto* emoji_flag_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(emoji_flag_buffer.data());
    const auto* emoji_flag_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        emoji_flag_buffer.data() + emoji_flag_header->glyphs_offset);
    bool saw_zwj_modifier = false;
    bool saw_flag = false;
    for (uint32_t glyph = 0; glyph < emoji_flag_header->glyph_count; glyph++) {
      saw_zwj_modifier |= emoji_flag_glyphs[glyph].utf16_start == 0 &&
                          emoji_flag_glyphs[glyph].utf16_length == 7;
      saw_flag |= emoji_flag_glyphs[glyph].utf16_start == 7 &&
                  emoji_flag_glyphs[glyph].utf16_length == 4;
    }
    Expect(emoji_flag_header->utf16_length == 11 &&
               emoji_flag_header->unicode_scalar_count == 6 &&
               saw_zwj_modifier && saw_flag,
           "emoji ZWJ/modifier and regional-indicator flag clusters survive");

    uint32_t small_required = 0;
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                      nullptr, 1, &small_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "null shaping output cannot claim nonzero capacity");
    std::vector<uint8_t> undersized(mixed_buffer.size() - 1, 0xa5);
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                      undersized.data(),
                      static_cast<uint32_t>(undersized.size()),
                      &small_required) == DTR_STATUS_BUFFER_TOO_SMALL &&
               small_required == mixed_buffer.size(),
           "undersized shaping output reports the exact retry size");
    bool undersized_untouched = true;
    for (uint8_t byte : undersized) {
      undersized_untouched &= byte == 0xa5;
    }
    Expect(undersized_untouched,
           "undersized shaping call never writes a partial record");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0x80000000,
                      kMixed, sizeof(kMixed), nullptr, 0, &small_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "unknown shaping feature is rejected");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      kInvalidUtf8, sizeof(kInvalidUtf8), nullptr, 0,
                      &small_required) == DTR_STATUS_INVALID_ARGUMENT,
           "shaping rejects malformed UTF-8 before allocation");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      DTR_MAX_RESOLVE_TEXT_BYTES + 1, nullptr, 0,
                      &small_required) == DTR_STATUS_INVALID_ARGUMENT,
           "shaping rejects an over-limit input before reading it");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      sizeof(kLatin) - 1, nullptr, 0, nullptr) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "shaping requires an output-size pointer");

    constexpr char kTimes[] = "Times-Roman";
    DtrFontCatalogSummaryV1 times_summary = {};
    times_summary.struct_size = sizeof(times_summary);
    times_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create(reinterpret_cast<const uint8_t*>(kTimes),
                       sizeof(kTimes) - 1, 16.0,
                       DTR_FONT_POLICY_ALLOW_SYNTHETIC, &times_summary) ==
               DTR_STATUS_OK,
           "ligature test face is created");
    constexpr char kLigatures[] = "office ffi affluent";
    const std::vector<uint8_t> ligatures_on = shape(
        times_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES,
        reinterpret_cast<const uint8_t*>(kLigatures),
        sizeof(kLigatures) - 1);
    const std::vector<uint8_t> ligatures_off = shape(
        times_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
        reinterpret_cast<const uint8_t*>(kLigatures),
        sizeof(kLigatures) - 1);
    const auto* ligatures_on_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(ligatures_on.data());
    const auto* ligatures_off_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(ligatures_off.data());
    const auto* ligature_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        ligatures_on.data() + ligatures_on_header->glyphs_offset);
    bool saw_ligature_span = false;
    for (uint32_t glyph = 0; glyph < ligatures_on_header->glyph_count; glyph++) {
      saw_ligature_span |= ligature_glyphs[glyph].utf16_length > 1;
    }
    Expect(ligatures_on_header->glyph_count <
                   ligatures_off_header->glyph_count &&
               saw_ligature_span,
           "ligature feature changes glyph count and cluster span");
    Expect(font_release(times_summary.handle) == DTR_STATUS_OK,
           "ligature test catalog releases");

    std::atomic<int> concurrent_failures{0};
    std::vector<std::thread> resolvers;
    for (int worker = 0; worker < 4; worker++) {
      resolvers.emplace_back([&] {
        for (int iteration = 0; iteration < 100; iteration++) {
          DtrResolvedFontV1 result = {};
          result.struct_size = sizeof(result);
          result.version = DTR_RESOLVED_FONT_VERSION;
          if (font_resolve(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                           reinterpret_cast<const uint8_t*>(kLatin),
                           sizeof(kLatin) - 1, &result) != DTR_STATUS_OK ||
              result.catalog_generation != font_summary.generation) {
            concurrent_failures.fetch_add(1);
          }
        }
      });
    }
    for (std::thread& resolver : resolvers) {
      resolver.join();
    }
    Expect(concurrent_failures.load() == 0,
           "concurrent catalog reads retain one valid generation");
    std::atomic<int> concurrent_shape_failures{0};
    std::vector<std::thread> shapers;
    for (int worker = 0; worker < 4; worker++) {
      shapers.emplace_back([&] {
        for (int iteration = 0; iteration < 50; iteration++) {
          uint32_t required = 0;
          if (font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                         DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                         nullptr, 0, &required) !=
                  DTR_STATUS_BUFFER_TOO_SMALL ||
              required < sizeof(DtrShapeHeaderV1) ||
              required > DTR_MAX_SHAPE_OUTPUT_BYTES) {
            concurrent_shape_failures.fetch_add(1);
            continue;
          }
          std::vector<uint8_t> bytes(required);
          uint32_t filled = 0;
          if (font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                         DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                         bytes.data(), static_cast<uint32_t>(bytes.size()),
                         &filled) != DTR_STATUS_OK ||
              filled != required ||
              reinterpret_cast<const DtrShapeHeaderV1*>(bytes.data())
                      ->catalog_generation != font_summary.generation) {
            concurrent_shape_failures.fetch_add(1);
          }
        }
      });
    }
    for (std::thread& shaper : shapers) {
      shaper.join();
    }
    Expect(concurrent_shape_failures.load() == 0,
           "concurrent whole-run shaping preserves one catalog generation");
    std::atomic<int> concurrent_raster_failures{0};
    std::vector<std::thread> rasterizers;
    for (int worker = 0; worker < 4; worker++) {
      rasterizers.emplace_back([&] {
        for (int iteration = 0; iteration < 10; iteration++) {
          uint32_t required = 0;
          if (font_rasterize(
                  font_summary.handle, 1u << 16, raster_requests.data(),
                  static_cast<uint32_t>(raster_requests.size()), nullptr, 0,
                  &required) != DTR_STATUS_BUFFER_TOO_SMALL ||
              required < sizeof(DtrRasterHeaderV1) ||
              required > DTR_MAX_RASTER_OUTPUT_BYTES) {
            concurrent_raster_failures.fetch_add(1);
            continue;
          }
          std::vector<uint8_t> bytes(required);
          uint32_t filled = 0;
          if (font_rasterize(
                  font_summary.handle, 1u << 16, raster_requests.data(),
                  static_cast<uint32_t>(raster_requests.size()), bytes.data(),
                  static_cast<uint32_t>(bytes.size()), &filled) !=
                  DTR_STATUS_OK ||
              filled != required ||
              reinterpret_cast<const DtrRasterHeaderV1*>(bytes.data())
                      ->catalog_generation != font_summary.generation) {
            concurrent_raster_failures.fetch_add(1);
          }
        }
      });
    }
    for (std::thread& rasterizer : rasterizers) {
      rasterizer.join();
    }
    Expect(concurrent_raster_failures.load() == 0,
           "concurrent raster batches preserve one catalog generation");
    const uint64_t released_font_handle = font_summary.handle;
    Expect(font_release != nullptr &&
               font_release(released_font_handle) == DTR_STATUS_OK,
           "font catalog releases exactly once");
    Expect(font_release(released_font_handle) == DTR_STATUS_INVALID_HANDLE,
           "double font catalog release is rejected");
    DtrResolvedFontV1 stale = {};
    stale.struct_size = sizeof(stale);
    stale.version = DTR_RESOLVED_FONT_VERSION;
    Expect(font_resolve(released_font_handle, DTR_FONT_STYLE_REGULAR,
                        reinterpret_cast<const uint8_t*>(kLatin),
                        sizeof(kLatin) - 1, &stale) ==
               DTR_STATUS_INVALID_HANDLE,
           "released font catalog generation cannot resolve");
    uint32_t stale_shape_required = 0;
    Expect(font_shape(released_font_handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      sizeof(kLatin) - 1, nullptr, 0,
                      &stale_shape_required) == DTR_STATUS_INVALID_HANDLE &&
               stale_shape_required == 0,
           "released font catalog generation cannot shape");
    uint32_t stale_raster_required = 0;
    Expect(font_rasterize(released_font_handle, 1u << 16,
                          raster_requests.data(),
                          static_cast<uint32_t>(raster_requests.size()),
                          nullptr, 0, &stale_raster_required) ==
               DTR_STATUS_INVALID_HANDLE &&
               stale_raster_required == 0,
           "released font catalog generation cannot rasterize");
    Expect(live_font_count() == 0, "font catalog registry returns to zero");

    DtrFontCatalogSummaryV1 racing_summary = {};
    racing_summary.struct_size = sizeof(racing_summary);
    racing_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create(reinterpret_cast<const uint8_t*>(kMenlo),
                       sizeof(kMenlo) - 1, 14.0,
                       DTR_FONT_POLICY_ALLOW_SYNTHETIC, &racing_summary) ==
               DTR_STATUS_OK,
           "concurrent-release catalog is created");
    std::atomic<bool> begin_race{false};
    std::atomic<int> race_failures{0};
    std::vector<std::thread> racing_resolvers;
    for (int worker = 0; worker < 4; worker++) {
      racing_resolvers.emplace_back([&] {
        while (!begin_race.load()) {
          std::this_thread::yield();
        }
        for (int iteration = 0; iteration < 200; iteration++) {
          DtrResolvedFontV1 result = {};
          result.struct_size = sizeof(result);
          result.version = DTR_RESOLVED_FONT_VERSION;
          const int32_t status = font_resolve(
              racing_summary.handle, DTR_FONT_STYLE_REGULAR,
              reinterpret_cast<const uint8_t*>(kLatin), sizeof(kLatin) - 1,
              &result);
          if (status != DTR_STATUS_OK && status != DTR_STATUS_INVALID_HANDLE) {
            race_failures.fetch_add(1);
          }
          if (status == DTR_STATUS_OK &&
              result.catalog_generation != racing_summary.generation) {
            race_failures.fetch_add(1);
          }
        }
      });
    }
    begin_race.store(true);
    Expect(font_release(racing_summary.handle) == DTR_STATUS_OK,
           "catalog release races safely with retained readers");
    for (std::thread& resolver : racing_resolvers) {
      resolver.join();
    }
    Expect(race_failures.load() == 0,
           "concurrent release yields only retained success or stale handle");
    Expect(live_font_count() == 0,
           "concurrent release returns catalog registry to zero");

    DtrMetalRendererConfigV1 metal_config = {};
    metal_config.struct_size = sizeof(metal_config);
    metal_config.version = DTR_METAL_RENDERER_CONFIG_VERSION;
    metal_config.maximum_viewport_width = 16;
    metal_config.maximum_viewport_height = 16;
    metal_config.maximum_instances = 16;
    metal_config.atlas_width = 8;
    metal_config.atlas_height = 8;
    metal_config.maximum_alpha_pages = 2;
    metal_config.maximum_color_pages = 2;
    DtrMetalRendererSummaryV1 unsupported_metal_summary = {};
    unsupported_metal_summary.struct_size = sizeof(unsupported_metal_summary);
    unsupported_metal_summary.version = 99;
    Expect(metal_create != nullptr &&
               metal_create(&metal_config, &unsupported_metal_summary) ==
                   DTR_STATUS_UNSUPPORTED_VERSION,
           "Metal summary version is mandatory");
    DtrMetalRendererConfigV1 invalid_metal_config = metal_config;
    invalid_metal_config.maximum_viewport_width = 0;
    DtrMetalRendererSummaryV1 invalid_metal_summary = {};
    invalid_metal_summary.struct_size = sizeof(invalid_metal_summary);
    invalid_metal_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    Expect(metal_create(&invalid_metal_config, &invalid_metal_summary) ==
               DTR_STATUS_INVALID_ARGUMENT &&
               invalid_metal_summary.handle == 0,
           "invalid Metal resource bounds are rejected without publication");

    Expect(metal_fail_next != nullptr &&
               metal_fail_next(DTR_METAL_TEST_FAILURE_NONE) ==
                   DTR_STATUS_INVALID_ARGUMENT,
           "Metal fault injection rejects an unknown empty fault");
    DtrMetalRendererSummaryV1 device_failure_summary = {};
    device_failure_summary.struct_size = sizeof(device_failure_summary);
    device_failure_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    Expect(metal_fail_next(DTR_METAL_TEST_FAILURE_CREATE_DEVICE) ==
                   DTR_STATUS_OK &&
               metal_create(&metal_config, &device_failure_summary) ==
                   DTR_STATUS_NOT_FOUND &&
               device_failure_summary.handle == 0 &&
               device_failure_summary.generation == 0 &&
               device_failure_summary.failure_kind ==
                   DTR_METAL_FAILURE_DEVICE_UNAVAILABLE &&
               live_metal_count() == 0,
           "device creation failure is typed without handle publication");
    DtrMetalRendererSummaryV1 shader_failure_summary = {};
    shader_failure_summary.struct_size = sizeof(shader_failure_summary);
    shader_failure_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    Expect(metal_fail_next(
               DTR_METAL_TEST_FAILURE_CREATE_SHADER_LIBRARY) ==
                   DTR_STATUS_OK &&
               metal_create(&metal_config, &shader_failure_summary) ==
                   DTR_STATUS_INTERNAL &&
               shader_failure_summary.handle == 0 &&
               shader_failure_summary.generation == 0 &&
               shader_failure_summary.failure_kind ==
                   DTR_METAL_FAILURE_SHADER_LIBRARY &&
               live_metal_count() == 0,
           "shader library failure is typed without resource publication");

    DtrMetalRendererSummaryV1 metal_summary = {};
    metal_summary.struct_size = sizeof(metal_summary);
    metal_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    Expect(metal_create(&metal_config, &metal_summary) == DTR_STATUS_OK,
           "precompiled Metal renderer is created");
    Expect(metal_summary.handle != 0 && metal_summary.generation != 0 &&
               metal_summary.maximum_viewport_width == 16 &&
               metal_summary.maximum_viewport_height == 16 &&
               metal_summary.maximum_instances == 16 &&
               metal_summary.atlas_width == 8 &&
               metal_summary.atlas_height == 8 &&
               metal_summary.maximum_alpha_pages == 2 &&
               metal_summary.maximum_color_pages == 2 &&
               metal_summary.failure_kind == DTR_METAL_FAILURE_NONE &&
               live_metal_count != nullptr && live_metal_count() == 1,
           "Metal renderer publishes exact bounded resource identity");

    DtrMetalAtlasResetV1 initial_atlas_reset = {};
    initial_atlas_reset.struct_size = sizeof(initial_atlas_reset);
    initial_atlas_reset.version = DTR_METAL_ATLAS_RESET_VERSION;
    initial_atlas_reset.renderer_generation = metal_summary.generation;
    initial_atlas_reset.atlas_generation = 1;
    Expect(metal_reset != nullptr &&
               metal_reset(metal_summary.handle, &initial_atlas_reset) ==
                   DTR_STATUS_OK,
           "empty atlas reset publishes the first complete generation");
    DtrMetalAtlasResetV1 invalid_atlas_reset = initial_atlas_reset;
    invalid_atlas_reset.version = 99;
    Expect(metal_reset(metal_summary.handle, &invalid_atlas_reset) ==
               DTR_STATUS_UNSUPPORTED_VERSION,
           "atlas reset version is mandatory");
    invalid_atlas_reset = initial_atlas_reset;
    invalid_atlas_reset.reserved[0] = 1;
    Expect(metal_reset(metal_summary.handle, &invalid_atlas_reset) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "atlas reset reserved fields are zero");
    Expect(metal_reset(metal_summary.handle, &initial_atlas_reset) ==
               DTR_STATUS_STALE_GENERATION,
           "an atlas reset generation cannot be reused");

    auto atlas_upload = [&](uint32_t format, uint64_t atlas_generation,
                            uint64_t page_generation, uint32_t x, uint32_t y,
                            uint32_t width, uint32_t height) {
      DtrMetalAtlasUploadV1 upload = {};
      upload.struct_size = sizeof(upload);
      upload.version = DTR_METAL_ATLAS_UPLOAD_VERSION;
      upload.renderer_generation = metal_summary.generation;
      upload.atlas_generation = atlas_generation;
      upload.page_generation = page_generation;
      upload.format = format;
      upload.page_index = 0;
      upload.x = x;
      upload.y = y;
      upload.width = width;
      upload.height = height;
      const uint32_t bytes_per_pixel =
          format == DTR_METAL_ATLAS_ALPHA8 ? 1u : 4u;
      upload.row_stride = width * bytes_per_pixel;
      upload.byte_length = upload.row_stride * height;
      return upload;
    };
    const std::vector<uint8_t> alpha_pixels(4, 128);
    DtrMetalAtlasUploadV1 alpha_upload = atlas_upload(
        DTR_METAL_ATLAS_ALPHA8, 1, 1, 1, 1, 2, 2);
    Expect(metal_upload != nullptr &&
               metal_upload(metal_summary.handle, &alpha_upload,
                            alpha_pixels.data()) == DTR_STATUS_OK,
           "alpha atlas dirty rectangle is copied");
    const std::vector<uint8_t> color_pixels = {
        0, 255, 0, 128, 0, 255, 0, 128,
        0, 255, 0, 128, 0, 255, 0, 128,
    };
    DtrMetalAtlasUploadV1 color_upload = atlas_upload(
        DTR_METAL_ATLAS_RGBA8_STRAIGHT, 1, 1, 1, 1, 2, 2);
    Expect(metal_upload(metal_summary.handle, &color_upload,
                        color_pixels.data()) == DTR_STATUS_OK,
           "straight RGBA atlas dirty rectangle is copied");
    DtrMetalAtlasUploadV1 invalid_upload = alpha_upload;
    invalid_upload.row_stride = 3;
    invalid_upload.byte_length = 6;
    Expect(metal_upload(metal_summary.handle, &invalid_upload,
                        alpha_pixels.data()) == DTR_STATUS_INVALID_ARGUMENT,
           "malformed atlas byte layout is rejected before mutation");
    invalid_upload = alpha_upload;
    invalid_upload.page_generation = (uint64_t)UINT32_MAX + 1u;
    Expect(metal_upload(metal_summary.handle, &invalid_upload,
                        alpha_pixels.data()) == DTR_STATUS_INVALID_ARGUMENT,
           "atlas page generation fits the packed frame field");

    DtrMetalInstanceV1 cell = {};
    cell.width = 8;
    cell.height = 8;
    cell.color_rgba = 0x202020ff;
    cell.kind = DTR_METAL_INSTANCE_CELL_BACKGROUND;
    DtrMetalInstanceV1 selection = {};
    selection.width = 2;
    selection.height = 2;
    selection.color_rgba = 0x0000ff80;
    selection.kind = DTR_METAL_INSTANCE_SELECTION;
    DtrMetalInstanceV1 alpha_glyph = {};
    alpha_glyph.x = 2;
    alpha_glyph.width = 2;
    alpha_glyph.height = 2;
    alpha_glyph.atlas_x = 1;
    alpha_glyph.atlas_y = 1;
    alpha_glyph.atlas_width = 2;
    alpha_glyph.atlas_height = 2;
    alpha_glyph.color_rgba = 0xff0000ff;
    alpha_glyph.kind = DTR_METAL_INSTANCE_ALPHA_GLYPH;
    alpha_glyph.page_generation = 1;
    DtrMetalInstanceV1 color_glyph = {};
    color_glyph.x = 4;
    color_glyph.width = 2;
    color_glyph.height = 2;
    color_glyph.atlas_x = 1;
    color_glyph.atlas_y = 1;
    color_glyph.atlas_width = 2;
    color_glyph.atlas_height = 2;
    color_glyph.color_rgba = 0xffffffff;
    color_glyph.kind = DTR_METAL_INSTANCE_COLOR_GLYPH;
    color_glyph.page_generation = 1;
    DtrMetalInstanceV1 decoration = {};
    decoration.y = 4;
    decoration.width = 4;
    decoration.height = 1;
    decoration.color_rgba = 0x00ffffff;
    decoration.kind = DTR_METAL_INSTANCE_DECORATION;
    DtrMetalInstanceV1 cursor = {};
    cursor.x = 6;
    cursor.y = 4;
    cursor.width = 2;
    cursor.height = 4;
    cursor.color_rgba = 0xffffffff;
    cursor.kind = DTR_METAL_INSTANCE_CURSOR;
    const std::vector<DtrMetalInstanceV1> instances = {
        cell, selection, alpha_glyph, color_glyph, decoration, cursor};
    auto make_frame = [&](const std::vector<DtrMetalInstanceV1>& items,
                          uint64_t renderer_generation,
                          uint64_t atlas_generation) {
      DtrMetalFrameHeaderV1 header = {};
      header.magic = DTR_METAL_FRAME_MAGIC;
      header.version = DTR_METAL_FRAME_VERSION;
      header.header_size = sizeof(header);
      header.total_size = sizeof(header) +
                          items.size() * sizeof(DtrMetalInstanceV1);
      header.renderer_generation = renderer_generation;
      header.frame_generation = 1;
      header.atlas_generation = atlas_generation;
      header.viewport_width = 8;
      header.viewport_height = 8;
      header.scale_16_16 = 1u << 16;
      header.background_rgba = 0x101010ff;
      header.instance_count = static_cast<uint32_t>(items.size());
      header.instance_stride = sizeof(DtrMetalInstanceV1);
      header.instances_offset = sizeof(header);
      std::vector<uint8_t> frame(header.total_size);
      memcpy(frame.data(), &header, sizeof(header));
      if (!items.empty()) {
        memcpy(frame.data() + sizeof(header), items.data(),
               items.size() * sizeof(DtrMetalInstanceV1));
      }
      return frame;
    };
    const std::vector<uint8_t> metal_frame =
        make_frame(instances, metal_summary.generation, 1);
    DtrMetalSubmissionV1 unbound_submission = {};
    unbound_submission.struct_size = sizeof(unbound_submission);
    unbound_submission.version = DTR_METAL_SUBMISSION_VERSION;
    Expect(metal_submit != nullptr &&
               metal_submit(metal_summary.handle, metal_frame.data(),
                            static_cast<uint32_t>(metal_frame.size()),
                            &unbound_submission) == DTR_STATUS_NOT_FOUND &&
               unbound_submission.submission_token == 0,
           "packed submission requires an explicitly bound terminal view");
    DtrMetalRendererStateV1 unbound_state = {};
    unbound_state.struct_size = sizeof(unbound_state);
    unbound_state.version = DTR_METAL_RENDERER_STATE_VERSION;
    Expect(metal_state != nullptr &&
               metal_state(metal_summary.handle, &unbound_state) ==
                   DTR_STATUS_OK &&
               unbound_state.renderer_generation == metal_summary.generation &&
               unbound_state.ready_slot_count == 0 &&
               unbound_state.in_flight_slot_count == 0 &&
               unbound_state.failure_kind == DTR_METAL_FAILURE_NONE &&
               unbound_state.failure_generation == 0 &&
               unbound_state.drawable_unavailable_count == 0 &&
               unbound_state.command_failure_count == 0 &&
               unbound_state.gpu_timing_sample_count == 0 &&
               unbound_state.gpu_total_time_ns == 0 &&
               unbound_state.gpu_max_time_ns == 0 &&
               unbound_state.accepted_atlas_upload_count == 2 &&
               unbound_state.accepted_atlas_upload_bytes == 20 &&
               unbound_state.flags ==
                   DTR_METAL_RENDERER_STATE_ADMITTING,
           "unbound renderer state is bounded and observable");
    uint32_t metal_required = 0;
    Expect(metal_render != nullptr &&
               metal_render(metal_summary.handle, metal_frame.data(),
                            static_cast<uint32_t>(metal_frame.size()), nullptr,
                            0, &metal_required) ==
                   DTR_STATUS_BUFFER_TOO_SMALL &&
               metal_required == 8u * 8u * 4u,
           "Metal readback size query is exact");
    std::vector<uint8_t> metal_undersized(metal_required - 1, 0xa5);
    Expect(metal_render(metal_summary.handle, metal_frame.data(),
                        static_cast<uint32_t>(metal_frame.size()),
                        metal_undersized.data(),
                        static_cast<uint32_t>(metal_undersized.size()),
                        &metal_required) == DTR_STATUS_BUFFER_TOO_SMALL,
           "undersized Metal readback reports retry size");
    bool metal_undersized_untouched = true;
    for (uint8_t byte : metal_undersized) {
      metal_undersized_untouched &= byte == 0xa5;
    }
    Expect(metal_undersized_untouched,
           "undersized Metal readback remains untouched");
    std::vector<uint8_t> metal_pixels(metal_required, 0xa5);
    Expect(metal_render(metal_summary.handle, metal_frame.data(),
                        static_cast<uint32_t>(metal_frame.size()),
                        metal_pixels.data(),
                        static_cast<uint32_t>(metal_pixels.size()),
                        &metal_required) == DTR_STATUS_OK,
           "packed Metal frame renders to synchronous readback");
    Expect(PixelNear(metal_pixels, 8, 7, 0, 0x202020ff) &&
               PixelNear(metal_pixels, 8, 0, 0, 0x101090ff) &&
               PixelNear(metal_pixels, 8, 2, 0, 0x901010ff) &&
               PixelNear(metal_pixels, 8, 4, 0, 0x109010ff) &&
               PixelNear(metal_pixels, 8, 0, 4, 0x00ffffff) &&
               PixelNear(metal_pixels, 8, 6, 4, 0xffffffff),
           "six visual kinds preserve top-down order and straight alpha");

    auto mutate_header = [&](std::vector<uint8_t> frame,
                             void (^mutation)(DtrMetalFrameHeaderV1*)) {
      DtrMetalFrameHeaderV1 header;
      memcpy(&header, frame.data(), sizeof(header));
      mutation(&header);
      memcpy(frame.data(), &header, sizeof(header));
      return frame;
    };
    auto mutate_instance = [&](std::vector<uint8_t> frame, uint32_t index,
                               void (^mutation)(DtrMetalInstanceV1*)) {
      DtrMetalInstanceV1 instance;
      const size_t offset = sizeof(DtrMetalFrameHeaderV1) +
                            index * sizeof(DtrMetalInstanceV1);
      memcpy(&instance, frame.data() + offset, sizeof(instance));
      mutation(&instance);
      memcpy(frame.data() + offset, &instance, sizeof(instance));
      return frame;
    };
    std::vector<uint8_t> malformed_frame = mutate_header(
        metal_frame, ^(DtrMetalFrameHeaderV1* header) {
          header->reserved[0] = 1;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_INVALID_ARGUMENT,
           "reserved frame fields are rejected");
    malformed_frame = mutate_instance(
        metal_frame, 0, ^(DtrMetalInstanceV1* instance) {
          instance->kind = DTR_METAL_INSTANCE_CURSOR;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_INVALID_ARGUMENT,
           "out-of-order visual layers are rejected");
    malformed_frame = mutate_instance(
        metal_frame, 2, ^(DtrMetalInstanceV1* instance) {
          instance->page_index = 2;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_INVALID_ARGUMENT,
           "out-of-range atlas page is rejected");
    malformed_frame = mutate_header(
        metal_frame, ^(DtrMetalFrameHeaderV1* header) {
          header->atlas_generation = 0;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_STALE_GENERATION,
           "stale frame atlas generation is rejected");
    malformed_frame = mutate_instance(
        metal_frame, 2, ^(DtrMetalInstanceV1* instance) {
          instance->page_generation = 2;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_STALE_GENERATION,
           "stale frame page generation is rejected");
    malformed_frame = mutate_header(
        metal_frame, ^(DtrMetalFrameHeaderV1* header) {
          header->renderer_generation = 0;
        });
    Expect(metal_render(metal_summary.handle, malformed_frame.data(),
                        static_cast<uint32_t>(malformed_frame.size()), nullptr,
                        0, &metal_required) == DTR_STATUS_STALE_GENERATION,
           "stale renderer generation is rejected");
    Expect(metal_render(metal_summary.handle, metal_frame.data(),
                        static_cast<uint32_t>(metal_frame.size() - 1), nullptr,
                        0, &metal_required) == DTR_STATUS_INVALID_ARGUMENT,
           "truncated packed frame is rejected");

    DtrMetalAtlasUploadV1 alpha_generation_two = atlas_upload(
        DTR_METAL_ATLAS_ALPHA8, 2, 2, 1, 1, 2, 2);
    Expect(metal_upload(metal_summary.handle, &alpha_generation_two,
                        alpha_pixels.data()) == DTR_STATUS_OK,
           "new atlas generation advances the complete snapshot identity");
    std::vector<uint8_t> generation_two_frame = mutate_header(
        metal_frame, ^(DtrMetalFrameHeaderV1* header) {
          header->atlas_generation = 2;
          header->frame_generation = 2;
        });
    generation_two_frame = mutate_instance(
        generation_two_frame, 2, ^(DtrMetalInstanceV1* instance) {
          instance->page_generation = 2;
        });
    uint32_t generation_two_required = 0;
    Expect(metal_render(metal_summary.handle, generation_two_frame.data(),
                        static_cast<uint32_t>(generation_two_frame.size()),
                        nullptr, 0, &generation_two_required) ==
               DTR_STATUS_BUFFER_TOO_SMALL,
           "advanced atlas snapshot remains renderable");
    std::vector<uint8_t> generation_two_pixels(generation_two_required);
    Expect(metal_render(metal_summary.handle, generation_two_frame.data(),
                        static_cast<uint32_t>(generation_two_frame.size()),
                        generation_two_pixels.data(), generation_two_required,
                        &generation_two_required) == DTR_STATUS_OK &&
               PixelNear(generation_two_pixels, 8, 4, 0, 0x109010ff),
           "atlas advance preserves unchanged color texture slices");
    Expect(metal_upload(metal_summary.handle, &alpha_upload,
                        alpha_pixels.data()) == DTR_STATUS_STALE_GENERATION,
           "older atlas upload is rejected");
    Expect(metal_render(metal_summary.handle, metal_frame.data(),
                        static_cast<uint32_t>(metal_frame.size()), nullptr, 0,
                        &metal_required) == DTR_STATUS_STALE_GENERATION,
           "old packed frame cannot observe a replaced atlas generation");
    DtrMetalAtlasResetV1 empty_generation_three = initial_atlas_reset;
    empty_generation_three.atlas_generation = 3;
    Expect(metal_reset(metal_summary.handle, &empty_generation_three) ==
               DTR_STATUS_OK,
           "empty full rebuild advances without a pixel upload");
    Expect(metal_render(metal_summary.handle, generation_two_frame.data(),
                        static_cast<uint32_t>(generation_two_frame.size()),
                        nullptr, 0, &generation_two_required) ==
               DTR_STATUS_STALE_GENERATION,
           "full atlas reset invalidates every prior page definition");

    const uint64_t released_metal_handle = metal_summary.handle;
    Expect(metal_release != nullptr &&
               metal_release(released_metal_handle) == DTR_STATUS_OK,
           "Metal renderer releases exactly once");
    Expect(metal_finalizer != nullptr,
           "Metal renderer exposes a NativeFinalizer fallback");
    Expect(metal_release(released_metal_handle) == DTR_STATUS_INVALID_HANDLE &&
               live_metal_count() == 0,
           "released Metal renderer cannot be reused or leaked");
    Expect(metal_render(released_metal_handle, metal_frame.data(),
                        static_cast<uint32_t>(metal_frame.size()), nullptr, 0,
                        &metal_required) == DTR_STATUS_INVALID_HANDLE,
           "released Metal renderer rejects packed frames");

    da_native_extension_services_v1 incompatible = {};
    incompatible.struct_size = sizeof(incompatible);
    incompatible.abi_version = 99;
    Expect(initialize != nullptr &&
               initialize(&incompatible) == DA_STATUS_UNSUPPORTED_VERSION,
           "incompatible host ABI is rejected");

    const da_native_extension_services_v1* services =
        da_native_extension_services(DA_NATIVE_EXTENSION_ABI_VERSION);
    Expect(services != nullptr, "host service table");
    std::atomic<int32_t> worker_status{DA_STATUS_OK};
    std::thread worker([&] { worker_status.store(initialize(services)); });
    worker.join();
    Expect(worker_status.load() == DA_STATUS_WRONG_THREAD,
           "off-main initialization is rejected");
    Expect(initialize(services) == DA_STATUS_OK, "renderer initializes");
    Expect(initialize(services) == DA_STATUS_OK,
           "duplicate initialization is idempotent");

    @autoreleasepool {
      constexpr char kProvider[] = "dart_terminal.TerminalMetalView";
      DaHandle view_handle = 0;
      Expect(da_view_create_custom(kProvider, sizeof(kProvider) - 1,
                                   &view_handle) == DA_STATUS_OK,
             "terminal view is created");
      Expect(view_handle != 0 && live_count() == 1,
             "renderer owns one live view");

      int32_t lookup_status = DA_STATUS_OK;
      __unsafe_unretained id object =
          dart_appkit::ObjectRegistry::Shared().Lookup(
              view_handle, dart_appkit::ObjectKind::kView,
              dart_appkit::ThreadDomain::kAppKitMain, &lookup_status);
      Expect(lookup_status == DA_STATUS_OK, "view handle resolves");
      Expect([object isKindOfClass:NSClassFromString(@"DtrTerminalMetalView")],
             "provider creates the renderer class");
      __unsafe_unretained MTKView* view = static_cast<MTKView*>(object);
      Expect(view.device != nil, "view owns a Metal device");
      Expect(view.isPaused, "view is paused until explicit redraw");
      Expect(view.enableSetNeedsDisplay, "view redraw is demand driven");
      Expect(view.autoResizeDrawable, "drawable follows view size");
      Expect(view.framebufferOnly, "drawable is framebuffer only");
      Expect(view.delegate == nil, "view starts without a render delegate");
      Expect(view.isFlipped, "view uses top-left coordinates");

      DtrMetalRendererConfigV1 presentation_config = metal_config;
      presentation_config.maximum_viewport_width = 4096;
      presentation_config.maximum_viewport_height = 4096;
      DtrMetalRendererSummaryV1 presentation_summary = {};
      presentation_summary.struct_size = sizeof(presentation_summary);
      presentation_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
      Expect(metal_create(&presentation_config, &presentation_summary) ==
                     DTR_STATUS_OK &&
                 live_metal_count() == 1,
             "view presentation renderer owns three bounded slots");
      DtrMetalAtlasUploadV1 presentation_alpha = alpha_upload;
      presentation_alpha.renderer_generation = presentation_summary.generation;
      DtrMetalAtlasUploadV1 presentation_color = color_upload;
      presentation_color.renderer_generation = presentation_summary.generation;
      Expect(metal_upload(presentation_summary.handle, &presentation_alpha,
                          alpha_pixels.data()) == DTR_STATUS_OK &&
                 metal_upload(presentation_summary.handle, &presentation_color,
                              color_pixels.data()) == DTR_STATUS_OK,
             "presentation renderer receives both atlas formats");
      DtrMetalViewBindingV1 binding = {};
      binding.struct_size = sizeof(binding);
      binding.version = DTR_METAL_VIEW_BINDING_VERSION;
      binding.operation = DTR_METAL_VIEW_OPERATION_BIND;
      binding.renderer_handle = presentation_summary.handle;
      binding.renderer_generation = presentation_summary.generation + 1;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_INVALID_HANDLE,
             "view binding rejects a stale renderer generation");
      binding.renderer_generation = presentation_summary.generation;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_OK,
             "opaque provider operation binds renderer to terminal view");
      Expect(view.delegate != nil && view.isPaused &&
                 view.enableSetNeedsDisplay && view.framebufferOnly,
             "bound view owns native on-demand presentation delegate");
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_INVALID_ARGUMENT,
             "terminal view and renderer bind at most once");

      constexpr char kTitle[] = "Terminal renderer capability";
      DaHandle window_handle = 0;
      Expect(
          da_window_create({100.0, 100.0, 640.0, 480.0}, kTitle,
                           sizeof(kTitle) - 1, &window_handle) == DA_STATUS_OK,
          "test window is created");
      Expect(da_window_set_content_view(window_handle, view_handle) ==
                 DA_STATUS_OK,
             "renderer attaches through the public view handle");
      __unsafe_unretained DaWindowOwner* owner = static_cast<DaWindowOwner*>(
          dart_appkit::ObjectRegistry::Shared().Lookup(
              window_handle, dart_appkit::ObjectKind::kWindow,
              dart_appkit::ThreadDomain::kAppKitMain, &lookup_status));
      Expect(lookup_status == DA_STATUS_OK && owner.window.contentView == view,
             "window owns the attached renderer view");
      Expect(owner.window.firstResponder == view,
             "attached renderer becomes first responder");

      [owner.window orderFront:nil];
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
      const uint32_t drawable_width =
          static_cast<uint32_t>(std::llround(view.drawableSize.width));
      const uint32_t drawable_height =
          static_cast<uint32_t>(std::llround(view.drawableSize.height));
      Expect(drawable_width > 0 && drawable_width <= 4096 &&
                 drawable_height > 0 && drawable_height <= 4096,
             "attached terminal view has a bounded drawable");

      const uint8_t accessibility_text[] = {'A', 0xf0, 0x9f, 0x98,
                                            0x80, '\n', 'B'};
      DtrAccessibilityLineV1 accessibility_lines[2] = {};
      accessibility_lines[0].row = 0;
      accessibility_lines[0].utf16_start = 0;
      accessibility_lines[0].utf16_length = 3;
      accessibility_lines[0].first_column_boundary = 0;
      accessibility_lines[0].column_boundary_count = 4;
      accessibility_lines[1].row = 1;
      accessibility_lines[1].utf16_start = 4;
      accessibility_lines[1].utf16_length = 1;
      accessibility_lines[1].first_column_boundary = 4;
      accessibility_lines[1].column_boundary_count = 2;
      const uint32_t accessibility_boundaries[] = {0, 1, 1, 3, 0, 1};
      DtrAccessibilitySnapshotHeaderV2 accessibility = {};
      accessibility.struct_size = sizeof(accessibility);
      accessibility.version = DTR_ACCESSIBILITY_SNAPSHOT_VERSION;
      accessibility.operation =
          DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_SNAPSHOT;
      accessibility.flags = DTR_ACCESSIBILITY_HAS_SELECTION |
                            DTR_ACCESSIBILITY_HAS_CURSOR;
      accessibility.generation = 1;
      accessibility.rows = 2;
      accessibility.columns = 4;
      accessibility.utf8_length = sizeof(accessibility_text);
      accessibility.utf16_length = 5;
      accessibility.line_count = 2;
      accessibility.column_boundary_count = 6;
      accessibility.selection_location = 1;
      accessibility.selection_length = 2;
      accessibility.cursor_location = 5;
      accessibility.cursor_row = 1;
      accessibility.cursor_column = 1;
      accessibility.cell_width = 10;
      accessibility.cell_height = 20;
      accessibility.content_origin_x = 12;
      accessibility.content_origin_y = 8;
      accessibility.lines_offset = sizeof(accessibility);
      accessibility.column_boundaries_offset =
          sizeof(accessibility) + sizeof(accessibility_lines);
      accessibility.text_offset =
          accessibility.column_boundaries_offset +
          sizeof(accessibility_boundaries);
      accessibility.total_size =
          accessibility.text_offset + sizeof(accessibility_text);
      std::vector<uint8_t> accessibility_packet(accessibility.total_size);
      auto write_accessibility_packet = [&] {
        memcpy(accessibility_packet.data(), &accessibility,
               sizeof(accessibility));
        memcpy(accessibility_packet.data() + accessibility.lines_offset,
               accessibility_lines, sizeof(accessibility_lines));
        memcpy(accessibility_packet.data() +
                   accessibility.column_boundaries_offset,
               accessibility_boundaries, sizeof(accessibility_boundaries));
        memcpy(accessibility_packet.data() + accessibility.text_offset,
               accessibility_text, sizeof(accessibility_text));
      };
      write_accessibility_packet();
      Expect(da_view_perform_custom_operation(
                 view_handle, accessibility_packet.data(),
                 accessibility_packet.size()) == DA_STATUS_OK,
             "complete accessibility snapshot is copied atomically");
      Expect([(id)view isAccessibilityElement] &&
                 [[(id)view accessibilityRole]
                     isEqualToString:NSAccessibilityTextAreaRole] &&
                 [[(id)view accessibilityLabel]
                     isEqualToString:@"Terminal"] &&
                 [[(id)view accessibilityValue]
                     isEqualToString:@"A😀\nB"] &&
                 [(id)view accessibilityNumberOfCharacters] == 5 &&
                 NSEqualRanges(
                     [(id)view accessibilityVisibleCharacterRange],
                     NSMakeRange(0, 5)) &&
                 NSEqualRanges([(id)view accessibilitySharedCharacterRange],
                               NSMakeRange(0, 5)),
             "terminal view exposes one labelled read-only text area");
      Expect(NSEqualRanges([(id)view accessibilitySelectedTextRange],
                           NSMakeRange(1, 2)) &&
                 [[(id)view accessibilitySelectedText]
                     isEqualToString:@"😀"] &&
                 [[(id)view accessibilitySelectedTextRanges] count] == 1 &&
                 [(id)view accessibilityInsertionPointLineNumber] == 1 &&
                 [(id)view isAccessibilityFocused],
             "selection, cursor line, and first-responder focus are visible");
      Expect([[(id)view accessibilityStringForRange:NSMakeRange(0, 3)]
                 isEqualToString:@"A😀"] &&
                 [[[(id)view
                     accessibilityAttributedStringForRange:NSMakeRange(4, 1)]
                       string] isEqualToString:@"B"] &&
                 NSEqualRanges([(id)view accessibilityRangeForLine:0],
                               NSMakeRange(0, 4)) &&
                 [(id)view accessibilityLineForIndex:4] == 1 &&
                 NSEqualRanges([(id)view accessibilityRangeForIndex:1],
                               NSMakeRange(1, 2)) &&
                 NSEqualRanges([(id)view accessibilityStyleRangeForIndex:4],
                               NSMakeRange(4, 1)),
             "native text navigation retains UTF-16 physical line ranges");
      NSRect selection_screen =
          [(id)view accessibilityFrameForRange:NSMakeRange(1, 2)];
      NSRect selection_window =
          [owner.window convertRectFromScreen:selection_screen];
      NSRect selection_local = [view convertRect:selection_window fromView:nil];
      NSPoint link_window =
          [view convertPoint:NSMakePoint(27, 18) toView:nil];
      NSPoint link_screen = [owner.window convertPointToScreen:link_window];
      NSPoint left_padding_window =
          [view convertPoint:NSMakePoint(11, 18) toView:nil];
      NSPoint left_padding_screen =
          [owner.window convertPointToScreen:left_padding_window];
      NSPoint top_padding_window =
          [view convertPoint:NSMakePoint(27, 7) toView:nil];
      NSPoint top_padding_screen =
          [owner.window convertPointToScreen:top_padding_window];
      NSPoint after_grid_window =
          [view convertPoint:NSMakePoint(52, 18) toView:nil];
      NSPoint after_grid_screen =
          [owner.window convertPointToScreen:after_grid_window];
      NSRect multiline_screen =
          [(id)view accessibilityFrameForRange:NSMakeRange(1, 4)];
      NSRect multiline_window =
          [owner.window convertRectFromScreen:multiline_screen];
      NSRect multiline_local =
          [view convertRect:multiline_window fromView:nil];
      Expect(std::abs(selection_local.origin.x - 22) < 0.01 &&
                 std::abs(selection_local.origin.y - 8) < 0.01 &&
                 std::abs(selection_local.size.width - 20) < 0.01 &&
                 std::abs(selection_local.size.height - 20) < 0.01 &&
                 std::abs(multiline_local.origin.x - 12) < 0.01 &&
                 std::abs(multiline_local.origin.y - 8) < 0.01 &&
                 std::abs(multiline_local.size.width - 40) < 0.01 &&
                 std::abs(multiline_local.size.height - 40) < 0.01 &&
                 NSEqualRanges(
                     [(id)view accessibilityRangeForPosition:link_screen],
                     NSMakeRange(1, 2)) &&
                 [(id)view accessibilityRangeForPosition:left_padding_screen]
                         .location == NSNotFound &&
                 [(id)view accessibilityRangeForPosition:top_padding_screen]
                         .location == NSNotFound &&
                 [(id)view accessibilityRangeForPosition:after_grid_screen]
                         .location == NSNotFound,
             "range and point geometry use one padded wide-cell origin");
      const uint64_t initial_value_notifications =
          [[(id)view
              valueForKey:@"terminalAccessibilityValueNotificationCount"]
              unsignedLongLongValue];
      const uint64_t initial_selection_notifications =
          [[(id)view
              valueForKey:@"terminalAccessibilitySelectionNotificationCount"]
              unsignedLongLongValue];
      accessibility.generation = 2;
      write_accessibility_packet();
      Expect(da_view_perform_custom_operation(
                 view_handle, accessibility_packet.data(),
                 accessibility_packet.size()) == DA_STATUS_OK &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilityValueNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_value_notifications &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilitySelectionNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_selection_notifications,
             "new identical generation emits no redundant notification");
      accessibility.generation = 3;
      accessibility.content_origin_x = 16;
      accessibility.content_origin_y = 9;
      write_accessibility_packet();
      Expect(da_view_perform_custom_operation(
                 view_handle, accessibility_packet.data(),
                 accessibility_packet.size()) == DA_STATUS_OK &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilityValueNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_value_notifications + 1 &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilitySelectionNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_selection_notifications,
             "content-origin change emits only one value notification");
      NSRect shifted_selection_screen =
          [(id)view accessibilityFrameForRange:NSMakeRange(1, 2)];
      NSRect shifted_selection_window =
          [owner.window convertRectFromScreen:shifted_selection_screen];
      NSRect shifted_selection_local =
          [view convertRect:shifted_selection_window fromView:nil];
      Expect(std::abs(shifted_selection_local.origin.x - 26) < 0.01 &&
                 std::abs(shifted_selection_local.origin.y - 9) < 0.01,
             "updated content origin moves range geometry exactly once");
      accessibility.generation = 4;
      accessibility.flags = DTR_ACCESSIBILITY_HAS_CURSOR;
      accessibility.selection_location = 5;
      accessibility.selection_length = 0;
      write_accessibility_packet();
      Expect(da_view_perform_custom_operation(
                 view_handle, accessibility_packet.data(),
                 accessibility_packet.size()) == DA_STATUS_OK &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilityValueNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_value_notifications + 1 &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilitySelectionNotificationCount"]
                         unsignedLongLongValue] ==
                     initial_selection_notifications + 1 &&
                 NSEqualRanges([(id)view accessibilitySelectedTextRange],
                               NSMakeRange(5, 0)),
             "cursor-only update emits exactly one selection notification");
      Expect(da_view_perform_custom_operation(
                 view_handle, accessibility_packet.data(),
                 accessibility_packet.size()) == DA_STATUS_INVALID_ARGUMENT,
             "duplicate accessibility generation is rejected");
      auto expect_invalid_accessibility_header =
          [&](DtrAccessibilitySnapshotHeaderV2 invalid,
              const char* description) {
            invalid.generation = 5;
            std::vector<uint8_t> packet = accessibility_packet;
            memcpy(packet.data(), &invalid, sizeof(invalid));
            Expect(da_view_perform_custom_operation(
                       view_handle, packet.data(), packet.size()) ==
                           DA_STATUS_INVALID_ARGUMENT &&
                       [[(id)view accessibilityValue]
                           isEqualToString:@"A😀\nB"] &&
                       NSEqualRanges([(id)view accessibilitySelectedTextRange],
                                     NSMakeRange(5, 0)),
                   description);
          };
      DtrAccessibilitySnapshotHeaderV2 negative_origin = accessibility;
      negative_origin.content_origin_x = -1;
      expect_invalid_accessibility_header(
          negative_origin,
          "negative accessibility content origin preserves native state");
      DtrAccessibilitySnapshotHeaderV2 nonfinite_origin = accessibility;
      nonfinite_origin.content_origin_y = std::nan("");
      expect_invalid_accessibility_header(
          nonfinite_origin,
          "nonfinite accessibility content origin preserves native state");
      DtrAccessibilitySnapshotHeaderV2 oversized_origin = accessibility;
      oversized_origin.content_origin_x = DTR_MAX_METAL_DIMENSION + 1;
      expect_invalid_accessibility_header(
          oversized_origin,
          "oversized accessibility content origin preserves native state");
      DtrAccessibilitySnapshotHeaderV2 unsupported_snapshot = accessibility;
      unsupported_snapshot.version = DTR_ACCESSIBILITY_SNAPSHOT_VERSION + 1;
      expect_invalid_accessibility_header(
          unsupported_snapshot,
          "unsupported accessibility snapshot version preserves native state");
      std::vector<uint8_t> malformed_accessibility = accessibility_packet;
      uint32_t malformed_boundary = 1;
      memcpy(malformed_accessibility.data() +
                 accessibility.column_boundaries_offset,
             &malformed_boundary, sizeof(malformed_boundary));
      accessibility.generation = 5;
      memcpy(malformed_accessibility.data(), &accessibility,
             sizeof(accessibility));
      Expect(da_view_perform_custom_operation(
                 view_handle, malformed_accessibility.data(),
                 malformed_accessibility.size()) ==
                 DA_STATUS_INVALID_ARGUMENT &&
                 [[(id)view accessibilityValue]
                     isEqualToString:@"A😀\nB"] &&
                 NSEqualRanges([(id)view accessibilitySelectedTextRange],
                               NSMakeRange(5, 0)),
             "malformed column topology cannot partially replace native state");
      DtrAccessibilityAcceptanceV1 accessibility_acceptance = {};
      accessibility_acceptance.struct_size =
          sizeof(accessibility_acceptance);
      accessibility_acceptance.version =
          DTR_ACCESSIBILITY_SNAPSHOT_VERSION;
      accessibility_acceptance.operation =
          DTR_METAL_VIEW_OPERATION_ACCESSIBILITY_ACCEPTANCE;
      accessibility_acceptance.generation = 4;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&accessibility_acceptance),
                 sizeof(accessibility_acceptance)) == DA_STATUS_OK,
             "content-free acceptance verifies native selectors and geometry");
      const uint64_t focus_notifications =
          [[(id)view
              valueForKey:@"terminalAccessibilityFocusNotificationCount"]
              unsignedLongLongValue];
      [owner.window makeFirstResponder:nil];
      [owner.window makeFirstResponder:view];
      Expect([(id)view isAccessibilityFocused] &&
                 [[(id)view
                     valueForKey:
                         @"terminalAccessibilityFocusNotificationCount"]
                         unsignedLongLongValue] >=
                     focus_notifications + 2,
             "first-responder transitions post focused-element notifications");

      Expect(text_input_set_notify != nullptr &&
                 text_input_set_notify(NotifyTextInput) == DTR_STATUS_OK &&
                 text_input_set_notify(NotifyTextInput) == DTR_STATUS_OK,
             "text-input scalar notification is installed idempotently");
      DtrTextInputClientV1 text_client = {};
      text_client.struct_size = sizeof(text_client);
      text_client.version = DTR_TEXT_INPUT_CLIENT_VERSION;
      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH;
      text_client.client_id = 77;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK &&
                 live_text_input_count() == 1,
             "terminal view owns one bounded text-input client");
      Expect([(id)view conformsToProtocol:@protocol(NSTextInputClient)] &&
                 [view acceptsFirstResponder],
             "terminal Metal view is an NSTextInputClient first responder");

      DtrTextInputGeometryV1 text_geometry = {};
      text_geometry.struct_size = sizeof(text_geometry);
      text_geometry.version = DTR_TEXT_INPUT_GEOMETRY_VERSION;
      text_geometry.operation =
          DTR_METAL_VIEW_OPERATION_TEXT_INPUT_GEOMETRY;
      text_geometry.client_id = text_client.client_id;
      text_geometry.generation = 2;
      text_geometry.x = 137;
      text_geometry.y = 121;
      text_geometry.width = 2;
      text_geometry.height = 24;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_geometry),
                 sizeof(text_geometry)) == DA_STATUS_OK,
             "finite caret geometry is cached on the native view");
      DtrTextInputGeometryV1 stale_geometry = text_geometry;
      stale_geometry.generation = 1;
      stale_geometry.x = 1;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&stale_geometry),
                 sizeof(stale_geometry)) == DA_STATUS_OK,
             "stale caret geometry is ignored without replacing the cache");

      auto take_text_input_event = [&](uint64_t client_id) {
        uint32_t required = 0;
        Expect(text_input_take(client_id, nullptr, 0, &required) ==
                       DTR_STATUS_BUFFER_TOO_SMALL &&
                   required >= sizeof(DtrTextInputEventHeaderV1) &&
                   required <= sizeof(DtrTextInputEventHeaderV1) +
                                   2 * DTR_MAX_TEXT_INPUT_BYTES,
               "text-input size query is bounded and non-consuming");
        std::vector<uint8_t> packet(required);
        Expect(text_input_take(client_id, packet.data(), required, &required) ==
                       DTR_STATUS_OK &&
                   required == packet.size(),
               "text-input packet is copied and consumed exactly once");
        return packet;
      };
      auto text_input_header = [&](const std::vector<uint8_t>& packet) {
        DtrTextInputEventHeaderV1 header = {};
        if (packet.size() >= sizeof(header)) {
          memcpy(&header, packet.data(), sizeof(header));
        }
        Expect(header.magic == DTR_TEXT_INPUT_EVENT_MAGIC &&
                   header.version == DTR_TEXT_INPUT_EVENT_VERSION &&
                   header.header_size == sizeof(header) &&
                   header.total_size == packet.size() &&
                   header.client_id == text_client.client_id,
               "text-input packet header has a stable identity");
        return header;
      };
      auto packet_string = [&](const std::vector<uint8_t>& packet,
                               uint32_t offset, uint32_t length) {
        if (offset > packet.size() || length > packet.size() - offset) {
          Expect(false, "text-input packet string region is in bounds");
          return std::string();
        }
        return std::string(reinterpret_cast<const char*>(packet.data() + offset),
                           length);
      };

      id<NSTextInputClient> input_view = (id<NSTextInputClient>)view;
      [input_view setMarkedText:@"にほん"
                 selectedRange:NSMakeRange(3, 0)
               replacementRange:NSMakeRange(NSNotFound, 0)];
      [input_view setMarkedText:@"にほんご"
                 selectedRange:NSMakeRange(4, 0)
               replacementRange:NSMakeRange(8, 3)];
      Expect(notified_text_input_client.load() == text_client.client_id &&
                 [input_view hasMarkedText] &&
                 NSEqualRanges([input_view markedRange], NSMakeRange(0, 4)) &&
                 NSEqualRanges([input_view selectedRange], NSMakeRange(4, 0)),
             "marked updates retain exact native UTF-16 state");
      std::vector<uint8_t> preedit_packet =
          take_text_input_event(text_client.client_id);
      DtrTextInputEventHeaderV1 preedit_header =
          text_input_header(preedit_packet);
      Expect(preedit_header.kind == DTR_TEXT_INPUT_EVENT_PREEDIT &&
                 preedit_header.event_generation == 2 &&
                 preedit_header.selection_location == 4 &&
                 preedit_header.selection_length == 0 &&
                 preedit_header.replacement_location == 8 &&
                 preedit_header.replacement_length == 3 &&
                 packet_string(preedit_packet, preedit_header.text_offset,
                               preedit_header.text_length) == "にほんご",
             "adjacent preedit updates coalesce to the newest exact event");
      uint32_t no_event_required = 99;
      Expect(text_input_take(text_client.client_id, nullptr, 0,
                             &no_event_required) == DTR_STATUS_NOT_FOUND &&
                 no_event_required == 0,
             "coalesced preedit leaves no stale event");

      NSRange substring_actual = NSMakeRange(NSNotFound, 0);
      NSAttributedString* substring =
          [input_view attributedSubstringForProposedRange:NSMakeRange(1, 2)
                                               actualRange:&substring_actual];
      Expect([substring.string isEqualToString:@"ほん"] &&
                 NSEqualRanges(substring_actual, NSMakeRange(1, 2)),
             "marked attributed substring reports its exact actual range");
      NSRange candidate_actual = NSMakeRange(NSNotFound, 0);
      NSRect candidate_screen =
          [input_view firstRectForCharacterRange:NSMakeRange(0, 4)
                                      actualRange:&candidate_actual];
      NSRect candidate_window =
          [owner.window convertRectFromScreen:candidate_screen];
      NSRect candidate_local = [view convertRect:candidate_window fromView:nil];
      Expect(NSEqualRanges(candidate_actual, NSMakeRange(0, 4)) &&
                 std::isfinite(candidate_screen.origin.x) &&
                 std::isfinite(candidate_screen.origin.y) &&
                 candidate_screen.size.width > 0 &&
                 candidate_screen.size.height > 0 &&
                 std::abs(candidate_local.origin.x - 137) < 0.01 &&
                 std::abs(candidate_local.origin.y - 121) < 0.01 &&
                 std::abs(candidate_local.size.width - 2) < 0.01 &&
                 std::abs(candidate_local.size.height - 24) < 0.01,
             "candidate rect uses cached geometry with exact screen round-trip");

      [input_view insertText:@"日本語"
            replacementRange:NSMakeRange(8, 3)];
      std::vector<uint8_t> commit_packet =
          take_text_input_event(text_client.client_id);
      DtrTextInputEventHeaderV1 commit_header =
          text_input_header(commit_packet);
      Expect(commit_header.kind == DTR_TEXT_INPUT_EVENT_COMMIT &&
                 commit_header.event_generation == 3 &&
                 ![input_view hasMarkedText] &&
                 packet_string(commit_packet, commit_header.text_offset,
                               commit_header.text_length) == "日本語",
             "commit clears marked state and emits UTF-8 once");

      [input_view setMarkedText:@"かな"
                 selectedRange:NSMakeRange(2, 0)
               replacementRange:NSMakeRange(NSNotFound, 0)];
      NSEvent* raw_key =
          [NSEvent keyEventWithType:NSEventTypeKeyUp
                           location:NSZeroPoint
                      modifierFlags:NSEventModifierFlagControl |
                                    NSEventModifierFlagFunction
                          timestamp:4.0
                       windowNumber:owner.window.windowNumber
                            context:nil
                         characters:@"\x03"
          charactersIgnoringModifiers:@"c"
                          isARepeat:YES
                            keyCode:8];
      [view keyUp:raw_key];
      [input_view unmarkText];
      std::vector<uint8_t> cancelled_preedit =
          take_text_input_event(text_client.client_id);
      std::vector<uint8_t> cancel_packet =
          take_text_input_event(text_client.client_id);
      Expect(text_input_header(cancelled_preedit).kind ==
                     DTR_TEXT_INPUT_EVENT_PREEDIT &&
                 text_input_header(cancel_packet).kind ==
                     DTR_TEXT_INPUT_EVENT_CANCEL &&
                 text_input_take(text_client.client_id, nullptr, 0,
                                 &no_event_required) == DTR_STATUS_NOT_FOUND,
             "composition suppresses raw keys and cancel never commits text");
      [view keyUp:raw_key];
      std::vector<uint8_t> raw_packet =
          take_text_input_event(text_client.client_id);
      DtrTextInputEventHeaderV1 raw_header = text_input_header(raw_packet);
      Expect(raw_header.kind == DTR_TEXT_INPUT_EVENT_RAW_KEY_UP &&
                 raw_header.key_code == 8 &&
                 raw_header.flags == DTR_TEXT_INPUT_EVENT_REPEAT &&
                 (raw_header.modifiers & (1u << 2)) != 0 &&
                 (raw_header.modifiers & (1u << 6)) != 0 &&
                 packet_string(raw_packet, raw_header.text_offset,
                               raw_header.text_length) == "\x03" &&
                 packet_string(raw_packet,
                               raw_header.unmodified_text_offset,
                               raw_header.unmodified_text_length) == "c",
             "raw key transport preserves key, text, modifiers, and repeat");

      NSMutableString* oversized = [NSMutableString string];
      for (uint32_t index = 0; index <= DTR_MAX_TEXT_INPUT_BYTES; index++) {
        [oversized appendString:@"a"];
      }
      [input_view setMarkedText:oversized
                 selectedRange:NSMakeRange(oversized.length, 0)
               replacementRange:NSMakeRange(NSNotFound, 0)];
      std::vector<uint8_t> overflow_packet =
          take_text_input_event(text_client.client_id);
      Expect(text_input_header(overflow_packet).kind ==
                     DTR_TEXT_INPUT_EVENT_OVERFLOW &&
                 ![input_view hasMarkedText],
             "oversized preedit resets composition with an explicit event");

      for (uint32_t index = 0; index <= DTR_MAX_TEXT_INPUT_EVENTS; index++) {
        [view keyUp:raw_key];
      }
      std::vector<uint8_t> queue_overflow_packet =
          take_text_input_event(text_client.client_id);
      Expect(text_input_header(queue_overflow_packet).kind ==
                     DTR_TEXT_INPUT_EVENT_OVERFLOW &&
                 text_input_take(text_client.client_id, nullptr, 0,
                                 &no_event_required) == DTR_STATUS_NOT_FOUND,
             "bounded queue collapse publishes one explicit overflow event");

      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_DETACH;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK &&
                 live_text_input_count() == 0 &&
                 text_input_take(text_client.client_id, nullptr, 0,
                                 &no_event_required) == DTR_STATUS_NOT_FOUND,
             "text-input detach drops queued ownership without leaking");

      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH;
      text_client.client_id = 78;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK,
             "acceptance client reattaches to the product view");
      text_geometry.client_id = text_client.client_id;
      text_geometry.generation = 1;
      text_geometry.x = 91;
      text_geometry.y = 73;
      text_geometry.width = 9;
      text_geometry.height = 20;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_geometry),
                 sizeof(text_geometry)) == DA_STATUS_OK,
             "acceptance client receives current product caret geometry");
      DtrTextInputAcceptanceV1 acceptance = {};
      acceptance.struct_size = sizeof(acceptance);
      acceptance.version = DTR_TEXT_INPUT_CLIENT_VERSION;
      acceptance.operation =
          DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ACCEPTANCE;
      acceptance.client_id = text_client.client_id;
      acceptance.stage = 1;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&acceptance),
                 sizeof(acceptance)) == DA_STATUS_OK,
             "acceptance stage drives raw, marked, and candidate methods");
      std::vector<uint8_t> acceptance_raw =
          take_text_input_event(text_client.client_id);
      std::vector<uint8_t> acceptance_preedit =
          take_text_input_event(text_client.client_id);
      DtrTextInputEventHeaderV1 acceptance_raw_header =
          text_input_header(acceptance_raw);
      DtrTextInputEventHeaderV1 acceptance_preedit_header =
          text_input_header(acceptance_preedit);
      Expect(acceptance_raw_header.kind ==
                     DTR_TEXT_INPUT_EVENT_RAW_KEY_DOWN &&
                 acceptance_raw_header.event_generation == 1 &&
                 acceptance_raw_header.key_code == 126 &&
                 acceptance_preedit_header.kind ==
                     DTR_TEXT_INPUT_EVENT_PREEDIT &&
                 acceptance_preedit_header.event_generation == 3 &&
                 packet_string(acceptance_preedit,
                               acceptance_preedit_header.text_offset,
                               acceptance_preedit_header.text_length) ==
                     "にほんご",
             "staged acceptance retains raw and newest marked events");
      acceptance.stage = 2;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&acceptance),
                 sizeof(acceptance)) == DA_STATUS_OK,
             "acceptance stage commits and begins cancellable preedit");
      std::vector<uint8_t> acceptance_commit =
          take_text_input_event(text_client.client_id);
      std::vector<uint8_t> acceptance_cancel_preedit =
          take_text_input_event(text_client.client_id);
      DtrTextInputEventHeaderV1 acceptance_commit_header =
          text_input_header(acceptance_commit);
      DtrTextInputEventHeaderV1 acceptance_cancel_preedit_header =
          text_input_header(acceptance_cancel_preedit);
      Expect(acceptance_commit_header.kind ==
                     DTR_TEXT_INPUT_EVENT_COMMIT &&
                 acceptance_commit_header.event_generation == 4 &&
                 packet_string(acceptance_commit,
                               acceptance_commit_header.text_offset,
                               acceptance_commit_header.text_length) ==
                     "日本語" &&
                 acceptance_cancel_preedit_header.kind ==
                     DTR_TEXT_INPUT_EVENT_PREEDIT &&
                 acceptance_cancel_preedit_header.event_generation == 5 &&
                 text_input_take(text_client.client_id, nullptr, 0,
                                 &no_event_required) == DTR_STATUS_NOT_FOUND,
             "marked raw key is suppressed while commit is delivered once");
      acceptance.stage = 3;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&acceptance),
                 sizeof(acceptance)) == DA_STATUS_OK,
             "acceptance stage cancels without committing");
      std::vector<uint8_t> acceptance_cancel =
          take_text_input_event(text_client.client_id);
      Expect(text_input_header(acceptance_cancel).kind ==
                     DTR_TEXT_INPUT_EVENT_CANCEL &&
                 text_input_take(text_client.client_id, nullptr, 0,
                                 &no_event_required) == DTR_STATUS_NOT_FOUND,
             "cancel leaves no raw or commit event behind");
      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_DETACH;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK &&
                 live_text_input_count() == 0,
             "acceptance client detaches without leaking");

      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_ATTACH;
      text_client.client_id = 79;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK,
             "matrix client reattaches to the product view");
      DtrTextInputClientV1 matrix = text_client;
      matrix.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_MATRIX;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&matrix),
                 sizeof(matrix)) == DA_STATUS_OK,
             "input-source matrix drives the native text client");
      const std::vector<std::string> matrix_commits = {
          "a", "A", "¥", "_", "é", "中文", "日本語", "한글", "👩‍💻", "⌘"};
      for (size_t index = 0; index < matrix_commits.size(); index++) {
        std::vector<uint8_t> packet =
            take_text_input_event(text_client.client_id);
        DtrTextInputEventHeaderV1 header = text_input_header(packet);
        Expect(header.kind == DTR_TEXT_INPUT_EVENT_COMMIT &&
                   header.event_generation == index + 1 &&
                   header.flags == 0 && header.key_code == 0 &&
                   header.modifiers == 0 &&
                   packet_string(packet, header.text_offset,
                                 header.text_length) == matrix_commits[index],
               "matrix commit retains exact order and UTF-8");
      }
      for (uint64_t index = 0; index < 3; index++) {
        std::vector<uint8_t> packet =
            take_text_input_event(text_client.client_id);
        DtrTextInputEventHeaderV1 header = text_input_header(packet);
        Expect(header.kind == DTR_TEXT_INPUT_EVENT_RAW_KEY_DOWN &&
                   header.event_generation == 11 + index &&
                   header.key_code == 124 &&
                   header.flags ==
                       (index == 0 ? 0 : DTR_TEXT_INPUT_EVENT_REPEAT) &&
                   header.modifiers == (1u << 6) &&
                   packet_string(packet, header.text_offset,
                                 header.text_length) == "\xef\x9c\x83" &&
                   packet_string(packet, header.unmodified_text_offset,
                                 header.unmodified_text_length) ==
                       "\xef\x9c\x83",
               "matrix repeat retains initial/repeated native key identity");
      }
      Expect(text_input_take(text_client.client_id, nullptr, 0,
                             &no_event_required) == DTR_STATUS_NOT_FOUND,
             "input-source matrix leaves no queued event");
      text_client.operation = DTR_METAL_VIEW_OPERATION_TEXT_INPUT_DETACH;
      Expect(da_view_perform_custom_operation(
                 view_handle,
                 reinterpret_cast<const uint8_t*>(&text_client),
                 sizeof(text_client)) == DA_STATUS_OK &&
                 live_text_input_count() == 0,
             "matrix client detaches without leaking");

      auto presentation_frame = [&](uint64_t frame_generation) {
        std::vector<uint8_t> frame =
            make_frame(instances, presentation_summary.generation, 1);
        return mutate_header(
            frame, ^(DtrMetalFrameHeaderV1* header) {
              header->frame_generation = frame_generation;
              header->viewport_width = drawable_width;
              header->viewport_height = drawable_height;
            });
      };
      std::vector<std::vector<uint8_t>> presentation_frames;
      std::vector<DtrMetalSubmissionV1> submissions;
      for (uint64_t generation = 1; generation <= 3; generation++) {
        presentation_frames.push_back(presentation_frame(generation));
        DtrMetalSubmissionV1 submission = {};
        submission.struct_size = sizeof(submission);
        submission.version = DTR_METAL_SUBMISSION_VERSION;
        const std::vector<uint8_t>& frame = presentation_frames.back();
        Expect(metal_submit(presentation_summary.handle, frame.data(),
                            static_cast<uint32_t>(frame.size()),
                            &submission) == DTR_STATUS_OK,
               "packed frame is copied into a free native slot");
        submissions.push_back(submission);
      }
      Expect(submissions.size() == 3 &&
                 submissions[0].submission_token == 1 &&
                 submissions[1].submission_token == 2 &&
                 submissions[2].submission_token == 3 &&
                 submissions[2].frame_generation == 3 &&
                 submissions[2].renderer_generation ==
                     presentation_summary.generation,
             "accepted submissions publish monotonic nonzero tokens");
      std::vector<uint8_t> fourth_frame = presentation_frame(4);
      DtrMetalSubmissionV1 rejected_submission = {};
      rejected_submission.struct_size = sizeof(rejected_submission);
      rejected_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(presentation_summary.handle, fourth_frame.data(),
                          static_cast<uint32_t>(fourth_frame.size()),
                          &rejected_submission) ==
                     DTR_STATUS_BACKPRESSURED &&
                 rejected_submission.submission_token == 0,
             "a fourth queued frame is backpressured without publication");
      DtrMetalSubmissionV1 stale_submission = {};
      stale_submission.struct_size = sizeof(stale_submission);
      stale_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(
                 presentation_summary.handle, presentation_frames.back().data(),
                 static_cast<uint32_t>(presentation_frames.back().size()),
                 &stale_submission) == DTR_STATUS_STALE_GENERATION,
             "duplicate frame generation is rejected before slot selection");
      DtrMetalAtlasUploadV1 blocked_atlas = alpha_generation_two;
      blocked_atlas.renderer_generation = presentation_summary.generation;
      DtrMetalAtlasResetV1 blocked_reset = initial_atlas_reset;
      blocked_reset.renderer_generation = presentation_summary.generation;
      blocked_reset.atlas_generation = 2;
      Expect(metal_upload(presentation_summary.handle, &presentation_alpha,
                          alpha_pixels.data()) == DTR_STATUS_BACKPRESSURED,
             "same-generation atlas writes cannot race queued GPU reads");
      Expect(metal_upload(presentation_summary.handle, &blocked_atlas,
                          alpha_pixels.data()) == DTR_STATUS_BACKPRESSURED,
             "atlas generation replacement waits for frame retirement");
      Expect(metal_reset(presentation_summary.handle, &blocked_reset) ==
                 DTR_STATUS_BACKPRESSURED,
             "empty atlas replacement waits for frame retirement");
      DtrMetalRendererStateV1 queued_state = {};
      queued_state.struct_size = sizeof(queued_state);
      queued_state.version = DTR_METAL_RENDERER_STATE_VERSION;
      Expect(metal_state(presentation_summary.handle, &queued_state) ==
                     DTR_STATUS_OK &&
                 queued_state.last_accepted_frame_generation == 3 &&
                 queued_state.last_submission_token == 3 &&
                 queued_state.retired_through_token == 0 &&
                 queued_state.accepted_submission_count == 3 &&
                 queued_state.backpressure_count == 1 &&
                 queued_state.gpu_timing_sample_count == 0 &&
                 queued_state.accepted_atlas_upload_count == 2 &&
                 queued_state.accepted_atlas_upload_bytes == 20 &&
                 queued_state.ready_slot_count == 3 &&
                 queued_state.in_flight_slot_count == 0 &&
                 queued_state.failure_kind == DTR_METAL_FAILURE_NONE &&
                 queued_state.drawable_unavailable_count == 0 &&
                 queued_state.flags ==
                     (DTR_METAL_RENDERER_STATE_BOUND |
                      DTR_METAL_RENDERER_STATE_ADMITTING),
             "three-slot state remains bounded before native draw");

      Expect(metal_fail_next(DTR_METAL_TEST_FAILURE_DRAWABLE_UNAVAILABLE) ==
                 DTR_STATUS_OK,
             "one drawable miss is injected without a retry queue");
      [view draw];
      DtrMetalRendererStateV1 drawable_state = {};
      drawable_state.struct_size = sizeof(drawable_state);
      drawable_state.version = DTR_METAL_RENDERER_STATE_VERSION;
      Expect(metal_state(presentation_summary.handle, &drawable_state) ==
                     DTR_STATUS_OK &&
                 drawable_state.drawable_unavailable_count == 1 &&
                 drawable_state.ready_slot_count == 3 &&
                 drawable_state.in_flight_slot_count == 0 &&
                 drawable_state.failure_kind == DTR_METAL_FAILURE_NONE &&
                 (drawable_state.flags &
                  DTR_METAL_RENDERER_STATE_FAULTED) == 0,
             "drawable absence keeps newest READY ownership retryable");
      Expect(metal_request_draw != nullptr &&
                 metal_request_draw(presentation_summary.handle) ==
                     DTR_STATUS_OK,
             "retained READY work accepts an explicit later draw request");
      [view draw];
      DtrMetalRendererStateV1 completed_state = queued_state;
      for (int attempt = 0; attempt < 200; attempt++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        completed_state.struct_size = sizeof(completed_state);
        completed_state.version = DTR_METAL_RENDERER_STATE_VERSION;
        if (metal_state(presentation_summary.handle, &completed_state) !=
            DTR_STATUS_OK) {
          break;
        }
        if (completed_state.retired_through_token == 3) {
          break;
        }
        [view draw];
      }
      Expect(completed_state.retired_through_token == 3 &&
                 completed_state.last_presented_frame_generation == 3 &&
                 completed_state.completed_submission_count == 1 &&
                 completed_state.gpu_timing_sample_count == 1 &&
                 completed_state.gpu_total_time_ns > 0 &&
                 completed_state.gpu_max_time_ns > 0 &&
                 completed_state.gpu_max_time_ns <=
                     completed_state.gpu_total_time_ns &&
                 completed_state.stale_ready_drop_count == 2 &&
                 completed_state.ready_slot_count == 0 &&
                 completed_state.in_flight_slot_count == 0,
             "newest ready frame presents and all three tokens retire once");
      Expect(metal_upload(presentation_summary.handle, &blocked_atlas,
                          alpha_pixels.data()) == DTR_STATUS_OK,
             "atlas replacement resumes after GPU completion");
      completed_state.struct_size = sizeof(completed_state);
      completed_state.version = DTR_METAL_RENDERER_STATE_VERSION;
      Expect(metal_state(presentation_summary.handle, &completed_state) ==
                     DTR_STATUS_OK &&
                 completed_state.accepted_atlas_upload_count == 3 &&
                 completed_state.accepted_atlas_upload_bytes == 24,
             "only three accepted atlas payloads contribute upload metrics");
      const uint64_t presentation_handle = presentation_summary.handle;
      Expect(metal_release(presentation_handle) == DTR_STATUS_OK,
             "renderer release succeeds on the AppKit main thread");
      Expect(view.delegate == nil,
             "renderer release detaches its view on the AppKit main thread");
      Expect(live_metal_count() == 0,
             "main-thread renderer release drops registry ownership");
      completed_state.struct_size = sizeof(completed_state);
      completed_state.version = DTR_METAL_RENDERER_STATE_VERSION;
      Expect(metal_state(presentation_handle, &completed_state) ==
                 DTR_STATUS_INVALID_HANDLE,
             "released presentation renderer state is inaccessible");

      DtrMetalRendererSummaryV1 encoding_failure_summary = {};
      encoding_failure_summary.struct_size =
          sizeof(encoding_failure_summary);
      encoding_failure_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
      Expect(metal_create(&presentation_config, &encoding_failure_summary) ==
                 DTR_STATUS_OK,
             "command-encoding failure renderer is created");
      presentation_alpha.renderer_generation =
          encoding_failure_summary.generation;
      presentation_alpha.atlas_generation = 1;
      presentation_color.renderer_generation =
          encoding_failure_summary.generation;
      Expect(metal_upload(encoding_failure_summary.handle,
                          &presentation_alpha, alpha_pixels.data()) ==
                     DTR_STATUS_OK &&
                 metal_upload(encoding_failure_summary.handle,
                              &presentation_color, color_pixels.data()) ==
                     DTR_STATUS_OK,
             "command-encoding failure renderer receives atlas definitions");
      binding.renderer_handle = encoding_failure_summary.handle;
      binding.renderer_generation = encoding_failure_summary.generation;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_OK,
             "command-encoding failure renderer binds to the view");
      std::vector<uint8_t> encoding_failure_frame =
          make_frame(instances, encoding_failure_summary.generation, 1);
      encoding_failure_frame = mutate_header(
          encoding_failure_frame, ^(DtrMetalFrameHeaderV1* header) {
            header->viewport_width = drawable_width;
            header->viewport_height = drawable_height;
          });
      DtrMetalSubmissionV1 encoding_failure_submission = {};
      encoding_failure_submission.struct_size =
          sizeof(encoding_failure_submission);
      encoding_failure_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(
                 encoding_failure_summary.handle,
                 encoding_failure_frame.data(),
                 static_cast<uint32_t>(encoding_failure_frame.size()),
                 &encoding_failure_submission) == DTR_STATUS_OK &&
                 metal_fail_next(DTR_METAL_TEST_FAILURE_COMMAND_ENCODING) ==
                     DTR_STATUS_OK,
             "accepted frame reaches the injected encoding failure point");
      [view draw];
      DtrMetalRendererStateV1 encoding_failure_state = {};
      encoding_failure_state.struct_size = sizeof(encoding_failure_state);
      encoding_failure_state.version = DTR_METAL_RENDERER_STATE_VERSION;
      Expect(metal_state(encoding_failure_summary.handle,
                         &encoding_failure_state) == DTR_STATUS_OK &&
                 encoding_failure_state.failure_kind ==
                     DTR_METAL_FAILURE_COMMAND_ENCODING &&
                 encoding_failure_state.failure_generation == 1 &&
                 encoding_failure_state.last_failed_frame_generation == 1 &&
                 encoding_failure_state.command_failure_count == 1 &&
                 encoding_failure_state.gpu_timing_sample_count == 0 &&
                 encoding_failure_state.retired_through_token == 1 &&
                 encoding_failure_state.ready_slot_count == 0 &&
                 encoding_failure_state.in_flight_slot_count == 0 &&
                 (encoding_failure_state.flags &
                  DTR_METAL_RENDERER_STATE_FAULTED) != 0 &&
                 (encoding_failure_state.flags &
                  DTR_METAL_RENDERER_STATE_ADMITTING) == 0 &&
                 metal_request_draw(encoding_failure_summary.handle) ==
                     DTR_STATUS_NOT_FOUND,
             "encoding failure faults one renderer generation and retires work");
      std::vector<uint8_t> rejected_fault_frame =
          make_frame(instances, encoding_failure_summary.generation, 1);
      rejected_fault_frame = mutate_header(
          rejected_fault_frame, ^(DtrMetalFrameHeaderV1* header) {
            header->frame_generation = 2;
            header->viewport_width = drawable_width;
            header->viewport_height = drawable_height;
          });
      DtrMetalSubmissionV1 rejected_fault_submission = {};
      rejected_fault_submission.struct_size =
          sizeof(rejected_fault_submission);
      rejected_fault_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(
                 encoding_failure_summary.handle, rejected_fault_frame.data(),
                 static_cast<uint32_t>(rejected_fault_frame.size()),
                 &rejected_fault_submission) == DTR_STATUS_NOT_FOUND &&
                 rejected_fault_submission.submission_token == 0,
             "faulted renderer rejects later frame admission");
      Expect(metal_release(encoding_failure_summary.handle) == DTR_STATUS_OK &&
                 view.delegate == nil,
             "faulted renderer release detaches the reusable view");

      DtrMetalRendererSummaryV1 completion_failure_summary = {};
      completion_failure_summary.struct_size =
          sizeof(completion_failure_summary);
      completion_failure_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
      Expect(metal_create(&presentation_config, &completion_failure_summary) ==
                 DTR_STATUS_OK,
             "command-completion failure renderer is created");
      presentation_alpha.renderer_generation =
          completion_failure_summary.generation;
      presentation_color.renderer_generation =
          completion_failure_summary.generation;
      Expect(metal_upload(completion_failure_summary.handle,
                          &presentation_alpha, alpha_pixels.data()) ==
                     DTR_STATUS_OK &&
                 metal_upload(completion_failure_summary.handle,
                              &presentation_color, color_pixels.data()) ==
                     DTR_STATUS_OK,
             "command-completion failure renderer receives atlas definitions");
      binding.renderer_handle = completion_failure_summary.handle;
      binding.renderer_generation = completion_failure_summary.generation;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_OK,
             "command-completion failure renderer binds to the view");
      std::vector<uint8_t> completion_failure_frame =
          make_frame(instances, completion_failure_summary.generation, 1);
      completion_failure_frame = mutate_header(
          completion_failure_frame, ^(DtrMetalFrameHeaderV1* header) {
            header->viewport_width = drawable_width;
            header->viewport_height = drawable_height;
          });
      DtrMetalSubmissionV1 completion_failure_submission = {};
      completion_failure_submission.struct_size =
          sizeof(completion_failure_submission);
      completion_failure_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(
                 completion_failure_summary.handle,
                 completion_failure_frame.data(),
                 static_cast<uint32_t>(completion_failure_frame.size()),
                 &completion_failure_submission) == DTR_STATUS_OK &&
                 metal_fail_next(
                     DTR_METAL_TEST_FAILURE_COMMAND_COMPLETION) ==
                     DTR_STATUS_OK,
             "accepted frame reaches the injected completion failure point");
      [view draw];
      DtrMetalRendererStateV1 completion_failure_state = {};
      for (int attempt = 0; attempt < 200; attempt++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        completion_failure_state.struct_size =
            sizeof(completion_failure_state);
        completion_failure_state.version =
            DTR_METAL_RENDERER_STATE_VERSION;
        if (metal_state(completion_failure_summary.handle,
                        &completion_failure_state) != DTR_STATUS_OK ||
            completion_failure_state.failure_generation == 1) {
          break;
        }
      }
      Expect(completion_failure_state.failure_kind ==
                     DTR_METAL_FAILURE_COMMAND_EXECUTION &&
                 completion_failure_state.failure_generation == 1 &&
                 completion_failure_state.last_failed_frame_generation == 1 &&
                 completion_failure_state.command_failure_count == 1 &&
                 completion_failure_state.completed_submission_count == 0 &&
                 completion_failure_state.gpu_timing_sample_count == 0 &&
                 completion_failure_state.retired_through_token == 1 &&
                 (completion_failure_state.flags &
                  DTR_METAL_RENDERER_STATE_FAULTED) != 0,
             "completion failure is retained as a terminal renderer fault");
      Expect(metal_release(completion_failure_summary.handle) ==
                     DTR_STATUS_OK &&
                 view.delegate == nil,
             "completion-faulted renderer releases without a live slot");

      DtrMetalRendererSummaryV1 async_summary = {};
      async_summary.struct_size = sizeof(async_summary);
      async_summary.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
      Expect(metal_create(&presentation_config, &async_summary) ==
                 DTR_STATUS_OK,
             "worker-release renderer is created");
      presentation_alpha.renderer_generation = async_summary.generation;
      presentation_alpha.atlas_generation = 1;
      presentation_alpha.page_generation = 1;
      presentation_color.renderer_generation = async_summary.generation;
      Expect(metal_upload(async_summary.handle, &presentation_alpha,
                          alpha_pixels.data()) == DTR_STATUS_OK &&
                 metal_upload(async_summary.handle, &presentation_color,
                              color_pixels.data()) == DTR_STATUS_OK,
             "worker-release renderer receives atlas definitions");
      binding.renderer_handle = async_summary.handle;
      binding.renderer_generation = async_summary.generation;
      Expect(da_view_perform_custom_operation(
                 view_handle, reinterpret_cast<const uint8_t*>(&binding),
                 sizeof(binding)) == DA_STATUS_OK,
             "terminal view accepts a new renderer generation after detach");
      std::vector<uint8_t> async_frame =
          make_frame(instances, async_summary.generation, 1);
      async_frame = mutate_header(
          async_frame, ^(DtrMetalFrameHeaderV1* header) {
            header->viewport_width = drawable_width;
            header->viewport_height = drawable_height;
          });
      DtrMetalSubmissionV1 async_submission = {};
      async_submission.struct_size = sizeof(async_submission);
      async_submission.version = DTR_METAL_SUBMISSION_VERSION;
      Expect(metal_submit(async_summary.handle, async_frame.data(),
                          static_cast<uint32_t>(async_frame.size()),
                          &async_submission) == DTR_STATUS_OK,
             "worker-release frame is accepted");
      [view draw];
      std::atomic<int32_t> async_release_status{DTR_STATUS_INTERNAL};
      std::thread renderer_releaser([&] {
        async_release_status.store(metal_release(async_summary.handle));
      });
      renderer_releaser.join();
      Expect(async_release_status.load() == DTR_STATUS_OK &&
                 metal_state(async_summary.handle, &completed_state) ==
                     DTR_STATUS_INVALID_HANDLE,
             "worker release invalidates the renderer handle immediately");
      for (int attempt = 0;
           attempt < 200 && (view.delegate != nil || live_metal_count() != 0);
           attempt++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
      }
      Expect(view.delegate == nil, "worker release detaches on main");
      Expect(live_metal_count() == 0,
             "worker release drops registry ownership");

      Expect(da_release(view_handle) == DA_STATUS_OK,
             "Dart view handle releases independently");
      Expect(live_count() == 1, "window retain keeps attached renderer alive");
      Expect(da_release(view_handle) == DA_STATUS_INVALID_HANDLE,
             "released renderer handle cannot be reused");
      DaHandle replacement_handle = 0;
      Expect(da_view_create(&replacement_handle) == DA_STATUS_OK,
             "replacement view is created");
      Expect(da_window_set_content_view(window_handle, replacement_handle) ==
                 DA_STATUS_OK,
             "renderer can be detached through ordinary view replacement");
      Expect(da_release(replacement_handle) == DA_STATUS_OK,
             "replacement view handle releases");
      Expect(da_release(window_handle) == DA_STATUS_OK,
             "window handle releases");
      dart_appkit::ShutdownBridge();
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    Expect(live_count() == 0, "renderer deallocates during teardown");

    void* retained = dlopen(argv[1], RTLD_NOW | RTLD_NOLOAD);
    Expect(retained != nullptr,
           "renderer image remains loaded through teardown");
    dart_appkit::ResetBridgeForTesting();
    if (retained != nullptr) {
      dlclose(retained);
    }
    dlclose(image);
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "Terminal renderer capability contract passed\n";
  return 0;
}
