# Phase 11 — Release candidate daily-use program matrix

## Status

- Phase: 11
- Task: release candidate daily-use program matrix
- Started: 2026-09-14
- State: in progress
- Current subtask: contract complete; versioned matrix pending

## Purpose

Turn the completed Phase 11 distribution, performance, reliability, safety,
and pinned-parity work into one reproducible release-candidate decision. The
decision must cover representative daily terminal programs and ordinary product
workflows, fail closed on stale evidence or a release-blocking result, and state
exactly which physical, credentialed, and duration-only observations it does
not claim.

## Background and current position

- Commit `5df1831` completed the pinned Ghostty P0/P1 aggregate gate. The
  mandatory post-commit roadmap reread found a clean worktree and identified
  this matrix as the only remaining Phase 11 item.
- The existing Phase 6 real-application matrix has eight controlled programs:
  Emacs, fzf, lazygit, mosh, ncurses, Neovim, OpenSSH, and tmux. Its version-2
  acceptance replays 57,737 captured PTY bytes and 32 snapshots. Seven cells
  are clean agreements; mosh has only the owned DEC mode 1001 hilite-mouse
  difference, which is explicitly unsupported, non-screen-mutating, and not a
  matrix blocker.
- `runtime-verify` already composes 22 bounded product suite families across
  Developer JIT and Release AOT: base lifecycle, display/input/render, native
  hierarchy, system recovery, shared actions, automation, native content,
  Quick Terminal, Secure Input, diagnostics, configuration/theme/localization,
  shell/desktop/OSC 52, restoration/clipboard/lifecycle, traffic/resource, and
  shutdown faults. It uses the ordinary AppKit window, real zsh PTYs, Metal,
  and shipped runtime ownership paths.
- `release-aot-distribution-verify`, `product-performance-regression-gate`,
  `product-sanitizer-fuzz-fault-gate`, and
  `ghostty-p0-p1-gap-closure` already provide the independently completed
  distribution, absolute/relative performance, native sanitizer/fuzz/fault,
  and pinned P0/P1 authorities. Their results must be referenced or recomposed;
  this task must not create weaker duplicate semantics.
- The user explicitly permits Apple notarization and long-duration-only tests
  to be skipped. ROADMAP already tracks real Developer ID/notary service,
  Intel-native no-rebuild execution, and physical 24/72-hour soak as
  post-goal follow-ups. They remain visible exclusions and are not blockers for
  the bounded M1 release-candidate decision.
- The adjacent `dart_appkit` repository is clean and generic. No product policy,
  product identifier, fixture, or code/path containing `terminal` may be added
  there; this final product matrix belongs wholly to `dart_terminal`.

## Scope

- Define a bounded, versioned daily-use matrix covering all eight reviewed
  programs and the product workflow families a person relies on during normal
  terminal use.
- Bind each program/workflow cell to an existing checked-in evidence source,
  exact gate owner, expected fixed marker, classification, and known limitation.
- Produce a checked-in, content-free release-candidate verdict that rejects
  stale source hashes, missing coverage, unexpected classifications, any
  actionable P0/P1 or silent behavior, and nonzero blocker/crash/data-loss/
  security-bug counts.
- Add one named aggregate target which composes the existing ordinary,
  distribution, performance, sanitizer/fuzz/fault, pinned parity, and
  Developer JIT/Release AOT product authorities without running shared build
  outputs concurrently.
- Update README and `FEATURE_MATRIX.md` only with claims observed by the final
  matrix and gate, then decide the Phase 11 parent.

## Out of scope

- Claiming that an automated bounded matrix is 30 days of human daily use, or
  waiting 24/72 hours solely for elapsed time.
- Physically sleeping the user's Mac, attaching/detaching a display, forcing OS
  memory pressure, accessing remote credentials, or changing system security.
- Performing real Developer ID signing, Apple notarization/stapling/Gatekeeper
  acceptance, or Intel-native no-rebuild execution.
- Recapturing third-party programs, accessing live SSH/mosh remote systems, or
  silently treating a missing external program as a passing live run.
- New product features, weakened thresholds, a new Ghostty revision, or any
  change in the generic `dart_appkit` repository.

## Dependencies and ownership boundaries

- `test/corpus/applications/matrix_v1.json` owns the eight-program scenario
  identity and bounds. `compatibility/application_matrix_acceptance.json` owns
  replay acceptance and the documented hilite-mouse difference.
- `compatibility/ghostty_p0_p1_gap_inventory.json` owns the exhaustive P0/P1
  row classifications and approved external follow-ups.
- `benchmark/evidence/product-performance-regression-macos-arm64-m1.json` and
  its generator/checker own performance thresholds and relative parity.
- The distribution policy, Universal build/audit/integration targets, native
  sanitizer/fuzz/fault targets, and 22 runtime suite families remain their own
  behavioral authorities. The daily-use matrix records their identities and
  composes them; it does not reinterpret raw output.
- Checked-in matrix/report data may contain only fixed IDs, counts, booleans,
  classifications, source-relative paths, and SHA-256 values. It must not retain
  terminal text, commands, cwd/path values from a session, PID, timestamp,
  environment, credentials, clipboard, or raw diagnostics.

## Completion conditions

1. Every reviewed application appears exactly once, every cell is accepted,
   and every non-clean result is linked to a non-mutating, non-blocking,
   explicitly owned limitation.
2. The workflow matrix covers startup/shell, input/editor, multiplexer/remote,
   hierarchy/content, configuration/appearance, automation/integration,
   lifecycle/recovery/resource, and distribution/performance/security/parity.
3. A strict generated-evidence checker rejects stale hashes, schema/order/count
   drift, missing/duplicate coverage, unknown gate owners, a false duration or
   notarization claim, nonzero release-blocker classes, actionable P0/P1, silent
   misbehavior, or an unowned program gap.
4. One named aggregate target runs the exact required authorities sequentially
   and emits a fixed content-free success marker only after all pass.
5. README, matrix, and this memo distinguish bounded M1 evidence from the three
   post-goal follow-ups; final diff review and the adjacent generic-library audit
   are clean; no known blocker/crash/data-loss/security bug remains.

## Verification approach

- Add focused parser/generator tests with positive checked-in freshness plus
  hostile schema, hash, program, workflow, gap, blocker, and unsupported-claim
  mutations.
- Register the focused test in the aggregate Dart runner and the checker in the
  ordinary Make gate so stale release-candidate evidence fails normal CI.
- Run the named release-candidate target on the Apple M1/arm64 baseline. Reuse
  deterministic bounded reliability rather than waiting for duration alone;
  retain exact child and final markers in this memo.
- Run formatting, analysis, the exact ordinary repository gate, `git diff
  --check`, tracked-artifact review, and the adjacent `dart_appkit` status plus
  case-insensitive tracked path/content audit before each completion commit.

## Ordered subtasks

1. **Contract, program/evidence inventory, and bounded-duration boundary**
   - Freeze this memo, the eight reviewed programs, workflow families,
     evidence/gate ownership, privacy rules, release-blocker criteria, and the
     three explicit external/duration exclusions.
   - Completion: the documentation-only split is complete and `git diff
     --check` passes; commit it and reread ROADMAP before implementation.
2. **Versioned daily-use matrix and fail-closed checker**
   - Add the strict schema, deterministic generated report, focused hostile
     tests, aggregate test registration, Make generate/check targets, and
     ordinary-gate freshness integration.
   - Completion: focused and exact ordinary gates pass; the report is bounded,
     content-free, and rejects every prohibited release claim; commit it and
     reread ROADMAP.
3. **Bounded release-candidate aggregate and Phase 11 closure**
   - Compose and run the existing distribution, performance, safety, parity,
     and complete two-mode product authorities; update public/matrix wording,
     audit the generic boundary, and close the parent only on complete success.
   - Completion: the named aggregate and exact full gate pass, evidence and
     exclusions are documented, the worktree is clean after the task commit,
     and all Phase 11 roadmap items are complete.

## Investigation log

- 2026-09-14: Repository inventory found no existing release-candidate or
  daily-use matrix artifact/tool. Reusing only the Phase 6 application matrix
  would omit normal product UI, configuration, recovery, distribution,
  performance, and safety ownership; running only `runtime-verify` would omit
  the reviewed third-party program classification and release evidence.
- 2026-09-14: The final gate must therefore combine two axes: eight pinned
  program replay cells and eight bounded product workflow families. Checked-in
  evidence decides coverage/classification; live bounded gates decide current
  product behavior. These axes are related but must not be collapsed into a
  false claim that captured external applications were freshly launched.
- 2026-09-14: Recursive aggregate targets used earlier are safe only when run
  sequentially. The final composition will avoid parallel `make` and reuse
  shared build/runtime outputs deliberately. Exact prerequisite selection is
  deferred to subtask 3 after the versioned matrix fixes the required gate IDs.
- 2026-09-14: The documentation-only contract records all eight programs,
  eight workflow families, evidence owners, release-blocker/privacy rules, and
  explicit notarization/Intel/duration exclusions. The ROADMAP split and link
  resolve correctly, `git diff --check` passes, and no source, generated
  evidence, runtime output, or adjacent repository file changed. The first
  child is complete; the versioned matrix/checker is the next ordered child.
