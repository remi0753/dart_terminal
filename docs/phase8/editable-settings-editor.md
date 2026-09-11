# Editable modal Settings editor

- Status: complete
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
   and feature evidence and perform the Phase 8 completion review.
6. Preserve an existing root file's permission bits across atomic replacement,
   prove failure cleanup and both packaged-runtime saves, then mark the child
   and parent complete, commit, reread the roadmap, and stop before Phase 9.

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

### 2026-09-11 — modal state and mode-invariant syntax

- Added `TerminalSettingsEditorState` as a UI-independent owner of one complete
  document buffer, UTF-16 scalar-safe selection, NORMAL/INSERT/SEARCH mode,
  explicit search query, detail visibility, dirty/save state, schema
  occurrences, syntax spans, and root diagnostic spans. It opens through the
  safe document session and continues to read accepted values from the existing
  reload controller.
- NORMAL no longer interprets arbitrary printable input as search. `/` alone
  enters SEARCH; bounded printable input then matches option name, syntax,
  description, draft value, or current value and moves the same document caret.
  `Esc` returns SEARCH to NORMAL, while a second `Esc` from NORMAL dismisses.
  Arrow keys and `h`/`j`/`k`/`l` move the scalar-safe caret, `i` inserts at it,
  `a` advances one scalar before entering INSERT, and `]` toggles the contextual
  pane. Command-S is classified as one save request in every mode.
- INSERT does not own a second value field or a per-row editing buffer. Ordinary
  text keys are classified as `nativeEditing`; the same future native editor
  returns its full text and selection through `synchronizeNativeDocument`.
  Tests change both `font-size` and `cursor-blink` in one synchronization to
  prove the model is a complete editor rather than a selected-value control.
- The presentation scanner colors comment prefixes/text, known option names,
  the `include` directive, equals operators, values (including `#RRGGBB`), and
  unknown names using checked non-overlapping UTF-16 spans. It also maps all
  active and generated-comment assignments to schema options for caret context.
  This scanner is intentionally presentation-only; actual draft validity still
  comes exclusively from `TerminalConfigLoader` at save.
- Mode changes never call the document analyzer. Tests retain the exact
  `syntaxSpans` list identity and byte-for-byte document across
  NORMAL -> INSERT -> NORMAL, both before and after a multi-line edit. The only
  mode-dependent rendering is the compact status string (`NORMAL`, `INSERT`, or
  `/query`) and, in the forthcoming native surface, caret/editability chrome.
- Context detail now presents the option name, balanced current/draft values,
  schema syntax and description, then an `After save` section. Live options say
  `Open terminals: Change immediately`; new-session options say
  `Open terminals: Keep current value`; both say
  `New terminals: Use saved value`. Relevant invalid-draft code/message/hint is
  shown without path, line, source, `APPLIES`, or `Config Lens` fields.
- Diagnostics from draft validation are projected to bounded root ranges for
  future native underlining without changing the syntax-color spans. Selection
  validation rejects positions inside surrogate pairs, and horizontal movement
  crosses one Unicode scalar rather than one UTF-16 code unit.

### Verification for ordered subtask 2

- `dart run test/terminal_settings_editor_test.dart`: passed. Coverage includes
  explicit search ownership, mode/Escape transitions, native-edit delegation,
  Command-S, detail toggle, whole-buffer synchronization, identical syntax
  projection across modes, live/new-terminal outcome copy, invalid diagnostic
  detail/range, emoji selection boundaries, and query overflow atomicity.
- `dart format --output=none --set-exit-if-changed` for the touched Dart files:
  passed, 0 changes.
- `dart analyze`: passed with no issues.
- Full `make test`: passed. All generation/freshness/configuration/
  compatibility checks passed, 245 files formatted with 0 changes, analysis
  reported no issues, and the aggregate ended with `dart_terminal tests passed`.
- `git diff --check`: passed. No adjacent `dart_appkit` changes have begun; its
  worktree remains clean at `2b36186`, which is the next ordered dependency
  subtask.

### 2026-09-11 — generic attributed editable AppKit surface

- The authorized adjacent `dart_appkit` repository now exposes a public
  `TextEditor` distinct from the display-only `TextView`. One native
  `NSScrollView`/`NSTextView` pair owns the complete multiline buffer,
  selection, marked-text state, scrolling, first-responder behavior, native
  input-client path, Undo infrastructure, and find panel for its lifetime.
- `TextEditor.setDocument` validates and atomically publishes UTF-8 text,
  UTF-16 selection, and ordered non-overlapping foreground/underline runs.
  Text is bounded at 16 MiB, runs at 65,536, and every selection/run endpoint
  rejects the middle of a surrogate pair. The native bridge constructs the
  attributed candidate away from live storage and swaps it only after all
  validation and styling succeeds.
- `TextEditor.setStyleRuns` changes attributes on the existing
  `NSTextStorage`, preserving both its string and selection. `isEditable`
  changes only native interaction on the same surface. Native acceptance keeps
  the entire `NSAttributedString` equal across the non-editable-to-editable
  transition, directly pinning the product requirement that NORMAL and INSERT
  retain identical syntax presentation.
- A generic-view wrapper remains the Dart ownership/container handle;
  `Window.makeFirstResponder` validates that wrapper in the content hierarchy
  and then targets its inner `NSTextView`. No Objective-C pointer crosses the C
  or Dart boundary and no terminal-specific code entered `dart_appkit`.
- The new ABI is additive and keeps existing ABI/event protocol versions.
  `FfiNativeBindings` discovers it through an optional, separate
  `NativeTextEditorBindings` capability, so older bridge images and unrelated
  existing fakes remain source/load compatible and return unsupported status
  8. The terminal fake will implement that optional capability only when the
  product composition begins in ordered subtask 4.
- Public/fake coverage verifies atomic document/config transfer, same-surface
  editable/selection/style mutations, invalid UTF-16 and run ordering, bounds,
  and lifecycle. Native coverage inspects real foreground/underline
  attributes, stale-attribute removal, text-storage identity, invalid-update
  atomicity, snapshot state, focus forwarding, wrong handle/thread, and stale
  handles. Current and legacy Mach-O FFI smoke tests verify signatures and
  fallback.
- The adjacent implementation and its README, G5 partial-progress roadmap,
  worklog, and verification matrix were committed as
  `3b92fa130a783ea13f35aebace002d776554d8dd` (`Add attributed multiline text
  editor`). The adjacent worktree is clean after the commit.

### Verification for ordered subtask 3

- Adjacent focused package format/analyze and Dart API tests: passed, including
  `attributed multiline text editor`.
- Adjacent `make native-test` and `make ffi-smoke`: passed with warnings as
  errors, real AppKit attribute/selection/focus checks, current FFI, and legacy
  optional-symbol fallback.
- Adjacent full `make test`: passed on the final source. Scaffold and C/C++
  header contracts, native bridge, Runner/scheduler, runtime/capabilities,
  renderer/PTY, every Dart package, launcher/Kernel compile, and FFI paths all
  remained green.
- Terminal full `make test` against the committed path dependency: passed. All
  generation/freshness/configuration/compatibility checks passed, 245 files
  formatted with 0 changes, analysis reported no issues, and the aggregate
  ended with `dart_terminal tests passed`.
- Terminal `git diff --check`: passed before progress recording. No product UI
  code was advanced early; native composition remains the next ordered
  subtask.

### 2026-09-11 — native editor, contextual detail, and save lifecycle

- `TerminalSettingsInspectorPresenter` now retains its existing product/action
  boundary but presents one dominant `TextEditor`, one compact status strip,
  and one contextual detail surface in two nested `TwoPaneSplitView`s. The
  window title is only the root configuration filename and also carries the
  represented-file path; the editor does not repeat that filename. The right
  panel has no `Config Lens`, line, source, or `APPLIES` labels. Collapsing it
  leaves a narrow `DETAIL` edge rail in the same right-side region rather than
  hiding discovery behind a top button.
- The status/detail views are passive and cannot become first responder. The
  one attributed editor remains first responder for the window lifetime.
  NORMAL and SEARCH use `dartOnly` key routing; `i` or `a` changes that same
  native handle to editable `dartAndAppKit` routing, and `Esc` changes only
  editability/routing back to NORMAL. `/` is the sole entry into SEARCH.
- The product projects the schema scanner into a restrained dark syntax
  palette and merges independent diagnostic underlines into checked,
  non-overlapping AppKit style runs. Published runs are structurally cached.
  Since changing NORMAL/INSERT does not change text, syntax spans, or
  diagnostics, the transition performs no style publication at all; fake
  native acceptance compares every range, foreground component, underline
  style, and underline color before and after the transition and finds them
  identical.
- Native text and UTF-16 selection are pulled back after INSERT key/mouse
  handling. A zero-delay coalescing boundary lets AppKit finish responder
  dispatch first. Marked text is reflected in draft state without restyling
  live composition; styling resumes after marked text commits. Oversized or
  invalid-boundary snapshots fail through the typed editor limit and restore
  the last accepted product document when it is safe to do so.
- `TerminalOptions.parse` now retains a `TerminalSettingsDocumentSession`
  built from the exact loader, arguments, environment, and current directory
  used for startup/reload. This preserves schema identity and all precedence
  semantics for draft validation. The interactive product rejects a reload
  controller without its matching document session instead of inventing a
  different validation context.
- Command-S first synchronizes the native document, validates it through the
  document session, and records the typed result. Invalid, conflicted,
  unavailable, and failed saves do not write or dispatch reload. Only a
  successful atomic save invokes the existing shared reload action, after
  which current/detail values refresh without replacing terminal panes or the
  Settings editor. Duplicate save requests are suppressed while that sequence
  is in progress.
- Close requests and NORMAL Escape cancel the event subscription, close the
  window, dispose both split views and all three child surfaces, invalidate
  queued native synchronizations, then restore the live terminal responder.
  Reopening an already-open editor reuses every owner; opening after a close
  creates one fresh complete document revision.
- The fake AppKit hierarchy test now implements only the optional
  `NativeTextEditorBindings` capability needed by this product. It pins nested
  axes/children, passive supporting views, filename title, all 36 occurrences,
  exact first responder, singleton reopen, explicit search, identical
  NORMAL/INSERT styling, native whole-buffer synchronization, invalid-save
  underline/no-write/no-reload behavior, corrected atomic save/shared reload,
  detail rail, focus restoration, and return to the exact native object
  baseline.
- The M1 configuration acceptance flow was updated from external file writes
  plus Command-R to the actual editor contract: explicit `/` search, INSERT on
  the native surface, rejected Command-S draft, corrected Command-S save, and
  the one ensuing shared reload. Its two-runtime execution remains the final
  ordered acceptance subtask.

### Verification for ordered subtask 4

- Targeted `dart analyze` for the presenter, product wiring, policy, and native
  hierarchy test: passed with no issues.
- `dart run test/terminal_native_hierarchy_test.dart`: passed after adding the
  invalid-save integration assertions.
- `dart run test/terminal_settings_editor_test.dart`,
  `terminal_settings_document_test.dart`, and
  `terminal_settings_inspector_test.dart`: passed.
- The first parallel focused invocations were blocked before test execution
  because the Metal build hook could not write Clang's user module cache from
  the workspace sandbox. Re-running the native hierarchy test with the
  required cache access populated the ordinary build cache; all focused reruns
  then passed. This was an environment restriction, not a product failure.
- The first full `make test` reached the intended Phase 7 AppKit freshness gate
  and rejected the changed product/application sources as stale. Running
  `make phase7-appkit-acceptance` updated only the reviewed SHA-256 entries for
  `terminal_application.dart` and `terminal_native_hierarchy_test.dart`; no
  acceptance criteria or assertions were regenerated away.
- Full `make test` then passed. All generated-reference, AppKit-evidence,
  compatibility, differential, application-matrix, terminfo, and shell-resource
  gates passed; all 245 Dart files were already formatted; analysis reported no
  issues; and the aggregate ended with `dart_terminal tests passed`.
- `git diff --check` and the final task-scoped diff review passed. The adjacent
  `dart_appkit` worktree remains clean at the previously accepted editor commit.

### 2026-09-11 — M1 dual-runtime acceptance start

- Purpose: run the packaged Developer JIT and Release AOT configuration product
  on the Apple M1 baseline, prove the editable Settings workflow against real
  AppKit/Metal/PTY ownership, reconcile user-facing evidence, and then
  re-evaluate every Phase 8 exit condition.
- Scope: the existing isolated configuration runtime suite; exact native menu
  and command-palette entry; explicit `/` search; same-surface INSERT;
  invalid Command-S draft retained with no file write or reload; corrected
  atomic save followed by exactly one shared reload; live/new-session resource
  boundaries; focus and handle cleanup; README, UI-09, CFG-07, task/parent
  roadmap state, generated evidence, source/bundle gates, and the complete test
  suite.
- Out of scope: a new runtime suite, additional editor features, Phase 9, Intel
  or Universal acceptance, or weakening the real native-event/owner checks.
- Dependencies: committed product integration `2d08a9d`, adjacent generic
  editor `3b92fa1`, the existing developer/release bundle builders and audits,
  the configuration smoke driver, and the M1 host's real AppKit session.
- Completion conditions: both packaged modes satisfy the same editable
  Settings contract and exit cleanly with four sessions, zero text clients,
  and zero native handles; all repository gates and documentation agree; no
  Phase 8 child remains unchecked.
- The existing smoke-driver expectations still describe the retired
  Command-R inspector flow: they require one rejected reload transaction and
  label the summary as `settings_reload`. The product now intentionally rejects
  invalid text before persistence/reload and emits only the later accepted
  reload. These exact expectations must be reconciled to the stronger editable
  save contract before the final dual-runtime result can pass; the scenario and
  target remain unchanged.
- The first Developer JIT product run built and launched the real arm64 bundle,
  opened the ordinary PTY/AppKit hierarchy, and stopped at the new initial
  Settings assertion. Cleanup still reaped the worker and PTY and returned all
  owners. The assertion had incorrectly required exactly 36 assignment
  occurrences and the canonical value `system` in the editable draft. The
  fixture intentionally contains five repeatable `keybind` lines (therefore 40
  occurrences covering 36 distinct schema options), and preserves the user's
  deprecated spelling `theme = default` while the accepted effective value is
  `system`. The assertion now checks 36 distinct schema options plus both
  draft/effective values, preserving rather than weakening the intended
  contract.
- The second Developer JIT run passed the corrected product assertion and
  completed its real Settings/PTY lifecycle. The outer smoke driver then
  rejected the expected stderr difference: only the two startup diagnostics
  were emitted, because the invalid `font-size` draft remained inside the
  editor and never reached the shared reload logger. The driver now requires
  zero rejected reload records, one accepted reload, and exactly those two
  startup diagnostics. Product and driver evidence names now distinguish
  `save_rejected`, `save_applied`, `reload_applied`, `settings_edit`, and
  `settings_style_stable` instead of describing every operation as reload.
- The reconciled Developer JIT configuration acceptance passed on the real M1
  bundle in 1,660 ms. Release AOT then passed the identical contract in
  1,077 ms. Each mode exercised the owner-free `--show-config` early exit and
  the ordinary four-pane AppKit/Metal/PTY product; Settings was reached through
  both menu and command palette, retained the initial file during invalid save,
  atomically installed the corrected file, dispatched one accepted reload,
  preserved existing pane resources, projected new-session state to later
  panes, restored focus, and finished with four clean sessions, zero text
  clients, and zero native handles.
- README now documents the complete modal document, explicit `/` search,
  same-style NORMAL/INSERT transition, contextual rail, invalid-save behavior,
  atomic Command-S/reload, and `--show-config` provenance boundary. Feature
  owners UI-09 and CFG-07 now describe the same accepted behavior rather than
  the retired read-only inspector/Command-R workflow.

### Verification for ordered subtask 5

- `make RUNTIME_ARCH=arm64 runtime-configuration-integration`: passed on the
  final source. Developer JIT reported
  `RUNTIME_CONFIGURATION_INTEGRATION_PASS` in 1,608 ms and Release AOT reported
  the same contract in 1,115 ms. Both were native arm64 launches with four
  panes, keybind, save, reload, editable Settings, and owner-free effective
  configuration checks enabled.
- The first final `make test` correctly rejected the README/FEATURE_MATRIX
  hashes in `compatibility/regression_coverage_report.json` as stale.
  `make terminal-compatibility-regression-coverage` changed only those two
  reviewed SHA-256 entries. The Phase 7 AppKit evidence regeneration likewise
  changed only the two `terminal_application.dart` hashes.
- Final full `make test`: passed. All schema/action generation, AppKit evidence,
  compatibility, differential, application-matrix, terminfo, shell-resource,
  formatting (245 files, 0 changes), analysis, and aggregate tests passed with
  `dart_terminal tests passed`.
- `make runtime-source-check`: passed with 451 tracked files, zero product
  native sources, and the one already reviewed test-native source.
- `make RUNTIME_ARCH=arm64 runtime-bundle-audit`: passed for both Developer JIT
  and Release AOT, each with one helper, one native-asset set, and one declared
  capability. The adjacent `dart_appkit` worktree remained clean at `3b92fa1`.
- All runtime-facing Phase 8 exit conditions were re-evaluated as satisfied:
  invalid startup
  configuration remains recoverable with file/line/hint diagnostics; invalid
  editor drafts do not reach disk or reload; accepted reload retains existing
  pane/PTY resources; generated schema/help/settings/action evidence is fresh;
  and the previously accepted disabled-shell path remains an ordinary terminal
  under the unchanged full gate. Final source review then found that the local
  atomic writer does not yet retain an existing root file's permission bits,
  despite that explicit storage completion condition. A final ordered child
  now tracks that fix and Phase 8 remains open; Phase 9 was not started.

### 2026-09-11 — existing-root permission retention start

- Purpose: preserve the POSIX permission bits of an existing root config across
  the same-directory atomic replacement, verify the failure-safe behavior, and
  perform the final Phase 8 completion review.
- Scope: `LocalTerminalSettingsDocumentWriter`, its real-filesystem focused
  test, task evidence, final full gate, and parent/child roadmap state.
- Out of scope: ownership/ACL/xattr cloning, changing the mode chosen by the OS
  for a newly created config, a different save protocol, generic filesystem
  APIs in `dart_appkit`, or any Phase 9 work.
- Dependencies: the existing symlink/directory refusal, exclusive sibling temp
  reservation, flushed write, same-directory rename, and session-level
  baseline/conflict check.
- Completion conditions: an existing file with a non-default mode retains all
  low 12 POSIX permission/special bits after replacement; a new file keeps the
  platform/umask default; permission-copy failure aborts before rename and the
  temporary sibling is removed; focused and complete gates pass.
- Validation: a real temporary-directory test sets an existing root to mode
  `0600`, replaces it, checks both new bytes and `(FileStat.mode & 0xFFF)`, and
  confirms there is still only the target sibling; format/analyze, full
  `make test`, source/diff review, and Phase 8 exit-condition reconciliation.
- Considered alternatives: truncating the target in place naturally preserves
  mode but gives up atomic publication; copying the target over the reserved
  temp has undocumented metadata behavior and `File.copySync` removes an
  existing destination; adding a package/native FFI chmod surface expands the
  dependency/ABI boundary for one macOS-local operation. The selected approach
  snapshots `FileStat.mode & 0xFFF` and invokes the fixed `/bin/chmod` executable
  with an argument list on the completed temp before rename. It uses no shell
  interpolation, leaves new-file behavior unchanged, and treats any nonzero
  chmod result as a failed atomic save whose temp is cleaned by the existing
  `finally` path.

### 2026-09-11 — existing-root permission retention implementation

- `LocalTerminalSettingsDocumentWriter` now refuses every existing
  non-regular target, snapshots all low 12 POSIX permission/special bits from
  an existing regular target, applies them to the completely flushed temporary
  sibling, and only then performs the same-directory rename. A newly created
  root skips that step and therefore retains the platform/umask-selected mode.
- The permission operation uses a fixed `/bin/chmod` executable and separate
  arguments. A nonzero result, process-launch failure, or injected callback
  failure propagates before publication and reaches the existing `finally`
  cleanup. The writer never truncates or partially rewrites the old target.
- The focused real-filesystem test establishes mode `0600`, verifies the
  replacement bytes and mode, and injects a permission-copy failure to prove
  that both the prior file and its mode survive without a temporary sibling.
- The packaged configuration acceptance fixture also establishes `0600` and
  now requires both Developer JIT and Release AOT Settings saves to retain it;
  the machine-readable product result exposes `permissions=true`.
- Touched-file format reported 0 changes, targeted analysis reported no issues,
  and `dart run test/terminal_settings_document_test.dart` exited successfully.
- The first sandboxed Phase 7 evidence regeneration reached the native build
  hook but the Metal compiler could not write its module cache under
  `~/.cache/clang`. Repeating the same gate with the required filesystem access
  succeeded. The only evidence changes are the two expected hashes for
  `lib/src/terminal_application.dart`; `git diff --check` passed.

### Verification for ordered subtask 6 and Phase 8 completion

- Final `make test`: passed. All generated schema/action, AppKit evidence,
  compatibility, differential, application-matrix, terminfo, shell-resource,
  formatting (245 files, 0 changes), analysis, and aggregate tests completed
  with `dart_terminal tests passed`.
- `make runtime-source-check`: passed with 451 tracked files, zero product
  native sources, and one previously reviewed test-native source.
- `make RUNTIME_ARCH=arm64 runtime-bundle-audit`: passed for Developer JIT and
  Release AOT; each packaged bundle reported one helper, one native-asset set,
  and one declared capability.
- `make RUNTIME_ARCH=arm64 runtime-configuration-integration`: passed on the M1
  baseline. Developer JIT completed in 1,769 ms and Release AOT in 1,062 ms;
  both reported four panes, editable Settings save/reload, owner-free effective
  config, clean lifecycle, and `permissions=true` after replacing the `0600`
  fixture.
- Final source review and `git diff --check` passed. The adjacent `dart_appkit`
  worktree remains clean at `3b92fa1`; no additional generic UI change was
  needed for permission retention.
- All six editor completion conditions and the four Phase 8 exit conditions
  are satisfied on final source: schema-complete drafts and diagnostics remain
  recoverable, invalid saves do not publish, accepted saves are atomic and
  retain root permissions, reload keeps existing pane/PTY/native identities,
  NORMAL/INSERT style runs are identical, Settings lifecycle cleanup is clean,
  schema/help/settings/action evidence agrees, and disabled shell integration
  remains covered by the unchanged full gate. Phase 8 is complete; Phase 9 was
  deliberately not started.
