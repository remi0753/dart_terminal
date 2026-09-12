# VoiceOver and Accessibility Inspector pass

## Status

- Phase: 10
- Task: complete VoiceOver/Accessibility Inspector pass
- Started: 2026-09-12
- State: in progress
- Current subtask: product projection, both-runtime acceptance, manual
  checklist, and parent completion decision
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Complete the release-facing VoiceOver and Accessibility Inspector pass on top
of the bounded Phase 5 terminal text-area implementation. The first ordered
correction makes accessibility point hit-testing and UTF-16 range frames use
the exact same effective configured-padding origin as Metal, pointer routing,
and IME caret geometry.

## Background and confirmed facts

- Phase 5 already publishes visible UTF-16 text, physical-line/terminal-column
  boundaries, selection, cursor, logical cell metrics, focus, and change
  notifications through one copied native snapshot. Accessibility selectors do
  not synchronously enter Dart.
- Phase 8 added horizontal and vertical terminal padding. Metal composition,
  pointer/caret routing, PTY grid sizing, and IME candidate geometry use the
  pane-local effective padding. Effective padding contracts symmetrically when
  a pane becomes smaller than twice the configured inset.
- The renderer accessibility snapshot currently carries cell width and height
  but no content origin. Native `accessibilityRangeForPosition:` divides the
  view-local point directly by cell metrics, while
  `accessibilityFrameForRange:` starts frames at view-local `(0, 0)`. Both are
  therefore displaced whenever configured padding is nonzero.
- The adjacent `dart_terminal_renderer_macos` package owns the terminal-specific
  native view and packet validation. The product manifest currently requires
  renderer capability ABI 10.
- Both the terminal and adjacent dependency worktrees were clean after commit
  `a2b3858`; that commit completed the preceding App Intents/notifications
  ROADMAP item and a full ROADMAP reread selected this task.

## Scope

- Extend the renderer accessibility snapshot with finite, nonnegative logical
  content-origin coordinates and validate them independently in Dart and
  native code.
- Apply that origin exactly once: subtract it for screen-point hit testing and
  add it for range/cursor frames. Points in padding or outside the terminal
  content rectangle return not-found rather than clamping into a cell.
- Publish the product's current effective horizontal/vertical padding alongside
  cell metrics and refresh accessibility state when a contracted origin changes
  during resize.
- Add Dart packet tests, native selector/geometry tests, product surface tests,
  and Developer JIT/Release AOT acceptance with nonzero configured padding.
- Publish an explicit VoiceOver/Accessibility Inspector and Full Keyboard
  Access manual release checklist, reconcile README/Feature Matrix/evidence,
  and decide the parent item only after all automated gates pass.

## Out of scope

- Editable accessibility text, full scrollback virtualization, custom rotors,
  semantic prompt/output regions, accessibility children for hyperlinks or
  Kitty images, or changes to terminal selection ownership.
- Reduce Motion, Increase Contrast, Differentiate Without Color, UI
  localization, and RTL UI. Those remain the next ordered ROADMAP item.
- Granting Accessibility permission, scripting VoiceOver/System Settings, or
  recording terminal content in logs. External observations remain manual and
  content-free.

## Dependencies and constraints

- Canonical text, selection, cursor, viewport, and padding policy remain
  Dart-owned. Native owns only a fully copied immutable snapshot and AppKit
  selector projection.
- Accessibility queries must stay synchronous over native-owned data and may
  not invoke Dart or allocate unbounded state.
- Logical content origin uses the same top-left/flipped view coordinate system
  and logical-point cell metrics already used by the renderer and IME.
- The renderer public capability ABI and operation-specific packet version must
  fail closed on unsupported layouts. Header C/C++ layout assertions, native
  malformed-input tests, package tests, and product manifest agreement are
  required.

## Ordered subtasks

1. **Renderer accessibility content-origin contract**
   - Add a versioned bounded origin to `dart_terminal_renderer_macos`, preserve
     explicit unsupported-version behavior, update native point/range geometry,
     and cover packet/layout/malformed/padding selectors in Dart and native
     tests. Update the dependency worklog, verification record, README, and
     ROADMAP; pass its exact full gate and commit independently.
2. **Product projection and both-runtime accessibility closure**
   - Publish effective padding from `TerminalLiveMetalSurface`, refresh on
     resize contraction, extend deterministic surface/product acceptance, run
     Developer JIT and Release AOT with nonzero padding, publish the manual
     release checklist, reconcile documentation/evidence, pass the exact full
     gate, and only then complete the child and parent ROADMAP items.

## Completion conditions

1. For zero and nonzero padding, point lookup, selection frame, and cursor frame
   resolve to the same logical cells and origin as Metal/pointer/IME geometry.
2. Padding-only points and points outside the content grid are not exposed as
   terminal characters; multi-line and collapsed ranges remain finite,
   positive, and screen-coordinate correct.
3. Initial publication and resize-driven effective-origin contraction/restore
   are monotonic, bounded, and notify only for actual accessibility geometry
   changes.
4. Dart/native validation rejects negative, non-finite, oversized, stale, and
   unsupported origin packets without replacing the prior snapshot.
5. Focused tests, dependency and consumer full gates, source/bundle audits,
   Developer JIT/Release AOT acceptance, manual checklist publication,
   documentation, and final diff review pass with clean ownership.

## Validation approach

- Dependency: C/C++ header layout checks, Dart encoding/validation tests,
  Objective-C++ native capability tests for zero/nonzero origin, padding misses,
  range/cursor frames, malformed packets, notifications, and teardown; then the
  exact dependency `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate.
- Consumer: focused accessibility snapshot/live-surface/configuration tests,
  Phase 7 evidence freshness, static analysis/formatting, and the exact main
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate.
- Runtime: both signed arm64 bundles run the ordinary display/configuration
  product acceptance with nonzero padding and content-free native selector
  assertions, followed by source and bundle audits.

## Findings and decision log

- A visual-only translation is insufficient: assistive hit testing would still
  select the wrong cell and returned screen frames would remain displaced.
  Content origin is therefore part of the copied accessibility geometry
  contract, not a native view-global setting or a second padding owner.
- Origin changes are value/geometry changes, not selection changes. They must
  participate in semantic publication deduplication and the native value-change
  notification comparison while leaving text and selection data unchanged.
- The first dependency focused run passed the C/C++ layout and native AppKit
  geometry suite, then the Dart aggregate correctly stopped because its direct
  native-asset smoke still required ABI 10 while the image now reports 11. The
  smoke expectation is part of this ABI unit and was advanced to 11; no loader
  compatibility check was bypassed.
- A native formatting probe first reached the Chromium-only `clang-format`
  wrapper on PATH and could not run outside a Chromium checkout. Xcode's real
  formatter was then located, but a whole-file dry-run reported thousands of
  pre-existing style differences across these legacy native files, so it is not
  a usable changed-lines gate. Warning-as-error C11/C++20/Objective-C++ builds,
  existing file style, and final diff review remain authoritative.
- The dependency exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes
  the scaffold, C11/C++20 headers, native bridge/Runner/runtime, renderer ABI 11
  and AppKit geometry, AppleScript, App Intents, PTY, every Dart package
  analysis/test, Kernel build, and current/legacy FFI gates.
- Dependency commit `c65a2ef` (`Align terminal accessibility geometry with
  padding`) contains the renderer ABI 11/snapshot v2 contract, native geometry,
  tests, and dependency documentation. A complete post-commit ROADMAP reread
  kept product projection and accessibility closure as the next ordered unit.

## Handoff and remaining work

- The renderer content-origin contract is complete and committed in the
  dependency. Product projection, both-runtime acceptance, the manual release
  checklist, documentation/evidence reconciliation, and parent completion are
  the current ordered unit. Reduce Motion/Contrast/localization remains out of
  scope until this unit is committed and the ROADMAP is reread.
