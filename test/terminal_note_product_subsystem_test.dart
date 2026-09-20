import 'dart:collection';
import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

Future<void> main() => runTerminalNoteProductSubsystemTests();

Future<void> runTerminalNoteProductSubsystemTests() async {
  await _testProductionAuthorityAndTopologyLifecycle();
  await _testStartupFailureStaysContentFree();
}

Future<void> _testProductionAuthorityAndTopologyLifecycle() async {
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  final int authorityBaseline = TerminalNoteAuthority.debugLiveAuthorityCount;
  final int workerBaseline = TerminalNoteStoreWorkerClient.debugLiveClientCount;
  final Directory temporary = await Directory.systemTemp.createTemp(
    'dart-terminal-note-product-',
  );
  final Directory root = Directory(await temporary.resolveSymbolicLinks());
  final List<_FakeProductNativeChannel> channels =
      <_FakeProductNativeChannel>[];
  final Queue<TerminalNotesAttachDisposition> initialAttachments =
      Queue<TerminalNotesAttachDisposition>();
  _FakeProductNativeChannel createChannel() {
    final _FakeProductNativeChannel channel = _FakeProductNativeChannel(
      nextAttachment: initialAttachments.isEmpty
          ? TerminalNotesAttachDisposition.attached
          : initialAttachments.removeFirst(),
    );
    channels.add(channel);
    return channel;
  }

  const TerminalNoteFeatureConfiguration configuration =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );
  try {
    final TerminalNoteSubsystemStartResult start =
        await TerminalNoteProductSubsystem.start(
          configuration: configuration,
          environment: <String, String>{'XDG_STATE_HOME': root.path},
          authorityGeneration: 101,
          restoration: null,
          initialPaneIdsInTraversalOrder: const <PaneId>[PaneId(1), PaneId(2)],
          ensureQuickTerminalContext: true,
          updatedAtUtcMicros: 1000,
          initializeNativeCapability: () {},
          surfaceFactory: createChannel,
        );
    _expect(
      start.capability == TerminalNoteApplicationCapability.available &&
          start.runtime is TerminalNoteProductSubsystem,
      'production factory starts one available authority',
    );
    final TerminalNoteProductSubsystem subsystem =
        start.runtime! as TerminalNoteProductSubsystem;
    _expect(
      subsystem.livePaneCount == 2 &&
          subsystem.liveSurfaceCount == 0 &&
          subsystem.nativeSurfaceCount == 0 &&
          channels.isEmpty &&
          TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
              productBaseline + 1 &&
          TerminalNoteAuthority.debugLiveAuthorityCount ==
              authorityBaseline + 1 &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount ==
              workerBaseline + 1,
      'store and authority are eager only after admission while native surfaces stay lazy',
    );

    final TerminalNoteProductTopologyResult quick = await subsystem.bindPane(
      paneId: const PaneId(90),
      kind: TerminalNoteContextKind.quickTerminal,
    );
    final List<TerminalNoteProductTopologyResult> standardAdds =
        await Future.wait(<Future<TerminalNoteProductTopologyResult>>[
          subsystem.bindPane(paneId: const PaneId(3)),
          subsystem.bindPane(paneId: const PaneId(4)),
        ]);
    _expect(
      quick.disposition == TerminalNoteProductTopologyDisposition.noChange &&
          standardAdds.every(
            (TerminalNoteProductTopologyResult value) =>
                value.disposition ==
                TerminalNoteProductTopologyDisposition.applied,
          ) &&
          subsystem.livePaneCount == 5,
      'Quick Terminal and concurrent standard pane binds serialize exactly',
    );

    final TerminalNoteProductTopologyResult attached = await subsystem
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 11,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    final _FakeProductNativeChannel first = channels.single;
    _expect(
      attached.disposition == TerminalNoteProductTopologyDisposition.applied &&
          attached.surfaceGeneration == 101 &&
          subsystem.surfaceGenerationForPane(const PaneId(1)) == 101 &&
          subsystem.liveSurfaceCount == 1 &&
          subsystem.nativeSurfaceCount == 1 &&
          first.operations.take(2).join(',') == 'attach,layout' &&
          first.attachments.single == (11, 11) &&
          first.projections.length == 2 &&
          first.projections.first.visibility ==
              TerminalNotesVisibility.collapsed &&
          first.projections.last.visibility ==
              TerminalNotesVisibility.expanded &&
          first.projections.last.presentationEligible &&
          first.projections.last.bodyFontMilliPoints == 15000,
      'surface attach orders native host and layout before authority projection',
    );
    final TerminalNoteProductTopologyResult duplicate = await subsystem
        .attachSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(handle: 11),
        );
    _expect(
      duplicate.disposition ==
              TerminalNoteProductTopologyDisposition.duplicate &&
          channels.length == 1,
      'duplicate surface admission creates no second native owner',
    );

    final TerminalNoteProductTopologyResult rebound = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 12,
            width: 900,
            height: 600,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    _expect(
      rebound.isAccepted &&
          first.detachCount == 1 &&
          first.attachments.last == (12, 12) &&
          first.layout == (900.0, 600.0, 2.0, 320.0),
      'renderer recovery reattaches the same surface generation to the new host',
    );
    first.nextAttachment = TerminalNotesAttachDisposition.rendererUnavailable;
    final TerminalNoteProductTopologyResult unavailable = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(handle: 13),
        );
    _expect(
      unavailable.disposition ==
              TerminalNoteProductTopologyDisposition.nativeUnavailable &&
          subsystem.liveSurfaceCount == 1 &&
          subsystem.nativeSurfaceCount == 0 &&
          first.projections.last.visibility ==
              TerminalNotesVisibility.collapsed &&
          !first.projections.last.presentationEligible,
      'failed recovery keeps one retryable adapter but hides its projection',
    );
    first.nextAttachment = TerminalNotesAttachDisposition.attached;
    final TerminalNoteProductTopologyResult retried = await subsystem
        .updateSurface(
          paneId: const PaneId(1),
          configuration: _surfaceConfiguration(
            handle: 13,
            visibility: TerminalNoteSurfaceVisibility.expanded,
            foreground: true,
            occluded: false,
          ),
        );
    _expect(
      retried.isAccepted && subsystem.nativeSurfaceCount == 1,
      'a later topology epoch can reattach the retained native surface',
    );

    subsystem.applyLiveConfiguration(
      const TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 24,
      ),
    );
    _expect(
      first.projections.last.bodyFontMilliPoints == 24000 &&
          first.layoutCount == 3,
      'live Note font reprojects cards without terminal layout ownership',
    );
    var rejectedLaunchFixedChange = false;
    try {
      subsystem.applyLiveConfiguration(
        const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: true,
          notesNextPrompt: false,
          fontSize: 23,
        ),
      );
    } on ArgumentError {
      rejectedLaunchFixedChange = true;
    }
    _expect(
      rejectedLaunchFixedChange &&
          first.projections.last.bodyFontMilliPoints == 24000,
      'direct injection cannot mutate launch-fixed Note flags',
    );

    initialAttachments.add(TerminalNotesAttachDisposition.rendererUnavailable);
    final TerminalNoteProductTopologyResult failedSurface = await subsystem
        .attachSurface(
          paneId: const PaneId(2),
          configuration: _surfaceConfiguration(handle: 21),
        );
    final _FakeProductNativeChannel failed = channels.last;
    _expect(
      failedSurface.disposition ==
              TerminalNoteProductTopologyDisposition.nativeUnavailable &&
          subsystem.liveSurfaceCount == 1 &&
          failed.disposeCount == 1 &&
          failed.detachCount == 1,
      'failed first attach releases native ownership without touching authority topology',
    );

    final TerminalNoteProductTopologyResult detached = await subsystem
        .detachSurface(const PaneId(1));
    final TerminalNoteProductTopologyResult invalidClose = await subsystem
        .closePane(paneId: const PaneId(4), updatedAtUtcMicros: -1);
    final TerminalNoteProductTopologyResult closedStandard = await subsystem
        .closePane(paneId: const PaneId(3), updatedAtUtcMicros: 2000);
    final TerminalNoteProductTopologyResult closedQuick = await subsystem
        .closePane(paneId: const PaneId(90), updatedAtUtcMicros: 2001);
    _expect(
      detached.isAccepted &&
          invalidClose.disposition ==
              TerminalNoteProductTopologyDisposition.rejected &&
          subsystem.hasPane(const PaneId(4)) &&
          closedStandard.isAccepted &&
          closedQuick.disposition ==
              TerminalNoteProductTopologyDisposition.noChange &&
          first.disposeCount == 1 &&
          subsystem.liveSurfaceCount == 0 &&
          subsystem.livePaneCount == 3,
      'detach precedes standard and Quick Terminal pane retirement',
    );

    final Future<void> firstShutdown = subsystem.shutdown();
    final Future<void> secondShutdown = subsystem.shutdown();
    _expect(
      identical(firstShutdown, secondShutdown),
      'product subsystem shutdown is single-flight',
    );
    await firstShutdown;
    _expect(
      subsystem.isStopped &&
          subsystem.livePaneCount == 0 &&
          subsystem.liveSurfaceCount == 0 &&
          TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
              productBaseline &&
          TerminalNoteAuthority.debugLiveAuthorityCount == authorityBaseline &&
          TerminalNoteStoreWorkerClient.debugLiveClientCount == workerBaseline,
      'shutdown returns product, authority, worker, pane, and surface owners to baseline',
    );
  } finally {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  }
}

Future<void> _testStartupFailureStaysContentFree() async {
  final int productBaseline =
      TerminalNoteProductSubsystem.debugLiveProductSubsystemCount;
  var initializerCalls = 0;
  final TerminalNoteSubsystemStartResult result =
      await TerminalNoteProductSubsystem.start(
        configuration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 15,
        ),
        environment: const <String, String>{},
        authorityGeneration: 1,
        restoration: null,
        initialPaneIdsInTraversalOrder: const <PaneId>[],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 0,
        initializeNativeCapability: () => initializerCalls++,
      );
  _expect(
    result.capability == TerminalNoteApplicationCapability.unavailable &&
        result.runtime == null &&
        initializerCalls == 1 &&
        TerminalNoteProductSubsystem.debugLiveProductSubsystemCount ==
            productBaseline,
    'invalid store environment exposes one fixed failure and no product owner',
  );

  final TerminalNoteSubsystemStartResult invalidConfiguration =
      await TerminalNoteProductSubsystem.start(
        configuration: const TerminalNoteFeatureConfiguration(
          notes: true,
          notesOnReturn: false,
          notesNextPrompt: false,
          fontSize: 25,
        ),
        environment: const <String, String>{'XDG_STATE_HOME': '/unused'},
        authorityGeneration: 1,
        restoration: null,
        initialPaneIdsInTraversalOrder: const <PaneId>[],
        ensureQuickTerminalContext: true,
        updatedAtUtcMicros: 0,
        initializeNativeCapability: () => initializerCalls++,
      );
  _expect(
    invalidConfiguration.capability ==
            TerminalNoteApplicationCapability.unavailable &&
        invalidConfiguration.runtime == null &&
        initializerCalls == 1,
    'out-of-schema launch input fails before native or store ownership',
  );
}

TerminalNoteProductSurfaceConfiguration _surfaceConfiguration({
  required int handle,
  double width = 800,
  double height = 500,
  TerminalNoteSurfaceVisibility visibility =
      TerminalNoteSurfaceVisibility.collapsed,
  bool foreground = false,
  bool occluded = true,
}) => TerminalNoteProductSurfaceConfiguration(
  rendererIdentity: TerminalMetalRendererCompositionIdentity(
    handle: handle,
    generation: handle,
  ),
  paneWidth: width,
  paneHeight: height,
  backingScale: 2,
  requestedRailWidth: 320,
  visibility: visibility,
  foreground: foreground,
  occluded: occluded,
);

final class _FakeProductNativeChannel
    implements TerminalNoteNativeSurfaceChannel {
  _FakeProductNativeChannel({required this.nextAttachment});

  final List<String> operations = <String>[];
  final List<(int, int)> attachments = <(int, int)>[];
  final List<TerminalNotesProjection> projections = <TerminalNotesProjection>[];
  TerminalNotesAttachDisposition nextAttachment;
  (double, double, double, double)? layout;
  int layoutCount = 0;
  int detachCount = 0;
  int disposeCount = 0;

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    operations.add('projection');
    projections.add(projection);
    return TerminalNotesApplyDisposition.accepted;
  }

  @override
  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) {
    operations.add('attach');
    attachments.add((rendererHandle, rendererGeneration));
    final TerminalNotesAttachDisposition result = nextAttachment;
    nextAttachment = TerminalNotesAttachDisposition.attached;
    return result;
  }

  @override
  void detachFromHost() {
    operations.add('detach');
    detachCount++;
  }

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    operations.add('layout');
    layout = (paneWidth, paneHeight, backingScale, requestedRailWidth);
    layoutCount++;
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
  void dispose() {
    operations.add('dispose');
    disposeCount++;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
