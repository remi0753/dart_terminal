# Phase 9 protocol fuzz, security, and memory validation

## Status

- Phase: 9
- Task: protocol-specific fuzz, security, and memory tests
- Started: 2026-09-12
- State: in progress
- Current subtask: authority and retained-resource state-machine stress (complete)

## Purpose

Close Phase 9 with deterministic adversarial evidence that the modern protocol
features remain chunk-independent, fail closed at their authority boundaries,
and retain only their documented bounded working sets under sustained hostile
input. This task validates the already selected protocol semantics; it does not
expand the supported wire surface.

## Background

Phase 9 has completed Kitty keyboard, synchronized output, light/dark and size
reports, Kitty graphics and animation, desktop notifications/progress/semantic
marks, and OSC 52 confirmation policy. Each feature has focused boundary tests
and Developer JIT/Release AOT product acceptance. The older Phase 3 property
runner predates those features: its generated parser uses a 32-byte string cap,
and its structured fragments do not deliberately exercise the Phase 9 grammar,
authority, or large retained-resource boundaries. The final roadmap item must
add that cross-protocol adversarial layer without replacing the focused tests.

## Scope

- Add fixed-seed, bounded, reproducible Phase 9 protocol generators and
  mutations covering valid, malformed, truncated, cancelled, over-limit, and
  interleaved sequences under whole, generated-chunk, and bytewise delivery.
- Assert parser recovery, exact reply digests, per-screen keyboard/state
  isolation, synchronized-output constant-space behavior, and bounded desktop
  signal/OSC 52/Kitty graphics admission.
- Exercise application authority state machines with generated focus, active,
  policy, approval, reset, close, timeout, pasteboard-generation, and native
  failure transitions. Terminal bytes must never acquire native authority
  without the exact live grant.
- Stress Kitty image worker/controller/store, notification queues/live IDs,
  OSC 52 pending/tracked sessions/replies, and synchronized rendering at product
  or deliberately smaller injected caps while checking exact retained counts,
  bytes, cleanup, and forward progress.
- Reuse the existing native resource, Kitty graphics, synchronized-output,
  desktop-signal, and OSC 52 Developer JIT/Release AOT suites to close the Phase
  9 exit conditions; update public/testing documentation and generated evidence
  only where the new test surface requires it.

## Out of scope

- New protocol commands, new clipboard or notification authority, new Kitty
  transport media, or changing the compatibility classification of intentional
  subsets.
- Internet-scale or nondeterministic continuous fuzzing, sanitizer-specific
  native builds, operating-system memory-pressure policy, or an absolute RSS
  threshold whose allocator and shared-framework noise cannot be attributed to
  a protocol owner.
- Phase 10 UI, accessibility, Secure Input, automation, or notification work.
- Replacing the existing Phase 3 generic parser fuzzer, focused protocol tests,
  or real-product acceptance suites.

## Dependencies

- The fixed source/behavior decisions and focused tests recorded by every prior
  `docs/phase9/` task memo.
- `test/terminal_property_fuzz_test.dart` for the local xorshift/reproduction
  precedent and bounded diagnostics, but not for Phase 9-specific coverage.
- Parser/screen snapshots and observable counters; bounded image worker,
  controller, and store limits; application coordinator fake ports and clocks.
- Existing `runtime-*-integration`, `runtime-resource-integration`, source audit,
  bundle audit, and exact repository gates.

## Risks and invariants

- Random execution must be exactly reproducible across SDK runs. Every failure
  reports suite seed, case, operation, and a bounded diagnostic; arbitrary
  payloads, clipboard content, notification content, paths, or environment data
  are not dumped.
- Generators have fixed case, operation, byte, allocation, and wall-clock
  budgets. Fuzz code itself must not create an unbounded queue or turn a product
  hard cap into excessive test memory.
- Chunking cannot change final typed state, replies, retained resource counts,
  eviction order, or authorization decisions.
- Parser models retain no AppKit/native port. Coordinator fakes count calls but
  never gain actual pasteboard or notification capabilities.
- A fuzz-discovered product defect is fixed and regression-pinned within the
  current ordered child before proceeding. Acceptance conditions are never
  weakened merely to preserve an old deterministic digest.
- Memory evidence is based on exact owner-visible counts/bytes and zero-after-
  dispose checks, complemented by existing native-handle runtime stress. A noisy
  process-wide RSS sample is diagnostic only and is not used as a false proof of
  protocol ownership.

## Completion conditions

1. Every Phase 9 protocol family has a deterministic valid/adversarial property
   case with chunk equivalence, recovery, bounded counters, and stable output.
2. OSC 52 and desktop notifications prove exact authority and revocation under
   generated multi-session lifecycle transitions with zero unauthorized fake
   native calls and complete cleanup.
3. Kitty graphics/animation worker and storage, protocol queues, synchronized
   output, and session reply ownership pass sustained bounded floods without
   exceeding documented/injected limits or retaining state after disposal.
4. Focused tests, both shipped runtime modes for relevant protocol/resource
   suites, source/bundle audits, documentation, generated evidence, exact
   `CI=true DART_SUPPRESS_ANALYTICS=true make test`, final diff review, ROADMAP
   and Phase 9 exit-condition closure, and a standalone final child commit pass.

## Validation approach

- Keep parser/state properties synchronous and deterministic; use immutable
  digests instead of full attacker-controlled output in success/failure lines.
- Keep coordinator/security properties on fake clocks and fake native ports.
  Explicitly model the maximum live set and verify every cleanup transition.
- Use injected small caps for combinatorial pressure and at least one product-
  cap case per retained-resource family. Reuse product runtime suites for native
  ownership rather than adding a second hidden AppKit path.
- Run focused format/analyze/tests for each child, the exact full gate before
  every child completion, and runtime/audit gates for the closure child.

## Ordered subtasks

1. **Deterministic Phase 9 parser and state properties**
   - Add a fixed-seed suite for Phase 9 CSI/OSC/APC protocol fragments, bounded
     mutations, whole/generated/bytewise chunk plans, exact state/reply digest,
     parser recovery, and per-screen/reset isolation.
   - Complete when every modern protocol family is represented, all executions
     are bounded and reproducible, focused format/analyze/tests and the exact
     repository gate pass, and the child has a standalone commit.
2. **Authority and retained-resource state-machine stress**
   - Add generated multi-session OSC 52/desktop-signal authority transitions and
     Kitty worker/controller/store plus protocol-queue floods with fake ports,
     clocks, reduced caps, product-cap boundary cases, and zero-after-dispose
     assertions.
   - Depends on child 1. Complete when unauthorized native calls remain zero,
     every exact grant/revocation and stale-generation boundary holds, retained
     counts/bytes never exceed caps, cleanup is complete, the exact gate passes,
     and the child has a standalone commit.
3. **Shipped-runtime/resource acceptance and Phase 9 closure**
   - Run the relevant Developer JIT and Release AOT protocol/resource suites,
     source and bundle audits, document the security/memory contract and all
     Phase 9 exit evidence, refresh generated inventories if necessary, and
     perform final full validation and review.
   - Depends on children 1 and 2. Complete when both runtime modes and audits
     pass, no Phase 9 residual work is untracked, the parent/exit conditions are
     closed in ROADMAP, and the final child is committed.

## Findings and decision log

- 2026-09-12: Post-commit reread after `493797d` (`Verify OSC 52 in shipped
  runtimes`) found a clean worktree and selected this final Phase 9 roadmap item.
  Phase 10 remains out of scope and work stops after this parent and all Phase 9
  exit conditions are verified.
- 2026-09-12: The existing Phase 3 property runner executes 96 generated inputs,
  seven reviewed seeds, 112 mutations, and 837 whole/chunk/bytewise/recovery
  runs. Its intentionally small 32-byte string limit and pre-Phase-9 structured
  fragment set make it a useful deterministic-design precedent, not sufficient
  evidence for modern protocol payload and authority boundaries.
- 2026-09-12: Existing focused Phase 9 stress is already substantial and must be
  composed rather than duplicated: synchronized output covers 100,000 held
  mutations and 1,024 scheduled revisions; Kitty storage covers a 1,024-image
  deterministic eviction flood and real-product 65-image pressure; worker caps
  are 64 pending transfers/8 MiB encoded, per-screen image caps are 64 images,
  256 placements, 256 extra frames, and 16 MiB; desktop parser queues and live
  IDs are capped at eight; both application coordinators cap tracked sessions at
  64; OSC 52 permits only one global pending confirmation.
- 2026-09-12: The repository's native resource suite measures exact AppKit owner
  counts across 1,000 create/release iterations rather than relying on allocator
  RSS. This task adopts the same exact-owner approach for protocol memory and
  reserves process-wide RSS for non-gating diagnostics.
- 2026-09-12: The first focused property run passed formatting and scoped
  analysis, then reproducibly found a whole-versus-generated-chunk state drift
  at suite seed `0x509f52a1`, derived case seed `0xf2213f56`, case 28. The
  failure occurs before the suite result is accepted and is treated as a
  possible product parser defect until a bounded first-difference diagnostic
  proves otherwise. No seed, case count, or assertion will be weakened to make
  it pass.
- 2026-09-12: The bounded diagnostic isolated the drift to an OSC 133 command
  row flag after printable text autowrapped and scrolled at the bottom margin.
  `printAscii` marked a destination only when `cursorRow` changed; a bottom
  scroll keeps the cursor on the same physical row, so only a later parser
  chunk happened to mark the new row. The same edge existed on the scalar slow
  path. Both paths now idempotently mark the final destination row, and a
  focused two-row regression compares the same bytes with and without a chunk
  immediately after the scrolling scalar.
- 2026-09-12: After the product fix, scoped formatting made no changes, scoped
  analysis reported no issues, the focused semantic-prompt regression passed,
  and the dedicated property target passed deterministically. Its pinned result
  covers eight protocol anchors, 64 bit mutations, 64 generated mixed programs,
  680 whole/generated/bytewise/repeat/recovery executions, 731,150 parsed bytes,
  and state hash `2246715040` under suite seed `0x509f52a1`.
- 2026-09-12: The first child suite uses bounded, content-free digests for
  replies, Kitty command data, OSC 52 envelopes, and notification text; failure
  output shows only the suite/case identity and the first differing digest line
  truncated to 160 characters. Every run validates both screen topologies, the
  16-frame Kitty keyboard stack/known flag mask, desktop pending/completion
  queues, text byte caps, callback data caps, parser ground recovery, and RIS
  cleanup across all modern protocol state.
- 2026-09-12: The Phase 7 source inventory was regenerated after the parser
  sink fix. The dedicated property target passed again, followed by the exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate: every freshness,
  compatibility/differential/application, terminfo, shell integration, format
  (269 files, zero changes), analysis (no issues), and Dart test stage passed.
  The deterministic parser/state property child meets its completion conditions.
- 2026-09-12: Commit `99bfb0e` (`Fuzz modern terminal protocol state`) recorded
  the first child. The required post-commit ROADMAP and task-memo reread found a
  clean worktree, confirmed the authority/resource stress child as the next
  ordered item, and left shipped-runtime closure as its only successor.
- 2026-09-12: The second child will reuse public owner diagnostics rather than
  infer memory from process RSS: OSC 52 pending/tracked-session metrics, desktop
  queued/live/tracked counts, image-worker pending transfer bytes, Kitty
  controller FIFO bytes/jobs, and image-store retained RGBA bytes. Fake native
  ports will require an explicit application-side call scope so any projection
  attempted directly by parser input is counted as an unauthorized call.
- 2026-09-12: The first scoped formatting command mistakenly included the
  Makefile and Markdown task memo in the `dart format` arguments. Dart correctly
  rejected those non-Dart inputs while formatting the two Dart files (one
  changed); this was a command-selection error, not a source failure. Subsequent
  formatting and validation commands are restricted to Dart source paths.
- 2026-09-12: The initial stress implementation formatted successfully. Scoped
  analysis reported only an unnecessary duplicate import and the test runner's
  use of `print`. The first fixed-seed execution then stopped at OSC 52 operation
  155 on the combined authority/cap assertion. The seed and operation remain
  fixed; bounded counter diagnostics are being added to distinguish fake-port
  authorization, tracked ownership, and reply-length causes before changing any
  model or expectation.
- 2026-09-12: Bounded diagnostics identified the operation-155 failure as one
  unauthorized generation observation. This was a harness bug: the periodic
  invalid-UTF-8 condition intended only for writes also suppressed the ask-time
  generation grant for a valid clear. Restricting that condition to write
  operations retained the same seed and operation counts; the complete stress
  suite then passed with 1,024 OSC 52 transitions, 1,024 desktop transitions,
  1,024 image-worker transitions, and 2,048 image-store transitions.
- 2026-09-12: The new suite covers eight mixed OSC 52 policy sessions, explicit
  content/generation capabilities, approval/denial/stale/focus/inactive/reset/
  timeout transitions, the one-pending-request invariant, bounded replies, and
  the exact 64-session rejection boundary. It also covers eight desktop sessions,
  parser-only no-native-call assertions, internal-only native identities, queue
  and four-live-ID caps, sliding-budget/focus/reset cleanup, and its exact
  64-session boundary. Both fake ports finished with zero unauthorized calls and
  zero retained registrations/native identities.
- 2026-09-12: Resource stress covers injected image-worker caps of four pending
  transfers and 32 encoded bytes, a gated Kitty controller FIFO capped at eight
  jobs/64 bytes with rejection and forward progress, and a store capped at four
  images/eight placements/eight extra frames/128 exact retained bytes. The
  product-boundary case retained exactly sixteen 1 MiB RGBA images, evicted the
  oldest on the seventeenth admission, and cleared to zero. Scoped analysis had
  no issues; the OSC 52, desktop projection, image worker, Kitty controller, and
  dedicated Make target all passed.
- 2026-09-12: The exact child completion gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed. All generated-source,
  configuration, compatibility, differential/application, terminfo, and shell
  integration freshness checks passed; formatting covered 270 Dart files with
  zero changes, analysis reported no issues, and the full Dart suite (including
  the 4,096-operation security/resource stress runner) passed. Diff whitespace
  review also passed. The authority/resource child meets its completion
  conditions with no product defect or residual child work.
