#include <type_traits>

#include "TerminalRendererPlugin.h"

static_assert(std::is_standard_layout_v<da_native_extension_services_v1>);
static_assert(std::is_standard_layout_v<DtrFontCatalogSummaryV1>);
static_assert(std::is_standard_layout_v<DtrResolvedFontV1>);
static_assert(std::is_standard_layout_v<DtrShapeHeaderV1>);
static_assert(std::is_standard_layout_v<DtrShapeRunV1>);
static_assert(std::is_standard_layout_v<DtrShapeFaceV1>);
static_assert(std::is_standard_layout_v<DtrShapeGlyphV1>);
static_assert(std::is_standard_layout_v<DtrRasterRequestV1>);
static_assert(std::is_standard_layout_v<DtrRasterHeaderV1>);
static_assert(std::is_standard_layout_v<DtrRasterGlyphV1>);
static_assert(std::is_standard_layout_v<DtrMetalRendererConfigV1>);
static_assert(std::is_standard_layout_v<DtrMetalRendererSummaryV1>);
static_assert(std::is_standard_layout_v<DtrMetalAtlasResetV1>);
static_assert(std::is_standard_layout_v<DtrMetalAtlasUploadV1>);
static_assert(std::is_standard_layout_v<DtrMetalFrameHeaderV1>);
static_assert(std::is_standard_layout_v<DtrMetalInstanceV1>);
static_assert(std::is_standard_layout_v<DtrMetalViewBindingV1>);
static_assert(std::is_standard_layout_v<DtrTextInputClientV1>);
static_assert(std::is_standard_layout_v<DtrTextInputGeometryV1>);
static_assert(std::is_standard_layout_v<DtrTextInputAcceptanceV1>);
static_assert(std::is_standard_layout_v<DtrTextInputEventHeaderV1>);
static_assert(std::is_standard_layout_v<DtrAccessibilitySnapshotHeaderV2>);
static_assert(std::is_standard_layout_v<DtrAccessibilityLineV1>);
static_assert(std::is_standard_layout_v<DtrAccessibilityAcceptanceV1>);
static_assert(std::is_standard_layout_v<DtrMetalSubmissionV1>);
static_assert(std::is_standard_layout_v<DtrMetalRendererStateV1>);
static_assert(sizeof(DtrFontCatalogSummaryV1) == 152);
static_assert(sizeof(DtrResolvedFontV1) == 192);
static_assert(sizeof(DtrShapeHeaderV1) == 80);
static_assert(sizeof(DtrShapeRunV1) == 40);
static_assert(sizeof(DtrShapeFaceV1) == 144);
static_assert(sizeof(DtrShapeGlyphV1) == 48);
static_assert(sizeof(DtrRasterRequestV1) == 8);
static_assert(sizeof(DtrRasterHeaderV1) == 64);
static_assert(sizeof(DtrRasterGlyphV1) == 48);
static_assert(sizeof(DtrMetalRendererConfigV1) == 48);
static_assert(sizeof(DtrMetalRendererSummaryV1) == 64);
static_assert(sizeof(DtrMetalAtlasResetV1) == 32);
static_assert(sizeof(DtrMetalAtlasUploadV1) == 80);
static_assert(sizeof(DtrMetalFrameHeaderV1) == 80);
static_assert(sizeof(DtrMetalInstanceV1) == 48);
static_assert(sizeof(DtrMetalViewBindingV1) == 32);
static_assert(sizeof(DtrTextInputClientV1) == 24);
static_assert(sizeof(DtrTextInputGeometryV1) == 64);
static_assert(sizeof(DtrTextInputAcceptanceV1) == 32);
static_assert(sizeof(DtrTextInputEventHeaderV1) == 96);
static_assert(sizeof(DtrAccessibilitySnapshotHeaderV2) == 136);
static_assert(sizeof(DtrAccessibilityLineV1) == 20);
static_assert(sizeof(DtrAccessibilityAcceptanceV1) == 24);
static_assert(sizeof(DtrMetalSubmissionV1) == 40);
static_assert(sizeof(DtrMetalRendererStateV1) == 176);

int main() {
  auto* version = &dtr_abi_version;
  auto* initialize = &dtr_initialize;
  auto* live_count = &dtr_debug_live_view_count;
  auto* catalog_create = &dtr_font_catalog_create;
  auto* catalog_release = &dtr_font_catalog_release;
  auto* catalog_finalizer = &dtr_font_catalog_release_finalizer;
  auto* catalog_resolve = &dtr_font_catalog_resolve;
  auto* catalog_shape = &dtr_font_catalog_shape;
  auto* catalog_rasterize = &dtr_font_catalog_rasterize;
  auto* catalog_count = &dtr_debug_live_font_catalog_count;
  auto* renderer_create = &dtr_metal_renderer_create;
  auto* renderer_release = &dtr_metal_renderer_release;
  auto* renderer_finalizer = &dtr_metal_renderer_release_finalizer;
  auto* renderer_reset = &dtr_metal_renderer_reset_atlas;
  auto* renderer_upload = &dtr_metal_renderer_upload_atlas;
  auto* renderer_submit = &dtr_metal_renderer_submit;
  auto* renderer_state = &dtr_metal_renderer_state;
  auto* renderer_request_draw = &dtr_metal_renderer_request_draw;
  auto* renderer_render = &dtr_metal_renderer_render_rgba;
  auto* renderer_count = &dtr_debug_live_metal_renderer_count;
  auto* renderer_fail_next = &dtr_debug_metal_fail_next;
  return version == nullptr || initialize == nullptr || live_count == nullptr ||
         catalog_create == nullptr || catalog_release == nullptr ||
         catalog_finalizer == nullptr || catalog_resolve == nullptr ||
         catalog_shape == nullptr || catalog_rasterize == nullptr ||
         catalog_count == nullptr || renderer_create == nullptr ||
         renderer_release == nullptr || renderer_finalizer == nullptr ||
         renderer_reset == nullptr ||
         renderer_upload == nullptr || renderer_submit == nullptr ||
         renderer_state == nullptr || renderer_request_draw == nullptr ||
         renderer_render == nullptr || renderer_count == nullptr ||
         renderer_fail_next == nullptr;
}
