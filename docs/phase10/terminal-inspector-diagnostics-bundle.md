# Phase 10 — Terminal inspector and diagnostics bundle

## Purpose

Complete the final ordered Phase 10 roadmap item by exposing a bounded,
privacy-safe terminal/parser inspector for the focused product pane and a
deterministic diagnostics bundle that a user can deliberately export. The
feature must help reproduce state and capability failures without copying
terminal contents, shell history, commands, environment values, clipboard
contents, paths, credentials, or opaque protocol payloads.

## Background and current position

- The preceding accessibility/localization parent completed in commit
  `1181639`. The roadmap was reread from a clean tree; this is now the first
  incomplete item and the last implementation item in Phase 10.
- Phase 6 already provides a bounded opt-in `VtParserInspector` and deterministic
  version-1 offline JSON trace exporter. It records parser action families,
  canonical headers, counts, lengths, recovery, and eviction without printable
  text or string payload bytes.
- Phase 8 already provides an effective-configuration inspector, typed
  diagnostics, and provenance. It is not a live terminal/parser inspector.
- Phase 1 defines local-only, content-free logging/crash metadata. Phase 11
  separately owns crash reports, hang samples, signing/update data, and the
  release diagnostics expansion; those must not be pulled forward implicitly.

## Scope

- Inventory the existing parser, pane/session, renderer, action/menu/palette,
  Settings/presenter, native file-panel, bundle metadata, and privacy contracts.
- Define immutable size/count/version/privacy contracts for a focused-pane
  inspector snapshot and an explicitly requested diagnostics export.
- Connect the inspector to the normal application action/focus lifecycle and
  keep capture disabled or bounded when the UI is closed.
- Export deterministic, user-initiated, content-free diagnostics with atomic
  file ownership, explicit success/failure/cancel behavior, and no ambient
  upload or network operation.
- Add unit/product/Developer JIT/Release AOT acceptance, documentation, matrix
  reconciliation, and a Phase 10 completion determination.

## Out of scope

- Crash report discovery, hang sampling, symbolication, upload, update checks,
  signing, notarization, and support-server integration (Phase 11).
- Printable terminal text, scrollback, command lines, title/cwd/path values,
  environment, clipboard/OSC 52 payloads, notification bodies, AppleScript
  input, image bytes, hyperlink targets, or parser string payload bytes.
- Long-duration usage and soak. The user explicitly allows those checks to be
  skipped and they are not a blocker for this task.
- Product-specific implementation in the adjacent generic `dart_appkit`
  repository. Any generic substrate discovered as necessary must remain
  product-neutral and accept product values from this repository.

## Dependencies and risks

- Depends on the existing shared action catalog/dispatcher, pane ownership,
  parser observer, renderer aggregate metrics, typed configuration snapshots,
  localization catalog, and runtime bundle manifest.
- The largest risk is accidental content disclosure through titles, cwd/source
  paths, exception strings, raw bytes, or user-entered configuration. Export
  types must be allowlisted rather than serialized from arbitrary objects.
- Inspector observation must never become parser backpressure, mutate canonical
  state, retain unbounded events, or outlive its pane/session.
- A save-panel or file-write substrate may require a generic AppKit addition;
  this will be decided only after inventorying existing injected callbacks.

## Initial completion conditions

- Every exported field has an owner, bound, privacy classification, and stable
  schema meaning documented and tested.
- Open/refresh/close/export actions are dynamically available and exactly once;
  terminal input does not receive their shortcuts or UI keystrokes.
- Inspector state follows the focused live pane, survives benign refreshes,
  and clears on pane close/application teardown without leaking observers.
- Export is explicit, deterministic, atomic, bounded, locally written, and
  covers success/cancel/failure without overwriting an unrelated file.
- Developer JIT and Release AOT use the ordinary application path and prove
  inspector/export behavior plus complete parser/pane/UI/native cleanup.
- Exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, focused checks, docs,
  matrix, generated evidence, roadmap state, and a dedicated commit complete
  each eventual ordered subtask.

## Validation plan

- Focused unit tests for schema bounds, privacy rejection, deterministic JSON,
  observer eviction/failure, action availability, focus changes, export
  cancel/failure/atomic success, localization, and lifecycle cleanup.
- Existing parser trace/fuzz/corpus gates to prove observation remains
  non-mutating and chunk-independent.
- Normal application acceptance using real AppKit, PTY, Metal, shared actions,
  and content-free assertions in both packaged runtimes.
- Static privacy/source audit over all diagnostics DTO/export owners.
- Full repository gate after regenerated derived evidence. Duration-only soak is
  recorded as intentionally skipped, not as an incomplete condition.

## Ordered subtasks

1. **Field inventory, privacy classification, and versioned contracts**
   - Freeze the exact snapshot/export allowlist, bounds, lifecycle, user
     interaction, and exclusions in this memo before changing product code.
   - Completion: every candidate source is classified; the implementation and
     test plan is reproducible; all later children are present in ROADMAP; the
     documentation-only contract is reviewed and committed.
2. **Generic save-destination panel substrate**
   - Add one synchronous main-thread AppKit save-panel abstraction in
     `dart_appkit`, with bounded injected title/message/default filename/file
     extensions and selected/cancelled/unavailable/failure outcomes.
   - No product name, terminal term, default product value, diagnostics policy,
     file write, or retained path belongs in the generic repository.
   - Completion: C ABI, FFI/fake bindings, native/Dart tests, headers/docs, and
     the complete generic repository gate pass in an adjacent-repository
     commit; this repository only consumes the released local package state in
     later children.
3. **Bounded live parser inspector and diagnostics export model**
   - Make the existing redacted parser decorator dynamically capturable and
     attach it to product sessions with capture off by default.
   - Define immutable focused-pane/application snapshots and deterministic
     version-1 JSON formatting plus atomic user-selected file export.
   - Completion: whole/split semantics remain equal, closed capture retains
     zero events, bounds/eviction/privacy/determinism/atomic success and failure
     are unit-tested, and the main full gate passes in a dedicated commit.
4. **Localized product window, shared actions, and export integration**
   - Add a single read-only inspector window, localized English/Japanese text,
     automatic focused-pane/capture handoff, and open/export shared actions in
     native menu, Command Palette, and optional keybind metadata.
   - Completion: focus change, pane close, cancel/failure/success, exactly-once
     dispatch, terminal-write zero, responder restoration, all UI/native owner
     cleanup, localization audit, and the normal full gate pass.
5. **Static privacy audit, dual-runtime acceptance, and closure**
   - Add a source/schema allowlist audit and ordinary-product Developer JIT and
     Release AOT acceptance for live redacted parser events, focused-pane
     switching, deterministic export bytes, menu/palette dispatch, and teardown.
   - Update README, FEATURE_MATRIX, privacy/reference/manual evidence, generated
     inventories, and decide Phase 10 completion. Long-duration checks remain
     explicitly skipped under the user's priority instruction.

Subtasks are strictly ordered and each receives its own verification,
ROADMAP state update, and commit. Phase 11 work cannot begin until all five and
the parent are complete.

## Inventory and field classification

### Existing owners reviewed

| Owner | Useful allowlisted state | Excluded state and reason |
| --- | --- | --- |
| `VtParserInspector` / `VtParserTraceExporter` | action kind/count, parser state, bounded CSI/DCS header metadata, payload length, terminator, eviction/observer-failure counts | printable scalars are count-only; OSC/DCS/APC payload bytes and input hash are unavailable by design |
| `TerminalScreenParserSink` | unsupported/cancel/limit/malformed/incomplete, reply/link/clipboard/graphics/notification/progress counts | no raw sequence or response bytes; no hyperlink target, clipboard value, notification title/body, or image data |
| `TerminalScreenSet` | rows/columns, active screen, viewport offset, mode booleans/enums, keyboard stack depth, transition/reset generations, resource counts | cell/grapheme/style contents, scrollback lines, title/cwd, semantic command text, notification/progress contents |
| `TerminalSession` / `TerminalPane` | lifecycle enum, live/disposed/backpressure and bounded aggregate counters | shell executable/arguments/environment/working directory, PTY input/output, failure/exception text, PID/PGID/session IDs |
| `TerminalLiveMetalSurfaceSnapshot` | logical geometry/scale, generation/frame/resource counts, pending/scheduled booleans, sync-output counters, preference booleans | accessibility UTF-16 length/selection/cursor position and hover cell are unnecessary content-shape data and will not be exported |
| hierarchy/application state | runtime kind, event protocol, window/tab/pane counts, active/Quick Terminal role, locale/direction, enabled feature enums | titles, represented URL/cwd, restoration paths, stable object IDs, timestamps, native handles |
| configuration/reload | schema option count, effective/attempt generations, diagnostic severity/code counts, live/new-session option counts | values, source/include paths, line text, user draft, CLI arguments, diagnostic free-form message/hint |
| existing feature controllers | bounded enablement and result enums/counters for Secure Input, Quick Terminal shortcut, notifications, App Intents, AppleScript, OSC 52 pending state | shortcuts as user-entered strings, notification/clipboard payloads, scripting input, external-owner identity, native error/exception text |
| Phase 1 runtime metadata | fixed schema/runtime/architecture/version/outcome/phase fields may be added by Phase 11 | launch ID, PID, wall-clock/path data and reading crash files are not needed for the Phase 10 live bundle |

The repository has no current native save panel. Settings already provides the
single-window/read-only `TextEditor` ownership pattern and focus restoration;
the action catalog/dispatcher/menu/palette already provide bounded dynamic
availability and exactly-once serialization. These are reused rather than
adding a second command system.

### Privacy classification

- **Public product constants:** format/version, product protocol versions,
  catalog/schema counts, enum names, hard limits.
- **Content-free runtime state:** booleans, bounded counters, generations,
  logical dimensions, enum dispositions, runtime mode, language/direction, and
  hierarchy counts. These may appear in the inspector and exported JSON.
- **Local transient path:** the path returned by the generic save panel may be
  used only by the atomic writer and discarded. It is never placed in the
  model, JSON, logs, machine markers, status text, or exception message.
- **Sensitive/excluded:** all terminal/user text and bytes; cwd/path/title;
  config values/drafts/source locations; argv/environment; clipboard,
  notification, AppleScript, hyperlink, image, and OSC payloads; raw errors and
  stack traces; stable IDs/handles/PIDs; timestamps/launch IDs. No generic
  serializer, reflection, `toString()` of product objects, or exception text is
  permitted at the export boundary.

### Version-1 bundle schema and bounds

The exported UTF-8 JSON is an ordered map with a trailing newline and these
exact top-level keys: `format`, `version`, `privacy`, `limits`, `application`,
`hierarchy`, `focused_pane`, `parser`, `renderer`, `configuration`, and
`features`. The format name is `dart-terminal-diagnostics`, version is `1`, and
the serialized output cap is 1 MiB. Same snapshot means identical bytes; wall
clock, random IDs, input hash, and destination path are deliberately absent.

- `privacy` states the exclusions and count/length-only policies as fixed
  schema values.
- `limits` publishes the 256 parser-record, 64 KiB parser-metadata, 256 KiB
  inspector-text, and 1 MiB JSON-output caps.
- `application` contains only runtime kind (`developerJit`/`releaseAot`), AppKit
  event protocol, language, direction, and three display-preference booleans.
- `hierarchy` contains bounded window/tab/pane/live-pane counts and the active
  window role only.
- `focused_pane` contains presence/lifecycle, rows/columns, active screen,
  viewport offset, mode enums/booleans, keyboard stack depth, resource counts,
  and bounded transport/backpressure aggregates without identity or text.
- `parser` contains the redacted inspector report and semantic sink counters.
  It never embeds or reconstructs PTY input; capture starts empty when the
  inspector opens and sees only subsequent typed actions.
- `renderer` contains the reviewed allowlist of geometry, scale, generation,
  frame/resource counts, pending/scheduled/synchronized-output and preference
  booleans. Content-shape accessibility and hover fields are omitted.
- `configuration` contains schema/effective/attempt generation and diagnostic
  code/severity aggregates only.
- `features` contains reviewed enablement/status enum names and bounded counts;
  absent controllers are explicit `unavailable`, never inferred from errors.

Unknown fields are not accepted by the static/schema test. Numeric values are
nonnegative and saturate or fail closed at their owning existing bound; string
values are fixed enum/schema tokens. Inspector rendering is independently
bounded to 256 KiB and shows a stable truncation/eviction summary when needed.

### Capture, UI, and export lifecycle

- Every product session owns a redacted inspector decorator so it can be
  enabled without replacing the parser/screen sink. Capture is false at
  construction and after close/dispose. Disabled forwarding does not allocate
  records, count printable content, invoke observers, or change downstream
  order/exceptions.
- Opening the single inspector window clears and enables only the currently
  focused live session. Focus handoff disables/clears the old session before
  enabling the new one; closing a pane or window yields either the new focused
  pane or an explicit unavailable snapshot. Closing the inspector clears all
  retained parser metadata.
- The inspector is a read-only, keyboard-closable AppKit text window. It
  refreshes from immutable snapshots and parser-event notifications, and never
  takes terminal bytes as display input. Closing restores the previously
  captured live terminal responder when still valid.
- `Open Terminal Inspector` is a View action with Option-Command-I.
  `Export Diagnostics…` is a File action with Option-Command-E. Both use the
  existing catalog, localization, dispatcher, native menu, Command Palette,
  and keybind grammar. Open requires a focused live pane; export requires the
  same snapshot but does not require the window to be open.
- Export invokes the generic save panel with all strings and `json` extension
  injected by this product. Cancel is a successful no-write disposition;
  unavailable and native failure are stable classified results. A selected
  path is written via a unique sibling temporary file, flushed, then atomically
  renamed only after complete encoding. Preexisting content is replaced only
  after native overwrite confirmation. Temporary files are removed on failure,
  the previous destination remains intact, and UI/machine evidence exposes
  only disposition and byte count—not the path or error string.

## Progress and findings

- 2026-09-13: created this memo before implementation after rereading README,
  ROADMAP, FEATURE_MATRIX, the clean worktree, Phase 6 parser inspector/trace
  references, Phase 8 Settings inspector/config diagnostics, and Phase 1
  logging/crash metadata. The current roadmap wording is a large cross-layer
  parent and requires ordered subdivision before product changes.
- 2026-09-13: inventoried the normal session parser/screen sink, redacted Phase
  6 inspector/exporter, screen modes and semantic counters, PTY lifecycle,
  live Metal snapshot, hierarchy, configuration inspector, feature status
  controllers, localization/action registry, Settings presenter, runtime
  metadata, and both repositories' AppKit APIs. No save-destination panel is
  currently exposed by the generic package.
- 2026-09-13: considered a fixed Application Support destination, a CLI-only
  output path, automatic Desktop/Downloads output, and a native save panel.
  Fixed or automatic paths make the exported artifact hard to find and can
  overwrite product-owned state; a CLI-only route does not complete the native
  product UI. Selected a generic save panel with product-injected strings and
  an atomic Dart writer. The selected path is transient and excluded from all
  diagnostics evidence.
- 2026-09-13: froze a ten-section ordered JSON allowlist and explicit field
  classification. Rejected generic object serialization and exception strings
  because either could silently expand the privacy surface. Parser capture is
  opt-in per focused pane, not an always-on history, and the Phase 11
  crash/hang/update expansion remains out of scope.
- 2026-09-13: split the parent into five ordered, independently reviewable
  children in ROADMAP before implementation. `git diff --check` passed for the
  contract/memo and roadmap-only change; there is no executable behavior to
  test in this first child.
- 2026-09-13: after commit `55c9a7f` (`Define inspector diagnostics privacy
  contract`), reread the roadmap and began only the generic save-destination
  child. The adjacent worktree is clean and has no repository-specific agent
  instructions. Its existing optional-binding pattern allows this API to be
  added without raising the base ABI or forcing legacy fakes to implement it.
- 2026-09-13: implemented the adjacent generic substrate as a synchronous,
  main-thread-only `NSSavePanel` boundary. All display strings, the default
  filename, one optional lowercase extension, and the directory-creation flag
  are copied from the caller under fixed UTF-8 limits. The API returns only a
  copied selected/cancelled result and never creates or writes a file. The C
  ABI result is borrowed only until the next panel call; the FFI layer validates
  and copies it immediately. Older native libraries fail closed through the
  existing optional-binding convention.
- 2026-09-13: added a native injected handler so tests cover selection,
  cancellation, presentation failure, copied Unicode input, invalid/unsafe or
  oversized input, invalid returned paths, malformed UTF-8, and wrong-thread
  calls without showing a real modal. Dart fake/API tests cover field injection,
  typed native failure, public validation, cancellation, and post-termination
  rejection. The README documents that content ownership and file writing stay
  with the caller.
- 2026-09-13: the first focused native build exposed a declaration-order
  designated-initializer warning under `-Werror`; reordering the test fixture
  fields resolved it. The next Dart analysis exposed two native result types
  omitted from the test's explicit `show` list; adding those imports resolved
  it. No product behavior or acceptance condition was weakened.
- 2026-09-13: adjacent validation passed with `make native-test dart-test
  validate`, including native tests, Dart analysis/API/launcher tests,
  `GENERIC_REPOSITORY_AUDIT_PASS`, and scaffold validation. Exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed the complete
  bridge, runner, runtime, example, FFI, and generic repository gate. The
  explicit forbidden-name search over every changed generic source, test,
  header, build, and documentation file returned no matches. Duration-only
  testing was intentionally not added under the user's priority instruction.
- 2026-09-13: committed the adjacent repository as `58dce74` (`Add generic save
  destination panel`). Its worktree is clean. This repository records the
  dependency milestone but does not yet consume product strings or add file
  writing; those remain ordered later children.
