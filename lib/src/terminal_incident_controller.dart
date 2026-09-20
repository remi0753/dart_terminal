import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_appkit_policy.dart';
import 'terminal_incident_service.dart';
import 'terminal_localization.dart';

enum TerminalIncidentStatus {
  idle,
  discovering,
  exporting,
  exported,
  notFound,
  unavailable,
  sampling,
  sampled,
  cancelled,
  failed,
  disposed,
}

enum TerminalIncidentOperationDisposition {
  exported,
  sampled,
  cancelled,
  notFound,
  unavailable,
  failed,
  busy,
  disposed,
  nativeFailure,
}

/// Content-free result retained by the product action boundary.
final class TerminalIncidentOperationResult {
  const TerminalIncidentOperationResult(
    this.disposition, {
    this.matchingReportCount = 0,
  });

  final TerminalIncidentOperationDisposition disposition;
  final int matchingReportCount;
}

/// Fixed-state/count-only projection suitable for general diagnostics.
final class TerminalIncidentStatusSnapshot {
  const TerminalIncidentStatusSnapshot({
    required this.status,
    required this.matchingReportCount,
    required this.completedOperationCount,
    required this.unsuccessfulOperationCount,
  });

  final TerminalIncidentStatus status;
  final int matchingReportCount;
  final int completedOperationCount;
  final int unsuccessfulOperationCount;
}

typedef TerminalIncidentStatusListener = void Function();

/// Serializes explicit local incident operations and retains no raw metadata.
final class TerminalIncidentController {
  TerminalIncidentController({TerminalIncidentService? service})
    : _service = service ?? TerminalLocalIncidentService.standard();

  final TerminalIncidentService _service;
  final Set<TerminalIncidentStatusListener> _listeners =
      <TerminalIncidentStatusListener>{};
  TerminalIncidentStatus _status = TerminalIncidentStatus.idle;
  TerminalIncidentCancellation? _activeCancellation;
  int _matchingReportCount = 0;
  int _completedOperationCount = 0;
  int _failureCount = 0;
  int _generation = 0;
  bool _disposed = false;

  TerminalIncidentStatus get status => _status;
  bool get isBusy => _activeCancellation != null;
  bool get isDisposed => _disposed;
  bool get canStart => !_disposed && !isBusy;
  TerminalIncidentStatusSnapshot get snapshot => TerminalIncidentStatusSnapshot(
    status: _status,
    matchingReportCount: _matchingReportCount,
    completedOperationCount: _completedOperationCount,
    unsuccessfulOperationCount: _failureCount,
  );

  void addListener(TerminalIncidentStatusListener listener) {
    if (_disposed) throw StateError('incident controller is disposed');
    _listeners.add(listener);
  }

  void removeListener(TerminalIncidentStatusListener listener) {
    _listeners.remove(listener);
  }

  Future<TerminalIncidentOperationResult> exportLatestCrashReport(
    File destination,
  ) async {
    final _TerminalIncidentOperation? operation = _begin();
    if (operation == null) return _unavailableResult();
    try {
      _setStatus(TerminalIncidentStatus.discovering);
      final TerminalIncidentReportSelection selection = await _service
          .discoverLatestCrashReport(cancellation: operation.cancellation);
      if (!_isCurrent(operation)) return _cancelledResult();
      _matchingReportCount = selection.matchingReportCount.clamp(
        0,
        TerminalIncidentLimits.maximumAllowedMatchingReports,
      );
      switch (selection.availability) {
        case TerminalIncidentReportAvailability.notFound:
          _setStatus(TerminalIncidentStatus.notFound);
          return TerminalIncidentOperationResult(
            TerminalIncidentOperationDisposition.notFound,
            matchingReportCount: _matchingReportCount,
          );
        case TerminalIncidentReportAvailability.unavailable:
          _setStatus(TerminalIncidentStatus.unavailable);
          return TerminalIncidentOperationResult(
            TerminalIncidentOperationDisposition.unavailable,
            matchingReportCount: _matchingReportCount,
          );
        case TerminalIncidentReportAvailability.ready:
          break;
      }
      _setStatus(TerminalIncidentStatus.exporting);
      await _service.exportLatestCrashReport(
        selection,
        destination,
        cancellation: operation.cancellation,
      );
      if (!_isCurrent(operation)) return _cancelledResult();
      _completedOperationCount++;
      _setStatus(TerminalIncidentStatus.exported);
      return TerminalIncidentOperationResult(
        TerminalIncidentOperationDisposition.exported,
        matchingReportCount: _matchingReportCount,
      );
    } on TerminalIncidentException catch (error) {
      return _classifyFailure(operation, error);
    } on Object {
      return _classifyFailure(
        operation,
        const TerminalIncidentException('incident-operation-failed'),
      );
    } finally {
      _finish(operation);
    }
  }

  Future<TerminalIncidentOperationResult> captureHangSample(
    File destination,
  ) async {
    final _TerminalIncidentOperation? operation = _begin();
    if (operation == null) return _unavailableResult();
    try {
      _setStatus(TerminalIncidentStatus.sampling);
      await _service.captureHangSample(
        destination,
        cancellation: operation.cancellation,
      );
      if (!_isCurrent(operation)) return _cancelledResult();
      _completedOperationCount++;
      _setStatus(TerminalIncidentStatus.sampled);
      return const TerminalIncidentOperationResult(
        TerminalIncidentOperationDisposition.sampled,
      );
    } on TerminalIncidentException catch (error) {
      return _classifyFailure(operation, error);
    } on Object {
      return _classifyFailure(
        operation,
        const TerminalIncidentException('incident-operation-failed'),
      );
    } finally {
      _finish(operation);
    }
  }

  void cancel() {
    final TerminalIncidentCancellation? cancellation = _activeCancellation;
    if (cancellation == null) return;
    cancellation.cancel();
    _generation++;
    _activeCancellation = null;
    if (!_disposed) _setStatus(TerminalIncidentStatus.cancelled);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    _service.dispose();
    _status = TerminalIncidentStatus.disposed;
    _listeners.clear();
  }

  _TerminalIncidentOperation? _begin() {
    if (_disposed || _activeCancellation != null) return null;
    final TerminalIncidentCancellation cancellation =
        TerminalIncidentCancellation();
    final _TerminalIncidentOperation operation = _TerminalIncidentOperation(
      generation: ++_generation,
      cancellation: cancellation,
    );
    _activeCancellation = cancellation;
    return operation;
  }

  bool _isCurrent(_TerminalIncidentOperation operation) =>
      !_disposed &&
      operation.generation == _generation &&
      identical(_activeCancellation, operation.cancellation) &&
      !operation.cancellation.isCancelled;

  void _finish(_TerminalIncidentOperation operation) {
    if (operation.generation == _generation &&
        identical(_activeCancellation, operation.cancellation)) {
      _activeCancellation = null;
    }
  }

  TerminalIncidentOperationResult _classifyFailure(
    _TerminalIncidentOperation operation,
    TerminalIncidentException error,
  ) {
    if (!_isCurrent(operation) || error.code == 'operation-cancelled') {
      if (!_disposed && operation.generation == _generation) {
        _setStatus(TerminalIncidentStatus.cancelled);
      }
      return _cancelledResult();
    }
    _failureCount++;
    _setStatus(TerminalIncidentStatus.failed);
    return const TerminalIncidentOperationResult(
      TerminalIncidentOperationDisposition.failed,
    );
  }

  TerminalIncidentOperationResult _unavailableResult() =>
      TerminalIncidentOperationResult(
        _disposed
            ? TerminalIncidentOperationDisposition.disposed
            : TerminalIncidentOperationDisposition.busy,
      );

  static TerminalIncidentOperationResult _cancelledResult() =>
      const TerminalIncidentOperationResult(
        TerminalIncidentOperationDisposition.cancelled,
      );

  void _setStatus(TerminalIncidentStatus value) {
    if (_disposed) return;
    _status = value;
    for (final TerminalIncidentStatusListener listener in _listeners.toList(
      growable: false,
    )) {
      try {
        listener();
      } on Object {
        // Status listeners cannot alter operation ownership or classification.
      }
    }
  }
}

final class TerminalIncidentFocusTarget {
  const TerminalIncidentFocusTarget({required this.window, required this.view});

  final Window window;
  final View view;

  bool get isAvailable =>
      !window.isClosed && !window.isDisposed && !view.isDisposed;
}

typedef TerminalIncidentFocusTargetProvider =
    TerminalIncidentFocusTarget? Function();
typedef TerminalIncidentSaveDestinationChooser = SavePanelResult Function(
  SavePanelConfiguration configuration,
);

/// Owns explicit native consent and one content-free incident status window.
final class TerminalIncidentPresenter {
  TerminalIncidentPresenter({
    required this.application,
    required this.controller,
    required TerminalIncidentFocusTargetProvider focusTarget,
    TerminalLocalization? localization,
    TerminalIncidentSaveDestinationChooser? chooseSaveDestination,
    this.onVisibilityChanged,
    this.onError,
  }) : _focusTarget = focusTarget,
       _localization = localization ?? TerminalLocalization.english,
       _chooseSaveDestination =
           chooseSaveDestination ?? application.chooseSaveDestination;

  static const int maximumRenderedUtf8Bytes = 16 * 1024;

  final AppKitApplication application;
  final TerminalIncidentController controller;
  final TerminalIncidentFocusTargetProvider _focusTarget;
  final TerminalLocalization _localization;
  final TerminalIncidentSaveDestinationChooser _chooseSaveDestination;
  final void Function(bool isPresented)? onVisibilityChanged;
  final void Function(Object error, StackTrace stackTrace)? onError;

  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  Future<void>? _closingFuture;
  TerminalIncidentOperationResult? _lastOperationResult;
  int _terminalResponderRestoreCount = 0;
  int _presentationGeneration = 0;
  bool _disposed = false;

  bool get isOpen => _window != null;
  bool get isDisposed => _disposed;
  bool get canStart => !_disposed && controller.canStart;
  Window? get activeWindow => _window;
  TextView? get activeView => _view;
  String? get renderedText => _view?.text;
  TerminalIncidentOperationResult? get lastOperationResult =>
      _lastOperationResult;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;

  Future<TerminalIncidentOperationResult> exportLatestCrashReport() =>
      _runWithConsent(
        configuration: SavePanelConfiguration(
          title: _localization.incidentCrashSavePanelTitle,
          message: _localization.incidentCrashSavePanelMessage,
          prompt: _localization.incidentSavePanelPrompt,
          defaultFileName: _localization.incidentCrashDefaultFileName,
          allowedFileExtension: 'ips',
        ),
        operation: controller.exportLatestCrashReport,
      );

  Future<TerminalIncidentOperationResult> captureHangSample() =>
      _runWithConsent(
        configuration: SavePanelConfiguration(
          title: _localization.incidentSampleSavePanelTitle,
          message: _localization.incidentSampleSavePanelMessage,
          prompt: _localization.incidentSavePanelPrompt,
          defaultFileName: _localization.incidentSampleDefaultFileName,
          allowedFileExtension: 'txt',
        ),
        operation: controller.captureHangSample,
      );

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_disposed) throw StateError('incident presenter is disposed');
    final Window? existing = _window;
    if (existing != null) {
      _render();
      existing.show();
      final TextView? view = _view;
      if (view != null) existing.makeFirstResponder(view);
      return;
    }
    final TextView view = TextView(
      configuration: terminalIncidentTextViewConfiguration,
    );
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      window = Window(
        frame: const Rect.fromLTWH(240, 180, 620, 380),
        title: _localization.incidentWindowTitle,
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
      _window = window;
      _view = view;
      _subscription = subscription;
      _presentationGeneration++;
      controller.addListener(_render);
      _render();
      window
        ..show()
        ..makeFirstResponder(view);
      onVisibilityChanged?.call(true);
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
    if (_disposed) {
      await (_closingFuture ?? Future<void>.value());
      return;
    }
    _disposed = true;
    await _close(restoreTerminalFocus: false, closeWindow: true);
    controller.dispose();
  }

  Future<TerminalIncidentOperationResult> _runWithConsent({
    required SavePanelConfiguration configuration,
    required Future<TerminalIncidentOperationResult> Function(File destination)
    operation,
  }) async {
    if (_disposed) {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.disposed,
        ),
      );
    }
    if (!controller.canStart) {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.busy,
        ),
      );
    }
    final SavePanelResult selection;
    try {
      selection = _chooseSaveDestination(configuration);
    } on Object {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.nativeFailure,
        ),
      );
    }
    if (!selection.isSelected) {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.cancelled,
        ),
      );
    }
    final String? destination = selection.path;
    if (destination == null) {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.nativeFailure,
        ),
      );
    }
    try {
      await open();
    } on Object {
      return _publish(
        const TerminalIncidentOperationResult(
          TerminalIncidentOperationDisposition.nativeFailure,
        ),
      );
    }
    final int presentationGeneration = _presentationGeneration;
    final TerminalIncidentOperationResult result = await operation(
      File(destination),
    );
    if (_disposed ||
        _window == null ||
        presentationGeneration != _presentationGeneration) {
      return result;
    }
    _render();
    return _publish(result);
  }

  void _render() {
    final TextView? view = _view;
    if (view == null || view.isDisposed) return;
    final TerminalIncidentStatusSnapshot snapshot = controller.snapshot;
    final String text = <String>[
      _localization.incidentWindowTitle,
      '',
      _localization.incidentLocalOnlyNotice,
      '',
      _localization.incidentStatus(snapshot.status.name),
      _localization.incidentMatchingReports(snapshot.matchingReportCount),
      _localization.incidentCompletedOperations(
        snapshot.completedOperationCount,
      ),
      _localization.incidentFailures(snapshot.unsuccessfulOperationCount),
      '',
      _localization.incidentWindowInstructions,
      '',
    ].join('\n');
    view.text = utf8.encode(text).length <= maximumRenderedUtf8Bytes
        ? text
        : '${_localization.incidentStatus('failed')}\n';
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case AppKitKeyEvent(:final kind, :final keyCode):
        if (kind == AppKitKeyEventKind.down && keyCode == 53) {
          unawaited(dismiss());
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
        _presentationGeneration++;
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
          final TerminalIncidentFocusTarget? target = _availableTarget();
          if (target != null) {
            target.window
              ..show()
              ..makeFirstResponder(target.view);
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

  TerminalIncidentFocusTarget? _availableTarget() {
    try {
      final TerminalIncidentFocusTarget? target = _focusTarget();
      return target != null && target.isAvailable ? target : null;
    } on Object {
      return null;
    }
  }

  TerminalIncidentOperationResult _publish(
    TerminalIncidentOperationResult result,
  ) {
    _lastOperationResult = result;
    return result;
  }
}

final class _TerminalIncidentOperation {
  const _TerminalIncidentOperation({
    required this.generation,
    required this.cancellation,
  });

  final int generation;
  final TerminalIncidentCancellation cancellation;
}
