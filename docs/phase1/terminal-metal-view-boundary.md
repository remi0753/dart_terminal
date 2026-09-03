# TerminalMetalView custom-view boundary

- Status: in progress
- Started: 2026-09-04
- Scope: first unchecked Phase 1 roadmap item only
- Related: `ROADMAP.md` Phase 1, ADR-001, ADR-002, ADR-004,
  `docs/phase0/DT-006-metal-instances.md`, and the adjacent `dart_appkit`
  generic `View` contract

## Purpose

Establish the smallest reusable boundary through which a terminal-owned native
`TerminalMetalView` can be created as a generation-checked AppKit view handle,
owned by Dart, and attached to a `Window` without exposing an Objective-C
pointer to Dart or moving terminal rendering policy into `dart_appkit`.

## Background

The preceding Phase 1 work introduced a generic Dart `View`, a native `DaView`
base, and subtype-aware content-view attachment. Creation is still closed:
`da_view_create` can instantiate only `DaView`, while the private Dart wrapper
constructor can wrap only handles created inside `dart_appkit`. A future
terminal renderer must instead attach an `MTKView`-derived class owned by Dart
Terminal.

ADR-001 assigns reusable AppKit primitives to `dart_appkit` and terminal Metal,
CoreText, packed-frame, and shader policy to Dart Terminal. ADR-004 also fixes
`MTKView` lifecycle to the AppKit main domain and reserves renderer submission,
buffer slots, display pacing, and GPU completion handling for Phase 4. This
task therefore needs an extensibility seam and a real terminal-owned view
class, but not a renderer.

## Scope

- Add an Objective-C++ provider-registration surface to `dart_appkit` for
  named `NSView` subclasses. Registration and instantiation remain AppKit-main
  operations.
- Add a plain-C `da_view_create_custom` call that accepts a copied UTF-8
  provider identifier and returns an ordinary registry-owned generic-view
  handle.
- Add `View.custom` and the corresponding optional FFI/fake-binding path. Dart
  receives only the opaque handle; it cannot supply or adopt a raw pointer or
  forge a wrapper around an arbitrary handle.
- Preserve generic-view lookup, generation checks, domain checks, explicit
  disposal, native finalization, shutdown, and borrow-only content attachment.
- Add a Dart Terminal-owned `TerminalMetalView : MTKView` shell, register it in
  both product hosts before Dart startup, and link the same native source into
  Developer JIT and Release AOT.
- Add deterministic native coverage that proves the registered object is the
  expected subclass, is represented as a generic view handle, attaches to an
  `NSWindow`, and releases under existing ownership rules.
- Exercise custom-view creation and attachment through the real Dart facade in
  the existing M1 Developer JIT and Release AOT integration smoke.

## Out of scope

- Metal command queues, pipeline state, shaders, glyph/image atlases, frame
  slots, packed submissions, display callbacks, frame pacing, or GPU failure
  handling; those remain Phase 4 work under ADR-004.
- CoreText shaping/rasterization, font metrics, caret rendering, terminal
  layout, or replacing the normal command-console `TextView` before the
  renderer vertical slice exists.
- `NSTextInputClient`, candidate geometry, accessibility, drag/drop, tabs,
  splits, PTY, or terminal input routing.
- A public raw-pointer adoption API, Dart callbacks invoked by native creation,
  arbitrary Objective-C construction arguments, or runtime provider removal.
- The following unified-logging and resource-leak/fault-injection roadmap
  items.
- x86_64, Rosetta, Universal, and Intel-native follow-up validation.

## Dependencies and confirmed facts

- Work started from clean Dart Terminal HEAD `6b4e026` and clean adjacent
  `dart_appkit` HEAD `fc05f1b`. No later Phase 1 item has been started.
- `README.md`, the complete roadmap and feature matrix, ADR-001/002/004, the
  Phase 0 Metal and IME evidence, the preceding generic-view task record, both
  repositories' source/test/build layouts, and both product host paths were
  reviewed before implementation.
- The public `dart_appkit.h` contract contains plain C types only. A supported
  native provider header must therefore be separate and Objective-C++-only;
  the Dart-facing create call can remain plain C and identifier-based.
- `ObjectRegistry` already strongly retains objects and records an exact kind,
  positive generation, and AppKit-main domain. A custom view can reuse
  `ObjectKind::kView`; no new kind or special release path is required.
- `da_window_set_content_view` currently narrows its view lookup to `DaView*`.
  Registered custom subclasses need this helper generalized to `NSView*`
  while retaining the same registry kind check.
- A public Dart constructor that accepts a numeric native handle was rejected:
  event records reveal valid handles, and such an API could forge a `View`
  wrapper whose generic `dispose` releases an unrelated registry object.
- A named native provider registry lets native product code choose the class
  while `View.custom` receives only a newly minted, already-typed handle.
- Both product runners compile the adjacent bridge sources directly. Their
  source inventories, fingerprint dependencies, clang-format list, include
  paths, and framework link lists must all include the new boundary inputs so
  cached bundles cannot conceal drift.
- Normal product startup must retain the current visible command console. The
  integration harness can opt into the Metal-view shell with a private test
  environment gate, then prove the same Dart create/attach/dispose path in
  each runtime mode.

## Design decision

Use a process-lifetime native provider map keyed by a non-empty UTF-8
identifier. Native product startup registers one `NSView` subclass for an
identifier through a separate Objective-C++ extension header. Re-registering
the same identifier/class pair is idempotent; attempting to replace it with a
different class is rejected. The class must inherit `NSView` and support normal
`initWithFrame:` construction.

`da_view_create_custom` copies and validates the identifier, resolves and
instantiates the provider on the main thread, validates the result, and inserts
it as `ObjectKind::kView`. From that point onward it is indistinguishable from
another generic view for attachment, generation/domain validation, disposal,
and shutdown. The provider map owns class metadata only; it does not own live
view instances or renderer state.

Dart exposes `View.custom(String providerIdentifier)` instead of any handle-
adoption constructor. The native provider for
`dart_terminal.TerminalMetalView` is registered explicitly in both hosts before
the Dart root starts. The initial subclass owns only `MTKView` configuration
needed to prove its AppKit identity and safe attachment. Renderer resources and
delegate behavior are deliberately absent.

## Ordered subtasks

### 1. Reusable registered custom-view provider

- Implement and document the Objective-C++ registration surface, provider
  registry, plain-C create call, `NSView`-generic lookup, Dart `View.custom`,
  optional FFI compatibility behavior, and fake/native/Dart/header tests.
- Completion: valid registered subclasses create and attach as generic views;
  empty/missing/wrong/duplicate registrations and off-main creation fail
  deterministically; existing view type, ownership, event, and legacy-bridge
  tests pass; the full `dart_appkit` suite is committed before subtask 2.

### 2. Terminal-owned view shell and native attachment contract

- Add the terminal-owned class/registration hook, call it from both product
  hosts, add it to fingerprints/build source inventories and framework links,
  and add a native contract executable.
- Completion: the contract proves class identity, a usable Metal device on the
  M1 baseline, paused/on-demand shell configuration, generic-handle attachment,
  stale-handle rejection, and zero remaining registry handles; source checks
  and the focused native test pass; this subtask is committed before subtask 3.

### 3. M1 product integration and acceptance

- Add a private integration gate that selects `View.custom` while normal runs
  retain `TextView`, require a machine-readable attach observation in the
  shared smoke, and update current product documentation/status.
- Completion: source checks, relevant freshness checks, both arm64 builds and
  audits, both real GUI integration smokes, clean official SDK, diff review,
  and repository hygiene pass. Then check all subitems and the parent and
  commit the completion record.

Subtasks are strictly ordered. The terminal class cannot be implemented before
the reusable provider contract is committed, and product integration cannot be
accepted before the terminal native contract is committed.

## Acceptance criteria

1. A native extension can register a named `NSView` subclass without adding it
   to `dart_appkit` or exposing Objective-C objects through `dart_appkit.h`.
2. Registration and creation enforce AppKit-main affinity, non-empty names,
   `NSView` inheritance, no conflicting replacement, and deterministic error
   details.
3. `View.custom` returns only a newly created generic-view handle from a
   registered provider; Dart has no public arbitrary-handle adoption path.
4. A missing provider, empty identifier, nil/wrong class, wrong thread, stale
   handle, wrong handle kind, and double disposal are covered without leaks.
5. A registered subclass attaches through `Window.contentView`; attachment
   consumes neither handle and preserves normal AppKit retaining behavior.
6. `TerminalMetalView` is implemented in Dart Terminal, subclasses `MTKView`,
   is created on the main thread with the system Metal device, and remains
   paused/on-demand with no renderer delegate or runtime shader compilation.
7. Both native product hosts explicitly register the same provider before Dart
   creates the view and link identical terminal/bridge sources.
8. Normal startup retains the command-console `TextView`; only a private
   integration gate selects the `TerminalMetalView` shell.
9. Developer JIT and Release AOT both create, attach, show, close, dispose, and
   exit with zero leaked handles through the real Dart/native boundary.
10. Formatting, analysis, C11/C++20 public-header checks, reusable tests,
    terminal tests, audits, M1 integrations, diff review, and SDK/repository
    hygiene pass.

## Validation plan

- Run focused native provider and Dart API tests while implementing the
  reusable boundary, then the complete adjacent `make test` suite.
- Run Dart Terminal's native custom-view contract and `runtime-source-check`
  after integrating the terminal-owned class.
- Rebuild rather than reuse both arm64 products after source/fingerprint input
  changes; run Developer JIT and Release AOT audit plus integration smoke.
- Run affected build-freshness/clean-SDK checks and verify the official Dart
  SDK, `dart_appkit`, and Dart Terminal worktrees after task-scoped commits.

## Risks and open checks

- An `MTKView` is not a `DaView` subclass. All generic operations must rely on
  registry kind plus `NSView`, not a concrete bridge subclass cast.
- Provider registration occurs before the Dart root but after the executable
  is loaded. Errors must fail host startup instead of leaving a latent Dart
  creation failure.
- The system Metal device may be absent on an unsupported host. The product
  baseline requires it; creation must return a deterministic failure rather
  than registering a half-initialized view.
- A window retains its content view after the registry handle is released.
  Tests must distinguish handle invalidation from Objective-C instance
  lifetime and release the window as well.
- Build fingerprints must include the new native sources and supported
  provider header; otherwise a cached signed product could pass with stale
  host code.

## Investigation log

### 2026-09-04 — repository and boundary review

- Confirmed this parent item is the first unchecked roadmap task and split it
  before implementation because it spans a reusable repository, a terminal-
  specific native adapter, and two product acceptance modes.
- Confirmed the prior `View` task explicitly deferred external/custom native
  subclass registration and `TerminalMetalView`, making this task the intended
  continuation rather than follow-up work hidden in the prior item.
- Confirmed the Phase 0 Metal spike used a native `MTKView` and system device,
  while ADR-004 places all command-buffer, slot, pacing, and GPU-completion
  behavior later. Only the view shell and ownership/attachment seam are needed
  here.
- Compared arbitrary Dart handle adoption, a Dart-to-native callback factory,
  and named native provider registration. Selected the named provider because
  it preserves opaque capability issuance, avoids synchronous native-to-Dart
  construction callbacks, and keeps terminal class knowledge outside
  `dart_appkit`.

### 2026-09-04 — Subtask 1: reusable provider implementation

- Added the separate Objective-C++ `dart_appkit_custom_view.h` surface and a
  process-lifetime provider map. Registration is AppKit-main-only, copies the
  identifier, validates `NSView` inheritance, is idempotent for the same pair,
  and rejects a conflicting class.
- Added `da_view_create_custom` and `View.custom`. The public C call validates
  and copies UTF-8, constructs through the registered native class, and inserts
  the result as the existing generic-view kind. The Dart FFI lookup is optional
  for legacy libraries and exposes no pointer or arbitrary-handle constructor.
- Generalized only the resolved native type used by content attachment from
  `DaView*` to `NSView*`. Registry kind, generation, domain, attachment borrow,
  finalizer, release, and shutdown behavior did not change.
- Added native coverage for invalid/missing/duplicate registrations, class
  identity, text-only rejection, window attachment, off-main registration and
  creation, stale/double release, and the independent AppKit retain edge. Added
  Dart fake/API coverage plus real and legacy FFI checks.
- Focused header/native/Dart tests passed first. The final adjacent `make test`
  passed the complete scaffold, native bridge, Runner, message-pump, event
  encoder, Dart API/launcher, example compile, real FFI, and legacy FFI suite.
  Dart and native format audits plus `git diff --check` also passed.
- The built dylib exposes 37 public `da_*` symbols including
  `da_view_create_custom` and the native provider registration symbol. The
  official Dart SDK is clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- The reusable subtask is fixed at adjacent `dart_appkit` commit `c19071e`
  (`Add registered custom view providers`). Its worktree was clean immediately
  after commit; the terminal implementation will consume this committed
  boundary rather than an untracked dependency state.

### 2026-09-04 — Subtask 2: TerminalMetalView shell

- Added `native/macos/renderer/TerminalMetalView.{h,mm}` as a Dart
  Terminal-owned `MTKView` subclass. Construction requires the system Metal
  device, uses flipped coordinates and width/height autoresizing, and remains
  paused with explicit invalidation enabled. It has no delegate, command queue,
  pipeline, shader, buffers, display callback, or renderer submission API.
- Both Developer JIT and Release AOT hosts explicitly register the provider on
  the process main thread after creating `NSApplication` and before Dart
  startup. A registration error is a host-startup software failure rather than
  a latent Dart-side failure.
- Updated the shared bridge source list for `CustomViewRegistry`, added the
  terminal view source/header to both host dependency graphs and link lines,
  and linked AppKit, Metal, and MetalKit identically in both modes.
- Added `native/macos/renderer` to the canonical runtime provenance directory
  list. The source fingerprint therefore covers the view, registration hook,
  and native contract test rather than permitting a stale product host.
- Added `terminal-metal-view-test` and made it part of
  `runtime-source-check`. The native test registers the provider twice,
  creates it through `da_view_create_custom`, verifies its exact subclass and
  shell state, attaches it as the window content/first-responder view, then
  proves stale/double-handle rejection, the independent AppKit retain edge,
  and a final live-handle count of zero.
- The first standalone native contract run passed on Apple M1/arm64 with a
  non-null system Metal device. The first full source-check attempt failed only
  its format audit because an earlier formatter invocation had not selected
  the adjacent `dart_appkit` style file and had reformatted the touched native
  files with a different pointer style. Re-running the formatter with the
  explicit project style restored the established formatting; no semantic
  workaround was needed.
- The corrected `runtime-source-check` passed Dart formatting, clang-format,
  C11/C++20 lifecycle-header compilation, plist validation, analysis, Dart
  tests, and the rebuilt native contract. Product binary builds and real GUI
  creation remain intentionally assigned to subtask 3.
