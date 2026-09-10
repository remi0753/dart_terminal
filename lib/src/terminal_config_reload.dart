import 'dart:async';
import 'dart:io';

import 'terminal_config.dart';

typedef TerminalConfigReloadResolver =
    FutureOr<TerminalConfigResolution> Function();

enum TerminalConfigReloadDisposition {
  applied,
  unchanged,
  rejected,
  busy,
  failed,
  disposed,
}

/// Immutable result of one bounded configuration reload request.
final class TerminalConfigReloadResult {
  const TerminalConfigReloadResult._({
    required this.disposition,
    required this.effectiveSnapshot,
    this.candidateSnapshot,
    this.changePlan,
    this.error,
    this.stackTrace,
  });

  final TerminalConfigReloadDisposition disposition;
  final TerminalConfigSnapshot effectiveSnapshot;
  final TerminalConfigSnapshot? candidateSnapshot;
  final TerminalConfigChangePlan? changePlan;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isAccepted =>
      disposition == TerminalConfigReloadDisposition.applied ||
      disposition == TerminalConfigReloadDisposition.unchanged;

  List<TerminalConfigDiagnostic> get diagnostics =>
      candidateSnapshot?.diagnostics ?? const <TerminalConfigDiagnostic>[];

  String machineLine({required int acceptedGeneration}) {
    final TerminalConfigChangePlan? plan = changePlan;
    return 'TERMINAL_CONFIG_RELOAD disposition=${disposition.name} '
        'generation=$acceptedGeneration changes=${plan?.changes.length ?? 0} '
        'live=${plan?.liveChanges.length ?? 0} '
        'new_session=${plan?.newSessionChanges.length ?? 0} '
        'diagnostics=${diagnostics.length}';
  }
}

/// Owns last-known-good configuration and serializes explicit reload attempts.
///
/// File resolution finishes before state publication. A candidate containing
/// any error diagnostic is rejected as a whole, while warnings are accepted.
/// Concurrent attempts are classified as busy and never queued.
final class TerminalConfigReloadController {
  TerminalConfigReloadController({
    required TerminalConfigSnapshot initialSnapshot,
    required TerminalConfigReloadResolver resolver,
  }) : _effectiveSnapshot = initialSnapshot,
       _resolver = resolver;

  factory TerminalConfigReloadController.fromStartup({
    required List<String> arguments,
    required TerminalConfigSnapshot initialSnapshot,
    TerminalConfigLoader? loader,
    Map<String, String>? environment,
    String? currentDirectory,
  }) {
    final TerminalConfigLoader selectedLoader =
        loader ?? TerminalConfigLoader();
    if (!identical(selectedLoader.schema, initialSnapshot.schema)) {
      throw ArgumentError(
        'initial snapshot and reload loader must use the same schema instance',
      );
    }
    final List<String> fixedArguments = List<String>.unmodifiable(arguments);
    final Map<String, String> fixedEnvironment =
        Map<String, String>.unmodifiable(environment ?? Platform.environment);
    final String fixedCurrentDirectory =
        currentDirectory ?? Directory.current.path;
    return TerminalConfigReloadController(
      initialSnapshot: initialSnapshot,
      resolver: () => selectedLoader.resolve(
        fixedArguments,
        environment: fixedEnvironment,
        currentDirectory: fixedCurrentDirectory,
      ),
    );
  }

  final TerminalConfigReloadResolver _resolver;
  TerminalConfigSnapshot _effectiveSnapshot;
  TerminalConfigSnapshot? _lastAttemptedSnapshot;
  List<TerminalConfigDiagnostic> _lastAttemptDiagnostics =
      const <TerminalConfigDiagnostic>[];
  Object? _lastFailure;
  StackTrace? _lastFailureStackTrace;
  var _inProgress = false;
  var _disposed = false;
  var _acceptedGeneration = 0;

  TerminalConfigSnapshot get effectiveSnapshot => _effectiveSnapshot;
  TerminalConfigSnapshot? get lastAttemptedSnapshot => _lastAttemptedSnapshot;
  List<TerminalConfigDiagnostic> get lastAttemptDiagnostics =>
      _lastAttemptDiagnostics;
  Object? get lastFailure => _lastFailure;
  StackTrace? get lastFailureStackTrace => _lastFailureStackTrace;
  bool get inProgress => _inProgress;
  bool get isDisposed => _disposed;
  int get acceptedGeneration => _acceptedGeneration;

  Future<TerminalConfigReloadResult> reload() {
    if (_disposed) {
      return Future<TerminalConfigReloadResult>.value(
        TerminalConfigReloadResult._(
          disposition: TerminalConfigReloadDisposition.disposed,
          effectiveSnapshot: _effectiveSnapshot,
        ),
      );
    }
    if (_inProgress) {
      return Future<TerminalConfigReloadResult>.value(
        TerminalConfigReloadResult._(
          disposition: TerminalConfigReloadDisposition.busy,
          effectiveSnapshot: _effectiveSnapshot,
        ),
      );
    }
    _inProgress = true;
    return Future<TerminalConfigResolution>.sync(_resolver)
        .then(_complete, onError: _fail);
  }

  TerminalConfigReloadResult _complete(TerminalConfigResolution resolution) {
    try {
      final TerminalConfigSnapshot candidate = resolution.snapshot;
      if (_disposed) {
        return TerminalConfigReloadResult._(
          disposition: TerminalConfigReloadDisposition.disposed,
          effectiveSnapshot: _effectiveSnapshot,
          candidateSnapshot: candidate,
        );
      }
      if (!identical(candidate.schema, _effectiveSnapshot.schema)) {
        throw ArgumentError(
          'reload candidate and effective snapshot use different schemas',
        );
      }
      _lastAttemptedSnapshot = candidate;
      _lastAttemptDiagnostics = candidate.diagnostics;
      _lastFailure = null;
      _lastFailureStackTrace = null;
      final bool hasError = candidate.diagnostics.any(
        (TerminalConfigDiagnostic diagnostic) =>
            diagnostic.severity == TerminalConfigDiagnosticSeverity.error,
      );
      if (hasError) {
        return TerminalConfigReloadResult._(
          disposition: TerminalConfigReloadDisposition.rejected,
          effectiveSnapshot: _effectiveSnapshot,
          candidateSnapshot: candidate,
        );
      }
      final TerminalConfigChangePlan plan = TerminalConfigChangePlan.between(
        _effectiveSnapshot,
        candidate,
      );
      _effectiveSnapshot = candidate;
      _acceptedGeneration++;
      return TerminalConfigReloadResult._(
        disposition: plan.isEmpty
            ? TerminalConfigReloadDisposition.unchanged
            : TerminalConfigReloadDisposition.applied,
        effectiveSnapshot: candidate,
        candidateSnapshot: candidate,
        changePlan: plan,
      );
    } on Object catch (error, stackTrace) {
      return _recordFailure(error, stackTrace);
    } finally {
      _inProgress = false;
    }
  }

  TerminalConfigReloadResult _fail(Object error, StackTrace stackTrace) {
    _inProgress = false;
    if (_disposed) {
      return TerminalConfigReloadResult._(
        disposition: TerminalConfigReloadDisposition.disposed,
        effectiveSnapshot: _effectiveSnapshot,
      );
    }
    return _recordFailure(error, stackTrace);
  }

  TerminalConfigReloadResult _recordFailure(
    Object error,
    StackTrace stackTrace,
  ) {
    _lastFailure = error;
    _lastFailureStackTrace = stackTrace;
    return TerminalConfigReloadResult._(
      disposition: TerminalConfigReloadDisposition.failed,
      effectiveSnapshot: _effectiveSnapshot,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void dispose() {
    _disposed = true;
  }
}
