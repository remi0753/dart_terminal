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
