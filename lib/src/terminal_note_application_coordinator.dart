import 'dart:async';

import 'terminal_application_state.dart';
import 'terminal_note_composition.dart';
import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_native_adapter.dart';
import 'terminal_note_product_subsystem.dart';
import 'terminal_pane.dart';
import 'terminal_product_configuration.dart';
import 'terminal_window_interaction.dart';

typedef TerminalNoteApplicationClock = int Function();
typedef TerminalNoteTerminalFocusHandler = bool Function();

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
  }) : _root = root,
       _runtime = runtime,
       _clock = clock {
    if (runtime != null) {
      for (final TerminalNoteApplicationPaneBinding binding
          in initialBindings) {
        _bindings[binding.paneId] = binding;
      }
    }
  }

  static Future<TerminalNoteApplicationCoordinator> start({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required Iterable<TerminalNoteApplicationPaneBinding> initialBindings,
    required TerminalNoteSubsystemFactory factory,
    TerminalNoteApplicationClock clock = _systemClock,
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
    );
  }

  static Future<TerminalNoteApplicationCoordinator> startProduction({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required Map<String, String> environment,
    required int authorityGeneration,
    required TerminalNoteRestorationArtifact? restoration,
    required Iterable<TerminalNoteApplicationPaneBinding> initialBindings,
    required bool ensureQuickTerminalContext,
    TerminalNoteNativeCapabilityInitializer? initializeNativeCapability,
    TerminalNoteNativeSurfaceChannelFactory? surfaceFactory,
    TerminalNoteStoreLocationResolver? locationResolver,
    TerminalNoteNativePresentationState presentation =
        const TerminalNoteNativePresentationState(),
    TerminalNoteApplicationClock clock = _systemClock,
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
            initializeNativeCapability: initializeNativeCapability,
            surfaceFactory: surfaceFactory,
            locationResolver: locationResolver,
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
  final Map<PaneId, TerminalNoteApplicationPaneBinding> _bindings =
      <PaneId, TerminalNoteApplicationPaneBinding>{};
  final Map<PaneId, _TerminalNoteApplicationSurface> _surfaces =
      <PaneId, _TerminalNoteApplicationSurface>{};
  Future<void> _tail = Future<void>.value();
  Future<TerminalNoteCompositionShutdownDisposition>? _shutdownFuture;
  bool _stopping = false;

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
}
