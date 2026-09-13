import 'dart:typed_data';

enum TerminalUnderlineStyle { none, single, double, curly, dotted, dashed }

/// Packed attributes stored behind a stable [TerminalStyleTable] ID.
abstract final class TerminalStyleAttributes {
  static const int bold = 1 << 0;
  static const int faint = 1 << 1;
  static const int italic = 1 << 2;
  static const int underlineShift = 3;
  static const int underlineMask = 0x07 << underlineShift;
  static const int blink = 1 << 6;
  static const int inverse = 1 << 7;
  static const int conceal = 1 << 8;
  static const int strike = 1 << 9;
  static const int overline = 1 << 10;
  static const int knownMask =
      bold |
      faint |
      italic |
      underlineMask |
      blink |
      inverse |
      conceal |
      strike |
      overline;

  static bool has(int attributes, int flag) => attributes & flag != 0;

  static TerminalUnderlineStyle underline(int attributes) {
    validate(attributes);
    return TerminalUnderlineStyle.values[(attributes & underlineMask) >>
        underlineShift];
  }

  static int withUnderline(int attributes, TerminalUnderlineStyle underline) {
    validate(attributes);
    return (attributes & ~underlineMask) | (underline.index << underlineShift);
  }

  static void validate(int attributes) {
    if (attributes < 0 || attributes & ~knownMask != 0) {
      throw ArgumentError.value(
        attributes,
        'attributes',
        'contains unknown terminal style bits',
      );
    }
    final int underline = (attributes & underlineMask) >> underlineShift;
    if (underline >= TerminalUnderlineStyle.values.length) {
      throw ArgumentError.value(
        attributes,
        'attributes',
        'contains an invalid underline style',
      );
    }
  }
}

/// Bounded immutable style definitions addressed by stable 16-bit IDs.
final class TerminalStyleTable {
  factory TerminalStyleTable({int capacity = defaultCapacity}) {
    if (capacity <= 0 || capacity > maxStyleId) {
      throw RangeError.range(capacity, 1, maxStyleId, 'capacity');
    }
    return TerminalStyleTable._(capacity);
  }

  TerminalStyleTable._(this.capacity)
    : _attributesById = Uint16List(capacity + 1),
      _underlineColorsById = Uint32List(capacity + 1);

  static const int defaultCapacity = 4096;
  static const int maxStyleId = 65534;

  final int capacity;
  final Uint16List _attributesById;
  final Uint32List _underlineColorsById;
  final Map<(int, int), int> _idsByDefinition = <(int, int), int>{};
  int _definitionCount = 0;
  int _generation = 1;

  int get definitionCount => _definitionCount;
  int get generation => _generation;

  int intern(int attributes, {int underlineColor = 0}) {
    TerminalStyleAttributes.validate(attributes);
    _validateColor(underlineColor);
    if (attributes == 0 && underlineColor == 0) {
      return 0;
    }
    final (int, int) definition = (attributes, underlineColor);
    final int? existing = _idsByDefinition[definition];
    if (existing != null) {
      return existing;
    }
    if (_definitionCount >= capacity) {
      throw StateError('terminal style table capacity exhausted');
    }
    final int id = ++_definitionCount;
    _attributesById[id] = attributes;
    _underlineColorsById[id] = underlineColor;
    _idsByDefinition[definition] = id;
    _generation++;
    return id;
  }

  int attributesAt(int id) {
    RangeError.checkValueInInterval(id, 0, _definitionCount, 'id');
    return _attributesById[id];
  }

  int underlineColorAt(int id) {
    RangeError.checkValueInInterval(id, 0, _definitionCount, 'id');
    return _underlineColorsById[id];
  }

  static void _validateColor(int color) {
    if (color == 0 || color >= 1 && color <= 256) return;
    if (color >= 0x80000000 && color <= 0x80ffffff) return;
    throw ArgumentError.value(
      color,
      'underlineColor',
      'is not a terminal color token',
    );
  }
}
