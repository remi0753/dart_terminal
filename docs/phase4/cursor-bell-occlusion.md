# Phase 4 — Cursor blink, visual bell, and occlusion pause

- Status: complete
- Date: 2026-09-06
- Scope: seventh Phase 4 roadmap item
- Related: ADR-002, ADR-003, ADR-004, SCR-03, REN-01, REN-04, REN-06,
  REN-09

## Purpose

Drive cursor blink and visual-bell animation from bounded monotonic state while
preventing an occluded terminal from building or submitting unnecessary
frames. Resume must converge on the newest terminal state with one full redraw,
without replaying hidden animation ticks or accumulating an event/frame queue.

## Background

The product now retains one newest damage-derived model marker, submits through
three native Metal slots, and atomically rebuilds resize/scale/font resources.
The terminal model already carries cursor visibility/blink state, and AppKit's
versioned window events carry visibility and occlusion. These pieces are not
yet connected to an explicit animation/pause policy.

## Scope

- Define monotonic cursor-blink and visual-bell timing/state with bounded
  deadlines and deterministic test injection.
- Coalesce animation invalidation into the existing newest-only frame policy.
- Pause frame construction/submission while occluded without dropping newer
  terminal state or resource rebuild requirements.
- On visibility resume, request exactly one full redraw against the newest
  model/resources and restart animation timing from an explicit epoch.
- Add pure-Dart state tests and real AppKit/Metal product smoke evidence where
  the existing test-gated custom-view path can exercise the public boundary.

## Out of scope

- Device, shader, command-buffer, or drawable failure recovery; this is the
  next roadmap item.
- Frame-time/atlas/upload metrics; these remain the following item.
- User configuration schema/UI for blink intervals, bell duration, colors, or
  reduced-motion preferences.
- Audible/system notification bells, focus-demand policy, multiple-window
  fairness, display-link creation, or replacing the normal application
  `TextView` path.

## Dependencies and ownership

- The render coordinator owns animation clocks and one pending frame marker;
  terminal-engine cursor semantics remain owned by `TerminalScreen`.
- AppKit supplies immutable visibility/occlusion observations on the UI owner;
  it does not run the render clock or invoke terminal model mutations.
- Occlusion may suppress work but must not acknowledge damage, release an
  in-flight transfer, mutate atlas pins, or publish partial rebuild resources.
- All counters/deadlines are bounded signed values and never wrap.

## Completion criteria

- Blink changes only when the cursor is visible and blink-enabled, never queues
  missed ticks, and resumes from a deterministic visible phase.
- A bell request starts/restarts one bounded visual pulse; repeated requests do
  not form a queue, and expiry requests at most one replacement frame.
- Occluded state builds/submits no frame. Damage/model/resource changes remain
  newest-only, and resume schedules exactly one full redraw of current state.
- Existing damage, rebuild, atlas pin, and native frame-generation contracts
  remain valid.

## Ordered subtasks

1. **Cursor/BEL presentation metadata in the strict damage protocol**
   - Carry cursor row/column/shape/visibility/blink and a monotonic visual-bell
     generation in a versioned canonical packet header.
   - Allow bounded metadata-only incremental packets, surface BEL through the
     screen parser, and publish metadata atomically in the retained render
     model without weakening row-delta ordering.
2. **Bounded animation clock and visibility/occlusion frame scheduling**
   - Add newest-only presentation invalidation to frame scheduling, with no
     build or native submit while hidden/occluded and exactly one resume frame.
   - Add deterministic cursor/bell monotonic timing, parser-to-animation
     connection, and Developer JIT/Release AOT custom-view smoke evidence.

The animation child depends on renderer-owned cursor/BEL metadata from the
first child. The failure-recovery roadmap item must not begin until both are
committed.

## Presentation damage design

- Damage wire version 2 has a canonical 104-byte little-endian header. The
  original fields remain at offsets 0–75; cursor row, cursor column, typed
  shape/visible/blinking flags, visual-bell generation, and a zero reserved
  word occupy offsets 76–103. Unknown flags, out-of-grid cursor coordinates,
  unsigned values outside the signed generation domain, nonzero reserved
  bytes, and noncanonical section offsets are rejected before publication.
- A full snapshot always carries presentation state. An incremental packet may
  contain zero rows and zero cells only when cursor or bell state is pending;
  all other zero/nonzero row-cell count combinations remain invalid. Capture
  clears exactly the captured row intervals and presentation marker, while a
  transport construction failure still restores the existing full-snapshot
  recovery requirement.
- Cursor row/column changes and shape/visibility/blink changes mark
  presentation damage. Wrap-pending-only mutations do not, because they do not
  change a rendered cursor. BEL advances one signed 64-bit screen generation;
  repeated bells coalesce to the newest counter rather than queueing pulses.
- Primary/alternate activation advances the destination to the current active
  bell generation, and resize/reflow copies it. The render model rejects any
  bell regression, stages all row topology first, then publishes rows and the
  presentation fields in one accepted damage generation.
- The existing one-in-flight outbox treats presentation as pending damage and
  sends metadata-only packets through the same transferable ownership and
  exact-byte ACK contract. No second queue or special acknowledgement path is
  introduced.

## Verification plan

- Focused deterministic clock/state tests for blink boundaries, disabled and
  hidden cursors, bell restart/expiry, occlusion, hidden updates, resume, and
  generation exhaustion.
- `dart format`, `dart analyze`, product `make test`, focused Release AOT,
  `make runtime-source-check`, and relevant Developer JIT/Release AOT bundle
  audits/integrations.
- Review staged/unstaged diffs and product, adjacent package, and official SDK
  worktrees before each completion commit.

## Animation and occlusion design

- `TerminalPresentationClock` accepts an explicit nondecreasing signed
  microsecond observation at every model, animation, and window-state boundary.
  Cursor on/off and bell duration are positive and capped at one minute;
  deadlines saturate at signed 64-bit maximum rather than wrapping.
- The clock owns at most one cursor deadline and one bell deadline. A late
  cursor observation toggles once and schedules from that observation rather
  than replaying missed intervals. A newer BEL generation restarts one pulse,
  and expiry creates one presentation revision. Model revisions remain the
  ordering source for cursor/BEL metadata; presentation revisions order only
  clock and pause/resume changes.
- `TerminalNewestFrameScheduler` snapshots the retained model, presentation
  revision, and an identity-based full-redraw marker for each build. A model,
  presentation, or visibility change during a build discards that work before
  native submission. Backpressure, stale outcomes, exceptions, and a change
  observed during native submission retain one newest marker without retaining
  packed frames.
- Visibility and occlusion jointly determine whether presentation is active.
  While inactive, submission returns `paused` before allocating a frame
  generation or invoking the builder. Pause drops deadlines and active bell
  state. Resume begins a deterministic cursor-visible epoch, does not replay a
  bell received while hidden, and installs one full-redraw marker for the
  newest initialized model.
- The test-gated native Metal view retains its scheduler and feeds immutable
  AppKit visibility/occlusion timestamps into this policy. A transition back
  to active immediately attempts the retained resume frame. Creating a
  display-link driver and multi-window fairness remain outside this child;
  the clock exposes one next deadline for the later presentation driver.

## Investigation log

- 2026-09-06: committed the first child as `0857ef9` (`Carry cursor and bell
  through damage`), reread `ROADMAP.md`, and confirmed the bounded animation
  clock plus visibility/occlusion scheduling child is now the first unchecked
  item. The parent remains incomplete and failure recovery remains out of
  scope until this child is committed.
- 2026-09-06: after product commit `4a1b93d`, reread the Phase 4 roadmap and
  confirmed this is the first unchecked item. Product, adjacent `dart_appkit`,
  and the bundled official SDK worktrees were clean.
- 2026-09-06: existing damage version 1 carries only cell/row data. Cursor-only
  motion or presentation changes can advance `TerminalScreen.generation`
  without producing a packet, and BEL is currently counted as an unsupported
  control. A renderer therefore cannot independently reproduce cursor state or
  start a visual bell from the accepted damage stream.
- 2026-09-06: AppKit already supplies versioned visibility and occlusion events
  and caches both states on `Window`; no adjacent API is needed. The remaining
  work separates into a damage-format/terminal-semantics failure domain and a
  render-clock/AppKit scheduling failure domain, so both ordered children were
  registered in `ROADMAP.md` before implementation.
- 2026-09-06: the first focused-test attempt reached compilation only and found
  that Dart library privacy prevents `TerminalScreenSet` from calling a private
  `TerminalScreen` synchronization method in a sibling library. The operation
  was made an explicitly documented forward-only public method; exposing a
  setter or allowing bell-generation regression was rejected because either
  would weaken renderer ordering.
- 2026-09-06: malformed-header coverage showed that this native Dart runtime
  represents an unsigned 64-bit wire value with its high bit set as a negative
  `int`. The bell field therefore rejects both negative decoded values and
  values above signed 64-bit maximum, matching the existing non-wrapping
  generation domain.
- 2026-09-06: the first full suite passed formatting and static analysis, then
  stopped at the pinned property/fuzz digest because BEL is now accepted
  instead of counted as unsupported. The fixture budget and input bytes were
  unchanged; the diagnostic was expanded to expose the newly expected digest
  before updating that reviewed semantic oracle.
- 2026-09-06: the unchanged 837-execution/66,675-byte property workload now
  deterministically produces state hash `1504754176` (previously
  `1724998591`). This is the expected parser-observation change from BEL moving
  out of `unsupportedControlCount`; no corpus, seed, or execution budget was
  changed.
- 2026-09-06: the first Release AOT 100,000-cell damage run completed at
  665 microseconds capture p95 and 1,621 microseconds transfer/decode/ACK p95,
  both below the 4,000-microsecond gates, but correctly failed its exact packet
  size invariant. Version 2 grows the canonical header by 24 bytes, so the
  reviewed full-packet expectation is `1,704,904` bytes rather than
  `1,704,880`; no cell payload or performance threshold changed.
- 2026-09-06: the first animation-scheduler static pass found two local API
  issues before tests: the cursor-shape owner was not imported into the
  scheduler library, and `Duration` has no relational operator. The scheduler
  now imports the terminal cursor type explicitly and validates bounded
  durations through integer microseconds.
- 2026-09-06: the first AppKit smoke static pass found that the product
  application imports screen and renderer implementation libraries directly,
  so its new parser-driven BEL probe could not rely on the package barrel. The
  parser sink import was added explicitly; no dependency or native API change
  was needed.
- 2026-09-06: duration validation initially used `RangeError.value`, whose
  value parameter is constrained to `num`; `Duration` is not numeric. It now
  reports the bounded configuration error through `ArgumentError.value`.
- 2026-09-06: final contract review removed the implicit zero timestamp from
  damage application. All callers now supply their observation explicitly, so
  an already advanced clock cannot accidentally receive a regressing default.
  The same review moved revision exhaustion checks before time publication and
  added signed-maximum deadline saturation coverage.
- 2026-09-06: an in-sandbox static-analysis attempt could format sources but
  could not update Dart's home-directory telemetry session timestamp. The
  unchanged analysis and focused test were rerun with the required filesystem
  permission and passed; this was an execution-environment restriction rather
  than a product failure.
- 2026-09-06: the first staging attempt could not create `.git/index.lock`
  under the managed workspace sandbox. No index or source change was made by
  that failed attempt; staging was retried with repository-write permission.

## Verification results

### Cursor/BEL damage child

- Focused JIT tests `test/terminal_damage_test.dart`,
  `test/terminal_damage_transfer_test.dart`, and
  `test/terminal_screen_set_test.dart` pass. They cover canonical full and
  metadata-only packets, parser BEL dispatch, cursor fields, repeated-bell
  coalescing, malformed header fields, atomic bell-regression rejection,
  primary/alternate inheritance, reflow preservation, pending outbox state,
  transferable materialization, and exact ACK release.
- The final `make test` passes with 96 formatted files, no analysis issues,
  fresh generated VT table output, and `dart_terminal tests passed`.
- The focused damage suite compiles and runs as Release AOT from
  `/private/tmp/dart-terminal-damage-presentation-aot`.
- `make product-damage-benchmark` passes in Release AOT with the canonical
  1,704,904-byte version-2 packet: capture plus TTD is 564 microseconds p95,
  transfer/decode/ACK is 1,715 microseconds p95, end-to-end is
  2,243 microseconds p95, and both required boundaries remain below
  4,000 microseconds.
- `make runtime-source-check` passes with `tracked=177 native_sources=0`.
  `git diff --check` passes, and the adjacent `dart_appkit` and bundled
  official Dart SDK worktrees are clean.

The cursor/BEL damage child is complete. The parent remains in progress until
the ordered animation/occlusion child is implemented and committed.

### Animation/occlusion child

- Focused JIT `test/frame_scheduler_test.dart` passes. It covers cursor
  on/off boundaries, missed-interval coalescing, disabled cursor blink, parser
  BEL start/restart/expiry, one-deadline limits, signed-maximum saturation,
  visibility plus occlusion state, hidden damage, no hidden build/frame
  allocation, deterministic resume, no hidden bell replay, build-time
  occlusion supersession, and presentation-generation exhaustion.
- The final `make test` passes with 96 formatted files, no analysis issues,
  fresh generated VT table output, and `dart_terminal tests passed`.
- The focused scheduler suite compiles and runs as Release AOT from
  `/private/tmp/dart-terminal-presentation-scheduler-aot`.
- `make runtime-source-check` passes with `tracked=178 native_sources=0`.
- Developer JIT and Release AOT bundle audits both pass with one helper, one
  native-asset set, and one declared capability. Their real AppKit/Metal
  integrations pass in 2,164 ms and 1,794 ms respectively, including an
  occluded hidden BEL, zero hidden build/frame allocation, and one native
  resume full redraw at frame generation 12.
- `git diff --check` passes. The adjacent `dart_appkit` and bundled official
  Dart SDK worktrees are clean.

Both ordered children meet their completion criteria. Device/shader/drawable
failure recovery remains the next roadmap task and was not implemented here.
