# Phase 7 — fullscreen, screen migration, restoration, and reopen

- Status: in progress
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
