#include "TerminalNotesPlugin.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <sys/sysctl.h>

namespace {

constexpr uint32_t kWarmupCount = 5u;
constexpr uint32_t kSampleCount = 21u;
constexpr uint32_t kContextNoteCount = 128u;
constexpr uint64_t kApplyBudgetNanoseconds = 8'000'000u;
constexpr uint64_t kFirstVisibleBudgetNanoseconds = 100'000'000u;
constexpr uint64_t kStallThresholdNanoseconds = 33'340'000u;
constexpr char kRequiredHardware[] = "MacBookPro17,1";
constexpr uint64_t kRequiredMemoryBytes = 16ull * 1024ull * 1024ull * 1024ull;

const da_native_extension_services_v1 kServices = {
    sizeof(da_native_extension_services_v1),
    DA_NATIVE_EXTENSION_ABI_VERSION,
    nullptr,
    nullptr,
};

void WriteU16(std::vector<uint8_t>& bytes, size_t offset, uint16_t value) {
  bytes[offset] = static_cast<uint8_t>(value);
  bytes[offset + 1u] = static_cast<uint8_t>(value >> 8u);
}

void WriteU32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
  for (size_t byte = 0; byte < 4u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

void WriteU64(std::vector<uint8_t>& bytes, size_t offset, uint64_t value) {
  for (size_t byte = 0; byte < 8u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

std::vector<uint8_t> ProjectionPacket(uint64_t generation, bool expanded) {
  const uint32_t card_count = expanded ? DTN_MAX_CARDS : 0u;
  const uint32_t body_bytes =
      expanded ? DTN_MAX_CARDS * DTN_MAX_CARD_BODY_BYTES : 0u;
  const size_t body_offset =
      DTN_PROJECTION_HEADER_BYTES + card_count * DTN_CARD_RECORD_BYTES;
  std::vector<uint8_t> bytes(body_offset + body_bytes, 0u);
  WriteU32(bytes, 0u, DTN_PROJECTION_MAGIC);
  WriteU32(bytes, 4u, static_cast<uint32_t>(bytes.size()));
  WriteU16(bytes, 8u, DTN_PROJECTION_VERSION);
  WriteU16(bytes, 10u, DTN_PROJECTION_HEADER_BYTES);
  WriteU16(bytes, 12u, DTN_CARD_RECORD_BYTES);
  bytes[14u] = expanded ? DTN_VISIBILITY_EXPANDED
                        : DTN_VISIBILITY_COLLAPSED;
  bytes[15u] = 1u;
  WriteU64(bytes, 16u, 1u);
  WriteU64(bytes, 24u, 1u);
  WriteU64(bytes, 32u, generation);
  WriteU64(bytes, 40u, 1u);
  WriteU64(bytes, 48u, expanded ? 1u : 0u);
  WriteU32(bytes, 56u, kContextNoteCount);
  WriteU32(bytes, 64u, card_count);
  WriteU32(bytes, 68u, body_bytes);
  WriteU32(bytes, 72u, DTN_PROJECTION_HEADER_BYTES);
  WriteU32(bytes, 76u, static_cast<uint32_t>(body_offset));
  bytes[80u] = DTN_FEATURE_AVAILABLE;
  bytes[81u] = DTN_SURFACE_READY;
  bytes[82u] = DTN_SECTION_CURRENT;
  bytes[83u] = DTN_EDITOR_INACTIVE;
  WriteU32(bytes, 92u, card_count);
  WriteU32(bytes, 96u, kContextNoteCount);
  WriteU32(bytes, 104u, 15000u);
  for (uint32_t index = 0u; index < card_count; ++index) {
    const size_t record =
        DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    WriteU64(bytes, record, index + 1u);
    WriteU32(bytes, record + 8u, index * DTN_MAX_CARD_BODY_BYTES);
    WriteU32(bytes, record + 12u, DTN_MAX_CARD_BODY_BYTES);
    WriteU32(bytes, record + 16u, index);
    bytes[record + 20u] = static_cast<uint8_t>(index % 6u);
  }
  std::fill(bytes.begin() + static_cast<ptrdiff_t>(body_offset), bytes.end(),
            static_cast<uint8_t>('x'));
  return bytes;
}

bool ReadAuthorityEnvironment(std::string* hardware, uint64_t* memory_bytes) {
#if !defined(__arm64__)
  (void)hardware;
  (void)memory_bytes;
  return false;
#else
  char model[128] = {};
  size_t model_size = sizeof(model);
  size_t memory_size = sizeof(*memory_bytes);
  if (sysctlbyname("hw.model", model, &model_size, nullptr, 0u) != 0 ||
      model_size == 0u || model_size > sizeof(model) ||
      sysctlbyname("hw.memsize", memory_bytes, &memory_size, nullptr, 0u) !=
          0 ||
      memory_size != sizeof(*memory_bytes)) {
    return false;
  }
  model[sizeof(model) - 1u] = '\0';
  *hardware = model;
  return *hardware == kRequiredHardware &&
         *memory_bytes == kRequiredMemoryBytes;
#endif
}

uint64_t Percentile95(std::vector<uint64_t> samples) {
  std::sort(samples.begin(), samples.end());
  const size_t rank = (samples.size() * 95u + 99u) / 100u;
  return samples[rank - 1u];
}

uint64_t MicrosecondsCeiling(uint64_t nanoseconds) {
  return (nanoseconds + 999u) / 1000u;
}

int Fail(const char* reason) {
  std::fprintf(stderr,
               "TERMINAL_NOTE_R0_NATIVE_BUDGET_FAIL reason=%s "
               "content_free=true\n",
               reason);
  return 1;
}

int FailBudget(const char* reason, uint64_t apply_p95,
               uint64_t first_visible_p95, uint32_t stalls) {
  std::fprintf(
      stderr,
      "TERMINAL_NOTE_R0_NATIVE_BUDGET_FAIL reason=%s apply_p95_us=%llu "
      "first_visible_p95_us=%llu stalls=%u content_free=true\n",
      reason,
      static_cast<unsigned long long>(MicrosecondsCeiling(apply_p95)),
      static_cast<unsigned long long>(MicrosecondsCeiling(first_visible_p95)),
      stalls);
  return 1;
}

}  // namespace

int main() {
  @autoreleasepool {
    if (![NSThread isMainThread]) return Fail("wrong_thread");
    std::string hardware;
    uint64_t memory_bytes = 0u;
    if (!ReadAuthorityEnvironment(&hardware, &memory_bytes)) {
      return Fail("environment_authority");
    }
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    if (dtn_initialize(&kServices) != DTN_STATUS_OK ||
        dtn_debug_live_surfaces() != 0u) {
      return Fail("initialization");
    }

    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(-10000, -10000, 800, 600)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    window.releasedWhenClosed = NO;
    window.contentView = host;
    [window orderFrontRegardless];

    DtnSurface* surface = dtn_surface_create();
    DtnLayoutV1 layout = {};
    layout.struct_size = sizeof(layout);
    layout.version = DTN_LAYOUT_VERSION;
    layout.pane_width = 800;
    layout.pane_height = 600;
    layout.backing_scale = 2;
    layout.requested_rail_width = 360;
    const bool setup_ok =
        window != nil && window.isVisible && surface != nullptr &&
        dtn_surface_attach_to_host(surface, (__bridge void*)host) ==
            DTN_STATUS_OK &&
        dtn_surface_update_layout(surface, &layout) == DTN_STATUS_OK;
    NSView* note_view = surface == nullptr
                            ? nil
                            : (__bridge NSView*)dtn_surface_native_view(surface);
    if (!setup_ok || note_view == nil || note_view.window != window) {
      if (surface != nullptr) dtn_surface_destroy(surface);
      [window orderOut:nil];
      [window close];
      return Fail("surface_setup");
    }

    std::vector<uint64_t> apply_samples;
    std::vector<uint64_t> first_visible_samples;
    apply_samples.reserve(kSampleCount);
    first_visible_samples.reserve(kSampleCount);
    uint32_t stalls = 0u;
    uint64_t generation = 1u;
    const char* failure = nullptr;
    const auto run_cycle = [&](bool measured) -> bool {
      @autoreleasepool {
        const std::vector<uint8_t> collapsed =
            ProjectionPacket(generation++, false);
        if (dtn_surface_apply_projection(surface, collapsed.data(),
                                         collapsed.size()) != DTN_STATUS_OK) {
          failure = "collapsed_apply";
          return false;
        }
        [host layoutSubtreeIfNeeded];
        [note_view setNeedsDisplay:YES];
        [note_view displayIfNeeded];

        const std::vector<uint8_t> expanded =
            ProjectionPacket(generation++, true);
        const auto started = std::chrono::steady_clock::now();
        if (dtn_surface_apply_projection(surface, expanded.data(),
                                         expanded.size()) != DTN_STATUS_OK) {
          failure = "expanded_apply";
          return false;
        }
        const auto applied = std::chrono::steady_clock::now();
        [host layoutSubtreeIfNeeded];
        [note_view setNeedsDisplay:YES];
        [note_view displayIfNeeded];
        [window displayIfNeeded];
        const auto visible = std::chrono::steady_clock::now();

        DtnSurfaceSnapshotV1 snapshot = {};
        snapshot.struct_size = sizeof(snapshot);
        snapshot.version = DTN_SNAPSHOT_VERSION;
        DtnPresentationSnapshotV1 presentation = {};
        presentation.struct_size = sizeof(presentation);
        presentation.version = DTN_PRESENTATION_SNAPSHOT_VERSION;
        if (dtn_surface_snapshot(surface, &snapshot) != DTN_STATUS_OK ||
            dtn_surface_presentation_snapshot(surface, &presentation) !=
                DTN_STATUS_OK ||
            snapshot.projection_generation != generation - 1u ||
            snapshot.projected_card_count != DTN_MAX_CARDS ||
            snapshot.materialized_card_count != DTN_MAX_MATERIALIZED_CARDS ||
            snapshot.packet_bytes != expanded.size() ||
            presentation.materialized_card_count !=
                DTN_MAX_MATERIALIZED_CARDS ||
            presentation.accessibility_body_count !=
                DTN_MAX_MATERIALIZED_CARDS ||
            (presentation.flags & DTN_PRESENTATION_RAIL_VISIBLE) == 0u ||
            presentation.first_card_width <= 0 ||
            presentation.first_card_height <= 0) {
          failure = "first_visible_state";
          return false;
        }
        if (measured) {
          const uint64_t apply_nanoseconds = static_cast<uint64_t>(
              std::chrono::duration_cast<std::chrono::nanoseconds>(applied -
                                                                   started)
                  .count());
          const uint64_t first_visible_nanoseconds = static_cast<uint64_t>(
              std::chrono::duration_cast<std::chrono::nanoseconds>(visible -
                                                                   started)
                  .count());
          apply_samples.push_back(apply_nanoseconds);
          first_visible_samples.push_back(first_visible_nanoseconds);
          if (first_visible_nanoseconds > kStallThresholdNanoseconds) {
            ++stalls;
          }
        }
        return true;
      }
    };

    for (uint32_t index = 0u; index < kWarmupCount && failure == nullptr;
         ++index) {
      run_cycle(false);
    }
    for (uint32_t index = 0u; index < kSampleCount && failure == nullptr;
         ++index) {
      run_cycle(true);
    }

    uint64_t apply_p95 = 0u;
    uint64_t first_visible_p95 = 0u;
    if (failure == nullptr &&
        (apply_samples.size() != kSampleCount ||
         first_visible_samples.size() != kSampleCount)) {
      failure = "sample_inventory";
    }
    if (failure == nullptr) {
      apply_p95 = Percentile95(apply_samples);
      first_visible_p95 = Percentile95(first_visible_samples);
      if (apply_p95 > kApplyBudgetNanoseconds) {
        failure = "apply_budget";
      } else if (first_visible_p95 > kFirstVisibleBudgetNanoseconds) {
        failure = "first_visible_budget";
      } else if (stalls != 0u) {
        failure = "main_thread_stall";
      }
    }

    const int32_t detach_status = dtn_surface_detach_from_host(surface);
    dtn_surface_destroy(surface);
    [window orderOut:nil];
    window.contentView = nil;
    [window close];
    const uint64_t owners = dtn_debug_live_surfaces();
    if (detach_status != DTN_STATUS_OK || owners != 0u) {
      failure = "surface_teardown";
    }
    if (failure != nullptr) {
      return apply_p95 == 0u && first_visible_p95 == 0u
                 ? Fail(failure)
                 : FailBudget(failure, apply_p95, first_visible_p95, stalls);
    }

    std::printf(
        "TERMINAL_NOTE_R0_NATIVE_BUDGET_PASS version=1 abi=macos_arm64 "
        "hardware=%s memory_bytes=%llu warmups=%u samples=%u cards=%u "
        "materialized=%u body_bytes=%u apply_p95_us=%llu "
        "apply_budget_us=%llu first_visible_p95_us=%llu "
        "first_visible_budget_us=%llu stalls=%u stall_threshold_us=%llu "
        "owners=%llu content_free=true\n",
        hardware.c_str(), static_cast<unsigned long long>(memory_bytes),
        kWarmupCount, kSampleCount, DTN_MAX_CARDS,
        DTN_MAX_MATERIALIZED_CARDS, DTN_MAX_BODY_BYTES,
        static_cast<unsigned long long>(MicrosecondsCeiling(apply_p95)),
        static_cast<unsigned long long>(
            MicrosecondsCeiling(kApplyBudgetNanoseconds)),
        static_cast<unsigned long long>(
            MicrosecondsCeiling(first_visible_p95)),
        static_cast<unsigned long long>(
            MicrosecondsCeiling(kFirstVisibleBudgetNanoseconds)),
        stalls,
        static_cast<unsigned long long>(
            MicrosecondsCeiling(kStallThresholdNanoseconds)),
        static_cast<unsigned long long>(owners));
    return 0;
  }
}
