import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_config.dart';
import 'terminal_config_reload.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_localization.dart';
import 'terminal_settings_document.dart';

enum TerminalSettingsEditorMode { normal, insert, search }

enum TerminalSettingsSyntaxKind {
  comment,
  optionName,
  directive,
  operatorToken,
  value,
  unknownOption,
}

final class TerminalSettingsSyntaxSpan {
  const TerminalSettingsSyntaxSpan({
    required this.start,
    required this.length,
    required this.kind,
  });

  final int start;
  final int length;
  final TerminalSettingsSyntaxKind kind;

  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is TerminalSettingsSyntaxSpan &&
      other.start == start &&
      other.length == length &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, length, kind);
}

final class TerminalSettingsDiagnosticSpan {
  const TerminalSettingsDiagnosticSpan({
    required this.start,
    required this.length,
    required this.severity,
  });

  final int start;
  final int length;
  final TerminalConfigDiagnosticSeverity severity;

  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is TerminalSettingsDiagnosticSpan &&
      other.start == start &&
      other.length == length &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(start, length, severity);
}

final class TerminalSettingsTextSelection {
  const TerminalSettingsTextSelection({required this.start, this.length = 0});

  final int start;
  final int length;

  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is TerminalSettingsTextSelection &&
      other.start == start &&
      other.length == length;

  @override
  int get hashCode => Object.hash(start, length);
}

/// One schema assignment located by the editor's presentation-only scanner.
final class TerminalSettingsOptionOccurrence {
  const TerminalSettingsOptionOccurrence({
    required this.option,
    required this.lineIndex,
    required this.lineStart,
    required this.lineEnd,
    required this.nameStart,
    required this.nameEnd,
    required this.valueStart,
    required this.valueEnd,
    required this.isCommented,
  });

  final TerminalConfigOptionBase option;
  final int lineIndex;
  final int lineStart;
  final int lineEnd;
  final int nameStart;
  final int nameEnd;
  final int valueStart;
  final int valueEnd;
  final bool isCommented;

  String draftValue(String document) =>
      document.substring(valueStart, valueEnd);
}

enum TerminalSettingsEditorLimitKind {
  documentCharacters,
  queryCharacters,
  syntaxSpans,
  detailCharacters,
}

final class TerminalSettingsEditorLimitException implements Exception {
  const TerminalSettingsEditorLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final TerminalSettingsEditorLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalSettingsEditorLimitException(${kind.name}: '
      '$actual > $maximum)';
}

final class TerminalSettingsEditorLimits {
  const TerminalSettingsEditorLimits({
    this.maxDocumentCharacters = 1024 * 1024,
    this.maxQueryCharacters = 256,
    this.maxSyntaxSpans = 16 * 1024,
    this.maxDetailCharacters = 16 * 1024,
  });

  static const int maximumDocumentCharacters = 16 * 1024 * 1024;
  static const int maximumQueryCharacters = 4096;
  static const int maximumSyntaxSpans = 64 * 1024;
  static const int maximumDetailCharacters = 1024 * 1024;

  final int maxDocumentCharacters;
  final int maxQueryCharacters;
  final int maxSyntaxSpans;
  final int maxDetailCharacters;

  void validate() {
    _bound(
      maxDocumentCharacters,
      maximumDocumentCharacters,
      'maxDocumentCharacters',
    );
    _bound(maxQueryCharacters, maximumQueryCharacters, 'maxQueryCharacters');
    _bound(maxSyntaxSpans, maximumSyntaxSpans, 'maxSyntaxSpans');
    _bound(maxDetailCharacters, maximumDetailCharacters, 'maxDetailCharacters');
  }

  static void _bound(int value, int maximum, String name) {
    if (value < 1 || value > maximum) {
      throw ArgumentError.value(value, name, 'must be in 1..$maximum');
    }
  }
}

enum TerminalSettingsSaveState {
  unchanged,
  modified,
  saved,
  invalid,
  conflict,
  unavailable,
  failed,
}

/// UI-independent modal state for the complete Settings document.
final class TerminalSettingsEditorState {
  TerminalSettingsEditorState({
    required this.controller,
    required this.documentSession,
    this.limits = const TerminalSettingsEditorLimits(),
    TerminalLocalization? localization,
  }) : localization = localization ?? TerminalLocalization.english {
    limits.validate();
  }

  final TerminalConfigReloadController controller;
  final TerminalSettingsDocumentSession documentSession;
  final TerminalSettingsEditorLimits limits;
  final TerminalLocalization localization;

  var _isOpen = false;
  var _mode = TerminalSettingsEditorMode.normal;
  var _query = '';
  var _detailsExpanded = true;
  var _text = '';
  var _persistedText = '';
  var _selection = const TerminalSettingsTextSelection(start: 0);
  var _saveState = TerminalSettingsSaveState.unchanged;
  List<TerminalSettingsSyntaxSpan> _syntaxSpans =
      const <TerminalSettingsSyntaxSpan>[];
  List<TerminalSettingsDiagnosticSpan> _diagnosticSpans =
      const <TerminalSettingsDiagnosticSpan>[];
  List<TerminalSettingsOptionOccurrence> _occurrences =
      const <TerminalSettingsOptionOccurrence>[];
  List<int> _lineStarts = const <int>[0];
  List<int> _lineEnds = const <int>[0];
  List<TerminalConfigDiagnostic> _diagnostics =
      const <TerminalConfigDiagnostic>[];
  List<TerminalSettingsOptionOccurrence> _searchMatches =
      const <TerminalSettingsOptionOccurrence>[];
  var _searchMatchIndex = 0;
  Object? _lastSaveError;

  bool get isOpen => _isOpen;
  TerminalSettingsEditorMode get mode => _mode;
  String get text => _text;
  String get query => _query;
  bool get detailsExpanded => _detailsExpanded;
  TerminalSettingsTextSelection get selection => _selection;
  TerminalSettingsSaveState get saveState => _saveState;
  bool get isDirty => _text != _persistedText;
  List<TerminalSettingsSyntaxSpan> get syntaxSpans => _syntaxSpans;
  List<TerminalSettingsDiagnosticSpan> get diagnosticSpans => _diagnosticSpans;
  List<TerminalSettingsOptionOccurrence> get occurrences => _occurrences;
  List<TerminalConfigDiagnostic> get diagnostics => _diagnostics;
  Object? get lastSaveError => _lastSaveError;

  TerminalSettingsOptionOccurrence? get selectedOccurrence {
    if (_occurrences.isEmpty) return null;
    final int caret = _selection.start;
    for (final TerminalSettingsOptionOccurrence occurrence in _occurrences) {
      if (caret >= occurrence.lineStart && caret <= occurrence.lineEnd) {
        return occurrence;
      }
    }
    TerminalSettingsOptionOccurrence? preceding;
    for (final TerminalSettingsOptionOccurrence occurrence in _occurrences) {
      if (occurrence.nameStart >= caret) return occurrence;
      preceding = occurrence;
    }
    return preceding;
  }

  void open() {
    if (_isOpen) throw StateError('settings editor is already open');
    final TerminalSettingsDocument document = documentSession.open(
      controller.effectiveSnapshot,
    );
    _isOpen = true;
    _mode = TerminalSettingsEditorMode.normal;
    _query = '';
    _detailsExpanded = true;
    _text = document.text;
    _persistedText = document.text;
    _saveState = TerminalSettingsSaveState.unchanged;
    _lastSaveError = null;
    _diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(
      controller.lastAttemptedSnapshot?.diagnostics ??
          controller.effectiveSnapshot.diagnostics,
    );
    _analyzeDocument();
    final int initial = _occurrences.isEmpty ? 0 : _occurrences.first.nameStart;
    _selection = TerminalSettingsTextSelection(start: initial);
    _rebuildDiagnosticSpans();
  }

  void dismiss() {
    _ensureOpen();
    _isOpen = false;
    _mode = TerminalSettingsEditorMode.normal;
    _query = '';
    _text = '';
    _persistedText = '';
    _selection = const TerminalSettingsTextSelection(start: 0);
    _saveState = TerminalSettingsSaveState.unchanged;
    _syntaxSpans = const <TerminalSettingsSyntaxSpan>[];
    _diagnosticSpans = const <TerminalSettingsDiagnosticSpan>[];
    _occurrences = const <TerminalSettingsOptionOccurrence>[];
    _diagnostics = const <TerminalConfigDiagnostic>[];
    _searchMatches = const <TerminalSettingsOptionOccurrence>[];
    _searchMatchIndex = 0;
    _lastSaveError = null;
  }

  void enterInsert({required bool append}) {
    _ensureOpen();
    if (_mode != TerminalSettingsEditorMode.normal) {
      throw StateError('INSERT may only begin from NORMAL');
    }
    var caret = _selection.end;
    if (append && _selection.length == 0 && caret < _text.length) {
      final int scalar = _text.codeUnitAt(caret);
      if (scalar != 0x0a && scalar != 0x0d) {
        caret = _nextScalarBoundary(_text, caret);
      }
    }
    _selection = TerminalSettingsTextSelection(start: caret);
    _mode = TerminalSettingsEditorMode.insert;
  }

  void enterNormal() {
    _ensureOpen();
    _mode = TerminalSettingsEditorMode.normal;
    _query = '';
    _searchMatches = const <TerminalSettingsOptionOccurrence>[];
    _searchMatchIndex = 0;
  }

  void enterSearch() {
    _ensureOpen();
    if (_mode != TerminalSettingsEditorMode.normal) {
      throw StateError('SEARCH may only begin from NORMAL');
    }
    _mode = TerminalSettingsEditorMode.search;
    _query = '';
    _searchMatches = const <TerminalSettingsOptionOccurrence>[];
    _searchMatchIndex = 0;
  }

  void commitSearch() {
    _ensureOpen();
    if (_mode != TerminalSettingsEditorMode.search) return;
    enterNormal();
  }

  void appendSearch(String value) {
    _ensureSearch();
    if (value.runes.any(_isControl)) {
      throw ArgumentError.value(
        value,
        'value',
        'search input cannot contain control characters',
      );
    }
    final String next = '$_query$value';
    if (next.length > limits.maxQueryCharacters) {
      throw TerminalSettingsEditorLimitException(
        kind: TerminalSettingsEditorLimitKind.queryCharacters,
        actual: next.length,
        maximum: limits.maxQueryCharacters,
      );
    }
    _query = next;
    _rebuildSearchMatches(selectFirst: true);
  }

  void deleteSearchScalar() {
    _ensureSearch();
    if (_query.isEmpty) return;
    final List<int> scalars = _query.runes.toList()..removeLast();
    _query = String.fromCharCodes(scalars);
    _rebuildSearchMatches(selectFirst: true);
  }

  void moveSearchMatch(int delta) {
    _ensureSearch();
    if (_searchMatches.isEmpty) return;
    _searchMatchIndex = (_searchMatchIndex + delta) % _searchMatches.length;
    _selectOccurrence(_searchMatches[_searchMatchIndex]);
  }

  void moveSearchPage(int direction) {
    _ensureSearch();
    if (_searchMatches.isEmpty) return;
    _searchMatchIndex = (_searchMatchIndex + direction * 10).clamp(
      0,
      _searchMatches.length - 1,
    );
    _selectOccurrence(_searchMatches[_searchMatchIndex]);
  }

  void toggleDetails() {
    _ensureOpen();
    _detailsExpanded = !_detailsExpanded;
  }

  void setSelection(TerminalSettingsTextSelection selection) {
    _ensureOpen();
    _validateSelection(_text, selection);
    _selection = selection;
  }

  /// Synchronizes text edited by the same native surface used in all modes.
  void synchronizeNativeDocument({
    required String text,
    required TerminalSettingsTextSelection selection,
  }) {
    _ensureOpen();
    if (text.length > limits.maxDocumentCharacters) {
      throw TerminalSettingsEditorLimitException(
        kind: TerminalSettingsEditorLimitKind.documentCharacters,
        actual: text.length,
        maximum: limits.maxDocumentCharacters,
      );
    }
    _validateSelection(text, selection);
    final bool changed = text != _text;
    _text = text;
    _selection = selection;
    if (changed) {
      _analyzeDocument();
      _rebuildDiagnosticSpans();
      _saveState = isDirty
          ? TerminalSettingsSaveState.modified
          : TerminalSettingsSaveState.unchanged;
      _lastSaveError = null;
      if (_mode == TerminalSettingsEditorMode.search) {
        _rebuildSearchMatches(selectFirst: false);
      }
    }
  }

  void moveCaretHorizontal(int delta) {
    _ensureNormal();
    final int next = delta < 0
        ? _previousScalarBoundary(_text, _selection.start)
        : _nextScalarBoundary(_text, _selection.end);
    _selection = TerminalSettingsTextSelection(start: next);
  }

  void moveCaretVertical(int delta) {
    _ensureNormal();
    final int line = _lineForOffset(_selection.start);
    final int target = (line + delta).clamp(0, _lineStarts.length - 1);
    final int column = _selection.start - _lineStarts[line];
    final int next = (_lineStarts[target] + column).clamp(
      _lineStarts[target],
      _lineEnds[target],
    );
    _selection = TerminalSettingsTextSelection(
      start: _safeScalarBoundary(_text, next),
    );
  }

  void moveCaretToLineBoundary({required bool end}) {
    _ensureNormal();
    final int line = _lineForOffset(_selection.start);
    _selection = TerminalSettingsTextSelection(
      start: end ? _lineEnds[line] : _lineStarts[line],
    );
  }

  TerminalSettingsDocumentSaveResult saveDraft() {
    _ensureOpen();
    try {
      final TerminalSettingsDocumentSaveResult result = documentSession.save(
        _text,
      );
      _diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(
        result.diagnostics,
      );
      _lastSaveError = result.error;
      _saveState = switch (result.disposition) {
        TerminalSettingsDocumentSaveDisposition.saved =>
          TerminalSettingsSaveState.saved,
        TerminalSettingsDocumentSaveDisposition.rejected =>
          TerminalSettingsSaveState.invalid,
        TerminalSettingsDocumentSaveDisposition.conflict =>
          TerminalSettingsSaveState.conflict,
        TerminalSettingsDocumentSaveDisposition.unavailable =>
          TerminalSettingsSaveState.unavailable,
        TerminalSettingsDocumentSaveDisposition.failed =>
          TerminalSettingsSaveState.failed,
      };
      if (result.isSaved) _persistedText = _text;
      _rebuildDiagnosticSpans();
      return result;
    } on Object catch (error) {
      _lastSaveError = error;
      _saveState = TerminalSettingsSaveState.failed;
      rethrow;
    }
  }

  void refreshEffectiveConfiguration() {
    _ensureOpen();
    _diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(
      controller.lastAttemptedSnapshot?.diagnostics ??
          controller.effectiveSnapshot.diagnostics,
    );
    _rebuildDiagnosticSpans();
  }

  String renderStatus() {
    _ensureOpen();
    final String save = localization.settingsSaveState(_saveState.name);
    return switch (_mode) {
      TerminalSettingsEditorMode.normal => localization.settingsNormalStatus(
        save,
      ),
      TerminalSettingsEditorMode.insert => localization.settingsInsertStatus(
        save,
      ),
      TerminalSettingsEditorMode.search => localization.settingsSearchStatus(
        _query,
      ),
    };
  }

  String renderDetail() {
    _ensureOpen();
    final TerminalSettingsOptionOccurrence? occurrence = selectedOccurrence;
    if (occurrence == null) return localization.settingsNoSettingAtCursor;
    final TerminalConfigOptionBase option = occurrence.option;
    final String current = _currentValue(option);
    final String draft = occurrence.draftValue(_text).isEmpty
        ? localization.settingsEmptyValue
        : occurrence.draftValue(_text);
    final String openTerminals =
        option.applicationPolicy == TerminalConfigApplicationPolicy.live
        ? localization.settingsChangeImmediately
        : localization.settingsKeepCurrentValue;
    final String newTerminals =
        option.applicationPolicy == TerminalConfigApplicationPolicy.nextLaunch
        ? localization.settingsKeepCurrentValue
        : localization.settingsUseSavedValue;
    final StringBuffer buffer = StringBuffer()
      ..writeln(option.name)
      ..writeln()
      ..writeln(localization.settingsCurrentValue)
      ..writeln('  ${_singleLine(current)}')
      ..writeln(localization.settingsDraft(disabled: occurrence.isCommented))
      ..writeln('  ${_singleLine(draft)}')
      ..writeln(localization.settingsSyntax)
      ..writeln('  ${option.valueSyntax}')
      ..writeln()
      ..writeln(localization.settingsAfterSave)
      ..writeln('  ${localization.settingsOpenTerminals}   $openTerminals')
      ..writeln(
        '  ${localization.settingsNewTerminals}    '
        '$newTerminals',
      );
    if (option.applicationPolicy ==
        TerminalConfigApplicationPolicy.nextLaunch) {
      buffer.writeln(
        '  ${localization.settingsApplicationRestart}   '
        '${localization.settingsUseSavedValue}',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        localization.settingsOptionDescription(option.name, option.description),
      );
    final List<TerminalConfigDiagnostic> relevant = _diagnostics
        .where(
          (TerminalConfigDiagnostic diagnostic) =>
              diagnostic.source.path ==
                  documentSession.currentDocument?.rootPath &&
              diagnostic.source.line == occurrence.lineIndex + 1,
        )
        .toList(growable: false);
    if (relevant.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(localization.settingsIssues);
      for (final TerminalConfigDiagnostic diagnostic in relevant.take(3)) {
        buffer.writeln(
          '  ${localization.settingsDiagnosticSeverity(diagnostic.severity.name.toUpperCase())} '
          '${diagnostic.code}: ${_singleLine(diagnostic.message)}',
        );
        final String? hint = diagnostic.hint;
        if (hint != null) {
          buffer.writeln('  ${localization.settingsFix}: ${_singleLine(hint)}');
        }
      }
    }
    final String rendered = buffer.toString();
    if (rendered.length > limits.maxDetailCharacters) {
      throw TerminalSettingsEditorLimitException(
        kind: TerminalSettingsEditorLimitKind.detailCharacters,
        actual: rendered.length,
        maximum: limits.maxDetailCharacters,
      );
    }
    return rendered;
  }

  void _analyzeDocument() {
    if (_text.length > limits.maxDocumentCharacters) {
      throw TerminalSettingsEditorLimitException(
        kind: TerminalSettingsEditorLimitKind.documentCharacters,
        actual: _text.length,
        maximum: limits.maxDocumentCharacters,
      );
    }
    final _TerminalSettingsDocumentAnalysis analysis =
        _TerminalSettingsDocumentAnalyzer.analyze(
          _text,
          controller.effectiveSnapshot.schema,
          maximumSpans: limits.maxSyntaxSpans,
        );
    _syntaxSpans = analysis.syntaxSpans;
    _occurrences = analysis.occurrences;
    _lineStarts = analysis.lineStarts;
    _lineEnds = analysis.lineEnds;
  }

  void _rebuildDiagnosticSpans() {
    final String? rootPath = documentSession.currentDocument?.rootPath;
    if (rootPath == null) {
      _diagnosticSpans = const <TerminalSettingsDiagnosticSpan>[];
      return;
    }
    final List<TerminalSettingsDiagnosticSpan> spans =
        <TerminalSettingsDiagnosticSpan>[];
    for (final TerminalConfigDiagnostic diagnostic in _diagnostics) {
      if (diagnostic.source.path != rootPath) continue;
      final int line = diagnostic.source.line - 1;
      if (line < 0 || line >= _lineStarts.length) continue;
      final int start = (_lineStarts[line] + diagnostic.source.column - 1)
          .clamp(_lineStarts[line], _lineEnds[line]);
      final int length = _lineEnds[line] - start;
      if (length <= 0) continue;
      spans.add(
        TerminalSettingsDiagnosticSpan(
          start: start,
          length: length,
          severity: diagnostic.severity,
        ),
      );
    }
    _diagnosticSpans = List<TerminalSettingsDiagnosticSpan>.unmodifiable(spans);
  }

  void _rebuildSearchMatches({required bool selectFirst}) {
    final List<String> tokens = _query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      _searchMatches = const <TerminalSettingsOptionOccurrence>[];
      _searchMatchIndex = 0;
      return;
    }
    final List<TerminalSettingsOptionOccurrence> matches =
        <TerminalSettingsOptionOccurrence>[];
    for (final TerminalSettingsOptionOccurrence occurrence in _occurrences) {
      final TerminalConfigOptionBase option = occurrence.option;
      final String candidate = <String>[
        option.name,
        option.valueSyntax,
        option.description,
        occurrence.draftValue(_text),
        _currentValue(option),
      ].join(' ').toLowerCase();
      if (tokens.every(candidate.contains)) matches.add(occurrence);
    }
    _searchMatches = List<TerminalSettingsOptionOccurrence>.unmodifiable(
      matches,
    );
    if (matches.isEmpty) {
      _searchMatchIndex = 0;
      return;
    }
    if (selectFirst || _searchMatchIndex >= matches.length) {
      _searchMatchIndex = 0;
    }
    _selectOccurrence(matches[_searchMatchIndex]);
  }

  void _selectOccurrence(TerminalSettingsOptionOccurrence occurrence) {
    _selection = TerminalSettingsTextSelection(start: occurrence.nameStart);
  }

  int _lineForOffset(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low <= high) {
      final int middle = (low + high) >> 1;
      if (_lineStarts[middle] <= offset) {
        if (middle == _lineStarts.length - 1 ||
            _lineStarts[middle + 1] > offset) {
          return middle;
        }
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return 0;
  }

  String _currentValue(TerminalConfigOptionBase option) {
    final TerminalConfigSnapshot snapshot = controller.effectiveSnapshot;
    if (!option.isRepeatable) {
      final Object? value = snapshot.resolvedOption(option).value;
      return option.formatObject(value) ?? localization.settingsNotSetValue;
    }
    final List<TerminalResolvedConfigValue<Object?>> values = snapshot
        .occurrencesFor(option);
    if (values.isEmpty) return localization.settingsNotSetValue;
    return values
        .map(
          (TerminalResolvedConfigValue<Object?> value) =>
              option.formatObject(value.value)!,
        )
        .join(', ');
  }

  void _ensureOpen() {
    if (!_isOpen) throw StateError('settings editor is not open');
  }

  void _ensureNormal() {
    _ensureOpen();
    if (_mode != TerminalSettingsEditorMode.normal) {
      throw StateError('operation requires NORMAL mode');
    }
  }

  void _ensureSearch() {
    _ensureOpen();
    if (_mode != TerminalSettingsEditorMode.search) {
      throw StateError('operation requires SEARCH mode');
    }
  }

  static void _validateSelection(
    String text,
    TerminalSettingsTextSelection selection,
  ) {
    if (selection.start < 0 ||
        selection.length < 0 ||
        selection.end > text.length ||
        !_isScalarBoundary(text, selection.start) ||
        !_isScalarBoundary(text, selection.end)) {
      throw RangeError('selection must use valid UTF-16 scalar boundaries');
    }
  }

  static int _safeScalarBoundary(String text, int offset) =>
      _isScalarBoundary(text, offset) ? offset : offset - 1;

  static int _previousScalarBoundary(String text, int offset) {
    if (offset <= 0) return 0;
    var next = offset - 1;
    if (next > 0 &&
        _isLowSurrogate(text.codeUnitAt(next)) &&
        _isHighSurrogate(text.codeUnitAt(next - 1))) {
      next--;
    }
    return next;
  }

  static int _nextScalarBoundary(String text, int offset) {
    if (offset >= text.length) return text.length;
    var next = offset + 1;
    if (next < text.length &&
        _isHighSurrogate(text.codeUnitAt(offset)) &&
        _isLowSurrogate(text.codeUnitAt(next))) {
      next++;
    }
    return next;
  }

  static bool _isScalarBoundary(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return true;
    return !(_isHighSurrogate(text.codeUnitAt(offset - 1)) &&
        _isLowSurrogate(text.codeUnitAt(offset)));
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
  static bool _isControl(int scalar) => scalar < 0x20 || scalar == 0x7f;

  static String _singleLine(String value) => String.fromCharCodes(
    value.runes.map((int scalar) => _isControl(scalar) ? 0xfffd : scalar),
  );
}

enum TerminalSettingsEditorKeyDisposition {
  ignored,
  updated,
  nativeEditing,
  saveRequested,
  dismissed,
  overflow,
}

final class TerminalSettingsEditorKeyController {
  const TerminalSettingsEditorKeyController(this.state);

  final TerminalSettingsEditorState state;

  TerminalSettingsEditorKeyDisposition handle(AppKitKeyEvent event) {
    if (!state.isOpen || event.kind != AppKitKeyEventKind.down) {
      return TerminalSettingsEditorKeyDisposition.ignored;
    }
    final TerminalKeyEvent key = TerminalAppKitKeyAdapter.adapt(event);
    if (key.physicalKey == TerminalPhysicalKey.keyS &&
        key.modifiers.command &&
        !key.modifiers.control &&
        !key.modifiers.option) {
      return TerminalSettingsEditorKeyDisposition.saveRequested;
    }
    return switch (state.mode) {
      TerminalSettingsEditorMode.insert => _handleInsert(key),
      TerminalSettingsEditorMode.search => _handleSearch(key),
      TerminalSettingsEditorMode.normal => _handleNormal(key),
    };
  }

  TerminalSettingsEditorKeyDisposition _handleInsert(TerminalKeyEvent key) {
    if (key.physicalKey == TerminalPhysicalKey.escape) {
      state.enterNormal();
      return TerminalSettingsEditorKeyDisposition.updated;
    }
    return TerminalSettingsEditorKeyDisposition.nativeEditing;
  }

  TerminalSettingsEditorKeyDisposition _handleSearch(TerminalKeyEvent key) {
    final int? pageDirection = _pageDirection(key);
    if (pageDirection != null) {
      if (!_hasPlainPageModifiers(key)) {
        return TerminalSettingsEditorKeyDisposition.ignored;
      }
      state.moveSearchPage(pageDirection);
      return TerminalSettingsEditorKeyDisposition.updated;
    }
    switch (key.physicalKey) {
      case TerminalPhysicalKey.escape:
        state.enterNormal();
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.enter || TerminalPhysicalKey.keypadEnter:
        state.commitSearch();
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.backspace:
        state.deleteSearchScalar();
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowUp:
        state.moveSearchMatch(-1);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowDown:
        state.moveSearchMatch(1);
        return TerminalSettingsEditorKeyDisposition.updated;
      default:
        break;
    }
    if (key.modifiers.command ||
        key.modifiers.control ||
        key.text.isEmpty ||
        key.text.runes.any(TerminalSettingsEditorState._isControl)) {
      return TerminalSettingsEditorKeyDisposition.ignored;
    }
    try {
      state.appendSearch(key.text);
    } on TerminalSettingsEditorLimitException {
      return TerminalSettingsEditorKeyDisposition.overflow;
    }
    return TerminalSettingsEditorKeyDisposition.updated;
  }

  TerminalSettingsEditorKeyDisposition _handleNormal(TerminalKeyEvent key) {
    if (key.modifiers.command ||
        key.modifiers.control ||
        key.modifiers.option) {
      return TerminalSettingsEditorKeyDisposition.ignored;
    }
    final int? pageDirection = _pageDirection(key);
    if (pageDirection != null) {
      if (!_hasPlainPageModifiers(key)) {
        return TerminalSettingsEditorKeyDisposition.ignored;
      }
      state.moveCaretVertical(pageDirection * 10);
      return TerminalSettingsEditorKeyDisposition.updated;
    }
    switch (key.physicalKey) {
      case TerminalPhysicalKey.escape:
        state.dismiss();
        return TerminalSettingsEditorKeyDisposition.dismissed;
      case TerminalPhysicalKey.keyI:
        state.enterInsert(append: false);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.keyA:
        state.enterInsert(append: true);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.slash:
        state.enterSearch();
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.rightBracket:
        state.toggleDetails();
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowUp || TerminalPhysicalKey.keyK:
        state.moveCaretVertical(-1);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowDown || TerminalPhysicalKey.keyJ:
        state.moveCaretVertical(1);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowLeft || TerminalPhysicalKey.keyH:
        state.moveCaretHorizontal(-1);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowRight || TerminalPhysicalKey.keyL:
        state.moveCaretHorizontal(1);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.home:
        state.moveCaretToLineBoundary(end: false);
        return TerminalSettingsEditorKeyDisposition.updated;
      case TerminalPhysicalKey.end:
        state.moveCaretToLineBoundary(end: true);
        return TerminalSettingsEditorKeyDisposition.updated;
      default:
        return TerminalSettingsEditorKeyDisposition.ignored;
    }
  }

  static bool _hasPlainPageModifiers(TerminalKeyEvent key) =>
      !key.modifiers.shift &&
      !key.modifiers.command &&
      !key.modifiers.control &&
      !key.modifiers.option;

  static int? _pageDirection(TerminalKeyEvent key) {
    if (key.physicalKey == TerminalPhysicalKey.pageUp) return -1;
    if (key.physicalKey == TerminalPhysicalKey.pageDown) return 1;
    // Some Fn+arrow events retain their arrow hardware code but translate the
    // function character. The Function flag alone is insufficient because
    // ordinary arrow events also carry it.
    if (key.physicalKey == TerminalPhysicalKey.arrowUp &&
        (key.text == '\uf72c' || key.unmodifiedText == '\uf72c')) {
      return -1;
    }
    if (key.physicalKey == TerminalPhysicalKey.arrowDown &&
        (key.text == '\uf72d' || key.unmodifiedText == '\uf72d')) {
      return 1;
    }
    return null;
  }
}

final class _TerminalSettingsDocumentAnalysis {
  const _TerminalSettingsDocumentAnalysis({
    required this.syntaxSpans,
    required this.occurrences,
    required this.lineStarts,
    required this.lineEnds,
  });

  final List<TerminalSettingsSyntaxSpan> syntaxSpans;
  final List<TerminalSettingsOptionOccurrence> occurrences;
  final List<int> lineStarts;
  final List<int> lineEnds;
}

abstract final class _TerminalSettingsDocumentAnalyzer {
  static final RegExp _name = RegExp(r'^[a-z][a-z0-9-]*$');

  static _TerminalSettingsDocumentAnalysis analyze(
    String text,
    TerminalConfigSchema schema, {
    required int maximumSpans,
  }) {
    final List<TerminalSettingsSyntaxSpan> spans =
        <TerminalSettingsSyntaxSpan>[];
    final List<TerminalSettingsOptionOccurrence> occurrences =
        <TerminalSettingsOptionOccurrence>[];
    final List<int> starts = <int>[];
    final List<int> ends = <int>[];
    var offset = 0;
    var lineIndex = 0;
    while (true) {
      starts.add(offset);
      final int newline = text.indexOf('\n', offset);
      final int rawEnd = newline < 0 ? text.length : newline;
      final int contentEnd =
          rawEnd > offset && text.codeUnitAt(rawEnd - 1) == 13
          ? rawEnd - 1
          : rawEnd;
      ends.add(contentEnd);
      _analyzeLine(
        text,
        schema,
        lineIndex: lineIndex,
        start: offset,
        end: contentEnd,
        spans: spans,
        occurrences: occurrences,
      );
      if (spans.length > maximumSpans) {
        throw TerminalSettingsEditorLimitException(
          kind: TerminalSettingsEditorLimitKind.syntaxSpans,
          actual: spans.length,
          maximum: maximumSpans,
        );
      }
      if (newline < 0) break;
      offset = newline + 1;
      lineIndex++;
      if (offset == text.length) {
        starts.add(offset);
        ends.add(offset);
        break;
      }
    }
    return _TerminalSettingsDocumentAnalysis(
      syntaxSpans: List<TerminalSettingsSyntaxSpan>.unmodifiable(spans),
      occurrences: List<TerminalSettingsOptionOccurrence>.unmodifiable(
        occurrences,
      ),
      lineStarts: List<int>.unmodifiable(starts),
      lineEnds: List<int>.unmodifiable(ends),
    );
  }

  static void _analyzeLine(
    String text,
    TerminalConfigSchema schema, {
    required int lineIndex,
    required int start,
    required int end,
    required List<TerminalSettingsSyntaxSpan> spans,
    required List<TerminalSettingsOptionOccurrence> occurrences,
  }) {
    var cursor = _skipWhitespace(text, start, end);
    if (cursor >= end) return;
    var commented = false;
    if (text.codeUnitAt(cursor) == 35) {
      commented = true;
      cursor = _skipWhitespace(text, cursor + 1, end);
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: start,
          length: end - start,
          kind: TerminalSettingsSyntaxKind.comment,
        ),
      );
      if (!_looksLikeAssignment(text, cursor, end)) {
        return;
      }
    }

    final int nameStart = cursor;
    while (cursor < end) {
      final int unit = text.codeUnitAt(cursor);
      if (unit == 61 || _isWhitespace(unit)) break;
      cursor++;
    }
    final int nameEnd = cursor;
    final String name = text.substring(nameStart, nameEnd);
    cursor = _skipWhitespace(text, cursor, end);
    if (cursor >= end || text.codeUnitAt(cursor) != 61) {
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: nameStart,
          length: end - nameStart,
          kind: TerminalSettingsSyntaxKind.unknownOption,
        ),
      );
      return;
    }
    final TerminalConfigOptionBase? option = schema.optionNamed(name);
    final TerminalSettingsSyntaxKind nameKind = option != null
        ? TerminalSettingsSyntaxKind.optionName
        : name == 'include'
        ? TerminalSettingsSyntaxKind.directive
        : TerminalSettingsSyntaxKind.unknownOption;
    if (!commented) {
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: nameStart,
          length: nameEnd - nameStart,
          kind: nameKind,
        ),
      );
    }
    final int equals = cursor;
    if (!commented) {
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: equals,
          length: 1,
          kind: TerminalSettingsSyntaxKind.operatorToken,
        ),
      );
    }
    final int valueStart = _skipWhitespace(text, equals + 1, end);
    final int commentStart = _commentStart(text, valueStart, end);
    var valueEnd = commentStart;
    while (valueEnd > valueStart &&
        _isWhitespace(text.codeUnitAt(valueEnd - 1))) {
      valueEnd--;
    }
    if (!commented && valueEnd > valueStart) {
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: valueStart,
          length: valueEnd - valueStart,
          kind: TerminalSettingsSyntaxKind.value,
        ),
      );
    }
    if (!commented && commentStart < end) {
      spans.add(
        TerminalSettingsSyntaxSpan(
          start: commentStart,
          length: end - commentStart,
          kind: TerminalSettingsSyntaxKind.comment,
        ),
      );
    }
    if (option != null) {
      occurrences.add(
        TerminalSettingsOptionOccurrence(
          option: option,
          lineIndex: lineIndex,
          lineStart: start,
          lineEnd: end,
          nameStart: nameStart,
          nameEnd: nameEnd,
          valueStart: valueStart,
          valueEnd: valueEnd,
          isCommented: commented,
        ),
      );
    }
  }

  static bool _looksLikeAssignment(String text, int start, int end) {
    var cursor = start;
    while (cursor < end) {
      final int unit = text.codeUnitAt(cursor);
      if (unit == 61) {
        final String candidate = text.substring(start, cursor).trim();
        return candidate == 'include' || _name.hasMatch(candidate);
      }
      if (unit == 35) return false;
      cursor++;
    }
    return false;
  }

  static int _commentStart(String text, int start, int end) {
    var quoted = false;
    var escaped = false;
    for (var index = start; index < end; index++) {
      final int unit = text.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (unit == 92 && quoted) {
        escaped = true;
        continue;
      }
      if (unit == 34) {
        quoted = !quoted;
        continue;
      }
      if (unit == 35 && !quoted) {
        if (_isHexColor(text, index, end)) {
          index += 6;
          continue;
        }
        return index;
      }
    }
    return end;
  }

  static bool _isHexColor(String text, int offset, int end) {
    if (offset + 7 > end) return false;
    for (var index = offset + 1; index < offset + 7; index++) {
      final int unit = text.codeUnitAt(index);
      final bool digit = unit >= 48 && unit <= 57;
      final bool lower = unit >= 97 && unit <= 102;
      final bool upper = unit >= 65 && unit <= 70;
      if (!digit && !lower && !upper) return false;
    }
    return true;
  }

  static int _skipWhitespace(String text, int start, int end) {
    var cursor = start;
    while (cursor < end && _isWhitespace(text.codeUnitAt(cursor))) {
      cursor++;
    }
    return cursor;
  }

  static bool _isWhitespace(int unit) => unit == 32 || unit == 9;
}
