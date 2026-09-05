import 'dart:convert';

import 'terminal_snapshot.dart';

/// Bounds exact snapshot comparison and its human-readable diagnostic.
final class TerminalSnapshotComparisonLimits {
  const TerminalSnapshotComparisonLimits({
    this.maxSnapshotCharacters = 16 * 1024 * 1024,
    this.maxDiagnosticCharacters = 4096,
    this.contextLines = 2,
    this.maxContextLineCharacters = 512,
  }) : assert(maxSnapshotCharacters > 0),
       assert(maxDiagnosticCharacters >= 128),
       assert(contextLines >= 0 && contextLines <= 8),
       assert(maxContextLineCharacters > 0);

  final int maxSnapshotCharacters;
  final int maxDiagnosticCharacters;
  final int contextLines;
  final int maxContextLineCharacters;
}

/// Result of one exact terminal snapshot comparison.
final class TerminalSnapshotComparison {
  const TerminalSnapshotComparison._match()
    : matches = true,
      firstDifferenceOffset = null,
      firstDifferenceLine = null,
      firstDifferenceColumn = null,
      diagnostic = '';

  const TerminalSnapshotComparison._mismatch({
    required this.firstDifferenceOffset,
    required this.firstDifferenceLine,
    required this.firstDifferenceColumn,
    required this.diagnostic,
  }) : matches = false;

  final bool matches;

  /// Zero-based UTF-16 code-unit offset shared by both inputs up to mismatch.
  final int? firstDifferenceOffset;

  /// One-based line containing the first different UTF-16 code unit.
  final int? firstDifferenceLine;

  /// One-based UTF-16 code-unit column of the first difference.
  final int? firstDifferenceColumn;

  /// Bounded escaped context. Empty when [matches] is true.
  final String diagnostic;

  /// Converts a mismatch into a test-runner-independent typed exception.
  void requireMatch([String description = 'terminal snapshot']) {
    if (!matches) {
      throw TerminalSnapshotMismatchException(
        description: description,
        line: firstDifferenceLine!,
        column: firstDifferenceColumn!,
        diagnostic: diagnostic,
      );
    }
  }
}

/// Contains only bounded mismatch context, never complete snapshot strings.
final class TerminalSnapshotMismatchException implements Exception {
  const TerminalSnapshotMismatchException({
    required this.description,
    required this.line,
    required this.column,
    required this.diagnostic,
  });

  final String description;
  final int line;
  final int column;
  final String diagnostic;

  @override
  String toString() =>
      'TerminalSnapshotMismatchException: $description at line $line, '
      'column $column\n$diagnostic';
}

/// Compares reviewed snapshot text and explains the first exact difference.
final class TerminalSnapshotComparator {
  const TerminalSnapshotComparator({
    this.limits = const TerminalSnapshotComparisonLimits(),
  });

  final TerminalSnapshotComparisonLimits limits;

  TerminalSnapshotComparison compare(String expected, String actual) {
    _validateLimits();
    _checkSnapshotLength('expected snapshot characters', expected.length);
    _checkSnapshotLength('actual snapshot characters', actual.length);

    final int sharedLength = expected.length < actual.length
        ? expected.length
        : actual.length;
    int offset = 0;
    int line = 1;
    int column = 1;
    while (offset < sharedLength) {
      final int expectedUnit = expected.codeUnitAt(offset);
      final int actualUnit = actual.codeUnitAt(offset);
      if (expectedUnit != actualUnit) {
        break;
      }
      offset++;
      if (expectedUnit == 0x0a) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    if (offset == expected.length && offset == actual.length) {
      return const TerminalSnapshotComparison._match();
    }

    return TerminalSnapshotComparison._mismatch(
      firstDifferenceOffset: offset,
      firstDifferenceLine: line,
      firstDifferenceColumn: column,
      diagnostic: _diagnostic(
        expected,
        actual,
        offset: offset,
        line: line,
        column: column,
      ),
    );
  }

  void _validateLimits() {
    if (limits.maxSnapshotCharacters <= 0) {
      throw ArgumentError.value(
        limits.maxSnapshotCharacters,
        'limits.maxSnapshotCharacters',
      );
    }
    if (limits.maxDiagnosticCharacters < 128) {
      throw ArgumentError.value(
        limits.maxDiagnosticCharacters,
        'limits.maxDiagnosticCharacters',
        'must be at least 128',
      );
    }
    if (limits.contextLines < 0 || limits.contextLines > 8) {
      throw RangeError.range(limits.contextLines, 0, 8, 'limits.contextLines');
    }
    if (limits.maxContextLineCharacters <= 0) {
      throw ArgumentError.value(
        limits.maxContextLineCharacters,
        'limits.maxContextLineCharacters',
      );
    }
  }

  void _checkSnapshotLength(String resource, int length) {
    if (length > limits.maxSnapshotCharacters) {
      throw TerminalSnapshotLimitException(
        resource: resource,
        actual: length,
        limit: limits.maxSnapshotCharacters,
      );
    }
  }

  String _diagnostic(
    String expected,
    String actual, {
    required int offset,
    required int line,
    required int column,
  }) {
    final int firstLine = line > limits.contextLines
        ? line - limits.contextLines
        : 1;
    final int lastLine = line + limits.contextLines;
    final StringBuffer result = StringBuffer()
      ..writeln(
        'terminal snapshot mismatch at line $line, column $column '
        '(UTF-16 code units)',
      )
      ..writeln('expected next: ${_nextCodeUnit(expected, offset)}')
      ..writeln('actual next:   ${_nextCodeUnit(actual, offset)}')
      ..writeln('expected context:');
    _writeContext(result, expected, firstLine, lastLine, line);
    result.writeln('actual context:');
    _writeContext(result, actual, firstLine, lastLine, line);
    return _truncateDiagnostic(result.toString());
  }

  void _writeContext(
    StringBuffer result,
    String snapshot,
    int firstLine,
    int lastLine,
    int mismatchLine,
  ) {
    final List<_SnapshotContextLine> lines = _contextLines(
      snapshot,
      firstLine,
      lastLine,
    );
    if (lines.isEmpty) {
      result.writeln('> $mismatchLine | <end-of-snapshot>');
      return;
    }
    for (final _SnapshotContextLine line in lines) {
      final String marker = line.number == mismatchLine ? '>' : ' ';
      result.writeln(
        '$marker ${line.number} | ${_escapeContextLine(line.value)}',
      );
    }
    if (mismatchLine > lines.last.number) {
      result.writeln('> $mismatchLine | <end-of-snapshot>');
    }
  }

  List<_SnapshotContextLine> _contextLines(
    String snapshot,
    int firstLine,
    int lastLine,
  ) {
    final List<_SnapshotContextLine> result = <_SnapshotContextLine>[];
    int line = 1;
    int start = 0;
    for (int offset = 0; offset <= snapshot.length; offset++) {
      if (offset != snapshot.length && snapshot.codeUnitAt(offset) != 0x0a) {
        continue;
      }
      if (line >= firstLine && line <= lastLine) {
        result.add(
          _SnapshotContextLine(line, snapshot.substring(start, offset)),
        );
      }
      if (line >= lastLine || offset == snapshot.length) {
        break;
      }
      line++;
      start = offset + 1;
    }
    return result;
  }

  String _escapeContextLine(String line) {
    final bool truncated = line.length > limits.maxContextLineCharacters;
    final String visible = truncated
        ? line.substring(0, limits.maxContextLineCharacters)
        : line;
    final String suffix = truncated
        ? ' … (${line.length - visible.length} more code units)'
        : '';
    return '${jsonEncode(visible)}$suffix';
  }

  static String _nextCodeUnit(String value, int offset) {
    if (offset >= value.length) {
      return '<end-of-snapshot>';
    }
    final int unit = value.codeUnitAt(offset);
    return '0x${unit.toRadixString(16).padLeft(4, '0')} '
        '${jsonEncode(String.fromCharCode(unit))}';
  }

  String _truncateDiagnostic(String diagnostic) {
    if (diagnostic.length <= limits.maxDiagnosticCharacters) {
      return diagnostic;
    }
    const String marker = '\n… diagnostic truncated\n';
    int end = limits.maxDiagnosticCharacters - marker.length;
    if (end > 0 && _isHighSurrogate(diagnostic.codeUnitAt(end - 1))) {
      end--;
    }
    return '${diagnostic.substring(0, end)}$marker';
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}

final class _SnapshotContextLine {
  const _SnapshotContextLine(this.number, this.value);

  final int number;
  final String value;
}
