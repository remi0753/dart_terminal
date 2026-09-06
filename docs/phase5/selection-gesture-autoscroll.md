# Phase 5 — selection gesture and drag autoscroll

- Status: in progress
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
