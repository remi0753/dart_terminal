import 'dart:convert';
import 'dart:io';

enum TerminalTerminfoDisposition { bundled, fallbackMissing, fallbackInvalid }

/// Validated child-process environment for Dart Terminal's local terminfo.
///
/// The product deliberately keeps the standard `xterm-256color` name. A local
/// `TERMINFO` root selects the audited bundled entry, while SSH's ordinary PTY
/// request carries only the same standard TERM name to a remote host.
final class TerminalTerminfoEnvironment {
  const TerminalTerminfoEnvironment._({
    required this.environment,
    required this.disposition,
    required this.compiledEntryBytes,
  });

  static const String terminalName = 'xterm-256color';
  static const String compiledEntryRelativePath =
      'resources/terminfo/78/xterm-256color';
  static const int maximumCompiledEntryBytes = 32 * 1024;
  static const int maximumNamesBytes = 512;

  final Map<String, String> environment;
  final TerminalTerminfoDisposition disposition;
  final int compiledEntryBytes;

  bool get usesBundledDatabase =>
      disposition == TerminalTerminfoDisposition.bundled;

  /// Environment fields represented by an ordinary SSH PTY allocation.
  ///
  /// `TERMINFO` is a local database path and is intentionally absent. A richer
  /// remote installation/wrapper is left to the later shell-integration owner.
  Map<String, String> get sshPtyEnvironment => const <String, String>{
    'TERM': terminalName,
  };

  String machineLine() =>
      'TERMINAL_TERMINFO_ENVIRONMENT '
      'disposition=${disposition.name} term=$terminalName '
      'private_database=$usesBundledDatabase '
      'compiled_bytes=$compiledEntryBytes '
      'ssh_term=${sshPtyEnvironment['TERM']} ssh_private_database=false';

  static TerminalTerminfoEnvironment resolve({
    required Map<String, String> parentEnvironment,
    String? bundledEntryPath,
  }) {
    final Map<String, String> environment = <String, String>{
      ...parentEnvironment,
      'TERM': terminalName,
      'COLORTERM': 'truecolor',
    }..remove('TERMINFO');
    if (bundledEntryPath == null) {
      return TerminalTerminfoEnvironment._(
        environment: Map<String, String>.unmodifiable(environment),
        disposition: TerminalTerminfoDisposition.fallbackMissing,
        compiledEntryBytes: 0,
      );
    }
    final _TerminfoEntryValidation validation = _validateEntry(
      bundledEntryPath,
    );
    if (!validation.valid) {
      return TerminalTerminfoEnvironment._(
        environment: Map<String, String>.unmodifiable(environment),
        disposition: TerminalTerminfoDisposition.fallbackInvalid,
        compiledEntryBytes: 0,
      );
    }
    environment['TERMINFO'] = File(bundledEntryPath)
        .parent
        .parent
        .absolute
        .path;
    return TerminalTerminfoEnvironment._(
      environment: Map<String, String>.unmodifiable(environment),
      disposition: TerminalTerminfoDisposition.bundled,
      compiledEntryBytes: validation.bytes,
    );
  }

  static _TerminfoEntryValidation _validateEntry(String path) {
    try {
      final File entry = File(path);
      if (!path.startsWith('/') ||
          !path.endsWith('/$compiledEntryRelativePath') ||
          FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.file) {
        return const _TerminfoEntryValidation.invalid();
      }
      final int length = entry.lengthSync();
      if (length <= 12 || length > maximumCompiledEntryBytes) {
        return const _TerminfoEntryValidation.invalid();
      }
      final List<int> bytes = entry.readAsBytesSync();
      final int magic = bytes[0] | (bytes[1] << 8);
      if (magic != 0x011a && magic != 0x021e) {
        return const _TerminfoEntryValidation.invalid();
      }
      final int namesLength = bytes[2] | (bytes[3] << 8);
      if (namesLength <= terminalName.length + 1 ||
          namesLength > maximumNamesBytes ||
          12 + namesLength > bytes.length ||
          bytes[11 + namesLength] != 0) {
        return const _TerminfoEntryValidation.invalid();
      }
      final String names = ascii.decode(
        bytes.sublist(12, 12 + namesLength - 1),
        allowInvalid: false,
      );
      if (!names.startsWith('$terminalName|') ||
          !names.contains('Dart Terminal audited ')) {
        return const _TerminfoEntryValidation.invalid();
      }
      return _TerminfoEntryValidation.valid(length);
    } on FileSystemException {
      return const _TerminfoEntryValidation.invalid();
    } on FormatException {
      return const _TerminfoEntryValidation.invalid();
    }
  }
}

final class _TerminfoEntryValidation {
  const _TerminfoEntryValidation.valid(this.bytes) : valid = true;
  const _TerminfoEntryValidation.invalid() : valid = false, bytes = 0;

  final bool valid;
  final int bytes;
}
