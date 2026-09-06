import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void main() => runTerminalTextInputEventRouterTests();

void runTerminalTextInputEventRouterTests() {
  final List<TerminalKeyEvent> raw = <TerminalKeyEvent>[];
  final List<String> preedits = <String>[];
  final List<int> clears = <int>[];
  final List<String> commits = <String>[];
  final List<String> overflows = <String>[];
  final TerminalTextInputEventRouter router = TerminalTextInputEventRouter(
    clientId: 41,
    onRawKeyDown: raw.add,
    onPreedit:
        ({
          required int generation,
          required String text,
          required int selectionLocation,
          required int selectionLength,
        }) {
          preedits.add('$generation:$text:$selectionLocation:$selectionLength');
        },
    onClearPreedit: clears.add,
    onCommit: commits.add,
    onOverflow: (int clientId, int generation) {
      overflows.add('$clientId:$generation');
    },
  );

  final TerminalTextInputRouteResult rawResult = router.route(
    const TerminalTextInputKeyEvent(
      clientId: 41,
      generation: 1,
      monotonicNanoseconds: 1,
      kind: TerminalTextInputKeyKind.down,
      keyCode: 126,
      modifiers: ModifierKeys(ModifierKeys.functionBit),
      isRepeat: true,
      characters: '\uf700',
      charactersIgnoringModifiers: '\uf700',
    ),
  );
  final TerminalTextInputRouteResult keyUpResult = router.route(
    const TerminalTextInputKeyEvent(
      clientId: 41,
      generation: 2,
      monotonicNanoseconds: 2,
      kind: TerminalTextInputKeyKind.up,
      keyCode: 126,
      modifiers: ModifierKeys(ModifierKeys.functionBit),
      isRepeat: false,
      characters: '\uf700',
      charactersIgnoringModifiers: '\uf700',
    ),
  );
  router.route(
    const TerminalTextInputPreeditEvent(
      clientId: 41,
      generation: 3,
      monotonicNanoseconds: 3,
      text: 'にほんご',
      selection: TerminalTextInputRange(4, 0),
      replacement: TerminalTextInputRange.notFound,
    ),
  );
  final TerminalTextInputRouteResult suppressedResult = router.route(
    const TerminalTextInputKeyEvent(
      clientId: 41,
      generation: 4,
      monotonicNanoseconds: 4,
      kind: TerminalTextInputKeyKind.down,
      keyCode: 8,
      modifiers: ModifierKeys(ModifierKeys.controlBit),
      isRepeat: false,
      characters: '\u0003',
      charactersIgnoringModifiers: 'c',
    ),
  );
  final TerminalTextInputCommitEvent commit =
      const TerminalTextInputCommitEvent(
        clientId: 41,
        generation: 5,
        monotonicNanoseconds: 5,
        text: '日本語',
        replacement: TerminalTextInputRange.notFound,
      );
  final TerminalTextInputRouteResult commitResult = router.route(commit);
  final TerminalTextInputRouteResult duplicateResult = router.route(commit);
  router.route(
    const TerminalTextInputPreeditEvent(
      clientId: 41,
      generation: 6,
      monotonicNanoseconds: 6,
      text: 'かな',
      selection: TerminalTextInputRange(2, 0),
      replacement: TerminalTextInputRange.notFound,
    ),
  );
  final TerminalTextInputRouteResult cancelResult = router.route(
    const TerminalTextInputCancelEvent(
      clientId: 41,
      generation: 7,
      monotonicNanoseconds: 7,
    ),
  );
  router.route(
    const TerminalTextInputPreeditEvent(
      clientId: 41,
      generation: 8,
      monotonicNanoseconds: 8,
      text: 'overflow',
      selection: TerminalTextInputRange(8, 0),
      replacement: TerminalTextInputRange.notFound,
    ),
  );
  final TerminalTextInputRouteResult overflowResult = router.route(
    const TerminalTextInputOverflowEvent(
      clientId: 41,
      generation: 9,
      monotonicNanoseconds: 9,
    ),
  );

  _expect(
    rawResult.disposition == TerminalTextInputRouteDisposition.rawKey &&
        raw.length == 1 &&
        raw.single.physicalKey == TerminalPhysicalKey.arrowUp &&
        raw.single.modifiers.function &&
        raw.single.isRepeat &&
        keyUpResult.disposition ==
            TerminalTextInputRouteDisposition.keyUpIgnored &&
        suppressedResult.disposition ==
            TerminalTextInputRouteDisposition.rawSuppressed &&
        commitResult.disposition ==
            TerminalTextInputRouteDisposition.committed &&
        duplicateResult.disposition ==
            TerminalTextInputRouteDisposition.stale &&
        cancelResult.disposition ==
            TerminalTextInputRouteDisposition.cancelled &&
        overflowResult.disposition ==
            TerminalTextInputRouteDisposition.overflowReset &&
        preedits.toString() ==
            <String>['3:にほんご:4:0', '6:かな:2:0', '8:overflow:8:0'].toString() &&
        clears.toString() == <int>[5, 7, 9].toString() &&
        commits.toString() == <String>['日本語'].toString() &&
        overflows.toString() == <String>['41:9'].toString() &&
        !router.isCompositionActive &&
        router.lastGeneration == 9,
    'raw, preedit, commit, cancel, and overflow have exclusive effects',
  );
  _expectThrows(
    () => router.route(
      const TerminalTextInputCancelEvent(
        clientId: 42,
        generation: 10,
        monotonicNanoseconds: 10,
      ),
    ),
    'events from another native client are rejected',
  );
}

void _expectThrows(void Function() body, String message) {
  try {
    body();
  } on StateError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
