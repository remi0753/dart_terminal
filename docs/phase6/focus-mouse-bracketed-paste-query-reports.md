# Phase 6 — Focus, mouse, bracketed paste, and query reports

## Identity and status

- Date started: 2026-09-07
- Scope: seventh Phase 6 compatibility-hardening roadmap item
- Current status: focus reporting and SGR pixel mouse/highlight-mode
  disposition complete; bounded DECRQSS SGR is next

## Purpose and background

The accepted real-application captures leave bounded gaps for DEC focus
reporting, SGR pixel mouse coordinates, xterm version/window-size reports, and
DECRQSS SGR. Bracketed paste and cell-coordinate mouse reporting already have
product routing and regression coverage, but must remain compatible while the
adjacent input/report protocols are added.

This task closes the P0/P1 gaps that have application evidence and records an
explicit disposition for highlight mouse tracking, whose interactive host-side
protocol is not exercised by the captured P0 applications. Every outbound
reply or input report remains bounded and travels through the existing ordered
PTY write boundary.

## Ordered implementation units

1. **DEC focus reporting and native routing**
   - Add DEC private mode 1004 state, DECRQM visibility, and exact `CSI I` /
     `CSI O` encoding.
   - Route native focus transitions to the active PTY only while the mode is
     enabled, without duplicate reports for repeated state.
   - Verify parser state, encoding bounds, application routing, and real-PTY
     behavior in Developer JIT and Release AOT.
2. **SGR pixel mouse and highlight-mode disposition**
   - Add DEC private mode 1016 as SGR syntax with one-based pixel positions,
     preserving local selection and Shift override behavior.
   - Verify coordinate bounds, resize/backing geometry, mode reset, and native
     product routing.
   - Retain mode 1001 as explicit unsupported unless new enable-path evidence
     justifies its stateful highlight handshake; a captured reset alone is not
     sufficient to advertise support.
3. **Bounded DECRQSS SGR replies**
   - Recognize only the complete `$q`/`m` request and serialize current SGR state
     in the pinned xterm form within a fixed reply bound.
   - Preserve malformed/incomplete DCS handling and explicit safe-ignore for
     other DECRQSS selectors.
   - Update the differential corpus and acceptance classification without
     normalizing legitimate product-specific reply serialization.
4. **XTVERSION, XTWINOPS, and compatibility closure**
   - Implement `CSI > q` / `CSI > 0 q`, `CSI 14 t`, and `CSI 18 t` with stable
     product identity and bounded logical viewport geometry.
   - Revalidate bracketed paste, cell/pixel mouse, focus routing, raw PTY
     replies, inventory freshness, and the real-application matrix.
   - Resolve owned matrix gaps, update feature/ownership records, and decide
     the parent roadmap item only after all four units pass.

Each unit is independently reviewed, verified, documented, marked complete,
and committed before the next unit starts.

## Scope

- DEC private modes 1004 and 1016, their mode queries, reset behavior, and
  snapshot/state ownership.
- Native-to-Dart focus/pointer geometry routing and ordered PTY writes.
- Exact bounded encoders for focus, pixel mouse, DECRQSS SGR, XTVERSION, and
  XTWINOPS 14/18 reports.
- Byte-level, all-split, integration, and both-runtime product acceptance.
- Inventory, differential, vttest, application-matrix, README, and feature
  records affected by these protocols.

## Out of scope

- Xterm highlight mouse mode 1001 unless P0 evidence demonstrates its enable
  and host/application handshake.
- Other XTWINOPS operations, arbitrary DECRQSS selectors, sixel/ReGIS, or
  private product emulation strings.
- New clipboard permission UI, keyboard protocol work, settings, tabs, or
  splits owned by later phases.
- Duration-only soak. Per the roadmap policy, long-duration evidence is a
  lower-priority follow-up and is not a normal blocker; bounded correctness,
  safety, queue, and resource checks remain required.

## Dependencies and confirmed facts

- `TerminalScreenSet` owns private-mode state while `TerminalApplication` owns
  native event routing and the PTY write queue.
- Cell-coordinate modes 9/1000/1002/1003 and encodings 1005/1006/1015 already
  exist. Mode 1016 must reuse SGR packet syntax but receive physical viewport
  pixel coordinates instead of cell coordinates.
- Bracketed paste already has bounded chunking/backpressure and product tests.
- The seven-byte `ESC P $ q m ESC \\` request is the minimized DECRQSS gap.
  Pinned xterm 411 reports explicit default SGR as `0m`; Kitty uses a different
  valid ordering/serialization for styled state.
- Captures exercise only reset for mode 1001. Implementing reset without the
  interactive enable/report protocol would create misleading partial support.
- XTWINOPS 18 can use terminal rows/columns. XTWINOPS 14 requires live logical
  text-area pixel geometry to cross the native/application boundary.

## Risks and boundaries

- Focus reports must not leak to an inactive/stale session generation or be
  emitted merely because mode 1004 is toggled.
- Pixel mouse coordinates must be one-based, bounded, and independent of cell
  selection geometry; backing-scale conversion must not double-scale logical
  AppKit coordinates.
- Query replies are attacker-triggerable PTY output. Payloads, parameters, and
  encoded replies therefore retain fixed limits and cannot contain environment
  data or arbitrary native strings.
- DECRQSS output must describe current terminal state without mutating style or
  consuming unsupported selectors as successful.
- Compatibility gates must distinguish semantic agreement from intentional
  product-specific SGR serialization.

## Completion conditions

- All four ordered units are complete and separately committed.
- Captured P0 focus, pixel-mouse, XTVERSION, window-size, and DECRQSS gaps are
  resolved or have a reviewed explicit non-adoption decision.
- Focus, mouse, and paste coexist with local selection and ordered bounded PTY
  writes.
- Every added sequence has byte-level regression coverage, parser split
  coverage where applicable, and Developer JIT/Release AOT product evidence.
- Compatibility manifests, application/differential acceptance, README,
  FEATURE_MATRIX, and this memo agree with the implementation.
- The normal full test gate passes with a clean task-scoped diff.

## Verification plan

- Focused Dart unit tests for mode state, encoders, parser dispatch, routing,
  bounds, and reset semantics.
- Existing mouse, paste, selection, input-event, snapshot, and parser suites.
- All-chunk-split replay for each terminal-originated query.
- Raw PTY product probes in Developer JIT and Release AOT for focus and query
  bytes, plus native pointer geometry for pixel mouse.
- Differential and real-application acceptance/freshness gates.
- `CI=true make test` after each implementation unit, with formatter and
  analyzer results recorded below.

## Investigation and decision log

- 2026-09-07: reread README, ROADMAP, FEATURE_MATRIX, the vttest adoption
  decisions, the real-application matrix, and the DECRQSS gap record. Confirmed
  this is the first incomplete roadmap item and that the worktree was clean.
- 2026-09-07: split the broad item before implementation because it crosses
  native focus routing, pointer coordinate semantics, DCS state reporting, and
  CSI geometry replies. The split keeps later protocols from being implemented
  ahead of the ordered current unit and gives each unit an independently
  reproducible acceptance boundary.
- 2026-09-07: adopted the roadmap's duration policy. Long-duration use remains
  useful follow-up evidence but does not block these bounded protocol units.
- 2026-09-07: implemented DEC private mode 1004 in `TerminalScreenSet`, including
  DECRQM reporting, reset semantics, and a dedicated mode generation. The mode
  survives alternate-screen activation and resize but resets on RIS.
- 2026-09-07: introduced `TerminalFocusReporter`. It emits only the exact
  three-byte `CSI I` or `CSI O` packet, suppresses repeated native state, and
  resets that suppression across mode disable/re-enable using the mode
  generation. Disabled events never reach the PTY callback.
- 2026-09-07: connected `WindowFocusChangedEvent` to the active pane's existing
  bounded input/write path. The product test enables mode 1004 in real zsh,
  injects blur/duplicate-blur/focus, reads exactly six raw PTY bytes, resets the
  mode, and proves a subsequent disabled event emits nothing.
- 2026-09-07: regenerated the implementation manifest and sequence inventory.
  Focus mode moved from unsupported to implemented, producing totals of 83
  implemented, 18 partial, 10 safe-ignore, and 149 unsupported records. The
  implementation surface now contains 101 declarations.
- 2026-09-07: replayed the immutable eight-application evidence. The two mode
  1004 variants and their owned gap disappeared; unsupported increments fell
  from 92 to 82, unique variants from 20 to 18, and gaps from 13 to 12. Original
  capture counters and bytes remain unchanged.
- 2026-09-07: the first full gate correctly rejected stale differential
  provenance after the implementation manifest changed. Regenerating the four
  reviewed Dart observations changed only their implementation revision and
  dependent hashes; text, cursor, modes, styles, and replies stayed identical.
  The 12-cell external acceptance remained six agreements, two documented
  gaps, and four unavailable captures.
- 2026-09-07: the next full gate exposed the expected recorded-Vim oracle
  change: its two captured mode-1004 sequences no longer increment the
  unsupported counter (8→6). Updating that one counter and the aggregate corpus
  hash was sufficient; all 1,437 split/bytewise runs matched and no grid,
  metadata, parser-error, or reply field changed.
- 2026-09-07: implemented DEC private mode 1016 as an encoding-family member.
  It uses the existing SGR button/release syntax but maps AppKit logical points
  to one-based physical pixels with the live window backing scale. Coordinates
  clamp at the text-area edge and fail closed above the fixed 65,535 protocol
  bound; rows/columns retain their separate 4,096 cell bound.
- 2026-09-07: pointer presses, releases, motion, and wheel reports share that
  mapping. Shift ownership is resolved before pixel conversion, so a local
  selection remains cell-based even when the corresponding pixel report would
  exceed the protocol bound. This prevents report limits from disabling the
  user escape hatch and avoids applying Retina scale to selection anchors.
- 2026-09-07: retained DEC private mode 1001 as explicit unsupported. The
  immutable mosh capture contains four reset packets and no enable path or
  application/terminal highlight handshake. Treating reset as implemented
  would advertise a stateful protocol that the terminal cannot complete.
- 2026-09-07: regenerated the implementation manifest and inventory. Mode 1016
  moved from unsupported to implemented, producing 84 implemented, 18 partial,
  10 safe-ignore, and 148 unsupported records, with 102 implementation
  declarations. The mistaken first trace invocation used an unsupported
  `--matrix` argument; rerunning the documented no-argument tool succeeded.
- 2026-09-07: immutable application replay removed lazygit's three mode-1016
  resets without changing capture provenance. Lazygit now has 33 current
  rejects, while the complete matrix has 79 increments, 17 variants, and 11
  owned gaps. The mode-1001 reset remains a bounded explicit gap.
- 2026-09-07: differential regeneration changed only implementation/inventory
  provenance and dependent hashes. All four reviewed semantic observations,
  the 12 external classifications, and the 1,437 product-corpus split runs
  remained unchanged.
- 2026-09-07: the first full gate completed every test but static analysis
  found one directive-ordering info introduced by the new mouse-event import.
  The import was moved ahead of the mouse router; the repeated analyzer/full
  gate is required before completion.

## Verification results — focus reporting

- `dart run test/terminal_focus_reporter_test.dart`: passed mode set/query/
  reset/RIS, generation, exact bytes, duplicate suppression, immutability, and
  bound checks.
- `dart run test/terminal_compatibility_surface_test.dart`: passed after the
  generated 21-mode manifest was refreshed.
- `dart run test/terminal_compatibility_inventory_test.dart`: passed exact
  inventory/freshness/reconciliation totals.
- `dart run test/terminal_application_acceptance_test.dart`: passed normal and
  negative acceptance cases with 82 replayed unsupported increments.
- `make runtime-terminal-display-integration`: passed on Apple M1/arm64 in
  Developer JIT (2,754 ms) and Release AOT (2,043 ms). Both runs observed exact
  blur/focus bytes, one suppressed duplicate, reset, and disabled-mode silence
  through real zsh/PTY routing.
- `dart run tool/terminal_differential_corpus.dart`: passed 4 cases, 202 input
  bytes, and 210 split runs; regenerated observations changed provenance only.
- `dart run tool/product_parser_corpus.dart`: passed 8 reviewed cases, 1,421
  input bytes, and 1,437 split runs with snapshot hash 2,091,085,125.
- `CI=true make test`: passed all generated-artifact freshness gates,
  differential/application/terminfo acceptance, formatting of 179 files,
  static analysis with no issues, and the complete Dart test runner.
- `git diff --check`: run in the final pre-commit review.

## Verification results — SGR pixel mouse and highlight disposition

- `dart run test/terminal_mouse_encoder_test.dart`: passed mode-family
  exclusivity, DECRQM, reset/RIS, exact SGR pixel press/release bytes, and
  coordinate bounds.
- `dart run test/terminal_mouse_router_test.dart`: passed 1x/2x logical-to-
  physical conversion, edge clamping, overflow silence, invalid scale, and
  cell-based Shift selection including coordinates beyond the report bound.
- `dart run test/terminal_scroll_router_test.dart`: passed pixel wheel routing
  with one-based physical coordinates and preserved ownership arbitration.
- `dart run test/terminal_compatibility_surface_test.dart` and
  `dart run test/terminal_compatibility_inventory_test.dart`: passed the
  generated 22-mode/102-declaration surface and exact inventory reconciliation.
- `dart run tool/terminal_application_acceptance.dart --check`: passed eight
  immutable captures with two clean cells, six documented-gap cells, 11 gaps,
  17 variants, and 79 replayed unsupported increments.
- `make runtime-terminal-display-integration`: passed on Apple M1/arm64 in
  Developer JIT (2,752 ms) and Release AOT (2,099 ms). Both product runs enabled
  modes 1000/1016 in real zsh, preserved two Shift-local intents, and observed
  the exact scaled SGR pixel packet through the PTY.
- `dart run tool/terminal_differential_corpus.dart`: passed 4 cases, 202 input
  bytes, and 210 split runs after provenance regeneration.
- `dart run tool/terminal_differential_acceptance.dart`: passed 12 results as
  six agreements, two documented gaps, and four unavailable captures.
- `dart run tool/product_parser_corpus.dart`: passed 8 cases, 1,421 bytes, and
  1,437 split runs with unchanged snapshot hash 2,091,085,125.
- `dart analyze`: passed with no issues after correcting the import order.
- Repeated `CI=true make test`: passed every generated-artifact freshness,
  differential/application/terminfo gate, formatting of 179 files, static
  analysis with no issues, and the complete Dart test runner.
- `git diff --check`: run in the final pre-commit review.
