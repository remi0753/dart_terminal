# Phase 2 — Competing child-reaper fixture determinism

- Status: planned, low-priority follow-up
- Recorded: 2026-09-17
- Environment: macOS / Apple M1, stock Dart 3.13.2

## Purpose and background

Make the real PTY competing-child-reaper regression reproducible without weakening
child status, exact ownership, or positive external-reap evidence requirements.
The untouched test `live Dart child cannot steal native PTY completion` in
`packages/dart_pty_macos/test/run_tests.dart` sometimes passes its exit-code-37
assertion but then finds no `externalReapObserved` diagnostic and throws
`Bad state: No element` at line 900. An immediate unchanged isolated rerun passed.
Earlier Settings and Context Dock task memos record the same signature.

## Scope, exclusions, dependencies, and risks

- Investigate whether native/Dart reap winner selection or asynchronous diagnostic
  delivery explains the missing event. Do not assume either cause from timing.
- Compare native exit/status retention, Dart backend diagnostic delivery, and
  the real fixture's external-reap expectation. Consider a narrowly test-owned
  deterministic synchronization boundary if needed, preserving production policy.
- Exclude window Close behavior, arbitrary process handling, and acceptance
  changes that merely delete the external-reap assertion or tolerate lost status.
- Depends on existing native PTY ownership/status contract and its real/fake
  tests. Retain user changes and keep native test-only hooks out of public API
  unless explicitly justified by the boundary contract.
- Risk: forcing scheduling can accidentally change the path under test; simple
  sleeps or broad retries can hide rather than fix nondeterminism.

## Acceptance and verification plan

1. Record the proven root cause with reproducible observations, not raw commands
   or process content outside the fixture.
2. Preserve a deterministic positive test of external Dart reap with retained
   exact status and matching diagnostic evidence, plus correct native-winner
   behavior, teardown, no zombie/live owner, and no double completion.
3. Run repeated isolated real-process tests and the full project gate without
   fixture-dependent failures. Record the repetition count and failure history.
4. Update docs and roadmap only after evidence passes and commit independently.

## Evidence

- Minimal read-only inspection during the original gate failure:
  `PtySession.cc` emits external-reap diagnostics only when `waitpid` returns
  `ECHILD` and a valid process-exit-ready status has already been observed.
  `native_backend.dart` decodes this as a distinct diagnostic event, and its
  final exit path completes the exit future and closes the diagnostic stream.
  These branches motivate winner/delivery hypotheses, but do not establish
  which occurred in the failed run; production code remains unchanged.

See `../phase7/tabbed-window-close-focus-regression.md`,
`../phase8/settings-effective-config-inspector.md`, and
`../phase7/context-dock-process-input-privacy.md` for observed failures and
unchanged successful reruns. No implementation has been started for this item.
