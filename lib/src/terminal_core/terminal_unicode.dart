import 'dart:typed_data';

import 'generated/unicode_tables.g.dart';

/// Unicode 17 properties and the deterministic terminal column-width policy.
abstract final class TerminalUnicode {
  static const String version = terminalUnicodeVersion;

  /// Returns zero for controls and extending/format components, two for
  /// East-Asian Wide/Fullwidth and emoji-presentation scalars, and one for all
  /// other scalars. East-Asian Ambiguous scalars are intentionally narrow.
  static int scalarWidth(int scalar) {
    validateScalar(scalar);
    final int graphemeBreak = graphemeBreakProperty(scalar);
    if (graphemeBreak == _GraphemeBreak.cr ||
        graphemeBreak == _GraphemeBreak.lf ||
        graphemeBreak == _GraphemeBreak.control ||
        graphemeBreak == _GraphemeBreak.extend ||
        graphemeBreak == _GraphemeBreak.zwj ||
        graphemeBreak == _GraphemeBreak.prepend) {
      return 0;
    }
    if (_containsPairRange(terminalUnicodeWideRanges, scalar) ||
        isEmojiPresentation(scalar)) {
      return 2;
    }
    return 1;
  }

  /// Returns a terminal width for one complete extended grapheme cluster.
  static int clusterWidth(List<int> scalars) {
    if (scalars.isEmpty) {
      throw ArgumentError.value(scalars, 'scalars', 'must not be empty');
    }
    var width = 0;
    var regionalIndicators = 0;
    var hasVariationSelector16 = false;
    var hasKeycap = false;
    for (final int scalar in scalars) {
      validateScalar(scalar);
      if (scalar == 0xfe0f) {
        hasVariationSelector16 = true;
      } else if (scalar == 0x20e3) {
        hasKeycap = true;
      }
      if (graphemeBreakProperty(scalar) == _GraphemeBreak.regionalIndicator) {
        regionalIndicators++;
      }
      if (isEmojiPresentation(scalar)) {
        width = 2;
      } else if (width < 2) {
        final int scalarColumns = scalarWidth(scalar);
        if (scalarColumns > width) {
          width = scalarColumns;
        }
      }
    }
    if (hasVariationSelector16 || hasKeycap || regionalIndicators >= 2) {
      return 2;
    }
    return width;
  }

  static bool isExtendedPictographic(int scalar) {
    validateScalar(scalar);
    return _containsPairRange(terminalExtendedPictographicRanges, scalar);
  }

  static bool isEmojiPresentation(int scalar) {
    validateScalar(scalar);
    return _containsPairRange(terminalEmojiPresentationRanges, scalar);
  }

  static int graphemeBreakProperty(int scalar) {
    validateScalar(scalar);
    return _valueInTripleRanges(terminalGraphemeBreakRanges, scalar);
  }

  static int indicConjunctProperty(int scalar) {
    validateScalar(scalar);
    return _valueInTripleRanges(terminalIndicConjunctRanges, scalar);
  }

  static void validateScalar(int scalar) {
    if (scalar < 0 ||
        scalar > 0x10ffff ||
        (scalar >= 0xd800 && scalar <= 0xdfff)) {
      throw ArgumentError.value(scalar, 'scalar', 'is not a Unicode scalar');
    }
  }
}

/// Incremental implementation of Unicode 17 extended grapheme boundaries.
///
/// [addScalar] returns whether a boundary occurs immediately before the added
/// scalar. The first scalar after construction or [reset] always starts a new
/// cluster. Invalid input is rejected without changing breaker state.
final class TerminalGraphemeBreaker {
  int _previous = _GraphemeBreak.other;
  int _regionalIndicatorCount = 0;
  int _emojiState = 0;
  int _indicState = 0;
  bool _empty = true;

  void reset() {
    _previous = _GraphemeBreak.other;
    _regionalIndicatorCount = 0;
    _emojiState = 0;
    _indicState = 0;
    _empty = true;
  }

  bool addScalar(int scalar) {
    TerminalUnicode.validateScalar(scalar);
    final int current = TerminalUnicode.graphemeBreakProperty(scalar);
    final int currentIndic = TerminalUnicode.indicConjunctProperty(scalar);
    final bool currentExtendedPictographic =
        TerminalUnicode.isExtendedPictographic(scalar);
    final bool boundary =
        _empty ||
        _hasBoundary(current, currentIndic, currentExtendedPictographic);
    if (boundary) {
      _regionalIndicatorCount = 0;
      _emojiState = 0;
      _indicState = 0;
    }
    _updateRegionalIndicators(current);
    _updateEmoji(current, currentExtendedPictographic);
    _updateIndic(currentIndic);
    _previous = current;
    _empty = false;
    return boundary;
  }

  bool _hasBoundary(
    int current,
    int currentIndic,
    bool currentExtendedPictographic,
  ) {
    if (_previous == _GraphemeBreak.cr && current == _GraphemeBreak.lf) {
      return false;
    }
    if (_isControl(_previous) || _isControl(current)) {
      return true;
    }
    if (_previous == _GraphemeBreak.l &&
        (current == _GraphemeBreak.l ||
            current == _GraphemeBreak.v ||
            current == _GraphemeBreak.lv ||
            current == _GraphemeBreak.lvt)) {
      return false;
    }
    if ((_previous == _GraphemeBreak.lv || _previous == _GraphemeBreak.v) &&
        (current == _GraphemeBreak.v || current == _GraphemeBreak.t)) {
      return false;
    }
    if ((_previous == _GraphemeBreak.lvt || _previous == _GraphemeBreak.t) &&
        current == _GraphemeBreak.t) {
      return false;
    }
    if (current == _GraphemeBreak.extend ||
        current == _GraphemeBreak.zwj ||
        current == _GraphemeBreak.spacingMark) {
      return false;
    }
    if (_previous == _GraphemeBreak.prepend) {
      return false;
    }
    if (_indicState == 2 && currentIndic == _IndicConjunct.consonant) {
      return false;
    }
    if (_emojiState == 2 && currentExtendedPictographic) {
      return false;
    }
    if (_previous == _GraphemeBreak.regionalIndicator &&
        current == _GraphemeBreak.regionalIndicator &&
        _regionalIndicatorCount.isOdd) {
      return false;
    }
    return true;
  }

  void _updateRegionalIndicators(int current) {
    if (current == _GraphemeBreak.regionalIndicator) {
      _regionalIndicatorCount++;
    } else {
      _regionalIndicatorCount = 0;
    }
  }

  void _updateEmoji(int current, bool extendedPictographic) {
    if (extendedPictographic) {
      _emojiState = 1;
    } else if (current == _GraphemeBreak.extend && _emojiState == 1) {
      return;
    } else if (current == _GraphemeBreak.zwj && _emojiState == 1) {
      _emojiState = 2;
    } else {
      _emojiState = 0;
    }
  }

  void _updateIndic(int current) {
    if (current == _IndicConjunct.consonant) {
      _indicState = 1;
    } else if (current == _IndicConjunct.linker && _indicState != 0) {
      _indicState = 2;
    } else if (current != _IndicConjunct.extend || _indicState == 0) {
      _indicState = 0;
    }
  }
}

/// Bounded immutable grapheme definitions addressed by stable 16-bit IDs.
final class TerminalGraphemeTable {
  factory TerminalGraphemeTable({
    int capacity = defaultCapacity,
    int maximumScalarCount = defaultMaximumScalarCount,
    int maximumClusterLength = defaultMaximumClusterLength,
  }) {
    if (capacity <= 0 || capacity > maximumGraphemeId) {
      throw RangeError.range(capacity, 1, maximumGraphemeId, 'capacity');
    }
    if (maximumScalarCount <= 0) {
      throw RangeError.value(
        maximumScalarCount,
        'maximumScalarCount',
        'must be positive',
      );
    }
    if (maximumClusterLength <= 0 ||
        maximumClusterLength > maximumScalarCount) {
      throw RangeError.range(
        maximumClusterLength,
        1,
        maximumScalarCount,
        'maximumClusterLength',
      );
    }
    return TerminalGraphemeTable._(
      capacity,
      maximumScalarCount,
      maximumClusterLength,
    );
  }

  TerminalGraphemeTable._(
    this.capacity,
    this.maximumScalarCount,
    this.maximumClusterLength,
  ) : _scalarsById = List<Uint32List?>.filled(capacity + 1, null),
      _widthsById = Uint8List(capacity + 1);

  static const int defaultCapacity = 4096;
  static const int maximumGraphemeId = 65534;
  static const int defaultMaximumScalarCount = 65536;
  static const int defaultMaximumClusterLength = 64;

  final int capacity;
  final int maximumScalarCount;
  final int maximumClusterLength;
  final List<Uint32List?> _scalarsById;
  final Uint8List _widthsById;
  final Map<String, int> _idsByScalars = <String, int>{};
  int _definitionCount = 0;
  int _scalarCount = 0;
  int _generation = 1;

  int get definitionCount => _definitionCount;
  int get scalarCount => _scalarCount;
  int get generation => _generation;

  int intern(List<int> scalars) {
    final int? id = tryIntern(scalars);
    if (id == null) {
      throw StateError('terminal grapheme table capacity exhausted');
    }
    return id;
  }

  /// Returns null when either bounded resource limit would be exceeded.
  /// Invalid scalar sequences remain programmer errors and are thrown.
  int? tryIntern(List<int> scalars) {
    if (scalars.isEmpty || scalars.length > maximumClusterLength) {
      throw RangeError.range(
        scalars.length,
        1,
        maximumClusterLength,
        'scalars.length',
      );
    }
    for (final int scalar in scalars) {
      TerminalUnicode.validateScalar(scalar);
    }
    final String key = String.fromCharCodes(scalars);
    final int? existing = _idsByScalars[key];
    if (existing != null) {
      return existing;
    }
    if (_definitionCount >= capacity ||
        _scalarCount + scalars.length > maximumScalarCount) {
      return null;
    }
    final int id = ++_definitionCount;
    final Uint32List stored = Uint32List.fromList(scalars);
    _scalarsById[id] = stored;
    _widthsById[id] = TerminalUnicode.clusterWidth(stored);
    _idsByScalars[key] = id;
    _scalarCount += stored.length;
    _generation++;
    return id;
  }

  Uint32List scalarsAt(int id) {
    RangeError.checkValueInInterval(id, 1, _definitionCount, 'id');
    return Uint32List.fromList(_scalarsById[id]!);
  }

  int widthAt(int id) {
    RangeError.checkValueInInterval(id, 1, _definitionCount, 'id');
    return _widthsById[id];
  }
}

abstract final class _GraphemeBreak {
  static const int other = 0;
  static const int cr = 1;
  static const int lf = 2;
  static const int control = 3;
  static const int extend = 4;
  static const int zwj = 5;
  static const int regionalIndicator = 6;
  static const int prepend = 7;
  static const int spacingMark = 8;
  static const int l = 9;
  static const int v = 10;
  static const int t = 11;
  static const int lv = 12;
  static const int lvt = 13;
}

abstract final class _IndicConjunct {
  static const int consonant = 1;
  static const int extend = 2;
  static const int linker = 3;
}

bool _isControl(int property) =>
    property == _GraphemeBreak.cr ||
    property == _GraphemeBreak.lf ||
    property == _GraphemeBreak.control;

bool _containsPairRange(List<int> ranges, int scalar) {
  var low = 0;
  var high = ranges.length ~/ 2 - 1;
  while (low <= high) {
    final int middle = (low + high) >> 1;
    final int offset = middle * 2;
    if (scalar < ranges[offset]) {
      high = middle - 1;
    } else if (scalar >= ranges[offset + 1]) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

int _valueInTripleRanges(List<int> ranges, int scalar) {
  var low = 0;
  var high = ranges.length ~/ 3 - 1;
  while (low <= high) {
    final int middle = (low + high) >> 1;
    final int offset = middle * 3;
    if (scalar < ranges[offset]) {
      high = middle - 1;
    } else if (scalar >= ranges[offset + 1]) {
      low = middle + 1;
    } else {
      return ranges[offset + 2];
    }
  }
  return 0;
}
