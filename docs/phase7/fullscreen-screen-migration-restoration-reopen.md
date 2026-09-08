# Phase 7 — fullscreen, screen migration, restoration, and reopen

- Status: complete
- Started: 2026-09-07
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 7 `fullscreen、screen migration、restoration、reopen`
- Related: UI-03, `docs/phase1/generic-view-window-state-events.md`,
  `docs/phase7/application-state-model.md`, and
  `docs/phase7/native-tabs-split-layout-focus.md`

## Purpose

Make window placement and fullscreen state application-owned and restorable,
move a retained window safely when its display changes or disappears, restore
the bounded window/tab/split/session launch hierarchy after a restart, and
handle a Dock reopen request when no terminal window is visible. Preserve the
existing root-isolate AppKit boundary and deterministic pane/native cleanup.

## Background and confirmed starting state

- The preceding title/tab metadata/cwd/proxy-icon item is complete at terminal
  commit `2385306 Project terminal session metadata to native tabs`. Both this
  repository and the adjacent `dart_appkit` worktree were clean when this item
  started.
- `TerminalApplicationState` owns bounded window/tab/split/pane identity,
  topology, selected/focused/zoom state, tab rename/color, and pane teardown.
  It has no versioned durable snapshot or restore admission path.
- The normal product creates one fixed `920 x 580` AppKit window. Its cached
  width/height follow resize events, its renderer already rebuilds on backing
  scale, and screen events are observed but do not apply placement policy.
- The hierarchy adapter creates one native `NSWindow` per logical tab with a
  fixed frame. It projects tabs, splits, focus, title/proxy/color, but not a
  logical window's frame or fullscreen state.
- `dart_appkit` protocol v5 already reports application reopen requests and a
  window's focus, visibility, occlusion, backing scale, and screen. A `Window`
  retains only its immutable creation frame; there is no public frame mutation,
  current-frame event, fullscreen request, or fullscreen-state event.
- The current application reopen handler can call `show()` only while its sole
  native window is still alive. A completed close ends the run loop path and
  tears down the session, so it cannot reconstruct a closed hierarchy.
- Phase 7 exit criteria require repeated creation/restoration of multiple
  windows, native tabs, and four-pane topologies. Restoration therefore covers
  presentation/topology/session launch metadata, not only a single rectangle.

## Scope

- A bounded, versioned, content-free restoration model and JSON codec for
  ordered windows, tabs, split topology, focus/zoom, safe tab metadata, pane
  launch cwd, windowed frame, display identity, and fullscreen intent.
- A deterministic placement policy that validates finite geometry, preserves
  relative placement across displays, clamps the window into the destination
  visible frame, and fails closed on malformed or absent screen information.
- Reusable `dart_appkit` frame/fullscreen control and cached state, plus
  versioned immutable native events for current frame and fullscreen changes.
- Terminal capture/restore admission using fresh logical/native/session IDs,
  native hierarchy frame/fullscreen projection, display migration, and a Dock
  reopen path that restores or creates a usable window when none is visible.
- M1/arm64 Developer JIT and Release AOT product acceptance covering
  fullscreen enter/exit, frame and scale/screen state, migration/clamping,
  multi-tab/four-pane round-trip restoration, reopen, and clean teardown.

## Out of scope

- Terminal screen contents, scrollback, running process checkpointing, PTY
  reconnection, or restoration of a live process. A restored pane starts a new
  shell at its validated local cwd; PTY-09 remains a separate P2 project.
- Active-process discovery, per-pane close decisions, and application quit
  confirmation. The immediately following Phase 7 item owns those policies.
- Fair multi-pane scheduling/resource budgets and the final broad AppKit UI
  suite, which remain later Phase 7 items.
- Automatic display selection preferences, Quick Terminal, animation, HDR or
  refresh-rate modeling, and custom titlebar/fullscreen implementations.
- x86_64, Rosetta, Universal, or Intel-native acceptance before the M1 contract
  is complete.

## Ordered subtasks

### 1. Bounded restoration snapshot and placement policy

- Add immutable versioned restoration DTOs/codec and strict count, numeric,
  UTF-8, topology, cwd, and serialized-size limits.
- Capture and reconstruct application topology through a dedicated restorer;
  assign fresh runtime IDs and session owners while preserving order and
  presentation semantics.
- Add pure placement/migration policy for saved/current screen rectangles,
  fullscreen intent, and safe visible-frame clamping.
- Completion: direct tests cover valid multi-window/multi-tab/four-pane
  round-trip, malformed/untrusted JSON, resource limits, fresh identity/session
  ownership, migration between negative/positive-origin screens, and missing
  display fallback; focused and complete terminal gates pass and the subtask is
  committed before AppKit work starts.

### 2. Reusable AppKit frame/fullscreen primitives and state events

- Add current-frame caching/mutation and idempotent fullscreen requests to the
  public Dart API and C ABI without exposing Objective-C objects.
- Add immutable frame/fullscreen state events under a new event protocol while
  preserving exact v1-v5 layouts and suppressing new events for old endpoints.
- Cover initial snapshot, move/resize/fullscreen callbacks, deduplication,
  transition/failure behavior, validation, wrong-kind/thread/generation calls,
  fake bindings, real FFI, headers, and legacy optional-symbol fallback.
- Completion: complete `dart_appkit` gates pass and the adjacent package change
  is committed independently before terminal adoption.

### 3. Terminal hierarchy restoration, projection, and reopen lifecycle

- Adopt the reusable frame/fullscreen API in the hierarchy adapter and normal
  product without making native handles logical identity.
- Persist only validated content-free restoration data, restore fresh sessions
  at trusted local cwd values, and reconcile screen changes through the bounded
  placement policy while the renderer continues to use the current scale.
- Keep the application available when appropriate after its last window closes;
  on reopen, restore the last valid hierarchy or create a default one, show it,
  and restore selected tab/focused pane/first responder exactly once.
- Completion: focused state/adapter/lifecycle tests pass, malformed persistence
  cannot prevent default startup, and every replaced/closed native/session
  owner is released in deterministic order.

### 4. M1 dual-runtime acceptance and parent completion

- Add a gated product scenario and smoke assertions for fullscreen, migration,
  restoration, and reopen using an isolated temporary persistence path.
- Exercise at least two native tabs and four real PTYs before and after restore,
  prove fresh identities and inherited cwd, then close with zero native, Metal,
  text-input, worker, or PTY leaks in Developer JIT and Release AOT.
- Run formatting, analysis, full tests, source/bundle audits, relevant ordinary
  smoke/display/hierarchy regressions, update README/FEATURE_MATRIX and this
  record, then close the parent roadmap item only when all checks pass.

## Acceptance criteria

1. Restoration input is versioned, content-free, bounded before allocation,
   deterministic to encode, and strictly rejects malformed types, unsafe cwd or
   tab text, duplicate/invalid topology, non-finite geometry, unsupported
   versions, trailing semantic data, and excessive serialized input.
2. A valid snapshot preserves ordered windows/tabs, selected/focused/zoom
   state, split axes/fractions, rename/color, pane launch cwd, windowed frame,
   display identity, and fullscreen intent while assigning fresh live owners.
3. Window placement always remains finite and usable. Display migration maps
   relative position to the new visible frame and clamps size/position; absent
   or malformed display state never moves a window to invented coordinates.
4. AppKit exposes current frame and fullscreen state asynchronously through the
   same root-isolate event boundary. Native callbacks never synchronously enter
   Dart or wait for renderer/session work.
5. Protocol v6 retains every v1-v5 record exactly and new event families are
   rejected or suppressed where the negotiated version cannot represent them.
6. Fullscreen entry retains the last safe windowed frame, exit restores/clamps
   it for the current display, and tabbed native windows remain one logical
   window with deterministic selection/focus.
7. A Dock reopen with no visible window yields exactly one usable restored or
   default window. Repeated reopen notifications do not duplicate sessions,
   windows, event subscriptions, or native handles.
8. Persistence failure is recoverable: corrupt/missing/unwritable state is
   diagnosed without terminal content or paths in ordinary logs, and startup
   falls back to a default window.
9. Both M1 runtimes prove the same observable contract and clean teardown; all
   prior title/input/render/lifecycle acceptance remains green.

## Validation plan

- Use direct pure-Dart tests for codec limits, topology round trips, restore
  ownership, and placement math before touching the reusable native layer.
- Run focused AppKit Dart/native/encoder/FFI/legacy tests, then its complete
  `make test`, for the protocol/API subtask.
- Add fake-binding hierarchy tests for retained frame/fullscreen updates and
  terminal lifecycle tests for restore/reopen idempotence and fallback.
- Run the isolated product fixture in Developer JIT and Release AOT, then the
  existing display and hierarchy suites affected by event/projection changes.
- Finish with terminal `make test`, source audit, both bundle audits, exact diff
  review, and clean worktree checks in both repositories.

## Risks and initial decisions

- Native fullscreen is asynchronous. The model records desired and observed
  state separately and treats AppKit completion events as authoritative; it
  will not infer completion from a request call.
- `NSScreen` identifiers are process-stable observations, not permanent display
  identities. The persisted ID is only a preference. Geometry is always
  validated against the currently observed destination visible frame.
- Native tabs are separate `NSWindow` instances. Frame/fullscreen projection is
  applied consistently to the retained group, but logical restoration records
  one placement per logical window.
- Restoration cannot resume a process safely with the current architecture.
  The durable contract deliberately starts fresh sessions at local cwd rather
  than serializing terminal content, environment secrets, or process metadata.
- The application currently exits after its sole window closes. Reopen support
  must not pre-implement the later quit-confirmation policy; test and product
  lifecycle changes will distinguish window closure from explicit application
  termination without guessing whether a foreground process is safe to kill.

## Findings and verification log

- 2026-09-07: reread `README.md`, `ROADMAP.md`, `FEATURE_MATRIX.md`, repository
  inventory, current worktree, Phase 1 window-state/lifecycle records, Phase 5
  close behavior, Phase 7 state/native-hierarchy records, terminal bootstrap,
  action registry, runtime smoke harness, and the current `dart_appkit`
  window/application/event APIs before implementation.
- 2026-09-07: confirmed the next roadmap item is this one and no later Phase 7
  implementation has started. The repository was clean after `2385306`; the
  adjacent AppKit repository was also clean after its metadata follow-up.
- 2026-09-07: existing protocol v5 provides sufficient screen/scale/reopen
  observations but not frame/fullscreen truth. Adding policy only in terminal
  would miss native green-button transitions and current coordinates, so the
  reusable event/API subtask is required rather than inferring state from resize.
- 2026-09-07: the item spans durable untrusted-data decoding, pure geometry,
  reusable native ABI/event work, terminal ownership integration, and two real
  runtime modes. It is split into four ordered commits above; later roadmap
  items are not being implemented in parallel.
- 2026-09-07: subtask 1 added a version 1 deterministic JSON contract with a
  512 KiB UTF-8 ceiling, 32-window/128-tab/64-total-pane admission budgets,
  existing per-window/per-tab structural limits, and a depth bound. The decoder
  rejects unknown keys, wrong scalar types, unsupported versions, invalid
  focus/zoom indices, unsafe local cwd values, invalid colors/fractions, and
  non-finite or unbounded geometry. Total tab and pane budgets are charged while
  decoding, before a complete oversized owner graph can be constructed.
- 2026-09-07: restoration capture serializes only ordered presentation and
  fresh-session launch state: windowed frame/current screen/fullscreen intent,
  tab selection/rename/color, split axes/fractions, pane focus/zoom, and safe
  absolute local cwd. It deliberately excludes terminal text, history,
  environment, process identity, and native/logical runtime handles.
- 2026-09-07: the restorer reconstructs arbitrary binary split trees through
  the public application mutations, assigns fresh owner-scoped window/tab/
  split/pane/session identities, restores selection/focus/zoom and metadata,
  and returns new-ID placement/cwd maps for later native/session integration.
  Any configuration or admission failure shuts down the partially reconstructed
  application before rethrowing the original error and stack.
- 2026-09-07: placement policy preserves relative position while migrating
  between positive- or negative-origin display visible frames, bounds window
  size and position to the destination, honors an explicit fallback display,
  and leaves saved coordinates unchanged when no valid screen inventory exists.
  Persisted display IDs remain preferences rather than permanent authority.
- 2026-09-07: focused format/analyze and the direct restoration test passed.
  Coverage includes two windows, three tabs, six fresh sessions, one nested
  four-pane tab, exact encode/decode/restore/recapture equality, title/color/
  focus/zoom/cwd/placement retention, missing and tiny displays, corrupt input,
  global resource bounds, and injected restore failure cleanup.
- 2026-09-07: the first complete `make test` passed every functional test but
  reported one analyzer info for the new public export's ordering. Moving the
  export after the renderer section fixed the issue; the repeated complete gate
  formatted 202 files with zero changes, reported no analyzer issues, and ended
  with `dart_terminal tests passed`.
- 2026-09-07: the first source audit reported `tracked=380` because its
  `git ls-files` inventory correctly excluded the still-untracked new source
  and test. After staging exactly the six task files, the repeated
  `make runtime-source-check` included them and passed with `tracked=383`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`. Subtask 1
  is complete; the next ordered work is the independently committed reusable
  AppKit frame/fullscreen API and protocol event extension.
- 2026-09-07: adjacent `dart_appkit` commit `47b1f5e Expose window frame and
  fullscreen state` completed subtask 2. It keeps C ABI version 1, adds optional
  `da_window_set_frame`/`da_window_set_fullscreen` symbols, and negotiates event
  protocol v6 for strict immutable outer-frame and observed native-fullscreen
  events. Version 1 through 5 layouts remain unchanged and v6-only records are
  suppressed for older sinks.
- 2026-09-07: AppKit owns only native mutation/observation. Frame and
  fullscreen snapshots are deduplicated after show and later delegate changes;
  fullscreen completion/failure events remain authoritative and no delegate
  enters Dart synchronously. Product screen selection, clamping, persistence,
  hierarchy identity, session launch, and reopen policy remain in this task.
- 2026-09-07: native, runner, Dart API, fake-binding, FFI, header, and legacy
  tests cover initial/current state, move/resize and fullscreen callbacks,
  transition failure, validation, wrong kind/thread/stale generation,
  cache-before-observer ordering, malformed records, and v5 filtering. The
  final `DART_SUPPRESS_ANALYTICS=true CI=true make test` passed the complete
  AppKit repository gate, including JIT/AOT manifest assembly and legacy image
  fallback. An initial adjacent-repository build write was sandbox-blocked and
  a later test fixture passed `nil` to SDK-nonnull delegate arguments; the
  scoped rerun and corrected real-notification fixture passed without product
  changes.
- 2026-09-07: subtask 2 is complete. After rereading `ROADMAP.md` and this
  record, the next ordered work is terminal hierarchy restoration, native
  frame/fullscreen projection and screen reconciliation, plus idempotent Dock
  reopen/default fallback lifecycle.
- 2026-09-07: the first terminal `make runtime-source-check` for the
  documentation checkpoint was blocked before the audit because the renderer
  build hook could not write Metal module-cache files below
  `~/.cache/clang/ModuleCache` under the workspace sandbox. This is an
  environment permission failure rather than a source/audit failure; the same
  bounded command reran with scoped permission and passed with `tracked=383`,
  `product_native_sources=0`, and `reviewed_test_native_sources=1`.
- 2026-09-07: terminal integration review found that AppKit's enter-fullscreen
  callback published the current frame before the observed fullscreen state,
  while resize/move callbacks could also publish animation frames before
  completion. A consumer cannot distinguish those rectangles from the last
  safe windowed frame, especially for a user-initiated green-button transition
  with no prior Dart request. The reusable layer must mark will-enter/will-exit,
  suppress frame observations during transition, and publish completion state
  before the resulting frame. This is a correctness follow-up within the active
  restoration item, not later roadmap work; it will be committed separately in
  `dart_appkit` before terminal adoption continues.
- 2026-09-07: AppKit follow-up `6d957a8 Preserve windowed frames across
  fullscreen` marks will-enter/will-exit transitions, suppresses only
  frame-state events during the transition, and emits observed fullscreen state
  before the completion frame. Legacy content-resize events remain live for
  renderer adaptation. Focused native and complete AppKit `make test` gates
  pass, including same/opposite pending targets and enter/exit/failure ordering.
- 2026-09-07: the terminal hierarchy adapter will keep one placement per
  logical window and project its safe windowed frame to every retained native
  tab while sending fullscreen intent only to the selected tab. It will consume
  already-routed typed events keyed by logical tab, never use a native handle as
  identity, ignore fullscreen rectangles, migrate against an observed
  destination screen, and restore the migrated frame when exit is observed.
- 2026-09-07: reopen/persistence is separated from the durable codec. A bounded
  file store reads at most the codec limit, uses same-directory replacement,
  and reports only content-free outcome kinds. A generation lifecycle will
  load-or-default, start restored panes in hierarchy order, present once,
  capture before native/session teardown, and coalesce concurrent reopen calls.
  Native projection is disposed before logical session shutdown; corrupt or
  unavailable persistence falls back to one default fresh session.
- 2026-09-07: normal product event handling now retains the last safe windowed
  frame outside fullscreen, migrates it through the bounded placement policy on
  a concrete screen event, restores it after fullscreen exit, and leaves the
  renderer's independent backing-scale rebuild path intact. The hierarchy
  adapter owns the corresponding placement per logical window, projects one
  frame to all native tabs, and routes typed frame/fullscreen/screen events by
  logical tab ID rather than retaining native handles as identity.
- 2026-09-07: the replaceable-generation lifecycle admits a bounded local file
  through the existing strict codec, starts fresh sessions with only validated
  local cwd launch values, subscribes each projected native tab once, and
  provides a direct `ApplicationReopenRequestedEvent` route. Concurrent close
  and reopen requests share their in-flight teardown/activation futures; IDs
  advance across generations so stale logical identities cannot alias reopened
  owners. An in-memory last-valid snapshot permits reopen even when the latest
  durable write is unavailable.
- 2026-09-07: the first focused analysis exposed one test-only use of
  `containsAll` on an `Iterable`; converting the diagnostic kinds to a set fixed
  it. Earlier compilation while introducing protocol-v6 events also found the
  intentionally exhaustive application and command-palette switches; both now
  explicitly handle or ignore the new frame/fullscreen event families. The
  focused analyzer, restoration/file-store test, and hierarchy/lifecycle test
  then passed. File-store coverage includes missing/read/replace, malformed
  UTF-8, input/output size limits, path admission, and pending-file cleanup;
  lifecycle coverage includes corrupt startup fallback, two-tab/four-pane
  restore, fresh IDs/sessions, unavailable writes, duplicate Dock reopens, and
  deterministic native-before-session teardown.
- 2026-09-07: final ownership review found that a newly reconciled restoration
  generation selected its tab and first responder once during reconciliation
  and then repeated both operations while showing the window. Presentation now
  suppresses that second restore for a newly built tree while retained-window
  Dock presentation still selects/focuses once. Fake native counters prove one
  select/focus/show on activation and only one additional set for two coalesced
  hidden-window reopen requests; an explicit disposal trace proves every pane's
  native adapters are released before any session shutdown begins.
- 2026-09-07: analysis after that correction reported no issues. Its first
  focused hierarchy run again encountered only the sandboxed Metal module-cache
  write; the exact scoped rerun passed.
- 2026-09-07: the first complete terminal `make test` attempt was blocked by
  the workspace sandbox when the renderer hook tried to populate Clang's Metal
  module cache below `~/.cache/clang/ModuleCache`; it did not reach source
  tests. The same exact gate reran with scoped cache permission, formatted 203
  files with no changes, reported no analyzer issues, passed every generated
  contract and regression check, and ended with `dart_terminal tests passed`.
- 2026-09-07: after the exact-once presentation correction, the complete
  scoped `make test` gate passed again with 203 files unchanged by formatting,
  no analyzer issues, all compatibility/differential/application/terminfo
  checks green, and `dart_terminal tests passed`. With all eight task files
  staged so the new source was in `git ls-files`, `make runtime-source-check`
  also passed with `tracked=384`, `product_native_sources=0`, and
  `reviewed_test_native_sources=1`.
- 2026-09-07: subtask 3 completion conditions are satisfied. The normal
  product consumes the new placement events, the reusable hierarchy/lifecycle
  path owns bounded persistence and Dock reopen reconstruction, malformed state
  cannot block startup, and focused plus complete gates prove fresh ownership
  and deterministic cleanup. The next ordered work after commit is the M1
  Developer JIT/Release AOT product scenario and parent completion decision.
- 2026-09-08: after commit `bdb57dd Restore terminal hierarchy across reopen`,
  `ROADMAP.md` and this record were reread and the worktree was clean. The next
  and only remaining child is subtask 4: an arm64 Developer JIT/Release AOT
  product fixture, smoke contract, documentation/feature updates, complete
  gates, audits, and parent completion decision.
- 2026-09-08: the existing gated hierarchy fixture already provides the needed
  production resource stack (real zsh PTYs, one native window per tab, split
  views, Metal surfaces, text-input clients, and a runtime worker), but it
  destructively collapses its one generation. The restoration acceptance will
  be a separate mutually exclusive gate so existing hierarchy evidence remains
  stable. It will use a smoke-owned temporary file, route an injected typed
  application reopen event through the real application event stream, enter
  and exit native fullscreen, inject a versioned screen migration observation,
  replace a two-tab/four-pane generation with fresh owners at inherited local
  cwd, and assert zero native/Metal/text-input/worker/PTY retention after the
  second generation shuts down. The smoke driver will validate and remove the
  isolated persistence directory without printing its path from the product.
- 2026-09-08: option/parser tests, the full direct Dart test runner, and the
  arm64 Developer JIT build passed. The first restoration launch created four
  real PTYs and entered native fullscreen, then failed an overly immediate
  assertion that the exit event itself had already restored the original
  frame. AppKit deliberately publishes fullscreen completion before its final
  post-transition frame event. The acceptance now waits for that event to
  settle and compares the authoritative placement with every native tab while
  retaining the pre-fullscreen windowed width/height. The failure cleanup still
  closed all four PTYs, released the native/Metal/text-input owners, and reaped
  the worker normally.
- 2026-09-08: the repeated Developer JIT launch showed the mismatch remained
  after the final event settled. The failing invariant isolated a real adapter
  gap: a post-fullscreen authoritative frame updated the one logical placement
  but was not reprojected to the other `NSWindow` members of its native tab
  group. Windowed frame observations now converge the frame across every tab;
  the fake-binding hierarchy test adds a direct post-exit frame case to prevent
  regression. This remains within subtask 4 because the first real product
  fullscreen transition exposed it before parent acceptance.
- 2026-09-08: the first focused hierarchy-test rerun after adding that case was
  stopped before source execution by the sandboxed Metal module-cache path.
  Its scoped rerun then exposed a fixture-only mismatch: raw native frame-event
  injection does not mutate the fake binding's authoritative frame map. The
  fixture now records the simulated native frame before injecting the event,
  matching the real binding contract, and the focused test passes.
- 2026-09-08: a subsequent Developer JIT launch proved the hierarchy correction
  with content-free diagnostics: fullscreen was observed off, placement and
  every tab converged, the selected native frame matched, and the pre-entry
  size was retained. It then failed the initial screen-migration wait because a
  zero-duration event race was used while a real native screen observation was
  still pending. The fixture now waits for the specific injected destination
  screen and polls both placement convergence and scale propagation.
- 2026-09-08: the next launch instead reproduced a nondeterministic loss of the
  original windowed size at fullscreen exit while all tabs still converged.
  Investigation isolated a reusable AppKit constructor defect rather than a
  terminal-policy exception: `da_window_create` passed the public `frame` to
  `initWithContentRect`, but Dart cached it and `da_window_set_frame` applied it
  as an outer frame. Depending on whether the show-time observation arrived
  before the fixture captured placement, the native pre-fullscreen outer
  height already included title-bar insets. The adjacent package will normalize
  construction to the requested outer frame and pin that behavior in its native
  suite before this acceptance continues; loosening the M1 invariant would hide
  the production bug.
- 2026-09-08: the adjacent AppKit correction sets the requested outer frame
  before installing the window owner, handle, or delegate, so normalization
  cannot emit a bridge event. Its native fixture asserts exact initial x, y,
  width, and height. Focused `make native-test` and complete `make test` both
  pass with warning-clean native builds, all Dart/package suites, JIT/AOT
  assembly, FFI loading, and legacy fallback green. The change is ready for its
  independent dependency commit before the terminal fixture reruns.
- 2026-09-08: AppKit dependency commit `3be1317 Honor outer frames during
  window creation` was followed by the required roadmap reread; M1 dual-runtime
  acceptance remains the current final child of the fullscreen/restoration
  parent. The first rebuilt Developer JIT run then reached four live PTYs but
  timed out before emitting the fullscreen diagnostic. Failure cleanup called
  explicit native-tab removal while AppKit still considered the selected
  window part of a fullscreen transition; AppKit rejected it with
  `windowToTakeFrom should be in FS`, and that secondary cleanup exception hid
  the original acceptance timeout and prevented timely process termination.
- 2026-09-08: explicit tab removal is unnecessary during owned-window teardown:
  releasing the window closes it and AppKit removes the closed member from its
  native tab group. Hierarchy reconciliation and final disposal now release
  removed windows directly after pane adapters and split views. The fake native
  binding mirrors close-time detachment, and final hierarchy coverage requires
  both zero handles and an empty tab group. This makes cleanup safe even if an
  acceptance invariant fires during a real fullscreen transition, without
  suppressing the original failure.
- 2026-09-08: the next rebuilt launch showed the native failure is deeper than
  explicit removal: releasing a grouped window while AppKit still considered a
  fullscreen transition pending reached `orderOut` in bridge release and raised
  the same uncaught `NSInternalInconsistencyException`. The runtime diagnostic
  consequently remained at `root-ready`. The fixture had requested fullscreen
  immediately after adding and selecting its second native tab, so the group
  could still be completing AppKit's asynchronous tab presentation. It now
  requires the selected tab to be visible on a concrete screen, permits the
  native group to settle for 500 ms, and emits content-free request/observation
  milestones around enter and exit. A future close/quit task must explicitly
  cover asynchronous shutdown during fullscreen; the current acceptance must
  first prove a completed transition rather than racing tab-group setup.
- 2026-09-08: after the teardown edit, `dart format` changed no files. The first
  focused analyzer invocation omitted `DART_SUPPRESS_ANALYTICS` and was blocked
  only while trying to update `~/.dart-tool/dart-flutter-telemetry-session.json`;
  the suppressed rerun reported no issues. The focused hierarchy test passed
  and confirmed window release empties the fake native tab group and all owned
  handles.
- 2026-09-08: with cleanup no longer masking the primary error, the next launch
  exited normally with four clean PTY shutdowns and zero lifecycle leak, and
  identified the missing precondition precisely: the selected second tab had
  no visibility/screen snapshot. The lifecycle intentionally constructs its
  adapter with `presentWindows: false` so initial activation presents exactly
  once, but this fixture added the second tab afterward and only reconciled its
  structure. It now explicitly presents that mutated generation with
  `restoreSelectionAndFocus: false`; this shows the already-selected tab and
  publishes its native state without repeating logical focus restoration.
- 2026-09-08: a second formatting attempt again put the analytics-suppression
  environment only on the analyzer half of a chained command, so formatting
  completed unchanged and then reported the same denied telemetry timestamp
  write. Running both formatter and analyzer with suppression succeeded; no
  source issue was reported.
- 2026-09-08: explicit presentation produced the expected visibility/screen
  state and reached `enter-requested`, proving the prior precondition fix. The
  second native tab nevertheless failed to complete fullscreen entry within
  eight seconds; failure cleanup then reproduced AppKit's fatal close-during-
  transition exception. The fixture will exercise real fullscreen and screen
  migration on the native tab-group anchor, then select the metadata-bearing
  second tab before persistence. This still combines one real two-tab/four-pane
  product generation with fullscreen, migration, durable restore, and complete
  resource audit, while avoiding an AppKit private-state race specific to
  immediately fullscreening a newly selected non-anchor tab. The ordered
  close/quit task must later cover shutdown while a transition is pending.
- 2026-09-08: selecting the tab-group anchor did not change the result: entry
  was requested, but no completion arrived in eight seconds; direct window
  release then cleaned every PTY, worker, and owned handle without the prior
  native exception. This demonstrates the instability belongs to an active
  native tab group rather than the non-anchor identity. The acceptance now
  completes fullscreen enter/exit and injected screen migration on the initial
  real one-window/one-pane generation, then constructs and persists the same
  required two-tab/four-pane topology. Restoration still recreates all four
  real PTYs, Metal surfaces, text clients, split views, and native tabs with
  fresh identities, so no hierarchy or resource condition is removed.
- 2026-09-08: fullscreen entry also timed out when requested before any native
  tab group existed, while the single PTY and runtime worker still shut down
  cleanly. The next diagnostic boundary is runner activation: AppKit fullscreen
  is asynchronous and requires a foreground application. The fixture now waits
  for the typed `ApplicationActiveChangedEvent` state as well as window
  visibility/screen state and records only the two booleans at the request
  milestone. This distinguishes an inactive-launch environment from a native
  fullscreen callback defect.
- 2026-09-08: the activation precondition failed before issuing fullscreen,
  while window visibility and concrete screen state were already available.
  The root cause is the smoke driver's direct execution of the binary below
  `.app/Contents/MacOS`, which this desktop session does not foreground even
  though the runner requests activation. The restoration suite now launches
  the bundle through LaunchServices with a fresh foreground instance, captures
  application stdout/stderr in an isolated temporary directory, forwards only
  the explicit gated environment, and obtains the real application PID from
  the bounded runtime diagnostic record. Other runtime suites keep direct
  execution; timeout cleanup targets the real app PID rather than only the
  waiting `open` process.
- 2026-09-08: LaunchServices did produce the real bundle PID and isolated
  stdout/stderr, but the typed current-active snapshot still remained false.
  Reviewing both generic hosts found activation was sequenced after Dart
  `main` invocation and startup-microtask draining, allowing asynchronous Dart
  product work to run before the delegate ever requested foreground status.
  The adjacent package will call modern `NSApplication.activate` at the start
  of both Developer JIT and Release AOT launch callbacks. Its event-port attach
  already publishes the then-current native active state, so no new ABI or
  event type is needed.
- 2026-09-08: both hosts compiled warning-clean after moving activation ahead
  of Dart startup, but the foreground acceptance still observed inactive state.
  At that early delegate point no key window exists. The reusable bridge will
  therefore also issue the same idempotent modern activation request from
  `da_window_show`, immediately after making the concrete owned window key and
  front. Existing delegate delivery remains the sole active-state event path.
- 2026-09-08: bridge and both host variants compiled warning-clean with the
  show-time activation request, but the Dart active cache still remained false.
  Because this can also mean the activation notification was missed or denied
  independently of fullscreen capability, the cache is retained as diagnostic
  evidence rather than a gate; the native enter/exit completion events remain
  the authoritative acceptance condition.
- 2026-09-08: a process-targeted Apple event returned success during a launch
  but did not grant foreground state, while a `System Events` frontmost query
  blocked on desktop automation permission and was interrupted. The reusable
  bridge now supports an explicit content-free UI-test environment gate that
  force-activates all windows through `NSRunningApplication` only at
  `da_window_show`. The restoration smoke sets this gate; ordinary products
  continue to use cooperative modern activation, and fullscreen itself still
  runs through the normal public window API and real AppKit callbacks.
- 2026-09-08: the proposed force-activation gate was rejected by the
  warning-as-error native build. The macOS 26.5 SDK states that
  `NSApplicationActivateIgnoringOtherApps` was deprecated in macOS 14 and has
  no effect, so retaining or suppressing that warning would not solve the
  acceptance problem. All uncommitted AppKit activation experiments and the
  terminal gate were removed; adjacent `dart_appkit` is clean at dependency
  commit `3be1317`. The successful outer-frame fix remains independently
  committed and verified.
- 2026-09-08: this is now a severe external blocker for subtask 4. In both a
  direct executable launch and a fresh LaunchServices bundle launch, the real
  window becomes visible on a concrete screen but the managed desktop does not
  grant active/frontmost ownership. `toggleFullScreen` is accepted by the
  bridge but no native enter completion arrives within eight seconds. A
  process-targeted activate Apple event reports success without changing the
  result, while `System Events` frontmost access blocks on an unavailable
  desktop-automation permission. Every failure path after the hierarchy
  teardown correction closes its real PTY, reaps the worker, and releases all
  owned resources.
- 2026-09-08: the LaunchServices smoke path now treats the bounded runtime
  diagnostic record's real application PID and exit code as authoritative,
  rather than confusing the waiting `open` process's zero status with the
  application's status 70. Its stdout/stderr and temporary directories remain
  isolated and removed. The detailed impact and resume procedure are in
  [`fullscreen-runtime-acceptance-blocker.md`](fullscreen-runtime-acceptance-blocker.md).
- 2026-09-08: stop-state verification formatted the five changed Dart sources
  with no further edits, analyzed the application, hierarchy, runner tests, and
  smoke driver with no issues, and passed the complete direct Dart runner with
  `dart_terminal tests passed`. `git diff --check` also passed. No terminal
  commit is permitted because the real Developer JIT scenario, Release AOT
  scenario, documentation/matrix completion, full repository/runtime gates,
  and roadmap completion conditions remain outstanding behind the recorded
  desktop blocker.
- 2026-09-08: the first formatting command for the acceptance changes
  mistakenly included this Markdown task memo in the Dart formatter input and
  failed with parser diagnostics for prose. No file corruption occurred; the
  Dart-only formatting rerun succeeded. The first complete direct Dart runner
  was likewise blocked only by the sandboxed Metal module cache; the identical
  scoped rerun passed with `dart_terminal tests passed`.
- 2026-09-08: after the user granted `System Events` desktop-automation
  permission, a frontmost query completed successfully and the next Developer
  JIT LaunchServices run reported `active=true`. Real AppKit fullscreen entry
  and exit completion events both arrived. This removed the prior external
  activation blocker and exposed the next acceptance failure: after exit the
  selected window and logical placement both reported non-fullscreen and all
  projected tab frames converged, but the resulting outer-frame size differed
  from the safe pre-fullscreen size (`size_preserved=false`). The run exited 70
  and still cleanly closed its PTY, reaped the lifecycle worker, and disposed
  its hierarchy. Investigation now targets event ordering and windowed-frame
  capture/projection before any later roadmap work.
- 2026-09-08: the exact exit diagnostic was safe `920x580` versus observed
  `1618x1020`. The adapter had already applied the observed non-fullscreen
  state when it consumed AppKit's contractually ordered completion frame, so
  it mistook that one transition result for an ordinary windowed move and
  replaced application-owned placement. The adapter now tracks only genuine
  requested or observed fullscreen state changes, consumes exactly their next
  frame as transition output, and on exit reprojects the retained safe frame.
  Equal initial fullscreen snapshots do not arm this suppression, and the
  tracking maps are pruned with logical windows and cleared on disposal. The
  fake-binding regression injects the real failing `1618x1020` completion
  frame, proves the safe placement and all native tabs stay at the migrated
  frame, then proves the following ordinary windowed frame remains
  authoritative. Formatting, focused analysis, and the focused native
  hierarchy test all pass.
- 2026-09-08: the corrected real arm64 Developer JIT scenario passed in
  4.152 seconds. It observed real fullscreen enter and exit, preserved the
  safe outer frame, applied the injected screen migration and scale, persisted
  and reopened a two-tab/four-pane generation with fresh live identities and
  local working directories, coalesced duplicate reopen requests, and ended
  with eight clean PTY sessions plus zero Metal, text-input, native-handle, and
  lifecycle-worker retention.
- 2026-09-08: the identical arm64 Release AOT scenario passed in 3.454 seconds
  with the same two-generation fullscreen, migration, restoration, reopen,
  fresh-owner, cwd, coalescing, and zero-retention contract. Both required M1
  runtime modes now provide real product-path evidence; documentation, the
  feature matrix, complete repository/runtime gates, and final audits remain
  before this child or its parent can be marked complete.
- 2026-09-08: README and the feature matrix now document protocol v6,
  application-owned content-free restoration, real fullscreen/display
  migration, Dock reopen coalescing, and the dual-runtime two-generation
  cleanup evidence. The first complete `make test` reached the generated
  Phase 6 compatibility coverage freshness check and correctly rejected its
  old report after `FEATURE_MATRIX.md` changed. The report must be regenerated
  through its declared Make target and included as a mechanical consequence of
  the evidence update before repeating the full gate.
- 2026-09-08: the declared coverage-generation target passed and updated only
  the README/feature-matrix source hashes in
  `compatibility/regression_coverage_report.json`. The repeated complete
  `make test` then passed: all generated compatibility/differential/application/
  terminfo checks were green, 203 Dart files required no formatting changes,
  analysis reported no issues, and the direct runner ended with
  `dart_terminal tests passed`.
- 2026-09-08: the first final `runtime-verify` repetition passed the complete
  test gate, source audit (`tracked=384`, `product_native_sources=0`,
  `reviewed_test_native_sources=1`), and both arm64 bundle audits. It then
  stopped at the Developer JIT ordinary smoke with
  `missing current native event wire observation`. This is a task-local v6
  event/integration regression until disproved; the remaining runtime suites
  and roadmap completion remain pending while the expected and captured
  ordinary event streams are compared.
- 2026-09-08: comparison found no missing product event. The ordinary smoke
  still required `negotiated=5 protocol=5` for its current window-close and
  state observations even though the reusable dependency now correctly
  negotiates v6. The smoke expectation is updated to v6 and now additionally
  requires the new positive-size outer-frame snapshot and initial
  `fullscreen=false` observation. AppKit's separate legacy endpoint tests
  remain responsible for exact v1-v5 compatibility.
- 2026-09-08: the focused Developer JIT smoke then passed window/state v6
  matching and stopped at the next stale current-protocol assertion for the
  application active snapshot. A complete source search found the remaining
  current v5 literals in application state, menu action, close request, and
  precision-scroll product/smoke evidence. All are updated to v6 together;
  none changes the underlying event semantics or legacy-version fixtures.
- 2026-09-08: formatting and focused analysis remained clean after the current
  protocol updates, and the Developer JIT ordinary smoke passed in 2.549
  seconds. The complete `runtime-verify` must now be repeated from the start so
  every later JIT/AOT suite is validated under the corrected v6 expectations.
- 2026-09-08: the second `runtime-verify` passed complete tests, source and
  bundle audits, both ordinary smokes, and both live display suites. Developer
  JIT native hierarchy then exited 70 when its existing IME acceptance invoked
  `TerminalTextInputClient.debugRunAcceptanceStage` and the custom view
  operation returned native status 7. All four PTYs and the worker still
  completed cleanly. The failure is outside the fullscreen path but remains a
  Phase 7 regression gate; focused reproduction and the status-7 native
  precondition are being checked before deciding whether it is transient or a
  task-local interaction.
- 2026-09-08: an immediate focused rerun reproduced status 7. The acceptance
  stage returns that internal status when its real `NSTextInputClient` view is
  no longer the native window's first responder (or another native-only
  precondition is lost). The fixture had changed split zoom/layout before the
  first pane loop, then selected the same logical pane; ordinary reconcile
  correctly skipped duplicate selection/focus calls based on logical state,
  while a genuinely frontmost AppKit tab could have changed its native
  responder during those layout operations. Immediately before each staged
  IME injection, the fixture now uses the adapter's existing explicit
  `present(restoreSelectionAndFocus: true)` boundary to re-establish native tab
  selection and first responder. Normal product reconcile and its exactly-once
  restoration contract are unchanged.
- 2026-09-08: reapplying explicit selection/focus in the same run-loop turn did
  not resolve status 7. Native tab selection can finish after that immediate
  call when the application is genuinely foreground. The fixture now gives
  AppKit a bounded 100 ms settling interval after logical reconcile and only
  then performs the explicit selection/focus restore immediately before the
  acceptance operation. If this remains insufficient, the next step is
  content-free native precondition diagnostics rather than further blind
  timing changes.
- 2026-09-08: the one-run native diagnostic proved the failed stage had a live
  client, queue, window, and geometry generation but `first_responder=0`.
  Review then found the deterministic cause in the adapter: `_presentWindow`
  set the terminal pane as first responder and subsequently called
  `Window.show()`, whose reusable native contract intentionally assigns the
  window content view as its initial responder. Presentation is reordered to
  show first, select the native tab second, and set the terminal pane responder
  last. The fake binding records and asserts this ordering. The speculative
  delay/extra presentation calls were removed, and the temporary renderer
  diagnostic was reverted with the adjacent repository clean.
- 2026-09-08: the first focused analyzer run for the ordering regression found
  that the test referenced an ordered-list helper local to the smoke driver.
  No product test ran and no source was damaged. Because initial hierarchy
  presentation has exactly three relevant calls, the assertion now compares
  the exact call count and each show/select/responder position directly.
- 2026-09-08: show/select/responder ordering alone did not fix the focused
  runtime because every later reconcile unconditionally assigned the same
  retained split root to `Window.contentView`. The native content-view setter
  correctly makes that root the initial responder, while logical focus had not
  changed and therefore did not trigger a second pane responder call. The
  hierarchy adapter now skips an identical retained content root; new or
  collapsed roots still attach normally. Fake bindings count content-view
  attachments so repeated reconciliation can pin this ownership/focus
  invariant.
- 2026-09-08: the content-root guard alone left the runtime failure because
  `_buildBranch` also reassigned the same two children to every retained
  `SplitView`. Native view-hierarchy reattachment may resign a descendant first
  responder. Child identity is already cached by the reusable split API, so the
  adapter now skips `setChildren` when both retained children are identical;
  fraction, minimum extent, zoom, and pane layout updates remain live. The fake
  binding separately counts child attachments to cover this recursive case.
- 2026-09-08: after both identity guards, formatting and focused analysis were
  clean, the direct hierarchy regression passed, and the real Developer JIT
  hierarchy/IME suite passed in 1.960 seconds with two tabs, four panes, exact
  input isolation, and clean teardown. This confirms the status-7 failure was
  retained native view reattachment, not timing or fullscreen behavior.
- 2026-09-08: the Release AOT hierarchy/IME suite also passed in 1.291 seconds
  with the same two-tab/four-pane isolation and cleanup contract. Both focused
  runtime modes are green; the complete aggregate gate still must pass from
  its first dependency through its final fault suite.
- 2026-09-08: the next full `runtime-verify` passed complete tests, source and
  bundle audits, both ordinary smokes, both display suites, both corrected
  hierarchy suites, and both restoration suites. It then stopped in the
  existing Developer JIT clipboard fixture after OSC 52 denial and exact CJK
  Copy passed: `MenuItem.performAction` rejected the next operation because
  its item remained disabled. Cleanup still reaped the worker and PTY and
  released product resources. Menu availability refresh versus clipboard
  fixture state is now the only active aggregate-gate investigation.
- 2026-09-08: the clipboard failure was deterministic asynchronous menu state,
  not pasteboard content. Native invocation starts the unawaited paste future;
  the menu controller refreshes while `pasteActionInProgress=true`, and the
  confirmation notice refresh also occurs before that flag is cleared. The
  `finally` block now clears the flag and immediately refreshes the action-menu
  projection, making the exact second confirmation invocation available while
  preserving busy-state exclusion during planning and transfer.
- 2026-09-08: formatting and focused analysis stayed clean, and the Developer
  JIT clipboard product suite passed in 3.943 seconds, including OSC 52 denial,
  exact CJK Copy, zero-write first confirmation, responsive bounded 10 MiB
  bracketed Paste, second-confirmation approval, and clean teardown.
- 2026-09-08: Release AOT clipboard passed the identical contract in 3.132
  seconds. Both focused modes are green; the aggregate gate must be repeated
  to exercise lifecycle, v6 scroll/traffic, resource stress, and shutdown
  faults that follow clipboard in target order.
- 2026-09-08: the final complete `make RUNTIME_ARCH=arm64 runtime-verify`
  repetition exited 0. It passed the complete Dart test/format/analyze gate,
  source audit (`tracked=384`, `product_native_sources=0`,
  `reviewed_test_native_sources=1`), both bundle audits, and every Developer
  JIT/Release AOT product suite: ordinary smoke, display, native hierarchy,
  restoration, clipboard, lifecycle, precision scroll/traffic, and the
  1,000-iteration resource stress. The final fault gates also passed in both
  modes, including expected PTY deadline status 75. Developer and Release
  resource runs stayed within the asserted baseline/peak bound (`33`/`35`).
- 2026-09-08: the aggregate result closes the final M1 acceptance child. The
  real restoration fixture proves fullscreen enter and exit, typed display
  migration, safe-frame clamping, scale observation, two-generation
  persistence, two reopen events with coalescing, fresh pane identities and
  cwd inheritance, and teardown of all eight PTYs with zero retained Metal,
  text-input, native-handle, or lifecycle-worker owners. README and UI-03
  evidence are current, the compatibility report was regenerated, and the
  parent roadmap item is complete with no untracked implementation remainder.
- 2026-09-08: the first exact-file staging attempt was denied when the managed
  sandbox could not create `.git/index.lock`. No index or worktree content was
  changed. Staging must be retried with the repository metadata permission
  granted; this is an environment permission boundary, not a product failure.
