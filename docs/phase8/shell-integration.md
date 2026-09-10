# zsh, bash, fish, and nushell integration

- Status: in progress
- Started: 2026-09-10
- Primary environment: macOS 14 or later on Apple M1/arm64
- Roadmap item: Phase 8 `zsh/bash/fish/nushell integration`
- Feature-matrix owner: CFG-06 (shell injection portion)
- Depends on: `docs/phase8/typed-config-schema-diagnostics.md`,
  `docs/phase8/product-option-families.md`, and
  `docs/phase6/terminfo-source-compile-install-fallback.md`

## Purpose

Provide an explicit, bounded, and disableable product contract that starts each
supported interactive shell with Dart Terminal's shell-integration bootstrap,
without replacing the user's shell startup files or weakening normal shell and
remote-PTY behavior.

## Background

- The ordinary product currently starts one login `/bin/zsh` per pane.
  `TerminalSession` already accepts an executable, arguments, environment, and
  working directory, but `TerminalProductConfiguration` has no shell or shell-
  integration fields and the application projects none.
- Phase 6 sets local `TERM=xterm-256color` and a validated bundle-local
  `TERMINFO`, while deliberately omitting the private `TERMINFO` path from the
  SSH PTY environment. Shell integration must preserve that boundary.
- The following roadmap item owns cwd/title/prompt marks, jump-to-prompt, and
  close hints as product semantics. This item owns supported-shell selection,
  bootstrap resources, safe injection, opt-out, and execution validation; it
  must not prematurely add the later UI/action behavior.
- zsh 5.9 and bash 3.2.57 are installed on the M1 host. `fish` and `nu` are not
  currently found on `PATH`, so their resource and launch contracts must be
  testable without making those optional user shells build dependencies.

## Scope

- Determine the fixed comparison source's injection and opt-out behavior for
  zsh, bash, fish, and nushell, then define an independent Dart Terminal
  contract.
- Add bounded typed new-session configuration for the shell executable and
  shell-integration enable/disable policy.
- Package versioned, ordinary resource files for all four shells and resolve
  them only through the application bundle/resource boundary.
- Select a supported integration by executable identity, prepare shell-specific
  startup arguments/environment without overwriting a user's startup files,
  and fall back to a normal shell for disabled, unsupported, missing, or invalid
  integration resources.
- Preserve `TERM`, validated local `TERMINFO`, login-shell behavior, working
  directory inheritance, environment bounds, and ownership by the pane's
  `TerminalSession`.
- Add deterministic unit/integration coverage plus M1 Developer JIT and Release
  AOT product acceptance for installed shells and resource/audit coverage for
  optional fish/nushell.

## Out of scope

- Product handling and UI for semantic prompt marks, jump-to-prompt, cursor
  shape, title/cwd enrichment, and close-confirmation hints; the next roadmap
  item owns those behaviors.
- Installing or managing user shells, editing home-directory startup files,
  running remote installers, forwarding private local resource paths over SSH,
  or sourcing untrusted configuration on behalf of a shell.
- Shell command history, command contents, prompt contents, environment dumps,
  telemetry, or automatic command execution.
- Settings UI and effective-configuration inspection.

## Dependencies and boundaries

- Shell selection and integration policy are immutable new-session values.
  Reload may affect later panes but never mutates a live shell process.
- The product repository owns portable text resources and typed launch-plan
  composition. PTY process creation remains in `dart_pty_macos`; AppKit does
  not inspect shell content.
- Integration resource resolution must use declared bundle resources in the
  packaged product and injected deterministic paths in pure-Dart tests.
- Optional shell absence is not a terminal-app launch failure. An explicitly
  configured missing executable follows the existing session start failure
  policy and retains an actionable non-live pane.
- Integration disabled or unavailable must leave the selected shell's ordinary
  interactive/login startup behavior intact.

## Ordered subtasks

1. Add bounded `shell` and `shell-integration` schema values, immutable product
   profile fields, supported-shell classification, and a pure-Dart launch-plan
   boundary. The planner must preserve the input environment transactionally
   when detection or resource validation fails; it is not connected to the
   ordinary product in this commit.
2. Add independently authored, versioned bootstrap resources for zsh, bash,
   fish, and nushell, plus a deterministic hash/size contract, manifest
   declarations, freshness tests, and bundle-audit coverage. These resources
   establish only a versioned integration marker and clean up temporary
   injection state; semantic prompt features remain deferred.
3. Resolve the declared integration contract at application startup, project a
   per-pane launch plan into `TerminalSession`, and verify normal/disabled/
   unsupported/missing-resource paths with fake PTYs and real installed shells.
   Automatic `/bin/bash` detection on Darwin must take the documented safe
   fallback; an explicitly forced bash policy retains an opt-in test path.
4. Add a gated M1 product scenario and verify the same bundle-contained shell
   contract in Developer JIT and Release AOT, update user/evidence documents,
   run the complete gates, and complete the parent only if every earlier
   subtask and the Phase 8 exit invariant remain satisfied.

Each subtask is documented, verified, marked complete, and committed before
the next begins. After each commit, reread `ROADMAP.md` and this memo.

## Completion conditions

1. The typed schema validates bounded shell selection and integration policy,
   preserves current zero-config `/bin/zsh`, and applies changes only to new
   sessions.
2. zsh, bash, fish, and nushell each have a declared, versioned integration
   resource and a tested launch plan that does not overwrite user files.
3. Disablement, unsupported-shell, missing/corrupt-resource, nested terminal,
   SSH, and user-startup compatibility paths fail closed to an ordinary shell
   without leaking a private bundle or terminfo path remotely.
4. Installed zsh/bash execute the integration and ordinary startup behavior in
   real PTYs; fish/nushell are covered by byte/resource/argument contract tests
   and by real-shell acceptance when available.
5. Formatting, analysis, complete tests, source/bundle audits, and M1 Developer
   JIT/Release AOT product acceptance pass before the parent roadmap item is
   completed.

## Verification plan

- Pure-Dart schema, executable classification, resource validation, launch-plan,
  opt-out, fallback, and remote-environment tests.
- Real PTY probes for zsh/bash and conditional fish/nushell probes when their
  executables exist; deterministic fake executables validate all four argument
  and environment contracts on every host.
- Manifest/resource freshness and bundle audit checks.
- `dart format`, `dart analyze`, focused tests, full `make test`, and
  `make RUNTIME_ARCH=arm64 runtime-verify` at the appropriate subtask boundary.
- Final `git diff --check`, staged-diff review, and task-scoped commits.

## Findings and decisions

- The worktree was clean on `main` after commit `d332de4`; the branch was 17
  commits ahead of `origin/main` when this task began.
- The first startup inspection combined README, feature matrix, roadmap, and a
  repository-wide search in one command. Its 13,108-token output was truncated,
  so it was not used as evidence; subsequent reads are file- and range-scoped.
- A follow-up search contained an unmatched quote due to a literal backtick in
  the shell command and failed before searching. The command was corrected by
  removing shell-sensitive punctuation; no files were changed by either failed
  attempt.
- `TerminalSession` currently defaults to `/bin/zsh`, makes all sessions login
  shells through `PtyCommand.loginShell`, and injects `TERM` and `COLORTERM` only
  when absent. Its executable/argument/environment inputs are already explicit
  and immutable, which is the correct lowest-level projection boundary.
- `TerminalProductConfiguration` currently resolves presentation, history,
  cursor, and keybinding options only. The earlier option-family memo explicitly
  deferred shell executable, arguments, environment integration, prompt marks,
  and close hints to this point in Phase 8.
- This host reports zsh 5.9 and bash 3.2.57. No `fish` or `nu` executable was
  found. Optional shells will therefore not become required build/test tools.
- A preliminary search did not find shell-integration files in the initially
  guessed fixed-source paths. The archive/mount layout must be resolved before
  adopting a comparison-derived contract.
- The guessed local fixed-source directories are empty except for a dangling
  repository instruction symlink. The exact pinned commit was therefore read
  from the official Ghostty GitHub repository. Its setup keeps failures
  transactional, detects shell type by executable identity, skips automatic
  `/bin/bash` integration on Darwin, uses `ZDOTDIR` for zsh, uses POSIX `ENV`
  for supported bash, and prepends a temporary `XDG_DATA_DIRS` root for fish
  and nushell. Forced shell selection is distinct from automatic detection.
- The fixed-source zsh bootstrap restores the original `ZDOTDIR`, loads the
  user's original `.zshenv`, and then runs integration; fish removes the
  injected XDG entry after its vendor script loads. These cleanup properties
  are adopted as behavior, not source code. Ghostty's scripts are GPL-derived,
  so Dart Terminal will use small independently authored resources with its
  own version marker and no copied implementation.
- The GNU Bash reference confirms that POSIX interactive startup reads `ENV`
  instead of normal startup files, so an injected bootstrap must recreate the
  applicable user startup sequence before leaving POSIX mode. The fixed source
  documents that Apple's patched `/bin/bash` disables this automatic route;
  detect mode will fail closed rather than silently replacing startup behavior.
- Official fish documentation confirms that `fish/vendor_conf.d/*.fish` under
  each `XDG_DATA_DIRS` entry is loaded during startup. Official nushell
  documentation confirms the corresponding
  `nushell/vendor/autoload/*.nu` paths. A temporary root is therefore adequate
  for both without changing the user's config directory.
- `PtyCommand` already validates absolute executables and NUL-free arguments/
  environment. Its `loginShell` flag changes only `argv[0]` to `-<basename>`,
  so the planner can retain login identity while supplying shell-specific
  arguments.
- `MacosRuntime.bundleResourcePath` validates one declared relative resource
  and returns an absolute bundle path. The integration contract file will be
  the root locator; each script will also be declared and independently audited.
- A GitHub tree query initially failed because zsh expanded the unquoted `?` in
  the URL as a glob. Quoting the URL returned the exact pinned resource list.
- One later raw nushell fetch encountered transient DNS failures after earlier
  pinned files succeeded. Official nushell documentation and the pinned tree
  establish the directory contract; the source fetch can be retried before its
  resource is authored and is not currently a blocker.
- The first subtask's initial formatter normalized three Dart files. The
  following targeted analyzer did not start because the restricted sandbox
  denied a modification-time update to Dart's user telemetry session file,
  despite `DART_SUPPRESS_ANALYTICS=true`. This is an environment failure, not a
  source diagnostic; the identical checks are rerun with the repository's
  established `CI=true` approved environment.
- The first shell-focused test initially expected two invalid CLI values to
  appear as recoverable snapshot diagnostics. It instead raised the existing
  `FormatException` at the first invalid command-line override. The test now
  checks actionable decoder failures separately and fixes the intentional
  distinction: invalid file values recover, while invalid CLI syntax/value is
  fatal.
- The product schema now contains 36 options. `shell` accepts only an absolute,
  control-free executable path within 4096 UTF-8 bytes; `shell-integration`
  accepts `detect`, `none`, or one explicitly forced supported shell. Both are
  immutable new-session values, so a reload cannot mutate a live process.
- `TerminalShellIntegrationPlanner` returns one immutable, content-free plan.
  Disabled, unknown, nonempty-argument, automatic Apple bash, unavailable-
  resource, and environment-limit outcomes retain the exact original argv and
  environment. Only a successful plan publishes mutations.
- Successful zsh planning preserves an existing `ZDOTDIR` and points zsh at
  the integration directory. Bash preserves `ENV`, adds one POSIX startup
  argument, and records an explicit injection flag. Fish and nushell prepend
  the shared XDG resource root while retaining an existing or standard default
  data-directory list; nushell also receives its module import expression.
- Injected and parent environment values are capped at 64 KiB each. Resource
  roots must be absolute, NUL-free, within 4096 UTF-8 bytes, and declare which
  shell contracts were validated. The future resource loader can therefore
  fail closed by passing no validated set.
- Targeted format, analyze, schema/profile tests, and the new planner suite pass
  after correcting the invalid-CLI expectation. The suite covers every policy,
  default values, reload classification, immutable inputs/outputs, all four
  launch strategies, Apple bash fallback, forced bash, missing/partial
  resources, original startup-variable preservation, XDG defaults, arguments,
  and environment limits.
- The first aggregate gate completed successfully, including every generated
  compatibility/terminfo/reference check and `dart_terminal tests passed`, but
  the analyzer reported one non-fatal directive-ordering info for the newly
  added aggregate-test import. The import was reordered. The provisional
  source audit reported `tracked=418`; because the new files were still
  untracked, source audit and the aggregate gate are repeated after staging so
  they cover the complete commit candidate.
- After the import-order correction, the final pre-staging
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed with 225 Dart files
  unchanged by formatting, no analyzer issues, all generated evidence fresh,
  and `dart_terminal tests passed`. Compatibility coverage was regenerated
  after the README/feature-matrix update and passed with 9 families, 9 cases,
  and 417 split runs.
- The post-staging source audit includes all three newly tracked files and
  passes with `tracked=421`, zero product native sources, and the one existing
  reviewed test-native fixture. `git diff --check` also passes for the complete
  staged candidate.

## Resolved split questions

- The exact comparison owners are
  `src/termio/shell_integration.zig`, `src/shell-integration/README.md`, and the
  shell-specific files under that directory at the pinned commit.
- Shell-specific strategies are required. One generic wrapper would either
  skip documented startup behavior or force every shell through an incompatible
  command-line convention.
- A stable exported `DART_TERMINAL_SHELL_INTEGRATION=1` and version value will
  prove that a shell resource actually executed. The planner itself must not set
  these markers, so tests cannot pass when injection silently fails.
- A dedicated resource-contract checker is the narrowest owner for source
  hashes and manifest membership. The existing runtime smoke and bundle audit
  are the correct owners for final JIT/AOT execution and staged-resource proof.
