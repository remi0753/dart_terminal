# VoiceOver and Accessibility Inspector pass

## Status

- Phase: 10
- Task: complete VoiceOver/Accessibility Inspector pass
- Started: 2026-09-12
- State: complete
- Current subtask: none
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
  native view and packet validation. At task start, the product manifest
  required renderer capability ABI 10; this task advances the matched
  dependency and consumer contract to ABI 11.
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
- Product projection now publishes the surface's effective horizontal and
  vertical padding in every accessibility snapshot, includes origin changes in
  semantic deduplication, and exposes content-free generation/origin state to
  deterministic acceptance. The configuration scenario checks initial and
  reloaded nonzero origins for all live panes, then focuses one reloaded native
  pane and verifies its selectors before and after undersized-viewport
  contraction from `(9, 7)` to `(7, 4)` and restoration.
- The first consumer formatting command used `--set-exit-if-changed`; it
  correctly stopped after formatting the newly added wait block, so analysis
  did not run in that invocation. A subsequent focused compile exposed that an
  initial-origin assertion had been inserted in the preceding theme scenario,
  before the configuration constants existed. The assertion was moved into the
  configuration scenario; idempotent formatting, `dart analyze`, and
  `test/terminal_config_test.dart` then passed.
- The first Developer JIT configuration acceptance timed out while reporting a
  teardown exception. Cleanup disposed and nulled the App Intents controller,
  then disabling notifications synchronously refreshed the still-live Settings
  presenter whose content-free status closure force-unwrapped that controller.
  Cleanup now retains the disposed controller through the notification refresh
  and clears it immediately afterward. This ordering repair is required to
  reveal the actual acceptance outcome and avoids changing steady-state status
  ownership.
- With the teardown exception removed, the second Developer JIT run exposed
  the original deterministic failure: the configuration acceptance still
  expected 45 unique Settings options and the smoke expected 45 options/48
  entries, although the preceding App Intents task added two schema options.
  The canonical schema and generated reference both report 47 options; this
  fixture repeats three keybind entries, so its exact effective-config shape is
  47 options/50 entries. Both stale acceptance expectations were advanced
  without weakening any diagnostic, owner-identity, or editor assertion.
- The third Developer JIT run reached the new native verifier but failed while
  iterating over every surface. That verifier intentionally asserts AppKit
  focused-element state and focus notifications, so it cannot validly pass for
  background panes. The product acceptance now asserts copied origin state for
  all four surfaces, explicitly focuses one reloaded native pane, and runs the
  content-free native selector verifier at configured, contracted, and restored
  origins. Dependency tests remain the exhaustive unfocused geometry/malformed
  packet authority.
- The first explicit-focus revision called the hierarchy's public reconcile
  method from inside the acceptance workflow. Applying the unchanged layouts
  synchronously resized PTYs, whose presentation callback correctly rejected a
  reentrant refresh while reconciliation was in progress. Reconciliation is
  unnecessary for this content-free check: the existing native window and pane
  resources are already projected. The acceptance now updates logical
  selection and uses those existing AppKit objects directly to select the tab
  and make the terminal view first responder.
- The next run showed that an artificial surface-only resize was coalesced with
  the still-authoritative native pane layout before its timer fired, so the
  intermediate contracted origin was never published. The acceptance now
  drains the surface synchronously immediately after the artificial contraction
  and restoration. This deterministically observes each intended geometry
  state without mutating the real window layout or PTY grid authority.
- The final Developer JIT configuration acceptance passes in 1,876 ms and the
  final Release AOT acceptance passes in 1,205 ms. Each uses four real PTY/
  Metal surfaces, validates initial and reloaded nonzero origins, runs the
  focused native selector verifier at configured/contracted/restored origins,
  preserves fixed font/cell behavior, and completes clean lifecycle teardown.
- The external release checklist is published at
  [`voiceover-accessibility-manual-checklist.md`](voiceover-accessibility-manual-checklist.md).
  It covers spoken visible text/selection/cursor/focus, Inspector point/range
  geometry at zero/nonzero/contracted padding and multiple display scales,
  Full Keyboard Access across terminal/native UI, cleanup, and both-runtime
  parity. No external VoiceOver, Inspector, or system setting observation is
  claimed or pre-checked.
- Phase 7 evidence regeneration changes only the two expected hashes for
  `terminal_application.dart`. Compatibility coverage regeneration changes
  only the README and Feature Matrix hashes. The public docs now describe ABI
  11, padding-aligned accessibility geometry, its fail-closed hit boundary, and
  the external checklist.
- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-source-check` passes with
  521 tracked files, zero product-native sources, and one reviewed test-native
  source. `make runtime-bundle-audit` passes for both arm64 modes with one
  helper, one asset set, two capabilities, one scripting definition, and three
  App Intents.
- The exact consumer `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate
  passes all freshness, compatibility, differential, application, terminfo,
  and shell checks; formats 283 files with zero changes; analyzes cleanly;
  passes the Phase 9 stress seed `0x509a1171`; and ends with
  `dart_terminal tests passed`.

## Completion decision

The dependency contract, product projection, both shipped runtime modes,
source/bundle/full gates, generated evidence, public documentation, and manual
release checklist satisfy the scoped automated contract. The unchecked manual
checklist records system-owned release-environment observations and is not an
unimplemented product path; this follows the same boundary as the Phase 10
AppleScript, native-content, Secure Keyboard Entry, and App Intents checklists.
The configured-padding child and VoiceOver/Accessibility Inspector parent may
therefore be marked complete without fabricating an external manual result.

## Handoff and remaining work

- This task is complete. The next ordered ROADMAP item is Reduce Motion,
  contrast, and localization, but the user requested that execution stop after
  this task's commit and post-commit ROADMAP reread.
