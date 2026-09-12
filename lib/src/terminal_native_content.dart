import 'terminal_core/terminal_screen_set.dart';
import 'terminal_input/terminal_paste.dart';

/// Why a terminal word cannot be offered to native Quick Look.
enum TerminalWordLookupDisposition {
  available,
  outsideViewport,
  unavailable,
  whitespace,
  boundaryLimited,
  tooLarge,
  stale,
}

/// One bounded word and its stable terminal geometry.
final class TerminalWordCandidate {
  const TerminalWordCandidate._({
    required this.text,
    required this.range,
    required this.viewportGeneration,
    required this.pointerRow,
    required this.pointerColumn,
    required this.baselineRow,
    required this.baselineColumn,
  });

  final String text;
  final TerminalSelectionRange range;
  final int viewportGeneration;
  final int pointerRow;
  final int pointerColumn;
  final int baselineRow;
  final int baselineColumn;
}

/// Typed result that never substitutes a partial or stale Quick Look word.
final class TerminalWordLookupResult {
  const TerminalWordLookupResult._(this.disposition, this.candidate);

  const TerminalWordLookupResult.rejected(
    TerminalWordLookupDisposition disposition,
  ) : this._(disposition, null);

  const TerminalWordLookupResult.available(TerminalWordCandidate candidate)
    : this._(TerminalWordLookupDisposition.available, candidate);

  final TerminalWordLookupDisposition disposition;
  final TerminalWordCandidate? candidate;

  bool get isAvailable =>
      disposition == TerminalWordLookupDisposition.available;
}

/// Resolves native pointer/caret coordinates through the canonical viewport.
abstract final class TerminalWordLookup {
  static const int defaultMaximumScalars = 256;
  static const int maximumScalars = 4096;

  static TerminalWordLookupResult atCell(
    TerminalViewport viewport,
    int row,
    int column, {
    int maxWordScanCells = TerminalSelectionRange.defaultMaxWordScanCells,
    int maxScalars = defaultMaximumScalars,
  }) {
    RangeError.checkValueInInterval(
      maxWordScanCells,
      1,
      TerminalSelectionRange.maximumWordScanCells,
      'maxWordScanCells',
    );
    RangeError.checkValueInInterval(
      maxScalars,
      1,
      maximumScalars,
      'maxScalars',
    );
    if (row < 0 ||
        row >= viewport.rows ||
        column < 0 ||
        column >= viewport.columns) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.outsideViewport,
      );
    }
    final int sourceColumns = viewport.columnsAt(row);
    if (column >= sourceColumns) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.outsideViewport,
      );
    }
    final int generation = viewport.generation;
    final TerminalLogicalAnchor focus = viewport.anchorAt(row, column);
    final TerminalSelectionRange? range = viewport.selectionRange(
      focus,
      focus,
      unit: TerminalSelectionUnit.word,
      maxWordScanCells: maxWordScanCells,
    );
    if (range == null) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.unavailable,
      );
    }
    if (range.isBoundaryLimited) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.boundaryLimited,
      );
    }
    final TerminalSelectionText? selected = viewport.extractSelection(
      range,
      maxScalars: maxScalars,
    );
    if (selected == null) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.unavailable,
      );
    }
    if (selected.isTruncated) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.tooLarge,
      );
    }
    if (selected.text.isEmpty || _isOnlyWhitespace(selected.text)) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.whitespace,
      );
    }
    final TerminalViewportPosition? baseline = viewport.positionOf(range.start);
    if (baseline == null || viewport.generation != generation) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    return TerminalWordLookupResult.available(
      TerminalWordCandidate._(
        text: selected.text,
        range: range,
        viewportGeneration: generation,
        pointerRow: row,
        pointerColumn: column,
        baselineRow: baseline.row,
        baselineColumn: baseline.column,
      ),
    );
  }

  static TerminalWordLookupResult revalidate(
    TerminalViewport viewport,
    TerminalWordCandidate candidate,
  ) {
    if (viewport.generation != candidate.viewportGeneration ||
        !viewport.isSelectionAvailable(candidate.range)) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    final TerminalSelectionText? selected = viewport.extractSelection(
      candidate.range,
      maxScalars: maximumScalars,
    );
    if (selected == null ||
        selected.isTruncated ||
        selected.text != candidate.text) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    return TerminalWordLookupResult.available(candidate);
  }
}

enum TerminalExternalContentKind { text, filePaths }

enum TerminalExternalTextSource { service, drop }

enum TerminalExternalContentDisposition {
  admitted,
  empty,
  invalidPath,
  tooManyItems,
  tooLarge,
}

/// External text admitted for later paste planning; it is not a PTY write.
final class TerminalExternalContent {
  const TerminalExternalContent._({
    required this.kind,
    required this.textSource,
    required this.text,
    required this.utf8Bytes,
    required this.itemCount,
  });

  final TerminalExternalContentKind kind;
  final TerminalExternalTextSource textSource;
  final String text;
  final int utf8Bytes;
  final int itemCount;
}

final class TerminalExternalContentResult {
  const TerminalExternalContentResult._(this.disposition, this.content);

  const TerminalExternalContentResult.rejected(
    TerminalExternalContentDisposition disposition,
  ) : this._(disposition, null);

  const TerminalExternalContentResult.admitted(TerminalExternalContent content)
    : this._(TerminalExternalContentDisposition.admitted, content);

  final TerminalExternalContentDisposition disposition;
  final TerminalExternalContent? content;

  bool get isAdmitted =>
      disposition == TerminalExternalContentDisposition.admitted;
}

/// Bounded admission shared by Services and the terminal drop destination.
abstract final class TerminalExternalContentAdmission {
  static const int maximumUtf8Bytes =
      TerminalPasteCodec.maximumEncodedBodyBytes;
  static const int maximumFilePathUtf8Bytes = 1024 * 1024;
  static const int maximumFilePaths = 256;

  static TerminalExternalContentResult text(
    String value, {
    required TerminalExternalTextSource source,
    int maxUtf8Bytes = maximumUtf8Bytes,
  }) {
    _checkMaximum(maxUtf8Bytes);
    if (value.isEmpty) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.empty,
      );
    }
    final int? bytes = _boundedUtf8Length(value, maxUtf8Bytes);
    if (bytes == null) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.tooLarge,
      );
    }
    return TerminalExternalContentResult.admitted(
      TerminalExternalContent._(
        kind: TerminalExternalContentKind.text,
        textSource: source,
        text: value,
        utf8Bytes: bytes,
        itemCount: 1,
      ),
    );
  }

  static TerminalExternalContentResult filePaths(
    Iterable<String> values, {
    int maxUtf8Bytes = maximumUtf8Bytes,
    int maxFilePathUtf8Bytes = maximumFilePathUtf8Bytes,
    int maxFilePaths = maximumFilePaths,
  }) {
    _checkMaximum(maxUtf8Bytes);
    RangeError.checkValueInInterval(
      maxFilePathUtf8Bytes,
      1,
      maximumFilePathUtf8Bytes,
      'maxFilePathUtf8Bytes',
    );
    RangeError.checkValueInInterval(
      maxFilePaths,
      1,
      maximumFilePaths,
      'maxFilePaths',
    );
    final List<String> admitted = <String>[];
    var encodedBytes = 0;
    for (final String path in values) {
      if (admitted.length == maxFilePaths) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooManyItems,
        );
      }
      if (!_isSafeAbsolutePath(path)) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.invalidPath,
        );
      }
      final int? pathBytes = _boundedUtf8Length(path, maxFilePathUtf8Bytes);
      if (pathBytes == null) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooLarge,
        );
      }
      final int quoteCount = "'".allMatches(path).length;
      final int quotedBytes = pathBytes + 2 + quoteCount * 3 + 1;
      if (encodedBytes + quotedBytes > maxUtf8Bytes) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooLarge,
        );
      }
      admitted.add(path);
      encodedBytes += quotedBytes;
    }
    if (admitted.isEmpty) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.empty,
      );
    }
    final StringBuffer serialized = StringBuffer();
    for (final String path in admitted) {
      serialized
        ..write("'")
        ..write(path.replaceAll("'", "'\\''"))
        ..write("' ");
    }
    return TerminalExternalContentResult.admitted(
      TerminalExternalContent._(
        kind: TerminalExternalContentKind.filePaths,
        textSource: TerminalExternalTextSource.drop,
        text: serialized.toString(),
        utf8Bytes: encodedBytes,
        itemCount: admitted.length,
      ),
    );
  }

  static void _checkMaximum(int maximum) {
    RangeError.checkValueInInterval(
      maximum,
      1,
      maximumUtf8Bytes,
      'maxUtf8Bytes',
    );
  }
}

bool _isOnlyWhitespace(String value) {
  for (final int scalar in value.runes) {
    if (!(scalar >= 0x09 && scalar <= 0x0d ||
        scalar == 0x20 ||
        scalar == 0x85 ||
        scalar == 0xa0 ||
        scalar == 0x1680 ||
        scalar >= 0x2000 && scalar <= 0x200a ||
        scalar == 0x2028 ||
        scalar == 0x2029 ||
        scalar == 0x202f ||
        scalar == 0x205f ||
        scalar == 0x3000)) {
      return false;
    }
  }
  return true;
}

bool _isSafeAbsolutePath(String path) {
  if (path.isEmpty || !path.startsWith('/')) return false;
  for (var index = 0; index < path.length; index++) {
    final int unit = path.codeUnitAt(index);
    if (unit < 0x20 || unit == 0x7f) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= path.length) return false;
      final int second = path.codeUnitAt(index);
      if (second < 0xdc00 || second > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

int? _boundedUtf8Length(String value, int maximum) {
  var bytes = 0;
  for (var index = 0; index < value.length; index++) {
    final int first = value.codeUnitAt(index);
    if (first <= 0x7f) {
      bytes++;
    } else if (first <= 0x7ff) {
      bytes += 2;
    } else if (first >= 0xd800 && first <= 0xdbff) {
      if (index + 1 < value.length) {
        final int second = value.codeUnitAt(index + 1);
        if (second >= 0xdc00 && second <= 0xdfff) {
          index++;
          bytes += 4;
        } else {
          bytes += 3;
        }
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
    if (bytes > maximum) return null;
  }
  return bytes;
}
