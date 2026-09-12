import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_appkit_policy.dart';
import 'terminal_core/vt_parser_inspector.dart';
import 'terminal_diagnostics.dart';
import 'terminal_localization.dart';

typedef TerminalDiagnosticsSnapshotReader =
    TerminalDiagnosticsSnapshot Function();
typedef TerminalDiagnosticsCaptureStarter = void Function(
  VtParserInspectionObserver observer,
);
typedef TerminalDiagnosticsCaptureStopper = void Function();

/// One currently focused live product pane without exposing its content.
final class TerminalDiagnosticsFocusTarget {
  const TerminalDiagnosticsFocusTarget({
    required this.identity,
    required this.window,
    required this.view,
    required this.isLive,
    required this.beginCapture,
    required this.endCapture,
    required this.snapshot,
  });

  final Object identity;
  final Window window;
  final View view;
  final bool Function() isLive;
  final TerminalDiagnosticsCaptureStarter beginCapture;
  final TerminalDiagnosticsCaptureStopper endCapture;
  final TerminalDiagnosticsSnapshotReader snapshot;

  bool get isAvailable =>
      isLive() && !window.isClosed && !window.isDisposed && !view.isDisposed;
}

typedef TerminalDiagnosticsFocusTargetProvider =
    TerminalDiagnosticsFocusTarget? Function();

enum TerminalDiagnosticsPresentationExportDisposition {
  written,
  cancelled,
  unavailable,
  nativeFailure,
  encodingFailure,
  writeFailure,
}

/// Path-free outcome retained by the product UI and acceptance evidence.
final class TerminalDiagnosticsPresentationExportResult {
  const TerminalDiagnosticsPresentationExportResult(
    this.disposition, {
    this.byteCount = 0,
  });

  final TerminalDiagnosticsPresentationExportDisposition disposition;
  final int byteCount;

  bool get isSuccess =>
      disposition == TerminalDiagnosticsPresentationExportDisposition.written ||
      disposition == TerminalDiagnosticsPresentationExportDisposition.cancelled;
}

typedef TerminalDiagnosticsPresentationExportObserver = void Function(
  TerminalDiagnosticsPresentationExportResult result,
);
typedef TerminalDiagnosticsPresentationErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Owns the single read-only inspector window and explicit local export flow.
final class TerminalDiagnosticsPresenter {
  TerminalDiagnosticsPresenter({
    required this.application,
    required TerminalDiagnosticsFocusTargetProvider focusTarget,
    TerminalLocalization? localization,
    TerminalDiagnosticsFormatter formatter =
        const TerminalDiagnosticsFormatter(),
    TerminalDiagnosticsAtomicWriter? writer,
    this.onExported,
    this.onError,
  }) : _focusTarget = focusTarget,
       _localization = localization ?? TerminalLocalization.english,
       _formatter = formatter,
       _writer = writer ?? TerminalDiagnosticsAtomicWriter();

  final AppKitApplication application;
  final TerminalDiagnosticsFocusTargetProvider _focusTarget;
  final TerminalLocalization _localization;
  final TerminalDiagnosticsFormatter _formatter;
  final TerminalDiagnosticsAtomicWriter _writer;
  final TerminalDiagnosticsPresentationExportObserver? onExported;
  final TerminalDiagnosticsPresentationErrorObserver? onError;

  Window? _window;
  TextView? _view;
  StreamSubscription<WindowEvent>? _subscription;
  TerminalDiagnosticsFocusTarget? _capturedTarget;
  Future<void>? _closingFuture;
  TerminalDiagnosticsPresentationExportResult? _lastExportResult;
  int _captureHandoffCount = 0;
  int _terminalResponderRestoreCount = 0;
  int _refreshEpoch = 0;
  bool _refreshScheduled = false;
  bool _isDisposed = false;

  bool get isOpen => _window != null;
  bool get isDisposed => _isDisposed;
  bool get hasAvailableTarget => _availableTarget() != null;
  Window? get activeWindow => _window;
  TextView? get activeView => _view;
  String? get renderedText => _view?.text;
  Object? get capturedTargetIdentity => _capturedTarget?.identity;
  int get captureHandoffCount => _captureHandoffCount;
  int get terminalResponderRestoreCount => _terminalResponderRestoreCount;
  TerminalDiagnosticsPresentationExportResult? get lastExportResult =>
      _lastExportResult;

  Future<void> open() async {
    final Future<void>? closing = _closingFuture;
    if (closing != null) await closing;
    if (_isDisposed) {
      throw StateError('terminal diagnostics presenter is disposed');
    }
    final TerminalDiagnosticsFocusTarget target =
        _availableTarget() ??
        (throw StateError('focused terminal diagnostics are unavailable'));
    final Window? existing = _window;
    if (existing != null) {
      _synchronizeTarget(target);
      _render();
      existing.show();
      final TextView? view = _view;
      if (view != null) existing.makeFirstResponder(view);
      return;
    }

    final TextView view = TextView(
      configuration: terminalDiagnosticsTextViewConfiguration,
    );
    Window? window;
    StreamSubscription<WindowEvent>? subscription;
    try {
      _synchronizeTarget(target);
      window = Window(
        frame: const Rect.fromLTWH(170, 100, 820, 680),
        title: _localization.terminalInspectorWindowTitle,
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
      _render();
      window
        ..show()
        ..makeFirstResponder(view);
    } on Object {
      _stopCapture();
      unawaited(subscription?.cancel());
      if (window != null && !window.isDisposed) {
        if (!window.isClosed) window.close();
        window.dispose();
      }
      if (!view.isDisposed) view.dispose();
      _view = null;
      _window = null;
      _subscription = null;
      rethrow;
    }
  }

  /// Follows hierarchy focus while the inspector is open.
  void synchronizeFocus() {
    if (_isDisposed || _window == null) return;
    final TerminalDiagnosticsFocusTarget? target = _availableTarget();
    if (target == null) {
      _stopCapture();
      _renderUnavailable();
      return;
    }
    _synchronizeTarget(target);
    _render();
  }

  void refresh() {
    if (_isDisposed || _window == null) return;
    synchronizeFocus();
  }

  Future<TerminalDiagnosticsPresentationExportResult> export() async {
    if (_isDisposed) {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.unavailable,
        ),
      );
    }
    final TerminalDiagnosticsFocusTarget? target = _availableTarget();
    if (target == null) {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.unavailable,
        ),
      );
    }

    late final Uint8List encoded;
    try {
      encoded = _formatter.encode(target.snapshot());
    } on Object {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.encodingFailure,
        ),
      );
    }

    SavePanelResult selection;
    try {
      selection = application.chooseSaveDestination(
        SavePanelConfiguration(
          title: _localization.diagnosticsSavePanelTitle,
          message: _localization.diagnosticsSavePanelMessage,
          prompt: _localization.diagnosticsSavePanelPrompt,
          defaultFileName: _localization.diagnosticsDefaultFileName,
          allowedFileExtension: 'json',
        ),
      );
    } on Object {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.nativeFailure,
        ),
      );
    }
    if (!selection.isSelected) {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.cancelled,
        ),
      );
    }
    final String? destinationPath = selection.path;
    if (destinationPath == null) {
      return _publishExport(
        const TerminalDiagnosticsPresentationExportResult(
          TerminalDiagnosticsPresentationExportDisposition.nativeFailure,
        ),
      );
    }
    final TerminalDiagnosticsExportResult result = await _writer.write(
      destinationPath: destinationPath,
      bytes: encoded,
    );
    return _publishExport(
      result.disposition == TerminalDiagnosticsExportDisposition.written
          ? TerminalDiagnosticsPresentationExportResult(
              TerminalDiagnosticsPresentationExportDisposition.written,
              byteCount: result.byteCount,
            )
          : const TerminalDiagnosticsPresentationExportResult(
              TerminalDiagnosticsPresentationExportDisposition.writeFailure,
            ),
    );
  }

  Future<void> dismiss() =>
      _close(restoreTerminalFocus: true, closeWindow: true);

  Future<void> dispose() {
    if (_isDisposed) return _closingFuture ?? Future<void>.value();
    _isDisposed = true;
    return _close(restoreTerminalFocus: false, closeWindow: true);
  }

  void _synchronizeTarget(TerminalDiagnosticsFocusTarget target) {
    final TerminalDiagnosticsFocusTarget? previous = _capturedTarget;
    if (previous?.identity == target.identity) return;
    _stopCapture();
    target.beginCapture(_handleParserEvent);
    _capturedTarget = target;
    _captureHandoffCount++;
  }

  void _handleParserEvent(VtParserInspectionEvent _) {
    if (_window == null || _isDisposed || _refreshScheduled) return;
    _refreshScheduled = true;
    final int epoch = _refreshEpoch;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (_window == null || _isDisposed || epoch != _refreshEpoch) return;
      try {
        synchronizeFocus();
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }

  void _stopCapture() {
    final TerminalDiagnosticsFocusTarget? target = _capturedTarget;
    _capturedTarget = null;
    _refreshEpoch++;
    _refreshScheduled = false;
    target?.endCapture();
  }

  void _render() {
    final TextView? view = _view;
    final TerminalDiagnosticsFocusTarget? target = _capturedTarget;
    if (view == null || view.isDisposed) return;
    if (target == null || !target.isAvailable) {
      _renderUnavailable();
      return;
    }
    final String diagnostics = _formatter.formatInspector(target.snapshot());
    final String instructions =
        '\n${_localization.terminalInspectorInstructions}\n';
    view.text =
        utf8.encode(diagnostics).length + utf8.encode(instructions).length <=
            TerminalDiagnosticsFormatter.maximumInspectorTextUtf8Bytes
        ? '$diagnostics$instructions'
        : diagnostics;
  }

  void _renderUnavailable() {
    final TextView? view = _view;
    if (view == null || view.isDisposed) return;
    view.text =
        '${_localization.terminalInspectorUnavailable}\n\n'
        '${_localization.terminalInspectorInstructions}\n';
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
        final StreamSubscription<WindowEvent>? subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
        _stopCapture();
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
          final TerminalDiagnosticsFocusTarget? target = _availableTarget();
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

  TerminalDiagnosticsFocusTarget? _availableTarget() {
    try {
      final TerminalDiagnosticsFocusTarget? target = _focusTarget();
      return target != null && target.isAvailable ? target : null;
    } on Object {
      return null;
    }
  }

  TerminalDiagnosticsPresentationExportResult _publishExport(
    TerminalDiagnosticsPresentationExportResult result,
  ) {
    _lastExportResult = result;
    onExported?.call(result);
    return result;
  }
}
