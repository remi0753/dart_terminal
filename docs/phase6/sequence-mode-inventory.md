# Phase 6 — ECMA-48, DEC, and xterm sequence/mode inventory

## Task identity

- Date started: 2026-09-06
- Scope: first Phase 6 compatibility-hardening roadmap item
- Status: all three subtasks complete

## Purpose and background

Create one bounded, versioned inventory that says which ECMA-48, DEC, and
xterm control sequences and modes Dart Terminal implements, partially
implements, safely ignores, or does not support. The inventory must be
traceable both to pinned primary specifications and to the actual parser,
screen, reply, input, and OSC behavior in this repository.

Phase 3 established a generated parser table, typed actions, bounded terminal
state, query replies, corpus replay, and fuzz/property coverage. Phase 6 must
turn those individual capabilities into an explicit compatibility management
surface before differential testing or application matrices can be trusted.

## Ordered subtasks

1. **Schema, source pin, and identifier taxonomy**
   - Define bounded versioned inventory records for sequence/mode identity,
     source family, syntax, support state, implementation/test evidence, and
     safety disposition.
   - Pin primary ECMA-48, DEC VT, and xterm control-sequence references with
     stable local citations and define deterministic identifiers for C0/C1,
     ESC, CSI, OSC, DCS, string controls, and modes.
   - Complete when schema validation and representative records pass focused
     tests and the format can express every existing parser action family.
2. **Implementation-derived manifest and freshness checker**
   - Enumerate the repository's implemented parser dispatch, screen/query
     handlers, modes, and OSC/DCS behavior through a checked-in manifest.
   - Add a deterministic checker that fails when relevant source declarations
     change without a reviewed inventory update.
   - Complete when generation/freshness tests and the full repository suite
     pass without weakening parser-table freshness.
3. **Support/gap classification and review acceptance**
   - Fill the inventory with the required ECMA-48/DEC/xterm baseline and mark
     implementation, partial behavior, safe ignore, or unsupported status with
     evidence and limits.
   - Publish human-readable summaries and FEATURE_MATRIX cross-references for
     later differential, `vttest`, real-application, terminfo, OSC-policy, and
     regression-corpus tasks.
   - Complete when coverage totals reconcile, every implemented feature has an
     evidence path, every non-implemented entry has an explicit disposition,
     and all focused/full checks pass.

Each subtask is independently reviewed, documented, verified, committed, and
followed by a ROADMAP reread. The parent remains incomplete until all three are
complete.

## Scope

- ECMA-48 control functions used by terminal emulators, DEC VT100 through
  VT5xx-compatible private controls relevant to the current architecture, and
  the pinned xterm control-sequence baseline.
- C0/C1, ESC, CSI, OSC, DCS, SOS/PM/APC, DEC/xterm private modes, query/reply
  behavior, state ownership, parser recovery, and explicit resource limits.
- Machine-readable checked-in inventory, deterministic validation/freshness,
  human-readable support summary, and evidence links to code/tests/docs.
- Both 7-bit and applicable 8-bit control spellings where the parser contract
  distinguishes or normalizes them.

## Out of scope

- Running xterm/Ghostty/Kitty differentials; that is the next ordered task.
- Deciding the final `vttest` adoption list, real-application compatibility
  matrix, terminfo content, OSC policy, or parser inspector UX.
- Implementing missing terminal sequences merely because the inventory finds
  a gap. Gaps are classified and handed to their correct later roadmap task.
- Exhaustive historical hardware emulation that is not relevant to a modern
  xterm-compatible macOS terminal.
- 24/72-hour soak or another duration-only gate. Per the user-requested ROADMAP
  policy, those remain lower-priority follow-ups and are not blockers by
  omission; bounded correctness/resource failures remain blockers.

## Dependencies and initial facts

- `tool/generate_vt_parser_table.dart` and
  `lib/src/terminal_core/generated/vt_parser_table.g.dart` already make parser
  state/byte classification declarative and freshness-checked.
- `TerminalScreenParserSink`, `TerminalScreenSet`, mode types, reply encoder,
  palette/hyperlink tables, and related focused tests contain semantic behavior
  that cannot be inferred from parser syntax alone.
- Phase 3 corpus/property/fuzz artifacts are evidence, not a substitute for an
  explicit standards inventory.
- The repository and adjacent `dart_appkit` worktrees were clean at task start;
  `dart_terminal` started at `312dc6a`.

## Completion conditions

- The schema is versioned, bounded, deterministic, rejects malformed or
  duplicate records, and represents all required sequence/mode families.
- Primary-source pins and local citations are sufficient for a later reviewer
  to reproduce every classification without relying on chat history.
- Checked-in inventory and relevant implementation declarations cannot drift
  silently; freshness verification is part of the normal test gate.
- Every current implementation maps to at least one inventory record and test
  or documentation evidence; all baseline gaps have explicit safe-ignore or
  unsupported classifications and later-task ownership.
- ROADMAP/FEATURE_MATRIX/docs are synchronized, relevant tests and full gates
  pass, and each ordered subtask has its own completion commit.

## Verification plan

- Focused schema/parser tests for valid families, identifier uniqueness,
  bounds, source pins, evidence paths, ordering, and malformed data.
- Freshness tests against parser action declarations and semantic dispatch
  declarations without parsing arbitrary source text at product runtime.
- Coverage reconciliation over status/family counts plus deterministic rendered
  summaries.
- `CI=true make test` after each subtask; proportional parser corpus and product
  runtime gates when semantic product behavior is affected.

## Investigation log

- 2026-09-06: reread README, ROADMAP, FEATURE_MATRIX, repository structure,
  Phase 3 parser/screen/query documentation list, and both worktrees before
  source changes. Phase 5 is complete and the first unchecked item is this
  Phase 6 inventory.
- 2026-09-06: the inventory item spans standards provenance, a machine-readable
  contract, source-to-inventory drift detection, and a reviewed gap report.
  It was therefore split before implementation into three strictly ordered
  commits with separate completion conditions.
- 2026-09-06: added the user-requested global ROADMAP policy that duration-only
  soak/continuous-use evidence is a low-priority follow-up and not a blocker by
  omission, while correctness, safety, resource-bound, and data-loss failures
  remain blockers.
- 2026-09-06: selected three primary baselines: ECMA-48 fifth edition (June
  1991), DEC VT510 Video Terminal Programmer Information B01
  (`EK-VT510-RM`), and xterm Patch #411 `ctlseqs.ms`. The official ECMA page
  identifies the fifth edition and ISO/IEC 6429 relationship; the DEC manual's
  Part II provides the ANSI/DEC sequence tables; xterm ships its control
  sequence reference in the pinned source archive.
- 2026-09-06: downloaded the exact artifacts to temporary storage, checked
  content lengths/PDF structure, and computed SHA-256 before using them as
  pins. The first parallel downloads of both PDFs and the xterm archive ended
  early and produced invalid/truncated files; those hashes were rejected. The
  ECMA server exposed byte ranges, so its remaining bytes were resumed rather
  than treating a partial PDF as evidence.
- 2026-09-06: accepted artifact evidence is: ECMA-48 PDF 1,607,865 bytes,
  SHA-256 `9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450`
  (108 pages); VT510 B01 PDF 3,378,497 bytes, SHA-256
  `440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514`
  (536 pages); xterm-411 archive 1,633,400 bytes, SHA-256
  `969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c`.
  Its 167,851-byte `xterm-411/ctlseqs.ms` document hashes to
  `69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349`.
- 2026-09-06: a single flat syntax string was considered for records but
  rejected: it cannot distinguish the same final byte across ESC/CSI/DCS or
  make mode/private-marker uniqueness mechanical. The schema will use a typed
  selector union for `c0`, `c1`, `esc`, `csi`, `osc`, `dcs`, `sos`, `pm`,
  `apc`, and `mode`, plus a short display syntax for reviewers.
- 2026-09-06: the first focused analyzer run found that Dart `Uri` exposes
  user information through `userInfo`, not a `hasUserInfo` getter. The URL
  safety check now requires `userInfo.isEmpty`; no schema behavior was relaxed.
- 2026-09-06: added inventory format version 1, revision 1, with strict root
  fields, size/count/text bounds, exact source metadata, typed selector
  decoding, sorted unique identifiers/selectors, safe repository-relative
  evidence paths, and support/disposition consistency rules. The foundation
  fixture contains one representative record for each of the ten selector
  kinds and reports 5 implemented, 1 partial, and 4 bounded safe-ignore cases.
- 2026-09-06: the first sandboxed `dart format` invocation formatted the two
  new Dart files, then failed only while trying to update the external Dart
  telemetry session file. Re-running the zero-diff format check in the normal
  Dart environment succeeded; no formatter failure was hidden.
- 2026-09-06: subtask 1 verification passed: focused `dart analyze`, direct
  manifest validation, and the focused schema regression executable. The
  final `CI=true make test` also passed parser-table freshness, compatibility
  inventory validation, formatting of 143 files, full static analysis, and
  the complete Dart Terminal test runner. The checker summary was
  `version=1 revision=1 sources=3 records=10 implemented=5 partial=1
  safe_ignore=4 unsupported=0`.
- 2026-09-06: after commit `88c27f7`, reread the global duration-only policy
  and Phase 6 ordering. Subtask 2 is now active. Its bounded goal is to expose
  the implemented semantic dispatch surface as product-code declarations,
  generate a checked-in machine manifest from those declarations, and make
  the normal test gate reject stale output. Standards-wide gap classification
  remains subtask 3 and will not be mixed into this commit.
- 2026-09-07: syntax recognition alone was rejected as the implementation
  source because the VT table intentionally accepts generic ESC/CSI/DCS/string
  syntax while semantic support lives in the screen sink. Added a sorted,
  immutable `TerminalCompatibilitySurface` product-code declaration instead.
  The sink now gates controls, ESC/CSI selectors, OSC commands, and ANSI/DEC
  modes through that declaration before its semantic switches. A case cannot
  become reachable merely by changing a switch; its selector must enter the
  declared surface and therefore change the generated manifest.
- 2026-09-07: the implementation manifest contains 65 supported selector
  shapes (11 controls, 9 ESC, 38 CSI, and 7 OSC), 20 set/reset modes (1 ANSI
  and 19 DEC private), and the bounded-unsupported DCS/SOS/PM/APC families.
  Selector keys encode private markers and intermediate bytes, so query forms
  such as DA/DSR/DECRQM cannot collide with ordinary CSI final bytes. Sorted
  list lookup is allocation-free and bounded by at most 38 entries.
- 2026-09-07: generation is deterministic, and both the command-line checker
  and the normal `make test` gate compare the checked-in JSON byte-for-byte.
  Regression coverage also proves that missing or changed output is stale,
  feeds every declared selector and every mode set/reset through the actual
  parser/screen sink, verifies all four unsupported string families are
  consumed exactly once within parser bounds, and checks undeclared examples
  remain explicitly unsupported.
- 2026-09-07: subtask 2 verification passed: focused static analysis, direct
  generation freshness, the 65-selector/20-mode reconciliation executable,
  `PRODUCT_PARSER_CORPUS_PASS` for 8 cases and 1,437 split runs, and final
  `CI=true make test`. The full gate passed parser-table freshness, schema
  validation, implementation-manifest freshness, formatting of 146 files,
  full static analysis, and the complete test runner.
- 2026-09-07: after commit `439ec3e`, reread Phase 6 and confirmed subtask 3 is
  the first unchecked item. The active goal is a reviewed, human-readable
  ECMA/DEC/xterm baseline whose support totals reconcile exactly with all 65
  selector shapes, 20 modes, and four bounded-unsupported families in the
  implementation manifest. Implementing gaps and starting differential tests
  remain out of scope.
- 2026-09-07: the host did not provide `pdftotext`; the bundled workspace PDF
  runtime extracted all 4,644 ECMA-48 lines and all 25,031 VT510 manual lines
  instead. Relevant rendered pages were visually checked after extraction:
  ECMA's presentation-control table and SGR definition preserve the notation
  columns/parameters, while the DEC ANSI table preserves its byte grid. The
  bundled DEC render emitted Fontconfig cache warnings because its packaged
  default cache is not writable, but produced readable PNG output and did not
  change extracted content or source hashes.
- 2026-09-07: full-text review of pinned xterm Patch #411 found that it does not
  document OSC 8 hyperlinks. The earlier foundation citation was therefore
  incorrect. Added the exact official iTerm2 Proprietary Escape Codes page as
  a fourth pin (31,258 bytes, SHA-256
  `b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98`)
  for OSC 7 and OSC 8, and explicitly prohibited attributing OSC 8 to xterm.
- 2026-09-07: generated the revision 2 `complete-baseline` inventory from the
  product declarations plus reviewed gap tables. It contains 260 sorted,
  selector-unique records: 71 implemented, 14 partial, 11 bounded safe-ignore,
  and 164 unsupported/reject. Selector-kind totals are 10 C0, 9 C1, 35 ESC,
  101 CSI, 14 OSC, 8 DCS, 1 each SOS/PM/APC, and 80 modes. The 85
  implemented/partial records exactly reconcile to all 65 sequence and 20 mode
  product declarations; safe-ignore records cover all four bounded string
  families.
- 2026-09-07: the baseline includes all product declarations, terminal-display
  ECMA controls, modern-emulator-relevant VT100–VT510 families, every DEC
  private mode number enumerated by pinned xterm #411, and high-use xterm/iTerm
  CSI/DCS/OSC families. Historical transmission/paged typography, exhaustive
  NRC finals, physical printer/modem variants, Tek details, host-bound key
  output, and later Kitty/Ghostty protocols are explicitly outside this bounded
  review, not silently supported.
- 2026-09-07: a first formatter parse failed because human-readable DCS syntax
  used unescaped Dart `$` literals. Escaping the display-only strings fixed the
  source without changing selector bytes. A later readability review changed
  byte 0x20 in intermediate syntax from literal whitespace to `SP`, yielding
  unambiguous forms such as `CSI SP q`.
- 2026-09-07: generated a human support summary containing the reviewed
  boundary, source pins, exact totals, all partial limits, all bounded ignores,
  later-task ownership, and review acceptance. `FEATURE_MATRIX.md` now links to
  the JSON authority and generated summary and distinguishes implemented,
  partial, safe-ignore, and unsupported behavior for affected capabilities.
- 2026-09-07: the first expanded focused regression run failed only because a
  malformed-fixture assertion expected an older validator message; the second
  exposed a stale one-line JSON fixture shape after pretty-print generation.
  Both tests were corrected to assert the current semantic rule and actual
  multi-line selector form. No validator rule or production classification was
  weakened. Focused analysis and the subsequent inventory regression passed;
  the generator/validator/summary freshness gate also passed with 260/85/4
  exact totals.
- 2026-09-07: subtask 3 final `CI=true make test` passed inventory generation
  freshness, strict schema/source/evidence validation, exact implementation
  reconciliation, generated-summary freshness, the independent implementation
  manifest check, formatting of 148 files, full static analysis, and the entire
  Dart Terminal test runner. No terminal runtime semantics changed in this
  classification subtask, so a product GUI/PTY run was not required for its
  acceptance.
