# ADR-005: Dart-only macOS application packaging and native capabilities

- Status: Accepted for Phase 2
- Date: 2026-09-04
- Decision owners: Dart Terminal and Dart AppKit projects
- Related: `ROADMAP.md` Phase 2,
  `docs/phase2/dart-only-application-packaging.md`, ADR-001, ADR-002, and
  ADR-004
- Supersedes: ADR-001 **Package placement** only; all semantic, ABI,
  scheduling, ownership, and safety rules in ADR-001 remain active

## Context

The Phase 1 product proves that a stock Dart root can run on the AppKit process
main thread in both Developer JIT and Release AOT modes. It also proves
versioned AppKit events, generation-safe handles, asynchronous destruction,
official Dart worker processes, custom native views, diagnostics, resource
stress, and bounded shutdown fault containment.

The checked-in product is not yet isolated at a reusable package boundary. Its
Makefile compiles native implementation files from the adjacent `dart_appkit`
repository and compiles product-owned JIT/AOT runner composition, lifecycle,
diagnostics, worker-resource injection, and `TerminalMetalView` sources. A new
macOS Dart application would have to reproduce those native build and host
steps even if its application behavior were entirely Dart.

ADR-001 deliberately placed terminal-specific native adapters in Dart
Terminal. That placement was correct for proving the feasibility and ownership
contracts, but it conflicts with the new product requirement that application
repositories contain no hand-written native implementation. Moving every
native adapter into `dart_appkit` would satisfy that repository property while
creating a package that mixes AppKit primitives, Dart Engine hosting, PTY
process semantics, and terminal-specific rendering.

Dart 3.13 provides stable build and link hooks for package-owned code assets.
Those hooks can build C, C++, and Objective-C code for dependency packages, but
the standard Dart application builder currently produces CLI bundles. The
custom AppKit host therefore must act as a Dart launcher: invoke or integrate
the hook runner, stage and sign its outputs, provide the native-asset mapping to
the embedded root, and preserve the package asset identity used by Dart FFI.

## Decision

Define a Dart-only application repository as one whose checked-in product
implementation contains Dart source, Dart tests, declarative macOS bundle
metadata, and non-native resources, but no product C, C++, Objective-C,
Objective-C++, Swift, assembly, or Metal source and no direct compilation of a
dependency's internal source tree. The built `.app` is intentionally native and
contains the generic host, Dart runtime, compiled native capabilities, property
lists, resources, and signatures.

Use four independently owned layers:

```text
Dart application and product semantics
  ├─ imports dart_appkit
  ├─ imports optional native capability Dart facades
  └─ is hosted and bundled by dart_macos_runtime

dart_macos_runtime
  ├─ stock Dart Engine root on the AppKit process main thread
  ├─ bounded Dart/AppKit message scheduling
  ├─ Developer JIT and Release AOT host implementations
  ├─ hook/native-asset integration and bundle resource lookup
  ├─ declarative .app assembly, architecture audit, and signing inputs
  └─ generic lifecycle and configurable diagnostics mechanisms

dart_appkit
  ├─ reusable AppKit objects, events, ownership, and thread rules
  └─ versioned native-extension service for custom AppKit capabilities

native capability packages
  ├─ dart_pty_macos
  └─ dart_terminal_renderer_macos
```

`dart_macos_runtime` and `dart_appkit` are separate logical packages. They are
developed in the existing adjacent `dart_appkit` repository initially so host,
bridge, Engine revision, ABI, and integration changes can be committed and
tested atomically. A repository rename or later split is a publishing decision,
not part of the Phase 2 migration.

Terminal-specific native capabilities are developed outside the Dart Terminal
application repository. They may share one repository while their public Dart
libraries, C ABIs, tests, and release versions remain independent.

### `dart_macos_runtime` owns

- `NSApplication`, its process-main-thread run loop, the generic application
  delegate, and the outer process exit.
- The exact official Dart Engine revision, root isolate creation, Kernel and
  AOT snapshot loading, bounded message pump, and process-lifetime VM teardown.
- One host shape for Developer JIT and one for Release AOT, with the same Dart
  application arguments, native-event encoding, lifecycle, and extension
  contracts.
- Declarative product identity: bundle identifier, display name, version,
  minimum macOS version, activation policy, icons, resources, helper
  executables, diagnostics configuration, and entitlements input.
- Running dependency build/link hooks through a pinned launcher adapter,
  validating target OS/architecture, preserving asset IDs, staging dylibs and
  data assets, producing the embedded native-assets mapping, and recording
  their hashes in the bundle manifest.
- Inside-out signing order and exact dependency/rpath/architecture audits. Phase
  2 need not perform Developer ID notarization, but it must produce a layout
  that does not require redesign for it.
- Generic host lifecycle functions such as setting a nonzero process result,
  requesting AppKit termination, resolving a declared bundle resource, and
  recording a bounded lifecycle phase.

The runtime does not own terminal worker protocols, pane recovery, PTY
semantics, rendering semantics, or application policy.

### `dart_appkit` owns

- Application attachment, windows, views, menus, pasteboard, screens, focus,
  visibility, occlusion, backing scale, application/window lifecycle requests,
  normalized input events, and later generic IME-capable view behavior.
- AppKit-main validation, native object registry, generation and domain checks,
  attachment borrowing, asynchronous finalization, event posting, and bridge
  shutdown.
- A versioned native-extension service table that permits a loaded capability
  to register a named `NSView` provider without statically compiling that
  provider into the product runner.

`dart_appkit` does not own PTY functions, terminal draw formats, terminal
shaders, terminal grids, terminal key encoding, or worker-process lifecycle.

### Native capability packages own

`dart_pty_macos` owns `openpty`/`forkpty`, the audited child setup and `execve`,
master-FD readiness, ordered bounded writes, read batching, winsize, signals,
process groups, exit, and reaping. It exposes no AppKit dependency and no VT,
shell-command interpolation, pane policy, or terminal state.

`dart_terminal_renderer_macos` owns the terminal-specific `MTKView` subclass,
CoreText/Metal object lifetimes, packed renderer ABI, and Metal shader source.
It does not parse VT input, own the authoritative grid, select key protocol
bytes, or decide stale-frame policy beyond enforcing submitted generation and
resource-lifetime contracts.

CoreText and Metal internals remain private modules of the renderer capability
until a second real consumer demonstrates a stable reusable API. They are not
prematurely exposed as an object-for-object Dart mirror of Apple frameworks.

### Dart Terminal owns

- Application/window/tab/split state and action routing.
- Official Dart worker-process orchestration, protocol, restart, deadlines,
  backpressure policy, and pane/session ownership.
- VT parsing, grid, scrollback, selection, search, input encoding, config,
  security policy, damage generation, and user-visible diagnostics decisions.
- Explicit initialization and disposal of optional native capabilities through
  their Dart facades.

Product worker executables are declared resources built by the generic builder,
but the runtime neither invents their command-line protocol nor supervises
them.

## Native extension contract

Add a plain-C, versioned host/capability boundary. Objective-C types, Dart
handles, C++ classes, STL values, and arbitrary native object pointers never
cross Dart FFI.

The AppKit host exposes a `struct_size` and `abi_version` prefixed service table
obtained through one process symbol. The initial table supports registering a
named custom-view provider and retrieving a stable diagnostic when registration
fails. Provider registration is AppKit-main-only and process-lifetime metadata.

A capability code asset exports an initialization function that accepts the
service table and returns a stable integer status. Its Dart facade performs
initialization explicitly on the root UI isolate before creating capability
objects. Initialization is idempotent for the same image and ABI, rejects an
unsupported ABI, and never invokes Dart from the native call.

The host or native-assets loader retains the capability image until every
provider instance and callback has been released. Provider creation returns an
Objective-C object only inside native code; the host validates it as an
`NSView`, inserts it into the existing registry, and returns only an opaque
generation-checked view handle to Dart. No public Dart constructor can adopt a
numeric handle or pointer.

Each capability has its own ABI and asynchronous event protocol. Shared envelope
conventions do not create one global ABI version:

- `dmr_*`: generic macOS runtime/host;
- `da_*`: AppKit objects and events;
- `dpty_*`: PTY/process capability;
- `dtr_*`: terminal renderer capability.

A change to one subsystem must not force unrelated event or ABI versions to
advance.

## Build and bundle contract

The application supplies a declarative manifest rather than a native runner
subclass. The manifest identifies product metadata, Dart root entrypoint,
declared Dart helper entrypoints, resources, capability packages, and optional
diagnostics policy. Paths are resolved through package configuration and the
builder; the native host does not trust product-supplied absolute internal
paths or accept forged host-owned arguments.

The builder performs, in order:

1. resolve the exact Dart package graph and lockfile;
2. run compatible dependency build hooks for the target architecture;
3. compile the root Kernel or AOT snapshot with the exact Engine toolchain;
4. compile declared Dart helper Kernels or self-contained AOT executables;
5. stage native code/data assets, helpers, and ordinary resources;
6. generate the native-assets and bundle-resource manifests;
7. assemble the generic host, AppKit bridge, Engine, and product metadata;
8. audit architecture, install names, rpaths, allowed dependencies, exported
   host symbols, resource freshness, SDK revision, and absence of undeclared
   files;
9. sign nested code before the outer application when signing is requested.

The host passes only opaque resource identities or resolved bundle-contained
paths to Dart. The current terminal-specific `--runtime-worker-*` injection is
replaced by a generic declared-resource API; product arguments cannot override
host-owned resource identities.

## Ownership, threading, and shutdown

- AppKit and capability initialization that registers an AppKit provider run
  only on the process main thread/root UI isolate.
- Worker processes and PTY reactors never call AppKit.
- A provider image outlives its registered factory, every created view, and
  queued teardown callback.
- Runtime, AppKit, PTY, and renderer handles use independent registries or
  explicit service ownership; a handle from one subsystem is invalid in
  another.
- Native-to-Dart delivery is asynchronous and immutable. No AppKit delegate,
  PTY readiness callback, renderer completion, or plugin initializer
  synchronously enters Dart.
- Shutdown admission closes from product to capability to AppKit to Dart Engine.
  Each subsystem drains or invalidates late generation-tagged work before its
  provider image or host service table becomes unavailable.

## Testing and compatibility gates

- Preserve the existing v1-v4 AppKit event compatibility fixtures and C11/C++20
  public-header compilation.
- Run one generic hello-window application in Developer JIT and Release AOT.
- Test plugin missing/unsupported ABI, duplicate init, wrong-thread init,
  failed view construction, stale/double release, pending asynchronous release,
  shutdown, and image lifetime.
- Re-run Dart Terminal's existing GUI, worker lifecycle, failure/replacement,
  bounded traffic, 1,000 Window/View churn, diagnostics, shutdown fault, bundle
  audit, freshness, and clean-SDK gates after every composition change.
- Reject any migration that needs a modified SDK, private Dart symbol, copied
  `runtime/bin` implementation, synchronous native-to-Dart re-entry, or a
  product-specific native host subclass.

## Alternatives rejected

### Put all native code in `dart_appkit`

Rejected because a terminal PTY and terminal renderer are not AppKit
primitives. This creates a release-cadence and ABI dependency between unrelated
applications and recreates a monolithic framework under an inaccurate name.

### Keep product-native composition in Dart Terminal

Rejected because every Dart macOS application would require its own native
runner and internal build graph. It also allows direct dependency-source
compilation to bypass package versioning.

### Create one `terminal_platform_macos` ABI for all native concerns

Rejected as the final boundary because PTY I/O and Metal/AppKit rendering have
different threads, ownership, error models, release cadence, and potential
non-terminal consumers. A facade package may combine their Dart APIs without
combining their native contracts.

### Mirror Objective-C APIs directly into Dart

Rejected for the reasons in ADR-001: subclass callbacks, autorelease pools,
thread affinity, ownership, fork safety, and ABI evolution remain native
concerns. Generated bindings may be used privately inside a capability, but do
not define the product architecture.

### Use `dart build cli` output as the GUI host

Rejected because the accepted product contract requires `NSApplication` to own
the process main thread and the embedded Dart root to run inside that AppKit
host. A CLI executable that later creates AppKit would not reproduce the proven
host topology.

## Consequences

- Dart Terminal can become a Dart-only application repository while retaining
  necessary native implementations in audited dependencies.
- Other applications can use the same stock Engine/AppKit host and select only
  the native capabilities they import.
- The generic builder and extension ABI add meaningful upfront work before the
  PTY implementation, but prevent each later native feature from adding a new
  product runner fork.
- Dynamic code asset, callback, rpath, signing, and native-assets mapping
  lifetime become release contracts and require dedicated tests.
- Cross-repository changes must use additive compatibility first: release the
  reusable runtime or capability, migrate the product, pass both runtime modes,
  then remove the old implementation.
