import 'dart:convert';
import 'dart:math';

import 'terminal_application_state.dart';
import 'terminal_note_model.dart';
import 'terminal_pane.dart';
import 'terminal_restoration.dart';
import 'terminal_sha256.dart';

abstract final class TerminalNoteContextIdentityLimits {
  static const int byteLength = 16;
  static const int maximumCollisionAttempts = 32;
}

enum TerminalNoteContextIdentityFailure { entropyRejected, collisionLimit }

/// Fixed, content-free context identity generation failure.
final class TerminalNoteContextIdentityException implements Exception {
  const TerminalNoteContextIdentityException(this.failure);

  final TerminalNoteContextIdentityFailure failure;

  @override
  String toString() => 'Terminal note context identity failed: ${failure.name}';
}

typedef TerminalNoteContextEntropySource = List<int> Function();

/// Issues opaque 128-bit Note context identities.
///
/// Product code uses [secure]. Tests may inject deterministic bytes through
/// [forTesting] without weakening the production constructor.
final class TerminalNoteContextIdGenerator {
  factory TerminalNoteContextIdGenerator.secure() {
    final Random random = Random.secure();
    return TerminalNoteContextIdGenerator._(
      () => List<int>.generate(
        TerminalNoteContextIdentityLimits.byteLength,
        (_) => random.nextInt(256),
        growable: false,
      ),
    );
  }

  const TerminalNoteContextIdGenerator.forTesting(
    TerminalNoteContextEntropySource source,
  ) : _source = source;

  const TerminalNoteContextIdGenerator._(this._source);

  final TerminalNoteContextEntropySource _source;

  TerminalNoteContextId next({
    Iterable<TerminalNoteContextId> excluding = const <TerminalNoteContextId>[],
  }) {
    final Set<TerminalNoteContextId> reserved = excluding.toSet();
    for (
      var attempt = 0;
      attempt < TerminalNoteContextIdentityLimits.maximumCollisionAttempts;
      attempt++
    ) {
      final List<int> bytes = _source();
      if (bytes.length != TerminalNoteContextIdentityLimits.byteLength ||
          bytes.any((int value) => value < 0 || value > 0xff)) {
        throw const TerminalNoteContextIdentityException(
          TerminalNoteContextIdentityFailure.entropyRejected,
        );
      }
      final StringBuffer encoded = StringBuffer();
      for (final int byte in bytes) {
        encoded.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      final TerminalNoteContextId candidate = TerminalNoteContextId.fromHex(
        encoded.toString(),
      );
      if (!reserved.contains(candidate)) return candidate;
    }
    throw const TerminalNoteContextIdentityException(
      TerminalNoteContextIdentityFailure.collisionLimit,
    );
  }
}

/// One version-1 restoration snapshot and the exact bytes used for binding.
final class TerminalNoteRestorationArtifact {
  factory TerminalNoteRestorationArtifact.fromSnapshot(
    TerminalRestorationSnapshot snapshot,
  ) => TerminalNoteRestorationArtifact._(
    snapshot: snapshot,
    exactEncoded: TerminalRestorationCodec.encode(snapshot),
  );

  factory TerminalNoteRestorationArtifact.fromExactEncoded(String encoded) =>
      TerminalNoteRestorationArtifact._(
        snapshot: TerminalRestorationCodec.decode(encoded),
        exactEncoded: encoded,
      );

  TerminalNoteRestorationArtifact._({
    required this.snapshot,
    required this.exactEncoded,
  }) : exactUtf8Bytes = List<int>.unmodifiable(utf8.encode(exactEncoded)),
       restorationSha256 = terminalSha256(utf8.encode(exactEncoded));

  final TerminalRestorationSnapshot snapshot;
  final String exactEncoded;
  final List<int> exactUtf8Bytes;
  final String restorationSha256;
}

/// Captured restoration bytes plus live standard panes in exact codec order.
final class TerminalNoteRestorationCaptureArtifact {
  TerminalNoteRestorationCaptureArtifact._({
    required this.restoration,
    required Iterable<PaneId> paneIdsInTraversalOrder,
  }) : paneIdsInTraversalOrder = List<PaneId>.unmodifiable(
         paneIdsInTraversalOrder,
       ) {
    if (this.paneIdsInTraversalOrder.length != restoration.snapshot.paneCount ||
        this.paneIdsInTraversalOrder.toSet().length !=
            this.paneIdsInTraversalOrder.length) {
      throw StateError('restoration pane traversal is inconsistent');
    }
  }

  factory TerminalNoteRestorationCaptureArtifact.capture(
    TerminalApplicationState state, {
    required TerminalRestorationPlacementProvider placementForWindow,
    required TerminalRestorationWorkingDirectoryProvider
    workingDirectoryForPane,
  }) {
    final TerminalRestorationCaptureResult captured =
        TerminalApplicationRestorationCapture.captureWithTraversal(
          state,
          placementForWindow: placementForWindow,
          workingDirectoryForPane: workingDirectoryForPane,
        );
    return TerminalNoteRestorationCaptureArtifact._(
      restoration: TerminalNoteRestorationArtifact.fromSnapshot(
        captured.snapshot,
      ),
      paneIdsInTraversalOrder: captured.paneIdsInTraversalOrder,
    );
  }

  final TerminalNoteRestorationArtifact restoration;
  final List<PaneId> paneIdsInTraversalOrder;
}
