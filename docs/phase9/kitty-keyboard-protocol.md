# Phase 9 — Kitty keyboard protocol

## Task identity

- Date started: 2026-09-11
- Scope: first Phase 9 roadmap item
- Status: subtask 1 complete; parent in progress

## Purpose and background

Add the Kitty keyboard protocol as a progressive, terminal-owned input mode
without regressing the Phase 5 legacy xterm encoder, IME commits, keybindings,
or AppKit menu arbitration. Close the four input-protocol gaps retained by the
immutable Phase 6 real-application capture: Kitty keyboard query, XTMODKEYS,
XTQMODKEYS, and application Escape mode.

The protocol origin specification requires bounded, independent main/alternate
screen flag stacks; query/set/push/pop controls; canonical CSI-u key encoding;
and optional repeat/release, alternate-key, all-key, and associated-text fields.
The implementation must keep the default flags at zero so legacy applications
continue to receive their existing byte stream.

## Ordered subtasks

1. **Protocol state, controls, and replies**
   - Add typed Kitty progressive-enhancement flags and bounded per-screen
     stacks to terminal state.
   - Parse/query/set/push/pop Kitty controls, reset them at RIS, and add exact
     reply/limit/chunk-independence coverage.
   - Reconcile observed XTMODKEYS/XTQMODKEYS/application-Escape compatibility
     controls with the Kitty mode without advertising ambiguous partial state.
2. **Canonical key-event encoding and routing**
   - Extend the platform-independent event with press/repeat/release identity.
   - Implement the Kitty functional/text/keypad code map, modifiers, event
     types, alternate keys, and associated text within the existing per-event
     byte bound.
   - Route release events only when requested; preserve keybind/menu ownership
     on key-down and the exact legacy path when no Kitty flags are active.
3. **Product acceptance and compatibility closure**
   - Exercise parser-to-pane mode projection and AppKit-to-PTY bytes, including
     main/alternate isolation and a legacy regression case.
   - Replay the immutable application evidence, remove only the four now
     implemented owned gaps, regenerate compatibility artifacts, and update
     README/FEATURE_MATRIX.
   - Run focused tests, format/analyze, the full normal gate, and the applicable
     M1 Developer JIT / Release AOT product acceptance before closing the task.

The subtasks are ordered. Each is independently verified, documented, marked
in ROADMAP, and committed before the next one begins.

## Scope

- Kitty protocol flags 1, 2, 4, 8, and 16, with unknown bits masked out.
- `CSI = flags ; mode u`, `CSI ? u`, `CSI > flags u`, and `CSI < count u`.
- Separate bounded state stacks for primary and alternate screens.
- Canonical key encoding for all physical keys currently exposed by the macOS
  adapter, including press/repeat/release and associated Unicode text.
- Default-zero progressive enhancement and exact legacy compatibility.
- Existing Phase 6 owned input-protocol gaps and their immutable replay.

## Out of scope

- New physical modifier-only key events not exposed by the current AppKit ABI.
- Keyboard layout changes, IME composition semantics, keybind grammar, or menu
  shortcut policy beyond preserving their established ownership boundaries.
- Synchronized output, theme reports, graphics, notification, and clipboard UI,
  which remain later ordered Phase 9 tasks.
- Copying Ghostty or Kitty source into the product.

## Dependencies and initial facts

- `TerminalKeyboardModes` currently exposes only DECCKM and DECPAM; its state is
  owned by `TerminalScreenSet` and read at the pane input boundary.
- `TerminalKeyEncoder` is bounded to 256 bytes and intentionally implements the
  Phase 5 legacy xterm contract. Command-key events fail closed.
- AppKit key events already distinguish down/up and repeat, but the current
  product adapter discards down/up identity and the router rejects key-up.
- The parser compatibility surface and generated implementation manifest make
  selector/mode additions reviewable and freshness-gated.
- The immutable application evidence currently has 71 unsupported increments,
  12 variants, and 8 gaps. Four gaps belong to this task.
- Kitty's official specification defines five flags, set/augment/subtract
  modes, a query reply, and bounded oldest-entry eviction for independent
  main/alternate flag stacks.

## Design decisions

- Keep Kitty state inside `TerminalScreenSet`, but use one bounded state object
  per screen rather than a global stack. Active-screen switching therefore
  changes the encoder-visible flags without copying state.
- Treat the specification's five known bits as the advertised surface. Unknown
  input bits are ignored rather than retained or echoed.
- Preserve XTMODKEYS and XTQMODKEYS as xterm compatibility controls with their
  own bounded modifier policy; do not silently alias their numeric semantics to
  Kitty flags. Application Escape mode is handled as the equivalent
  disambiguation request already observed from tmux.
- Key-up bypasses keybindings and application actions. It is encoded only when
  the active Kitty flags request report-event-types; key-down keeps the existing
  exactly-once binding/menu arbitration.

## Completion conditions

- All five progressive enhancements encode according to the protocol origin
  documented cases, and default mode remains byte-identical to the legacy tests.
- State/reply controls are chunk-independent, bounded, independently stacked per
  screen, and atomically reset by RIS.
- Unknown flags, excessive push/pop, unsupported physical keys, large associated
  text, and command/menu-owned events fail safely within existing bounds.
- Neovim/lazygit/tmux captured input-protocol controls replay without an owned
  input-protocol reject, while unrelated Phase 9 gaps remain explicit.
- Focused, full, and both M1 runtime product gates pass with no leaked PTY,
  worker, text-input, Metal, or native-handle resources.

## Verification plan

- Focused unit tests for state, parser controls/replies, encoder vectors,
  release suppression, bounds, and legacy equivalence.
- Compatibility manifest/inventory/application-acceptance freshness checks.
- `dart analyze`, `CI=true make test`, and diff/staged-scope review.
- The existing dual-runtime user-action/input product suite, extended with
  exact Kitty query/mode/key bytes if its injection boundary is sufficient.

## Investigation log

- 2026-09-11: ROADMAP, README, FEATURE_MATRIX, repository layout, current
  worktree, Phase 6 application evidence, keyboard state/encoder/router, parser
  compatibility surface, generators, and normal test gate were inspected. The
  worktree was clean and `main` was 51 commits ahead of `origin/main`.
- 2026-09-11: the first unchecked ROADMAP item is Kitty keyboard protocol and
  Phase 9 must stop after all its items, or earlier for a serious blocker.
- 2026-09-11: the Kitty protocol-origin documentation confirms flags 1/2/4/8/16,
  query/set/push/pop syntax, independent primary/alternate stacks, and bounded
  oldest-entry eviction. The pinned Ghostty paths named by FEATURE_MATRIX remain
  comparison evidence only; product code will be independently implemented.
- 2026-09-11: subtask 1 stores Kitty flags in separate primary/alternate
  16-entry stacks. Push at capacity evicts the oldest saved entry, an excessive
  pop returns to flags zero, and RIS clears both stacks plus application-Escape
  and modifyOtherKeys state. Unknown Kitty bits are masked and never echoed.
- 2026-09-11: parser dispatch now accepts exact Kitty query/set/push/pop forms,
  XTMODKEYS resource 4 values 0–3, XTQMODKEYS resource 4, and mintty DEC private
  mode 7727. Invalid resource IDs, parameter counts, set modes, and zero pop
  counts remain bounded rejects. Query replies use the existing 64-byte
  terminal reply builder.
- 2026-09-11: the primary sources were pinned by exact retrieved bytes:
  kitty v0.48.2 `keyboard-protocol.rst` is 36,641 bytes with SHA-256
  `cd452d4f1b5070752499233f8d76455c854d0ec5f2318e38309f835baf2410ce`;
  mintty historical CtrlSeqs is 264,856 bytes with SHA-256
  `4144a9212fdc412088d5a094a09d827d729082239c8fbb7ef7b163d13d5d9d0e`.
  The first sandboxed downloads failed at DNS resolution and were repeated
  through approved network access. A codeload archive probe returned 404, so
  the exact historical wiki page URL and retrieved-content hash are the pin.
- 2026-09-11: adding the two source families initially made summary generation
  fail because the typed inventory schema admitted only its five prior
  families. The schema, ID grammar, exact-family invariant, source tests, and
  generated summary were extended together; no unknown-family fallback was
  introduced.
- 2026-09-11: the first declaration test used generic parameter `0` for the
  newly declared XTMODKEYS selector and correctly rejected `CSI > 0 m`. Its
  canonical probe now uses the valid empty reset form. The first acceptance
  edit also changed the adjacent mosh classification instead of Neovim; replay
  caught the mismatch and the two exact cell labels were corrected.
- 2026-09-11: immutable application replay removed six now-supported variants:
  Kitty query, both XTMODKEYS forms, XTQMODKEYS, and application-Escape
  set/reset. Current totals are 63 unsupported increments, 6 variants, and 4
  owned gaps; Neovim is the fourth clean agreement. The enclosing keyboard
  task remains incomplete because key-event emission is the next subtask.
- 2026-09-11: regenerating the implementation surface intentionally made the
  Dart differential baseline provenance stale. The four 202-byte baseline
  observations and aggregate acceptance were regenerated against the new
  surface hash; semantic results remain 12 accepted, 8 agreements, 0 owned
  differential gaps, and 4 unavailable external cases.
- 2026-09-11: direct Dart tests first failed inside the workspace sandbox when
  telemetry and Metal build hooks could not write existing user cache paths.
  Approved external-cache reruns passed. The first full normal gate then found
  only the recorded-vim parser oracle stale: unsupported sequences changed
  6→2 and accepted replies 3→4 while every visible snapshot line matched. The
  exact counter line and aggregate snapshot hash `995854368` were updated;
  exhaustive 1,437 split/bytewise runs passed afterward.

## Subtask 1 verification

- `test/terminal_reply_test.dart`: passed exact Kitty/XTMODKEYS/XTQMODKEYS/
  mode-7727 replies, malformed forms, fixed stack bound, and every split of the
  new control stream.
- `test/terminal_screen_set_test.dart`: passed primary/alternate isolation and
  RIS reset.
- compatibility surface, inventory, application acceptance, differential, and
  regression coverage focused tests: passed; inventory revision 3 has 266
  records, 112 product declarations, and 7 source pins.
- `test/product_parser_corpus_test.dart`: passed 8 cases, 1,421 input bytes,
  1,437 split runs, and snapshot hash `995854368`.
- Final `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed all freshness
  checks, formatted 246 files without changes, reported no analyzer issues,
  and passed the complete test runner.
- `git diff --check`: passed before the ROADMAP progress update. Final staged
  scope and generated-artifact freshness are reviewed immediately before the
  subtask commit.
