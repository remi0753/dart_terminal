import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'terminal_application_state.dart';
import 'terminal_core/terminal_keyboard_modes.dart';
import 'terminal_input/terminal_hyperlink_interaction.dart';
import 'terminal_input/terminal_paste.dart';
import 'terminal_note_application_coordinator.dart';
import 'terminal_note_authority.dart';
import 'terminal_note_composition.dart';
import 'terminal_note_context_restoration.dart';
import 'terminal_note_model.dart';
import 'terminal_note_native_adapter.dart';
import 'terminal_note_product_subsystem.dart';
import 'terminal_note_projection.dart';
import 'terminal_note_store_isolate.dart';
import 'terminal_note_store_process.dart';
import 'terminal_note_store_worker.dart';
import 'terminal_pane.dart';
import 'terminal_pane_close_coordinator.dart';
import 'terminal_product_configuration.dart';
import 'terminal_restoration.dart';
import 'terminal_restoration_lifecycle.dart';
import 'terminal_window_interaction.dart';

typedef TerminalNoteS1SentinelProbe = TerminalNoteS1SentinelSnapshot Function();

/// Content-free product state which Notes must not mutate.
final class TerminalNoteS1SentinelSnapshot {
  TerminalNoteS1SentinelSnapshot({
    required this.terminalOutputBytes,
    required this.terminalRows,
    required this.terminalColumns,
    required this.shellIntegrationEvents,
    required this.restorationPayloadEntries,
    required this.diagnosticContentFields,
  }) {
    if (terminalOutputBytes < 0 ||
        terminalRows <= 0 ||
        terminalColumns <= 0 ||
        shellIntegrationEvents < 0 ||
        restorationPayloadEntries < 0 ||
        diagnosticContentFields < 0) {
      throw ArgumentError('Note S1 sentinel snapshot is invalid');
    }
  }

  final int terminalOutputBytes;
  final int terminalRows;
  final int terminalColumns;
  final int shellIntegrationEvents;
  final int restorationPayloadEntries;
  final int diagnosticContentFields;

  bool hasSameProtectedState(TerminalNoteS1SentinelSnapshot other) =>
      terminalOutputBytes == other.terminalOutputBytes &&
      terminalRows == other.terminalRows &&
      terminalColumns == other.terminalColumns &&
      shellIntegrationEvents == other.shellIntegrationEvents &&
      restorationPayloadEntries == other.restorationPayloadEntries &&
      diagnosticContentFields == other.diagnosticContentFields;
}

typedef TerminalNoteS2SentinelProbe = TerminalNoteS2SentinelSnapshot Function();

/// Content-free terminal/TUI state which On Return presentation must preserve.
final class TerminalNoteS2SentinelSnapshot {
  TerminalNoteS2SentinelSnapshot({
    required this.terminalOutputBytes,
    required this.terminalRows,
    required this.terminalColumns,
    required this.shellIntegrationEvents,
    required this.restorationPayloadEntries,
    required this.diagnosticContentFields,
    required this.terminalInputDeliveries,
    required this.ptyWriteEnqueuedCount,
    required this.focusReportCount,
    required this.usingAlternateScreen,
    required this.applicationCursorKeys,
    required this.bracketedPasteMode,
    required this.focusReportingMode,
    required this.mouseTrackingEnabled,
    required this.mouseSgrEncoding,
  }) {
    if (terminalOutputBytes < 0 ||
        terminalRows <= 0 ||
        terminalColumns <= 0 ||
        shellIntegrationEvents < 0 ||
        restorationPayloadEntries < 0 ||
        diagnosticContentFields < 0 ||
        terminalInputDeliveries < 0 ||
        ptyWriteEnqueuedCount < 0 ||
        focusReportCount < 0) {
      throw ArgumentError('Note S2 sentinel snapshot is invalid');
    }
  }

  final int terminalOutputBytes;
  final int terminalRows;
  final int terminalColumns;
  final int shellIntegrationEvents;
  final int restorationPayloadEntries;
  final int diagnosticContentFields;
  final int terminalInputDeliveries;
  final int ptyWriteEnqueuedCount;
  final int focusReportCount;
  final bool usingAlternateScreen;
  final bool applicationCursorKeys;
  final bool bracketedPasteMode;
  final bool focusReportingMode;
  final bool mouseTrackingEnabled;
  final bool mouseSgrEncoding;

  bool get hasTuiModeSignature =>
      usingAlternateScreen &&
      applicationCursorKeys &&
      bracketedPasteMode &&
      focusReportingMode &&
      mouseTrackingEnabled &&
      mouseSgrEncoding;

  bool hasSameProtectedState(TerminalNoteS2SentinelSnapshot other) =>
      terminalOutputBytes == other.terminalOutputBytes &&
      terminalRows == other.terminalRows &&
      terminalColumns == other.terminalColumns &&
      shellIntegrationEvents == other.shellIntegrationEvents &&
      restorationPayloadEntries == other.restorationPayloadEntries &&
      diagnosticContentFields == other.diagnosticContentFields &&
      terminalInputDeliveries == other.terminalInputDeliveries &&
      ptyWriteEnqueuedCount == other.ptyWriteEnqueuedCount &&
      focusReportCount == other.focusReportCount &&
      usingAlternateScreen == other.usingAlternateScreen &&
      applicationCursorKeys == other.applicationCursorKeys &&
      bracketedPasteMode == other.bracketedPasteMode &&
      focusReportingMode == other.focusReportingMode &&
      mouseTrackingEnabled == other.mouseTrackingEnabled &&
      mouseSgrEncoding == other.mouseSgrEncoding;
}

/// Fixed, content-free evidence emitted by the reusable S1 product vector.
final class TerminalNoteS1ProductAcceptanceResult {
  const TerminalNoteS1ProductAcceptanceResult({
    required this.standardWindowCount,
    required this.standardTabCount,
    required this.standardPaneCount,
    required this.quickTerminalCount,
    required this.durableFlowCount,
    required this.dirtyPaneCloseBlocked,
    required this.dirtyWindowCloseBlocked,
    required this.dirtyQuitBlocked,
    required this.storeFaultReduced,
    required this.nativeFaultCount,
    required this.exactRestart,
    required this.defaultOffZeroCost,
    required this.protectedStateUnchanged,
    required this.ownerLeakCount,
  });

  final int standardWindowCount;
  final int standardTabCount;
  final int standardPaneCount;
  final int quickTerminalCount;
  final int durableFlowCount;
  final bool dirtyPaneCloseBlocked;
  final bool dirtyWindowCloseBlocked;
  final bool dirtyQuitBlocked;
  final bool storeFaultReduced;
  final int nativeFaultCount;
  final bool exactRestart;
  final bool defaultOffZeroCost;
  final bool protectedStateUnchanged;
  final int ownerLeakCount;

  bool get isSuccess =>
      standardWindowCount == 2 &&
      standardTabCount == 3 &&
      standardPaneCount == 5 &&
      quickTerminalCount == 1 &&
      durableFlowCount >= 12 &&
      dirtyPaneCloseBlocked &&
      dirtyWindowCloseBlocked &&
      dirtyQuitBlocked &&
      storeFaultReduced &&
      nativeFaultCount == 2 &&
      exactRestart &&
      defaultOffZeroCost &&
      protectedStateUnchanged &&
      ownerLeakCount == 0;

  String machineLine() =>
      'TERMINAL_NOTE_S1_PRODUCT_PASS '
      'windows=$standardWindowCount tabs=$standardTabCount '
      'panes=$standardPaneCount quick=$quickTerminalCount '
      'durable_flows=$durableFlowCount '
      'dirty_pane=${dirtyPaneCloseBlocked ? 1 : 0} '
      'dirty_window=${dirtyWindowCloseBlocked ? 1 : 0} '
      'dirty_quit=${dirtyQuitBlocked ? 1 : 0} '
      'store_fault=${storeFaultReduced ? 1 : 0} '
      'native_faults=$nativeFaultCount restart=${exactRestart ? 1 : 0} '
      'default_off=${defaultOffZeroCost ? 1 : 0} '
      'protected_state=${protectedStateUnchanged ? 1 : 0} '
      'owners=$ownerLeakCount';
}

/// Fixed, content-free evidence emitted by the reusable S2 product vector.
final class TerminalNoteS2ProductAcceptanceResult {
  const TerminalNoteS2ProductAcceptanceResult({
    required this.reviewVectorCount,
    required this.standardWindowCount,
    required this.standardTabCount,
    required this.standardPaneCount,
    required this.quickTerminalCount,
    required this.focusEdgeCount,
    required this.fifoAcknowledgementCount,
    required this.falseConsumeCount,
    required this.exactRestart,
    required this.detachedPassive,
    required this.disabledZeroEntry,
    required this.tuiModeSignature,
    required this.protectedStateUnchanged,
    required this.ownerLeakCount,
  });

  final int reviewVectorCount;
  final int standardWindowCount;
  final int standardTabCount;
  final int standardPaneCount;
  final int quickTerminalCount;
  final int focusEdgeCount;
  final int fifoAcknowledgementCount;
  final int falseConsumeCount;
  final bool exactRestart;
  final bool detachedPassive;
  final bool disabledZeroEntry;
  final bool tuiModeSignature;
  final bool protectedStateUnchanged;
  final int ownerLeakCount;

  bool get isSuccess =>
      reviewVectorCount == 4 &&
      standardWindowCount == 2 &&
      standardTabCount == 3 &&
      standardPaneCount == 5 &&
      quickTerminalCount == 1 &&
      focusEdgeCount == 64 &&
      fifoAcknowledgementCount == 2 &&
      falseConsumeCount == 0 &&
      exactRestart &&
      detachedPassive &&
      disabledZeroEntry &&
      tuiModeSignature &&
      protectedStateUnchanged &&
      ownerLeakCount == 0;

  String machineLine() =>
      'TERMINAL_NOTE_S2_PRODUCT_PASS '
      'vectors=$reviewVectorCount windows=$standardWindowCount '
      'tabs=$standardTabCount panes=$standardPaneCount '
      'quick=$quickTerminalCount focus_edges=$focusEdgeCount '
      'fifo_acks=$fifoAcknowledgementCount '
      'false_consumes=$falseConsumeCount '
      'restart=${exactRestart ? 1 : 0} '
      'detached=${detachedPassive ? 1 : 0} '
      'disabled=${disabledZeroEntry ? 1 : 0} '
      'tui_modes=${tuiModeSignature ? 1 : 0} '
      'protected_state=${protectedStateUnchanged ? 1 : 0} '
      'owners=$ownerLeakCount';
}

/// Runs the deterministic S1 product vector used by focused and runtime gates.
///
/// The vector owns a real Note worker/filesystem and the real product
/// composition/authority. Its native channel is injected at the existing
/// semantic boundary so automation never depends on control coordinates.
abstract final class TerminalNoteS1ProductAcceptance {
  static const TerminalNoteFeatureConfiguration _enabled =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );
  static const TerminalNoteFeatureConfiguration _disabled =
      TerminalNoteFeatureConfiguration(
        notes: false,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );

  static Future<TerminalNoteS1ProductAcceptanceResult> run({
    required Directory rootDirectory,
    required TerminalNoteS1SentinelProbe sentinelProbe,
    TerminalNoteAuthorityStoreFactory? storeFactory,
    TerminalNoteContextIdGenerator? contextIdGenerator,
    TerminalNoteIdGenerator? noteIdGenerator,
  }) async {
    final Directory root = Directory(
      await rootDirectory.resolveSymbolicLinks(),
    );
    final TerminalNoteS1SentinelSnapshot before = sentinelProbe();
    final _NoteOwnerCounts ownerBaseline = _NoteOwnerCounts.capture();
    final TerminalNoteContextIdGenerator selectedContextIdGenerator =
        contextIdGenerator ?? TerminalNoteContextIdGenerator.secure();
    final TerminalNoteIdGenerator selectedNoteIdGenerator =
        noteIdGenerator ?? TerminalNoteIdGenerator.secure();
    selectedContextIdGenerator.next();
    selectedNoteIdGenerator.next();
    final Map<String, String> environment = <String, String>{
      'XDG_STATE_HOME': '${root.path}/state',
    };
    final TerminalRestorationPersistence restorationPersistence =
        TerminalRestorationPersistence(
          FileTerminalRestorationStore('${root.path}/restoration.json'),
        );
    final File exportFile = File('${root.path}/explicit-export.json');
    var timestamp = 10000;
    var durableFlowCount = 0;
    var copiedBodyCount = 0;
    var disabledLocationResolutions = 0;
    var nativeFaultCount = 0;
    var dirtyPaneCloseBlocked = false;
    var dirtyWindowCloseBlocked = false;
    var dirtyQuitBlocked = false;
    var storeFaultReduced = false;
    var exactRestart = false;
    TerminalNoteApplicationCoordinator? coordinator;
    TerminalWindowInteractionAuthority? interactionAuthority;
    TerminalWindowInteractionRouter? interactionRouter;
    _AcceptanceTopology? topology;
    TerminalNoteApplicationCoordinator? reopenedCoordinator;
    TerminalWindowInteractionAuthority? reopenedInteractionAuthority;
    TerminalWindowInteractionRouter? reopenedInteractionRouter;
    _AcceptanceTopology? reopenedTopology;
    try {
      final _AcceptanceTopology disabledTopology = await _createTopology();
      final TerminalNoteApplicationCoordinator disabled =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _disabled,
            environment: const <String, String>{},
            authorityGeneration: 1,
            restoration: null,
            initialBindings: disabledTopology.standardBindings,
            ensureQuickTerminalContext: true,
            copyEffect: (_) => false,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () => throw StateError('unexpected'),
            surfaceFactory: () => throw StateError('unexpected'),
            locationResolver: (_) {
              disabledLocationResolutions++;
              throw StateError('unexpected');
            },
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
          );
      final bool defaultOffZeroCost =
          disabled.capability == TerminalNoteApplicationCapability.disabled &&
          !disabled.ownsRuntime &&
          disabled.liveBindingCount == 0 &&
          disabled.liveSurfaceCount == 0 &&
          disabledLocationResolutions == 0 &&
          _NoteOwnerCounts.capture() == ownerBaseline;
      await disabled.shutdown();
      await disabledTopology.state.shutdown();
      _require(
        defaultOffZeroCost,
        'default-off Notes allocated product owners',
      );

      topology = await _createTopology();
      final Queue<TerminalNotesAttachDisposition> attachments =
          Queue<TerminalNotesAttachDisposition>()
            ..add(TerminalNotesAttachDisposition.attached)
            ..add(TerminalNotesAttachDisposition.rendererUnavailable)
            ..add(TerminalNotesAttachDisposition.attached);
      final List<_NoteAcceptanceNativeChannel> channels =
          <_NoteAcceptanceNativeChannel>[];
      _NoteAcceptanceNativeChannel createChannel() {
        final _NoteAcceptanceNativeChannel channel =
            _NoteAcceptanceNativeChannel(
              attachment: attachments.isEmpty
                  ? TerminalNotesAttachDisposition.attached
                  : attachments.removeFirst(),
            );
        channels.add(channel);
        return channel;
      }

      coordinator = await TerminalNoteApplicationCoordinator.startProduction(
        launchConfiguration: _enabled,
        environment: environment,
        authorityGeneration: 101,
        restoration: null,
        initialBindings: topology.standardBindings,
        ensureQuickTerminalContext: true,
        copyEffect: (String body) {
          copiedBodyCount++;
          return body.isNotEmpty;
        },
        exportDestinationChooser: (_) =>
            TerminalNoteApprovedExportPath.fromAbsolutePath(exportFile.path),
        initializeNativeCapability: () {},
        surfaceFactory: createChannel,
        storeFactory: storeFactory,
        contextIdGenerator: selectedContextIdGenerator,
        noteIdGenerator: selectedNoteIdGenerator,
        clock: () => timestamp++,
      );
      await coordinator.synchronizeTopology(topology.allBindings);
      _require(
        topology.standardWindowCount == 2 &&
            topology.standardTabCount == 3 &&
            topology.standardPaneIds.length == 5 &&
            topology.quickPaneId != null &&
            coordinator.liveBindingCount == 6,
        'S1 product topology mismatch: '
        'windows=${topology.standardWindowCount} '
        'tabs=${topology.standardTabCount} '
        'panes=${topology.standardPaneIds.length} '
        'quick=${topology.quickPaneId == null ? 0 : 1} '
        'bindings=${coordinator.liveBindingCount} '
        'capability=${coordinator.capability.name} '
        'store_failure=${storeFactory is TerminalNoteProcessStoreFactory ? storeFactory.debugLastStartupFailure?.name ?? 'none' : 'in-process'}',
      );

      interactionAuthority = TerminalWindowInteractionAuthority(topology.state);
      interactionRouter = TerminalWindowInteractionRouter(interactionAuthority);
      final PaneId primaryPane = topology.standardPaneIds.first;
      final TerminalPaneLocation primaryLocation = topology.state
          .locationForPane(primaryPane)!;
      topology.state.focusPane(primaryLocation.tabId, primaryPane);
      interactionAuthority.synchronize();
      final TerminalWindowId primaryWindow = topology.state
          .locationForPane(primaryPane)!
          .windowId;
      final TerminalNoteProductTopologyResult attached = await coordinator
          .synchronizeSurface(
            paneId: primaryPane,
            windowId: primaryWindow,
            configuration: _surfaceConfiguration(11),
            interactionAuthority: interactionAuthority,
            interactionRouter: interactionRouter,
            focusTerminal: () => true,
          );
      _require(
        attached.isAccepted,
        'primary Note surface was not attached: '
        '${attached.disposition.name}/${coordinator.capability.name}',
      );
      final _NoteAcceptanceNativeChannel primary = channels.first;

      final TerminalNoteProductTopologyResult began = await coordinator
          .performAction(
            primaryPane,
            TerminalNoteApplicationActionKind.newNote,
          );
      _require(began.isAccepted, 'New Note application action was rejected');
      primary.editorDirty = true;
      primary.notify();
      await _drainEvents();
      final TerminalPaneCloseCoordinator close = TerminalPaneCloseCoordinator(
        state: topology.state,
        canRemovePane: (PaneId paneId) {
          final TerminalPaneLocation? location = topology!.state
              .locationForPane(paneId);
          return location != null &&
              interactionAuthority!.permitsHierarchyMutation(location.windowId);
        },
        canRemoveWindow: interactionAuthority.permitsHierarchyMutation,
        canBeginApplicationQuit: () => topology!.state.windows.every(
          (TerminalWindowState window) =>
              interactionAuthority!.permitsHierarchyMutation(window.id),
        ),
      );
      dirtyPaneCloseBlocked =
          (await close.requestClose(paneId: primaryPane)).disposition ==
          TerminalPaneCloseDisposition.busy;
      dirtyWindowCloseBlocked =
          (await close.requestWindowClose(primaryWindow)).disposition ==
          TerminalWindowCloseDisposition.busy;
      dirtyQuitBlocked = !close.beginApplicationQuit();
      _require(
        dirtyPaneCloseBlocked && dirtyWindowCloseBlocked && dirtyQuitBlocked,
        'dirty Note editor did not block pane/window/quit',
      );

      primary.editorDirty = false;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.yellow,
        body: 's1-vector-primary',
      );
      durableFlowCount++;
      await coordinator.performAction(
        primaryPane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.green,
        body: 's1-vector-secondary',
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.moveEarlier,
        cardToken: primary.projection.selectedToken,
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.moveLater,
        cardToken: primary.projection.selectedToken,
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.changeColor,
        cardToken: primary.projection.selectedToken,
        color: TerminalNotesColor.blue,
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.resolve,
        cardToken: primary.projection.selectedToken,
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.reopen,
        cardToken: primary.projection.selectedToken,
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.beginEdit,
        cardToken: primary.projection.selectedToken,
      );
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.save,
        cardToken: primary.projection.selectedToken,
        color: TerminalNotesColor.pink,
        body: 's1-vector-secondary-edited',
      );
      durableFlowCount++;
      await coordinator.performAction(
        primaryPane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.neutral,
        body: 's1-vector-delete-candidate',
      );
      durableFlowCount++;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.delete,
        cardToken: primary.projection.selectedToken,
      );
      durableFlowCount++;
      final TerminalNotesCard selected = primary.projection.cards.first;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.copy,
        cardToken: selected.token,
        body: selected.body,
      );
      await _sendIntent(primary, kind: TerminalNotesIntentKind.export);
      _require(
        copiedBodyCount == 1 && await exportFile.exists(),
        'explicit copy/export effects were not completed',
      );

      final PaneId faultPane = topology.standardPaneIds[1];
      final TerminalPaneLocation faultLocation = topology.state.locationForPane(
        faultPane,
      )!;
      final TerminalNoteProductTopologyResult nativeAttachFault =
          await coordinator.synchronizeSurface(
            paneId: faultPane,
            windowId: faultLocation.windowId,
            configuration: _surfaceConfiguration(12),
            interactionAuthority: interactionAuthority,
            interactionRouter: interactionRouter,
            focusTerminal: () => true,
          );
      if (nativeAttachFault.disposition ==
          TerminalNoteProductTopologyDisposition.nativeUnavailable) {
        nativeFaultCount++;
      }

      final PaneId detachedSourcePane = topology.standardPaneIds[2];
      final TerminalPaneLocation sourceLocation = topology.state
          .locationForPane(detachedSourcePane)!;
      topology.state.focusPane(sourceLocation.tabId, detachedSourcePane);
      interactionAuthority.synchronize();
      final TerminalNoteProductTopologyResult sourceAttached = await coordinator
          .synchronizeSurface(
            paneId: detachedSourcePane,
            windowId: sourceLocation.windowId,
            configuration: _surfaceConfiguration(13),
            interactionAuthority: interactionAuthority,
            interactionRouter: interactionRouter,
            focusTerminal: () => true,
          );
      _require(
        sourceAttached.isAccepted,
        'Detached source surface unavailable',
      );
      final _NoteAcceptanceNativeChannel source = channels.last;
      await coordinator.performAction(
        detachedSourcePane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        source,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.neutral,
        body: 's1-vector-detached',
      );
      durableFlowCount++;
      final List<TerminalNoteApplicationPaneBinding> withoutSource = topology
          .allBindings
          .where(
            (TerminalNoteApplicationPaneBinding binding) =>
                binding.paneId != detachedSourcePane,
          )
          .toList(growable: false);
      await coordinator.synchronizeTopology(withoutSource);
      topology.state.focusPane(primaryLocation.tabId, primaryPane);
      interactionAuthority.synchronize();
      await _sendIntent(primary, kind: TerminalNotesIntentKind.showDetached);
      final int detachedToken = primary.projection.cards.single.token;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.reattach,
        cardToken: detachedToken,
      );
      durableFlowCount++;
      await _sendIntent(primary, kind: TerminalNotesIntentKind.showCurrent);
      await coordinator.synchronizeTopology(topology.allBindings);

      final _AcceptanceTopology storeFaultTopology = await _createTopology(
        standardWindowCount: 1,
        initialPaneId: 200,
      );
      final TerminalNoteApplicationCoordinator storeFault =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _enabled,
            environment: environment,
            authorityGeneration: 102,
            restoration: null,
            initialBindings: storeFaultTopology.standardBindings,
            ensureQuickTerminalContext: false,
            copyEffect: (_) => false,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () {},
            surfaceFactory: () => _NoteAcceptanceNativeChannel(
              attachment: TerminalNotesAttachDisposition.attached,
            ),
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
            clock: () => timestamp++,
          );
      storeFaultReduced =
          storeFault.capability ==
              TerminalNoteApplicationCapability.inUseByOtherProcess &&
          !storeFault.ownsRuntime;
      await storeFault.shutdown();
      await storeFaultTopology.state.shutdown();
      _require(storeFaultReduced, 'store lock fault was not reduced safely');

      primary.nextResultApply = TerminalNotesResultApplyDisposition.failed;
      await _sendIntent(primary, kind: TerminalNotesIntentKind.showDetached);
      await _drainEvents();
      if (primary.disposeCount == 1 && coordinator.liveSurfaceCount == 0) {
        nativeFaultCount++;
      }
      _require(nativeFaultCount == 2, 'native fault ownership did not retire');

      final TerminalNoteRestorationCaptureArtifact capture =
          TerminalNoteRestorationCaptureArtifact.capture(
            topology.state,
            placementForWindow: _placementForWindow,
            workingDirectoryForPane: (_) => null,
          );
      Future<bool> commitRestoration(
        TerminalNoteRestorationArtifact artifact,
      ) async =>
          (await restorationPersistence.saveExactEncoded(artifact.exactEncoded))
              .disposition ==
          TerminalRestorationSaveDisposition.saved;
      final TerminalNoteApplicationShutdownResult firstShutdown =
          await coordinator.shutdownApplication(
            capture: capture,
            updatedAtUtcMicros: timestamp++,
            commitRestoration: commitRestoration,
          );
      _require(firstShutdown.isSuccess, 'first ordered shutdown failed');
      coordinator = null;
      interactionRouter.dispose();
      interactionRouter = null;
      interactionAuthority.dispose();
      interactionAuthority = null;
      await topology.state.shutdown();
      topology = null;

      final TerminalRestorationLoadResult loaded = await restorationPersistence
          .load();
      _require(
        loaded.disposition == TerminalRestorationLoadDisposition.restored &&
            loaded.exactEncoded == capture.restoration.exactEncoded,
        'exact restoration bytes were not persisted',
      );
      reopenedTopology = await _createTopology(initialPaneId: 400);
      final List<_NoteAcceptanceNativeChannel> reopenedChannels =
          <_NoteAcceptanceNativeChannel>[];
      reopenedCoordinator =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _enabled,
            environment: environment,
            authorityGeneration: 103,
            restoration: TerminalNoteRestorationArtifact.fromExactEncoded(
              loaded.exactEncoded!,
            ),
            initialBindings: reopenedTopology.standardBindings,
            ensureQuickTerminalContext: true,
            copyEffect: (_) => true,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () {},
            surfaceFactory: () {
              final _NoteAcceptanceNativeChannel channel =
                  _NoteAcceptanceNativeChannel(
                    attachment: TerminalNotesAttachDisposition.attached,
                  );
              reopenedChannels.add(channel);
              return channel;
            },
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
            clock: () => timestamp++,
          );
      await reopenedCoordinator.synchronizeTopology(
        reopenedTopology.allBindings,
      );
      reopenedInteractionAuthority = TerminalWindowInteractionAuthority(
        reopenedTopology.state,
      );
      reopenedInteractionRouter = TerminalWindowInteractionRouter(
        reopenedInteractionAuthority,
      );
      final PaneId reopenedPrimary = reopenedTopology.standardPaneIds.first;
      final TerminalPaneLocation reopenedPrimaryLocation = reopenedTopology
          .state
          .locationForPane(reopenedPrimary)!;
      reopenedTopology.state.focusPane(
        reopenedPrimaryLocation.tabId,
        reopenedPrimary,
      );
      reopenedInteractionAuthority.synchronize();
      final TerminalWindowId reopenedWindow = reopenedTopology.state
          .locationForPane(reopenedPrimary)!
          .windowId;
      await reopenedCoordinator.synchronizeSurface(
        paneId: reopenedPrimary,
        windowId: reopenedWindow,
        configuration: _surfaceConfiguration(21),
        interactionAuthority: reopenedInteractionAuthority,
        interactionRouter: reopenedInteractionRouter,
        focusTerminal: () => true,
      );
      exactRestart =
          reopenedChannels.single.projection.cards.length == 3 &&
          reopenedCoordinator.liveBindingCount == 6;
      _require(exactRestart, 'restart did not restore the exact Note context');
      final TerminalNoteRestorationCaptureArtifact reopenedCapture =
          TerminalNoteRestorationCaptureArtifact.capture(
            reopenedTopology.state,
            placementForWindow: _placementForWindow,
            workingDirectoryForPane: (_) => null,
          );
      final TerminalNoteApplicationShutdownResult reopenedShutdown =
          await reopenedCoordinator.shutdownApplication(
            capture: reopenedCapture,
            updatedAtUtcMicros: timestamp++,
            commitRestoration: commitRestoration,
          );
      _require(reopenedShutdown.isSuccess, 'reopened ordered shutdown failed');
      reopenedCoordinator = null;
      reopenedInteractionRouter.dispose();
      reopenedInteractionRouter = null;
      reopenedInteractionAuthority.dispose();
      reopenedInteractionAuthority = null;
      await reopenedTopology.state.shutdown();
      reopenedTopology = null;

      final TerminalNoteS1SentinelSnapshot after = sentinelProbe();
      final int ownerLeakCount = _NoteOwnerCounts.capture().delta(
        ownerBaseline,
      );
      final TerminalNoteS1ProductAcceptanceResult result =
          TerminalNoteS1ProductAcceptanceResult(
            standardWindowCount: 2,
            standardTabCount: 3,
            standardPaneCount: 5,
            quickTerminalCount: 1,
            durableFlowCount: durableFlowCount,
            dirtyPaneCloseBlocked: dirtyPaneCloseBlocked,
            dirtyWindowCloseBlocked: dirtyWindowCloseBlocked,
            dirtyQuitBlocked: dirtyQuitBlocked,
            storeFaultReduced: storeFaultReduced,
            nativeFaultCount: nativeFaultCount,
            exactRestart: exactRestart,
            defaultOffZeroCost: defaultOffZeroCost,
            protectedStateUnchanged: before.hasSameProtectedState(after),
            ownerLeakCount: ownerLeakCount,
          );
      _require(
        result.isSuccess,
        'S1 product acceptance result is incomplete: ${result.machineLine()}',
      );
      return result;
    } finally {
      await coordinator?.shutdown();
      interactionRouter?.dispose();
      interactionAuthority?.dispose();
      if (topology != null && !topology.state.isDisposed) {
        await topology.state.shutdown();
      }
      await reopenedCoordinator?.shutdown();
      reopenedInteractionRouter?.dispose();
      reopenedInteractionAuthority?.dispose();
      if (reopenedTopology != null && !reopenedTopology.state.isDisposed) {
        await reopenedTopology.state.shutdown();
      }
    }
  }

  static TerminalWindowPlacement _placementForWindow(
    TerminalWindowId windowId,
  ) => TerminalWindowPlacement(
    windowedFrame: TerminalWindowFrame(
      left: 100 + (windowId.value * 20),
      top: 100 + (windowId.value * 20),
      width: 900,
      height: 600,
    ),
    screen: null,
    fullscreen: false,
  );
}

/// Runs the deterministic S2 product vector used by focused and runtime gates.
///
/// The host supplies a content-free snapshot of its live PTY/TUI state. The
/// vector owns the real Note worker/filesystem and product authority while its
/// native channel remains injected at the semantic projection boundary.
abstract final class TerminalNoteS2ProductAcceptance {
  static const TerminalNoteFeatureConfiguration _enabled =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: true,
        notesNextPrompt: false,
        fontSize: 15,
      );
  static const TerminalNoteFeatureConfiguration _s1Only =
      TerminalNoteFeatureConfiguration(
        notes: true,
        notesOnReturn: false,
        notesNextPrompt: false,
        fontSize: 15,
      );

  static Future<TerminalNoteS2ProductAcceptanceResult> run({
    required Directory rootDirectory,
    required TerminalNoteS2SentinelProbe sentinelProbe,
    TerminalNoteAuthorityStoreFactory? storeFactory,
    TerminalNoteContextIdGenerator? contextIdGenerator,
    TerminalNoteIdGenerator? noteIdGenerator,
  }) async {
    final Directory root = Directory(
      await rootDirectory.resolveSymbolicLinks(),
    );
    final TerminalNoteS2SentinelSnapshot before = sentinelProbe();
    _require(
      before.hasTuiModeSignature,
      'Note S2 runtime did not enter the required TUI mode signature',
    );
    final _NoteOwnerCounts ownerBaseline = _NoteOwnerCounts.capture();
    final TerminalNoteContextIdGenerator selectedContextIdGenerator =
        contextIdGenerator ?? TerminalNoteContextIdGenerator.secure();
    final TerminalNoteIdGenerator selectedNoteIdGenerator =
        noteIdGenerator ?? TerminalNoteIdGenerator.secure();
    final TerminalRestorationPersistence restorationPersistence =
        TerminalRestorationPersistence(
          FileTerminalRestorationStore('${root.path}/restoration.json'),
        );
    var timestamp = 20000;
    var fifoAcknowledgementCount = 0;
    var falseConsumeCount = 0;
    var detachedPassive = false;
    var disabledZeroEntry = false;
    var exactRestart = false;
    var acceptancePhase = 'startup';

    void reportAsynchronousError(Object error, StackTrace stackTrace) {
      Zone.current.handleUncaughtError(
        StateError('Note S2 $acceptancePhase failed asynchronously: $error'),
        stackTrace,
      );
    }

    TerminalNoteApplicationCoordinator? disabledCoordinator;
    TerminalWindowInteractionAuthority? disabledInteractionAuthority;
    TerminalWindowInteractionRouter? disabledInteractionRouter;
    _AcceptanceTopology? disabledTopology;
    TerminalNoteApplicationCoordinator? detachedCoordinator;
    TerminalWindowInteractionAuthority? detachedInteractionAuthority;
    TerminalWindowInteractionRouter? detachedInteractionRouter;
    _AcceptanceTopology? detachedTopology;
    TerminalNoteApplicationCoordinator? coordinator;
    TerminalWindowInteractionAuthority? interactionAuthority;
    TerminalWindowInteractionRouter? interactionRouter;
    _AcceptanceTopology? topology;
    TerminalNoteApplicationCoordinator? reopenedCoordinator;
    TerminalWindowInteractionAuthority? reopenedInteractionAuthority;
    TerminalWindowInteractionRouter? reopenedInteractionRouter;
    _AcceptanceTopology? reopenedTopology;
    try {
      // `notes-on-return=false` retains S1 but has no S2 entry or mutation.
      acceptancePhase = 'disabled-path';
      disabledTopology = await _createTopology(
        standardWindowCount: 1,
        initialPaneId: 700,
      );
      final _NoteAcceptanceNativeChannel disabledChannel =
          _NoteAcceptanceNativeChannel(
            attachment: TerminalNotesAttachDisposition.attached,
          );
      disabledCoordinator =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _s1Only,
            environment: <String, String>{
              'XDG_STATE_HOME': '${root.path}/disabled-state',
            },
            authorityGeneration: 201,
            restoration: null,
            initialBindings: disabledTopology.standardBindings,
            ensureQuickTerminalContext: false,
            copyEffect: (_) => false,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () {},
            surfaceFactory: () => disabledChannel,
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
            clock: () => timestamp++,
            onError: reportAsynchronousError,
          );
      disabledInteractionAuthority = TerminalWindowInteractionAuthority(
        disabledTopology.state,
      );
      disabledInteractionRouter = TerminalWindowInteractionRouter(
        disabledInteractionAuthority,
      );
      final PaneId disabledPane = disabledTopology.standardPaneIds.single;
      final TerminalPaneLocation disabledLocation = disabledTopology.state
          .locationForPane(disabledPane)!;
      disabledTopology.state.focusPane(disabledLocation.tabId, disabledPane);
      disabledInteractionAuthority.synchronize();
      final TerminalNoteProductTopologyResult disabledAttached =
          await disabledCoordinator.synchronizeSurface(
            paneId: disabledPane,
            windowId: disabledLocation.windowId,
            configuration: _surfaceConfiguration(701),
            interactionAuthority: disabledInteractionAuthority,
            interactionRouter: disabledInteractionRouter,
            focusTerminal: () => true,
          );
      _require(disabledAttached.isAccepted, 'S1-only surface did not attach');
      await disabledCoordinator.performAction(
        disabledPane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        disabledChannel,
        kind: TerminalNotesIntentKind.save,
        color: TerminalNotesColor.neutral,
        body: 's2-disabled-s1-note',
      );
      final TerminalNotesProjection disabledBefore = disabledChannel.projection;
      final TerminalNotesNativeResult rejectedArm = await _sendIntent(
        disabledChannel,
        kind: TerminalNotesIntentKind.armOnReturn,
        cardToken: disabledBefore.cards.single.token,
        expectedDisposition: TerminalNotesResultDisposition.rejected,
      );
      final TerminalNotesProjection disabledAfter = disabledChannel.projection;
      disabledZeroEntry =
          !disabledAfter.onReturnEnabled &&
          disabledAfter.activeCount == 1 &&
          disabledAfter.storeRevision == disabledBefore.storeRevision &&
          disabledAfter.cards.single.triggerKind == null &&
          rejectedArm.newStoreRevision == disabledBefore.storeRevision;
      _require(
        disabledZeroEntry,
        'S2-disabled configuration admitted an On Return mutation',
      );
      await disabledCoordinator.shutdown();
      disabledCoordinator = null;
      disabledInteractionRouter.dispose();
      disabledInteractionRouter = null;
      disabledInteractionAuthority.dispose();
      disabledInteractionAuthority = null;
      await disabledTopology.state.shutdown();
      disabledTopology = null;

      // F4 is isolated so its user-close topology does not weaken the exact
      // topology used by the F3 restoration vector.
      acceptancePhase = 'detached-close';
      detachedTopology = await _createTopology(initialPaneId: 800);
      final List<_NoteAcceptanceNativeChannel> detachedChannels =
          <_NoteAcceptanceNativeChannel>[];
      detachedCoordinator =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _enabled,
            environment: <String, String>{
              'XDG_STATE_HOME': '${root.path}/detached-state',
            },
            authorityGeneration: 202,
            restoration: null,
            initialBindings: detachedTopology.standardBindings,
            ensureQuickTerminalContext: false,
            copyEffect: (_) => false,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () {},
            surfaceFactory: () {
              final _NoteAcceptanceNativeChannel channel =
                  _NoteAcceptanceNativeChannel(
                    attachment: TerminalNotesAttachDisposition.attached,
                  );
              detachedChannels.add(channel);
              return channel;
            },
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
            clock: () => timestamp++,
            onError: reportAsynchronousError,
          );
      await detachedCoordinator.synchronizeTopology(
        detachedTopology.standardBindings,
      );
      detachedInteractionAuthority = TerminalWindowInteractionAuthority(
        detachedTopology.state,
      );
      detachedInteractionRouter = TerminalWindowInteractionRouter(
        detachedInteractionAuthority,
      );
      final PaneId detachedViewer = detachedTopology.standardPaneIds.first;
      final PaneId detachedSource = detachedTopology.standardPaneIds[1];
      for (final (PaneId paneId, int identity) in <(PaneId, int)>[
        (detachedViewer, 801),
        (detachedSource, 802),
      ]) {
        final TerminalPaneLocation location = detachedTopology.state
            .locationForPane(paneId)!;
        detachedTopology.state.focusPane(location.tabId, paneId);
        detachedInteractionAuthority.synchronize();
        final TerminalNoteProductTopologyResult attached =
            await detachedCoordinator.synchronizeSurface(
              paneId: paneId,
              windowId: location.windowId,
              configuration: _surfaceConfiguration(identity),
              interactionAuthority: detachedInteractionAuthority,
              interactionRouter: detachedInteractionRouter,
              focusTerminal: () => true,
            );
        _require(attached.isAccepted, 'F4 surface did not attach');
      }
      final _NoteAcceptanceNativeChannel detachedViewerChannel =
          detachedChannels[0];
      final _NoteAcceptanceNativeChannel detachedSourceChannel =
          detachedChannels[1];
      await detachedCoordinator.performAction(
        detachedSource,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        detachedSourceChannel,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.purple,
        body: 's2-f4-detached',
      );
      final List<TerminalNoteApplicationPaneBinding> retainedBindings =
          detachedTopology.standardBindings
              .where(
                (TerminalNoteApplicationPaneBinding binding) =>
                    binding.paneId != detachedSource,
              )
              .toList(growable: false);
      await detachedCoordinator.synchronizeTopology(retainedBindings);
      final TerminalPaneLocation detachedViewerLocation = detachedTopology.state
          .locationForPane(detachedViewer)!;
      detachedTopology.state.focusPane(
        detachedViewerLocation.tabId,
        detachedViewer,
      );
      detachedInteractionAuthority.synchronize();
      await _sendIntent(
        detachedViewerChannel,
        kind: TerminalNotesIntentKind.showDetached,
      );
      final TerminalNotesProjection detachedProjection =
          detachedViewerChannel.projection;
      detachedPassive =
          detachedProjection.section ==
              TerminalNotesCollectionSection.detached &&
          detachedProjection.dueCount == 0 &&
          detachedProjection.cards.length == 1 &&
          detachedProjection.cards.single.body == 's2-f4-detached' &&
          detachedProjection.cards.single.triggerKind == null &&
          detachedProjection.cards.single.triggerPhase == null;
      _require(
        detachedPassive,
        'F4 user close did not leave one passive Detached Note',
      );
      await detachedTopology.state.removePane(detachedSource);
      detachedInteractionAuthority.synchronize();
      await detachedCoordinator.shutdown();
      detachedCoordinator = null;
      detachedInteractionRouter.dispose();
      detachedInteractionRouter = null;
      detachedInteractionAuthority.dispose();
      detachedInteractionAuthority = null;
      await detachedTopology.state.shutdown();
      detachedTopology = null;

      acceptancePhase = 'focus-fifo';
      topology = await _createTopology();
      final List<_NoteAcceptanceNativeChannel> channels =
          <_NoteAcceptanceNativeChannel>[];
      coordinator = await TerminalNoteApplicationCoordinator.startProduction(
        launchConfiguration: _enabled,
        environment: <String, String>{
          'XDG_STATE_HOME': '${root.path}/main-state',
        },
        authorityGeneration: 203,
        restoration: null,
        initialBindings: topology.standardBindings,
        ensureQuickTerminalContext: true,
        copyEffect: (_) => false,
        exportDestinationChooser: (_) => null,
        initializeNativeCapability: () {},
        surfaceFactory: () {
          final _NoteAcceptanceNativeChannel channel =
              _NoteAcceptanceNativeChannel(
                attachment: TerminalNotesAttachDisposition.attached,
              );
          channels.add(channel);
          return channel;
        },
        storeFactory: storeFactory,
        contextIdGenerator: selectedContextIdGenerator,
        noteIdGenerator: selectedNoteIdGenerator,
        clock: () => timestamp++,
        onError: reportAsynchronousError,
      );
      await coordinator.synchronizeTopology(topology.allBindings);
      interactionAuthority = TerminalWindowInteractionAuthority(topology.state);
      interactionRouter = TerminalWindowInteractionRouter(interactionAuthority);
      final _AcceptanceTopology activeTopology = topology;
      final TerminalNoteApplicationCoordinator activeCoordinator = coordinator;
      final TerminalWindowInteractionAuthority activeInteractionAuthority =
          interactionAuthority;
      final TerminalWindowInteractionRouter activeInteractionRouter =
          interactionRouter;

      Future<_NoteAcceptanceNativeChannel> attachPane(
        PaneId paneId,
        int identity,
      ) async {
        final TerminalPaneLocation location = activeTopology.state
            .locationForPane(paneId)!;
        activeTopology.state.focusPane(location.tabId, paneId);
        activeInteractionAuthority.synchronize();
        final TerminalNoteProductTopologyResult attached =
            await activeCoordinator.synchronizeSurface(
              paneId: paneId,
              windowId: location.windowId,
              configuration: _surfaceConfiguration(identity),
              interactionAuthority: activeInteractionAuthority,
              interactionRouter: activeInteractionRouter,
              focusTerminal: () => true,
            );
        _require(attached.isAccepted, 'S2 product surface did not attach');
        return channels.last;
      }

      final PaneId primaryPane = topology.standardPaneIds.first;
      final _NoteAcceptanceNativeChannel primary = await attachPane(
        primaryPane,
        901,
      );
      for (final (String body, TerminalNotesColor color)
          in <(String, TerminalNotesColor)>[
            ('s2-fifo-first', TerminalNotesColor.yellow),
            ('s2-fifo-second', TerminalNotesColor.blue),
          ]) {
        await coordinator.performAction(
          primaryPane,
          TerminalNoteApplicationActionKind.newNote,
        );
        await _sendIntent(
          primary,
          kind: TerminalNotesIntentKind.saveOnReturn,
          color: color,
          body: body,
        );
      }
      TerminalNotesProjection projection = primary.projection;
      final int firstToken = projection.cards
          .firstWhere((TerminalNotesCard card) => card.body == 's2-fifo-first')
          .token;
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.beginEdit,
        cardToken: firstToken,
      );
      await _sendIntent(
        primary,
        kind: TerminalNotesIntentKind.cancel,
        cardToken: primary.projection.selectedToken,
      );
      projection = primary.projection;
      final int explicitFocusCallCount = primary.focusCallCount;
      _require(
        projection.dueCount == 0 &&
            projection.cards.length == 2 &&
            projection.cards.every(
              (TerminalNotesCard card) =>
                  card.triggerPhase ==
                  TerminalNotesTriggerPhase.onReturnArmedHere,
            ) &&
            explicitFocusCallCount > 0,
        'F1 editor visit created a delivery or lost explicit editor focus',
      );

      const int focusEdgeCount = 64;
      final List<Future<TerminalNoteProductTopologyResult>> pressure =
          <Future<TerminalNoteProductTopologyResult>>[];
      for (var edge = 0; edge < focusEdgeCount; edge++) {
        final bool eligible = edge.isOdd;
        pressure.add(
          coordinator.synchronizeSurface(
            paneId: primaryPane,
            windowId: topology.state.locationForPane(primaryPane)!.windowId,
            configuration: _surfaceConfiguration(
              901,
              visibility: TerminalNoteSurfaceVisibility.collapsed,
              foreground: eligible,
              occluded: !eligible && edge % 4 == 2,
            ),
            interactionAuthority: interactionAuthority,
            interactionRouter: interactionRouter,
            focusTerminal: () => true,
          ),
        );
      }
      final List<TerminalNoteProductTopologyResult> pressureResults =
          await Future.wait(pressure);
      _require(
        pressureResults.every(
          (TerminalNoteProductTopologyResult result) => result.isAccepted,
        ),
        '64-edge S2 pressure rejected a product surface transition',
      );
      projection = await _waitForProjection(
        primary,
        (TerminalNotesProjection candidate) =>
            candidate.dueCount == 2 &&
            candidate.visibility == TerminalNotesVisibility.expanded &&
            candidate.presentationEligible &&
            candidate.cards.length == 2 &&
            candidate.cards.every((TerminalNotesCard card) => card.due),
      );
      final List<String> fifoBodies = projection.cards
          .map((TerminalNotesCard card) => card.body)
          .toList(growable: false);
      _require(
        fifoBodies.toSet().containsAll(<String>{
              's2-fifo-first',
              's2-fifo-second',
            }) &&
            primary.focusCallCount == explicitFocusCallCount,
        'F2 did not expose one non-focusing FIFO rail',
      );

      Future<void> expectFalseConsume(String label) async {
        final int dueBefore = primary.projection.dueCount;
        await _notifyAndWaitForPump(primary);
        final int dueAfter = primary.projection.dueCount;
        if (dueAfter < dueBefore) falseConsumeCount += dueBefore - dueAfter;
        _require(
          dueAfter == dueBefore,
          '$label consumed an ineligible S2 delivery',
        );
      }

      await coordinator.synchronizeSurface(
        paneId: primaryPane,
        windowId: topology.state.locationForPane(primaryPane)!.windowId,
        configuration: _surfaceConfiguration(
          901,
          foreground: false,
          occluded: false,
        ),
        interactionAuthority: interactionAuthority,
        interactionRouter: interactionRouter,
        focusTerminal: () => true,
      );
      await expectFalseConsume('background wake');
      await coordinator.synchronizeSurface(
        paneId: primaryPane,
        windowId: topology.state.locationForPane(primaryPane)!.windowId,
        configuration: _surfaceConfiguration(
          901,
          foreground: true,
          occluded: true,
        ),
        interactionAuthority: interactionAuthority,
        interactionRouter: interactionRouter,
        focusTerminal: () => true,
      );
      await expectFalseConsume('occluded wake');
      await coordinator.synchronizeSurface(
        paneId: primaryPane,
        windowId: topology.state.locationForPane(primaryPane)!.windowId,
        configuration: _surfaceConfiguration(901),
        interactionAuthority: interactionAuthority,
        interactionRouter: interactionRouter,
        focusTerminal: () => true,
      );
      projection = await _waitForProjection(
        primary,
        (TerminalNotesProjection candidate) =>
            candidate.dueCount == 2 && candidate.presentationEligible,
      );
      primary.smallPane = true;
      await expectFalseConsume('small-pane wake');
      primary.smallPane = false;
      primary.presentationProjectionGeneration =
          projection.projectionGeneration - 1;
      await expectFalseConsume('stale-layout wake');
      primary.presentationProjectionGeneration = null;

      final int firstAcknowledgedGeneration =
          primary.projection.projectionGeneration;
      primary.notify();
      projection = await _waitForProjection(
        primary,
        (TerminalNotesProjection candidate) =>
            candidate.dueCount == 1 &&
            candidate.cards.first.body == fifoBodies[1] &&
            candidate.cards.first.due,
      );
      fifoAcknowledgementCount++;
      primary.presentationProjectionGeneration = firstAcknowledgedGeneration;
      primary.visibleAcknowledgementEligibleGeneration =
          firstAcknowledgedGeneration;
      await expectFalseConsume('duplicate old-generation wake');
      primary.presentationProjectionGeneration = null;
      primary.visibleAcknowledgementEligibleGeneration = null;
      primary.notify();
      projection = await _waitForProjection(
        primary,
        (TerminalNotesProjection candidate) => candidate.dueCount == 0,
      );
      fifoAcknowledgementCount++;
      _require(
        fifoAcknowledgementCount == 2 &&
            falseConsumeCount == 0 &&
            primary.focusCallCount == explicitFocusCallCount,
        'F2 FIFO acknowledgement or false-consume boundary failed',
      );

      acceptancePhase = 'quick-terminal';
      final PaneId quickPane = topology.quickPaneId!;
      final _NoteAcceptanceNativeChannel quick = await attachPane(
        quickPane,
        902,
      );
      await coordinator.performAction(
        quickPane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        quick,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.green,
        body: 's2-quick-return',
      );
      final int quickExplicitFocusCallCount = quick.focusCallCount;
      final TerminalWindowId quickWindow = topology.state
          .locationForPane(quickPane)!
          .windowId;
      await coordinator.synchronizeSurface(
        paneId: quickPane,
        windowId: quickWindow,
        configuration: _surfaceConfiguration(
          902,
          foreground: false,
          occluded: true,
        ),
        interactionAuthority: interactionAuthority,
        interactionRouter: interactionRouter,
        focusTerminal: () => true,
      );
      await coordinator.synchronizeSurface(
        paneId: quickPane,
        windowId: quickWindow,
        configuration: _surfaceConfiguration(902),
        interactionAuthority: interactionAuthority,
        interactionRouter: interactionRouter,
        focusTerminal: () => true,
      );
      await _waitForProjection(
        quick,
        (TerminalNotesProjection candidate) =>
            candidate.dueCount == 1 &&
            candidate.visibility == TerminalNotesVisibility.expanded &&
            candidate.presentationEligible,
      );
      quick.notify();
      await _waitForProjection(
        quick,
        (TerminalNotesProjection candidate) => candidate.dueCount == 0,
      );
      _require(
        quickExplicitFocusCallCount > 0 &&
            quick.focusCallCount == quickExplicitFocusCallCount,
        'Quick Terminal return stole terminal focus',
      );

      acceptancePhase = 'restart-arm';
      final int restartPaneIndex = 1;
      final PaneId restartPane = topology.standardPaneIds[restartPaneIndex];
      final _NoteAcceptanceNativeChannel restart = await attachPane(
        restartPane,
        903,
      );
      await coordinator.performAction(
        restartPane,
        TerminalNoteApplicationActionKind.newNote,
      );
      await _sendIntent(
        restart,
        kind: TerminalNotesIntentKind.saveOnReturn,
        color: TerminalNotesColor.pink,
        body: 's2-f3-restart',
      );
      _require(
        restart.projection.cards.single.triggerPhase ==
            TerminalNotesTriggerPhase.onReturnArmedHere,
        'F3 restart Note was not armed in the current visit',
      );

      final TerminalNoteRestorationCaptureArtifact capture =
          TerminalNoteRestorationCaptureArtifact.capture(
            topology.state,
            placementForWindow:
                TerminalNoteS1ProductAcceptance._placementForWindow,
            workingDirectoryForPane: (_) => null,
          );
      Future<bool> commitRestoration(
        TerminalNoteRestorationArtifact artifact,
      ) async =>
          (await restorationPersistence.saveExactEncoded(artifact.exactEncoded))
              .disposition ==
          TerminalRestorationSaveDisposition.saved;
      final TerminalNoteApplicationShutdownResult firstShutdown =
          await coordinator.shutdownApplication(
            capture: capture,
            updatedAtUtcMicros: timestamp++,
            commitRestoration: commitRestoration,
          );
      _require(firstShutdown.isSuccess, 'F3 ordered shutdown failed');
      coordinator = null;
      interactionRouter.dispose();
      interactionRouter = null;
      interactionAuthority.dispose();
      interactionAuthority = null;
      await topology.state.shutdown();
      topology = null;

      final TerminalRestorationLoadResult loaded = await restorationPersistence
          .load();
      _require(
        loaded.disposition == TerminalRestorationLoadDisposition.restored &&
            loaded.exactEncoded == capture.restoration.exactEncoded,
        'F3 exact restoration artifact was not persisted',
      );
      acceptancePhase = 'restart-reopen';
      reopenedTopology = await _createTopology(initialPaneId: 1000);
      final _NoteAcceptanceNativeChannel reopenedChannel =
          _NoteAcceptanceNativeChannel(
            attachment: TerminalNotesAttachDisposition.attached,
          );
      reopenedCoordinator =
          await TerminalNoteApplicationCoordinator.startProduction(
            launchConfiguration: _enabled,
            environment: <String, String>{
              'XDG_STATE_HOME': '${root.path}/main-state',
            },
            authorityGeneration: 204,
            restoration: TerminalNoteRestorationArtifact.fromExactEncoded(
              loaded.exactEncoded!,
            ),
            initialBindings: reopenedTopology.standardBindings,
            ensureQuickTerminalContext: true,
            copyEffect: (_) => false,
            exportDestinationChooser: (_) => null,
            initializeNativeCapability: () {},
            surfaceFactory: () => reopenedChannel,
            storeFactory: storeFactory,
            contextIdGenerator: selectedContextIdGenerator,
            noteIdGenerator: selectedNoteIdGenerator,
            clock: () => timestamp++,
            onError: reportAsynchronousError,
          );
      await reopenedCoordinator.synchronizeTopology(
        reopenedTopology.allBindings,
      );
      reopenedInteractionAuthority = TerminalWindowInteractionAuthority(
        reopenedTopology.state,
      );
      reopenedInteractionRouter = TerminalWindowInteractionRouter(
        reopenedInteractionAuthority,
      );
      final PaneId reopenedPane =
          reopenedTopology.standardPaneIds[restartPaneIndex];
      final TerminalPaneLocation reopenedLocation = reopenedTopology.state
          .locationForPane(reopenedPane)!;
      reopenedTopology.state.focusPane(reopenedLocation.tabId, reopenedPane);
      reopenedInteractionAuthority.synchronize();
      final TerminalNoteProductTopologyResult reopenedAttached =
          await reopenedCoordinator.synchronizeSurface(
            paneId: reopenedPane,
            windowId: reopenedLocation.windowId,
            configuration: _surfaceConfiguration(
              904,
              visibility: TerminalNoteSurfaceVisibility.collapsed,
            ),
            interactionAuthority: reopenedInteractionAuthority,
            interactionRouter: reopenedInteractionRouter,
            focusTerminal: () => true,
          );
      _require(
        reopenedAttached.isAccepted,
        'F3 reopened surface did not attach',
      );
      final TerminalNotesProjection reopenedProjection =
          await _waitForProjection(
            reopenedChannel,
            (TerminalNotesProjection candidate) =>
                candidate.dueCount == 1 &&
                candidate.visibility == TerminalNotesVisibility.expanded &&
                candidate.cards.single.body == 's2-f3-restart' &&
                candidate.cards.single.due,
          );
      exactRestart =
          reopenedProjection.presentationEligible &&
          reopenedChannel.focusCallCount == 0;
      reopenedChannel.notify();
      await _waitForProjection(
        reopenedChannel,
        (TerminalNotesProjection candidate) => candidate.dueCount == 0,
      );
      _require(exactRestart, 'F3 first eligible restart visit was not exact');
      final TerminalNoteRestorationCaptureArtifact reopenedCapture =
          TerminalNoteRestorationCaptureArtifact.capture(
            reopenedTopology.state,
            placementForWindow:
                TerminalNoteS1ProductAcceptance._placementForWindow,
            workingDirectoryForPane: (_) => null,
          );
      final TerminalNoteApplicationShutdownResult reopenedShutdown =
          await reopenedCoordinator.shutdownApplication(
            capture: reopenedCapture,
            updatedAtUtcMicros: timestamp++,
            commitRestoration: commitRestoration,
          );
      _require(
        reopenedShutdown.isSuccess,
        'F3 reopened ordered shutdown failed',
      );
      reopenedCoordinator = null;
      reopenedInteractionRouter.dispose();
      reopenedInteractionRouter = null;
      reopenedInteractionAuthority.dispose();
      reopenedInteractionAuthority = null;
      await reopenedTopology.state.shutdown();
      reopenedTopology = null;

      final TerminalNoteS2SentinelSnapshot after = sentinelProbe();
      final int ownerLeakCount = _NoteOwnerCounts.capture().delta(
        ownerBaseline,
      );
      final TerminalNoteS2ProductAcceptanceResult result =
          TerminalNoteS2ProductAcceptanceResult(
            reviewVectorCount: 4,
            standardWindowCount: 2,
            standardTabCount: 3,
            standardPaneCount: 5,
            quickTerminalCount: 1,
            focusEdgeCount: focusEdgeCount,
            fifoAcknowledgementCount: fifoAcknowledgementCount,
            falseConsumeCount: falseConsumeCount,
            exactRestart: exactRestart,
            detachedPassive: detachedPassive,
            disabledZeroEntry: disabledZeroEntry,
            tuiModeSignature:
                before.hasTuiModeSignature && after.hasTuiModeSignature,
            protectedStateUnchanged: before.hasSameProtectedState(after),
            ownerLeakCount: ownerLeakCount,
          );
      _require(
        result.isSuccess,
        'S2 product acceptance result is incomplete: ${result.machineLine()}',
      );
      return result;
    } finally {
      await disabledCoordinator?.shutdown();
      disabledInteractionRouter?.dispose();
      disabledInteractionAuthority?.dispose();
      if (disabledTopology != null && !disabledTopology.state.isDisposed) {
        await disabledTopology.state.shutdown();
      }
      await detachedCoordinator?.shutdown();
      detachedInteractionRouter?.dispose();
      detachedInteractionAuthority?.dispose();
      if (detachedTopology != null && !detachedTopology.state.isDisposed) {
        await detachedTopology.state.shutdown();
      }
      await coordinator?.shutdown();
      interactionRouter?.dispose();
      interactionAuthority?.dispose();
      if (topology != null && !topology.state.isDisposed) {
        await topology.state.shutdown();
      }
      await reopenedCoordinator?.shutdown();
      reopenedInteractionRouter?.dispose();
      reopenedInteractionAuthority?.dispose();
      if (reopenedTopology != null && !reopenedTopology.state.isDisposed) {
        await reopenedTopology.state.shutdown();
      }
    }
  }
}

final class _NoteOwnerCounts {
  const _NoteOwnerCounts({
    required this.compositions,
    required this.products,
    required this.authorities,
    required this.workers,
    required this.processPorts,
    required this.interactions,
  });

  factory _NoteOwnerCounts.capture() => _NoteOwnerCounts(
    compositions: TerminalNoteCompositionRoot.debugLiveSubsystemCount,
    products: TerminalNoteProductSubsystem.debugLiveProductSubsystemCount,
    authorities: TerminalNoteAuthority.debugLiveAuthorityCount,
    workers: TerminalNoteStoreWorkerClient.debugLiveClientCount,
    processPorts: TerminalNoteProcessStoreFactory.debugLivePortCount,
    interactions:
        TerminalNoteApplicationCoordinator.debugLiveInteractionAdapterCount,
  );

  final int compositions;
  final int products;
  final int authorities;
  final int workers;
  final int processPorts;
  final int interactions;

  int delta(_NoteOwnerCounts baseline) =>
      (compositions - baseline.compositions).abs() +
      (products - baseline.products).abs() +
      (authorities - baseline.authorities).abs() +
      (workers - baseline.workers).abs() +
      (processPorts - baseline.processPorts).abs() +
      (interactions - baseline.interactions).abs();

  @override
  bool operator ==(Object other) =>
      other is _NoteOwnerCounts && delta(other) == 0;

  @override
  int get hashCode => Object.hash(
    compositions,
    products,
    authorities,
    workers,
    processPorts,
    interactions,
  );
}

final class _AcceptanceTopology {
  const _AcceptanceTopology({
    required this.state,
    required this.standardBindings,
    required this.allBindings,
    required this.standardPaneIds,
    required this.quickPaneId,
    required this.standardWindowCount,
    required this.standardTabCount,
  });

  final TerminalApplicationState state;
  final List<TerminalNoteApplicationPaneBinding> standardBindings;
  final List<TerminalNoteApplicationPaneBinding> allBindings;
  final List<PaneId> standardPaneIds;
  final PaneId? quickPaneId;
  final int standardWindowCount;
  final int standardTabCount;
}

Future<_AcceptanceTopology> _createTopology({
  int standardWindowCount = 2,
  int initialPaneId = 0,
}) async {
  final TerminalApplicationState state = TerminalApplicationState(
    paneOwner: TerminalPaneOwner(initialPaneId: initialPaneId),
  );
  final TerminalPaneConfiguration configuration = _paneConfiguration();
  final TerminalWindowState first = await state.createWindow(configuration);
  if (standardWindowCount == 2) {
    final PaneId firstPane = first.selectedTab.focusedPaneId;
    await state.splitPane(
      firstPane,
      configuration,
      axis: TerminalSplitAxis.horizontal,
    );
    final TerminalTabState secondTab = await state.createTab(
      first.id,
      configuration,
    );
    await state.splitPane(
      secondTab.focusedPaneId,
      configuration,
      axis: TerminalSplitAxis.vertical,
    );
    await state.createWindow(configuration);
  }
  PaneId? quickPaneId;
  if (standardWindowCount == 2) {
    final TerminalWindowState quick = await state.createWindow(
      configuration,
      role: TerminalWindowRole.quickTerminal,
    );
    quickPaneId = quick.selectedTab.focusedPaneId;
  }
  final List<TerminalNoteApplicationPaneBinding> standard =
      <TerminalNoteApplicationPaneBinding>[
        for (final TerminalWindowState window in state.windows)
          if (window.role == TerminalWindowRole.standard)
            for (final TerminalTabState tab in window.tabs)
              for (final PaneId paneId in tab.paneIds)
                TerminalNoteApplicationPaneBinding(
                  paneId: paneId,
                  windowId: window.id,
                ),
      ];
  final List<TerminalNoteApplicationPaneBinding> all =
      <TerminalNoteApplicationPaneBinding>[
        ...standard,
        if (quickPaneId != null)
          TerminalNoteApplicationPaneBinding(
            paneId: quickPaneId,
            windowId: state.quickTerminalWindow!.id,
            kind: TerminalNoteContextKind.quickTerminal,
          ),
      ];
  return _AcceptanceTopology(
    state: state,
    standardBindings: List<TerminalNoteApplicationPaneBinding>.unmodifiable(
      standard,
    ),
    allBindings: List<TerminalNoteApplicationPaneBinding>.unmodifiable(all),
    standardPaneIds: List<PaneId>.unmodifiable(
      standard.map(
        (TerminalNoteApplicationPaneBinding binding) => binding.paneId,
      ),
    ),
    quickPaneId: quickPaneId,
    standardWindowCount: state.windows
        .where(
          (TerminalWindowState window) =>
              window.role == TerminalWindowRole.standard,
        )
        .length,
    standardTabCount: state.windows
        .where(
          (TerminalWindowState window) =>
              window.role == TerminalWindowRole.standard,
        )
        .fold<int>(0, (int count, TerminalWindowState window) {
          return count + window.tabs.length;
        }),
  );
}

TerminalPaneConfiguration _paneConfiguration() => TerminalPaneConfiguration(
  sessionFactory: (
    TerminalSessionId id, {
    required void Function() onChanged,
    required void Function() onTerminated,
  }) => _AcceptanceSession(id),
  onChanged: () {},
  onExitRequested: () {},
);

TerminalNoteProductSurfaceConfiguration _surfaceConfiguration(
  int identity, {
  TerminalNoteSurfaceVisibility visibility =
      TerminalNoteSurfaceVisibility.expanded,
  bool foreground = true,
  bool occluded = false,
  double paneWidth = 900,
  double paneHeight = 600,
}) => TerminalNoteProductSurfaceConfiguration(
  rendererIdentity: TerminalMetalRendererCompositionIdentity(
    handle: identity,
    generation: identity,
  ),
  paneWidth: paneWidth,
  paneHeight: paneHeight,
  backingScale: 2,
  requestedRailWidth: 320,
  visibility: visibility,
  foreground: foreground,
  occluded: occluded,
);

Future<TerminalNotesNativeResult> _sendIntent(
  _NoteAcceptanceNativeChannel channel, {
  required TerminalNotesIntentKind kind,
  int? cardToken,
  TerminalNotesColor? color,
  String? body,
  TerminalNotesResultDisposition expectedDisposition =
      TerminalNotesResultDisposition.accepted,
}) async {
  final TerminalNotesProjection projection = channel.projection;
  final int resultCount = channel.results.length;
  channel.intents.add(
    TerminalNotesNativeIntent(
      surfaceGeneration: projection.surfaceGeneration,
      projectionGeneration: projection.projectionGeneration,
      eventGeneration: channel.takeEventGeneration(),
      draftGeneration: projection.draftGeneration,
      cardToken: cardToken,
      expectedStoreRevision: projection.storeRevision,
      kind: kind,
      color: color,
      body: body,
    ),
  );
  channel.notify();
  final Stopwatch deadline = Stopwatch()..start();
  while (channel.results.length == resultCount &&
      deadline.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (channel.results.length != resultCount + 1) {
    throw StateError(
      'Note acceptance intent did not produce exactly one result: '
      '${kind.name}/results=${channel.results.length - resultCount}/'
      'pending=${channel.intents.length}/disposed=${channel.disposeCount}',
    );
  }
  final TerminalNotesNativeResult result = channel.results.last;
  if (result.disposition != expectedDisposition) {
    throw StateError(
      'Note acceptance intent disposition ${result.disposition.name} did not '
      'match ${expectedDisposition.name}',
    );
  }
  return result;
}

Future<TerminalNotesProjection> _waitForProjection(
  _NoteAcceptanceNativeChannel channel,
  bool Function(TerminalNotesProjection projection) predicate,
) async {
  final Stopwatch deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 5)) {
    if (channel.projections.isNotEmpty) {
      final TerminalNotesProjection projection = channel.projection;
      if (predicate(projection)) return projection;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('timed out waiting for Note acceptance projection');
}

Future<void> _notifyAndWaitForPump(_NoteAcceptanceNativeChannel channel) async {
  final int baseline = channel.takeIntentCount;
  channel.notify();
  final Stopwatch deadline = Stopwatch()..start();
  while (channel.takeIntentCount == baseline &&
      deadline.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (channel.takeIntentCount != baseline + 1) {
    throw StateError('Note acceptance wake did not pump exactly once');
  }
  await _drainEvents();
}

Future<void> _drainEvents() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _NoteAcceptanceNativeChannel
    implements TerminalNoteNativeSurfaceChannel {
  _NoteAcceptanceNativeChannel({
    required TerminalNotesAttachDisposition attachment,
  }) : _nextAttachment = attachment;

  final List<TerminalNotesProjection> projections = <TerminalNotesProjection>[];
  final Queue<TerminalNotesNativeIntent> intents =
      Queue<TerminalNotesNativeIntent>();
  final List<TerminalNotesNativeResult> results = <TerminalNotesNativeResult>[];
  TerminalNotesAttachDisposition _nextAttachment;
  TerminalNotesResultApplyDisposition nextResultApply =
      TerminalNotesResultApplyDisposition.accepted;
  void Function()? _notificationHandler;
  (double, double, double, double)? _layout;
  var _eventGeneration = 0;
  var takeIntentCount = 0;
  var disposeCount = 0;
  var detachCount = 0;
  var focusCallCount = 0;
  var editorDirty = false;
  var confirmingDiscard = false;
  var smallPane = false;
  var railVisible = true;
  int? snapshotProjectionGeneration;
  int? presentationProjectionGeneration;
  int? visibleAcknowledgementEligibleGeneration;
  TerminalNotesRect? firstCard;
  TerminalNotesNativeFocusTarget _focusTarget =
      TerminalNotesNativeFocusTarget.none;

  TerminalNotesProjection get projection => projections.last;

  int takeEventGeneration() => ++_eventGeneration;

  void notify() => _notificationHandler?.call();

  @override
  void setNotificationHandler(void Function()? handler) {
    _notificationHandler = handler;
  }

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    projections.add(projection);
    if (projection.editorMode == TerminalNotesEditorMode.inactive) {
      editorDirty = false;
      confirmingDiscard = false;
    }
    return TerminalNotesApplyDisposition.accepted;
  }

  @override
  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) {
    final TerminalNotesAttachDisposition disposition = _nextAttachment;
    _nextAttachment = TerminalNotesAttachDisposition.attached;
    return disposition;
  }

  @override
  void detachFromHost() {
    detachCount++;
  }

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    _layout = (paneWidth, paneHeight, backingScale, requestedRailWidth);
  }

  @override
  TerminalNotesNativeIntent? takeIntent() {
    takeIntentCount++;
    return intents.isEmpty ? null : intents.removeFirst();
  }

  @override
  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) {
    results.add(result);
    final TerminalNotesResultApplyDisposition disposition = nextResultApply;
    nextResultApply = TerminalNotesResultApplyDisposition.accepted;
    return disposition;
  }

  @override
  bool focus(TerminalNotesNativeFocusTarget target) {
    focusCallCount++;
    _focusTarget = target;
    return true;
  }

  @override
  bool presentDiscardConfirmation() {
    confirmingDiscard = true;
    return true;
  }

  @override
  TerminalNotesNativeSnapshot get snapshot {
    final TerminalNotesProjection current = projection;
    return TerminalNotesNativeSnapshot(
      paneId: current.paneId,
      surfaceGeneration: current.surfaceGeneration,
      projectionGeneration:
          snapshotProjectionGeneration ?? current.projectionGeneration,
      storeRevision: current.storeRevision,
      acceptedProjectionCount: projections.length,
      rejectedProjectionCount: 0,
      draftGeneration: current.draftGeneration,
      activeCount: current.activeCount,
      dueCount: current.dueCount,
      projectedCardCount: current.cards.length,
      materializedCardCount: current.cards.length,
      packetBytes: 0,
      visibility: current.visibility,
      presentationEligible: current.presentationEligible,
      initialized: true,
      readyCue: current.readyCue,
      darkAppearance: current.darkAppearance,
      increaseContrast: current.increaseContrast,
      differentiateWithoutColor: current.differentiateWithoutColor,
      reduceMotion: current.reduceMotion,
      systemBadgeVisible: current.systemBadgeVisible,
      onReturnEnabled: current.onReturnEnabled,
      featureState: current.featureState,
      surfaceState: current.surfaceState,
      section: current.section,
      editorMode: current.editorMode,
      messageKey: current.messageKey,
      pageStart: current.pageStart,
      totalCount: current.totalCount,
      bodyFontMilliPoints: current.bodyFontMilliPoints,
      outstandingIntent: intents.isNotEmpty,
      emittedIntentCount: _eventGeneration,
      appliedResultCount: results.length,
      editorDirty: editorDirty,
      confirmingDiscard: confirmingDiscard,
      focusTarget: _focusTarget,
    );
  }

  @override
  TerminalNotesNativePresentation get presentation {
    final TerminalNotesProjection current = projection;
    final bool expanded =
        current.visibility == TerminalNotesVisibility.expanded;
    final bool visibleRail = expanded && railVisible && !smallPane;
    final bool visibleDue =
        visibleRail &&
        current.presentationEligible &&
        current.editorMode == TerminalNotesEditorMode.inactive &&
        current.dueCount > 0 &&
        current.cards.isNotEmpty &&
        current.cards.first.due;
    return TerminalNotesNativePresentation(
      projectionGeneration:
          presentationProjectionGeneration ?? current.projectionGeneration,
      paneWidth: _layout?.$1 ?? 900,
      paneHeight: _layout?.$2 ?? 600,
      backingScale: _layout?.$3 ?? 2,
      badgeHit: const TerminalNotesRect(x: 840, y: 280, width: 44, height: 44),
      badgeVisual: const TerminalNotesRect(
        x: 840,
        y: 288,
        width: 44,
        height: 28,
      ),
      rail: const TerminalNotesRect(x: 568, y: 12, width: 320, height: 576),
      firstCard:
          firstCard ??
          const TerminalNotesRect(x: 580, y: 74, width: 284, height: 88),
      flags: (visibleRail ? 2 : 1) | (smallPane ? 4 : 0),
      materializedCardCount: current.cards.length,
      accessibilityNodeCount: 1,
      accessibilityBodyCount: current.cards.length,
      visibleAcknowledgementEligibleGeneration:
          visibleAcknowledgementEligibleGeneration ??
          (visibleDue ? current.projectionGeneration : 0),
      accessibilityAnnouncementCount: 0,
      animationMilliseconds: 0,
      bodyFontMilliPoints: current.bodyFontMilliPoints,
      badgeDisplayCount: current.activeCount,
    );
  }

  @override
  void dispose() {
    if (disposeCount == 0) disposeCount = 1;
    _notificationHandler = null;
  }
}

final class _AcceptanceSession implements TerminalPaneSession {
  _AcceptanceSession(this.id);

  @override
  final TerminalSessionId id;
  var _live = false;

  @override
  bool get isLive => _live;
  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => null;
  @override
  TerminalKeyboardModes get keyboardModes => const TerminalKeyboardModes();
  @override
  bool get bracketedPasteMode => false;
  @override
  bool get pasteInProgress => false;
  @override
  TerminalPaneProcessSnapshot processSnapshot() =>
      TerminalPaneProcessSnapshot.nonLive(id);
  @override
  Future<void> start() async => _live = true;
  @override
  String render() => '';
  @override
  void insertText(String value) {}
  @override
  void deleteBackward() {}
  @override
  void deleteForward() {}
  @override
  void moveLeft() {}
  @override
  void moveRight() {}
  @override
  void moveToStart() {}
  @override
  void moveToEnd() {}
  @override
  void previousHistory() {}
  @override
  void nextHistory() {}
  @override
  Future<void> submit() async {}
  @override
  void interrupt() {}
  @override
  void suspend() {}
  @override
  void quitForegroundProcess() {}
  @override
  void sendEndOfFile() {}
  @override
  void sendInput(Uint8List bytes) {}
  @override
  Future<TerminalPasteTransferResult> paste(TerminalPastePlan plan) async =>
      const TerminalPasteTransferResult(
        disposition: TerminalPasteTransferDisposition.completed,
        encodedBytes: 0,
        completedChunks: 0,
        backpressureCount: 0,
        maximumQueuedBytes: 0,
        concurrentInputRejections: 0,
      );
  @override
  void resize({required int rows, required int columns}) {}
  @override
  void showClipboardNotice(TerminalClipboardNotice notice) {}
  @override
  void showHyperlinkNotice(TerminalHyperlinkNoticeKind kind) {}
  @override
  void showCloseConfirmation() {}
  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    _live = false;
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}
