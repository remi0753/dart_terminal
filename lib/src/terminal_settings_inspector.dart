import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_action_registry.dart';
import 'terminal_appkit_policy.dart';
import 'terminal_config.dart';
import 'terminal_config_reload.dart';
import 'terminal_effective_config.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_event.dart';

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
  }) {
    limits.validate();
    return TerminalSettingsInspectorState._(controller, limits);
  }

  TerminalSettingsInspectorState._(this.controller, this.limits);

  final TerminalConfigReloadController controller;
  final TerminalSettingsInspectorLimits limits;

  var _isOpen = false;
  var _query = '';
  var _selectedIndex = 0;
  var _matchingEntryCount = 0;
  late TerminalEffectiveConfigSnapshot _effective;
  List<TerminalEffectiveConfigEntry> _results =
      const <TerminalEffectiveConfigEntry>[];
  List<TerminalConfigDiagnostic> _diagnostics =
      const <TerminalConfigDiagnostic>[];
  String _diagnosticContext = 'effective configuration';
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
  String get diagnosticContext => _diagnosticContext;
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
    );
    final TerminalConfigSnapshot? attempted = controller.lastAttemptedSnapshot;
    _diagnostics = List<TerminalConfigDiagnostic>.unmodifiable(
      attempted?.diagnostics ?? _effective.diagnostics,
    );
    _diagnosticContext = attempted == null
        ? 'effective configuration'
        : 'latest reload attempt';
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
      ..line('Settings — Effective Configuration')
      ..line('Search: $_query')
      ..line(
        'Accepted generation: $acceptedGeneration    '
        'Reload: ${reloadInProgress ? 'in progress' : 'idle'}',
      )
      ..line('Config file: ${_field(_effective.rootPath ?? '<none>')}')
      ..line(
        'Matches: $_matchingEntryCount of ${_effective.entries.length} '
        'effective entries',
      )
      ..line();

    if (_results.isEmpty) {
      writer.line('  No matching configuration entries');
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
          '${index == _selectedIndex ? '›' : ' '} '
          '${entry.option.name}$occurrence = '
          '${_field(entry.canonicalValue ?? '<none>')}',
        );
      }
      if (_results.length > visible) {
        writer.line(
          '  Showing ${start + 1}-${start + visible} of ${_results.length}',
        );
      }
    }

    final TerminalEffectiveConfigEntry? selected = selectedEntry;
    writer
      ..line()
      ..line('Selected entry');
    if (selected == null) {
      writer.line('  <none>');
    } else {
      final TerminalConfigSource source = selected.source;
      writer
        ..line('  Name: ${selected.option.name}')
        ..line('  Value: ${_field(selected.canonicalValue ?? '<none>')}')
        ..line('  Syntax: ${_field(selected.option.valueSyntax)}')
        ..line('  Policy: ${_policy(selected.option.applicationPolicy)}')
        ..line(
          '  Source: ${_sourceKind(source.kind)} '
          '${_field(source.path)}:${source.line}:${source.column}',
        )
        ..line(
          '  Occurrence: ${selected.occurrenceIndex}/'
          '${selected.occurrenceCount}',
        )
        ..line('  ${_field(selected.option.description)}');
    }

    writer
      ..line()
      ..line('Diagnostics — $_diagnosticContext (${_diagnostics.length})');
    if (_diagnostics.isEmpty) {
      writer.line('  None');
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
            '  ${diagnostic.severity.name.toUpperCase()} '
            '${_field(diagnostic.code)} '
            '${_field(_sourceLabel(source))}:'
            '${source.line}:${source.column}',
          )
          ..line('    ${_field(diagnostic.message)}');
        final String? hint = diagnostic.hint;
        if (hint != null) writer.line('    Fix: ${_field(hint)}');
      }
      if (_diagnostics.length > visible) {
        writer.line('  … ${_diagnostics.length - visible} more diagnostics');
      }
    }
    final String? failure = _lastFailure;
    if (failure != null) writer.line('  Reload failure: ${_field(failure)}');
    writer
      ..line()
      ..line('Type to search    ↑↓ Select    ⌘R Reload    Esc Close');
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

  static bool _matches(
    TerminalEffectiveConfigEntry entry,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return true;
    final TerminalConfigSource source = entry.source;
    final String candidate = <String>[
      entry.option.name,
      entry.option.valueSyntax,
      entry.option.description,
      entry.canonicalValue ?? '<none>',
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
      };

  static String _sourceKind(TerminalConfigSourceKind kind) => switch (kind) {
    TerminalConfigSourceKind.schemaDefault => 'default',
    TerminalConfigSourceKind.file => 'file',
    TerminalConfigSourceKind.commandLine => 'command-line',
  };

  static String _sourceLabel(TerminalConfigSource source) =>
      source.path.isEmpty ? _sourceKind(source.kind) : source.path;
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

/// Product-owned native Settings window backed by one reload controller.
final class TerminalSettingsInspectorPresenter {
  TerminalSettingsInspectorPresenter({
    required TerminalConfigReloadController controller,
    required TerminalSettingsInspectorFocusTargetProvider focusTarget,
    required TerminalSettingsInspectorReload reload,
    TerminalSettingsInspectorLimits limits =
        const TerminalSettingsInspectorLimits(),
    this.onReloaded,
    this.onError,
  }) : _focusTarget = focusTarget,
       _reload = reload,
       state = TerminalSettingsInspectorState(
         controller: controller,
         limits: limits,
       ) {
    _keys = TerminalSettingsInspectorKeyController(state);
  }

  final TerminalSettingsInspectorFocusTargetProvider _focusTarget;
  final TerminalSettingsInspectorReload _reload;
  final TerminalSettingsInspectorReloadObserver? onReloaded;
  final TerminalSettingsInspectorErrorObserver? onError;
  final TerminalSettingsInspectorState state;

  late final TerminalSettingsInspectorKeyController _keys;
  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  TerminalActionDispatchResult? _lastReloadResult;
  var _reloadRequestCount = 0;
  var _terminalResponderRestoreCount = 0;
  var _isDisposed = false;

  bool get isOpen => state.isOpen && _window != null;
  bool get isDisposed => _isDisposed;
  Window? get activeWindow => _window;
  TextView? get activeView => _view;
  String? get renderedText => _view?.text;
  TerminalActionDispatchResult? get lastReloadResult => _lastReloadResult;
  int get reloadRequestCount => _reloadRequestCount;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_isDisposed)
      throw StateError('settings inspector presenter is disposed');
    final Window? existing = _window;
    final TextView? existingView = _view;
    if (existing != null && existingView != null) {
      state.refresh();
      _render();
      existing.show();
      existing.makeFirstResponder(existingView);
      return;
    }

    final TextView view = TextView(
      configuration: terminalSettingsInspectorTextViewConfiguration,
    );
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      window = Window(
        frame: const Rect.fromLTWH(140, 100, 760, 680),
        title: 'Settings — Effective Configuration',
        configuration: terminalWindowConfiguration,
      )..contentView = view;
      window
        ..keyEventRouting = KeyEventRouting.dartOnly
        ..defersCloseRequests = true;
      subscription = window.events.listen(
        _handleWindowEvent,
        onError: (Object error, StackTrace stackTrace) {
          onError?.call(error, stackTrace);
        },
      );
      _view = view;
      _window = window;
      _subscription = subscription;
      state.open();
      _render();
      window
        ..show()
        ..makeFirstResponder(view);
    } on Object {
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) window.close();
        window.dispose();
      }
      if (!view.isDisposed) view.dispose();
      _view = null;
      _window = null;
      _subscription = null;
      if (state.isOpen) state.dismiss();
      rethrow;
    }
  }

  void refresh() {
    if (_isDisposed || !state.isOpen) return;
    state.refresh();
    _render();
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
          AppKitMouseEvent() ||
          AppKitScrollEvent():
        break;
    }
  }

  Future<void> _handleKey(AppKitKeyEvent event) async {
    try {
      final TerminalSettingsInspectorKeyDisposition disposition = _keys.handle(
        event,
      );
      if (disposition == TerminalSettingsInspectorKeyDisposition.dismissed ||
          !state.isOpen) {
        await _close(restoreTerminalFocus: true, closeWindow: true);
        return;
      }
      if (disposition ==
          TerminalSettingsInspectorKeyDisposition.reloadRequested) {
        _reloadRequestCount++;
        final TerminalActionDispatchResult result = await _reload();
        _lastReloadResult = result;
        onReloaded?.call(result);
        if (!state.isOpen) return;
        state.refresh();
        _render();
        final Object? error = result.error;
        final StackTrace? stackTrace = result.stackTrace;
        if (error != null && stackTrace != null)
          onError?.call(error, stackTrace);
        return;
      }
      if (disposition != TerminalSettingsInspectorKeyDisposition.ignored) {
        _render();
      }
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  void _render() {
    final TextView? view = _view;
    if (view == null || view.isDisposed || !state.isOpen) return;
    view.text = state.render();
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
        final TextView? view = _view;
        _window = null;
        _view = null;
        if (window != null && !window.isDisposed) {
          if (closeWindow && !window.isClosed) window.close();
          window.dispose();
        }
        if (view != null && !view.isDisposed) view.dispose();
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
