import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'terminal_application_state.dart';
import 'terminal_core/terminal_session_metadata.dart';
import 'terminal_input/terminal_paste.dart';

/// Hard limits shared by the product model and the native scripting adapter.
abstract final class TerminalAppleScriptLimits {
  static const int maximumWindows =
      TerminalApplicationStateLimits.maximumWindows;
  static const int maximumTabsPerWindow =
      TerminalApplicationStateLimits.maximumTabsPerWindow;
  static const int maximumTerminals =
      TerminalApplicationStateLimits.maximumTotalPanes;
  static const int maximumPendingCommands = 16;
  static const int maximumSnapshotBytes = 4 * 1024 * 1024;
  static const int maximumTitleUtf8Bytes =
      TerminalSessionMetadata.maximumTitleUtf8Bytes;
  static const int maximumWorkingDirectoryUtf8Bytes =
      TerminalSessionMetadata.maximumWorkingDirectoryUtf8Bytes;
  static const int maximumInputUtf8Bytes =
      TerminalPasteCodec.maximumEncodedBodyBytes;
  static const int maximumCommandBytes = maximumInputUtf8Bytes + 4096;
}

enum TerminalAppleScriptObjectKind { window, tab, terminal }

/// A stable, kind-safe external identity. Product IDs are never reused.
final class TerminalAppleScriptObjectId {
  factory TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind kind,
    int value,
  ) {
    if (value <= 0 || value > TerminalApplicationState.maximumIdentityValue) {
      throw RangeError.range(
        value,
        1,
        TerminalApplicationState.maximumIdentityValue,
        'value',
      );
    }
    return TerminalAppleScriptObjectId._(kind, value);
  }

  const TerminalAppleScriptObjectId._(this.kind, this.value);

  factory TerminalAppleScriptObjectId.parse(String source) {
    final int separator = source.indexOf(':');
    if (separator <= 0 || separator != source.lastIndexOf(':')) {
      throw FormatException('invalid AppleScript object identity', source);
    }
    final TerminalAppleScriptObjectKind kind = switch (source.substring(
      0,
      separator,
    )) {
      'window' => TerminalAppleScriptObjectKind.window,
      'tab' => TerminalAppleScriptObjectKind.tab,
      'terminal' => TerminalAppleScriptObjectKind.terminal,
      _ => throw FormatException('unknown AppleScript object kind', source),
    };
    final String digits = source.substring(separator + 1);
    if (digits.isEmpty ||
        digits.length > 19 ||
        digits.length > 1 && digits.startsWith('0') ||
        !RegExp(r'^[0-9]+$').hasMatch(digits)) {
      throw FormatException('invalid AppleScript object value', source);
    }
    final int? value = int.tryParse(digits);
    if (value == null ||
        value <= 0 ||
        value > TerminalApplicationState.maximumIdentityValue) {
      throw FormatException('AppleScript object value is out of range', source);
    }
    return TerminalAppleScriptObjectId._(kind, value);
  }

  final TerminalAppleScriptObjectKind kind;
  final int value;

  String get externalValue => '${kind.name}:$value';

  @override
  bool operator ==(Object other) =>
      other is TerminalAppleScriptObjectId &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => externalValue;
}

final class TerminalAppleScriptTerminalSnapshot {
  factory TerminalAppleScriptTerminalSnapshot({
    required TerminalAppleScriptObjectId id,
    required String title,
    required String? workingDirectory,
  }) {
    _requireKind(id, TerminalAppleScriptObjectKind.terminal, 'id');
    _requireDisplayText(
      title,
      'title',
      TerminalAppleScriptLimits.maximumTitleUtf8Bytes,
      allowEmpty: true,
    );
    if (workingDirectory != null) {
      _requireWorkingDirectory(workingDirectory);
    }
    return TerminalAppleScriptTerminalSnapshot._(
      id: id,
      title: title,
      workingDirectory: workingDirectory,
    );
  }

  const TerminalAppleScriptTerminalSnapshot._({
    required this.id,
    required this.title,
    required this.workingDirectory,
  });

  final TerminalAppleScriptObjectId id;
  final String title;
  final String? workingDirectory;
}

final class TerminalAppleScriptTabSnapshot {
  factory TerminalAppleScriptTabSnapshot({
    required TerminalAppleScriptObjectId id,
    required String title,
    required int index,
    required bool selected,
    required TerminalAppleScriptObjectId focusedTerminalId,
    required Iterable<TerminalAppleScriptTerminalSnapshot> terminals,
  }) {
    _requireKind(id, TerminalAppleScriptObjectKind.tab, 'id');
    _requireKind(
      focusedTerminalId,
      TerminalAppleScriptObjectKind.terminal,
      'focusedTerminalId',
    );
    _requireDisplayText(
      title,
      'title',
      TerminalAppleScriptLimits.maximumTitleUtf8Bytes,
      allowEmpty: true,
    );
    if (index <= 0 || index > TerminalAppleScriptLimits.maximumTabsPerWindow) {
      throw RangeError.range(
        index,
        1,
        TerminalAppleScriptLimits.maximumTabsPerWindow,
        'index',
      );
    }
    final List<TerminalAppleScriptTerminalSnapshot> copied =
        List<TerminalAppleScriptTerminalSnapshot>.unmodifiable(terminals);
    if (copied.isEmpty ||
        copied.length > TerminalAppleScriptLimits.maximumTerminals) {
      throw ArgumentError.value(
        copied.length,
        'terminals.length',
        'must be within the application terminal bounds',
      );
    }
    _requireUnique(copied.map((item) => item.id), 'terminal');
    if (!copied.any((item) => item.id == focusedTerminalId)) {
      throw ArgumentError.value(
        focusedTerminalId,
        'focusedTerminalId',
        'must identify a terminal in this tab',
      );
    }
    return TerminalAppleScriptTabSnapshot._(
      id: id,
      title: title,
      index: index,
      selected: selected,
      focusedTerminalId: focusedTerminalId,
      terminals: copied,
    );
  }

  const TerminalAppleScriptTabSnapshot._({
    required this.id,
    required this.title,
    required this.index,
    required this.selected,
    required this.focusedTerminalId,
    required this.terminals,
  });

  final TerminalAppleScriptObjectId id;
  final String title;
  final int index;
  final bool selected;
  final TerminalAppleScriptObjectId focusedTerminalId;
  final List<TerminalAppleScriptTerminalSnapshot> terminals;
}

final class TerminalAppleScriptWindowSnapshot {
  factory TerminalAppleScriptWindowSnapshot({
    required TerminalAppleScriptObjectId id,
    required String title,
    required int index,
    required bool frontmost,
    required TerminalAppleScriptObjectId selectedTabId,
    required Iterable<TerminalAppleScriptTabSnapshot> tabs,
  }) {
    _requireKind(id, TerminalAppleScriptObjectKind.window, 'id');
    _requireKind(
      selectedTabId,
      TerminalAppleScriptObjectKind.tab,
      'selectedTabId',
    );
    _requireDisplayText(
      title,
      'title',
      TerminalAppleScriptLimits.maximumTitleUtf8Bytes,
      allowEmpty: true,
    );
    if (index <= 0 || index > TerminalAppleScriptLimits.maximumWindows) {
      throw RangeError.range(
        index,
        1,
        TerminalAppleScriptLimits.maximumWindows,
        'index',
      );
    }
    final List<TerminalAppleScriptTabSnapshot> copied =
        List<TerminalAppleScriptTabSnapshot>.unmodifiable(tabs);
    if (copied.isEmpty ||
        copied.length > TerminalAppleScriptLimits.maximumTabsPerWindow) {
      throw ArgumentError.value(
        copied.length,
        'tabs.length',
        'must be within the window tab bounds',
      );
    }
    _requireUnique(copied.map((item) => item.id), 'tab');
    for (var position = 0; position < copied.length; position++) {
      if (copied[position].index != position + 1) {
        throw ArgumentError.value(
          copied[position].index,
          'tabs[$position].index',
          'must match one-based collection order',
        );
      }
    }
    if (!copied.any((item) => item.id == selectedTabId)) {
      throw ArgumentError.value(
        selectedTabId,
        'selectedTabId',
        'must identify a tab in this window',
      );
    }
    if (copied.where((item) => item.selected).length != 1 ||
        !copied.any((item) => item.id == selectedTabId && item.selected)) {
      throw ArgumentError.value(
        selectedTabId,
        'selectedTabId',
        'must match the single selected tab',
      );
    }
    return TerminalAppleScriptWindowSnapshot._(
      id: id,
      title: title,
      index: index,
      frontmost: frontmost,
      selectedTabId: selectedTabId,
      tabs: copied,
    );
  }

  const TerminalAppleScriptWindowSnapshot._({
    required this.id,
    required this.title,
    required this.index,
    required this.frontmost,
    required this.selectedTabId,
    required this.tabs,
  });

  final TerminalAppleScriptObjectId id;
  final String title;
  final int index;
  final bool frontmost;
  final TerminalAppleScriptObjectId selectedTabId;
  final List<TerminalAppleScriptTabSnapshot> tabs;
}

/// One atomic, terminal-content-free cache projection for Cocoa scripting.
final class TerminalAppleScriptApplicationSnapshot {
  factory TerminalAppleScriptApplicationSnapshot({
    required int generation,
    required bool enabled,
    required Iterable<TerminalAppleScriptWindowSnapshot> windows,
  }) {
    if (generation < 0 ||
        generation > TerminalApplicationState.maximumIdentityValue) {
      throw RangeError.range(
        generation,
        0,
        TerminalApplicationState.maximumIdentityValue,
        'generation',
      );
    }
    final List<TerminalAppleScriptWindowSnapshot> copied =
        List<TerminalAppleScriptWindowSnapshot>.unmodifiable(windows);
    if (!enabled && copied.isNotEmpty) {
      throw ArgumentError.value(
        copied.length,
        'windows.length',
        'disabled scripting must publish an empty hierarchy',
      );
    }
    if (copied.length > TerminalAppleScriptLimits.maximumWindows) {
      throw ArgumentError.value(
        copied.length,
        'windows.length',
        'exceeds the scripting window limit',
      );
    }
    _requireUnique(copied.map((item) => item.id), 'window');
    final Set<TerminalAppleScriptObjectId> tabIds =
        <TerminalAppleScriptObjectId>{};
    final Set<TerminalAppleScriptObjectId> terminalIds =
        <TerminalAppleScriptObjectId>{};
    var selectedWindows = 0;
    for (var position = 0; position < copied.length; position++) {
      final TerminalAppleScriptWindowSnapshot window = copied[position];
      if (window.index != position + 1) {
        throw ArgumentError.value(
          window.index,
          'windows[$position].index',
          'must match one-based collection order',
        );
      }
      if (window.frontmost) selectedWindows++;
      for (final TerminalAppleScriptTabSnapshot tab in window.tabs) {
        if (!tabIds.add(tab.id)) {
          throw ArgumentError('tab IDs must be unique across the application');
        }
        for (final TerminalAppleScriptTerminalSnapshot terminal
            in tab.terminals) {
          if (!terminalIds.add(terminal.id)) {
            throw ArgumentError(
              'terminal IDs must be unique across the application',
            );
          }
        }
      }
    }
    if (selectedWindows > 1 ||
        terminalIds.length > TerminalAppleScriptLimits.maximumTerminals) {
      throw ArgumentError(
        'application selection or terminal bounds are invalid',
      );
    }
    return TerminalAppleScriptApplicationSnapshot._(
      generation: generation,
      enabled: enabled,
      windows: copied,
    );
  }

  const TerminalAppleScriptApplicationSnapshot._({
    required this.generation,
    required this.enabled,
    required this.windows,
  });

  final int generation;
  final bool enabled;
  final List<TerminalAppleScriptWindowSnapshot> windows;
}

/// Deterministic versioned JSON consumed as one native snapshot replacement.
abstract final class TerminalAppleScriptSnapshotCodec {
  static const int version = 1;

  static Uint8List encode(TerminalAppleScriptApplicationSnapshot snapshot) {
    final Uint8List bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'version': version,
          'generation': snapshot.generation,
          'enabled': snapshot.enabled,
          'windows': snapshot.windows
              .map(
                (window) => <String, Object?>{
                  'id': window.id.externalValue,
                  'title': window.title,
                  'index': window.index,
                  'frontmost': window.frontmost,
                  'selectedTab': window.selectedTabId.externalValue,
                  'tabs': window.tabs
                      .map(
                        (tab) => <String, Object?>{
                          'id': tab.id.externalValue,
                          'title': tab.title,
                          'index': tab.index,
                          'selected': tab.selected,
                          'focusedTerminal':
                              tab.focusedTerminalId.externalValue,
                          'terminals': tab.terminals
                              .map(
                                (terminal) => <String, Object?>{
                                  'id': terminal.id.externalValue,
                                  'title': terminal.title,
                                  'workingDirectory': terminal.workingDirectory,
                                },
                              )
                              .toList(growable: false),
                        },
                      )
                      .toList(growable: false),
                },
              )
              .toList(growable: false),
        }),
      ),
    );
    if (bytes.length > TerminalAppleScriptLimits.maximumSnapshotBytes) {
      throw const FormatException('AppleScript snapshot exceeds byte limit');
    }
    return bytes;
  }

  static TerminalAppleScriptApplicationSnapshot decode(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > TerminalAppleScriptLimits.maximumSnapshotBytes) {
      throw const FormatException('invalid AppleScript snapshot byte length');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object catch (error) {
      throw FormatException('invalid AppleScript snapshot JSON', error);
    }
    final Map<String, Object?> root = _object(decoded, 'snapshot');
    _exactKeys(root, const <String>{
      'version',
      'generation',
      'enabled',
      'windows',
    });
    if (root['version'] != version) {
      throw const FormatException('unsupported AppleScript snapshot version');
    }
    final List<Object?> windows = _list(root['windows'], 'windows');
    return TerminalAppleScriptApplicationSnapshot(
      generation: _integer(root['generation'], 'generation'),
      enabled: _boolean(root['enabled'], 'enabled'),
      windows: windows.map((value) {
        final Map<String, Object?> window = _object(value, 'window');
        _exactKeys(window, const <String>{
          'id',
          'title',
          'index',
          'frontmost',
          'selectedTab',
          'tabs',
        });
        return TerminalAppleScriptWindowSnapshot(
          id: TerminalAppleScriptObjectId.parse(_string(window['id'], 'id')),
          title: _string(window['title'], 'title'),
          index: _integer(window['index'], 'index'),
          frontmost: _boolean(window['frontmost'], 'frontmost'),
          selectedTabId: TerminalAppleScriptObjectId.parse(
            _string(window['selectedTab'], 'selectedTab'),
          ),
          tabs: _list(window['tabs'], 'tabs').map((value) {
            final Map<String, Object?> tab = _object(value, 'tab');
            _exactKeys(tab, const <String>{
              'id',
              'title',
              'index',
              'selected',
              'focusedTerminal',
              'terminals',
            });
            return TerminalAppleScriptTabSnapshot(
              id: TerminalAppleScriptObjectId.parse(_string(tab['id'], 'id')),
              title: _string(tab['title'], 'title'),
              index: _integer(tab['index'], 'index'),
              selected: _boolean(tab['selected'], 'selected'),
              focusedTerminalId: TerminalAppleScriptObjectId.parse(
                _string(tab['focusedTerminal'], 'focusedTerminal'),
              ),
              terminals: _list(tab['terminals'], 'terminals').map((value) {
                final Map<String, Object?> terminal = _object(
                  value,
                  'terminal',
                );
                _exactKeys(terminal, const <String>{
                  'id',
                  'title',
                  'workingDirectory',
                });
                final Object? cwd = terminal['workingDirectory'];
                return TerminalAppleScriptTerminalSnapshot(
                  id: TerminalAppleScriptObjectId.parse(
                    _string(terminal['id'], 'id'),
                  ),
                  title: _string(terminal['title'], 'title'),
                  workingDirectory: cwd == null
                      ? null
                      : _string(cwd, 'workingDirectory'),
                );
              }),
            );
          }),
        );
      }),
    );
  }
}

enum TerminalAppleScriptCommandKind {
  newWindow,
  newTab,
  split,
  inputText,
  focus,
  closeTerminal,
  closeTab,
  closeWindow,
}

enum TerminalAppleScriptSplitDirection { right, left, down, up }

final class TerminalAppleScriptCommandRequest {
  factory TerminalAppleScriptCommandRequest({
    required int operationId,
    required TerminalAppleScriptCommandKind kind,
    TerminalAppleScriptObjectId? target,
    TerminalAppleScriptSplitDirection? direction,
    String? text,
  }) {
    if (operationId <= 0 ||
        operationId > TerminalApplicationState.maximumIdentityValue) {
      throw RangeError.range(
        operationId,
        1,
        TerminalApplicationState.maximumIdentityValue,
        'operationId',
      );
    }
    final TerminalAppleScriptObjectKind? requiredTarget = switch (kind) {
      TerminalAppleScriptCommandKind.newWindow => null,
      TerminalAppleScriptCommandKind.newTab =>
        TerminalAppleScriptObjectKind.window,
      TerminalAppleScriptCommandKind.split ||
      TerminalAppleScriptCommandKind.inputText ||
      TerminalAppleScriptCommandKind.focus ||
      TerminalAppleScriptCommandKind.closeTerminal =>
        TerminalAppleScriptObjectKind.terminal,
      TerminalAppleScriptCommandKind.closeTab =>
        TerminalAppleScriptObjectKind.tab,
      TerminalAppleScriptCommandKind.closeWindow =>
        TerminalAppleScriptObjectKind.window,
    };
    if (requiredTarget == null && target != null ||
        requiredTarget != null && target?.kind != requiredTarget) {
      throw ArgumentError.value(target, 'target', 'does not match $kind');
    }
    if ((kind == TerminalAppleScriptCommandKind.split) != (direction != null)) {
      throw ArgumentError.value(direction, 'direction', 'does not match $kind');
    }
    if ((kind == TerminalAppleScriptCommandKind.inputText) != (text != null)) {
      throw ArgumentError.value(text, 'text', 'does not match $kind');
    }
    if (text != null) {
      if (text.isEmpty ||
          !_utf8LengthWithin(
            text,
            TerminalAppleScriptLimits.maximumInputUtf8Bytes,
          )) {
        throw ArgumentError.value(
          text.length,
          'text',
          'must be non-empty valid text within the input byte limit',
        );
      }
    }
    return TerminalAppleScriptCommandRequest._(
      operationId: operationId,
      kind: kind,
      target: target,
      direction: direction,
      text: text,
    );
  }

  const TerminalAppleScriptCommandRequest._({
    required this.operationId,
    required this.kind,
    required this.target,
    required this.direction,
    required this.text,
  });

  final int operationId;
  final TerminalAppleScriptCommandKind kind;
  final TerminalAppleScriptObjectId? target;
  final TerminalAppleScriptSplitDirection? direction;
  final String? text;
}

/// Strict decoder for one validated command packet emitted by the native
/// Cocoa Scripting bridge.
abstract final class TerminalAppleScriptCommandCodec {
  static const int version = 1;

  static TerminalAppleScriptCommandRequest decode(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > TerminalAppleScriptLimits.maximumCommandBytes) {
      throw const FormatException('invalid AppleScript command byte length');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object catch (error) {
      throw FormatException('invalid AppleScript command JSON', error);
    }
    final Map<String, Object?> root = _object(decoded, 'command');
    _exactKeys(root, const <String>{
      'version',
      'operationId',
      'kind',
      'target',
      'direction',
      'text',
    });
    if (root['version'] != version) {
      throw const FormatException('unsupported AppleScript command version');
    }
    final String kindName = _string(root['kind'], 'kind');
    final TerminalAppleScriptCommandKind kind = TerminalAppleScriptCommandKind
        .values
        .firstWhere(
          (TerminalAppleScriptCommandKind value) => value.name == kindName,
          orElse: () => throw FormatException(
            'unknown AppleScript command kind',
            kindName,
          ),
        );
    final Object? targetValue = root['target'];
    final Object? directionValue = root['direction'];
    final Object? textValue = root['text'];
    final TerminalAppleScriptSplitDirection? direction = directionValue == null
        ? null
        : TerminalAppleScriptSplitDirection.values.firstWhere(
            (TerminalAppleScriptSplitDirection value) =>
                value.name == _string(directionValue, 'direction'),
            orElse: () => throw FormatException(
              'unknown AppleScript split direction',
              directionValue,
            ),
          );
    try {
      return TerminalAppleScriptCommandRequest(
        operationId: _integer(root['operationId'], 'operationId'),
        kind: kind,
        target: targetValue == null
            ? null
            : TerminalAppleScriptObjectId.parse(_string(targetValue, 'target')),
        direction: direction,
        text: textValue == null ? null : _string(textValue, 'text'),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid AppleScript command shape', error);
    }
  }
}

enum TerminalAppleScriptCommandDisposition {
  completed,
  confirmationRequired,
  disabled,
  notFound,
  busy,
  rejected,
  failed,
  timedOut,
  disposed,
}

final class TerminalAppleScriptCommandResult {
  const TerminalAppleScriptCommandResult({
    required this.operationId,
    required this.disposition,
    this.object,
  });

  final int operationId;
  final TerminalAppleScriptCommandDisposition disposition;
  final TerminalAppleScriptObjectId? object;

  bool get isCompleted =>
      disposition == TerminalAppleScriptCommandDisposition.completed;
}

abstract interface class TerminalAppleScriptCommandExecutor {
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  );
}

/// Serializes asynchronous Dart-owned mutations and resolves each request once.
final class TerminalAppleScriptCommandController {
  TerminalAppleScriptCommandController({
    required bool enabled,
    required TerminalAppleScriptCommandExecutor executor,
    this.commandTimeout = const Duration(seconds: 30),
    this.maximumPendingCommands =
        TerminalAppleScriptLimits.maximumPendingCommands,
  }) : _enabled = enabled,
       _executor = executor {
    if (commandTimeout <= Duration.zero) {
      throw ArgumentError.value(commandTimeout, 'commandTimeout');
    }
    RangeError.checkValueInInterval(
      maximumPendingCommands,
      1,
      TerminalAppleScriptLimits.maximumPendingCommands,
      'maximumPendingCommands',
    );
  }

  final TerminalAppleScriptCommandExecutor _executor;
  final Duration commandTimeout;
  final int maximumPendingCommands;
  final List<_TerminalAppleScriptPendingCommand> _queue =
      <_TerminalAppleScriptPendingCommand>[];
  _TerminalAppleScriptPendingCommand? _active;
  bool _enabled;
  bool _disposed = false;

  bool get isEnabled => _enabled;
  bool get isDisposed => _disposed;
  int get pendingCount => _queue.length + (_active == null ? 0 : 1);

  Future<TerminalAppleScriptCommandResult> submit(
    TerminalAppleScriptCommandRequest request,
  ) {
    if (_disposed)
      return Future.value(
        _result(request, TerminalAppleScriptCommandDisposition.disposed),
      );
    if (!_enabled)
      return Future.value(
        _result(request, TerminalAppleScriptCommandDisposition.disabled),
      );
    if (pendingCount >= maximumPendingCommands) {
      return Future.value(
        _result(request, TerminalAppleScriptCommandDisposition.busy),
      );
    }
    if (_active?.request.operationId == request.operationId ||
        _queue.any(
          (pending) => pending.request.operationId == request.operationId,
        )) {
      return Future.value(
        _result(request, TerminalAppleScriptCommandDisposition.rejected),
      );
    }
    final _TerminalAppleScriptPendingCommand pending =
        _TerminalAppleScriptPendingCommand(request);
    _queue.add(pending);
    _drain();
    return pending.completer.future;
  }

  void setEnabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    if (!value) {
      for (final _TerminalAppleScriptPendingCommand pending in _queue.toList(
        growable: false,
      )) {
        _complete(
          pending,
          _result(
            pending.request,
            TerminalAppleScriptCommandDisposition.disabled,
          ),
        );
      }
      _queue.clear();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enabled = false;
    final List<_TerminalAppleScriptPendingCommand> pending =
        <_TerminalAppleScriptPendingCommand>[
          if (_active != null) _active!,
          ..._queue,
        ];
    _queue.clear();
    _active = null;
    for (final _TerminalAppleScriptPendingCommand item in pending) {
      _complete(
        item,
        _result(item.request, TerminalAppleScriptCommandDisposition.disposed),
      );
    }
  }

  void _drain() {
    if (_disposed || _active != null || _queue.isEmpty) return;
    final _TerminalAppleScriptPendingCommand pending = _queue.removeAt(0);
    _active = pending;
    unawaited(_execute(pending));
  }

  Future<void> _execute(_TerminalAppleScriptPendingCommand pending) async {
    TerminalAppleScriptCommandResult result;
    try {
      result = await _executor
          .execute(pending.request)
          .timeout(
            commandTimeout,
            onTimeout: () => _result(
              pending.request,
              TerminalAppleScriptCommandDisposition.timedOut,
            ),
          );
      if (result.operationId != pending.request.operationId) {
        result = _result(
          pending.request,
          TerminalAppleScriptCommandDisposition.failed,
        );
      }
    } on Object {
      result = _result(
        pending.request,
        TerminalAppleScriptCommandDisposition.failed,
      );
    }
    if (identical(_active, pending)) _active = null;
    _complete(pending, result);
    _drain();
  }

  static TerminalAppleScriptCommandResult _result(
    TerminalAppleScriptCommandRequest request,
    TerminalAppleScriptCommandDisposition disposition,
  ) => TerminalAppleScriptCommandResult(
    operationId: request.operationId,
    disposition: disposition,
  );

  static void _complete(
    _TerminalAppleScriptPendingCommand pending,
    TerminalAppleScriptCommandResult result,
  ) {
    if (!pending.completer.isCompleted) pending.completer.complete(result);
  }
}

final class _TerminalAppleScriptPendingCommand {
  _TerminalAppleScriptPendingCommand(this.request);

  final TerminalAppleScriptCommandRequest request;
  final Completer<TerminalAppleScriptCommandResult> completer =
      Completer<TerminalAppleScriptCommandResult>();
}

void _requireKind(
  TerminalAppleScriptObjectId value,
  TerminalAppleScriptObjectKind expected,
  String name,
) {
  if (value.kind != expected) {
    throw ArgumentError.value(value, name, 'must be a ${expected.name} ID');
  }
}

void _requireUnique(Iterable<TerminalAppleScriptObjectId> values, String name) {
  final Set<TerminalAppleScriptObjectId> ids = <TerminalAppleScriptObjectId>{};
  for (final TerminalAppleScriptObjectId value in values) {
    if (!ids.add(value)) throw ArgumentError('duplicate $name ID: $value');
  }
}

void _requireDisplayText(
  String value,
  String name,
  int maximumUtf8Bytes, {
  required bool allowEmpty,
}) {
  if (!allowEmpty && value.isEmpty ||
      !TerminalSessionMetadata.isSafeDisplayText(
        value,
        maximumUtf8Bytes: maximumUtf8Bytes,
      )) {
    throw ArgumentError.value(value, name, 'must be bounded safe text');
  }
}

void _requireWorkingDirectory(String value) {
  if (!value.startsWith('/') ||
      !_utf8LengthWithin(
        value,
        TerminalAppleScriptLimits.maximumWorkingDirectoryUtf8Bytes,
      )) {
    throw ArgumentError.value(
      value,
      'workingDirectory',
      'must be a bounded absolute POSIX path',
    );
  }
  for (final int scalar in value.runes) {
    if (scalar <= 0x1f || scalar == 0x7f) {
      throw ArgumentError.value(
        value,
        'workingDirectory',
        'must not contain control characters',
      );
    }
  }
}

bool _utf8LengthWithin(String value, int maximum) {
  var bytes = 0;
  for (var index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    if (unit <= 0x7f) {
      bytes++;
    } else if (unit <= 0x7ff) {
      bytes += 2;
    } else if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) return false;
      final int second = value.codeUnitAt(index);
      if (second < 0xdc00 || second > 0xdfff) return false;
      bytes += 4;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    } else {
      bytes += 3;
    }
    if (bytes > maximum) return false;
  }
  return true;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String name) {
  if (value is! List<Object?>) throw FormatException('$name must be a list');
  return value;
}

String _string(Object? value, String name) {
  if (value is! String) throw FormatException('$name must be text');
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw FormatException('$name must be an integer');
  return value;
}

bool _boolean(Object? value, String name) {
  if (value is! bool) throw FormatException('$name must be a boolean');
  return value;
}

void _exactKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException(
      'AppleScript snapshot has unknown or missing keys',
    );
  }
}
