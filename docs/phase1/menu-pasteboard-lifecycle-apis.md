# Menu, pasteboard, and lifecycle APIs

- Status: in progress; lifecycle subtask complete
- Started: 2026-09-04
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, ADR-001, ADR-002, `dart_appkit`
  bridge/API/event codec and Runner application delegate

## Purpose

Add the reusable AppKit primitives needed for a native application menu,
explicit user-initiated close/quit coordination, activation/reopen state, and
plain-text access to the general pasteboard. Preserve the asynchronous
native-to-Dart boundary and make confirmation-capable lifecycle requests safe
without changing existing clients' default close or termination behavior.

## Background

The current substrate can create one window and generic/text views, post
window/input/state events, and terminate the application programmatically. It
cannot distinguish a user close request from a programmatic close, defer a
quit decision for Dart-owned cleanup, publish application activation/reopen,
build an `NSMenu`, route menu actions, or use `NSPasteboard` through the stable
C ABI.

The later PTY, interaction, and multi-window phases require these primitives,
but their product policies are not ready yet. This Phase 1 item therefore owns
only reusable AppKit adapters, explicit ownership, strict payloads, and a
minimal single-window product integration. Terminal selection semantics,
paste confirmation, keybinding arbitration, and multi-window restoration stay
in their scheduled phases.

## Scope

- Introduce event protocol v4 while preserving exact v1/v2/v3 envelopes and
  suppressing all v4-only event types for older negotiated sinks.
- Add application active-change, reopen-request, terminate-request,
  window-close-request, and menu-item-invoked event records. Application events
  use the documented zero source/generation sentinel; window and menu events
  retain positive generation-checked handles.
- Keep ordinary user close and terminate behavior immediately allowed by
  default. Add explicit deferral toggles and operation-ID-checked replies so a
  Dart consumer can opt into asynchronous confirmation without synchronous
  Dart re-entry or an unresponsive default.
- Preserve a programmatic termination bypass for orderly Dart teardown, and a
  programmatic window close that does not recursively create a user request.
- Add plain-text general-pasteboard read snapshots, writes, clears, and change
  counts. Copy UTF-8 at the ABI boundary and never expose Objective-C objects
  or retain Dart-owned buffers.
- Add generation/domain-checked `Menu` and `MenuItem` handles, separators,
  titles, key equivalents/modifiers, enabled state, submenu attachment,
  top-level main-menu attachment, and asynchronous action events.
- Route application/menu/window events through typed Dart streams and update
  application state before observers. Keep native callbacks limited to
  immutable port posts.
- Install a minimal native menu in Dart Terminal, route Close/Quit through the
  close-request path, make Paste consume general-pasteboard text only on the
  user action, and validate the substrate in both M1 product modes.

## Out of scope

- Persistent PTY, bracketed paste, newline normalization, multiline/control
  confirmation, size throttling, OSC 52, selection ownership, or copy of a
  terminal selection. Those remain in Phases 2, 5, and 6/9.
- A complete action registry, configurable keybindings, command palette,
  menu validation from terminal modes, Services, context menus, localization,
  or every standard macOS menu item. Those remain in Phases 7–10.
- Multiple windows, native tabs, splits, fullscreen, restoration, document
  opening, proxy icons, or active-process close policy.
- Pasteboard formats other than public plain text, promised/lazy data,
  drag-and-drop pasteboards, file URLs, images, or polling/change events.
- Synchronous native-to-Dart callbacks, nested run loops, blocking AppKit while
  Dart computes, or exposing selectors/Objective-C pointers through the ABI.
- The following terminal-specific custom-view, unified logging, crash metadata,
  broad leak, and shutdown fault-injection roadmap items.
- x86_64, Rosetta, Universal, and Intel-native follow-up acceptance.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD
  `c12a2dc9425959faef91e4cef365390694b3e0f5`, clean `dart_appkit` HEAD
  `be09f1a8e8f9d867cdf8d255fd40586fc9df5cc2`, and clean official Dart
  SDK/Engine revision `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- This is the first unchecked roadmap item. No later Phase 1 or Phase 2 item
  has been started.
- `DartAppKitAppDelegate` already owns application launch/termination and is
  the correct adapter for `NSApplicationDelegate` activation, reopen, and
  termination callbacks. `DaWindowOwner` already owns `NSWindowDelegate`.
- `applicationShouldTerminate:` may return `NSTerminateLater`, after which
  AppKit requires exactly one `replyToApplicationShouldTerminate:` decision.
  `windowShouldClose:` is synchronous, so an opted-in consumer must return
  false, post an immutable request, then close only after a matching async
  reply.
- Existing `AppKitApplication.terminate()` cancels its Dart event subscription
  while native termination is queued. Its native path must bypass user-request
  deferral or shutdown could wait for a reply that Dart can no longer receive.
- Current protocol v3 requires positive window handles before decoding.
  Application lifecycle needs an explicit zero-source sentinel in v4; menu
  actions instead use their menu-item handle as the positive source.
- Adding menu action types after publishing v4 would make an earlier strict v4
  decoder reject them. The v4 type set and codec therefore include the menu
  action record in the first subtask even though menu object creation follows
  later.
- `NSPasteboard` exposes an atomic text lookup plus `changeCount`; native tests
  must use an isolated test-only named pasteboard rather than overwrite the
  user's general clipboard.
- Existing legacy bridge fixtures omit additive symbols. Every new Dart FFI
  lookup must remain optional and report stable unsupported-version status
  only when the new operation is used.

## Design decision

Version 4 keeps the six-field v2/v3 prefix. Application-scoped records encode
source handle and generation as zero; all other records require a positive
handle and matching encoded generation. Deferred close/terminate requests
carry a positive, monotonically allocated operation ID. State and menu action
notifications use operation ID zero.

Deferral is explicit and off by default. If a v4 event cannot be posted, native
code falls back to allowing the user operation so an unavailable/older Dart
endpoint cannot trap a window or application. Only one request per target may
be pending. A reply with the wrong, stale, zero, or already-consumed operation
ID fails without changing AppKit state. Programmatic close/termination clears
or bypasses pending user coordination and retains the existing orderly
shutdown contract.

Menus and items remain independently owned registry objects. Menu attachment
borrows handles; AppKit retain relationships do not transfer the registry
lease. Dart wrappers retain attached item/submenu/main-menu wrappers to keep
their public lifetime explicit. Releasing an item clears its action target and
handle before dropping the registry reference, preventing a retained native
menu from posting a stale action.

General-pasteboard reads return a same-call snapshot containing nullable text
and the corresponding change count. Native storage is borrowed only long
enough for the FFI facade to copy it. Writes clear and replace the public text
item in one main-thread call. Product code reads only from a user-triggered
Paste action; no background polling or test mutation of the user's clipboard
is allowed.

## Ordered subtasks

### 1. Versioned application/window lifecycle

- Define all v4 event identifiers and source/operation invariants, including
  the reserved menu action record, across the C header, native model, shared
  encoder, Dart decoder, and compatibility tests.
- Implement application active/reopen callbacks, opt-in terminate deferral and
  matching replies, plus opt-in window close deferral/request/reply and an
  explicit user-style close request operation.
- Completion: v1/v2/v3 layouts remain exact, older sinks suppress v4-only
  records, wrong/stale replies fail closed, default close/terminate remains
  permissive, full `dart_appkit` tests pass, and the reusable change is
  committed before pasteboard work starts.

### 2. Plain-text general pasteboard

- Add UTF-8 snapshot/read, replace/write, clear, and change-count C/Dart APIs
  with strict outputs and optional legacy symbol resolution.
- Test native conversion against an isolated named pasteboard and Dart behavior
  through the fake backend; do not read or overwrite the user's clipboard in
  automated reusable tests.
- Completion: empty versus absent text, Unicode, embedded NUL, change counts,
  invalid outputs, errors, thread guards, and legacy fallback are covered; the
  full reusable suite passes and the subtask is committed.

### 3. Menu ownership and actions

- Add Menu/MenuItem registry kinds, creation, separators, hierarchy,
  key-equivalent modifiers, enabled state, main-menu attachment, programmatic
  action dispatch, typed Dart wrappers/streams, and release cleanup.
- Cover wrong-kind/stale/cross-application use, strong wrapper relationships,
  v4 action routing, legacy unsupported behavior, and main-menu detachment.
- Completion: native/Dart/FFI/header/example/docs checks and full reusable suite
  pass; the menu implementation is committed before product integration.

### 4. M1 product integration and acceptance

- Install minimal Application/File/Edit menus. Route Close and Quit through
  the opted-in window lifecycle request/reply path and read pasteboard text
  only from the Paste menu action.
- Extend the integration-only observer so common smoke proves real menu action,
  deferred close request/reply, activation state, pasteboard availability,
  protocol v4 metadata, and normal cleanup without changing ordinary logs.
- Completion: source checks, arm64 Developer JIT and Release AOT builds/audits,
  normal/lifecycle/traffic integration, clean-SDK freshness, repository/SDK
  hygiene, all four subitems and the parent checked, and the final product
  change committed.

Subtasks are strictly ordered. Pasteboard and menu work depend on the clean
v4 compatibility boundary. Product integration depends on clean committed
reusable revisions for all three API families.

## Acceptance criteria

1. Current clients negotiate v4; v1/v2/v3 clients retain exact envelopes and
   receive no new event type.
2. Application active/reopen events use only the documented zero source; menu
   and window records remain generation checked and route only to live wrappers.
3. User terminate/close remains immediately allowed unless deferral is
   explicitly enabled. A failed post also allows the operation.
4. Deferred requests produce one positive operation ID, accept exactly one
   matching reply, reject stale/mismatched replies, and never synchronously
   enter Dart.
5. Programmatic application termination cannot be caught by user-request
   deferral after the Dart event subscription is closed.
6. Pasteboard text distinguishes absent from empty, round-trips arbitrary valid
   UTF-8 including embedded NUL, and pairs reads/writes with a change count.
7. Automated tests do not modify the user's general pasteboard and product
   code reads it only in response to the Paste action.
8. Menus/items have generation/domain ownership, borrowed attachment, safe
   release cleanup, stable key modifier bits, separators, submenus, enabled
   state, and action delivery by menu-item handle.
9. Retained native menu objects cannot post an event after their public handle
   is released; wrong-kind/stale/cross-application operations fail.
10. Dart updates application state and request state before synchronous stream
    observers, and routes menu actions before consumer policy executes.
11. Dart Terminal performs orderly worker/session/native teardown after its
    Close or Quit menu path and never leaves a deferred lifecycle operation.
12. Both M1 product modes advertise protocol v4, pass the same real GUI smoke,
    and retain all existing lifecycle/backpressure/build-provenance guarantees.
13. Formatting, analysis, C11/C++20 headers, native/Dart/FFI/legacy tests,
    bundle audits, diff review, and repository/SDK hygiene pass.

## Validation plan

- Run focused bridge, shared-encoder, Dart API, FFI, header, formatting, and
  analysis checks after each reusable subtask, followed by full `make test`.
- Use deterministic poster/fake-stream fixtures for every v4 payload, source
  domain, request/reply transition, suppression path, and malformed record.
- Use an isolated test-only `NSPasteboard` inside native tests and fake bindings for
  Dart tests. Reserve general-pasteboard access for the real product adapter.
- Run the real reusable hello smoke after lifecycle and menu milestones.
- Run Dart Terminal `runtime-source-check`, both arm64 builds and bundle audits,
  common normal/lifecycle/traffic integration, both clean-SDK freshness gates,
  and inspect protocol provenance.
- Confirm Dart Terminal, `dart_appkit`, and the official SDK are clean after
  task-scoped commits.

## Risks and open checks

- AppKit may call termination again while a previous decision is pending.
  Native state must return `NSTerminateLater` without posting a duplicate.
- A consumer can dispose a window or menu item while a request/action event is
  queued. Generation-safe routing and native handle clearing must make the
  late event harmless.
- Rejecting a close reply must clear the pending operation so a later user
  close can produce a fresh ID.
- Native menu retain graphs can outlive registry handles. Cleanup must disable
  action dispatch before dropping the registered reference.
- AppKit key-equivalent masks contain platform-only flags. Only the existing
  stable modifier bit subset crosses the public ABI; unknown bits are rejected.
- General-pasteboard contents can change between user actions. The snapshot's
  change count is observational and not a lock or compare-and-swap token.
- Clipboard privacy prompts and policy evolve by macOS release. This task does
  not poll and reads only on an explicit user action, but later interaction and
  privacy work must revalidate the shipped behavior.

## Investigation log

### 2026-09-04 — repository and AppKit review

- Re-read the repository rules, README, complete roadmap, complete feature
  matrix, Phase 1 boundaries, ADR-001/ADR-002 context, the preceding generic
  view/state task record, both repository inventories, reusable architecture,
  C ABI, verification matrix, bridge/registry/event encoder, Dart bindings,
  Runner delegate, product integration harness, and all three clean worktrees.
- Confirmed from the local macOS SDK headers the `NSTerminateLater` reply
  obligation, application active/resign/reopen delegate callbacks,
  `windowShouldClose:`, menu/submenu/item APIs, and public string pasteboard
  operations/change count on the supported deployment range.
- Rejected always-deferred lifecycle requests because existing consumers that
  do not register a handler would become unclosable. Selected explicit opt-in
  deferral with permissive fallback on a failed post.
- Rejected synchronous Dart callbacks from `applicationShouldTerminate:` and
  `windowShouldClose:` because they violate the existing run-loop boundary and
  can deadlock AppKit. Selected operation-ID request/reply over the native port.
- Rejected using the user's general pasteboard in automated native tests.
  Internal helpers accept an isolated test-only named pasteboard while public C calls
  select the general pasteboard.
- Split the item before implementation because versioned lifecycle semantics,
  pasteboard data transfer, menu ownership/actions, and two-mode product
  acceptance are independently reviewable and strictly dependent.

### 2026-09-04 — lifecycle event protocol and APIs complete

- `dart_appkit` now negotiates event protocol v4 without changing C ABI version
  1 or any v1/v2/v3 layout. Application active/reopen/terminate, window close
  request, and the reserved menu-action event have exact native encoder and
  strict Dart decoder coverage.
- Application events use source handle/generation zero. Window/menu sources
  remain generation checked. Notifications require operation ID zero and
  close/terminate requests require a positive operation ID.
- AppDelegate publishes an active snapshot on v4 registration plus later
  active/resign/reopen changes. Application termination and window close are
  permissive by default, fail open when posting is unavailable, and become
  reply-driven only after explicit Dart opt-in. Duplicate requests coalesce;
  wrong, stale, or reused replies fail without changing state.
- Programmatic close and termination bypass the user-decision path. This keeps
  existing clients unchanged and prevents shutdown from depending on an event
  subscription that `AppKitApplication.terminate()` is about to cancel.
- Dart exposes cached `isActive`, typed application/window request streams,
  deferral properties, user-style `requestClose`, and event-typed reply calls.
  All new FFI lookups are optional; the legacy fixture loads normally and
  reports status 8 only when an unavailable lifecycle operation is attempted.
- Adding a new sealed `WindowEvent` subtype made the consuming exhaustive
  switch require a case. Dart Terminal now has a deliberately policy-free
  `WindowCloseRequestedEvent` branch so its source remains analyzable; actual
  Close/Quit policy remains ordered subtask 4 and was not implemented early.
- The first native verification compile failed because the existing diagnostic
  equality macro cannot stream a scoped enum. Boolean decision assertions fixed
  the test only. A later malformed-event test surfaced unhandled errors on
  derived typed streams; explicit test error handlers preserved the primary
  stream's seven-error assertion.
- Two initial real GUI smokes hung after the timer invoked AppKit
  `performClose:`; an arrival log showed no request event. The explicit bridge
  operation now invokes the same window-owner delegate decision directly and
  closes only when it allows. A final GUI run delivered operation 1, accepted
  the Dart reply, emitted the closed event, released handles, and exited 0.
- One no-write Dart formatting audit found zero changed files but its analytics
  timestamp update was sandbox-denied; the permission-enabled repeat passed. A
  PATH `clang-format` resolved to depot_tools and rejected the non-Chromium
  checkout; the pinned ARM64 formatter then passed. Neither failed attempt
  changed source.
- Final verification passed: `dart_appkit make test`; warning-as-error C11,
  C++20, Objective-C++ and Runner checks; exact encoder/FFI/legacy tests; Dart
  analysis and tests; example Kernel compilation; real GUI smoke; ten repeated
  native bridge runs; native and Dart format checks; 24-symbol export audit;
  `git diff --check`; `make engine-check`; and Dart Terminal
  `make runtime-source-check`.
- The official SDK remained clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. Reusable changes were committed
  in `dart_appkit` as
  `e48be7f3d8c70d32a5a2392be33d09b5dd39f0cb` (`Add deferred application and
  window lifecycle APIs`). Pasteboard work may now start from that clean
  prerequisite.
- The first Dart Terminal staging attempt could not create `.git/index.lock`
  under the managed filesystem sandbox. Repeating the same explicit three-file
  stage with repository metadata permission succeeded; no broader path or
  unrelated change was included.

### 2026-09-04 — plain-text pasteboard API complete

- Added four main-thread-only C operations for a same-call general-pasteboard
  text snapshot, UTF-8 replacement, clear, and change-count observation. The
  snapshot's explicit presence flag and byte length distinguish missing text,
  present-empty text, Unicode, and embedded NUL without relying on C-string
  termination. Outputs are zeroed before validation and borrowed native bytes
  are copied immediately by FFI.
- The application owns one stable Dart `Pasteboard` facade. It exposes
  immutable `PasteboardTextSnapshot` values, rejects use after application
  termination, and keeps all four new symbol lookups optional so the legacy
  native fixture continues to load and reports unsupported only on use.
- Native tests use a private named pasteboard, never the general pasteboard.
  The first ten-run audit found that globally retained one-off unique
  pasteboards exhaust the service and eventually return `nil`; the fixture now
  reuses one test name and calls `releaseGlobally`. The rebuilt suite then
  passed ten consecutive executions.
- Final verification passed the complete `dart_appkit make test` suite, C/C++
  header checks, warning-as-error native formatting, Dart analysis and API
  tests, real-dylib FFI and legacy-fixture smokes, 28-symbol export audit,
  `git diff --check`, and Dart Terminal `make runtime-source-check`. The SDK
  worktree remained clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- The reusable implementation and its evidence were committed in `dart_appkit`
  as `f46d89853348702c3fc00e1c0c91d20ca51000bc` (`Add plain-text pasteboard
  snapshots`). Menu ownership/action work may now begin from that clean
  prerequisite.
