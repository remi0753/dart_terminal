import 'dart:async';
import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_appkit_policy.dart';
import 'terminal_localization.dart';
import 'terminal_update_feed.dart';

enum TerminalUpdateStatus {
  notConfigured,
  idle,
  checking,
  available,
  upToDate,
  installing,
  restartRequired,
  cancelled,
  failed,
  disposed,
}

enum TerminalUpdateOperationDisposition {
  completed,
  notConfigured,
  busy,
  unavailable,
  cancelled,
  failed,
}

final class TerminalUpdateOperationResult {
  const TerminalUpdateOperationResult(this.disposition);

  final TerminalUpdateOperationDisposition disposition;
}

abstract interface class TerminalUpdateProductService {
  Future<TerminalUpdateRelease?> check();

  Future<void> prepareInstall(TerminalUpdateRelease release);

  void cancel();

  FutureOr<void> dispose();
}

typedef TerminalUpdateStatusListener = void Function();

final class TerminalUpdateController {
  TerminalUpdateController({TerminalUpdateProductService? service})
    : _service = service,
      _status = service == null
          ? TerminalUpdateStatus.notConfigured
          : TerminalUpdateStatus.idle;

  static const int maximumListeners = 8;

  final TerminalUpdateProductService? _service;
  final Set<TerminalUpdateStatusListener> _listeners =
      <TerminalUpdateStatusListener>{};
  TerminalUpdateStatus _status;
  TerminalUpdateRelease? _release;
  var _operationGeneration = 0;
  var _operationInProgress = false;
  var _isDisposed = false;

  TerminalUpdateStatus get status => _status;
  TerminalUpdateRelease? get release => _release;
  bool get isConfigured => _service != null;
  bool get isDisposed => _isDisposed;
  bool get operationInProgress => _operationInProgress;
  bool get canInstall =>
      !_isDisposed &&
      !_operationInProgress &&
      _status == TerminalUpdateStatus.available &&
      _release != null;

  void addListener(TerminalUpdateStatusListener listener) {
    _ensureAlive();
    if (!_listeners.contains(listener) &&
        _listeners.length >= maximumListeners) {
      throw StateError('terminal update listener limit exceeded');
    }
    _listeners.add(listener);
  }

  void removeListener(TerminalUpdateStatusListener listener) {
    _listeners.remove(listener);
  }

  Future<TerminalUpdateOperationResult> check() async {
    if (_isDisposed) {
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.unavailable,
      );
    }
    final TerminalUpdateProductService? service = _service;
    if (service == null) {
      _setStatus(TerminalUpdateStatus.notConfigured, release: null);
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.notConfigured,
      );
    }
    if (_operationInProgress) {
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.busy,
      );
    }
    final int generation = ++_operationGeneration;
    _operationInProgress = true;
    _setStatus(TerminalUpdateStatus.checking, release: null);
    try {
      final TerminalUpdateRelease? release = await service.check();
      if (_isDisposed || generation != _operationGeneration) {
        return const TerminalUpdateOperationResult(
          TerminalUpdateOperationDisposition.cancelled,
        );
      }
      _setStatus(
        release == null
            ? TerminalUpdateStatus.upToDate
            : TerminalUpdateStatus.available,
        release: release,
      );
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.completed,
      );
    } on Object {
      if (_isDisposed || generation != _operationGeneration) {
        return const TerminalUpdateOperationResult(
          TerminalUpdateOperationDisposition.cancelled,
        );
      }
      _setStatus(TerminalUpdateStatus.failed, release: null);
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.failed,
      );
    } finally {
      if (generation == _operationGeneration) {
        _operationInProgress = false;
        _notify();
      }
    }
  }

  Future<TerminalUpdateOperationResult> install() async {
    if (_isDisposed) {
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.unavailable,
      );
    }
    if (_operationInProgress) {
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.busy,
      );
    }
    final TerminalUpdateProductService? service = _service;
    final TerminalUpdateRelease? selected = _release;
    if (service == null || selected == null || !canInstall) {
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.unavailable,
      );
    }
    final int generation = ++_operationGeneration;
    _operationInProgress = true;
    _setStatus(TerminalUpdateStatus.installing, release: selected);
    try {
      await service.prepareInstall(selected);
      if (_isDisposed || generation != _operationGeneration) {
        return const TerminalUpdateOperationResult(
          TerminalUpdateOperationDisposition.cancelled,
        );
      }
      _setStatus(TerminalUpdateStatus.restartRequired, release: selected);
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.completed,
      );
    } on Object {
      if (_isDisposed || generation != _operationGeneration) {
        return const TerminalUpdateOperationResult(
          TerminalUpdateOperationDisposition.cancelled,
        );
      }
      _setStatus(TerminalUpdateStatus.failed, release: null);
      return const TerminalUpdateOperationResult(
        TerminalUpdateOperationDisposition.failed,
      );
    } finally {
      if (generation == _operationGeneration) {
        _operationInProgress = false;
        _notify();
      }
    }
  }

  void cancel() {
    if (_isDisposed || !_operationInProgress) return;
    _operationGeneration++;
    _operationInProgress = false;
    _service?.cancel();
    _setStatus(TerminalUpdateStatus.cancelled, release: null);
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    if (_operationInProgress) {
      _service?.cancel();
    }
    _operationGeneration++;
    _operationInProgress = false;
    _release = null;
    _isDisposed = true;
    _status = TerminalUpdateStatus.disposed;
    _notify();
    _listeners.clear();
    await _service?.dispose();
  }

  String machineLine() =>
      'TERMINAL_UPDATE status=${_status.name} configured=$isConfigured '
      'busy=$_operationInProgress available=${_release != null} '
      'notes=${_release?.releaseNotes.length ?? 0}';

  void _setStatus(
    TerminalUpdateStatus value, {
    required TerminalUpdateRelease? release,
  }) {
    _status = value;
    _release = release;
    _notify();
  }

  void _notify() {
    for (final TerminalUpdateStatusListener listener in _listeners.toList(
      growable: false,
    )) {
      try {
        listener();
      } on Object {
        // UI listeners are advisory and cannot change update authority.
      }
    }
  }

  void _ensureAlive() {
    if (_isDisposed) throw StateError('terminal update controller is disposed');
  }
}

final class TerminalUpdateFocusTarget {
  const TerminalUpdateFocusTarget({required this.window, required this.view});

  final Window window;
  final View view;

  bool get isAvailable =>
      !window.isClosed && !window.isDisposed && !view.isDisposed;
}

typedef TerminalUpdateFocusTargetProvider =
    TerminalUpdateFocusTarget? Function();

final class TerminalUpdatePresenter {
  TerminalUpdatePresenter({
    required this.controller,
    required TerminalUpdateFocusTargetProvider focusTarget,
    TerminalLocalization? localization,
    this.onError,
  }) : _focusTarget = focusTarget,
       _localization = localization ?? TerminalLocalization.english;

  static const int maximumRenderedUtf8Bytes = 32 * 1024;

  final TerminalUpdateController controller;
  final TerminalUpdateFocusTargetProvider _focusTarget;
  final TerminalLocalization _localization;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  var _terminalResponderRestoreCount = 0;
  var _isDisposed = false;

  bool get isOpen => _window != null;
  bool get isDisposed => _isDisposed;
  String? get renderedText => _view?.text;
  Window? get activeWindow => _window;
  TextView? get activeView => _view;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;

  Future<TerminalUpdateOperationResult> openAndCheck() async {
    await open();
    final TerminalUpdateOperationResult result = await controller.check();
    _render();
    return result;
  }

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_isDisposed) throw StateError('terminal update presenter is disposed');
    final Window? existing = _window;
    if (existing != null) {
      _render();
      existing.show();
      final TextView? view = _view;
      if (view != null) existing.makeFirstResponder(view);
      return;
    }
    final TextView view = TextView(
      configuration: terminalUpdateTextViewConfiguration,
    );
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      window = Window(
        frame: const Rect.fromLTWH(210, 150, 660, 460),
        title: _localization.updateWindowTitle,
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
      controller.addListener(_render);
      _render();
      window
        ..show()
        ..makeFirstResponder(view);
    } on Object {
      controller.removeListener(_render);
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) window.close();
        window.dispose();
      }
      if (!view.isDisposed) view.dispose();
      _window = null;
      _view = null;
      _subscription = null;
      rethrow;
    }
  }

  Future<void> dismiss() =>
      _close(restoreTerminalFocus: true, closeWindow: true);

  Future<void> dispose() async {
    if (_isDisposed) {
      await (_closingFuture ?? Future<void>.value());
      return;
    }
    _isDisposed = true;
    await _close(restoreTerminalFocus: false, closeWindow: true);
    await controller.dispose();
  }

  Future<void> _invokeDefaultAction() async {
    if (controller.canInstall) {
      await controller.install();
    } else {
      await controller.check();
    }
    _render();
  }

  void _render() {
    final TextView? view = _view;
    if (view == null || view.isDisposed) return;
    final StringBuffer text = StringBuffer()
      ..writeln(_localization.updateWindowTitle)
      ..writeln()
      ..writeln(_localization.updateStatus(controller.status.name));
    final TerminalUpdateRelease? release = controller.release;
    if (release != null) {
      text
        ..writeln()
        ..writeln(
          _localization.updateVersion(
            release.version.toString(),
            release.build,
          ),
        )
        ..writeln()
        ..writeln(_localization.updateReleaseNotesTitle);
      if (release.releaseNotes.isEmpty) {
        text.writeln(_localization.updateNoReleaseNotes);
      } else {
        for (final String line in release.releaseNotes) {
          text.writeln('• $line');
        }
      }
    }
    text
      ..writeln()
      ..writeln(
        _localization.updateInstructions(canInstall: controller.canInstall),
      );
    final String rendered = text.toString();
    view.text = utf8.encode(rendered).length <= maximumRenderedUtf8Bytes
        ? rendered
        : '${_localization.updateStatus('failed')}\n';
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case AppKitKeyEvent(:final kind, :final keyCode):
        if (kind != AppKitKeyEventKind.down) break;
        if (keyCode == 53) {
          unawaited(dismiss());
        } else if (keyCode == 36) {
          unawaited(_invokeDefaultAction());
        }
      case WindowCloseRequestedEvent():
        final Window? window = _window;
        if (window != null && !window.isClosed && !window.isDisposed) {
          window.replyToCloseRequest(event, allow: false);
        }
        unawaited(dismiss());
      case WindowClosedEvent():
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
        controller.cancel();
        controller.removeListener(_render);
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
          final TerminalUpdateFocusTarget? target = _availableTarget();
          if (target != null) {
            target.window
              ..show()
              ..makeFirstResponder(target.view);
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

  TerminalUpdateFocusTarget? _availableTarget() {
    try {
      final TerminalUpdateFocusTarget? target = _focusTarget();
      return target != null && target.isAvailable ? target : null;
    } on Object {
      return null;
    }
  }
}
