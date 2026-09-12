#include <metal_stdlib>

using namespace metal;

struct DtrMetalInstanceV1 {
  int2 origin;
  uint2 size;
  uint2 atlas_origin;
  uint2 atlas_size;
  uint color_rgba;
  uint kind;
  uint page_index;
  uint page_generation;
};

struct DtrVertexOutput {
  float4 position [[position]];
  float2 atlas_position;
  float4 color;
  uint kind [[flat]];
  uint page_index [[flat]];
};

static float4 dtr_unpack_rgba(uint packed) {
  return float4(float((packed >> 24) & 0xffu),
                float((packed >> 16) & 0xffu),
                float((packed >> 8) & 0xffu), float(packed & 0xffu)) /
         255.0;
}

vertex DtrVertexOutput dtr_terminal_vertex(
    uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
    const device DtrMetalInstanceV1* instances [[buffer(0)]],
    constant float2& viewport [[buffer(1)]]) {
  const float2 corners[4] = {
      float2(0.0, 0.0), float2(1.0, 0.0),
      float2(0.0, 1.0), float2(1.0, 1.0),
  };
  const DtrMetalInstanceV1 instance = instances[instance_id];
  const float2 corner = corners[vertex_id];
  const float2 pixel = float2(instance.origin) + corner * float2(instance.size);
  DtrVertexOutput output;
  output.position = float4(pixel.x * 2.0 / viewport.x - 1.0,
                           1.0 - pixel.y * 2.0 / viewport.y, 0.0, 1.0);
  output.atlas_position =
      float2(instance.atlas_origin) + corner * float2(instance.atlas_size);
  output.color = dtr_unpack_rgba(instance.color_rgba);
  output.kind = instance.kind;
  output.page_index = instance.page_index;
  return output;
}

fragment float4 dtr_terminal_fragment(
    DtrVertexOutput input [[stage_in]],
    texture2d_array<float, access::sample> alpha_atlas [[texture(0)]],
    texture2d_array<float, access::sample> color_atlas [[texture(1)]]) {
  constexpr sampler atlas_sampler(coord::pixel, address::clamp_to_zero,
                                  filter::nearest);
  if (input.kind == 3u) {
    const float coverage =
        alpha_atlas.sample(atlas_sampler, input.atlas_position,
                           input.page_index).r;
    return float4(input.color.rgb, input.color.a * coverage);
  }
  if (input.kind == 4u) {
    return color_atlas.sample(atlas_sampler, input.atlas_position,
                              input.page_index);
  }
  return input.color;
}
