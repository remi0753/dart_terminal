# Silent Escape in Settings

- Status: investigating
- Date/environment: 2026-09-17, macOS arm64, main
- Owners: Phase 8 Settings/UI-09, reusable adjacent AppKit text editor

## Purpose, background and scope

Stop the audible beep when Escape is pressed in Settings, without changing
INSERT/SEARCH -> NORMAL -> close semantics, document/styles/query ownership,
native IME editing, terminal focus restoration, save/reload or unrelated keys.
The main working tree was clean. Adjacent AppKit has three pre-existing engine
docs/scripts edits; preserve them and do not stage them.

README, ROADMAP, FEATURE_MATRIX, modal Settings docs and ADR-005 establish that
native reusable behavior belongs in adjacent AppKit. Settings NORMAL/SEARCH
route keys Dart-only; INSERT routes to both Dart and AppKit. The Dart handler
consumes Escape as a mode command, but asynchronous event posting cannot stop
that same native event reaching the responder before the Dart handler runs.

## Ordered work and acceptance

1. Investigate the native Escape fallback, then implement the smallest opt-in
   reusable mechanism in adjacent AppKit. Existing default native behavior
   must remain unchanged; preserve IME/completion ownership and typed handle,
   main-thread, legacy-symbol and API cache failure contracts. Native regression
   must observe whether Escape reaches an unhandled responder/beep path, not
   merely inject a Dart event. Verify and commit this dependency independently.
2. Apply that mechanism only to Settings, preserve/pull the latest native draft
   before leaving INSERT, and verify NORMAL, SEARCH, INSERT, repeated Escape,
   style/selection/draft preservation, close/focus/owner cleanup. Run focused
   unit/fake tests, generated evidence, both runtime configuration acceptance,
   formatter/analyzer/full main tests; update docs/progress and commit.

## Alternatives and risks

- Making INSERT Dart-only would suppress beeps but break native editing/IME;
  reject that workaround.
- Globally muting system sound or swallowing every Escape in every window is
  out of scope and would hide legitimate native cancellation.
- Prefer an explicit opt-in unhandled Escape fallback at the reusable editor
  boundary; inspect the actual selector/IME behavior before choosing it.
- No Control+Tab routing change (the user explicitly requested diagnosis only
  on that previous task), terminal/navigator shortcut change, configuration
  option, product native code or unrelated roadmap work.

## Findings so far

- Settings `_render` changes `window.keyEventRouting` between Dart-only and
  dual delivery. `_handleInsert` changes mode on Esc; native `DaWindow.sendEvent`
  posts before `super sendEvent`, so changing routing from Dart is too late.
- `synchronizeNativeEditor` pulls text/UTF-16 selection and renders. Leaving
  INSERT without an explicit final pull can also race its queued synchronization;
  tests must include a native draft update immediately before Esc.
- Selected instruction/code files were discovered with `rg --files`; two
  earlier guessed adjacent lib/test paths did not exist. Use the actual
  package/API and test tree rather than repeating guessed paths.
- Standalone AppKit reproduction confirms Esc becomes `cancelOperation:` and
  reaches the window when no native cancellation is handled (draft unchanged,
  one counted fallback, exit 0). The reusable change is an opt-in
  `TextEditor.suppressesUnhandledEscape` boolean, default false, at the outer
  wrapper's final fallback; inner text-view/IME event handling still runs first.
- Adjacent focused native and Dart API tests passed after correcting the test
  create-function signature and forwarding through `nextResponder.tryToPerform`
  rather than a nonexistent super cancelOperation implementation. A later
  noResponderFor observer produced zero counts because AppKit handles the final
  fallback at NSWindow.cancelOperation first. The final regression replaces
  that existing method temporarily, prevents sound in the test, and restores
  its original implementation without adding permanent class methods.

## Reusable capability completed

- Adjacent commit `41c5f3e` — `Add opt-in silent Escape fallback for text editors`.
  Generic task record: `../dart_appkit/docs/TEXT_EDITOR_ESCAPE_FALLBACK.md` (from
  repository root). Native `NSWindow.cancelOperation:` count is 1 by default,
  remains 1 after two enabled Esc presses, becomes 2 after reset. All three
  original Esc events still reach Dart once. Ordinary typing, metadata/style,
  marked-text state, handle/thread validation and legacy missing-symbol status
  8 are tested. The observer restores the existing method in finally.
- Adjacent focused tests, full `make test`, Dart format/analyzer and final
  formatted native rerun passed. Only the generic API/docs/tests were committed;
  the three pre-existing engine files remain dirty and untouched.
- Product application is now the next unchecked subtask. No Settings code was
  changed before the dependency was verified and committed.
