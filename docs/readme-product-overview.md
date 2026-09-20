# Concise English README

## Purpose

Replace the current engineering-ledger-style README with a short, entirely
English introduction for someone who wants to understand and launch Dart
Terminal.

## Background

The existing README exceeds 1,000 lines and mixes product introduction,
implementation history, an exhaustive feature inventory, configuration schema,
build and test targets, release procedures, and architecture notes. Those
details already have more appropriate sources of truth in `FEATURE_MATRIX.md`,
`ROADMAP.md`, `docs/reference/`, and the phase notes under `docs/`.

## Scope

- Introduce the product and its current platform boundary.
- Explain how to open an existing application bundle.
- Give one minimal source-development launch path for Apple Silicon.
- Highlight only a small representative set of user-facing capabilities.
- Link to the detailed configuration, keybinding, diagnostics, feature-status,
  and development-plan references.
- Repair documentation links that target headings removed from the README.

## Out of scope

- An exhaustive list of features, actions, settings, or shortcuts.
- A catalog of Make targets or command variants.
- Distribution, notarization, architecture, and validation procedures.
- Rewriting `FEATURE_MATRIX.md`, `ROADMAP.md`, or the reference documentation in
  English.
- Product or runtime behavior changes.

## Dependencies and confirmed facts

- `make RUNTIME_ARCH=arm64 developer-jit-run` is the direct Developer JIT build
  and launch target on Apple Silicon.
- The project currently requires the unmodified Dart engine supplied by the
  adjacent `dart_appkit` repository; `make engine` prepares it there.
- An already built `.app` bundle can be opened from Finder or with macOS
  `open`.
- The detailed generated keybinding and configuration references remain the
  appropriate place for comprehensive usage information.

## Completion criteria

- `README.md` contains no Japanese prose.
- The README is concise and limited to introduction, launch, selected features,
  and links to authoritative details.
- Launch commands and documentation links match the repository.
- Removed README headings leave no broken repository documentation links.
- Documentation checks and the relevant repository test gate pass.

## Validation plan

- Search the rewritten README for Japanese characters and unintended Make
  target enumeration.
- Verify every relative link and launch command against the repository.
- Run whitespace validation and the repository test gate.
- Review the final diff for scope and readability.

## Findings and decisions

- `README.md` had 1,071 lines before the rewrite and used Japanese for nearly
  all product guidance.
- `docs/reference/terminal-diagnostics.md` linked to the old README heading
  `runtime-diagnostics`. Because that heading is intentionally removed, the
  reference will describe the separate metadata record without that link.
- The compatibility regression coverage generator hashes `README.md`; the
  generated evidence must therefore be refreshed if its freshness check reports
  a mismatch after the rewrite.
- The launch section will show only the normal App bundle opening path and one
  Apple Silicon development path. It will not reproduce the release, audit,
  integration, or distribution target matrix.
- A single `apply_patch` operation cannot delete and add the same path. The
  first replacement attempt was rejected without changing the worktree, so the
  README replacement is split into separate delete and add operations.

## Implementation result

- Replaced the 1,071-line Japanese README with a 66-line English overview.
- Kept one application-bundle launch example and one Apple Silicon source
  launch path.
- Limited the product overview to four representative areas: terminal core,
  windows/tabs/splits, Context Dock, and native macOS integration.
- Linked comprehensive usage and development information instead of duplicating
  it in the README.
- Removed the obsolete README heading link from
  `docs/reference/terminal-diagnostics.md` while preserving the documented
  distinction between exported diagnostics and per-launch runtime metadata.
- Regenerated the compatibility coverage, Ghostty gap inventory, and daily-use
  matrix because they form a checked hash chain rooted in `README.md`.

## Validation results

- Japanese-character search in `README.md`: no matches.
- README Make references: exactly the two required launch steps, `make engine`
  and `make RUNTIME_ARCH=arm64 developer-jit-run`; no target catalog remains.
- Relative link target check: all README links and the required sibling
  `dart_appkit` checkout exist in the development workspace.
- Repository-wide README anchor search: no references remain to removed README
  headings.
- `git diff --check`: passed.
- `make terminal-compatibility-regression-coverage
  ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`: passed and
  regenerated only the expected hash-chain evidence.
- `make test`: passed, including formatting, analysis, package tests,
  documentation freshness, compatibility evidence, daily-use evidence, and
  distribution policy tests.
