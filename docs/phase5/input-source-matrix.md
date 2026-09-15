# Phase 5 — input-source and repeat matrix

- Status: complete
- Date: 2026-09-06
- Updated: 2026-09-15
- Scope: third Phase 5 production-input roadmap item
- Related: IN-01, IN-02, IN-03, IN-04, TXT-01, TXT-03

## Purpose

Turn US/JIS positions, dead-key results, CJK/emoji/Unicode commits, and key
repeat from individually tested implementation details into one reproducible
product matrix. Every automated row must pass through the registered AppKit
terminal view, the bounded native event queue, the product router, and a real
PTY without duplicate or intermediate bytes.

## Background

The preceding task completed the reusable `NSTextInputClient`, preedit overlay,
candidate geometry, and single-delivery product path. Existing tests already
map all macOS US/JIS physical positions and shape CJK/emoji, while the staged
product acceptance proves Japanese marked/update/commit/cancel. What remains is
an explicit cross-layer corpus for final text produced by dead keys and system
pickers, non-Japanese CJK, JIS printable positions, and repeated raw keys.

Phase 0 deliberately did not change the user's selected macOS input source.
This production matrix keeps that safety property: automated tests call the
same real `NSTextInputClient` methods used by input methods but do not globally
select, add, or remove keyboard/input sources. A human checklist will document
the visible system UI checks that cannot be made deterministic without mutating
the user's global input state.

## Scope

- Define immutable matrix rows with stable IDs, source category, expected
  native event kind/count, and exact UTF-8 or xterm bytes.
- Cover US lower/upper output, JIS yen/underscore output, composed dead-key
  Latin, Chinese and Korean commits, emoji ZWJ, Unicode Hex-style scalar output,
  first/subsequent repeated navigation input, and Option-Left／Right shell word
  navigation.
- Drive final text through `insertText:replacementRange:` and repeated raw
  navigation through the product view's raw command path.
- Read the concatenated result from a real no-echo/raw PTY and require exact
  bytes in Developer JIT and Release AOT.
- Preserve the existing Japanese marked/update/candidate/commit/cancel case as
  the CJK composition row and keep US/JIS physical mapping tests exhaustive.
- Publish a non-mutating manual checklist for real US/JIS hardware/input-source
  switching, visible dead-key state, Japanese conversion candidates, Character
  Viewer/emoji picker, Unicode Hex Input, and held-key repeat.

## Out of scope

- Installing, enabling, disabling, or globally switching the user's macOS
  input sources from a test process.
- Assuming that a particular keyboard, locale, Chinese/Korean IME, or Unicode
  Hex Input is installed on every build host.
- Changing terminal key encoding beyond the bounded Option-Left／Right word
  navigation correction, IME ownership, font fallback, or preedit layout
  semantics already accepted by the preceding tasks.
- Kitty keyboard, Secure Input, accessibility, mouse, selection, and paste.

## Dependencies and risks

- The matrix depends on `KeyEventRouting.appKitOnly`,
  `DtrTerminalMetalView<NSTextInputClient>`, the bounded native queue, and the
  product event router completed immediately before this task.
- `insertText:` is the common final-text callback for dead keys, emoji picker,
  Unicode Hex Input, and IME commit; deterministic automation can validate that
  common boundary but not the OS UI used to choose a result.
- Repeat must remain separate events rather than coalesced marked updates.
  Queue count and real PTY byte count catch accidental loss or duplication.
- Diagnostic output must expose only row IDs, counts, booleans, and hashes/hex
  of fixed public fixtures; it must not log user input.

## Completion criteria

- The versioned matrix is immutable, bounded, rejects duplicate/invalid rows,
  and has unit coverage for every required category.
- Native capability tests drive every automated row through the product view
  and prove exact event order, repeat flags, produced fields, and no queue
  remainder.
- Developer JIT and Release AOT read the exact expected byte stream from a real
  PTY, emit one content-free matrix result, and retain all earlier display/IME
  acceptance.
- The manual checklist names setup, action, expected visual/PTY behavior,
  restoration, and evidence fields without requiring the automated test to
  mutate global input state.
- Full tests, source audit, both bundle audits, and relevant real-window smoke/
  display/resource checks pass with both repositories clean.

## Verification plan

- Add pure Dart matrix validation and router/encoder expectation tests.
- Extend the dependency-owned staged acceptance ABI with one matrix operation;
  validate its fixed packet and real native events in capability tests.
- Extend the display suite's raw PTY reader with a fixed exact-byte matrix and
  require its machine line in both product modes.
- Run `make test` in `dart_appkit` and `dart_terminal`, source/bundle audits,
  both display integrations, and ownership/resource integration.

## Investigation log

- 2026-09-06: project commit `3bed13a` completed the previous roadmap item;
  both repositories were clean before this matrix task began. The first
  unchecked roadmap item is this matrix.
- 2026-09-06: existing exhaustive virtual-key tests cover the US ANSI positions,
  JIS yen/underscore/keypad-comma/Eisu/Kana codes, navigation, function keys,
  keypad, independent produced/unmodified text, seven modifiers, and repeat.
- 2026-09-06: existing native/product acceptance covers Japanese `にほんご`
  marked state, candidate round-trip, exactly one `日本語` PTY commit, a
  cancellable `かな`, and raw suppression during marked text.
- 2026-09-06: CoreText/Metal tests already cover Chinese/Japanese glyph fallback,
  Korean/combining shaping, color emoji ZWJ/modifier/flag clusters, and 1x/2x
  raster output. The new matrix must test their input delivery, not duplicate
  font qualification.
- 2026-09-06: chose a fixed version-one corpus with 12 rows, 13 native events,
  seven categories, and 51 expected PTY bytes. Ten commit callbacks cover US,
  JIS, composed Latin, CJK, emoji ZWJ, and a Unicode scalar; initial plus two
  repeated Right Arrow callbacks cover repeat identity.
- 2026-09-06: a test-gated custom view operation calls the registered product
  view's real `insertText:replacementRange:` and `doCommandBySelector:` paths.
  It carries only a client ID; text remains a fixed native fixture and no
  Objective-C object or user input crosses the ABI.
- 2026-09-06: `dart_appkit` commit `d715c86` added the native operation and
  capability assertions. Its complete `make test` passed, including the
  terminal renderer native and Dart suites.
- 2026-09-06: real input-source switching cannot be deterministic without
  mutating per-user macOS state. The automated matrix therefore qualifies the
  common callback/PTY boundary, while
  [`input-source-manual-checklist.md`](input-source-manual-checklist.md) covers
  physical hardware, system pickers, candidates, and restoration.
- 2026-09-15: matrix version 2 extends the fixed corpus with Option-Left and
  Option-Right native raw-key events. The events retain physical key codes
  123/124, Option+Function modifiers, and AppKit private-use characters before
  the product encoder writes exact `ESC b`／`ESC f` bytes to the PTY.
- 2026-09-06: the first Developer JIT display run delivered all 13 native
  events but timed out while searching for a marker containing the complete
  102-character hex result. The marker soft-wrapped beyond one screen row, and
  the acceptance helper intentionally searches canonical rows independently.
  The PTY script now compares the 51 captured bytes to the fixed expected hex
  itself and exposes only a short `EXACT` or `MISMATCH` marker; this preserves
  byte equality without depending on viewport width.

## Verification results

- 2026-09-06 follow-up: the later mouse product acceptance exposed that an
  unrelated native key-up/cancel event may advance the shared text-input client
  generation after all 13 matrix fixtures. The product readiness assertion now
  accepts that monotonic suffix while still requiring inactive composition and
  the unchanged byte-exact 51-byte PTY payload; missing or duplicate fixture
  input therefore still fails closed.

- Current matrix identity: version 2, 14 immutable rows, 15 events, seven required
  categories, and 55 exact PTY bytes. Unit tests also reject duplicate/invalid
  IDs, missing categories, unbounded repeat, and collection mutation.
- `CI=true make test` in `dart_terminal`: passed. The parser table freshness
  check, formatter (118 files, zero changes), analyzer, build hooks, and full
  Dart test runner all passed.
- `make test` in `dart_appkit`: passed. This includes native renderer capability
  checks for ten ordered commits, three ordered Right Arrow events, initial vs
  repeat flags, exact UTF-8/PUA fields, empty queue, and client cleanup, plus all
  repository native/Dart/runtime/PTY tests.
- `CI=true make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`:
  passed for Developer JIT and Release AOT. Each real AppKit window accepted the
  complete native matrix through the product router into a raw real PTY, whose
  shell-side comparison now requires all 55 bytes to match exactly. Earlier IME,
  Metal, SGR, wrap, bottom-prompt, font, and newest-frame assertions remained
  required and passed.
- `CI=true make RUNTIME_ARCH=arm64 runtime-source-check
  runtime-bundle-audit runtime-integration runtime-resource-integration`:
  passed. Both bundle audits reported one helper, one native asset, and one
  capability; both normal smokes passed; both resource runs returned from 1,000
  Window/View iterations to baseline 12 with peak 14.
- Source audit reported 208 tracked product files and zero native source files.
  Both `dart_terminal` and `dart_appkit` worktrees contained only the intended
  task changes before their respective commits.
- Manual OS-source/hardware checks were not executed or simulated by changing
  user settings. The bounded, restoration-aware checklist is published at
  [`input-source-manual-checklist.md`](input-source-manual-checklist.md).
- Tooling notes: an initial sandboxed test could not write Clang's user module
  cache and was rerun with the normal approved build environment. The two new
  Dart files also needed one write-mode formatter pass before the format gate
  accepted them. Neither issue changed product behavior or acceptance scope.

### 2026-09-15 — Option-arrow matrix extension verification

- `make terminal-renderer-native-test` passed with ten ordered commits, three
  Right Arrow repeat events, and two ordered Option-Left／Right events. The new
  events preserve key codes 123/124, Option+Function modifiers, private-use
  text fields, and empty-queue cleanup.
- Developer JIT and Release AOT display integration both passed the version 2
  real-PTY comparison: 14 rows, 15 native events, and 55 exact bytes including
  final `1b 62 1b 66`.
- The complete `make test` gate passed after regenerating all dependent
  compatibility evidence.
