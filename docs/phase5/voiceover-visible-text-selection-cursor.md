# Phase 5 — VoiceOver visible text, selection, and cursor

## Task identity

- Date started: 2026-09-06
- Scope: final Phase 5 production-input roadmap item
- Status: in progress
- Ordered subtasks:
  1. build a bounded UTF-16 accessibility snapshot from the current viewport,
     local selection, and cursor;
  2. expose that snapshot through the native `TerminalMetalView` AppKit
     accessibility contract and send change notifications;
  3. synchronize the real product surface and prove both-runtime VoiceOver
     acceptance.

## Purpose and background

Expose the same visible terminal content that the Metal renderer shows as one
read-only, navigable AppKit text element. VoiceOver must be able to read the
visible prompt and output, inspect the local selection, and locate the terminal
cursor without introducing a second mutable terminal model or blocking the
AppKit main thread.

This is the last ordered Phase 5 task. Completing it must also satisfy the
phase exit condition that keyboard-only and VoiceOver users can reach the
prompt, selection, and visible output. The current custom Metal view is already
the first responder and implements `NSTextInputClient`, but it exposes no
terminal text through `NSAccessibility`.

## Scope

- Project only the currently visible viewport, including primary scrollback or
  alternate-screen rows, into a bounded immutable UTF-16 text document.
- Preserve Unicode scalar, grapheme, combining-mark, emoji, and wide-cell
  boundaries while mapping physical row/column coordinates to UTF-16 ranges.
- Report a visible local selection as one clipped text range. When there is no
  nonempty selection, report the visible cursor as a collapsed selected range.
- Report the cursor line and a screen-space bounding rectangle derived from
  the same cell metrics and top-left coordinate system used by the Metal view.
- Make `TerminalMetalView` one read-only text-area accessibility element with a
  stable label, value, visible range, selection, cursor/insertion line, line and
  substring navigation, range geometry, and focused state.
- Copy and atomically validate each complete snapshot at the native boundary.
  Reject malformed UTF-8/UTF-16 ranges, non-monotonic generations, inconsistent
  rows/columns, oversized packets, and out-of-range selection/cursor data.
- Post AppKit accessibility value, selection/cursor, and focused-element change
  notifications only when their corresponding state changes.
- Exercise a real PTY fixture, local selection, viewport/cursor state, native
  accessibility selectors, and notifications in Developer JIT and Release AOT.

## Out of scope

- Editable-document semantics, VoiceOver-driven text replacement, arbitrary
  selection mutation, command history navigation, or shell input through an
  accessibility setter. The terminal remains a read-only accessibility value;
  keyboard input continues through the existing first-responder path.
- Full scrollback as one virtual document, semantic prompt/command/output
  regions, custom rotors, live-region speech policy, links as accessibility
  children, per-style attributed text, tables, or images.
- Full Keyboard Access, Reduce Motion, Increase Contrast, Differentiate Without
  Color, and the complete Accessibility Inspector release checklist. Those are
  later Phase 10 work.
- Changing terminal selection ownership, clipboard semantics, canonical screen
  content, render damage, or the accepted AppKit/isolate ownership ADRs.

## Dependencies and confirmed facts

- `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, all five ADRs, the Phase 5
  selection/preedit notes, and both repositories were reviewed after hyperlink
  commit `ffe66ab`. The main and adjacent `dart_appkit` trees were clean.
- `TerminalViewport` is already the authoritative visible projection over
  primary history plus active grid. It provides current generation, visible
  cursor position, cell content/flags, stable anchors, and clipped selection
  spans, but it does not yet expose grapheme text or a UTF-16 document map.
- `TerminalSelectionGestureController` owns an immutable stable range and the
  live Metal surface already receives its generation and visible spans. This is
  the selection source; accessibility must not invent a separate selection.
- `TerminalLiveMetalSurface` already coalesces screen/viewport/selection changes
  outside AppKit callbacks, knows exact cell metrics, and owns the custom view.
  It is the correct synchronization point for a newest-only accessibility
  snapshot.
- The adjacent renderer capability owns `DtrTerminalMetalView : MTKView`, its
  existing `NSTextInputClient`, and the synchronous copied custom-view operation
  channel. Terminal-specific accessibility belongs there rather than in
  `dart_appkit`'s generic `View`.
- Apple's `NSAccessibilityProtocol` documentation says custom `NSView`
  subclasses customize getters for dynamic read-only properties and must post
  their own notifications for nonstandard controls. Its navigable-static-text
  contract requires string, line/range, and range-frame methods; frame results
  use screen coordinates. `valueChanged` must be posted through the
  accessibility posting API, not `NSNotificationCenter`.

Primary references:

- <https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol>
- <https://developer.apple.com/documentation/appkit/nsaccessibilitynavigablestatictext>
- <https://developer.apple.com/documentation/appkit/nsaccessibilitynavigablestatictext/accessibilityframe(for:)>
- <https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/valuechanged>

## Design decisions

### Visible document and bounds

- The snapshot contains only physical viewport rows. Rows are separated by one
  newline so VoiceOver line navigation matches what is visually on screen,
  including soft-wrapped rows. Trailing blank cells are omitted unless needed
  to represent the cursor or visible selection.
- Every row carries its document UTF-16 range and a monotonic UTF-16 boundary
  for each represented terminal column. Continuation cells share their lead
  grapheme boundary; the boundary after a wide cell reaches the full grapheme.
  Native geometry therefore never splits a surrogate pair or combining cluster.
- Capture and wire formats have explicit row, cell-boundary, UTF-8, UTF-16, and
  total-byte limits. Product-sized 4096-pixel viewports fit comfortably; an
  impossible oversized snapshot is rejected as unavailable rather than partly
  publishing inconsistent text.

### Ownership and update policy

- Canonical terminal and selection state remain Dart-owned. The native view
  receives one fully copied, validated immutable snapshot. It never calls Dart
  synchronously from an accessibility selector and therefore cannot re-enter
  the UI isolate or observe a half-updated screen.
- Generations are strictly increasing for changed snapshots. Identical state is
  not resent. The live surface refreshes accessibility during its existing
  bounded newest-state drain after screen, resize/reflow, viewport, selection,
  or cursor changes.
- Native replaces the complete snapshot atomically on the AppKit main thread.
  Value notifications are tied to text/layout changes; selection notification
  covers both nonempty selection and collapsed cursor movement; focused-element
  notification follows first-responder focus transitions.

### Read-only accessibility semantics

- The Metal view exposes one terminal-labelled text-area element. It provides
  getters but no accessibility text/selection setters, so assistive clients can
  inspect but cannot mutate shell state through an accidental editable-control
  path.
- `accessibilityValue`, `accessibilityVisibleCharacterRange`, selected text and
  range, character count, insertion-point line, substring/range/line queries,
  point lookup, and range frames are all derived from the same copied snapshot.
  Invalid client ranges return safe empty/not-found values without exceptions.

## Completion conditions

- The core snapshot deterministically represents visible ASCII, CJK, combining,
  emoji, wide cells, soft/hard wraps, blank extents, history/alternate viewports,
  clipped forward/reverse selection, visible/offscreen/hidden cursor, and resize.
- Every public UTF-16 range is scalar/grapheme-safe and maps back to the expected
  visible row/cell geometry without unbounded scanning or allocation.
- Native selector tests prove role/label/value/focus, visible and selected
  ranges/text, cursor line, line/index/point/range queries, screen-space frames,
  generation monotonicity, atomic malformed-input rejection, bounds, and exact
  change-notification categories.
- The real product publishes a PTY-produced visible prompt/output, selection,
  and cursor through the actual `TerminalMetalView` in both runtime modes while
  keeping terminal text out of machine logs and diagnostics.
- Full repository/runtime verification passes, matrix/overview/roadmap and this
  memo are current, and Phase 5 has no unchecked item.

## Verification plan

- Core unit tests for document text, per-row UTF-16 boundaries, grapheme/wide
  topology, selection and cursor mapping, history/alternate projection, limits,
  stale selection, hidden cursor, and unchanged/change generation behavior.
- Renderer Dart tests for deterministic packed encoding and all malformed
  ranges/limits; native capability tests for validation, selectors, geometry,
  focus, notifications, and lifecycle reset.
- Product display acceptance with fixed markers and content-free booleans/counts,
  followed by Developer JIT and Release AOT integration, source/bundle audits,
  smoke, resource, lifecycle, shutdown, and full `runtime-verify`.

## Investigation and implementation log

### 2026-09-06 — task start and decomposition

- Re-read the ordered roadmap after `ffe66ab`; VoiceOver is the only remaining
  Phase 5 item and Phase 6 must not start in this session.
- Confirmed there is no current accessibility implementation in either product
  or renderer capability. `TerminalMetalView` is already the live window content
  view, a first responder, top-left/flipped, and the native owner of text-input
  geometry, making it the single accessibility element rather than a hidden
  `TextView` mirror.
- Compared a generic `dart_appkit` API, a second AppKit text view, synchronous
  native-to-Dart callbacks, and a copied renderer-owned snapshot. The copied
  snapshot was selected: it preserves the existing terminal-specific capability
  boundary, does not add a second view/render source, and keeps AppKit selectors
  non-reentrant.
- Split the task before source implementation because core UTF-16 projection,
  native selector/notification behavior, and product acceptance are separately
  reviewable artifacts with ordered dependencies.

## Verification results

Pending.
