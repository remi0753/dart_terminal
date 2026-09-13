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

1. **Export Latest Crash Report…** performs an on-demand bounded scan. If one
   exact product report exists, a Save panel explains the sensitive content and
   asks for a local `.ips` destination. Cancellation reads/copies nothing beyond
   bounded identity discovery and writes nothing.
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
  application version, runtime mode, architecture set, relative code path,
  source SHA-256, relative dSYM path, DWARF SHA-256, UUIDs, and bounded symbol
  count. It contains no absolute paths, build host/user, timestamp, tool stderr,
  signing identity, report data, or source file names.
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
