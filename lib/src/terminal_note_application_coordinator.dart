import 'dart:async';

import 'terminal_application_state.dart';
import 'terminal_note_authority.dart';
import 'terminal_note_composition.dart';
import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_native_adapter.dart';
import 'terminal_note_product_subsystem.dart';
import 'terminal_note_projection.dart';
import 'terminal_pane.dart';
import 'terminal_product_configuration.dart';
import 'terminal_window_interaction.dart';

typedef TerminalNoteApplicationClock = int Function();
typedef TerminalNoteTerminalFocusHandler = bool Function();
typedef TerminalNoteApplicationErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

enum TerminalNoteApplicationPointerPhase { down, drag, up, moved, cancel }

enum TerminalNoteApplicationActionKind { newNote, toggleNotes, focusTerminal }

/// Content-free outcome for application-owned ordered Note shutdown.
final class TerminalNoteApplicationShutdownResult {
  const TerminalNoteApplicationShutdownResult({
    required this.compositionDisposition,
    required this.authorityResult,
  });

  final TerminalNoteCompositionShutdownDisposition compositionDisposition;
  final TerminalNoteAuthorityShutdownResult? authorityResult;

  bool get isSuccess =>
      compositionDisposition !=
          TerminalNoteCompositionShutdownDisposition.failed &&
      (authorityResult == null || authorityResult!.isSuccess);
}

/// Content-free logical placement of one pane in the application hierarchy.
final class TerminalNoteApplicationPaneBinding {
  const TerminalNoteApplicationPaneBinding({
    required this.paneId,
    required this.windowId,
    this.kind = TerminalNoteContextKind.standard,
  });

  final PaneId paneId;
  final TerminalWindowId windowId;
  final TerminalNoteContextKind kind;
}

/// Application-owned composition of launch admission, pane topology, native
/// surface lifetime, and the sole window interaction authority.
///
/// This type deliberately lives in dart_terminal. It accepts only product
/// ports and volatile renderer/layout values, so neither dart_appkit nor the
/// native Notes package learns about durable contexts or application state.
final class TerminalNoteApplicationCoordinator {
  TerminalNoteApplicationCoordinator._({
    required TerminalNoteCompositionRoot root,
    required TerminalNoteProductTopologyPort? runtime,
    required Iterable<TerminalNoteApplicationPaneBinding> initialBindings,
    required TerminalNoteApplicationClock clock,
    TerminalNoteApplicationErrorHandler? onError,
  }) : _root = root,
       _runtime = runtime,
       _clock = clock,
       _onError = onError {
    if (runtime != null) {
      for (final TerminalNoteApplicationPaneBinding binding
          in initialBindings) {
        _bindings[binding.paneId] = binding;
      }
      runtime.setSurfaceEventHandler(_scheduleSurfaceEvent);
    }
  }

  static Future<TerminalNoteApplicationCoordinator> start({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required Iterable<TerminalNoteApplicationPaneBinding> initialBindings,
    required TerminalNoteSubsystemFactory factory,
    TerminalNoteApplicationClock clock = _systemClock,
    TerminalNoteApplicationErrorHandler? onError,
  }) async {
    final List<TerminalNoteApplicationPaneBinding> bindings = _validateBindings(
      initialBindings,
    );
    TerminalNoteProductTopologyPort? runtime;
    final TerminalNoteCompositionRoot root =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: launchConfiguration,
          factory: (TerminalNoteFeatureConfiguration configuration) async {
            final TerminalNoteSubsystemStartResult result =
                await Future<TerminalNoteSubsystemStartResult>.value(
                  factory(configuration),
                );
            final TerminalNoteSubsystemPort? candidate = result.runtime;
            if (candidate == null) return result;
            if (candidate is! TerminalNoteProductTopologyPort ||
                bindings.any(
                  (TerminalNoteApplicationPaneBinding binding) =>
                      !candidate.hasPane(binding.paneId),
                )) {
              try {
                await candidate.shutdown();
              } on Object {
                // Startup still exposes only the fixed unavailable class.
              }
              return TerminalNoteSubsystemStartResult.failure(
                TerminalNoteApplicationCapability.unavailable,
              );
            }
            runtime = candidate;
            return result;
          },
        );
    return TerminalNoteApplicationCoordinator._(
      root: root,
      runtime: runtime,
      initialBindings: bindings,
      clock: clock,
      onError: onError,
    );
  }

  static Future<TerminalNoteApplicationCoordinator> startProduction({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required Map<String, String> environment,
    required int authorityGeneration,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<TerminalNoteApplicationPaneBinding> initialBindings,
    required bool ensureQuickTerminalContext,
    required TerminalNoteBodyCopyEffect copyEffect,
    required TerminalNoteExportDestinationChooser exportDestinationChooser,
    TerminalNoteNativeCapabilityInitializer? initializeNativeCapability,
    TerminalNoteNativeSurfaceChannelFactory? surfaceFactory,
    TerminalNoteStoreLocationResolver? locationResolver,
    TerminalNoteAuthorityStoreFactory? storeFactory,
    TerminalNoteContextIdGenerator? contextIdGenerator,
    TerminalNoteIdGenerator? noteIdGenerator,
    TerminalNoteNativePresentationState presentation =
        const TerminalNoteNativePresentationState(),
    TerminalNoteApplicationClock clock = _systemClock,
    TerminalNoteApplicationErrorHandler? onError,
  }) {
    final List<TerminalNoteApplicationPaneBinding> bindings = _validateBindings(
      initialBindings,
    );
    if (bindings.any(
      (TerminalNoteApplicationPaneBinding binding) =>
          binding.kind != TerminalNoteContextKind.standard,
    )) {
      throw ArgumentError('initial Note bindings must be standard panes');
    }
    return start(
      launchConfiguration: launchConfiguration,
      initialBindings: bindings,
      clock: clock,
      onError: onError,
      factory: (TerminalNoteFeatureConfiguration configuration) =>
          TerminalNoteProductSubsystem.start(
            configuration: configuration,
            environment: environment,
            authorityGeneration: authorityGeneration,
            restoration: restoration,
            initialPaneIdsInTraversalOrder: bindings.map(
              (TerminalNoteApplicationPaneBinding binding) => binding.paneId,
            ),
            ensureQuickTerminalContext: ensureQuickTerminalContext,
            updatedAtUtcMicros: clock(),
            copyEffect: copyEffect,
            exportDestinationChooser: exportDestinationChooser,
            clock: clock,
            initializeNativeCapability: initializeNativeCapability,
            surfaceFactory: surfaceFactory,
            locationResolver: locationResolver,
            storeFactory: storeFactory,
            contextIdGenerator: contextIdGenerator,
            noteIdGenerator: noteIdGenerator,
            presentation: presentation,
          ),
    );
  }

  static int _debugLiveInteractionAdapterCount = 0;

  static int get debugLiveInteractionAdapterCount =>
      _debugLiveInteractionAdapterCount;

  final TerminalNoteCompositionRoot _root;
  final TerminalNoteProductTopologyPort? _runtime;
  final TerminalNoteApplicationClock _clock;
  final TerminalNoteApplicationErrorHandler? _onError;
  final Map<PaneId, TerminalNoteApplicationPaneBinding> _bindings =
      <PaneId, TerminalNoteApplicationPaneBinding>{};
  final Map<PaneId, _TerminalNoteApplicationSurface> _surfaces =
      <PaneId, _TerminalNoteApplicationSurface>{};
  Future<void> _tail = Future<void>.value();
  Future<TerminalNoteCompositionShutdownDisposition>? _shutdownFuture;
  Future<TerminalNoteApplicationShutdownResult>? _applicationShutdownFuture;
  bool _stopping = false;
  final Set<PaneId> _pendingSurfaceEvents = <PaneId>{};
  bool _surfaceEventDrainScheduled = false;
  var _nextPointerEventSequence = 1;

  TerminalNoteApplicationCapability get capability => _root.capability;
  bool get ownsRuntime => _runtime != null;
  int get liveBindingCount => _bindings.length;
  int get liveSurfaceCount => _surfaces.length;
  int get liveInteractionAdapterCount => _surfaces.values
      .where(
        (_TerminalNoteApplicationSurface surface) =>
            !surface.interaction.isDisposed,
      )
      .length;

  TerminalWindowNoteInteractionAdapter? interactionForPane(PaneId paneId) =>
      _surfaces[paneId]?.interaction;

  bool notesVisibleForPane(PaneId paneId) =>
      _runtime?.interactionSnapshotForPane(paneId)?.visibility ==
      TerminalNoteSurfaceVisibility.expanded;

  bool canPerformAction(
    PaneId paneId,
    TerminalNoteApplicationActionKind action,
  ) {
    if (_stopping) return false;
    final TerminalNoteProductTopologyPort? runtime = _runtime;
    final _TerminalNoteApplicationSurface? surface = _surfaces[paneId];
    if (runtime == null || surface == null || surface.interaction.isDisposed) {
      return false;
    }
    final TerminalNoteProductInteractionSnapshot? snapshot = runtime
        .interactionSnapshotForPane(paneId);
    return switch (action) {
      TerminalNoteApplicationActionKind.newNote => runtime.canPerformAction(
        paneId,
        TerminalNoteProductActionKind.newNote,
      ),
      TerminalNoteApplicationActionKind.toggleNotes => runtime.canPerformAction(
        paneId,
        TerminalNoteProductActionKind.toggleNotes,
      ),
      TerminalNoteApplicationActionKind.focusTerminal =>
        _ownsNoteInteraction(surface) &&
            snapshot?.editorMode == TerminalNoteEditorMode.inactive &&
            snapshot?.draftGeneration == 0 &&
            snapshot?.editorDirty == false &&
            snapshot?.confirmingDiscard == false,
    };
  }

  Future<TerminalNoteProductTopologyResult> performAction(
    PaneId paneId,
    TerminalNoteApplicationActionKind action,
  ) => _serialize(() async {
    if (!canPerformAction(paneId, action)) return _unavailable;
    final TerminalNoteProductTopologyPort runtime = _runtime!;
    final _TerminalNoteApplicationSurface surface = _surfaces[paneId]!;
    if (action == TerminalNoteApplicationActionKind.focusTerminal) {
      final TerminalWindowInteractionTransferResult transfer = surface
          .interaction
          .requestTerminalAfterResolution();
      return _completeFocusTransfer(surface, transfer, surface.focusTerminal)
          ? TerminalNoteProductTopologyResult(
              TerminalNoteProductTopologyDisposition.applied,
              surfaceGeneration: runtime.surfaceGenerationForPane(paneId),
            )
          : _busy;
    }
    final TerminalNoteProductTopologyResult result = await runtime
        .performAction(
          paneId,
          action == TerminalNoteApplicationActionKind.newNote
              ? TerminalNoteProductActionKind.newNote
              : TerminalNoteProductActionKind.toggleNotes,
        );
    if (!result.isAccepted) return result;
    final TerminalNoteProductInteractionSnapshot? snapshot = runtime
        .interactionSnapshotForPane(paneId);
    if (snapshot == null || !_synchronizeInteraction(surface, snapshot)) {
      return _busy;
    }
    return result;
  });

  /// Routes one window pointer event without replaying Note-owned input to the
  /// terminal. Coordinates are pane-local and contain no Note content.
  bool handlePointerEvent({
    required PaneId paneId,
    required TerminalNoteApplicationPointerPhase phase,
    required double x,
    required double y,
  }) {
    final TerminalNoteProductTopologyPort? runtime = _runtime;
    final TerminalNoteApplicationPaneBinding? binding = _bindings[paneId];
    _TerminalNoteApplicationSurface? surface = _surfaces[paneId];
    if (phase != TerminalNoteApplicationPointerPhase.down && binding != null) {
      for (final _TerminalNoteApplicationSurface candidate
          in _surfaces.values) {
        if (candidate.windowId == binding.windowId &&
            (candidate.pointerGesture != null ||
                candidate.pointerSequenceConsumed != null)) {
          surface = candidate;
          break;
        }
      }
    }
    if (runtime == null ||
        binding == null ||
        surface == null ||
        surface.interaction.isDisposed ||
        _stopping) {
      return false;
    }
    final TerminalWindowConsumedGestureIdentity? active =
        surface.pointerGesture;
    if (active != null) {
      final TerminalWindowConsumedGesturePhase gesturePhase = switch (phase) {
        TerminalNoteApplicationPointerPhase.down =>
          TerminalWindowConsumedGesturePhase.down,
        TerminalNoteApplicationPointerPhase.drag =>
          TerminalWindowConsumedGesturePhase.drag,
        TerminalNoteApplicationPointerPhase.up =>
          TerminalWindowConsumedGesturePhase.up,
        TerminalNoteApplicationPointerPhase.moved =>
          TerminalWindowConsumedGesturePhase.drag,
        TerminalNoteApplicationPointerPhase.cancel =>
          TerminalWindowConsumedGesturePhase.cancel,
      };
      surface.interaction.consumeGesture(active, gesturePhase);
      if (phase == TerminalNoteApplicationPointerPhase.up ||
          phase == TerminalNoteApplicationPointerPhase.cancel) {
        surface.pointerGesture = null;
        surface.pointerSequenceConsumed = null;
      }
      return true;
    }
    final bool? sequenceConsumed = surface.pointerSequenceConsumed;
    if (phase != TerminalNoteApplicationPointerPhase.down &&
        sequenceConsumed != null) {
      if (phase == TerminalNoteApplicationPointerPhase.up ||
          phase == TerminalNoteApplicationPointerPhase.cancel) {
        surface.pointerSequenceConsumed = null;
      }
      return sequenceConsumed;
    }
    final bool inside = runtime.surfaceContainsPoint(paneId, x: x, y: y);
    if (phase != TerminalNoteApplicationPointerPhase.down) return inside;
    surface.pointerSequenceConsumed = null;
    if (inside) {
      surface.pointerSequenceConsumed = true;
      final TerminalNoteProductInteractionSnapshot? snapshot = runtime
          .interactionSnapshotForPane(paneId);
      if (snapshot == null ||
          !_synchronizeInteraction(
            surface,
            snapshot,
            forceRailWhenCollapsed: true,
          )) {
        return true;
      }
      final TerminalWindowConsumedGestureResult gesture = surface.interaction
          .beginGesture(eventSequence: _takePointerEventSequence());
      surface.pointerGesture = gesture.identity;
      return true;
    }
    final TerminalWindowNoteOutsideResult outside = surface.interaction
        .handleOutsidePointerDown();
    final TerminalWindowInteractionTransferRequest? request = outside.request;
    if (outside.disposition ==
        TerminalWindowNoteOutsideDisposition.discardConfirmation) {
      surface.pointerSequenceConsumed = true;
      if (!runtime.presentDiscardConfirmation(paneId)) {
        surface.interaction.keepEditingAfterDiscardConfirmation();
      }
      return true;
    }
    if (request != null) {
      surface.pointerSequenceConsumed = true;
      if (!surface.focusTerminal()) {
        surface.interaction.cancelNativeFocus(request);
      } else {
        surface.interaction.confirmNativeFocus(request);
      }
      return true;
    }
    final bool consumed =
        outside.disposition != TerminalWindowNoteOutsideDisposition.stale;
    surface.pointerSequenceConsumed = consumed;
    return consumed;
  }

  TerminalNoteLiveConfigurationDisposition applyLiveConfiguration(
    TerminalNoteFeatureConfiguration configuration,
  ) => _root.applyLiveConfiguration(configuration);

  /// Reconciles settled logical topology. Host preparation for removals is
  /// synchronous and therefore completes before a caller destroys views.
  Future<void> synchronizeTopology(
    Iterable<TerminalNoteApplicationPaneBinding> liveBindings,
  ) {
    final List<TerminalNoteApplicationPaneBinding> validated =
        _validateBindings(liveBindings);
    final Map<PaneId, TerminalNoteApplicationPaneBinding> live =
        <PaneId, TerminalNoteApplicationPaneBinding>{
          for (final TerminalNoteApplicationPaneBinding binding in validated)
            binding.paneId: binding,
        };
    for (final PaneId removed in _bindings.keys.where(
      (PaneId paneId) => !live.containsKey(paneId),
    )) {
      preparePaneForViewTeardown(removed);
    }
    return _serialize(() async {
      final TerminalNoteProductTopologyPort? runtime = _runtime;
      if (runtime == null || _stopping) return;
      for (final PaneId paneId
          in _bindings.keys
              .where((PaneId paneId) => !live.containsKey(paneId))
              .toList(growable: false)) {
        await runtime.closePane(
          paneId: paneId,
          updatedAtUtcMicros: _takeTimestamp(),
        );
        _retireSurface(paneId);
        _bindings.remove(paneId);
      }
      for (final TerminalNoteApplicationPaneBinding binding in validated) {
        final TerminalNoteApplicationPaneBinding? current =
            _bindings[binding.paneId];
        if (current != null) {
          if (current.kind != binding.kind) {
            throw StateError('live Note pane kind changed');
          }
          _bindings[binding.paneId] = binding;
          continue;
        }
        final TerminalNoteProductTopologyResult result = await runtime.bindPane(
          paneId: binding.paneId,
          kind: binding.kind,
        );
        if (result.isAccepted) _bindings[binding.paneId] = binding;
      }
    });
  }

  Future<TerminalNoteProductTopologyResult> synchronizeSurface({
    required PaneId paneId,
    required TerminalWindowId windowId,
    required TerminalNoteProductSurfaceConfiguration configuration,
    required TerminalWindowInteractionAuthority interactionAuthority,
    required TerminalWindowInteractionRouter interactionRouter,
    required TerminalNoteTerminalFocusHandler focusTerminal,
  }) => _serialize(() async {
    final TerminalNoteProductTopologyPort? runtime = _runtime;
    if (runtime == null || _stopping) return _unavailable;
    final TerminalNoteApplicationPaneBinding? binding = _bindings[paneId];
    if (binding == null || binding.windowId != windowId) return _stale;
    _TerminalNoteApplicationSurface? surface = _surfaces[paneId];
    if (surface == null) {
      final TerminalNoteProductTopologyResult result = await runtime
          .attachSurface(paneId: paneId, configuration: configuration);
      final int? generation = result.surfaceGeneration;
      if (!result.isAccepted || generation == null) return result;
      try {
        surface = _TerminalNoteApplicationSurface(
          paneId: paneId,
          windowId: windowId,
          interaction: TerminalWindowNoteInteractionAdapter(
            authority: interactionAuthority,
            router: interactionRouter,
            windowId: windowId,
            paneId: paneId,
            surfaceGeneration: generation,
          ),
          focusTerminal: focusTerminal,
        );
      } on Object {
        await runtime.detachSurface(paneId);
        rethrow;
      }
      _surfaces[paneId] = surface;
      _debugLiveInteractionAdapterCount++;
      final TerminalNoteProductInteractionSnapshot? snapshot = runtime
          .interactionSnapshotForPane(paneId);
      if (snapshot != null && !_synchronizeInteraction(surface, snapshot)) {
        return _busy;
      }
      return result;
    }
    if (surface.windowId != windowId || surface.interaction.isDisposed) {
      if (!surface.interaction.isDisposed && !_releaseInteraction(surface)) {
        return _busy;
      }
      final int? surfaceGeneration = runtime.surfaceGenerationForPane(paneId);
      if (surfaceGeneration == null) {
        _retireSurface(paneId);
        return _stale;
      }
      surface
        ..windowId = windowId
        ..interaction = TerminalWindowNoteInteractionAdapter(
          authority: interactionAuthority,
          router: interactionRouter,
          windowId: windowId,
          paneId: paneId,
          surfaceGeneration: surfaceGeneration,
        );
      _debugLiveInteractionAdapterCount++;
    }
    surface.focusTerminal = focusTerminal;
    final TerminalNoteProductTopologyResult result = await runtime
        .updateSurface(paneId: paneId, configuration: configuration);
    if (!result.isAccepted &&
        runtime.surfaceGenerationForPane(paneId) == null) {
      _retireSurface(paneId);
    } else if (result.isAccepted) {
      final TerminalNoteProductInteractionSnapshot? snapshot = runtime
          .interactionSnapshotForPane(paneId);
      if (snapshot != null && !_synchronizeInteraction(surface, snapshot)) {
        return _busy;
      }
    }
    return result;
  });

  bool preparePaneForViewTeardown(PaneId paneId) {
    final _TerminalNoteApplicationSurface? surface = _surfaces[paneId];
    final bool interactionReleased =
        surface == null || _releaseInteraction(surface);
    if (!interactionReleased) return false;
    final bool hostDetached =
        _runtime?.prepareSurfaceForHostTeardown(paneId) ?? true;
    return hostDetached;
  }

  Future<TerminalNoteCompositionShutdownDisposition> shutdown() {
    final Future<TerminalNoteCompositionShutdownDisposition>? existing =
        _shutdownFuture;
    if (existing != null) return existing;
    _stopping = true;
    _runtime?.setSurfaceEventHandler(null);
    _pendingSurfaceEvents.clear();
    for (final PaneId paneId in _surfaces.keys.toList(growable: false)) {
      preparePaneForViewTeardown(paneId);
    }
    return _shutdownFuture = _serialize(() async {
      final TerminalNoteCompositionShutdownDisposition disposition = await _root
          .shutdown();
      for (final PaneId paneId in _surfaces.keys.toList(growable: false)) {
        _retireSurface(paneId);
      }
      _bindings.clear();
      return disposition;
    });
  }

  /// Performs the restoration-first Note shutdown owned by the application.
  ///
  /// Disabled and unavailable compositions still stop normally and return no
  /// authority result. Starting plain [shutdown] first makes this operation
  /// unavailable because exact restoration can no longer be committed.
  Future<TerminalNoteApplicationShutdownResult> shutdownApplication({
    required TerminalNoteRestorationCaptureArtifact capture,
    required int updatedAtUtcMicros,
    required TerminalNoteRestorationCommit commitRestoration,
    Duration drainTimeout = const Duration(seconds: 3),
  }) {
    final Future<TerminalNoteApplicationShutdownResult>? existing =
        _applicationShutdownFuture;
    if (existing != null) return existing;
    if (_shutdownFuture != null) {
      return Future<TerminalNoteApplicationShutdownResult>.error(
        StateError('Note application shutdown already started'),
      );
    }
    if (drainTimeout <= Duration.zero) {
      return Future<TerminalNoteApplicationShutdownResult>.error(
        ArgumentError.value(drainTimeout, 'drainTimeout', 'must be positive'),
      );
    }
    _stopping = true;
    _runtime?.setSurfaceEventHandler(null);
    _pendingSurfaceEvents.clear();
    for (final PaneId paneId in _surfaces.keys.toList(growable: false)) {
      preparePaneForViewTeardown(paneId);
    }
    final Future<TerminalNoteApplicationShutdownResult> future = _serialize(
      () async {
        TerminalNoteAuthorityShutdownResult? authorityResult;
        Object? shutdownError;
        StackTrace? shutdownStackTrace;
        try {
          authorityResult = await _runtime?.shutdownApplication(
            capture: capture,
            updatedAtUtcMicros: updatedAtUtcMicros,
            commitRestoration: commitRestoration,
            drainTimeout: drainTimeout,
          );
        } on Object catch (error, stackTrace) {
          shutdownError = error;
          shutdownStackTrace = stackTrace;
        }
        final TerminalNoteCompositionShutdownDisposition disposition =
            await _root.shutdown();
        for (final PaneId paneId in _surfaces.keys.toList(growable: false)) {
          _retireSurface(paneId);
        }
        _bindings.clear();
        if (shutdownError != null) {
          Error.throwWithStackTrace(shutdownError, shutdownStackTrace!);
        }
        return TerminalNoteApplicationShutdownResult(
          compositionDisposition: disposition,
          authorityResult: authorityResult,
        );
      },
    );
    _applicationShutdownFuture = future;
    _shutdownFuture = future.then(
      (TerminalNoteApplicationShutdownResult result) =>
          result.compositionDisposition,
    );
    return future;
  }

  bool _releaseInteraction(_TerminalNoteApplicationSurface surface) {
    final TerminalWindowNoteInteractionAdapter adapter = surface.interaction;
    if (adapter.isDisposed) return true;
    try {
      adapter.authority.synchronize();
      final TerminalWindowInteractionTransferResult prepared = adapter
          .prepareForViewTeardown();
      final TerminalWindowInteractionTransferRequest? request =
          prepared.request;
      if (request != null) {
        if (!surface.focusTerminal()) {
          adapter.cancelNativeFocus(request);
          return false;
        }
        if (adapter.confirmNativeFocus(request).disposition !=
            TerminalWindowInteractionTransferDisposition.confirmed) {
          return false;
        }
      } else if (prepared.disposition ==
              TerminalWindowInteractionTransferDisposition.busy ||
          prepared.disposition ==
              TerminalWindowInteractionTransferDisposition.rejected) {
        return false;
      }
      adapter.dispose();
      _debugLiveInteractionAdapterCount--;
      return true;
    } on Object {
      return false;
    }
  }

  void _scheduleSurfaceEvent(PaneId paneId) {
    if (_stopping || !_surfaces.containsKey(paneId)) return;
    _pendingSurfaceEvents.add(paneId);
    if (_surfaceEventDrainScheduled) return;
    _surfaceEventDrainScheduled = true;
    scheduleMicrotask(() {
      _surfaceEventDrainScheduled = false;
      final Set<PaneId> pending = Set<PaneId>.of(_pendingSurfaceEvents);
      _pendingSurfaceEvents.clear();
      for (final PaneId pendingPaneId in pending) {
        unawaited(
          _serialize(() => _handleSurfaceEvent(pendingPaneId)).then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              final TerminalNoteApplicationErrorHandler? onError = _onError;
              if (onError != null) {
                onError(error, stackTrace);
              } else {
                Zone.current.handleUncaughtError(error, stackTrace);
              }
            },
          ),
        );
      }
    });
  }

  Future<void> _handleSurfaceEvent(PaneId paneId) async {
    final TerminalNoteProductTopologyPort? runtime = _runtime;
    final _TerminalNoteApplicationSurface? surface = _surfaces[paneId];
    if (runtime == null || surface == null || _stopping) return;
    final TerminalNoteProductTopologyResult result = await runtime
        .pumpSurfaceIntent(paneId);
    if (result.disposition ==
            TerminalNoteProductTopologyDisposition.nativeUnavailable ||
        runtime.surfaceGenerationForPane(paneId) == null) {
      _retireSurface(paneId);
      return;
    }
    final TerminalNoteProductInteractionSnapshot? snapshot = runtime
        .interactionSnapshotForPane(paneId);
    if (snapshot == null || !_synchronizeInteraction(surface, snapshot)) {
      throw StateError('Note surface interaction reconciliation failed');
    }
  }

  bool _synchronizeInteraction(
    _TerminalNoteApplicationSurface surface,
    TerminalNoteProductInteractionSnapshot snapshot, {
    bool forceRailWhenCollapsed = false,
  }) {
    final TerminalWindowNoteInteractionAdapter interaction =
        surface.interaction;
    final TerminalWindowInteractionSnapshot? owner = interaction.authority
        .snapshotForWindow(surface.windowId);
    if (owner?.owner.kind == TerminalWindowInteractionOwnerKind.noteEditor &&
        owner?.owner.paneId == surface.paneId &&
        owner?.owner.surfaceGeneration == snapshot.surfaceGeneration &&
        !interaction.synchronizeEditorPhase(
          dirty: snapshot.editorDirty,
          confirmingDiscard: snapshot.confirmingDiscard,
        )) {
      return false;
    }
    if (snapshot.visibility == TerminalNoteSurfaceVisibility.collapsed &&
        !forceRailWhenCollapsed) {
      final bool ownsThisSurface =
          owner?.owner.isNoteOwner == true &&
          owner?.owner.paneId == surface.paneId &&
          owner?.owner.surfaceGeneration == snapshot.surfaceGeneration;
      if (!ownsThisSurface) return true;
      final TerminalWindowInteractionTransferResult transfer = interaction
          .requestTerminalAfterResolution();
      return _completeFocusTransfer(surface, transfer, surface.focusTerminal);
    }
    final bool editorActive =
        snapshot.editorMode != TerminalNoteEditorMode.inactive;
    final TerminalWindowInteractionTransferResult transfer = editorActive
        ? interaction.requestEditorFocus(
            draftGeneration: snapshot.draftGeneration,
          )
        : interaction.requestRailFocus();
    final bool focused = _completeFocusTransfer(
      surface,
      transfer,
      () => _runtime!.focusSurface(
        surface.paneId,
        editorActive
            ? TerminalNoteProductFocusTarget.editor
            : TerminalNoteProductFocusTarget.rail,
      ),
    );
    if (!focused) return false;
    return !editorActive ||
        interaction.synchronizeEditorPhase(
          dirty: snapshot.editorDirty,
          confirmingDiscard: snapshot.confirmingDiscard,
        );
  }

  static bool _completeFocusTransfer(
    _TerminalNoteApplicationSurface surface,
    TerminalWindowInteractionTransferResult transfer,
    bool Function() focus,
  ) {
    final TerminalWindowInteractionTransferRequest? request = transfer.request;
    if (request == null) {
      return transfer.disposition ==
          TerminalWindowInteractionTransferDisposition.noChange;
    }
    if (!focus()) {
      surface.interaction.cancelNativeFocus(request);
      return false;
    }
    return surface.interaction.confirmNativeFocus(request).disposition ==
        TerminalWindowInteractionTransferDisposition.confirmed;
  }

  static bool _ownsNoteInteraction(_TerminalNoteApplicationSurface surface) {
    final TerminalWindowInteractionSnapshot? snapshot = surface
        .interaction
        .authority
        .snapshotForWindow(surface.windowId);
    return snapshot?.owner.isNoteOwner == true &&
        snapshot?.owner.paneId == surface.paneId &&
        snapshot?.owner.surfaceGeneration ==
            surface.interaction.surfaceGeneration;
  }

  int _takePointerEventSequence() {
    if (_nextPointerEventSequence >
        TerminalWindowInteractionLimits.maximumGeneration) {
      throw StateError('Note pointer event sequence exhausted');
    }
    return _nextPointerEventSequence++;
  }

  void _retireSurface(PaneId paneId) {
    final _TerminalNoteApplicationSurface? surface = _surfaces.remove(paneId);
    if (surface == null || surface.interaction.isDisposed) return;
    if (!_releaseInteraction(surface)) {
      throw StateError('Note interaction owner survived surface retirement');
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  int _takeTimestamp() {
    final int value = _clock();
    if (value < 0 || value > 0x7fffffffffffffff) {
      throw StateError('Note application clock is outside the durable range');
    }
    return value;
  }

  static List<TerminalNoteApplicationPaneBinding> _validateBindings(
    Iterable<TerminalNoteApplicationPaneBinding> bindings,
  ) {
    final List<TerminalNoteApplicationPaneBinding> result =
        List<TerminalNoteApplicationPaneBinding>.unmodifiable(bindings);
    if (result.length > TerminalApplicationStateLimits.maximumTotalPanes ||
        result.map((binding) => binding.paneId).toSet().length !=
            result.length) {
      throw ArgumentError('Note application pane bindings are invalid');
    }
    return result;
  }

  static int _systemClock() => DateTime.now().toUtc().microsecondsSinceEpoch;

  static const TerminalNoteProductTopologyResult _unavailable =
      TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.unavailable,
      );
  static const TerminalNoteProductTopologyResult _stale =
      TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.stale,
      );
  static const TerminalNoteProductTopologyResult _busy =
      TerminalNoteProductTopologyResult(
        TerminalNoteProductTopologyDisposition.busy,
      );
}

final class _TerminalNoteApplicationSurface {
  _TerminalNoteApplicationSurface({
    required this.paneId,
    required this.windowId,
    required this.interaction,
    required this.focusTerminal,
  });

  final PaneId paneId;
  TerminalWindowId windowId;
  TerminalWindowNoteInteractionAdapter interaction;
  TerminalNoteTerminalFocusHandler focusTerminal;
  TerminalWindowConsumedGestureIdentity? pointerGesture;
  bool? pointerSequenceConsumed;
}
