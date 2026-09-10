# Editable modal Settings editor

- Status: in progress
- Started: 2026-09-11 after commit `e215e14`
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `schema-complete modal settings editor と contextual detail panel`
- Feature-matrix owners: UI-09 and CFG-07
- Depends on: `docs/phase8/settings-effective-config-inspector.md`,
  `docs/phase8/safe-configuration-reload.md`,
  `docs/phase8/product-option-families.md`, and the generic `dart_appkit`
  Window/View/SplitView boundary

## Purpose

Replace the read-only effective-configuration inspector with a focused native
configuration editor. The configuration document is the primary surface, every
schema option remains discoverable even for a missing or sparse root file, and
the contextual detail pane explains the option under the caret without turning
Settings into a conventional form or permanently visible dashboard.

The editor uses NORMAL, INSERT, and SEARCH interaction states. NORMAL and
INSERT must render the exact same syntax-highlighted document with the same
font, colors, spacing, and selected configuration context. Entering INSERT may
change only input interpretation, caret visibility/shape, and the compact mode
status; it must never replace the highlighted editor with a plain text field or
otherwise make the document look visually different.

## Background

- The completed Phase 8 Settings surface is a bounded display-only `TextView`.
  It makes all 36 effective entries searchable and explains canonical value,
  provenance, policy, and diagnostics, but it cannot edit or persist the root
  configuration.
- The current key controller assigns every printable key to search. That is
  efficient once learned but surprising in a settings editor; search should be
  an explicit `/` command from NORMAL instead.
- The current inspector gives title, generation, file, matches, list, selected
  detail, diagnostics, and commands equal visual weight. The revised surface
  keeps the configuration document dominant and moves explanation into a
  contextual right pane with a narrow persistent rail when collapsed.
- The product already owns typed parsing, canonical formatting, diagnostics,
  reload serialization, last-known-good publication, and per-option
  live/new-session policy. Editing must reuse these authorities rather than
  introduce a second configuration grammar or apply path.
- The adjacent `dart_appkit` repository currently exposes only a custom-drawn,
  display-only `TextView`. Replacing that view with a separate plain native
  input control in INSERT would lose syntax color and violate the requested
  mode-invariant presentation. A reusable attributed editable surface is
  therefore required in `dart_appkit`; terminal-specific native source remains
  prohibited in this repository.

## Scope

- Build a bounded editable root-document projection from the schema and the
  existing root file. Preserve readable user text and comments, then include a
  clearly delimited schema catalog for options not already represented. A new
  or empty file receives a complete canonical scalar scaffold; nullable and
  repeatable options receive explicit commented examples rather than invented
  active values.
- Keep included-file and command-line precedence honest. Missing options whose
  effective value comes from another source are represented without silently
  pinning or overriding that source merely because Settings was opened.
- Validate the complete draft through the existing loader semantics before any
  replacement. On an error, retain both the draft and the last-known-good
  effective configuration and show actionable diagnostics. On success, write
  UTF-8 atomically in the root file's directory and dispatch the existing
  shared reload action; no second application path is allowed.
- Add NORMAL, INSERT, and SEARCH state with bounded cursor/selection/query
  behavior. `i` and `a` enter INSERT before/after the current caret, `Esc`
  returns from INSERT/SEARCH to NORMAL before it closes the window, `/` enters
  SEARCH only from NORMAL, arrows and `j`/`k` navigate in NORMAL, and Command-S
  validates/saves from either NORMAL or INSERT.
- Compute syntax and diagnostic spans from the same document in Dart. The span
  projection is independent of editor mode. The option under the caret drives
  the right pane, including syntax, description, current/draft value, and a
  direct outcome label such as `Open terminals: changes immediately` or
  `Open terminals: keep current value`; it does not expose line or source rows.
- Compose a native window whose title is the root filename, with the editor as
  the dominant left surface, a compact command/mode status, and a contextual
  right pane. The right-pane rail stays visible while collapsed and owns its
  open/close affordance; there is no duplicate filename, top search button,
  `Config Lens` title, oversized effective-value card, or generic settings
  sidebar.
- Extend `dart_appkit` with a generic scrollable attributed text editor that
  can atomically set a document, update style runs without replacing the text,
  toggle editability, read text/UTF-16 selection, and set selection. AppKit
  remains responsible for ordinary INSERT editing and selection; Dart remains
  responsible for modes, schema syntax spans, persistence, and product policy.
- Update unit, fake-AppKit, generated evidence, README, and feature matrix, then
  exercise edit/invalid-save/valid-save/reload/focus/cleanup in Developer JIT
  and Release AOT on the M1 baseline.

## Out of scope

- A generic preference-form widget hierarchy, per-option popovers, cloud sync,
  remote includes, automatic filesystem watching, SIGHUP, per-pane overrides,
  or editing every included file as a multi-document project.
- Reformatting or flattening a readable existing root file on open, silently
  overwriting include-owned values, or persisting anything before an explicit
  save command.
- Vim command parity beyond the documented modal entry/navigation/search/save
  commands, plugin scripting, macros, arbitrary Ex commands, or turning the
  Settings editor into a general-purpose text editor.
- Completing the full generic IME/Undo/accessibility program tracked by
  `dart_appkit` G5/G6. The reusable surface must retain AppKit's ordinary
  NSTextView editing path and must not make future IME support impossible, but
  this task does not claim those separate roadmap goals complete.
- Phase 9 protocols or Phase 10 terminal/parser inspector work.

## Dependencies and boundaries

- `TerminalConfigSchema` owns option names, order, defaults, syntax,
  descriptions, canonical formatters, repeatability, and application policy.
- `TerminalConfigLoader` remains the grammar and validation authority. Draft
  validation uses an overlay for the root bytes while includes continue through
  the configured filesystem; a UI-only parser may locate/color lines but may
  not decide whether a value is valid.
- `TerminalConfigReloadController` remains the accepted snapshot and
  single-flight publication authority. A successful file replacement is
  followed by the existing `application.reload-configuration` dispatch.
- Root-file writes use a sibling temporary file, flush, and atomic rename. The
  implementation must clean up its own temporary artifact on failure, preserve
  an existing file's permission bits where supported, and never overwrite a
  different path derived from editable content.
- Every document, query, style-run, diagnostic, and rendered-detail field has a
  hard bound. UTF-16 ranges passed to AppKit are checked against scalar
  boundaries; invalid or overlapping attributed runs are rejected atomically.
- The Settings window remains a root-isolate/main-thread owner. It creates no
  terminal pane, PTY, renderer, or worker and releases every editor, status,
  detail, split, and window handle before restoring the prior terminal first
  responder.
- The generic native implementation and ABI live only in `dart_appkit`.
  `dart_terminal` consumes public package APIs and retains zero product-native
  source files.

## Completion conditions

1. A missing, empty, sparse, included, or ordinary root configuration opens as
   one bounded editable document where all 36 schema options are represented
   exactly once in either active content or the generated catalog, without an
   implicit write or semantic override.
2. Invalid drafts never replace the root file or effective snapshot. A valid
   explicit save is atomic, reloads through the shared action, preserves open
   pane/PTY/native resource identity, and reports whether open terminals change
   immediately or only later terminals use the new value.
3. NORMAL, INSERT, and SEARCH obey the documented keys and do not leak text to
   the PTY. INSERT can edit the complete buffer rather than one value cell.
   NORMAL and INSERT expose byte-for-byte identical text and identical syntax
   style runs; only mode/caret chrome differs.
4. The native UI keeps the editor dominant, has one filename in the title,
   shows the right-pane affordance on its own persistent rail, follows the
   caret's schema option, omits all line/source/`APPLIES` rows, and uses balanced
   typography for current value, syntax, description, diagnostics, and
   after-save outcome.
5. Reopen, repeated mode changes, collapsed/open detail, rejected save,
   accepted save/reload, close, application quit, and failure paths retain one
   presenter and release all native handles while restoring terminal focus.
6. Focused model/storage/native tests, formatting, analysis, complete tests,
   source/bundle audits, and M1 Developer JIT/Release AOT configuration-product
   acceptance pass. README, UI-09, CFG-07, and Phase 8 completion evidence agree
   before this session stops.

## Ordered subtasks

1. Add the schema-complete document composer, root overlay validation, and
   atomic persistence transaction. Cover new/sparse/include-owned content,
   UTF-8/size failures, invalid-draft non-write, successful replacement, and
   temporary-file cleanup without changing the native inspector yet.
2. Replace the inspector-only model with NORMAL/INSERT/SEARCH, full-buffer
   cursor/edit synchronization, option lookup, contextual detail, diagnostics,
   and mode-independent syntax spans. Keep it UI-independent and cover every
   transition and bound.
3. Implement and commit a generic attributed editable text surface in the
   authorized adjacent `dart_appkit` repository, then record its dependency
   revision here. Verify public Dart validation, fake/FFI binding compatibility,
   native bridge ownership, selection/editability, scrolling, styling, and
   complete adjacent-package gates.
4. Compose the product Settings window from the generic editor, nested split
   layout, compact status, and right detail/rail. Connect native text/selection
   snapshots, modal routing, shared save/reload, singleton/focus lifecycle, and
   failure cleanup; replace the read-only presenter tests and product exercise.
5. Run the full generated/configuration/source/bundle regression gates and the
   M1 Developer JIT/Release AOT product acceptance. Reconcile user-facing docs
   and feature evidence, mark the child and parent complete, commit, reread the
   roadmap, and stop before Phase 9.

## Validation plan

- Focused Dart tests for document composition/storage and modal/syntax state.
- `dart_appkit` public API, fake binding, FFI current/legacy, C/C++ header,
  Objective-C++ bridge, staged real-window selector, format, analyze, and full
  `make test` gates.
- Fake-AppKit hierarchy assertions for exact resources, first responder,
  routing changes, same style runs across modes, collapsed/open detail, save
  outcomes, close/reopen, and zero leaked handles.
- `dart format --output=none --set-exit-if-changed`, `dart analyze`, focused
  configuration tests, full `make test`, product-native source audit, manifest
  and bundle audit, and `git diff --check`.
- `make RUNTIME_ARCH=arm64 runtime-configuration-integration` for both packaged
  runtimes with a real temporary root configuration and live PTY hierarchy.

## Findings and decisions

### 2026-09-11 — task start and architecture boundary

- `ROADMAP.md` had all Phase 8 items complete and Phase 9 Kitty keyboard as the
  first unfinished item. This user-requested Settings correction belongs after
  the completed Phase 8 inspector item, so adding it there deliberately reopens
  Phase 8 and makes it the first unfinished work. Phase 9 remains untouched.
- The current presenter owns exactly one `Window` and one display-only
  `TextView`, sets `KeyEventRouting.dartOnly`, and rewrites one plain string for
  every search/selection/reload update. Its key controller treats all printable
  input as search. It therefore cannot gain full-buffer INSERT editing or keep
  attributed syntax merely by changing product key mappings.
- `dart_appkit`'s `DaTextView` is a custom-drawn `DaView`, not `NSTextView`, and
  the public `TextView` has only a whole-string setter. The sibling roadmap also
  records multiline editable text as missing. A generic scrollable NSTextView
  wrapper with checked attributed runs and selection/editability operations is
  the narrow reusable addition needed by this product correction.
- The chosen native interaction keeps one editor instance for its whole
  lifetime. NORMAL makes it non-editable and routes modal commands exclusively
  to Dart; INSERT makes the same NSTextView editable and lets AppKit perform
  ordinary editing. Dart reapplies syntax attributes to its existing text
  storage after observing text changes rather than swapping to a second control
  or resetting the document. This is the enforceable answer to the latest
  visual-continuity requirement.
- Existing config resolution retains the absolute root path even when the
  default file does not exist, while `--no-config` or an environment without a
  usable config location can yield no root path. The editor will still show a
  complete draft in that case but must disable persistence with an explicit
  explanation instead of inventing a filesystem target.
- The root composer will preserve readable root text and append only missing
  schema representations. It will not flatten includes or copy CLI winners into
  active root assignments. Missing schema defaults in a new/empty file may be
  active canonical scalar assignments; nullable/repeatable examples and
  include/CLI-owned omissions remain commented until the user explicitly edits
  them.

### 2026-09-11 — complete document and safe persistence

- Added `lib/src/terminal_settings_document.dart` as a UI-independent editing
  boundary. `TerminalSettingsDocumentComposer` emits a schema-ordered 36-option
  scaffold for a missing/empty root. Scalar canonical values are active, while
  the nullable `working-directory` and repeatable `keybind` use commented syntax
  examples. For an existing sparse file it preserves the original UTF-8 text,
  comments, and LF/CRLF convention and appends only absent names in a delimited
  commented catalog.
- The catalog deliberately uses the accepted snapshot's canonical value only as
  a disabled suggestion. An include-owned `theme = dark`, for example, appears
  as `# theme = dark` in the root draft and therefore does not acquire higher
  precedence merely because Settings was opened. Existing root assignments and
  commented examples count as represented and are not duplicated by the
  generated catalog.
- `TerminalSettingsDocumentSession` captures whether the root existed and its
  exact byte revision. Save first rejects a missing persistence target (such as
  `--no-config`), enforces the loader file-size bound, compares the current root
  to that revision, and validates draft bytes through an overlay
  `TerminalConfigFileSystem`. Includes continue through the original filesystem
  and the original argument/environment/current-directory priority is retained.
- Any loader error diagnostic returns `rejected` without calling the writer.
  Any external byte change returns `conflict`. A warning-only/clean candidate is
  passed to one `TerminalSettingsDocumentWriter` call, after which the session
  advances its baseline. This separates future UI save/reload orchestration
  cleanly: persistence can succeed only once parsing has succeeded, while the
  existing shared reload controller remains the later publication authority.
- `LocalTerminalSettingsDocumentWriter` refuses relative paths, directories,
  and symbolic-link replacement, creates a missing parent directory, reserves
  an exclusive sibling temporary file, flushes its bytes, renames it over the
  root, and removes its own temporary artifact on failure. The target path is
  never derived from draft contents. Symlinked root configurations are an
  intentional safe rejection in this first editor contract rather than a
  potentially surprising replacement of the link itself.
- Added focused coverage for the missing root, all 36 representations, nullable
  and repeatable placeholders, an untouched sparse CRLF root, include-owned
  suggestions, invalid-draft zero writes, successful include-aware validation,
  external-change conflict, no-target behavior, malformed UTF-8 refusal, nested
  local directory creation, atomic replacement, and temporary cleanup. The test
  is included in the aggregate runner and the public library exports the new
  model.

### Verification for ordered subtask 1

- The first plain sandbox `dart format` formatted the intended files but then
  reported a denied SDK telemetry-log cleanup. The first focused run likewise
  stopped in the existing Metal build hook because Clang could not write its
  user module cache. Both are environment restrictions, not product failures;
  subsequent validation used `CI=true DART_SUPPRESS_ANALYTICS=true` with the
  required cache access.
- The first unrestricted focused invocation then identified that the newly
  created test file lacked a standalone `main`; adding the conventional wrapper
  fixed the harness without changing implementation behavior.
- `dart run test/terminal_settings_document_test.dart`: passed.
- `dart format --output=none --set-exit-if-changed` for all four touched Dart
  integration files: passed, 0 changes.
- `dart analyze`: initially reported only two directive-ordering infos; imports
  and exports were sorted, and the rerun passed with no issues.
- Full `make test`: passed. All generation/freshness/configuration/
  compatibility gates passed, 243 files formatted with 0 changes, analysis
  reported no issues, and the aggregate ended with `dart_terminal tests passed`.
- `git diff --check`: passed. The adjacent `dart_appkit` worktree is still clean
  at `2b36186`; no native dependency change belongs to this first subtask.
