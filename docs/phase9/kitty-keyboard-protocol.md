# Phase 9 — Kitty keyboard protocol

## Task identity

- Date started: 2026-09-11
- Scope: first Phase 9 roadmap item
- Status: complete

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

- 2026-09-11: after committing subtask 2 as `dd92d5e` (`Implement progressive
  Kitty key event encoding`), ROADMAP and this memo were reread from a clean
  worktree. The next ordered target is product acceptance and compatibility
  closure. No later Phase 9 protocol is in scope until this parent item is
  accepted and committed.
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
- 2026-09-11: after committing subtask 1 as `341f938` (`Add bounded Kitty
  keyboard protocol controls`), ROADMAP and this memo were reread. The next
  ordered target is canonical key-event encoding and press/repeat/release
  routing; product acceptance and compatibility closure remain explicitly
  deferred to subtask 3.
- 2026-09-11: subtask 2 starts from a clean worktree. The existing native text
  input router currently discards key-up before adapting the event, while the
  direct AppKit router also rejects it. The release path must therefore be
  added at the composition boundary as well as the AppKit adapter/router, with
  release events bypassing keybindings and remaining silent unless Kitty's
  report-event-types policy permits an encoding.
- 2026-09-11: Kitty v0.48.2 defines press/repeat/release values 1/2/3, permits
  omitting the default press subfield, suppresses Enter/Tab/Backspace release
  unless all-keys reporting is active, excludes control code points from
  associated text, maps Command to Super and Option to Alt, and assigns the
  exposed F13–F20/keypad families to PUA values 57376–57383 and 57399–57416.
  The implementation keeps the AppKit `numericPad` origin bit separate from
  Num Lock state, because the former does not establish that Num Lock is on.
- 2026-09-11: the pinned xterm-411 contract and its current official manual
  agree that modifyOtherKeys level 1 retains well-known Shift/Control behavior,
  level 2 applies all ordinary-key modifiers, and level 3 also encodes
  unmodified keys as `CSI 27;modifier;codepoint~`. The pinned mintty page
  specifies application Escape exactly as `ESC O [`.
- 2026-09-11: a current Alacritty primary implementation was consulted only as
  corroborating comparison evidence: it omits the press event subfield, adds
  event types only for repeat/release, excludes associated text on release,
  routes release outside keybindings, and uses the canonical F3 `CSI 13 ~`
  form. Product behavior remains derived from the pinned protocol sources.
- 2026-09-11: direct formatting completed but then Dart telemetry attempted to
  update an existing user-cache timestamp outside the workspace sandbox and
  failed. Approved-cache focused encoder, adapter, and native text-input router
  tests passed. The first integrated `test/run_tests.dart` attempt stopped at
  the expected Phase 7 AppKit acceptance freshness gate after its covered input
  sources changed; `dart analyze` independently reported no issues. The
  acceptance ledger must be regenerated and the same runner repeated.
- 2026-09-11: the platform-independent event now retains an explicit
  press/repeat/release type. The former `isRepeat` constructor input and getter
  remain compatible, while AppKit and native text-input events translate key-up
  to release. Release bypasses the binding engine and application actions; the
  encoder emits it only when report-event-types is set and the key is reportable
  under the active progressive flags. IME-active raw events remain suppressed.
- 2026-09-11: Kitty encoding takes precedence over modifyOtherKeys whenever a
  progressive flag requires an escape representation. Default flags still use
  the original encoder branch byte-for-byte. Disambiguation covers Escape,
  modified ASCII keys, non-text functional keys, and dedicated keypad PUA
  values; F3 uses canonical `CSI 13 ~`, while F1/F2/F4 and cursor keys use the
  protocol's parameterized CSI forms independent of legacy application modes.
- 2026-09-11: alternate-key emission includes a shifted key only when Shift is
  active and its scalar differs, and includes the PC-101 physical base only
  when distinct, using an empty shifted subfield when required. Associated text
  is emitted only with all-keys plus associated-text, only for press/repeat,
  only when Ctrl/Alt/Super did not prevent text production, and only when the
  complete scalar list contains no C0/C1/AppKit private function placeholder.
  Unknown text-only input can use key zero; unsupported key-only physical
  positions return no bytes.
- 2026-09-11: xterm modifyOtherKeys states 1–3 are encoded separately in their
  `CSI 27;modifier;keysym~` form. Level 1 preserves well-known Control mappings,
  level 2 includes all modified ordinary keys (including the shifted keysym),
  and level 3 includes unmodified ordinary keys. Kitty state wins if both are
  active. The 256-byte product limit is enforced after every new encoding path.
- 2026-09-11: product acceptance first proves the unchanged legacy DECCKM Up
  bytes, then drives a real raw-mode PTY through Kitty state set/query on the
  primary and alternate screens. The child observes exact replies `CSI ? 1 u`
  and `CSI ? 10 u`; alternate-screen Control-D key-up reaches the PTY exactly as
  `CSI 100;5:3 u`, bypassing the matching key-down application action. Leaving
  the alternate screen restores the primary flags, and a final reset restores
  the zero-flag legacy policy. The complete asserted protocol exchange is 21
  bytes.
- 2026-09-11: the established product input injection boundary calls the same
  AppKit event router used by the native adapter, while focused native
  text-input tests separately prove key-up preservation at the C-ABI boundary.
  The product run therefore covers AppKit routing, parser-to-pane state,
  screen isolation, PTY ordering, and exact child-visible bytes without adding
  test-only encoder access.
- 2026-09-11: README and FEATURE_MATRIX now describe the completed progressive
  input surface. The Phase 6 compatibility matrix records the closure while
  retaining the immutable 57,737-byte, 32-snapshot application evidence.
  Replay remains at 63 unsupported increments, 6 variants, and 4 unrelated
  owned gaps; Neovim is clean. Regeneration changed only the README and
  FEATURE_MATRIX source hashes in the regression report, and only the product
  application source hash in the AppKit acceptance ledger.
- 2026-09-11: the first full normal gate stopped at its expected regression
  coverage freshness check after README/FEATURE_MATRIX changed. Running
  `make terminal-compatibility-regression-coverage` regenerated the derived
  report, after which the complete gate passed. A direct sandboxed formatter
  invocation also formatted successfully before Dart telemetry failed to touch
  its external cache timestamp; the normal gate's formatter completed with
  246 files unchanged and is the authoritative formatting result.

## Subtask 3 verification

- `CI=true DART_SUPPRESS_ANALYTICS=true make developer-jit-display`: passed on
  Apple M1/arm64 with the real AppKit/Metal/PTY product bundle, exact Kitty
  exchange marker, clean shutdown, 2x backing scale, and 3,010 ms elapsed.
- `CI=true DART_SUPPRESS_ANALYTICS=true make release-aot-display`: passed the
  same product assertions with the stock release AOT host and 2,206 ms elapsed.
- Final `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed every generated
  artifact and compatibility freshness check; regression replay covered 9
  cases, 390 bytes, and 417 split runs; the compatibility inventory retained
  266 records and 112 implementation declarations; differential acceptance
  retained 12 accepted cases, 8 agreements, zero owned gaps, and 4 unavailable
  external cases; application evidence retained 8 cells and 4 documented gap
  cells; formatting reported 246 unchanged files; analysis reported no issues;
  and the complete Dart test runner passed.
- `git diff --check`: passed before the final documentation and ROADMAP update.
  Generated artifacts and the final staged scope are reviewed immediately
  before the completion commit.

## Subtask 2 verification

- `test/terminal_key_encoder_test.dart`: passed legacy equivalence plus exact
  application-Escape and modifyOtherKeys levels 1–3 vectors; all exposed
  cursor/edit/F1–F20/keypad mappings; Super/Caps Lock handling; Cyrillic
  PC-101 base and shifted alternates; press/repeat/release suppression and
  emission; associated multi-codepoint text/control filtering; unsupported-key
  fail-closed behavior; and an oversized associated-text rejection.
- `test/terminal_appkit_key_adapter_test.dart` and
  `test/terminal_text_input_event_router_test.dart`: passed repeat/release field
  preservation and exclusive IME/raw delivery with key-up retained.
- `test/run_tests.dart`: passed mode-aware AppKit routing, including one
  requested arrow release write and a Control-D release which bypasses the
  matching key-down action. The regenerated Phase 7 AppKit acceptance ledger
  reports 4 criteria, 13 source references, 10 unit tests, 4 integration tests,
  and 8 UI assertions.
- Final `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed every generated
  artifact and compatibility freshness check, formatted 246 files without
  changes, reported no analyzer issues, and passed the complete test runner.
- `git diff --check`: passed before the ROADMAP progress update. Final staged
  scope is reviewed immediately before the subtask commit.

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
