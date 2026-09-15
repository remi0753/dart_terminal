# Metal Toolchain environment recovery

- Status: complete
- Date: 2026-09-15
- Scope: restore the arm64 Release AOT build after the Xcode 27.0 update
- Related: ROADMAP completed-feature regressions, REN-02, DIST-01

## Purpose

Restore `make RUNTIME_ARCH=arm64 release-aot-build` on the Apple M1 baseline
without weakening the accepted build-time metallib contract or replacing it
with runtime shader compilation.

## Background

The submitted build log reaches the `dart_terminal_renderer_macos` native
asset hook, where `xcrun -sdk macosx metal` exits with status 1 and reports a
missing Metal Toolchain. Local inspection reproduces the same failure under
Xcode 27.0 build 27A266a. `xcrun --sdk macosx --find metal` resolves the driver,
so checking only for an executable path is insufficient; the selected Xcode
installation must also have its matching separately distributed toolchain
component installed.

This repository deliberately compiles `TerminalShaders.metal` at build time
and embeds the resulting metallib. Runtime source compilation is outside the
accepted renderer boundary and is not a valid workaround.

## Scope

- Install the official Metal Toolchain component matching the selected Xcode.
- Verify the compiler can execute, not merely resolve through `xcrun`.
- Re-run the exact failing arm64 Release AOT build.
- Record the environment change and verification result.

## Out of scope

- Changing renderer ABI, shader behavior, frame scheduling, or application
  code.
- Automatically downloading Xcode components from a build hook or Make
  target.
- Runtime Metal shader compilation.
- Intel-native, Developer ID, notarization, or long-duration follow-ups.

## Dependencies and risks

- `xcodebuild -downloadComponent MetalToolchain` requires network access and
  writes an Apple-managed system asset outside the repository.
- A matching Xcode update may require this component to be downloaded again.
- The Metal compiler also writes its Clang module cache outside the repository;
  product verification must run with the normal developer-environment access
  already required by existing renderer gates.

## Completion criteria

- The selected Xcode reports version 27.0 build 27A266a.
- The matching Metal Toolchain component is installed successfully.
- An actual Metal compiler invocation no longer reports `missing Metal
  Toolchain`.
- `make RUNTIME_ARCH=arm64 release-aot-build` exits successfully.
- The resulting Release AOT bundle is audited if the build completes.
- Documentation, ROADMAP state, and task-scoped diff are reviewed and
  committed independently.

## Verification plan

1. Run `xcodebuild -version`, `xcode-select -p`, and an actual `xcrun -sdk
   macosx metal` invocation.
2. Run the exact failing `make RUNTIME_ARCH=arm64 release-aot-build` command.
3. Run `make RUNTIME_ARCH=arm64 release-aot-audit` against the result.
4. Review `git diff --check`, the worktree, and the task-scoped staged diff.

## Investigation log

- 2026-09-15: the supplied build log resolved dependencies, built and signed
  the App Intents capability, verified the Dart Engine configuration, and
  linked the generic Release AOT host before the renderer build hook failed.
  The first actionable failure is exactly `cannot execute tool 'metal' due to
  missing Metal Toolchain`; no Dart, Objective-C, linker, or shader-source
  diagnostic precedes it.
- 2026-09-15: the worktree was clean on branch
  `codex/context-file-navigator-roadmap` before task changes. The first existing
  unchecked ROADMAP items are explicitly low-priority external follow-ups;
  this build regression is inserted before them under completed-feature
  regressions.
- 2026-09-15: local reproduction selected `/Applications/Xcode.app`, Xcode
  27.0 build 27A266a. `xcrun --sdk macosx --find metal` returned the driver
  path, while invoking it reproduced the missing-component error.
- 2026-09-15: the authorized Apple component download completed successfully:
  `xcodebuild -downloadComponent MetalToolchain` installed Metal Toolchain
  27A266a from an 838.9 MB system asset. Source and build contracts were not
  changed.
- 2026-09-15: the exact submitted command, `make RUNTIME_ARCH=arm64
  release-aot-build`, passed after the environment repair. The renderer native
  asset hook compiled and linked all three build assets, and the builder
  generated and ad-hoc signed
  `build/runtime/arm64/release-aot/DartTerminal.app`. This is also the required
  actual compiler-execution check: the hook reached Metal compilation without
  the former missing-toolchain error.
- 2026-09-15: `make RUNTIME_ARCH=arm64 release-aot-audit` repeated the build
  successfully and ended with `DART_ONLY_BUNDLE_AUDIT_PASS` for `release-aot`
  `arm64`, including one helper, one asset, two capabilities, one scripting
  definition, three App Intents, and eight localization resources.
- 2026-09-15: no renderer, hook, Makefile, or application source change was
  needed. Automatically downloading an 838.9 MB Xcode component from a build
  remains intentionally outside repository build behavior; the actionable
  Xcode diagnostic and this task memo preserve the recovery path.
