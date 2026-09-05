# Phase 4 — Resize, scale, and font full rebuild

- Status: in progress
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
