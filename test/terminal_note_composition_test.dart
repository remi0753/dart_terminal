import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNoteCompositionTests();

Future<void> runTerminalNoteCompositionTests() async {
  await _testDisabledAdmissionAndRestartLifecycle();
  await _testLiveFontIsolationAndFailureClassification();
  await _testRealWorkerDisabledEnabledReopen();
}

Future<void> _testDisabledAdmissionAndRestartLifecycle() async {
  final int subsystemBaseline =
      TerminalNoteCompositionRoot.debugLiveSubsystemCount;
  var factoryCalls = 0;
  var locationResolutions = 0;
  var storeStarts = 0;
  var contextBindings = 0;
  var surfaceCreates = 0;
  var timerCreates = 0;
  final _FakeNoteSubsystem runtime = _FakeNoteSubsystem();
  Future<TerminalNoteSubsystemStartResult> factory(
    TerminalNoteFeatureConfiguration configuration,
  ) async {
    factoryCalls++;
    locationResolutions++;
    storeStarts++;
    contextBindings++;
    surfaceCreates++;
    timerCreates++;
    return TerminalNoteSubsystemStartResult.available(runtime);
  }

  const TerminalNoteFeatureConfiguration disabledConfiguration =
      TerminalNoteFeatureConfiguration(
        notes: false,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 15,
      );
  final TerminalNoteCompositionRoot disabled =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: disabledConfiguration,
        factory: factory,
      );
  _expect(
    disabled.capability == TerminalNoteApplicationCapability.disabled &&
        !disabled.ownsRuntime &&
        factoryCalls == 0 &&
        locationResolutions == 0 &&
        storeStarts == 0 &&
        contextBindings == 0 &&
        surfaceCreates == 0 &&
        timerCreates == 0 &&
        TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
            subsystemBaseline &&
        disabled.applyLiveConfiguration(
              const TerminalNoteFeatureConfiguration(
                notes: false,
                notesOnReturn: true,
                notesNextPrompt: false,
                fontSize: 24,
              ),
            ) ==
            TerminalNoteLiveConfigurationDisposition.disabled,
    'C-01 disabled launch does not evaluate any Notes resource boundary',
  );
  final TerminalNoteCompositionShutdownDisposition disabledStop = await disabled
      .shutdown();

  const TerminalNoteFeatureConfiguration enabledConfiguration =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 15,
      );
  final TerminalNoteCompositionRoot enabled =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: enabledConfiguration,
        factory: factory,
      );
  _expect(
    disabledStop == TerminalNoteCompositionShutdownDisposition.stopped &&
        enabled.capability == TerminalNoteApplicationCapability.available &&
        enabled.ownsRuntime &&
        factoryCalls == 1 &&
        locationResolutions == 1 &&
        storeStarts == 1 &&
        contextBindings == 1 &&
        surfaceCreates == 1 &&
        timerCreates == 1 &&
        TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
            subsystemBaseline + 1,
    'a restart is the only transition that admits the enabled subsystem',
  );
  final Future<TerminalNoteCompositionShutdownDisposition> firstShutdown =
      enabled.shutdown();
  final Future<TerminalNoteCompositionShutdownDisposition> secondShutdown =
      enabled.shutdown();
  _expect(
    identical(firstShutdown, secondShutdown),
    'concurrent composition shutdown is single-flight',
  );
  final TerminalNoteCompositionShutdownDisposition enabledStop =
      await firstShutdown;

  final TerminalNoteCompositionRoot disabledAgain =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: disabledConfiguration,
        factory: factory,
      );
  await disabledAgain.shutdown();
  _expect(
    enabledStop == TerminalNoteCompositionShutdownDisposition.stopped &&
        runtime.shutdownCount == 1 &&
        factoryCalls == 1 &&
        TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
            subsystemBaseline,
    'enabled-to-disabled restart tears down once and does not recreate Notes',
  );
}

Future<void> _testLiveFontIsolationAndFailureClassification() async {
  final _FakeTerminalGeometry terminal = _FakeTerminalGeometry();
  final _FakeNoteSubsystem runtime = _FakeNoteSubsystem(terminal: terminal);
  const TerminalNoteFeatureConfiguration launch =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 12,
      );
  final TerminalNoteCompositionRoot root =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: launch,
        factory: (_) => TerminalNoteSubsystemStartResult.available(runtime),
      );
  final TerminalNoteLiveConfigurationDisposition noChange = root
      .applyLiveConfiguration(launch);
  final TerminalNoteLiveConfigurationDisposition stale = root
      .applyLiveConfiguration(
        const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 24,
        ),
      );
  final TerminalNoteLiveConfigurationDisposition applied = root
      .applyLiveConfiguration(
        const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: true,
          notesNextPrompt: false,
          fontSize: 24,
        ),
      );
  _expect(
    noChange == TerminalNoteLiveConfigurationDisposition.noChange &&
        stale == TerminalNoteLiveConfigurationDisposition.stale &&
        applied == TerminalNoteLiveConfigurationDisposition.applied &&
        runtime.applied.length == 1 &&
        runtime.applied.single.fontSize == 24 &&
        runtime.cardReflowCount == 1 &&
        runtime.editorReflowCount == 1 &&
        terminal.gridMutationCount == 0 &&
        terminal.drawableResizeCount == 0 &&
        terminal.winsizeMutationCount == 0 &&
        terminal.sigwinchCount == 0,
    'C-03 font 12-to-24 reflows Note UI without terminal geometry effects',
  );
  await root.shutdown();

  final TerminalNoteCompositionRoot classified =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: launch,
        factory: (_) => TerminalNoteSubsystemStartResult.failure(
          TerminalNoteApplicationCapability.inUseByOtherProcess,
        ),
      );
  final TerminalNoteCompositionRoot thrown =
      await TerminalNoteCompositionRoot.start(
        launchConfiguration: launch,
        factory: (_) => throw StateError('private startup detail'),
      );
  _expect(
    classified.capability ==
            TerminalNoteApplicationCapability.inUseByOtherProcess &&
        !classified.ownsRuntime &&
        thrown.capability == TerminalNoteApplicationCapability.unavailable &&
        !thrown.toString().contains('private startup detail'),
    'startup failure exposes only a fixed capability and retains no exception',
  );
  await classified.shutdown();
  await thrown.shutdown();
}

Future<void> _testRealWorkerDisabledEnabledReopen() async {
  final int subsystemBaseline =
      TerminalNoteCompositionRoot.debugLiveSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int clientBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-composition-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final String notePath = '${root.path}/notes';
  var factoryCalls = 0;
  var locationResolutions = 0;
  var generation = 70;
  Future<TerminalNoteSubsystemStartResult> factory(
    TerminalNoteFeatureConfiguration configuration,
  ) async {
    factoryCalls++;
    locationResolutions++;
    final TerminalNoteStoreLocation location =
        TerminalNoteStoreLocation.fromAbsolutePath(notePath);
    final TerminalNoteAuthority authority =
        await TerminalNoteAuthority.startWorker(
          location: location,
          authorityGeneration: generation++,
          restoration: null,
          paneIdsInTraversalOrder: const <PaneId>[],
          ensureQuickTerminalContext: true,
          updatedAtUtcMicros: generation,
        );
    return TerminalNoteSubsystemStartResult.available(
      _AuthorityNoteSubsystem(authority),
    );
  }

  const TerminalNoteFeatureConfiguration disabledConfiguration =
      TerminalNoteFeatureConfiguration(
        notes: false,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 15,
      );
  const TerminalNoteFeatureConfiguration enabledConfiguration =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 15,
      );
  try {
    final TerminalNoteCompositionRoot disabled =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: disabledConfiguration,
          factory: factory,
        );
    _expect(
      factoryCalls == 0 &&
          locationResolutions == 0 &&
          !Directory(notePath).existsSync() &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              clientBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline,
      'real disabled launch performs zero path, directory, worker, or authority work',
    );
    await disabled.shutdown();

    final TerminalNoteCompositionRoot enabled =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: enabledConfiguration,
          factory: factory,
        );
    _expect(
      enabled.capability == TerminalNoteApplicationCapability.available &&
          factoryCalls == 1 &&
          locationResolutions == 1 &&
          Directory(notePath).existsSync() &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              clientBaseline + 1 &&
          TerminalNoteAuthority.debugLiveAuthorityCount ==
              authorityBaseline + 1 &&
          TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
              subsystemBaseline + 1,
      'enabled restart creates exactly one real store worker and authority',
    );
    await enabled.shutdown();
    final File current = File(
      '$notePath/${TerminalNoteStoreTransactionEngine.currentLeaf}',
    );
    _expect(
      current.existsSync(),
      'enabled startup persists the Quick Terminal context binding',
    );
    final List<int> durableBytes = current.readAsBytesSync();

    final TerminalNoteCompositionRoot disabledAgain =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: disabledConfiguration,
          factory: factory,
        );
    await disabledAgain.shutdown();
    _expect(
      factoryCalls == 1 &&
          current.readAsBytesSync().toString() == durableBytes.toString() &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              clientBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline &&
          TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
              subsystemBaseline,
      'disabled restart leaves durable data untouched and every handle closed',
    );

    final TerminalNoteCompositionRoot reopened =
        await TerminalNoteCompositionRoot.start(
          launchConfiguration: enabledConfiguration,
          factory: factory,
        );
    _expect(
      reopened.capability == TerminalNoteApplicationCapability.available &&
          factoryCalls == 2 &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              clientBaseline + 1,
      're-enable reopens the preserved real store after a disabled launch',
    );
    await reopened.shutdown();
    _expect(
      TerminalNoteStoreWorkerClient.debugLiveClientCount == clientBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline &&
          TerminalNoteCompositionRoot.debugLiveSubsystemCount ==
              subsystemBaseline,
      'real disabled-enabled-reenabled sequence returns every owner to baseline',
    );
  } finally {
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  }
}

final class _FakeTerminalGeometry {
  var gridMutationCount = 0;
  var drawableResizeCount = 0;
  var winsizeMutationCount = 0;
  var sigwinchCount = 0;
}

final class _FakeNoteSubsystem implements TerminalNoteSubsystemPort {
  _FakeNoteSubsystem({this.terminal});

  final _FakeTerminalGeometry? terminal;
  final List<TerminalNoteFeatureConfiguration> applied =
      <TerminalNoteFeatureConfiguration>[];
  var cardReflowCount = 0;
  var editorReflowCount = 0;
  var shutdownCount = 0;

  @override
  void applyLiveConfiguration(TerminalNoteFeatureConfiguration configuration) {
    applied.add(configuration);
    cardReflowCount++;
    editorReflowCount++;
  }

  @override
  Future<void> shutdown() async {
    shutdownCount++;
  }
}

final class _AuthorityNoteSubsystem implements TerminalNoteSubsystemPort {
  _AuthorityNoteSubsystem(this.authority);

  final TerminalNoteAuthority authority;

  @override
  void applyLiveConfiguration(TerminalNoteFeatureConfiguration configuration) {}

  @override
  Future<void> shutdown() async {
    await authority.stop();
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
