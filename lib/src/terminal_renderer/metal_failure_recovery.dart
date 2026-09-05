import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';

/// One renderer/atlas ownership domain managed by failure recovery.
abstract interface class TerminalMetalRecoveryDomain {
  int get rendererGeneration;
  TerminalMetalFailureKind get failure;
  bool get isFaulted;
  bool get isAbandoned;

  /// Binds a completely prepared domain to its retained presentation view.
  void activate();

  /// Releases bridge-local pins and disposes the native renderer exactly once.
  int abandon();
}

/// A recoverable preparation or activation failure at the product boundary.
final class TerminalMetalRecoveryException implements Exception {
  const TerminalMetalRecoveryException({
    required this.operation,
    required this.failure,
    this.cause,
  });

  final String operation;
  final TerminalMetalFailureKind failure;
  final Object? cause;

  @override
  String toString() =>
      'TerminalMetalRecoveryException($operation, failure=${failure.name})';
}

typedef TerminalMetalReplacementPreparer<
  Domain extends TerminalMetalRecoveryDomain
> = Domain Function();

enum TerminalMetalRecoveryDisposition {
  idle,
  recovered,
  retryableFailure,
  exhausted,
}

final class TerminalMetalRecoveryResult {
  const TerminalMetalRecoveryResult({
    required this.disposition,
    required this.attempt,
    required this.rendererGeneration,
    required this.failure,
    required this.abandonedPinCount,
  });

  final TerminalMetalRecoveryDisposition disposition;
  final int attempt;
  final int rendererGeneration;
  final TerminalMetalFailureKind failure;
  final int abandonedPinCount;

  bool get isRecovered =>
      disposition == TerminalMetalRecoveryDisposition.recovered;
}

/// Retains one recovery request and advances it through bounded attempts.
///
/// Preparation happens while the previous renderer remains published. Once a
/// complete newer domain exists, activation is a synchronous ownership handoff:
/// old pins/renderer are abandoned, the replacement is bound, then full model
/// and redraw requests are emitted before the new domain becomes observable.
final class TerminalMetalFailureRecoveryCoordinator<
  Domain extends TerminalMetalRecoveryDomain
> {
  TerminalMetalFailureRecoveryCoordinator({
    required Domain initialDomain,
    required TerminalMetalReplacementPreparer<Domain> prepareReplacement,
    required void Function() requestFullDamage,
    required void Function() requestFullRedraw,
    this.maximumAttempts = 3,
  }) : _current = initialDomain,
       _prepareReplacement = prepareReplacement,
       _requestFullDamage = requestFullDamage,
       _requestFullRedraw = requestFullRedraw,
       _generationFloor = initialDomain.rendererGeneration {
    RangeError.checkValueInInterval(maximumAttempts, 1, 64, 'maximumAttempts');
    if (initialDomain.rendererGeneration <= 0 || initialDomain.isAbandoned) {
      throw ArgumentError('initial Metal recovery domain is not live');
    }
  }

  final TerminalMetalReplacementPreparer<Domain> _prepareReplacement;
  final void Function() _requestFullDamage;
  final void Function() _requestFullRedraw;
  final int maximumAttempts;

  Domain? _current;
  int _generationFloor;
  TerminalMetalFailureKind? _pendingFailure;
  int _pendingAttemptCount = 0;
  int _totalAttemptCount = 0;
  int _recoveryCount = 0;
  bool _exhausted = false;
  bool _disposed = false;

  Domain get currentDomain =>
      _current ??
      (throw StateError('Metal recovery has no active renderer domain'));
  bool get hasCurrentDomain => _current != null;
  int get rendererGenerationFloor => _generationFloor;
  bool get hasPendingRecovery => _pendingFailure != null;
  int get pendingRecoveryCount => hasPendingRecovery ? 1 : 0;
  int get pendingAttemptCount => _pendingAttemptCount;
  int get totalAttemptCount => _totalAttemptCount;
  int get recoveryCount => _recoveryCount;
  bool get isExhausted => _exhausted;
  bool get isDisposed => _disposed;

  /// Observes the typed native state and coalesces a fault into one request.
  bool observeCurrentFailure() {
    _requireLive();
    final Domain? current = _current;
    if (current == null || !current.isFaulted) return false;
    final TerminalMetalFailureKind failure = current.failure;
    if (failure == TerminalMetalFailureKind.none) {
      throw StateError('faulted Metal domain omitted its failure kind');
    }
    return requestRecovery(failure);
  }

  /// Retains at most one pending request until success or budget exhaustion.
  bool requestRecovery(TerminalMetalFailureKind failure) {
    _requireLive();
    if (failure == TerminalMetalFailureKind.none) {
      throw ArgumentError.value(failure, 'failure', 'must describe a failure');
    }
    if (_exhausted || _pendingFailure != null) return false;
    _pendingFailure = failure;
    _pendingAttemptCount = 0;
    return true;
  }

  TerminalMetalRecoveryResult processNewest() {
    _requireLive();
    final TerminalMetalFailureKind? requestedFailure = _pendingFailure;
    if (requestedFailure == null) {
      return TerminalMetalRecoveryResult(
        disposition: TerminalMetalRecoveryDisposition.idle,
        attempt: 0,
        rendererGeneration: _current?.rendererGeneration ?? _generationFloor,
        failure: TerminalMetalFailureKind.none,
        abandonedPinCount: 0,
      );
    }

    _pendingAttemptCount++;
    _totalAttemptCount++;
    final int attempt = _pendingAttemptCount;
    Domain? candidate;
    var abandonedPinCount = 0;
    try {
      candidate = _prepareReplacement();
      if (candidate.isAbandoned ||
          candidate.rendererGeneration <= _generationFloor) {
        throw StateError(
          'replacement Metal renderer generation must advance strictly',
        );
      }
      _generationFloor = candidate.rendererGeneration;

      final Domain? previous = _current;
      if (previous != null) {
        abandonedPinCount = previous.abandon();
        _current = null;
      }
      candidate.activate();
      _requestFullDamage();
      _requestFullRedraw();
      _current = candidate;
      candidate = null;
      _pendingFailure = null;
      _pendingAttemptCount = 0;
      _recoveryCount++;
      return TerminalMetalRecoveryResult(
        disposition: TerminalMetalRecoveryDisposition.recovered,
        attempt: attempt,
        rendererGeneration: _current!.rendererGeneration,
        failure: requestedFailure,
        abandonedPinCount: abandonedPinCount,
      );
    } on Object catch (error, stackTrace) {
      try {
        candidate?.abandon();
      } on Object catch (cleanupError, cleanupStackTrace) {
        // A failed cleanup invalidates the no-leak retry guarantee and is a
        // terminal product invariant violation, not another recoverable try.
        Error.throwWithStackTrace(cleanupError, cleanupStackTrace);
      }
      final TerminalMetalFailureKind? failure = _recoverableFailure(
        error,
        requestedFailure,
      );
      if (failure == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (attempt >= maximumAttempts) {
        _pendingFailure = null;
        _exhausted = true;
        return TerminalMetalRecoveryResult(
          disposition: TerminalMetalRecoveryDisposition.exhausted,
          attempt: attempt,
          rendererGeneration: _current?.rendererGeneration ?? _generationFloor,
          failure: failure,
          abandonedPinCount: abandonedPinCount,
        );
      }
      _pendingFailure = failure;
      return TerminalMetalRecoveryResult(
        disposition: TerminalMetalRecoveryDisposition.retryableFailure,
        attempt: attempt,
        rendererGeneration: _current?.rendererGeneration ?? _generationFloor,
        failure: failure,
        abandonedPinCount: abandonedPinCount,
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingFailure = null;
    _current?.abandon();
    _current = null;
  }

  void _requireLive() {
    if (_disposed) {
      throw StateError('TerminalMetalFailureRecoveryCoordinator is disposed');
    }
  }
}

/// Real renderer/bridge pair used by the product recovery coordinator.
final class TerminalMetalRendererRecoveryDomain
    implements TerminalMetalRecoveryDomain {
  TerminalMetalRendererRecoveryDomain.active({
    required this.renderer,
    required this.bridge,
    required this.view,
  }) : _activated = true {
    _validateParts();
    final TerminalMetalRendererState state = renderer.state();
    if (!state.isBound || !state.isAdmitting || state.isFaulted) {
      throw ArgumentError('initial Metal renderer domain is not active');
    }
  }

  TerminalMetalRendererRecoveryDomain._prepared({
    required this.renderer,
    required this.bridge,
    required this.view,
  }) {
    _validateParts();
    final TerminalMetalRendererState state = renderer.state();
    if (state.isBound || !state.isAdmitting || state.isFaulted) {
      throw StateError('prepared Metal renderer domain is not isolated');
    }
  }

  static TerminalMetalRendererRecoveryDomain prepare({
    required TerminalGlyphAtlas atlas,
    required TerminalMetalRendererConfig config,
    required View view,
  }) {
    final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
      config: config,
    );
    try {
      final TerminalGlyphAtlasMetalBridge bridge =
          TerminalGlyphAtlasMetalBridge(atlas: atlas, renderer: renderer);
      final TerminalGlyphAtlasSyncDisposition synchronized = bridge
          .synchronize();
      if (synchronized != TerminalGlyphAtlasSyncDisposition.synchronized ||
          !bridge.isSynchronized) {
        bridge.abandonRenderer();
        throw const TerminalMetalRecoveryException(
          operation: 'Metal replacement atlas synchronization',
          failure: TerminalMetalFailureKind.resourceAllocation,
        );
      }
      return TerminalMetalRendererRecoveryDomain._prepared(
        renderer: renderer,
        bridge: bridge,
        view: view,
      );
    } on Object {
      if (!renderer.isDisposed) renderer.dispose();
      rethrow;
    }
  }

  final TerminalMetalRenderer renderer;
  final TerminalGlyphAtlasMetalBridge bridge;
  final View view;
  bool _activated = false;
  bool _abandoned = false;

  @override
  int get rendererGeneration => renderer.generation;

  @override
  TerminalMetalFailureKind get failure => renderer.state().failure;

  @override
  bool get isFaulted => renderer.state().isFaulted;

  @override
  bool get isAbandoned => _abandoned;

  bool get isActivated => _activated && !_abandoned;

  @override
  void activate() {
    if (_abandoned || _activated || !bridge.isSynchronized) {
      throw StateError('replacement Metal domain is not activatable');
    }
    try {
      renderer.bindToView(view);
    } on Object catch (error) {
      throw TerminalMetalRecoveryException(
        operation: 'Metal replacement view binding',
        failure: TerminalMetalFailureKind.resourceAllocation,
        cause: error,
      );
    }
    final TerminalMetalRendererState state = renderer.state();
    if (!state.isBound || !state.isAdmitting || state.isFaulted) {
      throw StateError('replacement Metal renderer did not become active');
    }
    _activated = true;
  }

  @override
  int abandon() {
    if (_abandoned) return 0;
    _abandoned = true;
    _activated = false;
    var abandonedPinCount = 0;
    try {
      abandonedPinCount = bridge.abandonRenderer();
    } finally {
      if (!renderer.isDisposed) renderer.dispose();
    }
    return abandonedPinCount;
  }

  void _validateParts() {
    if (!identical(bridge.renderer, renderer) ||
        renderer.isDisposed ||
        bridge.isAbandoned ||
        !bridge.isSynchronized) {
      throw ArgumentError('Metal renderer recovery domain is inconsistent');
    }
  }
}

TerminalMetalFailureKind? _recoverableFailure(
  Object error,
  TerminalMetalFailureKind requestedFailure,
) {
  if (error case TerminalMetalRecoveryException recovery) {
    return recovery.failure == TerminalMetalFailureKind.none
        ? requestedFailure
        : recovery.failure;
  }
  if (error case TerminalMetalRendererException renderer) {
    return renderer.failure == TerminalMetalFailureKind.none
        ? requestedFailure
        : renderer.failure;
  }
  return null;
}
