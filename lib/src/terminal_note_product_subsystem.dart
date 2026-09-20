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

  bool prepareSurfaceForHostTeardown(PaneId paneId);

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
    required Iterable<PaneId> initialPaneIds,
    required TerminalNoteNativePresentationState presentation,
  }) : _authority = authority,
       _configuration = configuration,
       _surfaceFactory = surfaceFactory,
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
    TerminalNoteNativeCapabilityInitializer? initializeNativeCapability,
    TerminalNoteNativeSurfaceChannelFactory? surfaceFactory,
    TerminalNoteStoreLocationResolver? locationResolver,
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
      authority = await TerminalNoteAuthority.startWorker(
        location: location,
        authorityGeneration: authorityGeneration,
        restoration: restoration,
        paneIdsInTraversalOrder: paneIds,
        ensureQuickTerminalContext: ensureQuickTerminalContext,
        updatedAtUtcMicros: updatedAtUtcMicros,
      );
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
  final Map<PaneId, TerminalNoteContextKind> _paneKinds =
      <PaneId, TerminalNoteContextKind>{};
  final Map<PaneId, _TerminalNoteProductSurface> _surfaces =
      <PaneId, _TerminalNoteProductSurface>{};
  Future<void> _topologyTail = Future<void>.value();
  TerminalNoteFeatureConfiguration _configuration;
  TerminalNoteNativePresentationState _presentation;
  Future<void>? _shutdownFuture;
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
  bool prepareSurfaceForHostTeardown(PaneId paneId) {
    final _TerminalNoteProductSurface? surface = _surfaces[paneId];
    if (surface == null || !surface.hostAttached) return true;
    try {
      surface.adapter.detachFromHost();
      surface.hostAttached = false;
      final TerminalNoteSurfaceResult result = _authority.updateSurface(
        sequence: _authority.nextSequence(),
        paneId: paneId,
        surfaceGeneration: surface.surfaceGeneration,
        visibility: TerminalNoteSurfaceVisibility.collapsed,
        foreground: false,
        occluded: true,
      );
      if (result.disposition == TerminalNoteSurfaceDisposition.applied) {
        return true;
      }
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
    final TerminalNoteNativeSurfaceAdapter adapter;
    try {
      adapter = TerminalNoteNativeSurfaceAdapter(
        channel: _surfaceFactory(),
        presentation: _presentationWithFont(
          configuration.presentation ?? _presentation,
          _configuration,
        ),
      );
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
    final TerminalNoteSurfaceResult result = _authority.updateSurface(
      sequence: _authority.nextSequence(),
      paneId: paneId,
      surfaceGeneration: surface.surfaceGeneration,
      visibility: configuration.visibility,
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
    try {
      await _authority.stop();
    } finally {
      final List<_TerminalNoteProductSurface> remaining = _surfaces.values
          .toList(growable: false);
      _surfaces.clear();
      _paneKinds.clear();
      for (final _TerminalNoteProductSurface surface in remaining) {
        await surface.adapter.dispose();
      }
      _stopped = true;
      _retireDebugOwner();
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
