import 'dart:async';

import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'terminal_note_authority.dart';
import 'terminal_note_composition.dart';
import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_native_adapter.dart';
import 'terminal_note_projection.dart';
import 'terminal_note_store_worker.dart';
import 'terminal_pane.dart';
import 'terminal_product_configuration.dart';

typedef TerminalNoteNativeCapabilityInitializer = void Function();
typedef TerminalNoteNativeSurfaceChannelFactory =
    TerminalNoteNativeSurfaceChannel Function();
typedef TerminalNoteStoreLocationResolver = TerminalNoteStoreLocation Function(
  Map<String, String> environment,
);
typedef TerminalNoteUtcMicrosClock = int Function();
typedef TerminalNoteProductSurfaceEventHandler = void Function(PaneId paneId);
typedef TerminalNoteBodyCopyEffect = bool Function(String body);
typedef TerminalNoteExportDestinationChooser =
    TerminalNoteApprovedExportPath? Function(TerminalNotesLocale locale);

enum TerminalNoteProductFocusTarget { rail, editor }

enum TerminalNoteProductActionKind { newNote, toggleNotes }

/// Content-free interaction state read from one generation-bound surface.
final class TerminalNoteProductInteractionSnapshot {
  const TerminalNoteProductInteractionSnapshot({
    required this.surfaceGeneration,
    required this.visibility,
    this.automaticPresentation = false,
    required this.editorMode,
    required this.draftGeneration,
    required this.editorDirty,
    required this.confirmingDiscard,
  });

  final int surfaceGeneration;
  final TerminalNoteSurfaceVisibility visibility;
  final bool automaticPresentation;
  final TerminalNoteEditorMode editorMode;
  final int draftGeneration;
  final bool editorDirty;
  final bool confirmingDiscard;
}

enum TerminalNoteProductTopologyDisposition {
  applied,
  noChange,
  duplicate,
  stale,
  busy,
  rejected,
  nativeUnavailable,
  unavailable,
}

/// Content-free outcome for one product topology transition.
final class TerminalNoteProductTopologyResult {
  const TerminalNoteProductTopologyResult(
    this.disposition, {
    this.surfaceGeneration,
  });

  final TerminalNoteProductTopologyDisposition disposition;
  final int? surfaceGeneration;

  bool get isAccepted => switch (disposition) {
    TerminalNoteProductTopologyDisposition.applied ||
    TerminalNoteProductTopologyDisposition.noChange => true,
    _ => false,
  };

  @override
  String toString() =>
      'TerminalNoteProductTopologyResult(${disposition.name}, '
      'surface=${surfaceGeneration != null})';
}

/// Renderer host and pane-local presentation values for one Note surface.
///
/// These values are volatile. None may be persisted or used as a Note/context
/// identity, and changing them must not resize a terminal grid, drawable, or
/// PTY.
final class TerminalNoteProductSurfaceConfiguration {
  TerminalNoteProductSurfaceConfiguration({
    required this.rendererIdentity,
    required this.paneWidth,
    required this.paneHeight,
    required this.backingScale,
    required this.visibility,
    required this.foreground,
    required this.occluded,
    this.requestedRailWidth = 0,
    this.presentation,
  }) {
    final int handle = rendererIdentity.handle;
    final int generation = rendererIdentity.generation;
    if (handle <= 0 ||
        handle > TerminalNoteProjectionLimits.maximumGeneration ||
        generation <= 0 ||
        generation > TerminalNoteProjectionLimits.maximumGeneration) {
      throw ArgumentError('Note renderer identity is invalid');
    }
    if (!paneWidth.isFinite ||
        paneWidth <= 0 ||
        paneWidth > 4096 ||
        !paneHeight.isFinite ||
        paneHeight <= 0 ||
        paneHeight > 4096 ||
        (backingScale != 1 && backingScale != 2) ||
        !requestedRailWidth.isFinite ||
        (requestedRailWidth != 0 &&
            (requestedRailWidth < 240 || requestedRailWidth > 360))) {
      throw ArgumentError('Note surface layout is invalid');
    }
  }

  final TerminalMetalRendererCompositionIdentity rendererIdentity;
  final double paneWidth;
  final double paneHeight;
  final double backingScale;
  final double requestedRailWidth;
  final TerminalNoteSurfaceVisibility visibility;
  final bool foreground;
  final bool occluded;
  final TerminalNoteNativePresentationState? presentation;
}

/// Product topology operations consumed by the application composition layer.
///
/// Keeping this port in dart_terminal lets deterministic tests inject a fake
/// runtime without teaching generic AppKit code about Notes.
abstract interface class TerminalNoteProductTopologyPort
    implements TerminalNoteSubsystemPort {
  bool get isStopped;
  int get livePaneCount;
  int get liveSurfaceCount;
  int get nativeSurfaceCount;

  bool hasPane(PaneId paneId);

  int? surfaceGenerationForPane(PaneId paneId);

  Future<TerminalNoteProductTopologyResult> bindPane({
    required PaneId paneId,
    TerminalNoteContextKind kind = TerminalNoteContextKind.standard,
  });

  Future<TerminalNoteProductTopologyResult> closePane({
    required PaneId paneId,
    required int updatedAtUtcMicros,
  });

  Future<TerminalNoteProductTopologyResult> attachSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  });

  Future<TerminalNoteProductTopologyResult> updateSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  });

  Future<TerminalNoteProductTopologyResult> detachSurface(PaneId paneId);

  /// Drains at most the one native intent allowed for this surface.
  ///
  /// The application invokes this after a routed native Note interaction;
  /// there is deliberately no idle polling timer.
  Future<TerminalNoteProductTopologyResult> pumpSurfaceIntent(PaneId paneId);

  bool canPerformAction(PaneId paneId, TerminalNoteProductActionKind action);

  Future<TerminalNoteProductTopologyResult> performAction(
    PaneId paneId,
    TerminalNoteProductActionKind action,
  );

  void setSurfaceEventHandler(TerminalNoteProductSurfaceEventHandler? handler);

  TerminalNoteProductInteractionSnapshot? interactionSnapshotForPane(
    PaneId paneId,
  );

  bool focusSurface(PaneId paneId, TerminalNoteProductFocusTarget target);

  bool presentDiscardConfirmation(PaneId paneId);

  bool surfaceContainsPoint(
    PaneId paneId, {
    required double x,
    required double y,
  });

  bool prepareSurfaceForHostTeardown(PaneId paneId);

  /// Freezes ingress and commits exact restoration bytes before the Note
  /// document that binds to them, then releases every product owner.
  Future<TerminalNoteAuthorityShutdownResult> shutdownApplication({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    Duration drainTimeout = const Duration(seconds: 3),
  });

  void updatePresentation(TerminalNoteNativePresentationState presentation);
}

/// Production owner of the durable Note authority and pane-local native
/// surfaces.
///
/// Construction is admitted only by [TerminalNoteCompositionRoot]. Store and
/// authority startup happen once, while native surfaces remain lazy until a
/// concrete pane renderer is attached. All topology changes are serialized so
/// authority sequence, native host, and adapter ownership cannot diverge.
final class TerminalNoteProductSubsystem
    implements TerminalNoteProductTopologyPort {
  TerminalNoteProductSubsystem._({
    required TerminalNoteAuthority authority,
    required TerminalNoteFeatureConfiguration configuration,
    required TerminalNoteNativeSurfaceChannelFactory surfaceFactory,
    required TerminalNoteUtcMicrosClock clock,
    required TerminalNoteBodyCopyEffect copyEffect,
    required TerminalNoteExportDestinationChooser exportDestinationChooser,
    required Iterable<PaneId> initialPaneIds,
    required TerminalNoteNativePresentationState presentation,
  }) : _authority = authority,
       _configuration = configuration,
       _surfaceFactory = surfaceFactory,
       _clock = clock,
       _copyEffect = copyEffect,
       _exportDestinationChooser = exportDestinationChooser,
       _presentation = _presentationWithFont(presentation, configuration) {
    for (final PaneId paneId in initialPaneIds) {
      _paneKinds[paneId] = TerminalNoteContextKind.standard;
    }
    _debugLiveProductSubsystemCount++;
  }

  static Future<TerminalNoteSubsystemStartResult> start({
    required TerminalNoteFeatureConfiguration configuration,
    required Map<String, String> environment,
    required int authorityGeneration,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<PaneId> initialPaneIdsInTraversalOrder,
    required bool ensureQuickTerminalContext,
    required int updatedAtUtcMicros,
    required TerminalNoteBodyCopyEffect copyEffect,
    required TerminalNoteExportDestinationChooser exportDestinationChooser,
    TerminalNoteNativeCapabilityInitializer? initializeNativeCapability,
    TerminalNoteNativeSurfaceChannelFactory? surfaceFactory,
    TerminalNoteStoreLocationResolver? locationResolver,
    TerminalNoteAuthorityStoreFactory? storeFactory,
    TerminalNoteContextIdGenerator? contextIdGenerator,
    TerminalNoteIdGenerator? noteIdGenerator,
    TerminalNoteUtcMicrosClock? clock,
    TerminalNoteNativePresentationState presentation =
        const TerminalNoteNativePresentationState(),
  }) async {
    if (!_isValidConfiguration(configuration) ||
        !configuration.surfaceEnabled ||
        authorityGeneration <= 0 ||
        authorityGeneration > TerminalNoteAuthorityLimits.maximumSequence ||
        updatedAtUtcMicros < 0 ||
        updatedAtUtcMicros > TerminalNoteAuthorityLimits.maximumSequence) {
      return TerminalNoteSubsystemStartResult.failure(
        TerminalNoteApplicationCapability.unavailable,
      );
    }
    final List<PaneId> paneIds = List<PaneId>.unmodifiable(
      initialPaneIdsInTraversalOrder,
    );
    if (paneIds.toSet().length != paneIds.length) {
      return TerminalNoteSubsystemStartResult.failure(
        TerminalNoteApplicationCapability.unavailable,
      );
    }
    try {
      (initializeNativeCapability ?? TerminalNotesMacos.initialize)();
    } on Object {
      return TerminalNoteSubsystemStartResult.failure(
        TerminalNoteApplicationCapability.unavailable,
      );
    }

    final TerminalNoteStoreLocation location;
    try {
      location =
          (locationResolver ?? TerminalNoteStoreLocation.fromEnvironment)(
            Map<String, String>.unmodifiable(environment),
          );
    } on Object {
      return TerminalNoteSubsystemStartResult.failure(
        TerminalNoteApplicationCapability.unavailable,
      );
    }

    final TerminalNoteAuthority authority;
    try {
      final TerminalNoteAuthorityStoreFactory? selectedFactory = storeFactory;
      if (selectedFactory == null) {
        authority = await TerminalNoteAuthority.startWorker(
          location: location,
          authorityGeneration: authorityGeneration,
          restoration: restoration,
          paneIdsInTraversalOrder: paneIds,
          ensureQuickTerminalContext: ensureQuickTerminalContext,
          updatedAtUtcMicros: updatedAtUtcMicros,
          idGenerator: contextIdGenerator,
          noteIdGenerator: noteIdGenerator,
        );
      } else {
        final TerminalNoteAuthorityStoreStartup startup = await selectedFactory
            .start(
              location: location,
              authorityGeneration: authorityGeneration,
            );
        authority = await TerminalNoteAuthority.start(
          authorityGeneration: authorityGeneration,
          store: startup.store,
          loadResult: startup.loadResult,
          restoration: restoration,
          paneIdsInTraversalOrder: paneIds,
          ensureQuickTerminalContext: ensureQuickTerminalContext,
          updatedAtUtcMicros: updatedAtUtcMicros,
          idGenerator: contextIdGenerator,
          noteIdGenerator: noteIdGenerator,
        );
      }
    } on Object {
      return TerminalNoteSubsystemStartResult.failure(
        TerminalNoteApplicationCapability.unavailable,
      );
    }
    final TerminalNoteApplicationCapability capability = _applicationCapability(
      authority,
    );
    if (capability != TerminalNoteApplicationCapability.available ||
        authority.livePaneCount != paneIds.length ||
        paneIds.any(
          (PaneId paneId) => authority.contextForPane(paneId) == null,
        )) {
      try {
        await authority.stop();
      } on Object {
        // Startup classification stays content-free even if cleanup fails.
      }
      return TerminalNoteSubsystemStartResult.failure(
        capability == TerminalNoteApplicationCapability.available
            ? TerminalNoteApplicationCapability.unavailable
            : capability,
      );
    }
    return TerminalNoteSubsystemStartResult.available(
      TerminalNoteProductSubsystem._(
        authority: authority,
        configuration: configuration,
        surfaceFactory: surfaceFactory ?? _openNativeSurface,
        clock: clock ?? () => DateTime.now().toUtc().microsecondsSinceEpoch,
        copyEffect: copyEffect,
        exportDestinationChooser: exportDestinationChooser,
        initialPaneIds: paneIds,
        presentation: presentation,
      ),
    );
  }

  static int _debugLiveProductSubsystemCount = 0;

  static int get debugLiveProductSubsystemCount =>
      _debugLiveProductSubsystemCount;

  final TerminalNoteAuthority _authority;
  final TerminalNoteNativeSurfaceChannelFactory _surfaceFactory;
  final TerminalNoteUtcMicrosClock _clock;
  final TerminalNoteBodyCopyEffect _copyEffect;
  final TerminalNoteExportDestinationChooser _exportDestinationChooser;
  final Map<PaneId, TerminalNoteContextKind> _paneKinds =
      <PaneId, TerminalNoteContextKind>{};
  final Map<PaneId, bool> _eligibleFocusByPane = <PaneId, bool>{};
  final Map<PaneId, _TerminalNoteProductSurface> _surfaces =
      <PaneId, _TerminalNoteProductSurface>{};
  TerminalNoteProductSurfaceEventHandler? _surfaceEventHandler;
  Future<void> _topologyTail = Future<void>.value();
  TerminalNoteFeatureConfiguration _configuration;
  TerminalNoteNativePresentationState _presentation;
  Future<void>? _shutdownFuture;
  Future<TerminalNoteAuthorityShutdownResult>? _applicationShutdownFuture;
  bool _stopping = false;
  bool _stopped = false;
  bool _debugRetired = false;

  TerminalNoteAuthorityCapability get capability => _authority.capability;
  bool get isStopped => _stopped;
  int get livePaneCount => _paneKinds.length;
  int get liveSurfaceCount => _surfaces.length;
  int get nativeSurfaceCount => _surfaces.values
      .where((_TerminalNoteProductSurface value) => value.hostAttached)
      .length;

  bool hasPane(PaneId paneId) => _paneKinds.containsKey(paneId);

  int? surfaceGenerationForPane(PaneId paneId) =>
      _surfaces[paneId]?.surfaceGeneration;

  @override
  bool canPerformAction(PaneId paneId, TerminalNoteProductActionKind action) {
    if (!_isRunning) return false;
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    final TerminalNoteSurfaceProjection? projection =
        surface?.adapter.lastAuthorityProjection;
    if (surface == null ||
        !surface.hostAttached ||
        surface.adapter.isDisposed ||
        projection == null ||
        projection.editorMode != TerminalNoteEditorMode.inactive ||
        projection.draftGeneration != 0) {
      return false;
    }
    return switch (action) {
      TerminalNoteProductActionKind.newNote ||
      TerminalNoteProductActionKind.toggleNotes => true,
    };
  }

  @override
  Future<TerminalNoteProductTopologyResult> performAction(
    PaneId paneId,
    TerminalNoteProductActionKind action,
  ) => _serialize(() async {
    if (!canPerformAction(paneId, action)) return _unavailable();
    final _TerminalNoteProductSurface surface = _surfaces[paneId]!;
    final TerminalNoteSurfaceProjection projection =
        surface.adapter.lastAuthorityProjection!;
    final TerminalNoteSurfaceIntentResult result;
    try {
      result = await _authority.submitApplicationSurfaceAction(
        sequence: _authority.nextSequence(),
        paneId: paneId,
        surfaceGeneration: projection.surfaceGeneration,
        projectionGeneration: projection.projectionGeneration,
        expectedStoreRevision: projection.storeRevision,
        action: switch (action) {
          TerminalNoteProductActionKind.newNote =>
            TerminalNoteApplicationSurfaceAction.newNote,
          TerminalNoteProductActionKind.toggleNotes =>
            TerminalNoteApplicationSurfaceAction.toggleNotes,
        },
      );
    } on Object {
      return _unavailable();
    }
    return TerminalNoteProductTopologyResult(
      _fromSurfaceIntent(result),
      surfaceGeneration: result.projection?.surfaceGeneration,
    );
  });

  @override
  void applyLiveConfiguration(TerminalNoteFeatureConfiguration configuration) {
    _requireRunning();
    if (!_isValidConfiguration(configuration) ||
        configuration.notes != _configuration.notes ||
        configuration.notesOnReturn != _configuration.notesOnReturn ||
        configuration.notesNextPrompt != _configuration.notesNextPrompt) {
      throw ArgumentError('Note live configuration is invalid');
    }
    _configuration = configuration;
    _presentation = _presentationWithFont(_presentation, configuration);
    _applyPresentationToLiveSurfaces();
  }

  @override
  void updatePresentation(TerminalNoteNativePresentationState presentation) {
    _requireRunning();
    _presentation = _presentationWithFont(presentation, _configuration);
    _applyPresentationToLiveSurfaces();
  }

  Future<TerminalNoteProductTopologyResult> bindPane({
    required PaneId paneId,
    TerminalNoteContextKind kind = TerminalNoteContextKind.standard,
  }) => _serialize(() async {
    if (!_isRunning) return _unavailable();
    if (_paneKinds.containsKey(paneId)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.duplicate,
      );
    }
    if (kind == TerminalNoteContextKind.quickTerminal &&
        _paneKinds.values.contains(TerminalNoteContextKind.quickTerminal)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.busy,
      );
    }
    final TerminalNoteAuthorityMutationResult result = await _authority
        .bindPane(
          sequence: _authority.nextSequence(),
          paneId: paneId,
          kind: kind,
        );
    if (result.isAccepted) _paneKinds[paneId] = kind;
    return _fromAuthorityMutation(result);
  });

  Future<TerminalNoteProductTopologyResult> closePane({
    required PaneId paneId,
    required int updatedAtUtcMicros,
  }) => _serialize(() async {
    if (!_isRunning) return _unavailable();
    if (updatedAtUtcMicros < 0 ||
        updatedAtUtcMicros > TerminalNoteAuthorityLimits.maximumSequence) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.rejected,
      );
    }
    if (!_paneKinds.containsKey(paneId)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
    }
    await _detachSurface(paneId);
    _paneKinds.remove(paneId);
    _eligibleFocusByPane.remove(paneId);
    final TerminalNoteAuthorityMutationResult result = await _authority
        .closePane(
          sequence: _authority.nextSequence(),
          paneId: paneId,
          updatedAtUtcMicros: updatedAtUtcMicros,
        );
    return _fromAuthorityMutation(result);
  });

  Future<TerminalNoteProductTopologyResult> attachSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  }) => _serialize(() => _attachSurface(paneId, configuration));

  Future<TerminalNoteProductTopologyResult> updateSurface({
    required PaneId paneId,
    required TerminalNoteProductSurfaceConfiguration configuration,
  }) => _serialize(() => _updateSurface(paneId, configuration));

  Future<TerminalNoteProductTopologyResult> detachSurface(PaneId paneId) =>
      _serialize(() => _detachSurface(paneId));

  @override
  Future<TerminalNoteProductTopologyResult> pumpSurfaceIntent(PaneId paneId) =>
      _serialize(() => _pumpSurfaceIntent(paneId));

  @override
  void setSurfaceEventHandler(TerminalNoteProductSurfaceEventHandler? handler) {
    _surfaceEventHandler = handler;
  }

  @override
  TerminalNoteProductInteractionSnapshot? interactionSnapshotForPane(
    PaneId paneId,
  ) {
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    final TerminalNoteSurfaceProjection? projection =
        surface?.adapter.lastAuthorityProjection;
    if (surface == null || projection == null || surface.adapter.isDisposed) {
      return null;
    }
    try {
      final TerminalNotesNativeSnapshot native = surface.adapter.snapshot;
      if (native.surfaceGeneration != projection.surfaceGeneration ||
          native.projectionGeneration != projection.projectionGeneration) {
        return null;
      }
      return TerminalNoteProductInteractionSnapshot(
        surfaceGeneration: projection.surfaceGeneration,
        visibility: projection.visibility,
        automaticPresentation: projection.automaticPresentation,
        editorMode: projection.editorMode,
        draftGeneration: projection.draftGeneration,
        editorDirty: native.editorDirty,
        confirmingDiscard: native.confirmingDiscard,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool focusSurface(PaneId paneId, TerminalNoteProductFocusTarget target) {
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null ||
        !surface.hostAttached ||
        surface.adapter.isDisposed) {
      return false;
    }
    try {
      return surface.adapter.focus(switch (target) {
        TerminalNoteProductFocusTarget.rail =>
          TerminalNotesNativeFocusTarget.rail,
        TerminalNoteProductFocusTarget.editor =>
          TerminalNotesNativeFocusTarget.editor,
      });
    } on Object {
      return false;
    }
  }

  @override
  bool presentDiscardConfirmation(PaneId paneId) {
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null ||
        !surface.hostAttached ||
        surface.adapter.isDisposed) {
      return false;
    }
    try {
      return surface.adapter.presentDiscardConfirmation();
    } on Object {
      return false;
    }
  }

  @override
  bool surfaceContainsPoint(
    PaneId paneId, {
    required double x,
    required double y,
  }) {
    if (!x.isFinite || !y.isFinite) return false;
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null ||
        !surface.hostAttached ||
        surface.adapter.isDisposed) {
      return false;
    }
    try {
      final TerminalNotesNativePresentation presentation =
          surface.adapter.presentation;
      bool contains(TerminalNotesRect rect) =>
          rect.width > 0 &&
          rect.height > 0 &&
          x >= rect.x &&
          x < rect.x + rect.width &&
          y >= rect.y &&
          y < rect.y + rect.height;
      return (presentation.badgeVisible && contains(presentation.badgeHit)) ||
          (presentation.railVisible && contains(presentation.rail));
    } on Object {
      return false;
    }
  }

  @override
  bool prepareSurfaceForHostTeardown(PaneId paneId) {
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null || !surface.hostAttached) return true;
    try {
      surface.adapter.detachFromHost();
      surface.hostAttached = false;
      // Host replacement is a composition transition, not a user Close.
      // Preserve the authority-owned visibility/editor state so the same
      // surface generation can resume on the replacement renderer.
      return true;
    } on Object {
      // Synchronous native destruction below is the final host-safety fence.
    }
    _surfaces.remove(paneId);
    surface
      ..hostAttached = false
      ..adapter.disposeSynchronously();
    return false;
  }

  @override
  Future<void> shutdown() {
    final Future<void>? existing = _shutdownFuture;
    if (existing != null) return existing;
    _stopping = true;
    return _shutdownFuture = _serialize(_runShutdown);
  }

  @override
  Future<TerminalNoteAuthorityShutdownResult> shutdownApplication({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    Duration drainTimeout = const Duration(seconds: 3),
  }) {
    final Future<TerminalNoteAuthorityShutdownResult>? existing =
        _applicationShutdownFuture;
    if (existing != null) return existing;
    if (_shutdownFuture != null) {
      return Future<TerminalNoteAuthorityShutdownResult>.error(
        StateError('Note product shutdown already started'),
      );
    }
    if (drainTimeout <= Duration.zero) {
      return Future<TerminalNoteAuthorityShutdownResult>.error(
        ArgumentError.value(drainTimeout, 'drainTimeout', 'must be positive'),
      );
    }
    _stopping = true;
    final Future<TerminalNoteAuthorityShutdownResult> future = _serialize(
      () => _runApplicationShutdown(
        capture: capture,
        updatedAtUtcMicros: updatedAtUtcMicros,
        commitRestoration: commitRestoration,
        drainTimeout: drainTimeout,
      ),
    );
    _applicationShutdownFuture = future;
    _shutdownFuture = future.then<void>((_) {});
    return future;
  }

  Future<TerminalNoteProductTopologyResult> _attachSurface(
    PaneId paneId,
    TerminalNoteProductSurfaceConfiguration configuration,
  ) async {
    if (!_isRunning) return _unavailable();
    if (!_paneKinds.containsKey(paneId)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
    }
    if (_surfaces.containsKey(paneId)) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.duplicate,
      );
    }
    final TerminalNoteProductTopologyResult? lifecycleFailure =
        _observeEligibleFocus(paneId, configuration);
    if (lifecycleFailure != null) return lifecycleFailure;
    final TerminalNoteNativeSurfaceAdapter adapter;
    try {
      adapter = TerminalNoteNativeSurfaceAdapter(
        channel: _surfaceFactory(),
        presentation: _presentationWithFont(
          configuration.presentation ?? _presentation,
          _configuration,
        ),
      );
      adapter.setNotificationHandler(() {
        if (!_stopping) _surfaceEventHandler?.call(paneId);
      });
    } on Object {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.nativeUnavailable,
      );
    }
    final TerminalNotesAttachDisposition nativeAttachment;
    try {
      nativeAttachment = adapter.attachToRenderer(
        rendererHandle: configuration.rendererIdentity.handle,
        rendererGeneration: configuration.rendererIdentity.generation,
      );
      if (nativeAttachment != TerminalNotesAttachDisposition.attached) {
        await adapter.dispose();
        return _fromNativeAttachment(nativeAttachment);
      }
      adapter.updateLayout(
        paneWidth: configuration.paneWidth,
        paneHeight: configuration.paneHeight,
        backingScale: configuration.backingScale,
        requestedRailWidth: configuration.requestedRailWidth,
      );
    } on Object {
      await adapter.dispose();
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.nativeUnavailable,
      );
    }

    final TerminalNoteSurfaceResult attached = _authority.attachSurface(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      port: adapter,
    );
    final int? surfaceGeneration =
        attached.projection?.surfaceGeneration ??
        adapter.lastAuthorityProjection?.surfaceGeneration;
    if (attached.disposition != TerminalNoteSurfaceDisposition.applied ||
        surfaceGeneration == null) {
      await adapter.dispose();
      return _fromAuthoritySurface(attached);
    }
    final TerminalNoteSurfaceResult updated = _authority.updateSurface(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      surfaceGeneration: surfaceGeneration,
      visibility: configuration.visibility,
      foreground: configuration.foreground,
      occluded: configuration.occluded,
    );
    if (updated.disposition != TerminalNoteSurfaceDisposition.applied) {
      await _cleanupAuthoritySurface(
        paneId: paneId,
        surfaceGeneration: surfaceGeneration,
        adapter: adapter,
      );
      return _fromAuthoritySurface(updated);
    }
    _surfaces[paneId] = _TerminalNoteProductSurface(
      adapter: adapter,
      surfaceGeneration: surfaceGeneration,
      configuration: configuration,
    );
    return TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
      surfaceGeneration: surfaceGeneration,
    );
  }

  Future<TerminalNoteProductTopologyResult> _updateSurface(
    PaneId paneId,
    TerminalNoteProductSurfaceConfiguration configuration,
  ) async {
    if (!_isRunning) return _unavailable();
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
    }
    final TerminalNoteProductTopologyResult? lifecycleFailure =
        _observeEligibleFocus(paneId, configuration);
    if (lifecycleFailure != null) return lifecycleFailure;
    final bool rendererChanged = !_sameRenderer(
      surface.configuration.rendererIdentity,
      configuration.rendererIdentity,
    );
    if (rendererChanged || !surface.hostAttached) {
      try {
        surface.adapter.detachFromHost();
        surface.hostAttached = false;
        final TerminalNotesAttachDisposition attachment = surface.adapter
            .attachToRenderer(
              rendererHandle: configuration.rendererIdentity.handle,
              rendererGeneration: configuration.rendererIdentity.generation,
            );
        if (attachment != TerminalNotesAttachDisposition.attached) {
          surface.configuration = configuration;
          final TerminalNoteProductTopologyResult? authorityFailure =
              await _hideOrRetireDetachedSurface(paneId, surface);
          if (authorityFailure != null) return authorityFailure;
          return _fromNativeAttachment(attachment);
        }
        surface.hostAttached = true;
      } on Object {
        surface
          ..hostAttached = false
          ..configuration = configuration;
        final TerminalNoteProductTopologyResult? authorityFailure =
            await _hideOrRetireDetachedSurface(paneId, surface);
        if (authorityFailure != null) return authorityFailure;
        return const TerminalNoteProductTopologyResult(
          TerminalNoteProductTopologyDisposition.nativeUnavailable,
        );
      }
    }
    try {
      surface.adapter
        ..updatePresentation(
          _presentationWithFont(
            configuration.presentation ?? _presentation,
            _configuration,
          ),
        )
        ..updateLayout(
          paneWidth: configuration.paneWidth,
          paneHeight: configuration.paneHeight,
          backingScale: configuration.backingScale,
          requestedRailWidth: configuration.requestedRailWidth,
        );
    } on Object {
      try {
        surface.adapter.detachFromHost();
      } on Object {
        // The adapter still owns deterministic destroy fallback.
      }
      surface
        ..hostAttached = false
        ..configuration = configuration;
      final TerminalNoteProductTopologyResult? authorityFailure =
          await _hideOrRetireDetachedSurface(paneId, surface);
      if (authorityFailure != null) return authorityFailure;
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.nativeUnavailable,
      );
    }
    surface.configuration = configuration;
    final TerminalNoteSurfaceVisibility authorityVisibility =
        surface.adapter.lastAuthorityProjection?.visibility ??
        configuration.visibility;
    final TerminalNoteSurfaceResult result = _authority.updateSurface(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      surfaceGeneration: surface.surfaceGeneration,
      visibility: authorityVisibility,
      foreground: configuration.foreground,
      occluded: configuration.occluded,
    );
    if (result.disposition != TerminalNoteSurfaceDisposition.applied) {
      _surfaces.remove(paneId);
      await surface.adapter.dispose();
      return _fromAuthoritySurface(result);
    }
    return TerminalNoteProductTopologyResult(
      TerminalNoteProductTopologyDisposition.applied,
      surfaceGeneration: surface.surfaceGeneration,
    );
  }

  Future<TerminalNoteProductTopologyResult> _detachSurface(
    PaneId paneId,
  ) async {
    final _TerminalNoteProductSurface? surface = _surfaces.remove(paneId);
    if (surface == null) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
    }
    TerminalNoteSurfaceResult result;
    try {
      result = await _authority.detachSurface(
        sequence: _authority.nextSequence(),
        paneId: paneId,
        surfaceGeneration: surface.surfaceGeneration,
      );
    } on Object {
      await surface.adapter.dispose();
      return _unavailable();
    }
    if (result.disposition != TerminalNoteSurfaceDisposition.applied) {
      await surface.adapter.dispose();
    }
    return _fromAuthoritySurface(result);
  }

  Future<TerminalNoteProductTopologyResult> _pumpSurfaceIntent(
    PaneId paneId,
  ) async {
    if (!_isRunning) return _unavailable();
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null || !surface.hostAttached) {
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
    }
    final TerminalNotesNativeIntent? intent;
    try {
      intent = surface.adapter.takeIntent();
    } on Object {
      await _retireFaultedSurface(paneId);
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.nativeUnavailable,
      );
    }
    if (intent == null) {
      return TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.noChange,
        surfaceGeneration: surface.surfaceGeneration,
      );
    }

    final bool onReturnIntent =
        intent.kind == TerminalNotesIntentKind.saveAlwaysAvailable ||
        intent.kind == TerminalNotesIntentKind.saveOnReturn ||
        intent.kind == TerminalNotesIntentKind.armOnReturn ||
        intent.kind == TerminalNotesIntentKind.makeAlwaysAvailable;
    if (onReturnIntent && !_configuration.onReturnEnabled) {
      return _completeNativeIntent(
        paneId: paneId,
        surface: surface,
        intent: intent,
        disposition: TerminalNotesResultDisposition.rejected,
        storeRevision: intent.expectedStoreRevision,
        projectionGeneration: intent.projectionGeneration,
        topologyDisposition: TerminalNoteProductTopologyDisposition.rejected,
      );
    }

    TerminalNoteApprovedExportPath? exportDestination;
    if (intent.kind == TerminalNotesIntentKind.export) {
      final TerminalNoteSurfaceProjection? projection =
          surface.adapter.lastAuthorityProjection;
      if (projection == null ||
          intent.surfaceGeneration != projection.surfaceGeneration ||
          intent.projectionGeneration != projection.projectionGeneration ||
          intent.expectedStoreRevision != projection.storeRevision ||
          intent.eventGeneration <= 0 ||
          intent.draftGeneration != 0 ||
          intent.draftGeneration != projection.draftGeneration ||
          intent.cardToken != null ||
          intent.body != null ||
          intent.color != null ||
          projection.visibility != TerminalNoteSurfaceVisibility.expanded ||
          projection.editorMode != TerminalNoteEditorMode.inactive) {
        return _completeNativeIntent(
          paneId: paneId,
          surface: surface,
          intent: intent,
          disposition: TerminalNotesResultDisposition.rejected,
          storeRevision: intent.expectedStoreRevision,
          projectionGeneration: intent.projectionGeneration,
          topologyDisposition: TerminalNoteProductTopologyDisposition.rejected,
        );
      }
      try {
        exportDestination = _exportDestinationChooser(_presentation.locale);
      } on Object {
        return _completeNativeIntent(
          paneId: paneId,
          surface: surface,
          intent: intent,
          disposition: TerminalNotesResultDisposition.unavailable,
          storeRevision: intent.expectedStoreRevision,
          projectionGeneration: intent.projectionGeneration,
          topologyDisposition:
              TerminalNoteProductTopologyDisposition.unavailable,
        );
      }
      if (exportDestination == null) {
        return _completeNativeIntent(
          paneId: paneId,
          surface: surface,
          intent: intent,
          disposition: TerminalNotesResultDisposition.rejected,
          storeRevision: intent.expectedStoreRevision,
          projectionGeneration: intent.projectionGeneration,
          topologyDisposition: TerminalNoteProductTopologyDisposition.rejected,
        );
      }
    }

    final TerminalNoteSurfaceIntentKind authorityKind = switch (intent.kind) {
      TerminalNotesIntentKind.open => TerminalNoteSurfaceIntentKind.open,
      TerminalNotesIntentKind.close => TerminalNoteSurfaceIntentKind.close,
      TerminalNotesIntentKind.selectCard =>
        TerminalNoteSurfaceIntentKind.selectCard,
      TerminalNotesIntentKind.beginCreate =>
        TerminalNoteSurfaceIntentKind.beginCreate,
      TerminalNotesIntentKind.beginEdit =>
        TerminalNoteSurfaceIntentKind.beginEdit,
      TerminalNotesIntentKind.showCurrent =>
        TerminalNoteSurfaceIntentKind.showCurrent,
      TerminalNotesIntentKind.showDetached =>
        TerminalNoteSurfaceIntentKind.showDetached,
      TerminalNotesIntentKind.previousPage =>
        TerminalNoteSurfaceIntentKind.previousPage,
      TerminalNotesIntentKind.nextPage =>
        TerminalNoteSurfaceIntentKind.nextPage,
      TerminalNotesIntentKind.cancel =>
        TerminalNoteSurfaceIntentKind.cancelEditor,
      TerminalNotesIntentKind.save => TerminalNoteSurfaceIntentKind.save,
      TerminalNotesIntentKind.saveAlwaysAvailable =>
        TerminalNoteSurfaceIntentKind.saveAlwaysAvailable,
      TerminalNotesIntentKind.saveOnReturn =>
        TerminalNoteSurfaceIntentKind.saveOnReturn,
      TerminalNotesIntentKind.armOnReturn =>
        TerminalNoteSurfaceIntentKind.armOnReturn,
      TerminalNotesIntentKind.makeAlwaysAvailable =>
        TerminalNoteSurfaceIntentKind.makeAlwaysAvailable,
      TerminalNotesIntentKind.changeColor =>
        TerminalNoteSurfaceIntentKind.changeColor,
      TerminalNotesIntentKind.moveEarlier =>
        TerminalNoteSurfaceIntentKind.moveEarlier,
      TerminalNotesIntentKind.moveLater =>
        TerminalNoteSurfaceIntentKind.moveLater,
      TerminalNotesIntentKind.resolve => TerminalNoteSurfaceIntentKind.resolve,
      TerminalNotesIntentKind.reopen => TerminalNoteSurfaceIntentKind.reopen,
      TerminalNotesIntentKind.delete => TerminalNoteSurfaceIntentKind.delete,
      TerminalNotesIntentKind.reattach =>
        TerminalNoteSurfaceIntentKind.reattach,
      TerminalNotesIntentKind.copy => TerminalNoteSurfaceIntentKind.copy,
      TerminalNotesIntentKind.export => TerminalNoteSurfaceIntentKind.export,
    };

    final bool requiresTimestamp = switch (authorityKind) {
      TerminalNoteSurfaceIntentKind.save ||
      TerminalNoteSurfaceIntentKind.saveAlwaysAvailable ||
      TerminalNoteSurfaceIntentKind.saveOnReturn ||
      TerminalNoteSurfaceIntentKind.changeColor ||
      TerminalNoteSurfaceIntentKind.moveEarlier ||
      TerminalNoteSurfaceIntentKind.moveLater ||
      TerminalNoteSurfaceIntentKind.resolve ||
      TerminalNoteSurfaceIntentKind.reopen ||
      TerminalNoteSurfaceIntentKind.delete ||
      TerminalNoteSurfaceIntentKind.reattach => true,
      _ => false,
    };
    final int? timestamp = requiresTimestamp ? _clock() : null;
    if (timestamp != null &&
        (timestamp < 0 ||
            timestamp > TerminalNoteAuthorityLimits.maximumSequence)) {
      return _completeNativeIntent(
        paneId: paneId,
        surface: surface,
        intent: intent,
        disposition: TerminalNotesResultDisposition.unavailable,
        storeRevision: intent.expectedStoreRevision,
        projectionGeneration: intent.projectionGeneration,
        topologyDisposition: TerminalNoteProductTopologyDisposition.unavailable,
      );
    }

    final TerminalNoteSurfaceIntentResult authorityResult;
    try {
      authorityResult = await _authority.submitSurfaceIntent(
        sequence: _authority.nextSequence(),
        paneId: paneId,
        surfaceGeneration: intent.surfaceGeneration,
        projectionGeneration: intent.projectionGeneration,
        eventGeneration: intent.eventGeneration,
        draftGeneration: intent.draftGeneration,
        cardToken: intent.cardToken == null
            ? null
            : TerminalNoteCardToken(intent.cardToken!),
        expectedStoreRevision: intent.expectedStoreRevision,
        kind: authorityKind,
        updatedAtUtcMicros: timestamp,
        body: intent.body,
        color: _authorityColor(intent.color),
        exportDestination: exportDestination,
      );
    } on Object {
      return _completeNativeIntent(
        paneId: paneId,
        surface: surface,
        intent: intent,
        disposition: TerminalNotesResultDisposition.unavailable,
        storeRevision: intent.expectedStoreRevision,
        projectionGeneration: intent.projectionGeneration,
        topologyDisposition: TerminalNoteProductTopologyDisposition.unavailable,
      );
    }
    if (authorityKind == TerminalNoteSurfaceIntentKind.copy &&
        authorityResult.isAccepted &&
        authorityResult.projection != null) {
      var copied = false;
      try {
        copied = _copyEffect(intent.body!);
      } on Object {
        copied = false;
      }
      if (!copied) {
        return _completeNativeIntent(
          paneId: paneId,
          surface: surface,
          intent: intent,
          disposition: TerminalNotesResultDisposition.unavailable,
          storeRevision: intent.expectedStoreRevision,
          projectionGeneration: intent.projectionGeneration,
          topologyDisposition:
              TerminalNoteProductTopologyDisposition.unavailable,
        );
      }
    }
    final bool accepted =
        authorityResult.isAccepted && authorityResult.projection != null;
    final TerminalNotesResultDisposition nativeDisposition = accepted
        ? TerminalNotesResultDisposition.accepted
        : switch (authorityResult.disposition) {
            TerminalNoteAuthorityMutationDisposition.busy =>
              TerminalNotesResultDisposition.busy,
            TerminalNoteAuthorityMutationDisposition.unavailable ||
            TerminalNoteAuthorityMutationDisposition.failed =>
              TerminalNotesResultDisposition.unavailable,
            TerminalNoteAuthorityMutationDisposition.rejected
                when (authorityKind == TerminalNoteSurfaceIntentKind.save ||
                        authorityKind ==
                            TerminalNoteSurfaceIntentKind.saveAlwaysAvailable ||
                        authorityKind ==
                            TerminalNoteSurfaceIntentKind.saveOnReturn) &&
                    authorityResult.mutationFailure ==
                        TerminalNoteMutationFailure.revisionConflict =>
              TerminalNotesResultDisposition.conflict,
            _ => TerminalNotesResultDisposition.rejected,
          };
    final TerminalNoteSurfaceProjection? projection = accepted
        ? authorityResult.projection
        : null;
    return _completeNativeIntent(
      paneId: paneId,
      surface: surface,
      intent: intent,
      disposition: nativeDisposition,
      storeRevision: projection?.storeRevision ?? intent.expectedStoreRevision,
      projectionGeneration:
          projection?.projectionGeneration ?? intent.projectionGeneration,
      topologyDisposition: _fromSurfaceIntent(authorityResult),
    );
  }

  Future<TerminalNoteProductTopologyResult> _completeNativeIntent({
    required PaneId paneId,
    required _TerminalNoteProductSurface surface,
    required TerminalNotesNativeIntent intent,
    required TerminalNotesResultDisposition disposition,
    required BigInt storeRevision,
    required int projectionGeneration,
    required TerminalNoteProductTopologyDisposition topologyDisposition,
  }) async {
    try {
      final TerminalNotesResultApplyDisposition applied = surface.adapter
          .applyResult(
            TerminalNotesNativeResult(
              intent: intent,
              disposition: disposition,
              newStoreRevision: storeRevision,
              newProjectionGeneration: projectionGeneration,
            ),
          );
      if (applied != TerminalNotesResultApplyDisposition.accepted) {
        await _retireFaultedSurface(paneId);
        return const TerminalNoteProductTopologyResult(
          TerminalNoteProductTopologyDisposition.nativeUnavailable,
        );
      }
    } on Object {
      await _retireFaultedSurface(paneId);
      return const TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.nativeUnavailable,
      );
    }
    return TerminalNoteProductTopologyResult(
      topologyDisposition,
      surfaceGeneration: surface.surfaceGeneration,
    );
  }

  Future<void> _retireFaultedSurface(PaneId paneId) async {
    try {
      await _detachSurface(paneId);
    } on Object {
      final _TerminalNoteProductSurface? surface = _surfaces.remove(paneId);
      await surface?.adapter.dispose();
    }
  }

  TerminalNoteProductTopologyResult? _observeEligibleFocus(
    PaneId paneId,
    TerminalNoteProductSurfaceConfiguration configuration,
  ) {
    if (!_configuration.onReturnEnabled) return null;
    final bool eligible = configuration.foreground && !configuration.occluded;
    if (_eligibleFocusByPane[paneId] == eligible) return null;
    final TerminalNoteLifecycleResult result = _authority.observeEligibleFocus(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      isEligible: eligible,
    );
    switch (result.disposition) {
      case TerminalNoteLifecycleDisposition.accepted:
      case TerminalNoteLifecycleDisposition.coalesced:
      case TerminalNoteLifecycleDisposition.duplicate:
      case TerminalNoteLifecycleDisposition.overflowed:
        _eligibleFocusByPane[paneId] = eligible;
        return null;
      case TerminalNoteLifecycleDisposition.stale:
        return const TerminalNoteProductTopologyResult(
          TerminalNoteProductTopologyDisposition.stale,
        );
      case TerminalNoteLifecycleDisposition.busy:
        return const TerminalNoteProductTopologyResult(
          TerminalNoteProductTopologyDisposition.busy,
        );
      case TerminalNoteLifecycleDisposition.unavailable:
        return const TerminalNoteProductTopologyResult(
          TerminalNoteProductTopologyDisposition.unavailable,
        );
    }
  }

  Future<TerminalNoteProductTopologyResult?> _hideOrRetireDetachedSurface(
    PaneId paneId,
    _TerminalNoteProductSurface surface,
  ) async {
    final TerminalNoteSurfaceResult result = _authority.updateSurface(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      surfaceGeneration: surface.surfaceGeneration,
      visibility: TerminalNoteSurfaceVisibility.collapsed,
      foreground: false,
      occluded: true,
    );
    if (result.disposition == TerminalNoteSurfaceDisposition.applied) {
      return null;
    }
    _surfaces.remove(paneId);
    await surface.adapter.dispose();
    return _fromAuthoritySurface(result);
  }

  Future<void> _cleanupAuthoritySurface({
    required PaneId paneId,
    required int surfaceGeneration,
    required TerminalNoteNativeSurfaceAdapter adapter,
  }) async {
    try {
      final TerminalNoteSurfaceResult result = await _authority.detachSurface(
        sequence: _authority.nextSequence(),
        paneId: paneId,
        surfaceGeneration: surfaceGeneration,
      );
      if (result.disposition != TerminalNoteSurfaceDisposition.applied) {
        await adapter.dispose();
      }
    } on Object {
      await adapter.dispose();
    }
  }

  void _applyPresentationToLiveSurfaces() {
    for (final MapEntry<PaneId, _TerminalNoteProductSurface> entry
        in _surfaces.entries) {
      final _TerminalNoteProductSurface surface = entry.value;
      surface.adapter.updatePresentation(
        _presentationWithFont(
          surface.configuration.presentation ?? _presentation,
          _configuration,
        ),
      );
      final TerminalNoteProductSurfaceConfiguration configuration =
          surface.configuration;
      final TerminalNoteSurfaceResult result = _authority.updateSurface(
        sequence: _authority.nextSequence(),
        paneId: entry.key,
        surfaceGeneration: surface.surfaceGeneration,
        visibility: surface.hostAttached
            ? configuration.visibility
            : TerminalNoteSurfaceVisibility.collapsed,
        foreground: surface.hostAttached && configuration.foreground,
        occluded: !surface.hostAttached || configuration.occluded,
      );
      if (result.disposition != TerminalNoteSurfaceDisposition.applied) {
        throw StateError('Note presentation projection was rejected');
      }
    }
  }

  Future<void> _runShutdown() async {
    _surfaceEventHandler = null;
    try {
      await _authority.stop();
    } finally {
      await _releaseProductOwnership();
    }
  }

  Future<TerminalNoteAuthorityShutdownResult> _runApplicationShutdown({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    required Duration drainTimeout,
  }) async {
    _surfaceEventHandler = null;
    try {
      return await _authority.shutdownApplication(
        capture: capture,
        updatedAtUtcMicros: updatedAtUtcMicros,
        commitRestoration: commitRestoration,
        drainTimeout: drainTimeout,
      );
    } finally {
      await _releaseProductOwnership();
    }
  }

  Future<void> _releaseProductOwnership() async {
    final List<_TerminalNoteProductSurface> remaining = _surfaces.values.toList(
      growable: false,
    );
    _surfaces.clear();
    _paneKinds.clear();
    _eligibleFocusByPane.clear();
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final _TerminalNoteProductSurface surface in remaining) {
      try {
        await surface.adapter.dispose();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    _stopped = true;
    _retireDebugOwner();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _topologyTail = _topologyTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  bool get _isRunning => !_stopping && !_stopped;

  void _requireRunning() {
    if (!_isRunning) throw StateError('Note product subsystem is stopped');
  }

  void _retireDebugOwner() {
    if (_debugRetired) return;
    _debugRetired = true;
    _debugLiveProductSubsystemCount--;
  }

  static TerminalNoteProductTopologyResult _fromAuthorityMutation(
    TerminalNoteAuthorityMutationResult result,
  ) => TerminalNoteProductTopologyResult(switch (result.disposition) {
    TerminalNoteAuthorityMutationDisposition.committed ||
    TerminalNoteAuthorityMutationDisposition.runtimeApplied =>
      TerminalNoteProductTopologyDisposition.applied,
    TerminalNoteAuthorityMutationDisposition.noChange =>
      TerminalNoteProductTopologyDisposition.noChange,
    TerminalNoteAuthorityMutationDisposition.duplicate =>
      TerminalNoteProductTopologyDisposition.duplicate,
    TerminalNoteAuthorityMutationDisposition.stale =>
      TerminalNoteProductTopologyDisposition.stale,
    TerminalNoteAuthorityMutationDisposition.busy =>
      TerminalNoteProductTopologyDisposition.busy,
    TerminalNoteAuthorityMutationDisposition.rejected =>
      TerminalNoteProductTopologyDisposition.rejected,
    TerminalNoteAuthorityMutationDisposition.unavailable ||
    TerminalNoteAuthorityMutationDisposition.failed =>
      TerminalNoteProductTopologyDisposition.unavailable,
  });

  static TerminalNoteProductTopologyResult _fromAuthoritySurface(
    TerminalNoteSurfaceResult result,
  ) => TerminalNoteProductTopologyResult(switch (result.disposition) {
    TerminalNoteSurfaceDisposition.applied =>
      TerminalNoteProductTopologyDisposition.applied,
    TerminalNoteSurfaceDisposition.duplicate =>
      TerminalNoteProductTopologyDisposition.duplicate,
    TerminalNoteSurfaceDisposition.stale =>
      TerminalNoteProductTopologyDisposition.stale,
    TerminalNoteSurfaceDisposition.rejected =>
      TerminalNoteProductTopologyDisposition.rejected,
    TerminalNoteSurfaceDisposition.unavailable =>
      TerminalNoteProductTopologyDisposition.unavailable,
  }, surfaceGeneration: result.projection?.surfaceGeneration);

  static TerminalNoteProductTopologyDisposition _fromSurfaceIntent(
    TerminalNoteSurfaceIntentResult result,
  ) => switch (result.disposition) {
    TerminalNoteAuthorityMutationDisposition.committed ||
    TerminalNoteAuthorityMutationDisposition.runtimeApplied =>
      TerminalNoteProductTopologyDisposition.applied,
    TerminalNoteAuthorityMutationDisposition.noChange =>
      TerminalNoteProductTopologyDisposition.noChange,
    TerminalNoteAuthorityMutationDisposition.duplicate =>
      TerminalNoteProductTopologyDisposition.duplicate,
    TerminalNoteAuthorityMutationDisposition.stale =>
      TerminalNoteProductTopologyDisposition.stale,
    TerminalNoteAuthorityMutationDisposition.busy =>
      TerminalNoteProductTopologyDisposition.busy,
    TerminalNoteAuthorityMutationDisposition.rejected =>
      TerminalNoteProductTopologyDisposition.rejected,
    TerminalNoteAuthorityMutationDisposition.unavailable ||
    TerminalNoteAuthorityMutationDisposition.failed =>
      TerminalNoteProductTopologyDisposition.unavailable,
  };

  static NoteColorKey? _authorityColor(TerminalNotesColor? color) =>
      switch (color) {
        null => null,
        TerminalNotesColor.neutral => NoteColorKey.neutral,
        TerminalNotesColor.yellow => NoteColorKey.yellow,
        TerminalNotesColor.blue => NoteColorKey.blue,
        TerminalNotesColor.green => NoteColorKey.green,
        TerminalNotesColor.pink => NoteColorKey.pink,
        TerminalNotesColor.purple => NoteColorKey.purple,
      };

  static TerminalNoteProductTopologyResult _fromNativeAttachment(
    TerminalNotesAttachDisposition disposition,
  ) => TerminalNoteProductTopologyResult(switch (disposition) {
    TerminalNotesAttachDisposition.attached =>
      TerminalNoteProductTopologyDisposition.applied,
    TerminalNotesAttachDisposition.rendererUnavailable =>
      TerminalNoteProductTopologyDisposition.nativeUnavailable,
    TerminalNotesAttachDisposition.busy =>
      TerminalNoteProductTopologyDisposition.busy,
  });

  static const TerminalNoteProductTopologyResult _unavailableResult =
      TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.unavailable,
      );

  static TerminalNoteProductTopologyResult _unavailable() => _unavailableResult;

  static TerminalNoteApplicationCapability _applicationCapability(
    TerminalNoteAuthority authority,
  ) => switch (authority.capability) {
    TerminalNoteAuthorityCapability.ready =>
      TerminalNoteApplicationCapability.available,
    TerminalNoteAuthorityCapability.recoveryRequired =>
      TerminalNoteApplicationCapability.recoveryRequired,
    TerminalNoteAuthorityCapability.upgradeRequired =>
      TerminalNoteApplicationCapability.incompatibleStore,
    TerminalNoteAuthorityCapability.unavailable
        when authority.storeFailure == TerminalNoteStoreFailure.lockBusy =>
      TerminalNoteApplicationCapability.inUseByOtherProcess,
    _ => TerminalNoteApplicationCapability.unavailable,
  };

  static TerminalNoteNativePresentationState _presentationWithFont(
    TerminalNoteNativePresentationState presentation,
    TerminalNoteFeatureConfiguration configuration,
  ) => TerminalNoteNativePresentationState(
    featureState: presentation.featureState,
    surfaceState: presentation.surfaceState,
    readyCue: presentation.readyCue,
    darkAppearance: presentation.darkAppearance,
    increaseContrast: presentation.increaseContrast,
    differentiateWithoutColor: presentation.differentiateWithoutColor,
    reduceMotion: presentation.reduceMotion,
    systemBadgeVisible: presentation.systemBadgeVisible,
    onReturnEnabled: configuration.onReturnEnabled,
    locale: presentation.locale,
    bodyFontMilliPoints: (configuration.fontSize * 1000).round(),
  );

  static bool _isValidConfiguration(
    TerminalNoteFeatureConfiguration configuration,
  ) =>
      configuration.fontSize.isFinite &&
      configuration.fontSize >= 12 &&
      configuration.fontSize <= 24;

  static TerminalNoteNativeSurfaceChannel _openNativeSurface() =>
      TerminalNoteFfiSurfaceChannel(TerminalNotesNativeSurface());

  static bool _sameRenderer(
    TerminalMetalRendererCompositionIdentity left,
    TerminalMetalRendererCompositionIdentity right,
  ) => left.handle == right.handle && left.generation == right.generation;
}

final class _TerminalNoteProductSurface {
  _TerminalNoteProductSurface({
    required this.adapter,
    required this.surfaceGeneration,
    required this.configuration,
  });

  final TerminalNoteNativeSurfaceAdapter adapter;
  final int surfaceGeneration;
  TerminalNoteProductSurfaceConfiguration configuration;
  bool hostAttached = true;
}
