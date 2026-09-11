# Phase 9 — Kitty image animation and resource eviction

## Task identity

- Date started: 2026-09-11
- Scope: fifth Phase 9 roadmap item
- Feature-matrix owners: CAP-11, SEC-01
- Status: first child committed; second child verified, completion commit pending
- Predecessor: `docs/phase9/kitty-graphics.md`

## Purpose and background

Extend the completed bounded static Kitty graphics path with protocol-defined
multi-frame animation and deterministic resource reclamation. Animation must use
the existing process-worker decode, per-screen state, immutable viewport, shared
color atlas, ordinary Metal frame scheduler, and renderer recovery boundaries;
it must not add UI-isolate decode, a second native rendering path, or unbounded
timers/resources. Resource pressure must reclaim eligible images predictably
instead of turning every full bounded store into a permanent rejection state.

## Scope

- Fix the Kitty v0.48.2 and Ghostty `d4d8f62` animation, composition, timing,
  deletion, and quota/eviction semantics used by this product.
- Admit only bounded animation commands with exact query/quiet/reply behavior,
  worker decode, generation ownership, and primary/alternate-screen separation.
- Store a bounded number of frames and bytes per image and screen; define atomic
  replacement/composition, validation, stale-result, failure, and teardown rules.
- Advance visible animations from one monotonic deadline through the ordinary
  newest-frame scheduler, pausing hidden/occluded work and never replaying missed
  ticks as a burst.
- Project the selected immutable frame through the existing CPU oracle and Metal
  tile atlas with generation-safe invalidation, pins, backpressure, renderer
  replacement, and content-free metrics.
- Implement deterministic protocol-compatible eviction under image/frame/byte
  pressure, including placement and atlas-cache cleanup without dangling IDs.
- Close public compatibility/security documentation and accept representative
  animation/eviction cases through real zsh PTYs and Metal in Developer JIT and
  Release AOT.

## Out of scope

- Kitty file, temporary-file, and shared-memory transports.
- Virtual/relative placement and the extreme-negative under-background z band.
- Sixel, iTerm2 inline images, network fetches, audio/video codecs, or native
  ImageIO decoding.
- Desktop notifications, progress, semantic prompts, OSC 52 UI, and later Phase
  9 work.

## Dependencies and initial facts

- Commit `88f7ca9` completed static Kitty grammar, worker decode/storage,
  placement/lifecycle, CPU golden, shared color-atlas/Metal rendering, renderer
  recovery, real-product acceptance, and public compatibility closure.
- Static decoded storage is currently reject-on-cap at 64 images, 1 MiB per
  image, and 16 MiB per screen. Placements are capped at 256. Animation commands
  and animation-specific delete forms currently fail closed.
- `TerminalNewestFrameScheduler` and `TerminalPresentationClock` already provide
  bounded monotonic animation deadlines, hidden/occluded suppression, newest-only
  pending work, and no missed-tick replay for cursor/BEL presentation. Exact reuse
  constraints must be confirmed before product design is fixed.
- The shared color atlas is bounded, LRU-evicted, build/submission pinned, and
  fully republished after renderer replacement. Animation-frame identity and
  stale tile invalidation must remain separate from glyph identity.
- The exact Kitty/Ghostty frame actions, frame numbering/composition, loop/timing
  behavior, and quota eviction priority remain investigation items; no behavior
  will be inferred without the immutable sources.

## Ordered subtasks

1. **Animation protocol and bounded frame state.** Pin and document exact frame/
   control/composition semantics, extend typed grammar and worker/session FIFO,
   and add generation-safe per-image frame state with explicit count/byte/time
   limits, atomic mutation, exact replies, malformed/backpressure/failure tests,
   and a standalone completion commit.
2. **Monotonic playback and CPU/Metal projection.** Select immutable frames from
   one bounded deadline, connect changes to the ordinary newest-frame scheduler,
   pause hidden/occluded or synchronized presentation correctly, invalidate
   atlas tiles by frame generation, and prove deterministic CPU/Metal pixels,
   backpressure, recovery, and timer cleanup in a standalone completion commit.
3. **Deterministic resource eviction and parent closure.** Implement the pinned
   quota priority across images, frames, placements, and atlas cache; prove flood,
   active/pinned, history, screen, reset, failure, and teardown boundaries; run
   both real-product runtimes, refresh compatibility/public docs, pass the full
   gate, and close the parent in a standalone completion commit.

The parent remains incomplete until all three children pass independently.

## Completion conditions

- Every admitted animation selector/parameter and eviction priority is tied to an
  immutable source and exact reply/state behavior; excluded forms fail closed.
- Frame count, decoded/retained bytes, dimensions, duration, loop count, queued
  work, timers, atlas entries, instances, and replies all have overflow-safe hard
  bounds, with no content retained in diagnostics.
- Animation composition, start/stop/loading/loop behavior, frame deletion,
  replacement, scrolling/history, primary/alternate, clear, RIS, reflow, and
  resource eviction are deterministic and cannot leave dangling references.
- Decode remains outside the UI isolate; late work, old animation ticks, evicted
  IDs, renderer replacement, or disposed sessions cannot resurrect resources.
- Hidden/occluded/synchronized/backpressured presentation remains constant-space,
  renders only the newest eligible frame, and recovers through one bounded
  deadline without tick storms.
- CPU oracle, Metal readback, focused protocol/state/scheduler/flood/failure
  tests, full analyzer/formatter/generator gates, Developer JIT and Release AOT
  real-PTY/Metal acceptance, docs, ROADMAP closure, diff review, and per-child
  commits all pass.

## Verification plan

- Protocol whole/every-split/bytewise tests for frame transmit/control/compose,
  parameter defaults/bounds, query/quiet replies, malformed commands, multipart,
  worker saturation/failure, and stale completions.
- Store/controller tests for frame identity, atomic composition, timing metadata,
  loop/load/start/stop, deletion, replacement, per-screen isolation, eviction
  priority, history/clear/RIS/reflow, and exact caps under flood.
- Fake-clock scheduler tests for deadlines, early/late polls, coalescing,
  visibility/occlusion, synchronized output, backpressure, failure recovery, and
  complete timer/resource teardown.
- CPU 1x/2x golden and native Metal readback for changing/composed frames, atlas
  reuse/invalidation/eviction/pins/replacement, plus real zsh PTY product cases in
  both required runtimes.
- Regenerated compatibility evidence, `dart analyze`, focused tests,
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`, `git diff --check`, staged
  scope review, and one completion commit per child.

## Investigation log

- 2026-09-11: immediately after commit `88f7ca9`, ROADMAP, README,
  FEATURE_MATRIX, recent commits, repository structure, and the clean worktree
  were reread. The first unchecked item is image animation and resource eviction;
  later notification, OSC 52 UI, and fuzz/security work must not start early.
- 2026-09-11: this roadmap item spans protocol/worker state, monotonic rendering,
  and quota reclamation with independent failure boundaries. It is split into the
  three ordered children above before implementation; all are also recorded
  beneath the parent in ROADMAP.
- 2026-09-11: Kitty v0.48.2 lines 771–929 and 984–1021 define `a=f` frame
  transmission, `a=a` control, and `a=c` composition. Frame 1 is the root/base
  image; new frames default to 40 ms, negative gaps are gapless, partial frame
  loads alpha-blend by default or overwrite with `X=1`, and use either a prior
  frame (`c`) or 32-bit RGBA background (`Y`) as the canvas. Control `c` selects
  the current frame, `s=1/2/3` means stop/loading/run, `v=1` loops forever and
  larger values mean `v-1` loops. Composition uses `r` as source and `c` as
  destination despite the reversed wording in the reference table; the prose,
  example, and pinned Ghostty implementation agree. Same-frame overlapping or
  out-of-bounds composition is `EINVAL`; absent image/frame is `ENOENT`.
- 2026-09-11: direct multipart continuation for frame data must repeat `a=f`
  (with `m` and optional `q`) according to Kitty lines 365–367. The current
  static compatibility predicate permits only `m/q`, so the first child must
  distinguish static and frame continuations while keeping the same worker FIFO
  and final-chunk cursor/context ownership.
- 2026-09-11: Kitty lines 671–702 define `d=f/F`; pinned Ghostty selects the
  image by `i` or newest `I` and the 1-based frame by `r`, clamps zero to the root
  and oversized values to the last frame, promotes frame 2 when deleting the
  root, and treats lowercase on a one-frame image as a no-op while uppercase
  removes the whole image and placements. Delete remains reply-free.
- 2026-09-11: Kitty quota guidance requires deleting older images to admit new
  data and preferentially reclaiming unplaced images; `N=1` is a transient hint
  that may raise eviction priority. The fixed Ghostty policy is deterministic:
  transient-unplaced, persistent-unplaced, transient-placed, persistent-placed,
  then oldest generation and lowest image ID. It excludes the image being
  replaced or receiving a frame and evicts whole images with their placements.
  This policy belongs to the third child; the first child retains reject-on-cap
  admission for frame bytes.
- 2026-09-11: the pinned Ghostty commit contains a separate
  `src/terminal/kitty/graphics_animation.zig` (5,810 bytes, SHA-256
  `d798431b96e977009cc46b5d43b67b7f623a7b1ec62bf8bfe00c80ac4304cecf`).
  The previously fixed command/exec/image/storage/renderer files were downloaded
  again and match their recorded hashes. The animation source eagerly resolves
  every extra frame to a full image-sized RGBA buffer, caps traversal by the
  retained frame list, advances at most one displayed frame per tick, skips only
  bounded gapless frames, parks loading/finite-loop completion, and reanchors a
  restarted monotonic clock. This new exact source must be added to the canonical
  inventory rather than relying only on a wildcard description.
- 2026-09-11: existing Dart storage already keeps every root image as canonical
  RGBA, so eager full-frame RGBA is the smallest auditable model and does not
  require a new decoder or native ABI. The first child will cap each image at 64
  total frames, each screen at 256 extra frames, and root-plus-frame bytes at the
  existing 16 MiB screen ceiling. Integer gaps and loop values remain bounded by
  the protocol's parsed 32-bit domains; a later single-deadline scheduler will
  bound wakeups and missed-tick behavior.
- 2026-09-11: the first child now types `a=f`, `a=a`, `a=c`, and `d=f/F`
  fields separately from static placement fields. Direct animation multipart
  continuation accepts only the protocol-required repeated `a=f` plus `m` and
  optional `q`; a static `m/q` continuation cannot silently join a frame load.
  The response encoder includes bounded `r=` identity after `i/I,p` and keeps
  the existing quiet policy. The new public protocol value types are exported
  through `lib/dart_terminal.dart`.
- 2026-09-11: decoded frame payloads continue through the existing process
  worker and session-owned FIFO. The initial command pins parser-time screen
  ownership and the target image's stable resource generation; replacement or
  deletion before worker completion returns `ENOENT` and cannot attach pixels
  to a newer image. Worker backpressure/failure and malformed multipart aborts
  retain the initial image/frame identity, while animation-control and deletion
  success remain reply-free.
- 2026-09-11: each image now owns one root plus at most 63 eager full-size RGBA
  frames. A screen admits at most 256 extra frames and counts root plus frame
  bytes against its existing 16 MiB ceiling. Creation validates the base and
  all caps before allocation/mutation; edits are byte-neutral; static image
  replacement, clear, and frame deletion release exact frame counts/bytes.
  This child intentionally remains reject-on-cap so the later eviction child
  can add one independently testable deterministic reclamation policy.
- 2026-09-11: frame creation uses 40 ms when `z=0`, zero for negative gaps,
  optional prior-frame or RGBA-color canvas, clipped source-over by default,
  and overwrite only for `X=1`. Existing-frame edit is in-place and only a
  nonzero gap changes timing. `a=c` rejects missing source/destination frames,
  out-of-bounds rectangles, and same-frame overlap before mutation; transient
  usage propagates through every involved frame. Control fields apply
  independently, reset loop/timing state as specified, and ignore invalid or
  out-of-range selectors without a success response.
- 2026-09-11: `d=f/F` is silent, resolves by ID or newest number, clamps frame
  zero/high to root/last, promotes frame two when deleting the root, repairs the
  current index/content generation, and removes the whole one-frame image plus
  placements only for uppercase `F`. Root resource generation remains stable
  across frame changes; a separate monotonic content generation is reserved for
  the next child's viewport/atlas invalidation.
- 2026-09-11: focused tests cover grammar fields, every split and bytewise APC,
  exact `r=`/quiet replies, valid and forbidden multipart forms, process-worker
  decode/backpressure, stale target generations, control/composition/deletion,
  alpha/overwrite state, root promotion, transient propagation, and exact byte,
  aggregate-frame, and 64-total-frame ceilings. The first sandboxed focused run
  did not enter Dart because the Metal hook could not write
  `/Users/remi/.cache/clang/ModuleCache`; its approved retry reached a fixture
  failure because a non-final base64 chunk was not four-byte aligned. The
  fixture was corrected from a two-byte to a four-byte chunk, and the grammar,
  controller/store, and compatibility-inventory focused tests then all passed.
- 2026-09-11: an initial formatter invocation changed the intended Dart files
  but also encountered the sandbox-external telemetry timestamp; subsequent
  `CI=true DART_SUPPRESS_ANALYTICS=true dart format` and focused analysis pass
  with no diagnostics. The first `make compatibility-inventory` attempt hit the
  same Metal module-cache permission boundary; the approved retry regenerated
  the 20-source inventory and Phase 6 summary. The dependent differential
  baseline (4 cases, 202 input bytes, 210 split runs), implementation manifest,
  and regression coverage report (9 cases, 390 input bytes, 417 split runs)
  were regenerated successfully.
- 2026-09-11: the exact completion gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed. It verified every
  generated/freshness contract including the 20-source compatibility inventory,
  formatted 260 Dart files with zero changes, reported no analyzer issues, and
  completed the unified suite with `dart_terminal tests passed`. `git diff
  --check` also passed. The first child meets its acceptance conditions; the
  playback/projection child has not started.
- 2026-09-11: the first child was committed as `4c7a5a3 Add bounded Kitty
  animation frame state`. Immediately afterward ROADMAP, README,
  FEATURE_MATRIX, repository structure, recent history, and the clean worktree
  were reread. The second child is now the first unchecked item; deterministic
  eviction and every later Phase 9 feature remain out of scope until it passes.
- 2026-09-11: the existing live surface already owns the only product `Timer`
  and derives its next wakeup from `TerminalNewestFrameScheduler`. Animation
  playback is therefore exposed as a bounded scheduler driver with one optional
  deadline, not as a store-owned timer. The scheduler pauses that driver while
  hidden, occluded, or synchronized-output-held; the live surface will also
  pause it while renderer recovery or scale publication prevents rendering.
- 2026-09-11: the pinned Ghostty animation loop advances at most one displayed
  frame on a late tick, skips at most the retained count of zero-gap frames,
  parks on a loading or exhausted finite animation, and reanchors a future
  timestamp instead of replaying time. The Dart store mirrors those bounds and
  accepts only the visible image-ID set projected from the active viewport, so
  unplaced, history-only, alternate-screen, and clipped images schedule no work.
- 2026-09-11: stable image resource identity cannot also identify mutable frame
  pixels: reusing it as the color-atlas key would collide with existing tiles.
  Each retained frame therefore owns a monotonic content generation. Viewport
  image/placement association continues to use the stable resource generation,
  while CPU pixels select the current immutable frame and Metal tile keys use
  its content generation. Returning to an unchanged earlier frame reuses its
  atlas entries; editing that frame allocates a fresh generation.
- 2026-09-11: the first focused analyzer pass found two integration-only
  boundary errors: the live driver referenced a nonexistent convenience getter
  for the inactive store and named a result type imported privately by the
  screen-set library. It now selects the inactive primary/alternate store from
  the public `usingAlternate` state and lets the public method result be inferred;
  no new export or wider API surface is required.
- 2026-09-11: CPU 1x/2x animation goldens were generated, and focused store/
  controller, CPU golden, atlas, native Metal readback, and renderer-replacement
  tests passed. Starting six native-assets-backed test entry points in parallel
  made one scheduler-only process race on `.dart_tool/lib/libdart_pty_macos.dylib`;
  `install_name_tool` observed the shared destination before its copy completed.
  This is a build-hook concurrency artifact rather than a product assertion;
  all further native-backed runs are serialized and the affected test is rerun
  alone.
- 2026-09-11: the first serialized scheduler test exposed an error in its fake
  animation driver: an early poll incorrectly moved the fake deadline forward,
  so the exact original deadline could not become due. The fake now retains an
  unelapsed deadline and schedules from `now` only after an actual change,
  matching the production store contract.
- 2026-09-11: frame edits and compositions reserve their next content
  generation before changing pixels, gaps, transient state, or playback timing.
  Generation exhaustion therefore fails before mutation instead of leaving new
  bytes under an old atlas identity; creation already reserved before insertion.
- 2026-09-11: one serialized focused command accidentally passed this Markdown
  memo to `dart format`; the formatter rejected it before any file change and
  `&&` prevented every following test from running. The corrected command limits
  formatting to Dart source before rerunning the same tests.
- 2026-09-11: the corrected serialized focused suite passed: store/controller
  timing and visibility, scheduler fake-clock/backpressure/pause cleanup, CPU
  1x/2x checked-in goldens, color-atlas content generations and pins, native
  Metal 1x/2x frame readback, and full atlas republish to a replacement
  renderer. Repository-wide `dart analyze` also reports no issues.
- 2026-09-11: the first exact `make test` passed dependency resolution, VT
  parser table, parser trace, configuration reference, and keybinding reference,
  then stopped because the Phase 7 AppKit acceptance inventory was stale after
  the intentional live-surface edit. The canonical generation target must
  refresh and review that derived evidence before retrying the full gate.
- 2026-09-11: after the first successful full gate, public capability text was
  reviewed and found to still call playback/projection unimplemented. README,
  FEATURE_MATRIX, and the generated compatibility source now distinguish the
  completed scheduler/CPU/Metal work from deferred eviction and final product
  acceptance. The first inventory regeneration then correctly rejected the
  expanded note for exceeding its 1,024-character bound; the canonical note was
  condensed without dropping limits, pause semantics, evidence, or exclusions
  before regeneration.
- 2026-09-11: the bounded inventory and summary then regenerated successfully.
  The next full gate correctly found its dependent reviewed differential
  baseline stale because that report pins the inventory and implementation-
  manifest hashes. Regeneration follows the established dependency order:
  implementation manifest, reviewed baseline, then regression coverage.
- 2026-09-11: the implementation manifest, reviewed differential baseline
  (4 cases, 202 input bytes, 210 split runs), and compatibility regression
  coverage (9 cases, 390 input bytes, 417 split runs) regenerated in dependency
  order. The final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed
  every freshness check, formatted 260 Dart files with zero changes, reported
  no analyzer issues, and completed the unified suite with
  `dart_terminal tests passed`. `git diff --check` passed as well. The second
  child meets its scheduler, projection, recovery, and cleanup conditions; only
  deterministic resource eviction and final product closure remain in the
  parent item.
- 2026-09-11: README was finally clarified so its existing two-runtime claim
  applies only to the already accepted static graphics path. After refreshing
  the dependent coverage hash, the exact full gate passed again with all
  freshness, format, analysis, and unified-test results unchanged.
- 2026-09-11: the first explicit `git add` was denied because the default
  filesystem sandbox cannot create `.git/index.lock`; no path was staged or
  changed. The same enumerated task-only path list is retried through the
  approved repository Git-write boundary before staged review.
