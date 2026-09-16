# Settings Function page navigation

- Status: complete
- Date/environment: 2026-09-17, macOS arm64

## Purpose and background

Make Fn+Up/Down useful for fast movement through the Settings document. The
current NORMAL controller handles only single-row arrows/j/k; PageUp/Down
are ignored. Keep the same attributed editor and existing selection reveal.

## Scope and exclusions

Support native PageUp/PageDown and translated Function+Up/Down in NORMAL.
Ordinary arrows retain single-line movement. INSERT remains AppKit-owned,
including marked text and native page commands. SEARCH retains its query and
match ownership, jumping ten matching options without changing the query.
No terminal input routing changes, new setting, config mutation, native API,
or unrelated navigator shortcut changes.

## Dependencies, acceptance, risks and verification

Begin after the Control+Tab diagnosis task is complete. Reuse
`moveCaretVertical` and the existing `scrollSelectionToVisible` presenter
contract: move the selection, then reveal it without recreating the document,
styles or editor. Bound/clamp movement at document edges and UTF-16 scalar
boundaries. Test repeated commands, ordinary arrows, modifiers, SEARCH and
INSERT, and fake/native viewport follow. Run formatter, analyzer, focused
tests, generated evidence freshness and both runtime configuration acceptance;
record actual results and review the diff before the completion commit.

## Decisions and findings

- NORMAL moves ten document lines, retaining the UTF-16 column where it fits;
  SEARCH moves ten option-name matches. Page movement clamps rather than wraps
  at either end, making repeated presses predictable. Single match Up/Down
  retain the existing wrapping behavior. INSERT remains native-owned.
- Support physical PageUp/Down (hardware 116/121) and arrow hardware codes
  carrying AppKit's translated PageUp/Down characters U+F72C/U+F72D.
  Do not infer physical Fn from `ModifierKeys.function`: ordinary native arrow
  events also carry that flag (`terminal_input_matrix.dart` fixtures confirm).
  Doing so would silently turn every ordinary arrow into a page command.
- Page commands accept Function/NumericPad/CapsLock provenance, but not
  Shift/Command/Control/Option. Document, dirty state, syntax, detail visibility,
  query, focus ownership and editor identity remain unchanged.
- No new generic native API is needed: the existing presenter reveals only
  actual selection changes using `scrollSelectionToVisible`.
- The initial multi-file patch failed because its docs context differed; it
  made no changes. Re-read the exact lines and applied the corrected patch.
- The user explicitly requested diagnosis only for Control+Tab after the
  asynchronous question. Do not alter that native routing in this task.

## Verification

- `dart format` on four changed Dart files: two formatted, no remaining issue.
- `dart analyze`: no issues. Settings editor and native-hierarchy focused
  tests: exit 0, including ten-line/match movement, edge clamping, translated
  arrows, ordinary Function-flag arrows, unsupported modifiers, empty matches,
  surrogate boundaries, INSERT delegation and fake native selection reveal.
- Reviewed public state getters before running tests: assert SEARCH via
  observable selection rather than exposing private match indices merely for
  tests. A guessed localization tool path did not exist; discovery with
  `rg --files tool` identifies the existing generator/check instead.
- Apple [keyboard shortcut reference](https://support.apple.com/102650)
  confirms Fn+Up/Down are PageUp/PageDown. Their ordinary native scroll-only
  semantics remain AppKit-owned in INSERT; NORMAL/SEARCH intentionally also
  move the caret/match for fast Settings navigation. The translated-arrow
  fallback is defensive input support, not a claim that physical Fn was
  captured manually on every keyboard model.
- Generated Phase 7 AppKit, regression coverage, Ghostty gap inventory and
  daily-use matrix evidence in dependency order; all four exited 0. Changes
  are source/test hashes, not weakened criteria or altered acceptance counts.
- `make RUNTIME_ARCH=arm64 runtime-configuration-integration`: both bundles
  built and passed, Developer JIT 1935 ms / Release AOT 1228 ms. The native
  Settings fixture checks ten-line down/up selection publication, repeated
  pages to the final option, unchanged document/window, then existing search,
  mode-invariant styles, editing, invalid/valid save, permissions, exactly-once
  reload and complete five-pane cleanup. Native keyboard delivery is injected
  through the AppKit event harness; physical keyboard models remain manual.
- ADR-005/ADR-002 boundaries remain unchanged: only Dart Settings navigation
  and its test fixture changed. No host, native dependency, PTY, renderer,
  worker ownership, menu reservations or standard keybind changes.
- Adjacent `dart_appkit` status still contains only its three pre-existing
  engine-building docs/scripts changes; they were not edited or staged.
- `make test`: exit 0, including all native package contracts, generated
  freshness/compatibility/privacy/distribution checks, 347 Dart files with zero
  formatting changes, analyzer with no issues, and full `test/run_tests.dart`
  (`dart_terminal tests passed`). Ran after both runtime builds, not alongside
  heavy native build work, to keep PTY lifecycle checks isolated.
- Final diff check passed. Only Settings implementation/acceptance tests,
  README, task records, source-hash evidence and task progress are changed.
  No user config, generic API, unrelated user changes or generated build
  artifacts are included. No remaining required implementation or automated
  acceptance work for this task.

## Manual follow-up (not an automated acceptance claim)

- On a physical keyboard, open Settings and press Fn+Down/Up in NORMAL, then
  search for an option family and repeat. Confirm the selected context stays
  visible and that ordinary arrows still advance only one row/match.
- In INSERT, confirm AppKit's standard page scroll and IME marked text remain
  natural. Automated coverage checks native-editing delegation rather than
  simulating every hardware/input-source combination.
- Control+Tab remains unchanged by explicit user choice; its known cause is
  documented separately. No other roadmap task or shortcut was implemented.
