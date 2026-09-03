# macOS unified logging and local crash metadata

- Status: in progress
- Started: 2026-09-04
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, `FEATURE_MATRIX.md` RT-01/RT-03/REL-01/DIST-04,
  ADR-001, ADR-002, and `docs/phase1/vm-isolate-lifecycle-contract.md`

## Purpose

Add a privacy-bounded diagnostic substrate to both product runtime modes. The
native host must emit filterable lifecycle/failure events through macOS Unified
Logging and atomically maintain enough local run metadata to distinguish a
clean exit, a classified product failure, and a previous process that ended
without recording termination.

## Background

The product already classifies usage, input, root/host fatal, worker-contained,
and forced-shutdown outcomes and preserves bounded worker stderr. Its native
hosts still write only to process stdout/stderr, so a normal GUI launch has no
stable subsystem/category for Console or `log` filtering. An abrupt UI-process
crash or kill also leaves no product-owned, privacy-safe correlation record.

The pinned Ghostty comparison implements local-only crash storage and does not
automatically upload reports. Its full crash reports can contain thread stack
memory and therefore sensitive data. Dart Terminal does not yet have the
release symbols, consent UI, diagnostics inspector, retention policy UI, or
distribution workflow required for such a reporter. Apple already supplies
the operating-system crash report; this Phase 1 task should add deterministic
breadcrumbs and metadata, not a competing signal/minidump implementation.

## Scope

- Use public `os_log` APIs with a fixed reverse-DNS subsystem and bounded,
  low-cardinality runtime/crash categories.
- Emit only fixed event names and allowlisted scalar product metadata. Dynamic
  terminal content, paths, arguments, environment, command output, worker
  stderr, and exception text are excluded.
- Maintain an atomic `current-run.json` record with schema/version, random
  launch ID, bundle/version/runtime/architecture/SDK revision, PID, UTC
  timestamps, lifecycle phase, outcome, and numeric exit status.
- Detect a prior compatible record whose outcome is still `running` on the
  next launch and atomically preserve one `previous-unclean-run.json` record.
  This means only that termination was not recorded; it must not claim that a
  crash rather than kill, power loss, or storage failure occurred.
- Store production metadata below the user's Application Support directory,
  enforce owner-only directory/file modes, retain at most the current and one
  previous unclean record, and never upload it.
- Add a gated absolute-directory override used only by deterministic tests.
  Production persistence remains best-effort so an unavailable diagnostics
  directory cannot prevent the terminal from starting; the test gate is
  strict so integration evidence cannot silently disappear.
- Add a fixed phase-only C ABI used by the bundled Dart root. The native host
  owns initialization/final outcome; Dart can report only known lifecycle
  phases and cannot inject free-form log or metadata text.
- Wire identical behavior into M1/arm64 Developer JIT and Release AOT and
  validate metadata for normal, usage/fatal, lifecycle, and traffic launches.

## Out of scope

- Minidumps, signal/exception handlers, stack/thread/register/memory capture,
  symbolication, dSYM processing, hang sampling, or replacement of Apple's
  crash reports.
- Network transport, Sentry or another telemetry SDK, automatic/manual upload,
  analytics, device/user identifiers, terminal/session contents, cwd, argv,
  environment variables, filenames, or worker diagnostic text.
- User-facing diagnostics bundle/inspector, consent controls, configurable
  retention, or complete crash/update/clipboard/shell-integration privacy UI;
  those remain Phase 10/11 work.
- The following resource-leak and shutdown fault-injection roadmap item.
- x86_64, Rosetta, Universal, and Intel-native follow-up validation.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `2239ac2`; the adjacent
  `dart_appkit` and official Dart Engine SDK worktrees were also clean.
- `README.md`, the complete roadmap and feature matrix, ADR-001/002, existing
  lifecycle records, both host implementations, build/fingerprint/audit
  sources, and the shared integration harness were reviewed before changes.
- Both product hosts already converge on
  `RuntimeLifecycleCompleteApplicationTermination`. Nonzero application
  outcomes call `_Exit` there, so diagnostics must finalize before that point;
  relying only on stack unwinding after `[NSApplication run]` would lose fatal
  metadata.
- The Developer host subclasses the reusable `dart_appkit` delegate while the
  Release host owns its delegate. A shared terminal-owned diagnostics object
  and C ABI can cover both without adding product policy to `dart_appkit`.
- The runtime source provenance already covers `native/macos/runtime`, but the
  Make dependency/source/format/test lists must explicitly include new native
  inputs to prevent stale host binaries and unformatted code.
- AppKit already brings Foundation into each launcher. Public Unified Logging
  is available through `<os/log.h>` and does not require a private framework or
  changed deployment target.
- The shared integration harness launches every smoke/lifecycle/traffic case
  itself. Giving every launch its own strict temporary metadata directory can
  validate real-product persistence without touching user Application Support.
- The pinned comparison's local-only policy and Apple logging/storage APIs were
  checked from primary sources:
  [Ghostty crash implementation](https://github.com/ghostty-org/ghostty/blob/d4d8f62262cb1a974a7d2470d5f79f811fab15e4/src/crash/sentry.zig),
  [Apple Logging](https://developer.apple.com/documentation/os/logging), and
  [Application Support directory](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/applicationsupportdirectory).

## Design decision

Use a process-lifetime `RuntimeDiagnosticsSession` owned by each native main.
It creates fixed runtime/crash log objects, resolves immutable bundle metadata,
installs itself before argument and host-fault handling, and writes the initial
`running` record atomically. The active session is visible to a phase-only C
entry point and to the existing native lifecycle completion boundary.

The Dart ABI accepts only a numeric enum for `root-starting`, `root-ready`,
`shutdown-started`, and `root-stopped`. The native side validates main-thread
affinity and monotonic phase progression. There is no string, path, key/value,
or arbitrary severity input. Host completion records `clean` for status zero
and `failure` plus the numeric status otherwise. If the process terminates
without completion, `outcome=running` remains and is preserved on the next
launch as `previous-unclean-run.json`.

Metadata writes use Foundation JSON serialization plus atomic replacement.
The schema and exact key set are versioned; an incompatible or malformed old
file is not promoted as unclean evidence. Persistence errors are logged with a
fixed non-sensitive event and do not change normal product control flow.

## Ordered subtasks

### 1. Native logger and metadata contract

- Implement the native session, fixed event taxonomy, atomic bounded metadata
  store, previous-unclean detection, permissions, test observer, and native
  contract executable.
- Completion: valid phase/outcome transitions, malformed prior records,
  previous-unclean retention, wrong-thread/invalid/regressing phases, strict
  storage failures, privacy key allowlist, permissions, and idempotent finish
  are covered and committed before host integration.

### 2. Dart and native host integration

- Add the phase-only C ABI/Dart binding; install/finalize the shared session in
  both native hosts; include all inputs in product build, provenance, format,
  and source-check paths.
- Completion: both hosts cover early usage/input/host failures, Dart root
  phases, clean shutdown, classified fatal `_Exit`, and the same metadata
  schema without free-form Dart logging; source checks and focused host-facing
  tests pass and are committed before product acceptance.

### 3. M1 product acceptance and documentation

- Make the shared integration harness assign a strict temporary diagnostics
  directory per launch and validate the resulting record. Update current
  product, privacy, operations, and feature-status documentation.
- Completion: source/freshness checks, both arm64 builds and audits, both full
  real-GUI integration suites, clean official SDK, diff review, repository
  hygiene, documentation, and roadmap closure pass in a final commit.

Subtasks are strictly ordered. Product hosts cannot consume the native session
before its contract is committed, and roadmap completion cannot precede the
real Developer JIT and Release AOT evidence.

## Acceptance criteria

1. Logs use a stable reverse-DNS subsystem and fixed categories/events in both
   runtime modes through public macOS Unified Logging.
2. No log or metadata field accepts terminal text, argv, cwd, environment,
   filenames, worker stderr, exception messages, stack memory, or arbitrary
   Dart strings.
3. Metadata is versioned, atomic, owner-only, bounded to current plus one prior
   unclean run, local-only, and uses explicit UTC timestamps and a random
   per-launch correlation ID.
4. A clean status, each classified nonzero status, and missing completion are
   distinguishable. Missing completion is called `unclean`, not proven crash.
5. Invalid/malformed old data is not trusted or promoted; disk failure does not
   block production startup, while a strict test override cannot pass without
   a valid persisted record.
6. Phase recording is main-thread-only, monotonic, enum-only, and idempotent
   finalization cannot overwrite the first outcome.
7. Initialization precedes argument/host failure gates; finalization precedes
   the existing fatal `_Exit` path and normal host return.
8. Developer JIT and Release AOT emit and persist the same schema and pass the
   same real-GUI smoke/lifecycle/traffic assertions.
9. No private Apple API, Engine modification, crash handler, network client,
   or new reusable `dart_appkit` product policy is introduced.
10. Formatting, analysis, native/Dart tests, bundle audits, M1 integrations,
    clean-SDK/freshness gates, diff review, and repository hygiene pass.

## Validation plan

- Build a focused Objective-C++ contract test for metadata transitions,
  permissions, exact schema/keys, corruption handling, previous-unclean
  retention, fixed log events, wrong-thread behavior, and idempotence.
- Compile the diagnostics header as C11 and C++20 and add the contract to
  `runtime-source-check`.
- Exercise every shared integration launch with an isolated strict directory;
  parse and validate `current-run.json` after process exit.
- Rebuild and audit both arm64 products, then run smoke, lifecycle, and traffic
  suites for Developer JIT and Release AOT.
- Run affected build-freshness/clean-SDK checks and verify Dart Terminal,
  `dart_appkit`, and the official Engine SDK worktrees after commits.

## Risks and open checks

- A normal nonzero `_Exit` bypasses destructors. The existing lifecycle
  completion function must explicitly finalize diagnostics first.
- An actual crash may interrupt an atomic write. The last complete JSON remains
  authoritative; no signal-time allocation, lock, Objective-C, or disk I/O is
  permitted.
- `outcome=running` can also result from SIGKILL, power loss, or storage failure.
  User-facing and log terminology must remain `unclean`, never assert a crash.
- Unified Logging privacy defaults can obscure dynamic values. All allowed
  values are explicitly public, bounded, and non-user content; excluded data
  must never be passed to the formatter at all.
- Integration tests must clean their temporary directory on success and
  failure and must not read or mutate the production Application Support path.

## Investigation log

### 2026-09-04 — repository, platform, and comparison review

- Confirmed this is the first unchecked roadmap item and that the next
  resource-leak/fault-injection item has not been started.
- Compared a full local minidump reporter, a signal handler that writes JSON,
  Unified Logging only, and a pre-crash run marker. Rejected the first two for
  Phase 1 because they capture sensitive memory or perform unsafe crash-time
  work and belong with the Phase 11 symbolication/privacy workflow. Unified
  logs plus a pre-written atomic run record provide the required substrate
  without claiming more evidence than is available.
- Confirmed the pinned comparison stores crash reports locally and performs no
  default network send, but its report can include stack memory. Adopted the
  local-only principle, not its Sentry/minidump dependency or report format.
- Confirmed public `os_log_create` objects are keyed by stable subsystem and
  category and should not be created dynamically per operation. Selected one
  fixed subsystem with runtime and crash categories.
- Confirmed Application Support is the appropriate production home for
  app-managed support data. Tests will use a gated absolute temporary override
  so acceptance leaves user state untouched.

### 2026-09-04 — Subtask 1 implementation start

- Added a C11/C++20 diagnostics header and terminal-owned Objective-C++ session
  with fixed `dev.dart-terminal` runtime/crash categories, phase-only C ABI,
  allowlisted metadata, owner-only storage, atomic replace, one prior-unclean
  record, and no destructor-based clean-exit claim.
- Added a native contract covering validation, main-thread affinity, phase
  monotonicity/idempotence, strict versus best-effort storage, record schema,
  permissions, previous-unclean detection, corruption handling, retention, and
  fixed log-event routing.
- The first native compile found only an Objective-C generic qualifier mismatch:
  `NSFileManager` accepts a nullable mutable-qualified dictionary pointer, while
  the local attributes variable had been declared as a pointer to `const`
  `NSDictionary`. Removed that incorrect pointee qualifier; no behavioral or
  acceptance change was needed.

### 2026-09-04 — Subtask 1 validation

- The corrected native contract passed on Apple M1/arm64. It proved exact
  schema keys and values, UUID/timestamp shape, current versus previous-unclean
  launch identity, `running`/`clean`/`failure` outcomes, numeric status,
  `0700` directory and `0600` record modes, two-record retention, and absence
  of temporary files after completed atomic writes.
- The same contract proved invalid mode/path rejection, off-main start/phase
  rejection, invalid and regressing phase rejection, duplicate phase and
  finish idempotence, strict storage failure, best-effort production storage
  failure, malformed prior JSON rejection, and preservation of earlier valid
  unclean evidence.
- A test-only observer verified that the real logging call path emits fixed
  start, phase, prior-unclean, invalid-prior, persistence-error, and finish
  event classes with the intended info/error/fault levels. Production still
  invokes `os_log`; the observer adds no alternate product behavior or dynamic
  message input.
- `runtime-source-check` passed after adding the contract: Dart format and
  analysis, clang-format, both lifecycle and diagnostics headers as C11/C++20,
  plist validation, all Dart tests, the new diagnostics contract, and the
  existing `TerminalMetalView` contract succeeded.
- Reviewed the subtask diff and confirmed the native source is not yet linked
  into either product host. That dependency remains ordered under subtask 2;
  no later roadmap functionality has been started.

### 2026-09-04 — Subtask 2 integration start

- Added a Dart binding that can report only the four numeric root lifecycle
  phases, recorded root start before option parsing, root readiness after
  worker readiness, and shutdown start/root stop around ordered cleanup.
- Installed the native session before argument parsing and host-failure gates
  in both product mains. Early return paths now finalize their classified
  status, while the shared application-termination boundary finalizes before
  its existing nonzero `_Exit`; normal return remains idempotent.
- Added the native source/header to both host dependency and compile lists.
  The first combined formatting command formatted all three Dart files but
  then the standalone Dart tool attempted to update its user-level analytics
  session timestamp outside the workspace sandbox and returned an error.
  This was a tool-side post-format write, not a source failure; subsequent Dart
  commands use the project's existing suppressed-analytics path or an approved
  workspace check.
- Updated `runtime-source-check` so its format, analyze, and test invocations
  all suppress Dart tool analytics. This makes the local gate deterministic in
  restricted environments and avoids an unrelated user-level telemetry state
  write during a privacy-sensitive diagnostics task.
- The rerun passed Dart formatting, analysis, Dart tests, plist validation,
  lifecycle and diagnostics header checks, and the diagnostics native contract.
  The pre-existing `TerminalMetalView` contract could not acquire a Metal
  device inside the restricted command sandbox (`DA_STATUS_PROVIDER_ERROR`),
  then passed unchanged when rerun in the normal macOS execution environment.
  This was an environment-access failure rather than a diagnostics regression.

### 2026-09-04 — Subtask 2 validation

- Built the arm64 Developer JIT and Release AOT application bundles against
  the pinned official Engine SDK. Both hosts compiled and linked the shared
  diagnostics implementation without warnings or errors.
- Inspected both final bundle launchers and confirmed they export
  `dt_runtime_diagnostics_abi_version` and
  `dt_runtime_diagnostics_record_phase`, so `DynamicLibrary.process()` can
  resolve the same fixed C ABI in both runtime modes.
- Re-ran the complete `runtime-source-check` gate in the normal macOS
  environment; formatting, analysis, Dart tests, both C/C++ header modes,
  plist validation, diagnostics native tests, and `TerminalMetalView` native
  tests all passed together.
- Reviewed every host return and application-termination path. Failures before
  Dart startup finish directly; Dart-initiated normal and fatal shutdowns pass
  through the shared termination boundary before a possible `_Exit`; the
  post-run finish remains intentionally idempotent.
- Subtask 2 is complete. Product-level metadata assertions, the full real-GUI
  acceptance matrix, and operator/privacy documentation remain in subtask 3.
