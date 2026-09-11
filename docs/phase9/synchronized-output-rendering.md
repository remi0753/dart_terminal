# Phase 9 — Synchronized output and rendering

## Task identity

- Date started: 2026-09-11
- Scope: second Phase 9 roadmap item
- Feature-matrix owner: CAP-09
- Status: subtask 1 complete; subtask 2 pending
- Predecessor: `docs/phase9/kitty-keyboard-protocol.md`

## Purpose and background

Implement DEC private mode 2026 so modern terminal applications can update the
canonical grid continuously while the user keeps seeing the last accepted
frame. Disabling the mode, resetting the terminal, or reaching a bounded
deadline must publish only the newest complete state. This closes the
presentation-atomicity gap observed in the immutable fzf and lazygit captures
without introducing a second screen model or an unbounded frame queue.

The protocol-origin document defines `CSI ? 2026 h` as begin synchronized
update, `CSI ? 2026 l` as end synchronized update, and DECRQM as feature/state
detection. It deliberately does not standardize a timeout. The pinned Ghostty
baseline uses a boolean DEC mode, keeps parsing while its renderer returns the
previous frame, restarts a 1,000 ms reset timer on enable, and wakes rendering
when that deadline resets the mode.

## Ordered subtasks

1. **Bounded parser-to-presentation hold, timeout, and compatibility closure**
   - Add boolean mode-2026 state, set/reset dispatch, DECRQM, RIS reset, and
     chunk-independent tests.
   - Gate damage capture, viewport/accessibility publication, presentation
     animation, frame build, and submission behind a monotonic 1,000 ms hold.
     Re-enable restarts but never extends one deadline beyond the latest begin;
     reset/timeout releases one newest full presentation.
   - Prove constant pending state across large mutations, screen switches,
     hidden/occluded windows, native backpressure, and teardown. Extend the
     compatibility inventory and remove only the synchronized-output gap from
     immutable fzf/lazygit replay.
2. **Real PTY/Metal product acceptance and parent completion**
   - Drive begin/partial/end and abandoned-begin streams through a real PTY,
     parser, live Metal surface, and injected monotonic observations.
   - Assert no intermediate accepted frame, one newest release frame, timeout
     recovery, legacy immediate presentation, and bounded/clean resources in
     Developer JIT and Release AOT.
   - Update README, FEATURE_MATRIX, Phase 6 compatibility documentation, run
     the complete normal and product gates, and close the parent item.

The first subtask is a complete semantic implementation rather than a parser-
only declaration: the captured application gap is not removed until the
renderer behavior exists. Each subtask is independently verified, documented,
marked in ROADMAP, and committed before the next one begins.

## Scope

- DECSET/DECRST 2026 and exact DECRQM set/reset reports.
- Session-owned boolean state shared by primary and alternate presentation.
- Canonical screen mutation, PTY replies, and input remain live during a hold.
- One monotonic 1,000 ms deadline, restarted by every accepted begin.
- Constant-space coalescing in the existing dirty screen/newest-frame pipeline.
- One full redraw of the newest state on end, timeout, RIS, recovery, or resume.
- Existing immutable fzf/lazygit evidence and both M1 product runtimes.

## Out of scope

- Buffering or delaying PTY input, parser execution, query replies, scrollback,
  screen mutation, or process lifecycle.
- Nesting/counting repeated DECSET 2026. DEC private modes are boolean; a
  repeated set only restarts the safety deadline.
- A second grid, copied frame history, or a queue proportional to output bytes,
  rows, frames, or the number of begin controls.
- Theme reports, Kitty graphics, notifications, OSC 52 UI, and later Phase 9
  work.
- Copying Ghostty, Contour, or another terminal's implementation.

## Dependencies and initial facts

- `TerminalScreenSet` owns session-wide DEC modes and is the parser sink's
  state authority. Primary/alternate grids share resources but remain distinct;
  synchronized presentation is session-wide, not per screen.
- `TerminalSession` parses every raw PTY batch before its single `onChanged`
  notification. A begin, mutations, and end received in one batch are therefore
  already naturally coalesced before the surface is scheduled.
- `TerminalLiveMetalSurface` owns damage capture, accessibility projection,
  cursor/bell deadlines, one scheduling timer, and newest-only frame submission.
  `TerminalDamageOutbox` retains no transferred payload and the screen already
  coalesces dirty ranges at bounded grid size.
- During a hold, leaving dirty state in the canonical screen is both cheaper
  and safer than consuming it into a retained render-model copy. Release can
  request a full snapshot, atomically replacing any stale retained model and
  correctly handling alternate-screen transitions.
- The immutable application capture is 57,737 bytes across 32 snapshots.
  Before this task it replays with 63 unsupported increments, 6 variants, and
  4 owned gaps. Only the two mode-2026 variants and the fzf/lazygit gap entries
  belong here.

## Protocol and comparison evidence

- Contour VT Extensions `synchronized-output.md`, retrieved 2026-09-11:
  5,967 bytes, SHA-256
  `7cb1e9bc9fad9b56d81ebd7d0e8dad423c1b865ce1089d99f2f175239b9dde89`.
  It defines boolean begin/end semantics, continued emulation, DECRQM detection,
  and intentionally leaves timeout policy unspecified.
- Ghostty baseline `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`:
  `src/terminal/modes.zig` is 17,749 bytes with SHA-256
  `3acd54343dd5c53448020708fb3182fd3396ac029b21fe9305a20e9e107af4e1`;
  `src/termio/stream_handler.zig` is 79,219 bytes with SHA-256
  `ce6140a6b6cddc303816edfc4058a251ae134cb34d3e86623eea61010fa562dc`;
  `src/termio/Thread.zig` is 18,182 bytes with SHA-256
  `e49ed4f996f37ee5dc64ab6f14b49e93d19488795ffb7febb049382bd1d7b593`;
  `src/termio/Termio.zig` is 29,679 bytes with SHA-256
  `e828fe8b538122933141305b55f2fff9a12f5481e859b9b286da92914f00b055`;
  and `src/renderer/generic.zig` is 152,842 bytes with SHA-256
  `ccdcca8ef11c3d94fe6823b836a1ed9fd57089c00879fd45b32f72aab8c7c0d5`.
  The reviewed paths declare mode 2026, start/restart a 1,000 ms safety timer,
  reset and wake on expiration, and return from frame update while set.

## Design decisions

- Keep the protocol bit and transition generation in `TerminalScreenSet`; keep
  monotonic time and scheduling in the live surface/render domain. Parser code
  must not depend on wall time or create timers.
- Hold before damage capture. The last accepted Metal frame stays visible,
  canonical screen mutations remain bounded by existing grid/scrollback caps,
  and no intermediate render-model/frame payload is retained.
- The live surface records a fresh deadline whenever the mode's transition
  generation changes to enabled. A matching reset clears it. Timeout calls an
  explicit screen-set expiration method so DECRQM immediately reports reset.
- Release requests a full screen snapshot and full redraw, then captures only
  the newest state. This avoids applying post-hold deltas to a retained model
  whose active-screen identity or row versions may no longer match.
- Query replies and PTY writes are never gated. Synchronization controls only
  presentation, as required by the origin semantics.

## Completion conditions

- Begin preserves the last accepted visible frame across arbitrary chunking and
  mutations; end exposes one newest canonical state without an intermediate
  frame.
- Abandoned begin recovers at 1,000 ms through monotonic scheduling, resets the
  reported mode, and cannot freeze a visible, hidden, or occluded pane.
- RIS and teardown cancel the hold safely. Screen switching and resize during a
  hold produce a full, generation-consistent newest frame on release.
- Pending damage/frame/timer state stays constant-space and within existing
  bounds under at least 100,000 mutations and repeated begins.
- fzf/lazygit mode-2026 captures replay without an owned reject. Highlight
  mouse and theme report/update gaps remain explicit and unchanged.
- Focused tests, formatter/analyzer, full normal gate, both M1 product gates,
  source/bundle scope checks, staged diff review, and clean shutdown pass.

## Verification plan

- Direct screen-set/parser tests for mode transitions, DECRQM, RIS, invalid
  forms, transition generations, and every single split.
- Pure scheduler/gate tests with injected monotonic time for begin/end/restart,
  exact deadline, regression rejection, release invalidation, constant pending
  state, visibility, and backpressure.
- Live product integration using real PTY output and Metal frame counters in
  Developer JIT and Release AOT.
- Compatibility manifest/inventory/application acceptance/differential/
  regression freshness, `dart analyze`, `CI=true make test`, runtime source and
  bundle audits, `git diff --check`, and staged-scope review.

## Investigation log

- 2026-09-11: after commit `06cf8c2` (`Close Kitty keyboard product
  acceptance`), ROADMAP and the predecessor memo were reread from a clean
  worktree. The first unchecked item is synchronized output/rendering; no later
  Phase 9 task is in scope until it is completed and committed.
- 2026-09-11: README, ROADMAP, FEATURE_MATRIX, repository layout, ownership
  ADR, Phase 4 damage/frame/live-surface records, Phase 6 immutable evidence,
  parser mode dispatch, screen state, render scheduler, product wiring, tests,
  generators, and Make targets were inspected before code changes.
- 2026-09-11: the work spans protocol/core, presentation scheduling,
  compatibility artifacts, and two runtime products. It was split into the two
  ordered, independently accepted subtasks above before implementation.
- 2026-09-11: the protocol source branch resolved to immutable commit
  `05050a11e793c8f4362bf4e34a59ed3f7e5105fe`; downloading that exact raw file
  reproduced the previously inspected 5,967-byte artifact and SHA-256
  `7cb1e9bc9fad9b56d81ebd7d0e8dad423c1b865ce1089d99f2f175239b9dde89`.
  The new inventory family is therefore `contour`, not an inferred DEC/xterm
  assignment.
- 2026-09-11: the first direct formatter invocation successfully formatted the
  selected files but returned nonzero only while updating an external Dart
  telemetry timestamp denied by the workspace sandbox. The exact scoped
  formatter was repeated with telemetry suppressed under the normal build-cache
  permission and completed cleanly; no source workaround was introduced.
- 2026-09-11: the first focused screen-set run reached the native build hook
  but could not write the user Metal cache in the sandbox. The same test was
  rerun with the established cache permission and passed. This was an
  environment boundary, not a product failure.
- 2026-09-11: the first pure gate test inspected time 1,019 before issuing a
  restart at time 900, correctly triggering the monotonic-clock guard. The
  pre-restart check was corrected to time 500 so the fixture preserves causal
  order; production monotonic validation was retained unchanged.
- 2026-09-11: a scheduler-level defense was added in addition to the live
  surface hold. Even if a future caller attempts direct submission while held,
  no frame is built and one newest pending marker survives. A 1,024-revision
  test proves release retries one native backpressure response and accepts only
  revision 1,025.
- 2026-09-11: manifest/inventory generation made the reviewed differential
  baseline stale solely because its in-process provenance pins the exact
  implementation-manifest digest. The first coverage generation therefore
  stopped. Regenerating the deterministic four baseline observations changed
  only that provenance digest; differential semantics remained 8 agreements,
  4 unavailable, and 0 unexpected mismatches. The acceptance and coverage
  artifacts were then regenerated in dependency order.
- 2026-09-11: the first complete normal gate reached the Phase 7 AppKit
  acceptance freshness check and stopped because `FEATURE_MATRIX.md` is an
  exact hashed source. The acceptance artifact was regenerated from unchanged
  Phase 7 criteria plus the new matrix digest; the gate was restarted from the
  beginning. No acceptance criterion was weakened.
- 2026-09-11: final diff review found that parser-side DECRST clears the core
  bit before `notifyScreenChanged`, so checking only that bit could publish the
  new caret rectangle just before the held gate released the matching frame.
  All immediate caret publication paths now require both the core bit and the
  render-domain gate to be open. This preserves same-batch begin/end behavior
  while keeping end/reset, resize, viewport, and preedit geometry atomic with
  the release frame.
- 2026-09-11: the scheduler regression was extended so release while occluded
  stays as one pending full redraw, then survives backpressure after visibility
  returns. Because the Phase 7 AppKit acceptance pins the exact scheduler test
  digest, the next full gate correctly stopped at freshness again. Its unchanged
  criteria were regenerated with the new test digest before the final rerun.

## Verification results

- Focused `terminal_screen_set_test`, `terminal_reply_test`, and
  `frame_scheduler_test`: passed after the final scheduler defense. The screen
  stress covers 100,000 canonical mutations; the scheduler stress covers 1,024
  held revisions, occluded release/resume, and native backpressure.
- Scoped `dart analyze` over all changed core/renderer/test sources: no issues.
- Compatibility surface, inventory, application acceptance, and regression
  coverage focused tests: passed. Inventory revision 4 has 8 immutable sources,
  267 records, and 113 reconciled product declarations (89 selectors plus 24
  modes).
- Immutable application replay: 8 accepted cells, 6 clean agreements, 2
  documented-gap cells, 3 remaining gaps, 4 variants, and 7 unsupported
  increments. fzf/lazygit each replay mode 2026 with zero rejects.
- Differential acceptance: 12 accepted results, 8 agreements, 4 unavailable,
  0 documented/unexpected gaps; its four semantic observations changed only
  their pinned implementation revision.
- Final scoped formatter and analyzer after the caret publication fix: one file
  formatted with zero changes and no analyzer issues.
- Complete `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed after the
  final fix. It validated every generated/freshness contract, formatted 246
  files with zero changes, reported no analyzer issues, and passed the complete
  Dart test runner.
- `git diff --check`: passed. Staged-scope and index review are performed
  immediately before the first-subtask completion commit.
