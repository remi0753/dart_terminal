# Test-only native fixture source audit classification

- Status: in progress
- Started: 2026-09-07
- Roadmap item: Phase 7 prerequisite before application-state product acceptance
- Related: `docs/phase6/real-application-compatibility-matrix.md`,
  `docs/phase7/application-state-model.md`, and `tool/dart_only_source_audit.dart`

## Purpose

Restore the Dart-only product source gate after Phase 6 added one reviewed C
source file as provenance for a prebuilt external ncurses compatibility
fixture. Keep the prohibition on product-owned native source exact while
distinguishing a pinned test-corpus input that is not compiled or bundled by
the Dart Terminal application.

## Background and confirmed facts

- Phase 7 application-state product acceptance first runs
  `runtime-source-check`. On 2026-09-07 it failed before either application
  bundle was built because the audit classified
  `test/corpus/applications/support/ncurses_resize_fixture.c` as product source.
- The file entered in Phase 6 commit `a5752f0 Capture pinned terminal
  application evidence`. Its path and SHA-256 are pinned by
  `compatibility/application_matrix_evidence.json` and revalidated by
  `tool/terminal_application_evidence.dart`.
- The application manifest contains only the public `dart_pty_macos` native
  asset and `dart_terminal_renderer_macos` capability. It does not include the
  ncurses source or fixture executable.
- The Makefile and application `bin/`/`lib/` sources do not reference the C
  file. The optional capture driver executes a separately prepared fixture
  binary from an external artifacts directory; normal tests validate checked-in
  byte evidence and do not compile the C source.
- The existing audit rejects every tracked `.c`, `.cc`, `.cpp`, `.h`, `.hpp`,
  `.m`, `.mm`, and `.metal` path without distinguishing product inputs from
  test-corpus provenance. The README therefore also has an over-broad claim
  that the repository contains no native source at all.

## Scope and decision

- Add an exact allowlist containing only the reviewed ncurses test source.
- Continue rejecting every other tracked native-language source path.
- Require the allowlisted fixture to remain present, under the test-corpus
  support directory, absent from the application manifest, Makefile, and
  product Dart source, and covered by the existing evidence hash validator.
- Report product-native and reviewed-test-native counts separately.
- Correct README wording to state that product/build paths contain no native
  source while acknowledging the reviewed test-only compatibility input.

The allowlist is deliberately not a directory-prefix exemption. A second test
native source must be reviewed and added explicitly or the audit fails.

## Out of scope

- Re-capturing the Phase 6 application corpus or changing its pinned evidence.
- Compiling the ncurses fixture in normal tests or application builds.
- Allowing native source in `bin/`, `lib/`, the application manifest, bundle
  resources, or repository-owned product build targets.

## Acceptance and validation

1. `runtime-source-check` passes with zero product native sources and exactly
   one reviewed test native source.
2. Removing/renaming the expected fixture or introducing another native source
   would fail the audit.
3. The full Dart test/freshness suite passes, including the existing fixture
   path/hash checks.
4. The Phase 7 Developer JIT and Release AOT acceptance can proceed without
   weakening application bundle or direct-FFI checks.

## Findings and verification log

- 2026-09-07: the original Phase 7 runtime acceptance attempt stopped with
  `DART_ONLY_SOURCE_AUDIT_FAIL product repository contains native source:
  test/corpus/applications/support/ncurses_resize_fixture.c`. No bundle or GUI
  test ran in that attempt.
- 2026-09-07: the audit now classifies native-language paths against an exact
  one-file reviewed test allowlist, rejects any non-allowlisted path as product
  native source, requires the reviewed fixture to exist below the application
  test-corpus support directory, and scans the Makefile, application manifest,
  and every tracked `bin/`/`lib/` source to ensure none reference that fixture.
- 2026-09-07: `CI=true make RUNTIME_ARCH=arm64 runtime-source-check` passed
  with `tracked=366 product_native_sources=0 reviewed_test_native_sources=1`.
- 2026-09-07: the first full test after correcting README wording correctly
  rejected the Phase 6 compatibility coverage report as stale because that
  report pins the README hash. The canonical coverage generator changed only
  the README SHA-256 entry. The repeated `make test` then passed every
  freshness and compatibility check, formatted 190 files with zero changes,
  analyzed the package with no issues, and completed the aggregate test runner.
- 2026-09-07: final diff review confirmed that no application/build source,
  manifest entry, native asset, native capability, or bundle resource was
  changed by this prerequisite. The existing ncurses evidence and fixture hash
  remain unchanged.
