# Phase 5 — hyperlink hover/open and URL safety

## Task identity

- Date started: 2026-09-06
- Scope: eighth Phase 5 production-input roadmap item
- Status: in progress
- Ordered subtasks:
  1. add a bounded OSC 8 table, current-link state, and cell lifecycle;
  2. add viewport hyperlink hit testing and a Metal hover overlay;
  3. add an allowlist-enforcing external-URL open boundary to `dart_appkit`;
  4. connect real AppKit hover/open behavior and both-runtime product acceptance.

## Purpose and background

Make producer-declared OSC 8 links discoverable and deliberately openable from
the live Metal terminal without permitting arbitrary terminal output to send an
unsafe target directly to Launch Services. The existing screen, scrollback,
reflow, snapshot, and damage layouts already preserve a reserved 16-bit
hyperlink ID per cell, but all product writes currently store ID zero. There is
no URI table, parser dispatch, viewport copy, hover overlay, or OS URL-opening
boundary.

This item follows the completed clipboard task and precedes the Phase 5
VoiceOver task. It crosses independently reusable terminal-core, renderer,
native AppKit, and product-integration boundaries, so it is split before source
implementation as required by the repository work rules.

## Scope

- Parse the standard `OSC 8 ; params ; URI ST` open form and `OSC 8 ; ; ST`
  close form from the already bounded VT string payload.
- Preserve a bounded immutable URI definition behind each nonzero 16-bit cell
  ID through primary/alternate grids, scrollback, resize/reflow, viewport
  projection, snapshots, and renderer damage.
- Treat the optional `id` parameter as producer-supplied grouping metadata;
  openings without `id` receive distinct cell IDs even when their URI text is
  identical.
- Refuse malformed UTF-8, invalid parameters, over-limit definitions, unsafe
  URI text, and exhausted table capacity without allocating an unbounded
  fallback or leaving a prior link active.
- Resolve hover/click coordinates against the current visible viewport,
  normalize wide-cell continuations, and reject stale/out-of-grid cells.
- Render an underline-style Metal hover indication without mutating canonical
  terminal content, style, selection, or scrollback.
- On macOS, open only explicitly allowlisted absolute `http`, `https`, and
  `mailto` targets. Block scheme-less, file, data, javascript, custom-scheme,
  credential-bearing, control/invisible-character, and malformed targets
  before calling `NSWorkspace`.
- Open only after an intentional Command-primary-click. A consumed open action
  must not also become terminal mouse input or a local selection gesture.
- Exercise the real native pointer/menu/event path and a real PTY-produced OSC
  8 fixture in both Developer JIT and Release AOT without launching the user's
  browser during automated acceptance.

## Out of scope

- Regex detection of visible plain-text URLs or file paths, semantic-history
  path resolution, configurable link matchers/actions, context menus, drag and
  drop, link previews, visited-link history, or persistence across sessions.
- Opening `file:` or custom schemes, executing link handlers or shell commands,
  and a confirmation UI that bypasses the allowlist. A later explicit product
  policy may add narrowly reviewed schemes.
- OSC 52 clipboard access, semantic prompt ranges, search overlays, images, and
  accessibility. VoiceOver remains the next ordered Phase 5 task.
- Cursor artwork changes in `dart_appkit`; visible Metal hover feedback and the
  Command-click contract are the completion boundary for this item.

## Dependencies and confirmed facts

- `README.md`, `ROADMAP.md`, and `FEATURE_MATRIX.md` were re-read after clipboard
  commit `1595350`; both repositories were clean at task start.
- `TerminalScreen`, `TerminalScrollback`, terminal reflow, state snapshots, and
  damage codec v2 already store/copy a `Uint16` hyperlink value, reserving zero
  for no link and `0xffff` as invalid. Public cell setters validate IDs through
  `TerminalScreen.maxResourceId`.
- `TerminalScreen._printNewCellGroup` nevertheless hard-codes hyperlink zero,
  and `TerminalScreenParserSink.dispatchOsc` currently accepts only palette and
  default-color commands. The default VT parser caps a string payload at 4096
  bytes before dispatch.
- `TerminalViewport.hyperlinkAt` already projects history or active-grid IDs,
  but `TerminalViewportRenderModel` omits that channel, so the default live
  Metal surface cannot inspect a visible link.
- `dart_appkit` protocol v5 already delivers finite content-view mouse
  down/up/moved/dragged coordinates and modifiers. The product routes them
  exclusively through terminal mouse reporting or local selection.
- `dart_appkit` has no `NSWorkspace` API. Its existing FFI bridge, typed result,
  fake-binding, main-thread, and optional-symbol compatibility patterns are the
  required extension points.
- The OSC 8 proposal states that an opening sequence applies its target to
  subsequently painted cells and that empty params/URI close the hyperlink.
  It defines colon-separated parameters and currently standardizes `id`.
- Apple's AppKit documentation defines `NSWorkspace.open(_:)` as the API that
  opens a URL with the registered application and returns whether the open was
  accepted. Ghostty's current macOS implementation separately classifies OSC 8
  targets as untrusted before reaching that API; this project adopts the same
  trust-boundary principle with a deliberately narrower deny-by-default policy.

Primary references:

- <https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda>
- <https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)> 
- <https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Ghostty/Ghostty.App.swift>

## Design decisions

### Resource ownership and bounds

- One session-owned `TerminalHyperlinkTable` is shared by primary and alternate
  screens. ID zero means no link; definitions use IDs 1 through 65534 and are
  immutable for the lifetime of the session so retained scrollback IDs cannot
  resolve to a newly reused URI.
- The alpha table admits at most 4096 definitions and 1 MiB total stored UTF-8
  URI/parameter-key bytes. The parser's existing 4096-byte payload cap is the
  per-definition ceiling. Capacity exhaustion closes the current hyperlink and
  increments a bounded refusal counter; it never grows storage or aliases IDs.
- Explicit producer `id` plus URI is interned so separated spans can share one
  identity. An opening without `id` always allocates a fresh identity. Unknown
  well-formed parameters are ignored for forward compatibility; malformed or
  duplicate `id` data rejects the opening.

### Safety and interaction

- URI policy is pure and tested in Dart before the native call. It rejects
  scalar controls, bidi formatting/isolate controls, line/paragraph separators,
  whitespace, backslash ambiguity, missing/relative schemes, web URLs without
  authority/host, and web credentials. Scheme comparison is ASCII
  case-insensitive and the only allowlist is `http`, `https`, and `mailto`.
- The native `dart_appkit` API receives only a policy-approved absolute URL,
  repeats structural and allowlist validation before constructing `NSURL`, and
  calls `NSWorkspace` without shell interpolation. Automated product acceptance
  substitutes an opener recorder after the same Dart policy so no external app
  is launched.
- Hover is derived state keyed by current viewport generation, cell, and
  hyperlink ID. It is discarded on pointer exit-equivalent/out-of-grid input,
  viewport movement, link disappearance, or surface disposal. Click resolution
  is repeated at click time rather than trusting the last hover snapshot.
- Command-primary-click owns the event only when the clicked cell still resolves
  to an allowed OSC 8 target. Blocked/malformed targets are consumed and produce
  a bounded status notice; they never fall through to a less restricted opener.

## Completion conditions

- Valid OSC 8 open/close sequences mark exactly the subsequently printed cells,
  preserve wide/grapheme topology and reflow/history identity, and resolve to
  the correct immutable URI.
- Malformed/oversized/exhausted input cannot create an unbounded table, reuse a
  retained ID for another URI, or accidentally continue a previous link.
- Visible history and active-grid links can be hit-tested; hover produces a
  deterministic Metal overlay without changing terminal text or selection.
- Only allowed absolute targets can reach `NSWorkspace`; all other schemes and
  invisible/deceptive targets are refused before OS dispatch.
- Command-click opens once and is not also reported to the PTY or selection.
  Ordinary click, Shift override, and terminal mouse modes retain their current
  exclusive routing behavior.
- Unit, parser/reflow/renderer, `dart_appkit`, native-asset, real PTY/AppKit, and
  both-runtime product acceptance all pass, with docs/matrix/roadmap updated.

## Verification plan

- Terminal core: chunk-split OSC 8 parser tests; malformed UTF-8/params, explicit
  and implicit identity, capacity/byte ceilings, reset/screen switching,
  wide/grapheme edits, scrollback and resize/reflow tests; snapshot/damage
  compatibility and bounded resource diagnostics.
- Renderer/input: viewport continuation normalization, history hit tests, stale
  hover invalidation, overlay spans, clipping, 1x/2x deterministic instances,
  selection coexistence, and no canonical-grid mutation.
- `dart_appkit`: public header and fake/FFI binding tests, missing-symbol legacy
  behavior, native structural/allowlist rejection, main-thread use, and a native
  test hook proving only accepted URLs reach the workspace dispatch point.
- Product: deterministic real-PTY OSC 8 output, native moved/down/up injection,
  allowed/blocked targets, one-open/exclusive ownership counters, visible hover
  Metal evidence, Developer JIT and Release AOT, source/bundle audits, smoke,
  display, resource, and final full runtime verification.

## Investigation and implementation log

### 2026-09-06 — task start and decomposition

- Re-read the product overview, ordered Phase 5 roadmap, feature matrix rows
  `SCR-11`, `CAP-05`, `REN-08`, `SEC-01`, and `SEC-02`, and confirmed this is
  the first unchecked task after the clean clipboard completion commit.
- Inspected the parser sink, screen/screen-set ownership, scrollback/reflow,
  viewport model, damage codec, Metal compositor/live surface, mouse router,
  product event subscription, and adjacent AppKit public/native binding layers.
- Confirmed that the pre-existing hyperlink arrays were intentional forward
  storage, not a functioning hyperlink implementation. The current rendering
  path drops the channel at viewport capture and product writes always use ID
  zero.
- Reviewed the OSC 8 proposal, Apple's `NSWorkspace` URL-opening contract, and
  Ghostty's current separation of producer-controlled OSC 8 targets from its
  unrestricted generic opener. No upstream source is copied.
- Split the task before implementation because core resource identity,
  renderer-derived hover state, reusable native URL dispatch, and real product
  arbitration have independent safety/compatibility failure modes and must be
  committed and re-checked in order.

### 2026-09-06 — bounded OSC 8 table and cell lifecycle

- Added the session-owned `TerminalHyperlinkTable`. It uses immutable IDs 1
  through 65534, with alpha defaults of 4096 definitions, 1 MiB aggregate
  stored UTF-8, 4096 bytes per definition, and 1024 bytes per explicit ID.
  Implicit openings always allocate a distinct identity; equal explicit
  `(id, URI)` openings reuse one identity without consuming another slot.
- Primary and alternate screens now share the table, and screen resize/reflow
  carries that exact table instance forward. Existing cell, scrollback,
  snapshot, and damage layouts remain 16-bit compatible; ID zero and the
  reserved `0xffff` value are unchanged.
- `TerminalScreen.printScalar` accepts the parser-owned current hyperlink and
  applies it atomically to scalar, grapheme, wide lead, and continuation cells.
  OSC dispatch already breaks the streaming grapheme boundary, so a link-state
  transition cannot retroactively extend a preceding cell under another ID.
- Added OSC 8 open/close dispatch with strict UTF-8 decoding, bounded
  colon-separated parameter parsing, explicit `id`, ignored well-formed future
  keys, and deterministic close-on-refusal behavior. Missing separators, empty
  or duplicate IDs, unsafe URI scalars, malformed UTF-8, table limits, OSC
  string limits, and RIS all clear the active link rather than extending stale
  authority to later output.
- Snapshot formatting records exact URI/explicit-ID definitions only when the
  table is nonempty and applies separate definition-count and aggregate-byte
  limits. Existing zero-link corpus snapshots therefore remain byte-identical,
  while link-bearing state can no longer compare equal solely because its cell
  IDs happen to match.
- Added focused tests over every parser split, explicit/implicit identity,
  malformed params and UTF-8, parser/table/byte ceilings, wide continuation,
  combining grapheme, scrollback, resize/reflow, primary/alternate switching,
  RIS, snapshot definitions, and snapshot resource limits.
- The first direct `dart format` invocation formatted the requested sources but
  then failed while updating the SDK telemetry session timestamp outside the
  workspace sandbox. The same explicit formatter command was rerun with the
  required filesystem permission and completed; no workaround or alternate
  formatter was used.
- The first full test run passed all tests but the analyzer emitted one
  `directives_ordering` info for the new public export. The export order was
  corrected, then the full analyzer and focused hyperlink test passed with no
  issues.

### 2026-09-06 — viewport hit test and Metal hover overlay

- Added `TerminalViewport.hitTestHyperlink`, which treats pointer coordinates
  outside the currently projected source row as no hit, normalizes a wide-cell
  continuation to its canonical lead while retaining the actual pointer
  column, rejects zero/undefined IDs, and returns one immutable URI definition
  tied to the observed viewport generation.
- Added explicit prior-hit refresh. It re-resolves the same physical pointer
  position after screen/history/offset changes and retains the hover only when
  the cell still has the same immutable hyperlink ID. It never retargets a
  click merely because a different link moved under a stale coordinate.
- `TerminalViewportRenderModel` now copies the existing hyperlink channel along
  with content, colors, styles, and width flags. This closes the only data loss
  between scrolled history and the default live Metal compositor; the retained
  damage model already implemented the same render-model field.
- The compositor accepts one bounded hovered ID, scans it during the existing
  visible-cell traversal, and emits foreground-colored underline rectangles on
  the decoration layer. Wide cells produce one double-width rectangle; a
  producer-grouped ID may underline separated visible spans. Canonical cells,
  styles, selection, and scrollback remain untouched.
- The live surface owns only the latest resolved hover, coalesces equal-ID
  moves, requests a full visual redraw on enter/leave, refreshes the hit after
  every pending screen/viewport update, and clears it on disappearance or
  disposal. Its content-free snapshot exposes only ID and cell coordinates,
  never URI text.
- Focused tests cover active/history hits, out-of-grid input, continuation
  normalization, replacement and viewport stale invalidation, copied render
  fields, separated explicit-ID spans, wide-cell geometry, canonical-state
  immutability, and native Metal readback at 1x and 2x.

### 2026-09-06 — allowlisted AppKit external URL boundary

- Added the closed `dart_appkit` `AllowedExternalUrl` value type. It preserves
  the exact approved text but can only be constructed by a parser that accepts
  absolute `http`, `https`, or `mailto` schemes within 4096 UTF-8 bytes. Web
  targets require an authority and host and reject credentials; mail targets
  require a non-authority recipient.
- Both the Dart policy and native bridge reject raw controls, whitespace,
  backslashes, soft-hyphen/bidi/invisible formatting characters, malformed
  percent escapes, and percent-encoded controls, backslashes, or invisible
  formatting. Encoded ASCII space remains accepted because it is an ordinary
  URL component representation rather than raw ambiguous input.
- `AppKitApplication.openExternalUrl` accepts only the closed value type. The
  optional ABI-v1 symbol copies the text, revalidates the complete policy on
  the AppKit main thread, constructs `NSURL` only afterward, and calls
  `NSWorkspace.openURL` directly without shell interpolation. A zero/one output
  distinguishes Launch Services refusal from bridge failure and is initialized
  to zero on all error and wrong-thread paths.
- The native test exercises the same post-validation dispatch with a recorder
  or refusing opener, so accepted targets reach that point exactly once and
  rejected targets never do. FFI smoke runs off-main and therefore proves the
  real Mach-O symbol/thread guard without opening the user's browser or mail
  client. Missing-symbol compatibility returns status 8 against the legacy
  bridge fixture.
- The first Dart API run exposed that Dart's `Uri.isAbsolute` rejects otherwise
  valid fragment-bearing references. The check was narrowed to the intended
  security condition—presence of the explicit allowlisted scheme—and the test
  passed. The first complete native run then exposed over-rejection of `%20` in
  a mail subject; encoded ASCII space was separated from the still-rejected
  encoded control/invisible set. The subsequent complete suite passed.
- The reusable dependency change was committed independently as `08ad353 Add
  allowlisted external URL opening`. The product repository remained otherwise
  unchanged while that dependency commit was prepared.

## Verification results

### Bounded OSC 8 table and cell lifecycle

- Explicit `dart format` over all changed Dart sources: passed.
- Focused static analysis over the core/table/snapshot/test changes: passed.
- `dart run test/terminal_hyperlink_test.dart`: passed before and after the
  export-order correction.
- Initial `CI=true make test`: all tests passed, with the one analyzer info
  described above. After correcting it, the final `CI=true make test` passed
  cleanly: all 137 files were format-clean, full analysis reported no issues,
  all native build hooks ran, and the complete Dart test suite passed.
- `git diff --check`: passed during final pre-commit review.

### Viewport hit test and Metal hover overlay

- Explicit `dart format` over the ten changed Dart sources: passed.
- Focused static analysis over hyperlink, viewport, render-model, compositor,
  live-surface, and test sources: passed with no issues.
- `dart run test/terminal_hyperlink_test.dart`: passed.
- `dart run test/terminal_viewport_render_model_test.dart`: passed.
- `dart run test/terminal_screen_metal_compositor_test.dart`: passed, including
  1x/2x native Metal frame rendering.
- Final `CI=true make test`: passed; all 137 files were format-clean, analyzer
  reported no issues, parser-table freshness and native build hooks passed,
  and the complete Dart test suite passed.
- `git diff --check`: passed during final pre-commit review.

### Allowlisted AppKit external URL boundary

- Explicit `dart format` over the ten changed Dart sources: passed.
- Focused `make native-test dart-test`: native bridge tests and Dart analysis
  passed; the first Dart run found the fragment issue recorded above, and the
  corrected rerun passed every API and launcher test.
- Final `make test` in `dart_appkit`: passed every C11/C++20 header and
  warning-as-error gate, native bridge/runner/runtime/renderer/PTY test, Dart
  package analysis/test, Kernel compilation, real Mach-O FFI smoke, and legacy
  additive-symbol fallback.
- `git diff --check`: passed during final pre-commit review.
