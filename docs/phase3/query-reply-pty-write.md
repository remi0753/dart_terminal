# Phase 3 — Query/reply encoding and PTY write connection

- Status: complete
- Date: 2026-09-05
- Scope: the first incomplete Phase 3 roadmap item after paged scrollback,
  viewport, selection, and search primitives
- Related: `ROADMAP.md` sections 5.1, 5.4, 5.5, 5.12, and Phase 3;
  `FEATURE_MATRIX.md` CAP-01, CAP-05, SEC-01;
  `docs/adr/ADR-001-dart-native-boundary.md`;
  `docs/adr/ADR-002-isolate-thread-ownership.md`;
  `docs/phase3/vt-sequence-parser.md`;
  `docs/phase3/sgr-palette-primary-alternate-screen.md`

## Purpose and background

Answer the bounded terminal capability and state queries needed by interactive
applications, encode replies without unbounded text construction, and route
those reply bytes back through the owning session's existing ordered PTY write
queue. Incoming PTY bytes must reach the Dart terminal parser without first
being converted to text, while the current legacy text projection remains
available until the renderer migration reaches its roadmap position.

The parser already produces typed CSI and OSC records, the screen and screen
set own the cursor, mode, palette, and alternate-screen state needed for
replies, and the native PTY backend already owns a bounded FIFO write queue.
The missing pieces are a truthful reply policy, a synchronous bounded encoder,
query dispatch in `TerminalScreenParserSink`, and the product-session
connection from raw PTY output through the parser back to `PtyProcess.write`.

## Scope

- Bounded 7-bit reply encoding for primary and secondary device attributes,
  terminal status, ANSI/DEC cursor position, ANSI/DEC mode reports, and OSC
  palette/default foreground/default background colors.
- Query recognition for DA/DA2, DSR/CPR/DECXCPR, ANSI and DEC DECRQM, and the
  already deferred OSC 4/10/11 `?` forms. Reports describe only state and
  capabilities actually implemented by the current terminal core.
- Preserve the query's BEL or ST terminator for OSC replies and encode current
  logical colors as deterministic 16-bit-per-component `rgb:` values.
- A synchronous reply callback with accepted/rejected counters and exception
  containment so transport failure cannot corrupt parser or screen state.
- One `TerminalScreenSet`, parser sink, and `VtParser` owned by each product
  `TerminalSession`; raw PTY chunks feed that parser before the existing UTF-8
  text projection consumes them.
- Route generated reply bytes to the same native bounded write queue as user
  input, preserve accepted-call ordering, surface reply backpressure with a
  separate bounded counter, finish parser state when PTY output closes, and
  resize the terminal core atomically with the PTY dimensions.

## Out of scope

- Keyboard, keypad, focus, bracketed-paste, mouse, Kitty keyboard, or paste
  encoding. Their state and outbound event encoders belong to later input
  roadmap tasks.
- XTGETTCAP, DECRQSS, window/pixel-size reports, tertiary DA, printer/UDK/
  keyboard/locator status, or project-specific terminfo.
- OSC title, cwd, hyperlink, clipboard, notification, progress, or semantic
  prompt protocols.
- A second Dart isolate or renderer migration. The current product session
  remains the owner until the later worker/render integration task.
- An unbounded retry queue above the native PTY writer. A transport rejection
  remains observable and bounded rather than retaining attacker-controlled
  replies indefinitely.

## Dependencies and constraints

- Parser callbacks are synchronous and must not recursively feed the parser.
  Reply callbacks may synchronously submit bytes to the PTY writer but cannot
  mutate parser input or retain a shared mutable encoder buffer.
- Every emitted reply is a fresh `Uint8List`, contains only validated 7-bit
  protocol bytes, and is bounded by a small fixed maximum. Query parameters are
  already capped by `VtParserLimits`, but unsupported or multi-parameter forms
  must remain safe no-ops.
- Primary DA advertises only VT220-class ANSI color support; secondary DA uses
  a fixed product version tuple. Unknown modes report DECRPM status 0 rather
  than claiming unsupported behavior.
- Cursor reports are one-based and origin-relative while origin mode is set.
  DEC and ANSI query forms retain their distinct private marker in replies.
- XTerm's control-sequence specification is the compatibility reference: DA
  response structure, DSR/CPR, DECRQM/DECRPM status values, multiple OSC 4
  query replies, and same-terminator OSC responses are documented in
  <https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html>.
- Core source remains Dart-only and independent of AppKit, Metal, PTY FFI, and
  native packages. Only `TerminalSession` depends on the PTY package.

## Ordered subtasks

1. **Bounded reply encoder and terminal-core query dispatch**
   - Add the reply encoder/callback contract and dispatch DA/DA2, DSR/CPR,
     ANSI/DEC DECRQM, and OSC 4/10/11 queries from current screen state.
   - Complete when exact bytes, origin-relative cursor coordinates, recognized
     and unknown mode reports, palette/default colors, BEL/ST preservation,
     multi-query ordering, missing/rejecting/throwing transports, malformed
     forms, every split, bytewise parsing, hard reply bounds, focused JIT,
     Release AOT, full tests, and source audit pass.
2. **Raw parser feed and bounded PTY reply connection**
   - Give each product session an owned terminal screen set/parser, feed raw
     PTY chunks into it while preserving the legacy projection, connect replies
     to `PtyProcess.write`, finish parser state on output close, and resize core
     plus PTY together.
   - Depends on subtask 1. Complete when fake-PTY tests prove raw split input,
     exact reply ordering, resize/state synchronization, backpressure and
     inactive/disposed rejection, parser completion, lifecycle compatibility,
     real PTY smoke, focused JIT, Release AOT, full tests, and source audit.

Each child receives its own verification notes, roadmap update, and completion
commit. The parent remains unchecked until both children pass.

## Completion criteria

- Supported queries emit exact, truthful, bounded bytes and never mutate
  terminal presentation state merely by being queried.
- Unknown, malformed, oversized, callback-rejected, and callback-throwing
  requests remain deterministic, observable, and parser-recoverable.
- Product PTY output is parsed from original byte chunks, generated replies use
  the existing bounded native writer, and accepted replies remain ordered with
  other accepted writes.
- Screen dimensions, parser lifetime, PTY lifetime, and legacy output
  projection remain synchronized without duplicate subscriptions or resource
  ownership leaks.
- Formatting, analysis, focused and full tests, Release AOT, Dart-only source
  audit, documentation, roadmap progress, and one commit per child pass.

## Verification plan

1. Table-test every encoder form at minimum/maximum values and reject invalid
   values without partial output or buffers larger than the fixed maximum.
2. Parse query streams as a whole, at every split, and bytewise; compare exact
   ordered reply bytes and unchanged state/counters for unsupported input.
3. Exercise cursor reports in normal/origin and primary/alternate state, every
   implemented mode state, unknown modes, OSC color mutations followed by BEL
   and ST queries, and multiple palette queries.
4. Drive a fake product PTY with split raw UTF-8 and query bytes; verify both
   legacy display output and canonical terminal state, exact PTY replies,
   resize, backpressure, close, and parser finish behavior.
5. Run focused JIT and Release AOT tests, `make test`,
   `make runtime-source-check`, whitespace checks, and staged diff review for
   each completion commit.

## Investigation log

- `fd2f1fc` completed selection/search. The worktree was clean after the
  required roadmap, README, and feature-matrix reread; query/reply encoding and
  PTY connection became the first unchecked task.
- The product `TerminalSession` currently transforms the single-subscription
  `Stream<Uint8List>` into strings before appending to legacy
  `TerminalBuffer`; it does not own or feed a `VtParser` or `TerminalScreenSet`.
- `TerminalScreenParserSink` already owns all implemented CSI/OSC semantics but
  counts every query as unsupported. It can answer from current cursor, mode,
  screen-set, and palette state without adding a second authoritative model.
- `PtyProcess.write` synchronously copies accepted bytes into a bounded native
  FIFO and returns `backpressured` on rejection. It provides no writable Future;
  therefore this task must not invent an unbounded Dart retry queue.
- The task is split because the pure terminal-core protocol contract is useful
  and independently testable without PTY dependencies, while product-session
  stream ownership and write backpressure are a separate integration boundary.
- The first screen-set mode test expected cursor blink/visibility values set
  on primary after it had switched to alternate. The report correctly read the
  active alternate screen's independent defaults; the expectation was updated
  to enforce active-screen ownership rather than cross-buffer leakage.
- Core query dispatch completed in `e2276cd`. The clean-worktree roadmap,
  README, feature-matrix, and task-memo reread made raw parser feed and the
  bounded PTY reply connection the current child.
- The first integration analysis found one unused direct PTY API import in the
  focused fake-backend test. The testing library already exposes the required
  fake types, so the redundant import was removed; product code was unaffected.
- The first real-PTY DSR assertion assumed one space between `od` bytes, while
  macOS `od` emitted two. The child had received the exact four reply bytes;
  the smoke command now removes formatting whitespace and compares the compact
  hex value instead of depending on presentation spacing.

## Decisions and alternatives

- Use a public semantic `TerminalReplyEncoder` backed by a private fixed-size
  byte builder. Generic caller-supplied format strings or unbounded parameter
  lists are excluded; each method validates its small fixed argument set and
  returns an independently retainable `Uint8List`.
- Advertise primary DA as VT220-class plus ANSI color (`CSI ? 62 ; 22 c`) and
  secondary DA as fixed VT220 type/version/component values. This is more
  conservative than copying xterm's full capability list and does not claim
  sixel, selective erase, locator, or input protocols not yet implemented.
- Report only mutable modes that the current sink can set: ANSI insert and DEC
  reverse video, origin, auto-wrap, cursor blink/visibility, alternate-screen,
  and horizontal-margin states. Unknown modes receive DECRPM 0; cursor-save
  mode 1048 is an action without persistent state and is therefore unknown.
- Keep the reply handler synchronous and return a boolean admission result.
  Accepted and rejected replies have separate monotonic counters; a missing,
  rejecting, or throwing handler rejects safely without converting a
  recognized query into an unsupported sequence.
- Parse every OSC 4 pair before applying any mutation or emitting any reply.
  This preserves existing malformed-sequence atomicity. Valid mutations apply
  as one batch, then query replies observe the final palette state and retain
  the query order and terminator.
- Tap the one PTY output subscription before its existing incremental UTF-8
  transformer: each original `Uint8List` first enters the terminal parser and
  the same object then continues to the legacy text projection. This avoids a
  second subscription, byte reconstruction, and regressions while renderer
  migration remains pending.
- Let each `TerminalSession` own one screen set, parser sink, and parser for its
  full process generation. Pre-start and live resizes update that screen set;
  the terminal-core dimension/cell limits now validate before PTY resize state
  is changed.
- Submit replies directly to `PtyProcess.write`, whose native FIFO already
  provides the project-wide ordering and byte cap. Rejection is not retried
  without a writable notification; it increments a separate saturating count
  and state flag, while the core sink records the rejected reply.
- Finish the parser from the PTY output stream's `onDone` callback before
  publishing output drain completion. This turns a trailing partial sequence
  into the existing typed incomplete observation exactly once.

## Verification results

### Bounded reply encoder and terminal-core query dispatch

- Direct encoder tests passed exact primary/secondary DA, terminal status,
  maximum cursor coordinate, maximum mode number, palette/default color, BEL,
  and ST bytes. Every result stayed within the fixed 64-byte limit, owned an
  independent retainable typed buffer, and rejected invalid coordinates,
  modes, palette indices, color tokens, and OSC commands.
- Parser integration passed omitted/zero DA forms, ANSI status/CPR, DECXCPR,
  normal and origin-relative coordinates, ANSI and DEC DECRQM/DECRPM, every
  currently modeled mode, unknown status 0, primary/alternate state isolation,
  and non-persistent 1048 rejection.
- OSC tests passed batched palette mutation/query, mixed mutation then query,
  default foreground/background mutation/query, deterministic 8-to-16-bit RGB
  expansion, ordered multi-replies, malformed batch atomicity, and exact BEL/
  ST terminator preservation.
- Missing, rejecting, and throwing reply handlers each incremented the bounded
  rejection counter without escaping the callback or blocking following
  printable input. Malformed/unsupported query forms produced no partial reply
  and recovered deterministically; a well-formed unknown mode still replied
  with DECRPM status 0.
- The representative combined query stream produced identical state, counters,
  and reply order as one chunk, at every single split, and bytewise. Related
  parser, screen, screen-set, and palette suites passed.
- `make test` passed dependency resolution, VT table freshness, formatting of
  65 files with zero changes, full static analysis with no issues, and the
  complete test runner. The focused reply suite compiled to a Release AOT
  executable and completed successfully.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 122 tracked files and zero native source files.

This completes ordered subtask 1. The parent remains open; raw parser feed and
the bounded PTY reply connection are now the first unchecked child.

### Raw parser feed and bounded PTY reply connection

- Fake-PTY integration passed an original UTF-8 scalar split across two output
  chunks together with terminal status and cursor-position queries. The same
  bytes updated canonical screen cells and the legacy text projection, while
  replies reflecting the updated cursor state were accepted in exact order
  between surrounding user writes.
- Each session now owns one screen set, parser sink, and parser for its process
  generation. Pre-start dimensions initialized the PTY and core consistently;
  live resize updated the PTY plus both primary/alternate grids. Invalid zero
  and over-limit dimensions changed neither screen identity nor PTY size.
- Closing PTY output with a partial CSI finished parser state and emitted one
  incomplete observation before output-drain completion. Existing termination,
  shutdown, and legacy buffer behavior remained intact.
- A four-byte fake native queue saturated by user input rejected one four-byte
  automatic status reply, incremented only the separate saturating reply
  pressure count and core rejection count, and retained no Dart retry payload.
  After fake native capacity drained, a later query succeeded and cleared the
  pressure flag. Queries before process start and after dispose were rejected
  without being mislabeled as queue pressure or touching native state.
- The real persistent-zsh smoke temporarily entered raw/no-echo mode, emitted
  DSR, read four bytes from the PTY, and observed compact hex `1b5b306e` for
  `CSI 0 n`. It then restored terminal settings and passed the existing TTY,
  size, multiple-command, background-job, foreground interrupt, exit, and reap
  assertions.
- Focused core-reply and session-reply suites and full static analysis passed.
  `make test` passed dependency resolution, VT table freshness, formatting of
  66 files with zero changes, full analysis with no issues, the fake
  integrations, real PTY round trip, and the complete test runner. The focused
  session integration compiled to a Release AOT executable and completed
  successfully.
- `git diff --cached --check` passed. The staged-source Dart-only audit passed
  with 123 tracked files and zero native source files.

This completes ordered subtask 2 and its parent. Snapshot formatting and
readable test diagnostics are now the first unchecked roadmap task.

## Risks and handoff

- A saturated native write queue can reject an automatic reply. This must be
  counted separately and remain visible to later queue/backpressure work; no
  readiness notification currently exists for a lossless bounded retry.
- Advertising capabilities not actually implemented can make applications
  select broken paths. Device attributes and mode reports must remain
  deliberately conservative as later input and protocol features arrive.
