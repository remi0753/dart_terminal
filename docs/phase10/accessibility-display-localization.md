# Phase 10 — Accessibility display preferences and localization

## Purpose

Complete the next ordered Phase 10 item by making the application respect the
macOS Reduce Motion, Increase Contrast, and Differentiate Without Color display
preferences, and by giving all static product-owned UI text a bounded,
injectable localization boundary with English and Japanese catalogs.

## Background and current state

- `dart_appkit` protocol version 13 publishes application active state and
  effective light/dark appearance, but it has no typed snapshot or change event
  for the three accessibility display preferences.
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
