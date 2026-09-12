# Phase 10 — Accessibility display preferences and localization

## Purpose

Complete the next ordered Phase 10 item by making the application respect the
macOS Reduce Motion, Increase Contrast, and Differentiate Without Color display
preferences, and by giving all static product-owned UI text a bounded,
injectable localization boundary with English and Japanese catalogs.

## Background and current state

- At task start, `dart_appkit` protocol version 13 published application active
  state and effective light/dark appearance but had no typed snapshot or change
  event for the three accessibility display preferences. The completed generic
  substrate now negotiates version 14 for that additive event.
- AppKit exposes those process-wide values through `NSWorkspace` and publishes
  one accessibility-display-options change notification. Observing the native
  mechanism belongs in the generic library; deciding how a terminal changes its
  animation and visual presentation belongs in this repository.
- Quick Terminal currently always uses the configured 0–5 second animation.
  Cursor blink and the 100 ms visual bell use the bounded product presentation
  clock. Reduce Motion must remove nonessential transition motion without
  changing terminal state or the user's stored configuration.
- Command Palette uses semantic AppKit label/window colors, while Settings uses
  a fixed dark product palette. Terminal content uses a mutable pane-owned
  palette and packed selection/cursor/bell overlays. The latter two surfaces
  need explicit high-contrast projection because AppKit cannot adapt their
  product-owned colors automatically.
- Selection and hyperlink rendering already have non-color geometry, and the
  Secure Input badge already has text. Tab color remains optional metadata.
  Differentiate Without Color must preserve or strengthen those shape/text
  channels and must never make color the sole indication of state.
- Static user-facing English is currently owned by
  `terminal_action_registry.dart`, `terminal_action_menu.dart`,
  `terminal_command_palette.dart`, `terminal_settings_editor.dart`,
  `terminal_settings_inspector.dart`, `terminal_osc52_confirmation.dart`,
  `terminal_secure_keyboard_entry.dart`, and application window/status
  composition. Finder Service and App Intent declarations also contain product
  display names. Machine-readable diagnostics, stable action/config IDs,
  terminal output, user-provided notification text, protocol replies, and
  generated developer references are not UI localization inputs.
- There is no locale model, message catalog, RTL decision, or catalog coverage
  test. Native menus inherit AppKit direction, but product-composed text and the
  Settings editor/detail split need an explicit application-owned direction.

## Scope

1. A generic, immutable AppKit accessibility-display-preference snapshot and a
   deduplicated application event delivered at attach and whenever the system
   notification reports a real change.
2. A product projection that applies the current snapshot live to Quick
   Terminal motion, Settings/terminal contrast, and non-color state cues while
   keeping user configuration and terminal semantics unchanged.
3. A bounded immutable localization catalog selected from an injected locale,
   with complete English and Japanese static UI messages, deterministic English
   fallback, locale-aware direction, and no localization of untrusted terminal
   content or stable machine contracts.
4. Product wiring, focused unit/native coverage, Developer JIT and Release AOT
   acceptance, documentation, feature-matrix reconciliation, and Phase 10
   completion evidence.

## Out of scope

- Translating shell output, terminal protocol text, filesystem paths, user
  configuration values, user-origin notification payloads, or stable IDs.
- Changing a stored theme, cursor-blink, or animation-duration configuration
  merely because a system preference is active.
- General bidirectional terminal emulation. Terminal cell layout remains LTR;
  RTL applies only to application-owned UI composition.
- Additional spoken-language catalogs beyond English and Japanese. Unknown
  languages must use deterministic English strings while retaining the locale's
  UI direction.
- Long-duration soak. The user explicitly made duration-only tests low priority;
  all short bounded correctness, safety, resource, and dual-runtime checks
  remain required.

## Ownership and constraints

- `dart_appkit` owns only OS observation, copied values, event versioning,
  lifecycle, validation, and typed generic API. It must not contain product
  names, terminal behavior, localized product strings, colors, or policy.
- This repository owns localization catalogs, adaptive colors/geometry,
  animation policy, application status text, and locale selection.
- New native events use the zero application source identity, operation ID zero,
  a monotonic timestamp, strict payload length/booleans, and legacy filtering.
- Display-preference changes are live application policy. Existing pane/session,
  PTY, renderer, atlas, Settings draft, and Quick Terminal identities must remain
  intact.
- All localized strings remain within the existing native text bounds. Catalog
  lookup is closed over typed message/action identifiers; missing entries fall
  back to English rather than rendering an identifier or throwing in UI code.

## Ordered subtasks

1. **Inventory and contract** — complete this ownership/risk inventory, define
   the split and acceptance conditions, and add every child to `ROADMAP.md`.
2. **Generic AppKit substrate** — add the immutable three-boolean snapshot,
   protocol event, native observer, Dart cache/stream, lifecycle cleanup,
   current/legacy FFI tests, and generic documentation in `dart_appkit`.
3. **Adaptive product projection** — add a single product controller that
   consumes the generic snapshot; suppress Quick Terminal transition duration
   and visual-bell motion under Reduce Motion, apply deterministic accessible
   Settings/terminal presentation under Increase Contrast, and retain explicit
   shape/text cues under Differentiate Without Color.
4. **Localization and RTL projection** — add typed English/Japanese catalogs,
   deterministic locale selection/fallback/direction, move every static
   product-owned UI message behind the catalog, and reverse only application UI
   composition that has directional meaning.
5. **Acceptance and closure** — pass focused and complete repository gates,
   Developer JIT and Release AOT product acceptance for live preference changes
   and both catalogs, update README/feature matrix/manual checks, and close the
   parent only when no static UI leak or resource/lifecycle regression remains.

## Completion criteria

- Initial and changed values for all three macOS preferences reach Dart exactly
  once per distinct snapshot, and stopping/terminating the application leaves
  no native observer or stale event.
- Reduce Motion produces zero-duration Quick Terminal window presentation and
  no timed visual-bell frame while preserving terminal input, output, focus, and
  configured values.
- Increase Contrast yields deterministic minimum-contrast application-owned
  surfaces and terminal overlays; Differentiate Without Color leaves selection,
  focus, secure input, disabled/error, link, and active-line states identifiable
  without relying on hue alone.
- English and Japanese expose the same complete typed message set. Unsupported
  locale tags fall back to English, Japanese regional tags select Japanese, and
  an RTL locale reverses directional application UI without changing terminal
  cells or stable action/config/protocol identities.
- Menus, context menu, Command Palette, Settings shell/detail/status, OSC 52
  confirmation, Secure Input badge, and other static product window/status text
  use the selected catalog. External/user data stays copied and untranslated.
- Focused tests, full non-duration gates, both runtime bundles/audits, live
  preference/localization integration, cleanup assertions, documentation, and
  roadmap state all pass.

## Verification plan

- Generic: C/C++ contract compile, event encoder, native observer
  start/change/dedup/stop tests, Dart strict decode/cache/stream/legacy tests,
  current and legacy FFI smoke, generic source audit, and complete `make test`.
- Product: catalog completeness/fallback/direction tests; action/menu/palette,
  Settings, confirmation, badge, theme/presentation, and controller unit tests;
  format/analyze/source audit and complete `make test`.
- Runtime: Developer JIT and Release AOT focused accessibility/localization
  suites plus bundle audit and bounded cleanup. Duration-only soak is recorded
  as intentionally skipped and is not a blocker.

## Progress

- 2026-09-13: reviewed `README.md`, all of `ROADMAP.md`, and
  `FEATURE_MATRIX.md`; confirmed the first incomplete item and the low-priority
  duration-only exception. The repository was clean before planning.
- 2026-09-13: inspected generic protocol/cache/observer patterns and product
  animation, palette, overlay, menu, palette, Settings, confirmation, badge, and
  manifest owners. The five-part plan above keeps generic mechanism and product
  policy separate and gives each child an independently verifiable commit.
- 2026-09-13: completed the adjacent generic substrate in commit `147cf2a`
  (`Observe accessibility display preferences`). Protocol v14 carries exactly
  three booleans under the zero application identity. `NSWorkspace` observation
  emits an initial copied snapshot, deduplicates complete-state changes, stops
  before event-port replacement and shutdown, and is not installed for legacy
  sinks. Dart exposes an immutable value, nullable latest cache, and typed
  stream with strict length/type/source/version/operation validation.
- 2026-09-13: generic focused tests and the exact full gate passed, including
  the ownership audit, header/native bridge/event encoder contracts, Dart API,
  runtime builder, current FFI, and v1 legacy fallback. The generic hello-window
  also built and completed its bounded Timer/menu/close/handle-release smoke in
  Developer JIT and Release AOT. No long-duration test was needed or run.
- 2026-09-13: the first consumer `make test` stopped at Kernel compilation
  because the additive sealed event made two application event switches
  non-exhaustive. Added explicit no-op cases only: isolated legacy fixtures and
  the ordinary hierarchy now accept v14 without prematurely choosing product
  presentation policy. The next subtask will replace the ordinary-hierarchy
  no-op with the dedicated live projection.
- 2026-09-13: a direct `dart format` reported no source changes but could not
  update the sandboxed user telemetry timestamp; subsequent commands set
  `DART_SUPPRESS_ANALYTICS=true`. The next complete consumer gate passed the
  new compile point, then one existing PTY process-lifecycle case did not find
  its expected child-exit event (`Bad state: No element`). This is unrelated to
  the display-preference event path; the focused PTY gate is being rerun before
  deciding whether it is an environmental transient or a blocker.
- 2026-09-13: the focused PTY rerun passed, and a second complete consumer gate
  also passed that lifecycle case. It then correctly rejected stale generated
  Phase 7 AppKit acceptance inventory because the adjacent public Dart suite
  gained the new preference-event test. Regeneration from the canonical test
  sources is required; acceptance conditions are not being weakened.
- 2026-09-13: regenerated `test/corpus/appkit/phase7_acceptance_v1.json`; only
  the two expected hashes for `terminal_application.dart` changed, and the
  acceptance check passed with the same 4 criteria, 13 source references, 10
  unit tests, 4 integrations, and 8 UI assertions. A third exact consumer
  `make test` then passed end to end, including format/analyze, all native
  capability and Dart suites, generated references, compatibility/differential
  evidence, application matrix, and bounded security stress. The isolated PTY
  failure did not recur in either rerun and is not a blocker.
- 2026-09-13: began the adaptive product projection from a clean tree after
  rereading the roadmap. The native preferences are process-wide, so one
  product controller will retain the latest immutable snapshot and fan out
  deduplicated changes. Existing panes, sessions, palettes, Settings state, and
  Quick Terminal configuration remain their current owners; the controller
  only supplies an ephemeral presentation policy.
- 2026-09-13: selected live update boundaries after inspecting the renderer,
  Quick Terminal, and Settings ownership. Reduce Motion will choose zero as the
  effective native window-transition duration and make the presentation clock
  acknowledge BEL generations without starting a timed overlay. Increase
  Contrast will use a deterministic Settings palette and black/white terminal
  overlay edges without rewriting OSC/user palette values. Differentiate
  Without Color will add selection edges, thicken link hover underlines, and
  render a bell border rather than relying on a hue change. The Settings
  window and draft stay alive while its three immutable native text views are
  transactionally replaced because their creation-time colors have no setter.
- 2026-09-13: duration-only soak remains intentionally skipped by user
  direction. Focused state/render/controller tests and the complete bounded
  repository gate remain required for this child.
- 2026-09-13: implemented `TerminalApplicationAccessibilityProjection` as the
  sole product snapshot owner. It starts from the generic AppKit cache,
  subscribes to the injected typed stream, deduplicates equal values, catches
  projection errors at the application boundary, and cancels delivery during
  teardown. New panes, Quick Terminal, and Settings receive the retained value;
  a distinct live event updates all existing surface owners without replacing
  sessions, screens, palettes, the Quick Terminal lifecycle, or its stored
  configuration.
- 2026-09-13: Quick Terminal now resolves the configured duration through the
  live product policy, returning exactly zero only while Reduce Motion is on.
  The presentation clock similarly records every monotonic BEL generation but
  creates no pulse or deadline under Reduce Motion. Enabling the preference
  clears an in-flight pulse; disabling it does not replay suppressed bells and
  affects only later generations.
- 2026-09-13: the Metal compositor now keeps OSC and theme palette values
  canonical while adapting application-owned overlays. Increase Contrast uses
  an opaque black-or-white cursor selected from WCAG relative luminance, a
  stronger selection fill, and two-tone selection edges. Differentiate Without
  Color adds explicit selection edges, doubles hovered-link underline thickness,
  and changes the visual bell from a full hue wash to a viewport border. The
  live surface exposes the three policy flags in its content-free snapshot and
  retains one newest full redraw on a real preference change.
- 2026-09-13: Settings now owns complete standard and high-contrast immutable
  presentations. All high-contrast text/syntax/diagnostic colors measure at
  least 7:1 against the black surface; active-line geometry and diagnostic
  underlines remain. Because generic native text colors are creation-time
  values, a live contrast change transactionally replaces only the editor,
  status, detail, and split views. Tests confirm the same window, draft,
  selection, NORMAL/INSERT mode, collapsed-detail state, first responder, and
  bounded native object count survive. The exception path restores the old
  owners and presentation before reporting the original projection failure.
- 2026-09-13: the first four direct `dart run` attempts were blocked before
  test entry by the Metal build hook trying to write Clang modules beneath the
  sandboxed user cache. `CLANG_MODULE_CACHE_PATH` did not affect `xcrun metal`.
  Re-running in the normal macOS build environment compiled the hook. One
  direct invocation then exposed a missing standalone `main` in the new test;
  it was added. The aggregate test next rejected the expected stale Phase 7
  source hashes; the canonical generator updated only the relevant application,
  scheduler, and native-hierarchy entries, without changing its criteria.
- 2026-09-13: final verification passed: `dart analyze` reported no issues;
  the aggregate `dart run test/run_tests.dart` passed twice (the second run
  includes the live Settings replacement); `git diff --check` passed; and the
  exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` completed all PTY,
  renderer, AppleScript, App Intents, generated-reference, compatibility,
  differential, application evidence/acceptance, terminfo, shell-integration,
  format, analyze, product, and bounded security-stress gates. The security
  stress result was seed `0x509a1171` with OSC 52/desktop/worker 1024 cases and
  store 2048 cases. No duration-only soak was run, as explicitly permitted.
- 2026-09-13: the first scoped staging attempt could not create
  `.git/index.lock` under the filesystem sandbox. The working tree remains
  intact; staging and commit are retried with repository metadata write access.
- 2026-09-13: after committing the adaptive product projection as `6ce5663`
  (`Respect accessibility display preferences`), reread the roadmap and began
  the localization child from a clean tree. This child spans independent
  catalog, presenter, application-composition, and audit deliverables, so it is
  split before implementation into four ordered roadmap children: locale and
  typed action catalog foundation; menu/palette/confirmation/status adoption;
  Settings/application/RTL/resource adoption; and a static UI leak plus catalog
  completeness closure. Each child has its own verification and commit.
- 2026-09-13: locale selection will consume an injected environment mapping in
  precedence order `LC_ALL`, `LC_MESSAGES`, then `LANG`. Empty, `C`, `POSIX`,
  malformed, and unsupported language tags select English strings. Japanese
  language tags, including regional/encoding suffixes, select Japanese. UI
  direction is derived independently from the normalized language subtag, so
  unsupported Arabic/Hebrew/Persian/Urdu tags retain English fallback strings
  but still project RTL application composition. Terminal cells, paths,
  user/PTY text, config values, stable IDs, protocol diagnostics, and machine
  markers remain unchanged.
- 2026-09-13: completed the locale/action foundation. `TerminalLocalization`
  normalizes POSIX-style encoding and modifier suffixes, selects the injected
  environment variables in the documented precedence, retains the requested
  locale for diagnostics, and resolves catalog language independently from UI
  direction. The typed action catalog contains one immutable English and
  Japanese title/keyword entry for every one of the 28 stable actions.
  `TerminalActionCatalog.standard` now projects those messages while retaining
  identical action order, menu ownership, shortcuts, separators, visibility,
  focus restoration, and stable names.
- 2026-09-13: focused localization, action-registry, and generated keybinding
  reference tests passed. Tests cover Japanese regional selection, `C`,
  `POSIX`, empty and malformed English fallback, unsupported Arabic English
  fallback with RTL direction, catalog completeness/nonempty bounds, Japanese
  search, and cross-language non-text policy parity. The exact full `make test`
  gate then passed unchanged, including format/analyze, generated references,
  application evidence, and bounded security stress. No duration-only test was
  run.
