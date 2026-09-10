# Cwd, title, prompt marks, jump-to-prompt, and close hints

- Status: in progress
- Started: 2026-09-11 after commit `d901085`
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `cwd/title/prompt mark/jump-to-prompt/close hint`
- Feature-matrix owner: CFG-06 (semantic metadata and actions portion)
- Depends on: `docs/phase8/shell-integration.md`,
  `docs/phase7/title-tab-metadata-cwd-proxy-icon.md`,
  `docs/phase7/per-pane-close-app-quit-confirmation.md`, and
  `docs/phase8/declarative-keybind-action-reference.md`

## Purpose

Turn the bounded shell-integration channel into useful, privacy-safe terminal
semantics: authoritative local cwd and title metadata, prompt/command marks,
user actions that move between prompts, and a close hint that improves process
risk classification without weakening the existing confirmation policy.

## Background

- The preceding Phase 8 item now injects a validated, versioned bootstrap into
  zsh, supported bash/fish/nushell launch contracts, and projects each immutable
  launch plan into new ordinary panes. Its resources intentionally publish only
  an execution marker and defer all semantic escape sequences to this item.
- Phase 7 already parses OSC 0/2 titles and local OSC 7 cwd into bounded terminal
  metadata, projects title/cwd to tabs and native proxy icons, inherits cwd for
  later panes, and classifies foreground process-group risk before close.
- The action registry, declarative keybindings, native menu, and command palette
  already share one bounded catalog, but no prompt-navigation actions exist.

## Scope

- Define one versioned, bounded shell-to-terminal semantic protocol for cwd,
  title, prompt start/end, command start/end, and close-relevant shell state.
- Emit that protocol from independently authored zsh/bash/fish/nushell resources
  without recording command text, history, prompt text, or arbitrary environment
  values.
- Parse and retain prompt marks with explicit scrollback/memory bounds and expose
  deterministic previous/next prompt navigation through the existing action
  catalog and pane viewport.
- Reuse the existing local OSC 7/title projection and close coordinator, adding
  only validated semantic inputs that materially improve correctness.
- Add unit/fake-PTY/real installed-shell coverage and M1 Developer JIT/Release
  AOT product acceptance, then update user/evidence documentation.

## Out of scope

- Settings UI/effective-config inspector, which is the following roadmap item.
- Shell command contents, command history, prompt rendering customization,
  telemetry, remote cwd trust, arbitrary URL opening, desktop notifications,
  progress reporting, or Phase 9 protocol extensions.
- Installing optional shells or editing user startup files.
- Weakening existing foreground-process close confirmation or making semantic
  hints authoritative when OS process evidence disagrees.

## Dependencies and boundaries

- Shell output remains untrusted terminal input. OSC/semantic payloads require
  byte/field limits, local-host validation where applicable, and fail-closed
  behavior.
- Mutable prompt marks belong to the pane's terminal model/scrollback owner;
  AppKit receives only product actions and already-bounded presentation state.
- Shell resources and their hash contract must be updated transactionally; any
  mismatch disables the entire integration generation.
- Close hints may refine presentation or avoid a false positive only when
  corroborated by safe process/session state. They may never hide a known live
  foreground process group.

## Initial completion conditions

1. All four shell resources emit the same versioned semantic contract while
   preserving ordinary startup and integration disablement.
2. Local cwd/title metadata remains bounded and drives the existing tab/window,
   proxy-icon, and new-pane inheritance paths without trusting remote origins.
3. Prompt marks survive parsing, wrapping, scrolling, resize, and bounded
   scrollback eviction; previous/next actions move only the intended pane.
4. Close hints compose conservatively with OS foreground-process evidence and
   never reduce an active-process warning incorrectly.
5. Focused tests, resource/source/bundle audits, complete tests, and M1
   Developer JIT/Release AOT product acceptance pass before parent completion.

## Validation approach

- Compare the pinned reference behavior, then document an independent protocol
  and threat model before authoring resources.
- Pure-Dart parser/model/action/close-policy tests, fake PTY launch/output tests,
  and real zsh plus conditional installed-shell execution.
- Generated resource freshness and manifest/bundle audit.
- Focused runtime scenarios, `make test`, and
  `make RUNTIME_ARCH=arm64 runtime-verify` at the final boundary.

## Ordered subtasks

1. Add a bounded OSC 133 `A`/`B`/`C`/`D`/`P` protocol model and parser
   projection. Mark existing screen rows without retaining options, command
   lines, prompt text, or exit status, and expose only a small shell-state hint.
2. Extend all four versioned shell resources to emit prompt/command lifecycle,
   local OSC 7 cwd, and bounded cwd-derived OSC 2 title updates. Regenerate the
   resource contract transactionally and cover startup, opt-out, hook
   coexistence, hostile cwd, and installed-shell behavior.
3. Add deterministic previous/next prompt scanning to the viewport and expose
   focused-pane actions through the shared action catalog, keybinding
   vocabulary, native menu, and command palette. Alternate screens and missing
   marks remain no-ops.
4. Compose the semantic shell-state hint with process snapshots and pane/app
   close admission. A known foreground process or unavailable OS evidence
   always confirms; an idle owning shell executing a builtin/function gains an
   additional confirmation, while unknown/forged semantic bytes can never make
   the pre-existing policy less conservative.
5. Add a gated real-product scenario, pass M1 Developer JIT and Release AOT plus
   the complete regression/resource/source audit matrix, reconcile README and
   feature evidence, and close the parent only after every prior subtask passes.

Each subtask is independently verified, documented, marked complete, and
committed. `ROADMAP.md` and this memo are reread after every commit before the
next subtask begins.

## Current subtask: bounded semantic protocol and row projection

- Status: complete
- Started: 2026-09-11
- Completed: 2026-09-11
- Purpose: convert the already bounded OSC channel into a privacy-safe semantic
  state machine and populate the existing row flags before any shell resource
  starts emitting the protocol.
- Scope: accept only OSC 133 actions `A`, `B`, `C`, `D`, and `P`; reject malformed
  action forms and oversize payloads; ignore all optional fields without
  decoding or retaining them; mark primary/alternate active rows consistently;
  reset transient state at the terminal reset boundary; expose a bounded
  unknown/prompt/input/command-output hint from `TerminalScreenSet`.
- Out of scope: resource changes, navigation actions, close-policy changes,
  runtime UI scenarios, settings UI, command text, exit codes, and OSC 133
  extensions `I`, `L`, or `N`.
- Dependencies: the VT parser's bounded OSC buffer, compatibility surface and
  generated manifest, row damage/generation ownership, scrollback copy/reflow,
  and screen-set reset/alternate-screen semantics.
- Completion conditions: valid markers change only the intended semantic state
  and row flags; malformed/oversize/unknown forms are safely unsupported;
  wrapping, line feed, scrolling, resize/reflow, reset, and alternate-screen
  tests preserve the documented ownership; existing parser compatibility and
  privacy guarantees remain intact.
- Validation: focused parser/screen/viewport/snapshot tests, generated
  compatibility freshness, formatting, analysis, complete tests, source audit,
  diff review, roadmap update, and one task-scoped commit.

## Findings and decisions

- The required post-commit reread confirms `d901085` left both repositories
  clean. The completed shell-integration parent is followed immediately by this
  semantic item; settings/effective-config inspection remains later and must not
  be implemented early.
- The existing terminal model already defines bounded per-row `prompt`,
  `command`, and `output` flags. Scrollback copies them, reflow aggregates them,
  snapshots expose them, and selection/search preserve their aggregate meaning.
  Parser input does not currently set those semantic flags; tests only exercise
  them by assigning flags directly.
- `TerminalScreen.lineFeed()` records hard breaks, wrapping retains semantic
  flags, and the viewport already exposes combined history/screen rows plus
  bounded top/bottom/relative scrolling. Prompt navigation can therefore reuse
  the owning viewport rather than introducing a second history store.
- OSC 0/1/2 title and OSC 7 cwd parsing are already bounded by
  `TerminalSessionMetadata` (1,024 and 4,096 UTF-8 bytes respectively) and reject
  control/bidirectional-control input. Product projection accepts only local
  `file:` authorities (empty host or `localhost`) for inherited paths and native
  represented URLs.
- Existing pane-close policy uses an on-demand, content-free OS process snapshot:
  non-live/idle owning shells close immediately, while a distinct foreground
  process group or unavailable evidence requires confirmation. Semantic terminal
  bytes are untrusted and must never suppress either latter case.
- The exact pinned Ghostty zsh integration at commit
  `d4d8f62262cb1a974a7d2470d5f79f811fab15e4` uses OSC 133 `A` for prompt start,
  `B` for input start, `C` for command/output start, `D` for command completion,
  and `P` for secondary/initial prompts. It refreshes OSC 7 cwd at startup,
  directory changes, and prompts. This is behavioral reference only; the bundled
  implementation will be independently authored and substantially smaller.
- The browser cache could not open exact raw files at the pinned revision. A
  direct read of the pinned zsh resource succeeded. One combined attempt to read
  the fish, nushell, and semantic-parser sources produced truncated output and
  was not usable as evidence; those files will be inspected separately with
  scoped pattern output.
- Separate scoped reads confirmed that the pinned fish integration emits
  `A`, `C`, and `D` around `fish_prompt`, `fish_preexec`, and `fish_postexec`,
  while the pinned nushell resource at that revision contains no semantic
  prompt hooks. The independent four-shell contract therefore cannot merely
  copy reference coverage; nushell needs its own tested hook composition.
- The pinned semantic parser accepts `A`, `B`, `C`, `D`, `I`, `L`, `N`, and
  `P` and can decode command-line options. This product deliberately selects
  only the five lifecycle actions needed by the roadmap and never decodes or
  stores `cmdline`/`cmdline_url`, avoiding a command-history side channel.
- A later scoped source fetch initially failed DNS resolution inside the
  workspace sandbox and succeeded unchanged with approved read-only network
  access. The pinned zsh source confirms cwd refresh at startup, `chpwd`, and
  every prompt; title-on-command includes command text and is therefore
  explicitly rejected for this product's privacy boundary.
- The close-hint design will add warnings only: when the OS reports the owning
  shell as the foreground process group, semantic `C` through `D` may classify
  a same-process shell builtin/function as active. Distinct foreground groups
  and unavailable snapshots retain unconditional confirmation, and an unknown
  hint retains today's behavior.
- The first focused semantic test attempt did not reach Dart tests because the
  renderer build hook tried to create Clang Metal module-cache files under
  `~/.cache`, which the workspace sandbox forbids. Formatting completed (eight
  files checked, three changed). The identical test must be rerun with the
  already-established build-cache write permission; this is an environment
  restriction, not a semantic test failure.
- The permitted rerun reached the new tests and failed the malformed-marker
  count: DEL (`0x7f`) is discarded by the VT parser while inside OSC, so it
  never reaches the semantic payload validator. The case now uses retained
  non-ASCII byte `0x80`, which directly verifies that the selected option
  grammar is printable ASCII only; DEL filtering remains covered by the core
  parser tests.
- After correcting that fixture, the focused semantic, compatibility-surface,
  screen-set, reflow, scrollback, and snapshot tests pass, and focused analysis
  reports no issues. The generated implementation manifest changed only by one
  declared `osc:133` execute selector (82 to 83 total selectors).
- Compatibility inventory freshness then failed as expected because its
  separately reviewed OSC metadata table did not yet describe newly declared
  command 133. This is a real generated-authority update, not a product test
  regression; the metadata and generated inventory/summary must be reconciled
  before completion.
- The first inventory regeneration wrote the updated JSON but summary
  validation rejected the new pinned `ghostty` source family. The inventory
  decoder has an explicit family enum independent of the generator; it must be
  extended transactionally before rerunning generation. No summary file was
  changed by the failed second step.
- The decoder now recognizes the exact pinned Ghostty semantic-parser source as
  a fifth bounded source family, including verified byte count and SHA-256.
  Regeneration and both manifest/inventory freshness gates pass with 261
  records, 15 OSC records, 20 partial records, and 105 reconciled implemented
  selectors/modes.
- Row marking initially bracketed every ASCII scalar to catch autowrap. It was
  tightened to one mark per parser-provided ASCII run plus a destination-row
  mark only when the cursor row actually changes; non-ASCII scalar dispatch
  similarly marks again only after a row transition. This retains wrap
  correctness without repeated row-flag writes in steady output.
- Focused semantic, compatibility-surface, compatibility-inventory, screen-set,
  reflow, scrollback, and snapshot tests pass after regeneration. The tests
  cover lifecycle rows, ignored options, excluded actions, the 256-byte cap,
  malformed bytes, chunk/BEL/ST independence, autowrap, bounded scrollback,
  resize/reflow, alternate-screen ownership, and RIS reset.
- The first complete `make test` progressed through parser-table, trace,
  keybinding/action reference, AppKit evidence, and regression replay, then
  correctly rejected stale compatibility-regression coverage because the
  reviewed inventory boundary gained OSC 133. The coverage reconciliation must
  be regenerated and reviewed before rerunning the complete gate.
- Updating the reviewed inventory/manifest totals let coverage proceed to its
  nested application-acceptance check, which then rejected the old
  implementation-manifest hash. The application evidence generator must be
  refreshed first; only after that dependency can the top-level regression
  coverage report be regenerated.
- Refreshing the manifest pin makes application acceptance pass unchanged
  (8 accepted cells, 3 clean, 5 documented-gap cells). Differential corpus
  checking still reports its baseline stale because that report also hashes
  the changed inventory/manifest inputs; its explicit generator must refresh
  those derived source pins before coverage can close.
- Explicit differential-baseline regeneration passes with the same four cases,
  202 input bytes, and 210 split runs; its observations did not change.
  Differential acceptance then rejected its own stale hash of that regenerated
  baseline, so that next derived report must also be refreshed in dependency
  order.
- Regenerated differential acceptance also retains its prior 12 accepted
  results (8 agreements, 4 unavailable pinned comparators, no documented or
  unexpected gaps), and the top-level regression coverage report now generates
  successfully. The first complete suite then passed every freshness/test
  stage, but analysis reported two non-fatal directive-ordering infos introduced
  by the new export/test import; those directives were reordered before the
  final clean rerun.
- The final analyzer rerun reports no issues. `make runtime-source-check`
  passes with 431 tracked files, zero product native sources, and one reviewed
  test-native source. The final complete `make test` rerun passes all
  freshness, format, analysis, and aggregate Dart tests across 231 formatted
  files.
- Because semantic row projection touches the printable hot path, the Release
  AOT parser benchmark was also rerun: 134,264,777 parsed bytes completed at
  107.84 MiB/s against the 100 MiB/s minimum, with the expected integrity hash
  and no cancel/limit/malformed/incomplete events.
- Final diff review found only the task memo/roadmap split, semantic
  parser/model/tests, the OSC 133 compatibility declaration and its generated
  evidence dependency chain. No `dart_appkit` change was required for this
  pure terminal-model subtask, and `git diff --check` passes.
- The first staging attempt was blocked because the workspace sandbox could not
  create `.git/index.lock`; no paths were staged. The exact explicit path list
  is retried with repository-metadata write permission before commit.
