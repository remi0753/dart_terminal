# Phase 11 — Local crash reports, hang samples, and privacy-safe diagnostics

## Purpose

Complete the first remaining Phase 11 item with a local-only incident workflow
that can find the newest Apple-generated report for this product, explicitly
capture a bounded sample of the current application, preserve release symbols
for offline analysis, and expose only content-free status through ordinary
diagnostics. Raw reports are potentially sensitive and are never read, copied,
uploaded, logged, or attached without a direct user action.

## Background and current position

- ROADMAP was reread after commits `c6e85cb` and `4bc80aa`; signed updates and
  their public action reconciliation are complete. This crash/hang item is the
  first incomplete task. Benchmark, soak, sanitizer/fuzz, parity burn-down, and
  daily-use work remain later items and cannot be implemented early.
- Phase 1 installed generic `dart_macos_runtime` Unified Logging and versioned
  `current-run.json`/`previous-unclean-run.json`. The record is local-only,
  bounded, owner-only, and correctly calls missing completion `unclean`, not a
  proven crash. It deliberately contains no stack, report discovery, sampling,
  symbolication, or consent path.
- Phase 10 added a read-only Terminal Inspector and explicit deterministic JSON
  export. Its 1 MiB allowlist excludes terminal text, commands, paths,
  environment, raw errors, and payloads. Raw crash/sample data must not be
  silently merged into that schema.
- macOS already owns fatal process reporting. Installing a product signal or
  exception handler would duplicate the OS, risk async-signal-unsafe work, and
  broaden memory capture. This task consumes Apple output after the fact and
  leaves process-fatal handling to macOS.
- `/usr/bin/sample` can capture a live process and may include thread stacks,
  binary paths, loaded images, usernames, and other context. It is a sensitive
  local artifact, not privacy-safe general telemetry.
- The current Release AOT bundle has stable Mach-O UUIDs and symbol tables for
  its host, application AOT snapshot, helper, Engine, and product capabilities.
  `dsymutil` can package those symbols even when source-line DWARF is absent;
  the AOT image already exposes Dart function symbols. No dSYM workflow or UUID
  manifest is currently published.
- `dart_appkit` and `dart_macos_runtime` are generic application/runtime
  libraries. Incident identity, Apple report policy, consent copy, product code
  inventory, UI, and privacy rules stay in `dart_terminal`. The adjacent
  repository must remain unchanged and must not receive product-specific or
  `terminal`-named code.

## Scope

- Define a bounded product-owned incident model and injected filesystem/process
  ports. Production discovery considers only regular, non-link `.ips` reports
  in the user's standard DiagnosticReports directory, with strict entry/count/
  byte bounds and exact product identity from bounded JSON metadata.
- Keep discovery explicit. A File-menu/command-palette action scans only when
  invoked, reports fixed availability/count/classification, and does not expose
  report names, paths, incident IDs, process IDs, timestamps, frames, exception
  text, or raw metadata to general diagnostics.
- Copy the latest matching Apple report only after a native Save panel clearly
  states that the selected raw report may contain stack traces, paths, process
  details, and other sensitive local information. Copy through an exclusive
  sibling temporary file, enforce a byte cap while streaming, flush, then
  replace the user-confirmed destination atomically. Preserve an existing
  destination on failure and remove incomplete temporary data.
- Add an explicit hang-sample action with a similarly explicit Save panel.
  Invoke absolute `/usr/bin/sample` directly without a shell, for only the
  current application PID, for one bounded second/one interval, into a private
  product temporary file. Validate the regular non-link bounded result and
  atomically publish only to the user-confirmed destination; delete the private
  raw temporary on success, cancellation, failure, and disposal.
- Generate offline Release AOT symbol bundles for every exact product code
  image using the system `dsymutil`; verify architecture/UUID equality with the
  source image, reject missing/extra/duplicate/case-alias entries, and publish a
  deterministic content-free manifest plus dSYM directory atomically. Symbol
  output is a release/operator artifact and is not included in the `.app`,
  update archive, runtime diagnostics, or automatic upload.
- Expose localized fixed status through shared product actions and a singleton
  read-only incident window. Actions must be single-flight, cancellation-safe,
  lifecycle-owned, and unable to route keystrokes or report/sample bytes to a
  PTY. Tests inject fixture reports, a process runner, save destinations, and a
  clock-free deterministic file boundary.
- Reconcile README, the diagnostics reference, localization/action references,
  privacy audit, FEATURE_MATRIX, and ROADMAP after Developer JIT and Release AOT
  product acceptance and the exact main gate pass.

## Out of scope

- Replacing macOS crash reporting, catching fatal signals/exceptions, writing a
  minidump from the failing process, stack-memory capture by Dart, or claiming
  an unclean prior run proves a crash.
- Background report scanning, automatic hang detection, watchdog-triggered
  sampling, automatic attachment, upload, telemetry, Sentry, analytics, remote
  symbolication, support tickets, or a server-side retention policy.
- Redacting and then presenting a raw report as complete. The product either
  shows a content-free summary or exports the unmodified sensitive local file
  after explicit destination consent; it does not make an incomplete
  pseudo-safe report.
- Accepting an arbitrary report directory, report filename, PID, sampling
  duration, executable, command, or command-line argument from product UI.
  Deterministic overrides exist only through injected test ports.
- Bundling dSYMs with the end-user app/update, storing source trees, signing
  credentials, usernames, absolute build paths, or timestamps in the symbol
  manifest.
- Long-duration hang/soak monitoring. Per user direction, duration-based tests
  remain lower priority and do not block this item; the ordered soak item is
  still later in ROADMAP.

## Threat and privacy inventory

- Apple `.ips` reports and `sample` output are untrusted, sensitive byte
  streams. They can contain terminal-related process memory, command lines,
  file paths, usernames, binary paths, system configuration, and third-party
  image names. They never enter terminal screen state, logs, machine lines,
  exceptions retained by controllers, Settings status, or the ordinary JSON
  diagnostics allowlist.
- Directory entries, JSON, symlinks, aliases, sparse/expanding files, races,
  and destination paths are attacker-controlled. Discovery opens only bounded
  regular files whose resolved parent remains the fixed directory, copies with
  size enforcement, and rechecks identity/type before publication.
- The user-selected destination is authority for one operation only. Cancel,
  stale completion, a closed window, a changed source, or a second concurrent
  request invalidates it. No remembered folder or implicit retry broadens that
  authority.
- `/usr/bin/sample` is executed as an argv vector, never through a shell. The
  PID comes from the running product, duration/interval and temporary path are
  fixed by code, stdout/stderr are bounded and reduced to classifications, and
  raw tool output is not included in an exception or log.
- Symbols are trusted release inputs only when each source image and dSYM DWARF
  object share the exact architecture/UUID set. A report can reference an
  unknown UUID; analysis must report it as unavailable rather than use symbols
  from a different build.
- No task path performs network I/O. All artifacts stay local until the user
  independently chooses how to handle an explicitly saved raw report/sample.

## User-visible and data-flow contract

The product adds two shared File actions:

1. **Export Latest Crash Report…** first opens a Save panel that explains the
   sensitive content and asks for a local `.ips` destination. Only affirmative
   **Save and Continue** consent performs the bounded exact-product scan and
   raw copy. Cancellation performs no report-directory access and writes
   nothing.
2. **Capture Hang Sample…** opens the warning/Save panel before sampling. After
   confirmation, the external system sampler captures only the current process
   for the fixed bound and publishes the raw text to that destination.

The incident window may display only fixed localized states and bounded scalar
counts: never checked, unavailable, ready, exporting, sampling, completed,
cancelled, failed, and disposed. It can mention whether a matching report
exists and whether local sampling is available, but not source/destination
paths or report/sample contents.

The existing Terminal Inspector JSON may gain an incident-status object only
if every key/value is added to the frozen privacy audit. It may contain fixed
availability/state and bounded counts, but no report/sample identifiers,
timestamps, filenames, paths, UUIDs, frame/symbol text, command data, or raw
errors. Raw artifacts remain separate user-selected files.

## Release symbol contract

- Input is one audited Release AOT `.app` with the exact runtime build manifest.
  Every manifest code path is included once; unknown executable/Mach-O
  placements and path aliases are rejected.
- Each source image is hashed and queried for an exact non-empty UUID set.
  `dsymutil` writes into a unique staging directory. Its DWARF object must be a
  regular non-link file, remain within the dSYM, have a bounded size, and expose
  exactly the same UUID/architecture pairs as its source image.
- The canonical manifest contains only format/version, bundle identifier,
  application version, runtime mode, the conservative `function-symbols`
  coverage classification, architecture set, relative code path, source
  SHA-256, relative dSYM path, DWARF SHA-256, UUIDs, and bounded symbol count.
  It contains no absolute paths, build host/user, timestamp, tool stderr,
  signing identity, report data, or source file names. The coverage value does
  not claim source-line mappings even when a future build happens to carry
  richer DWARF.
- Publication is an atomic sibling-directory replacement with last-good output
  preserved on every pre-publication failure. The product distribution archive
  and update candidate remain unchanged.

## Dependencies and risks

- Apple report JSON schemas can evolve. Parsing therefore uses a small set of
  reviewed identity fields and fails closed for an unrecognized record instead
  of guessing from filename alone. Fixture versions document every accepted
  shape.
- DiagnosticReports permissions or system privacy policy may deny discovery;
  that is a fixed `unavailable` state and does not impair normal terminal use.
- `sample` may be denied by OS task inspection policy. The operation reports a
  fixed failure and leaves no destination/temp; it never asks for elevated
  privileges or weakens system policy.
- dSYM generation from existing symbol tables can recover function names but
  may lack source-line mappings. The manifest must state a bounded coverage
  classification, and documentation must not claim line-level symbolication
  when the build contains none.
- Product acceptance cannot depend on a real crash, user DiagnosticReports, or
  GUI interaction with a personal save location. Deterministic adapters prove
  the same controller/presenter/action lifecycle; a manual checklist covers the
  visible warnings and an optional local real sample.

## Completion conditions

- Report selection rejects wrong identity, malformed/oversized JSON, links,
  path escape, too many entries, wrong extensions/types, mutation during copy,
  and oversized data; exact latest selection and atomic raw copy pass.
- Hang sampling proves exact `/usr/bin/sample` argv, current PID only,
  duration/interval bound, output validation, cancellation/timeout/failure,
  existing-destination preservation, raw-temp cleanup, and content-free errors.
- Release symbol tooling covers every exact code image, verifies source/dSYM
  UUID parity, rejects drift/faults, publishes atomically, and passes against an
  actual M1 Release AOT bundle. It does not modify the adjacent generic repo or
  distributable app.
- Shared actions/presenter, localization, privacy audit, zero PTY writes,
  single-flight/late-result rejection, close/quit cancellation, and exact
  native owner cleanup pass in unit/fake-AppKit and Developer JIT/Release AOT
  product acceptance.
- Public docs distinguish content-free diagnostics from explicitly exported
  sensitive raw artifacts and state local-only/no-upload/no-background policy.
  Formatting, analysis, generated freshness, exact main gate, matrix, ROADMAP,
  and both worktree audits pass.

## Validation plan

- Pure-Dart fixtures cover accepted Apple metadata shapes and hostile directory,
  file, JSON, size, identity, ordering, race, destination, and cleanup cases.
- An injected sampler records executable/argv and produces bounded sensitive
  sentinel bytes. Tests prove the sentinel reaches only the explicitly selected
  raw file and never status, machine lines, normal diagnostics, PTY, or errors.
- Symbol fixtures inject `dwarfdump`, `dsymutil`, hashes, staging faults, UUID
  mismatch, extra/missing images, and last-good output. A focused real-bundle
  gate verifies the M1 Release AOT output and exact manifest without retaining
  temporary artifacts in source control.
- Fake-AppKit tests exercise localized menu/palette actions, warnings, Save
  cancellation, singleton status window, responder restoration, and disposal.
  Product acceptance repeats the shared route in both runtime modes with an
  isolated fixture service and zero terminal input.
- The exact `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate, relevant
  Release AOT symbol gate, and Developer JIT/Release AOT diagnostics acceptance
  must pass before closure. Long-duration testing is skipped as authorized.

## Ordered subtasks

1. **Contract, privacy, and inventory**
   - Freeze this memo, trust/data-flow boundaries, exact outcomes, symbol/report
     ownership, validation matrix, and ordered children before executable work.
   - Completion: docs and ROADMAP agree, both worktrees are otherwise clean,
     and `git diff --check` passes in a documentation-only commit.
2. **Release symbol package**
   - Add product-owned exact code inventory, dSYM generation, UUID/hash
     verification, deterministic manifest, atomic publication, fixture/fault
     tests, and real M1 Release AOT gate.
   - Completion: no distributable bundle/generic runtime mutation, fixture and
     real-bundle gates pass, and the symbol limits are documented and committed.
3. **Local report and hang-sample service**
   - Add bounded on-demand report discovery/raw copy, fixed current-PID sample
     capture, explicit-destination transaction, injected ports, and hostile/
     cancellation/privacy tests.
   - Completion: raw sentinel isolation, atomicity, source/destination races,
     timeout/failure and cleanup all pass and are committed.
4. **Product integration and closure**
   - Add shared actions, localized consent/status UI, lifecycle wiring,
     content-free general diagnostics, fake/native product acceptance,
     public/manual docs, audits, matrix, and parent completion judgment.
   - Completion: both product runtime modes and exact main gate pass; child and
     parent are committed before benchmark work begins.

Subtasks are strictly ordered. The benchmark roadmap item cannot start until
all four incident children and this parent are complete.

## Progress log

### 2026-09-13 — Product integration task start

- After commit `325d6ea` (`Add private local incident capture`), reread
  ROADMAP, README, FEATURE_MATRIX, this contract, and the existing shared
  action/menu, diagnostics, update-window, localization, runtime-smoke, and
  product disposal paths. The first incomplete child is the product
  action/consent UI, diagnostics projection, two-runtime acceptance, and
  documentation/matrix/parent closure. Benchmark work remains out of scope
  until this child and parent are committed.
- The integration will add two stable File actions, `Export Latest Crash
  Report…` and `Capture Hang Sample…`, backed by one product-owned controller
  and one singleton read-only status window. Each action must present a native
  Save panel whose warning describes the raw sensitive content before the
  service is allowed to discover/read a report or invoke `sample`. Cancelling
  that panel is a successful no-access/no-write result.
- Retained UI and general diagnostics state is limited to fixed operation
  states and bounded counts. Raw bytes, names/paths, timestamps, process IDs,
  UUIDs, tool output, and underlying error text remain outside the controller,
  status window, diagnostics JSON, machine output, and action result. Closing,
  quitting, or disposing cancels the active operation; late completion must not
  recreate or mutate UI state. The shared dispatcher supplies an additional
  outer single-flight boundary and both native actions must restore the
  terminal responder without delivering PTY input.
- Product acceptance will inject an isolated fake incident service and Save
  destinations into the existing diagnostics suite, so both Developer JIT and
  Release AOT prove menu/palette routing, consent-before-access, atomic product
  lifecycle, singleton native ownership, cancellation, cleanup, and zero PTY
  input without scanning personal DiagnosticReports or retaining a real
  process sample. Authorized long-duration/manual sampling remains skipped and
  non-blocking.

### 2026-09-13 — Product integration implementation and runtime acceptance

- Added two localized File actions with stable IDs, no default shortcut, menu
  and Command Palette routing, dynamic availability, and exactly-once shared
  dispatch. Both warnings and the **Save and Continue** destination choice run
  before the controller may scan DiagnosticReports or invoke the sampler.
- Added a product-owned single-flight controller and singleton read-only native
  presenter. Retained state is restricted to the fixed operation enum plus
  matching, completed, and failure counts. Escape, native close, pane loss,
  quit, and disposal cancel ownership and prevent late completion from
  recreating UI; terminal focus is restored without a PTY write.
- Extended the version-1 general diagnostics `features` object with exactly four
  allowlisted incident fields: fixed state and three bounded counts. The static
  privacy audit now freezes 172 schema keys, 11 top-level entries, and seven
  source-owner boundaries. Localization/action evidence now covers 33 actions,
  15 production localization sources, 12 injection sites, four resource
  families, and 21 paired resource keys.
- The fake-AppKit acceptance covers Japanese discovery, both warning texts,
  cancellation before raw access, exact crash/sample raw publication,
  single-flight, singleton native ownership, fixed content-free rendering,
  responder restoration, disposal, late completion rejection, and sentinel
  isolation. The ordinary product diagnostics suite injects only a private
  fixture report and fake current-PID sampler, then proves menu/palette routing,
  two raw exports, two ordinary JSON exports, no private marker in UI/general
  diagnostics, zero PTY input, clean sessions, and zero final native handles.
- The first embedded Developer JIT run failed before the first copy boundary
  with fixed `copy-failed` classification. Standalone service tests passed, and
  the failure was isolated to the secure-random temporary-name dependency in
  the embedded product. Replaced it with the same process-ID/monotonic ordinal
  plus exclusive-create collision loop already used by product atomic saves.
  This retains no-clobber behavior and atomic publication without requiring
  random-device support. All 13 service groups then passed again.
- `CI=true DART_SUPPRESS_ANALYTICS=true make developer-jit-diagnostics` passed
  with two diagnostics and two incident exports in 1,813 ms. The corresponding
  `make release-aot-diagnostics` gate passed in 1,009 ms. Both use isolated raw
  sentinels; no personal Apple report was scanned and no real process sample was
  retained. Long-duration/manual sampling remains skipped as authorized.

### 2026-09-13 — Product integration final validation

- Focused validation passed: `dart analyze`, all 13 incident-service groups,
  native hierarchy/presenter lifecycle, diagnostics encoding, the 33-action
  generated reference, 15-source localization audit, and 172-key/seven-owner
  diagnostics privacy audit. `git diff --check` also passed.
- The first exact main-gate attempt correctly found the Phase 7 AppKit source
  hash evidence stale after the product/native acceptance changes. After
  regenerating it, the second attempt found the compatibility coverage report's
  README/FEATURE_MATRIX hashes stale. Regenerating that report changed only
  expected SHA-256 fields. The third exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` run passed formatting of 309
  files, all root/package analyses, native and Dart tests, all generated
  freshness checks, privacy/security gates, incident/update/symbol fault tests,
  and distribution policy tests.
- A final `make RUNTIME_ARCH=arm64 runtime-diagnostics-integration` rebuilt and
  passed the ordinary Developer JIT product in 1,754 ms and Release AOT product
  in 956 ms. Each reported two ordinary diagnostics exports, two isolated raw
  incident exports, content-free incident diagnostics, clean session teardown,
  zero PTY writes, and zero final native handles.
- The adjacent generic `dart_appkit` worktree is clean. Its tracked Dart/native
  code and tracked filenames contain no case-insensitive `terminal` match, and
  this task changed only `dart_terminal`. Public README/reference/matrix and the
  optional manual checklist now distinguish content-free diagnostics from
  sensitive explicit raw artifacts. Real crash creation, real sampling,
  24/72-hour runs, and Apple notarization were not performed and are explicitly
  non-blocking under the user's authorization.

### 2026-09-13 — Local report/sample service task start

- After commit `d7b4b40` (`Package verified release symbols`), reread ROADMAP,
  README, FEATURE_MATRIX, this task contract, the current product tree, and the
  adjacent generic worktree. The first incomplete item is now the local Apple
  report discovery/raw-copy and current-process sample service; product actions,
  AppKit consent UI, diagnostics projection, and runtime acceptance remain the
  next child and are not part of this implementation.
- Selected a non-recursive scan of the fixed DiagnosticReports directory. Only
  non-link regular `.ips` entries with a newline-terminated bounded first JSON
  record are candidates. The record must contain exact `bundleID` value
  `dev.dart-terminal` and exact `app_name` value `dart_terminal`. Other report
  formats, filenames, malformed headers, wrong identities, links, and oversized
  entries are ignored rather than guessed. Aggregate entry/header/match bounds
  fail the scan to a fixed unavailable classification.
- Latest ordering uses filesystem modification time and a deterministic internal
  filename tie-break. Neither value nor the selected path/name is exposed by the
  public selection object. Export revalidates the original size, modification,
  change time, type, mode, and product header before and after streaming; a
  changed source fails before the sibling temporary file can replace the
  explicit `.ips` destination.
- The sample adapter will invoke exactly `/usr/bin/sample <current-pid> 1 1
  -file <private-temp>` without a shell. The PID is captured from the running
  product (injectable only at the service boundary for deterministic tests),
  while executable, duration, interval, and options are fixed. The private
  workspace must be a fresh owner-only directory and is deleted after success,
  cancellation, timeout, failure, disposal, or invalid output.
- Public outcomes and errors remain content-free. Process stdout/stderr, source
  and destination names/paths, timestamps, raw header values, sample/report
  bytes, and underlying exception text are never retained in the selection,
  operation result, machine output, or error classification. Tests will inject
  the report directory, copy boundaries, process runner, current PID, temporary
  parent, and cancellation/disposal timing.

### 2026-09-13 — Local report/sample service implementation

- Added a product-owned service, Apple report-store adapter, process-runner
  port, cancellation token, and bounded public selection/outcome types. The
  production maxima are 4,096 directory entries, 16 KiB per header, 4 MiB
  aggregate header input, 256 matching reports, 64 MiB per raw artifact, and
  64 KiB aggregate output per process stream. Raw copy has a 30-second total
  deadline and sampling has a five-second process deadline around the fixed
  one-second capture. Runtime validation prevents injected limits from
  expanding these caps in Release AOT where assertions are absent.
- Discovery reads only the first newline-terminated JSON record and snapshots
  regular-file size, modification/change time, mode, and type around that read.
  It never traverses the report directory or trusts a filename for identity.
  Ready selections expose only availability and a bounded match count; the
  selected name/path/revision remains library-private, is bound to one store,
  and can authorize at most one export attempt.
- Report export accepts only an absolute `.ips` path whose immediate parent is
  a real directory and whose target is missing or regular. It reserves a unique
  sibling exclusively, streams no more than the discovered size/cap, observes
  cancellation and deadline, rechecks the source revision, validates the copied
  product header, flushes, and atomically renames. Failure preserves an existing
  destination and reports a fixed cleanup failure if sensitive staging cannot
  be removed.
- Hang capture accepts only an absolute `.sample.txt` destination, creates a
  fresh owner-only workspace beneath the configured temporary parent, and
  invokes `/usr/bin/sample` with exact argv `[current PID, 1, 1, -file,
  private path]`. The system adapter counts but never decodes or retains
  stdout/stderr. It kills on cancellation/timeout and reduces every completion
  to one fixed enum before the service validates and atomically copies the raw
  output. The created workspace is removed for every exit path; cleanup failure
  cannot be reported as success.
- Thirteen focused groups pass through both the direct Dart command and
  `make terminal-incident-service-test`. They cover exact newest selection and
  bytes, wrong bundle/process identity, extension/type/link/path escape,
  malformed/unterminated/oversized input, directory/header/match limits,
  cancellation, store and one-use selection authority, stale/mutated source,
  existing-destination preservation, unsafe destination, exact sample argv/PID,
  owner-only storage, every process disposition, missing/oversized/linked output,
  exception sentinel isolation, pre-cancellation, disposal, real subprocess
  output overflow/failure/timeout, and temporary cleanup.
- One focused iteration initially failed because the linked-output fixture
  correctly kept its deliberately external symlink target while the assertion
  incorrectly required the whole injected temporary parent to be empty. The
  corrected assertion separately proves removal of the workspace/link and
  preservation of the external target; the rerun passes. No real user crash
  report was scanned and no raw real-process sample was retained. Duration-based
  or personal-data manual testing remains deferred as authorized and does not
  block this deterministic service child.
- Final focused analysis reported no issues. The exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` gate passed formatting of 308
  files, root/package analysis with no issues, all native and generated-evidence
  gates, the 13 incident groups, security stress, updates, release symbols, and
  all existing root tests. `git diff --check` passed, and the adjacent generic
  worktree remained clean.

### 2026-09-13 — Release symbol package

- Implemented the product-owned `terminal_release_symbols` library and CLI.
  The CLI accepts only absolute application/output paths and invokes the fixed
  system tools `/usr/bin/plutil`, `/usr/bin/xcrun` (`dwarfdump` and
  `dsymutil`), `/usr/bin/shasum`, and `/usr/bin/nm` as argv vectors without a
  shell. Each process has a three-minute timeout and 4 MiB output bound; its
  stdout/stderr is reduced to a fixed result or error code rather than copied
  into the manifest or machine line.
- Validation binds the exact nine product code paths already audited by the
  update transaction, the `dev.dart-terminal` identity, semantic application
  version, Release AOT runtime manifest, and exact arm64 or arm64/x86_64
  architecture order. The application and generated dSYM trees reject links,
  unsupported nodes, case aliases, oversized inventories, missing/extra Mach-O
  images, and executable files outside the reviewed inventory.
- Every source is limited to 1 GiB; each generated dSYM tree is limited to
  50,000 entries and 2 GiB and must contain exactly one regular DWARF object.
  Source and dSYM UUID/architecture sets must be byte-for-byte equivalent.
  Symbol counting is bounded to ten million, and source/DWARF SHA-256 values
  are captured only after successful generation and UUID validation.
- The deterministic JSON manifest uses an exact content-free allowlist and a
  conservative `function-symbols` coverage classification. It contains no
  timestamp, absolute path, host/user, signing identity, raw tool output,
  incident data, or source-code path. It and the `dSYMs` directory are built in
  a random sibling staging directory, then published by directory rename. An
  existing output is restored when publication fails after its temporary move;
  no bundle/update/distribution file is mutated.
- Added focused fixture tests for thin and Universal manifests, deterministic
  encoding, exact manifest keys, complete one-time code generation, missing and
  extra images, links, input/output overlap, unknown executable placement,
  UUID mismatch, and faults immediately before publication and after moving the
  previous output. A further recovery case simulates a process interruption
  that left only `.last-good`; the next attempt restores it before doing any new
  symbol work and preserves it when that attempt fails. All eight focused
  groups passed. Initial sandboxed test and real-build attempts could not write
  the existing Clang Metal module cache; the identical commands passed in the
  normal build environment.
- `CI=true DART_SUPPRESS_ANALYTICS=true make release-aot-symbols` rebuilt and
  audited the actual M1 Release AOT app, reran all focused tests, and reported
  `TERMINAL_RELEASE_SYMBOLS code=9 architectures=1 symbols=31526`. The 3,579-byte
  manifest lists exactly the nine reviewed relative paths, one arm64 UUID set
  per source/dSYM pair, and no local absolute path. Generated symbols remain an
  ignored `build/runtime/release-symbols` artifact and are not source-controlled
  or included in the application/update.
- The adjacent generic `dart_appkit` worktree remained clean and received no
  product code. Real Developer ID/Apple notarization acceptance remains the
  separately documented low-priority follow-up authorized by the user; this
  symbol workflow neither depends on it nor represents notarization evidence.
- The first complete root gate passed every executable test but reported two
  non-failing directive-order lint infos in the newly edited export/import
  lists. After applying the analyzer's deterministic ordering, focused analysis
  reported no issues and the final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed all native/package
  tests, generated-evidence freshness, formatting of 306 files, analysis with
  no issues, security stress, and root tests including all eight symbol groups.
  `git diff --check` also passed. No duration test was needed for this bounded
  build artifact.

## Progress and findings

- 2026-09-13: after `4bc80aa`, reread ROADMAP, README, and FEATURE_MATRIX from
  clean main and adjacent worktrees. Confirmed this incident workflow as the
  first incomplete task and `DIST-04`/`SEC-05` as the primary matrix contracts.
- 2026-09-13: reviewed Phase 1 runtime metadata, generic runtime native host,
  product manifest, integration harness, Terminal Inspector/export, privacy
  audit, Release AOT build and distribution paths. The generic runtime already
  provides the necessary unclean correlation substrate; no product change in
  `dart_appkit` is needed.
- 2026-09-13: a local `dsymutil` probe against the current M1 Release AOT host
  returned the expected no-source-debug warning but produced a UUID-matched
  dSYM containing native symbols. The application AOT image produced a
  UUID-matched dSYM with Dart function symbols. This supports offline function
  symbol packaging while confirming that line-level claims must remain out of
  scope for current artifacts.
- 2026-09-13: considered an in-process fatal signal handler, automatic report
  upload, background report scanning, watchdog sampling, silently embedding raw
  bytes in Terminal Inspector JSON, and trusting report filenames. Rejected
  them for async-signal safety, privacy, authority, schema-evolution, and
  least-surprise reasons. Selected explicit local export plus a separate
  content-free status boundary.
- 2026-09-13: the contract link resolves, `git diff --check` passes, and both
  worktrees contain no unrelated changes. This documentation-only child changes
  no executable path and needs no duration test. The release symbol package is
  the next ordered child.
