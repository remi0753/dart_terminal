# Phase 7 — title, tab metadata, cwd inheritance, and proxy icon

- Status: in progress
- Date: 2026-09-07
- Scope: fifth Phase 7 roadmap item
- Related: PTY-08, CAP-05, UI-02, UI-07

## Purpose

Turn the bounded per-session title and OSC 7 working-directory metadata from
Phase 6 into application-owned tab presentation and new-session policy. Support
an explicit user tab rename and color without losing the focused pane's live
title, inherit only a safe local directory into a newly created tab or split,
and project that directory through the standard macOS proxy-icon surface.

## Background

Phase 6 already owns strict OSC 0/1/2 titles, a bounded title stack, and OSC 7
file-URI metadata in `TerminalSessionMetadata`. Its contract deliberately makes
OSC 7 descriptive and grants it no process or filesystem mutation authority.
Phase 7 now has a bounded application/window/tab/split/pane model and an AppKit
adapter that maps every logical tab to one native `NSWindow`, but the adapter
only sets an externally supplied string title. The model has no user title or
color, new sessions always use the process-wide initial cwd, and AppKit exposes
neither `NSWindow.representedURL` nor a native-tab color marker.

The adjacent `dart_appkit` package owns generic window/tab primitives. It must
therefore expose the reusable represented-file and tab-color operations; this
product must keep OSC trust policy, title precedence, cwd inheritance, and
terminal-specific acceptance in Dart.

## Scope

- Add bounded application-owned optional tab rename and color state, with
  checked public mutations and deterministic reset behavior.
- Resolve each native tab title using explicit rename first, then the focused
  pane's accepted session title, then a local cwd basename, then the product
  fallback title.
- Convert accepted OSC 7 metadata to an inherited path only when it is a local
  (`file:///...` or `file://localhost/...`) absolute path without control data;
  remote authorities remain display metadata and never become launch cwd or a
  proxy icon.
- Add generic checked AppKit window APIs for an optional represented absolute
  file path and optional native-tab color marker, with direct Objective-C++,
  FFI, fake-binding, Dart API, lifecycle, and validation tests.
- Project title, rename/color, cwd, and proxy-icon state onto retained native
  tab windows without creating independent product ownership.
- Extend the gated native hierarchy workflow to prove live OSC title/cwd
  metadata, rename precedence/reset, color set/reset, inherited real PTY cwd,
  proxy state, and exact native-handle cleanup in Developer JIT and Release AOT.

## Out of scope

- Foreground-process discovery and process-derived close hints. PTY-08 retains
  those for the later per-pane close/quit-confirmation roadmap item.
- Filesystem probing, symlink resolution, directory creation, bookmarks,
  security-scoped resources, or trusting a remote OSC 7 authority.
- Config-file colors, title templates, shell integration, or persistent tab
  metadata. Phase 8 owns configuration/shell integration and the next Phase 7
  item owns restoration.
- Custom titlebar UI. The first color treatment is a small standard native-tab
  accessory marker, and the proxy icon uses `NSWindow.representedURL`.
- Implementing later roadmap actions or moving terminal-specific policy into
  `dart_appkit`.

## Ordered subtasks

1. Add bounded tab rename/color state plus deterministic focused-session title,
   local cwd, inherited-path, and represented-path policy with pure Dart tests.
2. Add reusable represented-file-path and native-tab-color APIs to
   `dart_appkit`, including C ABI, Objective-C++, FFI, fake binding, public API,
   native/Dart tests, and ownership documentation; commit that repository
   independently.
3. Record the reviewed adjacent dependency commit and generic/product boundary
   in this repository before consuming it in product integration.
4. Apply resolved presentation in the native hierarchy and normal single-pane
   product, then extend the four-pane native product acceptance and run all M1
   gates before completing the parent item.

The parent remains incomplete until all four ordered commits and the combined
verification pass.

## Dependencies and ownership

- `TerminalSessionMetadata` remains the sole owner of untrusted OSC title/cwd
  reports and continues to impose its existing UTF-8 and scalar bounds.
- `TerminalApplicationState` owns user tab metadata. A user rename overrides
  the live title only for presentation and clearing it resumes live resolution.
- `TerminalPane`/`TerminalSession` remain one-to-one PTY owners. A new session
  receives a copied launch path; no existing process cwd is changed.
- `TerminalNativeHierarchyAdapter` projects one immutable resolution per
  logical tab onto its retained native window. It owns no duplicate title/cwd
  state.
- `dart_appkit` copies and validates generic file paths/colors on the AppKit
  main thread. It never parses OSC or chooses inheritance/title precedence.

## Completion criteria

- Rename/title/cwd/path text and color components are hard bounded and invalid
  mutations are atomic; returned state does not expose mutable collections.
- Title precedence is deterministic across focused-pane changes, explicit
  rename/reset, OSC title/reset, local cwd fallback, and product fallback.
- Only a local absolute safe OSC 7 file URI can produce a launch cwd or native
  represented path. Remote, malformed, query/fragment, control, and oversized
  input fail closed without touching the filesystem.
- Native represented-path and tab-color operations are checked, clearable,
  cached in Dart, generation-safe, main-thread-only, and add no registry handle.
- A real inherited shell reports the expected cwd, native tab title/color and
  proxy state follow model/session mutations, and teardown restores the exact
  PTY/Metal/text-client/native-handle baseline.
- Focused tests, full tests/analysis/format, source audit, both arm64 bundle
  audits, and Developer JIT/Release AOT product acceptance pass.
- ROADMAP, README, FEATURE_MATRIX, the AppKit ownership docs, and this memo
  agree; both repositories are clean after their required commits.

## Verification plan

- Add pure Dart tables for valid/invalid rename, color bounds/equality, local
  versus remote URI conversion, percent decoding, title precedence, fallback,
  and atomic failure.
- Extend AppKit fake/native tests for set/replace/clear, invalid path/color,
  wrong handle/thread/stale generation, native accessory/represented URL, and
  absence of extra handles.
- Extend hierarchy fake tests for idempotent retained-window projection and
  clearing all optional presentation.
- In the gated real product, emit accepted OSC title/cwd bytes from zsh, create
  a descendant session from the resolved local cwd, verify `pwd`, exercise tab
  rename/color/reset and proxy state, then retain the existing four-pane input,
  IME, resize/zoom, close, and resource-cleanup checks.
- Run formatter/analyzer/focused suites after each subtask, the appropriate
  full repository gate before each completion commit, and final Developer JIT,
  Release AOT, bundle, and source-audit gates.

## Investigation log

- 2026-09-07: after commit `8c7a718`, both repositories were clean and the
  roadmap was reread. This is the first unchecked Phase 7 item.
- 2026-09-07: `TerminalSessionMetadata` already limits titles to 1,024 UTF-8
  bytes and cwd URI text to 4,096, rejects control/bidirectional controls, and
  stores cwd independently of both terminal grids. `isSafeWorkingDirectory`
  permits any file-URI host because Phase 6 treated it as descriptive metadata;
  inheritance must add the stricter local-host policy rather than weakening or
  silently changing the parser contract.
- 2026-09-07: `TerminalTabState` currently owns only split/focus/zoom state.
  `TerminalNativeHierarchyAdapter` retains one AppKit `Window` per tab and has
  a title-builder seam, so presentation can be resolved without a parallel
  hierarchy or new native object identity.
- 2026-09-07: the normal product already synchronizes the active session OSC
  title in its root-isolate `onChanged` callback, but it does not set a proxy
  path. The four-pane acceptance currently gives every `TerminalSession` the
  same initial cwd and uses fixed native titles.
- 2026-09-07: the macOS 14 SDK exposes `NSWindow.representedURL` and
  `NSWindowTab.accessoryView`. A small layer-backed accessory can represent
  color without freezing the tab title, while `representedURL` supplies the
  standard proxy-icon/path-menu behavior. These are generic AppKit operations
  and require no additional registry handle.
- 2026-09-07: the work crosses independently testable model, reusable native,
  dependency-adoption, and product-runtime boundaries. The four subtasks above
  were therefore registered in ROADMAP before implementation.

## Verification results

### 2026-09-07 — bounded tab presentation and cwd policy

- Added immutable byte-channel `TerminalTabColor` values, six standard marker
  colors, a visible-alpha requirement, and application-owned optional custom
  title/color state. `renameTab` and `setTabColor` return whether state changed,
  reject unknown/disposed state through the existing mutation boundary, and
  leave prior state intact on invalid input.
- Custom titles are non-empty, free of the session title policy's control and
  bidi scalars, and capped at 256 UTF-8 bytes. The smaller user-label cap is
  independent of the 1,024-byte child-controlled OSC title cap.
- Added a presentation resolver whose precedence is user rename, focused-pane
  OSC window title (including an intentional accepted empty title), local cwd
  basename, then a checked product fallback. Color and represented path are
  resolved from the same application/session snapshot.
- Inheritance accepts only safe absolute file URIs with an empty authority or
  case-insensitive `localhost`. It decodes the path and rechecks byte/control/
  bidi bounds, so a remote authority or percent-encoded NUL cannot become a
  PTY launch path or proxy path. It performs no filesystem operation.
- Focused formatting and analysis completed with no issues. The focused
  application-state suite passed, including local/remote/encoded-control URI,
  session-title/local-basename/fallback precedence, rename reset,
  focused-pane change, color equality/bounds, and atomic invalid-mutation cases.
- The first full `make test` passed all generated/freshness/native and Dart
  tests and formatted 200 files with no changes, but the analyzer reported one
  non-fatal directive-ordering info for the two new exports. The exports were
  moved into lexical order.
- The complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` rerun then
  passed every freshness/compatibility/native and aggregate Dart test, formatted
  200 files with zero changes, and reported no analyzer issues.
- `make runtime-source-check` passed with `tracked=377`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- The first ordered subtask is complete. The parent remains in progress pending
  the generic AppKit metadata primitives, terminal dependency record, and
  product hierarchy/runtime projection.
