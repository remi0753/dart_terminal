import 'dart:async';
import 'dart:math' as math;

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_screen_set.dart';
import '../terminal_input/terminal_preedit.dart';
import '../terminal_pane.dart';
import 'frame_scheduler.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'metal_failure_recovery.dart';
import 'terminal_damage.dart';
import 'terminal_damage_transfer.dart';
import 'terminal_screen_metal_compositor.dart';

typedef TerminalLiveMetalSurfaceFatalError = void Function(
  Object error,
  StackTrace stackTrace,
);

typedef TerminalCaretGeometryPublisher = void Function(
  TerminalCaretRect rectangle,
);

final class TerminalCaretRect {
  const TerminalCaretRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is TerminalCaretRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

final class TerminalGridSize {
  const TerminalGridSize({required this.rows, required this.columns});

  final int rows;
  final int columns;
}

/// Content-free diagnostic state for the live product surface.
final class TerminalLiveMetalSurfaceSnapshot {
  const TerminalLiveMetalSurfaceSnapshot({
    required this.isDisposed,
    required this.usesMacosSystemMonospaceFont,
    required this.fontPointSize,
    required this.rows,
    required this.columns,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scale16_16,
    required this.lastAppliedDamageGeneration,
    required this.lastAcceptedModelRevision,
    required this.lastAcceptedFrameGeneration,
    required this.rendererGeneration,
    required this.atlasResourceGeneration,
    required this.frameBuildCount,
    required this.acceptedFrameCount,
    required this.pendingFrameCount,
    required this.liveAtlasPinCount,
    required this.hasScheduledWork,
  });

  final bool isDisposed;
  final bool usesMacosSystemMonospaceFont;
  final double fontPointSize;
  final int rows;
  final int columns;
  final int viewportWidth;
  final int viewportHeight;
  final int scale16_16;
  final int lastAppliedDamageGeneration;
  final int lastAcceptedModelRevision;
  final int lastAcceptedFrameGeneration;
  final int rendererGeneration;
  final int atlasResourceGeneration;
  final int frameBuildCount;
  final int acceptedFrameCount;
  final int pendingFrameCount;
  final int liveAtlasPinCount;
  final bool hasScheduledWork;
}

/// Owns the default live terminal screen-to-Metal relationship.
///
/// Notifications only retain newest scalar state and schedule one later drain;
/// AppKit callbacks never shape, rasterize, or submit synchronously.
final class TerminalLiveMetalSurface {
  factory TerminalLiveMetalSurface.attach({
    required TerminalSessionId sessionId,
    required TerminalScreenSet screenSet,
    required View view,
    required double logicalWidth,
    required double logicalHeight,
    double backingScaleFactor = 1,
    bool isVisible = false,
    bool isOccluded = true,
    bool automaticScheduling = true,
    TerminalLiveMetalSurfaceFatalError? onFatalError,
    TerminalCaretGeometryPublisher? onCaretGeometryChanged,
    TerminalMetalRendererConfig rendererConfig =
        const TerminalMetalRendererConfig(),
  }) {
    _validateViewport(logicalWidth, logicalHeight);
    final int scale16_16 = TerminalRasterBufferV1.scaleToFixed(
      backingScaleFactor,
    );
    final TerminalFontCatalog catalog = TerminalFontCatalog.open(
      family: defaultFontFamily,
      pointSize: defaultFontPointSize,
    );
    final TerminalShapingCache shapingCache = TerminalShapingCache(catalog);
    final TerminalGlyphAtlas atlas = TerminalGlyphAtlas(
      catalogGeneration: catalog.generation,
      scale: scale16_16 / 65536.0,
    );
    TerminalMetalRenderer? renderer;
    TerminalGlyphAtlasMetalBridge? bridge;
    try {
      renderer = TerminalMetalRenderer.open(config: rendererConfig);
      bridge = TerminalGlyphAtlasMetalBridge(atlas: atlas, renderer: renderer);
      if (bridge.synchronize() !=
          TerminalGlyphAtlasSyncDisposition.synchronized) {
        throw const TerminalMetalCompositionBackpressureException();
      }
      renderer.bindToView(view);
      final TerminalMetalRendererRecoveryDomain domain =
          TerminalMetalRendererRecoveryDomain.active(
            renderer: renderer,
            bridge: bridge,
            view: view,
          );
      return TerminalLiveMetalSurface._(
        sessionId: sessionId,
        screenSet: screenSet,
        view: view,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        backingScaleFactor: backingScaleFactor,
        isVisible: isVisible,
        isOccluded: isOccluded,
        automaticScheduling: automaticScheduling,
        onFatalError: onFatalError,
        onCaretGeometryChanged: onCaretGeometryChanged,
        rendererConfig: rendererConfig,
        catalog: catalog,
        shapingCache: shapingCache,
        atlas: atlas,
        initialDomain: domain,
      );
    } on Object {
      bridge?.abandonRenderer();
      if (renderer != null && !renderer.isDisposed) renderer.dispose();
      shapingCache.dispose();
      catalog.dispose();
      rethrow;
    }
  }

  TerminalLiveMetalSurface._({
    required this.sessionId,
    required this.screenSet,
    required this.view,
    required double logicalWidth,
    required double logicalHeight,
    required double backingScaleFactor,
    required bool isVisible,
    required bool isOccluded,
    required this.automaticScheduling,
    required this.onFatalError,
    required this.onCaretGeometryChanged,
    required this.rendererConfig,
    required TerminalFontCatalog catalog,
    required TerminalShapingCache shapingCache,
    required this.atlas,
    required TerminalMetalRendererRecoveryDomain initialDomain,
  }) : _catalog = catalog,
       _shapingCache = shapingCache,
       _logicalWidth = logicalWidth,
       _logicalHeight = logicalHeight,
       _desiredScale = backingScaleFactor,
       _publishedScale = backingScaleFactor,
       _desiredVisible = isVisible,
       _desiredOccluded = isOccluded,
       _boundScreen = screenSet.activeScreen,
       _outbox = TerminalDamageOutbox(
         sessionId: sessionId,
         screen: screenSet.activeScreen,
       ) {
    _updatePixelViewport();
    late final TerminalMetalFailureRecoveryCoordinator<
      TerminalMetalRendererRecoveryDomain
    >
    recovery;
    late final TerminalNewestFrameScheduler<TerminalScheduledMetalFrame>
    scheduler;
    scheduler = TerminalNewestFrameScheduler<TerminalScheduledMetalFrame>(
      model: TerminalDamageRenderModel(),
      buildFrame:
          (
            TerminalDamageRenderModel model, {
            required int modelRevision,
            required int frameGeneration,
            required TerminalFramePresentation presentation,
          }) =>
              TerminalScreenMetalCompositor(
                    catalog: _catalog,
                    shapingCache: _shapingCache,
                    atlas: atlas,
                    bridge: recovery.currentDomain.bridge,
                    styleTable: screenSet.styleTable,
                    palette: screenSet.palette,
                    graphemeTable: screenSet.graphemeTable,
                  )
                  .compose(
                    model,
                    frameGeneration: frameGeneration,
                    viewportWidth: _viewportWidth,
                    viewportHeight: _viewportHeight,
                    presentation: presentation,
                    preedit: _preeditLayoutForModel(model),
                  )
                  .scheduledFrame,
      submitFrame:
          (
            TerminalScheduledMetalFrame frame, {
            required int modelRevision,
            required int frameGeneration,
          }) =>
              TerminalMetalFrameSubmissionAdapter(recovery.currentDomain.bridge)
                  .submit(
                    frame,
                    modelRevision: modelRevision,
                    frameGeneration: frameGeneration,
                  ),
    );
    recovery = TerminalMetalFailureRecoveryCoordinator(
      initialDomain: initialDomain,
      prepareReplacement: () => TerminalMetalRendererRecoveryDomain.prepare(
        atlas: atlas,
        config: rendererConfig,
        view: view,
      ),
      requestFullDamage: () {
        _boundScreen.requestFullSnapshot();
        _needsDrain = true;
      },
      requestFullRedraw: () {
        if (scheduler.model.isInitialized) scheduler.requestFullRedraw();
        _needsDrain = true;
      },
    );
    _scheduler = scheduler;
    _recovery = recovery;
    _needsDrain = true;
    _publishCaretGeometry(force: true);
    _scheduleImmediate();
  }

  static const Duration retryInterval = Duration(milliseconds: 16);
  static const int minimumRows = 4;
  static const int minimumColumns = 20;

  /// Empty family delegates face selection to AppKit's system monospace API.
  static const String defaultFontFamily = '';

  /// Product-owned readable zero-config size for the macOS system monospace.
  static const double defaultFontPointSize = 14;

  final TerminalSessionId sessionId;
  final TerminalScreenSet screenSet;
  final View view;
  final bool automaticScheduling;
  final TerminalLiveMetalSurfaceFatalError? onFatalError;
  final TerminalCaretGeometryPublisher? onCaretGeometryChanged;
  final TerminalMetalRendererConfig rendererConfig;
  final TerminalGlyphAtlas atlas;
  final Stopwatch _clock = Stopwatch()..start();
  final TerminalDamageOutbox _outbox;
  final TerminalPreeditModel _preeditModel = TerminalPreeditModel();
  late final TerminalNewestFrameScheduler<TerminalScheduledMetalFrame>
  _scheduler;
  late final TerminalMetalFailureRecoveryCoordinator<
    TerminalMetalRendererRecoveryDomain
  >
  _recovery;
  TerminalFontCatalog _catalog;
  TerminalShapingCache _shapingCache;
  TerminalScreen _boundScreen;
  double _logicalWidth;
  double _logicalHeight;
  double _desiredScale;
  double _publishedScale;
  late int _viewportWidth;
  late int _viewportHeight;
  bool _desiredVisible;
  bool _desiredOccluded;
  bool _publishedVisible = true;
  bool _publishedOccluded = false;
  bool _needsDrain = false;
  bool _retryRequested = false;
  bool _processing = false;
  bool _disposed = false;
  int _lastMonotonicMicros = 0;
  TerminalCaretRect? _lastPublishedCaretRect;
  Timer? _timer;

  bool get isDisposed => _disposed;
  TerminalFontCatalogMetrics get fontMetrics => _catalog.metrics;
  TerminalPreeditState get preeditState => _preeditModel.state;

  bool updatePreedit({
    required int generation,
    required String text,
    required int selectionLocation,
    required int selectionLength,
  }) {
    _requireLive();
    final bool changed = _preeditModel.update(
      generation: generation,
      text: text,
      selectionLocation: selectionLocation,
      selectionLength: selectionLength,
    );
    if (!changed) return false;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _publishCaretGeometry();
    _scheduleImmediate();
    return true;
  }

  bool clearPreedit({required int generation}) {
    _requireLive();
    final bool changed = _preeditModel.clear(generation: generation);
    if (!changed) return false;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _publishCaretGeometry();
    _scheduleImmediate();
    return true;
  }

  TerminalCaretRect caretRect() {
    _requireLive();
    return _currentCaretRect();
  }

  TerminalGridSize gridSizeFor({
    required double logicalWidth,
    required double logicalHeight,
  }) {
    _requireLive();
    _validateViewport(logicalWidth, logicalHeight);
    final double maximumLogicalWidth =
        rendererConfig.maximumViewportWidth / _desiredScale;
    final double maximumLogicalHeight =
        rendererConfig.maximumViewportHeight / _desiredScale;
    final int columns =
        (math.min(logicalWidth, maximumLogicalWidth) /
                _catalog.metrics.cellWidth)
            .floor()
            .clamp(minimumColumns, TerminalScreen.maxColumns);
    final int rows =
        (math.min(logicalHeight, maximumLogicalHeight) /
                _catalog.metrics.cellHeight)
            .floor()
            .clamp(minimumRows, TerminalScreen.maxRows);
    if (rows * columns > TerminalScreen.maxCellCount) {
      return TerminalGridSize(
        rows: math.max(minimumRows, TerminalScreen.maxCellCount ~/ columns),
        columns: columns,
      );
    }
    return TerminalGridSize(rows: rows, columns: columns);
  }

  TerminalGridSize resizeViewport({
    required double logicalWidth,
    required double logicalHeight,
  }) {
    final TerminalGridSize size = gridSizeFor(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
    );
    if (_logicalWidth != logicalWidth || _logicalHeight != logicalHeight) {
      _logicalWidth = logicalWidth;
      _logicalHeight = logicalHeight;
      _updatePixelViewport();
      _needsDrain = true;
      _publishCaretGeometry();
      _scheduleImmediate();
    }
    return size;
  }

  void updateBackingScale(double backingScaleFactor) {
    _requireLive();
    TerminalRasterBufferV1.scaleToFixed(backingScaleFactor);
    if (_desiredScale == backingScaleFactor) return;
    _desiredScale = backingScaleFactor;
    _needsDrain = true;
    _scheduleImmediate();
  }

  void updateWindowState({bool? isVisible, bool? isOccluded}) {
    _requireLive();
    final bool nextVisible = isVisible ?? _desiredVisible;
    final bool nextOccluded = isOccluded ?? _desiredOccluded;
    if (nextVisible == _desiredVisible && nextOccluded == _desiredOccluded) {
      return;
    }
    _desiredVisible = nextVisible;
    _desiredOccluded = nextOccluded;
    _needsDrain = true;
    _scheduleImmediate();
  }

  void notifyScreenChanged() {
    _requireLive();
    _needsDrain = true;
    _publishCaretGeometry();
    _scheduleImmediate();
  }

  /// Advances one bounded coalesced render turn outside AppKit callbacks.
  void processPending({int? monotonicMicros}) {
    _requireLive();
    if (_processing) {
      _needsDrain = true;
      return;
    }
    final int now = monotonicMicros ?? _clock.elapsedMicroseconds;
    if (now < _lastMonotonicMicros) {
      throw StateError('live Metal surface monotonic time regressed');
    }
    _lastMonotonicMicros = now;
    _processing = true;
    _timer?.cancel();
    _timer = null;
    _retryRequested = false;
    try {
      _publishWindowState(now);
      if (!_retireAndRecover()) {
        _retryRequested = true;
        return;
      }
      if (!_publishScaleIfReady()) {
        _retryRequested = true;
        return;
      }
      _rebindCurrentScreen();
      _applyNewestDamage(now);
      _scheduler.advancePresentation(monotonicMicros: now);
      _submitNewest();
      _needsDrain = _outbox.hasPendingDamage;
    } on TerminalMetalCompositionBackpressureException {
      _retryRequested = true;
    } on TerminalMetalRendererException catch (error, stackTrace) {
      _requestRecovery(error, stackTrace);
    } finally {
      _processing = false;
      _scheduleNext(now);
    }
  }

  TerminalLiveMetalSurfaceSnapshot snapshot() {
    final TerminalMetalRendererRecoveryDomain? domain =
        !_disposed && _recovery.hasCurrentDomain
        ? _recovery.currentDomain
        : null;
    return TerminalLiveMetalSurfaceSnapshot(
      isDisposed: _disposed,
      usesMacosSystemMonospaceFont: _catalog.family.isEmpty,
      fontPointSize: _catalog.metrics.pointSize,
      rows: _boundScreen.rows,
      columns: _boundScreen.columns,
      viewportWidth: _viewportWidth,
      viewportHeight: _viewportHeight,
      scale16_16: atlas.scale16_16,
      lastAppliedDamageGeneration: _scheduler.model.lastDamageGeneration,
      lastAcceptedModelRevision: _scheduler.lastAcceptedModelRevision,
      lastAcceptedFrameGeneration: _scheduler.lastAcceptedFrameGeneration,
      rendererGeneration: domain?.renderer.generation ?? 0,
      atlasResourceGeneration: atlas.resourceGeneration,
      frameBuildCount: _scheduler.metrics.buildCount,
      acceptedFrameCount: _scheduler.metrics.acceptedCount,
      pendingFrameCount: _scheduler.pendingFrameCount,
      liveAtlasPinCount: atlas.livePinCount,
      hasScheduledWork: _timer != null,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _outbox.notifyPortClosed(sessionId);
    _recovery.dispose();
    _shapingCache.dispose();
    _catalog.dispose();
  }

  void _publishWindowState(int now) {
    if (_publishedVisible == _desiredVisible &&
        _publishedOccluded == _desiredOccluded) {
      return;
    }
    final bool wasActive = _scheduler.isPresentationActive;
    _scheduler.updateWindowState(
      isVisible: _desiredVisible,
      isOccluded: _desiredOccluded,
      monotonicMicros: now,
    );
    _publishedVisible = _desiredVisible;
    _publishedOccluded = _desiredOccluded;
    if (!wasActive && _scheduler.isPresentationActive) {
      if (_recovery.hasCurrentDomain) {
        _recovery.currentDomain.renderer.requestPresentation();
      } else {
        _retryRequested = true;
      }
    }
  }

  bool _retireAndRecover() {
    if (_recovery.hasCurrentDomain) {
      final TerminalMetalRendererRecoveryDomain domain =
          _recovery.currentDomain;
      domain.bridge.retireCompletedSubmissions();
      _recovery.observeCurrentFailure();
    }
    if (!_recovery.hasPendingRecovery) return _recovery.hasCurrentDomain;
    final TerminalMetalRecoveryResult result = _recovery.processNewest();
    switch (result.disposition) {
      case TerminalMetalRecoveryDisposition.idle:
      case TerminalMetalRecoveryDisposition.recovered:
        _needsDrain = true;
        return _recovery.hasCurrentDomain;
      case TerminalMetalRecoveryDisposition.retryableFailure:
        _retryRequested = true;
        return false;
      case TerminalMetalRecoveryDisposition.exhausted:
        throw StateError(
          'live Metal renderer recovery exhausted for ${result.failure.name}',
        );
    }
  }

  bool _publishScaleIfReady() {
    if (_publishedScale == _desiredScale) return true;
    _recovery.currentDomain.bridge.retireCompletedSubmissions();
    if (atlas.livePinCount != 0) return false;
    atlas.reset(catalogGeneration: _catalog.generation, scale: _desiredScale);
    _publishedScale = _desiredScale;
    _updatePixelViewport();
    _boundScreen.requestFullSnapshot();
    _scheduler.requestFullRedraw();
    return true;
  }

  void _rebindCurrentScreen() {
    final TerminalScreen current = screenSet.activeScreen;
    if (identical(current, _boundScreen)) return;
    _boundScreen = current;
    _outbox.rebindScreenForFullRebuild(current);
    _scheduler.requestFullRedraw();
    _publishCaretGeometry();
  }

  void _applyNewestDamage(int now) {
    final TerminalDamageTransferEnvelope? transfer = _outbox.tryCreateTransfer(
      requiredResourceGeneration: atlas.resourceGeneration,
    );
    if (transfer == null) return;
    final TerminalDecodedDamage damage = transfer.materializeDamage(
      expectedSessionId: sessionId,
    );
    final TerminalDamageApplyResult result = _scheduler.applyDamage(
      damage,
      availableResourceGeneration: atlas.resourceGeneration,
      monotonicMicros: now,
    );
    if (!result.isApplied) {
      _outbox.acknowledge(
        TerminalDamageAcknowledgement.rejected(
          sessionId: sessionId,
          damageGeneration: damage.damageGeneration,
        ),
      );
      throw StateError(
        'live Metal surface rejected damage: ${result.disposition.name} '
        '${_damageRejectionContext(damage)}',
      );
    }
    final TerminalDamageAckHandlingResult acknowledgement = _outbox.acknowledge(
      TerminalDamageAcknowledgement.applied(
        sessionId: sessionId,
        damageGeneration: damage.damageGeneration,
        acceptedBytes: result.acceptedBytes,
      ),
    );
    if (!acknowledgement.isAccepted) {
      throw StateError('live Metal surface failed to acknowledge damage');
    }
  }

  void _submitNewest() {
    for (int attempt = 0; attempt < 2; attempt++) {
      final TerminalFrameAttemptResult result = _scheduler.submitNewest();
      switch (result.disposition) {
        case TerminalFrameAttemptDisposition.idle:
        case TerminalFrameAttemptDisposition.paused:
        case TerminalFrameAttemptDisposition.accepted:
          return;
        case TerminalFrameAttemptDisposition.stale:
          continue;
        case TerminalFrameAttemptDisposition.backpressured:
        case TerminalFrameAttemptDisposition.superseded:
          _retryRequested = true;
          return;
      }
    }
    _retryRequested = _scheduler.hasPendingFrame;
  }

  String _damageRejectionContext(TerminalDecodedDamage damage) {
    final TerminalDamageRenderModel model = _scheduler.model;
    String rowVersion = 'none';
    if (model.isInitialized &&
        damage.columns == model.columns &&
        damage.rows == model.rows) {
      for (final TerminalDamageRowRecord record in damage.rowRecords) {
        final int retained = model.rowVersionAt(record.row);
        if (record.rowVersion != retained + 1) {
          rowVersion = '${record.row}:$retained>${record.rowVersion}';
          break;
        }
      }
    }
    return 'incoming_generation=${damage.damageGeneration} '
        'retained_generation=${model.lastDamageGeneration} '
        'full=${damage.isFullSnapshot} '
        'incoming_grid=${damage.rows}x${damage.columns} '
        'retained_grid=${model.rows}x${model.columns} '
        'incoming_resource=${damage.requiredResourceGeneration} '
        'retained_resource=${model.requiredResourceGeneration} '
        'incoming_bell=${damage.visualBellGeneration} '
        'retained_bell=${model.visualBellGeneration} '
        'row_version=$rowVersion';
  }

  void _requestRecovery(
    TerminalMetalRendererException error,
    StackTrace stackTrace,
  ) {
    if (error.failure == TerminalMetalFailureKind.none) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    _recovery.requestRecovery(error.failure);
    final TerminalMetalRecoveryResult result = _recovery.processNewest();
    if (result.disposition == TerminalMetalRecoveryDisposition.exhausted) {
      throw StateError(
        'live Metal renderer recovery exhausted for ${result.failure.name}',
      );
    }
    _retryRequested = true;
    _needsDrain = true;
  }

  void _updatePixelViewport() {
    _viewportWidth = (_logicalWidth * _publishedScale).ceil().clamp(
      1,
      rendererConfig.maximumViewportWidth,
    );
    _viewportHeight = (_logicalHeight * _publishedScale).ceil().clamp(
      1,
      rendererConfig.maximumViewportHeight,
    );
  }

  TerminalPreeditLayout? _preeditLayoutForModel(
    TerminalDamageRenderModel model,
  ) {
    final TerminalPreeditState state = _preeditModel.state;
    if (!state.isActive || !model.isInitialized) return null;
    return TerminalPreeditLayout.compute(
      state: state,
      startRow: model.cursorRow,
      startColumn: model.cursorColumn,
      rows: model.rows,
      columns: model.columns,
    );
  }

  TerminalCaretRect _currentCaretRect() {
    var row = _boundScreen.cursorRow;
    var column = _boundScreen.cursorColumn;
    final TerminalPreeditState state = _preeditModel.state;
    if (state.isActive) {
      final TerminalPreeditLayout layout = TerminalPreeditLayout.compute(
        state: state,
        startRow: row,
        startColumn: column,
        rows: _boundScreen.rows,
        columns: _boundScreen.columns,
      );
      row = layout.caretRow;
      column = layout.caretColumn;
    }
    return TerminalCaretRect(
      x: column * _catalog.metrics.cellWidth,
      y: row * _catalog.metrics.cellHeight,
      width: _catalog.metrics.cellWidth,
      height: _catalog.metrics.cellHeight,
    );
  }

  void _publishCaretGeometry({bool force = false}) {
    final TerminalCaretGeometryPublisher? publisher = onCaretGeometryChanged;
    if (publisher == null) return;
    final TerminalCaretRect rectangle = _currentCaretRect();
    if (!force && rectangle == _lastPublishedCaretRect) return;
    publisher(rectangle);
    _lastPublishedCaretRect = rectangle;
  }

  void _scheduleImmediate() {
    if (!automaticScheduling || _disposed || _processing) return;
    _timer?.cancel();
    _timer = Timer(Duration.zero, _runScheduled);
  }

  void _scheduleNext(int now) {
    if (!automaticScheduling || _disposed) return;
    Duration? delay;
    if (_retryRequested ||
        _needsDrain ||
        _scheduler.hasPendingFrame ||
        atlas.livePinCount != 0 ||
        _recovery.hasPendingRecovery ||
        _publishedScale != _desiredScale) {
      delay = retryInterval;
    }
    final int? deadline = _scheduler.nextPresentationDeadlineMicros;
    if (deadline != null) {
      final Duration animationDelay = Duration(
        microseconds: math.max(0, deadline - now),
      );
      if (delay == null || animationDelay < delay) delay = animationDelay;
    }
    if (delay != null) {
      _timer?.cancel();
      _timer = Timer(delay, _runScheduled);
    }
  }

  void _runScheduled() {
    _timer = null;
    try {
      processPending();
    } on Object catch (error, stackTrace) {
      final TerminalLiveMetalSurfaceFatalError? handler = onFatalError;
      if (handler == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      handler(error, stackTrace);
    }
  }

  void _requireLive() {
    if (_disposed) {
      throw StateError('TerminalLiveMetalSurface is disposed');
    }
  }

  static void _validateViewport(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError('terminal viewport must be finite and positive');
    }
  }
}
