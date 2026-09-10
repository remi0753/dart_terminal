# Declarative keybindings and generated action reference

- Status: in progress
- Started: 2026-09-10
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `declarative keybind と action reference generation`
- Feature-matrix owners: IN-09 and CFG-03/CFG-07
- Depends on: `docs/phase5/mode-aware-key-input.md`,
  `docs/phase7/menu-action-registry-command-palette.md`, and
  `docs/phase8/typed-config-schema-diagnostics.md`

## Purpose

Load bounded, typed keybinding declarations from the normal configuration
authority, route them through the existing exact-chord engine to either a pane
operation or shared application action, and generate an always-fresh user
reference from the same stable action identities.

## Background

- Phase 5 already owns an immutable two-layer physical-key binding engine with
  terminal actions, exact modifiers, conflicts, unbind, passthrough, and a
  single-write router.
- Phase 7 owns a separate 15-action application catalog and dispatcher used by
  native menus and the command palette. Application action identifiers are
  stable, but are not currently valid keybinding targets.
- The Phase 8 configuration schema is scalar-only. It warns on a repeated
  option and retains only the last valid value, which cannot express one
  readable binding declaration per line or retain per-declaration provenance.
- Native AppKit menu key equivalents are consumed before raw terminal key
  routing. A configured declaration that silently collides with one would not
  observe the semantics shown in the configuration file.
- There is no generated action/key syntax reference or freshness gate.

## Scope

- Add a typed repeatable-option contract to the configuration schema. Preserve
  one source record per occurrence and the existing file/include/CLI order,
  assignment/diagnostic bounds, and scalar precedence behavior.
- Add repeatable `keybind` declarations using exact physical-key chords and
  Shift/Control/Option/Command modifiers. Accept pane action IDs, application
  action IDs, `unbind`, and `passthrough` through one bounded decoder.
- Apply declarations in order over the zero-config defaults; a later
  declaration of the same chord replaces the earlier one. Invalid entries are
  diagnosed independently and do not prevent startup.
- Route configured pane actions synchronously and configured application
  actions exactly once through the existing serialized dispatcher. Refresh
  menu/palette availability after asynchronous application dispatch.
- Reject declarations that collide with standard native menu shortcuts with an
  actionable diagnostic. AppKit remains the single owner of those reserved
  shortcuts; unrecognized Command chords may still use explicit passthrough or
  application actions through the raw-key path.
- Generate and check in a deterministic user reference containing syntax,
  bounds, modifier/key vocabulary, pane actions, application actions, default
  binding, and reserved native shortcuts.
- Add pure/config/router/product tests and gated Developer JIT/Release AOT
  acceptance for one pane action, one application action, unbind,
  passthrough, invalid recovery, native-menu priority, and exact cleanup.

## Out of scope

- Multi-stroke sequences, leader keys, text-character rather than physical-key
  matching, global shortcuts, per-pane keymaps, or arbitrary byte macros.
- Changing the standard native menu shortcut set or exposing menu-shortcut
  remapping. Those shortcuts remain visible, stable, and AppKit-authoritative.
- Live configuration reload; bindings are resolved once for the process and
  follow the next roadmap item's reload policy.
- Generating the complete configuration reference or effective-config output;
  this item generates the action/keybinding reference only.
- Kitty keyboard protocol or shell integration.

## Dependencies and risks

- Repeatable options must not weaken scalar duplicate warnings or
  default/include/root/CLI precedence.
- Application dispatch is asynchronous while AppKit key delivery is
  synchronous. The router may schedule exactly one dispatcher call, but must
  not block/re-enter AppKit or create an unbounded queue.
- The dispatcher already serializes application actions. A busy or unavailable
  result is observable and must not fall through to terminal encoding.
- Physical-key names and action IDs are compatibility surface once documented;
  the generator must reject drift rather than silently rewrite during tests.
- A reserved menu collision must be rejected during decoding, not accepted and
  later shadowed by AppKit.

## Ordered subtasks

1. Add repeatable typed configuration occurrences, the bounded `keybind`
   grammar/action target model, immutable ordered declarations, and exhaustive
   parser/provenance/precedence/recovery tests. Do not change runtime routing.
2. Project resolved bindings into the normal pane key router and shared
   application dispatcher, preserving native-menu priority and exactly-once
   outcomes. Add focused router/product/fake-AppKit tests.
3. Generate the user keybinding/action reference from the stable key and action
   authorities, add a freshness gate, and update README/feature evidence.
4. Add the real-product scenario, pass M1 Developer JIT and Release AOT plus the
   complete regression/audit matrix, reconcile evidence, and close the parent.

Each subtask is verified, documented, marked complete, and committed before
the next begins. `ROADMAP.md` and this memo are reread after every commit.

## Completion conditions

1. A user can declare multiple keybindings in included/root configuration and
   on the command line with per-occurrence provenance and deterministic order.
2. All physical keys, the four exact modifiers, both action namespaces,
   `unbind`, and `passthrough` have a bounded unambiguous syntax; malformed,
   unknown, duplicate, oversized, and reserved inputs recover independently.
3. Zero-config bindings and native menu shortcuts are unchanged. Configured
   pane/application actions execute once, unbind and passthrough retain their
   existing semantics, and unavailable/busy application actions do not encode
   terminal bytes.
4. The generated reference is deterministic, complete for every current key
   and action ID, linked from README, and rejected when stale.
5. Focused tests, formatting, analysis, complete tests, source/bundle audits,
   and M1 Developer JIT/Release AOT configured-product acceptance pass.

## Verification plan

1. Run focused config/keybinding/action catalog tests after the model work.
2. Run focused router, product hierarchy, menu, and fake-AppKit tests after
   runtime projection.
3. Run the generator twice, its check mode, formatting, analysis, and the
   complete unit/freshness suite after documentation generation.
4. Run a gated real-product scenario independently in both runtime modes, then
   `make RUNTIME_ARCH=arm64 runtime-verify`.
5. Review source/bundle audits, `git diff --check`, staged scope, and generated
   hashes before every completion commit.

## Initial findings and decisions

- The worktree is clean at `7ad193f`; the first unchecked roadmap item is this
  task and Phase 8 still has five later parent items.
- `TerminalConfigOption<T>` currently stores one resolved value and source.
  `_TerminalConfigCollector` processes included files before their parents and
  CLI last, so an ordered repeatable occurrence list can reuse that traversal
  without changing scalar precedence.
- The existing line grammar can use one readable `keybind = ...` declaration
  per line after repeatable options are introduced. A single packed list value
  was rejected because it would make source locations, recovery, and edits less
  precise.
- Chords remain physical positions because that is the Phase 5 engine contract.
  Produced text, keyboard layout, Caps Lock, numeric-pad provenance, Function,
  and repeat do not enter binding identity.
- Keybinding action targets must not duplicate the application action catalog.
  The typed binding model will refer to `TerminalActionId` for application
  actions and retain `TerminalKeyBindingAction` for pane operations.
- The standard catalog's non-empty shortcut identities are reserved during
  config decoding because AppKit consumes them before Dart raw-key routing.
  Silently accepting a conflicting declaration would violate the displayed
  effective behavior.
- `TerminalConfigRepeatedOption<T>` keeps scalar resolution unchanged while a
  separate snapshot occurrence map retains each decoded value and exact source.
  Included-file occurrences arrive first, including-file occurrences next, and
  command-line occurrences last through the loader's existing traversal.
- Every repeatable option declares a hard occurrence cap. Once full, a later
  higher-precedence occurrence evicts the earliest retained value and emits one
  bounded `CFG_REPEAT_LIMIT` warning. The keybind option reserves one of the
  engine's 1,024 definition slots for the standard Control-D binding and
  retains at most 1,023 configured declarations.
- The selected syntax is `keybind = modifiers+physical-key=target`. Modifier
  names are exactly `shift`, `control`, `option`, and `command`; every
  non-unknown `TerminalPhysicalKey` has a unique lowercase stable name. Target
  names reuse the four pane-action config IDs and all 15 `TerminalActionId`
  stable names, plus `unbind` and `passthrough`.
- `TerminalKeyBindingDefinition` and its resolution now distinguish pane and
  application action identities without copying the application catalog.
  Existing constructors and programmatic duplicate-conflict behavior remain
  available. `standardWithOrderedOverrides` is the config boundary where later
  declarations intentionally replace earlier chords.
- The first focused product-profile run failed because its new engine assertion
  was added to a separate CLI fixture that did not yet declare the two bindings
  used by the assertion. Adding those explicit CLI inputs corrected the fixture;
  no production behavior changed.
- Focused config, keybinding, and product-profile tests now pass. They cover all
  key names and action targets, include/root/repeated-CLI order, per-occurrence
  provenance, scalar compatibility, native-menu collision recovery, malformed
  recovery, bounded eviction, immutable snapshots/profiles, ordered chord
  replacement, and default/action factory results. Full analysis reports no
  issues.
- `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes every generated
  parser/compatibility/application/terminfo freshness gate, formats 218 files
  with zero changes, reports no analyzer issues, and completes the aggregate
  Dart suite. `make runtime-source-check` passes with `tracked=409`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- The first ordered subtask is complete. No normal-product router construction
  consumes the new profile yet; runtime behavior remains intentionally
  unchanged until the next committed subtask.
- The first commit attempt was rejected because the workspace sandbox could not
  create `.git/index.lock`; the staged scope remained intact and the identical
  commit was retried with repository metadata write approval.
- The normal hierarchy product now constructs one immutable configured binding
  engine and shares it across every pane router. Pane actions stay synchronous;
  an application action is consumed by the same single-outcome router and
  handed once to `TerminalActionDispatchScheduler`, with no PTY encoding path.
- `TerminalActionDispatchScheduler` owns no queue. It starts exactly one call to
  the existing `TerminalActionDispatcher`; concurrent invocations therefore
  resolve as `busy`, and unavailable/failed outcomes remain observable. The
  product refreshes both menu and palette availability after every scheduled
  outcome and promotes failed outcomes to its existing asynchronous error path.
- Pane resources can exist during the small startup interval before the shared
  dispatcher is installed. An application-action chord received in that
  interval is deliberately consumed with no dispatch and no terminal fallback;
  once installed, every current and future pane closes over the same scheduler.
- AppKit remains the owner of catalogued native shortcuts: config decoding
  rejects those chords, native menu projection handles them before raw key
  delivery, and the Dart router only receives accepted non-reserved configured
  chords. The focused fake-AppKit test uses a non-reserved exact chord and
  confirms one application identity with zero pane writes.
- Focused analysis initially stopped on the sandbox-prohibited Dart telemetry
  timestamp. Retrying with both `CI=true` and
  `DART_SUPPRESS_ANALYTICS=true` reported no issues. Focused Dart tests also
  initially stopped because the Metal compiler attempted to write its clang
  module cache under `~/.cache`; the requested `/private/tmp` environment was
  ignored by `xcrun metal`, so the identical tests were rerun with build-cache
  write permission and passed.
- The first complete test run correctly rejected stale Phase 7 AppKit evidence
  after `terminal_application.dart` changed. Its existing generator changed
  only the two source hashes for that file. The regenerated freshness check and
  the complete `CI=true DART_SUPPRESS_ANALYTICS=true make test` suite pass,
  including format of 218 files, analysis, and the aggregate Dart tests.
- A source-audit attempt without `CI=true` repeated the telemetry permission
  failure before the audit began. The standard CI environment passed with
  `DART_ONLY_SOURCE_AUDIT_PASS tracked=410 product_native_sources=0
  reviewed_test_native_sources=1`.
- The pane/application action routing and native-menu arbitration subtask is
  complete; generated user documentation and its freshness gate remain the
  next ordered work.
- The keybinding compatibility constants are now explicit authorities:
  `TerminalKeyBindingLimits` owns the 1,024-definition and 512-UTF-16 value
  bounds, `TerminalKeyBindingVocabulary.modifierConfigNames` owns canonical
  modifier spelling/order, and the special target names are constants on
  `TerminalKeyBindingDefinition`. Config decoding and documentation generation
  consume those declarations instead of repeating literals.
- `tool/generate_keybind_action_reference.dart` validates unique round-tripping
  key names, unique target namespaces, full application-catalog coverage,
  reconciled configured/default bounds, convertible unique native shortcuts,
  and non-reserved valid defaults before emitting deterministic Markdown.
  The checked-in result is `docs/reference/keybindings-and-actions.md`.
- The reference contains declaration precedence and bounds, all 105 physical
  key names, 4 pane action IDs, 15 application actions with titles/menu
  ownership, 1 standard binding, both special directives, and all 9 reserved
  native shortcuts. Two consecutive generation runs produced a source accepted
  by the new `keybind-action-reference-check` freshness gate.
- `test/keybind_action_reference_test.dart` independently requires the
  committed source to equal a fresh generation, checks every current key,
  pane/application action, and standard binding is present, and rejects a
  mutated reference. The aggregate runner invokes this test and `make test`
  runs the freshness target before formatting/analysis/test execution.
- README now links the generated reference from both the product inventory and
  Configuration guide. Feature evidence marks IN-09/CFG-03 as implemented but
  awaiting the final M1 keybind acceptance, and CFG-07 as complete only for the
  action/keybinding reference; full effective-config/help/settings generation
  and deprecated migration warnings remain later work.
- The first complete run after those evidence edits passed the new reference
  gate, then correctly rejected the existing compatibility coverage report as
  stale. Its generator changed only the README and FEATURE_MATRIX source hashes
  (not criteria or accepted gaps). The next complete
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` run passed every freshness
  gate, formatted 220 files with zero changes, reported no analysis issues, and
  passed the aggregate Dart suite.
- The generated keybind/action reference and freshness gate subtask is
  complete. The real M1 Developer JIT/Release AOT product acceptance is next.
- After staging the new generator, test, and reference so the Git-based source
  inventory included them, `make runtime-source-check` passed with
  `tracked=413`, `product_native_sources=0`, and
  `reviewed_test_native_sources=1`.
- Restaging this final audit note was once rejected by the workspace's
  `.git/index.lock` restriction; the identical one-file `git add` was retried
  with repository metadata write permission.
