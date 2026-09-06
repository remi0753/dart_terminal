# Phase 6 — OSC title, cwd, hyperlink, palette, and clipboard policy

## Task identity

- Date started: 2026-09-07
- Scope: sixth Phase 6 compatibility-hardening roadmap item
- Status: in progress

## Purpose and background

Turn the already bounded OSC parser into an explicit product policy for
window metadata, current-directory metadata, hyperlinks, colors, and
clipboard access. Close the title/title-stack gaps promoted by the pinned
vttest decisions and real-application captures without granting an untrusted
PTY child implicit access to the macOS pasteboard.

OSC 8 hyperlinks and OSC 4/10/11/104/110/111 palette operations already have
bounded semantic state and focused tests. OSC 0/1/2 titles, iTerm2 OSC 7 cwd,
xterm title-stack operations, cursor color OSC 12/112, and security-sensitive
OSC 52 are still explicit unsupported inputs.

## Ordered subtasks

1. Add session-owned, bounded title/icon/cwd metadata; implement strict OSC
   0/1/2/7 decoding plus the captured xterm title-stack subset; include the
   state in deterministic snapshots and byte-level tests.
2. Synchronize accepted window-title metadata to the native AppKit window and
   prove the bridge in Developer JIT and Release AOT product acceptance.
3. Add independent cursor-color state, implement/query/reset OSC 12/112, and
   render the cursor from that state without changing text foreground.
4. Define OSC 52 as deny-by-default: bounded valid requests are consumed,
   reads return no clipboard data, and writes/clears never reach AppKit.
   Reconcile the inventory, implementation manifest, real-application replay,
   vttest decision, and existing hyperlink/palette evidence before closing the
   parent item.

The order keeps native integration dependent on accepted core metadata,
keeps cursor presentation independently reviewable, and delays the final
compatibility classification until every policy branch is fixed.

## Scope

- Session metadata independent of primary/alternate screen buffers.
- Strict UTF-8 and control/bidirectional-control rejection for displayed
  title metadata.
- File-URI-only cwd metadata with no process cwd or filesystem mutation.
- A bounded ten-entry xterm title/icon stack, including the variants observed
  in immutable lazygit, ncurses, and tmux output.
- Native title propagation through the existing `Window.title` API.
- Cursor color separate from the default foreground palette token.
- OSC 52 validation and default-deny behavior with no pasteboard data flow.
- Existing OSC 8 URL policy and palette behavior re-audited as part of the
  final parent acceptance.

## Out of scope

- Tabs, splits, user title overrides, cwd inheritance, proxy icons, and window
  restoration; Phase 7 owns those consumers of the metadata model.
- Protocol-driven font changes or arbitrary xterm window operations.
- Enabling OSC 52 through settings or interactive permission UI; those require
  the later configuration/privacy UI and may build on this deny boundary.
- Shell integration outside OSC 7, notifications, images, synchronized output,
  or Kitty keyboard features.
- Duration-only soak. ROADMAP policy permits bounded deterministic substitutes;
  reproducible corruption, unintended clipboard access, or unbounded resource
  behavior remains a blocker.

## Dependencies and initial facts

- The screen parser currently recognizes OSC 4, 8, 10, 11, 104, 110, and 111
  and caps retained string payloads at 4096 bytes by default.
- `TerminalScreenSet` owns state shared across primary/alternate buffers and is
  the natural session-metadata boundary. Phase 7 can consume it without moving
  metadata into a grid.
- `dart_appkit` already exposes a checked `Window.title` setter and bounded
  plain-text pasteboard reads/writes. No adjacent native change is needed.
- The application currently updates rendering from the pane `onChanged`
  callback, which runs after parsed PTY output and can coalesce native title
  synchronization with the same ownership boundary.
- The immutable application replay still reports four title-stack byte
  variants under `xterm:csi:xtwinops`; title metadata itself was not required
  to render captured screen cells.
- Bundled terminfo intentionally cancels `Ms`, and XTGETTCAP currently reports
  it unavailable, so the product does not advertise OSC 52 capability.

## Risks and design boundaries

- Titles are untrusted display text. Malformed UTF-8, C0/C1 controls, DEL, and
  Unicode bidirectional formatting controls must not reach AppKit.
- OSC 7 is metadata only. Accepting a URI must not call `chdir`, resolve
  symlinks, stat a path, or grant filesystem authority.
- Title stacks need a fixed depth and fixed per-title byte limit; repeated
  pushes cannot grow memory without bound.
- Cursor color must invalidate presentation and survive primary/alternate
  switching while remaining independently resettable.
- OSC 52 queries can exfiltrate clipboard contents and writes can replace user
  data. The default policy therefore has no clipboard callback at all; a child
  cannot bypass denial by selecting a different xterm selection token.
- Native title updates remain on the AppKit root isolate and must tolerate
  window disposal during shutdown without changing PTY ownership.

## Completion conditions

- Every ordered subtask is verified, documented, checked in ROADMAP, and
  committed separately.
- Accepted title/cwd fields are bounded, deterministic, strict UTF-8 values;
  rejected values do not partially mutate metadata.
- Captured title-stack variants no longer increment the unsupported counter,
  while unsupported XTWINOPS remain explicit.
- A live app visibly uses an accepted OSC 2 title and restores the product
  fallback title after a reset/empty-state transition in both runtimes.
- OSC 12 affects only cursor presentation and OSC 112 restores its initial
  value; queries have byte-exact bounded replies.
- Valid OSC 52 read/write/clear requests cannot read or change the native
  pasteboard under the default policy, with byte-level proof and explicit
  counters/replies.
- Inventory, implementation manifest, application acceptance, FEATURE_MATRIX,
  README, vttest decisions, and task notes agree; the full repository gate
  passes before each completion commit.

## Verification plan

- Focused core tests for whole, split, and bytewise OSC/CSI delivery; malformed
  UTF-8, controls, URI edge cases, stack overflow/underflow, reset, alternate
  screen, snapshots, and deterministic chunking.
- Product tests for native title mutation and fallback in the existing
  deterministic display workflow, then Developer JIT and Release AOT runtime
  integration.
- Renderer composition and golden/reference assertions for cursor color.
- OSC 52 selector/data validation, empty query response, denial counters, and
  proof that no `_TerminalClipboard` method is invoked by PTY output.
- Regenerate and validate compatibility inventory/implementation manifests,
  differential baselines, and application matrix acceptance as required by
  freshness gates.
- Run formatter, analyzer, focused tests, both bundle audits, and
  `CI=true make test`; record exact results below.

## Investigation log

- 2026-09-07: after commit `fb4fbda`, ROADMAP was reread with a clean
  worktree. README, FEATURE_MATRIX, the current Phase 6 exit conditions,
  vttest title disposition, and immutable application title-stack evidence
  were reviewed. This is the first unchecked roadmap item.
- 2026-09-07: xterm Patch #411 defines OSC 0/1/2 title changes, CSI 22/23 title
  stack operations, and OSC 52 selection transfer. iTerm2's pinned source owns
  OSC 7. The product parser already bounds every OSC string before semantic
  dispatch.
- 2026-09-07: the adjacent AppKit package already has tested UTF-8 window-title
  and pasteboard APIs. The terminal project needs no native API extension;
  policy and authority remain in Dart product code.
- 2026-09-07: the task crosses four independently testable ownership domains,
  so all four ordered subtasks above were registered in ROADMAP before code
  implementation. None is complete at this point.
- 2026-09-07: the first focused metadata run rejected the otherwise valid OSC
  2 title `window 日本語` twice. Investigation found that the parser treated
  byte `0x9c` inside the UTF-8 encoding of `本` as an eight-bit ST terminator,
  because string states sent every high byte through the ground-state UTF-8
  decoder. String parsing now retains a valid UTF-8 lead and its continuation
  bytes as raw bounded payload; C1 ST remains a terminator only at an accepting
  byte boundary. Strict semantic decoding still rejects malformed sequences.
- 2026-09-07: a subsequent formatter command accidentally included this
  Markdown memo in a Dart-only file list and stopped before running the test.
  The command was corrected to format only Dart sources; the focused metadata
  test then passed. No generated or product file was changed by the failed
  formatter invocation.
- 2026-09-07: the first compatibility regeneration invoked inventory/summary
  before refreshing the implementation manifest. Inventory bytes were written,
  then reconciliation correctly stopped on the five newly declared selectors.
  Re-running in dependency order (manifest, inventory, summary) succeeded; the
  normal targets themselves are unchanged.
- 2026-09-07: immutable application replay after title-stack support reduced
  current unsupported increments from 98 to 92 and variants from 24 to 20.
  Lazygit moved 40→38, ncurses 2→0, and tmux 12→10; all four observed title
  variants disappeared. Ncurses is now a clean-agreement cell. The remaining
  XTWINOPS window-size queries are valid unsupported parameter variants under
  the same partially implemented selector, so acceptance now permits an
  explicit gap to reference either an unsupported or partial inventory record.
- 2026-09-07: the reviewed product corpus snapshots gained an explicit default
  metadata line. Its recorded Vim fixture also contains four title-stack
  operations, so the expected unsupported count legitimately changed from 12
  to 8 while every screen cell and reply remained unchanged.
- 2026-09-07: all eight reviewed product snapshots then matched. Adding the
  metadata line and closing those four rejects changed the aggregate snapshot
  hash from `80618664` to `1430189535` after the explicit version-2 header;
  input remains 1,421 bytes over 1,437 deterministic split runs.
- 2026-09-07: the fixed-seed property/fuzz suite preserved 837 executions and
  66,675 parsed bytes. Snapshot metadata changed its deterministic state hash
  from `1309664684` through the pre-version-bump intermediate `2004308727` to
  final version-2 hash `1292372482`; no seed, mutation count, or resource bound
  changed.
- 2026-09-07: because the new metadata line changes the semantic snapshot
  schema, the formatter version advances from 1 to 2. Reviewed current product
  oracles use version 2. Immutable application captures remain valid version-1
  historical evidence; their loader explicitly accepts versions 1 and 2 while
  still pinning the exact per-sample hash.
- 2026-09-07: after the metadata completion commit, ROADMAP was reread with a
  clean worktree and the native-title child was confirmed as the next ordered
  task. `dart_appkit` already provides a checked, cached `Window.title` setter;
  no adjacent package change is required. `TerminalSession` parses PTY bytes
  before notifying `TerminalPane`, so the pane `onChanged` callback is the
  existing root-isolate boundary where current session metadata and the native
  window can be synchronized without adding parser-to-AppKit authority.
- 2026-09-07: macOS has no independent terminal icon-title surface. OSC 1
  therefore remains bounded session metadata only; OSC 0 and OSC 2 update the
  shared window-title field and consequently the native window. A null title
  after RIS maps back to the fixed product title `Dart Terminal`; an accepted
  empty string remains an explicit child-provided title rather than being
  silently rewritten.
- 2026-09-07: commit `8a7ba8f` completed native title synchronization.
  ROADMAP, README, FEATURE_MATRIX, and the clean worktree were reread
  immediately afterward; OSC 12/112 cursor color is the next ordered child.
  The existing palette is already session-shared by the primary and alternate
  grids and is observed directly by the Metal compositor, while each attached
  screen can publish metadata-only presentation damage. This permits an
  independent initial/current cursor color without treating it as token-zero
  text foreground or transferring duplicate color state in cell damage.
- 2026-09-07: cursor-color mutation will advance the bounded palette
  generation but use presentation-only screen invalidation rather than dirtying
  every text row. OSC 12 accepts the same strict xterm color grammar as OSC
  10/11 plus the single `?` query; OSC 112 accepts only an empty payload and
  restores the constructor-provided initial cursor color. Query replies retain
  the request's BEL or ST terminator. RIS follows the existing dynamic-palette
  policy and does not silently reset the color.
- 2026-09-07: the first manifest/inventory regeneration intentionally stopped
  after writing the implementation manifest because the inventory generator's
  exact-key gate found OSC 12/112 missing from its reviewed implemented
  metadata. The stale inventory and summary were not written. Their pinned
  xterm locators and partial/full support policy were then moved from the old
  unsupported-gap declarations into the implemented metadata before retrying
  generation in dependency order.
- 2026-09-07: cursor color is semantic terminal state, so the readable
  snapshot format advances from version 2 to version 3 and adds it to the
  palette-defaults record. The eight reviewed product oracles were updated
  only for the version and default cursor field; their 1,421 input bytes remain
  unchanged. The aggregate corpus hash is now `1997758255`. The same schema
  addition and newly recognized OSC selectors move the fixed fuzz state hash
  to `1051389745` across the unchanged 837 executions and 66,675 bytes.
  Immutable version-1 application captures remain unchanged and the loader now
  accepts historical versions 1/2 plus current version 3 while retaining exact
  per-sample hashes.

## Decisions and verification record

- The metadata model is shared by the primary and alternate grids but owned by
  one `TerminalScreenSet`. It never enters cell storage, scrollback, shaping,
  or renderer damage.
- Titles preserve accepted Unicode exactly. Rejection is atomic for malformed
  UTF-8, C0/C1/DEL, line/paragraph separators, bidi-format controls, or more
  than 1,024 UTF-8 bytes.
- OSC 7 accepts only absolute `file://` URIs without userinfo, port, query, or
  fragment, up to 4,096 UTF-8 bytes. Hostnames and percent-encoded paths are
  retained as metadata; no path is resolved or accessed.
- Title save/restore supports xterm operations 22/23, title selectors 0/1/2,
  and normal stack access (missing or zero third parameter). Direct slots 1–10
  and all other XTWINOPS remain explicit unsupported. Each icon/window stack
  retains the newest ten values, including a null fallback value.
- Snapshot format version 2 adds current title/icon/cwd and both title stacks.
  Version-1 application captures remain immutable historical evidence.
- Focused tests passed for metadata invariants, OSC/CSI whole/split/bytewise
  parsing, Unicode `0x9c` continuation handling, stack bounds/underflow,
  alternate/RIS behavior, snapshots, inventory reconciliation, and immutable
  application replay.
- `dart run test/run_tests.dart` passed after regenerating reviewed
  compatibility/differential artifacts and updating product/fuzz hashes.
  `dart analyze` then found only two directive-ordering infos in newly touched
  export/import lists; those lists were reordered and require the final clean
  verification below.
- Final `dart analyze`: passed with no issues after directive ordering was
  corrected.
- Final `CI=true make test`: passed parser-table, inventory/summary/manifest,
  differential, application-matrix/evidence/acceptance, and terminfo freshness;
  formatted 176 Dart files with zero changes; analyzed cleanly; and completed
  the full Dart test runner. Exact current compatibility totals are 260 records
  (81 implemented, 16 partial, 10 safe-ignore, 153 unsupported), 97 product
  declarations, and 92 immutable-application replay rejects across 20 variants
  and 13 owned gaps.
- `git diff --check` passed before the final full gate. No `dart_appkit` change,
  external clipboard access, process cwd mutation, or raw application-capture
  rewrite is included in this subtask.
- The native child compares the accepted session window title with the cached
  AppKit title in the existing pane change callback and performs no native call
  when they already agree. It checks closed/disposed state before both getter
  and setter. Null metadata maps to `Dart Terminal`; OSC 1 does not change the
  macOS title because it only addresses icon metadata.
- `dart format lib/src/terminal_application.dart
  tool/runtime_integration_smoke.dart` formatted the two changed Dart files;
  the first sandboxed `dart analyze` attempt could not update the SDK telemetry
  session file and made no source change. Re-running with the required local
  SDK access passed with no issues.
- `make runtime-terminal-display-integration` passed on Apple arm64 for both
  Developer JIT (2,653 ms) and Release AOT (1,933 ms). Each real application
  set an OSC 2 title, verified the native `Window.title`, saved/set/restored the
  xterm window-title stack, issued RIS, and verified both null session metadata
  and the `Dart Terminal` native fallback before clean ownership teardown.
- Final `CI=true make test` passed all freshness gates, formatting of 176 Dart
  files with zero changes, clean static analysis, and the full Dart test
  runner. Compatibility totals remained 260 records (81 implemented, 16
  partial, 10 safe-ignore, 153 unsupported); application evidence remained 8
  accepted cells with 92 unsupported increments across 20 variants. This
  native-only consumer did not alter parser classifications or reviewed
  snapshots.
- OSC 12/112 now own one configured initial/current direct-sRGB cursor color in
  `TerminalPalette`. Cursor mutation increments the palette generation and
  marks presentation damage on both attached grids without dirtying cell rows;
  identical changes remain no-ops. Primary/alternate switching shares the
  value, and RIS deliberately preserves it until OSC 112 restores the initial
  color.
- Focused palette tests passed default/configured/invalid colors, mutation,
  BEL/ST query bytes, alternate-screen persistence, reset, malformed atomic
  rejection, whole/split/bytewise parsing, and presentation-only damage.
  Reply, compatibility-surface, version-3 snapshot, and native Metal
  compositor tests passed; the compositor observed `0x123456c0` on the cursor
  instance while the text glyph remained `0xe5e5e5ff`.
- Manifest/inventory generation then passed with 99 product declarations and
  260 inventory records: 82 implemented, 17 partial, 10 safe-ignore, and 151
  unsupported. OSC 112 is implemented; OSC 12 remains partial only because the
  product deliberately accepts bounded RGB syntax rather than arbitrary xterm
  color names/chained parameters. Immutable application evidence and the
  reviewed acceptance replay remained 8 accepted cells, 92 unsupported
  increments, 20 variants, and 13 owned gaps; only its implementation-manifest
  hash pin changed.
- `make runtime-terminal-display-integration` passed the live
  presentation-only cursor mutation and reset in Developer JIT (2,634 ms) and
  Release AOT (2,007 ms). Both arm64 products retained the default text
  foreground, accepted a newer Metal frame for OSC 12, accepted another frame
  for OSC 112, and completed clean ownership teardown.
- The first full gate stopped at the differential baseline freshness check
  because that reviewed baseline pins the implementation-surface SHA. The
  official generator replayed all four cases over 210 split runs; observations
  remained unchanged apart from their provenance, and regenerated acceptance
  retained 12 accepted attempts (6 agreements, 2 documented gaps, 4 unavailable).
- The second full gate reached the Dart tests and found that the raw-application
  negative fixture still used snapshot version 3 as its deliberately
  unsupported value. Since version 3 is now current, the fixture was advanced
  to version 4; this changes no accepted historical evidence or parser rule.
- Final `CI=true make test` passed every parser-table, inventory, manifest,
  differential, application-matrix, and terminfo freshness gate; formatting
  checked 176 Dart files with zero changes, analysis reported no issues, and
  the complete Dart test runner passed. `git diff --check` also passed. No
  `dart_appkit` source, native clipboard authority, or cell foreground token is
  changed by this child.
