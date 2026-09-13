# Phase 11 pinned Ghostty P0/P1 gap burn-down

## Status

- Phase: 11
- Task: Ghostty pinned matrix P0/P1 gap burn-down
- Started: 2026-09-13
- State: in progress
- Current subtask: P0 gap burn-down (complete)

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
