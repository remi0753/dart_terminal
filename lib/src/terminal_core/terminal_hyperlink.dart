import 'dart:convert';

/// Immutable OSC 8 target stored behind one stable 16-bit cell ID.
final class TerminalHyperlinkDefinition {
  const TerminalHyperlinkDefinition({
    required this.id,
    required this.uri,
    required this.explicitId,
    required this.utf8Bytes,
  });

  final int id;
  final String uri;
  final String? explicitId;
  final int utf8Bytes;
}

/// One hyperlink resolved against an exact visible viewport generation.
final class TerminalHyperlinkHit {
  factory TerminalHyperlinkHit({
    required int viewportGeneration,
    required int row,
    required int column,
    required int pointerColumn,
    required int cellWidth,
    required TerminalHyperlinkDefinition definition,
  }) {
    if (viewportGeneration <= 0) {
      throw RangeError.value(
        viewportGeneration,
        'viewportGeneration',
        'must be positive',
      );
    }
    if (row < 0 || column < 0 || pointerColumn < 0) {
      throw RangeError('hyperlink hit coordinates must be non-negative');
    }
    if (cellWidth != 1 && cellWidth != 2) {
      throw RangeError.value(cellWidth, 'cellWidth', 'must be one or two');
    }
    return TerminalHyperlinkHit._(
      viewportGeneration,
      row,
      column,
      pointerColumn,
      cellWidth,
      definition,
    );
  }

  const TerminalHyperlinkHit._(
    this.viewportGeneration,
    this.row,
    this.column,
    this.pointerColumn,
    this.cellWidth,
    this.definition,
  );

  final int viewportGeneration;
  final int row;
  final int column;
  final int pointerColumn;
  final int cellWidth;
  final TerminalHyperlinkDefinition definition;

  int get hyperlinkId => definition.id;
  String get uri => definition.uri;

  @override
  bool operator ==(Object other) =>
      other is TerminalHyperlinkHit &&
      other.viewportGeneration == viewportGeneration &&
      other.row == row &&
      other.column == column &&
      other.pointerColumn == pointerColumn &&
      other.cellWidth == cellWidth &&
      other.definition.id == definition.id &&
      other.definition.uri == definition.uri;

  @override
  int get hashCode => Object.hash(
    viewportGeneration,
    row,
    column,
    pointerColumn,
    cellWidth,
    definition.id,
    definition.uri,
  );
}

/// Session-owned bounded OSC 8 definition table.
///
/// Definitions are never reused: scrollback and reflow may retain a cell ID
/// long after the producer closes its current hyperlink. ID zero remains the
/// canonical no-link value used by the packed cell layout.
final class TerminalHyperlinkTable {
  factory TerminalHyperlinkTable({
    int capacity = defaultCapacity,
    int maximumUtf8Bytes = defaultMaximumUtf8Bytes,
    int maximumDefinitionUtf8Bytes = defaultMaximumDefinitionUtf8Bytes,
  }) {
    if (capacity <= 0 || capacity > maximumHyperlinkId) {
      throw RangeError.range(capacity, 1, maximumHyperlinkId, 'capacity');
    }
    if (maximumUtf8Bytes <= 0) {
      throw RangeError.value(
        maximumUtf8Bytes,
        'maximumUtf8Bytes',
        'must be positive',
      );
    }
    if (maximumDefinitionUtf8Bytes <= 0 ||
        maximumDefinitionUtf8Bytes > maximumUtf8Bytes) {
      throw RangeError.range(
        maximumDefinitionUtf8Bytes,
        1,
        maximumUtf8Bytes,
        'maximumDefinitionUtf8Bytes',
      );
    }
    return TerminalHyperlinkTable._(
      capacity,
      maximumUtf8Bytes,
      maximumDefinitionUtf8Bytes,
    );
  }

  TerminalHyperlinkTable._(
    this.capacity,
    this.maximumUtf8Bytes,
    this.maximumDefinitionUtf8Bytes,
  ) : _definitions = List<TerminalHyperlinkDefinition?>.filled(
        capacity + 1,
        null,
      );

  static const int defaultCapacity = 4096;
  static const int maximumHyperlinkId = 65534;
  static const int defaultMaximumUtf8Bytes = 1024 * 1024;
  static const int defaultMaximumDefinitionUtf8Bytes = 4096;
  static const int maximumExplicitIdUtf8Bytes = 1024;

  final int capacity;
  final int maximumUtf8Bytes;
  final int maximumDefinitionUtf8Bytes;
  final List<TerminalHyperlinkDefinition?> _definitions;
  final Map<_TerminalExplicitHyperlinkKey, int> _explicitIds =
      <_TerminalExplicitHyperlinkKey, int>{};

  int _definitionCount = 0;
  int _utf8Bytes = 0;
  int _generation = 1;
  int _refusalCount = 0;

  int get definitionCount => _definitionCount;
  int get utf8Bytes => _utf8Bytes;
  int get generation => _generation;
  int get refusalCount => _refusalCount;

  /// Returns a stable ID, or null without retaining partial input on refusal.
  ///
  /// An explicit producer ID groups equal `(id, URI)` openings. Without an
  /// explicit ID, each open operation intentionally receives a new identity.
  int? tryIntern({required String uri, String? explicitId}) {
    if (uri.isEmpty ||
        _containsUnsafeUriScalar(uri) ||
        (explicitId != null && !_validExplicitId(explicitId))) {
      _refusalCount++;
      return null;
    }
    final int uriBytes = utf8.encode(uri).length;
    final int explicitIdBytes = explicitId == null
        ? 0
        : utf8.encode(explicitId).length;
    final int definitionBytes = uriBytes + explicitIdBytes;
    if (definitionBytes > maximumDefinitionUtf8Bytes ||
        explicitIdBytes > maximumExplicitIdUtf8Bytes) {
      _refusalCount++;
      return null;
    }

    final _TerminalExplicitHyperlinkKey? key = explicitId == null
        ? null
        : _TerminalExplicitHyperlinkKey(explicitId, uri);
    final int? existing = key == null ? null : _explicitIds[key];
    if (existing != null) {
      return existing;
    }
    if (_definitionCount >= capacity ||
        definitionBytes > maximumUtf8Bytes - _utf8Bytes) {
      _refusalCount++;
      return null;
    }

    final int id = ++_definitionCount;
    _definitions[id] = TerminalHyperlinkDefinition(
      id: id,
      uri: uri,
      explicitId: explicitId,
      utf8Bytes: definitionBytes,
    );
    if (key != null) {
      _explicitIds[key] = id;
    }
    _utf8Bytes += definitionBytes;
    _generation++;
    return id;
  }

  TerminalHyperlinkDefinition definitionAt(int id) {
    RangeError.checkValueInInterval(id, 1, _definitionCount, 'id');
    return _definitions[id]!;
  }

  String uriAt(int id) => definitionAt(id).uri;

  static bool _validExplicitId(String value) {
    if (value.isEmpty) return false;
    for (final int scalar in value.runes) {
      if (scalar < 0x21 || scalar > 0x7e || scalar == 0x3a) {
        return false;
      }
    }
    return true;
  }

  static bool _containsUnsafeUriScalar(String value) {
    for (final int scalar in value.runes) {
      if (scalar <= 0x20 ||
          (scalar >= 0x7f && scalar <= 0x9f) ||
          scalar == 0x00a0 ||
          scalar == 0x1680 ||
          (scalar >= 0x2000 && scalar <= 0x200f) ||
          (scalar >= 0x2028 && scalar <= 0x202e) ||
          (scalar >= 0x205f && scalar <= 0x206f) ||
          scalar == 0x3000 ||
          scalar == 0xfeff) {
        return true;
      }
    }
    return false;
  }
}

final class _TerminalExplicitHyperlinkKey {
  const _TerminalExplicitHyperlinkKey(this.explicitId, this.uri);

  final String explicitId;
  final String uri;

  @override
  bool operator ==(Object other) =>
      other is _TerminalExplicitHyperlinkKey &&
      other.explicitId == explicitId &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(explicitId, uri);
}
