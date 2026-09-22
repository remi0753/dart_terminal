import 'dart:convert';
import 'dart:io';

import 'terminal_restoration.dart';
import 'terminal_restoration_lifecycle.dart';
import 'terminal_sha256.dart';

/// The ordinary application's own restoration file, independent of Notes.
final class TerminalInteractiveRestorationLocation {
  TerminalInteractiveRestorationLocation.fromEnvironment(
    Map<String, String> environment,
  ) : path = _pathFromEnvironment(environment);

  final String path;

  static String _pathFromEnvironment(Map<String, String> environment) {
    final String? stateRoot = environment['XDG_STATE_HOME'];
    if (stateRoot != null && _safeAbsolutePath(stateRoot)) {
      return '$stateRoot/dart-terminal/restoration.json';
    }
    final String? home = environment['HOME'];
    if (home == null || !_safeAbsolutePath(home)) {
      throw const FormatException('restoration location is unavailable');
    }
    return '$home/Library/Application Support/Dart Terminal/restoration.json';
  }

  static bool _safeAbsolutePath(String value) {
    if (!value.startsWith('/') || value.contains('\u0000')) return false;
    for (final String component in value.split('/')) {
      if (component == '.' || component == '..') return false;
    }
    return !value.runes.any((int rune) => rune < 0x20 || rune == 0x7f) &&
        utf8.encode(value).length <
            FileTerminalRestorationStore.maximumPathUtf8Bytes - 64;
  }
}

enum TerminalInteractiveRestorationLoadDisposition {
  restored,
  missing,
  untrusted,
  unavailable,
}

final class TerminalInteractiveRestorationLoad {
  const TerminalInteractiveRestorationLoad({
    required this.disposition,
    this.snapshot,
    this.exactEncoded,
  });

  final TerminalInteractiveRestorationLoadDisposition disposition;
  final TerminalRestorationSnapshot? snapshot;
  final String? exactEncoded;
}

/// Binds a normal GUI snapshot to an exact digest trust marker.
///
/// A persistent untrusted sentinel prevents an off/unavailable launch from
/// making an old Note binding trusted again by rewriting identical v1 bytes.
final class TerminalInteractiveRestorationPersistence {
  TerminalInteractiveRestorationPersistence(String path)
    : _store = FileTerminalRestorationStore(path),
      _trustPath = '$path.trusted',
      _untrustedPath = '$path.untrusted';

  static const String _trustPrefix = 'v1:';

  final FileTerminalRestorationStore _store;
  final String _trustPath;
  final String _untrustedPath;

  /// Claims a clean-shutdown snapshot. A crash or failed exit cannot replay it.
  Future<TerminalInteractiveRestorationLoad> loadAndConsumeTrusted() async {
    final String? trustedHash;
    final bool noteContextUntrusted;
    try {
      noteContextUntrusted = await File(_untrustedPath).exists();
      final File marker = File(_trustPath);
      if (!await marker.exists()) {
        if (!noteContextUntrusted && !await invalidateTrust()) {
          return const TerminalInteractiveRestorationLoad(
            disposition:
                TerminalInteractiveRestorationLoadDisposition.unavailable,
          );
        }
        return TerminalInteractiveRestorationLoad(
          disposition: noteContextUntrusted
              ? TerminalInteractiveRestorationLoadDisposition.untrusted
              : TerminalInteractiveRestorationLoadDisposition.missing,
        );
      }
      final RandomAccessFile opened = await marker.open();
      try {
        final List<int> bytes = await opened.read(72);
        if (bytes.length != 68) {
          return await _rejectUntrusted();
        }
        final String markerText = utf8.decode(bytes, allowMalformed: false);
        if (!markerText.startsWith(_trustPrefix) ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(markerText.substring(3, 67)) ||
            !markerText.endsWith('\n')) {
          return await _rejectUntrusted();
        }
        trustedHash = markerText.substring(3, 67);
      } finally {
        await opened.close();
      }
    } on Object {
      return const TerminalInteractiveRestorationLoad(
        disposition: TerminalInteractiveRestorationLoadDisposition.unavailable,
      );
    }
    final TerminalRestorationLoadResult loaded =
        await TerminalRestorationPersistence(_store).load();
    if (loaded.disposition == TerminalRestorationLoadDisposition.unavailable) {
      await invalidateTrust();
      return const TerminalInteractiveRestorationLoad(
        disposition: TerminalInteractiveRestorationLoadDisposition.unavailable,
      );
    }
    final String? exact = loaded.exactEncoded;
    if (exact == null ||
        loaded.snapshot == null ||
        terminalSha256(utf8.encode(exact)) != trustedHash) {
      return _rejectUntrusted();
    }
    try {
      await File(_trustPath).rename(_untrustedPath);
    } on Object {
      await invalidateTrust();
      return const TerminalInteractiveRestorationLoad(
        disposition: TerminalInteractiveRestorationLoadDisposition.unavailable,
      );
    }
    return TerminalInteractiveRestorationLoad(
      disposition: noteContextUntrusted
          ? TerminalInteractiveRestorationLoadDisposition.untrusted
          : TerminalInteractiveRestorationLoadDisposition.restored,
      snapshot: loaded.snapshot,
      exactEncoded: exact,
    );
  }

  Future<TerminalInteractiveRestorationLoad> _rejectUntrusted() async {
    if (!await invalidateTrust()) {
      return const TerminalInteractiveRestorationLoad(
        disposition: TerminalInteractiveRestorationLoadDisposition.unavailable,
      );
    }
    return const TerminalInteractiveRestorationLoad(
      disposition: TerminalInteractiveRestorationLoadDisposition.untrusted,
    );
  }

  /// The restoration bytes and marker must both land before the Note commit.
  Future<bool> saveTrusted(String exactEncoded) async {
    final TerminalRestorationSaveResult saved =
        await TerminalRestorationPersistence(_store)
            .saveExactEncoded(exactEncoded);
    if (saved.disposition != TerminalRestorationSaveDisposition.saved) {
      return false;
    }
    final File pending = File('$_trustPath.pending');
    try {
      final String digest = terminalSha256(utf8.encode(exactEncoded));
      await pending.writeAsString('$_trustPrefix$digest\n', flush: true);
      await pending.rename(_trustPath);
      return true;
    } on Object {
      try {
        if (await pending.exists()) await pending.delete();
      } on Object {
        // Preserve the primary failure; the next load remains fail-closed.
      }
      return false;
    }
  }

  /// Preserves the v1 snapshot and Note store while persisting distrust.
  Future<bool> invalidateTrust() async {
    try {
      await File(_untrustedPath).parent.create(recursive: true);
      final File marker = File(_trustPath);
      if (await marker.exists()) {
        await marker.rename(_untrustedPath);
        return await File(_untrustedPath).exists();
      }
      if (await File(_untrustedPath).exists()) return true;
      final File pending = File('$_untrustedPath.pending');
      try {
        await pending.writeAsString('v1:untrusted\n', flush: true);
        await pending.rename(_untrustedPath);
      } on Object {
        if (await pending.exists()) await pending.delete();
        rethrow;
      }
      return await File(_untrustedPath).exists();
    } on Object {
      return false;
    }
  }

  /// Only a completed restoration-first/Note-second commit may re-enable it.
  Future<bool> clearUntrustedAfterNoteCommit() async {
    try {
      final File sentinel = File(_untrustedPath);
      if (await sentinel.exists()) await sentinel.delete();
      return !await sentinel.exists();
    } on Object {
      return false;
    }
  }
}
