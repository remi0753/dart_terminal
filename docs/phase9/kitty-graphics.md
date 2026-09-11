# Phase 9 — Kitty graphics parse, storage, placement, and render

## Task identity

- Date started: 2026-09-11
- Scope: fourth Phase 9 roadmap item
- Feature-matrix owner: CAP-11
- Status: grammar, process-worker storage, placement-action, and lifecycle/
  projection children complete; CPU reference compositor child in progress
- Predecessor: `docs/phase9/light-dark-notification-extended-reports.md`

## Purpose and background

Add the Kitty graphics protocol needed by modern terminal applications without
moving decode work or unbounded image payloads onto the UI isolate. The first
roadmap item owns transmit parsing, bounded storage, placement, z-index,
scroll/erase semantics, and a real Metal projection. Animation and general
resource eviction remain the immediately following roadmap item, so this task
must establish compatible ownership and limits without implementing that later
behavior early.

## Scope

- Pin immutable Kitty/Ghostty protocol sources and enumerate only the transport,
  action, format, compression, placement, query, delete, scroll, and z-index
  forms that this product can own safely.
- Parse APC graphics controls incrementally with strict byte, parameter,
  dimension, decode, image, placement, and reply bounds; malformed or unsupported
  forms must recover without displaying payload bytes as terminal text.
- Keep encoded payload accumulation and image decode outside the UI isolate,
  publish immutable bounded image resources/placements to the existing terminal
  state and renderer boundary, and preserve single-writer/session ownership.
- Implement documented placement, virtual placement if required by pinned
  semantics, z-order relative to text, scroll attachment, erase/delete, resize,
  primary/alternate-screen, and reset behavior for static images.
- Render accepted static images through the ordinary Metal product path and
  verify exact protocol replies, frame acceptance, backpressure, and teardown in
  Developer JIT and Release AOT.

## Out of scope

- Image animation, frame composition/timing, and general resource eviction,
  which belong to the next ordered roadmap item.
- Sixel, iTerm2 inline images, arbitrary network fetches, or decoding file paths
  not explicitly authorized by the product policy.
- Expanding native platform source ownership or decoding images on the AppKit/UI
  event path.
- Desktop notification, progress, semantic prompt, OSC 52 UI, or later Phase 9
  tasks.

## Dependencies and initial facts

- The terminal parser already recognizes bounded APC strings, and parser actions
  flow into a single session-owned `TerminalScreenSet`; exact current handling
  and limits must be verified before design is fixed.
- `TerminalLiveMetalSurface` already consumes immutable grid/palette/glyph
  presentation packets with generation and one-in-flight ownership; image
  resources must extend that contract rather than create a second UI mutation
  path.
- The runtime worker and isolate transport already own bounded heavy work for
  other product resources; suitability for image decode and cancellation must be
  established from code and tests, not assumed.
- CAP-11 names fixed Ghostty `graphics*.zig` and renderer image sources as parity
  evidence. Exact commits, source hashes, documented Kitty cases, and current
  compatibility inventory/application gaps remain to be identified.

## Completion conditions

- Every implemented selector and parameter has an immutable protocol source,
  explicit product authority, exact success/error reply behavior, and all-chunk
  parser coverage; every excluded form fails closed and is documented.
- Encoded/decoded bytes, dimensions, pixel count, image count, placement count,
  reply length, in-flight decode work, and isolate messages have enforced upper
  bounds with overflow-safe arithmetic.
- Static image transmit/storage/placement/z-index/scroll/erase/reset semantics
  are deterministic across primary/alternate screen changes, resize/reflow, and
  malformed/cancelled transfers without corrupting text/grid state.
- Decode does not run on the UI isolate; stale/late results cannot resurrect
  deleted sessions, images, placements, surfaces, or native handles.
- Ordinary Metal product rendering accepts the documented static image cases in
  both M1 runtimes, while legacy text rendering and synchronized output do not
  regress.
- Focused tests, immutable compatibility evidence, formatter/analyzer, complete
  normal gate, source/bundle audits, diff review, documentation, ROADMAP closure,
  and a standalone completion commit all pass.

## Verification plan

- Protocol unit/property tests covering whole input, every single split,
  bytewise parsing, parameter order/defaults, base64/compression/format limits,
  multipart transfer, replies, recovery, and unsupported transports.
- State tests for IDs, replacement, placement, z-index, scrolling, erase/delete,
  resize, alternate screen, RIS, and deterministic bounded snapshots.
- Decode-worker tests for cancellation, malformed content, oversized metadata,
  queue saturation, stale generations, and teardown.
- Renderer/reference tests for clipping, cell anchoring, below/above-text order,
  damage, scale, and stable resources, plus real PTY/Metal product acceptance in
  Developer JIT and Release AOT.
- Compatibility inventory/application replay, `CI=true make test`, Dart-only
  source and bundle audits, `git diff --check`, and staged-scope review.

## Investigation log

- 2026-09-11: commit `9d28881` (`Accept appearance and extended reports in real
  sessions`) completed the preceding roadmap item. ROADMAP, README,
  FEATURE_MATRIX, the completed task memo, and the clean worktree were reread.
  The first unchecked item is Kitty graphics parse/storage/placement/render;
  animation/eviction and later protocol work must not start before it closes.
- 2026-09-11: the official Kitty v0.48.2 graphics specification is fixed at
  `docs/graphics-protocol.rst`, 59,715 bytes, SHA-256
  `f575c1644fd4242a10e8c0d4d784f8cc8d8445f1bad3f3a87e6c3f51ad56e364`.
  It defines `APC G<keys>;<base64> ST`, direct multipart payload chunks of at
  most 4,096 base64 bytes, 24-bit RGB/32-bit RGBA/PNG, optional zlib, exact
  `i`/`I`/`p` replies and quiet modes, cursor-anchored placements, source/dest
  rectangles, z-order, deletion, scroll/margin clipping, screen clear/reset,
  and separate animation/quota semantics. The immutable source is
  `https://raw.githubusercontent.com/kovidgoyal/kitty/v0.48.2/docs/graphics-protocol.rst`.
- 2026-09-11: fixed Ghostty parity at commit
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`. Relevant exact artifacts are
  `graphics.zig` (1,446 bytes,
  `4a8853a61c8e03b4832802d5f79bd75d8704dd6d7775c88e42ab7b7240bc249d`),
  `graphics_command.zig` (59,818 bytes,
  `72d96e07ff675af5b77651a6718571688604e089525694979c797420ada19051`),
  `graphics_exec.zig` (121,582 bytes,
  `617587c5edd81699029ae726436abf01a2852ed06598fea8ad4456a1bb99e8e2`),
  `graphics_image.zig` (62,395 bytes,
  `b8c2071d24ca11fa077b5e3eb6bf09990257424428ce61a3d6c0d12e958d7d84`),
  `graphics_storage.zig` (183,116 bytes,
  `a2c29c02531f00b939485a9e45eeb8198d55648f116282c31e37bed84677328d`),
  and `renderer/image.zig` (55,221 bytes,
  `96562bf9b0a6a4fd2104586076768a7d15db34957cffbb0417b78371658fb3ad`).
  These are parity/reference evidence only; no Zig/native implementation is
  copied or linked.
- 2026-09-11: one initial GitHub tree request left its `?recursive=1` URL
  unquoted, so zsh treated it as a glob and rejected it before network access.
  The quoted immutable URL succeeded. A later stdout request returned the full
  1.1 MB tree but exceeded the tool display budget; the same response was saved
  to an explicit temporary file and queried only for relevant paths. Neither
  failed attempt changed repository files.
- 2026-09-11: the current VT parser copies complete control strings into one
  fixed buffer. Generic OSC/DCS/SOS/PM/APC payloads are capped at 4,096 bytes,
  and APC is currently a bounded safe-ignore family. Kitty permits a 4,096-byte
  base64 chunk in addition to its control header, so the existing global cap is
  too small while raising it globally would weaken the documented OSC 52
  parser boundary. The grammar child will add a distinct bounded APC allowance,
  retain the 4,096-byte graphics data-chunk cap, and leave OSC/DCS limits
  unchanged.
- 2026-09-11: terminal state already exposes stable logical anchors containing
  screen kind, logical-line ID/epoch, and cell offset. They resolve across
  primary scrollback and reflow and fail when history is evicted, so placements
  can reuse that authority instead of adding raw row pointers or copying text.
  Primary and alternate screens already have independent state/reset paths.
- 2026-09-11: the native Metal ABI has bounded alpha/color atlas pages and
  ordered instances but no independent image texture API. Static images can be
  tiled into bounded color-atlas entries and ordered within the existing
  color-glyph layer before or after text; image cache keys, decoded storage, and
  placement state must remain distinct from glyph identity. The special Kitty
  band below `INT32_MIN/2`, which is under non-default cell backgrounds, cannot
  be represented by the current ABI and will be an explicit, tested unsupported
  z band unless a repository-owned API can express it without changing the
  adjacent `dart_appkit` repository.
- 2026-09-11: ADR-002 requires heavy decode outside the AppKit/UI root and
  copied, versioned, bounded worker frames with generation/operation identity.
  The ordinary product already owns one supervised official-Dart runtime worker
  with a 64-request cap and 1 MiB fixed frames. The decode child will extend
  that typed worker contract rather than create an in-process isolate or invoke
  native ImageIO. APC base64, zlib, and PNG decode occur in the worker; stale
  results are guarded by session/image generations. Direct transport is the
  only initially admitted medium because it works locally and through SSH and
  does not grant terminal output filesystem/shared-memory authority. File,
  temporary-file, and shared-memory probes receive bounded explicit errors.
- 2026-09-11: ADR-004 requires synchronous-copy Metal submission, resource
  generations, pins through native completion, newest-frame backpressure, and
  no retained Dart pointer. Image atlas entries will use the same submission
  lifetime and ordinary pane scheduler. Decoded image storage uses a fixed
  reject-on-cap policy in this parent; replacement/priority eviction and
  animation timing remain the next ordered roadmap item.
- 2026-09-11: this parent crosses protocol, process IPC, terminal/history, and
  GPU layers and cannot be reviewed safely as one change. It is therefore split
  into four ordered children in ROADMAP before implementation. Each child has a
  standalone completion gate/commit, and no animation or eviction behavior is
  pulled forward.
- 2026-09-11: the grammar child fixes one APC payload at 4,610 bytes: one `G`
  byte, at most 512 control bytes, one separator, and at most 4,096 encoded
  data bytes. `VtParserLimits.maxApplicationProgramCommandBytes` is independent
  from `maxStringBytes`, so OSC/DCS/SOS/PM remain at the existing 4,096-byte
  product boundary. The command parser accepts unsigned 32-bit and signed
  32-bit extrema without relying on the CSI numeric limit, rejects overflow and
  empty/malformed pairs, ignores unknown single-letter keys, and uses the last
  value for repeated known keys to match the fixed Ghostty parser behavior.
  Character-valued fields and the Kitty-defined binary/quiet domains are
  checked separately from later image-semantic validation. Known keys that do
  not apply to the selected action are ignored, matching the fixed Ghostty
  action-union parser rather than rejecting extensible clients for irrelevant
  metadata.
- 2026-09-11: parser trace and product parser-corpus fixtures now carry the APC
  limit explicitly beside the generic string limit. This preserves exact
  reproduction when a caller chooses a smaller APC cap; the bounded-recovery
  corpus uses 16 while ordinary product cases use 4,610. The compatibility
  APC record remains safe-ignore until the storage child connects commands to
  session semantics, so the inventory does not overstate product support.
- 2026-09-11: the first focused `dart analyze` attempt followed a successful
  format but failed before analysis because Dart tried to update
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json`, outside the
  writable workspace. No source diagnostic was produced. Subsequent Dart gates
  use Dart's supported top-level `--suppress-analytics` option or the
  repository-standard suppressed Make gates.
- 2026-09-11: `dart --suppress-analytics format` completed, but the first
  focused grammar test did not reach Dart test code because the package build
  hook tried to create Clang/Metal module-cache files below the sandbox-external
  `/Users/remi/.cache/clang`. The failure is environmental, with no repository
  mutation from the hook; focused retries use a task-specific writable module
  cache under `/private/tmp`.
- 2026-09-11: setting `CLANG_MODULE_CACHE_PATH` and `XDG_CACHE_HOME` did not
  redirect the Metal build hook's explicitly selected user cache. An approved
  focused run with ordinary host cache permission then passed. The first
  `make compatibility-inventory` attempt likewise stopped after dependency
  resolution on the sandbox-external Dart telemetry timestamp because Make's
  `DART` executable did not include the top-level suppression flag. Generator
  retries pass `DART='dart --suppress-analytics'` explicitly.
- 2026-09-11: three parallel focused parser/trace/inventory test attempts also
  stopped in the same pre-test Metal module-cache hook under sandboxed access.
  This confirms the hook recreates or updates its cache on each package run;
  these attempts produced no Dart assertions. They are rerun with the same
  narrowly approved ordinary cache permission used by the grammar test.
- 2026-09-11: full Dart formatting checked 246 files and changed only the two
  newly touched parser tests. The chained trace-regeneration/analyzer command
  then stopped at trace generation on the same pre-execution Metal cache
  denial, so the analyzer portion did not run. Trace generation and analysis
  are repeated with the already identified cache permission boundary.
- 2026-09-11: the first source regeneration wrote the deterministic inventory
  but the summary validator rejected its 19 pins because the Phase 6 schema
  retained a 16-pin collection ceiling. The format already permits 4,096
  records and 64 MiB source artifacts; the collection ceiling is raised to a
  still-fixed 32 so the seven exact graphics sources fit without dropping
  earlier evidence. Regeneration must complete before the written inventory is
  accepted or committed.

## Ordered subtasks

1. **Immutable source pins, bounded APC grammar, and replies.** Add the official
   Kitty and fixed Ghostty artifacts to the source inventory, introduce a
   Kitty-specific APC byte allowance without changing OSC/DCS limits, and parse
   the complete static command/control grammar into immutable typed values.
   Implement a bounded printable response encoder and exact parser/reply tests
   for defaults, all integer boundaries, duplicate/unknown/malformed keys,
   quiet policy, whole/every-split/bytewise input, cancellation, and recovery.
   Complete when the isolated grammar is source-pinned, formatted/analyzed, and
   the normal compatibility freshness chain remains internally consistent.
2. **Process-worker direct decode and bounded static image storage.** Extend the
   supervised official-Dart worker protocol with typed, generation-safe image
   decode requests/results; support direct multipart base64 for RGB, RGBA, PNG,
   and optional zlib under strict encoded/pixel/dimension/storage/work caps.
   Add per-screen image IDs/numbers, replacement, pending-transfer abort, query,
   quiet/error replies, reject-on-cap storage, stale completion, worker failure,
   and teardown. Explicitly reject file, temporary-file, shared-memory, and
   animation actions. Complete when no decode runs on the UI root and focused
   worker/session tests prove FIFO reply/state behavior and clean recovery.
   This child is itself split before implementation because pure-Dart image
   decode/IPC and session-owned protocol state have independent failure and
   review boundaries:
   1. **Typed worker decode.** Generalize lifecycle requests to copied bounded
      payload replies while preserving the existing signed-int traffic API;
      add a versioned image subprotocol and worker-only strict base64, bounded
      RFC 1950 zlib, raw RGB/RGBA, and non-interlaced 8-bit PNG decode to
      canonical RGBA. Enforce request/response, encoded, decompressed,
      dimension, pixel, PNG chunk, and CRC bounds. Complete with codec/decode,
      process generation, malformed input, backpressure, late result, and
      teardown tests, plus the normal gate and a standalone commit.
   2. **Session storage and FIFO semantics.** Add independent bounded primary
      and alternate image stores, generation-safe ID/number replacement, and a
      session controller that sends every direct multipart chunk to the worker
      instead of accumulating/decompressing on the UI root. Serialize graphics
      commands and later ordinary replies, enforce command/work/storage caps,
      abort partial transfers on delete/restart/dispose, publish exact query/
      success/error replies, and ignore stale completions. Explicitly reject
      local media and animation actions. Complete with fake-PTY/real-worker
      tests for all state/reply/failure/teardown transitions, then close the
      storage child in a second standalone commit.
3. **Placement, deletion, z-index, scrolling, screen semantics, and reference
   projection.** Reuse stable logical anchors for static placements; implement
   crop/offset/cell sizing, cursor movement, IDs, supported z ordering, clear/
   delete selectors, primary/alternate/RIS behavior, scrollback/reflow/eviction
   invalidation, and immutable viewport image projection. Add a CPU reference
   compositor/golden for alpha blending and clipping. Complete when tests cover
   all state transitions and unsupported virtual/relative/extreme-z behavior is
   exact and documented without implementing animation/resource eviction.
4. **Metal product acceptance and parent closure.** Add generation/pin-safe
   bounded color-atlas tiles to ordinary pane composition, preserving text,
   synchronized output, scale/rebuild, backpressure, and failure recovery.
   Exercise query, multipart PNG/RGBA, placement, below/above-text z order,
   scroll/erase/delete, and cleanup through real zsh PTYs and accepted Metal
   frames in Developer JIT and Release AOT. Refresh compatibility/public docs,
   run all normal/source/bundle gates, and close the parent only if all pass.

The placement child is split into three ordered review units before its
implementation because protocol mutation, terminal-history lifecycle, and
pixel compositing have independent invariants and failure surfaces:

1. **Bounded placement state and actions.** Add immutable per-screen static
   placements tied to image generations and stable logical anchors, a separate
   placement cap, explicit/anonymous placement identity and replacement,
   transmit-and-place, all non-animation delete selectors, crop/offset/grid
   sizing, bounded cursor movement, supported z ordering, and exact replies.
   Reject virtual, relative, invalid geometry, and the under-cell-background
   extreme-z band explicitly. Complete with store/controller/fake-PTY tests and
   a standalone commit.
2. **Terminal lifecycle and viewport projection.** Make full-screen/region
   scroll, scrollback pruning, reflow, clear-screen, alternate 1049, RIS, and
   teardown update placements without changing other erase behavior. Resolve
   stable anchors to copied visible placement/image snapshots with deterministic
   clipping and generation checks. Complete with history/viewport state tests
   and a standalone commit.
3. **CPU reference compositor and golden.** Scale and crop projected RGBA into
   logical pixels, blend stable z/image/placement order below or above text,
   clip at cell/viewport boundaries, and extend the deterministic 1x/2x oracle.
   Complete with pixel-exact golden/failure tests, the normal gate, and a
   standalone commit that closes the placement child. Metal atlas/product work
   remains the following roadmap child.

Dependencies are strict: storage consumes the typed grammar, placement consumes
decoded generation-owned images, and Metal consumes immutable placements. The
next roadmap item may replace reject-on-cap with eviction and add animation only
after this parent is committed.

## Verification results

- Focused Kitty grammar test: passed after granting the package hook its normal
  Clang module-cache write.
- Focused VT parser, parser trace, and compatibility inventory tests: passed
  with the same build-hook cache permission.
- Source inventory and generated support summary: regenerated successfully at
  19 immutable source pins and 270 compatibility records.
- First complete `CI=true DART_SUPPRESS_ANALYTICS=true make test`: reached the
  compatibility regression-coverage freshness check, which correctly rejected
  its baseline report after the parser trace gained the explicit APC limit.
  All earlier generators/checks passed. The reviewed report is regenerated and
  the complete gate is rerun; this is a freshness failure, not a behavior-test
  failure.
- 2026-09-11: invoking the regression-coverage generator directly still
  rejected the stale reviewed differential baseline because coverage embeds
  that baseline's verified hashes. The correct dependency order is to
  regenerate the local reviewed differential corpus report/observations first,
  then regenerate coverage; no coverage file was accepted from the failed
  attempt.
- 2026-09-11: after ordered baseline/coverage regeneration, the second complete
  gate passed every freshness, differential, application, terminfo, and shell
  integration check. Its format stage then found two style changes in the
  grammar source/test made after the earlier format pass and returned nonzero.
  No analyzer or test runner executed in that attempt.
- 2026-09-11: the immediate rerun reported the same two files because the Make
  gate uses `dart format --output=none --set-exit-if-changed`: it reports the
  required rewrite but deliberately does not persist it. The earlier note's
  claim that the gate rewrote the files was incorrect. An explicit formatter
  invocation is required before the next gate.
- Final explicit formatter check: 248 Dart files, zero changes.
- Final `dart --suppress-analytics analyze`: passed with no issues.
- Final focused Kitty grammar, VT parser, parser trace, product parser corpus,
  and compatibility inventory suites: passed.
- Final `CI=true DART_SUPPRESS_ANALYTICS=true make test`: passed every generated
  freshness, compatibility, differential, application, terminfo, shell
  integration, formatting, analysis, and Dart/native-hook test stage;
  `dart_terminal tests passed`.
- `git diff --check`: passed. Review confirmed generated differential changes
  contain only hashes affected by the source inventory and explicit trace
  limit, with no baseline observation drift.
- The first explicit staging attempt was denied while creating `.git/index.lock`
  under the managed repository metadata boundary. No index entry changed; the
  identical scoped file list is staged with repository-metadata permission.
- 2026-09-11: grammar child completed in commit `e376ea9` (`Define bounded
  Kitty graphics command grammar`). ROADMAP, README, FEATURE_MATRIX, this memo,
  and the clean worktree were reread. The first unchecked item is process-worker
  direct decode and bounded static image storage. This child owns worker IPC,
  multipart/static decode, per-screen image identity/storage, query/reply FIFO,
  rejection policy, cancellation, and teardown only; placement projection,
  Metal, animation, and eviction remain later ordered work.
- 2026-09-11: the existing worker frame is versioned, generation/operation
  addressed, copied, and capped at 1 MiB, while the coordinator stores only
  `Completer<int>` and validates every response as an 8-byte integer. The worker
  loop is currently colocated in `runtime_lifecycle.dart`, so importing the
  coordinator into the AppKit root also compiles worker-only behavior. The
  typed-decode unit will generalize the coordinator to bounded byte payloads
  (retaining the integer wrapper), move the child loop to a worker-only source,
  and keep all base64/zlib/PNG routines reachable only from the helper
  entrypoint.
- 2026-09-11: canonical static output is RGBA8 with a per-image ceiling of
  262,144 pixels / 1 MiB. Direct encoded input is capped at 1,398,104 bytes
  (the exact RFC 4648 expansion ceiling for 1 MiB), each APC chunk remains
  4,096 bytes, PNG dimensions are capped at 4,096 per axis, and non-interlaced
  8-bit grayscale, truecolor, indexed, grayscale-alpha, and RGBA PNG are
  admitted. The worker validates PNG structure, CRC, palette/transparency,
  filter bytes, bounded IDAT/inflated scanlines, and exact raw dimensions.
  Interlacing, higher/lower bit depths, color-management transforms, and
  unknown critical chunks fail closed.
- 2026-09-11: multipart encoded bytes are owned only by the helper. Requests
  identify pane, session generation, and transfer generation; start replaces
  an older transfer for that session, continuation must match, abort/dispose
  releases it, and every chunk gets a typed acknowledgement/result. The worker
  caps pending transfers at 64 and aggregate pending encoded bytes at 8 MiB so
  64 request slots cannot imply 64 maximum-sized image accumulators. The outer
  frame payload cap becomes 1 MiB plus a fixed 64-byte allowance, sufficient
  for one canonical RGBA response without permitting the full encoded
  accumulator in a single IPC frame.
- 2026-09-11: the first scoped worker analyzer pass found one compile-time
  issue: `dart:io`'s `ZLibDecoder` constructor is not const. Removing the
  incorrect `const` is the only correction; no behavioral test had run yet.
- 2026-09-11: the new worker decode suite passed, including real helper
  processes. A direct invocation of the pre-existing lifecycle test did not
  run because that imported suite lacked a standalone `main`; adding the same
  thin `main => runRuntimeLifecycleTests` entrypoint used by other suites makes
  the focused regression independently executable without changing assertions.
- 2026-09-11: after adding configurable bounded-service caps and an outer
  coordinator payload preflight, scoped formatting changed only the image
  worker test, scoped analysis reported no issues, and both the image-worker
  and lifecycle focused suites passed. The real-worker test proves an
  oversized request is rejected before IPC and that the same worker remains
  usable for legacy integer traffic.
- 2026-09-11: the first complete `make test` for this child stopped at the
  Phase 7 AppKit acceptance freshness check after all earlier generators
  passed. The acceptance artifact hashes the lifecycle source moved by this
  child, so this is an expected reviewed-artifact regeneration requirement,
  not a runtime assertion failure. Regenerate that artifact in its prescribed
  order, review the delta, and rerun the complete gate.
- 2026-09-11: Phase 7 acceptance regeneration changed only the expected SHA-256
  values for `runtime_lifecycle.dart` and its focused test; criteria, evidence
  paths, counts, and statuses did not drift. The complete gate then passed all
  freshness, compatibility, differential, application, terminfo, shell,
  formatting, analysis, native-hook, and Dart test stages with 252 formatted
  files and `dart_terminal tests passed`. `git diff --check` also passed.
  The typed worker-decode child therefore meets its isolated completion
  conditions; per-screen identity/storage and FIFO session replies remain the
  next ordered child and are deliberately not marked complete.
- 2026-09-11: typed worker decode completed in commit `d5df4c0` (`Decode
  bounded Kitty images in the runtime worker`). ROADMAP, README,
  FEATURE_MATRIX, this memo, and the clean worktree were reread. The first
  unchecked item is session storage and FIFO semantics. Its scope is
  per-screen image identity/bytes, direct multipart dispatch, strict command
  ordering, exact replies, local-media/animation rejection, stale/failure
  handling, and teardown. Placement, viewport projection, scrolling, and Metal
  remain the following roadmap child.
- 2026-09-11: the fixed Kitty specification requires direct chunks no larger
  than 4,096 bytes, all non-final chunks aligned to four base64 bytes, and only
  `m` plus optional `q` on continuation commands. A client must finish one
  multipart image before another graphics command; a query decodes and replies
  without replacing or storing data. Re-transmitting an explicit image ID
  replaces the old data (and, in the later placement child, its placements).
  Image numbers are non-unique: each transmission creates a new terminal-owned
  ID, replies with both values, and later number lookup selects the newest.
  Supplying both `i` and `I` is an error. Any delete command aborts an incomplete
  upload. These rules were rechecked against immutable Kitty v0.48.2 lines
  348–410, 451–456, 687–705, and 725–750 before fixing session state.
- 2026-09-11: the existing parser sink synchronously writes ordinary replies
  directly to the PTY and treats all APC as bounded safe-ignore. A Kitty decode
  is asynchronous, so a later ordinary reply can otherwise overtake it. The
  storage child therefore needs one session-owned bounded FIFO containing
  graphics commands and any ordinary replies that arrive behind them; ordinary
  replies retain the existing synchronous fast path when no graphics work is
  pending. The parser will recognize only a leading-`G` APC when this handler is
  installed; SOS, PM, non-Kitty APC, and parser-only sinks retain safe-ignore.
- 2026-09-11: `TerminalScreenSet` already owns independent primary/alternate
  state, but no image resource storage. Each screen will receive a bounded
  reject-on-cap image store with copied immutable RGBA, explicit-ID atomic
  replacement, monotonically generated IDs for image numbers, and newest-number
  lookup. Upload screen kind is captured on the first chunk. This child does not
  add placements, scroll anchors, or renderer projection. The shared runtime
  worker may be attached after session construction, replaced, or unavailable;
  controller epochs must ignore its stale completions and session teardown must
  clear both stores and best-effort abort the helper transfer.
- 2026-09-11: the first scoped analyzer pass over the new storage/controller
  skeleton found one nullable field-promotion error in the private queue-job
  initializer and one import-order lint in `terminal_session.dart`. Both are
  local compile/style corrections; no behavior test has run for this child yet.
- 2026-09-11: after adding the focused store/controller/session tests, the
  second scoped analyzer pass had no source errors and reported only one
  alphabetic import-order lint in the aggregate test runner. The runner import
  is reordered before executing the new behavior suite.
- 2026-09-11: the first focused storage suite passed all in-process store,
  protocol, queue, stale-worker, and fake-PTY checks, then failed while locating
  the real helper because `Platform.packageConfig` is null under this direct
  `dart run` entrypoint. No product assertion failed. Reuse the repository's
  established package-config discovery from the worker lifecycle tests instead
  of null-asserting that optional runtime value.
- 2026-09-11: the first ordered compatibility regeneration attempt used a
  uniform `--generate` flag, but these older generators do not share one CLI:
  the manifest tool interpreted that token as an output filename and the
  inventory tool rejected it with usage status 64. The accidental workspace
  file is removed, no reviewed artifact from this attempt is accepted, and the
  Makefile-defined targets/arguments are used for the retry.
- 2026-09-11: the ordered retry regenerated the implementation manifest,
  sequence/mode inventory, and generated support summary with their native
  no-argument interfaces. Independent `--check` runs for all three now pass.
  The compatibility model treats APC as a partially implemented family: a
  bounded leading-`G` Kitty command uses the execute/reply handler while every
  other APC remains bounded safe-ignore. DCS, SOS, and PM remain the three
  wholly unsupported bounded string families.
- 2026-09-11: failure coverage is extended before the complete gate to make
  the storage child's recovery contract explicit. Worker backpressure maps to
  an identified `EBUSY` reply, worker request exceptions map to `EIO`, rejected
  PTY writes are counted without publishing query data, and dispose during a
  blocked first chunk invalidates its completion, clears both screen stores,
  and sends a best-effort helper abort. A malformed leading-`G` APC is also
  rejected without poisoning the following valid command.
- 2026-09-11: the focused compatibility surface test passed. The first focused
  inventory test then found one stale exact-count assertion at the top-level
  baseline check: generated data correctly moved APC from safe-ignore to
  partial, but this assertion still expected the old 20 partial / 9 safe-ignore
  totals. It is updated to 21 / 8; selector and overall record counts do not
  change.
- 2026-09-11: the first complete gate for session storage passed its parser,
  trace, and generated configuration/keybinding checks, then stopped at the
  Phase 7 AppKit acceptance freshness check. The storage child necessarily
  changes `terminal_session.dart`, its tests, and application lifecycle wiring,
  all of which are hashed by that reviewed artifact. This is an expected stale
  evidence result rather than a behavioral failure; regenerate it using the
  Makefile-prescribed tool, review that only evidence hashes/inventory changed,
  then restart the full gate.
- 2026-09-11: Phase 7 acceptance regeneration changed only SHA-256 evidence for
  `terminal_application.dart`, `runtime_lifecycle.dart`, and
  `terminal_session.dart`. Criteria, evidence paths, status, and test inventory
  remain unchanged, so the reviewed artifact is accepted for the next gate.
- 2026-09-11: the second complete gate passed Phase 7 acceptance and the nine
  compatibility regression cases, then correctly rejected the regression-
  coverage report because its embedded implementation-manifest hash predates
  the new APC selector. Coverage also embeds the reviewed differential report,
  which in turn embeds inventory and implementation hashes, so regeneration
  must follow the established dependency order: local reviewed differential
  baseline/report first, regression coverage second. Observation semantics are
  reviewed before accepting either generated delta.
- 2026-09-11: differential baseline regeneration changed the embedded inventory
  and implementation hashes, and each of four local observation files changed
  only its provenance implementation revision; screen, cursor, mode, and reply
  observations are byte-for-byte unchanged. The first coverage regeneration
  attempt then exposed an earlier dependency: the reviewed application-matrix
  acceptance also pins the implementation manifest. Its single manifest hash
  is advanced without changing any cell, gap, status, or acceptance total. The
  differential acceptance report is regenerated from the reviewed captures
  before coverage is retried because it pins local baseline hashes.
- 2026-09-11: application acceptance revalidation passed with 8 accepted cells
  and its unchanged owned gap. Differential acceptance regeneration changed
  only the eight references to the four local baseline hashes; external probe
  hashes, classifications, differences, and acceptance totals remain unchanged
  (12 accepted, 8 agreements, 4 unavailable). Regression coverage then
  regenerated successfully, changing prerequisite hashes plus the reviewed
  inventory totals from 20/9 partial/safe-ignore and 89 selectors to 21/8 and
  90 selectors. Fix-family, case, split-run, gap, and corruption totals did not
  drift.
- 2026-09-11: the final complete `CI=true DART_SUPPRESS_ANALYTICS=true make
  test` passed every generated freshness, Phase 7 acceptance, compatibility,
  differential, application-matrix, terminfo, shell-integration, formatting,
  analyzer, native-hook, and Dart test stage. It formatted 255 Dart files with
  zero changes, reported no analyzer issues, and ended with
  `dart_terminal tests passed`. The focused storage/controller suite, focused
  compatibility surface/inventory suites, and independent generator checks
  also pass.
- 2026-09-11: commit review confirmed the controller retains no decoded or
  encoded mutable caller buffer, caps FIFO jobs/bytes independently of helper
  decode/storage caps, captures screen ownership on the first chunk, and
  invalidates worker replacement/dispose completions before publication. The
  application attaches every product session to the supervised worker either
  at construction or immediately after worker readiness. Generated changes are
  confined to the declared APC partial-support transition and evidence hashes.
  `git diff --check` passed. The session-storage/FIFO child and its
  process-worker parent are therefore complete; placement/projection remains
  the first unchecked Kitty graphics child.
- 2026-09-11: session storage/FIFO completed in commit `0dc010f` (`Store Kitty
  images through the session worker FIFO`). ROADMAP, README, FEATURE_MATRIX,
  this memo, recent commits, and the clean worktree were reread. The first
  unchecked item is placement/delete/z-index/scroll/screen semantics and
  reference projection. CAP-11 and SEC-01 still say image/storage limits are
  wholly unimplemented; update them to an exact partial state as the placement
  work documents the now-supported surface. Metal, animation, and eviction
  remain later ordered work.
- 2026-09-11: immutable Kitty v0.48.2 lines 413–499 and 671–750 confirm that
  placements reference the newest ID resolved from an ID or image number, an
  explicit `(image ID, placement ID)` replaces atomically while placement ID
  zero creates additional anonymous placements, and explicit image
  retransmission removes all prior placements. Source cropping is intersected
  with the image; destination columns/rows scale the result; negative z renders
  below text; `C=1` suppresses cursor movement. Delete selectors distinguish
  lowercase placement-only from uppercase data reclamation and any delete
  aborts a partial upload.
- 2026-09-11: immutable Kitty lines 1034–1049 require RIS and clear-screen to
  clear visible images, mode 1049 entry to clear alternate images, other text
  erases to leave graphics untouched, and scrolling/history navigation to move
  graphics with text. Margin scrolling moves only placements wholly inside the
  page region and clips them when they cross it. The pinned Ghostty source
  downloaded for review matches the recorded hashes for `graphics_exec.zig`
  and `graphics_storage.zig`; its bounded cursor behavior uses the resolved
  grid size, at most a screen of extra index operations, and then leaves the
  cursor immediately right of the placement (wrapping once when necessary).
- 2026-09-11: the existing `TerminalLogicalAnchor` can preserve a placement
  through full-screen scrollback and reflow, but its public viewport lookup is
  tied to the user's current scroll offset. Placement actions/deletion need a
  live-grid resolver independent of viewport navigation, while margin scroll
  and clipping need an explicit screen-mutation hook because a content anchor
  alone cannot represent a placement intentionally held at a physical cell.
  The existing reference renderer already owns deterministic straight-alpha
  RGBA bitmaps and bounded source bytes but has only text layers. These are
  three independent changes, so the placement child is split in ROADMAP before
  implementation into action state, lifecycle/projection, and reference-
  compositor units with separate completion commits.
- 2026-09-11: the action-state implementation keeps placement metadata beside
  its per-screen image store but stores only logical-line ID/epoch/cell offset,
  avoiding a dependency cycle with the viewport library. Each placement pins
  the decoded image resource generation; explicit nonzero placement IDs replace
  only the same image/placement pair, zero IDs receive a fresh internal
  generation, and 256 retained placements per screen is an independent hard
  ceiling. Source/destination geometry uses saturating 32-bit products,
  intersected crop rectangles, clamped first-cell offsets, nearest-integer
  aspect scaling, and no loop proportional to untrusted dimensions.
- 2026-09-11: placement anchors are captured/resolved against the live grid,
  independent of the user's scrollback viewport offset. The controller admits
  standalone put and transmit-and-place, resolves image numbers newest-first,
  moves the cursor with a screen-bounded form of the pinned Ghostty rule, and
  notifies presentation after asynchronous state publication. Virtual,
  relative, invalid cursor mode, and z below -1,073,741,824 fail explicitly;
  animation-frame delete is parsed only to return `ENOTSUP`. Static lowercase/
  uppercase delete selectors are implemented as placement-only versus unused-
  data reclamation, with zero/invalid coordinates selecting nothing.
- 2026-09-11: the first scoped analyzer pass found one missing public screen
  selector: image stores already had `kittyImagesFor(kind)`, but the controller
  also needs the corresponding primary/alternate `TerminalScreen` for a
  multipart transmit-and-place captured on a non-active screen. Add the bounded
  `screenFor(kind)` switch; no placement assertion had run yet.
- 2026-09-11: scoped analysis passed after the screen selector correction. The
  placement/store/controller focused suite passes crop/aspect calculation,
  generation-safe explicit replacement, anonymous placement cap, every one of
  the 20 non-animation lowercase/uppercase delete selectors, standalone put,
  transmit-and-place, cursor behavior, presentation notification, unsupported
  form rejection, partial-upload abort, and replacement-start teardown. The
  grammar focused suite also passes with `f/F` delete parsing, raw `C=2`
  preservation, and any nonzero `U` classified as virtual.
- 2026-09-11: FEATURE_MATRIX now reports CAP-11 and SEC-01 as exact partial
  implementations, including worker/image/placement/FIFO ceilings. The APC
  inventory text and generated human summary include static placement/delete
  while continuing to exclude lifecycle projection, Metal, virtual/relative/
  extreme-z, local media, and animation. Inventory and summary regenerated
  successfully; their classification/count totals are unchanged.
- 2026-09-11: reviewed evidence was refreshed in dependency order before the
  complete gate. Phase 7 acceptance changed only the `terminal_session.dart`
  hash. The differential baseline report changed only its inventory hash and
  no local observation file or external acceptance changed because the
  implementation selector manifest and recorded screen/reply behavior are
  unchanged. Regression coverage changed only inventory and FEATURE_MATRIX
  hashes; all case, split, gap, and corruption results remain fixed.
- 2026-09-11: `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed the full
  freshness, compatibility, differential, application, terminfo, shell,
  formatting, analysis, native-hook, and Dart test chain with 255 formatted
  files, zero changes, no analyzer issues, and `dart_terminal tests passed`.
- 2026-09-11: commit review identified that the new live-grid anchor API needed
  a direct regression with the user viewport scrolled into history. The focused
  viewport suite now proves `anchorAtActiveScreen` still resolves to live row 0
  while ordinary `anchorAt` refers to the visible history row. The focused
  suite passes; the complete gate is rerun because this assertion was added
  after the preceding pass.
- 2026-09-11: the final rerun passed the entire gate again with 255 Dart files,
  zero format changes, no analyzer findings, and `dart_terminal tests passed`.
  Final review confirms image/placement generations cannot cross-reference a
  replaced resource, delete work is bounded by at most 256 placements and 64
  images, cursor work is bounded by at most the distance to the margin plus one
  screen, and no renderer/lifecycle behavior from the next subtask was added.
  `git diff --check` passed; the bounded placement state/action subtask meets
  its completion conditions and is marked complete.
- 2026-09-11: bounded placement state/action completed in commit `b2d0e93`
  (`Place and delete bounded Kitty images`). ROADMAP, README, FEATURE_MATRIX,
  this memo, recent commits, and the clean worktree were reread immediately
  after the commit. The first unchecked item is now scroll/erase/reflow/
  alternate/RIS lifecycle semantics and immutable viewport projection. The CPU
  reference compositor remains the next ordered child and is not part of this
  change.
- 2026-09-11: lifecycle design must observe mutations inside `TerminalScreen`,
  not only parser dispatch, because scrolling also occurs through print/index,
  direct screen APIs, cursor movement, and resize paths. Stable logical anchors
  already carry placements through full-width scrolling and primary reflow;
  explicit reconciliation is required for margin scrolling, clipping, history
  eviction, clear-screen, alternate reset, and RIS. Projection will copy each
  retained RGBA resource once into an immutable snapshot, keep placements as
  generation-pinned records, and order them deterministically before any
  renderer consumes the state.
- 2026-09-11: a screen-set-owned mutation observer now brackets every internal
  up/down region scroll and observes ED/reset after mutation. A full-width,
  full-screen upward scroll with scrollback capture leaves logical anchors
  untouched, so placements enter history with their text. Other scrolls
  snapshot at most 256 placements, move only rectangles wholly contained by
  the active page region, hold intersecting/outside rectangles at their
  physical cells, and permanently clip source/destination pixels at a crossed
  top or bottom boundary. The work remains bounded by the placement ceiling;
  evicted/unresolvable anchors are pruned without prematurely reclaiming their
  reusable decoded image data.
- 2026-09-11: ED modes 0/1 and every line/character erase continue to affect
  text only. ED 2 removes placements intersecting the live screen and reclaims
  only image data made unused by that clear. A screen reset clears its entire
  store, which gives mode 1049 (and the existing mode 1047 clear-on-return)
  alternate-only cleanup; RIS clears both stores. Mode 47 switching keeps the
  independent stores. Resize reattaches observers to replacement grids,
  resolves primary placements through reflowed logical content, and prunes
  anchors lost by resize/history bounds.
- 2026-09-11: the first margin regression failed before the partial-width
  assertion because the selection-oriented logical anchor intentionally
  collapses trailing blank columns to the logical line end. Kitty placement
  instead needs the exact cursor cell even when blank. Dedicated grid-exact
  capture/resolution APIs now preserve those trailing cells while all existing
  selection/search anchor APIs retain their original normalization. The
  controller uses the exact form for place and delete, and product placement
  fails deterministically with `EAGAIN` until authoritative logical cell
  metrics exist; this prevents pre-surface margin/clipping behavior from being
  guessed from image pixels.
- 2026-09-11: `TerminalKittyViewportSnapshot` copies each visible referenced
  RGBA resource once, pins image/store/viewport generations, publishes only
  immutable lists and copy-on-access bytes, projects placements in logical
  viewport pixels (including history navigation), rejects stale resource
  generations, and sorts by z then placement generation. Clipping against the
  viewport and blending are intentionally left to the next CPU reference
  compositor child.
- 2026-09-11: scoped analysis reports no issues. The focused Kitty suite passes
  full-screen history attachment, history navigation, eviction invalidation,
  z ordering, RGBA copy isolation, vertical-margin source clipping,
  partial-width movement, partial/full display erasure, reflow, modes 47/1049,
  RIS, and missing-cell-metrics rejection. Independent viewport,
  history-reflow, reflow, screen-set, and screen regression programs also pass.
- 2026-09-11: the first complete gate stopped at the regression-coverage
  freshness check because the CAP-11 text change advanced the FEATURE_MATRIX
  hash. The prescribed generator changed only that embedded SHA-256; all nine
  fix families, nine cases, 417 split runs, the one owned gap, and zero known
  P0 silent-corruption count remained unchanged. Its independent check passes.
- 2026-09-11: after the evidence refresh,
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed every freshness,
  compatibility, differential, application, terminfo, shell, formatting,
  analyzer, native-hook, and Dart test stage. It formatted 256 Dart files with
  zero changes, reported no analyzer issues, and ended with
  `dart_terminal tests passed`. Final scope review confirms no compositor,
  Metal, animation, or eviction policy was implemented in this child, and
  `git diff --check` passes.
- 2026-09-11: lifecycle/projection completed in commit `129179c` (`Preserve
  Kitty images across screen mutations`). ROADMAP, README, FEATURE_MATRIX, this
  memo, recent commits, and the clean worktree were reread immediately after
  the commit. The first unchecked item is the CPU reference compositor/golden
  and placement-parent completion decision. The existing reference renderer
  already owns straight-alpha sRGB source-over, device-scale expansion,
  clipping, source-byte/primitive/pixel ceilings, and deterministic golden
  encoding; this child will extend that oracle with shared bitmap resources,
  nearest-neighbor source-rectangle scaling, and explicit below/above-text
  layers rather than duplicate blending code. Metal remains the next child.
- 2026-09-11: the reference renderer now has explicit `imageBelowText` and
  `imageAboveText` layers. The accepted z band maps negative images after cell
  backgrounds but before selection/text, and zero/positive images after text
  decorations but before the cursor. A shared immutable bitmap source is
  charged once against the source-byte ceiling even when referenced by
  multiple placements; each sampled placement validates its source rectangle
  and uses integer nearest-neighbor mapping before the existing straight-alpha
  sRGB source-over path. Render target, scaled pixel count, resource count,
  placement count, primitive count, and unique source bytes all fail before
  unbounded traversal or allocation.
- 2026-09-11: `TerminalKittyReferenceCompositor` converts one generation-pinned
  viewport snapshot into shared sources and sampled primitives, rejects absent
  resource generations and missing logical cell geometry, and lets the common
  renderer own viewport clipping and device-scale expansion. Its deterministic
  fixture covers a placement entering history above the viewport, right-edge
  clipping, 2-to-4 and 2-to-3 nearest scaling, opaque and half-alpha RGBA,
  negative z under a glyph, nonnegative z over a glyph, selection ordering,
  and cursor precedence.
- 2026-09-11: checked-in golden artifacts are 225 bytes at
  `test/goldens/kitty/static-placement-1x.dtgi` (SHA-256
  `19491de7707f6b61c7071ec6e0a029b202fd7a74147fc1b0d7af77d8de11bd9e`)
  and 418 bytes at `test/goldens/kitty/static-placement-2x.dtgi` (SHA-256
  `37361d055b97a4ea833315884f49e0da947d395b81076203742ab6614dffbd92`).
  A dedicated generator owns only these two paths; tests encode and compare
  without rewriting them. Scoped analysis and the reference-renderer, Kitty
  compositor, and existing golden-image focused programs pass.
- 2026-09-11: the first complete gate stopped at the expected regression-
  coverage freshness boundary after CAP-11 changed. Regeneration advanced only
  the FEATURE_MATRIX SHA-256 and preserved all nine fix families, nine cases,
  417 split runs, one owned gap, and zero known P0 silent-corruption count. The
  next full run reached `dart_terminal tests passed` but reported one analyzer
  info for the new public export ordering. Sorting the directive removed the
  finding; focused analysis then reported no issues.
- 2026-09-11: the final `CI=true DART_SUPPRESS_ANALYTICS=true make test` rerun
  passed every repository stage, formatted 260 Dart files with zero changes,
  reported no analyzer issues, and ended with `dart_terminal tests passed`.
  Review confirms the CPU compositor uses only immutable snapshot copies,
  bounds all source/placement/target work, retains exact 1x/2x golden evidence,
  and adds no native or animation behavior. `git diff --check` passes. The
  placement/reference-projection parent is complete; Metal product acceptance
  is now the first unchecked Kitty graphics child.
