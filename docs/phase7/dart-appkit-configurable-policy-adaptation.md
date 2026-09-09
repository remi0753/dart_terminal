# dart_appkit configurable policy adaptation

Date: 2026-09-10
Environment: macOS, Dart 3.13.2, local `../dart_appkit`

## Purpose

Keep Dart Terminal's product behavior explicit after `dart_appkit` moves
previously fixed Runner, window, tab accessory, external URL, split helper,
base/text view, menu, and message-pump choices into reusable application-owned
configuration.

## Background

The adjacent package now preserves its historical behavior only as safe
compatibility defaults. Dart Terminal must own the choices that are part of its
product policy rather than inheriting those defaults accidentally. The user
explicitly requested this maintenance without adding a new `ROADMAP.md` item.

## Scope

- Declare the existing regular/activate/continue/reopen Runner lifecycle and
  conservative 64-message/4000-microsecond message-pump budgets in
  `macos_application.json`.
- Centralize immutable AppKit product policy for normal window styles,
  explicit-state menus, package-created base/display text views, HTTP/HTTPS and
  mailto external URLs, and the current 8-by-8 elliptical tab marker.
- Pass the URL policy both when attaching the application and when parsing an
  untrusted hyperlink.
- Use `TwoPaneSplitView` directly instead of the deprecated source alias.
- Add focused policy assertions and refresh deterministic acceptance evidence.

## Out of scope

- Changing observable terminal UX, widening allowed URL schemes, changing
  lifecycle semantics, or tuning scheduling budgets.
- Configuring provider-owned `TerminalMetalView`; its native capability remains
  responsible for focus, autoresizing, and presentation.
- Generalizing `dart_appkit` further or starting later roadmap feature work.
- Adding or changing a Dart Terminal roadmap item.

## Dependencies and risks

- Depends on the seven adjacent `dart_appkit` commits ending at `60d5460`.
- URL parsing and opening must use the same policy instance or application
  revalidation will reject a value accepted under different rules.
- Menu auto-enablement must remain false because
  `TerminalMenuProjectionController` owns enabled-state synchronization.
- The tab accessory replacement must preserve the exact 8-by-8 ellipse and
  existing sRGB color conversion.

## Completion conditions

- No product construction site relies on a moved compatibility default where
  Dart Terminal has an application choice.
- Hyperlink parsing/opening, menu enablement, native tab metadata, split
  behavior, command-palette text presentation, and lifecycle behavior remain
  unchanged.
- Relevant focused tests, source audit, formatting, analysis, full unit suite,
  and manifest-driven build validation pass.
- The final diff contains no `ROADMAP.md` change and is committed separately
  from the adjacent package.

## Verification plan

1. Add focused policy assertions and run the directly affected application,
   hierarchy, menu, palette, hyperlink, and manifest/source-audit coverage.
2. Run `make test` for generated-evidence freshness, formatting, analysis, and
   the complete Dart suite.
3. Build the manifest-driven Developer JIT bundle to exercise strict manifest
   parsing and generated Runner metadata.
4. Review `git diff --check`, source/default searches, and the staged diff.

## Findings

- The worktree was clean on `main` before this maintenance began.
- Product windows are created in the main application, native hierarchy,
  command palette, and resource/fault probes. Plain views occur only in the two
  probes; live terminal views are capability-created custom views and accept no
  `ViewConfiguration` by design.
- `TerminalMenuProjectionController.refresh` explicitly writes every native
  item state, so auto-enablement must remain disabled for every projected menu.
- Hyperlinks were parsed with the library default and the application attached
  with the library default. The terminal policy remains HTTP/HTTPS with a host
  and no credentials plus non-authority mailto with a path, but will now be an
  application-owned immutable object used at both boundaries.
- A first broad patch found that the hyperlink controller's import context did
  not match the assumed line and therefore applied no source changes. The edit
  was split into smaller verified patches; no partial implementation had to be
  recovered.
- `terminal_appkit_policy.dart` now centralizes the terminal's immutable
  choices. The normal window, diagnostic base view, and command-palette text
  configurations intentionally reproduce prior presentation. The tab adapter
  constructs an explicit 8-by-8 ellipse rather than using the compatibility
  `tabColor` helper.
- The manifest explicitly selects regular activation, launch activation,
  application-managed last-window continuation, handled reopen, and the
  conservative 64/4000 message-pump budgets. No scheduler tuning is introduced.
- The hierarchy now exposes `TwoPaneSplitView` directly. This is a source-level
  naming correction only: the two-child, thin-divider, non-collapsible native
  behavior and ownership are unchanged.
- The first `dart format` formatted all nine requested files (one changed), then
  exited 1 because Dart attempted to update a telemetry-session timestamp
  outside the writable workspace. Verification is rerun with
  `CI=true DART_SUPPRESS_ANALYTICS=true`; the failure did not indicate a
  source-format error.
- The first analyzer run found one wrong local import for `TerminalTabColor`,
  one import made redundant by the central adapter, and three directive-order
  lints. The policy now imports `terminal_tab_metadata.dart` directly, the
  redundant import is removed, and local directives follow project ordering.
- Focused tests first stopped in the renderer build hook because Metal attempted
  to write Clang modules under `~/.cache`, which is outside the workspace
  sandbox. The same command in the approved normal environment passed the
  policy, hyperlink, menu, command-palette, and native-hierarchy test programs.
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze` passes with no issues, and
  the focused formatting check reports no source changes.
- `make runtime-source-check` passes with `tracked=399`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- The first complete `make test` reached the Phase 7 AppKit freshness gate and
  correctly rejected its pre-change acceptance inventory as stale. The
  project generator must refresh that derived evidence before rerunning the
  complete suite.
- Regenerating `phase7_acceptance_v1.json` changed only hashes for the modified
  application, hierarchy, menu, and hierarchy-test sources. Its freshness gate
  then passed. The next aggregate compatibility-coverage gate also reported a
  stale derived report, requiring the same deterministic regeneration chain.
- The compatibility generator updated only the stored SHA-256 values for
  `README.md` and `FEATURE_MATRIX.md`. Both files are unmodified and byte-equal
  to `HEAD`; their recorded hashes were already stale in the clean starting
  revision. Keeping the regenerated report is necessary for the mandated
  complete freshness gate and does not change either source document.
- After both deterministic regenerations,
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes every generated
  parser, Phase 7, compatibility, differential, application-matrix, and
  terminfo freshness check; formats 213 files with zero changes; reports no
  analyzer issues; and completes the aggregate Dart suite.
- `make RUNTIME_ARCH=arm64 developer-jit-build` successfully parses the strict
  product manifest, rebuilds the adjacent generic Runner, stages both native
  assets and the worker helper, signs, and produces `DartTerminal.app`.
  Inspection of its generated Info.plist and runtime-build-manifest confirms
  regular activation, launch activation enabled, last-window termination
  disabled, reopen handled, 64 messages, and 4000 microseconds.
- Final searches find no deprecated `SplitView`, `Window.tabColor`, implicit
  AppKit attachment policy, or unconfigured package-created Menu/View/TextView
  construction in product source. Every native product window receives the
  terminal window configuration; capability-created terminal renderer views
  remain provider-owned.
- `ROADMAP.md` is unchanged as requested. `git diff --check` passes.
- The first commit attempt could not create `.git/index.lock` under the
  workspace sandbox. The staged diff remained intact and the same commit was
  retried in the approved normal environment.

## Result

Dart Terminal now explicitly owns all application choices introduced by the
adjacent package generalization while retaining its previous observable
behavior. No unverified or deferred work remains in this adaptation.
