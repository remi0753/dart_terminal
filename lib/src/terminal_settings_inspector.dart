import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_accessibility_presentation.dart';
import 'terminal_action_registry.dart';
import 'terminal_appkit_policy.dart';
import 'terminal_config.dart';
import 'terminal_config_reload.dart';
import 'terminal_effective_config.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_event.dart';
import 'terminal_localization.dart';
import 'terminal_settings_document.dart';
import 'terminal_settings_editor.dart';

enum TerminalSettingsInspectorLimitKind { query, renderedOutput }

final class TerminalSettingsInspectorLimitException implements Exception {
  const TerminalSettingsInspectorLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final TerminalSettingsInspectorLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalSettingsInspectorLimitException(${kind.name}: '
      '$actual > $maximum)';
}

final class TerminalSettingsInspectorLimits {
  const TerminalSettingsInspectorLimits({
    this.maxQueryCharacters = 256,
    this.maxSearchResults = 4608,
    this.maxVisibleResults = 8,
    this.maxVisibleDiagnostics = 4,
    this.maxFieldCharacters = 1024,
    this.maxRenderedCharacters = 64 * 1024,
  });

  static const int maximumQueryCharacters = 4096;
  static const int maximumSearchResults = 8192;
  static const int maximumVisibleResults = 64;
  static const int maximumVisibleDiagnostics = 128;
  static const int maximumFieldCharacters = 16 * 1024;
  static const int maximumRenderedCharacters = 1024 * 1024;

  final int maxQueryCharacters;
  final int maxSearchResults;
  final int maxVisibleResults;
  final int maxVisibleDiagnostics;
  final int maxFieldCharacters;
  final int maxRenderedCharacters;

  void validate() {
    _bound(maxQueryCharacters, maximumQueryCharacters, 'maxQueryCharacters');
    _bound(maxSearchResults, maximumSearchResults, 'maxSearchResults');
    _bound(maxVisibleResults, maximumVisibleResults, 'maxVisibleResults');
    _bound(
      maxVisibleDiagnostics,
      maximumVisibleDiagnostics,
      'maxVisibleDiagnostics',
    );
    _bound(maxFieldCharacters, maximumFieldCharacters, 'maxFieldCharacters');
    _bound(
      maxRenderedCharacters,
      maximumRenderedCharacters,
      'maxRenderedCharacters',
    );
  }

  static void _bound(int value, int maximum, String name) {
    if (value < 1 || value > maximum) {
      throw ArgumentError.value(value, name, 'must be in 1..$maximum');
    }
  }
}

/// Searchable projection of the accepted snapshot and latest diagnostics.
final class TerminalSettingsInspectorState {
  factory TerminalSettingsInspectorState({
    required TerminalConfigReloadController controller,
    TerminalSettingsInspectorLimits limits =
        const TerminalSettingsInspectorLimits(),
    TerminalLocalization? localization,
  }) {
    limits.validate();
    return TerminalSettingsInspectorState._(
      controller,
      limits,
      localization ?? TerminalLocalization.english,
    );
  }

  TerminalSettingsInspectorState._(
    this.controller,
    this.limits,
    this.localization,
  );

  final TerminalConfigReloadController controller;
  final TerminalSettingsInspectorLimits limits;
  final TerminalLocalization localization;

  var _isOpen = false;
  var _query = '';
  var _selectedIndex = 0;
  var _matchingEntryCount = 0;
  late TerminalEffectiveConfigSnapshot _effective;
  List<TerminalEffectiveConfigEntry> _results =
      const <TerminalEffectiveConfigEntry>[];
  List<TerminalConfigDiagnostic> _diagnostics =
      const <TerminalConfigDiagnostic>[];
  var _latestDiagnosticAttempt = false;
  String? _lastFailure;

  bool get isOpen => _isOpen;
  String get query => _query;
  int get selectedIndex => _selectedIndex;
  int get matchingEntryCount => _matchingEntryCount;
  int get acceptedGeneration => controller.acceptedGeneration;
  bool get reloadInProgress => controller.inProgress;
  TerminalEffectiveConfigSnapshot get effectiveSnapshot {
    _ensureOpen();
    return _effective;
  }

  List<TerminalEffectiveConfigEntry> get results => _results;
  List<TerminalConfigDiagnostic> get diagnostics => _diagnostics;
  String get diagnosticContext =>
      localization.settingsInspectorDiagnosticContext(_latestDiagnosticAttempt);
  String? get lastFailure => _lastFailure;
  TerminalEffectiveConfigEntry? get selectedEntry =>
      _results.isEmpty ? null : _results[_selectedIndex];

  void open() {
    _isOpen = true;
    _query = '';
    _selectedIndex = 0;
    refresh();
  }

  void dismiss() {
    _isOpen = false;
    _query = '';
    _selectedIndex = 0;
    _matchingEntryCount = 0;
    _results = const <TerminalEffectiveConfigEntry>[];
    _diagnostics = const <TerminalConfigDiagnostic>[];
    _lastFailure = null;
  }

  void refresh() {
    _ensureOpen();
    _effective = TerminalEffectiveConfigSnapshot.fromSnapshot(
      controller.effectiveSnapshot,
      publicOnly: true,
    );
    final TerminalConfigSnapshot? attempted = controller.lastAttemptedSnapshot;
    _diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(
      attempted?.diagnostics ?? _effective.diagnostics,
    );
    _latestDiagnosticAttempt = attempted != null;
    _lastFailure = _safeFailure(controller.lastFailure);
    _rebuildResults();
  }

  void setQuery(String value) {
    _ensureOpen();
    if (value.length > limits.maxQueryCharacters) {
      throw TerminalSettingsInspectorLimitException(
        kind: TerminalSettingsInspectorLimitKind.query,
        actual: value.length,
        maximum: limits.maxQueryCharacters,
      );
    }
    if (value.runes.any(_isControl)) {
      throw ArgumentError.value(
        value,
        'value',
        'settings queries cannot contain control characters',
      );
    }
    _query = value;
    _selectedIndex = 0;
    _rebuildResults();
  }

  void append(String value) => setQuery('$_query$value');

  void deleteLastScalar() {
    _ensureOpen();
    if (_query.isEmpty) return;
    final List<int> scalars = _query.runes.toList()..removeLast();
    setQuery(String.fromCharCodes(scalars));
  }

  void moveSelection(int delta) {
    _ensureOpen();
    if (_results.isEmpty) {
      _selectedIndex = 0;
      return;
    }
    _selectedIndex = (_selectedIndex + delta) % _results.length;
  }

  String render() {
    _ensureOpen();
    final _TerminalSettingsWriter writer = _TerminalSettingsWriter(
      limits.maxRenderedCharacters,
    );
    writer
      ..line(localization.settingsInspectorTitle)
      ..line(localization.settingsInspectorSearch(_query))
      ..line(
        localization.settingsInspectorGeneration(
          generation: acceptedGeneration,
          inProgress: reloadInProgress,
        ),
      )
      ..line(
        localization.settingsInspectorPendingRestart(
          controller.pendingRestartChanges.length,
        ),
      )
      ..line(
        localization.settingsInspectorConfigFile(
          _field(_effective.rootPath ?? localization.settingsNoValue),
        ),
      )
      ..line(
        localization.settingsInspectorMatches(
          matches: _matchingEntryCount,
          total: _effective.entries.length,
        ),
      )
      ..line();

    if (_results.isEmpty) {
      writer.line(localization.settingsInspectorNoMatches);
    } else {
      final int visible = limits.maxVisibleResults.clamp(1, _results.length);
      var start = _selectedIndex - visible ~/ 2;
      if (start < 0) start = 0;
      if (start + visible > _results.length) {
        start = _results.length - visible;
      }
      for (var index = start; index < start + visible; index++) {
        final TerminalEffectiveConfigEntry entry = _results[index];
        final String occurrence = entry.isRepeatable
            ? ' ${entry.occurrenceIndex}/${entry.occurrenceCount}'
            : '';
        writer.line(
          '${index == _selectedIndex ? localization.directionalSelectionMarker : ' '} '
          '${entry.option.name}$occurrence = '
          '${_field(entry.canonicalValue ?? localization.settingsNoValue)}',
        );
      }
      if (_results.length > visible) {
        writer.line(
          localization.settingsInspectorShowing(
            first: start + 1,
            last: start + visible,
            total: _results.length,
          ),
        );
      }
    }

    final TerminalEffectiveConfigEntry? selected = selectedEntry;
    writer
      ..line()
      ..line(localization.settingsInspectorSelectedEntry);
    if (selected == null) {
      writer.line('  ${localization.settingsNoValue}');
    } else {
      final TerminalConfigSource source = selected.source;
      writer
        ..line(
          '  ${localization.settingsInspectorName}: ${selected.option.name}',
        )
        ..line(
          '  ${localization.settingsInspectorValue}: '
          '${_field(selected.canonicalValue ?? localization.settingsNoValue)}',
        )
        ..line(
          '  ${localization.settingsSyntax}: '
          '${_field(selected.option.valueSyntax)}',
        )
        ..line(
          '  ${localization.settingsInspectorPolicy}: '
          '${_localizedPolicy(selected.option.applicationPolicy)}',
        )
        ..line(
          '  ${localization.settingsInspectorSource}: '
          '${_localizedSourceKind(source.kind)} '
          '${_field(source.path)}:${source.line}:${source.column}',
        )
        ..line(
          '  ${localization.settingsInspectorOccurrence}: '
          '${selected.occurrenceIndex}/'
          '${selected.occurrenceCount}',
        )
        ..line(
          '  ${_field(localization.settingsOptionDescription(selected.option.name, selected.option.description))}',
        );
    }

    writer
      ..line()
      ..line(
        localization.settingsInspectorDiagnostics(
          latestAttempt: _latestDiagnosticAttempt,
          count: _diagnostics.length,
        ),
      );
    if (_diagnostics.isEmpty) {
      writer.line(localization.settingsInspectorNone);
    } else {
      final int visible = limits.maxVisibleDiagnostics.clamp(
        1,
        _diagnostics.length,
      );
      for (var index = 0; index < visible; index++) {
        final TerminalConfigDiagnostic diagnostic = _diagnostics[index];
        final TerminalConfigSource source = diagnostic.source;
        writer
          ..line(
            '  ${localization.settingsDiagnosticSeverity(diagnostic.severity.name.toUpperCase())} '
            '${_field(diagnostic.code)} '
            '${_field(_localizedSourceLabel(source))}:'
            '${source.line}:${source.column}',
          )
          ..line('    ${_field(diagnostic.message)}');
        final String? hint = diagnostic.hint;
        if (hint != null) {
          writer.line('    ${localization.settingsFix}: ${_field(hint)}');
        }
      }
      if (_diagnostics.length > visible) {
        writer.line(
          localization.settingsInspectorMoreDiagnostics(
            _diagnostics.length - visible,
          ),
        );
      }
    }
    final String? failure = _lastFailure;
    if (failure != null) {
      writer.line(localization.settingsInspectorReloadFailure(_field(failure)));
    }
    writer
      ..line()
      ..line(localization.settingsInspectorInstructions);
    return writer.finish();
  }

  void _rebuildResults() {
    final List<String> tokens = _query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
    final List<TerminalEffectiveConfigEntry> results =
        <TerminalEffectiveConfigEntry>[];
    var matches = 0;
    for (final TerminalEffectiveConfigEntry entry in _effective.entries) {
      if (!_matches(entry, tokens)) continue;
      matches++;
      if (results.length < limits.maxSearchResults) results.add(entry);
    }
    _matchingEntryCount = matches;
    _results = List<TerminalEffectiveConfigEntry>.unmodifiable(results);
    if (_results.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= _results.length) {
      _selectedIndex = _results.length - 1;
    }
  }

  bool _matches(TerminalEffectiveConfigEntry entry, List<String> tokens) {
    if (tokens.isEmpty) return true;
    final TerminalConfigSource source = entry.source;
    final String candidate = <String>[
      entry.option.name,
      entry.option.valueSyntax,
      entry.option.description,
      localization.settingsOptionDescription(
        entry.option.name,
        entry.option.description,
      ),
      entry.canonicalValue ?? localization.settingsNoValue,
      _policy(entry.option.applicationPolicy),
      _sourceKind(source.kind),
      source.path,
    ].join(' ').toLowerCase();
    return tokens.every(candidate.contains);
  }

  String _field(String value) => _clip(_singleLine(value));

  String _clip(String value) {
    if (value.length <= limits.maxFieldCharacters) return value;
    final StringBuffer clipped = StringBuffer();
    var units = 0;
    for (final int scalar in value.runes) {
      final String character = String.fromCharCode(scalar);
      if (units + character.length + 1 > limits.maxFieldCharacters) break;
      clipped.write(character);
      units += character.length;
    }
    return '${clipped}…';
  }

  String? _safeFailure(Object? error) {
    if (error == null) return null;
    try {
      return _clip(_singleLine('$error'));
    } on Object {
      return error.runtimeType.toString();
    }
  }

  void _ensureOpen() {
    if (!_isOpen) throw StateError('settings inspector is not open');
  }

  static bool _isControl(int scalar) => scalar < 0x20 || scalar == 0x7f;

  static String _singleLine(String value) => String.fromCharCodes(
    value.runes.map((int scalar) => _isControl(scalar) ? 0xfffd : scalar),
  );

  static String _policy(TerminalConfigApplicationPolicy policy) =>
      switch (policy) {
        TerminalConfigApplicationPolicy.live => 'live',
        TerminalConfigApplicationPolicy.newSession => 'new-session',
        TerminalConfigApplicationPolicy.nextLaunch => 'next-launch',
      };

  static String _sourceKind(TerminalConfigSourceKind kind) => switch (kind) {
    TerminalConfigSourceKind.schemaDefault => 'default',
    TerminalConfigSourceKind.file => 'file',
    TerminalConfigSourceKind.commandLine => 'command-line',
  };

  String _localizedPolicy(TerminalConfigApplicationPolicy policy) =>
      localization.settingsApplicationPolicy(_policy(policy));

  String _localizedSourceKind(TerminalConfigSourceKind kind) =>
      localization.settingsSourceKind(_sourceKind(kind));

  String _localizedSourceLabel(TerminalConfigSource source) =>
      source.path.isEmpty ? _localizedSourceKind(source.kind) : source.path;
}

enum TerminalSettingsInspectorKeyDisposition {
  ignored,
  updated,
  dismissed,
  reloadRequested,
  overflow,
}

final class TerminalSettingsInspectorKeyController {
  const TerminalSettingsInspectorKeyController(this.state);

  final TerminalSettingsInspectorState state;

  TerminalSettingsInspectorKeyDisposition handle(AppKitKeyEvent event) {
    if (!state.isOpen || event.kind != AppKitKeyEventKind.down) {
      return TerminalSettingsInspectorKeyDisposition.ignored;
    }
    final TerminalKeyEvent key = TerminalAppKitKeyAdapter.adapt(event);
    switch (key.physicalKey) {
      case TerminalPhysicalKey.escape:
        state.dismiss();
        return TerminalSettingsInspectorKeyDisposition.dismissed;
      case TerminalPhysicalKey.backspace:
        state.deleteLastScalar();
        return TerminalSettingsInspectorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowUp:
        state.moveSelection(-1);
        return TerminalSettingsInspectorKeyDisposition.updated;
      case TerminalPhysicalKey.arrowDown:
        state.moveSelection(1);
        return TerminalSettingsInspectorKeyDisposition.updated;
      case TerminalPhysicalKey.keyR
          when key.modifiers.command &&
              !key.modifiers.control &&
              !key.modifiers.option:
        return TerminalSettingsInspectorKeyDisposition.reloadRequested;
      default:
        break;
    }
    if (key.modifiers.command ||
        key.modifiers.control ||
        key.text.isEmpty ||
        key.text.runes.any(TerminalSettingsInspectorState._isControl)) {
      return TerminalSettingsInspectorKeyDisposition.ignored;
    }
    try {
      state.append(key.text);
    } on TerminalSettingsInspectorLimitException {
      return TerminalSettingsInspectorKeyDisposition.overflow;
    }
    return TerminalSettingsInspectorKeyDisposition.updated;
  }
}

final class TerminalSettingsInspectorFocusTarget {
  const TerminalSettingsInspectorFocusTarget({
    required this.window,
    required this.view,
  });

  final Window window;
  final View view;
}

typedef TerminalSettingsInspectorFocusTargetProvider =
    TerminalSettingsInspectorFocusTarget? Function();
typedef TerminalSettingsInspectorReload =
    Future<TerminalActionDispatchResult> Function();
typedef TerminalSettingsInspectorReloadObserver = void Function(
  TerminalActionDispatchResult result,
);
typedef TerminalSettingsInspectorErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);
typedef TerminalSettingsRuntimeStatusProvider = String? Function();

/// Product-owned modal Settings editor backed by one reload controller.
final class TerminalSettingsInspectorPresenter {
  TerminalSettingsInspectorPresenter({
    required TerminalConfigReloadController controller,
    required TerminalSettingsDocumentSession documentSession,
    required TerminalSettingsInspectorFocusTargetProvider focusTarget,
    required TerminalSettingsInspectorReload reload,
    TerminalSettingsEditorLimits limits = const TerminalSettingsEditorLimits(),
    this.onReloaded,
    this.onVisibilityChanged,
    this.onError,
    this.runtimeStatus,
    TerminalLocalization? localization,
    TerminalAccessibilityPresentation accessibilityPresentation =
        const TerminalAccessibilityPresentation.standard(),
  }) : _focusTarget = focusTarget,
       _reload = reload,
       _localization = localization ?? TerminalLocalization.english,
       _accessibilityPresentation = accessibilityPresentation,
       _settingsPresentation = terminalSettingsPresentationFor(
         accessibilityPresentation,
       ),
       state = TerminalSettingsEditorState(
         controller: controller,
         documentSession: documentSession,
         limits: limits,
         localization: localization,
       ) {
    _keys = TerminalSettingsEditorKeyController(state);
  }

  final TerminalSettingsInspectorFocusTargetProvider _focusTarget;
  final TerminalSettingsInspectorReload _reload;
  final TerminalSettingsInspectorReloadObserver? onReloaded;
  final void Function(bool isPresented)? onVisibilityChanged;
  final TerminalSettingsInspectorErrorObserver? onError;
  final TerminalSettingsRuntimeStatusProvider? runtimeStatus;
  final TerminalLocalization _localization;
  final TerminalSettingsEditorState state;
  TerminalAccessibilityPresentation _accessibilityPresentation;
  TerminalSettingsPresentation _settingsPresentation;

  late final TerminalSettingsEditorKeyController _keys;
  Window? _window;
  TextEditor? _editor;
  TextView? _statusView;
  TextView? _detailView;
  TwoPaneSplitView? _editorStatusSplit;
  TwoPaneSplitView? _rootSplit;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  TerminalActionDispatchResult? _lastReloadResult;
  TerminalSettingsDocumentSaveResult? _lastSaveResult;
  List<TextEditorStyleRun> _publishedStyleRuns = const <TextEditorStyleRun>[];
  bool? _publishedDetailsExpanded;
  var _nativeSynchronizationEpoch = 0;
  var _nativeSynchronizationScheduled = false;
  var _saveInProgress = false;
  var _saveRequestCount = 0;
  var _reloadRequestCount = 0;
  var _terminalResponderRestoreCount = 0;
  var _isDisposed = false;

  bool get isOpen => state.isOpen && _window != null;
  bool get isDisposed => _isDisposed;
  Window? get activeWindow => _window;
  TextEditor? get activeView => _editor;
  TextView? get activeStatusView => _statusView;
  TextView? get activeDetailView => _detailView;
  TwoPaneSplitView? get activeEditorStatusSplit => _editorStatusSplit;
  TwoPaneSplitView? get activeRootSplit => _rootSplit;
  String? get renderedText {
    final TextView? status = _statusView;
    final TextView? detail = _detailView;
    if (status == null || detail == null) return null;
    return '${status.text}\n${detail.text}';
  }

  TerminalActionDispatchResult? get lastReloadResult => _lastReloadResult;
  TerminalSettingsDocumentSaveResult? get lastSaveResult => _lastSaveResult;
  int get saveRequestCount => _saveRequestCount;
  int get reloadRequestCount => _reloadRequestCount;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;
  TerminalAccessibilityPresentation get accessibilityPresentation =>
      _accessibilityPresentation;

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_isDisposed)
      throw StateError('settings inspector presenter is disposed');
    final Window? existing = _window;
    final TextEditor? existingEditor = _editor;
    if (existing != null && existingEditor != null) {
      state.refreshEffectiveConfiguration();
      _render();
      existing.show();
      existing.makeFirstResponder(existingEditor);
      return;
    }

    TextEditor? editor;
    TextView? statusView;
    TextView? detailView;
    TwoPaneSplitView? editorStatusSplit;
    TwoPaneSplitView? rootSplit;
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      state.open();
      editor = TextEditor(
        configuration: _settingsPresentation.editorConfiguration,
      )..suppressesUnhandledEscape = true;
      statusView = TextView(
        configuration: _settingsPresentation.statusConfiguration,
      );
      detailView = TextView(
        configuration: _settingsPresentation.detailConfiguration,
      );
      editorStatusSplit = TwoPaneSplitView(axis: SplitViewAxis.vertical)
        ..setChildren(first: editor, second: statusView)
        ..setPosition(
          fraction: 0.93,
          firstMinimumExtent: 260,
          secondMinimumExtent: 38,
        );
      rootSplit = TwoPaneSplitView(axis: SplitViewAxis.horizontal);
      _setRootChildren(rootSplit, editorStatusSplit, detailView);
      window =
          Window(
              frame: const Rect.fromLTWH(110, 80, 1040, 720),
              title: _fileName(state.documentSession.currentDocument?.rootPath),
              configuration: terminalWindowConfiguration,
            )
            ..representedFilePath =
                state.documentSession.currentDocument?.rootPath
            ..contentView = rootSplit;
      window
        ..keyEventRouting = KeyEventRouting.dartOnly
        ..defersCloseRequests = true;
      subscription = window.events.listen(
        _handleWindowEvent,
        onError: (Object error, StackTrace stackTrace) {
          onError?.call(error, stackTrace);
        },
      );
      _editor = editor;
      _statusView = statusView;
      _detailView = detailView;
      _editorStatusSplit = editorStatusSplit;
      _rootSplit = rootSplit;
      _window = window;
      _subscription = subscription;
      _publishedStyleRuns = const <TextEditorStyleRun>[];
      _publishedDetailsExpanded = null;
      _nativeSynchronizationEpoch++;
      _render();
      window
        ..show()
        ..makeFirstResponder(editor);
      onVisibilityChanged?.call(true);
    } on Object {
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) window.close();
        window.dispose();
      }
      _disposeView(rootSplit);
      _disposeView(editorStatusSplit);
      _disposeView(detailView);
      _disposeView(statusView);
      _disposeView(editor);
      _editor = null;
      _statusView = null;
      _detailView = null;
      _editorStatusSplit = null;
      _rootSplit = null;
      _window = null;
      _subscription = null;
      if (state.isOpen) state.dismiss();
      rethrow;
    }
  }

  void refresh() {
    if (_isDisposed || !state.isOpen) return;
    state.refreshEffectiveConfiguration();
    _render();
  }

  /// Replaces only immutable native presentation views while retaining the
  /// Settings window, document session, draft, selection, and editor mode.
  bool updateAccessibilityPresentation(
    TerminalAccessibilityPresentation presentation,
  ) {
    if (_isDisposed || _accessibilityPresentation == presentation) {
      return false;
    }
    final TerminalSettingsPresentation next = terminalSettingsPresentationFor(
      presentation,
    );
    if (!isOpen || identical(next, _settingsPresentation)) {
      _accessibilityPresentation = presentation;
      _settingsPresentation = next;
      return true;
    }

    synchronizeNativeEditor();
    TextEditor? editor;
    TextView? statusView;
    TextView? detailView;
    TwoPaneSplitView? editorStatusSplit;
    TwoPaneSplitView? rootSplit;
    final Window window = _window!;
    final TextEditor oldEditor = _editor!;
    final TextView oldStatusView = _statusView!;
    final TextView oldDetailView = _detailView!;
    final TwoPaneSplitView oldEditorStatusSplit = _editorStatusSplit!;
    final TwoPaneSplitView oldRootSplit = _rootSplit!;
    final TerminalAccessibilityPresentation oldAccessibilityPresentation =
        _accessibilityPresentation;
    final TerminalSettingsPresentation oldSettingsPresentation =
        _settingsPresentation;
    final List<TextEditorStyleRun> oldPublishedStyleRuns = _publishedStyleRuns;
    final bool? oldPublishedDetailsExpanded = _publishedDetailsExpanded;
    try {
      editor = TextEditor(configuration: next.editorConfiguration)
        ..suppressesUnhandledEscape = true;
      statusView = TextView(configuration: next.statusConfiguration);
      detailView = TextView(configuration: next.detailConfiguration);
      editorStatusSplit = TwoPaneSplitView(axis: SplitViewAxis.vertical)
        ..setChildren(first: editor, second: statusView)
        ..setPosition(
          fraction: 0.93,
          firstMinimumExtent: 260,
          secondMinimumExtent: 38,
        );
      rootSplit = TwoPaneSplitView(axis: SplitViewAxis.horizontal);
      _setRootChildren(rootSplit, editorStatusSplit, detailView);

      _editor = editor;
      _statusView = statusView;
      _detailView = detailView;
      _editorStatusSplit = editorStatusSplit;
      _rootSplit = rootSplit;
      _accessibilityPresentation = presentation;
      _settingsPresentation = next;
      _publishedStyleRuns = const <TextEditorStyleRun>[];
      _publishedDetailsExpanded = null;
      _nativeSynchronizationEpoch++;
      window.contentView = rootSplit;
      _render();
      window.makeFirstResponder(editor);
      _disposeView(oldRootSplit);
      _disposeView(oldEditorStatusSplit);
      _disposeView(oldDetailView);
      _disposeView(oldStatusView);
      _disposeView(oldEditor);
      return true;
    } on Object catch (error, stackTrace) {
      _editor = oldEditor;
      _statusView = oldStatusView;
      _detailView = oldDetailView;
      _editorStatusSplit = oldEditorStatusSplit;
      _rootSplit = oldRootSplit;
      _accessibilityPresentation = oldAccessibilityPresentation;
      _settingsPresentation = oldSettingsPresentation;
      _publishedStyleRuns = oldPublishedStyleRuns;
      _publishedDetailsExpanded = oldPublishedDetailsExpanded;
      _nativeSynchronizationEpoch++;
      try {
        window.contentView = oldRootSplit;
        window.makeFirstResponder(oldEditor);
      } on Object {
        // Preserve the original creation/projection failure for the owner.
      }
      _disposeView(rootSplit);
      _disposeView(editorStatusSplit);
      _disposeView(detailView);
      _disposeView(statusView);
      _disposeView(editor);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> dismiss() {
    if (_isDisposed && _window == null) return Future<void>.value();
    if (state.isOpen) state.dismiss();
    return _close(restoreTerminalFocus: true, closeWindow: true);
  }

  Future<void> dispose() {
    if (_isDisposed) return _closingFuture ?? Future<void>.value();
    _isDisposed = true;
    if (state.isOpen) state.dismiss();
    return _close(restoreTerminalFocus: false, closeWindow: true);
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case AppKitKeyEvent():
        unawaited(_handleKey(event));
      case WindowCloseRequestedEvent():
        final Window? window = _window;
        if (window != null && !window.isClosed && !window.isDisposed) {
          window.replyToCloseRequest(event, allow: false);
        }
        unawaited(dismiss());
      case WindowClosedEvent():
        if (state.isOpen) state.dismiss();
        unawaited(_close(restoreTerminalFocus: true, closeWindow: false));
      case WindowResizedEvent() ||
          WindowFocusChangedEvent() ||
          WindowVisibilityChangedEvent() ||
          WindowOcclusionChangedEvent() ||
          WindowBackingScaleChangedEvent() ||
          WindowScreenChangedEvent() ||
          WindowFrameChangedEvent() ||
          WindowFullscreenChangedEvent() ||
          AppKitScrollEvent():
        break;
      case AppKitMouseEvent():
        _scheduleNativeSynchronization();
    }
  }

  Future<void> _handleKey(AppKitKeyEvent event) async {
    try {
      if (state.mode == TerminalSettingsEditorMode.insert &&
          event.kind == AppKitKeyEventKind.down &&
          TerminalAppKitKeyAdapter.adapt(event).physicalKey ==
              TerminalPhysicalKey.escape) {
        // The native edit may precede its queued synchronization. Pull it before
        // leaving INSERT so NORMAL rendering cannot replace the latest draft.
        synchronizeNativeEditor();
      }
      final TerminalSettingsEditorKeyDisposition disposition = _keys.handle(
        event,
      );
      if (disposition == TerminalSettingsEditorKeyDisposition.dismissed ||
          !state.isOpen) {
        await _close(restoreTerminalFocus: true, closeWindow: true);
        return;
      }
      switch (disposition) {
        case TerminalSettingsEditorKeyDisposition.saveRequested:
          await _saveAndReload();
        case TerminalSettingsEditorKeyDisposition.nativeEditing:
          _scheduleNativeSynchronization();
        case TerminalSettingsEditorKeyDisposition.updated ||
            TerminalSettingsEditorKeyDisposition.overflow:
          _render();
        case TerminalSettingsEditorKeyDisposition.dismissed ||
            TerminalSettingsEditorKeyDisposition.ignored:
          break;
      }
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  void _scheduleNativeSynchronization() {
    if (_nativeSynchronizationScheduled || !state.isOpen) return;
    _nativeSynchronizationScheduled = true;
    final int epoch = _nativeSynchronizationEpoch;
    Future<void>.delayed(Duration.zero).then((_) {
      _nativeSynchronizationScheduled = false;
      if (epoch != _nativeSynchronizationEpoch || !state.isOpen) return;
      try {
        synchronizeNativeEditor();
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }

  /// Pulls native text and selection into the validated product draft.
  void synchronizeNativeEditor() {
    final TextEditor? editor = _editor;
    if (editor == null || editor.isDisposed || !state.isOpen) return;
    final TextEditorSnapshot snapshot = editor.snapshot;
    try {
      state.synchronizeNativeDocument(
        text: snapshot.text,
        selection: TerminalSettingsTextSelection(
          start: snapshot.selection.start,
          length: snapshot.selection.length,
        ),
      );
    } on TerminalSettingsEditorLimitException {
      if (!snapshot.hasMarkedText) {
        editor.setDocument(_documentForState());
      }
      rethrow;
    }
    _render(editorSnapshot: snapshot);
  }

  Future<void> _saveAndReload() async {
    if (_saveInProgress || !state.isOpen) return;
    _saveInProgress = true;
    final Window? expectedWindow = _window;
    try {
      synchronizeNativeEditor();
      _saveRequestCount++;
      final TerminalSettingsDocumentSaveResult saved = state.saveDraft();
      _lastSaveResult = saved;
      _render();
      if (!saved.isSaved) {
        final Object? error = saved.error;
        final StackTrace? stackTrace = saved.stackTrace;
        if (error != null && stackTrace != null) {
          onError?.call(error, stackTrace);
        }
        return;
      }
      _reloadRequestCount++;
      final TerminalActionDispatchResult result = await _reload();
      _lastReloadResult = result;
      onReloaded?.call(result);
      if (identical(_window, expectedWindow) && state.isOpen) {
        state.refreshEffectiveConfiguration();
        _render();
      }
      final Object? error = result.error;
      final StackTrace? stackTrace = result.stackTrace;
      if (error != null && stackTrace != null) {
        onError?.call(error, stackTrace);
      }
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _saveInProgress = false;
    }
  }

  void _render({TextEditorSnapshot? editorSnapshot}) {
    final TextEditor? editor = _editor;
    final TextView? statusView = _statusView;
    final TextView? detailView = _detailView;
    final TwoPaneSplitView? rootSplit = _rootSplit;
    final Window? window = _window;
    if (editor == null ||
        statusView == null ||
        detailView == null ||
        rootSplit == null ||
        window == null ||
        editor.isDisposed ||
        statusView.isDisposed ||
        detailView.isDisposed ||
        rootSplit.isDisposed ||
        !state.isOpen) {
      return;
    }

    TextEditorSnapshot snapshot = editorSnapshot ?? editor.snapshot;
    var selectionMovedByDart = false;
    final List<TextEditorStyleRun> styles = _projectStyleRuns(
      state,
      _settingsPresentation,
    );
    if (snapshot.text != state.text) {
      editor.setDocument(
        TextEditorDocument(
          text: state.text,
          selection: _editorSelection(state.selection),
          styleRuns: styles,
        ),
      );
      _publishedStyleRuns = styles;
      snapshot = editor.snapshot;
    } else {
      final TextEditorSelection desiredSelection = _editorSelection(
        state.selection,
      );
      if (!snapshot.hasMarkedText && snapshot.selection != desiredSelection) {
        editor.setSelection(desiredSelection);
        selectionMovedByDart = true;
      }
      if (!snapshot.hasMarkedText &&
          !_sameStyleRuns(_publishedStyleRuns, styles)) {
        editor.setStyleRuns(styles);
        _publishedStyleRuns = styles;
      }
    }

    final bool editable = state.mode == TerminalSettingsEditorMode.insert;
    if (snapshot.isEditable != editable) editor.isEditable = editable;
    final TextEditorLineHighlight lineHighlight = TextEditorLineHighlight(
      location: state.selection.start,
      color: _settingsPresentation.currentLineColor,
    );
    if (editor.lineHighlight != lineHighlight) {
      editor.setLineHighlight(lineHighlight);
    }
    if (selectionMovedByDart && !editable) {
      editor.scrollSelectionToVisible();
    }
    window.keyEventRouting = editable
        ? KeyEventRouting.dartAndAppKit
        : KeyEventRouting.dartOnly;
    final String? productStatus = _boundedRuntimeStatus(runtimeStatus?.call());
    statusView.text = productStatus == null
        ? state.renderStatus()
        : '${state.renderStatus()}    $productStatus';
    detailView.text = state.detailsExpanded
        ? state.renderDetail()
        : _localization.settingsCollapsedDetail;
    if (_publishedDetailsExpanded != state.detailsExpanded) {
      _setRootPosition(rootSplit, state.detailsExpanded);
      _publishedDetailsExpanded = state.detailsExpanded;
    }
  }

  Future<void> _close({
    required bool restoreTerminalFocus,
    required bool closeWindow,
  }) {
    final Future<void>? existing = _closingFuture;
    if (existing != null) return existing;
    final Completer<void> completion = Completer<void>();
    _closingFuture = completion.future;
    () async {
      try {
        final StreamSubscription<WindowEvent>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
        final Window? window = _window;
        final TextEditor? editor = _editor;
        final TextView? statusView = _statusView;
        final TextView? detailView = _detailView;
        final TwoPaneSplitView? editorStatusSplit = _editorStatusSplit;
        final TwoPaneSplitView? rootSplit = _rootSplit;
        _window = null;
        _editor = null;
        _statusView = null;
        _detailView = null;
        _editorStatusSplit = null;
        _rootSplit = null;
        _nativeSynchronizationEpoch++;
        _nativeSynchronizationScheduled = false;
        _publishedStyleRuns = const <TextEditorStyleRun>[];
        _publishedDetailsExpanded = null;
        if (window != null && !window.isDisposed) {
          if (closeWindow && !window.isClosed) window.close();
          window.dispose();
        }
        _disposeView(rootSplit);
        _disposeView(editorStatusSplit);
        _disposeView(detailView);
        _disposeView(statusView);
        _disposeView(editor);
        if (restoreTerminalFocus) {
          final TerminalSettingsInspectorFocusTarget? target = _focusTarget();
          if (target != null &&
              !target.window.isClosed &&
              !target.window.isDisposed &&
              !target.view.isDisposed) {
            target.window.show();
            target.window.makeFirstResponder(target.view);
            _terminalResponderRestoreCount++;
          }
        }
        if (window != null) onVisibilityChanged?.call(false);
        completion.complete();
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
        onError?.call(error, stackTrace);
      } finally {
        _closingFuture = null;
      }
    }();
    return completion.future;
  }

  TextEditorDocument _documentForState() => TextEditorDocument(
    text: state.text,
    selection: _editorSelection(state.selection),
    styleRuns: _projectStyleRuns(state, _settingsPresentation),
  );

  static TextEditorSelection _editorSelection(
    TerminalSettingsTextSelection selection,
  ) => TextEditorSelection(start: selection.start, length: selection.length);

  String _fileName(String? path) {
    if (path == null || path.isEmpty) return _localization.settingsWindowTitle;
    final List<String> components = path.split(RegExp(r'[/\\]'));
    return components.lastWhere(
      (String component) => component.isNotEmpty,
      orElse: () => _localization.settingsWindowTitle,
    );
  }

  void _setRootChildren(
    TwoPaneSplitView root,
    TwoPaneSplitView editorStatus,
    TextView detail,
  ) {
    if (_localization.textDirection == TerminalTextDirection.rightToLeft) {
      root.setChildren(first: detail, second: editorStatus);
    } else {
      root.setChildren(first: editorStatus, second: detail);
    }
  }

  void _setRootPosition(TwoPaneSplitView root, bool detailsExpanded) {
    if (_localization.textDirection == TerminalTextDirection.rightToLeft) {
      root.setPosition(
        fraction: detailsExpanded ? 0.3 : 0.035,
        firstMinimumExtent: detailsExpanded ? 260 : 30,
        secondMinimumExtent: 360,
      );
    } else {
      root.setPosition(
        fraction: detailsExpanded ? 0.7 : 0.965,
        firstMinimumExtent: 360,
        secondMinimumExtent: detailsExpanded ? 260 : 30,
      );
    }
  }

  static String? _boundedRuntimeStatus(String? value) {
    if (value == null || value.isEmpty) return null;
    final Iterable<int> safe = value.runes
        .take(512)
        .map((int rune) => rune < 0x20 || rune == 0x7f ? 0x20 : rune);
    return String.fromCharCodes(safe);
  }

  static void _disposeView(View? view) {
    if (view != null && !view.isDisposed) view.dispose();
  }
}

final class _TerminalSettingsStyleEvent {
  const _TerminalSettingsStyleEvent.syntax({
    required this.offset,
    required this.starts,
    required TerminalSettingsSyntaxKind kind,
  }) : syntaxKind = kind,
       severity = null;

  const _TerminalSettingsStyleEvent.diagnostic({
    required this.offset,
    required this.starts,
    required TerminalConfigDiagnosticSeverity severity,
  }) : syntaxKind = null,
       severity = severity;

  final int offset;
  final bool starts;
  final TerminalSettingsSyntaxKind? syntaxKind;
  final TerminalConfigDiagnosticSeverity? severity;
}

List<TextEditorStyleRun> _projectStyleRuns(
  TerminalSettingsEditorState state,
  TerminalSettingsPresentation presentation,
) {
  final String text = state.text;
  final List<_TerminalSettingsStyleEvent> events =
      <_TerminalSettingsStyleEvent>[];
  for (final TerminalSettingsSyntaxSpan span in state.syntaxSpans) {
    final int start = _styleBoundary(text, span.start, towardEnd: false);
    final int end = _styleBoundary(text, span.end, towardEnd: true);
    if (start >= end) continue;
    events
      ..add(
        _TerminalSettingsStyleEvent.syntax(
          offset: start,
          starts: true,
          kind: span.kind,
        ),
      )
      ..add(
        _TerminalSettingsStyleEvent.syntax(
          offset: end,
          starts: false,
          kind: span.kind,
        ),
      );
  }
  for (final TerminalSettingsDiagnosticSpan span in state.diagnosticSpans) {
    final int start = _styleBoundary(text, span.start, towardEnd: false);
    final int end = _styleBoundary(text, span.end, towardEnd: true);
    if (start >= end) continue;
    events
      ..add(
        _TerminalSettingsStyleEvent.diagnostic(
          offset: start,
          starts: true,
          severity: span.severity,
        ),
      )
      ..add(
        _TerminalSettingsStyleEvent.diagnostic(
          offset: end,
          starts: false,
          severity: span.severity,
        ),
      );
  }
  if (events.isEmpty) return const <TextEditorStyleRun>[];
  events.sort(
    (_TerminalSettingsStyleEvent left, _TerminalSettingsStyleEvent right) =>
        left.offset.compareTo(right.offset),
  );

  final List<TextEditorStyleRun> runs = <TextEditorStyleRun>[];
  TerminalSettingsSyntaxKind? syntaxKind;
  var errorCount = 0;
  var warningCount = 0;
  var cursor = events.first.offset;
  var index = 0;
  while (index < events.length) {
    final int offset = events[index].offset;
    if (offset > cursor &&
        (syntaxKind != null || errorCount > 0 || warningCount > 0)) {
      final TerminalConfigDiagnosticSeverity? severity = errorCount > 0
          ? TerminalConfigDiagnosticSeverity.error
          : warningCount > 0
          ? TerminalConfigDiagnosticSeverity.warning
          : null;
      _appendProjectedRun(
        runs,
        start: cursor,
        end: offset,
        foreground: _syntaxColor(syntaxKind, presentation),
        severity: severity,
        presentation: presentation,
      );
    }

    final int groupStart = index;
    while (index < events.length && events[index].offset == offset) {
      index++;
    }
    for (var eventIndex = groupStart; eventIndex < index; eventIndex++) {
      final _TerminalSettingsStyleEvent event = events[eventIndex];
      if (event.starts) continue;
      final TerminalSettingsSyntaxKind? endedSyntax = event.syntaxKind;
      if (endedSyntax != null && syntaxKind == endedSyntax) syntaxKind = null;
      switch (event.severity) {
        case TerminalConfigDiagnosticSeverity.error:
          errorCount--;
        case TerminalConfigDiagnosticSeverity.warning:
          warningCount--;
        case null:
          break;
      }
    }
    for (var eventIndex = groupStart; eventIndex < index; eventIndex++) {
      final _TerminalSettingsStyleEvent event = events[eventIndex];
      if (!event.starts) continue;
      final TerminalSettingsSyntaxKind? startedSyntax = event.syntaxKind;
      if (startedSyntax != null) syntaxKind = startedSyntax;
      switch (event.severity) {
        case TerminalConfigDiagnosticSeverity.error:
          errorCount++;
        case TerminalConfigDiagnosticSeverity.warning:
          warningCount++;
        case null:
          break;
      }
    }
    cursor = offset;
  }
  return List<TextEditorStyleRun>.unmodifiable(runs);
}

void _appendProjectedRun(
  List<TextEditorStyleRun> runs, {
  required int start,
  required int end,
  required TextViewColor foreground,
  required TerminalConfigDiagnosticSeverity? severity,
  required TerminalSettingsPresentation presentation,
}) {
  final TextEditorUnderlineStyle underline = severity == null
      ? TextEditorUnderlineStyle.none
      : TextEditorUnderlineStyle.single;
  final TextViewColor underlineColor = switch (severity) {
    TerminalConfigDiagnosticSeverity.error => presentation.errorColor,
    TerminalConfigDiagnosticSeverity.warning => presentation.warningColor,
    null => presentation.primaryTextColor,
  };
  if (runs.isNotEmpty) {
    final TextEditorStyleRun previous = runs.last;
    if (previous.end == start &&
        previous.foregroundColor == foreground &&
        previous.underlineStyle == underline &&
        previous.underlineColor == underlineColor) {
      runs[runs.length - 1] = TextEditorStyleRun(
        start: previous.start,
        length: end - previous.start,
        foregroundColor: foreground,
        underlineStyle: underline,
        underlineColor: underlineColor,
      );
      return;
    }
  }
  if (runs.length >= TextEditorLimits.maximumStyleRuns) {
    throw TerminalSettingsEditorLimitException(
      kind: TerminalSettingsEditorLimitKind.syntaxSpans,
      actual: runs.length + 1,
      maximum: TextEditorLimits.maximumStyleRuns,
    );
  }
  runs.add(
    TextEditorStyleRun(
      start: start,
      length: end - start,
      foregroundColor: foreground,
      underlineStyle: underline,
      underlineColor: underlineColor,
    ),
  );
}

TextViewColor _syntaxColor(
  TerminalSettingsSyntaxKind? kind,
  TerminalSettingsPresentation presentation,
) => switch (kind) {
  TerminalSettingsSyntaxKind.comment => presentation.commentColor,
  TerminalSettingsSyntaxKind.optionName => presentation.optionColor,
  TerminalSettingsSyntaxKind.directive => presentation.directiveColor,
  TerminalSettingsSyntaxKind.operatorToken => presentation.operatorColor,
  TerminalSettingsSyntaxKind.value => presentation.valueColor,
  TerminalSettingsSyntaxKind.unknownOption => presentation.unknownColor,
  null => presentation.primaryTextColor,
};

int _styleBoundary(String text, int offset, {required bool towardEnd}) {
  final int bounded = offset.clamp(0, text.length);
  if (bounded <= 0 || bounded >= text.length) return bounded;
  final int before = text.codeUnitAt(bounded - 1);
  final int after = text.codeUnitAt(bounded);
  final bool splitsSurrogate =
      before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff;
  if (!splitsSurrogate) return bounded;
  return towardEnd ? bounded + 1 : bounded - 1;
}

bool _sameStyleRuns(
  List<TextEditorStyleRun> left,
  List<TextEditorStyleRun> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _TerminalSettingsWriter {
  _TerminalSettingsWriter(this.maximumCharacters);

  final int maximumCharacters;
  final StringBuffer _buffer = StringBuffer();
  var _characters = 0;

  void line([String value = '']) {
    final int next = _characters + value.length + 1;
    if (next > maximumCharacters) {
      throw TerminalSettingsInspectorLimitException(
        kind: TerminalSettingsInspectorLimitKind.renderedOutput,
        actual: next,
        maximum: maximumCharacters,
      );
    }
    _buffer
      ..write(value)
      ..write('\n');
    _characters = next;
  }

  String finish() => _buffer.toString();
}
