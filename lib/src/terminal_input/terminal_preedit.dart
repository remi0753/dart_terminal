import 'dart:convert';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_unicode.dart';

final class TerminalPreeditCluster {
  const TerminalPreeditCluster({
    required this.text,
    required this.utf16Start,
    required this.utf16Length,
    required this.width,
  });

  final String text;
  final int utf16Start;
  final int utf16Length;
  final int width;
}

/// Immutable bounded preedit text independent of the canonical terminal grid.
final class TerminalPreeditState {
  factory TerminalPreeditState({
    required int generation,
    required String text,
    required int selectionLocation,
    required int selectionLength,
  }) {
    RangeError.checkValueInInterval(
      generation,
      1,
      0x7fffffffffffffff,
      'generation',
    );
    final List<int> encoded = utf8.encode(text);
    if (encoded.length > maximumTextBytes) {
      throw RangeError.range(
        encoded.length,
        0,
        maximumTextBytes,
        'UTF-8 text length',
      );
    }
    _validateUtf16Range(text, selectionLocation, selectionLength);
    return TerminalPreeditState._(
      generation: generation,
      text: text,
      selectionLocation: selectionLocation,
      selectionLength: selectionLength,
      clusters: _clusters(text),
    );
  }

  const TerminalPreeditState._({
    required this.generation,
    required this.text,
    required this.selectionLocation,
    required this.selectionLength,
    required this.clusters,
  });

  static const int maximumTextBytes = 64 * 1024;
  static const int maximumScalarsPerCluster = 64;
  static const TerminalPreeditState empty = TerminalPreeditState._(
    generation: 0,
    text: '',
    selectionLocation: 0,
    selectionLength: 0,
    clusters: <TerminalPreeditCluster>[],
  );

  final int generation;
  final String text;
  final int selectionLocation;
  final int selectionLength;
  final List<TerminalPreeditCluster> clusters;

  bool get isActive => text.isNotEmpty;
  int get selectionEnd => selectionLocation + selectionLength;

  static void _validateUtf16Range(String text, int location, int length) {
    if (location < 0 || length < 0 || location > text.length) {
      throw RangeError('preedit selection is outside UTF-16 text');
    }
    final int end = location + length;
    if (end < location || end > text.length) {
      throw RangeError('preedit selection is outside UTF-16 text');
    }
    bool boundary(int index) =>
        index == 0 ||
        index == text.length ||
        !(_isHighSurrogate(text.codeUnitAt(index - 1)) &&
            _isLowSurrogate(text.codeUnitAt(index)));
    if (!boundary(location) || !boundary(end)) {
      throw ArgumentError('preedit selection splits a surrogate pair');
    }
  }

  static List<TerminalPreeditCluster> _clusters(String text) {
    if (text.isEmpty) return const <TerminalPreeditCluster>[];
    final TerminalGraphemeBreaker breaker = TerminalGraphemeBreaker();
    final List<TerminalPreeditCluster> result = <TerminalPreeditCluster>[];
    final List<int> scalars = <int>[];
    var clusterStart = 0;
    var clusterEnd = 0;

    void flush() {
      if (scalars.isEmpty) return;
      final List<int> visible = <int>[
        for (final int scalar in scalars)
          _isDisplayControl(scalar) ? 0xfffd : scalar,
      ];
      var width = TerminalUnicode.clusterWidth(visible);
      if (width == 0) {
        visible.insert(0, 0x25cc);
        width = 1;
      }
      result.add(
        TerminalPreeditCluster(
          text: String.fromCharCodes(visible),
          utf16Start: clusterStart,
          utf16Length: clusterEnd - clusterStart,
          width: width,
        ),
      );
      scalars.clear();
    }

    var offset = 0;
    while (offset < text.length) {
      final int start = offset;
      final int first = text.codeUnitAt(offset++);
      late final int scalar;
      if (_isHighSurrogate(first) &&
          offset < text.length &&
          _isLowSurrogate(text.codeUnitAt(offset))) {
        scalar =
            0x10000 +
            ((first - 0xd800) << 10) +
            (text.codeUnitAt(offset++) - 0xdc00);
      } else {
        scalar = _isHighSurrogate(first) || _isLowSurrogate(first)
            ? 0xfffd
            : first;
      }
      final bool boundary = breaker.addScalar(scalar);
      if (scalars.isNotEmpty &&
          (boundary || scalars.length == maximumScalarsPerCluster)) {
        flush();
        breaker.reset();
        breaker.addScalar(scalar);
      }
      if (scalars.isEmpty) clusterStart = start;
      scalars.add(scalar);
      clusterEnd = offset;
    }
    flush();
    return List<TerminalPreeditCluster>.unmodifiable(result);
  }

  static bool _isDisplayControl(int scalar) =>
      scalar < 0x20 ||
      scalar == 0x7f ||
      (scalar >= 0x80 && scalar <= 0x9f) ||
      scalar == 0x2028 ||
      scalar == 0x2029;

  static bool _isHighSurrogate(int value) => value >= 0xd800 && value <= 0xdbff;
  static bool _isLowSurrogate(int value) => value >= 0xdc00 && value <= 0xdfff;
}

/// Monotonic owner that ignores stale native composition generations.
final class TerminalPreeditModel {
  TerminalPreeditState _state = TerminalPreeditState.empty;

  TerminalPreeditState get state => _state;

  bool update({
    required int generation,
    required String text,
    required int selectionLocation,
    required int selectionLength,
  }) {
    if (generation <= _state.generation) return false;
    _state = TerminalPreeditState(
      generation: generation,
      text: text,
      selectionLocation: selectionLocation,
      selectionLength: selectionLength,
    );
    return true;
  }

  bool clear({required int generation}) {
    if (generation <= _state.generation) return false;
    RangeError.checkValueInInterval(
      generation,
      1,
      0x7fffffffffffffff,
      'generation',
    );
    _state = TerminalPreeditState._(
      generation: generation,
      text: '',
      selectionLocation: 0,
      selectionLength: 0,
      clusters: const <TerminalPreeditCluster>[],
    );
    return true;
  }
}

final class TerminalPreeditCell {
  const TerminalPreeditCell({
    required this.row,
    required this.column,
    required this.width,
    required this.text,
    required this.isSelected,
  });

  final int row;
  final int column;
  final int width;
  final String text;
  final bool isSelected;
}

final class TerminalPreeditLayout {
  TerminalPreeditLayout._({
    required Iterable<TerminalPreeditCell> cells,
    required this.caretRow,
    required this.caretColumn,
    required this.isClipped,
  }) : cells = List<TerminalPreeditCell>.unmodifiable(cells);

  factory TerminalPreeditLayout.compute({
    required TerminalPreeditState state,
    required int startRow,
    required int startColumn,
    required int rows,
    required int columns,
  }) {
    RangeError.checkValueInInterval(rows, 1, TerminalScreen.maxRows, 'rows');
    RangeError.checkValueInInterval(
      columns,
      1,
      TerminalScreen.maxColumns,
      'columns',
    );
    RangeError.checkValueInInterval(startRow, 0, rows - 1, 'startRow');
    RangeError.checkValueInInterval(startColumn, 0, columns - 1, 'startColumn');
    if (!state.isActive) {
      return TerminalPreeditLayout._(
        cells: const <TerminalPreeditCell>[],
        caretRow: startRow,
        caretColumn: startColumn,
        isClipped: false,
      );
    }

    final List<TerminalPreeditCell> cells = <TerminalPreeditCell>[];
    final int caretOffset = state.selectionEnd;
    var row = startRow;
    var column = startColumn;
    var caretRow = row;
    var caretColumn = column;
    var caretPlaced = false;
    var clipped = false;
    for (final TerminalPreeditCluster cluster in state.clusters) {
      if (column + cluster.width > columns) {
        row++;
        column = 0;
      }
      if (!caretPlaced && caretOffset <= cluster.utf16Start) {
        caretRow = row;
        caretColumn = column;
        caretPlaced = true;
      }
      final int clusterEnd = cluster.utf16Start + cluster.utf16Length;
      final bool selected =
          state.selectionLength > 0 &&
          cluster.utf16Start < state.selectionEnd &&
          clusterEnd > state.selectionLocation;
      if (row < rows) {
        cells.add(
          TerminalPreeditCell(
            row: row,
            column: column,
            width: cluster.width,
            text: cluster.text,
            isSelected: selected,
          ),
        );
      } else {
        clipped = true;
      }
      column += cluster.width;
      if (column >= columns) {
        row++;
        column = 0;
      }
      if (!caretPlaced && caretOffset <= clusterEnd) {
        caretRow = row;
        caretColumn = column;
        caretPlaced = true;
      }
    }
    if (!caretPlaced) {
      caretRow = row;
      caretColumn = column;
    }
    if (caretRow >= rows) {
      caretRow = rows - 1;
      caretColumn = columns - 1;
      clipped = true;
    }
    return TerminalPreeditLayout._(
      cells: cells,
      caretRow: caretRow,
      caretColumn: caretColumn,
      isClipped: clipped,
    );
  }

  final List<TerminalPreeditCell> cells;
  final int caretRow;
  final int caretColumn;
  final bool isClipped;
}
