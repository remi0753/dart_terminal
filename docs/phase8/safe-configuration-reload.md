# Safe configuration reload and option application policy

- Status: in progress
- Started: 2026-09-10
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `safe reload, per-option live/new-session policy`
- Feature-matrix owner: CFG-04
- Depends on: `docs/phase8/product-option-families.md` and
  `docs/phase8/declarative-keybind-action-reference.md`

## Purpose

Reload the resolved configuration without replacing an existing pane, PTY,
screen, renderer, or native window, and declare for every schema option whether
an accepted value applies immediately or only when a later session/resource is
created.

## Background

- Startup resolves one immutable `TerminalConfigSnapshot`, converts it to one
  immutable `TerminalProductConfiguration`, and captures that profile for the
  lifetime of the ordinary product hierarchy.
- Existing panes independently own mutable palette, scrollback, screen, font,
  atlas, input router, text-input client, view, and PTY resources. Recreating a
  pane to apply configuration would violate the Phase 8 safety condition.
- `keybind` and `macos-option-key` are consulted only when a new key event is
  routed. Their immutable resolver/encoder can therefore be atomically swapped
  at the application-owned input boundary without mutating a terminal session.
- Palette reset defaults, initial cursor state, scrollback capacity, font
  resources, and padding are embedded in existing mutable resource ownership.
  Window dimensions and working directory likewise describe creation state.
  These options must affect later resources without rewriting existing state.
- The loader deliberately recovers individual invalid startup values so an
  invalid file cannot prevent application startup. During reload, accepting a
  partially recovered candidate would unexpectedly erase last-known-good user
  values; a safe transaction must retain the active snapshot when any candidate
  error diagnostic exists.

## Scope

- Add an explicit `live` or `newSession` application policy to every scalar and
  repeatable schema option and reject schemas lacking valid metadata.
- Compare two typed snapshots into deterministic changed-option sets grouped by
  policy, including semantic comparison of repeatable key bindings.
- Add a bounded, single-flight reload controller that resolves from the same
  startup arguments/environment/current-directory inputs, atomically accepts a
  diagnostic-free candidate, and otherwise retains the last-known-good
  snapshot while publishing the rejected diagnostics.
- Add `application.reload-configuration` to the shared action catalog and route
  it through the ordinary product menu/command-palette dispatcher.
- Apply accepted live input policy to every existing pane, use the complete
  accepted profile for later panes/windows/tabs/splits, and keep all existing
  pane/PTY/native handles stable.
- Add focused pure-Dart, routing, action, fake-AppKit, and gated real-product
  Developer JIT/Release AOT coverage.

## Out of scope

- Automatic filesystem watching, debounce policy, SIGHUP, or settings-driven
  writes. Reload is an explicit bounded application action in this task.
- Live replacement of palette reset defaults, screen cursor defaults,
  scrollback storage, CoreText/Metal font resources, padding, window frames, or
  a running process working directory.
- Theme catalog/appearance switching, shell integration, effective-config UI,
  and deprecated-option migration; these remain later Phase 8 items.
- Per-pane overrides or rollback after an accepted live consumer callback
  throws. Live policy construction is pure and validated before publication.

## Dependencies and boundaries

- `TerminalConfigSchema` remains the only option inventory and decoder. Policy
  is metadata on that same inventory, not a parallel handwritten table.
- Command-line overrides remain fixed across reloads and retain precedence over
  re-read files. `--no-config` has no mutable file input and reload is an
  accepted no-op.
- Candidate resolution completes before active state changes. Any error
  diagnostic rejects the entire candidate; warnings may be accepted.
- Live publication swaps already-created immutable key binding and Option-key
  encoder state on the main isolate. It performs no I/O and owns no PTY or
  AppKit resource.
- A new pane captures one coherent accepted profile before constructing its
  session and renderer resources. Existing panes retain their creation profile
  except for the two declared live input options.
- Reload action availability is false while another reload is executing or
  product teardown is in progress. Concurrent requests are consumed as busy,
  not queued into repeated file reads.

## Ordered subtasks

1. Add per-option application policy metadata, semantic snapshot diff/plan
   types, exhaustive schema-policy tests, and documentation. Do not change
   runtime behavior in this commit.
2. Add the last-known-good reload controller with fixed startup inputs,
   diagnostic rejection, no-op handling, and single-flight coverage. Do not
   connect AppKit or the ordinary product in this commit.
3. Add the shared reload action and ordinary-product projection: atomically
   publish live input policy, capture the accepted profile for later resources,
   keep existing resources stable, and cover action/routing/fake-AppKit paths.
4. Extend configured-product acceptance to valid, invalid, and corrected real
   file reloads in Developer JIT and Release AOT; run the full runtime gate,
   update user/reference/evidence documentation, and close the parent item.

Each subtask is verified, documented, marked complete, and committed before the
next begins. After each commit, reread `ROADMAP.md` and this memo.

## Completion conditions

1. Every schema option declares exactly one visible policy, with `keybind` and
   `macos-option-key` live and all creation/resource defaults new-session.
2. A diagnostic-free reload atomically advances the effective snapshot and
   reports deterministic live/new-session changes. An erroneous reload retains
   every last-known-good value and exposes file/line/code/hint diagnostics.
3. Reload requests are bounded and single-flight. No accepted, rejected, busy,
   or no-op outcome tears down or replaces an existing pane, PTY, screen,
   renderer, native view, or window.
4. Existing panes observe accepted key binding and Option-key changes on their
   next key event. Later panes capture all accepted new-session values with
   independent mutable resources.
5. Generated action documentation, format/analyze/tests/audits, and M1
   Developer JIT/Release AOT configured-product acceptance all pass.

## Verification plan

- Pure-Dart schema/diff tests after subtask 1.
- Controller transaction/concurrency/diagnostic tests after subtask 2.
- Key routing, action registry/menu, native hierarchy, and aggregate tests after
  subtask 3, including regenerated action reference freshness.
- A real isolated config file rewritten through valid, invalid, and corrected
  states in both runtime modes after subtask 4, followed by
  `make RUNTIME_ARCH=arm64 runtime-verify`.

## Findings and decisions

- The worktree was clean at `f241192` when this task began.
- The parent crosses schema metadata, transaction state, application actions,
  pane creation, input routing, and packaged runtime acceptance. It is split
  before implementation as required by the repository work rules.
- `TerminalPalette` has mutable OSC-facing colors but immutable reset defaults;
  applying a new config palette to a live screen would either erase application
  OSC overrides or leave reset semantics stale. Palette options are therefore
  new-session until a distinct layered palette authority exists.
- `TerminalLiveMetalSurface` owns final padding and a generation-owned font
  catalog/shaping cache/atlas. Safe live font or padding publication needs a
  renderer transaction beyond this task, so these options are new-session.
- Initial cursor shape/blink can be superseded by terminal escape sequences.
  Reapplying config to a live screen would override application state, so both
  remain new-session.
- Existing action/menu infrastructure already supplies exactly-once dispatch,
  busy classification, dynamic availability, and native shortcut arbitration.
  Reload should reuse that bounded authority instead of introducing a second
  AppKit callback path; no adjacent `dart_appkit` change is currently required.
- The product schema currently contains 34 options. `macos-option-key` and
  repeatable `keybind` are `live`; `working-directory`, `theme`, all 19 palette
  entries, all three font entries, all four window/padding entries, both
  scrollback entries, and both cursor entries are `newSession`.
- `TerminalConfigSnapshot` now retains its schema identity. Change planning
  rejects snapshots from different authorities instead of attempting to match
  options by user-controlled names.
- Snapshot difference ignores provenance-only movement and compares decoded
  values in schema order. Key binding definitions now have semantic equality,
  so reconstructing an identical ordered override list is a no-op while order
  or target changes remain observable.
- The first focused test attempt was blocked by the workspace sandbox when the
  Metal native hook tried to write Clang module cache files below `~/.cache`.
  Re-running the unchanged tests with the required external cache permission
  succeeded; this was not a source failure.

## Subtask 1 verification

- Focused formatting completed for the four changed Dart files.
- Focused analysis reported no issues.
- `dart run test/terminal_product_configuration_test.dart` and
  `dart run test/terminal_config_test.dart` pass with cache permission. They
  cover the complete policy inventory, deterministic mixed-policy planning,
  semantic repeated values, provenance-insensitive no-op behavior, and foreign
  schema rejection.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all freshness gates,
  formats 220 files with zero changes, reports no analyzer issues, and completes
  the aggregate Dart suite.

## Subtask 2 findings and decisions

- `TerminalConfigReloadController.fromStartup` defensively copies the original
  argument list and environment and fixes the current directory at creation.
  Every reload therefore reuses the same file selection and CLI precedence even
  if a caller later mutates its input collections or process state changes.
- A request owns one asynchronous resolution slot. A second request observes
  `busy` immediately and is not queued; an accepted candidate advances a
  monotonic generation, including semantic no-ops whose provenance or warnings
  may still matter to the later effective-config inspector.
- Any error-severity candidate diagnostic yields `rejected`, publishes the
  complete bounded candidate diagnostics, and leaves the effective snapshot
  object unchanged. Warning-only candidates are accepted.
- Unexpected resolver/schema failures are classified separately as `failed`
  with their stack trace and retain active state. Disposal prevents new work
  and also prevents an already-running resolver from publishing after product
  teardown.
- The controller is independent of AppKit, pane/session ownership, and the
  product action catalog in this subtask. `dart_terminal.dart` exports the
  transaction API for focused consumers and tests.

## Subtask 2 verification

- Focused formatting completed for the new controller/test and aggregate
  registration files; focused analysis reported no issues.
- `dart run test/terminal_config_reload_test.dart` passes. It covers mixed live
  and new-session acceptance, located invalid-value rejection and complete
  last-known-good retention, correction/no-op, warning acceptance, fixed CLI
  precedence, copied input arguments, concurrent busy classification,
  unexpected failure, post-disposal request, and disposal during resolution.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all freshness gates,
  formats 222 files with zero changes, reports no analyzer issues, and completes
  the aggregate Dart suite.
- `make runtime-source-check` passes with `tracked=416`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1` after the new
  Dart files are staged.

## Subtask 3 findings and decisions

- `TerminalOptions.parse` now creates the reload controller from the exact
  loader, copied arguments/environment, current directory, and initial snapshot
  used at startup. Directly constructed test/fault options may omit the
  controller; the shared action remains catalogued but unavailable there.
- `TerminalProductConfigurationAuthority` publishes one coherent accepted
  new-session profile and one private pair of immutable live key-binding/Option
  encoder objects. New-session-only reloads preserve the identity and generation
  of the live pair; rejected results cannot be applied.
- Every ordinary hierarchy key router refers to the authority rather than
  retaining its own startup resolver/encoder. Since routing and publication are
  synchronous on the main isolate, one event observes either the complete old
  pair or the complete new pair.
- Each pane configuration captures the authority's accepted profile before its
  session is constructed. The same captured object supplies its working
  directory, palette, scrollback, cursor defaults, font, padding, and renderer
  viewport. Existing panes retain their captured resource defaults while their
  shared live input policy advances.
- An explicit configured `working-directory` wins for later session creation;
  when it is absent, the existing OSC 7/source-launch-directory inheritance
  remains unchanged.
- The native hierarchy now optionally captures a frame per newly encountered
  logical window. Existing placements remain immutable across later reloads,
  while a post-reload window receives the then-current configured dimensions.
  Its default split extent derives from that captured placement rather than a
  process-global startup frame.
- `application.reload-configuration` is a shortcut-free Application-menu and
  command-palette action. The ordinary dispatcher enables it only while the
  controller and product are live and idle, prints bounded diagnostics and a
  content-free machine result, and treats unexpected resolver failure as an
  action failure. The generated action reference now contains 16 application
  actions; reserved native shortcut count remains 9.
- No adjacent `dart_appkit` change is needed: the existing menu projection,
  invocation events, dynamic enablement, and exactly-once dispatcher boundary
  already carry the new catalog action.
- The first complete test attempt stopped at the expected Phase 7 reviewed
  AppKit inventory freshness gate after application/native-hierarchy source
  changes. Regenerating that inventory updated only the intended source/test
  hashes.
- The next aggregate attempt found a test-helper mismatch: the new constructor
  conflict correctly threw `ArgumentError`, while the local helper defaulted to
  expecting `FormatException`. Supplying the explicit expected type fixed the
  test; no product behavior changed.

## Subtask 3 verification

- Focused formatting and analysis of all changed product, configuration,
  action, hierarchy, and test sources complete with no issues.
- Focused product-configuration, config-options, action-registry, and native
  hierarchy tests pass. Coverage includes accepted/rejected authority
  publication, live-object identity, an existing router's next-event keybind
  and UTF-8 Option behavior, constructor conflict rejection, deterministic
  Application-menu order, and distinct creation-time frames through fake
  AppKit.
- `make keybind-action-reference` regenerates the checked-in reference, and its
  freshness check reports `application_actions=16`, `standard_bindings=1`, and
  `reserved_shortcuts=9`.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes all freshness gates,
  formats 222 files with zero changes, reports no analyzer issues, and completes
  the aggregate Dart suite after the reviewed AppKit inventory refresh.
- `make runtime-source-check` passes with `tracked=416`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
