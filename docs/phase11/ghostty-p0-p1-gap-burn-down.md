# Phase 11 pinned Ghostty P0/P1 gap burn-down

## Status

- Phase: 11
- Task: Ghostty pinned matrix P0/P1 gap burn-down
- Started: 2026-09-13
- State: in progress
- Current subtask: P1 gap burn-down — extended rendition and protected
  selective erase (complete); next is bounded semantic ranges

## Purpose

Turn the feature matrix's pinned Ghostty comparison into a reproducible release
closure: every P0/P1 acceptance unit must have an exact product result and
traceable pinned evidence, and every remaining difference must be either fixed
or explicitly demonstrated to be a non-blocking, non-silent limitation with an
owner and bounded acceptance. No blocker, crash, data-loss, security, or silent
misbehavior gap may remain.

## Background

Earlier phases implemented the product feature rows and added parser,
differential, real-application, performance, distribution, accessibility, and
reliability evidence. The matrix still contains evidence gathered at different
times and at more than one pinned Ghostty revision, including one documented
application behavior difference and deliberately deferred physical-duration,
credential, and Intel-host observations. This task must reconcile those facts
systematically instead of treating the prose claim of feature completeness as
an executable parity decision.

The adjacent `dart_appkit` repository is a generic macOS GUI library. Any work
found here remains in Dart Terminal unless a genuinely generic substrate is
strictly necessary. No Dart Terminal implementation, product identifier, or
code/name containing `terminal` may be added to `dart_appkit`.

## Scope

- Inventory every `FEATURE_MATRIX.md` row whose priority contains P0 or P1,
  including its phase, pinned evidence, current product evidence, explicit gap,
  and gate ownership.
- Validate the accepted pinned revisions, local/captured artifact identities,
  checked-in evidence provenance, and freshness relationships without silently
  substituting a newer upstream behavior.
- Classify each remaining difference as actionable product gap, intentional
  product policy, unavailable external observation, or already-approved
  low-priority follow-up. P0/P1 product gaps are completed in roadmap order.
- Add the smallest deterministic tests and product-side implementation needed
  for confirmed P0 then P1 gaps, preserving owner/resource/security bounds.
- Provide one aggregate matrix gate and public/matrix documentation whose
  claims are limited to evidence actually executed.

## Out of scope

- P2-only parity polish and copying Ghostty UI, configuration names, or internal
  architecture where the product acceptance behavior already passes.
- Updating the pinned Ghostty revision merely because upstream has moved.
- Live network capture, unbounded differential fuzzing, or real-time 24/72-hour
  and 30-day campaigns.
- Real Developer ID credentials, Apple notarization service acceptance, and an
  Intel-native host run; those are already-approved follow-ups and cannot mask
  a product correctness gap.
- Product-specific changes or naming in `dart_appkit`.

## Dependencies

- `FEATURE_MATRIX.md` and the pinned revision declared at its top.
- `compatibility/sequence_mode_inventory.json`, implemented surface,
  differential contracts/evidence/acceptance, real-application matrix, and the
  Phase 6 regression coverage report.
- Phase 11 pinned performance comparator provenance and aggregate performance
  gate.
- Existing distribution, diagnostics, accessibility, reliability, and runtime
  acceptance notes and their Make targets.

## Completion conditions

1. Every P0/P1 row has a machine-readable, deterministic classification bound
   to its exact matrix text and applicable checked-in evidence.
2. Every actionable P0 then P1 product gap is fixed with a focused regression;
   no blocker/crash/data-loss/security issue or silent misbehavior remains.
3. Intentional differences and unavailable/deferred external observations are
   narrowly documented and cannot be reported as passing product behavior.
4. A named aggregate gate rejects stale matrix/evidence and passes the focused,
   ordinary repository, and relevant Developer JIT/Release AOT checks.
5. Public documentation and `FEATURE_MATRIX.md` match executed evidence, the
   final diff contains no unrelated/generated runtime artifact, and the
   adjacent generic-library boundary remains clean.

## Verification approach

- Build the inventory from parsed matrix rows rather than hand-maintained row
  counts, with exact allowed priority/classification vocabularies and bounded
  checked-in JSON.
- Reuse existing canonical generators and acceptance tools where possible;
  add negative freshness/ownership tests before accepting aggregate output.
- Run focused tests after each gap, then the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate for every completed
  child. Run bounded product runtime checks where behavior crosses the native
  application boundary.
- Record commands, expected markers, actual results, failures, and residual
  risks here as they are discovered.

## Ordered subtasks

1. **Contract, pinned evidence, and P0/P1 gap inventory**
   - Parse every in-scope matrix row, reconcile all existing pinned sources and
     evidence stores, and assign gap class plus gate owner.
   - Fix the versioned inventory contract and ordered implementation children.
2. **P0 gap burn-down**
   - Resolve every actionable P0 behavior/evidence gap in inventory order with
     focused regressions and no weakened acceptance.
3. **P1 gap burn-down**
   - Resolve every actionable P1 behavior/evidence gap in inventory order and
     preserve explicit policy/deferred distinctions. The order is extended
     rendition/selective erase; semantic ranges; snapshot restore; cursor-cell
     shaping break; variable axes/overrides/diagnostics; synthetic cell glyphs;
     remaining overlays/P3 conversion; then Option-click/semantic selection.
     Renderer and input consumers follow the semantic/font owners they depend
     on rather than introducing duplicate state.
4. **Aggregate closure**
   - Compose freshness and product gates, run ordinary and relevant runtime
     acceptance, update public/matrix documentation, audit `dart_appkit`, and
     close the parent only when all conditions pass.

## Inventory and decisions

- 2026-09-13: Work began immediately after commit `db54f89` and a mandatory
  roadmap reread. The sanitizer/fuzz/fault parent is complete, the worktree is
  clean, and this is the first unchecked Phase 11 item. The next item, release
  candidate daily-use matrix, will not be implemented early.
- 2026-09-13: Initial search confirmed that pinned evidence is distributed
  across the feature matrix, sequence/mode inventory, differential backend and
  capture files, application acceptance, regression coverage, and the Phase 11
  performance comparator. A complete row-by-row classification is therefore
  required before choosing any product implementation change.
- 2026-09-13: Matrix parsing found 102 in-scope rows: 69 `P0`, six `P0/P1`,
  26 `P1`, and one `P1/P2`. The reviewed classification has no actionable P0
  product gap, eight actionable P1 units (`SCR-10`, `SCR-11`, `SCR-12`,
  `TXT-07`, `TXT-08`, `TXT-10`, `REN-08`, and the P1 portion of `IN-10`), two
  rows with explicit non-silent differences, and three rows with approved
  external follow-ups. This inventory does not reinterpret the supplemental
  Ghostty query capture revision as the matrix/performance revision.
- 2026-09-13: A direct `dart format` formatted the new inventory tool and test,
  then emitted a sandbox-denied telemetry timestamp exception under
  `/Users/remi/.dart-tool`. The requested files were formatted successfully;
  subsequent Dart commands use `DART_SUPPRESS_ANALYTICS=true`, and this
  incidental analytics write is not a product or test dependency.
- 2026-09-13: The first focused verification incorrectly ran the Make check
  and direct Dart test concurrently. Both build hooks attempted the same Metal
  module-cache output under `/Users/remi/.cache/clang` and were sandbox-denied;
  the concurrently run focused `dart analyze` still reported no issues. This
  is an orchestration failure, not accepted evidence. Native/build-hook Dart
  commands will be rerun sequentially with the required local cache access,
  matching the repository's shared-output policy.
- 2026-09-13: The first exact `make test` completed with exit status zero and
  every test passed, including the new inventory marker, but `dart analyze`
  reported one informational `directives_ordering` issue in the aggregate test
  runner. The run is not the final warning-clean acceptance; the import order
  was corrected before the required rerun.
- 2026-09-13: Added a deterministic version 1 inventory at
  `compatibility/ghostty_p0_p1_gap_inventory.json` and a generator/checker at
  `tool/ghostty_p0_p1_gap_inventory.dart`. It requires the exact ordered set of
  102 P0/P1 rows, hashes each acceptance/evidence/current field, binds ten
  existing evidence files, and distinguishes the matrix/performance Ghostty
  revision `d4d8f622...` from the separately pinned supplemental differential
  revision `492300ca...`; neither may silently substitute for the other.
- 2026-09-13: Reviewed totals are 89 accepted rows, two accepted rows with
  documented differences, three accepted rows with approved external
  follow-ups, eight actionable P1 rows, zero actionable P0 gaps, and zero
  silent-misbehavior gaps. The 13 gap records carry exact row IDs, kind,
  priority, owner, actionability, and reason. P1 was split into eight ordered
  roadmap children because style/state, shaping/font, renderer, and input work
  cannot be implemented or reviewed safely as one commit.
- 2026-09-13: Focused validation passed
  `make ghostty-p0-p1-gap-inventory-check` with
  `GHOSTTY_P0_P1_GAP_INVENTORY_PASS rows=102 accepted=89 actionable_p0=0
  actionable_p1=8 documented_differences=2 external_follow_ups=3
  pinned_revision=d4d8f62`. Direct unit tests passed exact committed/generated
  equality plus stale total, pin drift, and duplicate-row negatives. Focused
  analysis reported no issues.
- 2026-09-13: After correcting the one import-order info from the first run,
  the exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` rerun passed all
  native/package, generated/freshness, compatibility/application/distribution,
  format (326 files, zero changes), analysis (no issues), and Dart tests,
  ending with `dart_terminal tests passed`. No runtime or sanitizer artifact is
  tracked by this child; the next ordered child is the zero-actionable-P0
  closure, not P1 implementation.
- 2026-09-13: After commit `42c2f7e` and the mandatory roadmap reread, the P0
  child began from a clean worktree. The only P0-classified difference is
  xterm mode 1001 in the mosh application cell: the captured sequence is reset
  only, inventory support is `unsupported`/`reject`, acceptance records exactly
  one variant, and both `screen_mutation` and `matrix_blocker` are false. The
  other P0 row carrying a follow-up is `DIST-01`; its arm64/x86_64/Universal and
  Rosetta product behavior is accepted, while an Intel-native host observation
  remains separately and explicitly unverified. Neither item authorizes
  inventing an enable handshake or treating external evidence as executed.
- 2026-09-13: The first P0 negative test removed the exact mode-1001 inventory
  owner and exposed an untyped `StateError` from `singleWhere` rather than the
  inventory's bounded validation exception. Positive data still passed. The
  validator now checks candidate cardinality first so missing or duplicate P0
  ownership fails with the task-specific, content-free classification.
- 2026-09-13: The next exact repository gate reached its format check after all
  prerequisite evidence checks passed, then stopped because the cardinality
  fix had not been run through focused format. `dart format` changed only the
  expected wrapping in the inventory tool. This procedural failure is not
  accepted as final evidence; the formatted source is retained for a clean
  rerun.
- 2026-09-13: The inventory checker now parses the canonical sequence record,
  application acceptance, and regression coverage instead of relying only on
  their hashes. It requires mode 1001 to remain one private rejected record
  with no claimed implementation/test evidence; the application gap must be
  exact, explicit, input-only, one-variant, non-mutating, and non-blocking; and
  aggregate coverage must retain zero known P0 silent corruption and zero
  blocking failures. The generated report exposes these facts under
  `p0_closure` and keeps the Intel-native observation in an explicit external
  follow-up list.
- 2026-09-13: Focused positive and negative tests passed after the typed-error
  correction. Mutating screen impact, removing the exact inventory owner, or
  changing known P0 silent corruption to one now fails closed. Focused format,
  analysis, generation freshness, and the marker with `actionable_p0=0` all
  passed.
- 2026-09-13: Final
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed all ordinary native,
  package, generated/freshness, compatibility, application, distribution,
  format (326 files, zero changes), analysis (no issues), and Dart tests,
  ending with `dart_terminal tests passed`. Diff validation before the roadmap
  status update found only the four intended implementation/evidence/memo
  files and no whitespace issue; the roadmap is the fifth final file. The
  adjacent `dart_appkit` worktree is clean and its case-insensitive code/name
  audit contains no `terminal` or `dart_terminal` occurrence. P0 closure has
  no remaining product work; the next ordered task is the first P1
  implementation child, extended rendition and protected selective erase.
- 2026-09-13: After commit `6dd8c00` and the mandatory roadmap reread, the
  first P1 child began from a clean worktree. Its purpose is to close `SCR-10`
  without changing the 17-byte cell payload: underline color and overline
  belong to immutable style definitions, while DEC character protection is
  already reserved as width/flag bit 3 by ADR-003. Scope is SGR 53/55/58/59,
  DECSCA, DECSED/DECSEL, style identity, current/saved rendition, snapshots,
  damage/render projection, and deterministic parser/render regressions.
  Semantic ranges, persisted sessions, shaping/font work, unrelated erase
  families such as DECSERA, and every change to generic `dart_appkit` remain
  outside this child. Completion requires bounded style interning, atomic
  wide/grapheme selective erase, ordinary erase overriding protection, reset
  and save/restore correctness, visible underline-color/overline output, fresh
  generated compatibility evidence, and the exact repository gate.
- 2026-09-13: Initial code inspection found that `TerminalCellFlags.protected`
  already survives packed copy, scrollback, reflow, snapshots, and topology
  validation, but parser printing hard-codes `isProtected: false` and exposes
  no current protection state. DECSCA, DECSED, and DECSEL are still declared
  unsupported in the sequence inventory and absent from the compatibility
  selector surface. `TerminalStyleTable` currently interns only a 16-bit
  attribute word; it has no underline-color column, and the compositor draws
  supported underline shapes with the resolved foreground while overline has
  no attribute or drawing operation. Therefore protection will stay a cell
  flag, whereas underline color and overline will extend the bounded style
  resource so style identity and renderer projection cannot diverge.
- 2026-09-13: The focused formatter changed only the expected Dart files, then
  the SDK again attempted to update its home-directory telemetry session file
  despite `DART_SUPPRESS_ANALYTICS=true` and exited after formatting. Analysis
  therefore did not run in that chained sandbox command. It was rerun with
  the same `CI=true`/suppression environment and the required cache access;
  focused analysis reported no issues. This is a tool telemetry restriction,
  not a source or product failure, and the final repository gate remains
  required.
- 2026-09-13: The first focused style test stopped on its fixture's old
  `definitionCount == 2` assertion after the bounded table fixture had been
  deliberately expanded to four definitions to cover underline-color
  identity and overline. The table correctly rejected the fifth definition;
  only the stale expected count was wrong. The assertion now expects four,
  and the entire focused sequence must be rerun from the beginning.
- 2026-09-13: The next focused run passed style, screen, and screen-set tests,
  then exposed another test expectation error: the maximum DECRQSS rendition
  is 84 bytes, not the estimated 87. The encoder remained below its new
  96-byte fixed cap and did not overflow; the exact expected length was
  corrected before another full focused rerun.
- 2026-09-13: The subsequent six-test focused run passed style, screen,
  screen-set, reply, compatibility-surface, and native Metal compositor
  coverage. A separate snapshot test then stopped because the readable style
  definition expectation still described the former attribute-only resource;
  the formatter correctly emitted the new `underline_color=default` field.
  The fixture now carries a palette underline color and overline so the exact
  snapshot assertion proves both additions instead of merely accepting the
  default serialization.
- 2026-09-13: The corrected standalone snapshot test passed. Regenerating the
  four deterministic differential baselines then passed with 202 input bytes
  and 210 split runs, and differential acceptance remained 12 accepted cells
  with eight agreements, zero undocumented gaps, and four unavailable external
  comparisons. The first regression-coverage regeneration was sandbox-blocked
  when the Dart native-assets hook attempted to write Clang's shared Metal
  module cache under `/Users/remi/.cache/clang`; it made no accepted report
  claim and must be rerun with the repository's already-required cache access.
- 2026-09-13: With shared-cache access, the regression prerequisite correctly
  failed closed on the reviewed `decrqss-current-sgr` observation: reply bytes,
  state, counters, and projected screen were identical, while only the full
  snapshot hash and UTF-8 size changed because every non-default style resource
  now serializes its underline-color token. This is an intentional snapshot
  contract extension; the reviewed corpus will be regenerated through its
  canonical `--generate` path and then checked before coverage is rebuilt.
- 2026-09-13: The pinned Ghostty sources were re-read at matrix revision
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. `Terminal.zig` (downloaded
  source SHA-256
  `f3c68cde1d7e871b2f901f50c85cc87a76360ff1fb56111d08f5269a9e5de602`)
  retains DEC-protected cursor state and distinguishes selective erase;
  `style.zig` (SHA-256
  `b26507489473b7b2158adf3e70c9aac2665417e582eb5c3cab5a491e6d2cf5c9`)
  carries underline color and overline in style state. This child implements
  the DEC DECSCA/DECSED/DECSEL contract; Ghostty's separately modeled ISO
  protection mode and DECSERA remain outside the matrix row and this scope.
- 2026-09-13: Canonical regeneration updated all nine reviewed compatibility
  observations and replayed 390 input bytes over 417 whole/split/bytewise
  plans. Regression coverage then regenerated successfully. Application
  acceptance still passed eight cells (seven clean and one explicit gap), so
  no external capture was rewritten. The final Ghostty inventory generation
  and freshness check passed with 102 rows, 90 accepted, zero actionable P0,
  seven remaining actionable P1, two documented differences, and three
  external follow-ups. Its positive and malformed-evidence unit tests also
  passed after formatting all 324 Dart files (one expected wrapping change).
- 2026-09-13: The first exact repository gate passed every native package,
  generated/freshness, compatibility, application, distribution, formatting,
  and analyzer prerequisite, then the aggregate Dart runner failed closed on
  the reviewed `screen-semantics` product-parser snapshot. As with the reviewed
  regression observation, line 5 differed only by the intentional appended
  `underline_color=default` style field. The product corpus snapshot must be
  refreshed through its canonical review flow before the exact gate is rerun;
  this failed run is not completion evidence.
- 2026-09-13: After reviewing and updating the sole affected parser snapshot,
  its direct harness passed all eight cases, 1,421 input bytes, and 1,437 split
  runs with aggregate snapshot hash `697844072`. The next exact gate reached
  the aggregate runner and correctly exposed that the unit test still pinned
  the former aggregate hash `995854368`; the per-case oracle was already exact.
  Both the numeric assertion and machine-readable line are updated to the
  directly observed new hash before another clean full-gate rerun.
- 2026-09-13: The following exact gate passed the corrected parser corpus and
  progressed deep into the aggregate Dart suite, where the inventory test
  exposed one remaining stale total: the reconciliation itself had already
  reported the correct 122 implementation selectors, while its unit assertion
  still expected 119. The three newly implemented DECSCA/DECSED/DECSEL
  selectors account exactly for the delta; the fixed cardinality assertion is
  retained and updated to 122 before rerunning focused and full checks.
- 2026-09-13: The next exact gate passed the corrected 122-selector inventory
  assertion and all earlier checks, then the deterministic property/fuzz gate
  reported its intentional snapshot-oracle delta: the execution budget stayed
  1,296, parsed bytes stayed 95,388, and only the state hash changed from
  `733442573` to `1691336757`. Because the accumulator hashes the complete
  snapshot, the serialized underline-color field accounts for this change;
  the fixed expected hash is updated and must reproduce in focused and full
  reruns.
- 2026-09-13: The focused property/fuzz rerun reproduced the new exact hash.
  The next full gate then stopped early in an unrelated real-PTY lifecycle
  test (`live Dart child cannot steal native PTY completion`) because its event
  lookup found no element. This same test passed in each of the three preceding
  full-gate attempts, while no PTY source changed in this child, so it is
  treated as a transient runtime observation rather than accepted evidence.
  The exact PTY target and then the complete gate will be rerun; a repeat would
  require investigation instead of being ignored.
- 2026-09-13: The isolated PTY target and subsequent complete gate both passed,
  confirming the one-off missing event was transient. Pre-commit review then
  found a real state-oracle omission: protected cell flags were readable, but
  the current and saved DECSCA attributes for future prints were not serialized.
  Because the style resource schema also gained underline color, retaining
  snapshot version 3 would silently change an exact format in place. The
  formatter therefore advances to version 4 and writes both protection booleans;
  historical application evidence versions 1–3 remain accepted, while a unit
  case proves current version 4 can coexist with immutable version-one captures.
- 2026-09-13: Focused snapshot validation passed with current/saved protection
  set true, and all eight reviewed product snapshots replayed exactly under
  version 4 with aggregate hash `915933130`. The first application-evidence
  unit rerun exposed that its former unsupported-version negative used version
  4; now that 4 is valid, the fixture correctly moves to version 5. No captured
  application snapshot or external observation is rewritten.
- 2026-09-13: The immediate rerun failed at the positive coexistence case
  because the mechanical one-token patch had changed its first `version=4`
  replacement to 5 while leaving the later negative at 4. Inspection showed
  the branches were inverted; the positive now explicitly uses version 4 and
  the unsupported negative explicitly uses 5 before rerunning the entire file.
- 2026-09-13: The corrected application-evidence file passed. Differential
  baselines/acceptance, all nine compatibility observations, regression
  coverage, and the Ghostty inventory were then regenerated in dependency
  order for version 4. The deterministic property/fuzz run preserved all
  budgets and produced the expected new snapshot-derived state hash
  `984263293`; its prior version-3 hash assertion is updated before a confirming
  rerun.
- 2026-09-13: The version-4 full gate passed every prerequisite and reached the
  Phase 9 protocol property suite, whose complete-snapshot digest intentionally
  changed from `2246715040` to `2980607666`. Its fixed workload remained eight
  anchors, 64 mutations, 64 generated cases, 680 executions, and 731,150 parsed
  bytes. The exact digest assertion is updated and will be reproduced directly
  before another full run.
- 2026-09-13: The focused Phase 9 property rerun reproduced state hash
  `2980607666`. Final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` then passed all native
  packages, generated/freshness, compatibility, differential, application,
  terminfo, shell, Ghostty inventory, distribution, format (326 files, zero
  changes), analysis (no issues), and aggregate Dart tests, ending with
  `dart_terminal tests passed`. The accepted inventory is 102 rows with 90
  accepted and seven remaining actionable P1 units. `git diff --check` passed.
  The adjacent `dart_appkit` worktree is clean, and a case-insensitive audit of
  its native/packages/scripts/test/tool/examples trees and Makefile found zero
  `terminal` or `dart_terminal` occurrences. Apple notarization and
  duration-only long-running tests were not executed, as explicitly authorized;
  neither is used to claim this product behavior. The next ordered child is
  bounded semantic prompt/command/output ranges.
