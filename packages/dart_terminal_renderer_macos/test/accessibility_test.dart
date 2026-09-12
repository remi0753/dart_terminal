import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void runAccessibilityTests() {
  _testDeterministicPacket();
  _testTopologyAndRangeValidation();
}

void _testDeterministicPacket() {
  final TerminalAccessibilityViewSnapshot snapshot =
      TerminalAccessibilityViewSnapshot(
        generation: 7,
        rows: 2,
        columns: 4,
        text: 'A界\nB',
        lines: <TerminalAccessibilityViewLine>[
          TerminalAccessibilityViewLine(
            row: 0,
            utf16Start: 0,
            utf16Length: 2,
            columnUtf16Offsets: const <int>[0, 1, 1, 2],
          ),
          TerminalAccessibilityViewLine(
            row: 1,
            utf16Start: 3,
            utf16Length: 1,
            columnUtf16Offsets: const <int>[0, 1],
          ),
        ],
        selectedRange: TerminalAccessibilityRange(location: 1, length: 1),
        hasVisibleSelection: true,
        cursorRange: TerminalAccessibilityRange(location: 4, length: 0),
        cursorRow: 1,
        cursorColumn: 1,
        cellWidth: 10,
        cellHeight: 20,
        contentOriginX: 12,
        contentOriginY: 8,
      );
  final Uint8List packet = snapshot.encode();
  final ByteData data = ByteData.sublistView(packet);
  _expect(
    data.getUint32(0, Endian.little) == 136 &&
        data.getUint32(4, Endian.little) == 2 &&
        data.getUint32(8, Endian.little) == 7 &&
        data.getUint32(12, Endian.little) == 3 &&
        data.getUint64(16, Endian.little) == 7 &&
        data.getUint32(24, Endian.little) == 2 &&
        data.getUint32(28, Endian.little) == 4 &&
        data.getUint32(32, Endian.little) == 6 &&
        data.getUint32(36, Endian.little) == 4 &&
        data.getUint32(40, Endian.little) == 2 &&
        data.getUint32(44, Endian.little) == 6 &&
        data.getUint32(48, Endian.little) == 1 &&
        data.getUint32(52, Endian.little) == 1 &&
        data.getUint32(56, Endian.little) == 4 &&
        data.getUint32(60, Endian.little) == 1 &&
        data.getUint32(64, Endian.little) == 1 &&
        data.getFloat64(72, Endian.little) == 10 &&
        data.getFloat64(80, Endian.little) == 20 &&
        data.getFloat64(88, Endian.little) == 12 &&
        data.getFloat64(96, Endian.little) == 8 &&
        data.getUint32(104, Endian.little) == 136 &&
        data.getUint32(108, Endian.little) == 176 &&
        data.getUint32(112, Endian.little) == 200 &&
        data.getUint32(116, Endian.little) == 206,
    'accessibility header is exact and bounded',
  );
  _expect(
    data.getUint32(136, Endian.little) == 0 &&
        data.getUint32(140, Endian.little) == 0 &&
        data.getUint32(144, Endian.little) == 2 &&
        data.getUint32(148, Endian.little) == 0 &&
        data.getUint32(152, Endian.little) == 4 &&
        data.getUint32(156, Endian.little) == 1 &&
        data.getUint32(160, Endian.little) == 3 &&
        data.getUint32(164, Endian.little) == 1 &&
        data.getUint32(168, Endian.little) == 4 &&
        data.getUint32(172, Endian.little) == 2,
    'physical line records are canonical and contiguous',
  );
  final List<int> boundaries = <int>[
    for (var offset = 176; offset < 200; offset += 4)
      data.getUint32(offset, Endian.little),
  ];
  _expect(
    boundaries.join(',') == '0,1,1,2,0,1' &&
        utf8.decode(packet.sublist(200)) == 'A界\nB',
    'column topology and UTF-8 text follow the records exactly',
  );
}

void _testTopologyAndRangeValidation() {
  _expectArgument(
    () => TerminalAccessibilityViewLine(
      row: 0,
      utf16Start: 0,
      utf16Length: 2,
      columnUtf16Offsets: const <int>[0, 2, 1],
    ),
    'nonmonotonic columns',
  );
  _expectArgument(
    () => _snapshot(
      text: 'A\nB',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 1, const <int>[0, 1]),
        _line(1, 1, 1, const <int>[0, 1]),
      ],
    ),
    'line start skipping newline',
  );
  _expectArgument(
    () => _snapshot(
      text: '😀',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 2, const <int>[0, 2]),
      ],
      selected: TerminalAccessibilityRange(location: 1, length: 0),
    ),
    'range splitting surrogate pair',
  );
  _expectArgument(
    () => _snapshot(
      text: '😀',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 2, const <int>[0, 1, 2]),
      ],
    ),
    'column splitting surrogate pair',
  );
  _expectArgument(
    () => _snapshot(
      text: 'A',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 1, const <int>[0, 1]),
      ],
      cursor: TerminalAccessibilityRange(location: 0, length: 0),
      cursorRow: 0,
      cursorColumn: 1,
    ),
    'cursor location disagrees with column boundary',
  );
  _expectRange(
    () => TerminalAccessibilityRange(location: 0x7fffffff, length: 1),
    'signed range overflow',
  );
  _expectArgument(
    () => _snapshot(
      text: 'A',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 1, const <int>[0, 1]),
      ],
      contentOriginX: -1,
    ),
    'negative content origin',
  );
  _expectArgument(
    () => _snapshot(
      text: 'A',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 1, const <int>[0, 1]),
      ],
      contentOriginY: double.nan,
    ),
    'non-finite content origin',
  );
  _expectArgument(
    () => _snapshot(
      text: 'A',
      lines: <TerminalAccessibilityViewLine>[
        _line(0, 0, 1, const <int>[0, 1]),
      ],
      contentOriginX:
          TerminalAccessibilityViewSnapshot.maximumContentOrigin + 1,
    ),
    'oversized content origin',
  );
  _expect(
    TerminalAccessibilityViewSnapshot.maximumUtf8Bytes == 4 * 1024 * 1024 &&
        TerminalAccessibilityViewSnapshot.maximumUtf16CodeUnits ==
            2 * 1024 * 1024 &&
        TerminalAccessibilityViewSnapshot.maximumLines == 4096 &&
        TerminalAccessibilityViewSnapshot.maximumColumns == 4096 &&
        TerminalAccessibilityViewSnapshot.maximumColumnBoundaries ==
            1048576 + 4096 &&
        TerminalAccessibilityViewSnapshot.maximumPacketBytes ==
            9 * 1024 * 1024 &&
        TerminalAccessibilityViewSnapshot.maximumContentOrigin == 4096,
    'Dart limits reproduce the native capability contract',
  );
}

TerminalAccessibilityViewSnapshot _snapshot({
  required String text,
  required List<TerminalAccessibilityViewLine> lines,
  TerminalAccessibilityRange? selected,
  TerminalAccessibilityRange? cursor,
  int? cursorRow,
  int? cursorColumn,
  double contentOriginX = 0,
  double contentOriginY = 0,
}) => TerminalAccessibilityViewSnapshot(
  generation: 1,
  rows: lines.length,
  columns: 4,
  text: text,
  lines: lines,
  selectedRange: selected ?? TerminalAccessibilityRange(location: 0, length: 0),
  hasVisibleSelection: (selected?.length ?? 0) > 0,
  cursorRange: cursor,
  cursorRow: cursorRow,
  cursorColumn: cursorColumn,
  cellWidth: 10,
  cellHeight: 20,
  contentOriginX: contentOriginX,
  contentOriginY: contentOriginY,
);

TerminalAccessibilityViewLine _line(
  int row,
  int start,
  int length,
  List<int> columns,
) => TerminalAccessibilityViewLine(
  row: row,
  utf16Start: start,
  utf16Length: length,
  columnUtf16Offsets: columns,
);

void _expectArgument(void Function() callback, String description) {
  try {
    callback();
  } on ArgumentError {
    return;
  }
  throw StateError('Expected ArgumentError: $description');
}

void _expectRange(void Function() callback, String description) {
  try {
    callback();
  } on RangeError {
    return;
  }
  throw StateError('Expected RangeError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
