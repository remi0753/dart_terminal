# Phase 11 — Developer ID signing, hardened runtime, and notarization

## Purpose

Complete the next ordered Phase 11 roadmap item by transforming an already
verified Universal Release AOT application into an immutable Developer ID
distribution artifact, enabling the hardened runtime with the smallest
product-owned entitlement set, submitting the signed archive to Apple's
notary service, stapling the accepted ticket, and proving Gatekeeper and clean
machine behavior without weakening the local ad-hoc development path.

## Background and current position

- The preceding AOT/Universal task completed in commit `0ee6d6c`. ROADMAP was
  reread from a clean worktree; this is the first incomplete item.
- The accepted Universal source bundle has nine exact arm64/x86_64 code images,
  20 architecture-neutral files, deterministic schema-2 ownership evidence,
  nested-then-outer ad-hoc signatures, and atomic generic publication.
- The adjacent `dart_appkit` repository is clean. Its generic
  `dart_macos_runtime` builder and assembler own bundle layout, code inventory,
  signing order, signature verification, and atomic publication. Distribution
  signing/notarization belongs there as generic mechanism; this repository
  must inject product identity, entitlement policy, and acceptance parameters.
- Local `security find-identity -v -p codesigning` currently reports
  `0 valid identities found`. Xcode provides `notarytool` and `stapler`, but no
  Developer ID or notary credential may be invented, embedded, logged, or
  replaced with an ad-hoc signature. Credential-independent implementation and
  fault gates can proceed; the final positive Apple-service acceptance is a
  real external credential boundary.

## Scope

- Freeze the immutable input/output, signing order, hardened-runtime option,
  timestamp, entitlement, archive, notarization, stapling, Gatekeeper,
  credential, evidence, privacy, and failure-publication contracts.
- Add a generic atomic distribution tool to `dart_macos_runtime`. It consumes
  an already audited `.app`, validates manifest-owned code, signs nested code
  before the outer app with one injected Developer ID identity, verifies the
  designated requirement/team/hardened-runtime/entitlements contract, creates
  a deterministic-location submission archive, submits and waits through an
  injected Keychain profile, staples and validates the accepted ticket, then
  publishes only a complete application and distribution evidence.
- Add product-owned minimal entitlements and a product audit that binds the
  generic result to `dev.dart-terminal`, its exact Universal inventory, the
  expected Developer ID team/identity inputs, notarization acceptance, staple,
  and Gatekeeper result.
- Provide positive fixture and fail-closed tests without real credentials,
  followed by a credentialed release gate when a valid identity/profile are
  available. Validate install, launch, update/replace, and uninstall in a clean
  account or clean machine without rebuilding the accepted artifact.

## Out of scope

- Creating, exporting, purchasing, or storing Apple certificates or account
  credentials on behalf of the user. The tool accepts a preconfigured signing
  identity and `notarytool` Keychain profile by name and never reads secrets.
- Update-feed format/signatures and rollback policy, which are the next roadmap
  item. This task may replace a locally installed candidate only to validate
  signed/notarized application lifecycle.
- Crash/hang collection, benchmark gates, duration-only soak, sanitizers,
  compatibility burn-down, and daily-use campaigns, which retain their later
  roadmap order.
- Product names, terminal behavior, PTY policy, or product-specific defaults in
  the adjacent generic repository.

## Dependencies and risks

- Positive distribution acceptance requires a valid `Developer ID Application`
  identity, its private key, an Apple Developer team, network access to the
  notary service, and a preconfigured `notarytool` Keychain profile.
- Hardened runtime must be selected with `codesign --options runtime` on every
  executable code owner. Distribution timestamping must remain enabled; using
  `--timestamp=none`, ad-hoc signing, `--deep` as a substitute for explicit
  nested signing, or a local self-signed certificate is not equivalent.
- Entitlements are security authority. Each nested image and the outer app must
  receive only its declared entitlement file; empty or absent declarations are
  preferred unless a measured product path requires more authority. Debug,
  JIT, unsigned-executable-memory, library-validation bypass, disabled runtime,
  and broad file/network entitlements are forbidden by default.
- Notarization operates on an archive, while stapling modifies the signed app.
  The final distributed archive must be created after successful stapling and
  validation. A submitted pre-staple archive is transient input, not the final
  deliverable.
- Input and last-good output are immutable until final publication. Signing,
  archive creation, upload, rejection, timeout, log retrieval, stapling,
  Gatekeeper, or evidence failure must remove staging and preserve the existing
  accepted result.
- Tool output and evidence may contain identity/team/profile labels and Apple
  submission identifiers, but never passwords, app-specific passwords, API
  private keys, Keychain contents, usernames, absolute build paths, or terminal
  content. Notary rejection logs require bounded privacy review before storage.

## Completion conditions

- The generic tool validates a schema-2 Universal Release AOT source, exact
  code/resource inventory, clean ad-hoc source signature, distinct bounded
  paths, and product-injected entitlement file before any destructive action.
- Every nested code image and the outer application has a valid Developer ID
  signature from the requested identity/team, secure timestamp, hardened
  runtime, exact expected entitlements, and bundle-relative/system-only loads.
- A credentialed submission returns `Accepted`; the exact signed application is
  stapled and validates with `stapler`, passes `spctl --assess --type execute`,
  is archived after stapling, and records deterministic content hashes plus
  bounded notarization metadata.
- All invalid argument, identity mismatch, entitlement drift, wrong source
  shape, signing/timestamp failure, archive failure, rejected/invalid/timeout
  submission, malformed output, staple/Gatekeeper failure, symlink/path alias,
  and interrupted publication cases fail closed and preserve last-good output.
- Product build/audit commands, generic and product fixture suites, exact gates,
  docs/matrix, and ROADMAP agree. A no-rebuild clean-machine or clean-account
  install, ordinary terminal/worker launch, replacement, and uninstall pass.
- The parent remains incomplete if the real Developer ID/notary/clean-machine
  evidence cannot be produced. Lack of credentials is recorded as a blocker,
  never silently replaced by fixture or ad-hoc evidence.

## Validation plan

- Generic parser/fixture tests use injected command execution and fake bundles
  to verify exact command order and arguments, identity/team binding, separate
  entitlements, hardened/timestamp flags, notary status handling, final archive
  timing, deterministic evidence, atomic replacement, and cleanup under every
  injected fault.
- Product static audit rejects prohibited entitlement keys and binds the
  distribution result to the existing Universal manifest and exact nine-image
  inventory. A credential-independent dry-run/fixture gate exercises all
  product-injected values without accepting a fake release as distributed.
- Credentialed validation rebuilds/audits Universal input, signs through the
  generic tool, submits with `xcrun notarytool`, retrieves a bounded rejection
  log only on failure, staples/validates, runs Gatekeeper assessment, and checks
  the final archive/application hashes and ordinary product smoke.
- A separate clean destination receives the immutable final archive only. The
  test extracts/installs, launches, replaces an older accepted candidate,
  verifies rollback input remains available for the following roadmap task,
  then uninstalls and confirms no product-owned bundle remains.

## Ordered subtasks

1. **Contract and credential inventory**
   - Record current architecture/signature ownership, minimal-authority policy,
     Apple CLI interfaces, credential boundary, artifact lifecycle, failure
     policy, and test matrix before executable changes.
   - Completion: this memo and every child are in ROADMAP, the current identity
     result is truthful, links and `git diff --check` pass, and the contract is
     committed independently.
2. **Generic atomic distribution substrate**
   - Add a product-neutral `dart_macos_runtime` CLI/API with strict inputs,
     explicit nested signing, hardened/timestamp verification, notary/staple/
     Gatekeeper orchestration, deterministic evidence, fault injection through
     test adapters, and atomic last-good publication.
   - Completion: generic positive/negative tests and adjacent exact gate pass;
     no product or `terminal` name is added to generic code; the generic commit
     and this repository's dependency milestone are committed before proceeding.
3. **Product policy and credential-independent gate**
   - Add the reviewed minimal entitlement input, Make orchestration, strict
     product audit, fixture/dry-run negative coverage, public documentation,
     and generated evidence reconciliation.
   - Completion: all credential-independent product gates and exact main test
     pass and are committed without claiming Developer ID/notary success.
4. **Credentialed acceptance and closure**
   - Use a real installed identity/profile to create, notarize, staple, assess,
     archive, install, launch, replace, and uninstall the no-rebuild artifact.
   - Completion: positive Apple-service and clean-destination evidence pass,
     secrets remain absent, docs/matrix are reconciled, and the child plus
     parent are committed complete. If credentials remain unavailable, record
     the exact blocker and stop without starting the update-feed item.

Subtasks are strictly ordered. The update-feed roadmap item cannot begin until
all four children and this parent are complete.

## Progress and findings

- 2026-09-13: after commit `0ee6d6c` (`Complete Universal release bundle
  validation`), reread ROADMAP from a clean worktree and identified this parent
  as the first incomplete item. Reconfirmed README's accepted distribution
  commands, FEATURE_MATRIX `DIST-02`, ADR-005's generic ownership, the
  Universal schema-2 manifest, product audit, and adjacent generic signing
  points.
- 2026-09-13: `security find-identity -v -p codesigning` reported zero valid
  identities. `xcrun notarytool --help` exposes store-credentials, submit,
  info, wait, history, and log; `xcrun stapler help` supports staple/validate
  for signed application bundles. Positive Developer ID/notary acceptance is
  therefore presently unavailable, while contract, generic implementation,
  fixture gates, and product policy remain actionable in this ordered item.
- 2026-09-13: the accepted Universal source displays `Signature=adhoc`,
  `TeamIdentifier=not set`, and CodeDirectory flags `adhoc`; it has no outer
  entitlements. It is a valid immutable input, not a distribution artifact.
  Distribution must reject an already Developer-ID-mutated source rather than
  obscure which generation was audited by the preceding task.
- 2026-09-13: selected one atomic generic output directory containing the
  stapled `.app`, an archive created from that stapled application, and a
  path-free distribution manifest. The pre-staple submission ZIP exists only
  in staging. The caller supplies distinct input/output paths, a Developer ID
  identity label, expected Team ID, one reviewed outer-app entitlements plist,
  one Keychain profile label, and a bounded wait timeout.
- 2026-09-13: selected explicit signing rather than `codesign --deep`:
  manifest-owned nested libraries, helper host, and AOT images are signed in
  sorted order with `--options runtime --timestamp`, then the outer app/main
  executable is signed with the same identity/options and the product-owned
  entitlements. Verification requires strict deep validity, Developer ID
  Application certificate OID, exact Team ID, runtime flag, secure timestamp,
  and exact entitlements; ad-hoc, development, locally self-signed, expired, or
  identity-fallback results cannot pass.
- 2026-09-13: `notarytool submit` supports JSON output and an explicit
  Keychain profile without exposing a password or API-key path. Selected a
  separate JSON submit followed by bounded JSON wait so the submission UUID is
  retained even when waiting times out and Apple's service continues. `--force`
  and raw `--password`/`--key` credential arguments are forbidden. Only status
  `Accepted` proceeds to `stapler staple`, `stapler validate`, and Gatekeeper;
  any other terminal state preserves last-good output.
- 2026-09-13: considered in-place signing, product-owned generic process
  orchestration, ad-hoc fixture output promoted as a release, and disabling
  library validation/JIT protections preemptively. In-place mutation destroys
  the audited input, product ownership duplicates reusable distribution
  mechanics, fake promotion misstates Apple acceptance, and speculative
  entitlements expand authority without evidence. All four were rejected.
- 2026-09-13: the documentation-only contract added no executable or credential
  state. All required sections and the ROADMAP link exist, `git diff --check`
  passed, and the adjacent generic worktree remained clean. The contract child
  is complete; the generic atomic distribution substrate is next.
