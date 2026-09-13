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
monotonic `sequence`, an exact release-key ID, and one to 32 releases. Every
release has exactly:

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

The detached signature is versioned binary evidence carrying the algorithm,
namespace `dart-terminal-update-v1`, key ID, and exact 64-byte Ed25519 signature.
The public key is exactly 32 bytes. Unknown algorithms/namespaces/key IDs,
wrong-length/non-canonical encodings, and signature mismatch fail closed.

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
