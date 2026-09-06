import 'dart:convert';
import 'dart:io';

import '../lib/src/terminal_core/terminal_compatibility_surface.dart';
import '../lib/src/terminal_core/vt_parser.dart';

const String defaultTerminalImplementationManifestPath =
    'compatibility/implemented_sequence_manifest.json';

/// Generates the reviewed snapshot of the product-code compatibility surface.
String generateTerminalImplementationManifestSource() {
  _validateDeclarations();
  final List<Map<String, Object?>> selectors = <Map<String, Object?>>[
    for (final int code in TerminalCompatibilitySurface.controlBytes)
      <String, Object?>{
        'key': '${code <= 0x1f ? 'c0' : 'c1'}:$code',
        'kind': code <= 0x1f ? 'c0' : 'c1',
        'code': code,
        'handler': 'execute',
      },
    for (final int key in TerminalCompatibilitySurface.escapeSelectors)
      _escapeRecord(key),
    for (final int key in TerminalCompatibilitySurface.csiSelectors)
      _csiRecord(key),
    for (final int key in TerminalCompatibilitySurface.dcsSelectors)
      _dcsRecord(key),
    for (final int command in TerminalCompatibilitySurface.oscCommands)
      <String, Object?>{
        'key': 'osc:$command',
        'kind': 'osc',
        'command': command,
        'handler': command == 4 || command == 10 || command == 11
            ? 'execute-or-reply'
            : 'execute',
      },
  ];
  final List<Map<String, Object?>> modes = <Map<String, Object?>>[
    for (final int mode in TerminalCompatibilitySurface.ansiModes)
      <String, Object?>{
        'key': 'mode:0:$mode',
        'private': false,
        'number': mode,
        'handler': 'execute',
      },
    for (final int mode in TerminalCompatibilitySurface.decPrivateModes)
      <String, Object?>{
        'key': 'mode:1:$mode',
        'private': true,
        'number': mode,
        'handler': 'execute',
      },
  ];
  final Map<String, Object?> manifest = <String, Object?>{
    'format': 'dart-terminal-implementation-surface',
    'version': TerminalCompatibilitySurface.formatVersion,
    'selectors': selectors,
    'modes': modes,
    'boundedUnsupportedFamilies': <String>[
      if (TerminalCompatibilitySurface.dcsIsBoundedUnsupported) 'dcs',
      for (final VtStringKind kind
          in TerminalCompatibilitySurface.boundedUnsupportedStringKinds)
        switch (kind) {
          VtStringKind.startOfString => 'sos',
          VtStringKind.privacyMessage => 'pm',
          VtStringKind.applicationProgramCommand => 'apc',
          VtStringKind.operatingSystemCommand => 'osc',
          VtStringKind.deviceControlString => 'dcs',
        },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
}

/// Returns whether [output] is the exact deterministic product-code snapshot.
bool terminalImplementationManifestIsFresh(File output) =>
    output.existsSync() &&
    output.readAsStringSync() == generateTerminalImplementationManifestSource();

Map<String, Object?> _escapeRecord(int key) {
  final int count = (key >> 16) & 0xff;
  final int firstIntermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return <String, Object?>{
    'key': 'esc:$count:$firstIntermediate:$finalByte',
    'kind': 'esc',
    'intermediates': <int>[if (count == 1) firstIntermediate],
    'finalByte': finalByte,
    'handler': 'execute',
  };
}

Map<String, Object?> _csiRecord(int key) {
  final int privateMarkerValue = (key >> 24) & 0xff;
  final int? privateMarker = privateMarkerValue == 0
      ? null
      : privateMarkerValue;
  final int count = (key >> 16) & 0xff;
  final int firstIntermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  final bool reply =
      count == 0 &&
          finalByte == 0x63 &&
          (privateMarker == null || privateMarker == 0x3e) ||
      count == 0 &&
          finalByte == 0x6e &&
          (privateMarker == null || privateMarker == 0x3f) ||
      count == 1 &&
          firstIntermediate == 0x24 &&
          finalByte == 0x70 &&
          (privateMarker == null || privateMarker == 0x3f);
  return <String, Object?>{
    'key': 'csi:${privateMarker ?? -1}:$count:$firstIntermediate:$finalByte',
    'kind': 'csi',
    'privateMarker': privateMarker,
    'intermediates': <int>[if (count == 1) firstIntermediate],
    'finalByte': finalByte,
    'handler': reply ? 'reply' : 'execute',
  };
}

Map<String, Object?> _dcsRecord(int key) {
  final int count = (key >> 16) & 0xff;
  final int firstIntermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return <String, Object?>{
    'key': 'dcs:-1:$count:$firstIntermediate:$finalByte',
    'kind': 'dcs',
    'privateMarker': null,
    'intermediates': <int>[if (count == 1) firstIntermediate],
    'finalByte': finalByte,
    'handler': 'reply',
  };
}

void _validateDeclarations() {
  _validateSortedUnique(
    TerminalCompatibilitySurface.controlBytes,
    'controlBytes',
  );
  for (final int code in TerminalCompatibilitySurface.controlBytes) {
    if (!((code >= 0 && code <= 0x1f) || (code >= 0x80 && code <= 0x9f))) {
      throw StateError('controlBytes contains an invalid code: $code');
    }
  }
  _validateSortedUnique(
    TerminalCompatibilitySurface.escapeSelectors,
    'escapeSelectors',
  );
  for (final int key in TerminalCompatibilitySurface.escapeSelectors) {
    final int count = (key >> 16) & 0xff;
    final int intermediate = (key >> 8) & 0xff;
    final int finalByte = key & 0xff;
    if ((count != 0 && count != 1) ||
        (count == 0 && intermediate != 0) ||
        (count == 1 && (intermediate < 0x20 || intermediate > 0x2f)) ||
        finalByte < 0x30 ||
        finalByte > 0x7e) {
      throw StateError('escapeSelectors contains an invalid key: $key');
    }
  }
  _validateSortedUnique(
    TerminalCompatibilitySurface.csiSelectors,
    'csiSelectors',
  );
  for (final int key in TerminalCompatibilitySurface.csiSelectors) {
    final int privateMarker = (key >> 24) & 0xff;
    final int count = (key >> 16) & 0xff;
    final int intermediate = (key >> 8) & 0xff;
    final int finalByte = key & 0xff;
    if ((privateMarker != 0 &&
            (privateMarker < 0x3c || privateMarker > 0x3f)) ||
        (count != 0 && count != 1) ||
        (count == 0 && intermediate != 0) ||
        (count == 1 && (intermediate < 0x20 || intermediate > 0x2f)) ||
        finalByte < 0x40 ||
        finalByte > 0x7e) {
      throw StateError('csiSelectors contains an invalid key: $key');
    }
  }
  _validateSortedUnique(
    TerminalCompatibilitySurface.oscCommands,
    'oscCommands',
  );
  _validateSortedUnique(
    TerminalCompatibilitySurface.dcsSelectors,
    'dcsSelectors',
  );
  for (final int key in TerminalCompatibilitySurface.dcsSelectors) {
    final int count = (key >> 16) & 0xff;
    final int intermediate = (key >> 8) & 0xff;
    final int finalByte = key & 0xff;
    if ((count != 0 && count != 1) ||
        (count == 0 && intermediate != 0) ||
        (count == 1 && (intermediate < 0x20 || intermediate > 0x2f)) ||
        finalByte < 0x40 ||
        finalByte > 0x7e) {
      throw StateError('dcsSelectors contains an invalid key: $key');
    }
  }
  _validateSortedUnique(TerminalCompatibilitySurface.ansiModes, 'ansiModes');
  _validateSortedUnique(
    TerminalCompatibilitySurface.decPrivateModes,
    'decPrivateModes',
  );
  for (final int value in <int>[
    ...TerminalCompatibilitySurface.oscCommands,
    ...TerminalCompatibilitySurface.ansiModes,
    ...TerminalCompatibilitySurface.decPrivateModes,
  ]) {
    if (value < 0 || value > 65535) {
      throw StateError('command/mode value is outside 0..65535: $value');
    }
  }
  final List<VtStringKind> stringKinds =
      TerminalCompatibilitySurface.boundedUnsupportedStringKinds;
  if (stringKinds.length != 3 || stringKinds.toSet().length != 3) {
    throw StateError('bounded unsupported string kinds must be unique/exact');
  }
}

void _validateSortedUnique(List<int> values, String name) {
  int? previous;
  for (final int value in values) {
    if (previous != null && value <= previous) {
      throw StateError('$name must be strictly sorted and unique');
    }
    previous = value;
  }
}

void main(List<String> arguments) {
  String outputPath = defaultTerminalImplementationManifestPath;
  bool check = false;
  for (final String argument in arguments) {
    if (argument == '--check') {
      check = true;
    } else if (outputPath == defaultTerminalImplementationManifestPath) {
      outputPath = argument;
    } else {
      stderr.writeln(
        'TERMINAL_IMPLEMENTATION_MANIFEST_FAIL usage: '
        'dart run tool/generate_terminal_compatibility_manifest.dart '
        '[--check] [output]',
      );
      exitCode = 64;
      return;
    }
  }
  final Directory repositoryRoot = File.fromUri(Platform.script)
      .absolute
      .parent
      .parent;
  final File output = File.fromUri(repositoryRoot.uri.resolve(outputPath));
  final String generated = generateTerminalImplementationManifestSource();
  if (check) {
    if (!terminalImplementationManifestIsFresh(output)) {
      stderr.writeln(
        'TERMINAL_IMPLEMENTATION_MANIFEST_STALE path=$outputPath; regenerate '
        'with `dart run tool/generate_terminal_compatibility_manifest.dart`',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'TERMINAL_IMPLEMENTATION_MANIFEST_CHECK_PASS path=$outputPath',
    );
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(generated);
  stdout.writeln('TERMINAL_IMPLEMENTATION_MANIFEST_GENERATED path=$outputPath');
}
