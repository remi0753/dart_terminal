# Quick Look, Services, Drag and Drop, and Context Menu

## Status

- Phase: 10
- Task: Quick Look, Services, drag/drop, and context menu
- Started: 2026-09-12
- State: active
- Current subtask: `dart_appkit` Services and drop-destination substrate
- Primary environment: macOS 14 or later on Apple M1/arm64

## Purpose

Make terminal text and files participate in standard macOS content workflows
without bypassing terminal input policy. A user must be able to look up a word,
invoke relevant terminal actions from a context menu, send or receive selected
plain text through Services, drop text or file URLs into a terminal, and open
folders from Finder Services in a new tab or window.

## Background

- Phase 5 completed bounded selection, standard plain-text Copy/Paste,
  dangerous/large paste confirmation, terminal mouse arbitration, hyperlinks,
  native text input, and Metal cell geometry.
- Phase 7 completed the application action registry, native menus, pane/window
  ownership, trusted working-directory inheritance, and deterministic teardown.
- Phase 10 Quick Terminal and Secure Keyboard Entry added retained window roles,
  checked menu projection, and application activation ownership.
- Feature Matrix IN-10 and UI-07 still identify drag/drop, Services, Quick Look,
  and contextual native interaction as missing. The adjacent `dart_appkit`
  roadmap likewise has no View context-menu, drag destination, or Services
  requestor/provider API.

## Scope

- Add bounded product contracts for word lookup at a terminal cell, shell-safe
  file-path insertion, and shared Quick Look/context-menu actions.
- Add generic `dart_appkit` View support for a prebuilt native context menu and
  dictionary definition presentation, including pressure-click request events.
- Add generic `dart_appkit` plain-text Services requestor support backed by a
  cached selection, asynchronous returned-text events, and a text/file-URL drag
  destination with typed operation negotiation and bounded payloads.
- Add a generic application Services provider for opening normalized directory
  URLs and the runtime manifest declarations needed for Finder's “New Tab at
  Folder” and “New Window at Folder” entries.
- Integrate all routes with the focused pane, existing paste confirmation and
  PTY transport, current action availability, terminal mouse capture, trusted
  cwd rules, Quick Terminal ownership, and deterministic shutdown.
- Verify native behavior in Developer JIT and Release AOT and provide a manual
  Finder/Services/force-click/context-menu checklist.

## Out of scope

- A drag source, promised files, image/rich-text/custom pasteboard types, or
  arbitrary application-defined drag operations. The pinned comparison surface
  is a text/file-URL drop destination, and broader generic AppKit drag support
  remains tracked by the dependency roadmap.
- Previewing files with `QLPreviewPanel`. Here Quick Look means the standard
  macOS dictionary/data-detector lookup for a terminal word, matching the pinned
  comparison surface.
- Option-click cursor positioning, semantic output selection, AppleScript, App
  Intents, complete accessibility audit, localization, or terminal inspector
  work from other roadmap items.
- Sending terminal contents other than the explicit local selection, accepting
  unbounded pasteboard data, or writing dropped/service-returned text directly
  to a PTY outside the existing paste policy.

## Dependencies

- `dart_appkit` generation-checked View/Menu ownership, asynchronous native
  event protocol, pasteboard bounds, fake/native bindings, application
  lifecycle, and AppKit-main-thread root.
- `dart_macos_runtime` manifest validation and deterministic Info.plist/bundle
  generation for declared Services.
- Terminal selection/viewport/cell metrics, mouse reporting state, paste
  planning/confirmation/transport, action registry/menu projection, hierarchy
  cwd inheritance, and shipped-runtime harness.
- ADR-001 keeps reusable OS mechanisms in dependencies and product policy in
  this repository. ADR-002 forbids synchronous native-to-Dart reentry.

## Completion conditions

1. Right-click and Control-click show one native terminal context menu only when
   terminal mouse capture does not own that gesture. Copy, Paste, Quick Look,
   Split Right, and Split Down use the same action registrations and current
   availability as the main menu/command palette; no terminal mouse or PTY byte
   is duplicated.
2. Force-click or the shared Quick Look action resolves one bounded word at the
   relevant terminal cell and uses native definition presentation with current
   font/baseline geometry. Empty, whitespace, truncated, stale, and unavailable
   lookups are inert and typed rather than guessed.
3. macOS Services can read only the current bounded plain-text selection and can
   return bounded plain text through the ordinary paste confirmation/transport
   path. Synchronous AppKit requestor checks use native cached state and never
   synchronously enter Dart.
4. Dropped plain text and file URLs are accepted with copy semantics, bounded
   before crossing the ABI, and delivered asynchronously through the same paste
   policy. File paths are normalized and shell-quoted as data. Unsupported,
   malformed, oversized, stale, or inactive-target drops make no PTY write.
5. Finder Services normalize selected files to unique parent directories and
   selected directories to themselves, then create a fresh terminal tab/window
   at each trusted local directory through typed asynchronous provider events.
   Runtime bundles contain only the declared service metadata.
6. Focused/fake/native/dependency tests, both shipped runtime paths, source and
   bundle audits, exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`, README/
   FEATURE_MATRIX/reference/evidence updates, final diff review, roadmap
   completion, and one standalone commit per ordered subtask pass.

## Validation approach

- Unit tests cover word boundaries, quoting, payload limits, stale target
  identity, mouse-capture suppression, and action availability without AppKit.
- `dart_appkit` fake/native tests cover context gesture recognition, menu
  attachment ownership, definition placement, pressure events, Services
  requestor send/receive, drag negotiation, type/size rejection, provider URL
  normalization, late events, and disposal.
- `dart_macos_runtime` tests compare exact manifest validation and generated
  Info.plist service dictionaries for JIT and AOT bundles.
- Product acceptance drives real AppKit events and pasteboards while using
  deterministic temporary paths and a private test pasteboard. It asserts exact
  PTY bytes only after policy approval, zero writes on rejection/cancellation,
  no gesture duplication, fixed terminal metrics, and zero native/session
  handles after close and Quit.
- A manual checklist covers Finder Services visibility, system service text
  transforms, trackpad force click, keyboard/context invocation, and assistive
  input settings that cannot be enabled deterministically in automation.

## Ordered subtasks

This item spans product text semantics, two native dependency ABIs, synchronous
AppKit responder requirements, runtime bundle metadata, and real Finder/system
integration. It is split before implementation so later layers consume only
committed contracts.

1. **Bounded terminal interaction contracts and shared actions**
   - Define word-at-cell lookup, shell-safe dropped-path serialization, typed
     external-content admission, and Quick Look action metadata independently
     of AppKit.
   - Complete when empty/wide/wrapped/stale/bounded word and hostile filename/
     text cases, action conflicts, API exports, focused tests, and the full
     terminal gate pass.
2. **AppKit context-menu and Quick Look substrate**
   1. Add reusable View-owned context-menu attachment with explicit Menu/View
      lifetime coordination.
   2. Add pressure/Quick Look request events and native definition
      presentation, preserving asynchronous event delivery and generation
      ownership.
   - Complete when fake/native/legacy/public API, accessibility geometry,
     disposal, both host builds, dependency full gate, and consuming terminal
     full gate pass.
3. **AppKit Services and drop-destination substrate**
   - Add cached plain-text Services requestor state, bounded asynchronous
     service-return/drop events, text/file URL operation negotiation, and a
     typed application folder-service provider.
   - Complete when synchronous responder behavior never re-enters Dart and all
     type/limit/normalization/stale/disposal/native tests plus dependency and
     consuming full gates pass.
4. **Runtime service declaration substrate**
   - Extend the runtime manifest and deterministic Info.plist generation with a
     closed service declaration schema required by the application provider.
   - Complete when malformed manifests fail closed and JIT/AOT fixture, schema,
     bundle audit, dependency full gate, and consuming full gate pass.
5. **Product integration, shipped-runtime acceptance, and closure**
   - Connect focused pane selection, mouse policy, shared actions, Services,
     drops, cwd creation, Settings/menu availability, and all teardown paths.
   - Complete when Developer JIT/Release AOT native acceptance, full gates and
     audits, manual checklist, docs/evidence, final diff review, roadmap parent,
     and its standalone commit pass.

## Findings and decision log

- 2026-09-12: After commit `0563192` (`Complete secure keyboard entry
  acceptance`), terminal and adjacent `dart_appkit` worktrees are clean. ROADMAP
  reread selects this item as the first remaining Phase 10 work; AppleScript and
  all later polish remain out of scope until this parent is committed.
- 2026-09-12: The pinned comparison Service provider reads file URLs from the
  service pasteboard, maps files to parent directories, de-duplicates directory
  URLs, and creates a terminal tab or window for each directory. Source:
  `macos/Sources/Features/Services/ServiceProvider.swift` at pinned commit
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4`.
- 2026-09-12: The pinned AppKit surface registers string/file-URL drop types,
  negotiates copy, and asynchronously sends the resulting text to its surface.
  It implements Quick Look as word-under-cursor dictionary presentation and
  exposes Services send/return text through the responder chain. Its context
  menu is limited to right-click/Control-click outside mouse capture and reuses
  ordinary application actions. Source: `macos/Sources/Ghostty/Surface View/
  SurfaceView_AppKit.swift` at the same pinned commit.
- 2026-09-12: The installed macOS SDK confirms `menuForEvent:`,
  `quickLookWithEvent:`, `showDefinitionForAttributedString:atPoint:`,
  `registerForDraggedTypes:`, `validRequestorForSendType:returnType:`, and the
  `NSServicesMenuRequestor` read/write callbacks are synchronous AppKit methods.
  Native code therefore must answer from cached bounded state and emit any Dart
  work later through the existing event queue.
- 2026-09-12: The runtime manifest currently has no arbitrary Info.plist or
  `NSServices` representation. A closed additive schema is required; accepting
  arbitrary plist fragments would weaken deterministic bundle validation.
- 2026-09-12: All external text entry will reuse `TerminalPasteCodec`, the
  confirmation gate, and one-in-flight transport. Drag or Services callbacks
  must not call the pane's raw input writer. File URLs will be converted to
  normalized local paths and quoted as shell data before that same admission.
- 2026-09-12: No drag source will be added. This matches the pinned product
  behavior and avoids pre-implementing the dependency's broader promised-file
  roadmap. The manual and automated acceptance will describe the delivered
  capability explicitly as a drop destination.
- 2026-09-12: The product contract now resolves a word from one viewport cell
  through existing stable selection anchors. It rejects off-grid, whitespace,
  boundary-limited, scalar-limited, unavailable, and generation-stale results
  with distinct dispositions; wide continuations and soft wraps resolve to one
  candidate plus its word-start baseline geometry. It never changes the local
  selection merely to ask for a definition.
- 2026-09-12: External Services/drop text is admitted with its source and exact
  UTF-8 byte count but remains inert until later paste planning. Dropped file
  paths are limited to 256 absolute paths, 1 MiB each and 64 MiB serialized,
  reject control characters and malformed UTF-16, and serialize every path as
  one single-quoted POSIX shell word. Embedded single quotes use the closed
  `'\''` form; spaces, globs, substitutions, and leading option characters are
  consequently data rather than shell syntax. A trailing space separates any
  command text the user types later.
- 2026-09-12: `pane.quick-look` is the 28th stable application action. It uses
  the standard macOS dictionary lookup chord Control-Command-D, participates in
  conflict/reserved-shortcut generation, and deliberately has no product
  handler until the later native substrate and integration subtasks exist.
- 2026-09-12: A first focused test attempt inside the filesystem sandbox passed
  static analysis but could not run the renderer build hook because Clang's
  existing module cache under `~/.cache` was not writable. The same native
  content test passed in the approved normal build environment. The first
  action-registry run then correctly exposed the stale expected View-menu list;
  adding Quick Look to that exact-order assertion made its rerun pass.
- 2026-09-12: UTF-8 admission counts code units incrementally and stops at the
  caller's bound, so an oversized external string is rejected without first
  allocating an equally large encoded byte list. Valid surrogate pairs count as
  four bytes and malformed units match Dart's replacement-scalar encoding.
- 2026-09-12: The first exact full gate stopped at the expected stale Phase 6
  regression coverage hash after README/FEATURE_MATRIX changed. Regenerating
  `compatibility/regression_coverage_report.json` changed only those two source
  hashes. A subsequent full run passed but reported two directive-ordering info
  diagnostics for the new export/import; alphabetizing them removed both.
- 2026-09-12: Final focused native-content, action-registry, and generated
  keybinding-reference tests pass. Final exact `CI=true
  DART_SUPPRESS_ANALYTICS=true make test` passes: generated references and
  compatibility evidence are fresh, 28 application actions and 15 native
  shortcuts reconcile, all 276 files are formatted, static analysis reports no
  issues, security stress passes, and the aggregate terminal tests pass.
- 2026-09-12: Dependency inspection after commit `2023a72` found that an
  ordinary context menu can reuse the existing generation-checked `Menu`
  through `NSView.menu`, but a force-click request must also reach registered
  custom views such as the terminal's provider-owned `MTKView`. The generic
  base View class alone cannot override such a custom view's pressure responder.
  A non-delaying pressure recognizer attached to the registered view and a new
  versioned view-source event are the reusable boundary.
- 2026-09-12: Context-menu attachment does not change the event protocol;
  Quick Look does. The two mechanisms are therefore added as ordered nested
  subtasks before dependency code changes.
- 2026-09-12: Adjacent `dart_appkit` commit `7869872` adds optional additive
  `da_view_set_context_menu`, public cache-on-success `View.contextMenu`, and
  generic/specialized View support without changing the ABI or event protocol
  versions. AppKit owns secondary-click/Control-click presentation through
  `NSView.menu`; selected items still use the existing asynchronous,
  generation-checked `MenuItem` event path, so no native callback enters Dart
  synchronously.
- 2026-09-12: Lifetime coordination is bidirectional. Native code keeps only a
  weak set of attached views, clears a View's menu on View release, and clears
  all matching Views before Menu release. Dart Menu wrappers hold weak View
  references and update either side only after native success. A failed View or
  Menu release consequently preserves retryable wrapper/native state, while a
  successful release clears the surviving wrappers' caches.
- 2026-09-12: The first dependency native run found that a registry-domain test
  intentionally stores a non-`NSView` release probe under generic `kView`.
  Limiting the new cleanup hook to objects that are actually `NSView`
  subclasses preserves that extensible registry contract. The first exact gate
  then found only an unused C header-probe pointer; referencing the new symbol
  in both C11 and C++20 probe results fixed the warning-as-error failure.
- 2026-09-12: Focused native/Dart/current+legacy FFI tests cover attach,
  replacement, clear, type/thread/stale rejection, cross-application guards,
  failure cache preservation, and release from either side. Both generic host
  builds and the dependency exact gate pass. The consuming exact `CI=true
  DART_SUPPRESS_ANALYTICS=true make test` also passes with 276 formatted files,
  clean analysis, generated reference/evidence checks, Phase 9 security stress,
  and the aggregate terminal suite.
- 2026-09-12: Rechecking the pinned comparison source shows its custom View
  receives `pressureChange`, resets a retained previous stage on mouse-up, and
  invokes Quick Look only on the first transition into pressure stage 2. It
  then resolves the terminal word/font and calls AppKit definition
  presentation at bottom-left View coordinates. `dart_appkit` cannot override
  an arbitrary provider-owned View method, so its reusable equivalent will be
  a non-consuming local pressure monitor enabled per generation-checked View;
  it returns the original event and emits one asynchronous v9 request only for
  the first stage-2 transition under that View.
- 2026-09-12: The Quick Look event will use stable type 42 and carry finite
  View-local AppKit x/y coordinates. Definition presentation is a separate
  synchronous Dart-to-native call with non-empty text bounded to 4096 UTF-8
  bytes, existing typed system/monospaced/named font selection, and finite
  baseline geometry. This keeps word/grid policy in the product and gives both
  native gesture and keyboard action paths the same presentation mechanism.
- 2026-09-12: The adjacent implementation now uses one non-consuming local
  AppKit pressure monitor for all explicitly enabled Views. It selects the
  deepest registered ancestor under the event, retains each View weakly,
  resets on mouse-up or a stage below 2, and emits one generation-checked v9
  request per first stage-2 transition. View release removes its registration
  and the monitor is removed when the last registration disappears.
- 2026-09-12: `DefinitionPresentation` validates non-empty display-safe text at
  a 4096-byte UTF-8 hard limit, reuses the existing typed View font contract,
  and requires finite View-local baseline geometry. The additive native call
  copies all bytes before returning and uses AppKit's attributed-string
  definition presentation; product word/grid selection remains outside the
  dependency.
- 2026-09-12: Event protocol v9 preserves the v2-v8 envelope and adds only type
  42 with two finite doubles. The shared Runner encoder, strict Dart decoder,
  weak exact-View routing, optional current/legacy FFI symbols, and release
  retry semantics are covered by native and Dart tests. Enabling requests on a
  negotiated v8 sink fails before native registration, while definition
  presentation remains an independent Dart-to-native call.
- 2026-09-12: The first focused Dart run stopped because one current-protocol
  lifecycle assertion still expected version 8. Since that test failed before
  disposing its singleton test application, all later cases reported the same
  attach conflict. Updating that exact negotiation assertion to version 9 made
  the rerun pass all 24 API groups plus current and legacy FFI smoke tests.
- 2026-09-12: The first consuming terminal gate reached compilation and found
  the expected consequence of extending sealed `AppKitEvent`: two application
  event switches were no longer exhaustive. This dependency subtask adds the
  new View request to their explicit no-op groups only. Product lookup routing
  remains deferred to the ordered integration subtask rather than being
  implemented ahead of Services/drop/runtime prerequisites.
- 2026-09-12: The terminal file formatter reported zero textual changes but
  returned 1 in the filesystem sandbox because the Dart CLI attempted to touch
  its existing telemetry session outside the writable roots. Repeating the
  exact one-file format in the approved normal environment returned 0 with
  zero changes.
- 2026-09-12: The next terminal gate correctly rejected stale Phase 7 AppKit
  acceptance evidence after the reviewed application source changed. Running
  `make phase7-appkit-acceptance` updated only the two deterministic SHA-256
  references for `terminal_application.dart`; no acceptance criteria or test
  inventory changed.
- 2026-09-12: Final dependency validation passes the focused ABI/native/shared
  encoder/Dart/current+legacy FFI gate, both warning-clean Developer JIT and
  Release AOT host builds, and the exact full dependency gate. The final
  consuming exact gate passes generated references/evidence, 276-file format,
  static analysis, Phase 9 security stress, and the aggregate terminal suite.
- 2026-09-12: Adjacent `dart_appkit` commit `1106ee6` records the complete
  Quick Look request/definition substrate. With the earlier context-menu commit,
  the ordered AppKit content-menu/Quick Look parent is complete. ROADMAP reread
  selects AppKit Services and drop-destination substrate next; runtime manifest
  declaration and product integration remain intentionally untouched.
- 2026-09-12: The first terminal staging attempt was rejected because the
  filesystem sandbox could not create `.git/index.lock`; no index or working
  tree content was changed. Staging is retried through the approved repository
  write path.

## Risks and handoff notes

- A system Services menu may call availability methods while Dart is busy. Only
  immutable cached selection text and closed native flags may be read there.
- Native menu objects cannot have ambiguous ownership between the main menu and
  a View context menu. Context menus will be separately constructed from shared
  action definitions and dispose their own generation-checked handles.
- File URLs may name remote, nonexistent, relative, control-containing, or very
  long paths. The provider and drop paths need separate closed validation;
  neither may infer trust from a URL string alone.
- Pressure events and force-click preferences vary by hardware and user
  settings. Automation covers the event/definition boundary; the checklist owns
  physical gesture acceptance.
