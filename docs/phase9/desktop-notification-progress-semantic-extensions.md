# Desktop notification, progress, and semantic prompt extensions

## Status

- Phase: 9
- Parent task: desktop notification, progress, and semantic prompt extensions
- Started: 2026-09-11
- State: in progress
- Current subtask: rate-limited native projection and lifecycle integration

## Purpose

Complete the remaining bounded terminal-to-desktop signalling surface without
turning untrusted terminal output into an unbounded native side effect or a
command-history side channel. The result must parse documented notification,
progress, and selected semantic-prompt extensions into immutable bounded state,
then project only policy-approved state through owned application boundaries.

## Background

Phase 8 already supplies privacy-safe OSC 133 `A`/`B`/`C`/`D`/`P` lifecycle
state, shell resources, prompt navigation, and conservative close hints. Phase 9
already supplies bounded Kitty graphics resources and renderer scheduling. The
compatibility inventory still classifies OSC 133 as partial and has no desktop
notification or progress protocol records. `FEATURE_MATRIX.md` identifies all
three surfaces as remaining CAP-12 work and explicitly requires notification
rate and memory limits.

The exact protocol selection is being established from immutable primary-source
pins before implementation. Existing title, cwd, palette, clipboard, graphics,
PTY, and semantic row ownership must remain unchanged.

## Scope

- Add immutable primary-source pins and generated compatibility records for the
  selected notification, progress, and semantic-prompt extensions.
- Parse accepted forms with exact payload, identifier, count, and numeric bounds;
  malformed, unsupported, and oversized forms must be safely ignored.
- Keep protocol state immutable and content-minimal. Do not retain command lines,
  prompt text, shell history, arbitrary icons, URLs, or attacker-selected native
  identifiers beyond the documented bounded needs.
- Add deterministic per-pane/session lifecycle, rate limiting, coalescing, reset,
  close, alternate-screen, and restore semantics where the selected protocols
  require them.
- Project policy-approved native notifications and progress through existing
  AppKit/application ownership boundaries, with fakes and observable diagnostics.
- Extend real PTY and native product acceptance, compatibility evidence, public
  documentation, and the Phase 9 source/resource/bundle audit.

## Out of scope

- OSC 52 confirmation and policy UI, which is the following roadmap task.
- Protocol-specific fuzz/security/memory suites beyond the focused boundary and
  regression coverage needed here; the dedicated roadmap task follows OSC 52.
- Remote notification media fetches, arbitrary command execution, command or
  prompt content retention, shell-history capture, and notification action URLs.
- Changes to existing Kitty graphics storage limits or semantic close admission
  that are not required by an accepted extension.
- Implementing later roadmap items or weakening current privacy and native-thread
  ownership guarantees.

## Dependencies

- Bounded OSC collection and dispatch in `TerminalParser`, plus generated
  compatibility/source evidence.
- `TerminalScreenSet` reset/alternate-screen ownership and Phase 8 semantic state.
- Pane/session lifecycle, fake PTY harnesses, app controller/window ownership, and
  `dart_appkit` notification/progress capabilities (to be confirmed by inventory).
- Phase 9 Developer JIT and Release AOT product acceptance harnesses.

## Risks and invariants

- Terminal output is untrusted. It must not generate an unbounded number of
  native notifications, attacker-controlled durable native resources, or large
  retained strings.
- Native calls must occur on their documented owning thread and must be cancelled
  when the pane/session/window closes or resets.
- A burst must have deterministic admission, coalescing, and drop behavior that
  is testable without wall-clock sleeps.
- Progress and semantic state must not leak between panes, primary/alternate
  screens, restored sessions, or later terminal generations.
- Compatibility claims must describe the implemented subset precisely; source
  behavior is reference evidence and will not be copied mechanically.

## Completion conditions

1. Immutable sources document the exact accepted grammar and behavior for all
   three surfaces, and generated inventories remain fresh.
2. Parser/model limits, malformed input handling, state isolation, resets, and
   deterministic rate/coalescing rules have focused unit and integration tests.
3. Native projection is observable with fakes, follows lifecycle/thread rules,
   and cannot be amplified beyond the configured notification budget.
4. Real PTY/native product scenarios pass in both Developer JIT and Release AOT,
   with documented negative, burst, close, and recovery cases.
5. Formatting, analysis, focused tests, the exact `make test` gate, source/resource
   audits, documentation reconciliation, diff review, and task-scoped commits all
   pass before the parent is marked complete.

## Validation approach

- Inspect and hash immutable protocol sources before selecting grammar.
- Add pure-Dart parser/model/property-style boundary tests using injected clocks
  or deterministic event counters rather than sleeps.
- Exercise pane/session/reset/close isolation through fake PTY and app-controller
  fakes, then run gated real PTY/native product cases.
- Run targeted formatting and analysis after each subtask. The final child also
  runs the exact repository gate: `CI=true DART_SUPPRESS_ANALYTICS=true make test`.
- Record every command, expectation, result, failure, and remaining risk here.

## Ordered subtasks

1. Pin immutable primary sources, define the selected grammar and threat model,
   implement bounded notification/progress/semantic protocol models, and update
   generated compatibility evidence. No native side effects are introduced here.
2. Add deterministic notification admission/coalescing and native projection,
   plus progress and semantic lifecycle integration across pane/session/reset and
   close boundaries. Verify with fakes and focused integration tests.
3. Add real PTY/native Developer JIT and Release AOT acceptance, close remaining
   compatibility/public-documentation gaps, run the complete gate, and mark the
   parent complete only after the prior children remain verified.

Each child is documented, verified, marked complete, and committed independently.
After each commit, `ROADMAP.md` and this memo are reread before continuing.

## Current subtask: immutable sources and bounded protocol core

- Status: complete
- Started: 2026-09-11
- Purpose: freeze auditable protocol inputs and turn accepted wire forms into
  immutable, bounded, content-minimal state before any desktop side effect exists.
- Scope: source pins, grammar/threat-model decision, pure parser/models, terminal
  dispatch/state ownership, compatibility generation, and focused unit tests.
- Out of scope: native notification delivery, app progress UI, real-product
  scenarios, and parent closure.
- Completion conditions: every accepted field has an explicit limit; malformed,
  unsupported, and oversized payloads cannot mutate state; reset/screen/session
  behavior is specified and tested; generated evidence is fresh; focused format,
  analysis, tests, full gate, diff review, roadmap update, and an independent
  commit pass.
- Validation: protocol-vector and boundary tests, parser/compatibility regression,
  formatting, analysis, exact `make test`, source audit, and staged-diff review.

## Findings and decision log

- 2026-09-11: The post-eviction commit reread found a clean worktree and selected
  this parent as the first unchecked roadmap item. The only later Phase 9 items
  are OSC 52 confirmation/policy UI and protocol-specific fuzz/security/memory;
  neither may be implemented early.
- 2026-09-11: The work spans three wire protocols, generated compatibility data,
  terminal state, native application ownership, and real-product verification.
  It is therefore split into the three ordered children above before code work,
  as required by the repository task-splitting rules.
- 2026-09-11: Existing Phase 8 OSC 133 state accepts only `A`/`B`/`C`/`D`/`P`,
  validates at most 256 payload bytes, never decodes or retains options, and
  exposes only unknown/prompt/input/command-output plus per-row flags. The pinned
  Ghostty semantic parser also recognizes `I`, `L`, and `N`; exact extension
  semantics and a privacy-safe subset still require source inspection.
- 2026-09-11: The compatibility generator currently pins Ghostty
  `semantic_prompt.zig` at commit
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`, reports OSC 133 as partial, and
  has no notification/progress records. Source pins and record syntax must be
  extended transactionally with the generated artifact and freshness tests.
- 2026-09-11: Kitty v0.48.2 defines OSC 99 as
  `OSC 99 ; metadata ; payload ST`, with colon-separated metadata, 2,048-byte
  plain or 4,096-byte encoded per-chunk payloads, `i`/`d` chunk correlation,
  and concatenated title/body parts. The immutable specification is 26,196
  bytes with SHA-256
  `57188360fc9466f4e2324457ca38f7d25de5383eeedd6b982bbea8af9fc60b51`.
- 2026-09-11: Ghostty's pinned `osc9.zig` is 34,996 bytes with SHA-256
  `bd53e0d4bd049fa00c0177049a0dd9ab33d52959d12d0c1f6321719f878fb6c7`.
  It gives OSC 9 non-ConEmu payloads legacy notification meaning and maps
  OSC 9;4 states 0/1/2/3/4 to remove/set/error/indeterminate/pause, with an
  optional 0–100 progress value. Invalid ConEmu-looking inputs fall back to a
  notification there; this product will reserve the `4;` prefix and reject a
  malformed progress form so attacker-controlled ambiguity cannot create a
  native notification.
- 2026-09-11: The selected OSC 99 subset accepts only safe plain UTF-8
  `title`/`body`, optional bounded identifiers, exact `d=0/1` chunking, and
  ignored syntactically valid unknown metadata. It rejects encoded payloads,
  icons, buttons, sounds, actions, close/alive/query messages, and occasion or
  urgency controls. Each chunk is capped at 2,048 UTF-8 bytes; each aggregate
  title and body is independently capped at 2,048 bytes; pending identifiers
  and completed requests each have an eight-entry cap. Unidentified incomplete
  chunks are rejected because they cannot be correlated safely.
- 2026-09-11: OSC 133 `L` moves to a fresh line only when not already at the
  left edge; `N` has the same visible effect as `A` while command identifiers
  remain deliberately untracked; `I` starts input that becomes output at the
  next explicit LF/VT/FF. The pinned reference also supports option-derived
  command lines and click/redraw behavior, which stay excluded to preserve the
  established privacy and input-authority boundaries.
- 2026-09-11: An initial formatting command incorrectly included the Markdown
  task memo and roadmap. `dart format` rejected those non-Dart inputs and then
  hit the sandboxed telemetry timestamp; it did not alter either Markdown file.
  The corrected Dart-only command completed with the required cache permission.
- 2026-09-11: The first combined compatibility regeneration ran inventory
  before manifest. Inventory JSON was generated, but summary reconciliation
  correctly rejected the stale manifest with extra product selectors `osc:9`
  and `osc:99`. Regeneration must run manifest first, then inventory/summary.
- 2026-09-11: Manifest-first regeneration succeeded. A following direct
  inventory check was blocked before tool execution because the renderer build
  hook could not write Clang Metal module-cache files under `~/.cache`; it must
  be rerun unchanged with the established build-cache permission.
- 2026-09-11: Focused desktop-signal, semantic-prompt, compatibility-surface,
  and compatibility-inventory tests pass, including NEL, chunk, aggregate,
  queue, malformed, reset, and immutable-view cases. Focused analysis reports
  no issues. The inventory check reports revision 6, 22 sources, 272 records,
  96 implemented, 23 partial, 8 safe-ignore, 145 unsupported, and 119
  reconciled implementation entries.
- 2026-09-11: The first compatibility regression-coverage regeneration was
  stopped by the same sandboxed Metal module-cache write before its prerequisite
  check ran. The unchanged target requires the established cache permission.
- 2026-09-11: The permitted coverage run passed the nine-case regression
  corpus, then correctly exposed a second reviewed total still fixed at 90
  selectors. It is updated to the generated 92-selector/27-mode contract before
  retrying; no coverage artifact was written by the failed run.
- 2026-09-11: The next coverage retry exposed the expected provenance chain:
  application-matrix acceptance still pins the previous implementation manifest
  hash. Its only intended change is the reviewed manifest SHA-256
  `31c9f42e278639b431b8345e56f7e2229ac81b600d0fd2e8009c83458c9de1b9`;
  all cells, gaps, evidence, and acceptance criteria remain unchanged. After its
  check passes, the local differential baseline, differential acceptance, and
  regression coverage must be regenerated in that order.
- 2026-09-11: The ordered provenance refresh passed application acceptance
  (8 accepted cells, 7 clean, 1 documented-gap cell), regenerated the unchanged
  four-case/202-byte/210-split local differential behavior, regenerated
  differential acceptance (12 accepted, 8 agreements, 4 unavailable), and
  regenerated regression coverage (9 cases, 390 bytes, 417 split runs). Review
  must confirm these deltas change only hashes and the intended 22-source,
  272-record, 23-partial, 92-selector totals.
- 2026-09-11: The first exact full `make test` gate passed every freshness,
  compatibility, differential, application, terminfo, shell-resource, format,
  and unified behavior test (`dart_terminal tests passed`). Analysis completed
  with two non-fatal `directives_ordering` infos in the public barrel and test
  runner. Those imports are sorted and the complete gate is rerun so the final
  recorded analyzer result is clean rather than merely successful.
- 2026-09-11: The final exact gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed after the import-order
  cleanup. It regenerated/check-verified the revision-6 inventory (22 sources,
  272 records), reconciled all 119 product declarations, passed the unchanged
  four-case differential and eight-cell application evidence, formatted 262
  Dart files with zero changes, reported `No issues found!`, and ended with
  `dart_terminal tests passed`.
- 2026-09-11: Final `git diff --check` passed. Manual diff review confirmed that
  notification/progress parsing has no native authority, retains at most eight
  partial and eight completed requests, rejects unsafe or unsupported fields,
  and clears session state on RIS. Generated report/corpus changes are confined
  to the intended source/selector totals, new partial-support records, and
  manifest/inventory provenance hashes; the pre-existing screen observations,
  application cells, and acceptance outcomes are unchanged.

## Current subtask: native projection and lifecycle integration

- Status: complete
- Started: 2026-09-11
- Predecessor commit: `57b8526` (`Parse bounded desktop terminal signals`)
- Purpose: consume the bounded protocol state through a deterministic admission
  layer, project only admitted notifications/progress to an owned application
  boundary, and make pane/session/reset/close behavior explicit and testable.
- Scope: deterministic rate budget and coalescing, fake-observable native
  notification and progress ports, application/pane integration, semantic-state
  lifecycle integration required by the accepted extensions, teardown/reset
  cancellation, metrics, and focused unit/integration tests.
- Out of scope: real PTY/native Developer JIT and Release AOT acceptance,
  compatibility/public-documentation closure, OSC 52 UI, and protocol-wide
  fuzz/security/memory suites.
- Dependencies: the committed bounded OSC 9/99 and OSC 133 models, existing
  pane/session work scheduling and lifecycle ownership, and the audited AppKit
  bridge surface. Any missing native primitive must be added only through its
  owning package with an independently verified dependency commit.
- Completion conditions: bursts cannot exceed the configured admission budget;
  equivalent pending work coalesces deterministically; stale generations cannot
  project after reset/close; progress and semantic state remain pane-local;
  fake/native boundaries are observable; focused format, analysis, tests, exact
  `make test`, diff review, roadmap update, and an independent commit pass.
- Validation: pure admission tests with an injected monotonic clock, fake port
  integration over multiple pane/session/reset/close cases, existing lifecycle
  regression, formatting, analysis, and the exact repository gate.

## Native projection findings and decisions

- 2026-09-12: The audited `dart_appkit` surface had no user-notification or
  Dock-progress mechanism. The adjacent package now exposes bounded, additive,
  main-thread-only notification post/remove and Dock badge primitives without
  product rate, focus, pane, or progress-state policy. Its warning-clean focused
  gate and complete `make test` passed, and the dependency change is committed as
  `0615817` (`Expose bounded application notifications`).
- 2026-09-12: The product admission layer will own one application-global
  sliding notification budget, an injected monotonic clock, per-sync logical-ID
  coalescing, content duplicate suppression, internal native identifiers, and a
  bounded set of live identifiers per session. This prevents adding panes or
  reusing an attacker-supplied identifier from multiplying native alerts beyond
  the same configured budget.
- 2026-09-12: `TerminalScreenSet` needs an explicit reset generation. Existing
  notification queue generations also advance when a consumer drains work, so
  they cannot distinguish RIS after all queued work has already been projected.
  A reset-only generation lets the coordinator cancel delivered/pending native
  identities without coupling cancellation to unrelated resize/screen changes.
- 2026-09-12: Progress remains terminal-session state, matching the selected
  OSC 9;4 surface semantics. Only the logically focused session projects its
  state to the application-global Dock badge; switching focus recomputes the
  badge from the target session. Semantic state is retained only as the existing
  content-free enum in the per-session projection snapshot, and reset/close
  removes that snapshot rather than adding command or prompt text retention.
- 2026-09-12: Focused format check, `dart analyze`, and the standalone desktop
  signal projection test pass. The first unified `dart run test/run_tests.dart`
  stopped at the Phase 7 AppKit acceptance freshness gate because integration
  changed the audited `terminal_application.dart` and `terminal_session.dart`
  sources. No behavioral test failed. The dedicated generator changed only the
  expected hashes for those two files; acceptance cases and claims are
  unchanged.
- 2026-09-12: The first passing coordinator design still accepted synchronization
  by raw session ID after `removeSession`. Although `TerminalSession` serialized
  close and output callbacks safely, that API shape could let a stale external
  caller recreate closed state. It was replaced with a bounded revocable
  `TerminalDesktopSignalSessionProjection` lease. Close removes all native
  identities and state; later synchronization through that old lease drains and
  counts queued requests without a native side effect or an unbounded tombstone.
- 2026-09-12: The final admission policy is application-global: three native
  posts per sliding ten-second window by default, with a hard maximum budget of
  eight. One parser turn coalesces matching logical Kitty IDs to the last value,
  already-live identical content is suppressed by a content-free fingerprint,
  and active/focused output is dropped rather than deferred. At most eight live
  native identities are retained per each of the at-most-64 live sessions.
  Native identifiers contain only internal pane/session/serial values.
- 2026-09-12: Focused progress maps remove/set/error/indeterminate/paused to
  null, percentage, percentage-plus-error, ellipsis, and bounded paused labels.
  Focus changes recompute the one application Dock badge from the selected
  session. Projection snapshots contain only progress, the privacy-safe semantic
  enum, reset generation, and live identity count; no notification text,
  command, prompt, or history content is exposed there.
- 2026-09-12: Focused formatting, clean `dart analyze`, direct coordinator tests,
  and fake-PTY `TerminalSession` integration pass. They cover same-turn logical
  coalescing, exact sliding-window recovery, active/focused suppression,
  cross-pane global budgeting, native-ID isolation, per-session live eviction,
  focused progress switching, semantic isolation, RIS cancellation, native
  failure metrics, revoked-lease rejection, and session shutdown cleanup.
- 2026-09-12: After the dedicated Phase 7 AppKit acceptance generator refreshed
  only the reviewed hashes of `terminal_application.dart` and
  `terminal_session.dart`, the unified Dart runner passed with
  `dart_terminal tests passed`.
- 2026-09-12: The exact final gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed every generated-source,
  compatibility, differential, application, terminfo, shell-resource, format,
  analysis, and unified behavior check. It reported 264 formatted Dart files
  with zero changes, `No issues found!`, and `dart_terminal tests passed`.
- 2026-09-12: Final `git diff --check` passed. Manual review confirms all native
  calls flow through the main-isolate AppKit application boundary, port failures
  are metrics/log events rather than parser failures, reset/close are explicit,
  all queues/maps have hard bounds, and the generated acceptance delta contains
  only the two intended source hashes. No later Phase 9 work, secrets, or
  unrelated generated artifacts are included.
