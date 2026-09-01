#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <pthread.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <mutex>
#include <vector>

constexpr uint32_t kFrameMagic = 0x4c475444;
constexpr uint16_t kFrameVersion = 1;
constexpr uint32_t kExpectedInstanceCount = 100000;
constexpr uint32_t kInstanceStride = 32;
constexpr size_t kSlotCount = 3;
constexpr uint64_t kFrameTarget = 120;
constexpr uint64_t kFrameBudgetMicros = 11667;
constexpr uint64_t kCopyBudgetMicros = 4000;

#pragma pack(push, 1)
struct PackedFrameHeader {
  uint32_t magic;
  uint16_t version;
  uint16_t header_bytes;
  uint32_t instance_stride;
  uint32_t instance_count;
  uint32_t total_bytes;
  uint32_t reserved;
  uint64_t generation;
};

struct PackedGlyphInstance {
  float origin_x;
  float origin_y;
  float size_x;
  float size_y;
  uint32_t rgba;
  uint32_t glyph_index;
  uint32_t flags;
  uint32_t reserved;
};
#pragma pack(pop)

static_assert(sizeof(PackedFrameHeader) == 32);
static_assert(sizeof(PackedGlyphInstance) == kInstanceStride);

struct RenderSlot {
  __strong id<MTLBuffer> buffer = nil;
  uint64_t generation = 0;
  bool ready = false;
  bool in_flight = false;
};

struct RenderStats {
  uint64_t accepted_submissions = 0;
  uint64_t backpressure_rejections = 0;
  uint64_t stale_frames_dropped = 0;
  uint64_t completed_frames = 0;
  uint64_t empty_draws = 0;
  uint64_t main_thread_violations = 0;
  uint64_t last_submitted_generation = 0;
  std::vector<uint64_t> copy_micros;
  std::vector<uint64_t> encode_micros;
  std::vector<uint64_t> gpu_micros;
};

static uint64_t Percentile95(std::vector<uint64_t> values) {
  if (values.empty()) {
    return 0;
  }
  std::sort(values.begin(), values.end());
  const size_t index = (values.size() * 95 + 99) / 100 - 1;
  return values[std::min(index, values.size() - 1)];
}

@interface Phase0MetalRenderer : NSObject <MTKViewDelegate>

- (instancetype)initWithWindow:(NSWindow*)window
                  instanceCount:(uint32_t)instanceCount;
- (int32_t)submitBytes:(const uint8_t*)bytes length:(uint64_t)length;
- (uint64_t)completedFrames;
- (uint64_t)acceptedSubmissions;
- (uint64_t)backpressureRejections;
- (int32_t)validateAndStop;

@end

@implementation Phase0MetalRenderer {
  MTKView* view_;
  id<MTLDevice> device_;
  id<MTLCommandQueue> command_queue_;
  id<MTLRenderPipelineState> pipeline_;
  uint32_t instance_count_;
  std::array<RenderSlot, kSlotCount> slots_;
  std::mutex mutex_;
  RenderStats stats_;
}

- (instancetype)initWithWindow:(NSWindow*)window
                  instanceCount:(uint32_t)instanceCount {
  self = [super init];
  if (self == nil || window == nil || instanceCount != kExpectedInstanceCount) {
    return nil;
  }

  device_ = MTLCreateSystemDefaultDevice();
  if (device_ == nil) {
    std::fprintf(stderr, "PHASE0_METAL_FAIL no Metal device\n");
    return nil;
  }
  command_queue_ = [device_ newCommandQueue];
  if (command_queue_ == nil) {
    std::fprintf(stderr, "PHASE0_METAL_FAIL no command queue\n");
    return nil;
  }

  view_ = [[MTKView alloc] initWithFrame:window.contentView.bounds
                                  device:device_];
  view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  view_.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  view_.clearColor = MTLClearColorMake(0.025, 0.03, 0.045, 1.0);
  view_.preferredFramesPerSecond = 60;
  view_.paused = NO;
  view_.enableSetNeedsDisplay = NO;
  view_.framebufferOnly = YES;

  static const char* const shader_source_utf8 = R"METAL(
#include <metal_stdlib>
using namespace metal;

struct GlyphInstance {
  packed_float2 origin;
  packed_float2 size;
  uint rgba;
  uint glyph_index;
  uint flags;
  uint reserved;
};

struct VertexOut {
  float4 position [[position]];
  float2 uv;
  float4 color;
  uint glyph_index [[flat]];
};

vertex VertexOut glyph_vertex(
    uint vertex_id [[vertex_id]],
    uint instance_id [[instance_id]],
    const device GlyphInstance* instances [[buffer(0)]],
    constant float2& viewport [[buffer(1)]]) {
  constexpr float2 corners[6] = {
    float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
    float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
  };
  GlyphInstance instance = instances[instance_id];
  float2 corner = corners[vertex_id];
  float2 pixel = float2(instance.origin) + corner * float2(instance.size);
  float2 ndc = float2((pixel.x / viewport.x) * 2.0 - 1.0,
                      1.0 - (pixel.y / viewport.y) * 2.0);
  uint rgba = instance.rgba;
  VertexOut out;
  out.position = float4(ndc, 0.0, 1.0);
  out.uv = corner;
  out.color = float4(float((rgba >> 0) & 255) / 255.0,
                     float((rgba >> 8) & 255) / 255.0,
                     float((rgba >> 16) & 255) / 255.0,
                     float((rgba >> 24) & 255) / 255.0);
  out.glyph_index = instance.glyph_index;
  return out;
}

fragment float4 glyph_fragment(VertexOut in [[stage_in]]) {
  float edge = min(min(in.uv.x, 1.0 - in.uv.x),
                   min(in.uv.y, 1.0 - in.uv.y));
  float bit = float((in.glyph_index >> uint(in.uv.x * 5.0)) & 1u);
  float ink = mix(0.35 + bit * 0.25, 1.0, smoothstep(0.0, 0.12, edge));
  return float4(in.color.rgb * ink, in.color.a);
}
)METAL";
  NSString* shader_source = [NSString stringWithUTF8String:shader_source_utf8];

  NSError* library_error = nil;
  id<MTLLibrary> library = [device_ newLibraryWithSource:shader_source
                                                 options:nil
                                                   error:&library_error];
  if (library == nil) {
    std::fprintf(stderr, "PHASE0_METAL_FAIL shader library: %s\n",
                 library_error.localizedDescription.UTF8String);
    return nil;
  }
  id<MTLFunction> vertex = [library newFunctionWithName:@"glyph_vertex"];
  id<MTLFunction> fragment = [library newFunctionWithName:@"glyph_fragment"];
  if (vertex == nil || fragment == nil) {
    std::fprintf(stderr, "PHASE0_METAL_FAIL shader function lookup\n");
    return nil;
  }
  MTLRenderPipelineDescriptor* descriptor =
      [[MTLRenderPipelineDescriptor alloc] init];
  descriptor.vertexFunction = vertex;
  descriptor.fragmentFunction = fragment;
  descriptor.colorAttachments[0].pixelFormat = view_.colorPixelFormat;
  NSError* pipeline_error = nil;
  pipeline_ = [device_ newRenderPipelineStateWithDescriptor:descriptor
                                                       error:&pipeline_error];
  if (pipeline_ == nil) {
    std::fprintf(stderr, "PHASE0_METAL_FAIL pipeline: %s\n",
                 pipeline_error.localizedDescription.UTF8String);
    return nil;
  }

  const NSUInteger buffer_length =
      static_cast<NSUInteger>(instanceCount) * sizeof(PackedGlyphInstance);
  for (RenderSlot& slot : slots_) {
    slot.buffer = [device_ newBufferWithLength:buffer_length
                                       options:MTLResourceStorageModeShared];
    if (slot.buffer == nil) {
      std::fprintf(stderr, "PHASE0_METAL_FAIL instance buffer allocation\n");
      return nil;
    }
  }

  instance_count_ = instanceCount;
  view_.delegate = self;
  window.contentView = view_;
  window.title = @"Dart Terminal — Phase 0 Metal 100k";
  return self;
}

- (int32_t)submitBytes:(const uint8_t*)bytes length:(uint64_t)length {
  if (bytes == nullptr || length < sizeof(PackedFrameHeader)) {
    return 1;
  }
  PackedFrameHeader header = {};
  std::memcpy(&header, bytes, sizeof(header));
  const uint64_t expected_length =
      sizeof(PackedFrameHeader) +
      static_cast<uint64_t>(header.instance_count) * header.instance_stride;
  if (header.magic != kFrameMagic || header.version != kFrameVersion ||
      header.header_bytes != sizeof(PackedFrameHeader) ||
      header.instance_stride != sizeof(PackedGlyphInstance) ||
      header.instance_count != instance_count_ ||
      header.total_bytes != length || expected_length != length ||
      header.reserved != 0 || header.generation == 0) {
    return 1;
  }

  const auto started = std::chrono::steady_clock::now();
  const std::lock_guard<std::mutex> lock(mutex_);
  if (header.generation <= stats_.last_submitted_generation) {
    return 3;
  }
  size_t slot_index = kSlotCount;
  for (size_t index = 0; index < slots_.size(); ++index) {
    if (!slots_[index].ready && !slots_[index].in_flight) {
      slot_index = index;
      break;
    }
  }
  if (slot_index == kSlotCount) {
    ++stats_.backpressure_rejections;
    return 2;
  }

  RenderSlot& slot = slots_[slot_index];
  std::memcpy(slot.buffer.contents, bytes + sizeof(PackedFrameHeader),
              static_cast<size_t>(length - sizeof(PackedFrameHeader)));
  slot.generation = header.generation;
  slot.ready = true;
  stats_.last_submitted_generation = header.generation;
  ++stats_.accepted_submissions;
  stats_.copy_micros.push_back(static_cast<uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - started)
          .count()));
  return 0;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

- (void)drawInMTKView:(MTKView*)view {
  @autoreleasepool {
    if (pthread_main_np() == 0) {
      const std::lock_guard<std::mutex> lock(mutex_);
      ++stats_.main_thread_violations;
    }

    MTLRenderPassDescriptor* render_pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (render_pass == nil || drawable == nil) {
      return;
    }

    size_t selected = kSlotCount;
    uint64_t selected_generation = 0;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      for (size_t index = 0; index < slots_.size(); ++index) {
        if (slots_[index].ready &&
            slots_[index].generation > selected_generation) {
          selected = index;
          selected_generation = slots_[index].generation;
        }
      }
      if (selected == kSlotCount) {
        ++stats_.empty_draws;
        return;
      }
      for (size_t index = 0; index < slots_.size(); ++index) {
        if (index != selected && slots_[index].ready &&
            slots_[index].generation < selected_generation) {
          slots_[index].ready = false;
          ++stats_.stale_frames_dropped;
        }
      }
      slots_[selected].ready = false;
      slots_[selected].in_flight = true;
    }

    const auto encode_started = std::chrono::steady_clock::now();
    id<MTLCommandBuffer> command_buffer = [command_queue_ commandBuffer];
    id<MTLRenderCommandEncoder> encoder =
        [command_buffer renderCommandEncoderWithDescriptor:render_pass];
    if (command_buffer == nil || encoder == nil) {
      const std::lock_guard<std::mutex> lock(mutex_);
      slots_[selected].in_flight = false;
      return;
    }
    [encoder setRenderPipelineState:pipeline_];
    [encoder setVertexBuffer:slots_[selected].buffer offset:0 atIndex:0];
    const vector_float2 viewport = {
        static_cast<float>(view.drawableSize.width),
        static_cast<float>(view.drawableSize.height),
    };
    [encoder setVertexBytes:&viewport length:sizeof(viewport) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:instance_count_];
    [encoder endEncoding];
    [command_buffer presentDrawable:drawable];

    __weak Phase0MetalRenderer* weak_self = self;
    [command_buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
      Phase0MetalRenderer* strong_self = weak_self;
      if (strong_self == nil) {
        return;
      }
      const double gpu_seconds = completed.GPUEndTime - completed.GPUStartTime;
      const std::lock_guard<std::mutex> completion_lock(strong_self->mutex_);
      strong_self->slots_[selected].in_flight = false;
      ++strong_self->stats_.completed_frames;
      if (gpu_seconds > 0) {
        strong_self->stats_.gpu_micros.push_back(
            static_cast<uint64_t>(gpu_seconds * 1000000.0));
      }
    }];
    [command_buffer commit];

    const uint64_t encode_micros = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - encode_started)
            .count());
    const std::lock_guard<std::mutex> lock(mutex_);
    stats_.encode_micros.push_back(encode_micros);
  }
}

- (uint64_t)completedFrames {
  const std::lock_guard<std::mutex> lock(mutex_);
  return stats_.completed_frames;
}

- (uint64_t)acceptedSubmissions {
  const std::lock_guard<std::mutex> lock(mutex_);
  return stats_.accepted_submissions;
}

- (uint64_t)backpressureRejections {
  const std::lock_guard<std::mutex> lock(mutex_);
  return stats_.backpressure_rejections;
}

- (int32_t)validateAndStop {
  RenderStats stats;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    stats = stats_;
  }
  const uint64_t copy_p95 = Percentile95(stats.copy_micros);
  const uint64_t encode_p95 = Percentile95(stats.encode_micros);
  const uint64_t gpu_p95 = Percentile95(stats.gpu_micros);
  uint32_t failures = 0;
  failures |= stats.completed_frames < kFrameTarget ? 1U << 0 : 0;
  failures |= stats.accepted_submissions < kFrameTarget ? 1U << 1 : 0;
  failures |= stats.main_thread_violations != 0 ? 1U << 2 : 0;
  failures |= stats.copy_micros.empty() || copy_p95 >= kCopyBudgetMicros
                  ? 1U << 3
                  : 0;
  failures |= stats.encode_micros.empty() || encode_p95 >= kFrameBudgetMicros
                  ? 1U << 4
                  : 0;
  failures |= stats.gpu_micros.empty() || gpu_p95 >= kFrameBudgetMicros
                  ? 1U << 5
                  : 0;

  std::fprintf(
      failures == 0 ? stdout : stderr,
      "PHASE0_METAL_NATIVE_%s failures=0x%x instances=%u frames=%llu "
      "accepted=%llu backpressure=%llu stale=%llu empty_draws=%llu "
      "copy_p95_us=%llu encode_p95_us=%llu gpu_p95_us=%llu "
      "main_thread_violations=%llu\n",
      failures == 0 ? "PASS" : "FAIL", failures, instance_count_,
      static_cast<unsigned long long>(stats.completed_frames),
      static_cast<unsigned long long>(stats.accepted_submissions),
      static_cast<unsigned long long>(stats.backpressure_rejections),
      static_cast<unsigned long long>(stats.stale_frames_dropped),
      static_cast<unsigned long long>(stats.empty_draws),
      static_cast<unsigned long long>(copy_p95),
      static_cast<unsigned long long>(encode_p95),
      static_cast<unsigned long long>(gpu_p95),
      static_cast<unsigned long long>(stats.main_thread_violations));

  view_.paused = YES;
  view_.delegate = nil;
  return static_cast<int32_t>(failures);
}

@end

static Phase0MetalRenderer* g_renderer = nil;

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_metal_create(uint32_t instance_count) {
  if (pthread_main_np() == 0 || g_renderer != nil) {
    return 1;
  }
  NSWindow* window = NSApp.keyWindow;
  if (window == nil) {
    window = NSApp.windows.firstObject;
  }
  if (window == nil) {
    return 2;
  }
  g_renderer = [[Phase0MetalRenderer alloc] initWithWindow:window
                                             instanceCount:instance_count];
  return g_renderer == nil ? 3 : 0;
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_metal_submit(const uint8_t* bytes, uint64_t length,
                       uint64_t generation) {
  (void)generation;
  @autoreleasepool {
    Phase0MetalRenderer* renderer = g_renderer;
    if (renderer == nil || pthread_main_np() != 0) {
      return 4;
    }
    return [renderer submitBytes:bytes length:length];
  }
}

extern "C" __attribute__((visibility("default"))) uint64_t
dt_phase0_metal_completed_frames(void) {
  Phase0MetalRenderer* renderer = g_renderer;
  return renderer == nil ? 0 : [renderer completedFrames];
}

extern "C" __attribute__((visibility("default"))) uint64_t
dt_phase0_metal_accepted_submissions(void) {
  Phase0MetalRenderer* renderer = g_renderer;
  return renderer == nil ? 0 : [renderer acceptedSubmissions];
}

extern "C" __attribute__((visibility("default"))) uint64_t
dt_phase0_metal_backpressure_rejections(void) {
  Phase0MetalRenderer* renderer = g_renderer;
  return renderer == nil ? 0 : [renderer backpressureRejections];
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_metal_validate_and_stop(void) {
  if (pthread_main_np() == 0 || g_renderer == nil) {
    return 1;
  }
  Phase0MetalRenderer* renderer = g_renderer;
  return [renderer validateAndStop];
}

extern "C" __attribute__((visibility("default"))) void
dt_phase0_native_finalize(void) {
  if (pthread_main_np() != 0 && g_renderer != nil) {
    g_renderer = nil;
  }
}
