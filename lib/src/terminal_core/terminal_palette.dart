part of 'terminal_screen.dart';

/// Mutable logical terminal palette with immutable reset defaults.
final class TerminalPalette {
  factory TerminalPalette({
    List<int>? colors,
    int defaultForeground = xtermDefaultForeground,
    int defaultBackground = xtermDefaultBackground,
  }) {
    final Uint32List initial = colors == null
        ? _createXtermColors()
        : _validatedColorCopy(colors);
    _validateDirectColor(defaultForeground, 'defaultForeground');
    _validateDirectColor(defaultBackground, 'defaultBackground');
    return TerminalPalette._(initial, defaultForeground, defaultBackground);
  }

  TerminalPalette._(
    Uint32List initial,
    this._initialDefaultForeground,
    this._initialDefaultBackground,
  ) : _initialColors = initial,
      _colors = Uint32List.fromList(initial),
      _defaultForeground = _initialDefaultForeground,
      _defaultBackground = _initialDefaultBackground;

  static const int colorCount = 256;
  static const int maxBatchEntries = 256;
  static const int xtermDefaultForeground = 0x80e5e5e5;
  static const int xtermDefaultBackground = 0x80000000;

  final Uint32List _initialColors;
  final Uint32List _colors;
  final int _initialDefaultForeground;
  final int _initialDefaultBackground;
  int _defaultForeground;
  int _defaultBackground;
  int _generation = 1;
  final List<WeakReference<TerminalScreen>> _screens =
      <WeakReference<TerminalScreen>>[];

  int get generation => _generation;
  int get defaultForeground => _defaultForeground;
  int get defaultBackground => _defaultBackground;
  int get typedStorageBytes => colorCount * 4 * 2;

  int colorAt(int index) {
    RangeError.checkValueInInterval(index, 0, colorCount - 1, 'index');
    return _colors[index];
  }

  int resolveToken(int token, {required bool foreground}) {
    if (token == 0) {
      return foreground ? _defaultForeground : _defaultBackground;
    }
    if (token >= 1 && token <= colorCount) {
      return _colors[token - 1];
    }
    _validateDirectColor(token, 'token');
    return token;
  }

  bool _setColors(List<int> indices, List<int> colors, int count) {
    _validateBatch(indices, colors, count);
    bool changed = false;
    for (int item = 0; item < count; item++) {
      bool superseded = false;
      for (int later = item + 1; later < count; later++) {
        if (indices[later] == indices[item]) {
          superseded = true;
          break;
        }
      }
      if (!superseded && _colors[indices[item]] != colors[item]) {
        changed = true;
      }
    }
    if (!changed) {
      return false;
    }
    for (int item = 0; item < count; item++) {
      _colors[indices[item]] = colors[item];
    }
    _didChange();
    return true;
  }

  bool _resetColors(List<int> indices, int count) {
    _validateResetBatch(indices, count);
    bool changed = false;
    for (int item = 0; item < count; item++) {
      final int index = indices[item];
      if (_colors[index] != _initialColors[index]) {
        changed = true;
      }
    }
    if (!changed) {
      return false;
    }
    for (int item = 0; item < count; item++) {
      final int index = indices[item];
      _colors[index] = _initialColors[index];
    }
    _didChange();
    return true;
  }

  bool _resetAllColors() {
    bool changed = false;
    for (int index = 0; index < colorCount; index++) {
      if (_colors[index] != _initialColors[index]) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return false;
    }
    _colors.setAll(0, _initialColors);
    _didChange();
    return true;
  }

  bool _setDefaultForeground(int color) {
    _validateDirectColor(color, 'color');
    if (_defaultForeground == color) {
      return false;
    }
    _defaultForeground = color;
    _didChange();
    return true;
  }

  bool _setDefaultBackground(int color) {
    _validateDirectColor(color, 'color');
    if (_defaultBackground == color) {
      return false;
    }
    _defaultBackground = color;
    _didChange();
    return true;
  }

  bool _resetDefaultForeground() {
    if (_defaultForeground == _initialDefaultForeground) {
      return false;
    }
    _defaultForeground = _initialDefaultForeground;
    _didChange();
    return true;
  }

  bool _resetDefaultBackground() {
    if (_defaultBackground == _initialDefaultBackground) {
      return false;
    }
    _defaultBackground = _initialDefaultBackground;
    _didChange();
    return true;
  }

  void _attach(TerminalScreen screen) {
    for (int index = _screens.length - 1; index >= 0; index--) {
      final TerminalScreen? attached = _screens[index].target;
      if (attached == null) {
        _screens.removeAt(index);
      } else if (identical(attached, screen)) {
        return;
      }
    }
    _screens.add(WeakReference<TerminalScreen>(screen));
  }

  void _didChange() {
    _generation++;
    for (int index = _screens.length - 1; index >= 0; index--) {
      final TerminalScreen? screen = _screens[index].target;
      if (screen == null) {
        _screens.removeAt(index);
      } else {
        screen._palettePresentationChanged();
      }
    }
  }

  static Uint32List _validatedColorCopy(List<int> colors) {
    if (colors.length != colorCount) {
      throw ArgumentError.value(
        colors.length,
        'colors.length',
        'must contain exactly $colorCount colors',
      );
    }
    final Uint32List result = Uint32List(colorCount);
    for (int index = 0; index < colorCount; index++) {
      final int color = colors[index];
      _validateDirectColor(color, 'colors[$index]');
      result[index] = color;
    }
    return result;
  }

  static void _validateBatch(List<int> indices, List<int> colors, int count) {
    if (count <= 0 ||
        count > maxBatchEntries ||
        count > indices.length ||
        count > colors.length) {
      throw RangeError.range(count, 1, maxBatchEntries, 'count');
    }
    for (int item = 0; item < count; item++) {
      RangeError.checkValueInInterval(
        indices[item],
        0,
        colorCount - 1,
        'indices[$item]',
      );
      _validateDirectColor(colors[item], 'colors[$item]');
    }
  }

  static void _validateResetBatch(List<int> indices, int count) {
    if (count <= 0 || count > maxBatchEntries || count > indices.length) {
      throw RangeError.range(count, 1, maxBatchEntries, 'count');
    }
    for (int item = 0; item < count; item++) {
      RangeError.checkValueInInterval(
        indices[item],
        0,
        colorCount - 1,
        'indices[$item]',
      );
    }
  }

  static void _validateDirectColor(int color, String name) {
    if (color < 0x80000000 || color > 0x80ffffff) {
      throw ArgumentError.value(color, name, 'must be tagged direct sRGB');
    }
  }

  static Uint32List _createXtermColors() {
    const List<int> base = <int>[
      0x000000,
      0xcd0000,
      0x00cd00,
      0xcdcd00,
      0x0000ee,
      0xcd00cd,
      0x00cdcd,
      0xe5e5e5,
      0x7f7f7f,
      0xff0000,
      0x00ff00,
      0xffff00,
      0x5c5cff,
      0xff00ff,
      0x00ffff,
      0xffffff,
    ];
    const List<int> levels = <int>[0, 95, 135, 175, 215, 255];
    final Uint32List result = Uint32List(colorCount);
    for (int index = 0; index < base.length; index++) {
      result[index] = 0x80000000 | base[index];
    }
    int index = 16;
    for (final int red in levels) {
      for (final int green in levels) {
        for (final int blue in levels) {
          result[index++] = 0x80000000 | (red << 16) | (green << 8) | blue;
        }
      }
    }
    for (int step = 0; step < 24; step++) {
      final int component = 8 + step * 10;
      result[index++] =
          0x80000000 | (component << 16) | (component << 8) | component;
    }
    return result;
  }
}
