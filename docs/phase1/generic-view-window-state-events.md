# Generic View and window-state events

- Status: in progress
- Started: 2026-09-04
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, ADR-001, ADR-002, `dart_appkit`
  bridge/API/event codec

## Purpose

Turn the hello-window-only `TextView` surface into a reusable AppKit
substrate. Dart must be able to own and attach a generic view, and must receive
stable asynchronous window focus, visibility, occlusion, backing-scale, and
screen state changes without exposing Objective-C objects or AppKit enum
layouts.

## Background

The reusable bridge currently has only window and text-view object kinds.
`da_window_set_content_view` accepts an exact text-view handle and the public
Dart `Window.contentView` property is typed as `TextView`. Native events
currently cover close, resize, mouse, and key input. Protocol v2 added source
generation, nanosecond time, and operation identity, but deliberately left the
state events in this task out of scope.

The later terminal renderer needs a reusable view supertype and window state
signals for frame scheduling, scale-dependent resource rebuilds, and display
migration. This task supplies only those generic primitives. It does not
create or attach a terminal-specific Metal view.

## Scope

- Add a concrete generic `View` backed by a generic `NSView` subclass and a
  distinct registry kind in `dart_appkit`.
- Make `TextView` a `View` subtype while preserving its create/text API and
  allow either kind to be borrowed as `Window.contentView`.
- Preserve exact-kind rejection for text-only operations and all existing
  generation, domain, release, finalizer, and shutdown rules.
- Add immutable focus, visibility, occlusion, backing-scale, and screen events
  to the reusable native model, shared encoder, Dart decoder, public streams,
  and cached window state.
- Emit an initial state snapshot after a window is shown, then emit changed
  states from AppKit delegate callbacks without synchronous Dart re-entry.
- Give screen events a process-stable display identifier plus full and visible
  rectangles; represent a window with no associated display explicitly.
- Introduce event protocol v3 for the new event types while retaining exact
  v1/v2 layouts and suppressing v3-only events for older negotiated endpoints.
- Consume the updated reusable package from Dart Terminal, handle every new
  sealed event type, and prove real v3 state and close delivery in both
  M1/arm64 Developer JIT and Release AOT products.

## Out of scope

- The following menu, pasteboard, application/window lifecycle API item.
- A `TerminalMetalView`, external/custom native subclass registration,
  Metal/CoreText resources, display links, frame scheduling, or IME.
- Terminal focus-report byte encoding, pane focus traversal, native tabs,
  splits, fullscreen, restoration, and screen-selection policy.
- Color-space/HDR/refresh-rate modeling or global display attach/detach
  enumeration.
- Changing view attachment into ownership transfer or weakening AppKit-main
  thread affinity.
- The later unified logging, crash metadata, broad resource-leak, and shutdown
  fault-injection items.
- x86_64, Rosetta, Universal, or Intel-native follow-up work.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `35eecce` and clean `dart_appkit`
  HEAD `9815e77`. The adjacent official Dart SDK/Engine checkout was clean at
  the preceding task boundary.
- This is the first unchecked roadmap item. No later Phase 1 item has been
  started.
- `ObjectRegistry` records an exact object kind, generation, and AppKit-main
  domain. Its lookup must gain an explicit subtype rule so `TextView` can be
  borrowed as `View` without being accepted by text-only calls.
- Attaching a content view currently borrows both handles. `NSWindow` may keep
  the native view alive after its registry lease is released; that ownership
  rule remains unchanged.
- The current pair negotiates protocol v2. Reusing v2 for new event types would
  cause an existing v2 Dart decoder to surface unknown-type errors when a
  current native bridge posts the new show-time snapshot.
- The macOS 14 minimum provides the required `NSWindowDelegate` callbacks and
  `backingScaleFactor`/`occlusionState` properties. The local macOS SDK confirms
  focus, miniaturization, screen, backing-property, and occlusion callbacks.
- `NSWindow.occlusionState` reports whether any part is visible. Public
  occlusion semantics will expose the inverse `isOccluded` boolean.
- Visibility in this API means ordered, user-visible window content:
  `window.isVisible && !window.isMiniaturized`. It is separate from focus and
  from coverage by other windows.
- A display identifier will be read from the conventional
  `NSScreenNumber` device-description entry as an unsigned 32-bit value. Zero
  is reserved for the explicit no-screen event representation.

## Design decision

Use one native `DaView : NSView` base with flipped coordinates, autoresizing,
and first-responder support. `DaTextView` subclasses it. The registry keeps
generic and text view as distinct actual kinds and implements only one
is-a relationship: text view satisfies an expected generic view; a generic
view never satisfies an expected text view.

Protocol v3 keeps the six-field v2 common prefix. Existing close/resize/input
records retain their payloads in all three versions. Focus, visibility,
occlusion, backing-scale, and screen event types are valid only in v3.
Negotiated v1/v2 sinks drop those events before invoking their poster, so old
decoders continue to receive only event types they understand.

The window owner tracks the last posted state. `show` requests an initial
snapshot after ordering the window front; delegate callbacks publish later
transitions. Focus, visibility, occlusion, and scale events carry normalized
booleans/scalars. A screen event carries an explicit presence flag, display
identifier, full frame, and visible frame in AppKit global point coordinates.
Dart caches the latest values but application policy remains outside the
bridge.

## Ordered subtasks

### 1. Generic View boundary

- Add native/Dart generic view types, subtype-aware registry lookup, create
  binding, and generic content-view attachment.
- Add native, fake-binding, Dart API, C/C++ header, FFI, and compatibility
  coverage. Update reusable API/ownership documentation.
- Completion: `View` and `TextView` both attach, text-only calls remain
  exact-kind, disposal/generation/domain behavior is unchanged, the full
  `dart_appkit` suite and Dart Terminal source checks pass, and this subtask is
  committed before starting subtask 2.

### 2. Versioned window-state events

- Add protocol v3 and all five state event families atomically across native
  capture, version filtering, shared serialization, Dart decoding, public
  streams/state, fake backend, and documentation.
- Cover initial snapshot, transition deduplication, absent screen, malformed
  payloads, exact v1/v2 compatibility, v3 serialization, and older-endpoint
  suppression.
- Completion: the full `dart_appkit` suite passes, v1/v2 fixtures retain their
  exact records, current clients negotiate v3, and reusable changes are
  committed before product integration begins.

### 3. M1 product integration and acceptance

- Update Dart Terminal's exhaustive event routing, build provenance/manifest
  expectations, smoke observation, README/feature status, and local dependency
  baseline.
- Build and audit both arm64 modes and require real show-time focus,
  visibility, occlusion, backing-scale, screen, and close events in the common
  integration harness.
- Completion: source checks, both builds/audits, relevant lifecycle/freshness
  gates, and final repository/SDK hygiene pass; all three subitems and their
  parent are checked and the terminal-side completion record is committed.

Subtasks are strictly ordered. Subtask 2 depends on the generic view-compatible
window owner from subtask 1. Subtask 3 depends on a clean committed reusable
revision from subtask 2.

## Acceptance criteria

1. `View()` creates one generic AppKit-main-domain handle and can be attached
   as a window content view without transferring either handle.
2. `TextView` is publicly usable wherever `View` is expected and retains its
   existing text behavior; generic views are rejected by text-only native
   operations.
3. Stale, wrong-kind, wrong-domain, double-release, finalizer, and shutdown
   behavior remains deterministic.
4. Protocol v3 uses the v2 six-field prefix and assigns stable event type and
   payload layouts for every new state event.
5. A v1/v2 registrant receives unchanged old records and no v3-only event. A
   current pair negotiates v3 and decodes old and new records.
6. Showing a window produces a complete current-state snapshot. Repeated
   identical delegate notifications do not create duplicate state events.
7. Focus reports key-window state. Visibility excludes miniaturized/ordered-out
   content. Occlusion reports full coverage independently of visibility.
8. Backing scale is finite and positive. Screen data is either explicitly
   absent or has a positive display ID and finite full/visible rectangles.
9. Dart routes every event by generation-safe window handle, exposes typed
   streams, and updates cached state before observers receive the event.
10. Native callbacks only post immutable data and never synchronously enter
    Dart or wait on a worker/render operation.
11. Developer JIT and Release AOT share the same encoder, advertise protocol
    v3 in provenance, and observe the real state snapshot plus close event.
12. Formatting, analysis, C11/C++20 header checks, native/Dart/FFI tests,
    M1/arm64 product validation, diff review, and repository/SDK hygiene pass.

## Validation plan

- Run focused native bridge, encoder, Dart API, FFI, format, and analysis
  checks after each reusable subtask, followed by `make test`.
- Exercise exact old record layouts and v3-only filtering with deterministic
  poster fixtures; send malformed Dart lists for each new payload.
- Run Dart Terminal `runtime-source-check` at each integration boundary.
- For final acceptance, build/audit Developer JIT and Release AOT, run normal
  integration smoke in both modes, run lifecycle and clean-SDK/freshness gates
  affected by provenance changes, and inspect exported symbols.
- Confirm terminal, reusable dependency, and official SDK worktrees are clean
  after task-scoped commits.

## Risks and open checks

- AppKit delegate notification ordering around `makeKeyAndOrderFront:` is not
  guaranteed to match the snapshot order. Per-state deduplication must make
  both orders equivalent.
- `isVisible` alone does not distinguish a miniaturized window for the product
  scheduling meaning; the normalized definition must be used consistently.
- A backing-property notification can indicate only a color-space change.
  Scale events must be deduplicated against the cached scale.
- A window can temporarily have no screen. The wire record and Dart API must
  represent that state without fabricating a display.
- Signed Dart integer/event slots must preserve the unsigned 32-bit display ID.
- Adding sealed Dart event subtypes makes product switches intentionally
  exhaustive; all consumers must be updated in the product-integration
  subtask.

## Investigation log

### 2026-09-04 — repository, ABI, and AppKit review

- Re-read the repository rules, README, complete roadmap, complete feature
  matrix, Phase 1 exit conditions, ADR-001, ADR-002, prior event/registry task
  records, both repository inventories, and both clean worktrees.
- Traced the native registry kinds, content-view lookup, text view subclass,
  event sink, shared v1/v2 encoder, Dart FFI facade, decoder, weak window
  routing, fake backend, product event switch, build inputs, manifest version,
  and smoke assertion.
- Confirmed from the local AppKit SDK headers that `NSWindowDelegate` exposes
  become/resign key, miniaturize/deminiaturize, screen change, backing-property
  change, and occlusion-state change callbacks on the supported deployment
  range.
- Rejected adding new event types to protocol v2 because an already deployed
  v2 decoder treats an unknown type as a stream error. Selected a v3 bump with
  native suppression for older negotiated sinks.
- Rejected treating `TextView` as a generic registry kind because that would
  either make text-only calls accept arbitrary views or require Objective-C
  runtime type checks outside the registry contract. Selected explicit
  registry subtype matching.
- Split the work before implementation because the generic ownership boundary,
  versioned event contract, and two-mode product acceptance are independently
  reviewable and have strict dependencies.

## Implementation and validation log

### 2026-09-04 — Subtask 1: generic View boundary

- Added native `DaView` and public Dart `View` base types. `DaTextView` and
  `TextView` now inherit those bases while retaining the existing constructor,
  text property, drawing behavior, and finalizer/disposal contract.
- Added additive `da_view_create` and `NativeBindings.viewCreate` APIs.
  `FfiNativeBindings` resolves the new symbol optionally so loading a legacy
  bridge remains possible; `View()` reports stable unsupported-version status
  only when the old bridge lacks the additive operation.
- Added `ObjectKind::kView` and one explicit registry subtype match from text
  view to generic view. `da_window_set_content_view` now borrows either view
  kind; `da_text_view_set_text` still rejects generic views, and all view
  lookups reject window handles.
- Changed `Window.contentView` to `View?`. Existing assignments of `TextView`
  remain source-compatible, and the Dart wrapper continues holding the
  attached view strongly without transferring its native handle lease.
- Updated reusable README, architecture, C ABI, and worklog records. No
  terminal-specific custom view, renderer, event, or later lifecycle API was
  introduced.

Validation:

- Focused `make validate`, `make native-test`, and `make dart-test` passed.
  Native coverage exercised both creation/attachment paths, subtype and
  exact-kind rejection, live counts, stale handles, and release.
- The complete `dart_appkit` `make test` passed C11/C++20 headers,
  warning-as-error bridge and Runner builds, registry/event/message-pump tests,
  Dart analysis/API/launcher tests, example Kernel compilation, real-dylib FFI,
  and the legacy bridge fallback.
- The built dylib exports 19 `da_*` symbols including `da_view_create`.
  The legacy fixture loads without that symbol and returns unsupported only
  for generic-view creation.
- Dart Terminal `make runtime-source-check` passed formatting, native header
  checks, plist lint, analysis, and unit tests against the changed public type
  hierarchy.
- The reusable implementation was committed as
  `62d0537a09f75320318542b2d3438134183ac215`
  (`Introduce generic AppKit views`). Its worktree was clean immediately
  afterward.

### 2026-09-04 — Subtask 2: versioned window-state events

- Raised the independently negotiated current event protocol to v3 while
  preserving the v1 four-field and v2 six-field prefixes and every existing
  close/resize/input payload. The sink and encoder reject v3-only state events
  for older selected protocols before calling the Dart poster.
- Added immutable native focus, visibility, occlusion, backing-scale, and
  screen records. `DaWindowOwner` emits a complete snapshot after show,
  translates the corresponding `NSWindowDelegate` callbacks, and deduplicates
  each state only after a successful post.
- Screen records explicitly distinguish no screen from a present display and
  carry the positive `NSScreenNumber` identifier plus finite full and visible
  frames. Invalid scale and screen values fail closed in both the shared
  encoder and Dart decoder.
- Added public Dart state event classes, `AppKitScreen`, per-window typed
  streams, and cached state. A window applies each state before either the
  application-level or window-level synchronous observer receives it.
- Updated the reusable README, architecture, C ABI, verification matrix,
  worklog, and hello example. The C ABI remains version 1 and the dylib still
  exports exactly 19 `da_*` symbols.

Validation:

- Focused native bridge, exact encoder, and Dart API tests passed. Coverage
  includes snapshot completeness, per-state deduplication, explicit no-screen,
  v1/v2 suppression, exact v1/v2 legacy payloads, v3 serialization, malformed
  payloads, and state-before-observer ordering.
- The first native build found an Objective-C nullability completeness warning;
  the inconsistent internal annotation was removed. The first encoder run had
  retained v3 as the unsupported-version probe; it was corrected to v4. The
  first complete suite found C/C++ header assertions still fixed at v2; both
  were updated to v3. These failed attempts and causes are also recorded in
  `../../../dart_appkit/docs/WORKLOG.md`.
- The corrected full `dart_appkit` `make test` passed all native, Runner,
  encoder, Dart, launcher, Kernel, FFI, and legacy-bridge checks. The native
  bridge suite then passed ten consecutive runs.
- The real hello-window smoke negotiated v3, observed all five AppKit state
  families, auto-closed, released native handles, and exited successfully.
  Final formatting and whitespace checks passed.
- The reusable implementation was committed as
  `be09f1a8e8f9d867cdf8d255fd40586fc9df5cc2`
  (`Add versioned window state events`). Its worktree was clean immediately
  afterward.
