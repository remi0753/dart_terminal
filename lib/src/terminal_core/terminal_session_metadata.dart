import 'dart:convert';

/// Bounded session metadata reported by terminal control sequences.
///
/// This state belongs to one PTY session, not to either terminal grid. A cwd
/// report is descriptive metadata only and never changes the process cwd.
final class TerminalSessionMetadata {
  TerminalSessionMetadata();

  static const int maximumTitleUtf8Bytes = 1024;
  static const int maximumWorkingDirectoryUtf8Bytes = 4096;
  static const int titleStackCapacity = 10;

  String? _windowTitle;
  String? _iconTitle;
  Uri? _workingDirectory;
  final List<String?> _windowTitleStack = <String?>[];
  final List<String?> _iconTitleStack = <String?>[];
  int _generation = 1;

  int get generation => _generation;
  String? get windowTitle => _windowTitle;
  String? get iconTitle => _iconTitle;
  Uri? get workingDirectory => _workingDirectory;
  List<String?> get windowTitleStack =>
      List<String?>.unmodifiable(_windowTitleStack);
  List<String?> get iconTitleStack =>
      List<String?>.unmodifiable(_iconTitleStack);

  static bool isSafeTitle(String value) =>
      isSafeDisplayText(value, maximumUtf8Bytes: maximumTitleUtf8Bytes);

  static bool isSafeDisplayText(
    String value, {
    required int maximumUtf8Bytes,
  }) =>
      maximumUtf8Bytes >= 0 &&
      _utf8LengthWithin(value, maximumUtf8Bytes) &&
      !_containsUnsafeDisplayScalar(value);

  static bool isSafeWorkingDirectory(Uri value) {
    final String encoded = value.toString();
    return value.scheme == 'file' &&
        encoded.startsWith('file://') &&
        value.path.startsWith('/') &&
        value.userInfo.isEmpty &&
        !value.hasPort &&
        !value.hasQuery &&
        !value.hasFragment &&
        _utf8LengthWithin(encoded, maximumWorkingDirectoryUtf8Bytes) &&
        !_containsUnsafeDisplayScalar(encoded);
  }

  bool setWindowTitle(String value) {
    _requireSafeTitle(value);
    if (_windowTitle == value) return false;
    _windowTitle = value;
    _generation++;
    return true;
  }

  bool setIconTitle(String value) {
    _requireSafeTitle(value);
    if (_iconTitle == value) return false;
    _iconTitle = value;
    _generation++;
    return true;
  }

  bool setIconAndWindowTitle(String value) {
    _requireSafeTitle(value);
    if (_windowTitle == value && _iconTitle == value) return false;
    _windowTitle = value;
    _iconTitle = value;
    _generation++;
    return true;
  }

  bool setWorkingDirectory(Uri value) {
    if (!isSafeWorkingDirectory(value)) {
      throw ArgumentError.value(value, 'value', 'must be a safe file URI');
    }
    if (_workingDirectory == value) return false;
    _workingDirectory = value;
    _generation++;
    return true;
  }

  void saveTitles(int selector) {
    _validateTitleSelector(selector);
    if (selector == 0 || selector == 1) {
      _push(_iconTitleStack, _iconTitle);
    }
    if (selector == 0 || selector == 2) {
      _push(_windowTitleStack, _windowTitle);
    }
    _generation++;
  }

  bool restoreTitles(int selector) {
    _validateTitleSelector(selector);
    bool changed = false;
    bool popped = false;
    if (selector == 0 || selector == 1) {
      if (_iconTitleStack.isNotEmpty) {
        final String? restored = _iconTitleStack.removeLast();
        popped = true;
        if (_iconTitle != restored) {
          _iconTitle = restored;
          changed = true;
        }
      }
    }
    if (selector == 0 || selector == 2) {
      if (_windowTitleStack.isNotEmpty) {
        final String? restored = _windowTitleStack.removeLast();
        popped = true;
        if (_windowTitle != restored) {
          _windowTitle = restored;
          changed = true;
        }
      }
    }
    if (popped) _generation++;
    return changed;
  }

  bool reset() {
    if (_windowTitle == null &&
        _iconTitle == null &&
        _workingDirectory == null &&
        _windowTitleStack.isEmpty &&
        _iconTitleStack.isEmpty) {
      return false;
    }
    _windowTitle = null;
    _iconTitle = null;
    _workingDirectory = null;
    _windowTitleStack.clear();
    _iconTitleStack.clear();
    _generation++;
    return true;
  }

  static void _push(List<String?> stack, String? value) {
    if (stack.length == titleStackCapacity) {
      stack.removeAt(0);
    }
    stack.add(value);
  }

  static void _requireSafeTitle(String value) {
    if (!isSafeTitle(value)) {
      throw ArgumentError.value(value, 'value', 'must be safe bounded text');
    }
  }

  static void _validateTitleSelector(int selector) {
    if (selector < 0 || selector > 2) {
      throw RangeError.range(selector, 0, 2, 'selector');
    }
  }

  static bool _utf8LengthWithin(String value, int maximum) {
    for (final int codeUnit in value.codeUnits) {
      if (codeUnit >= 0xd800 && codeUnit <= 0xdfff) return false;
    }
    return utf8.encode(value).length <= maximum;
  }

  static bool _containsUnsafeDisplayScalar(String value) {
    for (final int scalar in value.runes) {
      if (scalar <= 0x1f ||
          scalar >= 0x7f && scalar <= 0x9f ||
          scalar == 0x061c ||
          scalar == 0x200e ||
          scalar == 0x200f ||
          scalar == 0x2028 ||
          scalar == 0x2029 ||
          scalar >= 0x202a && scalar <= 0x202e ||
          scalar >= 0x2066 && scalar <= 0x2069) {
        return true;
      }
    }
    return false;
  }
}

/// Restores a fully validated metadata snapshot into a fresh owner.
///
/// This package-internal boundary exists so the text snapshot decoder does
/// not have to replay bounded title-stack operations and accidentally lose
/// null entries or stack order.
void restoreTerminalSessionMetadataSnapshotState(
  TerminalSessionMetadata metadata, {
  required String? windowTitle,
  required String? iconTitle,
  required Uri? workingDirectory,
  required List<String?> windowTitleStack,
  required List<String?> iconTitleStack,
}) {
  if (windowTitle != null &&
          !TerminalSessionMetadata.isSafeTitle(windowTitle) ||
      iconTitle != null && !TerminalSessionMetadata.isSafeTitle(iconTitle) ||
      workingDirectory != null &&
          !TerminalSessionMetadata.isSafeWorkingDirectory(workingDirectory) ||
      windowTitleStack.length > TerminalSessionMetadata.titleStackCapacity ||
      iconTitleStack.length > TerminalSessionMetadata.titleStackCapacity ||
      windowTitleStack.any(
        (String? value) =>
            value != null && !TerminalSessionMetadata.isSafeTitle(value),
      ) ||
      iconTitleStack.any(
        (String? value) =>
            value != null && !TerminalSessionMetadata.isSafeTitle(value),
      )) {
    throw StateError('invalid snapshot session metadata');
  }
  metadata._windowTitle = windowTitle;
  metadata._iconTitle = iconTitle;
  metadata._workingDirectory = workingDirectory;
  metadata._windowTitleStack
    ..clear()
    ..addAll(windowTitleStack);
  metadata._iconTitleStack
    ..clear()
    ..addAll(iconTitleStack);
  metadata._generation++;
}
