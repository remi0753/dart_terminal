import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';

final class TerminalAccessibilityRange {
  TerminalAccessibilityRange({required this.location, required this.length}) {
    if (location < 0 || length < 0 || location > 0x7fffffff - length) {
      throw RangeError('accessibility range must fit signed 32-bit values');
    }
  }

  final int location;
  final int length;
  int get end => location + length;
}

final class TerminalAccessibilityViewLine {
  TerminalAccessibilityViewLine({
    required this.row,
    required this.utf16Start,
    required this.utf16Length,
    required List<int> columnUtf16Offsets,
  }) : columnUtf16Offsets = List<int>.unmodifiable(columnUtf16Offsets) {
    if (row < 0 ||
        utf16Start < 0 ||
        utf16Length < 0 ||
        columnUtf16Offsets.isEmpty) {
      throw ArgumentError('accessibility line fields must be nonnegative');
    }
    var previous = -1;
    for (final int offset in this.columnUtf16Offsets) {
      if (offset < previous || offset > utf16Length) {
        throw ArgumentError('line column offsets must be monotonic and local');
      }
      previous = offset;
    }
    if (this.columnUtf16Offsets.first != 0 ||
        this.columnUtf16Offsets.last != utf16Length) {
      throw ArgumentError('line column offsets must span its complete text');
    }
  }

  final int row;
  final int utf16Start;
  final int utf16Length;
  final List<int> columnUtf16Offsets;
  int get representedColumns => columnUtf16Offsets.length - 1;
}

final class TerminalAccessibilityViewSnapshot {
  TerminalAccessibilityViewSnapshot({
    required this.generation,
    required this.rows,
    required this.columns,
    required this.text,
    required List<TerminalAccessibilityViewLine> lines,
    required this.selectedRange,
    required this.hasVisibleSelection,
    required this.cursorRange,
    required this.cursorRow,
    required this.cursorColumn,
    required this.cellWidth,
    required this.cellHeight,
    this.contentOriginX = 0,
    this.contentOriginY = 0,
  }) : lines = List<TerminalAccessibilityViewLine>.unmodifiable(lines) {
    if (generation <= 0 || generation > 0x7fffffffffffffff) {
      throw RangeError('accessibility generation must be a positive int64');
    }
    RangeError.checkValueInInterval(rows, 1, maximumLines, 'rows');
    RangeError.checkValueInInterval(columns, 1, maximumColumns, 'columns');
    if (this.lines.length != rows) {
      throw ArgumentError('accessibility snapshot needs one line per row');
    }
    if (!cellWidth.isFinite ||
        !cellHeight.isFinite ||
        cellWidth <= 0 ||
        cellHeight <= 0) {
      throw ArgumentError('accessibility cell metrics must be finite/positive');
    }
    if (!contentOriginX.isFinite ||
        !contentOriginY.isFinite ||
        contentOriginX < 0 ||
        contentOriginY < 0 ||
        contentOriginX > maximumContentOrigin ||
        contentOriginY > maximumContentOrigin) {
      throw ArgumentError(
        'accessibility content origin must be finite and bounded',
      );
    }
    final List<int> textBytes = utf8.encode(text);
    if (textBytes.length > maximumUtf8Bytes ||
        text.length > maximumUtf16CodeUnits) {
      throw RangeError('accessibility text exceeds its native bound');
    }
    var expectedStart = 0;
    var boundaryCount = 0;
    for (var index = 0; index < this.lines.length; index++) {
      final TerminalAccessibilityViewLine line = this.lines[index];
      if (line.row != index ||
          line.utf16Start != expectedStart ||
          line.utf16Start + line.utf16Length > text.length ||
          line.representedColumns > columns) {
        throw ArgumentError('accessibility line topology is inconsistent');
      }
      for (final int offset in line.columnUtf16Offsets) {
        if (!_isScalarBoundary(text, line.utf16Start + offset)) {
          throw ArgumentError('accessibility column splits a surrogate pair');
        }
      }
      boundaryCount += line.columnUtf16Offsets.length;
      if (boundaryCount > maximumColumnBoundaries) {
        throw RangeError('accessibility column map exceeds its native bound');
      }
      final int end = line.utf16Start + line.utf16Length;
      if (index + 1 < rows) {
        if (end >= text.length || text.codeUnitAt(end) != 0x0a) {
          throw ArgumentError('physical accessibility lines need newlines');
        }
        expectedStart = end + 1;
      } else {
        expectedStart = end;
      }
    }
    if (expectedStart != text.length ||
        selectedRange.end > text.length ||
        !_isScalarBoundary(text, selectedRange.location) ||
        !_isScalarBoundary(text, selectedRange.end)) {
      throw ArgumentError('accessibility text ranges are inconsistent');
    }
    if (hasVisibleSelection != (selectedRange.length > 0)) {
      throw ArgumentError('selection flag must match its nonempty range');
    }
    final bool hasCursor = cursorRange != null;
    if (hasCursor != (cursorRow != null && cursorColumn != null)) {
      throw ArgumentError('cursor fields must be all present or all absent');
    }
    if (cursorRange != null) {
      if (cursorRange!.length != 0 ||
          cursorRange!.location > text.length ||
          cursorRow! < 0 ||
          cursorRow! >= rows ||
          cursorColumn! < 0 ||
          cursorColumn! > this.lines[cursorRow!].representedColumns ||
          this.lines[cursorRow!].utf16Start +
                  this.lines[cursorRow!].columnUtf16Offsets[cursorColumn!] !=
              cursorRange!.location ||
          (!hasVisibleSelection &&
              selectedRange.location != cursorRange!.location)) {
        throw ArgumentError('cursor range does not match its row/column');
      }
    } else if (!hasVisibleSelection && selectedRange.location != 0) {
      throw ArgumentError('cursorless collapsed selection must be at zero');
    }
  }

  static const int maximumUtf8Bytes = 4 * 1024 * 1024;
  static const int maximumUtf16CodeUnits = 2 * 1024 * 1024;
  static const int maximumLines = 4096;
  static const int maximumColumns = 4096;
  static const int maximumColumnBoundaries = 1048576 + 4096;
  static const int maximumPacketBytes = 9 * 1024 * 1024;
  static const double maximumContentOrigin = 4096;

  final int generation;
  final int rows;
  final int columns;
  final String text;
  final List<TerminalAccessibilityViewLine> lines;
  final TerminalAccessibilityRange selectedRange;
  final bool hasVisibleSelection;
  final TerminalAccessibilityRange? cursorRange;
  final int? cursorRow;
  final int? cursorColumn;
  final double cellWidth;
  final double cellHeight;
  final double contentOriginX;
  final double contentOriginY;

  Uint8List encode() {
    final Uint8List textBytes = Uint8List.fromList(utf8.encode(text));
    final int boundaryCount = lines.fold<int>(
      0,
      (int count, TerminalAccessibilityViewLine line) =>
          count + line.columnUtf16Offsets.length,
    );
    final int boundariesOffset = _headerBytes + lines.length * _lineBytes;
    final int textOffset = boundariesOffset + boundaryCount * 4;
    final int totalBytes = textOffset + textBytes.length;
    if (totalBytes > maximumPacketBytes) {
      throw RangeError('accessibility packet exceeds its native bound');
    }
    final Uint8List packet = Uint8List(totalBytes);
    final ByteData data = ByteData.sublistView(packet);
    final int flags =
        (hasVisibleSelection ? _hasSelection : 0) |
        (cursorRange != null ? _hasCursor : 0);
    data
      ..setUint32(0, _headerBytes, Endian.little)
      ..setUint32(4, _version, Endian.little)
      ..setUint32(8, _operationSnapshot, Endian.little)
      ..setUint32(12, flags, Endian.little)
      ..setUint64(16, generation, Endian.little)
      ..setUint32(24, rows, Endian.little)
      ..setUint32(28, columns, Endian.little)
      ..setUint32(32, textBytes.length, Endian.little)
      ..setUint32(36, text.length, Endian.little)
      ..setUint32(40, lines.length, Endian.little)
      ..setUint32(44, boundaryCount, Endian.little)
      ..setUint32(48, selectedRange.location, Endian.little)
      ..setUint32(52, selectedRange.length, Endian.little)
      ..setUint32(56, cursorRange?.location ?? 0xffffffff, Endian.little)
      ..setUint32(60, cursorRow ?? 0xffffffff, Endian.little)
      ..setUint32(64, cursorColumn ?? 0xffffffff, Endian.little)
      ..setFloat64(72, cellWidth, Endian.little)
      ..setFloat64(80, cellHeight, Endian.little)
      ..setFloat64(88, contentOriginX, Endian.little)
      ..setFloat64(96, contentOriginY, Endian.little)
      ..setUint32(104, _headerBytes, Endian.little)
      ..setUint32(108, boundariesOffset, Endian.little)
      ..setUint32(112, textOffset, Endian.little)
      ..setUint32(116, totalBytes, Endian.little);
    var firstBoundary = 0;
    for (var index = 0; index < lines.length; index++) {
      final TerminalAccessibilityViewLine line = lines[index];
      final int offset = _headerBytes + index * _lineBytes;
      data
        ..setUint32(offset, line.row, Endian.little)
        ..setUint32(offset + 4, line.utf16Start, Endian.little)
        ..setUint32(offset + 8, line.utf16Length, Endian.little)
        ..setUint32(offset + 12, firstBoundary, Endian.little)
        ..setUint32(offset + 16, line.columnUtf16Offsets.length, Endian.little);
      for (final int value in line.columnUtf16Offsets) {
        data.setUint32(
          boundariesOffset + firstBoundary * 4,
          value,
          Endian.little,
        );
        firstBoundary++;
      }
    }
    packet.setRange(textOffset, totalBytes, textBytes);
    return packet;
  }

  static const int _version = 2;
  static const int _operationSnapshot = 7;
  static const int _hasSelection = 1 << 0;
  static const int _hasCursor = 1 << 1;
  static const int _headerBytes = 136;
  static const int _lineBytes = 20;
}

final class TerminalAccessibilityClient {
  TerminalAccessibilityClient(this.view);

  final View view;
  int _lastGeneration = 0;

  int get lastGeneration => _lastGeneration;

  void publish(TerminalAccessibilityViewSnapshot snapshot) {
    if (snapshot.generation <= _lastGeneration) {
      throw StateError('accessibility snapshot generation must increase');
    }
    view.performCustomOperation(snapshot.encode());
    _lastGeneration = snapshot.generation;
  }

  /// Verifies the native selector/range/geometry state without returning text.
  void debugVerifyCurrentSnapshot() {
    if (_lastGeneration == 0) {
      throw StateError('an accessibility snapshot must be published first');
    }
    final Uint8List payload = Uint8List(24);
    ByteData.sublistView(payload)
      ..setUint32(0, 24, Endian.little)
      ..setUint32(4, 2, Endian.little)
      ..setUint32(8, 8, Endian.little)
      ..setUint64(16, _lastGeneration, Endian.little);
    view.performCustomOperation(payload);
  }
}

bool _isScalarBoundary(String text, int index) {
  if (index <= 0 || index >= text.length) return true;
  final int previous = text.codeUnitAt(index - 1);
  final int next = text.codeUnitAt(index);
  return !(previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff);
}
