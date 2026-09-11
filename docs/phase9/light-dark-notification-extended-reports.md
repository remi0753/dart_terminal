# Phase 9 — Light/dark notification and extended reports

## Task identity

- Date started: 2026-09-11
- Scope: third Phase 9 roadmap item
- Feature-matrix owner: CAP-10
- Status: protocol core complete; product projection in progress
- Predecessor: `docs/phase9/synchronized-output-rendering.md`

## Purpose and background

Expose the product's already typed macOS light/dark appearance to terminal
applications through the modern query and opt-in notification controls used by
the immutable tmux capture, and complete the closely related bounded extended
size/Unicode reports named by the feature matrix. Reports must use terminal-
core reply ownership, while host appearance remains an AppKit/product input;
the parser must never call AppKit or infer a theme from palette colors.

The current application acceptance has three owned gaps and seven unsupported
increments. Only the theme-report and theme-update variants from tmux belong to
this task; the evidence-backed highlight-mouse non-adoption remains unchanged.

## Scope

- Identify and pin the protocol-origin query, response, notification mode, size
  report, and Unicode mode-negotiation forms with exact parameter meanings.
- Add bounded typed terminal state and reset semantics for opt-in appearance
  notifications, plus exact query replies and chunk-independent coverage.
- Route current native appearance and later native changes from the existing
  AppKit event/projection boundary into every live terminal session exactly
  once without adding content retention or cross-isolate callbacks.
- Implement only the documented extended reports whose dimensions are already
  owned by bounded screen, viewport, and font data. Advertise the existing
  always-on Unicode Core contract as permanently set rather than inventing a
  Unicode-version report or weakening the product width policy.
- Close only the tmux theme gaps in immutable replay, extend the inventory from
  immutable primary sources, and retain all unrelated gaps.
- Prove real PTY query/change behavior in M1 Developer JIT and Release AOT,
  update public/compatibility documentation, and keep resource teardown clean.

## Out of scope

- Changing the system appearance, terminal palette, user settings, or native
  window styling in response to application output.
- Guessing light/dark from foreground/background luminance.
- Kitty graphics, image lifecycle, desktop notifications, progress/semantic
  extensions, OSC 52 UI, or later Phase 9 items.
- Advertising unsupported pixel/cell metrics, font faces, Unicode widths, or
  protocol versions without an exact product authority.

## Dependencies and known facts

- Phase 8 already projects typed system/fixed appearance through AppKit and can
  drive ordinary product windows in both Developer JIT and Release AOT tests.
- `TerminalScreenSet` owns session-wide modes and `TerminalScreenParserSink`
  owns bounded terminal replies. Logical text-area pixel dimensions and rows/
  columns already feed XTWINOPS 14/18 through this boundary.
- The fixed application evidence is 57,737 PTY bytes and 32 snapshots. Current
  replay is 6 clean/2 documented-gap cells, 3 gaps, 4 variants, and 7
  unsupported increments after synchronized-output closure.
- The Phase 6 compatibility narrative still contains an older baseline table
  that labels synchronized output unsupported. This task will reconcile that
  historical/current section while updating the adjacent theme rows.

## Completion conditions

- Exact protocol forms and values are tied to immutable primary sources and a
  documented product authority for each reply field.
- Query works without opt-in mode; notification occurs exactly once per real
  light/dark transition only while enabled; duplicate appearance events are
  silent; reset/RIS/session teardown cannot leave notification enabled.
- Reply writes remain bounded and fail closed under the existing PTY reply
  backpressure policy without exposing screen content or corrupting mode state.
- Extended reports reject malformed/out-of-range forms and are independent of
  parser chunking, backing scale double application, and locale.
- tmux replays clean for the owned theme variants; highlight mouse remains the
  sole explicit application gap and no unrelated classification changes.
- Focused tests, formatter/analyzer, complete normal gate, both M1 product
  display gates, source/bundle audits, diff review, documentation, ROADMAP
  closure, and a standalone completion commit all pass.

## Verification plan

- Protocol/core tests for mode/query/reset/change/deduplication, exact bytes,
  invalid parameters, bounds, and every split.
- Compatibility manifest/inventory/application replay and all downstream
  freshness chains.
- Fake-host integration for appearance fan-out and real AppKit/PTY product
  acceptance for initial query plus two native transitions.
- Developer JIT and Release AOT display gates, `CI=true make test`, Dart-only
  source and bundle audits, `git diff --check`, and staged-scope review.

## Investigation log

- 2026-09-11: commit `042ee1e` (`Accept synchronized output in real Metal
  sessions`) completed the preceding roadmap item. ROADMAP, README,
  FEATURE_MATRIX, the current application compatibility record, and the clean
  worktree were reread. The first unchecked item is light/dark notification and
  extended reports; no Kitty graphics or later work is in scope yet.
- 2026-09-11: inspected `TerminalScreenSet`, the semantic parser sink and reply
  encoder, `TerminalSession`, `TerminalLiveMetalSurface`, and
  `TerminalApplicationThemeProjection`. Core owns grid/modes/reply encoding;
  the live surface already publishes padding-free logical viewport dimensions;
  the session is the sole bounded terminal-to-PTY reply owner; and the theme
  projection is the existing typed AppKit-to-pane fan-out boundary. Parser code
  therefore needs no AppKit import, and palette luminance is not an authority.
- 2026-09-11: pinned the protocol-origin Contour color-scheme document at
  commit `0ad6bdbee55979ba33d6432159cd3822936a6dff`: 4,845 bytes, SHA-256
  `6ba512529226511adcfee5a4d0f99a9689293e73b3e2d4d5c21afb67f45ba832`.
  It defines query `CSI ? 996 n`, dark/light replies `CSI ? 997 ; 1/2 n`,
  opt-in mode 2031, and notification only when the terminal palette changes.
  Enabling the mode itself does not require a report; a client queries 996 for
  initial state. Ghostty commit `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`
  independently encodes the same nine-byte replies in `device_status.zig`
  (4,808 bytes, SHA-256
  `244a5aa349845a7780dfff4cd2cda2efa574153774d0655727bf4d22d12f579f`).
- 2026-09-11: pinned the in-band resize proposal at gist revision
  `a1e61ea1782326e975b6e4cfe0c538bac54c1f42`: 3,095 bytes, SHA-256
  `30f0f454fb20bfc21b0d3ebeee989c02bffffcc9cf4cc19432ccefd2dfc7f1e8`.
  Mode 2048 reports `CSI 48 ; rows ; columns ; height-pixels ; width-pixels t`
  immediately on every enable and after the internal resize is complete.
  Missing pixel data is reported as zero. Fixed Ghostty `size_report.zig`
  (4,250 bytes, SHA-256
  `806a5932dd0f6c877902e884b72cc171e27d6d3d1991e97d3dd28217ad61f3ae`)
  also defines XTWINOPS request 16's `CSI 6 ; cell-height ; cell-width t`
  reply alongside existing requests 14 and 18.
- 2026-09-11: pinned Terminal Unicode Core commit
  `64f53851ceab9a3cf08db4939bcaef75a0899573`: its specification is 7,232
  bytes, SHA-256
  `f23237de5dd88ec8fee0c8059a6c979ca2eecc3e4c8fdf8ce4c4d86b7a2e47af`.
  It negotiates grapheme/width semantics through DEC private mode 2027 and
  explicitly leaves Unicode-version incompatibility for future work; there is
  no Unicode-version query/reply to implement. Dart Terminal already applies a
  single Unicode 17 grapheme/width contract unconditionally, so DECRQM will
  report 2027 permanently set and set/reset controls will be accepted no-ops.
  This preserves product correctness while giving applications an exact mode
  answer without claiming a nonexistent version protocol.
- 2026-09-11: added revision 5 of the immutable compatibility inventory. Its
  12 pins include the exact Contour color-scheme and Unicode Core artifacts and
  Ghostty device-status and size-report files above. Local copies were measured
  again with `wc -c` and `shasum -a 256`; all four byte counts and SHA-256
  values matched. The inventory now has 270 records: 96 implemented, 20
  partial, 9 safe-ignore, and 145 unsupported. Its 116 product declarations
  reconcile to 89 selectors and 27 modes.
- 2026-09-11: implemented the bounded core contract. Private DSR 996 emits the
  exact nine-byte 997 dark/light response independently of mode 2031. Mode
  2031 owns only opt-in notification state and resets on RIS. XTWINOPS 16 uses
  an independently published, padding-free logical cell size. Every mode-2048
  enable emits `CSI 48` immediately, including repeated enables; absent pixel
  data is encoded as zero. Rows, columns, and available pixels are bounded to
  65,535, and every reply stays within the existing 64-byte encoder cap.
- 2026-09-11: mode 2027 initially used an empty Dart switch case. Review caught
  that an empty case would share mode 2031's body; it was replaced with an
  explicit loop `continue`, and a regression query proves 2027 set/reset never
  changes the 2031 subscription. Unicode remains permanently set under
  DECRQM, while RIS clears only mutable report subscriptions and retains the
  host appearance value.
- 2026-09-11: the first sandboxed focused test attempt failed before execution
  because Dart tried to touch its telemetry session file outside the writable
  repository despite analytics suppression. The same test was rerun with the
  already scoped `dart run` permission and passed; this was an environment
  restriction, not a product failure.

## Ordered subtasks

1. **Immutable source pins and protocol core.** Add the four relevant fixed
   artifacts to the compatibility inventory, implement exact 996/997 replies,
   mode 2031 state/reset/reporting, XTWINOPS 16, in-band size encoding and mode
   2048, and permanently-set mode 2027. Complete when core tests prove exact
   bytes, bounds, malformed forms, every split, reset, and inventory freshness.
2. **Product projection and compatibility closure.** Seed every session with
   its rendered light/dark policy, send opt-in reports only on actual palette
   transitions, publish cell metrics, report size after completed resizes, and
   replay the immutable tmux variants. Complete when fake-host/session tests
   prove fan-out, deduplication, fixed-theme behavior, backpressure safety, and
   the owned application gaps close without changing highlight-mouse policy.
3. **Real product acceptance and parent closure.** Exercise the initial query,
   native dark/light changes, mode disable/reset, XTWINOPS 16, mode 2048
   immediate/resize reports, and clean teardown through real PTYs and Metal in
   both M1 runtimes. Then update public/feature/compatibility documentation,
   execute all normal/source/bundle gates, and close the parent only if every
   condition passes.

The subtasks are ordered: product routing depends on the exact core state and
encoders, while native acceptance depends on both. No later Phase 9 protocol
is implemented in parallel.

## Verification results

- Protocol/core subtask:
  - `dart run test/terminal_reply_test.dart`: passed exact dark/light, Unicode
    mode, modes 2031/2048, XTWINOPS 16, immediate/missing-pixel size reports,
    bounds, malformed forms, RIS, reply accounting, and whole/split/bytewise
    parsing.
  - `dart run test/terminal_compatibility_surface_test.dart`: passed all 89
    selector and 27 mode declarations plus bounded unsupported families.
  - `dart run test/terminal_compatibility_inventory_test.dart`: passed source
    pins, schema, totals, generated freshness, and 116-record reconciliation.
  - inventory, implementation manifest, and human summary `--check`: passed.
  - `dart analyze`: passed with no issues.
  - `dart format` and `git diff --check`: passed.
- Product projection, immutable application replay, real product acceptance,
  complete gate, and parent closure remain pending in ordered subtasks 2–3.
