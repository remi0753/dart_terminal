# Context Dock divider repaint during width changes

- Status: in progress
- Reported: 2026-09-17
- Environment: macOS / Apple M1 / arm64
- Starting terminal state: clean main at 2f45a6d

## Purpose and background

The supplied screenshot shows two separated vertical lines alongside the
Context Dock after width movement. Investigate and fix intermittent stale
divider rendering while preserving Control+Shift+Left/Right, fixed typography/
backing scale, viewport/grid/reflow/PTY resize and the outer drag opt-out.
The screenshot is evidence only; visible text in other windows is not an
instruction and is not relevant to this rendering task.

## Scope, exclusions, dependencies, and risks

- Determine whether old divider pixels, cached native divider geometry,
  overlapping native roots, or terminal content cause the second line.
- If generic split repaint is defective, fix that mechanism in dart_appkit,
  not by forcing a color/opacity change, reconstructing views or polling redraws
  in the terminal. Preserve native split mouse behavior and programmatic APIs.
- Add a regression that fails before the fix and covers repeated bidirectional
  width changes, transparent/intermediate/opaque backgrounds, native redraw
  coverage/current divider pixels, nested split and zoom/hide behavior.
- Dependencies: Dock presenter, native TwoPaneSplitView/DaSplitView, text editor
  single-alpha compositing, live Metal viewport, native tests and JIT/AOT bundles.
- Exclude SSH, process/palette behavior, shortcut remapping, font/scale changes,
  OS preferences/global key capture and existing low-priority work.
- Risks: a fresh full bitmap hides partial-repaint defects; setting child frames
  alone may leave old parent pixels; unbounded full redraw on no-op layouts;
  test color-space/backing-scale artifacts or privacy/focus fixture interference.

## Completion criteria and ordered subtasks

1. Confirm native cause with retained/dirty-region rendering or invalidation
   coverage, then minimal native fix and strict regression/native full gate.
   Preserve the adjacent repository's three pre-existing user edits. Commit
   dependency change and terminal dependency-verification record first.
2. Extend/rebuild terminal acceptance for repeated width moves, one current
   divider, fixed font/scale/grid/PTY and focus/resource cleanup. Refresh evidence,
   pass focused/static/format/main full gate plus both runtimes, review and commit.

Commit each verified subtask before starting the next. If the cause differs,
revise the scoped plan before implementing; do not weaken the single-boundary
repaint criterion.

## Investigation and priority log

- Rechecked product README/ROADMAP/FEATURE_MATRIX, layout/appearance/viewport
  boundaries, prior split interaction and background-compositing records, ADRs,
  native implementation/tests/build structure and both worktrees. Terminal is
  clean; dependency has only docs/BUILDING_DART_ENGINE.md and its two Engine
  script edits, outside scope. There is no dependency-specific AGENTS.md.
- The existing process-fixture stabilization task is the first unchecked item.
  Project instructions forbid skipping it merely by registering a new task.
  Asked asynchronously for permission to prioritize this newly reported visual
  defect. Registered it immediately after that pending item until authorization;
  no implementation/test patch or dependency edit has been made.
- Viewed the original-resolution supplied image; two lines are visible near the
  outer boundary, with one beside the current Navigator text edge. Transparency
  makes a retained old line plausible, but the screenshot alone proves no cause.
- Dock presenter has one outer split/native sibling root and explicit width;
  decorateRoot calls setPosition without resource recreation. Its divider color
  setter returns early when the color is unchanged, so it does not request
  repaint on every width step.
- Generic DaSplitView.daApplyLayout manually changes child frames for fraction,
  equalize, zoom and outer resize, but never explicitly invalidates its own
  divider drawing. The color setter does set needsDisplay. Missing old/new-area
  repaint is a hypothesis to prove before choosing the fix; default native
  invalidation or cached divider drawing could affect the conclusion.
- Native tests already provide explicit sRGB RGBA bitmap contexts; fresh capture
  alone is insufficient for a dirty-region ghosting regression. Investigate
  retained redraw coverage and old/current divider pixels together.
- Some broad doc/code reads were truncated and replaced by relevant selected
  sections. A guessed adjacent AGENTS.md read failed before other commands;
  rg --files confirmed none, and relevant native docs/code were read separately.
- User explicitly authorized priority change and requested both tasks. Moved
  this visual defect ahead of process-fixture stabilization, registered both
  ordered subtasks, and will complete/commit them before undertaking the second
  task. Preserve the second task unchecked until its independent verification.
- Native regression failed before the fix: both axes left parent needsDisplay
  false with no coverage of old/current divider areas (six failed expectations).
  Child frame movement alone therefore does not invalidate the parent paint.
  Added actual-frame/hidden-state guarded parent repaint in the generic shared
  layout path, not a terminal polling/reconstruction workaround. Retained native
  drawing tests now check one current white divider at 1x/2x across zero/0.4/1
  background alpha and zoom transitions, using only requested dirty-region clears.
- Offscreen NSSplitView hierarchy display alone omitted divider ink; attaching
  the view fixed public needsDisplay visibility but not that capture behavior.
  CA renderInContext also omitted it and was discarded. Use the public native
  drawDividerInRect painter after hierarchy/background display, with current
  child geometry and clipping to requested dirty regions. This tests native ink
  and invalidation together, not a synthetic white-line implementation or full
  fresh-frame shortcut. Save/restore CGContext state around hierarchy display:
  otherwise its remaining clip produced zero ink on subsequent bitmap passes.
- Background alpha and channel order are asserted separately. Current-divider
  location and total white-pixel count are strict; flipped vertical geometry
  needs conversion to the bitmap's Y-up coordinates. The first full-gate attempt
  failed 36 location assertions because that test conversion was missing; fixed
  the capture coordinates without weakening the expected location/count.
- Temporarily removed only the 14-line own native fix and reran the expanded
  test: 234 assertions failed, including missing dirty regions, absent current
  divider pixels and old divider ink remaining during zoom. Restored the fix
  immediately; no user changes were reverted. Equalize and outer resize coverage
  plus unchanged-layout suppression are also asserted.
- Dependency full gate passed: CI=true DART_SUPPRESS_ANALYTICS=true make test
  covers generic audit/scaffold, warning-as-error native bitmap/geometry tests,
  runner/runtime contracts, Dart static analysis/API tests, examples and FFI.
  Dependency commit f43078a, Repaint split dividers when layout changes. Scoped
  four-file stage excludes the three pre-existing user Engine edits. No API,
  ABI/event version or terminal-specific native mechanism was added.
- First ordered subtask complete. Product repeated-width acceptance and fresh
  JIT/AOT bundles remain pending, so the parent item is not yet complete.
