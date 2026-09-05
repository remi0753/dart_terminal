# Phase 4 — Resize, scale, and font full rebuild

- Status: complete
- Date: 2026-09-06
- Scope: sixth Phase 4 roadmap item
- Related: ADR-001, ADR-003, ADR-004, SCR-07, SCR-09, TXT-05, REN-01,
  REN-03, REN-04

## Purpose

Make terminal-grid resize, backing-scale change, and font change converge on
one newest generation-owned render configuration. Publish no damage or frame
for a partially rebuilt configuration, and require one full snapshot after the
matching font/atlas resources are ready.

## Background

The terminal core already replaces primary and alternate grids atomically on
resize and marks replacement screens for a full snapshot. The glyph atlas can
reset to a new catalog/scale generation, while the Metal frame format carries
viewport, scale, renderer, and atlas generations. The preceding coordinator
applies strict ordered damage and retains only the newest frame marker.

Two gaps remain. First, `TerminalDamageOutbox` currently retains its original
screen object, even though `TerminalScreenSet.resize` replaces both grids.
Second, full-snapshot acknowledgement is a boolean: an ACK for an earlier full
packet can incorrectly clear a newer scale/font rebuild request made while
that packet is in flight. There is also no state machine that keeps a rebuilt
resource generation and its full damage publication atomic.

## Scope

- Add a monotonic full-snapshot request epoch to `TerminalScreen` and make the
  outbox acknowledge only the exact screen/epoch captured by its in-flight
  full packet.
- Allow an open outbox to rebind to a replacement screen without dropping or
  aliasing the one older in-flight packet; the replacement remains full-dirty.
- Define bounded immutable render targets covering screen identity/dimensions,
  viewport pixels, fixed-point backing scale, and font-configuration revision.
- Coalesce resize/scale/font requests to one newest plan, discard completion of
  superseded plans, validate catalog/atlas generation transitions, and publish
  the screen rebind/full-snapshot request only after resources complete.
- Integrate real CoreText catalog/cache, Dart atlas reset, Metal bridge upload,
  and frame encoding so 1x/2x, resize, and font changes prove matching
  generation/dimension publication.

## Out of scope

- Cursor blink, visual bell, vsync pacing, and occlusion policy; they are the
  next roadmap item.
- Device/shader/drawable failure recovery and renderer recreation; those remain
  in the following recovery item.
- User-facing font preferences, zoom key bindings, split-layout policy, color
  space migration, IME caret geometry, or replacing the normal application
  `TextView` path.
- Waiting for GPU work or calling CoreText from an AppKit event handler. Heavy
  resource work remains a render/font-domain responsibility.

## Dependencies and ownership

- The terminal engine owns resize/reflow and supplies the resulting active
  `TerminalScreen`; the rebuild coordinator never mutates cell contents.
- The outbox owns one in-flight packet plus its captured screen identity and
  full-snapshot epoch. A later screen or rebuild request cannot be cleared by
  the older ACK.
- The render coordinator owns requested/active/published rebuild generations.
  It retains one requested target and at most one synchronous active plan, not
  a per-event queue or built frame.
- Font catalogs remain native generation-owned, shaping cache and atlas remain
  Dart-owned, and Metal retains submitted atlas/frame bytes under its existing
  token/fence rules.

## Ordered subtasks

1. **Coalesced rebuild state and full-snapshot epoch ownership**
   - Add exact full-snapshot epochs and replacement-screen ownership to the
     terminal/outbox boundary.
   - Add the newest-only rebuild target/plan state machine with strict signed
     generation exhaustion and catalog/atlas transition validation.
   - Cover older full ACK versus newer request, resize during an in-flight
     packet, request bursts/reversion, superseded completion, failure retry,
     invalid resource transitions, and constant-size state.
2. **CoreText/atlas/Metal resource rebuild integration**
   - Apply a current plan by retiring pins, replacing/clearing shaping state as
     needed, resetting the atlas for scale/font changes, synchronizing native
     pages, and encoding only the published target generation.
   - Prove resize-only resource preservation, 1x→2x atlas replacement, actual
     font-catalog replacement, stale-entry rejection, full damage publication,
     and matching Metal viewport/scale/atlas headers.

The second child depends on the publication/epoch contract of the first. The
cursor/occlusion roadmap item must not begin until both children are committed.

## Acceptance criteria

- Repeated resize/scale/font events retain one newest target and accumulated
  reason set. A completion for an older plan never publishes resources,
  rebinds the outbox, or clears the newer request.
- Resize rebinds the outbox to the replacement screen without violating the
  one-in-flight rule. An old ACK only affects the exact captured screen/epoch.
- Scale/font changes advance atlas generation; font changes also advance the
  catalog generation. Resize alone may preserve both. No generation regresses
  or wraps.
- The first transferable damage after publication is a full snapshot with the
  target dimensions and resource generation. No frame uses mismatched target,
  catalog, scale, atlas, renderer, or viewport metadata.
- Atlas reset never invalidates a live submission pin. Failure/backpressure
  leaves the newest rebuild pending for bounded retry.

## Verification plan

- Focused pure-Dart epoch/outbox/rebuild state tests, including at least 1,000
  coalesced requests and exact state snapshots before/after rejected actions.
- Focused real CoreText raster/atlas/Metal integration at 1x/2x and two font
  configurations, plus stale object and generation rejection.
- `dart format`, `dart analyze`, product `make test`, focused Release AOT,
  `make runtime-source-check`, and relevant Developer JIT/Release AOT bundle
  audits/integrations.
- Review staged/unstaged diffs and product, adjacent package, and official SDK
  worktrees before each child commit.

## Investigation log

- 2026-09-06: after product commit `5d8ec36`, reread `ROADMAP.md`, `README.md`,
  `FEATURE_MATRIX.md`, ADR-001/003/004, terminal resize/reflow, damage outbox,
  font catalog/cache, atlas reset/bridge, Metal frame/state APIs, AppKit resize
  and backing-scale events, tests, and both worktrees. This parent is the first
  unchecked Phase 4 item and the worktrees are clean.
- 2026-09-06: split the task before implementation because exact terminal/TTD
  ownership and real CoreText/atlas/Metal rebuilding are independent failure
  domains with separate tests and reviewable commits. The state/epoch child is
  prerequisite to publishing any result of the resource-integration child.
- 2026-09-06: a resize replaces `TerminalScreenSet.primary` and `.alternate`;
  therefore a final screen reference inside the current outbox would continue
  publishing the retired grid. Retaining the in-flight packet's captured
  screen separately lets its ACK complete safely while later publication uses
  the replacement grid.
- 2026-09-06: ordinary mutations during a full packet do not require another
  full snapshot, but scale/font/recovery requests do. A dedicated snapshot
  request epoch distinguishes those cases without turning every mutation while
  awaiting ACK into an unnecessary full transfer.
- 2026-09-06: the screen now advances its full-snapshot request epoch for every
  explicit full request and for reset/row-version/logical-line rollover paths.
  An unqualified acknowledgement remains available to direct single-owner
  callers, while the transferable outbox always supplies the exact captured
  epoch. The outbox also retains the captured screen identity in its one
  outstanding record, so resize can switch future publication to a replacement
  grid without redirecting the older ACK.
- 2026-09-06: the rebuild coordinator separates requested, active, and
  published state. It stores one newest requested target and an accumulated
  three-bit reason set. Resource preparation may have one synchronous active
  plan; a newer request makes its completion superseded, and a failure restores
  the same newest plan for retry rather than enqueuing work.
- 2026-09-06: resource transition checks are reason-specific. Resize alone may
  preserve catalog and atlas generations; scale requires a newer atlas; font
  requires both a newer catalog and atlas. Every path rejects regression, and
  signed rebuild generations use an explicit exhausted state before wrap.
- 2026-09-06: integration exposed an empty-grid boundary: the existing native
  Metal API could advance atlas generation only by uploading a nonempty glyph
  rectangle. A blank terminal therefore could not publish a scale/font reset
  without inventing a glyph. The adjacent renderer now exposes ABI-v7
  `resetAtlas`, which atomically advances a strictly newer complete generation,
  zeros every alpha/color slice and page generation, retains no pointer, and
  returns immediate backpressure while any frame slot is active.
- 2026-09-06: adjacent C/C++ header checks, native capability tests, typed Dart
  facade tests, and the full `dart_appkit` suite pass for the empty-atlas reset.
  Tests cover version/reserved/generation validation, prior-page invalidation,
  empty publication, and READY/IN_FLIGHT backpressure. Product manifest and
  bridge consumption remain part of the current integration child.
- 2026-09-06: committed the adjacent ABI-v7 capability as
  `455e112 Add generation-safe Metal atlas reset`, then reread the product
  roadmap before resuming this child. Both adjacent focused checks and its full
  suite passed before that commit.
- 2026-09-06: a rebuild request now pauses only new outbox capture. Any one
  older in-flight transfer keeps its exact screen/epoch ownership and may ACK
  while resource work proceeds. Publication requests a full snapshot on the
  selected screen and releases the pause only after the coordinator accepts
  matching resources.
- 2026-09-06: the atlas bridge now treats native generation zero, a catalog or
  scale-domain change, an explicit Dart-atlas reset epoch, and a same-domain
  generation with no surviving dirty upload as complete-reset paths. A
  successful reset rebuilds slice mappings, snapshots every live page,
  consumes aliased dirty rectangles once, and also publishes a legitimate
  empty generation without a synthetic glyph.
- 2026-09-06: selected one synchronous `TerminalRenderResourceRebuilder` for
  the font/render owner domain. It owns the active catalog and shaping cache,
  waits for all atlas pins to retire, retains prepared work across immediate
  native backpressure, replaces catalog/cache only for font changes, and calls
  the coordinator only after native atlas synchronization. Its frame encoder
  rejects pending rebuilds or any target/catalog/scale/atlas mismatch.
- 2026-09-06: two initial verification invocations used a nonexistent
  product-local SDK `bin/dart`; the configured SDK source root contains the
  executable at `sdk/bin/dart`, while the installed Dart 3.13.2 command is the
  normal product test driver. The first direct Dart analysis also hit the
  filesystem sandbox while updating its telemetry session; rerunning the same
  checks in the approved normal environment succeeded without code changes.
- 2026-09-06: standalone AOT Metal executions returned native internal status
  only inside the filesystem/process sandbox. The same freshly compiled AOT
  tests with the already-tested adjacent renderer dylib passed outside that
  sandbox, matching the established Metal verification procedure. Developer
  JIT and Release AOT application bundles independently passed real GPU/view
  initialization, so this was an execution-environment restriction rather
  than an accepted product failure.

## Verification results

### Coalesced rebuild state and full-snapshot epoch ownership

- `test/render_rebuild_coordinator_test.dart` passes in JIT and as a compiled
  Release AOT executable. It covers an old full ACK versus a newer request,
  resize during an in-flight full packet, exact replacement-grid/resource
  publication, 1,000-request coalescing, active-plan supersession, all three
  accumulated reasons, invalid resource transitions without partial publish,
  failure retry, resize-only generation preservation, request exhaustion, and
  input/owner validation.
- `make test` passes with 94 formatted Dart files, no analysis issues, and
  `dart_terminal tests passed`. Existing terminal-screen, resize/reflow, damage
  codec, and real-isolate transfer cases remain in the combined regression.
- `make runtime-source-check` passes after staging with
  `tracked=175 native_sources=0`; the adjacent `dart_appkit` and bundled Dart
  SDK worktrees remain clean.

### CoreText/atlas/Metal resource rebuild integration

- Focused JIT tests pass for the coordinator, Metal pipeline, and real resource
  rebuilder. The integration opens two real Menlo/CoreText configurations,
  preserves catalog/cache/atlas identity for resize alone, advances the atlas
  for 1x→2x, replaces and disposes catalog/cache for a point-size change,
  rejects retired shaped text and atlas entries, and checks matching Metal
  renderer/viewport/scale/atlas frame fields.
- Damage and frame publication remain blocked from request through completion.
  Each successful resize, scale, and font publication emits one full damage
  snapshot with the target rows/columns and exact atlas generation. A live
  submission pin returns bounded backpressure twice without generation churn;
  releasing it publishes that same plan on the next attempt.
- Empty first attachment and empty same-domain reset tests publish native atlas
  generations through ABI v7 without fake glyph pixels. The bound application
  smoke now performs this reset before seeding the native frame scheduler.
- `make test` passes dependency resolution, generated-parser freshness, 96
  formatted Dart files, analysis, build hooks, the complete CoreText/Metal
  suite, terminal core, real isolate/PTY, and application regressions.
- The focused resource rebuild and existing Metal pipeline tests compile as
  Release AOT executables and pass with the tested adjacent renderer dylib
  preloaded in the normal execution environment.
- Fresh arm64 Developer JIT and Release AOT products pass ABI-v7 Dart-only
  bundle audits and final GUI integrations in 2158 ms and 1998 ms
  respectively.
- `make runtime-source-check` passes after staging all task files with
  `tracked=177 native_sources=0`. Staged and unstaged whitespace checks pass;
  the adjacent repository and bundled official SDK checkout are clean.
- Adjacent dependency commit: `455e112 Add generation-safe Metal atlas reset`.
