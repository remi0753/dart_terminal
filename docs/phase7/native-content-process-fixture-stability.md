# Native-content process observation fixture stability

- Status: not started
- Identified: 2026-09-17
- Environment: macOS / Apple M1 / arm64
- Related: [shifted boundary shortcut verification](context-dock-boundary-shift-shortcut.md)

## Purpose and background

Investigate intermittent failures in the existing Developer JIT native-content
process argv reveal/elapsed acceptance fixture. Do not treat rerunning until a
pass as a long-term stabilization strategy, or assume the new Dock shortcut
caused a process-observation regression.

## Scope, dependencies, and exclusions

- Reproduce with the smoke driver and fresh developer-jit/release-aot bundles;
  record content-free observation timings, active/focus authority and job lifetime.
- Inspect the existing pipeline's 4-second sleep, palette open/invoke/dismiss,
  process poll/activation/inventory intervals and native event ordering.
- Determine whether the defect is harness authority/lifetime or product focus/
  observation policy before choosing a fix. Preserve inactive/focus privacy
  clearing, stable identity, argument hiding, no PTY key writes and all assertions.
- Dependencies: Phase 7 native-content harness, command palette focus restore,
  Context Dock process coordinator, native application/window event state.
- Exclude SSH, shortcut remapping, global keyboard interception and unrelated
  native PTY competing-reaper work. Do not weaken timeout/argv/elapsed expectations
  merely to obtain a green run. Split work if distinct product fixes are required.

## Confirmed evidence and unresolved hypotheses

- During the shifted-shortcut task, two rebuilt JIT runs passed the new resize
  marker but timed out at argv reveal (~9350 of terminal_application.dart).
- An unchanged direct JIT run passed reveal then null-checked a missing process
  snapshot after the 1100 ms elapsed wait (~9365). A fourth unchanged direct JIT
  run passed the full suite (10398 ms); rebuilt AOT also passed (9958 ms).
- The complete `make test` rerun passed. No process/focus implementation, fixture
  lifetime, timeout or assertion was modified in the shortcut task.
- Coordinator eligibility requires active application plus visible/focused native
  window. The direct/headless harness injects initial active/focus events; prior
  foreground-inspector notes explain this requirement. Palette transitions and
  the short pipeline lifetime are hypotheses, not established causes.

## Completion criteria and verification plan

- Establish a reproducible cause with safe metadata, not private argv/path dumps.
- Apply a justified minimal fix, keep all process/privacy/elapsed/cleanup checks,
  and document why alternatives were rejected. Repeat both runtimes across focus
  transitions and measured scheduling variation with bounded attempts/time.
- Pass focused tests, formatting/static analysis, rebuilt runtime integration and
  full gate; refresh evidence if sources change, then commit this separate task.
