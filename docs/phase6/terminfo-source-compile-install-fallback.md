# Phase 6 — terminfo source, compile/install, and fallback

## Task identity

- Date started: 2026-09-07
- Scope: fifth Phase 6 compatibility-hardening roadmap item
- Status: in progress

## Purpose and background

Ship an audited terminfo description which matches Dart Terminal's implemented
surface, compile and install it reproducibly into the macOS application bundle,
and keep remote SSH sessions usable when that private bundle is absent. Close
the visible DEC Special Graphics and capability-query gaps promoted by the
pinned real-application matrix instead of hiding them behind a broad xterm
claim.

The product currently exports `TERM=xterm-256color` and `COLORTERM=truecolor`
without a project-owned terminfo source or bundle resource. That is a useful
remote fallback name, but local capability negotiation is controlled by the
host database rather than by the product's reviewed protocol surface.

## Ordered subtasks

1. Add a versioned xterm-256color-compatible source, an explicit compiler
   contract, compiled bundle resource, semantic/freshness validator, tests, and
   a normal Make gate.
2. Resolve the bundled database in product startup, export a local `TERMINFO`
   path only when its compiled entry is valid, and prove the standard TERM name
   remains a remote-safe SSH fallback when private environment state is absent.
3. Implement the observed DEC Special Graphics designation/shift semantics,
   decide bounded XTGETTCAP replies from the advertised capabilities, reduce
   both to byte-level regressions, and rerun the affected real-application
   observations before closing the parent item.

The subtasks are ordered: runtime lookup cannot be accepted before a valid
resource exists, and the final capability/source audit must reflect the
promoted terminal semantics rather than advertising them early.

## Scope

- A repository-owned source and compiled database entry for the standard
  `xterm-256color` TERM name.
- A pinned compiler/version policy and reproducible generation/check commands.
- App-bundle resource declaration and validation of exact relative paths.
- Product environment resolution with a safe no-resource fallback.
- DEC ASCII/Special Graphics G0/G1 designation and SI/SO behavior needed by
  the captured ncurses-class applications.
- A bounded XTGETTCAP reply policy consistent with the source.
- Focused, snapshot, inventory, and real-application regression evidence.

## Out of scope

- Transparent installation on remote hosts or shell-specific SSH wrappers;
  retaining the ubiquitous standard TERM name is the Phase 6 fallback. General
  zsh/bash/fish/nushell shell integration remains Phase 8.
- OSC 52 clipboard advertisement before its later security policy owner.
- ISO-2022 national replacement sets, G2/G3 single/locking shifts, DRCS, or
  hardware-terminal character repertoires without real-application evidence.
- Kitty keyboard, synchronized output, theme reports, title stack, and
  focus/mouse/window queries owned by later ordered items.
- Duration-only soak. Per ROADMAP policy, bounded deterministic substitutes are
  sufficient here; short reproducible corruption or resource failures remain
  blockers.

## Dependencies and initial facts

- The matrix pinned tmux, OpenSSH, mosh, Neovim, Emacs, ncurses, fzf, and
  lazygit and recorded 57,737 PTY output bytes over 32 snapshots.
- Its acceptance trace reduced 526 unsupported-action increments to 28 observed
  byte variants in 16 owned groups. Character-set designation is the sole
  immediately owned visible-content gap; XTGETTCAP is a capability-fallback
  gap.
- `TerminalSession` currently supplies the standard TERM name with
  `putIfAbsent`; deterministic application runners also use that name.
- `macos_application.json` currently declares no resources. The adjacent
  runtime builder copies each declared file below `Contents/Resources` using
  the manifest-relative path, and `MacosRuntime.bundleResourcePath` exposes
  resource lookup to Dart.
- Homebrew ncurses 6.6.20251230 and macOS ncurses 6.0.20150808 were observed
  during the preceding matrix task. The exact compiler selected for committed
  output, and the compatibility policy for a different local compiler, still
  require inspection.

## Risks and design boundaries

- A custom TERM name would make an ordinary `ssh` PTY advertise an entry which
  is normally missing remotely. Keeping `xterm-256color` as the primary name
  allows the application bundle to override local lookup through `TERMINFO`
  while remote hosts naturally use their standard database after that private
  path disappears.
- Blindly inheriting every local `xterm-256color` capability could advertise
  behavior the terminal does not implement and make output less safe. The
  source and compiled semantic projection therefore need an explicit audit.
- Compiled terminfo layout and byte encoding may differ by ncurses generation.
  The checked artifact needs a pinned producer and a semantic validator; an
  arbitrary host compiler must not silently rewrite it during a normal check.
- Ignoring `ESC ( 0` is visible corruption: following ASCII-range bytes carry
  DEC line-drawing meanings. Character-set selection must be terminal state,
  survive relevant cursor save/restore boundaries, reset deterministically,
  and be included in snapshot evidence.
- XTGETTCAP payloads are untrusted DCS input. Hex parsing, name count, payload,
  and reply size must remain bounded, with unknown or security-sensitive
  capabilities denied explicitly.

## Completion conditions

- All three ordered subtasks are individually verified, documented, checked in
  ROADMAP, and committed.
- A clean app build contains a validator-approved compiled database at the
  manifest-declared path; stale source, compiler metadata, manifest paths, or
  compiled semantics fail the normal gate.
- Product startup uses the private database only when it exists and validates,
  otherwise keeps a functional standard `TERM=xterm-256color` environment.
- A remote-style environment without the private `TERMINFO` path resolves the
  standard entry and never advertises a project-only TERM name.
- Captured character-set and XTGETTCAP inputs have minimal byte regressions,
  deterministic snapshots/replies, bounded malformed-input behavior, and
  updated inventory/matrix classification.
- README, FEATURE_MATRIX, task notes, and Phase 6 ownership records agree; the
  full repository gate passes before each completion commit.

## Verification plan

- Validate source metadata, capability allow/deny sets, compiler identity,
  compiled `infocmp` projection, exact resource paths, and committed hashes.
- Run focused generator/validator negative fixtures for missing tools, stale
  artifacts, malformed source, semantic drift, and path escape.
- Build Developer JIT and Release AOT bundles and inspect the installed entry.
- Test direct product, app-bundle, absent-resource, and remote-style
  environment resolution without changing the user's shell configuration.
- Replay designation, SI/SO, save/restore, reset, alternate-screen, UTF-8, and
  malformed inputs over whole, split, and bytewise delivery.
- Replay bounded real-application scenarios whose traces contained character
  set or XTGETTCAP gaps and update exact acceptance evidence.
- Run formatting, static analysis, focused tests, bundle audit/integration as
  relevant, and `CI=true make test`; record every result below.

## Investigation log

- 2026-09-07: after commit `31218c8`, ROADMAP was reread with a clean worktree.
  README, FEATURE_MATRIX, vttest dispositions, matrix acceptance, and Phase 6
  exit conditions were reviewed. This item is the first unchecked task.
- 2026-09-07: the work spans independently reviewable source/build, runtime
  environment, and terminal-semantics boundaries. The three ordered subtasks
  above were registered in ROADMAP before implementation; none is complete at
  this point.
- 2026-09-07: the first formatter invocation found an unterminated negative-test
  replacement string before generation ran. That fixture now replaces the
  entire JSON property through a bounded regular expression. The same command
  also encountered Dart telemetry's sandbox-denied home-directory timestamp;
  subsequent Dart tool invocations require the established external execution
  permission and the failed run is not treated as verification.
- 2026-09-07: the first permitted generator compile stopped before invoking
  ncurses because Dart did not promote a nullable `Object?` through the custom
  assertion helper. The JSON text reader now introduces an explicit local
  `String` after validation; no contract condition was relaxed.
- 2026-09-07: the next generator run exposed a macOS path assumption in its
  executable preflight: `test` is `/bin/test`, not `/usr/bin/test`. The helper
  now uses the baseline's absolute system path; the requested ncurses binary
  itself was present and had not yet been executed by that failed run.
- 2026-09-07: generation with ncurses 6.6.20251230 succeeded. The audited
  projection contains 289 effective/cancelled capability records and produced
  a 3,761-byte `78/xterm-256color` entry. A focused regeneration check and the
  contract's negative parser tests both passed.
- 2026-09-07: Developer JIT and Release AOT app bundles built and passed the
  Dart-only bundle audit after that audit was extended to require the exact
  reviewed terminfo hash below `Contents/Resources`.
- 2026-09-07: the first full gate completed all tests, but static analysis
  reported one directive-ordering info for the newly added test import. The
  import was placed in lexical order; the run is retained as a failed clean-gate
  attempt and must be repeated.
- 2026-09-07: the repeated full gate passed with no formatting drift or analyzer
  issue. The first subtask is complete: source, producer/base provenance,
  compiled bytes, semantic capability projection, deny policy, and both bundle
  copies are now independently checked. Runtime lookup remains deliberately
  untouched until the next ordered subtask.
- 2026-09-07: after commit `a78b962`, ROADMAP was reread with a clean
  worktree. The second subtask is now current. `MacosRuntime` resolves a
  declared file relative to `Contents/Resources` and rejects a missing file;
  the product can therefore distinguish the bundled path from a no-resource
  fallback without guessing its installation directory.
- 2026-09-07: the compiled entry begins with ncurses magic `0x011a`, a bounded
  66-byte names section, and the primary name `xterm-256color`. Runtime
  validation checks the regular-file layout, 32 KiB bound, accepted ncurses
  magic, bounded names section, and audited name before exporting its database
  root. The code signature plus bundle audit remains the exact-byte integrity
  boundary; runtime parsing does not duplicate the build-time SHA-256 engine.
- 2026-09-07: macOS OpenSSH 10.3p1 `ssh_config(5)` states that `SendEnv`
  variables require client selection and server acceptance, while `TERM` is
  always sent when a pseudo-terminal is requested because the protocol
  requires it. Therefore the Phase 6 remote contract contains the standard
  TERM name only and never carries the local `TERMINFO` path. General shell
  wrappers and remote entry installation remain Phase 8.
- 2026-09-07: focused runtime tests passed valid bundle, absent bundle,
  malformed/truncated entry, wrong layout, inherited-environment replacement,
  and remote PTY projection. Focused static analysis reported no issues.
- 2026-09-07: Developer JIT and Release AOT display integrations both launched
  the actual AppKit product and persistent PTY. The login zsh observed the
  standard TERM name and successfully resolved the bundled entry through
  `/usr/bin/infocmp -A "$TERMINFO"`; the content-free runtime evidence also
  confirmed the SSH projection excludes the local database path.
- 2026-09-07: the full normal gate passed after the product integration. The
  second subtask is complete: ordinary product sessions receive the validated
  local database, malformed/missing resources fail closed, and the remote PTY
  contract retains the standard name without a private path. Character-set and
  XTGETTCAP semantics remain untouched until the final ordered subtask.

## Decisions

- Keep the primary TERM name `xterm-256color`. Locally, a private `TERMINFO`
  root selects Dart Terminal's audited entry; remotely, omission of that local
  path naturally selects the host's standard entry. This avoids a shell-wrapper
  dependency in Phase 6 and leaves richer remote installation to Phase 8.
- Product startup overrides inherited `TERM` and `COLORTERM`, and replaces an
  inherited `TERMINFO` only after validating the bundled entry. Missing or
  malformed resources clear that explicit private lookup and fall back to the
  standard TERM name. This avoids advertising a stale local database while
  preserving unrelated child environment fields.

## Verification log

- `dart run tool/terminal_terminfo.dart --check`: pass; 289 capability records,
  exact 3,761-byte producer regeneration, source/base/artifact/semantic hashes,
  deny list, and manifest resource path all matched.
- `dart run test/terminal_terminfo_test.dart`: pass; schema, path, hash,
  allow/deny overlap, and normalized `infocmp` projection checks passed.
- `make developer-jit-audit release-aot-audit`: pass on M1/arm64; both signed
  bundles contained the reviewed entry and passed architecture/linkage/resource
  audits.
- First `CI=true make test`: all runtime tests passed, but the analyzer emitted
  one import-order info. This is not the final clean verification result.
- Repeated `CI=true make test`: pass; all freshness gates passed, 172 files were
  already formatted, static analysis reported no issues, and the full Dart
  Terminal test runner passed.
- `dart run test/terminal_terminfo_environment_test.dart`: pass; valid,
  missing, malformed, wrong-layout, inherited-variable, and SSH projection
  cases passed.
- Focused `dart analyze`: pass with no issues in the resolver, product hookup,
  tests, and integration checker.
- `make runtime-terminal-display-integration`: pass in Developer JIT and
  Release AOT on M1/arm64. Actual login shells resolved the bundled database;
  elapsed application runs were 2,707 ms and 1,945 ms respectively.
- `CI=true make test`: pass; all freshness gates passed, 174 files were already
  formatted, static analysis reported no issues, and the complete Dart
  Terminal test runner passed.

## First-subtask artifact record

- Source SHA-256: `f920fe80249c264062439212222b325c127fb2e7b02bb67b5fa83872292bbfb3`
- Pinned base `infocmp` SHA-256:
  `5518916deefe8e29efd5bfddef564b45350cdb1eb450cae4045fc4ecef300291`
- Compiled SHA-256:
  `d2ab9d9bb2ed1caf8937920687307bfd1f8ebed80e54587d9d4d1d2884049b39`
- Compiled semantic projection SHA-256:
  `f845fec722fe4e6ccd97371d409d39bc4f33edc4ba450db9f68fd4d460c97c7e`
- Producer: `/opt/homebrew/opt/ncurses/bin/tic`, ncurses 6.6.20251230,
  `-x -e xterm-256color -o <temporary-root>` after compiling the pinned
  standard projection under `dart-terminal-pinned-xterm-base`.

## Handoff and blockers

- No blocker is known at task start.
