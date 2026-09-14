import 'dart:async';
import 'dart:math' as math;

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_accessibility_presentation.dart';
import '../terminal_core/terminal_hyperlink.dart';
import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_screen_set.dart';
import '../terminal_input/terminal_preedit.dart';
import '../terminal_input/terminal_selection_gesture.dart';
import '../terminal_pane.dart';
import '../terminal_typography.dart';
import 'frame_scheduler.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'metal_failure_recovery.dart';
import 'pane_work_scheduler.dart';
import 'terminal_damage.dart';
import 'terminal_damage_transfer.dart';
import 'terminal_overlay.dart';
import 'terminal_render_model.dart';
import 'terminal_screen_metal_compositor.dart';
import 'terminal_viewport_render_model.dart';

typedef TerminalLiveMetalSurfaceFatalError = void Function(
  Object error,
  StackTrace stackTrace,
);

typedef TerminalCaretGeometryPublisher = void Function(
  TerminalCaretRect rectangle,
);

typedef TerminalLiveMetalFrameObserver = void Function(
  TerminalLiveMetalFrameObservation observation,
);

enum TerminalMemoryPressureSheddingDisposition { ignored, applied, deferred }

/// Content-free result from one owner-safe memory-pressure shedding attempt.
final class TerminalMemoryPressureSheddingResult {
  const TerminalMemoryPressureSheddingResult({
    required this.disposition,
    required this.level,
    required this.shapingEntryCount,
    required this.atlasEntryCount,
    required this.atlasReleasedBytes,
    required this.pinnedSubmissionCount,
  });

  final TerminalMemoryPressureSheddingDisposition disposition;
  final AppKitMemoryPressureLevel level;
  final int shapingEntryCount;
  final int atlasEntryCount;
  final int atlasReleasedBytes;
  final int pinnedSubmissionCount;

  bool get isDeferred =>
      disposition == TerminalMemoryPressureSheddingDisposition.deferred;
}

/// Optional content-free timing observation for product acceptance tooling.
final class TerminalLiveMetalFrameObservation {
  const TerminalLiveMetalFrameObservation({
    required this.disposition,
    required this.frameGeneration,
    required this.buildMicroseconds,
    required this.submissionMicroseconds,
  });

  final TerminalFrameAttemptDisposition disposition;
  final int frameGeneration;
  final int buildMicroseconds;
  final int submissionMicroseconds;

  bool get isAccepted =>
      disposition == TerminalFrameAttemptDisposition.accepted;
  int get totalWorkMicroseconds => buildMicroseconds + submissionMicroseconds;
}

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
    required this.contentOffsetX,
    required this.contentOffsetY,
    required this.contentViewportWidth,
    required this.contentViewportHeight,
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
    required this.shapingCacheEntryCount,
    required this.shapingCacheRetainedBytes,
    required this.atlasEntryCount,
    required this.atlasRetainedBytes,
    required this.kittyAtlasEntryCount,
    required this.kittyImageCount,
    required this.kittyPlacementCount,
    required this.kittyTileCount,
    required this.kittyResourceEvictionCount,
    required this.kittyEvictedBytes,
    required this.kittyEvictedPlacementCount,
    required this.kittyAtlasEvictionCount,
    required this.hasScheduledWork,
    required this.isSystemSuspended,
    required this.pendingMemoryPressureLevel,
    required this.memoryPressureWarningCount,
    required this.memoryPressureCriticalCount,
    required this.memoryPressureDeferredCount,
    required this.memoryPressureShapingEntryCount,
    required this.memoryPressureAtlasEntryCount,
    required this.memoryPressureAtlasReleasedBytes,
    required this.synchronizedOutputMode,
    required this.synchronizedOutputHeld,
    required this.synchronizedOutputReleaseCount,
    required this.synchronizedOutputTimeoutCount,
    required this.accessibilityGeneration,
    required this.accessibilityUtf16Length,
    required this.accessibilityHasVisibleSelection,
    required this.accessibilitySelectionLength,
    required this.accessibilityHasCursor,
    required this.accessibilityCursorRow,
    required this.accessibilityCursorColumn,
    required this.accessibilityContentOriginX,
    required this.accessibilityContentOriginY,
    required this.reduceMotion,
    required this.increaseContrast,
    required this.differentiateWithoutColor,
    this.viewportOffset = 0,
    this.selectionGeneration = 0,
    this.selectionSpanCount = 0,
    this.selectionCellCount = 0,
    this.searchGeneration = 0,
    this.searchProjectionGeneration = 0,
    this.searchSpanCount = 0,
    this.searchCellCount = 0,
    this.selectedSearchSpanCount = 0,
    this.searchProjectionTruncated = false,
    this.inspectorOverlayGeneration = 0,
    this.inspectorOverlayActive = false,
    this.inspectorProjectionGeneration = 0,
    this.inspectorSemanticGeneration = 0,
    this.inspectorSpanCount = 0,
    this.inspectorHyperlinkSpanCount = 0,
    this.inspectorPromptSpanCount = 0,
    this.inspectorInputSpanCount = 0,
    this.inspectorProjectionTruncated = false,
    this.hyperlinkHoverId = 0,
    this.hyperlinkHoverRow = -1,
    this.hyperlinkHoverColumn = -1,
  });

  final bool isDisposed;
  final bool usesMacosSystemMonospaceFont;
  final double fontPointSize;
  final int rows;
  final int columns;
  final int viewportWidth;
  final int viewportHeight;
  final int contentOffsetX;
  final int contentOffsetY;
  final int contentViewportWidth;
  final int contentViewportHeight;
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
  final int shapingCacheEntryCount;
  final int shapingCacheRetainedBytes;
  final int atlasEntryCount;
  final int atlasRetainedBytes;
  final int kittyAtlasEntryCount;
  final int kittyImageCount;
  final int kittyPlacementCount;
  final int kittyTileCount;
  final int kittyResourceEvictionCount;
  final int kittyEvictedBytes;
  final int kittyEvictedPlacementCount;
  final int kittyAtlasEvictionCount;
  final bool hasScheduledWork;
  final bool isSystemSuspended;
  final AppKitMemoryPressureLevel? pendingMemoryPressureLevel;
  final int memoryPressureWarningCount;
  final int memoryPressureCriticalCount;
  final int memoryPressureDeferredCount;
  final int memoryPressureShapingEntryCount;
  final int memoryPressureAtlasEntryCount;
  final int memoryPressureAtlasReleasedBytes;
  final bool synchronizedOutputMode;
  final bool synchronizedOutputHeld;
  final int synchronizedOutputReleaseCount;
  final int synchronizedOutputTimeoutCount;
  final int accessibilityGeneration;
  final int accessibilityUtf16Length;
  final bool accessibilityHasVisibleSelection;
  final int accessibilitySelectionLength;
  final bool accessibilityHasCursor;
  final int accessibilityCursorRow;
  final int accessibilityCursorColumn;
  final double accessibilityContentOriginX;
  final double accessibilityContentOriginY;
  final bool reduceMotion;
  final bool increaseContrast;
  final bool differentiateWithoutColor;
  final int viewportOffset;
  final int selectionGeneration;
  final int selectionSpanCount;
  final int selectionCellCount;
  final int searchGeneration;
  final int searchProjectionGeneration;
  final int searchSpanCount;
  final int searchCellCount;
  final int selectedSearchSpanCount;
  final bool searchProjectionTruncated;
  final int inspectorOverlayGeneration;
  final bool inspectorOverlayActive;
  final int inspectorProjectionGeneration;
  final int inspectorSemanticGeneration;
  final int inspectorSpanCount;
  final int inspectorHyperlinkSpanCount;
  final int inspectorPromptSpanCount;
  final int inspectorInputSpanCount;
  final bool inspectorProjectionTruncated;
  final int hyperlinkHoverId;
  final int hyperlinkHoverRow;
  final int hyperlinkHoverColumn;
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
    TerminalPaneWorkScheduler? paneWorkScheduler,
    TerminalLiveMetalSurfaceFatalError? onFatalError,
    TerminalCaretGeometryPublisher? onCaretGeometryChanged,
    TerminalLiveMetalFrameObserver? onFrameAttempt,
    String fontFamily = defaultFontFamily,
    double fontPointSize = defaultFontPointSize,
    TerminalSyntheticStylePolicy syntheticStylePolicy =
        TerminalSyntheticStylePolicy.allow,
    TerminalFontCatalogConfiguration? fontCatalogConfiguration,
    double horizontalPadding = 0,
    double verticalPadding = 0,
    double backgroundOpacity = 1,
    TerminalMetalRendererConfig rendererConfig =
        const TerminalMetalRendererConfig(),
    TerminalAccessibilityPresentation accessibilityPresentation =
        const TerminalAccessibilityPresentation.standard(),
  }) {
    _validateViewport(logicalWidth, logicalHeight);
    _validatePadding(horizontalPadding, verticalPadding);
    _validateBackgroundOpacity(backgroundOpacity);
    if (!automaticScheduling && paneWorkScheduler != null) {
      throw ArgumentError.value(
        paneWorkScheduler,
        'paneWorkScheduler',
        'requires automaticScheduling',
      );
    }
    final int scale16_16 = TerminalRasterBufferV1.scaleToFixed(
      backingScaleFactor,
    );
    final TerminalFontCatalog catalog = TerminalFontCatalog.open(
      family: fontFamily,
      pointSize: fontPointSize,
      syntheticStylePolicy: syntheticStylePolicy,
      configuration:
          fontCatalogConfiguration ?? TerminalFontCatalogConfiguration.empty,
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
      TerminalRendererMacos.setBackgroundOpacity(view, backgroundOpacity);
      final TerminalAccessibilityClient accessibilityClient =
          TerminalAccessibilityClient(view);
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
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
        backgroundOpacity: backgroundOpacity,
        backingScaleFactor: backingScaleFactor,
        isVisible: isVisible,
        isOccluded: isOccluded,
        automaticScheduling: automaticScheduling,
        paneWorkScheduler: paneWorkScheduler,
        onFatalError: onFatalError,
        onCaretGeometryChanged: onCaretGeometryChanged,
        onFrameAttempt: onFrameAttempt,
        rendererConfig: rendererConfig,
        catalog: catalog,
        shapingCache: shapingCache,
        atlas: atlas,
        initialDomain: domain,
        accessibilityClient: accessibilityClient,
        accessibilityPresentation: accessibilityPresentation,
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
    required this.horizontalPadding,
    required this.verticalPadding,
    required double backgroundOpacity,
    required double backingScaleFactor,
    required bool isVisible,
    required bool isOccluded,
    required this.automaticScheduling,
    required TerminalPaneWorkScheduler? paneWorkScheduler,
    required this.onFatalError,
    required this.onCaretGeometryChanged,
    required this.onFrameAttempt,
    required this.rendererConfig,
    required TerminalFontCatalog catalog,
    required TerminalShapingCache shapingCache,
    required this.atlas,
    required TerminalMetalRendererRecoveryDomain initialDomain,
    required TerminalAccessibilityClient accessibilityClient,
    required TerminalAccessibilityPresentation accessibilityPresentation,
  }) : _paneWorkScheduler = paneWorkScheduler,
       _catalog = catalog,
       _shapingCache = shapingCache,
       _accessibilityClient = accessibilityClient,
       _logicalWidth = logicalWidth,
       _logicalHeight = logicalHeight,
       _backgroundOpacity = backgroundOpacity,
       _desiredScale = backingScaleFactor,
       _publishedScale = backingScaleFactor,
       _desiredVisible = isVisible,
       _desiredOccluded = isOccluded,
       _boundScreen = screenSet.activeScreen,
       _accessibilityPresentation = accessibilityPresentation,
       _outbox = TerminalDamageOutbox(
         sessionId: sessionId,
         screen: screenSet.activeScreen,
       ) {
    _updatePixelViewport();
    screenSet.updateLogicalViewportSize(
      width: _contentLogicalWidth,
      height: _contentLogicalHeight,
    );
    screenSet.updateLogicalCellSize(
      width: _catalog.metrics.cellWidth,
      height: _catalog.metrics.cellHeight,
    );
    late final TerminalMetalFailureRecoveryCoordinator<
      TerminalMetalRendererRecoveryDomain
    >
    recovery;
    late final TerminalNewestFrameScheduler<TerminalScheduledMetalFrame>
    scheduler;
    final _TerminalKittyFrameAnimationDriver kittyAnimationDriver =
        _TerminalKittyFrameAnimationDriver(screenSet);
    scheduler = TerminalNewestFrameScheduler<TerminalScheduledMetalFrame>(
      model: TerminalDamageRenderModel(),
      animationDriver: kittyAnimationDriver,
      buildFrame:
          (
            TerminalDamageRenderModel model, {
            required int modelRevision,
            required int frameGeneration,
            required TerminalFramePresentation presentation,
          }) {
            final TerminalScreenMetalComposition composition =
                TerminalScreenMetalCompositor(
                  catalog: _catalog,
                  shapingCache: _shapingCache,
                  atlas: atlas,
                  bridge: recovery.currentDomain.bridge,
                  styleTable: screenSet.styleTable,
                  palette: screenSet.palette,
                  graphemeTable: screenSet.graphemeTable,
                  backgroundOpacity: _backgroundOpacity,
                  accessibilityPresentation: _accessibilityPresentation,
                ).compose(
                  _visibleRenderModel(model),
                  frameGeneration: frameGeneration,
                  viewportWidth: _viewportWidth,
                  viewportHeight: _viewportHeight,
                  contentOffsetX: _contentOffsetX,
                  contentOffsetY: _contentOffsetY,
                  contentViewportWidth: _contentViewportWidth,
                  contentViewportHeight: _contentViewportHeight,
                  presentation: presentation,
                  preedit: _viewportRenderModel == null
                      ? _preeditLayoutForModel(model)
                      : null,
                  selection: _selectionProjection,
                  gridOverlay: _gridOverlayProjection,
                  kittyImages: screenSet.captureKittyImageViewport(),
                  hoveredHyperlinkId: _hyperlinkHover?.hyperlinkId ?? 0,
                );
            _lastKittyImageCount = composition.kittyImageCount;
            _lastKittyPlacementCount = composition.kittyPlacementCount;
            _lastKittyTileCount = composition.kittyTileCount;
            return composition.scheduledFrame;
          },
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
    if (_accessibilityPresentation.reduceMotion) {
      scheduler.updateReduceMotion(reduceMotion: true, monotonicMicros: 0);
    }
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
    if (!screenSet.synchronizedOutputMode) {
      _publishCaretGeometry(force: true);
    }
    _paneWorkScheduler?.register(sessionId, _runScheduled);
    _scheduleImmediate();
  }

  static const Duration retryInterval = Duration(milliseconds: 16);
  static const int minimumRows = 4;
  static const int minimumColumns = 20;

  /// Empty family delegates face selection to AppKit's system monospace API.
  static const String defaultFontFamily = TerminalDefaultTypography.fontFamily;

  /// Product-owned readable zero-config size for the macOS system monospace.
  static const double defaultFontPointSize = TerminalDefaultTypography.fontSize;

  final TerminalSessionId sessionId;
  final TerminalScreenSet screenSet;
  final View view;
  final bool automaticScheduling;
  final TerminalPaneWorkScheduler? _paneWorkScheduler;
  final TerminalLiveMetalSurfaceFatalError? onFatalError;
  final TerminalCaretGeometryPublisher? onCaretGeometryChanged;
  final TerminalLiveMetalFrameObserver? onFrameAttempt;
  final TerminalMetalRendererConfig rendererConfig;
  final TerminalGlyphAtlas atlas;
  final double horizontalPadding;
  final double verticalPadding;
  final TerminalAccessibilityClient _accessibilityClient;
  final Stopwatch _clock = Stopwatch()..start();
  final TerminalDamageOutbox _outbox;
  final TerminalPreeditModel _preeditModel = TerminalPreeditModel();
  final TerminalSynchronizedPresentationGate _synchronizedPresentationGate =
      TerminalSynchronizedPresentationGate();
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
  double _backgroundOpacity;
  late int _viewportWidth;
  late int _viewportHeight;
  late int _contentOffsetX;
  late int _contentOffsetY;
  late int _contentViewportWidth;
  late int _contentViewportHeight;
  bool _desiredVisible;
  bool _desiredOccluded;
  bool _publishedVisible = true;
  bool _publishedOccluded = false;
  bool _needsDrain = false;
  bool _retryRequested = false;
  bool _processing = false;
  bool _systemSuspended = false;
  AppKitMemoryPressureLevel? _pendingMemoryPressureLevel;
  bool _disposed = false;
  int _lastMonotonicMicros = 0;
  TerminalCaretRect? _lastPublishedCaretRect;
  TerminalSelectionGestureSnapshot? _selectionSnapshot;
  TerminalSelectionProjection? _selectionProjection;
  final TerminalSearchOverlayState _searchOverlayState =
      TerminalSearchOverlayState();
  TerminalGridOverlayProjection? _searchOverlayProjection;
  final TerminalInspectorOverlayState _inspectorOverlayState =
      TerminalInspectorOverlayState();
  TerminalGridOverlayProjection? _inspectorOverlayProjection;
  TerminalGridOverlayProjection? _gridOverlayProjection;
  TerminalHyperlinkHit? _hyperlinkHover;
  TerminalAccessibilityPresentation _accessibilityPresentation;
  TerminalViewportRenderModel? _viewportRenderModel;
  int _publishedViewportGeneration = 0;
  int _publishedSelectionGeneration = -1;
  int _publishedSearchGeneration = -1;
  int _publishedInspectorOverlayGeneration = -1;
  int _publishedInspectorSemanticGeneration = -1;
  int _publishedProjectionResourceGeneration = 0;
  int _publishedKittyStoreGeneration = 0;
  int _seenAccessibilityViewportGeneration = 0;
  int _seenAccessibilitySelectionGeneration = -1;
  int _accessibilityGeneration = 0;
  int _accessibilityUtf16Length = 0;
  bool _accessibilityHasVisibleSelection = false;
  int _accessibilitySelectionLength = 0;
  bool _accessibilityHasCursor = false;
  int _accessibilityCursorRow = -1;
  int _accessibilityCursorColumn = -1;
  int _synchronizedOutputReleaseCount = 0;
  int _synchronizedOutputTimeoutCount = 0;
  int _lastKittyImageCount = 0;
  int _lastKittyPlacementCount = 0;
  int _lastKittyTileCount = 0;
  int _memoryPressureWarningCount = 0;
  int _memoryPressureCriticalCount = 0;
  int _memoryPressureDeferredCount = 0;
  int _memoryPressureShapingEntryCount = 0;
  int _memoryPressureAtlasEntryCount = 0;
  int _memoryPressureAtlasReleasedBytes = 0;
  int _prunedPrimaryKittyImageSetGeneration = 0;
  int _prunedAlternateKittyImageSetGeneration = 0;
  double _publishedAccessibilityCellWidth = 0;
  double _publishedAccessibilityCellHeight = 0;
  double _publishedAccessibilityContentOriginX = -1;
  double _publishedAccessibilityContentOriginY = -1;
  TerminalAccessibilitySnapshot? _lastAccessibilitySnapshot;
  Timer? _timer;

  bool get isDisposed => _disposed;
  TerminalFontCatalogMetrics get fontMetrics => _catalog.metrics;
  String get fontFamily => _catalog.family;
  TerminalSyntheticStylePolicy get syntheticStylePolicy =>
      _catalog.syntheticStylePolicy;
  TerminalFontCatalogConfiguration get fontCatalogConfiguration =>
      _catalog.configuration;
  TerminalPreeditState get preeditState => _preeditModel.state;
  TerminalAccessibilityPresentation get accessibilityPresentation =>
      _accessibilityPresentation;
  double get backgroundOpacity => _backgroundOpacity;

  double get _contentLogicalWidth =>
      _logicalWidth - _effectiveHorizontalPadding * 2;
  double get _contentLogicalHeight =>
      _logicalHeight - _effectiveVerticalPadding * 2;
  double get _effectiveHorizontalPadding =>
      _effectivePadding(_logicalWidth, horizontalPadding);
  double get _effectiveVerticalPadding =>
      _effectivePadding(_logicalHeight, verticalPadding);

  bool updateSelection(TerminalSelectionGestureSnapshot snapshot) {
    _requireLive();
    final TerminalSelectionGestureSnapshot? previous = _selectionSnapshot;
    if (previous != null && snapshot.generation < previous.generation) {
      throw StateError('live selection generation regressed');
    }
    if (previous?.generation == snapshot.generation) return false;
    _selectionSnapshot = snapshot;
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  /// Publishes stable, content-free search ranges for viewport projection.
  bool updateSearchResults({
    required int generation,
    required TerminalSearchResult? result,
    int selectedMatchIndex = -1,
  }) {
    _requireLive();
    final bool changed = _searchOverlayState.update(
      generation: generation,
      result: result,
      selectedMatchIndex: selectedMatchIndex,
    );
    if (!changed) return false;
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  /// Activates or clears the content-free overlay owned by the diagnostics
  /// presenter. Geometry is always re-derived from current screen metadata.
  bool updateInspectorOverlay({
    required int generation,
    required bool isActive,
  }) {
    _requireLive();
    final bool changed = _inspectorOverlayState.update(
      generation: generation,
      isActive: isActive,
    );
    if (!changed) return false;
    _inspectorOverlayProjection = null;
    _gridOverlayProjection = _currentCombinedGridOverlay();
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  /// Resolves and publishes a derived hover at one visible cell coordinate.
  bool updateHyperlinkHover({required int row, required int column}) {
    _requireLive();
    final TerminalHyperlinkHit? next = screenSet.viewport.hitTestHyperlink(
      row,
      column,
    );
    final TerminalHyperlinkHit? previous = _hyperlinkHover;
    _hyperlinkHover = next;
    if (previous?.hyperlinkId == next?.hyperlinkId) {
      return false;
    }
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  bool clearHyperlinkHover() {
    _requireLive();
    if (_hyperlinkHover == null) return false;
    _hyperlinkHover = null;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  bool updateAccessibilityPresentation(
    TerminalAccessibilityPresentation presentation,
  ) {
    _requireLive();
    if (_accessibilityPresentation == presentation) return false;
    _accessibilityPresentation = presentation;
    _scheduler.updateReduceMotion(
      reduceMotion: presentation.reduceMotion,
      monotonicMicros: _lastMonotonicMicros,
    );
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  /// Atomically applies the shared terminal-only presentation opacity.
  bool updateBackgroundOpacity(double opacity) {
    _requireLive();
    _validateBackgroundOpacity(opacity);
    if (_backgroundOpacity == opacity) return false;
    TerminalRendererMacos.setBackgroundOpacity(view, opacity);
    _backgroundOpacity = opacity;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _scheduleImmediate();
    return true;
  }

  TerminalHyperlinkHit? hyperlinkAtCell({
    required int row,
    required int column,
  }) {
    _requireLive();
    return screenSet.viewport.hitTestHyperlink(row, column);
  }

  void notifyViewportChanged() {
    _requireLive();
    _needsDrain = true;
    _publishCaretGeometryIfPresentationOpen();
    _scheduleImmediate();
  }

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
    _publishCaretGeometryIfPresentationOpen();
    _scheduleImmediate();
    return true;
  }

  bool clearPreedit({required int generation}) {
    _requireLive();
    final bool changed = _preeditModel.clear(generation: generation);
    if (!changed) return false;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    _publishCaretGeometryIfPresentationOpen();
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
    _validatePadding(horizontalPadding, verticalPadding);
    final double contentWidth =
        logicalWidth - _effectivePadding(logicalWidth, horizontalPadding) * 2;
    final double contentHeight =
        logicalHeight - _effectivePadding(logicalHeight, verticalPadding) * 2;
    final double maximumLogicalWidth =
        rendererConfig.maximumViewportWidth / _desiredScale;
    final double maximumLogicalHeight =
        rendererConfig.maximumViewportHeight / _desiredScale;
    final int columns =
        (math.min(contentWidth, maximumLogicalWidth) /
                _catalog.metrics.cellWidth)
            .floor()
            .clamp(minimumColumns, TerminalScreen.maxColumns);
    final int rows =
        (math.min(contentHeight, maximumLogicalHeight) /
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
    screenSet.updateLogicalViewportSize(
      width:
          logicalWidth - _effectivePadding(logicalWidth, horizontalPadding) * 2,
      height:
          logicalHeight - _effectivePadding(logicalHeight, verticalPadding) * 2,
    );
    if (_logicalWidth != logicalWidth || _logicalHeight != logicalHeight) {
      _logicalWidth = logicalWidth;
      _logicalHeight = logicalHeight;
      _updatePixelViewport();
      _needsDrain = true;
      _publishCaretGeometryIfPresentationOpen();
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
    _publishCaretGeometryIfPresentationOpen();
    _scheduleImmediate();
  }

  /// Stops or resumes presentation for an application sleep/wake transition.
  ///
  /// Canonical screen, selection, preedit, and pending newest damage remain
  /// owned throughout suspension. Only transient hover and scheduled work are
  /// discarded. Resume synchronizes the latest window state before deciding
  /// whether this surface is eligible to present again.
  void updateSystemSuspended(bool isSuspended) {
    _requireLive();
    if (_systemSuspended == isSuspended) return;
    final int now = _clock.elapsedMicroseconds;
    if (now < _lastMonotonicMicros) {
      throw StateError('live Metal surface monotonic time regressed');
    }
    _lastMonotonicMicros = now;
    if (isSuspended) {
      _systemSuspended = true;
      _hyperlinkHover = null;
      _scheduler.updateSystemSuspended(isSuspended: true, monotonicMicros: now);
      _timer?.cancel();
      _timer = null;
      _paneWorkScheduler?.cancel(sessionId);
      _retryRequested = false;
      return;
    }

    _publishWindowState(now);
    _systemSuspended = false;
    _scheduler.updateSystemSuspended(isSuspended: false, monotonicMicros: now);
    if (_scheduler.isPresentationActive && _recovery.hasCurrentDomain) {
      _recovery.currentDomain.renderer.requestPresentation();
    }
    _needsDrain = true;
    _scheduleImmediate();
  }

  /// Applies one product-owned pressure stage outside the AppKit callback.
  ///
  /// Shaping and hover are always reproducible. Atlas work is delayed while a
  /// frame build or native submission owns an entry, then retried by the normal
  /// bounded render turn. Canonical terminal and Kitty image state is never
  /// mutated by this operation.
  TerminalMemoryPressureSheddingResult shedMemoryPressure(
    AppKitMemoryPressureLevel level,
  ) {
    _requireLive();
    if (level == AppKitMemoryPressureLevel.normal) {
      return const TerminalMemoryPressureSheddingResult(
        disposition: TerminalMemoryPressureSheddingDisposition.ignored,
        level: AppKitMemoryPressureLevel.normal,
        shapingEntryCount: 0,
        atlasEntryCount: 0,
        atlasReleasedBytes: 0,
        pinnedSubmissionCount: 0,
      );
    }
    final AppKitMemoryPressureLevel? pending = _pendingMemoryPressureLevel;
    if (pending == null ||
        _pressureSeverity(level) > _pressureSeverity(pending)) {
      _pendingMemoryPressureLevel = level;
    }
    final int shapingEntryCount = _shapingCache.entryCount;
    _shapingCache.clear();
    _memoryPressureShapingEntryCount = _boundedMetricSum(
      _memoryPressureShapingEntryCount,
      shapingEntryCount,
    );
    if (_hyperlinkHover != null) {
      _hyperlinkHover = null;
      if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    }
    final TerminalMemoryPressureSheddingResult result =
        _applyPendingMemoryPressure(shapingEntryCount: shapingEntryCount);
    _needsDrain = true;
    _scheduleImmediate();
    return result;
  }

  /// Advances one bounded coalesced render turn outside AppKit callbacks.
  void processPending({int? monotonicMicros}) {
    _requireLive();
    if (_systemSuspended) {
      _timer?.cancel();
      _timer = null;
      _paneWorkScheduler?.cancel(sessionId);
      return;
    }
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
      final bool synchronizedOutputReleased = _synchronizeSynchronizedOutput(
        now,
      );
      if (synchronizedOutputReleased) {
        _releaseSynchronizedOutputPresentation();
      }
      if (!_retireAndRecover()) {
        _scheduler.pauseAnimation();
        _retryRequested = true;
        return;
      }
      if (!_publishScaleIfReady()) {
        _scheduler.pauseAnimation();
        _retryRequested = true;
        return;
      }
      final TerminalMemoryPressureSheddingResult pressure =
          _applyPendingMemoryPressure();
      if (pressure.isDeferred) {
        _scheduler.pauseAnimation();
        _retryRequested = true;
        return;
      }
      _pruneStaleKittyAtlasResources();
      if (_synchronizedPresentationGate.isHolding) {
        _needsDrain = true;
        return;
      }
      _rebindCurrentScreen();
      _publishCaretGeometry();
      _applyNewestDamage(now);
      _scheduler.advancePresentation(monotonicMicros: now);
      _refreshViewportPresentation();
      _refreshAccessibilityPresentation();
      _refreshHyperlinkHover();
      _submitNewest();
      _needsDrain = _outbox.hasPendingDamage;
    } on TerminalMetalCompositionBackpressureException {
      _retryRequested = true;
    } on TerminalMetalRendererException catch (error, stackTrace) {
      _scheduler.pauseAnimation();
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
      contentOffsetX: _contentOffsetX,
      contentOffsetY: _contentOffsetY,
      contentViewportWidth: _contentViewportWidth,
      contentViewportHeight: _contentViewportHeight,
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
      shapingCacheEntryCount: _shapingCache.entryCount,
      shapingCacheRetainedBytes: _shapingCache.retainedBytes,
      atlasEntryCount: atlas.entryCount,
      atlasRetainedBytes: atlas.retainedBytes,
      kittyAtlasEntryCount: atlas.kittyImageEntryCount,
      kittyImageCount: _lastKittyImageCount,
      kittyPlacementCount: _lastKittyPlacementCount,
      kittyTileCount: _lastKittyTileCount,
      kittyResourceEvictionCount: _boundedMetricSum(
        screenSet.primaryKittyImages.evictionCount,
        screenSet.alternateKittyImages.evictionCount,
      ),
      kittyEvictedBytes: _boundedMetricSum(
        screenSet.primaryKittyImages.evictedBytes,
        screenSet.alternateKittyImages.evictedBytes,
      ),
      kittyEvictedPlacementCount: _boundedMetricSum(
        screenSet.primaryKittyImages.evictedPlacementCount,
        screenSet.alternateKittyImages.evictedPlacementCount,
      ),
      kittyAtlasEvictionCount: atlas.kittyImageEvictionCount,
      hasScheduledWork:
          _timer != null || (_paneWorkScheduler?.isPending(sessionId) ?? false),
      isSystemSuspended: _systemSuspended,
      pendingMemoryPressureLevel: _pendingMemoryPressureLevel,
      memoryPressureWarningCount: _memoryPressureWarningCount,
      memoryPressureCriticalCount: _memoryPressureCriticalCount,
      memoryPressureDeferredCount: _memoryPressureDeferredCount,
      memoryPressureShapingEntryCount: _memoryPressureShapingEntryCount,
      memoryPressureAtlasEntryCount: _memoryPressureAtlasEntryCount,
      memoryPressureAtlasReleasedBytes: _memoryPressureAtlasReleasedBytes,
      synchronizedOutputMode: screenSet.synchronizedOutputMode,
      synchronizedOutputHeld: _synchronizedPresentationGate.isHolding,
      synchronizedOutputReleaseCount: _synchronizedOutputReleaseCount,
      synchronizedOutputTimeoutCount: _synchronizedOutputTimeoutCount,
      accessibilityGeneration: _accessibilityGeneration,
      accessibilityUtf16Length: _accessibilityUtf16Length,
      accessibilityHasVisibleSelection: _accessibilityHasVisibleSelection,
      accessibilitySelectionLength: _accessibilitySelectionLength,
      accessibilityHasCursor: _accessibilityHasCursor,
      accessibilityCursorRow: _accessibilityCursorRow,
      accessibilityCursorColumn: _accessibilityCursorColumn,
      accessibilityContentOriginX: _publishedAccessibilityContentOriginX,
      accessibilityContentOriginY: _publishedAccessibilityContentOriginY,
      reduceMotion: _accessibilityPresentation.reduceMotion,
      increaseContrast: _accessibilityPresentation.increaseContrast,
      differentiateWithoutColor:
          _accessibilityPresentation.differentiateWithoutColor,
      viewportOffset: screenSet.viewport.offset,
      selectionGeneration: _selectionSnapshot?.generation ?? 0,
      selectionSpanCount: _selectionProjection?.spans.length ?? 0,
      selectionCellCount: _selectionProjection?.selectedCellCount ?? 0,
      searchGeneration: _searchOverlayState.generation,
      searchProjectionGeneration:
          _searchOverlayProjection?.sourceGeneration ?? 0,
      searchSpanCount: _searchOverlayProjection?.spanCount ?? 0,
      searchCellCount: _searchOverlayProjection?.cellCount ?? 0,
      selectedSearchSpanCount:
          _searchOverlayProjection?.spans
              .where(
                (TerminalGridOverlaySpan span) =>
                    span.kind == TerminalGridOverlayKind.searchSelectedMatch,
              )
              .length ??
          0,
      searchProjectionTruncated: _searchOverlayProjection?.isTruncated ?? false,
      inspectorOverlayGeneration: _inspectorOverlayState.generation,
      inspectorOverlayActive: _inspectorOverlayState.isActive,
      inspectorProjectionGeneration:
          _inspectorOverlayProjection?.sourceGeneration ?? 0,
      inspectorSemanticGeneration: _publishedInspectorSemanticGeneration < 0
          ? 0
          : _publishedInspectorSemanticGeneration,
      inspectorSpanCount: _inspectorOverlayProjection?.spanCount ?? 0,
      inspectorHyperlinkSpanCount: _inspectorSpanCount(
        TerminalGridOverlayKind.inspectorHyperlink,
      ),
      inspectorPromptSpanCount: _inspectorSpanCount(
        TerminalGridOverlayKind.inspectorSemanticPrompt,
      ),
      inspectorInputSpanCount: _inspectorSpanCount(
        TerminalGridOverlayKind.inspectorSemanticInput,
      ),
      inspectorProjectionTruncated:
          _inspectorOverlayProjection?.isTruncated ?? false,
      hyperlinkHoverId: _hyperlinkHover?.hyperlinkId ?? 0,
      hyperlinkHoverRow: _hyperlinkHover?.row ?? -1,
      hyperlinkHoverColumn: _hyperlinkHover?.pointerColumn ?? -1,
    );
  }

  /// Returns the current content-free native presentation state.
  TerminalMetalRendererState rendererState() {
    _requireLive();
    return _recovery.currentDomain.renderer.state();
  }

  /// Returns bounded font resolution counters and safe face identities.
  TerminalFontCatalogDiagnostics fontDiagnostics() {
    _requireLive();
    return _catalog.diagnostics();
  }

  /// Runs the native content-free selector/range/geometry/focus acceptance.
  void debugVerifyAccessibility() {
    _requireLive();
    _accessibilityClient.debugVerifyCurrentSnapshot();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hyperlinkHover = null;
    _inspectorOverlayProjection = null;
    _gridOverlayProjection = null;
    _scheduler.pauseAnimation();
    _timer?.cancel();
    _timer = null;
    _paneWorkScheduler?.unregister(sessionId);
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

  TerminalMemoryPressureSheddingResult _applyPendingMemoryPressure({
    int shapingEntryCount = 0,
  }) {
    final AppKitMemoryPressureLevel? level = _pendingMemoryPressureLevel;
    if (level == null) {
      return const TerminalMemoryPressureSheddingResult(
        disposition: TerminalMemoryPressureSheddingDisposition.ignored,
        level: AppKitMemoryPressureLevel.normal,
        shapingEntryCount: 0,
        atlasEntryCount: 0,
        atlasReleasedBytes: 0,
        pinnedSubmissionCount: 0,
      );
    }
    if (_systemSuspended || !_recovery.hasCurrentDomain) {
      _memoryPressureDeferredCount = _boundedMetricSum(
        _memoryPressureDeferredCount,
        1,
      );
      return TerminalMemoryPressureSheddingResult(
        disposition: TerminalMemoryPressureSheddingDisposition.deferred,
        level: level,
        shapingEntryCount: shapingEntryCount,
        atlasEntryCount: 0,
        atlasReleasedBytes: 0,
        pinnedSubmissionCount: atlas.livePinCount,
      );
    }
    final TerminalGlyphAtlasMetalBridge bridge = _recovery.currentDomain.bridge;
    bridge.retireCompletedSubmissions();
    if (atlas.livePinCount != 0 || atlas.activeBuildLeaseCount != 0) {
      _memoryPressureDeferredCount = _boundedMetricSum(
        _memoryPressureDeferredCount,
        1,
      );
      return TerminalMemoryPressureSheddingResult(
        disposition: TerminalMemoryPressureSheddingDisposition.deferred,
        level: level,
        shapingEntryCount: shapingEntryCount,
        atlasEntryCount: 0,
        atlasReleasedBytes: 0,
        pinnedSubmissionCount: atlas.livePinCount,
      );
    }

    final int atlasEntryCount = atlas.entryCount;
    final int retainedBytes = atlas.retainedBytes;
    if (level == AppKitMemoryPressureLevel.critical) {
      atlas.reset(
        catalogGeneration: _catalog.generation,
        scale: _publishedScale,
      );
      _memoryPressureCriticalCount = _boundedMetricSum(
        _memoryPressureCriticalCount,
        1,
      );
    } else {
      final TerminalGlyphAtlasReclaimResult reclaimed = atlas
          .reclaimUnpinnedResources();
      if (reclaimed.isDeferred) {
        throw StateError('unpinned atlas reclamation changed ownership');
      }
      _memoryPressureWarningCount = _boundedMetricSum(
        _memoryPressureWarningCount,
        1,
      );
    }
    final int releasedBytes = retainedBytes - atlas.retainedBytes;
    _memoryPressureAtlasEntryCount = _boundedMetricSum(
      _memoryPressureAtlasEntryCount,
      atlasEntryCount,
    );
    _memoryPressureAtlasReleasedBytes = _boundedMetricSum(
      _memoryPressureAtlasReleasedBytes,
      releasedBytes,
    );
    _pendingMemoryPressureLevel = null;
    _boundScreen.requestFullSnapshot();
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _needsDrain = true;
    return TerminalMemoryPressureSheddingResult(
      disposition: TerminalMemoryPressureSheddingDisposition.applied,
      level: level,
      shapingEntryCount: shapingEntryCount,
      atlasEntryCount: atlasEntryCount,
      atlasReleasedBytes: releasedBytes,
      pinnedSubmissionCount: 0,
    );
  }

  void _pruneStaleKittyAtlasResources() {
    final int primaryGeneration =
        screenSet.primaryKittyImages.imageSetGeneration;
    final int alternateGeneration =
        screenSet.alternateKittyImages.imageSetGeneration;
    if (primaryGeneration == _prunedPrimaryKittyImageSetGeneration &&
        alternateGeneration == _prunedAlternateKittyImageSetGeneration) {
      return;
    }
    final result = atlas.pruneKittyImageResources((
      TerminalKittyImageAtlasKey key,
    ) {
      final store = switch (key.screenKindIndex) {
        0 => screenSet.primaryKittyImages,
        1 => screenSet.alternateKittyImages,
        _ => null,
      };
      final image = store?.imageById(key.imageId);
      return image != null &&
          image.resourceGeneration == key.imageResourceGeneration;
    });
    if (result.pinnedEntryCount == 0) {
      _prunedPrimaryKittyImageSetGeneration = primaryGeneration;
      _prunedAlternateKittyImageSetGeneration = alternateGeneration;
    }
  }

  bool _synchronizeSynchronizedOutput(int now) {
    TerminalSynchronizedPresentationDisposition disposition =
        _synchronizedPresentationGate.synchronize(
          enabled: screenSet.synchronizedOutputMode,
          modeGeneration: screenSet.synchronizedOutputGeneration,
          monotonicMicros: now,
        );
    if (_synchronizedPresentationGate.deadlineReached(monotonicMicros: now)) {
      final bool expired = screenSet.expireSynchronizedOutputMode(
        _synchronizedPresentationGate.observedModeGeneration,
      );
      if (expired) {
        _synchronizedOutputTimeoutCount++;
        disposition = _synchronizedPresentationGate.synchronize(
          enabled: screenSet.synchronizedOutputMode,
          modeGeneration: screenSet.synchronizedOutputGeneration,
          monotonicMicros: now,
        );
      }
    }
    _scheduler.updateSynchronizedOutput(
      isHeld: _synchronizedPresentationGate.isHolding,
    );
    return disposition == TerminalSynchronizedPresentationDisposition.released;
  }

  void _releaseSynchronizedOutputPresentation() {
    screenSet.activeScreen.requestFullSnapshot();
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
    _synchronizedOutputReleaseCount++;
    _needsDrain = true;
  }

  void _rebindCurrentScreen() {
    final TerminalScreen current = screenSet.activeScreen;
    if (identical(current, _boundScreen)) return;
    _boundScreen = current;
    _outbox.rebindScreenForFullRebuild(current);
    _scheduler.requestFullRedraw();
    _publishCaretGeometry();
  }

  void _refreshViewportPresentation() {
    final TerminalViewport viewport = screenSet.viewport;
    final int viewportGeneration = viewport.generation;
    final int selectionGeneration = _selectionSnapshot?.generation ?? 0;
    final int searchGeneration = _searchOverlayState.generation;
    final int inspectorOverlayGeneration = _inspectorOverlayState.generation;
    final TerminalSemanticRangeSnapshot? semanticRanges =
        _inspectorOverlayState.isActive
        ? screenSet.semanticRangeSnapshot()
        : null;
    final int inspectorSemanticGeneration = semanticRanges?.generation ?? 0;
    final int resourceGeneration = atlas.resourceGeneration;
    final int kittyStoreGeneration =
        screenSet.activeKittyImages.stateGeneration;
    if (viewportGeneration == _publishedViewportGeneration &&
        selectionGeneration == _publishedSelectionGeneration &&
        searchGeneration == _publishedSearchGeneration &&
        inspectorOverlayGeneration == _publishedInspectorOverlayGeneration &&
        inspectorSemanticGeneration == _publishedInspectorSemanticGeneration &&
        resourceGeneration == _publishedProjectionResourceGeneration &&
        kittyStoreGeneration == _publishedKittyStoreGeneration) {
      return;
    }
    _viewportRenderModel = viewport.atBottom
        ? null
        : TerminalViewportRenderModel.capture(
            viewport,
            activeScreen: _boundScreen,
            requiredResourceGeneration: resourceGeneration,
          );
    final TerminalSelectionRange? range = _selectionSnapshot?.range;
    _selectionProjection = range == null
        ? null
        : viewport.projectSelection(range);
    _searchOverlayProjection = _searchOverlayState.project(viewport);
    _inspectorOverlayProjection = semanticRanges == null
        ? null
        : _inspectorOverlayState.project(viewport, semanticRanges);
    _gridOverlayProjection = _currentCombinedGridOverlay();
    _publishedViewportGeneration = viewportGeneration;
    _publishedSelectionGeneration = selectionGeneration;
    _publishedSearchGeneration = searchGeneration;
    _publishedInspectorOverlayGeneration = inspectorOverlayGeneration;
    _publishedInspectorSemanticGeneration = inspectorSemanticGeneration;
    _publishedProjectionResourceGeneration = resourceGeneration;
    _publishedKittyStoreGeneration = kittyStoreGeneration;
    if (_scheduler.model.isInitialized) _scheduler.requestFullRedraw();
  }

  TerminalGridOverlayProjection? _currentCombinedGridOverlay() {
    if (_searchOverlayProjection == null &&
        _inspectorOverlayProjection == null) {
      return null;
    }
    return TerminalGridOverlayProjection.combine(
      sourceGeneration: screenSet.viewport.generation,
      first: _searchOverlayProjection,
      second: _inspectorOverlayProjection,
    );
  }

  int _inspectorSpanCount(TerminalGridOverlayKind kind) =>
      _inspectorOverlayProjection?.spans
          .where((TerminalGridOverlaySpan span) => span.kind == kind)
          .length ??
      0;

  void _refreshAccessibilityPresentation() {
    final TerminalViewport viewport = screenSet.viewport;
    final int viewportGeneration = viewport.generation;
    final int selectionGeneration = _selectionSnapshot?.generation ?? 0;
    final double cellWidth = _catalog.metrics.cellWidth;
    final double cellHeight = _catalog.metrics.cellHeight;
    final double contentOriginX = _effectiveHorizontalPadding;
    final double contentOriginY = _effectiveVerticalPadding;
    if (viewportGeneration == _seenAccessibilityViewportGeneration &&
        selectionGeneration == _seenAccessibilitySelectionGeneration &&
        cellWidth == _publishedAccessibilityCellWidth &&
        cellHeight == _publishedAccessibilityCellHeight &&
        contentOriginX == _publishedAccessibilityContentOriginX &&
        contentOriginY == _publishedAccessibilityContentOriginY) {
      return;
    }
    final TerminalAccessibilitySnapshot snapshot =
        TerminalAccessibilitySnapshot.capture(
          viewport,
          selection: _selectionSnapshot?.range,
          maxUtf8Bytes: TerminalAccessibilityViewSnapshot.maximumUtf8Bytes,
          maxUtf16CodeUnits:
              TerminalAccessibilityViewSnapshot.maximumUtf16CodeUnits,
          maxColumnBoundaries:
              TerminalAccessibilityViewSnapshot.maximumColumnBoundaries,
        );
    final TerminalAccessibilitySnapshot? previous = _lastAccessibilitySnapshot;
    final bool metricsChanged =
        cellWidth != _publishedAccessibilityCellWidth ||
        cellHeight != _publishedAccessibilityCellHeight ||
        contentOriginX != _publishedAccessibilityContentOriginX ||
        contentOriginY != _publishedAccessibilityContentOriginY;
    if (!metricsChanged &&
        previous != null &&
        _sameAccessibilitySnapshot(previous, snapshot)) {
      _seenAccessibilityViewportGeneration = viewportGeneration;
      _seenAccessibilitySelectionGeneration = selectionGeneration;
      return;
    }
    final int generation = _accessibilityGeneration + 1;
    _accessibilityClient.publish(
      TerminalAccessibilityViewSnapshot(
        generation: generation,
        rows: snapshot.rows,
        columns: snapshot.columns,
        text: snapshot.text,
        lines: <TerminalAccessibilityViewLine>[
          for (final TerminalAccessibilityLine line in snapshot.lines)
            TerminalAccessibilityViewLine(
              row: line.row,
              utf16Start: line.utf16Start,
              utf16Length: line.utf16Length,
              columnUtf16Offsets: line.columnUtf16Offsets,
            ),
        ],
        selectedRange: TerminalAccessibilityRange(
          location: snapshot.selectedRange.location,
          length: snapshot.selectedRange.length,
        ),
        hasVisibleSelection: snapshot.hasVisibleSelection,
        cursorRange: snapshot.cursorRange == null
            ? null
            : TerminalAccessibilityRange(
                location: snapshot.cursorRange!.location,
                length: snapshot.cursorRange!.length,
              ),
        cursorRow: snapshot.cursorRow,
        cursorColumn: snapshot.cursorColumn,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        contentOriginX: contentOriginX,
        contentOriginY: contentOriginY,
      ),
    );
    _seenAccessibilityViewportGeneration = viewportGeneration;
    _seenAccessibilitySelectionGeneration = selectionGeneration;
    _lastAccessibilitySnapshot = snapshot;
    _publishedAccessibilityCellWidth = cellWidth;
    _publishedAccessibilityCellHeight = cellHeight;
    _publishedAccessibilityContentOriginX = contentOriginX;
    _publishedAccessibilityContentOriginY = contentOriginY;
    _accessibilityGeneration = generation;
    _accessibilityUtf16Length = snapshot.utf16Length;
    _accessibilityHasVisibleSelection = snapshot.hasVisibleSelection;
    _accessibilitySelectionLength = snapshot.selectedRange.length;
    _accessibilityHasCursor = snapshot.cursorRange != null;
    _accessibilityCursorRow = snapshot.cursorRow ?? -1;
    _accessibilityCursorColumn = snapshot.cursorColumn ?? -1;
  }

  void _refreshHyperlinkHover() {
    final TerminalHyperlinkHit? previous = _hyperlinkHover;
    if (previous == null) return;
    final TerminalHyperlinkHit? refreshed = screenSet.viewport
        .refreshHyperlinkHit(previous);
    _hyperlinkHover = refreshed;
    if (refreshed == null && _scheduler.model.isInitialized) {
      _scheduler.requestFullRedraw();
    }
  }

  TerminalRenderModel _visibleRenderModel(TerminalDamageRenderModel model) =>
      _viewportRenderModel ?? model;

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
      final TerminalFrameSchedulerMetrics? before = onFrameAttempt == null
          ? null
          : _scheduler.metrics;
      final TerminalFrameAttemptResult result = _scheduler.submitNewest();
      final TerminalLiveMetalFrameObserver? observer = onFrameAttempt;
      if (observer != null && before != null) {
        final TerminalFrameSchedulerMetrics after = _scheduler.metrics;
        if (after.buildCount > before.buildCount) {
          observer(
            TerminalLiveMetalFrameObservation(
              disposition: result.disposition,
              frameGeneration: result.frameGeneration,
              buildMicroseconds:
                  after.buildTotalMicroseconds - before.buildTotalMicroseconds,
              submissionMicroseconds:
                  after.submissionTotalMicroseconds -
                  before.submissionTotalMicroseconds,
            ),
          );
        }
      }
      switch (result.disposition) {
        case TerminalFrameAttemptDisposition.idle:
        case TerminalFrameAttemptDisposition.paused:
        case TerminalFrameAttemptDisposition.synchronized:
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
    _contentOffsetX = (_effectiveHorizontalPadding * _publishedScale).round();
    _contentOffsetY = (_effectiveVerticalPadding * _publishedScale).round();
    _contentViewportWidth = math.max(1, _viewportWidth - _contentOffsetX * 2);
    _contentViewportHeight = math.max(1, _viewportHeight - _contentOffsetY * 2);
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
      x: _effectiveHorizontalPadding + column * _catalog.metrics.cellWidth,
      y: _effectiveVerticalPadding + row * _catalog.metrics.cellHeight,
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

  void _publishCaretGeometryIfPresentationOpen() {
    if (screenSet.synchronizedOutputMode ||
        _synchronizedPresentationGate.isHolding) {
      return;
    }
    _publishCaretGeometry();
  }

  void _scheduleImmediate() {
    if (!automaticScheduling || _disposed || _processing || _systemSuspended) {
      return;
    }
    final TerminalPaneWorkScheduler? paneScheduler = _paneWorkScheduler;
    if (paneScheduler != null) {
      if (!paneScheduler.request(sessionId)) {
        throw StateError('live Metal surface is absent from pane scheduler');
      }
      return;
    }
    _timer?.cancel();
    _timer = Timer(Duration.zero, _runScheduled);
  }

  void _scheduleNext(int now) {
    if (!automaticScheduling || _disposed || _systemSuspended) return;
    Duration? delay;
    final bool synchronizedOutputHeld = _synchronizedPresentationGate.isHolding;
    if (_retryRequested ||
        (!synchronizedOutputHeld && _needsDrain) ||
        (!synchronizedOutputHeld && _scheduler.hasPendingFrame) ||
        atlas.livePinCount != 0 ||
        _recovery.hasPendingRecovery ||
        _publishedScale != _desiredScale) {
      delay = retryInterval;
    }
    final int? deadline = synchronizedOutputHeld
        ? _synchronizedPresentationGate.nextDeadlineMicros
        : _scheduler.nextPresentationDeadlineMicros;
    if (deadline != null) {
      final Duration animationDelay = Duration(
        microseconds: math.max(0, deadline - now),
      );
      if (delay == null || animationDelay < delay) delay = animationDelay;
    }
    if (delay != null) {
      final TerminalPaneWorkScheduler? paneScheduler = _paneWorkScheduler;
      if (paneScheduler != null) {
        if (!paneScheduler.request(sessionId, delay: delay)) {
          throw StateError('live Metal surface is absent from pane scheduler');
        }
        return;
      }
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

  static void _validatePadding(double horizontal, double vertical) {
    if (!horizontal.isFinite || !vertical.isFinite) {
      throw ArgumentError('terminal padding must be finite');
    }
    if (horizontal < 0 || vertical < 0) {
      throw ArgumentError('terminal padding must be non-negative');
    }
  }

  static void _validateBackgroundOpacity(double opacity) {
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw RangeError.range(opacity, 0, 1, 'backgroundOpacity');
    }
  }

  static double _effectivePadding(double extent, double configured) =>
      math.min(configured, math.max(0, (extent - 1) / 2));

  static int _boundedMetricSum(int first, int second) =>
      first >= 0x7fffffffffffffff - second
      ? 0x7fffffffffffffff
      : first + second;

  static int _pressureSeverity(AppKitMemoryPressureLevel level) =>
      switch (level) {
        AppKitMemoryPressureLevel.normal => 0,
        AppKitMemoryPressureLevel.warning => 1,
        AppKitMemoryPressureLevel.critical => 2,
      };
}

/// Projects active-screen Kitty animation state into the ordinary frame clock.
final class _TerminalKittyFrameAnimationDriver
    implements TerminalFrameAnimationDriver {
  _TerminalKittyFrameAnimationDriver(this._screens);

  final TerminalScreenSet _screens;
  int? _nextDeadlineMicros;

  @override
  int? get nextDeadlineMicros => _nextDeadlineMicros;

  @override
  TerminalFrameAnimationTick advance({required int monotonicMicros}) {
    if (_screens.usingAlternate) {
      _screens.primaryKittyImages.pauseAnimationPlayback();
    } else {
      _screens.alternateKittyImages.pauseAnimationPlayback();
    }
    final result = _screens.activeKittyImages.advanceAnimations(
      monotonicMicros: monotonicMicros,
      visibleImageIds: _screens.captureVisibleKittyImageIds(),
    );
    _nextDeadlineMicros = result.nextDeadlineMicros;
    return TerminalFrameAnimationTick(
      changed: result.changed,
      nextDeadlineMicros: result.nextDeadlineMicros,
    );
  }

  @override
  void pause() {
    _screens.primaryKittyImages.pauseAnimationPlayback();
    _screens.alternateKittyImages.pauseAnimationPlayback();
    _nextDeadlineMicros = null;
  }
}

bool _sameAccessibilitySnapshot(
  TerminalAccessibilitySnapshot first,
  TerminalAccessibilitySnapshot second,
) {
  if (first.rows != second.rows ||
      first.columns != second.columns ||
      first.text != second.text ||
      first.selectedRange != second.selectedRange ||
      first.hasVisibleSelection != second.hasVisibleSelection ||
      first.cursorRange != second.cursorRange ||
      first.cursorRow != second.cursorRow ||
      first.cursorColumn != second.cursorColumn ||
      first.lines.length != second.lines.length) {
    return false;
  }
  for (var index = 0; index < first.lines.length; index++) {
    final TerminalAccessibilityLine left = first.lines[index];
    final TerminalAccessibilityLine right = second.lines[index];
    if (left.row != right.row ||
        left.utf16Start != right.utf16Start ||
        left.utf16Length != right.utf16Length ||
        left.columnUtf16Offsets.length != right.columnUtf16Offsets.length) {
      return false;
    }
    for (var column = 0; column < left.columnUtf16Offsets.length; column++) {
      if (left.columnUtf16Offsets[column] != right.columnUtf16Offsets[column]) {
        return false;
      }
    }
  }
  return true;
}
