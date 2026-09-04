# Dart-only macOS application packaging migration

- Status: plan and acceptance contract complete; architecture ADR is next
- Started: 2026-09-04
- Primary environment: macOS 14 or later on Apple M1/arm64
- Related: `ROADMAP.md` Phase 2, `docs/adr/ADR-001-dart-native-boundary.md`,
  `docs/adr/ADR-002-isolate-thread-ownership.md`, and the adjacent
  `dart_appkit` architecture and C ABI

## Purpose

Make the checked-in Dart Terminal application and terminal core consist only
of Dart source, tests, declarative bundle metadata, and non-native resources.
All Objective-C, Objective-C++, C, C++, Metal, Dart Engine hosting, and macOS
bundle assembly must be owned by reusable dependencies and tooling. The final
`.app` remains a native macOS bundle; the boundary applies to application
source ownership rather than to the contents of the built product.

## Background

Phase 1 proved a stock Dart Engine root on the AppKit process main thread in
Developer JIT and Release AOT modes, a bounded AppKit message pump, versioned
events, generation-checked native handles, asynchronous destruction, a named
custom-view provider, a terminal-owned `TerminalMetalView` shell, official
Dart worker processes, local runtime diagnostics, resource stress, and
shutdown fault containment.

The current product build nevertheless compiles adjacent `dart_appkit`
implementation files and Dart Terminal-owned native runner, lifecycle,
diagnostics, worker-configuration, and renderer sources directly. The custom
view is registered by product-specific runner code before the Dart root starts.
This makes the repository boundary weaker than the public Dart package and C
ABI boundaries and requires every application to own native composition code.

## Scope

The migration is split into the following strictly ordered tasks.

1. Freeze this purpose, scope, order, acceptance contract, and the matching
   Phase 2 roadmap entries.
2. Accept a new ADR that assigns generic host/runtime, AppKit primitives,
   optional native capabilities, and product semantics to independent owners.
3. Extract the common Developer JIT and Release AOT host, lifecycle,
   configurable diagnostics, native-asset staging, and bundle assembly into a
   `dart_macos_runtime` package developed with `dart_appkit`.
4. Add a versioned native plugin contract and prove a dependency-owned custom
   `NSView` provider in the hello-window application without application-owned
   Objective-C++ runner code.
5. Move `TerminalMetalView` and its native contract tests into a terminal
   renderer capability package and initialize it through its Dart facade.
6. Implement the Phase 2 stable PTY ABI, safe spawn, bounded reactor, lifecycle,
   Dart facade, fake backend, and integration harness as `dart_pty_macos`.
7. Migrate Dart Terminal to the generic builder and capability packages, prove
   Developer JIT and Release AOT parity, then remove product native source and
   direct references to adjacent repository internals.

No task may start before the preceding task has passed its own validation and
has a completion commit. Compatibility shims remain until both product modes
pass against the replacement.

## Out of scope

- VT parsing, grid, scrollback, and renderer semantics scheduled for later
  phases.
- A complete terminal Metal renderer; only the already accepted view shell is
  moved in task 5.
- Phase 4 CoreText shaping, atlas management, draw submission, and shaders.
- Phase 5 production IME semantics and accessibility completion.
- x86_64, Rosetta, Universal, signing, notarization, and Intel-native follow-up
  beyond preserving their existing build contracts.
- Literal native-free `.app` output. macOS and the embedded Dart runtime still
  require Mach-O binaries, system frameworks, property lists, and signatures.

## Dependency and ownership decisions to prove

- `dart_macos_runtime` owns `NSApplication`, the process main loop, stock Dart
  Engine root hosting, bounded message scheduling, JIT/AOT bundle layouts,
  application lifecycle exit plumbing, and configurable diagnostics mechanics.
- `dart_appkit` owns reusable window, view, menu, pasteboard, screen, focus,
  lifecycle-event, and custom-view attachment primitives.
- `dart_pty_macos` owns macOS PTY/process mechanics but no terminal semantics.
- `dart_terminal_renderer_macos` owns the terminal-specific `MTKView` subclass
  and later CoreText/Metal resource mechanics, but no VT/grid semantics.
- Dart Terminal owns application policy, process-worker orchestration, pane and
  session state, terminal semantics, and user-visible diagnostics policy.
- No Dart API exposes Objective-C objects, arbitrary registry handles, or raw
  pointers that grant ownership. Native capability APIs use independently
  versioned C ABIs, opaque generation-checked handles, fixed-width wire types,
  bounded asynchronous events, and explicit shutdown contracts.

## Acceptance criteria

1. `dart_terminal` contains no product `.c`, `.cc`, `.m`, `.mm`, native header,
   or Metal shader source after task 7; historical documentation may continue
   to cite removed commits and external capability repositories.
2. Dart Terminal's build does not include files through paths inside adjacent
   repositories. It consumes public Dart packages, versioned native capability
   contracts, and the generic macOS application builder only.
3. One generic host executable shape runs both hello-window and Dart Terminal;
   product identity and resources are declarative inputs rather than compiled
   runner subclasses.
4. Developer JIT and Release AOT preserve the stock, unmodified Dart SDK and
   the AppKit-main-thread root contract.
5. A native capability can register a custom AppKit view through a versioned
   extension contract, be retained for the full lifetime of its instances, and
   shut down without exposing an Objective-C pointer to Dart.
6. The PTY capability passes safe child-path, interactive shell, resize,
   signal/job-control, ordered batching/backpressure, exit/reap, and fake-backend
   tests without blocking the AppKit main isolate.
7. Existing event compatibility, native handle churn, lifecycle/failure,
   bounded traffic, diagnostics, shutdown fault, clean-SDK, and bundle audits
   pass after the migration.

## Validation strategy

- Every reusable change first passes its package-local format, analysis, unit,
  C/C++ header, native contract, and GUI smoke tests.
- Each compatibility migration rebuilds both arm64 runtime modes rather than
  accepting cached products.
- Native extension loading is tested for ABI mismatch, duplicate initialization,
  missing asset, wrong thread, constructor failure, late event, shutdown, and
  leaked handles.
- The PTY package is tested with a fake backend and a real interactive zsh,
  including `tty`, `stty size`, signals, process groups, partial UTF-8, a 10 MiB
  burst, bounded writes, graceful close, forced close, and child reaping.
- Before each completion commit, review repository status, staged diff,
  generated artifacts, source inventories, and exact official SDK cleanliness.

## Risks

- Dart build hooks can build native code assets, but the custom AppKit host must
  explicitly integrate their outputs and native-asset mapping; the current
  direct Kernel/AOT paths do not establish this automatically.
- Dynamically loaded provider callbacks are invalid if their image unloads
  before the last view. Plugin image and callback lifetime must therefore be a
  process-lifetime or explicitly reference-counted host responsibility.
- The existing Release AOT runner contains product and generic host behavior in
  one file. Extraction must preserve teardown ordering and cannot be treated as
  a mechanical file move.
- A PTY child created after a multithreaded Dart VM starts must execute only the
  audited async-signal-safe child path before `execve`.
- Cross-repository migration can leave an apparently clean product using stale
  binaries. Fingerprints and bundle manifests must record exact dependency
  revisions and native asset identities.

## Investigation log

### 2026-09-04 — plan registration

- Reviewed the complete Dart Terminal README, roadmap, feature matrix, Phase 1
  records, boundary and ownership ADRs, current runtime/renderer sources, build
  source inventories, and the adjacent `dart_appkit` README, roadmap,
  architecture, C ABI, Dart facade, bridge, and runner boundaries.
- Confirmed the first previously unchecked item was the Phase 2 stable PTY ABI.
  This migration is inserted immediately before it because dependency-owned
  native build and packaging are prerequisites for placing that ABI outside the
  application repository.
- Confirmed the current Makefile compiles `dart_appkit` implementation files by
  internal path and also compiles Dart Terminal-owned runner, lifecycle,
  diagnostics, worker configuration, and `TerminalMetalView` sources.
- Confirmed Developer JIT and Release AOT use separate product runner
  composition and register `TerminalMetalView` from native startup code.
- Confirmed Dart 3.13.2 provides stable build hooks and link hooks, while the
  official `dart build` application bundler currently targets CLI bundles. A
  custom AppKit builder integration must therefore be proven rather than
  assumed.
- The Dart Terminal worktree was clean at `4d22570`. The adjacent `dart_appkit`
  worktree was clean at `52ddd2c` and one commit ahead of its configured
  `origin/main`.
- Added all seven ordered migration tasks immediately before the existing PTY
  implementation backlog. The purpose, scope, exclusions, dependencies,
  acceptance criteria, validation strategy, and known risks are now fixed in
  this task record.
- `git diff --check` passed for the roadmap and task-record changes. No source,
  build, or runtime behavior changed, so product tests were not required for
  this planning-only completion.
