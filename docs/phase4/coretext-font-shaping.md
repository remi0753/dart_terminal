# Phase 4 — CoreText font catalog, fallback, metrics, and shaping cache

- Status: in progress
- Date: 2026-09-05
- Scope: second Phase 4 roadmap item
- Related: ADR-001, ADR-002, ADR-004, TXT-01, TXT-03–05, TXT-07,
  TXT-09, REN-03

## Purpose

Provide a production CoreText boundary that resolves terminal font styles and
ordered fallback, exposes stable cell metrics, shapes complete UTF-8 runs with
cluster mapping, and avoids repeated native work through a bounded Dart-owned
cache. CoreText objects stay native while terminal cells, grapheme meaning,
cache policy, and frame construction stay Dart-owned.

## Background

The accepted Phase 0 spike proved that coarse CoreText calls can shape Latin,
CJK fallback, color emoji clusters, and ligatures away from the AppKit root in
well under the provisional budget. Its fixed summary and retired native source
are evidence, not a product ABI. ADR-001 requires versioned fixed-width records,
whole-run calls, explicit lengths, and no retained Dart pointer. ADR-002 assigns
font objects to a native font/render domain and prohibits shaping on the UI
root. ADR-004 requires resolved font/feature identity in cache and atlas keys.

The dependency-owned `dart_terminal_renderer_macos` package currently exposes
only an ABI-v1 paused `TerminalMetalView`. It is the reusable terminal-specific
native capability and therefore owns the new CoreText adapter. No generic
CoreText policy is added to `dart_appkit`, and the adjacent repository's own
roadmap order is intentionally not consulted per the user instruction.

## Scope

- Versioned additive native ABI for creating/releasing a font catalog and
  resolving regular, bold, italic, bold-italic, CJK, symbol, and color-emoji
  faces.
- Family and point-size validation, deterministic monospace fallback, explicit
  synthetic-style policy, native handle generation, thread-safe lookup, and
  exact-once release.
- Typographic/cell metrics including ascent, descent, leading, cell advance,
  cell height, baseline, underline position/thickness, and strike position/
  thickness with finite/range validation.
- Coarse UTF-8 shaping with bounded input/output, glyph IDs, positions,
  advances, UTF-16 cluster indices, face identity, color/missing flags, and
  explicit required-buffer reporting.
- Dart facade types with native memory owned only for a synchronous call and a
  bounded entry/byte LRU shaping cache keyed by catalog generation, style,
  feature state, and exact UTF-8 bytes.
- Native/header/Dart tests and Dart Terminal product package integration.

## Out of scope

- Glyph rasterization and monochrome/color atlas storage, which are the next
  roadmap item.
- Metal pipelines, packed frame submission, display timing, damage handling,
  view lifecycle expansion, or replacing the current product `TextView`.
- Font configuration UI, variable axes, arbitrary codepoint overrides, system
  font-change observation, synthetic box/block glyphs, or bidi terminal layout.
- Calling CoreText from AppKit event handlers or retaining a Dart pointer after
  any native call.

## Dependencies and ownership

- `dart_terminal_renderer_macos` owns native `CTFont`/descriptor/catalog data
  and releases it through generation-checked handles.
- Native lookup is synchronized but never holds its lock while shaping or
  copying caller output. A retained catalog snapshot survives the call.
- Dart owns immutable decoded results and the LRU. Native has no unbounded
  global text/run cache.
- The caller must use the API from a render/font worker domain. The facade does
  not make a UI-root call safe and documents this precondition.
- The format and cache have independent hard caps for input bytes, glyphs,
  runs/faces, output bytes, entries, and retained bytes.

## Ordered subtasks

1. **Versioned font catalog, style/fallback resolution, and cell metrics**
   - Add ABI-v2 font catalog create/release/resolve functions and fixed-size
     summary records.
   - Add the Dart facade and validate Menlo/default family, style selection,
     CJK and color emoji fallback, metrics, invalid UTF-8/arguments, stale and
     double release, and multithreaded resolve/release ownership.
   - Update the package hook/build inputs, header checks, native capability
     tests, manifest ABI, and package documentation.
   - Complete after adjacent focused/full tests, Dart Terminal full tests and
     source audit, documentation/roadmap child update, and separate commits in
     each changed repository.
2. **Bounded CoreText run shaping and Dart-owned LRU shaping cache**
   - Define/validate the packed shaping output and return complete glyph/run/
     face/cluster evidence in one synchronous bounded call.
   - Decode into immutable Dart result types and implement exact-byte cache
     keys, LRU promotion/eviction, byte accounting, generation separation, and
     disposal behavior.
   - Cover Latin, CJK, emoji ZWJ/modifier/flag, combining, wide, ligature on/off,
     malformed UTF-8, required-size retry, corrupt output decoder fixtures,
     cache hits/eviction, and repeated concurrency.
   - Complete after adjacent and product verification, Phase 4 1x/2x text
     golden preparation evidence, parent roadmap/matrix/readme updates, and
     separate commits in each changed repository.

The second subtask depends on the catalog handle and face/metric identity from
the first. Atlas work must not start until both are committed.

## Acceptance criteria

- A valid catalog exposes finite positive metrics and a cell grid aligned to
  the requested point size without inventing per-cell CoreText calls.
- Requested regular/bold/italic/bold-italic faces are explicit; unavailable
  traits follow the configured synthetic-style policy rather than silently
  changing it.
- CJK resolves away from the requested Latin monospace face and emoji resolves
  to a color-glyph-capable face on the M1/macOS baseline.
- A whole UTF-8 run returns all glyphs, positions, advances, UTF-16 cluster
  indices, run/face identities, and missing/color flags with no retained Dart
  pointer and no AppKit dependency.
- Ligature enablement is evidenced by multi-code-unit cluster spans; disabling
  it preserves legacy one-cluster-per-character behavior for the chosen test
  face.
- Every native record and output section is versioned, strictly validated, and
  bounded before allocation/use. Invalid handles and double release are
  deterministic.
- Cache entries and bytes never exceed configured caps, eviction is LRU, and a
  catalog generation or feature change cannot alias an old result.

## Verification plan

- C11/C++20 public header compile checks and Objective-C++ native tests for
  catalog, fallback, metrics, ownership, concurrency, and packed shaping.
- Dart native-asset/facade tests for decode, required-size retry, cache and
  malformed boundary behavior.
- Adjacent `make terminal-renderer-native-test`,
  `make terminal-renderer-dart-test`, and full locally available checks.
- Dart Terminal `make test`, `make runtime-source-check`, focused Release AOT
  tests, bundle ABI audit, and Developer JIT/Release AOT product integration as
  required by native ABI changes.
- Staged diff checks, both repository worktrees, and clean official SDK audit.

## Investigation log

- 2026-09-05: after commit `260d0d7`, reread the Phase 4 roadmap and confirmed
  this is the next unchecked task. Dart Terminal and adjacent `dart_appkit`
  worktrees were clean at `260d0d7` and `2592cd3` respectively.
- 2026-09-05: reviewed the renderer package public facade, ABI header,
  Objective-C implementation, native/header/Dart tests, build hook, adjacent
  Make targets, product manifest, ADR-001/002/004, Phase 0 CoreText evidence,
  and the completed custom-view boundary record.
- 2026-09-05: selected an additive ABI-v2 catalog handle plus whole-run output.
  Stateless per-call font creation would discard reusable descriptors and
  metric/face identity; a native text cache would move Dart-owned policy across
  the architecture boundary. The native catalog retains only font resources,
  while Dart owns bounded shaped-result caching.
- 2026-09-05: the first native compile rejected Foundation's `MIN`/`MAX`
  macros because the package treats GNU statement-expression extensions as
  errors. Both sites now use explicit conditional expressions, preserving the
  values without weakening warnings or build flags.
- 2026-09-05: after adding an exact-once `NativeFinalizer` fallback, analysis
  required its owner to implement Dart FFI's `Finalizable` marker. The catalog
  now declares that contract; explicit `dispose` detaches the finalizer before
  native release, while abandonment remains recoverable without a Dart
  callback or borrowed pointer.
- 2026-09-06: completed the first subtask as native ABI version 2. A catalog
  handle owns the requested and four resolved `CTFont` styles, assigns stable
  per-catalog face IDs, reports 1/64-point-rounded cell/decorations metrics,
  and resolves the effective face and glyph count for one bounded UTF-8 text
  unit. Registry lookup retains the catalog snapshot before releasing its
  lock, so a concurrent release cannot invalidate an in-flight call.
- 2026-09-06: kept the catalog API in the terminal-specific renderer package.
  Putting CoreText policy in generic `dart_appkit` would erase the established
  terminal/font ownership boundary; creating fonts separately on every call
  would also lose generation and face identity required by later cache/atlas
  keys.
- 2026-09-06: a direct execution of a separately compiled Dart executable first
  failed because `dart compile exe` does not embed the package code asset in
  that standalone invocation. Re-running the same Release AOT executable with
  the already-tested renderer dylib preloaded exercised the public facade and
  passed. Product Developer/Release bundles independently proved normal code
  asset packaging, so the failed invocation is not treated as a product fault.

## Verification results

### Font catalog subtask

- Adjacent renderer focused native tests passed: header ABI checks, version
  rejection, Menlo/default metrics and four styles, Latin/CJK/color-emoji
  resolution, malformed UTF-8, four-thread resolution, concurrent release,
  stale/double release, and a zero live-catalog count.
- Adjacent renderer Dart tests and the complete adjacent `make test` suite
  passed, including analysis, native bridge/runtime capabilities, PTY,
  examples, FFI, and the new public font facade.
- Dart Terminal `make test` and `make runtime-source-check` passed. Developer
  JIT and Release AOT bundle audits passed as Dart-only product bundles; the
  corresponding GUI integration smokes passed in 2264 ms and 1809 ms.
- The focused public-facade Release AOT executable compiled successfully and
  passed when supplied the built renderer capability through
  `DYLD_INSERT_LIBRARIES`, covering the catalog from AOT Dart through the C ABI.
- Both repository diffs passed whitespace/error checks. The official SDK
  checkout remained clean, and no generated SDK source or unrelated worktree
  change was present.
- Adjacent dependency commit: `36bcbcb Add generation-owned CoreText font
  catalogs`.
- The first ordered subtask is complete. Whole-run packed shaping and the
  Dart-owned bounded LRU remain the next unchecked child; this parent task and
  Phase 4 remain in progress.
