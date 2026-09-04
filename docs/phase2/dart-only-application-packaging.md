# Dart-only macOS application packaging migration

- Status: renderer extraction complete; PTY capability implementation is next
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

### 2026-09-04 — architecture ownership decision

- Accepted `docs/adr/ADR-005-dart-only-macos-application-packaging.md` and
  superseded only ADR-001's package-placement decision. Its C ABI, scheduling,
  semantics, ownership, fork-safety, and shutdown rules remain unchanged.
- Selected a separate logical `dart_macos_runtime` package for the generic
  AppKit-main Dart host and builder, while keeping it in the adjacent
  `dart_appkit` repository initially for atomic host/bridge verification.
- Kept reusable AppKit primitives in `dart_appkit`, assigned PTY and terminal
  rendering to independent native capability packages, and retained all
  terminal/application/worker policy in Dart Terminal.
- Fixed a versioned native-extension service table and explicit Dart facade
  initialization instead of raw Objective-C pointers, arbitrary handle
  adoption, or product-specific runner subclasses.
- Fixed the builder's responsibility for hook execution, native-asset mapping,
  helper/resource declaration, bundle staging, architecture/rpath audit, and
  inside-out signing inputs.
- This task changes documentation and progress state only. Source behavior and
  the accepted Phase 1 runtime artifacts are unchanged.

### 2026-09-04 — reusable JIT/AOT runtime extraction

- Added and committed the separate logical `dart_macos_runtime` package in the
  adjacent `dart_appkit` repository at `649a4ac`. It owns strict application
  manifest validation, stock-Engine toolchain selection, generic host builds,
  Kernel/AOT compilation, fixed bundle assembly, declared resources, build
  metadata, ad-hoc signing, inherited stdio, and application argument/exit
  forwarding.
- Added generic Objective-C++ Developer JIT and Release AOT hosts plus
  independent `dmr_*` lifecycle and diagnostic C ABIs. No Dart Terminal
  symbol, worker argument, renderer registration, PTY operation, or product
  runner subclass appears in the new host sources.
- Diagnostics are optional manifest policy with generic metadata identity,
  owner-only atomic persistence, monotonic main-thread phases, and bounded
  previous-unclean retention. The Dart API validates ABI versions and exposes
  lifecycle, phase, and normalized bundle-resource operations.
- The first real Release AOT smoke found that an application `main` invoked by
  native name was tree-shaken. The builder now generates a private annotated
  Dart wrapper that imports and calls the ordinary application
  `main(List<String>)`. This preserves Dart-only application source and gives
  JIT/AOT one entrypoint contract.
- C11/C++20 public-header checks, lifecycle and diagnostics native tests,
  runtime package formatting/analysis/unit tests, both warning-as-error generic
  host builds, and the complete existing `dart_appkit` regression suite pass.
  The manifest-driven hello-window passes real GUI smokes in Developer JIT and
  Release AOT with Timer, menu action, deferred close, handle release, and exit
  0. The official SDK checkout remains clean at the pinned revision.

### 2026-09-04 — versioned native asset and plugin proof

- Added and committed the versioned AppKit extension service plus generic
  capability loader at adjacent `dart_appkit` commit `10f5425`.
- `da_native_extension_services_v1` exposes a size/version-prefixed plain-C
  factory registration call. The bridge validates main-thread use, UTF-8,
  duplicate/conflicting registration, factory failure, and `NSView` identity,
  while all created instances use the existing generation/domain handle and
  asynchronous shutdown rules.
- A separate `dart_appkit_example_view` dependency owns the example Objective-C
  view and Dart facade. Its Dart 3.13 build hook produces the dylib; the generic
  runtime builder stages only manifest-declared images and records their
  package/library/ABI/symbol identity. Neither generic host nor hello application
  compiles the view implementation.
- `MacosNativeCapability.load` rejects undeclared, missing, symbol-missing, and
  ABI-mismatched images, initializes once on the UI isolate, and retains the
  image for process life so provider callbacks cannot outlive their code.
- Native tests cover ABI mismatch, off-main and duplicate initialization,
  conflict, failed factory, view release, bridge shutdown, and image retention.
  Dart tests cover declaration validation, build-hook invocation and staging,
  missing images, one-time load, and generated metadata. The complete existing
  suite and legacy JIT hello remain compatible.
- Real capability-enabled hello bundles pass in Developer JIT and Release AOT,
  including dependency view initialization, Timer, menu/close events, handle
  release, exit 0, and deep signature validation. The first hook integration
  exposed toolchain-injected linker flags during compilation; only the matching
  unused-command-line diagnostic is suppressed while source warnings stay fatal.

### 2026-09-04 — terminal renderer capability extraction

- Added `dart_terminal_renderer_macos` in the adjacent reusable platform
  repository at commit `733b371`. It owns the former `TerminalMetalView` shell,
  a Dart 3.13 native build hook, an independent versioned `dtr_*` ABI, and the
  public `TerminalRendererMacos.initialize/createView` facade.
- Preserved provider identifier `dart_terminal.TerminalMetalView`, so the final
  product migration can switch from direct native registration to capability
  initialization without changing the AppKit custom-view name.
- The capability registers a retained Objective-C factory only through
  `da_native_extension_services_v1`. The Dart API receives an ordinary
  generation-checked `View`; it cannot observe an Objective-C pointer or adopt
  a native registry handle.
- Native coverage verifies ABI mismatch, wrong-thread and idempotent
  initialization, Metal device/view invariants, window attachment, independent
  handle release, stale handles, bounded AppKit teardown, zero remaining view
  instances, and loaded-image lifetime. `MTKView` cleanup is deferred until a
  bounded main-run-loop turn, which is now an explicit test condition rather
  than an invalid synchronous-deallocation assumption.
- C11/C++20 headers, warning-as-error native compilation, Dart analysis, actual
  build-hook code-asset generation, source inventory, exported symbols,
  `git diff --check`, and the complete adjacent `make test` regression pass.
  The official SDK remains clean.
- The compatibility copy under this repository's `native/macos/renderer`
  remains temporarily because task 7 performs the atomic product build switch
  and native-source removal after the PTY capability is available.
