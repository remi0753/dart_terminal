#import <Foundation/Foundation.h>

#include <dlfcn.h>

#include <iostream>
#include <vector>

#include "TerminalRendererPlugin.h"

namespace {

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "TerminalRendererSanitizer expectation failed: "
              << description << '\n';
    ++failures;
  }
}

template <typename Function>
Function Lookup(void* image, const char* symbol) {
  dlerror();
  Function function = reinterpret_cast<Function>(dlsym(image, symbol));
  const char* error = dlerror();
  if (function == nullptr || error != nullptr) {
    std::cerr << "Could not resolve " << symbol << '\n';
    ++failures;
  }
  return function;
}

}  // namespace

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      std::cerr << "usage: renderer_sanitizer_tests <plugin.dylib>\n";
      return 64;
    }
    void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == nullptr) {
      std::cerr << "Could not load renderer sanitizer capability\n";
      return 1;
    }

    using Version = uint32_t (*)();
    using FontCreate = int32_t (*)(const uint8_t*, uint32_t, double, uint32_t,
                                   DtrFontCatalogSummaryV1*);
    using FontRelease = int32_t (*)(uint64_t);
    using FontResolve = int32_t (*)(uint64_t, uint32_t, const uint8_t*,
                                    uint32_t, DtrResolvedFontV1*);
    using FontShape = int32_t (*)(uint64_t, uint32_t, uint32_t,
                                  const uint8_t*, uint32_t, uint8_t*, uint32_t,
                                  uint32_t*);
    using FontRasterize = int32_t (*)(uint64_t, uint32_t,
                                      const DtrRasterRequestV1*, uint32_t,
                                      uint8_t*, uint32_t, uint32_t*);
    using MetalCreate = int32_t (*)(const DtrMetalRendererConfigV1*,
                                    DtrMetalRendererSummaryV1*);
    using MetalRelease = int32_t (*)(uint64_t);
    using LiveCount = int32_t (*)();

    const Version version = Lookup<Version>(image, "dtr_abi_version");
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
    const LiveCount live_fonts =
        Lookup<LiveCount>(image, "dtr_debug_live_font_catalog_count");
    const MetalCreate metal_create =
        Lookup<MetalCreate>(image, "dtr_metal_renderer_create");
    const MetalRelease metal_release =
        Lookup<MetalRelease>(image, "dtr_metal_renderer_release");
    const LiveCount live_renderers =
        Lookup<LiveCount>(image, "dtr_debug_live_metal_renderer_count");
    if (failures != 0) {
      dlclose(image);
      return 1;
    }

    Expect(version() == DTR_ABI_VERSION, "exact renderer ABI version");
    DtrFontCatalogSummaryV1 unsupported = {};
    unsupported.struct_size = sizeof(unsupported);
    unsupported.version = UINT32_MAX;
    Expect(font_create(nullptr, 0, 14.0, DTR_FONT_POLICY_ALLOW_SYNTHETIC,
                       &unsupported) == DTR_STATUS_UNSUPPORTED_VERSION,
           "unsupported summary version fails closed");

    constexpr char kMenlo[] = "Menlo";
    DtrFontCatalogSummaryV1 font = {};
    font.struct_size = sizeof(font);
    font.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create(reinterpret_cast<const uint8_t*>(kMenlo),
                       sizeof(kMenlo) - 1, 14.0,
                       DTR_FONT_POLICY_ALLOW_SYNTHETIC,
                       &font) == DTR_STATUS_OK &&
               font.handle != 0 && font.generation != 0 &&
               font.cell_width > 0.0 && font.cell_height > 0.0 &&
               live_fonts() == 1,
           "font catalog publishes one bounded live owner");

    const uint8_t invalid_utf8[] = {0xff};
    DtrResolvedFontV1 invalid = {};
    invalid.struct_size = sizeof(invalid);
    invalid.version = DTR_RESOLVED_FONT_VERSION;
    Expect(font_resolve(font.handle, DTR_FONT_STYLE_REGULAR, invalid_utf8,
                        sizeof(invalid_utf8),
                        &invalid) == DTR_STATUS_INVALID_ARGUMENT,
           "malformed UTF-8 is rejected before allocation");

    constexpr char kText[] = "sanitizer";
    uint32_t shape_required = 0;
    Expect(font_shape(font.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES,
                      reinterpret_cast<const uint8_t*>(kText),
                      sizeof(kText) - 1, nullptr, 0,
                      &shape_required) == DTR_STATUS_BUFFER_TOO_SMALL &&
               shape_required >= sizeof(DtrShapeHeaderV1) &&
               shape_required <= DTR_MAX_SHAPE_OUTPUT_BYTES,
           "shape query publishes a bounded allocation size");
    std::vector<uint8_t> shape(shape_required, 0xa5);
    uint32_t filled_shape = 0;
    Expect(font_shape(font.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES,
                      reinterpret_cast<const uint8_t*>(kText),
                      sizeof(kText) - 1, shape.data(), shape.size(),
                      &filled_shape) == DTR_STATUS_OK &&
               filled_shape == shape.size(),
           "shape output fills the exact queried allocation");
    const auto* shape_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(shape.data());
    const bool shape_is_valid =
        shape.size() >= sizeof(DtrShapeHeaderV1) &&
        shape_header->magic == DTR_SHAPE_BUFFER_MAGIC &&
        shape_header->version == DTR_SHAPE_BUFFER_VERSION &&
        shape_header->total_size == shape.size() &&
        shape_header->glyph_count > 0 &&
        shape_header->glyphs_offset <=
            shape.size() - sizeof(DtrShapeGlyphV1);
    Expect(shape_is_valid, "shape output has a valid bounded glyph section");

    if (shape_is_valid) {
      const auto* glyph = reinterpret_cast<const DtrShapeGlyphV1*>(
          shape.data() + shape_header->glyphs_offset);
      const DtrRasterRequestV1 request = {glyph->face_id, glyph->glyph_id};
      uint32_t raster_required = 0;
      Expect(font_rasterize(font.handle, 1u << 16, &request, 1, nullptr, 0,
                            &raster_required) ==
                     DTR_STATUS_BUFFER_TOO_SMALL &&
                 raster_required >= sizeof(DtrRasterHeaderV1) &&
                 raster_required <= DTR_MAX_RASTER_OUTPUT_BYTES,
             "raster query publishes a bounded allocation size");
      std::vector<uint8_t> raster(raster_required, 0xa5);
      uint32_t filled_raster = 0;
      Expect(font_rasterize(font.handle, 1u << 16, &request, 1, raster.data(),
                            raster.size(), &filled_raster) == DTR_STATUS_OK &&
                 filled_raster == raster.size(),
             "raster output fills and owns the exact allocation");
      const auto* raster_header =
          reinterpret_cast<const DtrRasterHeaderV1*>(raster.data());
      Expect(raster.size() >= sizeof(DtrRasterHeaderV1) &&
                 raster_header->magic == DTR_RASTER_BUFFER_MAGIC &&
                 raster_header->version == DTR_RASTER_BUFFER_VERSION &&
                 raster_header->total_size == raster.size() &&
                 raster_header->glyph_count == 1,
             "raster output has a valid bounded payload");
    }

    Expect(font_release(font.handle) == DTR_STATUS_OK && live_fonts() == 0,
           "font allocation is released exactly once");
    Expect(font_release(font.handle) == DTR_STATUS_INVALID_HANDLE &&
               live_fonts() == 0,
           "duplicate font release is inert");

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
    DtrMetalRendererSummaryV1 metal = {};
    metal.struct_size = sizeof(metal);
    metal.version = DTR_METAL_RENDERER_SUMMARY_VERSION;
    const int32_t metal_status = metal_create(&metal_config, &metal);
    if (metal_status == DTR_STATUS_OK) {
      Expect(metal.handle != 0 && metal.generation != 0 &&
                 metal.failure_kind == DTR_METAL_FAILURE_NONE &&
                 live_renderers() == 1,
             "available Metal device publishes one renderer owner");
      Expect(metal_release(metal.handle) == DTR_STATUS_OK &&
                 live_renderers() == 0,
             "available Metal renderer releases exactly once");
    } else {
      Expect(metal_status == DTR_STATUS_NOT_FOUND && metal.handle == 0 &&
                 metal.generation == 0 &&
                 metal.failure_kind == DTR_METAL_FAILURE_DEVICE_UNAVAILABLE &&
                 live_renderers() == 0,
             "unavailable Metal device fails typed without publication");
    }
    Expect(metal_status == DTR_STATUS_OK,
           "sanitizer acceptance requires a real Metal renderer allocation");

    dlclose(image);
  }

  if (failures != 0) {
    return 1;
  }
  std::cout << "Terminal renderer sanitizer-safe capabilities passed\n";
  return 0;
}
