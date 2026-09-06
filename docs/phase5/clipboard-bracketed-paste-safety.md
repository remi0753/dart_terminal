# Phase 5 — clipboard, bracketed paste, and paste safety

## Task identity

- Date started: 2026-09-06
- Scope: seventh Phase 5 production-input roadmap item
- Status: active
- Ordered subtasks:
  1. add a bounded plain-text pasteboard read boundary to `dart_appkit`;
  2. add DEC bracketed-paste mode plus a bounded safe paste encoder;
  3. add PTY-completion-driven bounded asynchronous paste transport;
  4. connect Copy/Paste, explicit confirmation, and a 10 MiB product
     acceptance in Developer JIT and Release AOT.

## Purpose and background

Complete daily clipboard use without allowing a large or hostile paste to
freeze the AppKit isolate, exceed the native PTY write queue, terminate its own
bracketed-paste frame, or silently execute multiple shell lines. The preceding
Phase 5 tasks already provide stable selection text, a general plain-text
pasteboard primitive, DEC mode dispatch patterns, a persistent PTY with a
bounded ordered write queue, native menu actions, and both-runtime product
acceptance infrastructure. The current product Paste action bypasses all of
those paste-specific policies and sends the entire clipboard through the
ordinary text insertion path.

## Scope

- Plain-text standard clipboard Copy and Paste through the native Edit menu.
- A maximum UTF-8 transfer bound at the generic `dart_appkit` pasteboard read
  boundary, large enough to accept the required 10 MiB fixture.
- DEC private mode 2004 set/reset/query state, reset semantics, and a single
  start/end frame around one logical paste.
- Streaming Unicode-to-UTF-8 encoding in bounded chunks, with CRLF/lone-CR/LF
  normalization and terminal-control byte replacement.
- Conservative classification requiring explicit user confirmation for
  multiline, unsafe-control, bracket-terminator, or large content.
- A content-free, expiring confirmation token tied to the pasteboard generation
  and scanned content identity; confirmation re-reads and revalidates the
  clipboard rather than retaining the full text.
- One tracked PTY chunk in flight at a time, completion-driven progress,
  cancellation at session shutdown, and observable queue/chunk metrics.
- Automated unit, integration, real AppKit/menu/pasteboard/PTY, 10 MiB
  responsiveness, and Developer JIT/Release AOT acceptance.

## Out of scope

- OSC 52 clipboard access, remote clipboard policy, rich pasteboard types,
  primary selection, drag/drop, Services, and copy-on-select.
- A configurable confirmation policy or native sheet styling; those belong to
  later configuration/application-polish work. The alpha uses a content-free
  terminal notice followed by an intentional repeat of Paste within a short
  bounded window.
- Kitty clipboard/paste-event protocol, shell integration, and multiple pane
  paste arbitration.
- Hyperlink copy/open and accessibility; they are the next ordered Phase 5
  tasks.

## Dependencies and current facts

- `README.md`, `ROADMAP.md`, and `FEATURE_MATRIX.md` were re-read after commit
  `510e776`. This is the first unchecked roadmap item and Phase 5 ends only
  after this task plus hyperlink and VoiceOver support are complete.
- `TerminalViewport.extractSelection` already returns soft-wrap-aware plain
  text from stable logical anchors, bounded to at most 4,194,304 scalars.
- `dart_appkit` already exposes standard plain-text read/write/clear and native
  Command-key menu dispatch. Its current read bridge copies an arbitrarily
  sized UTF-8 representation into Dart without a caller limit.
- `dart_pty_macos` defaults to a 1 MiB write capacity, rejects writes that
  would exceed it, preserves accepted order, and exposes tracked request IDs
  plus `writeCompleted`/`writeError` diagnostics with queued-byte counts.
- Ordinary terminal key input is limited to 256 encoded bytes. Paste must use
  a separate API rather than weakening this key-event invariant.
- The current Paste menu reads the general pasteboard and calls
  `TerminalPane.insertText`, causing a whole-string UTF-8 allocation and one
  write with no bracket, newline, safety, or retry semantics.
- xterm defines DEC private mode 2004 and the `ESC [ 200 ~` / `ESC [ 201 ~`
  delimiters. Its documentation also records the embedded-terminator risk.
- Ghostty `src/terminal/paste.zig` and `src/input/paste.zig`, inspected from
  upstream `main` on 2026-09-06, centralize mode-aware paste encoding, replace
  dangerous C0/DEL bytes with spaces regardless of bracket mode, and emit one
  bracket pair around the complete paste rather than one pair per transport
  chunk. This project adopts those safety properties while intentionally using
  a stricter multiline confirmation rule and canonical newline normalization.

Primary references:

- <https://invisible-island.net/xterm/terminfo-contents.html>
- <https://invisible-island.net/xterm/xterm-paste64.html>
- <https://github.com/ghostty-org/ghostty/blob/main/src/terminal/paste.zig>
- <https://github.com/ghostty-org/ghostty/blob/main/src/input/paste.zig>

## Design decisions

### Bounds

- `dart_appkit` will admit at most 64 MiB of UTF-8 clipboard text into Dart.
  This leaves headroom over the mandatory 10 MiB acceptance while making the
  process boundary explicit. Oversize is a typed, content-free result rather
  than a partial paste.
- Paste transport chunks are at most 16 KiB and never exceed the configured
  PTY write capacity. At most one tracked paste chunk is accepted but not yet
  completed, so the paste's native queue contribution is bounded by one chunk.
- Large-paste confirmation begins at 1 MiB encoded content. It does not reject
  the 10 MiB acceptance fixture.

### Encoding and safety

- CRLF, lone CR, and lone LF each represent one logical newline. In bracketed
  mode they encode as LF; outside bracketed mode they encode as CR, matching
  terminal paste submission semantics without producing doubled CR for a
  Windows newline.
- NUL, EOT, ENQ, BS, ESC, DEL, and the conventional terminal-driver control
  bytes for interrupt, quit, kill, suspend, flow control, word erase, literal
  next, reprint, and discard are replaced with ASCII space. Classification is
  performed before replacement, so the user must still confirm hidden control
  content.
- Any logical newline, replaceable control, embedded bracket terminator, or
  encoded payload at least 1 MiB requires confirmation, even when bracketed
  mode would keep a newline inside the application paste operation.
- Mode state and encoding options are frozen when the paste begins. Prefix and
  suffix are emitted once across all transport chunks.

### Confirmation and concurrency

- The first unsafe Paste invocation emits no PTY bytes and publishes a notice
  asking the user to invoke Paste again within ten seconds.
- The token retains only change count, bounded metadata, a deterministic
  content fingerprint, and expiry. The second invocation re-reads and rescans;
  any change or expiry becomes a new confirmation request.
- A second paste cannot start while one is active. Ordinary input is not
  queued behind a potentially long paste; it is rejected with one bounded
  status notice while the paste owns the PTY input stream. This prevents input
  from being interleaved inside one bracket frame without introducing an
  unbounded secondary queue.

## Completion conditions

- Plain selected text copies to the standard pasteboard and Paste uses the
  paste-specific path; an absent/truncated selection never silently writes
  partial clipboard data.
- DECSET/DECRST/DECRQM 2004 and RIS behave deterministically.
- Chunk encoding preserves valid Unicode, normalizes all newline forms,
  replaces dangerous bytes, prevents an embedded suffix from escaping, and
  emits exactly one frame per bracketed paste.
- Unsafe paste writes zero bytes before explicit confirmation.
- A 10 MiB multiline paste is confirmed, reaches a real PTY exactly once,
  keeps the AppKit timer/event loop responsive, and never exceeds the bounded
  PTY queue in either runtime mode.
- All modified package tests, project formatting/analysis/unit tests, source
  and bundle audits, and relevant product integrations pass.

## Verification plan

- `dart_appkit`: bridge/header tests, fake/FFI binding tests, Dart tests,
  format/analyze, Developer/Release native asset checks.
- Terminal core: DEC mode set/reset/query/RIS tests and adversarial encoder
  tests across every input split, Unicode/surrogate boundaries, unsafe bytes,
  embedded suffixes, and newline forms.
- Session/pane: fake PTY completion/backpressure/cancellation tests proving one
  in-flight chunk, stable ordering, and no unbounded retry/input queue.
- Product: real native Copy/Paste menu actions, changed clipboard rejection,
  first-invocation zero-write confirmation, bracketed exact bytes, and a
  10 MiB slow-reader fixture with timer responsiveness and native maximum queue
  assertions in Developer JIT and Release AOT.
- Final regression: full `CI=true make test`, source audit, both builds/bundle
  audits, smoke, terminal display, resource, and new clipboard acceptance.

## Investigation and implementation log

### 2026-09-06 — task start and decomposition

- Both repositories were clean before decomposition (`dart_terminal` ahead of
  upstream by 16 commits; `dart_appkit` ahead by 5).
- Confirmed the existing generic pasteboard surface and product Paste shortcut,
  stable selection extraction, DEC mode dispatch/reset locations, the 256-byte
  key-event cap, and the native PTY write/completion contract described above.
- A direct raw GitHub fetch first failed under the restricted network
  environment. It was repeated with the approved network capability and the
  two upstream Ghostty source files were reviewed successfully. No source was
  copied; the safety behavior and rationale are recorded above.
- The task is split before implementation because it changes a reusable native
  boundary, terminal protocol state/encoding, asynchronous PTY ownership, and
  end-user product behavior with independently verifiable failure modes.

### 2026-09-06 — bounded `dart_appkit` pasteboard read

- Added the public/native constant `64 * 1024 * 1024` UTF-8 bytes and status
  `DA_STATUS_LIMIT_EXCEEDED` (`10`). The existing ABI function and snapshot
  layout remain unchanged; current and legacy clients therefore keep symbol
  and struct compatibility.
- The bridge obtains the AppKit string representation and its UTF-8 `NSData`,
  checks the byte count before copying into thread-local bridge storage, clears
  that storage on refusal, and publishes no partial snapshot.
- Added an internal variable-limit helper so native tests exercise an oversize
  refusal with a tiny fixture instead of allocating more than 64 MiB. The Dart
  fake has a length override for the same reason.
- `make test` initially reached the `dart_appkit` analyzer and failed because
  the package test imported the internal API library rather than the public
  barrel that re-exports the new constant. The test was corrected to assert the
  public `Pasteboard.maximumTextUtf8Bytes` contract; the fake/native layers
  independently assert the matching constant.
- Re-run verification: complete `dart_appkit make test` passed, including
  native bridge/header/runner/message-pump/capability tests, all package format
  and analyzers, `dart_pty_macos`, renderer/native-asset hooks, current FFI
  smoke, and legacy bridge fallback smoke.
- The reusable package implementation was committed in `dart_appkit` as
  `35350f8` (`Bound pasteboard text reads`). The next subtask remains terminal
  DEC mode and paste planning/encoding; no product clipboard behavior has been
  enabled early.

### 2026-09-06 — DEC mode and bounded paste codec

- Added screen-set-owned DEC private mode 2004 with idempotent set/reset,
  DECRQM status, RIS reset, and chunk-independent parser behavior. It remains
  session-wide across primary/alternate screen changes, matching keyboard and
  mouse terminal modes rather than visual grid modes.
- Added `TerminalPasteCodec`, immutable content-free analysis, and a stateful
  single-pass encoder. The encoder holds only one 4-byte scalar staging buffer
  plus one caller-sized output chunk; it never constructs the complete encoded
  10 MiB payload.
- CRLF, CR, and LF each become one logical newline. Bracketed mode emits LF;
  plain mode emits CR. One prefix/suffix pair spans every transport chunk.
- The recorded xterm/Ghostty terminal-driver bytes are replaced by spaces.
  All other C0/DEL content (including tab) is still classified for
  confirmation, while the embedded `ESC [ 201 ~` attack is both classified
  and made impossible by ESC replacement.
- Analysis freezes the source UTF-16 length, normalized/body/total byte counts,
  newline/control/replacement counts, bracket state, large-paste state, and a
  deterministic 64-bit source fingerprint. It rejects an encoded body beyond
  64 MiB while scanning.
- Targeted format/analyze and paste/mode/reply tests passed. Encoder tests cover
  CRLF/CR/LF, every replaced byte, tab classification, embedded terminator,
  astral/combining text, malformed surrogate replacement, empty input, limits,
  and every output chunk size from 1 through 17 bytes.
- The first full `CI=true make test` reached the reviewed corpus and correctly
  reported that zsh/Vim mode-2004 sequences had changed from unsupported to
  supported. The reviewed snapshots were updated only at those parser counters
  (`recorded-shell` 4→0, `recorded-vim` 15→12). An explicit corpus replay then
  passed all 1,437 split runs with aggregate hash `952049488`; its pinned test
  oracle was updated accordingly.
- Final subtask verification: `CI=true make test` passed all 135 formatted
  source files, analyzer checks, reviewed corpus/split/hash oracles, terminal
  protocol/renderer/session tests, and native-asset-backed test execution.
- No PTY transport or menu behavior was added in this subtask. The next ordered
  work owns tracked-completion transport and consumes this frozen plan/encoder.

### 2026-09-06 — completion-driven PTY paste transport

- Added a paste-specific `TerminalPaneSession`/`TerminalPane` operation and
  exposed the session's frozen bracketed-paste mode without weakening the
  existing 256-byte key-event API.
- `TerminalSession` now retains one encoded chunk of at most
  `min(16 KiB, writeCapacityBytes)`, submits it with `writeTracked`, and does
  not advance the encoder until the matching `writeCompleted` diagnostic.
  `writeError` fails the transfer before counting the chunk; shutdown or
  natural termination cancels the outstanding completion.
- A native-capacity rejection retains and retries that same one chunk after a
  one-millisecond event-loop yield. This is constant-memory backpressure, not a
  retry queue, and lets AppKit timers/events run between attempts.
- A concurrent paste returns `busy` immediately. Ordinary byte writes and
  automatic terminal replies are rejected while a paste owns the input byte
  stream, with only one visible status notice; this prevents them from landing
  inside a bracket frame. Direct process signals remain out-of-band and do not
  alter PTY byte ordering.
- Content-free results report disposition, completed bytes/chunks,
  backpressure attempts, maximum native queued bytes observed for the tracked
  requests, and concurrent-input rejections. No clipboard or terminal text is
  logged in diagnostics.
- Fake-PTY tests prove one accepted chunk in flight, exact UTF-8/frame ordering,
  concurrent paste/input refusal, queue-full retry and progress, native write
  error accounting, pane delegation, and shutdown cancellation. Each progress
  loop has a two-second test deadline so regressions fail rather than hang.
- Verification: targeted format/analyze and the full native-asset-backed Dart
  suite passed; final `CI=true make test` passed formatter (135 files), analyzer,
  parser corpus/oracles, renderer/protocol/session tests, and all new transport
  cases.
- The next ordered subtask owns clipboard menu behavior, expiring explicit
  confirmation, user-visible status, and real 10 MiB both-runtime acceptance.
