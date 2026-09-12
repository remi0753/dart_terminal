import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalAppleScriptTests();

Future<void> runTerminalAppleScriptTests() async {
  _testObjectIdentity();
  _testSnapshotCodecAndBounds();
  _testCommandValidation();
  await _testOrderedCommandLifecycle();
  await _testInvalidExecutorCompletion();
  await _testDisableBusyTimeoutAndDispose();
}

void _testObjectIdentity() {
  final TerminalAppleScriptObjectId terminal = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.terminal,
    41,
  );
  _expect(
    terminal.externalValue == 'terminal:41' &&
        TerminalAppleScriptObjectId.parse('terminal:41') == terminal,
    'AppleScript identities must round-trip with their object kind',
  );
  for (final String invalid in <String>[
    '',
    'terminal',
    'terminal:0',
    'terminal:01',
    'terminal:-1',
    'pane:1',
    'terminal:1:2',
    'window:9223372036854775808',
  ]) {
    _expectThrows<FormatException>(
      () => TerminalAppleScriptObjectId.parse(invalid),
      'invalid identity was accepted: $invalid',
    );
  }
}

void _testSnapshotCodecAndBounds() {
  final TerminalAppleScriptObjectId windowId = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.window,
    1,
  );
  final TerminalAppleScriptObjectId firstTabId = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.tab,
    2,
  );
  final TerminalAppleScriptObjectId secondTabId = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.tab,
    3,
  );
  final TerminalAppleScriptObjectId firstTerminalId =
      TerminalAppleScriptObjectId(TerminalAppleScriptObjectKind.terminal, 4);
  final TerminalAppleScriptObjectId secondTerminalId =
      TerminalAppleScriptObjectId(TerminalAppleScriptObjectKind.terminal, 5);
  final TerminalAppleScriptApplicationSnapshot snapshot =
      TerminalAppleScriptApplicationSnapshot(
        generation: 8,
        enabled: true,
        windows: <TerminalAppleScriptWindowSnapshot>[
          TerminalAppleScriptWindowSnapshot(
            id: windowId,
            title: 'project',
            index: 1,
            frontmost: true,
            selectedTabId: secondTabId,
            tabs: <TerminalAppleScriptTabSnapshot>[
              TerminalAppleScriptTabSnapshot(
                id: firstTabId,
                title: 'shell',
                index: 1,
                selected: false,
                focusedTerminalId: firstTerminalId,
                terminals: <TerminalAppleScriptTerminalSnapshot>[
                  TerminalAppleScriptTerminalSnapshot(
                    id: firstTerminalId,
                    title: 'zsh',
                    workingDirectory: '/tmp/one',
                  ),
                ],
              ),
              TerminalAppleScriptTabSnapshot(
                id: secondTabId,
                title: 'editor',
                index: 2,
                selected: true,
                focusedTerminalId: secondTerminalId,
                terminals: <TerminalAppleScriptTerminalSnapshot>[
                  TerminalAppleScriptTerminalSnapshot(
                    id: secondTerminalId,
                    title: 'nvim',
                    workingDirectory: null,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
  final Uint8List encoded = TerminalAppleScriptSnapshotCodec.encode(snapshot);
  final TerminalAppleScriptApplicationSnapshot decoded =
      TerminalAppleScriptSnapshotCodec.decode(encoded);
  _expect(
    decoded.generation == 8 &&
        decoded.enabled &&
        decoded.windows.single.id == windowId &&
        decoded.windows.single.selectedTabId == secondTabId &&
        decoded.windows.single.tabs.last.focusedTerminalId ==
            secondTerminalId &&
        decoded.windows.single.tabs.first.terminals.single.workingDirectory ==
            '/tmp/one',
    'bounded snapshot codec did not retain ordering and relationships',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptApplicationSnapshot(
      generation: 1,
      enabled: false,
      windows: snapshot.windows,
    ),
    'disabled scripting retained a visible hierarchy',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptWindowSnapshot(
      id: windowId,
      title: 'project',
      index: 1,
      frontmost: true,
      selectedTabId: firstTabId,
      tabs: snapshot.windows.single.tabs,
    ),
    'selected tab reference disagreed with the selected flag',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptWindowSnapshot(
      id: windowId,
      title: 'project',
      index: 1,
      frontmost: true,
      selectedTabId: secondTabId,
      tabs: snapshot.windows.single.tabs.reversed,
    ),
    'tab indexes disagreed with collection order',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptTerminalSnapshot(
      id: firstTerminalId,
      title: 'bad\nname',
      workingDirectory: '/tmp',
    ),
    'unsafe terminal title was accepted',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptTerminalSnapshot(
      id: firstTerminalId,
      title: '',
      workingDirectory: 'relative',
    ),
    'relative working directory was accepted',
  );
  final Map<String, Object?> unknown =
      jsonDecode(utf8.decode(encoded)) as Map<String, Object?>;
  unknown['unknown'] = true;
  _expectThrows<FormatException>(
    () => TerminalAppleScriptSnapshotCodec.decode(
      Uint8List.fromList(utf8.encode(jsonEncode(unknown))),
    ),
    'snapshot codec accepted an unknown field',
  );
  _expectThrows<FormatException>(
    () => TerminalAppleScriptSnapshotCodec.decode(
      Uint8List(TerminalAppleScriptLimits.maximumSnapshotBytes + 1),
    ),
    'snapshot codec accepted an oversized packet',
  );
}

void _testCommandValidation() {
  final TerminalAppleScriptObjectId window = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.window,
    1,
  );
  final TerminalAppleScriptObjectId terminal = TerminalAppleScriptObjectId(
    TerminalAppleScriptObjectKind.terminal,
    2,
  );
  final TerminalAppleScriptCommandRequest split =
      TerminalAppleScriptCommandRequest(
        operationId: 1,
        kind: TerminalAppleScriptCommandKind.split,
        target: terminal,
        direction: TerminalAppleScriptSplitDirection.left,
      );
  final TerminalAppleScriptCommandRequest input =
      TerminalAppleScriptCommandRequest(
        operationId: 2,
        kind: TerminalAppleScriptCommandKind.inputText,
        target: terminal,
        text: 'printf ok\n',
      );
  _expect(
    split.direction == TerminalAppleScriptSplitDirection.left &&
        input.text == 'printf ok\n',
    'valid script commands lost typed arguments',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptCommandRequest(
      operationId: 3,
      kind: TerminalAppleScriptCommandKind.newTab,
      target: terminal,
    ),
    'new-tab accepted a terminal target',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptCommandRequest(
      operationId: 4,
      kind: TerminalAppleScriptCommandKind.newWindow,
      target: window,
    ),
    'new-window accepted a target',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptCommandRequest(
      operationId: 5,
      kind: TerminalAppleScriptCommandKind.split,
      target: terminal,
    ),
    'split accepted a missing direction',
  );
  _expectThrows<ArgumentError>(
    () => TerminalAppleScriptCommandRequest(
      operationId: 6,
      kind: TerminalAppleScriptCommandKind.inputText,
      target: terminal,
      text: '',
    ),
    'input accepted empty text',
  );
}

Future<void> _testOrderedCommandLifecycle() async {
  final _ControlledExecutor executor = _ControlledExecutor();
  final TerminalAppleScriptCommandController controller =
      TerminalAppleScriptCommandController(enabled: true, executor: executor);
  final TerminalAppleScriptCommandRequest first = _newWindow(1);
  final TerminalAppleScriptCommandRequest second = _newWindow(2);
  final Future<TerminalAppleScriptCommandResult> firstResult = controller
      .submit(first);
  final Future<TerminalAppleScriptCommandResult> secondResult = controller
      .submit(second);
  _expect(
    (await controller.submit(_newWindow(1))).disposition ==
        TerminalAppleScriptCommandDisposition.rejected,
    'duplicate live operation ID was accepted',
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    executor.started.join(',') == '1' && controller.pendingCount == 2,
    'controller ran script mutations concurrently',
  );
  executor.completeNext(TerminalAppleScriptCommandDisposition.completed);
  _expect((await firstResult).isCompleted, 'first mutation did not complete');
  await Future<void>.delayed(Duration.zero);
  _expect(
    executor.started.join(',') == '1,2',
    'second mutation did not begin after the first completion',
  );
  executor.completeNext(TerminalAppleScriptCommandDisposition.notFound);
  _expect(
    (await secondResult).disposition ==
        TerminalAppleScriptCommandDisposition.notFound,
    'typed command failure was not retained',
  );
  controller.dispose();
}

Future<void> _testInvalidExecutorCompletion() async {
  final TerminalAppleScriptCommandController mismatchController =
      TerminalAppleScriptCommandController(
        enabled: true,
        executor: _ImmediateExecutor(
          (request) => TerminalAppleScriptCommandResult(
            operationId: request.operationId + 1,
            disposition: TerminalAppleScriptCommandDisposition.completed,
          ),
        ),
      );
  _expect(
    (await mismatchController.submit(_newWindow(30))).disposition ==
        TerminalAppleScriptCommandDisposition.failed,
    'mismatched executor completion escaped as a successful operation',
  );
  mismatchController.dispose();

  final TerminalAppleScriptCommandController throwingController =
      TerminalAppleScriptCommandController(
        enabled: true,
        executor: _ImmediateExecutor((request) => throw StateError('failed')),
      );
  _expect(
    (await throwingController.submit(_newWindow(31))).disposition ==
        TerminalAppleScriptCommandDisposition.failed,
    'executor exception escaped the typed failure boundary',
  );
  throwingController.dispose();
}

Future<void> _testDisableBusyTimeoutAndDispose() async {
  final _ControlledExecutor executor = _ControlledExecutor();
  final TerminalAppleScriptCommandController controller =
      TerminalAppleScriptCommandController(
        enabled: true,
        executor: executor,
        maximumPendingCommands: 2,
      );
  final Future<TerminalAppleScriptCommandResult> active = controller.submit(
    _newWindow(10),
  );
  final Future<TerminalAppleScriptCommandResult> queued = controller.submit(
    _newWindow(11),
  );
  _expect(
    (await controller.submit(_newWindow(12))).disposition ==
        TerminalAppleScriptCommandDisposition.busy,
    'pending-command cap was not enforced',
  );
  _expect(
    (await controller.submit(_newWindow(10))).disposition ==
        TerminalAppleScriptCommandDisposition.busy,
    'full queue must reject without replacing a live operation',
  );
  controller.setEnabled(false);
  _expect(
    (await queued).disposition ==
            TerminalAppleScriptCommandDisposition.disabled &&
        (await controller.submit(_newWindow(13))).disposition ==
            TerminalAppleScriptCommandDisposition.disabled,
    'disable did not reject queued and new commands',
  );
  executor.completeNext(TerminalAppleScriptCommandDisposition.completed);
  _expect((await active).isCompleted, 'active mutation was not resolved once');
  controller.setEnabled(true);
  final Future<TerminalAppleScriptCommandResult> disposed = controller.submit(
    _newWindow(14),
  );
  controller.dispose();
  _expect(
    (await disposed).disposition ==
            TerminalAppleScriptCommandDisposition.disposed &&
        (await controller.submit(_newWindow(15))).disposition ==
            TerminalAppleScriptCommandDisposition.disposed,
    'dispose did not resolve active and future commands',
  );
  executor.completeNext(TerminalAppleScriptCommandDisposition.completed);

  final TerminalAppleScriptCommandController timeoutController =
      TerminalAppleScriptCommandController(
        enabled: true,
        executor: _NeverExecutor(),
        commandTimeout: const Duration(milliseconds: 1),
      );
  _expect(
    (await timeoutController.submit(_newWindow(20))).disposition ==
        TerminalAppleScriptCommandDisposition.timedOut,
    'command timeout did not produce a typed terminal result',
  );
  timeoutController.dispose();
}

TerminalAppleScriptCommandRequest _newWindow(int operationId) =>
    TerminalAppleScriptCommandRequest(
      operationId: operationId,
      kind: TerminalAppleScriptCommandKind.newWindow,
    );

final class _ControlledExecutor implements TerminalAppleScriptCommandExecutor {
  final List<int> started = <int>[];
  final List<
    ({
      TerminalAppleScriptCommandRequest request,
      Completer<TerminalAppleScriptCommandResult> completer,
    })
  >
  pending =
      <
        ({
          TerminalAppleScriptCommandRequest request,
          Completer<TerminalAppleScriptCommandResult> completer,
        })
      >[];

  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) {
    started.add(request.operationId);
    final Completer<TerminalAppleScriptCommandResult> completer =
        Completer<TerminalAppleScriptCommandResult>();
    pending.add((request: request, completer: completer));
    return completer.future;
  }

  void completeNext(TerminalAppleScriptCommandDisposition disposition) {
    final item = pending.removeAt(0);
    item.completer.complete(
      TerminalAppleScriptCommandResult(
        operationId: item.request.operationId,
        disposition: disposition,
      ),
    );
  }
}

final class _NeverExecutor implements TerminalAppleScriptCommandExecutor {
  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) => Completer<TerminalAppleScriptCommandResult>().future;
}

final class _ImmediateExecutor implements TerminalAppleScriptCommandExecutor {
  const _ImmediateExecutor(this.callback);

  final TerminalAppleScriptCommandResult Function(
    TerminalAppleScriptCommandRequest request,
  )
  callback;

  @override
  Future<TerminalAppleScriptCommandResult> execute(
    TerminalAppleScriptCommandRequest request,
  ) async => callback(request);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}
