import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_session.dart';

import 'font_shaping_test.dart';
import 'frame_scheduler_test.dart';
import 'glyph_atlas_test.dart';
import 'golden_image_test.dart';
import 'metal_failure_recovery_test.dart';
import 'metal_pipeline_test.dart';
import 'product_parser_benchmark_test.dart';
import 'product_parser_corpus_test.dart';
import 'reference_renderer_test.dart';
import 'render_rebuild_coordinator_test.dart';
import 'render_resource_rebuilder_test.dart';
import 'renderer_metrics_test.dart';
import 'runtime_lifecycle_test.dart';
import 'terminal_appkit_key_adapter_test.dart';
import 'terminal_core_test.dart';
import 'terminal_damage_copy_test.dart';
import 'terminal_damage_test.dart';
import 'terminal_damage_transfer_test.dart';
import 'terminal_history_reflow_test.dart';
import 'terminal_input_matrix_test.dart';
import 'terminal_key_binding_test.dart';
import 'terminal_key_encoder_test.dart';
import 'terminal_live_metal_surface_font_test.dart';
import 'terminal_mouse_encoder_test.dart';
import 'terminal_mouse_router_test.dart';
import 'terminal_palette_test.dart';
import 'terminal_preedit_test.dart';
import 'terminal_property_fuzz_test.dart';
import 'terminal_reflow_test.dart';
import 'terminal_reply_test.dart';
import 'terminal_screen_metal_compositor_test.dart';
import 'terminal_screen_set_test.dart';
import 'terminal_screen_test.dart';
import 'terminal_scrollback_test.dart';
import 'terminal_selection_gesture_test.dart';
import 'terminal_selection_search_test.dart';
import 'terminal_session_reply_test.dart';
import 'terminal_snapshot_test.dart';
import 'terminal_style_test.dart';
import 'terminal_text_input_event_router_test.dart';
import 'terminal_unicode_test.dart';
import 'terminal_viewport_test.dart';
import 'terminal_wide_grapheme_test.dart';
import 'vt_parser_test.dart';

@Native<Uint64 Function()>(
  symbol: 'dpty_debug_live_session_count',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _livePtySessionCount();

Future<void> main() async {
  runTerminalCoreTests();
  runFrameSchedulerTests();
  runTerminalDamageTests();
  runTerminalDamageCopyTests();
  await runTerminalDamageTransferTests();
  runProductParserBenchmarkTests();
  runProductParserCorpusTests();
  runGoldenImageTests();
  runFontShapingTests();
  runGlyphAtlasTests();
  runMetalPipelineTests();
  runMetalFailureRecoveryTests();
  runReferenceRendererTests();
  runRenderRebuildCoordinatorTests();
  runRenderResourceRebuilderTests();
  runRendererMetricsTests();
  runTerminalHistoryReflowTests();
  runTerminalInputMatrixTests();
  runTerminalAppKitKeyAdapterTests();
  runTerminalKeyBindingTests();
  runTerminalKeyEncoderTests();
  runTerminalMouseEncoderTests();
  runTerminalMouseRouterTests();
  runTerminalSelectionGestureTests();
  runTerminalLiveMetalSurfaceFontTests();
  runTerminalPaletteTests();
  runTerminalPreeditTests();
  runTerminalPropertyFuzzTests();
  runTerminalReflowTests();
  runTerminalReplyTests();
  runTerminalScrollbackTests();
  runTerminalScreenTests();
  runTerminalScreenSetTests();
  runTerminalSelectionSearchTests();
  runTerminalSnapshotTests();
  runTerminalScreenMetalCompositorTests();
  runTerminalStyleTests();
  runTerminalTextInputEventRouterTests();
  runTerminalUnicodeTests();
  runTerminalViewportTests();
  runTerminalWideGraphemeTests();
  runVtParserTests();
  _testEditing();
  _testUnicodeEditing();
  _testHistoryNavigation();
  _testTranscriptLimitAndViewport();
  _testOptions();
  _testNativeObservationFormatting();
  await _testPaneIdentityOwnershipAndClosePolicy();
  await _testControlDAppKitKeyRoute();
  await _testModeAwareAppKitKeyRoute();
  await runRuntimeLifecycleTests().timeout(const Duration(seconds: 30));
  await runTerminalSessionReplyTests();
  await _testPersistentCommandSession();
  await _testBoundedSessionShutdown();
  await _testRealPersistentPtySession();
  await _testControlDSemanticsMatrix().timeout(const Duration(seconds: 30));
  await _testRepeatedControlDNaturalExit().timeout(const Duration(seconds: 45));
  stdout.writeln('dart_terminal tests passed');
}

void _testNativeObservationFormatting() {
  const TerminalSessionNativeObservation observation =
      TerminalSessionNativeObservation(
        sessionId: TerminalSessionId(paneId: PaneId(9), generation: 2),
        processId: 4100,
        event: PtyDiagnosticEvent(
          stage: PtyDiagnosticStage.writeCompleted,
          requestId: 7,
          byteCount: 1,
          queuedBytes: 0,
        ),
      );
  final String line = observation.machineLine();
  _expect(
    line.startsWith(
          'TERMINAL_PTY_NATIVE pane=9 session=9:2 process_id=4100 '
          'stage=writeCompleted request_id=7 byte_count=1 queued_bytes=0 ',
        ) &&
        line.contains('child_status=0 child_status_valid=false') &&
        !line.contains('input') &&
        !line.contains('output') &&
        !line.contains('command') &&
        !line.contains('cwd'),
    'native PTY observation uses the content-free scalar allowlist',
  );
}

Future<void> _testControlDAppKitKeyRoute() async {
  final TerminalPaneOwner owner = TerminalPaneOwner();
  late final _FakePaneSession session;
  final TerminalPane pane = owner.createPane(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          session = _FakePaneSession(
            id: id,
            onChanged: onChanged,
            onTerminated: onTerminated,
          );
          return session;
        },
    onChanged: () {},
    onExitRequested: () {},
  );
  await pane.start();
  final TerminalKeyRouteResult result = TerminalKeyEventRouter().handleKeyDown(
    const AppKitKeyEvent(
      windowHandle: 1,
      monotonicMicros: 1,
      kind: AppKitKeyEventKind.down,
      keyCode: 2,
      modifiers: ModifierKeys(ModifierKeys.controlBit),
      isRepeat: false,
      characters: '\u0004',
      charactersIgnoringModifiers: 'd',
    ),
    pane,
  );
  _expect(
    session.endOfFileCount == 1 &&
        result.disposition == TerminalKeyRouteDisposition.action &&
        result.action == TerminalKeyBindingAction.sendEndOfFile,
    'decoded AppKit Control-D routes exactly once to terminal EOF input',
  );
  await owner.shutdown();
}

Future<void> _testModeAwareAppKitKeyRoute() async {
  final TerminalPaneOwner owner = TerminalPaneOwner();
  late final _FakePaneSession session;
  final TerminalPane pane = owner.createPane(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          session = _FakePaneSession(
            id: id,
            onChanged: onChanged,
            onTerminated: onTerminated,
          );
          return session;
        },
    onChanged: () {},
    onExitRequested: () {},
  );
  await pane.start();
  session.keyboardModes = const TerminalKeyboardModes(
    applicationCursorKeys: true,
  );

  final TerminalKeyEventRouter standardRouter = TerminalKeyEventRouter();
  final TerminalKeyRouteResult cursorResult = standardRouter.handleKeyDown(
    _appKitKeyEvent(
      keyCode: 126,
      characters: '\uf700',
      unmodifiedCharacters: '\uf700',
      modifierBits: ModifierKeys.functionBit,
    ),
    pane,
  );
  _expect(
    cursorResult.disposition == TerminalKeyRouteDisposition.encoded &&
        cursorResult.encodedByteCount == 3 &&
        _bytesEqual(session.inputWrites.single, <int>[0x1b, 0x4f, 0x41]),
    'AppKit Up reads DECCKM state and produces one SS3 pane write',
  );

  final TerminalKeyRouteResult controlCResult = standardRouter.handleKeyDown(
    _appKitKeyEvent(
      keyCode: 8,
      characters: '\x03',
      unmodifiedCharacters: 'c',
      modifierBits: ModifierKeys.controlBit,
    ),
    pane,
  );
  _expect(
    controlCResult.disposition == TerminalKeyRouteDisposition.encoded &&
        _bytesEqual(session.inputWrites.last, <int>[0x03]) &&
        session.interruptCount == 0,
    'ordinary Control-C is terminal input rather than an application signal',
  );

  final int writesBeforeIgnored = session.inputWrites.length;
  _expect(
    standardRouter
            .handleKeyDown(
              _appKitKeyEvent(
                keyCode: 0,
                characters: 'a',
                unmodifiedCharacters: 'a',
                modifierBits: ModifierKeys.commandBit,
              ),
              pane,
            )
            .disposition ==
        TerminalKeyRouteDisposition.ignored,
    'unbound Command input has no implicit PTY bytes',
  );
  _expect(
    standardRouter
                .handleKeyDown(
                  _appKitKeyEvent(
                    keyCode: 0,
                    characters: 'a',
                    unmodifiedCharacters: 'a',
                    kind: AppKitKeyEventKind.up,
                  ),
                  pane,
                )
                .disposition ==
            TerminalKeyRouteDisposition.ignored &&
        session.inputWrites.length == writesBeforeIgnored,
    'key-up and ignored Command input do not duplicate a pane write',
  );

  final TerminalKeyEventRouter passthroughRouter = TerminalKeyEventRouter(
    bindingEngine: TerminalKeyBindingEngine.standard(
      overrides: const <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.passthrough(
          chord: TerminalKeyBindingChord(
            physicalKey: TerminalPhysicalKey.keyA,
            command: true,
          ),
        ),
      ],
    ),
  );
  final TerminalKeyRouteResult passthroughResult = passthroughRouter
      .handleKeyDown(
        _appKitKeyEvent(
          keyCode: 0,
          characters: 'a',
          unmodifiedCharacters: 'a',
          modifierBits: ModifierKeys.commandBit,
        ),
        pane,
      );
  _expect(
    passthroughResult.disposition == TerminalKeyRouteDisposition.encoded &&
        _bytesEqual(session.inputWrites.last, <int>[0x61]),
    'explicit Command passthrough reaches the terminal encoder exactly once',
  );

  final TerminalKeyEventRouter unboundRouter = TerminalKeyEventRouter(
    bindingEngine: TerminalKeyBindingEngine.standard(
      overrides: const <TerminalKeyBindingDefinition>[
        TerminalKeyBindingDefinition.unbind(
          chord: TerminalKeyBindingChord(
            physicalKey: TerminalPhysicalKey.keyD,
            control: true,
          ),
        ),
      ],
    ),
  );
  final TerminalKeyRouteResult unboundResult = unboundRouter.handleKeyDown(
    _appKitKeyEvent(
      keyCode: 2,
      characters: '\x04',
      unmodifiedCharacters: 'd',
      modifierBits: ModifierKeys.controlBit,
    ),
    pane,
  );
  _expect(
    unboundResult.disposition == TerminalKeyRouteDisposition.encoded &&
        _bytesEqual(session.inputWrites.last, <int>[0x04]) &&
        session.endOfFileCount == 0,
    'unbinding tracked Control-D restores ordinary encoded terminal input',
  );

  final Uint8List ownedInput = Uint8List.fromList(<int>[0x7a]);
  pane.sendInput(ownedInput);
  ownedInput[0] = 0;
  _expect(
    session.inputWrites.last.single == 0x7a,
    'pane input copies caller-owned bytes before session delegation',
  );
  _expectThrows(
    () => pane.sendInput(
      Uint8List(TerminalInputLimits.maximumEncodedBytesPerKeyEvent + 1),
    ),
    'pane input rejects writes beyond the per-key-event bound',
    expectedType: RangeError,
  );
  await owner.shutdown();
}

AppKitKeyEvent _appKitKeyEvent({
  required int keyCode,
  required String characters,
  required String unmodifiedCharacters,
  int modifierBits = 0,
  AppKitKeyEventKind kind = AppKitKeyEventKind.down,
}) => AppKitKeyEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  keyCode: keyCode,
  modifiers: ModifierKeys(modifierBits),
  isRepeat: false,
  characters: characters,
  charactersIgnoringModifiers: unmodifiedCharacters,
);

bool _bytesEqual(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

Future<void> _testPaneIdentityOwnershipAndClosePolicy() async {
  final TerminalPaneOwner owner = TerminalPaneOwner(initialPaneId: 40);
  final List<_FakePaneSession> sessions = <_FakePaneSession>[];
  final List<TerminalPaneLifecycleObservation> paneLifecycle =
      <TerminalPaneLifecycleObservation>[];
  final List<TerminalPaneExitObservation> paneExits =
      <TerminalPaneExitObservation>[];
  var changed = 0;
  var exitRequests = 0;
  TerminalPane createPane() => owner.createPane(
    sessionFactory:
        (
          TerminalSessionId id, {
          required void Function() onChanged,
          required void Function() onTerminated,
        }) {
          final _FakePaneSession session = _FakePaneSession(
            id: id,
            onChanged: onChanged,
            onTerminated: onTerminated,
          );
          sessions.add(session);
          return session;
        },
    onChanged: () {
      ++changed;
    },
    onExitRequested: () {
      ++exitRequests;
    },
    lifecycleObserver: paneLifecycle.add,
    exitObserver: paneExits.add,
  );

  final TerminalPane first = createPane();
  final TerminalPane second = createPane();
  _expect(first.id == const PaneId(41), 'first monotonic pane ID');
  _expect(second.id == const PaneId(42), 'second monotonic pane ID');
  _expect(first.id != second.id, 'pane IDs are unique');
  _expect(
    first.sessionId ==
        const TerminalSessionId(paneId: PaneId(41), generation: 1),
    'session identity binds pane and generation',
  );
  _expect(owner.livePaneCount == 2, 'owner retains created panes');

  final Future<void> firstStart = first.start();
  _expect(identical(firstStart, first.start()), 'pane start is idempotent');
  await firstStart;
  _expect(first.state == TerminalPaneState.running, 'pane reaches running');
  _expect(
    sessions.first.startCount == 1,
    'owner starts one session generation',
  );

  _expect(
    first.requestClose() == TerminalPaneCloseDecision.confirmationRequired &&
        first.state == TerminalPaneState.confirmationPending &&
        sessions.first.confirmationCount == 1,
    'first live close requires confirmation',
  );
  first.insertText('x');
  _expect(
    first.state == TerminalPaneState.running &&
        sessions.first.insertedText.single == 'x',
    'terminal interaction cancels close confirmation',
  );
  _expect(
    first.requestClose() == TerminalPaneCloseDecision.confirmationRequired,
    'close after interaction requires confirmation again',
  );
  _expect(
    first.requestClose() == TerminalPaneCloseDecision.allow &&
        first.state == TerminalPaneState.closing,
    'second consecutive close is allowed',
  );
  await owner.disposePane(first);
  await owner
      .disposePane(first)
      .then<void>(
        (_) => throw StateError('removed pane disposal unexpectedly succeeded'),
        onError: (Object error) {
          _expect(error is StateError, 'removed pane is rejected by owner');
        },
      );
  _expect(
    sessions.first.disposeCount == 1 &&
        first.state == TerminalPaneState.closed &&
        owner.livePaneCount == 1,
    'pane disposal is owned and idempotent',
  );

  await second.start();
  sessions[1].finish();
  _expect(
    second.state == TerminalPaneState.exited && exitRequests == 1,
    'natural session exit updates pane before requesting window close',
  );
  _expect(
    second.requestClose() == TerminalPaneCloseDecision.allow,
    'exited pane closes without confirmation',
  );

  final TerminalPane abnormal = createPane();
  await abnormal.start();
  sessions[2].finish(disposition: TerminalPaneSessionExitDisposition.nonZero);
  _expect(
    abnormal.state == TerminalPaneState.exited && exitRequests == 1,
    'nonzero shell exit retains its pane without requesting window close',
  );
  _expect(
    abnormal.requestClose() == TerminalPaneCloseDecision.allow,
    'retained non-live pane closes without confirmation',
  );

  final TerminalPane failed = createPane();
  sessions[3].failStart = true;
  try {
    await failed.start();
    throw StateError('failing pane session unexpectedly started');
  } on StateError catch (error) {
    _expect(
      error.message == 'requested fake start failure',
      'start failure remains observable',
    );
  }
  _expect(
    failed.state == TerminalPaneState.failed &&
        failed.requestClose() == TerminalPaneCloseDecision.allow,
    'failed pane closes without confirmation',
  );
  sessions[3].failShutdown = true;
  final Future<TerminalPaneOwnerShutdownResult> ownerShutdown = owner
      .shutdown();
  _expect(
    identical(ownerShutdown, owner.shutdown()),
    'pane owner shutdown returns one cached future',
  );
  final TerminalPaneOwnerShutdownResult ownerResult = await ownerShutdown;
  await owner.dispose();
  _expect(
    owner.livePaneCount == 0 &&
        sessions[1].disposeCount == 1 &&
        sessions[2].disposeCount == 1 &&
        sessions[3].disposeCount == 1,
    'owner teardown reaches zero panes exactly once',
  );
  _expect(
    ownerResult.disposition == TerminalSessionShutdownDisposition.failed &&
        ownerResult.sessions.length == 3 &&
        failed.state == TerminalPaneState.closed &&
        identical(owner.shutdownResult, ownerResult),
    'owner contains a session shutdown failure and publishes its aggregate',
  );
  final TerminalPaneSessionShutdownResult failedResult = ownerResult.sessions
      .singleWhere(
        (TerminalPaneSessionShutdownResult result) =>
            result.sessionId == failed.sessionId,
      );
  _expect(
    !failedResult.terminationObserved &&
        !failedResult.cleanupCompleted &&
        failedResult.machineLine() ==
            'TERMINAL_SESSION_SHUTDOWN pane=44 session=44:1 process_id=0 '
                'disposition=failed termination_observed=false '
                'cleanup_completed=false' &&
        ownerResult.machineLine() ==
            'TERMINAL_PANE_OWNER_SHUTDOWN pane_count=3 disposition=failed',
    'shutdown summaries use exact privacy-safe typed fields',
  );
  _expect(changed > 0, 'pane lifecycle emits view changes');
  _expect(
    paneLifecycle
            .where(
              (TerminalPaneLifecycleObservation observation) =>
                  observation.paneId == first.id,
            )
            .map(
              (TerminalPaneLifecycleObservation observation) =>
                  observation.state,
            )
            .join(',') ==
        <TerminalPaneState>[
          TerminalPaneState.created,
          TerminalPaneState.starting,
          TerminalPaneState.running,
          TerminalPaneState.confirmationPending,
          TerminalPaneState.running,
          TerminalPaneState.confirmationPending,
          TerminalPaneState.closing,
          TerminalPaneState.closed,
        ].join(','),
    'pane diagnostics preserve the complete first-pane state order',
  );
  _expect(
    paneLifecycle.first.machineLine() ==
        'TERMINAL_PANE_LIFECYCLE pane=41 session=41:1 state=created',
    'pane diagnostic machine line contains only stable lifecycle metadata',
  );
  _expect(
    paneExits.length == 2 &&
        paneExits[0].machineLine() ==
            'TERMINAL_PANE_EXIT pane=42 session=42:1 '
                'disposition=clean action=close' &&
        paneExits[1].machineLine() ==
            'TERMINAL_PANE_EXIT pane=43 session=43:1 '
                'disposition=nonZero action=retain',
    'shell exit policy publishes exact content-free close/retain decisions',
  );
  _expectThrows(
    createPane,
    'disposed owner refuses new pane publication',
    expectedType: StateError,
  );
}

void _testEditing() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('helo');
  buffer.moveLeft();
  buffer.insert('l');
  _expect(buffer.input == 'hello', 'insertion at cursor');
  buffer.deleteBackward();
  _expect(buffer.input == 'helo', 'backspace');
  buffer.deleteForward();
  _expect(buffer.input == 'hel', 'forward delete');
  buffer.moveToStart();
  buffer.insert('s');
  buffer.moveToEnd();
  _expect(buffer.input == 'shel', 'home/end movement');
}

void _testUnicodeEditing() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('A😀B');
  buffer.moveLeft();
  buffer.deleteBackward();
  _expect(buffer.input == 'AB', 'editing uses Unicode scalar values');
}

void _testHistoryNavigation() {
  final TerminalBuffer buffer = TerminalBuffer();
  buffer.insert('pwd');
  _expect(buffer.takeInput() == 'pwd', 'take first command');
  buffer.insert('ls -la');
  _expect(buffer.takeInput() == 'ls -la', 'take second command');
  buffer.insert('draft');
  buffer.previousHistory();
  _expect(buffer.input == 'ls -la', 'latest history item');
  buffer.previousHistory();
  _expect(buffer.input == 'pwd', 'older history item');
  buffer.nextHistory();
  _expect(buffer.input == 'ls -la', 'newer history item');
  buffer.nextHistory();
  _expect(buffer.input == 'draft', 'history restores draft');
}

void _testTranscriptLimitAndViewport() {
  final TerminalBuffer buffer = TerminalBuffer(maxTranscriptLines: 3);
  buffer.appendLines(<String>['one', 'two', 'three', 'four']);
  _expect(
    buffer.transcript.join(',') == 'two,three,four',
    'scrollback line limit',
  );
  buffer.insert('echo hi');
  final String rendered = buffer.render(prompt: '% ', rows: 2, isBusy: false);
  _expect(rendered == 'four\n% echo hi▌', 'viewport keeps newest rows');

  final TerminalBuffer output = TerminalBuffer(maxTranscriptLines: 3);
  output.appendOutput('one\r\ntw');
  output.appendOutput('o\b');
  output.appendOutput('o\rreplace\npartial');
  _expect(
    output.outputText == 'one\nreplace\npartial',
    'PTY projection preserves split lines and applies CR/backspace',
  );
  _expect(
    output.renderOutput(rows: 2) == 'replace\npartial',
    'PTY projection keeps the newest visible rows',
  );
}

void _testOptions() {
  final TerminalOptions options = _parseOptions(<String>[
    '--working-directory=/tmp',
    '--auto-close-after=3',
  ]);
  _expect(
    options.initialWorkingDirectory == '/tmp',
    'working directory option',
  );
  _expect(
    options.autoCloseAfter == const Duration(seconds: 3),
    'auto-close option',
  );
  _expect(!options.runtimeResourceStress, 'resource stress defaults off');
  _expect(
    !options.runtimeShutdownFaultInjection,
    'shutdown fault injection defaults off',
  );
  _expect(
    !options.runtimePtyExitFaultInjection,
    'PTY exit fault injection defaults off',
  );
  _expect(
    !options.runtimeTerminalDisplayTest,
    'terminal display test defaults off',
  );
  _expect(
    options.runtimeShellExitTestScenario == RuntimeShellExitTestScenario.none,
    'shell exit policy test defaults off',
  );
  _expect(
    options.runtimeWorkerCommand.executable == '/usr/bin/true' &&
        options.runtimeWorkerCommand.arguments.isEmpty,
    'declarative bundled worker command',
  );
  final TerminalOptions faultOptions = _parseOptions(
    const <String>['--runtime-lifecycle-scenario=worker-sync-uncaught'],
    environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
  );
  _expect(
    faultOptions.runtimeLifecycleScenario ==
        RuntimeLifecycleScenario.workerSyncUncaught,
    'gated lifecycle scenario option',
  );
  final TerminalOptions resourceOptions = _parseOptions(
    const <String>['--runtime-resource-stress'],
    environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
  );
  _expect(resourceOptions.runtimeResourceStress, 'gated resource stress');
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-resource-stress',
    ], environment: const <String, String>{}),
    'resource stress gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>['--runtime-resource-stress', '--runtime-resource-stress'],
      environment: const <String, String>{'DT_RUNTIME_RESOURCE_TEST': '1'},
    ),
    'duplicate resource stress option',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-resource-stress',
        '--runtime-lifecycle-scenario=worker-sync-uncaught',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_RESOURCE_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'resource stress and lifecycle fault are mutually exclusive',
  );
  final TerminalOptions shutdownFaultOptions = _parseOptions(
    const <String>[
      '--runtime-shutdown-faults',
      '--runtime-lifecycle-scenario=worker-unexpected-exit',
    ],
    environment: const <String, String>{
      'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      'DT_RUNTIME_LIFECYCLE_TEST': '1',
    },
  );
  _expect(
    shutdownFaultOptions.runtimeShutdownFaultInjection,
    'gated shutdown fault injection',
  );
  final TerminalOptions ptyExitFaultOptions = _parseOptions(
    const <String>['--runtime-pty-exit-fault', '--auto-close-after=1'],
    environment: const <String, String>{
      'DT_RUNTIME_PTY_SHUTDOWN_FAULT_TEST': '1',
    },
  );
  _expect(
    ptyExitFaultOptions.runtimePtyExitFaultInjection,
    'gated PTY exit fault injection',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-pty-exit-fault',
    ], environment: const <String, String>{}),
    'PTY exit fault gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>['--runtime-pty-exit-fault', '--runtime-pty-exit-fault'],
      environment: const <String, String>{
        'DT_RUNTIME_PTY_SHUTDOWN_FAULT_TEST': '1',
      },
    ),
    'duplicate PTY exit fault option',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-pty-exit-fault',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_PTY_SHUTDOWN_FAULT_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'PTY exit fault and lifecycle fault are mutually exclusive',
  );
  final TerminalOptions shellExitTestOptions = _parseOptions(
    const <String>['--runtime-shell-exit-test=clean-control-d'],
    environment: const <String, String>{'DT_RUNTIME_SHELL_EXIT_TEST': '1'},
  );
  _expect(
    shellExitTestOptions.runtimeShellExitTestScenario ==
        RuntimeShellExitTestScenario.cleanControlD,
    'gated clean Control-D shell exit test',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-shell-exit-test=nonzero',
    ], environment: const <String, String>{}),
    'shell exit policy test gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shell-exit-test=clean-control-d',
        '--runtime-shell-exit-test=nonzero',
      ],
      environment: const <String, String>{'DT_RUNTIME_SHELL_EXIT_TEST': '1'},
    ),
    'duplicate shell exit policy test option',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shell-exit-test=clean-control-d',
        '--auto-close-after=1',
      ],
      environment: const <String, String>{'DT_RUNTIME_SHELL_EXIT_TEST': '1'},
    ),
    'shell exit policy test and automatic close are mutually exclusive',
  );
  final TerminalOptions terminalDisplayTestOptions = _parseOptions(
    const <String>['--runtime-terminal-display-test'],
    environment: const <String, String>{
      'DT_RUNTIME_TERMINAL_DISPLAY_TEST': '1',
    },
  );
  _expect(
    terminalDisplayTestOptions.runtimeTerminalDisplayTest,
    'gated terminal display test',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-terminal-display-test',
    ], environment: const <String, String>{}),
    'terminal display test gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-terminal-display-test',
        '--runtime-terminal-display-test',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_TERMINAL_DISPLAY_TEST': '1',
      },
    ),
    'duplicate terminal display test option',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-terminal-display-test',
        '--runtime-shell-exit-test=clean-control-d',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_TERMINAL_DISPLAY_TEST': '1',
        'DT_RUNTIME_SHELL_EXIT_TEST': '1',
      },
    ),
    'terminal display and shell exit tests are mutually exclusive',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ],
      environment: const <String, String>{'DT_RUNTIME_LIFECYCLE_TEST': '1'},
    ),
    'shutdown fault gate',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>['--runtime-shutdown-faults'],
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
      },
    ),
    'shutdown faults require the worker crash scenario',
  );
  _expectThrows(
    () => _parseOptions(
      const <String>[
        '--runtime-shutdown-faults',
        '--runtime-shutdown-faults',
        '--runtime-lifecycle-scenario=worker-unexpected-exit',
      ],
      environment: const <String, String>{
        'DT_RUNTIME_SHUTDOWN_FAULT_TEST': '1',
        'DT_RUNTIME_LIFECYCLE_TEST': '1',
      },
    ),
    'duplicate shutdown fault option',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-lifecycle-scenario=worker-sync-uncaught',
    ], environment: const <String, String>{}),
    'lifecycle scenario gate',
  );
  _expectThrows(
    () => _parseOptions(const <String>['--unknown']),
    'unknown option',
  );
  _expectThrows(
    () => _parseOptions(const <String>[
      '--runtime-worker-executable=relative/dart',
    ]),
    'internal worker configuration is not an application option',
  );
}

TerminalOptions _parseOptions(
  List<String> arguments, {
  Map<String, String>? environment,
}) => TerminalOptions.parse(
  arguments,
  environment: environment,
  runtimeWorkerCommand: const RuntimeLifecycleWorkerCommand(
    executable: '/usr/bin/true',
  ),
);

Future<void> _testPersistentCommandSession() async {
  var changeCount = 0;
  var terminationCount = 0;
  final List<TerminalSessionLifecycleObservation> lifecycle =
      <TerminalSessionLifecycleObservation>[];
  final FakePtyBackend ptyBackend = FakePtyBackend(autoExitOnClose: false);
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(7), generation: 3),
    ptyBackend: ptyBackend,
    initialWorkingDirectory: Directory.systemTemp.path,
    onChanged: () {
      ++changeCount;
    },
    onTerminated: () {
      ++terminationCount;
    },
    lifecycleObserver: lifecycle.add,
  );
  final Future<void> start = session.start();
  _expect(identical(start, session.start()), 'session start is idempotent');
  await start;
  _expect(session.isLive, 'persistent shell is live after start');
  _expect(
    ptyBackend.commands.length == 1 &&
        ptyBackend.commands.single.executable == '/bin/zsh' &&
        ptyBackend.commands.single.arguments.isEmpty &&
        ptyBackend.commands.single.loginShell,
    'one login shell is created for the session generation',
  );
  final FakePtyProcess process = ptyBackend.processes.single;
  final int processId = session.processId!;

  session.insertText("printf 'shell-ok\\n'");
  await session.submit();
  session.insertText("printf 'second-command\\n'");
  await session.submit();
  session.resize(rows: 40, columns: 120);
  session.deleteBackward();
  session.deleteForward();
  session.moveLeft();
  session.moveRight();
  session.previousHistory();
  session.nextHistory();
  session.moveToStart();
  session.moveToEnd();
  session.sendEndOfFile();
  session.interrupt();
  session.suspend();
  session.quitForegroundProcess();
  process.emitOutput(<int>[0xe2]);
  process.emitOutput(<int>[0x82, 0xac, 0x0d, 0x0a]);
  session.showCloseConfirmation();
  _expect(
    ptyBackend.processes.length == 1 && session.processId == processId,
    'multiple commands retain the same PTY process',
  );
  _expect(
    utf8.decode(process.writes[0]) == "printf 'shell-ok\\n'" &&
        process.writes[1].single == 0x0d &&
        utf8.decode(process.writes[2]) == "printf 'second-command\\n'" &&
        process.writes[3].single == 0x0d,
    'commands are written to the persistent shell instead of spawning',
  );
  _expect(
    process.sizes.last.rows == 40 && process.sizes.last.columns == 120,
    'active PTY tracks terminal size',
  );
  _expect(
    process.signals.join(',') ==
        <PtySignal>[
          PtySignal.interrupt,
          PtySignal.suspend,
          PtySignal.quit,
        ].join(','),
    'foreground control signals use the PTY process group',
  );
  _expect(
    session.buffer.outputText.contains('€') &&
        session.buffer.outputText.contains('repeat Close or Quit'),
    'split UTF-8 output and close notice reach the projection',
  );
  process.finish(exitCode: 0);
  await session.waitForTermination();
  _expect(!session.isLive && terminationCount == 1, 'shell exit is observed');
  _expect(changeCount > 0, 'session emits view updates');
  await session.dispose();
  await session.dispose();
  _expectOrderedSessionStages(lifecycle, <TerminalSessionLifecycleStage>[
    TerminalSessionLifecycleStage.startRequested,
    TerminalSessionLifecycleStage.processStarted,
    TerminalSessionLifecycleStage.eofRequested,
    TerminalSessionLifecycleStage.eofWriteAccepted,
    TerminalSessionLifecycleStage.nativeExitObserved,
    TerminalSessionLifecycleStage.outputDrainStarted,
    TerminalSessionLifecycleStage.outputDrained,
    TerminalSessionLifecycleStage.terminationCompleted,
    TerminalSessionLifecycleStage.ownerTerminationNotified,
    TerminalSessionLifecycleStage.disposeStarted,
    TerminalSessionLifecycleStage.gracefulCloseRequested,
    TerminalSessionLifecycleStage.terminationWaitCompleted,
    TerminalSessionLifecycleStage.outputCancellationStarted,
    TerminalSessionLifecycleStage.outputCancellationCompleted,
    TerminalSessionLifecycleStage.processDisposeStarted,
    TerminalSessionLifecycleStage.processDisposeCompleted,
    TerminalSessionLifecycleStage.shutdownResultPublished,
    TerminalSessionLifecycleStage.disposeCompleted,
  ], 'session lifecycle diagnostics');
  _expect(
    lifecycle.first.machineLine() ==
        'TERMINAL_PTY_LIFECYCLE pane=7 session=7:3 process_id=0 '
            'stage=startRequested',
    'PTY diagnostic machine line contains only stable lifecycle metadata',
  );

  final FakePtyBackend boundedBackend = FakePtyBackend();
  final TerminalSession bounded = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(9), generation: 1),
    ptyBackend: boundedBackend,
    writeCapacityBytes: 2,
    onChanged: () {},
    onTerminated: () {},
  );
  await bounded.start();
  bounded.insertText('three bytes');
  _expect(
    bounded.writeBackpressureCount == 1 &&
        bounded.buffer.outputText.contains('input is backpressured') &&
        boundedBackend.processes.single.writes.isEmpty,
    'rejected input is surfaced without an unbounded retry queue',
  );
  bounded.insertText('x');
  _expect(
    utf8.decode(boundedBackend.processes.single.writes.single) == 'x',
    'session accepts later input after a bounded rejection',
  );
  await bounded.dispose();
  await bounded.dispose();
  _expect(
    boundedBackend.processes.single.closeGracePeriods.length == 1,
    'active persistent process is closed exactly once',
  );
}

Future<void> _testBoundedSessionShutdown() async {
  final List<TerminalSessionLifecycleObservation> forcedLifecycle =
      <TerminalSessionLifecycleObservation>[];
  final FakePtyBackend forcedBackend = FakePtyBackend(autoExitOnClose: false);
  final TerminalSession forced = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(10), generation: 1),
    ptyBackend: forcedBackend,
    gracefulShutdownTimeout: const Duration(milliseconds: 10),
    finalShutdownTimeout: const Duration(milliseconds: 200),
    cleanupStepTimeout: const Duration(milliseconds: 200),
    onChanged: () {},
    onTerminated: () {},
    lifecycleObserver: forcedLifecycle.add,
  );
  await forced.start();
  final Future<TerminalSessionShutdownResult> forcedShutdown = forced
      .shutdown();
  _expect(
    identical(forcedShutdown, forced.shutdown()),
    'session shutdown returns one cached future',
  );
  final TerminalSessionShutdownResult forcedResult = await forcedShutdown
      .timeout(const Duration(seconds: 1));
  _expect(
    identical(forced.shutdownResult, forcedResult) &&
        forcedResult.disposition == TerminalSessionShutdownDisposition.forced &&
        forcedResult.terminationObserved &&
        forcedResult.cleanupCompleted &&
        forcedResult.exit?.signal == 9 &&
        forced.exitDisposition == TerminalPaneSessionExitDisposition.signaled,
    'forced shutdown publishes an observed and completely cleaned result',
  );
  _expect(
    forcedBackend.processes.single.closeGracePeriods.length == 1 &&
        forcedBackend.processes.single.forceCloseRequests == 1,
    'graceful timeout escalates exactly once through force close',
  );
  _expectOrderedSessionStages(forcedLifecycle, <TerminalSessionLifecycleStage>[
    TerminalSessionLifecycleStage.disposeStarted,
    TerminalSessionLifecycleStage.gracefulCloseRequested,
    TerminalSessionLifecycleStage.terminationWaitTimedOut,
    TerminalSessionLifecycleStage.forceCloseRequested,
    TerminalSessionLifecycleStage.nativeExitObserved,
    TerminalSessionLifecycleStage.outputDrained,
    TerminalSessionLifecycleStage.finalTerminationWaitCompleted,
    TerminalSessionLifecycleStage.processDisposeCompleted,
    TerminalSessionLifecycleStage.shutdownResultPublished,
    TerminalSessionLifecycleStage.disposeCompleted,
  ], 'forced session shutdown');
  await forced.dispose().timeout(const Duration(milliseconds: 100));

  final List<TerminalSessionLifecycleObservation> missingLifecycle =
      <TerminalSessionLifecycleObservation>[];
  final FakePtyBackend missingBackend = FakePtyBackend(
    autoExitOnClose: false,
    autoExitOnForceClose: false,
  );
  final TerminalSession missing = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(11), generation: 1),
    ptyBackend: missingBackend,
    gracefulShutdownTimeout: const Duration(milliseconds: 10),
    finalShutdownTimeout: const Duration(milliseconds: 10),
    cleanupStepTimeout: const Duration(milliseconds: 100),
    onChanged: () {},
    onTerminated: () {},
    lifecycleObserver: missingLifecycle.add,
  );
  await missing.start();
  final Stopwatch missingElapsed = Stopwatch()..start();
  final TerminalSessionShutdownResult missingResult = await missing
      .shutdown()
      .timeout(const Duration(seconds: 1));
  missingElapsed.stop();
  final FakePtyProcess missingProcess = missingBackend.processes.single;
  _expect(
    missingResult.disposition ==
            TerminalSessionShutdownDisposition.deadlineExceeded &&
        !missingResult.terminationObserved &&
        !missingResult.cleanupCompleted &&
        missingResult.exit == null &&
        identical(missing.shutdownResult, missingResult),
    'missing exit remains explicitly unreaped after the final deadline',
  );
  _expect(
    missingElapsed.elapsed < const Duration(milliseconds: 500),
    'missing exit cannot retain session teardown indefinitely',
  );
  _expect(
    missingProcess.closeGracePeriods.length == 1 &&
        missingProcess.forceCloseRequests == 1 &&
        missingProcess.finalStats == null,
    'deadline path requests force close and skips exit-waiting process dispose',
  );
  await missing.waitForTermination().timeout(const Duration(milliseconds: 100));
  await missing.dispose().timeout(const Duration(milliseconds: 100));
  _expectOrderedSessionStages(missingLifecycle, <TerminalSessionLifecycleStage>[
    TerminalSessionLifecycleStage.disposeStarted,
    TerminalSessionLifecycleStage.gracefulCloseRequested,
    TerminalSessionLifecycleStage.terminationWaitTimedOut,
    TerminalSessionLifecycleStage.forceCloseRequested,
    TerminalSessionLifecycleStage.finalDeadlineExceeded,
    TerminalSessionLifecycleStage.outputCancellationStarted,
    TerminalSessionLifecycleStage.outputCancellationCompleted,
    TerminalSessionLifecycleStage.processDisposeSkipped,
    TerminalSessionLifecycleStage.terminationCompleted,
    TerminalSessionLifecycleStage.shutdownResultPublished,
    TerminalSessionLifecycleStage.disposeCompleted,
  ], 'missing-exit session shutdown');

  _expectThrows(
    () => TerminalSession(
      id: const TerminalSessionId(paneId: PaneId(12), generation: 1),
      gracefulShutdownTimeout: Duration.zero,
      onChanged: () {},
      onTerminated: () {},
    ),
    'non-positive session shutdown timeout',
    expectedType: ArgumentError,
  );
}

Future<void> _testRealPersistentPtySession() async {
  var terminated = false;
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(8), generation: 1),
    initialWorkingDirectory: Directory.systemTemp.path,
    environment: <String, String>{
      'PATH': '/usr/bin:/bin',
      'HOME': Directory.systemTemp.path,
      'TERM': 'dumb',
      'LC_ALL': 'C',
    },
    shellArguments: const <String>['-f'],
    onChanged: () {},
    onTerminated: () {
      terminated = true;
    },
  );
  session.resize(rows: 37, columns: 111);
  await session.start().timeout(const Duration(seconds: 5));
  final int processId = session.processId!;
  session.insertText("stty -echo; printf '__SHELL_READY__\\n'");
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => _occurrences(output, '__SHELL_READY__') >= 2,
    'interactive shell startup',
  );
  session.insertText(
    "stty raw -echo; printf '\\033[5n'; "
    "dd bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \\n'; "
    "stty sane -echo; printf '__QUERY_REPLY_DONE__\\n'",
  );
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => output.contains('__QUERY_REPLY_DONE__'),
    'terminal query reply round trip',
  );
  session.insertText(
    "printf '__DART_TERMINAL_PTY__\\n'; tty; stty size; "
    "printf '__FIRST_COMMAND_DONE__\\n'",
  );
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => output.contains('__FIRST_COMMAND_DONE__'),
    'first persistent-shell command',
  );
  session.insertText("sleep 5 & jobs; printf '__JOB_READY__\\n'");
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => output.contains('__JOB_READY__'),
    'background job listing',
  );
  session.insertText('fg');
  await session.submit();
  await Future<void>.delayed(const Duration(milliseconds: 150));
  session.interrupt();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  session.insertText("printf '__AFTER_INTERRUPT__\\n'; exit");
  await session.submit();
  await session.waitForTermination().timeout(const Duration(seconds: 8));
  final String output = session.buffer.outputText;
  _expect(
    output.contains('1b5b306e'),
    'real PTY child reads the exact terminal status reply',
  );
  _expect(
    output.contains('__DART_TERMINAL_PTY__') &&
        output.contains('__FIRST_COMMAND_DONE__') &&
        output.contains('__JOB_READY__') &&
        output.toLowerCase().contains('running') &&
        output.contains('__AFTER_INTERRUPT__'),
    'multiple real commands use the persistent session',
  );
  _expect(
    output.contains('/dev/tty') && output.contains('37 111'),
    'real shell has a PTY and observes the initial window size',
  );
  _expect(
    session.processId == processId &&
        session.exit?.exitCode == 0 &&
        session.exitDisposition == TerminalPaneSessionExitDisposition.clean &&
        terminated,
    'real login shell exits and is reaped once',
  );
  await session.dispose();
}

Future<void> _testRepeatedControlDNaturalExit() async {
  const int repetitions = 24;
  _expect(_livePtySessionCount() == 0, 'Control-D test starts without PTYs');
  final Process competingDartChild = await Process.start(
    '/bin/sleep',
    const <String>['60'],
  );
  try {
    for (var iteration = 0; iteration < repetitions; ++iteration) {
      var terminationCount = 0;
      final List<TerminalSessionLifecycleObservation> lifecycle =
          <TerminalSessionLifecycleObservation>[];
      final List<TerminalSessionNativeObservation> native =
          <TerminalSessionNativeObservation>[];
      final TerminalSession session = TerminalSession(
        id: TerminalSessionId(paneId: PaneId(1000 + iteration), generation: 1),
        initialWorkingDirectory: Directory.systemTemp.path,
        environment: <String, String>{
          'PATH': '/usr/bin:/bin',
          'HOME': Directory.systemTemp.path,
          'TERM': 'dumb',
          'LC_ALL': 'C',
          'PS1': '__CTRL_D_PROMPT_${iteration}__ ',
          'RPS1': '',
        },
        shellArguments: const <String>['-f'],
        onChanged: () {},
        onTerminated: () {
          ++terminationCount;
        },
        lifecycleObserver: lifecycle.add,
        nativeObserver: native.add,
      );
      await session.start().timeout(const Duration(seconds: 3));
      final int processId = session.processId!;
      session.insertText(
        "stty -echo; unsetopt ignoreeof; printf '__CTRL_D_READY_${iteration}__\\n'",
      );
      await session.submit();
      await _waitForTerminalOutput(
        session,
        (String output) =>
            _occurrences(output, '__CTRL_D_READY_${iteration}__') >= 2,
        'Control-D ready marker for iteration $iteration',
      );
      session.sendEndOfFile();
      await session.waitForTermination().timeout(const Duration(seconds: 3));
      _expect(
        session.exit?.exitCode == 0 &&
            session.exit?.signal == null &&
            terminationCount == 1,
        'Control-D iteration $iteration exits and notifies exactly once',
      );
      await session.dispose().timeout(const Duration(seconds: 1));
      _expectOrderedSessionStages(lifecycle, <TerminalSessionLifecycleStage>[
        TerminalSessionLifecycleStage.processStarted,
        TerminalSessionLifecycleStage.eofRequested,
        TerminalSessionLifecycleStage.eofWriteAccepted,
        TerminalSessionLifecycleStage.nativeExitObserved,
        TerminalSessionLifecycleStage.outputDrained,
        TerminalSessionLifecycleStage.terminationCompleted,
        TerminalSessionLifecycleStage.ownerTerminationNotified,
        TerminalSessionLifecycleStage.disposeStarted,
        TerminalSessionLifecycleStage.terminationWaitCompleted,
        TerminalSessionLifecycleStage.processDisposeStarted,
        TerminalSessionLifecycleStage.processDisposeCompleted,
        TerminalSessionLifecycleStage.shutdownResultPublished,
        TerminalSessionLifecycleStage.disposeCompleted,
      ], 'Control-D lifecycle iteration $iteration');
      final int? requestId = lifecycle
          .where(
            (TerminalSessionLifecycleObservation observation) =>
                observation.stage ==
                TerminalSessionLifecycleStage.eofWriteAccepted,
          )
          .single
          .writeRequestId;
      _expect(requestId != null, 'Control-D iteration $iteration request ID');
      for (final PtyDiagnosticStage stage in <PtyDiagnosticStage>[
        PtyDiagnosticStage.writeEnqueued,
        PtyDiagnosticStage.writeDequeued,
        PtyDiagnosticStage.writeCompleted,
        PtyDiagnosticStage.stateSnapshot,
        PtyDiagnosticStage.termiosSnapshot,
        PtyDiagnosticStage.processExitReady,
        PtyDiagnosticStage.waitpidResult,
        PtyDiagnosticStage.exitPublished,
      ]) {
        _expect(
          native.any(
            (TerminalSessionNativeObservation observation) =>
                observation.event.stage == stage &&
                (observation.event.requestId == null ||
                    observation.event.requestId == requestId),
          ),
          'Control-D iteration $iteration native ${stage.name}',
        );
      }
      _expect(
        native.any(
          (TerminalSessionNativeObservation observation) =>
              observation.event.stage == PtyDiagnosticStage.writeCompleted &&
              observation.event.requestId == requestId &&
              observation.event.byteCount == 1 &&
              observation.event.queuedBytes == 0,
        ),
        'Control-D iteration $iteration is flushed exactly once',
      );
      final bool ptyOwnedReap = native.any(
        (TerminalSessionNativeObservation observation) =>
            observation.event.stage == PtyDiagnosticStage.waitpidResult &&
            observation.event.waitpidResult == processId,
      );
      final bool externalReap = native.any(
        (TerminalSessionNativeObservation observation) =>
            observation.event.stage ==
                PtyDiagnosticStage.externalReapObserved &&
            observation.event.childProcessId == processId &&
            observation.event.childStatus == 0,
      );
      _expect(
        ptyOwnedReap || externalReap,
        'Control-D iteration $iteration classifies the child reap owner before '
        'exit publication',
      );
      _expect(
        _livePtySessionCount() == 0,
        'Control-D iteration $iteration reaps and destroys its native session',
      );
    }
  } finally {
    competingDartChild.kill(ProcessSignal.sigterm);
    try {
      await competingDartChild.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      competingDartChild.kill(ProcessSignal.sigkill);
      await competingDartChild.exitCode;
    }
  }
}

Future<void> _testControlDSemanticsMatrix() async {
  _expect(_livePtySessionCount() == 0, 'Control-D matrix starts without PTYs');

  final _ControlDProbe ignoreEof = await _startControlDProbe(
    2101,
    'setopt ignoreeof',
  );
  try {
    await _sendAndObserveControlD(ignoreEof, 'IGNORE_EOF');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _expect(
      ignoreEof.session.isLive,
      'IGNORE_EOF intentionally keeps zsh live',
    );
    ignoreEof.session.insertText('unsetopt ignoreeof; exit');
    await ignoreEof.session.submit();
  } finally {
    await _finishControlDProbe(ignoreEof);
  }

  final _ControlDProbe nonempty = await _startControlDProbe(
    2102,
    'unsetopt ignoreeof',
  );
  try {
    nonempty.session.insertText('not-submitted');
    await _sendAndObserveControlD(nonempty, 'nonempty edit buffer');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _expect(
      nonempty.session.isLive,
      'Control-D on a nonempty zsh edit buffer is not shell EOF',
    );
    nonempty.session.interrupt();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    nonempty.session.insertText('exit');
    await nonempty.session.submit();
  } finally {
    await _finishControlDProbe(nonempty);
  }

  final _ControlDProbe foregroundReader = await _startControlDProbe(
    2103,
    'unsetopt ignoreeof; precmd() { print -r -- __CD_PROMPT_2103__; }',
  );
  try {
    final int promptCount = _occurrences(
      foregroundReader.session.buffer.outputText,
      '__CD_PROMPT_2103__',
    );
    foregroundReader.session.insertText('cat');
    await foregroundReader.session.submit();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _sendAndObserveControlD(foregroundReader, 'foreground reader');
    await _waitForTerminalOutput(
      foregroundReader.session,
      (String output) =>
          _occurrences(output, '__CD_PROMPT_2103__') > promptCount,
      'foreground reader returning to zsh after Control-D',
    );
    _expect(
      foregroundReader.session.isLive,
      'foreground reader consumes EOF without exiting its owning shell',
    );
    foregroundReader.session.insertText('exit');
    await foregroundReader.session.submit();
  } finally {
    await _finishControlDProbe(foregroundReader);
  }

  final _ControlDProbe rawMode = await _startControlDProbe(
    2104,
    'unsetopt ignoreeof',
  );
  try {
    rawMode.session.insertText(
      'saved=\$(stty -g); print -r -- __CD_RAW_READY__; '
      'stty raw -echo; dd bs=1 count=1 of=/dev/null 2>/dev/null; '
      'stty "\$saved"; print -r -- __CD_RAW_DONE__',
    );
    await rawMode.session.submit();
    await _waitForTerminalOutput(
      rawMode.session,
      (String output) => output.contains('__CD_RAW_READY__'),
      'raw-mode reader readiness',
    );
    await _sendAndObserveControlD(rawMode, 'raw terminal mode');
    await _waitForTerminalOutput(
      rawMode.session,
      (String output) => output.contains('__CD_RAW_DONE__'),
      'raw-mode reader consuming Control-D as data',
    );
    _expect(
      rawMode.session.isLive,
      'raw-mode Control-D is data and does not exit zsh',
    );
    rawMode.session.insertText('exit');
    await rawMode.session.submit();
  } finally {
    await _finishControlDProbe(rawMode);
  }

  final _ControlDProbe suspendedJob = await _startControlDProbe(
    2105,
    'unsetopt ignoreeof; precmd() { print -r -- __CD_PROMPT_2105__; }',
  );
  try {
    final int promptCount = _occurrences(
      suspendedJob.session.buffer.outputText,
      '__CD_PROMPT_2105__',
    );
    suspendedJob.session.insertText('cat');
    await suspendedJob.session.submit();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    suspendedJob.session.suspend();
    await _waitForTerminalOutput(
      suspendedJob.session,
      (String output) =>
          _occurrences(output, '__CD_PROMPT_2105__') > promptCount,
      'suspended foreground job returning to zsh',
    );
    await _sendAndObserveControlD(suspendedJob, 'suspended job');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _expect(
      suspendedJob.session.isLive,
      'zsh refuses the first EOF while a stopped job exists',
    );
    suspendedJob.session.insertText(
      'kill %1 2>/dev/null; wait %1 2>/dev/null; exit',
    );
    await suspendedJob.session.submit();
  } finally {
    await _finishControlDProbe(suspendedJob);
  }

  _expect(_livePtySessionCount() == 0, 'Control-D matrix reaps every PTY');
}

Future<_ControlDProbe> _startControlDProbe(int paneId, String setup) async {
  final List<TerminalSessionLifecycleObservation> lifecycle =
      <TerminalSessionLifecycleObservation>[];
  final List<TerminalSessionNativeObservation> native =
      <TerminalSessionNativeObservation>[];
  final TerminalSession session = TerminalSession(
    id: TerminalSessionId(paneId: PaneId(paneId), generation: 1),
    initialWorkingDirectory: Directory.systemTemp.path,
    environment: <String, String>{
      'PATH': '/usr/bin:/bin',
      'HOME': Directory.systemTemp.path,
      'TERM': 'dumb',
      'LC_ALL': 'C',
      'PS1': '',
      'RPS1': '',
    },
    shellArguments: const <String>['-f'],
    gracefulShutdownTimeout: const Duration(milliseconds: 500),
    finalShutdownTimeout: const Duration(milliseconds: 500),
    cleanupStepTimeout: const Duration(milliseconds: 500),
    onChanged: () {},
    onTerminated: () {},
    lifecycleObserver: lifecycle.add,
    nativeObserver: native.add,
  );
  await session.start().timeout(const Duration(seconds: 3));
  final String marker = '__CD_READY_${paneId}__';
  session.insertText("stty -echo; $setup; print -r -- $marker");
  await session.submit();
  await _waitForTerminalOutput(
    session,
    (String output) => _occurrences(output, marker) >= 2,
    'Control-D semantics setup $paneId',
  );
  return _ControlDProbe(session, lifecycle, native);
}

Future<void> _sendAndObserveControlD(
  _ControlDProbe probe,
  String description,
) async {
  probe.session.sendEndOfFile();
  final int requestId = probe.lifecycle
      .lastWhere(
        (TerminalSessionLifecycleObservation observation) =>
            observation.stage == TerminalSessionLifecycleStage.eofWriteAccepted,
      )
      .writeRequestId!;
  final Stopwatch timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 3)) {
    if (probe.native.any(
      (TerminalSessionNativeObservation observation) =>
          observation.event.stage == PtyDiagnosticStage.writeCompleted &&
          observation.event.requestId == requestId,
    )) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  _expect(
    probe.native.any(
      (TerminalSessionNativeObservation observation) =>
          observation.event.stage == PtyDiagnosticStage.writeCompleted &&
          observation.event.requestId == requestId &&
          observation.event.byteCount == 1,
    ),
    '$description Control-D reaches native write completion',
  );
  _expect(
    probe.native.any(
      (TerminalSessionNativeObservation observation) =>
          observation.event.stage == PtyDiagnosticStage.stateSnapshot &&
          observation.event.requestId == requestId &&
          observation.event.foregroundProcessGroup != null,
    ),
    '$description captures foreground process group state',
  );
  _expect(
    probe.native.any(
      (TerminalSessionNativeObservation observation) =>
          observation.event.stage == PtyDiagnosticStage.termiosSnapshot &&
          observation.event.requestId == requestId &&
          observation.event.terminalLocalFlags != null &&
          observation.event.terminalEofCharacter != null,
    ),
    '$description captures termios flags and VEOF identity',
  );
}

Future<void> _finishControlDProbe(_ControlDProbe probe) async {
  if (probe.session.isLive) {
    try {
      await probe.session.waitForTermination().timeout(
        const Duration(seconds: 3),
      );
    } on TimeoutException {
      await probe.session.shutdown();
    }
  }
  await probe.session.dispose();
}

void _expectOrderedSessionStages(
  List<TerminalSessionLifecycleObservation> observations,
  List<TerminalSessionLifecycleStage> expected,
  String description,
) {
  var expectedIndex = 0;
  for (final TerminalSessionLifecycleObservation observation in observations) {
    if (expectedIndex < expected.length &&
        observation.stage == expected[expectedIndex]) {
      ++expectedIndex;
    }
  }
  _expect(
    expectedIndex == expected.length,
    '$description missing ${expected.skip(expectedIndex).map((stage) => stage.name).join(', ')}; '
    'observed ${observations.map((observation) => observation.stage.name).join(', ')}',
  );
}

Future<void> _waitForTerminalOutput(
  TerminalSession session,
  bool Function(String output) predicate,
  String description,
) async {
  final Stopwatch timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 3)) {
    if (predicate(session.buffer.outputText)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for $description: ${session.buffer.outputText}',
  );
}

int _occurrences(String value, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(value).length;

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('Expectation failed: $description');
  }
}

void _expectThrows(
  void Function() callback,
  String description, {
  Type expectedType = FormatException,
}) {
  try {
    callback();
  } on Object catch (error) {
    if (error.runtimeType == expectedType) {
      return;
    }
    throw StateError(
      'Expected $expectedType for $description, got ${error.runtimeType}',
    );
  }
  throw StateError('Expected $expectedType: $description');
}

final class _ControlDProbe {
  const _ControlDProbe(this.session, this.lifecycle, this.native);

  final TerminalSession session;
  final List<TerminalSessionLifecycleObservation> lifecycle;
  final List<TerminalSessionNativeObservation> native;
}

final class _FakePaneSession implements TerminalPaneSession {
  _FakePaneSession({
    required this.id,
    required void Function() onChanged,
    required void Function() onTerminated,
  }) : _onChanged = onChanged,
       _onTerminated = onTerminated;

  @override
  final TerminalSessionId id;
  final void Function() _onChanged;
  final void Function() _onTerminated;
  final List<String> insertedText = <String>[];
  final List<Uint8List> inputWrites = <Uint8List>[];

  var startCount = 0;
  var disposeCount = 0;
  var confirmationCount = 0;
  var endOfFileCount = 0;
  var interruptCount = 0;
  var failStart = false;
  var failShutdown = false;
  var _live = false;
  TerminalPaneSessionExitDisposition? _exitDisposition;

  @override
  TerminalKeyboardModes keyboardModes = const TerminalKeyboardModes();

  @override
  bool get isLive => _live;

  @override
  TerminalPaneSessionExitDisposition? get exitDisposition => _exitDisposition;

  @override
  Future<void> start() async {
    ++startCount;
    if (failStart) {
      throw StateError('requested fake start failure');
    }
    _live = true;
  }

  void finish({
    TerminalPaneSessionExitDisposition disposition =
        TerminalPaneSessionExitDisposition.clean,
  }) {
    _live = false;
    _exitDisposition = disposition;
    _onTerminated();
  }

  @override
  String render() => '';

  @override
  void insertText(String value) {
    insertedText.add(value);
    _onChanged();
  }

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
  void interrupt() {
    ++interruptCount;
  }

  @override
  void suspend() {}

  @override
  void quitForegroundProcess() {}

  @override
  void sendEndOfFile() {
    ++endOfFileCount;
  }

  @override
  void sendInput(Uint8List bytes) {
    inputWrites.add(bytes);
  }

  @override
  void resize({required int rows, required int columns}) {}

  @override
  void showCloseConfirmation() {
    ++confirmationCount;
    _onChanged();
  }

  @override
  Future<TerminalPaneSessionShutdownResult> shutdown() async {
    ++disposeCount;
    _live = false;
    if (failShutdown) {
      throw StateError('requested fake shutdown failure');
    }
    return TerminalPaneSessionShutdownResult(
      sessionId: id,
      processId: null,
      disposition: TerminalSessionShutdownDisposition.clean,
      terminationObserved: true,
      cleanupCompleted: true,
    );
  }
}
