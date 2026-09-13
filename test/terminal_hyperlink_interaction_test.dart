import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalHyperlinkInteractionTests();

void runTerminalHyperlinkInteractionTests() {
  _testHoverAndExclusiveCommandClick();
  _testBlockedUnavailableAndStaleTargets();
}

void _testHoverAndExclusiveCommandClick() {
  final _Fixture fixture = _Fixture();
  final TerminalHyperlinkRouteResult moved = fixture.route(
    _event(AppKitMouseEventKind.moved, column: 1, button: -1, clickCount: 0),
  );
  _expect(
    !moved.isConsumed &&
        fixture.hoveredRows.last == 0 &&
        fixture.hoveredColumns.last == 1 &&
        fixture.mouseIgnored == 1,
    'hover observes the current cell while motion still reaches mouse routing',
  );

  fixture.route(_event(AppKitMouseEventKind.down, column: 1));
  fixture.route(_event(AppKitMouseEventKind.up, column: 1));
  _expect(
    fixture.localSelections == 2 && fixture.opened.isEmpty,
    'ordinary primary click preserves local selection behavior',
  );

  final TerminalHyperlinkRouteResult armed = fixture.route(
    _event(AppKitMouseEventKind.down, column: 1, modifiers: _command),
  );
  final TerminalHyperlinkRouteResult opened = fixture.route(
    _event(AppKitMouseEventKind.up, column: 1, modifiers: _command),
  );
  _expect(
    armed.isConsumed &&
        armed.action == TerminalHyperlinkAction.armed &&
        opened.isConsumed &&
        opened.action == TerminalHyperlinkAction.opened &&
        fixture.opened.length == 1 &&
        fixture.opened.single.value == 'https://example.test/path' &&
        fixture.localSelections == 2 &&
        fixture.terminalReports == 0,
    'Command-primary-click opens once without local or PTY duplication',
  );

  fixture.route(
    _event(
      AppKitMouseEventKind.down,
      column: 1,
      modifiers: const ModifierKeys(
        ModifierKeys.commandBit | ModifierKeys.shiftBit,
      ),
    ),
  );
  fixture.route(
    _event(
      AppKitMouseEventKind.up,
      column: 1,
      modifiers: const ModifierKeys(
        ModifierKeys.commandBit | ModifierKeys.shiftBit,
      ),
    ),
  );
  _expect(
    fixture.localSelections == 4 && fixture.opened.length == 1,
    'non-exact Command chord is not promoted to a link action',
  );

  final TerminalHyperlinkRouteResult tripleDown = fixture.route(
    _event(
      AppKitMouseEventKind.down,
      column: 1,
      clickCount: 3,
      modifiers: _command,
    ),
  );
  final TerminalHyperlinkRouteResult tripleUp = fixture.route(
    _event(
      AppKitMouseEventKind.up,
      column: 1,
      clickCount: 3,
      modifiers: _command,
    ),
  );
  _expect(
    !tripleDown.isConsumed &&
        !tripleUp.isConsumed &&
        fixture.localSelections == 6 &&
        fixture.opened.length == 1,
    'Command triple-click passes through for semantic output selection',
  );

  fixture.route(
    _event(AppKitMouseEventKind.moved, column: 12, button: -1, clickCount: 0),
  );
  _expect(fixture.clearHoverCount == 1, 'out-of-grid motion clears hover');
}

void _testBlockedUnavailableAndStaleTargets() {
  final _Fixture fixture = _Fixture();
  TerminalHyperlinkRouteResult result = fixture.route(
    _event(AppKitMouseEventKind.down, column: 3, modifiers: _command),
  );
  _expect(result.action == TerminalHyperlinkAction.armed, 'blocked link arms');
  result = fixture.route(
    _event(AppKitMouseEventKind.up, column: 3, modifiers: _command),
  );
  _expect(
    result.action == TerminalHyperlinkAction.blocked &&
        fixture.notices.single == TerminalHyperlinkNoticeKind.blocked &&
        fixture.opened.isEmpty &&
        fixture.localSelections == 0 &&
        fixture.terminalReports == 0,
    'unsafe target is consumed and notified before any opener or mouse route',
  );

  fixture.acceptOpen = false;
  fixture.route(
    _event(AppKitMouseEventKind.down, column: 1, modifiers: _command),
  );
  result = fixture.route(
    _event(AppKitMouseEventKind.up, column: 1, modifiers: _command),
  );
  _expect(
    result.action == TerminalHyperlinkAction.unavailable &&
        fixture.notices.last == TerminalHyperlinkNoticeKind.unavailable &&
        fixture.opened.length == 1,
    'an opener refusal remains consumed and emits a content-free notice',
  );

  fixture.acceptOpen = true;
  fixture.route(
    _event(AppKitMouseEventKind.down, column: 1, modifiers: _command),
  );
  fixture.screens.primary.setNarrowCell(0, 1, 0x58);
  result = fixture.route(
    _event(AppKitMouseEventKind.up, column: 1, modifiers: _command),
  );
  _expect(
    result.action == TerminalHyperlinkAction.cancelled &&
        fixture.opened.length == 1,
    'click re-resolves and rejects a link removed after mouse-down',
  );

  fixture.screens.primary.setNarrowCell(
    0,
    1,
    0x41,
    hyperlink: fixture.allowedId,
  );
  fixture.route(
    _event(AppKitMouseEventKind.down, column: 1, modifiers: _command),
  );
  result = fixture.route(
    _event(AppKitMouseEventKind.dragged, column: 2, modifiers: _command),
  );
  final TerminalHyperlinkRouteResult up = fixture.route(
    _event(AppKitMouseEventKind.up, column: 1, modifiers: _command),
  );
  _expect(
    result.action == TerminalHyperlinkAction.cancelled &&
        up.action == TerminalHyperlinkAction.cancelled &&
        fixture.opened.length == 1,
    'drag permanently cancels an armed open while consuming the sequence',
  );
}

const ModifierKeys _command = ModifierKeys(ModifierKeys.commandBit);

final class _Fixture {
  _Fixture() {
    allowedId = screens.hyperlinkTable.tryIntern(
      uri: 'https://example.test/path',
    )!;
    blockedId = screens.hyperlinkTable.tryIntern(uri: 'file:///tmp/report')!;
    screens.primary
      ..setNarrowCell(0, 1, 0x41, hyperlink: allowedId)
      ..setNarrowCell(0, 3, 0x42, hyperlink: blockedId);
    mouse = TerminalMouseRouter(
      onTerminalReport: (Uint8List bytes) => terminalReports++,
      onLocalSelection: (TerminalLocalSelectionIntent intent) =>
          localSelections++,
    );
    controller = TerminalHyperlinkInteractionController(
      viewport: screens.viewport,
      onHoverCell: (int row, int column) {
        hoveredRows.add(row);
        hoveredColumns.add(column);
      },
      onClearHover: () => clearHoverCount++,
      onOpen: (AllowedExternalUrl target) {
        opened.add(target);
        return acceptOpen;
      },
      onNotice: notices.add,
    );
  }

  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 8);
  late final int allowedId;
  late final int blockedId;
  late final TerminalMouseRouter mouse;
  late final TerminalHyperlinkInteractionController controller;
  final List<int> hoveredRows = <int>[];
  final List<int> hoveredColumns = <int>[];
  final List<AllowedExternalUrl> opened = <AllowedExternalUrl>[];
  final List<TerminalHyperlinkNoticeKind> notices =
      <TerminalHyperlinkNoticeKind>[];
  bool acceptOpen = true;
  int clearHoverCount = 0;
  int terminalReports = 0;
  int localSelections = 0;
  int mouseIgnored = 0;

  TerminalHyperlinkRouteResult route(AppKitMouseEvent event) {
    final TerminalHyperlinkRouteResult result = controller.route(
      event,
      rows: 2,
      columns: 8,
      cellWidth: 10,
      cellHeight: 20,
    );
    if (!result.isConsumed) {
      final TerminalMouseRouteResult mouseResult = mouse.route(
        event,
        modes: const TerminalMouseModes(),
        rows: 2,
        columns: 8,
        cellWidth: 10,
        cellHeight: 20,
      );
      if (mouseResult.disposition == TerminalMouseRouteDisposition.ignored) {
        mouseIgnored++;
      }
    }
    return result;
  }
}

AppKitMouseEvent _event(
  AppKitMouseEventKind kind, {
  required int column,
  int row = 0,
  int button = 0,
  int clickCount = 1,
  ModifierKeys modifiers = const ModifierKeys(0),
}) => AppKitMouseEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: kind,
  x: (column + 0.5) * 10,
  y: (row + 0.5) * 20,
  button: button,
  modifiers: modifiers,
  clickCount: clickCount,
);

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
