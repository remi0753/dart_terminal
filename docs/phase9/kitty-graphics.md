# Phase 9 — Kitty graphics parse, storage, placement, and render

## Task identity

- Date started: 2026-09-11
- Scope: fourth Phase 9 roadmap item
- Feature-matrix owner: CAP-11
- Status: grammar child complete; storage child pending
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
