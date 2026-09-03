# Native event wire format versioning and compatibility

- Status: completed
- Started: 2026-09-03
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, ADR-001, `dart_appkit` native event bridge

## Purpose

Replace the implicit native-event list contract with an explicitly versioned,
negotiated wire protocol. The Developer JIT and Release AOT products must emit
the same current format while a legacy Dart or native endpoint can continue to
use the existing version-1 format without misinterpreting fields.

## Background

The current `dart_appkit` bridge uses `DA_ABI_VERSION == 1` as both the public
C ABI version and the first value in every event list. Event registration only
passes a Dart port, so there is no capability negotiation. Both native hosts
emit `[version, type, window_handle, monotonic_micros, ...payload]`, and the
Dart decoder accepts only version 1 with exact list lengths. This does not meet
ADR-001's asynchronous-event prefix or provide a compatible way to introduce
source generation, nanosecond timestamps, operation identity, or later event
formats.

## Scope

- Separate native-event protocol versions from the stable C ABI version.
- Keep the legacy event-port registration call and version-1 encoding intact.
- Add an additive C ABI registration call that negotiates the highest mutually
  supported event protocol version and fails closed when no version overlaps.
- Define version 2 with the ADR-001 prefix:
  `[version, type, source_handle, source_generation, monotonic_ns,
  operation_id, ...payload]`.
- Emit version 2 for current Dart/native pairs in both Developer JIT and
  Release AOT; emit version 1 for a legacy registrant.
- Decode versions 1 and 2 in Dart, retain the existing microsecond-facing API,
  and expose the negotiated metadata without breaking existing constructors.
- Validate envelope/payload types, lengths, handle/generation consistency,
  timestamps, operation IDs, unknown types, and unsupported versions.
- Add native, Dart, FFI, and product-level conformance coverage, including
  exact Developer/Release observation parity.
- Update build provenance so an event-protocol input change cannot reuse a
  stale product bundle.

## Out of scope

- The following handle-registry thread-domain/asynchronous-destruction task.
- New view, focus, visibility, occlusion, backing-scale, screen, menu,
  pasteboard, PTY, renderer, or IME event types.
- Changing handle ownership, adding per-window asynchronous operations, or
  assigning nonzero operation IDs to today's unsolicited AppKit events.
- Increasing the top-level C ABI version for an additive symbol.
- x86_64, Rosetta, Universal, or Intel-native follow-up work.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `623fa86` and clean pinned
  `dart_appkit` HEAD `77e3553`.
- This is the first unchecked roadmap item; no later Phase 1 item is in scope.
- The Developer host serializes events in `dart_appkit`'s `DartHost`; the
  Release host has an equivalent serializer in this repository. Both consume
  the same `NativeEvent` and event sink.
- Generation-checked handles encode a positive 32-bit generation in their high
  half. Version 2 can validate its explicit source generation against that
  stable handle representation without changing registry ownership.
- Current UI events are unsolicited, so operation ID zero is the only valid
  value emitted by this task. The field is present for future async completion
  events.
- The existing Dart API exposes `monotonicMicros`; version 2 must preserve that
  getter while retaining the nanosecond wire value for new consumers.
- `Dart_PostCObject` copies the event synchronously, so temporary encoder
  storage remains safe until the post returns.

## Design decision

Use protocol negotiation rather than changing the meaning of the legacy port
registration call. `da_application_set_event_port` selects version 1 exactly.
An additive versioned registration call accepts a minimum and maximum and
selects the highest overlap with the native `[minimum, current]` range. The
current pair requests versions 1 through 2 and therefore selects version 2.
An endpoint that only knows the legacy symbol/call continues to receive the
unchanged version-1 lists.

The selected protocol version is stored with the event sink registration and
passed to the host-owned serializer. Version 1 converts the internal monotonic
nanosecond timestamp to microseconds. Version 2 emits the exact nanoseconds,
the handle's encoded generation, and operation ID zero before the unchanged
event-specific payload. The Dart decoder normalizes either version into one
event model.

## Acceptance criteria

1. Legacy registration emits byte-for-byte/value-for-value version-1 event
   lists with their existing field order and microsecond timestamp unit.
2. Versioned registration selects version 2 for range `[1, 2]`, selects
   version 1 for `[1, 1]`, and returns a deterministic unsupported-version
   failure with no active port for disjoint, reversed, zero, or unsupported
   ranges.
3. Version 2 uses the exact six-field ADR-001 prefix and the existing payload
   order, with a positive source generation matching the handle, a nonnegative
   monotonic nanosecond timestamp, and operation ID zero.
4. Dart decodes valid v1 and v2 close, resize, mouse, and key events to the same
   public event kinds and values. Existing `monotonicMicros` behavior and
   public event constructors remain source-compatible.
5. Malformed envelopes, bad types/lengths, invalid handles/generations,
   negative timestamps/operations, unknown event types, and unsupported
   versions become deterministic stream errors and do not hang or terminate
   the application.
6. New Dart code can attach to a legacy native bridge through a deterministic
   v1 fallback; old Dart code can register against the new bridge and continues
   to receive v1.
7. Developer JIT and Release AOT build, audit, and smoke with version 2 and
   report the same selected version and decoded event metadata.
8. Formatting, static analysis, native/Dart unit tests, current product source
   checks, focused arm64 bundle/audit/integration tests, clean SDK checks, and
   final diff/artifact hygiene pass.
9. The roadmap is checked only after all accepted changes and verification are
   recorded here, followed by task-scoped commits.

## Validation plan

- Run `dart_appkit`'s header, native bridge, Dart API, FFI smoke, and complete
  local test targets.
- Add table-driven codec fixtures for both protocol versions and every rejected
  envelope class; exercise negotiated and legacy registration independently.
- Run Dart Terminal formatting, analysis, unit tests, native source checks,
  build freshness checks, and the arm64 Developer JIT/Release AOT audits and
  integration smoke suites.
- Confirm both product modes record version 2 from a real window event rather
  than relying only on unit fixtures.
- Review both repositories' working trees, staged diffs, generated files,
  adjacent SDK cleanliness, and final commits.

## Risks and open checks

- The Dart FFI fallback must distinguish a genuinely missing additive symbol
  from a native call failure without hiding unrelated symbol-resolution bugs.
- Exact v1 compatibility requires timestamp conversion at serialization time;
  changing the internal clock unit must not silently change legacy values.
- The Developer serializer is owned by `dart_appkit` while the Release
  serializer is product-owned. Shared constants and conformance fixtures must
  prevent drift without moving terminal-specific code into `dart_appkit`.
- Product integration currently proves close delivery indirectly. The harness
  needs a stable diagnostic that demonstrates the selected wire version and
  decoded metadata without making normal user output noisy.

## Investigation log

### 2026-09-03 — repository and boundary review

- Read the project rules, product overview, roadmap, feature matrix, ADR-001,
  ADR-002, existing Phase 1 runtime records, complete repository inventory,
  worktree state, and the adjacent pinned `dart_appkit` bridge/Runner/Dart API
  and tests.
- Confirmed that C ABI version 1 is incorrectly reused as the event protocol
  discriminator and that neither endpoint negotiates compatibility.
- Confirmed that the current v1 common prefix has four fields and exact event
  lengths, while ADR-001 requires source generation, monotonic nanoseconds,
  and operation ID in a six-field prefix.
- Rejected changing the existing event registration call to emit v2: an old
  Dart decoder would reject it. Rejected emitting v1 forever: current products
  would not exercise or prove the Phase 1 contract. Selected an additive
  negotiation call plus unchanged legacy registration.
- Determined that the task crosses the reusable `dart_appkit` event boundary
  and the product-owned Release host/provenance boundary. Both repositories
  are clean and no unrelated changes are present.

## Implementation log

### 2026-09-03 — reusable AppKit protocol boundary

- Added independent event protocol constants for minimum version 1 and current
  version 2 while retaining `DA_ABI_VERSION == 1`.
- Kept `da_application_set_event_port` as a strict v1 registration and added
  `da_application_set_event_port_versioned`. The latter validates a positive,
  ordered unsigned range, selects the highest overlap, returns
  `DA_STATUS_UNSUPPORTED_VERSION` for a disjoint range, zeroes its result, and
  disables event posting on every failed negotiation.
- The event sink now stores the selected version with the port. Internal event
  time is nanoseconds; the legacy encoder divides only at the v1 wire boundary.
- Moved the `Dart_CObject` serializer out of the JIT host into one reusable
  `DartEventEncoder`. The Dart Terminal Release host now calls that exact
  encoder instead of retaining a second implementation.
- Version 2 emits the six-field ADR prefix. Source generation comes from the
  handle's high 32 bits, and invalid handle generation, negative time,
  unsupported version, and unrepresentable legacy operation IDs fail before a
  post.
- Dart FFI looks up the additive symbol optionally. A missing symbol uses the
  legacy registration only when the requested range includes v1; a fixture
  dylib with the old symbol set proves this path. Current native pairs negotiate
  v2.
- `AppKitEvent` retains its existing constructors and `monotonicMicros` while
  exposing protocol version, source generation, exact nanoseconds, and
  operation ID. The decoder normalizes v1 and v2 and rejects malformed or
  inconsistent metadata as stream errors.
- The reusable boundary was committed in adjacent `dart_appkit` as
  `a70e5e400c9321471f133dff1356a7cc29114fa4` (`Negotiate native event protocol
  versions`). That clean revision is now the product build input.

### 2026-09-03 — product integration and provenance

- Added the shared encoder to both product host build graphs. Release AOT's
  duplicate v1-only serializer was removed.
- Added `native_event_protocol_version: 2` to effective build configuration.
  Fingerprint format advanced from 6 to 7 and manifest format from 8 to 9 so
  old cached artifacts cannot satisfy the changed schema. Manifest validation
  and both focused freshness paths require the current protocol version.
- Added a test-gated real-event observation. The smoke harness sets
  `DT_RUNTIME_EVENT_WIRE_TEST=1`; the application reports the negotiated and
  decoded metadata only under that gate, avoiding normal-user output changes.
  The harness requires negotiated v2, decoded v2, positive source generation,
  operation ID zero, and a positive nanosecond timestamp on the actual native
  window-close event.
- Updated the README and feature matrix without claiming the following handle
  registry, generic-view, PTY, renderer, or resource-leak tasks.

## Failed attempts and corrections

- The first formatter/test invocation for the adjacent repository was denied
  by the workspace sandbox when it attempted to rewrite files and update the
  Dart telemetry timestamp outside the writable root. It made no partial
  source change. The same scoped formatting and tests were rerun with explicit
  permission and succeeded.
- The first standalone FFI smoke expected `EVENT_PORT_UNAVAILABLE`, but a
  standalone Dart process is also outside the AppKit main thread and correctly
  hits the earlier `WRONG_THREAD` guard. The fixture assertion was corrected to
  accept either valid precondition failure while requiring native diagnostic
  text. No product behavior was changed to satisfy the test.

## Validation record

### Reusable `dart_appkit` boundary

- `make test`: passed scaffold/C/C++ header checks, native bridge tests, strict
  Runner checks, message-pump tests, exact v1/v2 encoder tests, Dart analysis,
  API and launcher tests, example Kernel compilation, current FFI smoke, and
  new-Dart/legacy-native fallback smoke.
- `dart format --output=none --set-exit-if-changed` and native
  `clang-format --dry-run --Werror`: passed with zero changes.
- The exact encoder fixture verified the unchanged v1 resize layout and v2 key
  layout. Native negotiation tests verified v2 `[1,2]`, v1 `[1,1]`, legacy v1,
  disjoint rejection, invalid ranges, null output, and posting disabled after
  failure.

### Dart Terminal product

- `make runtime-source-check`: passed Dart formatting, native formatting,
  C/C++ lifecycle header checks, plist lint, repository analysis, and unit
  tests.
- `make RUNTIME_ARCH=arm64 developer-jit-build release-aot-build`: passed with
  fingerprint v7, manifest v9, clean official SDK/Engine evidence, clean
  `dart_appkit` revision `a70e5e4`, and protocol version 2 in both manifests.
- Developer JIT and Release AOT bundle audits passed with arm64 slices, strict
  ad-hoc signatures, expected payload separation, and valid manifest schema.
- Developer JIT and Release AOT integration smoke passed in 2466 ms and
  1723 ms respectively. Both required the real v2 close-event observation.
- A final post-format rerun of `runtime-source-check`, both arm64 integration
  smoke targets, and both bundle audits passed after the test-only diagnostic
  was gated behind `DT_RUNTIME_EVENT_WIRE_TEST=1`.
- Developer clean-SDK freshness passed with 9 stable no-op and 9 regeneration
  cases. Release clean-SDK freshness passed with 19 stable no-op and 19
  regeneration cases plus worker/layout/executable/tamper/signature/override
  rejection cases.
- The adjacent official Dart Engine checkout remained clean after builds,
  audits, integration, and freshness tests.

## Completion review

- All nine acceptance criteria are satisfied. The current native/Dart pair
  negotiates v2, both compatibility directions retain v1, rejected envelopes
  become deterministic stream errors, and the two product modes use the same
  native encoder and real-event observation contract.
- Final source, staged-diff, repository, adjacent dependency, and generated SDK
  hygiene checks found no unrelated tracked edits or generated source files.
- No follow-up roadmap item was added. The existing handle-registry task remains
  the next unchecked item and was not started.
