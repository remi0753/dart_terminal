# Phase 5 — selection gesture and drag autoscroll

- Status: complete
- Date: 2026-09-06
- Scope: fifth Phase 5 production-input roadmap item
- Related: IN-05, IN-06, SCR-07, SCR-11, REN-02

## Purpose

Turn the exclusive local-selection intents established by the preceding mouse
task into visible, stable, bounded character/word/logical-line selection.
Dragging beyond the top or bottom edge must advance the retained viewport at a
bounded rate, extend the same selection through history, and stop immediately
when the gesture ends or its anchors become unavailable.

## Background

Phase 3 already provides a history-aware `TerminalViewport`, stable logical
anchors that survive reflow while retained, end-exclusive range normalization,
word expansion, logical-line expansion, and bounded extraction. Phase 4's Metal
compositor has a selection layer but currently uses it only for preedit and the
visual bell. The live surface renders the active screen directly and therefore
does not yet project a scrolled viewport or a persistent terminal selection.

The preceding Phase 5 mouse task routes normal-shell and Shift-overridden
pointer events to `TerminalLocalSelectionIntent`, but deliberately stops before
mutating selection. Its point normalization clamps to a visible cell, so the
handoff must be extended with bounded above/below edge information before drag
autoscroll can distinguish an edge cell from a pointer outside the view.

Clipboard copying, precision/momentum wheel scrolling, terminal-mouse wheel
reports, hyperlink interaction, and accessibility exposure are later roadmap
items and remain outside this task.

## Ordered subtasks

1. **Gesture state and stable anchors**
   - Extend local intents with validated vertical edge state without changing
     terminal-report coordinates or ownership arbitration.
   - Add a single-owner gesture model: one click selects cells, double click
     selects words, and three or more clicks select logical lines.
   - Preserve inclusive pointer behavior through end-exclusive start/end
     anchors in both drag directions; retain the completed range after mouse-up
     and cancel safely after screen changes or anchor eviction.
   - Completion: focused router/gesture tests and the full suite pass; commit
     only this subtask and reread the roadmap.
2. **Viewport rendering and bounded autoscroll**
   - Project the current viewport, including history, into the render-side
     model without weakening the existing damage/resource/size caps.
   - Convert the stable range into clipped per-row selection spans and compose
     them in the existing Metal selection layer without editing canonical cells.
   - Add a monotonic, one-deadline drag autoscroller with explicit rate/work
     bounds; redraw only the newest viewport/selection state.
   - Completion: viewport/history, wide-cell, reflow/eviction, render ordering,
     timing, stop, and cap tests pass; commit only this subtask and reread the
     roadmap.
3. **Product and real-AppKit acceptance**
   - Connect local intents to the live gesture/render owner and drive automatic
     ticks outside AppKit callbacks.
   - Prove character, word, logical-line, reverse drag, Shift override, and
     above/below history autoscroll using the real window and Metal product path
     in Developer JIT and Release AOT.
   - Retain mouse-protocol byte acceptance and prove local selection produces
     no PTY write.
   - Completion: full tests, source/bundle audits, smoke/resource checks, and
     both real-window runtime modes pass; then complete the parent item.

Dependencies are strictly ordered. Subtask 2 consumes the gesture snapshot
from subtask 1, and subtask 3 consumes both. No clipboard or wheel behavior is
implemented early.

## Scope

- Primary-button cell, word, and logical-line selection from click count.
- Forward/reverse drag with end-exclusive inclusive-cell behavior.
- Soft-wrapped word/logical-line expansion through the existing viewport rules.
- Stable retained anchors across output, resize/reflow, and viewport movement.
- Explicit cancellation when a screen-kind transition or eviction invalidates
  either gesture anchor.
- Bounded top/bottom drag autoscroll over primary history; alternate screen
  remains clamped at offset zero.
- Persistent selection overlay rendered between cell backgrounds and glyphs.
- Content-free counters/state for deterministic product acceptance.

## Out of scope

- Copying selected text, primary selection, pasteboard writes, paste, and
  selection ownership outside this application.
- Wheel/trackpad delta, momentum phases, alternate-screen key emulation, and
  terminal wheel reports.
- Shift-click range extension, rectangular/block selection, multiple disjoint
  ranges, right/middle-button actions, Option-click cursor movement, and drag
  and drop.
- Hyperlink hover/open, URL policy, semantic prompt selection, search UI,
  VoiceOver, Services, and Quick Look.
- Configurable selection colors, click timing/preferences, or autoscroll rate.

## Decisions and invariants

- The terminal core remains the canonical text/anchor owner. Gesture code never
  copies or reconstructs strings to decide word or logical-line boundaries.
- A gesture stores both start and end boundaries of its origin cell. Forward
  drag uses origin-start to focus-end; reverse drag uses origin-end to
  focus-start, so both directions include the cell under the pointer before
  unit expansion.
- Only the primary/left button mutates selection. Other local intents are
  consumed as no-ops and cannot steal or finish an active primary gesture.
- Click count is interpreted only on begin: one is cell, two is word, and three
  through the existing 255 cap are logical line. Update/end retain that unit.
- Edge information is a three-value enum (`inside`, `above`, `below`) derived
  from finite view coordinates. It carries no unbounded distance or pixel data.
- Autoscroll uses one monotonic deadline and a fixed rows-per-tick cap. There is
  no catch-up loop after a delayed tick, preventing UI starvation.
- Selection is transient presentation state. It does not enter the terminal
  screen, PTY stream, parser snapshots, or scrollback storage.

## Completion criteria

- Cell/word/logical-line gestures select byte-for-byte expected retained text
  across narrow, wide, combining, soft-wrap, hard-break, and history cases.
- Forward and reverse drag produce equivalent normalized content while keeping
  direction available for gesture behavior.
- Reflow preserves retained selection; eviction or screen-kind change cancels
  it deterministically without stale rendering.
- Above/below drag moves the primary viewport and extends selection at a
  bounded rate; mouse-up, cancel, bottom/top bounds, and alternate screen stop
  further movement.
- Metal renders clipped selection spans at 1x/2x in the correct layer order,
  and the scrolled viewport displays history rather than the live bottom grid.
- Product routing proves local-only ownership and real-window visual state in
  Developer JIT and Release AOT while retaining exact remote mouse reporting.
- Full tests, documentation, source audit, both bundle audits, smoke/resource
  acceptance, and both repositories' cleanliness checks pass.

## Verification plan

- Pure-Dart gesture tests for unit mapping, begin/update/end, reversal,
  unsupported buttons, invalid ordering, wide cells, wrap, reflow, eviction,
  alternate transition, and immutable snapshots.
- Router tests for inside/above/below classification at finite pixel bounds.
- Viewport projection and compositor tests for every cell field, cursor
  visibility, selection span clipping/layer order, 1x/2x, and configured caps.
- Injected-clock autoscroll tests for one-deadline scheduling, no catch-up,
  bounds, direction reversal, cancellation, and newest-only redraw.
- Existing full Dart/native suites after each subtask, followed by real AppKit
  and PTY acceptance in both product runtime modes.

## Investigation log

- 2026-09-06: mouse product integration commit `01a36dd` completed the
  preceding roadmap item. `dart_terminal` and `dart_appkit` were clean before
  this task.
- 2026-09-06: `TerminalViewport` already projects primary history plus the
  active grid, preserves an offset while new output arrives, exposes all cell
  fields, hides an offscreen cursor, and resolves stable anchors. No new text
  semantic implementation is required.
- 2026-09-06: `TerminalLiveMetalSurface` currently binds its damage outbox to
  `screenSet.activeScreen`; changing `TerminalViewport.offset` alone cannot
  change visible Metal content. A bounded full viewport projection is therefore
  required before drag autoscroll can be considered usable.
- 2026-09-06: selection must be passed separately to the compositor. Encoding
  it as cell style or background damage would mutate terminal-owned content and
  lose the established presentation-layer ordering.
- 2026-09-06: completed ordered subtask 1. `TerminalMouseRouter` now classifies
  each local intent as inside, above, or below the finite viewport while keeping
  the protocol coordinate clamped and unchanged. The enum carries no pixel
  distance and therefore cannot introduce unbounded scroll acceleration.
- 2026-09-06: `TerminalSelectionGestureController` accepts only left-button
  begin/update/end sequences, maps click counts 1/2/3+ to cell/word/logical
  line, and stores both origin-cell boundaries. Its reverse path uses
  origin-end to focus-start, preserving inclusive pointer cells in the existing
  end-exclusive range model.
- 2026-09-06: completed mouse-up retains the immutable range but clears active
  edge state. Invalid phase order, zero-click begin, and right/middle events are
  no-ops. Reflow keeps retained anchors; eviction or active-screen transition
  clears the complete gesture snapshot with one monotonic generation change.
- 2026-09-06: the first invalidation test exposed that
  `extractSelection(range)` can resolve retained primary anchors while the
  alternate screen is active. Extraction is a document operation, whereas a
  gesture additionally requires active-screen ownership. `TerminalViewport`
  now exposes `isSelectionAvailable`, which checks both retained boundaries and
  active screen kind explicitly; using extraction as a proxy was rejected.
- 2026-09-06: the first full-suite run passed tests but reported one analyzer
  info for an unsorted new runner import. The import was reordered and the
  entire command was rerun cleanly rather than accepting a diagnostic.
- 2026-09-06: completed ordered subtask 2. A minimal read-only
  `TerminalRenderModel` lets the compositor consume either the existing
  incremental damage model or an immutable typed-array viewport snapshot. The
  live surface keeps normal bottom-follow damage unchanged and substitutes a
  full bounded projection only while primary history is visible.
- 2026-09-06: viewport projection copies content, foreground, background,
  style, width/protection flags, and a visible cursor across the history/grid
  boundary. Rows with a different stored width are clipped/padded, and an
  orphaned wide/continuation edge is omitted rather than emitting invalid
  topology. Scrolled-off cursors are hidden with valid placeholder coordinates.
- 2026-09-06: stable ranges project to at most one non-empty physical-column
  span per visible row. End boundaries preserve wide-cell coverage, offscreen
  retained ranges yield an empty projection, and a different active screen
  yields no projection. Metal adds these spans to the existing selection layer
  between cell backgrounds and glyphs without editing terminal cells.
- 2026-09-06: `TerminalSelectionAutoscroller` uses a 50 ms default interval,
  one deadline, and a configurable 1–8 rows-per-tick cap. A delayed call moves
  only once and schedules from the observed time; direction changes replace
  the deadline, while mouse-up, inside movement, history bounds, alternate
  screen, invalid anchors, and cancellation leave no pending work.
- 2026-09-06: the initial Metal ordering test used palette token 1, which is
  xterm black and matched the default black background, so no cell-background
  instance was correctly emitted. The test now uses non-default token 2. Its
  first width expectation also rounded `2 * cellWidth` directly, while the
  compositor correctly subtracts separately rounded cell boundaries; the test
  now follows the same deterministic boundary rule at both 1x and 2x.
- 2026-09-06: as in subtask 1, the first full runner after adding a new test
  reported one import-order info while all tests passed. The runner import was
  sorted and full analysis/tests were rerun with no diagnostics.
- 2026-09-06: completed ordered subtask 3. A product-owned gesture/autoscroll
  owner receives only the local branch of `TerminalMouseRouter`, publishes the
  immutable selection snapshot to the live Metal surface, and owns one Timer
  matching the core autoscroll deadline. Timer ticks extend the stable range
  and notify viewport rendering outside the AppKit event callback.
- 2026-09-06: screen changes ask an existing selection to synchronize before
  rendering; inactive/no-selection state costs no document scan. Shutdown
  cancels the owner Timer before disposing the surface, so no late tick can
  access released Metal/AppKit state.
- 2026-09-06: the real product fixture writes unique character, word, logical
  line, and scroll-history rows through the live PTY, finds their canonical
  screen cells, and injects raw events through the existing test-only AppKit
  boundary. It proves exact extracted text and unit, reverse direction, prior
  Shift override, at least three upward ticks, return-to-bottom ticks, visible
  Metal spans, and an unchanged terminal-report count across local gestures.
- 2026-09-06: acceptance emits only fixed booleans in
  `TERMINAL_SELECTION_TEST`; selected text and terminal content never enter
  diagnostics. The aggregate display gate now additionally requires
  `selection=true`.

## Verification results

### Gesture state and stable anchors

- Focused analysis and `test/terminal_selection_gesture_test.dart` plus
  `test/terminal_mouse_router_test.dart`: passed. Coverage includes edge
  classification, forward/reverse inclusive cell drag, word expansion,
  soft-wrapped logical-line expansion, immutable historical snapshots,
  unsupported buttons and phase ordering, persistent mouse-up range, clear,
  reflow retention, alternate transition, and eviction cancellation.
- `CI=true make test`: passed after the directive-order fix with parser-table
  freshness, 126-file format check (zero changes), whole-package analysis with
  no issues, native asset hooks, and the full Dart runner.
- Viewport projection, Metal overlay, and timed drag autoscroll remain tracked
  in ordered subtask 2; product wiring remains tracked in subtask 3.

### Viewport rendering and bounded autoscroll

- Focused projection tests passed for every compositor cell field, mixed
  history/screen rows, visible/offscreen cursor, copy isolation, resource/grid
  validation, wide-cell spans, offscreen clipping, and active-screen rejection.
- Focused autoscroll tests passed for arming/waiting, exact deadline, no
  catch-up after a 200 ms delay, above/below movement, direction reversal,
  mouse-up stop, bottom/alternate bounds, interval/rate caps, and monotonic-time
  rejection.
- Focused Metal tests passed at 1x and 2x, proving exact cell-boundary geometry
  and background → selection → glyph ordering. Existing SGR, wide grapheme,
  preedit, prompt-bottom, and instance-cap cases also remained green.
- Final `CI=true make test`: passed with parser-table freshness, 131-file format
  check (zero changes), whole-package analysis with no issues, native asset
  hooks, and the full Dart runner.
- `CI=true make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`:
  passed in Developer JIT (1382 ms) and Release AOT (891 ms), retaining exact
  input/mouse evidence, Metal output, wrapping, and bottom prompt before product
  selection wiring.
- At this subtask boundary, real AppKit gesture ownership and observable
  selection/autoscroll evidence remained solely in ordered subtask 3; they are
  completed below.

### Product and real-AppKit acceptance

- `CI=true make RUNTIME_ARCH=arm64 developer-jit-display`: passed the complete
  character/word/logical-line, reverse, Shift, upward/downward autoscroll,
  Metal, and local-only contract in 1927 ms while retaining exact keyboard,
  IME, input-matrix, terminal-mouse, style, wrap, and bottom-prompt evidence.
- `CI=true make RUNTIME_ARCH=arm64 release-aot-display`: passed the same
  contract in 1294 ms.
- Final `CI=true make test`: passed with parser-table freshness, 131-file format
  check (zero changes), whole-package analysis with no issues, native asset
  hooks, and the full Dart runner.
- Final `CI=true make RUNTIME_ARCH=arm64 runtime-source-check
  runtime-bundle-audit runtime-integration runtime-resource-integration`:
  passed. Source audit found 227 tracked files and no native source; both
  bundles retained one helper, one native asset, and one capability; both smoke
  runs passed; both 1,000-iteration resource runs remained bounded at baseline
  12 and peak 14 descriptors.
- Final worktree review found no `dart_appkit` changes and only this product
  owner, acceptance, smoke gate, documentation, and progress update in the
  `dart_terminal` task.

## Phase 11 semantic pointer follow-up

The later pinned-compatibility closure extends this same terminal-local owner
without changing generic AppKit transport:

- An exact Option + primary-button single-click on the current primary-screen
  OSC 133 input range moves the shell cursor with normal CSI or
  application-cursor SS3 left/right sequences. The plan is bounded to 85
  movements and 255 encoded bytes. A drag, viewport history, alternate screen,
  stale screen/semantic generation, a point outside the live input, or any
  additional modifier fails closed without a PTY write.
- Active terminal mouse reporting retains exclusive ownership. An Option-click
  becomes the negotiated mouse report and cannot also move the prompt cursor or
  start a local selection.
- An ordinary triple-click selects a logical line clamped to its OSC 133
  prompt, input, or output segment. Control- or Command-triple-click selects a
  complete output block, and drag combines only complete output blocks using
  stable anchors. Prompt/input targets do not expand an output selection.
- Developer JIT and Release AOT acceptance inject native pointer events into a
  real AppKit window backed by a real zsh PTY and Metal surface. It checks exact
  CSI/SS3/report bytes, exact copied prompt/input/output text, output-block drag,
  non-empty current-generation Metal spans, and idle cleanup.
