# Software updates

Dart Terminal owns its update format, trust policy, release selection,
installation transaction, and user interface. The adjacent `dart_appkit`
package remains generic AppKit infrastructure and contains no product update
policy.

## User-visible behavior

`Dart Terminal` > `Check for Updates…` and the command palette invoke the same
application action. One read-only Software Update window reports a fixed state:
not configured, checking, update available, up to date, preparing, restart
required, cancelled, or failed. When an authenticated update is available, the
window shows its version, build, and bounded plain-text release notes. Release
notes are never interpreted as HTML or Markdown and the archive URL is not
shown.

Press Return to check again or, when a verified release is available, prepare
its candidate. Press Esc to cancel an in-progress operation, close the update
window, and restore focus to the terminal. These actions never write update
metadata or UI keystrokes to a PTY.

The checked-in application has no production endpoint, private key, fixture
trust root, or fallback installer. Unless a release build injects an explicitly
configured product update service backed by its pinned public key, the action
stays inert and visibly reports `not configured`; it performs no network or
filesystem mutation.

## Trust and installation boundary

The signed feed uses canonical UTF-8 JSON and a detached Ed25519 SSHSIG under a
pinned key ID and namespace. The signature authenticates product/channel,
monotonic sequence, expiry, version/build, compatibility, exact archive URL,
size, SHA-256, bundle identity, and plain-text release notes. Strict parsing,
canonical byte comparison, signature verification, replay/downgrade checks,
and compatibility selection all complete before an archive is accepted.

Archive download is HTTPS-only, credential-free, streamed, size bounded, and
hash checked. ZIP inventory and the extracted tree reject traversal, links,
case aliases, extra roots, and unsupported entries. Before installation, the
candidate must match the product bundle/version, Universal Release AOT
manifest, exact code inventory, pinned Developer ID Team, hardened runtime,
secure timestamps, stapled ticket, and Gatekeeper policy.

Installation uses a same-volume staging directory, one bounded last-good
backup, and a content-free atomic journal. A new application must acknowledge a
one-use health token after its identity is rechecked. An interruption, missing
health acknowledgement, or explicit rollback restores only the previously
verified last-good application. The updater never repairs, resigns, unstaples,
or bypasses Gatekeeper for a candidate.

## Privacy and data flow

An explicit check may send only the ordinary HTTPS request needed to retrieve
the configured public feed and archive; no cookie, credential, terminal text,
command, working directory, environment, path, username, or analytics payload
is attached. There is no background polling or unattended download in this
version.

Persistent state is bounded and content-free: schema/product identifiers,
highest accepted feed sequence, version/build, archive hashes, an opaque
transaction ID, fixed relative transaction names, and a phase/outcome. General
diagnostics retain only fixed update status and bounded counts. They exclude
URLs, response bodies, signatures, release-note text, absolute paths, commands,
terminal content, environment values, timestamps, and raw exceptions. Nothing
is uploaded by the diagnostics path.

## Release operation

The canonical release-feed tool requires an external archive, private signing
key path, separate pinned public key, and explicit release metadata. Missing
inputs fail closed; the repository ships no production signing key. See
`make help` for `release-update-feed` and its credential check.

A publicly distributable positive candidate still requires a real Developer ID
identity, Apple notarization acceptance, stapling, and Gatekeeper validation.
Those credentialed Apple-service checks are deliberately deferred and no
ad-hoc fixture is represented as a public release. Credential-independent feed,
signature, hostile archive, transaction, rollback, UI, and product acceptance
remain enforced by the normal test gates.
