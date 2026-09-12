#include "TerminalRendererPlugin.h"

_Static_assert(sizeof(DtrFontCatalogSummaryV1) == 152,
               "font catalog summary ABI size");
_Static_assert(sizeof(DtrResolvedFontV1) == 192,
               "resolved font ABI size");
_Static_assert(sizeof(DtrShapeHeaderV1) == 80, "shape header ABI size");
_Static_assert(sizeof(DtrShapeRunV1) == 40, "shape run ABI size");
_Static_assert(sizeof(DtrShapeFaceV1) == 144, "shape face ABI size");
_Static_assert(sizeof(DtrShapeGlyphV1) == 48, "shape glyph ABI size");
_Static_assert(sizeof(DtrRasterRequestV1) == 8, "raster request ABI size");
_Static_assert(sizeof(DtrRasterHeaderV1) == 64, "raster header ABI size");
_Static_assert(sizeof(DtrRasterGlyphV1) == 48, "raster glyph ABI size");
_Static_assert(sizeof(DtrMetalRendererConfigV1) == 48,
               "Metal renderer config ABI size");
_Static_assert(sizeof(DtrMetalRendererSummaryV1) == 64,
               "Metal renderer summary ABI size");
_Static_assert(sizeof(DtrMetalAtlasResetV1) == 32,
               "Metal atlas reset ABI size");
_Static_assert(sizeof(DtrMetalAtlasUploadV1) == 80,
               "Metal atlas upload ABI size");
_Static_assert(sizeof(DtrMetalFrameHeaderV1) == 80,
               "Metal frame header ABI size");
_Static_assert(sizeof(DtrMetalInstanceV1) == 48,
               "Metal instance ABI size");
_Static_assert(sizeof(DtrMetalViewBindingV1) == 32,
               "Metal view binding ABI size");
_Static_assert(sizeof(DtrTextInputClientV1) == 24,
               "text input client ABI size");
_Static_assert(sizeof(DtrTextInputGeometryV1) == 64,
               "text input geometry ABI size");
_Static_assert(sizeof(DtrTextInputAcceptanceV1) == 32,
               "text input acceptance ABI size");
_Static_assert(sizeof(DtrTextInputEventHeaderV1) == 96,
               "text input event ABI size");
_Static_assert(sizeof(DtrAccessibilitySnapshotHeaderV2) == 136,
               "accessibility snapshot header ABI size");
_Static_assert(sizeof(DtrAccessibilityLineV1) == 20,
               "accessibility line ABI size");
_Static_assert(sizeof(DtrAccessibilityAcceptanceV1) == 24,
               "accessibility acceptance ABI size");
_Static_assert(sizeof(DtrMetalSubmissionV1) == 40,
               "Metal submission ABI size");
_Static_assert(sizeof(DtrMetalRendererStateV1) == 176,
               "Metal renderer state ABI size");

int main(void) {
  uint32_t (*version)(void) = dtr_abi_version;
  int32_t (*initialize)(const da_native_extension_services_v1*) =
      dtr_initialize;
  int32_t (*live_count)(void) = dtr_debug_live_view_count;
  int32_t (*catalog_create)(const uint8_t*, uint32_t, double, uint32_t,
                            DtrFontCatalogSummaryV1*) =
      dtr_font_catalog_create;
  int32_t (*catalog_release)(uint64_t) = dtr_font_catalog_release;
  void (*catalog_finalizer)(void*) = dtr_font_catalog_release_finalizer;
  int32_t (*catalog_resolve)(uint64_t, uint32_t, const uint8_t*, uint32_t,
                             DtrResolvedFontV1*) = dtr_font_catalog_resolve;
  int32_t (*catalog_shape)(uint64_t, uint32_t, uint32_t, const uint8_t*,
                           uint32_t, uint8_t*, uint32_t, uint32_t*) =
      dtr_font_catalog_shape;
  int32_t (*catalog_rasterize)(uint64_t, uint32_t,
                               const DtrRasterRequestV1*, uint32_t, uint8_t*,
                               uint32_t, uint32_t*) =
      dtr_font_catalog_rasterize;
  int32_t (*catalog_count)(void) = dtr_debug_live_font_catalog_count;
  int32_t (*renderer_create)(const DtrMetalRendererConfigV1*,
                             DtrMetalRendererSummaryV1*) =
      dtr_metal_renderer_create;
  int32_t (*renderer_release)(uint64_t) = dtr_metal_renderer_release;
  void (*renderer_finalizer)(void*) = dtr_metal_renderer_release_finalizer;
  int32_t (*renderer_reset)(uint64_t, const DtrMetalAtlasResetV1*) =
      dtr_metal_renderer_reset_atlas;
  int32_t (*renderer_upload)(uint64_t, const DtrMetalAtlasUploadV1*,
                             const uint8_t*) =
      dtr_metal_renderer_upload_atlas;
  int32_t (*renderer_submit)(uint64_t, const uint8_t*, uint32_t,
                             DtrMetalSubmissionV1*) =
      dtr_metal_renderer_submit;
  int32_t (*renderer_state)(uint64_t, DtrMetalRendererStateV1*) =
      dtr_metal_renderer_state;
  int32_t (*renderer_request_draw)(uint64_t) =
      dtr_metal_renderer_request_draw;
  int32_t (*renderer_render)(uint64_t, const uint8_t*, uint32_t, uint8_t*,
                             uint32_t, uint32_t*) =
      dtr_metal_renderer_render_rgba;
  int32_t (*renderer_count)(void) = dtr_debug_live_metal_renderer_count;
  int32_t (*renderer_fail_next)(uint32_t) = dtr_debug_metal_fail_next;
  return version == 0 || initialize == 0 || live_count == 0 ||
         catalog_create == 0 || catalog_release == 0 ||
         catalog_finalizer == 0 || catalog_resolve == 0 ||
         catalog_shape == 0 || catalog_rasterize == 0 || catalog_count == 0 ||
         renderer_create == 0 || renderer_release == 0 ||
         renderer_finalizer == 0 ||
         renderer_reset == 0 ||
         renderer_upload == 0 || renderer_submit == 0 ||
         renderer_state == 0 || renderer_request_draw == 0 ||
         renderer_render == 0 || renderer_count == 0 ||
         renderer_fail_next == 0;
}
