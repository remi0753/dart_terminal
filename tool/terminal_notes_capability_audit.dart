import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tool/terminal_notes_capability_audit.dart <dylib>',
    );
    exitCode = 64;
    return;
  }
  final Directory root = File.fromUri(Platform.script).parent.parent;
  final File library = File(arguments.single);
  _expect(library.existsSync(), 'native capability library is missing');

  final String rootPubspec = _read(root, 'pubspec.yaml');
  final String appManifest = _read(root, 'macos_application.json');
  _expect(
    !rootPubspec.contains('dart_terminal_notes_macos') &&
        !appManifest.contains('dart_terminal_notes_macos'),
    'CM-08 must remain absent from the application dependency and manifest',
  );

  final String header = _read(
    root,
    'packages/dart_terminal_notes_macos/native/TerminalNotesPlugin.h',
  );
  final String presentationSnapshot = _between(
    header,
    'typedef struct DtnPresentationSnapshotV1 {',
    '} DtnPresentationSnapshotV1;',
  );
  final String stateSnapshot = _between(
    header,
    'typedef struct DtnSurfaceSnapshotV1 {',
    '} DtnSurfaceSnapshotV1;',
  );
  for (final String forbidden in <String>[
    'body_text',
    'body_bytes',
    'body_offset',
    'color',
    'token',
    'timestamp',
    'path',
    'persistent',
  ]) {
    _expect(
      !presentationSnapshot.toLowerCase().contains(forbidden) &&
          !stateSnapshot.toLowerCase().contains(forbidden),
      'public machine snapshot exposes forbidden field: $forbidden',
    );
  }

  final String nativeSource = _read(
    root,
    'packages/dart_terminal_notes_macos/native/TerminalNotesPlugin.m',
  );
  for (final String forbiddenLog in <String>[
    'NSLog(',
    'os_log(',
    'fprintf(',
    'printf(',
  ]) {
    _expect(
      !nativeSource.contains(forbiddenLog),
      'native capability contains an unbounded diagnostic sink',
    );
  }
  _expect(
    header.contains('#define DTN_MAX_CARDS 64u') &&
        header.contains('#define DTN_MAX_MATERIALIZED_CARDS 32u') &&
        header.contains('#define DTN_MAX_CARD_BODY_BYTES 4096u') &&
        header.contains('#define DTN_MAX_BODY_BYTES (256u * 1024u)'),
    'native resource bounds changed without an ABI review',
  );

  final ProcessResult symbols = await Process.run('/usr/bin/nm', <String>[
    '-gjU',
    library.absolute.path,
  ]);
  _expect(symbols.exitCode == 0, 'failed to inspect native exports');
  final Set<String> actual = (symbols.stdout as String)
      .split('\n')
      .where((String line) => line.isNotEmpty)
      .toSet();
  const Set<String> expected = <String>{
    '_dtn_abi_version',
    '_dtn_debug_live_surfaces',
    '_dtn_surface_apply_projection',
    '_dtn_surface_apply_result',
    '_dtn_surface_attach_to_host',
    '_dtn_surface_create',
    '_dtn_surface_destroy',
    '_dtn_surface_detach_from_host',
    '_dtn_surface_focus',
    '_dtn_surface_native_view',
    '_dtn_surface_presentation_snapshot',
    '_dtn_surface_request_intent',
    '_dtn_surface_snapshot',
    '_dtn_surface_take_intent',
    '_dtn_surface_update_layout',
  };
  _expect(
    actual.length == expected.length && actual.containsAll(expected),
    'native export allowlist changed',
  );

  final Directory appkit = Directory('${root.parent.path}/dart_appkit');
  _expect(appkit.existsSync(), 'generic dart_appkit dependency is missing');
  final ProcessResult appkitSearch = await Process.run('/usr/bin/git', <String>[
    '-C',
    appkit.path,
    'grep',
    '-n',
    '-E',
    'DtnNote|TerminalNotes|dart_terminal_notes',
    '--',
    '.',
  ]);
  _expect(
    appkitSearch.exitCode == 1 && (appkitSearch.stdout as String).isEmpty,
    'Dart Terminal Note code leaked into generic dart_appkit',
  );

  stdout.writeln(
    'TERMINAL_NOTES_CAPABILITY_AUDIT_PASS manifest=absent '
    'snapshot=content-free exports=${actual.length} dart_appkit=generic',
  );
}

String _read(Directory root, String relative) =>
    File('${root.path}/$relative').readAsStringSync();

String _between(String source, String start, String end) {
  final int begin = source.indexOf(start);
  final int finish = source.indexOf(end, begin + start.length);
  _expect(begin >= 0 && finish > begin, 'audit source block is missing');
  return source.substring(begin, finish + end.length);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
