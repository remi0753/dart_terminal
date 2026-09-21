import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_note_store_process.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

const bool _releaseAot = bool.fromEnvironment('dart.vm.product');
const String _requiredAbi = 'macos_arm64';
const String _requiredHardware = 'MacBookPro17,1';
const int _requiredMemoryBytes = 16 * 1024 * 1024 * 1024;
const String _requiredDartSdk = '3.13.2';
const int _idlePaneCount = 64;
const int _idleWindowMilliseconds = 250;
const int _idleRssBudgetBytes = 16 * 1024 * 1024;
const int _modelSampleCount = 64;
const int _modelP95BudgetMicroseconds = 1000;
const int _modelMaximumBudgetMicroseconds = 4000;
const int _projectionSampleCount = 21;
const int _projectionNoteCount = 128;
const int _projectionP95BudgetMicroseconds = 100000;
const int _steadyRssBudgetBytes = 64 * 1024 * 1024;
const int _peakRssBudgetBytes = 96 * 1024 * 1024;

Future<void> main(List<String> arguments) async {
  var phase = 'bootstrap';
  try {
    if (!_releaseAot) {
      throw StateError('R0 Note budget benchmark requires Release AOT');
    }
    final _BenchmarkEnvironment environment = _benchmarkEnvironment();
    if (arguments.isEmpty) {
      await _runParent(environment);
      return;
    }
    if (arguments.length != 1 || !arguments.single.startsWith('--phase=')) {
      throw const FormatException('R0 Note budget argument is invalid');
    }
    phase = arguments.single.substring('--phase='.length);
    final String result = switch (phase) {
      'idle' => await _runIdlePhase(),
      'model' => await _runModelPhase(),
      'projection' => await _runProjectionPhase(),
      'hard-cap' => await _runHardCapPhase(),
      _ => throw const FormatException('R0 Note budget phase is invalid'),
    };
    stdout.writeln(result);
  } on Object catch (error) {
    final String metrics = error is _HardCapBudgetFailure
        ? ' steady_delta_bytes=${error.steadyDeltaBytes} '
              'peak_delta_bytes=${error.peakDeltaBytes} '
              'file_bytes=${error.fileBytes}'
        : '';
    stderr.writeln(
      'TERMINAL_NOTE_R0_DART_BUDGET_FAIL phase=$phase '
      'reason=${_failureCode(error)}$metrics content_free=true',
    );
    exitCode = 1;
  }
}

String _failureCode(Object error) {
  if (error is _HardCapBudgetFailure) return error.code;
  if (error is StateError) {
    const Map<String, String> codes = <String, String>{
      'R0 Note budget benchmark requires Release AOT': 'not_release_aot',
      'R0 Note budget child failed': 'child_failed',
      'idle product startup failed': 'idle_startup',
      'idle surface attach failed': 'idle_attach',
      'idle fixture inventory is invalid': 'idle_inventory',
      'enabled collapsed idle budget failed': 'idle_budget',
      'idle fixture teardown leaked an owner': 'idle_teardown',
      'model product startup failed': 'model_startup',
      'model surface attach failed': 'model_attach',
      'model warmup transition failed': 'model_warmup',
      'model measured transition failed': 'model_transition',
      'model transition budget failed': 'model_budget',
      'model fixture teardown leaked an owner': 'model_teardown',
      'projection product startup failed': 'projection_startup',
      'projection collapsed fixture is invalid': 'projection_inventory',
      'projection toggle failed': 'projection_transition',
      'projection toggle visibility mismatch': 'projection_visibility',
      'projection measured page is invalid': 'projection_page',
      'projection first-visible budget failed': 'projection_budget',
      'projection fixture teardown leaked an owner': 'projection_teardown',
      'hard-cap worker startup failed': 'hard_cap_startup',
      'hard-cap commit failed': 'hard_cap_commit',
      'hard-cap fixture is invalid': 'hard_cap_fixture',
      'hard-cap file budget failed': 'hard_cap_file_budget',
      'hard-cap steady RSS budget failed': 'hard_cap_steady_rss_budget',
      'hard-cap peak RSS budget failed': 'hard_cap_peak_rss_budget',
      'hard-cap fixture teardown leaked an owner': 'hard_cap_teardown',
      'R0 Note benchmark requires macOS arm64': 'environment_abi',
      'R0 Note benchmark authority environment differs':
          'environment_authority',
      'R0 Note benchmark environment is unavailable': 'environment_unavailable',
    };
    return codes[error.message] ?? 'state_error';
  }
  if (error is FormatException) return 'format_error';
  return 'runtime_error';
}

Future<void> _runParent(_BenchmarkEnvironment environment) async {
  const List<String> phases = <String>[
    'idle',
    'model',
    'projection',
    'hard-cap',
  ];
  const Map<String, String> prefixes = <String, String>{
    'idle': 'TERMINAL_NOTE_R0_IDLE_PASS ',
    'model': 'TERMINAL_NOTE_R0_MODEL_PASS ',
    'projection': 'TERMINAL_NOTE_R0_PROJECTION_PASS ',
    'hard-cap': 'TERMINAL_NOTE_R0_HARD_CAP_PASS ',
  };
  final List<String> summaries = <String>[];
  for (final String phase in phases) {
    final ProcessResult child = await Process.run(
      Platform.resolvedExecutable,
      <String>['--phase=$phase'],
      workingDirectory: Directory.current.path,
    );
    final String output = child.stdout is String
        ? (child.stdout! as String).trim()
        : '';
    final String diagnostic = child.stderr is String
        ? (child.stderr! as String).trim()
        : '';
    final List<String> lines = const LineSplitter()
        .convert(output)
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (child.exitCode != 0 ||
        diagnostic.isNotEmpty ||
        lines.length != 1 ||
        !lines.single.startsWith(prefixes[phase]!)) {
      throw StateError('R0 Note budget child failed');
    }
    summaries.add(lines.single);
  }
  for (final String summary in summaries) {
    stdout.writeln(summary);
  }
  stdout.writeln(
    'TERMINAL_NOTE_R0_DART_BUDGET_PASS version=1 build=release-aot '
    'abi=${environment.abi} hardware=${environment.hardware} '
    'memory_bytes=${environment.memoryBytes} dart=${environment.dartSdk} '
    'phases=${phases.length} content_free=true',
  );
}

Future<String> _runIdlePhase() async {
  final _OwnerSnapshot ownersBefore = _OwnerSnapshot.capture();
  final TerminalCurrentProcessResourceSampler sampler =
      TerminalCurrentProcessResourceSampler();
  sampler.snapshot();
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r0-idle-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final String storePath = '${root.path}/store';
  TerminalNoteProductSubsystem? product;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final TerminalProcessResourceSnapshot baseline = sampler.snapshot();
    final List<PaneId> paneIds = List<PaneId>.generate(
      _idlePaneCount,
      (int index) => PaneId(index + 1),
      growable: false,
    );
    final List<_BenchmarkNativeChannel> channels = <_BenchmarkNativeChannel>[];
    final TerminalNoteSubsystemStartResult startup =
        await TerminalNoteProductSubsystem.start(
          configuration: _enabledConfiguration,
          environment: const <String, String>{},
          authorityGeneration: 1,
          restoration: null,
          initialPaneIdsInTraversalOrder: paneIds,
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 1,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () {
            final _BenchmarkNativeChannel channel = _BenchmarkNativeChannel();
            channels.add(channel);
            return channel;
          },
          locationResolver: (_) =>
              TerminalNoteStoreLocation.fromAbsolutePath(storePath),
          contextIdGenerator: _contextGenerator(1),
          noteIdGenerator: _noteGenerator(1000),
          clock: () => 2,
        );
    _expect(
      startup.capability == TerminalNoteApplicationCapability.available &&
          startup.runtime is TerminalNoteProductSubsystem,
      'idle product startup failed',
    );
    product = startup.runtime! as TerminalNoteProductSubsystem;
    for (var index = 0; index < paneIds.length; index++) {
      final TerminalNoteProductTopologyResult attached = await product
          .attachSurface(
            paneId: paneIds[index],
            configuration: _surfaceConfiguration(index + 1),
          );
      _expect(attached.isAccepted, 'idle surface attach failed');
    }
    _expect(
      product.livePaneCount == _idlePaneCount &&
          product.liveSurfaceCount == _idlePaneCount &&
          channels.length == _idlePaneCount &&
          channels.every(
            (_BenchmarkNativeChannel channel) =>
                channel.lastProjection?.visibility ==
                    TerminalNotesVisibility.collapsed &&
                channel.lastProjection?.cards.isEmpty == true,
          ) &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              ownersBefore.workers + 1,
      'idle fixture inventory is invalid',
    );
    final int projectionBefore = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.applyCount,
    );
    final int notificationBefore = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.notificationCount,
    );
    final int layoutBefore = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.layoutCount,
    );
    final Map<String, List<int>> storeBefore = _captureStorePayloads(
      Directory(storePath),
    );
    await Future<void>.delayed(
      const Duration(milliseconds: _idleWindowMilliseconds),
    );
    final TerminalProcessResourceSnapshot settled = sampler.snapshot();
    final int projectionAfter = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.applyCount,
    );
    final int notificationAfter = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.notificationCount,
    );
    final int layoutAfter = channels.fold<int>(
      0,
      (int total, _BenchmarkNativeChannel channel) =>
          total + channel.layoutCount,
    );
    final int rssDelta = max(
      0,
      settled.currentResidentBytes - baseline.currentResidentBytes,
    );
    final bool storeUnchanged = _sameFiles(
      storeBefore,
      _captureStorePayloads(Directory(storePath)),
    );
    _expect(
      rssDelta <= _idleRssBudgetBytes &&
          projectionAfter == projectionBefore &&
          notificationAfter == notificationBefore &&
          layoutAfter == layoutBefore &&
          storeUnchanged,
      'enabled collapsed idle budget failed',
    );
    await product.shutdown();
    final int ownerDelta = _OwnerSnapshot.capture().deltaFrom(ownersBefore);
    _expect(
      product.isStopped &&
          product.livePaneCount == 0 &&
          product.liveSurfaceCount == 0 &&
          channels.every(
            (_BenchmarkNativeChannel channel) => channel.disposeCount == 1,
          ) &&
          ownerDelta == 0,
      'idle fixture teardown leaked an owner',
    );
    return 'TERMINAL_NOTE_R0_IDLE_PASS panes=$_idlePaneCount '
        'surfaces=$_idlePaneCount worker=1 rss_delta_bytes=$rssDelta '
        'rss_budget_bytes=$_idleRssBudgetBytes '
        'idle_window_ms=$_idleWindowMilliseconds projection_delta=0 '
        'notification_delta=0 layout_delta=0 frame_delta=0 '
        'store_changes=0 owners=$ownerDelta';
  } finally {
    if (product != null && !product.isStopped) await product.shutdown();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<String> _runModelPhase() async {
  final _OwnerSnapshot ownersBefore = _OwnerSnapshot.capture();
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r0-model-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final _MemoryStoreFactory storeFactory = _MemoryStoreFactory(
    TerminalNoteStoreDocument(snapshot: TerminalNoteSnapshot.empty()),
  );
  final _BenchmarkNativeChannel channel = _BenchmarkNativeChannel();
  TerminalNoteProductSubsystem? product;
  try {
    final TerminalNoteSubsystemStartResult startup =
        await TerminalNoteProductSubsystem.start(
          configuration: _enabledConfiguration,
          environment: const <String, String>{},
          authorityGeneration: 2,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 1,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => channel,
          locationResolver: (_) =>
              TerminalNoteStoreLocation.fromAbsolutePath(root.path),
          storeFactory: storeFactory,
          contextIdGenerator: _contextGenerator(2000),
          noteIdGenerator: _noteGenerator(3000),
          clock: () => 2,
        );
    _expect(
      startup.capability == TerminalNoteApplicationCapability.available &&
          startup.runtime is TerminalNoteProductSubsystem,
      'model product startup failed',
    );
    product = startup.runtime! as TerminalNoteProductSubsystem;
    final TerminalNoteProductTopologyResult attached = await product
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(1),
        );
    _expect(attached.isAccepted, 'model surface attach failed');
    for (var index = 0; index < 16; index++) {
      _expect(
        (await product.performAction(
          const PaneId(1),
          TerminalNoteProductActionKind.toggleNotes,
        )).isAccepted,
        'model warmup transition failed',
      );
    }
    final int commitBefore = storeFactory.store.commitCount;
    final int applyBefore = channel.applyCount;
    final List<int> samples = <int>[];
    for (var index = 0; index < _modelSampleCount; index++) {
      final Stopwatch watch = Stopwatch()..start();
      final TerminalNoteProductTopologyResult result = await product
          .performAction(
            const PaneId(1),
            TerminalNoteProductActionKind.toggleNotes,
          );
      watch.stop();
      _expect(result.isAccepted, 'model measured transition failed');
      samples.add(watch.elapsedMicroseconds);
    }
    final int p95 = _percentile(samples, 95);
    final int maximum = samples.reduce(max);
    final int commitDelta = storeFactory.store.commitCount - commitBefore;
    _expect(
      p95 <= _modelP95BudgetMicroseconds &&
          maximum <= _modelMaximumBudgetMicroseconds &&
          commitDelta == 0 &&
          channel.applyCount - applyBefore == _modelSampleCount,
      'model transition budget failed',
    );
    await product.shutdown();
    final int ownerDelta = _OwnerSnapshot.capture().deltaFrom(ownersBefore);
    _expect(ownerDelta == 0, 'model fixture teardown leaked an owner');
    return 'TERMINAL_NOTE_R0_MODEL_PASS samples=$_modelSampleCount '
        'p95_us=$p95 max_us=$maximum '
        'p95_budget_us=$_modelP95BudgetMicroseconds '
        'max_budget_us=$_modelMaximumBudgetMicroseconds '
        'store_commit_delta=$commitDelta body_encode=0 fsync=0 '
        'owners=$ownerDelta';
  } finally {
    if (product != null && !product.isStopped) await product.shutdown();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<String> _runProjectionPhase() async {
  final _OwnerSnapshot ownersBefore = _OwnerSnapshot.capture();
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r0-projection-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final ({
    TerminalNoteStoreDocument document,
    TerminalNoteRestorationArtifact restoration,
  })
  fixture = _projectionFixture();
  final _MemoryStoreFactory storeFactory = _MemoryStoreFactory(
    fixture.document,
  );
  final _BenchmarkNativeChannel channel = _BenchmarkNativeChannel();
  TerminalNoteProductSubsystem? product;
  try {
    final TerminalNoteSubsystemStartResult startup =
        await TerminalNoteProductSubsystem.start(
          configuration: _enabledConfiguration,
          environment: const <String, String>{},
          authorityGeneration: 3,
          restoration: fixture.restoration,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
          ensureQuickTerminalContext: false,
          updatedAtUtcMicros: 1000,
          copyEffect: (_) => true,
          exportDestinationChooser: (_) => null,
          initializeNativeCapability: () {},
          surfaceFactory: () => channel,
          locationResolver: (_) =>
              TerminalNoteStoreLocation.fromAbsolutePath(root.path),
          storeFactory: storeFactory,
          contextIdGenerator: _contextGenerator(4000),
          noteIdGenerator: _noteGenerator(5000),
          clock: () => 1001,
        );
    _expect(
      startup.capability == TerminalNoteApplicationCapability.available &&
          startup.runtime is TerminalNoteProductSubsystem,
      'projection product startup failed',
    );
    product = startup.runtime! as TerminalNoteProductSubsystem;
    final TerminalNoteProductTopologyResult attached = await product
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(1),
        );
    _expect(
      attached.isAccepted &&
          channel.lastProjection?.visibility ==
              TerminalNotesVisibility.collapsed &&
          channel.lastProjection?.activeCount == _projectionNoteCount,
      'projection collapsed fixture is invalid',
    );
    for (var index = 0; index < 4; index++) {
      await _toggleAndRequire(product, TerminalNotesVisibility.expanded);
      await _toggleAndRequire(product, TerminalNotesVisibility.collapsed);
    }
    final int commitBefore = storeFactory.store.commitCount;
    final List<int> samples = <int>[];
    for (var index = 0; index < _projectionSampleCount; index++) {
      final Stopwatch watch = Stopwatch()..start();
      await _toggleAndRequire(product, TerminalNotesVisibility.expanded);
      watch.stop();
      final TerminalNotesProjection projection = channel.lastProjection!;
      _expect(
        projection.cards.length == TerminalNotesLimits.maximumCards &&
            projection.totalCount == _projectionNoteCount &&
            projection.aggregateBodyUtf8Bytes ==
                TerminalNotesLimits.maximumAggregateBodyUtf8Bytes,
        'projection measured page is invalid',
      );
      samples.add(watch.elapsedMicroseconds);
      await _toggleAndRequire(product, TerminalNotesVisibility.collapsed);
    }
    final int p95 = _percentile(samples, 95);
    final int commitDelta = storeFactory.store.commitCount - commitBefore;
    _expect(
      p95 <= _projectionP95BudgetMicroseconds && commitDelta == 0,
      'projection first-visible budget failed',
    );
    await product.shutdown();
    final int ownerDelta = _OwnerSnapshot.capture().deltaFrom(ownersBefore);
    _expect(ownerDelta == 0, 'projection fixture teardown leaked an owner');
    return 'TERMINAL_NOTE_R0_PROJECTION_PASS '
        'samples=$_projectionSampleCount notes=$_projectionNoteCount '
        'cards=${TerminalNotesLimits.maximumCards} '
        'body_bytes=${TerminalNotesLimits.maximumAggregateBodyUtf8Bytes} '
        'p95_us=$p95 budget_us=$_projectionP95BudgetMicroseconds '
        'store_commit_delta=$commitDelta owners=$ownerDelta';
  } finally {
    if (product != null && !product.isStopped) await product.shutdown();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<String> _runHardCapPhase() async {
  final _OwnerSnapshot ownersBefore = _OwnerSnapshot.capture();
  final TerminalCurrentProcessResourceSampler sampler =
      TerminalCurrentProcessResourceSampler();
  sampler.snapshot();
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-r0-hard-cap-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  TerminalNoteStoreWorkerClient? client;
  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final TerminalProcessResourceSnapshot baseline = sampler.snapshot();
    final TerminalNoteStoreDocument document = _hardCapDocument();
    final TerminalNoteStoreWorkerStartup startup =
        await TerminalNoteStoreWorkerClient.start(
          location: TerminalNoteStoreLocation.fromAbsolutePath(
            '${root.path}/store',
          ),
          authorityGeneration: 4,
        );
    _expect(
      startup.hasLiveClient && startup.loadResult.isSuccess,
      'hard-cap worker startup failed',
    );
    client = startup.client!;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final TerminalProcessResourceSnapshot steady = sampler.snapshot();
    final int steadyDelta = max(
      0,
      steady.currentResidentBytes - baseline.currentResidentBytes,
    );
    var complete = false;
    var maximumPeakBytes = steady.peakResidentBytes;
    final Future<TerminalNoteStoreResult> commitFuture = client
        .commitCandidate(document)
        .whenComplete(() => complete = true);
    while (!complete) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final TerminalProcessResourceSnapshot sample = sampler.snapshot();
      maximumPeakBytes = max(
        maximumPeakBytes,
        max(sample.currentResidentBytes, sample.peakResidentBytes),
      );
    }
    final TerminalNoteStoreResult committed = await commitFuture;
    final TerminalProcessResourceSnapshot afterCommit = sampler.snapshot();
    maximumPeakBytes = max(
      maximumPeakBytes,
      max(afterCommit.currentResidentBytes, afterCommit.peakResidentBytes),
    );
    final int peakDelta = max(0, maximumPeakBytes - baseline.peakResidentBytes);
    final int fileBytes = committed.metrics.canonicalBytes;
    _expect(committed.isSuccess, 'hard-cap commit failed');
    _expect(
      document.snapshot.contexts.length == TerminalNoteLimits.maximumContexts &&
          document.snapshot.notes.length == TerminalNoteLimits.maximumNotes &&
          document.snapshot.triggers.length ==
              TerminalNoteLimits.maximumTriggers &&
          document.snapshot.deliveries.length ==
              TerminalNoteLimits.maximumDeliveries &&
          document.snapshot.aggregateBodyUtf8Bytes ==
              TerminalNoteLimits.maximumAggregateBodyUtf8Bytes,
      'hard-cap fixture is invalid',
    );
    _expect(
      fileBytes > 0 &&
          fileBytes <= TerminalNoteStoreCodecLimits.maximumFileBytes,
      'hard-cap file budget failed',
    );
    if (steadyDelta > _steadyRssBudgetBytes) {
      throw _HardCapBudgetFailure(
        code: 'hard_cap_steady_rss_budget',
        steadyDeltaBytes: steadyDelta,
        peakDeltaBytes: peakDelta,
        fileBytes: fileBytes,
      );
    }
    if (peakDelta > _peakRssBudgetBytes) {
      throw _HardCapBudgetFailure(
        code: 'hard_cap_peak_rss_budget',
        steadyDeltaBytes: steadyDelta,
        peakDeltaBytes: peakDelta,
        fileBytes: fileBytes,
      );
    }
    final TerminalNoteStoreResult stopped = await client.stop();
    final int ownerDelta = _OwnerSnapshot.capture().deltaFrom(ownersBefore);
    _expect(
      stopped.disposition == TerminalNoteStoreDisposition.stopped &&
          ownerDelta == 0,
      'hard-cap fixture teardown leaked an owner',
    );
    return 'TERMINAL_NOTE_R0_HARD_CAP_PASS '
        'notes=${TerminalNoteLimits.maximumNotes} '
        'contexts=${TerminalNoteLimits.maximumContexts} '
        'triggers=${TerminalNoteLimits.maximumTriggers} '
        'deliveries=${TerminalNoteLimits.maximumDeliveries} '
        'body_bytes=${TerminalNoteLimits.maximumAggregateBodyUtf8Bytes} '
        'file_bytes=$fileBytes steady_delta_bytes=$steadyDelta '
        'steady_budget_bytes=$_steadyRssBudgetBytes '
        'peak_delta_bytes=$peakDelta peak_budget_bytes=$_peakRssBudgetBytes '
        'owners=$ownerDelta';
  } finally {
    if (client != null && !client.isStopped) await client.stop();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<void> _toggleAndRequire(
  TerminalNoteProductSubsystem product,
  TerminalNotesVisibility expected,
) async {
  final TerminalNoteProductTopologyResult result = await product.performAction(
    const PaneId(1),
    TerminalNoteProductActionKind.toggleNotes,
  );
  _expect(result.isAccepted, 'projection toggle failed');
  final TerminalNoteProductInteractionSnapshot? interaction = product
      .interactionSnapshotForPane(const PaneId(1));
  _expect(
    interaction?.visibility.name == expected.name,
    'projection toggle visibility mismatch',
  );
}

({
  TerminalNoteStoreDocument document,
  TerminalNoteRestorationArtifact restoration,
})
_projectionFixture() {
  final TerminalNoteRestorationArtifact restoration =
      TerminalNoteRestorationArtifact.fromSnapshot(_onePaneRestoration());
  final TerminalNoteContextReconciliationResult reconciled =
      TerminalNoteContextReconciler(_contextGenerator(6000)).reconcile(
        stored: TerminalNoteStoreDocument(
          snapshot: TerminalNoteSnapshot.empty(),
        ),
        restoration: restoration,
        paneIdsInTraversalOrder: const <PaneId>[PaneId(1)],
        ensureQuickTerminalContext: false,
        updatedAtUtcMicros: 1,
      );
  final TerminalNoteContextId contextId = reconciled.bindings.contextForPane(
    const PaneId(1),
  )!;
  final String tail = List<String>.filled(4088, 'p', growable: false).join();
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{};
  for (var index = 0; index < _projectionNoteCount; index++) {
    final NoteId id = _noteId('b0000000', index);
    notes[id] = NoteRecord(
      id: id,
      attachment: TerminalNoteAttachment.attached(contextId),
      body: NoteBody.fromText(
        '${index.toRadixString(16).padLeft(8, '0')}$tail',
      ),
      color: NoteColorKey.values[index % NoteColorKey.values.length],
      status: NoteStatus.active,
      order: index,
      createdAtUtcMicros: index,
      updatedAtUtcMicros: index,
      revision: BigInt.one,
    );
  }
  return (
    document: TerminalNoteStoreDocument(
      snapshot: TerminalNoteSnapshot.fromRecords(
        storeRevision: BigInt.from(_projectionNoteCount + 1),
        nextDeliverySequence: BigInt.one,
        contexts: reconciled.document.snapshot.contexts,
        notes: notes,
        triggers: const <NoteId, NoteTriggerRecord>{},
        deliveries: const <NoteId, NoteDeliveryRecord>{},
      ),
      restorationBinding: reconciled.document.restorationBinding,
    ),
    restoration: restoration,
  );
}

TerminalNoteStoreDocument _hardCapDocument() {
  final Map<TerminalNoteContextId, NoteContextRecord> contexts =
      <TerminalNoteContextId, NoteContextRecord>{};
  for (var index = 0; index < TerminalNoteLimits.maximumContexts; index++) {
    final TerminalNoteContextId id = _contextId('a0000000', index);
    contexts[id] = NoteContextRecord(
      id: id,
      kind: TerminalNoteContextKind.standard,
      state: TerminalNoteContextState.active,
      revision: BigInt.one,
    );
  }
  final List<TerminalNoteContextId> attachedContexts = contexts.keys
      .take(
        TerminalNoteLimits.maximumNotes ~/
            TerminalNoteLimits.maximumNotesPerAttachedContext,
      )
      .toList(growable: false);
  final String tail = List<String>.filled(4088, 'h', growable: false).join();
  final Map<NoteId, NoteRecord> notes = <NoteId, NoteRecord>{};
  final Map<NoteId, NoteTriggerRecord> triggers = <NoteId, NoteTriggerRecord>{};
  final Map<NoteId, NoteDeliveryRecord> deliveries =
      <NoteId, NoteDeliveryRecord>{};
  for (var index = 0; index < TerminalNoteLimits.maximumNotes; index++) {
    final NoteId id = _noteId('c0000000', index);
    notes[id] = NoteRecord(
      id: id,
      attachment: TerminalNoteAttachment.attached(
        attachedContexts[index ~/
            TerminalNoteLimits.maximumNotesPerAttachedContext],
      ),
      body: NoteBody.fromText(
        '${index.toRadixString(16).padLeft(8, '0')}$tail',
      ),
      color: NoteColorKey.yellow,
      status: NoteStatus.active,
      order: index % TerminalNoteLimits.maximumNotesPerAttachedContext,
      createdAtUtcMicros: index,
      updatedAtUtcMicros: index,
      revision: BigInt.one,
    );
    triggers[id] = NoteTriggerRecord(
      noteId: id,
      generation: BigInt.one,
      kind: NoteTriggerKind.onReturn,
      phase: NoteTriggerPhase.due,
      suspendReason: null,
      armedAtRevision: BigInt.one,
    );
    deliveries[id] = NoteDeliveryRecord(
      noteId: id,
      triggerGeneration: BigInt.one,
      sequence: DeliverySequence(BigInt.from(index + 1)),
    );
  }
  return TerminalNoteStoreDocument(
    snapshot: TerminalNoteSnapshot.fromRecords(
      storeRevision: BigInt.from(TerminalNoteLimits.maximumNotes),
      nextDeliverySequence: BigInt.from(TerminalNoteLimits.maximumNotes + 1),
      contexts: contexts,
      notes: notes,
      triggers: triggers,
      deliveries: deliveries,
    ),
  );
}

const TerminalNoteFeatureConfiguration _enabledConfiguration =
    TerminalNoteFeatureConfiguration(
      notes: true,
      notesOnReturn: true,
      notesNextPrompt: false,
      fontSize: 15,
    );

TerminalNoteProductSurfaceConfiguration _surfaceConfiguration(int identity) =>
    TerminalNoteProductSurfaceConfiguration(
      rendererIdentity: TerminalMetalRendererCompositionIdentity(
        handle: identity,
        generation: identity,
      ),
      paneWidth: 800,
      paneHeight: 500,
      backingScale: 2,
      requestedRailWidth: 320,
      visibility: TerminalNoteSurfaceVisibility.collapsed,
      foreground: false,
      occluded: true,
    );

TerminalRestorationSnapshot _onePaneRestoration() =>
    TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        TerminalRestorableWindow(
          placement: TerminalWindowPlacement(
            windowedFrame: TerminalWindowFrame(
              left: 100,
              top: 100,
              width: 800,
              height: 500,
            ),
            screen: null,
            fullscreen: false,
          ),
          tabs: <TerminalRestorableTab>[
            TerminalRestorableTab(
              splitTree: TerminalRestorableSplitLeaf(
                TerminalRestorablePane(workingDirectory: null),
              ),
              focusedPaneIndex: 0,
              zoomedPaneIndex: null,
              customTitle: null,
              color: null,
            ),
          ],
          selectedTabIndex: 0,
        ),
      ],
      activeWindowIndex: 0,
    );

TerminalNoteContextIdGenerator _contextGenerator(int initial) {
  var value = initial;
  return TerminalNoteContextIdGenerator.forTesting(
    () => _identityBytes(value++),
  );
}

TerminalNoteIdGenerator _noteGenerator(int initial) {
  var value = initial;
  return TerminalNoteIdGenerator.forTesting(() => _identityBytes(value++));
}

List<int> _identityBytes(int value) {
  final List<int> bytes = List<int>.filled(16, 0);
  for (var index = 0; index < 8; index++) {
    bytes[15 - index] = (value >> (index * 8)) & 0xff;
  }
  return bytes;
}

TerminalNoteContextId _contextId(String prefix, int value) =>
    TerminalNoteContextId.fromHex(
      '$prefix${value.toRadixString(16).padLeft(24, '0')}',
    );

NoteId _noteId(String prefix, int value) =>
    NoteId.fromHex('$prefix${value.toRadixString(16).padLeft(24, '0')}');

int _percentile(List<int> samples, int percentile) {
  final List<int> sorted = List<int>.of(samples)..sort();
  final int index = ((sorted.length * percentile + 99) ~/ 100) - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

Map<String, List<int>> _captureStorePayloads(Directory directory) {
  const Set<String> leaves = <String>{
    TerminalNoteStoreTransactionEngine.currentLeaf,
    TerminalNoteStoreTransactionEngine.backupLeaf,
    TerminalNoteStoreTransactionEngine.deletionJournalLeaf,
  };
  final Map<String, List<int>> result = <String, List<int>>{};
  if (!directory.existsSync()) return result;
  for (final FileSystemEntity entity in directory.listSync(
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String leaf = entity.uri.pathSegments.last;
    if (leaves.contains(leaf)) result[leaf] = entity.readAsBytesSync();
  }
  return result;
}

bool _sameFiles(Map<String, List<int>> left, Map<String, List<int>> right) {
  if (left.length != right.length ||
      !left.keys.toSet().containsAll(right.keys)) {
    return false;
  }
  for (final String name in left.keys) {
    final List<int> a = left[name]!;
    final List<int> b = right[name]!;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
  }
  return true;
}

_BenchmarkEnvironment _benchmarkEnvironment() {
  if (!Platform.isMacOS || Abi.current().toString() != _requiredAbi) {
    throw StateError('R0 Note benchmark requires macOS arm64');
  }
  final String hardware = _sysctl('hw.model');
  final int memoryBytes = int.parse(_sysctl('hw.memsize'));
  final String dartSdk = Platform.version.split(' ').first;
  if (hardware != _requiredHardware ||
      memoryBytes != _requiredMemoryBytes ||
      dartSdk != _requiredDartSdk) {
    throw StateError('R0 Note benchmark authority environment differs');
  }
  return _BenchmarkEnvironment(
    abi: _requiredAbi,
    hardware: hardware,
    memoryBytes: memoryBytes,
    dartSdk: dartSdk,
  );
}

String _sysctl(String name) {
  final ProcessResult result = Process.runSync('/usr/sbin/sysctl', <String>[
    '-n',
    name,
  ]);
  final String value = result.stdout is String
      ? (result.stdout! as String).trim()
      : '';
  if (result.exitCode != 0 ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains('\n')) {
    throw StateError('R0 Note benchmark environment is unavailable');
  }
  return value;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _BenchmarkEnvironment {
  const _BenchmarkEnvironment({
    required this.abi,
    required this.hardware,
    required this.memoryBytes,
    required this.dartSdk,
  });

  final String abi;
  final String hardware;
  final int memoryBytes;
  final String dartSdk;
}

final class _HardCapBudgetFailure implements Exception {
  const _HardCapBudgetFailure({
    required this.code,
    required this.steadyDeltaBytes,
    required this.peakDeltaBytes,
    required this.fileBytes,
  });

  final String code;
  final int steadyDeltaBytes;
  final int peakDeltaBytes;
  final int fileBytes;
}

final class _OwnerSnapshot {
  const _OwnerSnapshot({
    required this.compositions,
    required this.products,
    required this.authorities,
    required this.workers,
    required this.processPorts,
    required this.interactionAdapters,
  });

  factory _OwnerSnapshot.capture() => _OwnerSnapshot(
    compositions: TerminalNoteCompositionRoot.debugLiveSubsystemCount,
    products: TerminalNoteProductSubsystem.debugLiveProductSubsystemCount,
    authorities: TerminalNoteAuthority.debugLiveAuthorityCount,
    workers: TerminalNoteStoreWorkerClient.debugLiveClientCount,
    processPorts: TerminalNoteProcessStoreFactory.debugLivePortCount,
    interactionAdapters:
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount,
  );

  final int compositions;
  final int products;
  final int authorities;
  final int workers;
  final int processPorts;
  final int interactionAdapters;

  int deltaFrom(_OwnerSnapshot other) =>
      (compositions - other.compositions).abs() +
      (products - other.products).abs() +
      (authorities - other.authorities).abs() +
      (workers - other.workers).abs() +
      (processPorts - other.processPorts).abs() +
      (interactionAdapters - other.interactionAdapters).abs();
}

final class _MemoryStoreFactory implements TerminalNoteAuthorityStoreFactory {
  _MemoryStoreFactory(TerminalNoteStoreDocument document)
    : store = _MemoryStore(document);

  final _MemoryStore store;
  var startCount = 0;

  @override
  Future<TerminalNoteAuthorityStoreStartup> start({
    required TerminalNoteStoreLocation location,
    required int authorityGeneration,
  }) async {
    startCount++;
    if (startCount != 1 || authorityGeneration <= 0) {
      return TerminalNoteAuthorityStoreStartup(
        store: null,
        loadResult: _storeFailure(TerminalNoteStoreFailure.invalidState),
      );
    }
    return TerminalNoteAuthorityStoreStartup(
      store: store,
      loadResult: store.loadResult,
    );
  }
}

final class _MemoryStore implements TerminalNoteAuthorityStorePort {
  _MemoryStore(this.current);

  TerminalNoteStoreDocument current;
  var commitCount = 0;
  var stopCount = 0;
  var stopped = false;

  TerminalNoteStoreResult get loadResult => TerminalNoteStoreResult(
    disposition: current.snapshot.storeRevision == BigInt.zero
        ? TerminalNoteStoreDisposition.empty
        : TerminalNoteStoreDisposition.loaded,
    failure: null,
    storeRevision: current.snapshot.storeRevision,
    metrics: _metrics(current),
    document: current,
  );

  @override
  Future<TerminalNoteStoreResult> commitCandidate(
    TerminalNoteStoreDocument candidate, {
    Iterable<TerminalNoteDeletionTombstone> deletions =
        const <TerminalNoteDeletionTombstone>[],
  }) async {
    if (stopped ||
        candidate.snapshot.storeRevision <= current.snapshot.storeRevision) {
      return _storeFailure(TerminalNoteStoreFailure.revisionConflict);
    }
    current = candidate;
    commitCount++;
    return TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.committed,
      failure: null,
      storeRevision: current.snapshot.storeRevision,
      metrics: _metrics(current),
    );
  }

  @override
  Future<TerminalNoteStoreResult> exportToApprovedPath(
    TerminalNoteApprovedExportPath destination,
  ) async => _storeFailure(TerminalNoteStoreFailure.invalidState);

  @override
  Future<TerminalNoteStoreResult> stop() async {
    stopped = true;
    stopCount++;
    return TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.stopped,
      failure: null,
      storeRevision: current.snapshot.storeRevision,
      metrics: _metrics(current),
    );
  }
}

TerminalNoteStoreMetrics _metrics(TerminalNoteStoreDocument document) =>
    TerminalNoteStoreMetrics(
      noteCount: document.snapshot.notes.length,
      activeCount: document.snapshot.notes.values
          .where((NoteRecord note) => note.status == NoteStatus.active)
          .length,
      dueCount: document.snapshot.deliveries.length,
      detachedCount: document.snapshot.notes.values
          .where((NoteRecord note) => note.attachment.isDetached)
          .length,
      canonicalBytes: 0,
    );

TerminalNoteStoreResult _storeFailure(TerminalNoteStoreFailure failure) =>
    TerminalNoteStoreResult(
      disposition: TerminalNoteStoreDisposition.unavailable,
      failure: failure,
      storeRevision: BigInt.zero,
      metrics: TerminalNoteStoreMetrics.zero,
    );

final class _BenchmarkNativeChannel
    implements TerminalNoteNativeSurfaceChannel {
  TerminalNotesProjection? lastProjection;
  void Function()? notificationHandler;
  var applyCount = 0;
  var notificationCount = 0;
  var layoutCount = 0;
  var detachCount = 0;
  var disposeCount = 0;
  var attached = false;

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    lastProjection = projection;
    applyCount++;
    return TerminalNotesApplyDisposition.accepted;
  }

  @override
  TerminalNotesNativeSnapshot get snapshot {
    final TerminalNotesProjection projection = lastProjection!;
    return TerminalNotesNativeSnapshot(
      paneId: projection.paneId,
      surfaceGeneration: projection.surfaceGeneration,
      projectionGeneration: projection.projectionGeneration,
      storeRevision: projection.storeRevision,
      acceptedProjectionCount: applyCount,
      rejectedProjectionCount: 0,
      draftGeneration: projection.draftGeneration,
      activeCount: projection.activeCount,
      dueCount: projection.dueCount,
      projectedCardCount: projection.cards.length,
      materializedCardCount: min(
        projection.cards.length,
        TerminalNotesLimits.maximumMaterializedCards,
      ),
      packetBytes: 0,
      visibility: projection.visibility,
      presentationEligible: projection.presentationEligible,
      initialized: true,
      readyCue: projection.readyCue,
      darkAppearance: projection.darkAppearance,
      increaseContrast: projection.increaseContrast,
      differentiateWithoutColor: projection.differentiateWithoutColor,
      reduceMotion: projection.reduceMotion,
      systemBadgeVisible: projection.systemBadgeVisible,
      onReturnEnabled: projection.onReturnEnabled,
      featureState: projection.featureState,
      surfaceState: projection.surfaceState,
      section: projection.section,
      editorMode: projection.editorMode,
      messageKey: projection.messageKey,
      pageStart: projection.pageStart,
      totalCount: projection.totalCount,
      bodyFontMilliPoints: projection.bodyFontMilliPoints,
      outstandingIntent: false,
      emittedIntentCount: 0,
      appliedResultCount: 0,
      editorDirty: false,
      confirmingDiscard: false,
      focusTarget: TerminalNotesNativeFocusTarget.none,
    );
  }

  @override
  TerminalNotesNativePresentation
  get presentation => TerminalNotesNativePresentation(
    projectionGeneration: lastProjection!.projectionGeneration,
    paneWidth: 800,
    paneHeight: 500,
    backingScale: 2,
    badgeHit: const TerminalNotesRect(x: 744, y: 228, width: 44, height: 44),
    badgeVisual: const TerminalNotesRect(x: 744, y: 236, width: 44, height: 28),
    rail: const TerminalNotesRect(x: 468, y: 12, width: 320, height: 476),
    firstCard: const TerminalNotesRect(x: 480, y: 74, width: 284, height: 88),
    flags: lastProjection!.visibility == TerminalNotesVisibility.expanded
        ? 2
        : 1,
    materializedCardCount: min(
      lastProjection!.cards.length,
      TerminalNotesLimits.maximumMaterializedCards,
    ),
    accessibilityNodeCount: 1,
    accessibilityBodyCount: lastProjection!.cards.length,
    visibleAcknowledgementEligibleGeneration: 0,
    accessibilityAnnouncementCount: 0,
    animationMilliseconds: 0,
    bodyFontMilliPoints: lastProjection!.bodyFontMilliPoints,
    badgeDisplayCount: lastProjection!.activeCount,
  );

  @override
  void setNotificationHandler(void Function()? handler) {
    notificationHandler = handler;
  }

  @override
  TerminalNotesNativeIntent? takeIntent() => null;

  @override
  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) => TerminalNotesResultApplyDisposition.accepted;

  @override
  bool focus(TerminalNotesNativeFocusTarget target) => true;

  @override
  bool presentDiscardConfirmation() => true;

  @override
  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) {
    attached = true;
    return TerminalNotesAttachDisposition.attached;
  }

  @override
  void detachFromHost() {
    attached = false;
    detachCount++;
  }

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    layoutCount++;
  }

  @override
  void dispose() {
    notificationHandler = null;
    lastProjection = null;
    attached = false;
    disposeCount++;
  }
}
