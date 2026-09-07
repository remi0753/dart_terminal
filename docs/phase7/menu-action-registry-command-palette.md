# Phase 7 — menu/action registry and command palette

- Status: in progress
- Date: 2026-09-07
- Scope: fourth Phase 7 roadmap item
- Related: IN-09, UI-05, UI-09

## Purpose

Replace the product's directly-wired four-item menu with one typed, bounded,
searchable action source that owns stable identities, presentation metadata,
availability, shortcut arbitration, and dispatch. Project that source into the
standard macOS menu bar and a keyboard-operated native command palette without
allowing commands or text to leak into the focused terminal pane.

## Background

Phase 1 added generation-checked `Menu`/`MenuItem` ownership, enabled state,
key equivalents, and asynchronous action events. Phase 5 established that
AppKit consumes recognized menu shortcuts before terminal key routing. The
current application still constructs Application/File/Edit menus inline and
subscribes each item directly to unrelated closures. There is no complete
action catalog, duplicate identity or shortcut validation, searchable snapshot,
palette selection state, or single dispatch boundary shared by menus and a
palette.

The reusable AppKit layer already provides the primitives needed here:
`MenuItem.isEnabled`, programmatic action performance, main-menu attachment,
`Window.keyEventRouting`, and a generic native `TextView`. A palette can
therefore remain product-owned and use a transient native window without adding
terminal-specific policy to `dart_appkit`.

## Scope

- Define stable application action identities and immutable presentation
  metadata for Application, File, Edit, Shell, View, and Window commands.
- Reject duplicate identities and conflicting non-empty native shortcuts,
  enforce hard action/query/result bounds, and return immutable snapshots.
- Centralize dynamic availability and exactly-once synchronous/asynchronous
  action dispatch with observable result classifications.
- Implement deterministic case-insensitive token/subsequence search and bounded
  command-palette query, selection, movement, invocation, and dismissal state.
- Build the product menu hierarchy from the same catalog and keep native item
  enablement synchronized with the active terminal context.
- Present the palette in a transient native AppKit window, own its raw keyboard
  input separately from the terminal text client, restore terminal focus on
  dismissal, and dispose every palette handle/subscription deterministically.
- Add gated Developer JIT and Release AOT product acceptance proving the menu
  and palette invoke the same action exactly once and palette typing never
  reaches the PTY.

## Out of scope

- Phase 8 config-file keybind loading, user shortcut overrides, settings UI,
  generated action references, themes, and localization.
- Phase 9 Kitty/modifyOtherKeys enhancements and Phase 10 Quick Terminal or
  global shortcuts.
- Reusable terminal-specific command-palette widgets in `dart_appkit`; the
  package remains limited to generic AppKit primitives.
- Title/tab metadata, restoration, close confirmation redesign, or multi-pane
  scheduler policy, which are later Phase 7 roadmap items.
- Pretending a command is available before its product mutation exists. The
  standard catalog may describe later actions, but dynamic validation must
  disable an action without a live handler/context.

## Ordered subtasks

1. Add a bounded immutable application action catalog/dispatcher and
   deterministic command-palette state, including identity, metadata,
   availability, conflict, search, selection, dispatch, and limit tests.
2. Replace inline product menu policy with a registry-driven standard
   Application/File/Edit/Shell/View/Window menu projection, dynamic validation,
   exactly-once action routing, and focused fake/native-independent tests.
3. Add the transient native command-palette presenter and gated real-product
   Developer JIT/Release AOT acceptance for shortcut arbitration, query/input
   isolation, shared dispatch, focus restoration, and complete handle cleanup.

The parent roadmap item remains incomplete until all three commits and the
combined product verification pass.

## Dependencies and ownership

- `TerminalApplicationState` remains the sole logical
  application/window/tab/split/pane owner. Actions request its public
  mutations; they do not maintain a parallel hierarchy.
- `TerminalPane` and `TerminalSession` remain the sole terminal input/PTY
  writers. Palette input is consumed by its own `dartOnly` window route and
  must never call either writer.
- AppKit remains authoritative for recognized menu key equivalents. Menu and
  palette events converge only after native shortcut arbitration at one Dart
  dispatcher.
- The action catalog owns immutable metadata. Product-owned context and
  handlers decide current availability and effects; no native callback enters
  Dart synchronously.
- A palette presenter owns its transient `Window`, `TextView`, and event
  subscription and tears them down before product application termination.

## Completion criteria

- Action identities and native shortcuts are unique, stable, bounded, and
  round-trip from their documented names; malformed definitions fail before
  any native object is created.
- Search is deterministic, case-insensitive, token aware, hard bounded, and
  never returns a mutable or disabled-to-execute result accidentally.
- Menus and the palette display metadata from one catalog and dispatch through
  one exactly-once boundary; unavailable actions are disabled consistently.
- Shift-Command-P is consumed by the native menu, palette query/navigation is owned
  by the palette window, Escape restores the terminal first responder, and no
  palette keystroke or invoked menu shortcut reaches a PTY.
- Focused tests, full tests/analysis/format, source audit, both arm64 bundle
  audits, and Developer JIT/Release AOT product acceptance pass.
- ROADMAP, README, FEATURE_MATRIX, and this memo reproduce the final behavior;
  every subtask is committed independently and both repositories are clean.

## Verification plan

- Add table-driven pure-Dart tests for catalog construction, identity/shortcut
  conflicts, immutable snapshots, availability, failure/busy behavior, search
  ordering, Unicode/case matching, query bounds, navigation, and invocation.
- Add product projection tests with fake handlers and menu-neutral presentation
  seams, including dynamic enabled-state refresh and shared menu/palette
  dispatch counts.
- Extend the packaged runtime harness with an integration-only palette scenario
  that uses real AppKit events and a real zsh PTY in both product modes.
- Run focused tests after each subtask, then `make test`,
  `make runtime-source-check`, Developer/Release runtime integration, and both
  bundle audits in proportion to the changed boundary.

## Investigation log

- 2026-09-07: work started from clean Dart Terminal `86f6c5b` and clean
  adjacent `dart_appkit` `5cd4810`. The first unchecked roadmap item is this
  Phase 7 action/menu/palette parent.
- 2026-09-07: `TerminalApplication.run` creates Application/File/Edit menus
  inline, retains four item subscriptions, and directly invokes copy, paste,
  close, and quit closures. Those definitions cannot be searched or validated
  as one namespace.
- 2026-09-07: the Phase 5 `TerminalKeyBindingEngine` has four terminal-control
  actions and exact chord conflict checks, but its scope explicitly excluded
  the Phase 7 application action surface and command palette. The two domains
  must not be conflated before Phase 8 configuration connects them.
- 2026-09-07: `dart_appkit` `MenuItem` exposes immutable title/shortcut
  metadata, mutable checked native enabled state, and a generation-routed
  action stream. A `dartOnly` window publishes key events after native menu
  arbitration. `TextView` is a generic autoresizing drawn-text surface rather
  than an editable `NSTextView`, so the product must own palette query editing
  and render its snapshot explicitly.
- 2026-09-07: a transient palette can be constructed from existing generic
  AppKit APIs. No adjacent repository change is currently required; this will
  be revisited only if product acceptance proves an actual missing primitive.

## Design decisions

- Keep the Phase 5 terminal-byte binding enum intact. Phase 7 introduces a
  separate application action namespace, and Phase 8 will be the ordered place
  to expose declarative user bindings across both domains.
- Search and palette state are platform independent. Native objects only
  project a snapshot and publish input, which keeps scoring, limits, and
  dispatch fully unit-testable.
- Treat handler presence and current context as validation inputs. Catalog
  membership alone never authorizes an unsupported product mutation.
- Use a transient standard AppKit window for the first native palette. It is
  intentionally product-owned, keyboard-only, and bounded; richer overlay
  styling remains renderer/UI follow-up rather than a prerequisite for correct
  action routing.

## Verification results

### 2026-09-07 — bounded catalog/dispatcher and palette state

- The first focused test attempt did not reach Dart tests because the restricted
  command sandbox denied Metal's module-cache write under
  `~/.cache/clang/ModuleCache`. The source formatter had already completed.
  This is the known native build-hook environment restriction; the same focused
  command will be rerun with host access and no product workaround.
- The first host-access focused run reached the new tests and showed that a
  repeated identity failed on its second item before a 257-item iterable could
  demonstrate the catalog's consumption bound. Construction now performs a
  bounded collection pass followed by identity/shortcut validation. It never
  retains more than 256 definitions and reports the limit deterministically
  before inspecting an oversized input's semantic conflicts.
- The next focused run found that subsequence matching stopped at individual
  candidate words, so the intentional abbreviation `SPLTRGHT` could not span
  “Split … Right.” Each action now also contributes one bounded concatenated
  token, retaining exact/token scoring while allowing deterministic
  cross-word abbreviations.
- A deliberately ambiguous shorter abbreviation matched both split actions and
  therefore could not prove a unique result. The assertion now uses the unique
  cross-word subsequence `SPLTRGHT`, leaving deterministic catalog-order tie
  behavior to the separate equal-keyword test.
- Added 15 stable application action IDs covering the standard Application,
  File, Edit, Shell, View, and Window surfaces. The immutable standard catalog
  owns display title, keywords, menu placement, separator hint, optional native
  shortcut, and palette visibility. It rejects duplicate identity or
  case-insensitive shortcut, invalid text, and any 257th definition.
- `TerminalActionDispatcher` owns product handlers separately from metadata,
  fails closed when availability inspection throws, serializes an in-flight
  asynchronous action, invokes an available handler exactly once, and returns
  explicit executed/unavailable/busy/failed results with retained failure
  evidence. Unsupported catalog entries have no implicit behavior.
- Search lowercases Unicode text, tokenizes letters/numbers, scores
  exact/prefix/substring/subsequence matches, supports bounded cross-word
  abbreviations, sorts enabled matches before disabled matches, preserves
  catalog order for ties, hides opted-out actions, and returns at most 32
  immutable snapshots for a query capped at 256 UTF-16 units.
- `TerminalCommandPaletteState` owns open/dismiss, query editing, Unicode-scalar
  deletion, wrapped selection, availability refresh, and selected dispatch.
  Control input and oversize queries are rejected; a successful action closes
  and clears the palette while unavailable/failed actions remain visible.
- The focused suite passed after the corrections above. Final `make test`
  passed all freshness and compatibility gates, formatting of 194 files with
  zero changes, static analysis with no issues, and the aggregate Dart/native
  test suite. `make runtime-source-check` passed with `tracked=370`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- The first ordered subtask is complete. The parent remains in progress pending
  registry-driven native menu projection and the native palette/runtime
  acceptance commits.
