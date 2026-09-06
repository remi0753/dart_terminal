# Phase 5 — NSTextInputClient and preedit overlay

- Status: in progress
- Date: 2026-09-06
- Scope: second Phase 5 production-input roadmap item
- Related: IN-01, IN-03, IN-04, ADR-001, ADR-003

## Purpose

Give the production Metal terminal view a real AppKit text-input client that
supports marked-text updates, commit, cancellation, replacement/selection
ranges, and candidate-window placement without mixing composition with raw
terminal keys. Render preedit as transient overlay state without mutating the
canonical PTY screen.

## Background

The accepted Phase 0 spike proved the ownership model on real arm64 hardware,
but its native view was deliberately removed with the spike. The current
product window uses Dart-only key routing: `DaWindow` posts a raw key and does
not call AppKit's responder chain. The product `DtrTerminalMetalView` is an
`MTKView` with no `NSTextInputClient`, marked-text state, candidate geometry, or
input event channel. Its compositor only consumes canonical terminal damage.

ADR-001 requires AppKit callbacks and synchronous candidate lookup to remain on
the native main thread, using the newest Dart-published caret geometry rather
than synchronously entering Dart. ADR-003 classifies IME preedit as overlay
state outside packed terminal cells.

## Scope

- Add an AppKit-first-responder-only window routing mode without regressing the
  existing Dart-only and combined modes or native menu key equivalents.
- Implement the required `NSTextInputClient` surface on the native terminal
  Metal view with bounded marked text, exact UTF-16 ranges, deterministic
  composition generations, and synchronous cached candidate geometry.
- Deliver immutable raw/preedit/commit/cancel events asynchronously to Dart
  through a bounded native queue and one scalar notification callback.
- Add a bounded Dart composition model and overlay layout based on Unicode 17
  grapheme/column width, including wrapping and selected preedit position.
- Shape/raster/submit preedit glyphs and underline through the existing CoreText,
  atlas, and Metal pipeline without changing terminal screen content.
- Route raw events through the mode-aware key router, commits once to the PTY,
  and suppress raw bytes while composition is active.

## Out of scope

- Changing the user's selected input source or automating the visible Japanese
  candidate UI; the following US/JIS/dead-key/CJK/emoji/repeat matrix owns that
  system-level/manual coverage.
- Replacement of arbitrary editable terminal history. Replacement ranges are
  preserved and validated as input-method metadata; commits remain insertion at
  the terminal cursor because the terminal is not an editable document.
- Mouse, selection, clipboard, Secure Input, accessibility, Kitty keyboard, and
  settings/configuration UI.

## Ordered subtasks

1. Add the reusable native/AppKit boundary: first-responder-only window routing,
   bounded `NSTextInputClient` state/event transport, cached candidate geometry,
   and native/Dart capability tests.
2. Add the bounded Dart preedit state/layout and CoreText/Metal overlay, publish
   current caret geometry, and cover grapheme, wrapping, range, redraw, and
   resource-limit behavior with deterministic tests.
3. Integrate the text-input stream into the live pane router, prove raw versus
   composition single-delivery and commit/cancel behavior through real AppKit
   and PTY paths in Developer JIT and Release AOT, then update product docs.

The parent roadmap item remains incomplete until all three subtasks and their
combined product verification pass.

## Dependencies and ownership

- `dart_appkit` owns window responder routing. Its roadmap does not constrain
  the project-required API change, per the user instruction.
- `dart_terminal_renderer_macos` owns the native `MTKView`, text input context,
  native marked string, event queue, and cached screen-coordinate conversion.
- Dart owns composition policy, terminal Unicode layout, overlay resources, and
  PTY routing. Native callback code may only notify that a bounded queue has
  data; it must not synchronously execute Dart logic or retain Dart memory.
- The canonical `TerminalScreen` remains unchanged by preedit. Commit is the
  only composition event that writes text to the pane.

## Completion criteria

- A live `DtrTerminalMetalView<NSTextInputClient>` becomes first responder and
  exposes valid marked/selected range, attributed substring, commit, cancel,
  command/raw handling, and candidate rect behavior.
- Input payloads, queue depth/bytes, UTF-8 decoding, ranges, generations, client
  IDs, and cached geometry generations are versioned, validated, and bounded.
- Candidate lookup returns immediately from finite positive cached geometry and
  never makes a synchronous Dart callback.
- Preedit handles narrow, wide, combining, emoji, multiline/control sanitizing,
  right-edge wrap, and selection offsets without editing the terminal grid.
- Raw key, marked update, commit, and cancel have mutually exclusive effects;
  key-up and menu shortcuts do not create duplicate PTY input.
- Focused native/Dart tests, full tests, source audits, real-window/PTY acceptance,
  both arm64 product modes, and bundle audits pass with clean repositories.

## Verification plan

- Extend `dart_appkit` bridge tests for all key-routing modes and menu priority.
- Add native capability tests that drive the actual `NSTextInputClient` methods,
  bounds/overflow, queue ordering/coalescing, stale geometry, candidate
  round-trip, and teardown.
- Add Dart decoder/controller tests for malformed packets, bounds, ordering,
  late client events, and disposal.
- Add pure-Dart preedit layout and compositor tests with CPU-readable instance
  assertions and unchanged canonical screen snapshots.
- Extend product application acceptance to use the registered native view and a
  real PTY for raw, preedit/update, commit, cancel, and candidate geometry.

## Investigation log

- 2026-09-06: the preceding keyboard/keybinding task was committed as
  `01cb40a`; both `dart_terminal` and adjacent `dart_appkit` were clean before
  this task began. ROADMAP identifies this as the first unchecked item.
- 2026-09-06: Phase 0 accepted marked/update/commit/cancel, exact candidate
  conversion, composition-time raw suppression, and a 4 ms callback ceiling.
  It explicitly requires native cached geometry and asynchronous events.
- 2026-09-06: current `KeyEventRouting.dartOnly` consumes key events in
  `DaWindow.sendEvent` after menu lookup, so the first responder cannot invoke
  an input context. The combined mode posts raw input before AppKit delivery and
  would duplicate composition. A third first-responder-only mode is required.
- 2026-09-06: the renderer native extension already creates the exact product
  `DtrTerminalMetalView`, and the custom-view operation can carry configuration
  and geometry without exposing Objective-C objects. A scalar-only
  `NativeCallable.listener` notification plus an owned bounded native packet
  queue avoids pointer lifetime hazards and synchronous Dart re-entry.
- 2026-09-06: the frame format already orders selection, glyph, decoration, and
  cursor layers. Preedit can reuse glyph and decoration instances, but must be a
  separately versioned input to frame building because it is not terminal
  damage.

## Design decisions

- Preserve AppKit UTF-16 selection and replacement indices at the event
  boundary; derive grapheme/column positions in Dart after validating that
  indices do not split surrogate pairs.
- Bound one text payload to 64 KiB UTF-8, one client queue to 256 events and
  1 MiB, and coalesce adjacent marked updates to the newest generation. Queue
  overflow becomes an explicit reset/error event rather than unbounded growth.
- Use the latest published caret rectangle for synchronous native candidate
  queries. Geometry updates carry a monotonic generation so stale publication
  is ignored and observable in tests.
- Keep ordinary key encoding out of native code. The view emits normalized raw
  event fields only when the input context declines or maps an unhandled command;
  Dart remains the sole keybind and terminal-protocol owner.

## Verification results

### 2026-09-06 — reusable AppKit and native text-input boundary

- Added `KeyEventRouting.appKitOnly` without changing the existing numeric
  values for combined or Dart-only routing. Native bridge tests prove that this
  mode does not pre-post key events to Dart, does deliver key down/up to the
  first responder, and still consumes a native main-menu equivalent first.
- The registered product `DtrTerminalMetalView` now conforms to
  `NSTextInputClient`, accepts first responder, owns bounded attributed marked
  state and UTF-16 selection, returns clipped attributed substrings, commits or
  cancels separately, suppresses raw events while marked, and emits normalized
  raw fields only outside composition.
- Added versioned attach/detach and monotonic geometry custom-view operations.
  Candidate lookup converts the newest finite positive local caret rectangle to
  screen coordinates synchronously; stale geometry generations succeed as a
  no-op and cannot replace the cache.
- Native events are immutable copied packets. Each text region is capped at
  64 KiB UTF-8. Each client queue is capped at 256 events and 1 MiB, coalesces
  adjacent preedit updates, and collapses resource exhaustion into one explicit
  overflow/reset event. A callback carries only the client ID and returns before
  Dart's `NativeCallable.listener` schedules a bounded 32-event drain turn.
- The Dart packet decoder validates magic/version/size/client identity,
  canonical contiguous regions, strict UTF-8, supported flags/modifiers,
  monotonic generations, reserved fields, uint32 ranges, event-specific fields,
  and UTF-16 surrogate boundaries before advancing retained state. Tests cover
  every event family, coalesced generation gaps, malformed atomic rejection,
  public transport limits, and not-found versus empty ranges.
- Native renderer capability tests drive the actual marked/update/substring/
  candidate/commit/cancel/raw methods, screen-to-local candidate round-trip,
  stale geometry, oversize input, 257-event overflow, queue consumption, and
  leak-free detach. The renderer native capability and Dart tests passed.
- The first `make test` output exceeded the tool's initial 30-second yield after
  reaching Dart package analysis, so it did not provide a final status. The
  cached rerun completed with exit 0 in 21.5 seconds: scaffold, all bridge/
  runtime/renderer/PTY native contracts, all Dart package analysis/tests,
  launcher tests, examples, FFI smoke, and legacy bridge smoke passed.
- The reusable boundary subtask is complete in adjacent `dart_appkit`. The next
  subtask is the Dart-owned composition model, overlay, and geometry publication;
  product routing remains intentionally unchanged until that layer exists.

### 2026-09-06 — bounded Dart preedit and Metal overlay

- Added an immutable composition model capped at the native 64 KiB UTF-8 text
  limit and 64 Unicode scalars per grapheme. It preserves validated AppKit
  UTF-16 selection offsets, rejects surrogate-splitting ranges, ignores stale
  generations, sanitizes C0/C1 and line-separator controls to replacement
  glyphs, and gives a standalone zero-width cluster a visible dotted-circle
  base.
- Layout uses the terminal's Unicode 17 grapheme breaker and column-width
  policy. Wide clusters wrap before the right edge, selected UTF-16 ranges map
  to whole visible clusters, a caret inside a grapheme snaps after that
  grapheme, and content beyond the fixed viewport is clipped without entering
  scrollback or changing packed screen cells.
- The Metal compositor receives preedit as a separate, optional frame input.
  It batches adjacent visible clusters into CoreText runs, reuses the existing
  shaping cache/glyph atlas, draws selection behind glyphs, draws marked-text
  underlines above glyphs, and replaces the terminal cursor with a composition
  bar caret for the duration of preedit. The existing layer-order contract and
  renderer instance limit remain authoritative; over-limit frames fail before
  submission rather than becoming partial frames.
- The live surface owns the monotonic preedit model, requests a redraw for each
  accepted update/clear, and publishes a finite positive local-view caret cell
  rectangle only when its geometry changes. Native candidate lookup can consume
  this without a synchronous callback into Dart. Backing scale stays out of the
  logical AppKit rectangle; native performs the existing view/window/screen
  conversion.
- Pure tests cover narrow, wide, combining, emoji ZWJ, controls, standalone
  marks, pathological extending clusters, UTF-8/range limits, right-edge wrap,
  viewport clipping, selection/caret mapping, and monotonic state. Metal tests
  verify selected background, preedit glyph/underline/caret layers, an
  unchanged canonical screen, CPU-readable rendering, and deterministic
  renderer-instance exhaustion.
- A proposed source-test-only live-surface test could not call
  `TerminalRendererMacos.initialize()` because a plain `dart` source process
  has no bundled native-capability manifest. It was removed rather than adding
  a false test environment. The next product-integration subtask owns the same
  redraw/caret path inside Developer JIT and Release AOT bundles, where the
  manifest and registered custom view exist.
- `dart test/terminal_preedit_test.dart` passed. The compositor test initially
  reported `deviceUnavailable` inside the restricted sandbox, then passed with
  real GPU access. `make test` passed with 114 formatted files, zero analyzer
  issues, and the complete Dart/native Metal/PTY suite. `git diff --check`
  passed, and a source audit found no FFI/pointer/native operation in the Dart
  model/compositor/live-surface additions.
- This second subtask is complete. Product key routing remains Dart-only and no
  text-input stream is attached yet; the final subtask must wire the native
  event stream, publish this surface geometry to its client, and prove
  mutually-exclusive raw/commit/cancel behavior through a real PTY.
