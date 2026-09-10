part of 'terminal_screen.dart';

/// Mutable logical terminal palette with replaceable reset defaults.
///
/// Terminal OSC mutations form an override layer above the reset defaults.
/// Replacing theme defaults updates only values that OSC has not overridden;
/// the matching OSC reset then reveals the latest theme value.
final class TerminalPalette {
  factory TerminalPalette({
    List<int>? colors,
    int defaultForeground = xtermDefaultForeground,
    int defaultBackground = xtermDefaultBackground,
    int cursorColor = xtermDefaultCursorColor,
  }) {
    final Uint32List initial = colors == null
        ? _createXtermColors()
        : _validatedColorCopy(colors);
    _validateDirectColor(defaultForeground, 'defaultForeground');
    _validateDirectColor(defaultBackground, 'defaultBackground');
    _validateDirectColor(cursorColor, 'cursorColor');
    return TerminalPalette._(
      initial,
      defaultForeground,
      defaultBackground,
      cursorColor,
    );
  }

  TerminalPalette._(
    Uint32List initial,
    this._initialDefaultForeground,
    this._initialDefaultBackground,
    this._initialCursorColor,
  ) : _initialColors = initial,
      _colors = Uint32List.fromList(initial),
      _colorOverrides = Uint8List(_overrideStorageBytes),
      _defaultForeground = _initialDefaultForeground,
      _defaultBackground = _initialDefaultBackground,
      _cursorColor = _initialCursorColor;

  static const int colorCount = 256;
  static const int maxBatchEntries = 256;
  static const int _overrideStorageBytes = colorCount ~/ 8;
  static const int xtermDefaultForeground = 0x80e5e5e5;
  static const int xtermDefaultBackground = 0x80000000;
  static const int xtermDefaultCursorColor = xtermDefaultForeground;

  final Uint32List _initialColors;
  final Uint32List _colors;
  final Uint8List _colorOverrides;
  int _initialDefaultForeground;
  int _initialDefaultBackground;
  int _initialCursorColor;
  int _defaultForeground;
  int _defaultBackground;
  int _cursorColor;
  bool _defaultForegroundOverridden = false;
  bool _defaultBackgroundOverridden = false;
  bool _cursorColorOverridden = false;
  int _generation = 1;
  final List<WeakReference<TerminalScreen>> _screens =
      <WeakReference<TerminalScreen>>[];

  int get generation => _generation;
  int get defaultForeground => _defaultForeground;
  int get defaultBackground => _defaultBackground;
  int get cursorColor => _cursorColor;
  int get typedStorageBytes => colorCount * 4 * 2 + _overrideStorageBytes;

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
    for (int item = 0; item < count; item++) {
      _colors[indices[item]] = colors[item];
      _setColorOverridden(indices[item], true);
    }
    if (!changed) {
      return false;
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
    for (int item = 0; item < count; item++) {
      final int index = indices[item];
      _colors[index] = _initialColors[index];
      _setColorOverridden(index, false);
    }
    if (!changed) {
      return false;
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
    _colors.setAll(0, _initialColors);
    _colorOverrides.fillRange(0, _colorOverrides.length, 0);
    if (!changed) {
      return false;
    }
    _didChange();
    return true;
  }

  bool _setDefaultForeground(int color) {
    _validateDirectColor(color, 'color');
    _defaultForegroundOverridden = true;
    if (_defaultForeground == color) {
      return false;
    }
    _defaultForeground = color;
    _didChange();
    return true;
  }

  bool _setDefaultBackground(int color) {
    _validateDirectColor(color, 'color');
    _defaultBackgroundOverridden = true;
    if (_defaultBackground == color) {
      return false;
    }
    _defaultBackground = color;
    _didChange();
    return true;
  }

  bool _resetDefaultForeground() {
    _defaultForegroundOverridden = false;
    if (_defaultForeground == _initialDefaultForeground) {
      return false;
    }
    _defaultForeground = _initialDefaultForeground;
    _didChange();
    return true;
  }

  bool _resetDefaultBackground() {
    _defaultBackgroundOverridden = false;
    if (_defaultBackground == _initialDefaultBackground) {
      return false;
    }
    _defaultBackground = _initialDefaultBackground;
    _didChange();
    return true;
  }

  bool _setCursorColor(int color) {
    _validateDirectColor(color, 'color');
    _cursorColorOverridden = true;
    if (_cursorColor == color) {
      return false;
    }
    _cursorColor = color;
    _didChange(cursorOnly: true);
    return true;
  }

  bool _resetCursorColor() {
    _cursorColorOverridden = false;
    if (_cursorColor == _initialCursorColor) {
      return false;
    }
    _cursorColor = _initialCursorColor;
    _didChange(cursorOnly: true);
    return true;
  }

  /// Atomically replaces theme/config reset defaults below the OSC layer.
  ///
  /// Returns whether any visible color changed. A change advances the palette
  /// generation exactly once and damages attached screens exactly once.
  bool applyResetDefaults({
    required List<int> colors,
    required int defaultForeground,
    required int defaultBackground,
    required int cursorColor,
  }) {
    final Uint32List validatedColors = _validatedColorCopy(colors);
    _validateDirectColor(defaultForeground, 'defaultForeground');
    _validateDirectColor(defaultBackground, 'defaultBackground');
    _validateDirectColor(cursorColor, 'cursorColor');

    bool paletteChanged = false;
    for (int index = 0; index < colorCount; index++) {
      final int color = validatedColors[index];
      if (!_isColorOverridden(index) && _colors[index] != color) {
        _colors[index] = color;
        paletteChanged = true;
      }
    }
    _initialColors.setAll(0, validatedColors);

    if (!_defaultForegroundOverridden &&
        _defaultForeground != defaultForeground) {
      _defaultForeground = defaultForeground;
      paletteChanged = true;
    }
    if (!_defaultBackgroundOverridden &&
        _defaultBackground != defaultBackground) {
      _defaultBackground = defaultBackground;
      paletteChanged = true;
    }
    _initialDefaultForeground = defaultForeground;
    _initialDefaultBackground = defaultBackground;

    var cursorChanged = false;
    if (!_cursorColorOverridden && _cursorColor != cursorColor) {
      _cursorColor = cursorColor;
      cursorChanged = true;
    }
    _initialCursorColor = cursorColor;

    if (paletteChanged) {
      _didChange();
    } else if (cursorChanged) {
      _didChange(cursorOnly: true);
    }
    return paletteChanged || cursorChanged;
  }

  bool _isColorOverridden(int index) {
    final int mask = 1 << (index & 7);
    return (_colorOverrides[index >> 3] & mask) != 0;
  }

  void _setColorOverridden(int index, bool overridden) {
    final int storageIndex = index >> 3;
    final int mask = 1 << (index & 7);
    if (overridden) {
      _colorOverrides[storageIndex] |= mask;
    } else {
      _colorOverrides[storageIndex] &= 0xff ^ mask;
    }
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

  void _didChange({bool cursorOnly = false}) {
    _generation++;
    for (int index = _screens.length - 1; index >= 0; index--) {
      final TerminalScreen? screen = _screens[index].target;
      if (screen == null) {
        _screens.removeAt(index);
      } else if (cursorOnly) {
        screen._cursorColorPresentationChanged();
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
