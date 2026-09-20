#include "TerminalNotesPlugin.h"

#include <cstdio>
#include <cstring>
#include <vector>

namespace {

void write_u16(std::vector<uint8_t>& bytes, size_t offset, uint16_t value) {
  bytes[offset] = static_cast<uint8_t>(value);
  bytes[offset + 1u] = static_cast<uint8_t>(value >> 8u);
}

void write_u32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
  for (size_t byte = 0; byte < 4u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

void write_u64(std::vector<uint8_t>& bytes, size_t offset, uint64_t value) {
  for (size_t byte = 0; byte < 8u; ++byte) {
    bytes[offset + byte] = static_cast<uint8_t>(value >> (byte * 8u));
  }
}

std::vector<uint8_t> packet(uint64_t projection_generation,
                            uint64_t store_revision,
                            const std::vector<std::string>& bodies = {"hello"}) {
  size_t aggregate_body_bytes = 0;
  for (const std::string& body : bodies) aggregate_body_bytes += body.size();
  const size_t body_offset =
      DTN_PROJECTION_HEADER_BYTES + bodies.size() * DTN_CARD_RECORD_BYTES;
  std::vector<uint8_t> bytes(body_offset + aggregate_body_bytes, 0u);
  write_u32(bytes, 0u, DTN_PROJECTION_MAGIC);
  write_u32(bytes, 4u, static_cast<uint32_t>(bytes.size()));
  write_u16(bytes, 8u, DTN_PROJECTION_VERSION);
  write_u16(bytes, 10u, DTN_PROJECTION_HEADER_BYTES);
  write_u16(bytes, 12u, DTN_CARD_RECORD_BYTES);
  bytes[14u] = DTN_VISIBILITY_EXPANDED;
  bytes[15u] = 1u;
  write_u64(bytes, 16u, 11u);
  write_u64(bytes, 24u, 7u);
  write_u64(bytes, 32u, projection_generation);
  write_u64(bytes, 40u, store_revision);
  if (!bodies.empty()) write_u64(bytes, 48u, 1u);
  write_u32(bytes, 56u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 64u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 68u, static_cast<uint32_t>(aggregate_body_bytes));
  write_u32(bytes, 72u, DTN_PROJECTION_HEADER_BYTES);
  write_u32(bytes, 76u, static_cast<uint32_t>(body_offset));
  bytes[80u] = DTN_FEATURE_AVAILABLE;
  bytes[81u] = DTN_SURFACE_READY;
  bytes[82u] = DTN_SECTION_CURRENT;
  bytes[83u] = DTN_EDITOR_INACTIVE;
  write_u32(bytes, 92u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 96u, static_cast<uint32_t>(bodies.size()));
  write_u32(bytes, 104u, 15000u);
  uint32_t running_body_offset = 0;
  for (size_t index = 0; index < bodies.size(); ++index) {
    const size_t record =
        DTN_PROJECTION_HEADER_BYTES + index * DTN_CARD_RECORD_BYTES;
    write_u64(bytes, record, static_cast<uint64_t>(index + 1u));
    write_u32(bytes, record + 8u, running_body_offset);
    write_u32(bytes, record + 12u,
              static_cast<uint32_t>(bodies[index].size()));
    bytes[record + 20u] = static_cast<uint8_t>(index % 6u);
    std::memcpy(bytes.data() + body_offset + running_body_offset,
                bodies[index].data(), bodies[index].size());
    running_body_offset += static_cast<uint32_t>(bodies[index].size());
  }
  return bytes;
}

bool expect(bool condition, const char* message) {
  if (!condition) std::fprintf(stderr, "FAIL: %s\n", message);
  return condition;
}

}  // namespace

int main() {
  bool ok = true;
  ok &= expect(dtn_abi_version() == 1u, "ABI version");
  ok &= expect(dtn_debug_live_surfaces() == 0u, "initial owner count");
  DtnSurface* surface = dtn_surface_create();
  ok &= expect(surface != nullptr, "surface creation");
  ok &= expect(dtn_debug_live_surfaces() == 1u, "live owner count");

  DtnSurfaceSnapshotV1 snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.initialized == 0u,
               "empty snapshot");

  std::vector<uint8_t> valid = packet(1u, 4u);
  ok &= expect(dtn_surface_apply_projection(surface, valid.data(), valid.size()) ==
                   DTN_STATUS_OK,
               "valid projection");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.projection_generation == 1u &&
                   snapshot.projected_card_count == 1u &&
                   snapshot.accepted_projection_count == 1u &&
                   snapshot.feature_state == DTN_FEATURE_AVAILABLE &&
                   snapshot.surface_state == DTN_SURFACE_READY,
               "accepted snapshot");

  std::vector<uint8_t> stale = packet(1u, 4u);
  ok &= expect(dtn_surface_apply_projection(surface, stale.data(), stale.size()) ==
                   DTN_STATUS_STALE,
               "stale generation rejection");
  std::vector<uint8_t> older_store = packet(2u, 3u);
  ok &= expect(dtn_surface_apply_projection(surface, older_store.data(),
                                            older_store.size()) ==
                   DTN_STATUS_STALE,
               "stale store revision rejection");
  std::vector<uint8_t> other_surface = packet(2u, 5u);
  write_u64(other_surface, 24u, 8u);
  ok &= expect(dtn_surface_apply_projection(surface, other_surface.data(),
                                            other_surface.size()) ==
                   DTN_STATUS_STALE,
               "cross-surface rejection");

  std::vector<uint8_t> unsupported = packet(2u, 5u);
  write_u16(unsupported, 8u, 2u);
  ok &= expect(dtn_surface_apply_projection(surface, unsupported.data(),
                                            unsupported.size()) ==
                   DTN_STATUS_UNSUPPORTED_VERSION,
               "version rejection");
  std::vector<uint8_t> unknown_flag = packet(2u, 5u);
  unknown_flag[15u] = 0x80u;
  ok &= expect(dtn_surface_apply_projection(surface, unknown_flag.data(),
                                            unknown_flag.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "unknown flag rejection");
  std::vector<uint8_t> collapsed_body = packet(2u, 5u);
  collapsed_body[14u] = DTN_VISIBILITY_COLLAPSED;
  ok &= expect(dtn_surface_apply_projection(surface, collapsed_body.data(),
                                            collapsed_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "collapsed body rejection");
  std::vector<uint8_t> duplicate = packet(2u, 5u, {"one", "two"});
  write_u64(duplicate, DTN_PROJECTION_HEADER_BYTES + DTN_CARD_RECORD_BYTES,
            1u);
  ok &= expect(dtn_surface_apply_projection(surface, duplicate.data(),
                                            duplicate.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "duplicate token rejection");
  std::vector<uint8_t> invalid_utf8 = packet(2u, 5u, {"x"});
  invalid_utf8.back() = 0xffu;
  ok &= expect(dtn_surface_apply_projection(surface, invalid_utf8.data(),
                                            invalid_utf8.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "invalid UTF-8 rejection");
  std::vector<uint8_t> oversized_body =
      packet(2u, 5u, {std::string(DTN_MAX_CARD_BODY_BYTES + 1u, 'x')});
  ok &= expect(dtn_surface_apply_projection(surface, oversized_body.data(),
                                            oversized_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "card body +1 rejection");
  std::vector<uint8_t> empty_body = packet(2u, 5u, {""});
  ok &= expect(dtn_surface_apply_projection(surface, empty_body.data(),
                                            empty_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "empty card body rejection");
  std::vector<uint8_t> control_body = packet(2u, 5u, {std::string("x\0y", 3)});
  ok &= expect(dtn_surface_apply_projection(surface, control_body.data(),
                                            control_body.size()) ==
                   DTN_STATUS_INVALID_ARGUMENT,
               "control body rejection");

  const std::string maximum_body(DTN_MAX_CARD_BODY_BYTES, 'x');
  std::vector<std::string> maximum_bodies(DTN_MAX_CARDS, maximum_body);
  std::vector<uint8_t> maximum = packet(2u, 5u, maximum_bodies);
  ok &= expect(dtn_surface_apply_projection(surface, maximum.data(),
                                            maximum.size()) == DTN_STATUS_OK,
               "maximum packet acceptance");
  snapshot = {};
  snapshot.struct_size = sizeof(snapshot);
  snapshot.version = DTN_SNAPSHOT_VERSION;
  ok &= expect(dtn_surface_snapshot(surface, &snapshot) == DTN_STATUS_OK &&
                   snapshot.projection_generation == 2u &&
                   snapshot.projected_card_count == DTN_MAX_CARDS &&
                   snapshot.materialized_card_count ==
                       DTN_MAX_MATERIALIZED_CARDS &&
                   snapshot.rejected_projection_count == 11u,
               "atomic last-good state and materialization bound");

  dtn_surface_destroy(surface);
  ok &= expect(dtn_debug_live_surfaces() == 0u, "final owner count");
  if (!ok) return 1;
  std::puts("terminal Notes native codec tests passed");
  return 0;
}
