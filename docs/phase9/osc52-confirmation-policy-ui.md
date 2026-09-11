# OSC 52 confirmation and policy UI

## Status

- Phase: 9
- Task: OSC 52 confirmation/policy UI
- Started: 2026-09-12
- State: in progress
- Current subtask: exact application confirmation and pasteboard projection

## Purpose

Replace the Phase 6 parser-level default-deny placeholder with an explicit,
bounded, user-controlled OSC 52 clipboard policy. Reads, writes, and clears must
have separately reviewable authority; untrusted terminal output must never gain
silent access to the macOS pasteboard, and confirmation UI must be tied to the
exact pane, session generation, request, and pasteboard state it represents.

## Background

Phase 6 accepts only bounded OSC 52 envelopes, validates a selection of at most
12 bytes and a parser payload of at most 4,096 bytes, returns an empty response
for queries, and counts writes/clears without any pasteboard callback. Standard
user-initiated Copy/Paste already has AppKit ownership and a separate dangerous
paste reconfirmation gate. CAP-06 and SEC-02 reserve opt-in OSC 52 authority and
confirmation UI for this Phase 9 task; `Ms` remains intentionally absent from
the bundled terminfo database.

## Scope

- Reconfirm the pinned xterm/Ghostty behavior and choose an explicit read,
  write, and clear policy with safe defaults and hard payload limits.
- Move accepted OSC 52 requests from parser classification into immutable,
  bounded, session-owned pending state without adding pasteboard authority to
  terminal core.
- Add application-owned confirmation/policy UI whose approval is exact,
  revocable, stale-safe, and isolated across panes, sessions, resets, focus
  changes, pasteboard changes, and teardown.
- Connect approved operations to bounded plain-text AppKit pasteboard reads or
  writes and encode replies through the existing PTY reply/backpressure path.
- Add focused unit/fake integration tests, real PTY/AppKit Developer JIT and
  Release AOT acceptance, compatibility/public documentation, source/resource/
  bundle audits, and the exact repository gate.

## Out of scope

- Standard user-initiated Copy/Paste behavior except shared primitive reuse.
- Rich pasteboard formats, remote clipboard synchronization, command execution,
  background URL/media access, OSC 52 capability advertisement through terminfo,
  and the following protocol-wide fuzz/security/memory roadmap task.
- Any Phase 10 UI or accessibility work not strictly required for a safe native
  confirmation surface.

## Dependencies

- The committed Phase 6 OSC 52 grammar, empty-query reply, compatibility source
  pins, and byte-level regression corpus.
- `TerminalSession` reply queue/backpressure and pane/session/reset ownership.
- AppKit pasteboard, menu/presenter, window focus, and teardown boundaries used
  by standard clipboard, settings, palette, and close confirmation flows.
- The current Developer JIT/Release AOT runtime integration harness and bundle
  audits.

## Risks and invariants

- Clipboard reads can exfiltrate unrelated user data; writes/clears can destroy
  it. Default behavior must remain deny, and an approval must not become durable
  authority unless a documented setting explicitly says so.
- Terminal output, selection bytes, decoded data, or native handles must not be
  retained without hard limits. Base64 must be validated and decoded only after
  policy admission, with bounded failure behavior.
- A confirmation shown for one request must not approve a later request, pane,
  session generation, terminal reset, focus owner, or unrelated pasteboard
  mutation. A read approval reads once at approval time; a write approval is
  stale if the pasteboard change count changed while it was pending.
- Native AppKit calls stay on the application owner; terminal core and PTY
  parsing remain deterministic and have no native callback.
- Query replies and approved writes must use existing bounded native PTY and
  pasteboard paths, with observable denial, approval, stale, and cleanup states.

## Completion conditions

1. The accepted policy and UI behavior are source-pinned, documented, bounded,
   default-deny, and independently testable without native authority.
2. Parser/session/application ownership, confirmation identity, reset/close,
   focus, pasteboard-change, overflow, malformed input, and backpressure cases
   pass focused tests.
3. Real PTY/AppKit behavior passes in both shipped runtime modes without reading
   or overwriting a user's real clipboard during unattended acceptance.
4. Compatibility, README/FEATURE_MATRIX, source/resource/bundle audits, focused
   format/analyze/tests, the exact `CI=true DART_SUPPRESS_ANALYTICS=true make
   test`, final diff review, roadmap completion, and a standalone commit pass.

## Validation approach

- Inventory the existing parser, reply, session, configuration, AppKit
  pasteboard, confirmation presenter, and runtime acceptance contracts before
  changing code.
- Prefer pure deterministic models and fake pasteboards for policy and stale
  state; use a test-only native acceptance adapter that cannot touch the user's
  real clipboard.
- Run each focused layer before both runtime modes, then audits and the exact
  repository gate. Record every finding, rejected option, failed attempt,
  verification result, and remaining risk here as it occurs.

## Ordered subtasks

The parent task crosses the parser, typed configuration, application/native UI,
and shipped-runtime acceptance boundaries, so it is split before implementation.
The children are intentionally sequential: later children consume the contracts
and tests committed by the earlier child.

1. **Bounded protocol/configuration core**
   - Define an immutable, bounded OSC 52 request contract and optional parser
     admission callback while retaining the no-callback deny behavior byte for
     byte.
   - Add independently configurable `deny|ask|allow` read and write policies as
     new-session settings, both defaulting to `deny`; clear follows write policy.
   - Complete when default-deny, admitted requests, invalid selections/base64,
     chunking, bounds, generated configuration reference, format, analyze, and
     focused tests pass without any native clipboard authority.
2. **Exact application confirmation and pasteboard projection**
   - Add one bounded application-owned coordinator, one native confirmation
     surface, exact allow/deny actions, focused-session ownership, reset/close/
     focus cleanup, timeout/busy behavior, and bounded plain-text pasteboard
     projection through fakes and product integration.
   - Depends on child 1. Complete when deny/ask/allow read, write, and clear;
     exact approval identity; stale pasteboard writes; reply backpressure; and
     teardown cases pass deterministic tests with the settings/menu/palette
     surface verified.
3. **Shipped-runtime acceptance and closure**
   - Exercise the real PTY and native AppKit ownership in Developer JIT and
     Release AOT using a test adapter that cannot inspect or overwrite the
     user's clipboard, then update compatibility/public documentation and run
     source/resource/bundle audits and the exact repository gate.
   - Depends on children 1 and 2. Complete when both runtime observations,
     focused and full validation, final diff review, parent completion, and its
     standalone commit pass.

## Findings and decision log

- 2026-09-12: After commit `aecc2eb` (`Verify desktop signals in shipped
  runtimes`), the worktree is clean and the ROADMAP reread selects OSC 52
  confirmation/policy UI as the first unchecked Phase 9 item. The only later
  Phase 9 item is protocol-specific fuzz/security/memory testing and must not be
  implemented early.
- 2026-09-12: Initial inventory confirms Phase 6 currently implements a
  parser-owned denial classifier only: valid queries emit empty OSC 52 replies;
  valid base64-looking writes and clears increment denial counters; malformed or
  oversized inputs are rejected before policy; no terminal-core callback can
  read or mutate an AppKit pasteboard.
- 2026-09-12: The official Ghostty configuration reference documents separate
  `clipboard-read` and `clipboard-write` policies with `ask|allow|deny`; its
  current defaults are read `ask` and write `allow`. This product will not copy
  the permissive write default: preserving the established default-deny
  contract avoids a silent behavior change. `git ls-remote` fixed the reviewed
  Ghostty main revision at
  `44f2a44df7e8c4a0c6df3f7d872ef3d7ead88e51` before inspecting its config and
  macOS confirmation ownership.
- 2026-09-12: The first fixed-revision raw-source download was blocked by the
  sandbox DNS boundary (`Could not resolve host: raw.githubusercontent.com`)
  before any file was created. Retry requires the approved network boundary;
  only byte counts, hashes, and relevant behavior will be retained in this memo.
- 2026-09-12: The approved retry downloaded three fixed-revision Ghostty files
  to `/private/tmp` for inspection only. `config.zig` is 427,828 bytes with
  SHA-256 `68dc87467f7f0cc66cccdbef0b5b24eca3380b178b46a6f0497b7f26c9efc1a2`;
  `ClipboardConfirmationView.swift` is 4,546 bytes with SHA-256
  `39e2ce4efcb1ee3b663da4b66316b3179a92071cf33441fcec65739ae9014672`;
  and `App.swift` is 98,505 bytes with SHA-256
  `410dd9ff5f53cf17fff230c23f9ec38554a97aad49240ddf3611423423da2922`.
  The reviewed sources are respectively
  `https://raw.githubusercontent.com/ghostty-org/ghostty/44f2a44df7e8c4a0c6df3f7d872ef3d7ead88e51/src/config/Config.zig`,
  `.../macos/Sources/Ghostty/Features/ClipboardConfirmationView.swift`, and
  `.../macos/Sources/Ghostty/App.swift` at the same immutable revision.
- 2026-09-12: Fixed Ghostty config source confirms separate read/write access
  enums and the current `ask`/`allow` defaults. Its native confirmation shows
  request content with Allow and Deny actions. Its read path copies the approved
  representation before asynchronous completion rather than rereading an
  unrelated later clipboard value; its write path retains the exact requested
  text. These are useful ownership precedents, not defaults to copy.
- 2026-09-12: Adopted policy: expose `clipboard-read` and `clipboard-write` as
  new-session `deny|ask|allow` settings, both defaulting to `deny`; an OSC 52
  clear uses the write policy. Only requests naming the macOS clipboard (`c`)
  can receive native authority; the other syntactically valid xterm selection
  names remain unavailable. `Ms` remains absent because authority is runtime
  configuration rather than an unconditional terminfo capability.
- 2026-09-12: Admission preserves the Phase 6 parser bound (4,096 string bytes)
  and immutable ASCII envelope. Native text accepts only strict UTF-8. Reads are
  performed only after `allow` policy or the exact user approval and replies
  are capped to the same 4,096-byte protocol envelope. Ask state is globally
  bounded to one focused, active session request; later requests are denied
  while it is occupied. Query denial/cancel/timeout returns the established
  empty reply; writes and clears have no reply. Pending state is invalidated by
  session reset, close, or focus loss; a pending write also records pasteboard
  change count and becomes stale if it changed before approval.
- 2026-09-12: The first child implementation adds only a protocol-data request
  model, a fail-closed parser callback, per-operation accepted counters, and the
  two typed new-session settings. The callback receives no pasteboard handle or
  other native capability; absent, false, and throwing handlers all retain the
  Phase 6 denial and empty-query behavior.
- 2026-09-12: The first focused `dart analyze` attempt did not reach analysis:
  the sandbox rejected an mtime update to
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`. Formatting had
  already completed (11 files, one changed). Subsequent Dart commands use
  `DART_SUPPRESS_ANALYTICS=true`; this was an environment-boundary failure, not
  a source failure.
- 2026-09-12: With suppression enabled, focused analysis reported `No issues
  found`, although the Dart launcher still emitted the same sandbox-only
  telemetry mtime exception after the result. The first focused test attempt
  then stopped before test execution because the renderer build hook could not
  write Clang's module cache under `/Users/remi/.cache/clang`. This is another
  sandbox boundary; the identical focused command must be retried through the
  approved build/test boundary.
- 2026-09-12: The first approved focused run reached the tests and exposed one
  expected stale fixture: effective-config headers still asserted 36 options.
  Schema-derived counts were updated to 38 (and entry counts to 38/39/41 for
  their exact repeated-option fixtures), complete/invalid profile coverage now
  exercises `ask`, `allow`, and recovery to `deny`, and the test was rerun.
- 2026-09-12: `make configuration-reference` regenerated
  `docs/reference/configuration-and-command-line.md` from the 38-option schema.
  Full `dart analyze` then reported no issues, and the OSC 52 parser policy,
  product/config loader, effective config, Settings document/inspector, native
  hierarchy, and configuration-reference focused executables all passed.
- 2026-09-12: The first exact repository gate passed parser-table, parser-trace,
  38-option configuration-reference, and keybind/action freshness, then stopped
  because the checked Phase 7 AppKit source inventory was stale after the new
  core file and schema lines. This generated evidence must be refreshed before
  rerunning the identical gate; no behavioral test failed.
- 2026-09-12: `make phase7-appkit-acceptance` refreshed the deterministic source
  hashes affected by schema-count assertions. The second exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed every generated-source,
  compatibility, differential, application-matrix, terminfo, shell-integration,
  format (265 files, zero changes), analyze (no issues), and Dart test gate.
  Final `git diff --check` passed and a repository scan found no remaining stale
  36-option assertions outside unrelated protocol offsets/key codes and captured
  corpora. The first child therefore meets its completion conditions.
- 2026-09-12: Post-commit reread after `11592e7` (`Define bounded OSC 52 policy
  contracts`) confirmed the parent remains open and selects the exact
  application confirmation/pasteboard child. The worktree was clean before this
  child began; the later shipped-runtime child and protocol fuzz item remain
  out of scope until this child is committed.
- 2026-09-12: Application projection inventory found that `TerminalSession`
  already has one ordered ordinary-reply FIFO shared with Kitty graphics and
  parser reports, native transient surfaces use owned `Window`/`TextView`
  lifecycles, the standard action catalog drives both native menus and the
  command palette, and the interactive hierarchy has a single reconciliation
  point for logical pane focus. These are the existing ownership seams used by
  this child.
- 2026-09-12: The application coordinator is bounded to 64 registered sessions
  and one global pending request with a 30-second deadline. It accepts only the
  general clipboard selector (`c`), strict UTF-8 text of at most 3,060 bytes,
  and a focused session while the application is active. This text cap makes
  the worst-case successful response exactly 4,100 wire bytes, including the
  longest admitted 12-byte selector and ST terminator, while its OSC payload
  remains within the parser's 4,096-byte bound.
- 2026-09-12: `allow` executes immediately; `deny` stays unavailable; and `ask`
  captures an exact immutable identity. Reads touch the pasteboard only on the
  matching approval. Writes and clears capture pasteboard `changeCount` and
  become stale if the user or another application changes it before approval.
  Focus change, application deactivation, RIS generation change, session close,
  coordinator disposal, explicit denial, and timeout all revoke the request;
  revoked reads receive the established empty OSC 52 reply.
- 2026-09-12: The native confirmation owns only a transient AppKit window and
  read-only text view. Return approves and Escape/window close denies the exact
  displayed request; matching Edit-menu and command-palette actions expose the
  same coordinator decision. Exact write text is JSON-quoted, and invisible or
  bidirectional-control scalars are additionally rendered as `\\uXXXX` escapes
  so confirmation content cannot visually spoof the surrounding authority
  labels.
- 2026-09-12: Initial focused projection, session-reply, and native presenter
  executables passed. The action-registry executable then exposed stale search
  expectations: `clipboard` now intentionally returns four catalog actions,
  and fuzzy matching can return lower-ranked candidates after the intended
  split action. The assertions were corrected to verify stable ranking and the
  exact four-action Edit order; this was a fixture update, not an authority
  failure.
- 2026-09-12: A first unprivileged `make keybind-action-reference` attempt
  resolved dependencies but stopped when Dart tried to update the protected
  telemetry-session mtime. The approved retry generated the 21-action
  reference successfully. `make phase7-appkit-acceptance` then refreshed the
  13-source AppKit inventory after the new coordinator, presenter, and native
  lifecycle test were added.
- 2026-09-12: Focused executables for OSC 52 projection, ordered session replies,
  native confirmation ownership, and the action registry all pass. The native
  fake proves exact write approval, spoof-safe preview text, Escape read denial
  without pasteboard access, empty reply, responder restoration, and release of
  every transient AppKit owner. Session tests prove the maximum 4,100-byte read
  reply uses the existing ordered/backpressured PTY path and that RIS/teardown
  revoke pending disclosure.
- 2026-09-12: The exact repository gate
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passes: all generated-source,
  configuration (38 options), action (21 actions), AppKit inventory,
  compatibility/differential/application, terminfo, shell-integration, format
  (268 files, zero changes), analyze (no issues), and Dart test checks completed
  successfully. Final `git diff --check` passed; review found no temporary
  logging, secrets, untracked build output, or unrelated edits. The exact
  application confirmation/pasteboard child meets its completion conditions.
