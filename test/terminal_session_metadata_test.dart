import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSessionMetadataTests();

void runTerminalSessionMetadataTests() {
  final TerminalSessionMetadata metadata = TerminalSessionMetadata();
  _expect(metadata.generation == 1, 'metadata starts at generation one');
  _expect(
    metadata.windowTitle == null &&
        metadata.iconTitle == null &&
        metadata.workingDirectory == null,
    'metadata starts without host-controlled values',
  );
  _expect(
    metadata.setIconAndWindowTitle('Dart Terminal — 日本語'),
    'safe Unicode title mutates both title channels',
  );
  _expect(
    metadata.windowTitle == 'Dart Terminal — 日本語' &&
        metadata.iconTitle == 'Dart Terminal — 日本語',
    'combined title mutation is atomic',
  );
  _expect(
    !metadata.setWindowTitle('Dart Terminal — 日本語'),
    'equal title does not change generation',
  );
  _expect(
    !TerminalSessionMetadata.isSafeTitle('line\nspoof') &&
        !TerminalSessionMetadata.isSafeTitle('left\u202eright') &&
        !TerminalSessionMetadata.isSafeTitle(
          List<String>.filled(
            TerminalSessionMetadata.maximumTitleUtf8Bytes + 1,
            'x',
          ).join(),
        ),
    'controls, bidi controls, and oversized titles are unsafe',
  );
  _expectThrows<ArgumentError>(
    () => metadata.setWindowTitle('unsafe\u0000title'),
    'direct title mutation preserves metadata invariants',
  );

  final Uri cwd = Uri.parse('file://host.example/Users/remi/Project%20One');
  _expect(metadata.setWorkingDirectory(cwd), 'safe OSC 7 URI is accepted');
  _expect(
    metadata.workingDirectory == cwd &&
        !TerminalSessionMetadata.isSafeWorkingDirectory(
          Uri.parse('https://example.invalid/path'),
        ) &&
        !TerminalSessionMetadata.isSafeWorkingDirectory(
          Uri.parse('file:///tmp/path?query=yes'),
        ),
    'cwd metadata is restricted to non-query file URIs',
  );

  final List<List<int>> validMetadataSequences = <List<int>>[
    _oscUtf8(0, 'icon and window'),
    _oscUtf8(1, 'icon only'),
    _oscUtf8(2, 'window 日本語'),
    _oscUtf8(7, 'file://mac.local/Users/remi/%E6%97%A5%E6%9C%AC%E8%AA%9E'),
  ];
  for (int index = 0; index < validMetadataSequences.length; index++) {
    final _ParseResult item = _parse(validMetadataSequences[index]);
    _expect(
      item.sink.unsupportedSequenceCount == 0,
      'valid OSC metadata item $index: '
      'unsupported=${item.sink.unsupportedSequenceCount}',
    );
  }
  final _ParseResult parsed = _parse(<int>[
    for (final List<int> sequence in validMetadataSequences) ...sequence,
  ]);
  _expect(
    parsed.sink.unsupportedSequenceCount == 0,
    'valid OSC metadata: unsupported=${parsed.sink.unsupportedSequenceCount}',
  );
  _expect(
    parsed.screens.metadata.iconTitle == 'icon only' &&
        parsed.screens.metadata.windowTitle == 'window 日本語' &&
        parsed.screens.metadata.workingDirectory.toString() ==
            'file://mac.local/Users/remi/%E6%97%A5%E6%9C%AC%E8%AA%9E',
    'OSC 0/1/2/7 update session metadata independently',
  );

  final _ParseResult titleStack = _parse(<int>[
    ..._oscUtf8(0, 'base'),
    ..._csi('22;0;0t'),
    ..._oscUtf8(1, 'next icon'),
    ..._oscUtf8(2, 'next window'),
    ..._csi('23;0;0t'),
    ..._csi('22;2t'),
    ..._oscUtf8(2, 'temporary'),
    ..._csi('23;2t'),
  ]);
  _expect(
    titleStack.sink.unsupportedSequenceCount == 0 &&
        titleStack.screens.metadata.iconTitle == 'base' &&
        titleStack.screens.metadata.windowTitle == 'base' &&
        titleStack.screens.metadata.iconTitleStack.isEmpty &&
        titleStack.screens.metadata.windowTitleStack.isEmpty,
    'captured and standard title-stack forms restore bounded metadata',
  );
  final int beforeUnderflow = titleStack.screens.metadata.generation;
  _feed(titleStack, _csi('23;2t'));
  _expect(
    titleStack.sink.unsupportedSequenceCount == 0 &&
        titleStack.screens.metadata.generation == beforeUnderflow,
    'title-stack underflow is a bounded accepted no-op',
  );
  _feed(titleStack, _csi('22;2;1t'));
  _expect(
    titleStack.sink.unsupportedSequenceCount == 1,
    'unimplemented direct title-stack access remains explicit',
  );

  final _ParseResult boundedStack = _parse(_oscUtf8(2, '0'));
  for (int index = 0; index < 12; index++) {
    _feed(boundedStack, <int>[
      ..._csi('22;2t'),
      ..._oscUtf8(2, '${index + 1}'),
    ]);
  }
  _expect(
    boundedStack.screens.metadata.windowTitleStack.length ==
        TerminalSessionMetadata.titleStackCapacity,
    'title stack discards its oldest entry at fixed capacity',
  );
  for (
    int index = 0;
    index < TerminalSessionMetadata.titleStackCapacity;
    index++
  ) {
    _feed(boundedStack, _csi('23;2t'));
  }
  _expect(
    boundedStack.screens.metadata.windowTitle == '2',
    'bounded title stack preserves the newest ten entries',
  );

  final _ParseResult invalid = _parse(_oscUtf8(2, 'safe'));
  final int invalidBaseline = invalid.sink.unsupportedSequenceCount;
  _feed(invalid, <int>[0x1b, 0x5d, ...ascii.encode('2;'), 0xff, 0x07]);
  _feed(invalid, <int>[0x1b, 0x5d, ...ascii.encode('2;'), 0xe0, 0x9c]);
  _feed(invalid, _oscUtf8(2, 'line\u2028spoof'));
  _feed(invalid, _oscUtf8(7, 'https://example.invalid/path'));
  _feed(invalid, _oscUtf8(7, 'file:///tmp/path#fragment'));
  _feed(
    invalid,
    _oscUtf8(
      2,
      List<String>.filled(
        TerminalSessionMetadata.maximumTitleUtf8Bytes + 1,
        'x',
      ).join(),
    ),
  );
  _expect(
    invalid.sink.unsupportedSequenceCount == invalidBaseline + 6 &&
        invalid.screens.metadata.windowTitle == 'safe' &&
        invalid.screens.metadata.workingDirectory == null,
    'invalid metadata is rejected atomically without partial mutation',
  );

  final _ParseResult lifecycle = _parse(<int>[
    ..._oscUtf8(2, 'persistent'),
    ..._oscUtf8(7, 'file:///tmp/project'),
    ..._csi('22;2t'),
    ..._csi('?1049h'),
    ..._csi('?1049l'),
  ]);
  _expect(
    lifecycle.screens.metadata.windowTitle == 'persistent' &&
        lifecycle.screens.metadata.workingDirectory.toString() ==
            'file:///tmp/project' &&
        lifecycle.screens.metadata.windowTitleStack.length == 1,
    'metadata is session state across alternate-screen transitions',
  );
  _feed(lifecycle, const <int>[0x1b, 0x63]);
  _expect(
    lifecycle.screens.metadata.windowTitle == null &&
        lifecycle.screens.metadata.workingDirectory == null &&
        lifecycle.screens.metadata.windowTitleStack.isEmpty,
    'RIS resets all host-controlled session metadata',
  );

  final List<int> chunkInput = <int>[
    ..._oscUtf8(0, 'chunk 日本語'),
    ..._oscUtf8(7, 'file:///Users/remi/chunk'),
    ..._csi('22;0;0t'),
    ..._oscUtf8(2, 'temporary'),
  ];
  final String whole = _snapshot(chunkInput, null);
  for (int split = 0; split <= chunkInput.length; split++) {
    _expect(
      _snapshot(chunkInput, split) == whole,
      'OSC metadata is chunk invariant at split $split',
    );
  }
  _expect(
    whole.contains(
          'metadata window_title="temporary" icon_title="chunk 日本語" '
          'cwd="file:///Users/remi/chunk"',
        ) &&
        whole.contains('window_title_stack=["chunk 日本語"]') &&
        whole.contains('icon_title_stack=["chunk 日本語"]'),
    'screen-set snapshot serializes future-affecting metadata and stacks',
  );
}

String _snapshot(List<int> bytes, int? split) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  if (split == null) {
    parser.parse(Uint8List.fromList(bytes));
  } else {
    parser.parse(Uint8List.fromList(bytes.sublist(0, split)));
    parser.parse(Uint8List.fromList(bytes.sublist(split)));
  }
  parser.finish();
  return const TerminalSnapshotFormatter().formatScreenSet(
    screens,
    parserSink: sink,
  );
}

_ParseResult _parse(List<int> bytes) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 8);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
  );
  final VtParser parser = VtParser(sink: sink);
  parser.parse(Uint8List.fromList(bytes));
  parser.finish();
  return (screens: screens, sink: sink, parser: parser);
}

void _feed(_ParseResult result, List<int> bytes) {
  result.parser.parse(Uint8List.fromList(bytes));
}

List<int> _oscUtf8(int command, String payload) => <int>[
  0x1b,
  0x5d,
  ...ascii.encode('$command;'),
  ...utf8.encode(payload),
  0x1b,
  0x5c,
];

List<int> _csi(String payload) => <int>[0x1b, 0x5b, ...ascii.encode(payload)];

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError(message);
}

typedef _ParseResult = ({
  TerminalScreenSet screens,
  TerminalScreenParserSink sink,
  VtParser parser,
});
