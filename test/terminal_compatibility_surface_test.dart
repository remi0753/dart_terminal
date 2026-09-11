import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import '../lib/src/terminal_core/terminal_compatibility_surface.dart';
import '../tool/generate_terminal_compatibility_manifest.dart'
    as manifest_generator;

void main() => runTerminalCompatibilitySurfaceTests();

void runTerminalCompatibilitySurfaceTests() {
  _testGeneratedManifestIsDeterministicAndFresh();
  _testEveryDeclaredSelectorReachesSemanticDispatch();
  _testEveryDeclaredModeReachesSemanticDispatch();
  _testBoundedUnsupportedFamiliesAndNegativeSelectors();
}

void _testGeneratedManifestIsDeterministicAndFresh() {
  final String first = manifest_generator
      .generateTerminalImplementationManifestSource();
  final String second = manifest_generator
      .generateTerminalImplementationManifestSource();
  final String checkedIn = File(
    manifest_generator.defaultTerminalImplementationManifestPath,
  ).readAsStringSync();
  final Map<String, Object?> root = jsonDecode(first) as Map<String, Object?>;
  final List<Object?> selectors = root['selectors']! as List<Object?>;
  final List<Object?> modes = root['modes']! as List<Object?>;
  final List<Object?> ignored =
      root['boundedUnsupportedFamilies']! as List<Object?>;
  _expect(first == second, 'implementation manifest generation is stable');
  _expect(first == checkedIn, 'checked-in implementation manifest is fresh');
  _expect(
    root['format'] == 'dart-terminal-implementation-surface' &&
        root['version'] == 1 &&
        selectors.length == 89 &&
        modes.length == 27 &&
        _listsEqual(ignored, const <String>['dcs', 'sos', 'pm', 'apc']),
    'manifest has the reviewed selector, mode, and policy totals',
  );

  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-implementation-manifest-',
  );
  try {
    final File candidate = File('${temporary.path}/manifest.json');
    _expect(
      !manifest_generator.terminalImplementationManifestIsFresh(candidate),
      'a missing generated manifest is stale',
    );
    candidate.writeAsStringSync('{}\n');
    _expect(
      !manifest_generator.terminalImplementationManifestIsFresh(candidate),
      'changed generated content is stale',
    );
    candidate.writeAsStringSync(first);
    _expect(
      manifest_generator.terminalImplementationManifestIsFresh(candidate),
      'exact generated content is fresh',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

void _testEveryDeclaredSelectorReachesSemanticDispatch() {
  for (final int controlByte in TerminalCompatibilitySurface.controlBytes) {
    final _ParseResult result = _parse(<int>[controlByte]);
    _expect(
      result.sink.unsupportedControlCount == 0 &&
          result.sink.unsupportedSequenceCount == 0,
      'declared control $controlByte reaches semantic dispatch',
    );
  }
  for (final int key in TerminalCompatibilitySurface.escapeSelectors) {
    final int count = (key >> 16) & 0xff;
    final int intermediate = (key >> 8) & 0xff;
    final int finalByte = key & 0xff;
    final _ParseResult result = _parse(<int>[
      0x1b,
      if (count == 1) intermediate,
      finalByte,
    ]);
    _expect(
      result.sink.unsupportedSequenceCount == 0,
      'declared ESC key $key reaches semantic dispatch',
    );
  }
  for (final int key in TerminalCompatibilitySurface.csiSelectors) {
    final _ParseResult result = _parse(_csiProbe(key));
    _expect(
      result.sink.unsupportedSequenceCount == 0,
      'declared CSI key $key reaches semantic dispatch',
    );
  }
  for (final int command in TerminalCompatibilitySurface.oscCommands) {
    final _ParseResult result = _parse(_oscProbe(command));
    _expect(
      result.sink.unsupportedSequenceCount == 0,
      'declared OSC command $command reaches semantic dispatch',
    );
  }
  for (final int key in TerminalCompatibilitySurface.dcsSelectors) {
    final _ParseResult result = _parse(_dcsProbe(key));
    _expect(
      result.sink.unsupportedSequenceCount == 0 &&
          result.sink.acceptedReplyCount == 1,
      'declared DCS key $key reaches bounded reply dispatch',
    );
  }
}

void _testEveryDeclaredModeReachesSemanticDispatch() {
  for (final int mode in TerminalCompatibilitySurface.ansiModes) {
    final _ParseResult result = _parse(
      ascii.encode(
        '\x1b[$mode'
        'h\x1b[$mode'
        'l',
      ),
    );
    _expect(
      result.sink.unsupportedSequenceCount == 0,
      'declared ANSI mode $mode supports set and reset',
    );
  }
  for (final int mode in TerminalCompatibilitySurface.decPrivateModes) {
    final _ParseResult result = _parse(
      ascii.encode(
        '\x1b[?$mode'
        'h\x1b[?$mode'
        'l',
      ),
    );
    _expect(
      result.sink.unsupportedSequenceCount == 0,
      'declared DEC private mode $mode supports set and reset',
    );
  }
}

void _testBoundedUnsupportedFamiliesAndNegativeSelectors() {
  final List<List<int>> boundedUnsupported = <List<int>>[
    ascii.encode('\x1bP1\x24qpayload\x1b\\'),
    ascii.encode('\x1bXpayload\x1b\\'),
    ascii.encode('\x1b^payload\x1b\\'),
    ascii.encode('\x1b_payload\x1b\\'),
  ];
  for (final List<int> input in boundedUnsupported) {
    final _ParseResult result = _parse(input);
    _expect(
      result.sink.unsupportedSequenceCount == 1 &&
          result.sink.limitCount == 0 &&
          result.sink.malformedCount == 0,
      'declared unsupported family is consumed once and remains bounded',
    );
  }

  final _ParseResult unknownControl = _parse(const <int>[0x01]);
  final _ParseResult unknownEscape = _parse(ascii.encode('\x1bZ'));
  final _ParseResult unknownCsi = _parse(ascii.encode('\x1b[z'));
  final _ParseResult unknownOsc = _parse(ascii.encode('\x1b]999;x\x07'));
  final _ParseResult unknownMode = _parse(ascii.encode('\x1b[?999h'));
  _expect(
    unknownControl.sink.unsupportedControlCount == 1 &&
        unknownEscape.sink.unsupportedSequenceCount == 1 &&
        unknownCsi.sink.unsupportedSequenceCount == 1 &&
        unknownOsc.sink.unsupportedSequenceCount == 1 &&
        unknownMode.sink.unsupportedSequenceCount == 1,
    'selectors outside the declarations remain explicitly unsupported',
  );
}

List<int> _csiProbe(int key) {
  final int privateMarker = (key >> 24) & 0xff;
  final int count = (key >> 16) & 0xff;
  final int intermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  final String parameters;
  if (count == 1 && intermediate == 0x20 && finalByte == 0x71) {
    parameters = '2';
  } else if (count == 1 && intermediate == 0x24 && finalByte == 0x70) {
    parameters = privateMarker == 0x3f ? '25' : '4';
  } else if (privateMarker == 0 && count == 0 && finalByte == 0x74) {
    parameters = '22;2';
  } else if (privateMarker == 0x3e && count == 0 && finalByte == 0x71) {
    parameters = '0';
  } else if (privateMarker == 0x3f && count == 0 && finalByte == 0x6d) {
    parameters = '4';
  } else if (privateMarker == 0x3e && count == 0 && finalByte == 0x6d) {
    parameters = '';
  } else if ((privateMarker == 0x3c ||
          privateMarker == 0x3d ||
          privateMarker == 0x3e ||
          privateMarker == 0x3f) &&
      count == 0 &&
      finalByte == 0x75) {
    parameters = '';
  } else {
    parameters = switch (finalByte) {
      0x63 => '0',
      0x67 => '0',
      0x68 || 0x6c => privateMarker == 0x3f ? '25' : '4',
      0x6d => '0',
      0x6e => privateMarker == 0x3f ? '6' : '5',
      0x72 => '1;2',
      _ => '1',
    };
  }
  return <int>[
    0x1b,
    0x5b,
    if (privateMarker != 0) privateMarker,
    ...ascii.encode(parameters),
    if (count == 1) intermediate,
    finalByte,
  ];
}

List<int> _oscProbe(int command) {
  final String payload = switch (command) {
    0 => '0;window and icon',
    1 => '1;icon',
    2 => '2;window',
    4 => '4;1;#010203',
    7 => '7;file:///tmp/project',
    8 => '8;;https://example.invalid/',
    10 => '10;#102030',
    11 => '11;#405060',
    12 => '12;#708090',
    52 => '52;c;?',
    104 => '104',
    110 => '110',
    111 => '111',
    112 => '112',
    133 => '133;A',
    _ => throw StateError('missing OSC probe for $command'),
  };
  return ascii.encode('\x1b]$payload\x07');
}

List<int> _dcsProbe(int key) {
  final int count = (key >> 16) & 0xff;
  final int intermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return <int>[
    0x1b,
    0x50,
    if (count == 1) intermediate,
    finalByte,
    ...ascii.encode(intermediate == 0x24 ? 'm' : '4D73'),
    0x1b,
    0x5c,
  ];
}

_ParseResult _parse(List<int> input) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 6, columns: 8);
  screens.updateLogicalViewportSize(width: 800, height: 600);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (_) => true,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(Uint8List.fromList(input));
  parser.finish();
  return (sink: sink, screens: screens);
}

typedef _ParseResult = ({
  TerminalScreenParserSink sink,
  TerminalScreenSet screens,
});

bool _listsEqual(List<Object?> first, List<Object?> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
