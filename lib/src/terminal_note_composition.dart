import 'dart:async';

import 'terminal_product_configuration.dart';

enum TerminalNoteApplicationCapability {
  disabled,
  starting,
  available,
  inUseByOtherProcess,
  recoveryRequired,
  incompatibleStore,
  unavailable,
  stopped,
}

enum TerminalNoteLiveConfigurationDisposition {
  applied,
  noChange,
  disabled,
  stale,
  unavailable,
}

enum TerminalNoteCompositionShutdownDisposition {
  stopped,
  alreadyStopped,
  failed,
}

/// Product-owned runtime created only after the launch-fixed master flag is on.
abstract interface class TerminalNoteSubsystemPort {
  void applyLiveConfiguration(TerminalNoteFeatureConfiguration configuration);

  Future<void> shutdown();
}

final class TerminalNoteSubsystemStartResult {
  TerminalNoteSubsystemStartResult.available(TerminalNoteSubsystemPort runtime)
    : capability = TerminalNoteApplicationCapability.available,
      runtime = runtime;

  TerminalNoteSubsystemStartResult.failure(this.capability) : runtime = null {
    if (capability == TerminalNoteApplicationCapability.available ||
        capability == TerminalNoteApplicationCapability.disabled ||
        capability == TerminalNoteApplicationCapability.starting ||
        capability == TerminalNoteApplicationCapability.stopped) {
      throw ArgumentError.value(
        capability,
        'capability',
        'must be a fixed startup failure capability',
      );
    }
  }

  final TerminalNoteApplicationCapability capability;
  final TerminalNoteSubsystemPort? runtime;
}

typedef TerminalNoteSubsystemFactory =
    FutureOr<TerminalNoteSubsystemStartResult> Function(
      TerminalNoteFeatureConfiguration configuration,
    );

/// Lazy application composition boundary for the entire Notes subsystem.
///
/// The disabled branch does not invoke [factory]. Store-location resolution,
/// worker startup, context binding, native surfaces, and timers therefore stay
/// behind one launch-fixed admission decision.
final class TerminalNoteCompositionRoot {
  TerminalNoteCompositionRoot._({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required TerminalNoteApplicationCapability capability,
    required TerminalNoteSubsystemPort? runtime,
  }) : _launchConfiguration = launchConfiguration,
       _currentConfiguration = launchConfiguration,
       _capability = capability,
       _runtime = runtime {
    if (runtime != null) _debugLiveSubsystemCount++;
  }

  static Future<TerminalNoteCompositionRoot> start({
    required TerminalNoteFeatureConfiguration launchConfiguration,
    required TerminalNoteSubsystemFactory factory,
  }) async {
    if (!launchConfiguration.surfaceEnabled) {
      return TerminalNoteCompositionRoot._(
        launchConfiguration: launchConfiguration,
        capability: TerminalNoteApplicationCapability.disabled,
        runtime: null,
      );
    }
    try {
      final TerminalNoteSubsystemStartResult result = await factory(
        launchConfiguration,
      );
      return TerminalNoteCompositionRoot._(
        launchConfiguration: launchConfiguration,
        capability: result.capability,
        runtime: result.runtime,
      );
    } on Object {
      return TerminalNoteCompositionRoot._(
        launchConfiguration: launchConfiguration,
        capability: TerminalNoteApplicationCapability.unavailable,
        runtime: null,
      );
    }
  }

  static int _debugLiveSubsystemCount = 0;

  static int get debugLiveSubsystemCount => _debugLiveSubsystemCount;

  final TerminalNoteFeatureConfiguration _launchConfiguration;
  TerminalNoteFeatureConfiguration _currentConfiguration;
  TerminalNoteApplicationCapability _capability;
  TerminalNoteSubsystemPort? _runtime;
  Future<TerminalNoteCompositionShutdownDisposition>? _shutdownFuture;

  TerminalNoteFeatureConfiguration get launchConfiguration =>
      _launchConfiguration;
  TerminalNoteFeatureConfiguration get currentConfiguration =>
      _currentConfiguration;
  TerminalNoteApplicationCapability get capability => _capability;
  bool get ownsRuntime => _runtime != null;

  TerminalNoteLiveConfigurationDisposition applyLiveConfiguration(
    TerminalNoteFeatureConfiguration configuration,
  ) {
    if (_capability == TerminalNoteApplicationCapability.disabled) {
      return TerminalNoteLiveConfigurationDisposition.disabled;
    }
    if (_capability == TerminalNoteApplicationCapability.stopped) {
      return TerminalNoteLiveConfigurationDisposition.stale;
    }
    final TerminalNoteSubsystemPort? runtime = _runtime;
    if (_capability != TerminalNoteApplicationCapability.available ||
        runtime == null) {
      return TerminalNoteLiveConfigurationDisposition.unavailable;
    }
    if (configuration.notes != _launchConfiguration.notes ||
        configuration.notesOnReturn != _launchConfiguration.notesOnReturn ||
        configuration.notesNextPrompt != _launchConfiguration.notesNextPrompt) {
      return TerminalNoteLiveConfigurationDisposition.stale;
    }
    if (configuration == _currentConfiguration) {
      return TerminalNoteLiveConfigurationDisposition.noChange;
    }
    try {
      runtime.applyLiveConfiguration(configuration);
      _currentConfiguration = configuration;
      return TerminalNoteLiveConfigurationDisposition.applied;
    } on Object {
      _capability = TerminalNoteApplicationCapability.unavailable;
      return TerminalNoteLiveConfigurationDisposition.unavailable;
    }
  }

  Future<TerminalNoteCompositionShutdownDisposition> shutdown() {
    final Future<TerminalNoteCompositionShutdownDisposition>? existing =
        _shutdownFuture;
    if (existing != null) return existing;
    if (_capability == TerminalNoteApplicationCapability.stopped) {
      return Future<TerminalNoteCompositionShutdownDisposition>.value(
        TerminalNoteCompositionShutdownDisposition.alreadyStopped,
      );
    }
    return _shutdownFuture = _runShutdown();
  }

  Future<TerminalNoteCompositionShutdownDisposition> _runShutdown() async {
    final TerminalNoteSubsystemPort? runtime = _runtime;
    _runtime = null;
    var disposition = TerminalNoteCompositionShutdownDisposition.stopped;
    if (runtime != null) {
      try {
        await runtime.shutdown();
      } on Object {
        disposition = TerminalNoteCompositionShutdownDisposition.failed;
      } finally {
        _debugLiveSubsystemCount--;
      }
    }
    _capability = TerminalNoteApplicationCapability.stopped;
    return disposition;
  }

  @override
  String toString() =>
      'TerminalNoteCompositionRoot(${_capability.name}, runtime=$ownsRuntime)';
}
