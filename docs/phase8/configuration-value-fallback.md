# Configuration value availability fallback

- Status: in progress
- Started: 2026-09-11 after commit `f5d3b16`
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `unavailable file option の default fallback と startup recovery`
- Feature-matrix owners: CFG-03, CFG-04, and CFG-07
- Depends on: `docs/phase8/typed-config-schema-diagnostics.md`,
  `docs/phase8/safe-configuration-reload.md`,
  `docs/phase8/product-option-families.md`, and the CoreText catalog boundary
  in the adjacent `dart_appkit` repository

## Purpose

Keep a file-backed configuration value that is syntactically valid but
unavailable in the current macOS process from preventing ordinary startup.
The unavailable winning item must produce an actionable source diagnostic,
resolve to its schema default, and leave unrelated valid settings effective.

The reported reproducer is `font-family = SF Mono Terminal`. The parser accepts
that bounded UTF-8 family name, but the renderer cannot resolve it and currently
lets a synchronous font-catalog exception escape during the first pane's native
resource creation. The app therefore exits before Settings can be used to
repair the file.

## Background and confirmed facts

- The supplied failure is
  `TerminalFontCatalogException(font catalog create, status=3)` from
  `TerminalLiveMetalSurface.attach`, followed by root exit status 70.
  `DTR_STATUS_NOT_FOUND` is ABI status 3.
- `SFMono-Terminal.ttf` and the SF Mono OTF faces on the baseline machine live
  inside Apple's Terminal.app resource directory, not any system/user font
  directory visible to other applications. Direct inspection identifies its
  family as `SF Mono Terminal`, but `NSFont fontWithName:` and
  `NSFontManager fontWithFamily:` both return nil in Dart Terminal's process.
- File syntax/type failures already add path/line/column diagnostics, omit the
  invalid assignment, and continue with a lower-precedence valid value or the
  schema default. Missing/unreadable roots likewise start with defaults.
- `font-family` currently validates only empty/control/UTF-8 bounds. Availability
  is necessarily a platform/resource question and must not add CoreText to the
  Dart-only schema parser.
- The initial interactive hierarchy creates its Metal/font resources before
  starting the first PTY. A font-catalog exception is not classified as a pane
  failure or configuration fallback and therefore tears down the root.
- `shell` and `working-directory` failures occur through the PTY start path,
  which already records a failed pane/status line; GPU, ABI, allocation, and
  internal renderer failures are not invalid configuration values and must
  remain fatal rather than being mislabeled or hidden.

## Scope

- Add a synchronous, injectable availability-validation boundary to
  `TerminalConfigLoader` without importing platform packages into
  `terminal_config.dart`.
- Evaluate only the resolved scalar winner when its source is a configuration
  file. On a reported availability issue, add one bounded error diagnostic at
  that winning source and replace its value/source with the schema default.
- Implement the macOS validator for explicit `font-family` values with the
  existing CoreText catalog. `system`/schema default must require no probe.
- Use the same validator for ordinary startup, `--show-config`, explicit
  reload, and Settings draft validation so their effective value and diagnostic
  agree.
- Prove that the exact unavailable-family class starts with the system
  monospace default, keeps unrelated settings, remains repairable in Settings,
  and behaves identically in Developer JIT and Release AOT.

## Out of scope

- Silently recovering unavailable command-line values; explicit CLI arguments
  remain fail-fast/application-owned input.
- Registering, copying, bundling, or licensing fonts from another application;
  installing fonts; a font picker; font discovery/catalog UI; or fuzzy family
  matching.
- Treating renderer/GPU/internal/resource-exhaustion failures as config errors.
- Replacing the atomic all-or-nothing reload contract. A reload candidate with
  an error diagnostic remains rejected and preserves the last-known-good
  snapshot; startup alone may begin from a recovered snapshot.
- Changing PTY failed-pane behavior or broad filesystem/executable probing in
  this task.

## Dependencies and boundaries

- The generic loader owns precedence, source locations, default replacement,
  diagnostic bounds, and deterministic invocation. It knows nothing about
  CoreText or numeric native statuses.
- The product-side macOS validator owns the `TerminalFontCatalog` probe and
  maps only `DTR_STATUS_NOT_FOUND` to an unavailable-value issue. Successful
  probes are disposed immediately; every other exception remains visible.
- Availability runs after file/include/CLI precedence has selected a scalar
  winner. It therefore performs at most one probe per effective scalar option,
  does not probe overridden file values, and does not weaken assignment/file
  bounds.
- The recovered snapshot is the single authority used by product projection,
  Settings/effective-config display, and the reload controller. Native surface
  creation must not invent a second silent fallback or report a configured
  family that it did not use.

## Completion conditions

1. An injected unavailable file winner resolves to its schema default with
   default provenance, one exact source diagnostic, and unrelated values
   unchanged. Defaults, repeated values, and command-line winners are not
   probed.
2. An unavailable macOS font family produces `CFG_UNAVAILABLE_VALUE`, resolves
   to `font-family = system`, and starts the ordinary interactive product. A
   valid explicit family and `system` retain their current behavior.
3. `--show-config`, startup stderr, Settings current/detail/diagnostics, save
   validation, and explicit reload use the same result. Invalid save/reload
   remains atomic, while a corrected family can be saved and used by later
   panes.
4. Focused tests, full format/analyze/test, source/bundle audits, and M1
   Developer JIT/Release AOT configuration acceptance pass without leaked
   font/native/PTY/worker resources.
5. README, generated reference, feature matrix, task evidence, and Phase 8
   completion state agree before this session stops.

## Ordered subtasks

1. Add the generic resolved-file-value availability contract and deterministic
   schema-default replacement to `TerminalConfigLoader`. Cover source,
   diagnostic, precedence, call count, and unaffected values without a native
   dependency, then commit.
2. Add the CoreText font availability adapter and wire one instance through
   ordinary options, early effective-config, reload, and Settings validation.
   Cover system/valid/missing/error boundaries and presenter recovery, then
   commit.
3. Extend real configuration acceptance with the reported unavailable font,
   update generated/user evidence, run all repository and arm64 packaged gates,
   mark this item and Phase 8 complete, commit, reread the roadmap, and stop
   before Phase 9.

## Validation plan

- Focused loader, product-configuration, command-line/reference, Settings, and
  native hierarchy tests.
- Exact `SF Mono Terminal` or a deterministic guaranteed-missing family at the
  real CoreText boundary, plus successful `system` and `Menlo` controls.
- `dart format --output=none --set-exit-if-changed`, `dart analyze`, full
  `make test`, Phase 7 evidence freshness, `git diff --check`, and product
  native-source audit.
- `make RUNTIME_ARCH=arm64 runtime-bundle-audit` and
  `make RUNTIME_ARCH=arm64 runtime-configuration-integration` for packaged
  Developer JIT and Release AOT on the M1 baseline.

## Findings and decisions

### 2026-09-11 — task start

- A catch-and-retry only inside `TerminalLiveMetalSurface.attach` was rejected:
  it would keep the app alive but leave effective config and Settings claiming
  the unavailable family, permit the same invalid draft to save, and retry the
  failure for every later pane.
- Platform lookup inside each schema parser was rejected because it would make
  the portable typed grammar depend on CoreText and multiply probes across
  overridden assignments.
- The selected boundary validates only the resolved winning scalar after all
  precedence has been applied. File winners can recover to a documented schema
  default; command-line winners are intentionally outside this recovery policy.
  The same loader instance is retained by startup, reload, and the Settings
  document session, preventing divergent validation semantics.

### 2026-09-11 — generic loader availability fallback

- Added `TerminalConfigValueAvailabilityValidator` and its bounded issue value
  as a platform-neutral optional loader dependency. The collector invokes it
  after include/root/CLI precedence is complete, once for each scalar whose
  effective source is a file. Schema defaults, repeatable options, and explicit
  command-line winners never cross this boundary.
- An availability issue adds `CFG_UNAVAILABLE_VALUE` at the retained effective
  option provenance and atomically replaces only that option with its schema
  default and default provenance. Other valid values and diagnostics remain
  unchanged. The existing diagnostic cap still applies, while fallback itself
  is not suppressed if the reporting cap has already been reached.
- Resolved provenance intentionally identifies the option assignment at column
  1, as already emitted by effective-config output, rather than retaining a
  second value-column location. The initial test expected column 15; correcting
  it to the established column-1 contract avoided an incompatible provenance
  change.
- The first focused test attempt was blocked before Dart execution because the
  sandbox denied Clang's Metal module-cache write. Repeating it with the
  required cache access reached the test and exposed only the column expectation
  above. After that correction, touched-file format and analysis passed with no
  issues and `dart run test/terminal_config_test.dart` exited successfully.

### Verification for ordered subtask 1

- Focused coverage proves unavailable file-family fallback to the empty/system
  schema default, exact code/path/line/default provenance, preservation of an
  unrelated file font size, one call per effective file scalar, and no probes
  for a command-line winner or repeated option.
- Full `make test`: passed. Generated configuration/action references, AppKit
  evidence, compatibility/differential/application evidence, terminfo and shell
  resource checks all passed; 245 Dart files were already formatted, analysis
  reported no issues, and the aggregate ended with `dart_terminal tests passed`.
- `git diff --check` is included in the commit review. No adjacent
  `dart_appkit` change is required by this generic subtask.

### 2026-09-11 — macOS font availability integration

- Added `TerminalMacosConfigValueAvailabilityValidator` at the product/native
  boundary. It skips the empty `system` sentinel, opens and immediately
  disposes a catalog for an explicit family, converts only renderer status 3
  (`DTR_STATUS_NOT_FOUND`) into an availability issue, and rethrows every other
  `TerminalFontCatalogException`. This keeps GPU, allocation, ABI, and internal
  failures observable instead of misclassifying them as bad configuration.
- The root entrypoint constructs one validator and supplies it to both early
  `--show-config` resolution and ordinary `TerminalOptions` resolution. The
  resulting loader is retained by the reload controller and Settings document
  session, so all four paths use the same policy and recovered snapshot.
- The first Settings integration assertion exposed that draft validation made
  a fresh overlay loader without copying the availability validator. The
  overlay loader now inherits it. Consequently an unavailable draft is
  rejected before an atomic write, while the editor continues to show the
  original file text and the running product keeps its recovered effective
  value.
- Real CoreText coverage accepts `system` and `Menlo`, while a unique missing
  family recovers only `font-family` to `system`, retains an unrelated
  `font-size`, and reports the exact file source, diagnostic code, message, and
  correction hint. Fake-boundary tests additionally prove startup/reload
  authority identity, Settings source preservation and save rejection, and
  matching `--show-config` output.

### Verification for ordered subtask 2

- Focused tests passed:
  `test/terminal_config_test.dart`,
  `test/terminal_configuration_reference_test.dart`, and
  `test/terminal_product_configuration_test.dart`.
- Touched-file analysis reported no issues. The initial sandboxed formatter
  and test attempts could not update Dart telemetry and Clang Metal module
  caches; the authorized cache-capable reruns reached the implementation. The
  only functional failure was the Settings overlay dependency omission above,
  and its rerun passed after the fix.
- `make phase7-appkit-acceptance` refreshed only the two reviewed occurrences
  of the `terminal_application.dart` source hash.
- Full `make test`: passed. All generated-reference and evidence freshness
  checks passed, 245 Dart files were formatted without changes, analysis found
  no issues, and the aggregate ended with `dart_terminal tests passed`.
- `git diff --check` passes. No adjacent `dart_appkit` modification is needed
  for this subtask.
