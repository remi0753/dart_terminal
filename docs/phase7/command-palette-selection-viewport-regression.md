# Phase 7 — command palette selection and viewport regression

- Status: complete
- Date: 2026-09-14
- Scope: regression correction for the completed Phase 7 command palette
- Related: IN-09, UI-05, UI-09

## Purpose

Keep command-palette keyboard selection bounded at the first and last search
result, and keep the selected command visible when the result list is taller
than the palette window.

## Background

`TerminalCommandPaletteState.moveSelection` currently applies modulo arithmetic,
so repeated Down Arrow input wraps from the last result to the first. The native
presenter renders the entire result list into a display-only `TextView`, which
has no scroll viewport or selected-range reveal operation. As a result, the
selection marker can move below the visible window without the presentation
following it.

The existing generic `dart_appkit` `TextEditor` is a scrollable `NSTextView`
surface. It supports an atomic read-only document with a UTF-16 selection and an
explicit `scrollSelectionToVisible` operation, so no terminal-specific native
API is needed.

## Scope

- Clamp Up/Down selection movement to the first and last filtered result.
- Render the palette in a read-only scrollable native text editor.
- Publish a zero-length UTF-16 selection on the selected command line and reveal
  it after every palette render.
- Add focused state and fake-AppKit presenter regressions for bottom-boundary
  behavior, viewport follow, and cleanup.
- Run formatting, static analysis, focused tests, and the complete project gate.

## Out of scope

- Mouse-driven palette selection, page-wise navigation, or a redesigned palette
  layout.
- Changes to the action search/ranking contract, command availability, dispatch,
  localization, shortcuts, or terminal focus restoration.
- Changes to `dart_appkit`; the required generic scrolling primitive already
  exists in the pinned local dependency.

## Dependencies and boundaries

- The action catalog remains bounded by
  `TerminalActionLimits.maximumPaletteResults`.
- The palette continues to own raw key events through `dartOnly` routing, so the
  read-only editor must not become an independent text-input authority.
- The reveal location must be computed from the exact rendered string in Dart
  UTF-16 offsets, matching `TextEditorSelection` and `NSRange` semantics.
- Palette window, editor handle, subscription, and terminal first-responder
  restoration retain their current ownership and teardown order.

## Options considered

1. Add scrolling directly to the display-only `TextView`. Rejected because it
   would expand the adjacent generic package and duplicate the existing
   scrollable editor surface.
2. Render only a manually sliced result window. Rejected because it introduces
   a second viewport model and hides surrounding results from the native text
   surface.
3. Use a read-only `TextEditor` and reveal the selected line. Adopted because it
   keeps the full bounded result document, uses the existing generic AppKit
   contract, and lets the native text system perform viewport scrolling.

## Completion conditions

- Repeated Down Arrow at the final result leaves the selected index unchanged;
  repeated Up Arrow at the first result behaves symmetrically.
- Moving through more results than fit in the window invokes native selected-
  range reveal for the newly selected command line.
- Search edits still reset selection, invocation remains exactly once, palette
  input does not reach the PTY, and dismissal restores terminal focus.
- Focused and aggregate tests pass with no leaked native handles.

## Verification plan

- Extend `test/terminal_command_palette_test.dart` with explicit first/last
  clamping and filtered-result boundary assertions.
- Extend `test/terminal_native_hierarchy_test.dart` with a fake-AppKit presenter
  scenario that checks read-only editor configuration, selected UTF-16 offset,
  reveal calls, bottom clamping, and cleanup.
- Run `dart format`, focused test entry points, `dart analyze`, and `make test`.
  Run the product runtime gate if the complete gate or existing project policy
  identifies it as required for this UI path.

## Findings and validation log

- 2026-09-14: The working tree was clean before the task. All normal Phase 0–11
  roadmap work is complete; only explicitly deferred, external-environment
  follow-ups were unchecked. This correctness regression was inserted before
  those follow-ups and is now the first unfinished task.
- 2026-09-14: Confirmed the state wrap is caused by
  `(_selectedIndex + delta) % _results.length`, while the presenter uses
  non-scrollable `TextView`. The local `dart_appkit` dependency already exposes
  a read-only `TextEditor`, atomic document selection, and
  `scrollSelectionToVisible`, with fake and native bridge coverage.
- 2026-09-14: Replaced modulo selection with inclusive clamping. Both the key
  controller suite and action-registry suite now assert that repeated Up/Down
  remains at the first/last result while unavailable and successful invocation
  behavior stays unchanged.
- 2026-09-14: Replaced only the palette presenter's display-only `TextView` with
  a read-only `TextEditor` using the same 18-point monospaced presentation. Each
  render records the exact UTF-16 start of the selected result line, publishes
  that zero-length selection with the full bounded document, and calls
  `scrollSelectionToVisible`. OSC 52 confirmation and other display-only views
  retain their existing `TextView` policy.
- 2026-09-14: Added fake-AppKit coverage that moves beyond the result count,
  proves the last index remains selected, checks the native read-only document
  selection and reveal call, repeats movement at the boundary, and verifies all
  editor/window/view handles are reclaimed.
- 2026-09-14: An initial attempt to run three native-asset-backed focused Dart
  entry points concurrently raced their shared `.dart_tool/lib` copy/install-
  name work. No source was affected. The suites were rerun sequentially; future
  runs for this repository must keep native-asset `dart run` commands serial.
- 2026-09-14: The first aggregate gate stopped at the expected stale Phase 7
  acceptance hash after the integration test changed. After regenerating that
  evidence, its dependent bounded daily-use matrix also reported stale and was
  regenerated. The generated diffs contain only the expected SHA-256 updates.
  A later aggregate run exposed one old action-registry assertion that still
  expected wraparound; it was corrected to cover both clamped boundaries.
- 2026-09-14: Final focused validation passed with exit 0 for
  `test/terminal_command_palette_test.dart`,
  `test/terminal_appkit_policy_test.dart`, and
  `test/terminal_native_hierarchy_test.dart`. `dart analyze` reported no issues.
  Final `make test` passed all freshness, formatting (338 files, zero changes),
  analysis, native package, compatibility, security, distribution, and Dart
  aggregate checks.
- 2026-09-14: `make runtime-terminal-display-integration` passed the real AppKit
  product command-palette path in Developer JIT (12,171 ms) and Release AOT
  (10,907 ms). Both retained exactly-once dispatch, zero terminal-write delta,
  terminal first-responder restoration, and native-handle restoration while
  using the new scrollable editor surface.

## Result

All completion conditions are satisfied. There are no task-specific remaining
items or new roadmap dependencies; the three pre-existing external-environment
follow-ups remain unchanged.
