# Phase 11 — Signed update feed, verification, and rollback

## Purpose

Complete the next ordered Phase 11 item with a product-owned update path that
accepts only a bounded, strictly parsed feed signed by an explicitly pinned
release key, verifies an immutable application archive before installation,
publishes an update through a recoverable transaction, and restores the last
known-good application after interruption or failed launch health. Release
notes are authenticated feed data and never executable content.

## Background and current position

- The Developer ID/hardened-runtime/notarization mechanism completed in commit
  `1e3d7e2`; its unavailable real-credential Apple-service exercise is tracked
  as a low-priority follow-up and is not claimed as accepted.
- ROADMAP was reread from a clean main worktree after that commit. This update
  item is the first incomplete task; crash/hang collection and all later Phase
  11 items remain untouched.
- The current Universal Release AOT artifact has an exact product audit and the
  distribution publisher has an exact post-staple archive contract. The update
  path consumes such an immutable archive; it does not rebuild, resign, staple,
  or otherwise repair a candidate.
- No updater, release-key declaration, feed schema, download policy, install
  journal, or update UI currently exists in this repository. Existing uses of
  Ed25519 names are SSH compatibility fixtures, not update authority.
- `dart_appkit` is generic application infrastructure. Feed semantics, release
  identity, candidate policy, install decisions, and user-facing update state
  belong to `dart_terminal`; no product-specific or `terminal`-named source is
  to be added to the adjacent generic repository.

## Scope

- Define a versioned exact-field feed with one product/channel, monotonic feed
  sequence, bounded release records, strict semantic version/build ordering,
  HTTPS archive location, byte size and SHA-256, exact application identity,
  minimum macOS version, architecture contract, and bounded plain-text release
  notes.
- Sign the exact canonical UTF-8 feed bytes with a detached Ed25519 signature.
  Generation consumes an external private-key path or signing adapter; runtime
  verification consumes only a pinned public key and key ID embedded through
  the product build declaration.
- Fetch through an injected transport with HTTPS-only production policy,
  redirect/size/count/time bounds, no cookies or credentials, and an offline
  file adapter used only by deterministic tests and explicit release tooling.
- Select only a strictly newer compatible release. Reject downgrade, replay,
  sequence rollback, equal build with different bytes, unknown key/format,
  expired metadata policy, malformed notes/URLs, and unbounded input before
  downloading an archive.
- Verify the archive byte count and SHA-256 before extraction. Extract to a
  private same-volume staging directory, reject traversal, symlink/hardlink,
  case-alias, extra-root, bundle-ID/version/architecture drift, and signature
  policy drift before any installed application mutation.
- Implement a content-free transaction journal and same-volume replacement:
  candidate staging, current-to-backup move, candidate-to-current move, launch
  health acknowledgement, commit, backup retention/pruning, and deterministic
  rollback/recovery after every interruption boundary.
- Expose a shared product action and bounded status/release-notes presentation.
  Update checks are explicit in the first implementation; unattended automatic
  download/install and background polling remain outside this item.

## Out of scope

- Generating, exporting, committing, logging, or otherwise taking custody of a
  production release private key. Test keys are ephemeral or fixture-scoped and
  cannot enable production update checks.
- Treating an ad-hoc, unsigned, self-signed, unstapled, or unnotarized fixture as
  a public release. The user-authorized Apple-service deferral remains truthful
  and the update mechanism cannot promote the current ad-hoc artifact.
- Privileged installation outside a user-writable application location,
  modifying another application, silently bypassing Gatekeeper, or changing
  quarantine/TCC state.
- Delta patches, multiple update channels, staged rollout, telemetry, remote
  analytics, HTML/Markdown execution, arbitrary post-install scripts, or
  in-process replacement of the running bundle.
- Crash/hang reporting, benchmark gates, long-duration soak, sanitizers, parity
  burn-down, and daily-use campaigns, which retain their ROADMAP order.

## Threat and trust inventory

- Network and feed storage are untrusted. Authenticity comes only from a valid
  detached signature under the exact pinned key ID/public key and namespace;
  TLS is defense in depth, not update authority.
- The feed signature covers the canonical bytes containing archive hash, size,
  identity, version/build, compatibility, notes, sequence, and channel. Parsing
  must reject unknown/duplicate fields and non-canonical bytes so two semantic
  interpretations cannot share one signature.
- The release private key is an offline/release-automation input. Command lines,
  JSON evidence, logs, diagnostics, and application resources may contain only
  the public key, key ID, and signature—not the private key or passphrase.
- A valid old feed is still hostile as a replay. The updater persists the
  highest accepted feed sequence and installed build in a product-owned local
  state file and never lowers either automatically. Reset requires an explicit
  local maintenance operation outside normal update checking.
- Archive extraction is hostile even after signature verification because the
  signed release process itself can be compromised. Paths, links, root count,
  code inventory, bundle metadata, size, and product signature policy receive
  independent validation.
- A crash or power loss can occur between any two filesystem operations. The
  durable journal is written and atomically replaced before each mutation;
  recovery is idempotent and always resolves to exactly one current app plus at
  most one bounded last-good backup.

## Feed contract

The canonical feed is UTF-8 JSON with format `dart-terminal-update-feed`,
version `1`, product `dev.dart-terminal`, channel `stable`, a positive
monotonic `sequence`, an exact release-key ID, an expiry expressed as positive
Unix seconds no more than 90 days ahead, and one to 32 releases. Every release
has exactly:

- `version`: canonical three-component semantic version without prerelease or
  build metadata in the stable channel;
- `build`: positive monotonically increasing integer;
- `minimum_macos`: canonical `major.minor` at or above the product deployment
  target;
- `architecture`: exactly `universal-arm64-x86_64`;
- `archive_url`: absolute HTTPS URL without credentials, fragment, control
  characters, or a non-default port;
- `archive_size`: 1 through 1 GiB;
- `archive_sha256`: lowercase 64-character SHA-256;
- `bundle_id`: exactly `dev.dart-terminal`;
- `release_notes`: zero to 64 plain-text lines, each at most 512 UTF-8 bytes and
  the aggregate at most 16 KiB, with control and bidi-control characters
  rejected.

Keys are emitted in a single documented order, arrays preserve release order,
numbers use canonical decimal form, strings use the repository's deterministic
JSON encoder, and the file ends with one newline. Strict verification parses,
validates, re-encodes, and byte-compares before checking the signature.

The detached signature uses the OpenSSH SSHSIG version 1 envelope and namespace
`dart-terminal-update-v1`. The bounded ASCII armor must contain the exact pinned
OpenSSH `ssh-ed25519` public-key blob, `sha512` message hash selector, and a
64-byte Ed25519 signature. The feed's key ID must equal the pinned key ID and is
also the sole allowed-signer identity passed to `/usr/bin/ssh-keygen -Y verify`.
The decoded public key is exactly 32 bytes. Unknown algorithms/namespaces/key
IDs, reserved data, wrong-length/non-canonical encodings, and signature mismatch
fail closed.

## Selection and update state

Feed releases are strictly descending by build and version, with no duplicate
version, build, URL, or archive hash. Selection filters by bundle/channel,
minimum OS, Universal architecture, feed sequence greater than or equal to the
persisted sequence, and build strictly greater than the installed build. An
equal or lower build is `upToDate` only if it does not contradict already
accepted version/hash evidence; contradictory evidence is an integrity error.

Persistent state is content-free and bounded: schema version, highest accepted
feed sequence, installed version/build/archive hash, transaction ID, fixed
phase enum, relative current/backup/staging names, and retry-safe outcome. It
contains no terminal text, command, cwd, environment, credential, URL query,
absolute path, user name, timestamp, raw exception, or server response body.

The transaction states are `prepared`, `backupMoved`, `candidateInstalled`,
`awaitingHealth`, `committed`, and `rolledBack`. Before replacement the updater
must run outside the target application process or receive its confirmed exit.
Health is a one-use opaque transaction token acknowledged by a normally started
new application after its bundle/version identity is checked. Timeout, explicit
failure, missing acknowledgement, or restart recovery restores the backup.

## Failure and rollback policy

- Any feed/signature/selection/download/archive/candidate failure occurs before
  mutation and leaves the installed app and accepted state unchanged.
- Failure after the backup move either completes the candidate move and enters
  bounded health checking, or immediately restores the backup. A second update
  cannot overlap an active journal.
- Rollback never installs bytes not previously verified as the exact last-good
  application. Failed candidates remain outside the current path and are
  removed after bounded diagnostic classification.
- A successfully acknowledged update atomically advances feed sequence/build/
  hash, marks committed, and retains at most one last-good backup for explicit
  rollback. A subsequent accepted update prunes the older backup only after the
  new health acknowledgement.
- Every error exposed to UI is a fixed classification and optional bounded
  counts. Raw response, filesystem path, signature bytes, release notes,
  command output, and exception text do not enter general diagnostics.

## Dependencies and risks

- A production pinned public key is required before enabling a real update
  endpoint. Absence disables remote checking with an explicit `notConfigured`
  state; it must not fall back to a fixture key or trust-on-first-use.
- Signing tooling must support deterministic detached Ed25519 signatures while
  keeping the private key outside the repository. Runtime cryptographic code
  must use a reviewed platform/library implementation rather than an improvised
  arithmetic implementation.
- A real distributed candidate remains coupled to the deferred Developer ID and
  notarization acceptance. Credential-independent tests use structurally valid
  fixtures but cannot establish public distribution readiness.
- Replacing a running app, read-only volume, `/Applications` ownership, Finder
  translocation, external volumes, and antivirus/indexer races require explicit
  failure classes and same-volume checks. The first accepted path is a
  user-writable local application directory.

## Completion conditions

- Exact schema/canonicalization, Ed25519 verification, pinned-key identity,
  downgrade/replay/compatibility selection, bounded notes, and hostile input
  tests pass without network or production secrets.
- A release tool generates a canonical feed and detached signature only from an
  explicit external signing key and audited archive metadata; logs/evidence do
  not contain private material.
- Candidate download/extraction/bundle/signature validation completes before
  mutation. Every injected filesystem/health interruption converges to the
  verified current or last-good app with no ambiguous pair or unbounded backup.
- The shared action and status/release-note UI never route feed text to PTY,
  never render executable markup, and remain inert when key/endpoint/install
  prerequisites are absent.
- Unit/property/fault tests, product acceptance, formatting, analysis, normal
  exact gate, docs/matrix/ROADMAP, and privacy/source audits pass. Any real-key
  or real-distribution acceptance that remains unavailable is explicitly
  described and cannot be mistaken for a public release.

## Validation plan

- Fixed canonical vectors cover each scalar boundary, reordered/unknown/
  duplicate fields, JSON aliases, malformed UTF-8, signature/key/namespace
  drift, 32-release/notes/size caps, version ordering, downgrade, replay, and
  incompatible macOS/architecture selection.
- Signing tests create an isolated ephemeral key outside the repository, sign
  exact bytes, verify with only the public key, and prove that every covered
  field mutation fails. No generated private key is staged or retained.
- Download/archive fixtures inject truncation, excess bytes, hash mismatch,
  redirect and timeout classifications, traversal, symlink/hardlink/case alias,
  bundle identity/version/code drift, and application-signature rejection.
- A fake same-volume filesystem records every fsync/rename/journal boundary.
  Fault injection at each boundary plus repeated recovery proves current/backup
  uniqueness, last-good preservation, bounded cleanup, and idempotence.
- Product acceptance invokes the same action/controller with an in-memory feed
  and candidate adapter, verifies release notes/status, PTY write count zero,
  single-flight behavior, close/quit cancellation, and full owner cleanup.

## Ordered subtasks

1. **Contract and threat inventory**
   - Freeze this memo, ROADMAP subdivision, ownership, schemas, key boundary,
     state machine, failure policy, and validation matrix before executable
     changes.
   - Completion: documents agree, links and `git diff --check` pass, both
     worktrees are otherwise clean, and the contract is committed alone.
2. **Strict signed feed and release generation**
   - Add the product-owned feed/value model, canonical codec, pinned Ed25519
     verifier, external-key signer tool, selection policy, and exhaustive
     vectors without touching the adjacent generic repository.
   - Completion: canonical/signature/selection/security tests and exact normal
     gate pass; no secret or production fixture key is shipped; docs and the
     child checkbox are committed before proceeding.
3. **Candidate transaction and rollback**
   - Add bounded transport/candidate validation, durable journal, atomic
     replacement, health acknowledgement, recovery, rollback, and injected
     filesystem fault coverage.
   - Completion: every pre/post-mutation fault preserves or restores a verified
     last-good app, package/privacy gates pass, and this child is committed.
4. **Product integration and closure**
   - Add shared update action, safe notes/status projection, lifecycle wiring,
     credential-independent product acceptance, public documentation, matrix
     reconciliation, and parent completion judgment.
   - Completion: Developer JIT/Release AOT applicable acceptance and exact main
     gate pass; unavailable production key/distributed candidate limits remain
     explicit; child and parent are committed complete.

Subtasks are strictly ordered. The crash/hang roadmap item cannot begin until
all four update children and this parent are complete.

## Progress and findings

- 2026-09-13: after commit `1e3d7e2` (`Defer credentialed distribution
  acceptance`), reread ROADMAP from clean main and adjacent worktrees and
  confirmed this as the first incomplete item. Repository search found no
  existing update feed, release-key, updater, or rollback implementation.
- 2026-09-13: selected a product-owned independent updater rather than adding
  release semantics to `dart_appkit`. The adjacent repository remains unchanged
  and generic. The existing distribution archive/audit is an immutable input,
  while feed authority, version policy, notes, and rollback state remain
  product concerns.
- 2026-09-13: considered TLS-only trust, archive hash without a signed feed,
  trust-on-first-use, a committed fixture private key, shell scripts embedded in
  release notes, and in-place mutation. These permit server replay, metadata
  substitution, key theft, code execution, or irrecoverable partial install and
  were rejected.
- 2026-09-13: selected detached Ed25519 with exact canonical bytes and a pinned
  build-time public key. This keeps the compact signature separate from archive
  code signing and lets every version/hash/notes/compatibility decision be
  authenticated. The implementation must use reviewed crypto and ephemeral test
  keys; handwritten elliptic-curve arithmetic is outside the trust boundary.
- 2026-09-13: verified that the ROADMAP link resolves, `git diff --check`
  passes, and both main and adjacent worktrees contain no unrelated changes.
  This documentation-only contract changes no executable path and needs no
  duration test. The contract/threat-inventory child is complete; strict signed
  feed and release generation is next.
- 2026-09-13: implemented the product-owned format/value model with exact
  top-level and release fields, canonical UTF-8 JSON byte comparison, 256 KiB
  feed cap, 32-release cap, strict stable semantic versions, monotonic build and
  sequence rules, 90-day expiry, macOS compatibility, HTTPS/archive bounds,
  exact product/Universal identity, SHA-256, and plain-text release-note limits.
- 2026-09-13: selected the system OpenSSH SSHSIG implementation as the reviewed
  Ed25519 boundary. Verification decodes and validates the version-1 envelope,
  embedded pinned key, namespace, empty reserved field, SHA-512 selector,
  algorithm, and signature length before invoking absolute
  `/usr/bin/ssh-keygen -Y verify` with a temporary one-key allowed-signers file.
  Process input/output, timeout, and temporary files are bounded; no shell or
  trust-on-first-use path exists.
- 2026-09-13: added an external-key release generator. It never reads or emits
  the private key, hashes the supplied archive, constructs canonical feed bytes,
  invokes OpenSSH signing, self-verifies with the separate public key, and then
  atomically replaces a directory containing feed, signature, and path-free
  evidence. Any signing/key mismatch before publication preserves last-good
  output. Make exposes a fail-closed credential check and generation target;
  absent release-key inputs do not fall back to fixture material.
- 2026-09-13: the focused suite passed canonical/selection behavior,
  noncanonical/unknown/malformed/expired/unsafe input, release bounds,
  replay/version/build contradiction, genuine ephemeral Ed25519 success, exact
  signed-byte mutation, wrong key/key-ID rejection, atomic generation,
  last-good preservation, secret/path absence, and option validation. The only
  failed attempt was an initial uppercase-hash negative fixture that lowercased
  its own mutation; the fixture was corrected to literal uppercase bytes and
  passed. A direct test invocation initially lacked `main`; the standalone
  entrypoint was added and the focused command then passed.
- 2026-09-13: the dedicated `make terminal-update-feed-test` first encountered
  the sandbox's denied Clang module-cache write in an unrelated Metal build
  hook; rerunning the exact target with normal host cache access passed all ten
  groups. `make release-update-feed-credentials-check` without external release
  values failed closed before signing with recipe status 69 (make status 2), as
  intended.
- 2026-09-13: after explicitly saving formatter output, the final exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed 299-file formatting,
  analysis, all generated-evidence, package/native, distribution, security, new
  update-feed, and root gates. No long-duration test was needed. Review found
  no private-key material, production fixture key, output path, or unrelated
  adjacent-repository change. The strict signed-feed/generation child is
  complete; candidate validation and rollback is next.
- 2026-09-13: implemented the candidate/update transaction entirely in the
  product package. The production downloader creates a fresh destination,
  disables redirects, accepts only HTTP 200 over the feed's already validated
  HTTPS URL, enforces declared and streamed byte counts plus idle/total timeout, and
  verifies the signed SHA-256 through `/usr/bin/shasum` without buffering an up
  to 1 GiB archive in Dart memory. A separately named file adapter provides the
  same exact size/hash gate for deterministic offline acceptance; production
  integration can depend on the downloader interface without selecting that
  adapter.
- 2026-09-13: the macOS candidate preparer rechecks the archive before use,
  inventories ZIP paths before extraction, rejects traversal, absolute or
  backslash paths, case-fold aliases, extra roots and unbounded inventory, and
  extracts only into a fixed private sibling directory on the install volume.
  The extracted tree rejects links, hard links, unsupported entries and path or
  entry-count excess. It then requires the exact bundle ID/version/executable,
  Release AOT schema-2 Universal manifest and code inventory, Developer ID and
  pinned Team ID, hardened runtime, secure timestamps, staple validation and
  Gatekeeper acceptance. The current generic runtime manifest has no build
  number field, so build identity remains authenticated by the signed feed and
  its exact archive hash while `CFBundleShortVersionString` is independently
  matched inside the bundle; no generic runtime change is required.
- 2026-09-13: added a strict 16 KiB canonical journal containing only product,
  fixed relative names, opaque 128-bit transaction ID, phase, feed sequence,
  version/build and archive hashes. It never persists URLs, release notes,
  paths, terminal content, commands, environment, timestamps or raw errors.
  The local storage writes and flushes a sibling temporary file before atomic
  replacement, permits only the four fixed transaction names, and accepts a
  product-owned bundle verifier callback for every current/backup decision.
- 2026-09-13: the coordinator verifies both current and candidate before the
  first installed-app mutation, journals `prepared`, then moves current to one
  bounded last-good backup and candidate to current with journal transitions at
  every boundary. A one-use opaque token is accepted only in `awaitingHealth`
  after re-verifying the current candidate. Missing health on restart and
  explicit rollback restore only the verified previous identity; malformed or
  unverifiable topology fails closed without installing unknown bytes.
- 2026-09-13: the first install-fault test expected candidate staging to be
  removed even when failure was injected before a journal could be written.
  That expectation was incorrect: pre-journal validation failure must leave the
  installed app unchanged and may retain exactly one bounded, still-verified
  staging candidate for retry. The assertion was corrected to distinguish this
  pre-mutation state; post-journal failures and all interrupted recoveries still
  remove staging and converge to one previous current app.
- 2026-09-13: focused formatting and analysis passed. The standalone suite
  passed exact candidate metadata/signature evidence, download redirect/status/
  timeout/network/size/hash classifications, hostile ZIP inventory, canonical
  journal/privacy, streamed offline copy and cleanup, one-use health commit,
  explicit rollback, each install boundary, repeated recovery faults, and real
  local atomic journal replacement/fixed-name moves. The dedicated
  `make terminal-update-transaction-test` gate passed all eleven groups. The real
  Developer ID/staple/Gatekeeper positive candidate remains unavailable under
  the user-authorized Apple-service deferral; structurally valid evidence and
  every credential-independent negative gate are covered without weakening the
  production preparer.
- 2026-09-13: source review found that a verifier callback alone would leave
  production current/backup identity checks unspecified. The macOS preparer now
  also exposes a fail-closed installed-application verifier using the same
  plist, runtime-manifest, code-signing, Team ID, hardened runtime, timestamp,
  staple and Gatekeeper checks. The transaction storage can bind that method as
  its callback; tests keep using an isolated deterministic verifier. ZIP mode
  inventory is also checked before extraction so link/device entries cannot be
  used as an extraction-time escape before the post-extraction tree scan.
- 2026-09-13: the first exact normal gate had one unrelated timing failure in
  the pre-existing `live Dart child cannot steal native PTY completion` case
  (`No element`). Its focused `make dpty-dart-test` rerun passed all cases, and
  the exact full gate rerun then passed. After the final journal ordering and
  ZIP-mode preflight review, the dedicated transaction gate and a second exact
  `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed: 301 files formatted,
  analyzer clean, all package/native/generated/security/distribution/feed/
  transaction/root tests green. The adjacent `dart_appkit` worktree remained
  clean. Long-duration and real Apple-service checks were skipped as authorized
  and are not blockers for this credential-independent child.
- 2026-09-13: product integration adds one stable `application.check-for-updates`
  action to the Application menu and command palette. Its lifecycle-owned
  controller accepts only an injected product service, rejects overlapping
  operations, invalidates late completion after cancel/dispose, and retains
  only fixed status plus an already-authenticated release value. With no
  production service, endpoint, or pinned key injected, the checked-in build is
  explicitly `notConfigured` and performs no remote or install work.
- 2026-09-13: selected a singleton read-only AppKit text view rather than a web
  view or rich-text renderer. English/Japanese copy shows only fixed state,
  version/build, and bounded plain feed lines; literal markup stays literal and
  archive URLs are not rendered. Return checks or prepares once, while Escape
  cancels/closes and restores the exact live terminal responder. Both paths
  were verified to leave the PTY input count unchanged and to release native
  owners on close/quit.
- 2026-09-13: focused analysis passed for the controller, application wiring,
  action/localization audits and tests. Controller tests passed unconfigured
  inertness, authenticated check/install, single-flight cancellation, late
  result rejection, disposal, and content-free failures. Fake-AppKit tests
  passed Japanese action lookup, plain-note projection, Return/Escape routing,
  focus restoration, and exact native/service cleanup. The localization audit
  now covers 14 production owners and 11 application injection sites.
- 2026-09-13: `CI=true DART_SUPPRESS_ANALYTICS=true make
  runtime-user-actions-integration` passed the normal product hierarchy in both
  Developer JIT and Release AOT. The same native menu/dispatcher route checked
  and prepared one in-memory authenticated release, exposed no URL, wrote zero
  update bytes to PTY, restored focus, and still completed the existing split,
  divider, window/tab/pane, input-isolation, close, quit, and zero-owner checks.
  This adapter is acceptance-only and contains no production key or network
  fallback.
- 2026-09-13: public update documentation now records the explicit-check data
  flow, no background polling, trust/install/rollback boundary, content-free
  persistence and diagnostics, external-key release operation, and fail-closed
  unconfigured state. The matrix records the completed credential-independent
  feature without claiming that an ad-hoc candidate is publicly distributable.
  Per user direction, real Developer ID/Apple notarization/staple positive
  acceptance and long-duration validation remain lower-priority follow-ups and
  are not blockers.
- 2026-09-13: the first exact main-gate attempt correctly rejected stale Phase
  7 AppKit evidence after the shared action/native presenter test changed. The
  canonical generator refreshed that evidence; the next attempt correctly
  rejected its dependent compatibility coverage hash, which was refreshed by
  its canonical generator. A subsequent run exposed the expected localization
  audit unit count still at 13 and two directive-ordering infos; these were
  updated to the audited 14 sources and sorted without weakening either audit.
- 2026-09-13: the final exact `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  passed 303-file formatting, analysis with no issues, all package/native,
  generated-evidence, compatibility, privacy, distribution, update feed,
  controller, candidate transaction, fault/recovery, and root suites. The
  adjacent `dart_appkit` worktree is unchanged. Credential-independent product
  integration and this update parent now satisfy their completion conditions;
  only the explicitly deferred real Apple-service acceptance remains outside
  this task.
