# Phase 6 — Compatibility bug regression corpus

## Identity and status

- Date started: 2026-09-07
- Scope: ninth and final Phase 6 compatibility-hardening roadmap item
- Current status: corpus contract, harness, and reviewed cases complete;
  coverage reconciliation and Phase closure is next

## Purpose and background

Phase 6 resolved application-observed gaps across DEC character sets,
capability queries, OSC metadata/policy, input-report modes, and query replies.
Each implementation has focused tests, but there is no single reviewed index
that proves every compatibility fix has a minimal byte input, exact observable
result, arbitrary-chunk replay, and an owner. The phase exit condition requires
that relationship to remain enforceable rather than relying on commit history
or prose.

This task creates the final versioned compatibility regression corpus and a
normal-gate reconciliation report. It does not use the new content-conscious
parser trace as an expected screen oracle: the trace diagnoses parser actions,
while this corpus must assert resulting screen, mode, metadata, policy counter,
and reply semantics.

## Ordered implementation units

1. **Versioned corpus contract, harness, and reviewed cases**
   - Define strict case IDs, source ownership, lowercase byte input, bounded
     terminal geometry, exact normalized observations, and hard corpus limits.
   - Cover DEC Special Graphics, audited XTGETTCAP, title stack/metadata,
     cursor color, default-deny OSC 52, focus mode, SGR pixel-mouse mode,
     DECRQSS SGR, and XTVERSION/XTWINOPS.
   - Replay each case as one chunk, every single split, and bytewise; compare
     complete canonical screen snapshots as well as reviewed projections.
2. **Coverage reconciliation, normal gate, and Phase closure**
   - Generate/check a deterministic report linking every required Phase 6 fix
     family to one or more passing corpus cases and documentation owners.
   - Revalidate differential and real-application acceptance, inventory
     disposition, parser trace freshness, README/FEATURE_MATRIX, and all tests.
   - Close the parent roadmap item and Phase 6 only when no required fix family
     is unowned and no known P0 silent corruption remains.

Each implementation unit is documented, verified, marked complete, and
committed before the next unit starts.

## Scope

- A versioned source-controlled manifest of minimal terminal byte streams and
  exact normalized post-parse observations.
- Full terminal snapshot equivalence under whole, every-single-split, and
  bytewise replay.
- Exact replies, parser/policy counters, mode state, metadata, palette/cursor
  color, text, and relevant resource projections.
- A deterministic coverage report/freshness gate for all reviewed Phase 6
  compatibility-fix families.

## Out of scope

- Implementing any remaining Phase 9 input, presentation, theme, or graphics
  gaps from the accepted application matrix.
- Reclassifying evidence-backed highlight mouse mode 1001 non-adoption without
  a captured enable/handshake use case.
- Replacing focused unit, product PTY, application-matrix, differential, or
  parser-inspector tests; the corpus reconciles them and adds a common byte
  boundary.
- Renderer, native input, clipboard UI, or application UX regressions that do
  not originate in a terminal byte stream.
- Thirty-day or duration-only soak. Per the roadmap-wide policy it remains a
  low-priority, nonblocking follow-up. Any bounded correctness, resource,
  safety, data-loss, or silent-corruption failure remains a blocker.

## Dependencies and initial facts

- The implementation manifest currently declares 104 selectors/modes against
  a 260-record inventory: 85 implemented, 19 partial, 9 safe-ignore, and 147
  explicit unsupported records.
- Current immutable application replay has 3 clean cells and 5 documented-gap
  cells, with 8 gaps, 12 variants, and 71 unsupported increments. All remaining
  gaps have explicit later ownership or the reviewed mode-1001 non-adoption;
  no known P0 cell is classified as silent agreement.
- Differential acceptance has 8 agreements (including one semantic Kitty SGR
  agreement), no documented gaps, and 4 unavailable Ghostty captures.
- Existing focused tests already prove the individual implementations. The new
  corpus must reference those owners but independently replay raw bytes through
  `VtParser` and `TerminalScreenParserSink`.

## Required fix-family coverage

1. DEC G0/G1 designation and Special Graphics translation.
2. Audited XTGETTCAP success and explicit negative reply policy.
3. Bounded OSC title/cwd/hyperlink metadata and CSI title-stack restore.
4. OSC palette/default/cursor-color mutation, query, and reset boundaries.
5. Default-deny OSC 52 query/write/clear/rejection behavior.
6. DEC focus-reporting mode 1004 state and DECRQM reply.
7. SGR pixel-mouse mode 1016 state and DECRQM reply, with mode 1001 remaining
   outside implemented coverage by explicit non-adoption.
8. Bounded DECRQSS SGR current-state reply.
9. Stable XTVERSION and XTWINOPS logical-pixel/character reports.

## Completion conditions

- Every required fix family maps to at least one unique, source-owned case.
- Each case has byte-exact input and expected replies plus a complete normalized
  observation; whole/split/bytewise terminal snapshots and observations match.
- Corpus limits reject excess cases, bytes, geometry, fields, or output before
  accepting an oracle.
- Coverage report generation is deterministic and `--check` rejects stale,
  missing, duplicate, or unknown family/case ownership.
- Parser trace, inventory, differential, application, terminfo, analyzer,
  formatter, and complete test gates all pass.
- ROADMAP and feature records state that duration-only soak remains a follow-up
  rather than falsely presenting it as completed evidence.

## Verification plan

- Focused corpus schema, negative validation, exact-observation, whole/split/
  bytewise, and snapshot-equivalence tests.
- Coverage report normal/freshness and mutation-negative tests.
- Existing differential/application/inventory/trace checks.
- `dart analyze`, `git diff --check`, and `CI=true make test` for each unit.

## Investigation and decision log

- 2026-09-07: after commit `596a7b1`, ROADMAP was reread with a clean worktree.
  The compatibility regression corpus is the only remaining Phase 6
  implementation item; Phase 7 work must not begin in this session.
- 2026-09-07: reread README, FEATURE_MATRIX, all Phase 6 task records, existing
  parser/differential/application corpora, normal-gate targets, and the Phase 6
  commit range. The required families above are the byte-stream-controlled
  compatibility fixes completed in this phase; native-only rendering and
  selection regressions remain in their owning Phase 4/5 suites.
- 2026-09-07: split the task because executable corpus semantics and the final
  completeness/phase decision are independently reviewable. The first unit
  cannot mark the parent complete; the second must reconcile all owners and
  accepted remaining gaps before closure.
- 2026-09-07: selected one strict normalized observation for every case:
  SHA-256 and UTF-8 length of the complete version 3 terminal snapshot, a
  reviewable projection of state/resource/content lines, concatenated reply
  bytes, global input modes and metadata not present in the snapshot, and all
  parser/reply/hyperlink/OSC 52 policy counters. Snapshot equality across chunk
  plans detects state outside the readable projection while the projection
  keeps each oracle auditable.
- 2026-09-07: the corpus accepts at most 32 cases, 256 input bytes per case,
  4,096 aggregate input bytes, 8x32 grids, 4,096 reply bytes, and 128 KiB
  snapshots. IDs, owner paths, exact fields, lowercase byte-aligned hex,
  geometry, counts, hashes, and output sizes are validated before replay.
- 2026-09-07: reviewed the generated observations before fixing them as the
  expected manifest. The nine cases contain 390 input bytes and exercise 417
  plans: one whole plan, every split including empty edges, and bytewise input
  per case. Mode 1004 and 1016 produce identical screen snapshots because that
  snapshot intentionally excludes screen-set input modes; the separate exact
  state projection distinguishes focus reporting from `sgrPixels` encoding.
- 2026-09-07: negative tests reject invalid hex, excess case bounds, unsafe or
  nonexistent owner paths, duplicate IDs, and an expected-observation change.
  Regeneration remains explicit and reviewable; normal checking never updates
  the source oracle.

## Verification results — corpus contract and cases

- `dart run tool/terminal_compatibility_regressions.dart --inspect`: passed all
  417 replay plans and printed the review candidate for nine cases before the
  expected observations were written.
- `dart run tool/terminal_compatibility_regressions.dart --generate` followed
  by `--check`: fixed and accepted 9 fix families, 390 input bytes, and 417
  whole/split/bytewise runs.
- `dart run test/terminal_compatibility_regressions_test.dart`: passed exact
  case/family totals, snapshots, projections, states, replies, counters, and
  all negative schema/ownership/oracle mutations.
- `dart analyze`: passed with no issues.
- `CI=true make test`: passed every existing parser-trace, inventory,
  differential, application, terminfo, formatting, analyzer, and unit gate;
  all 186 Dart files were already formatted and the complete test runner
  passed.
- `git diff --check`: run in the final pre-commit review.

## Verification results — coverage and Phase closure

- Pending the second ordered unit.
