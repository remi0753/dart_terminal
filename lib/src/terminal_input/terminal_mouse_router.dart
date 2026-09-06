import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';

import '../terminal_core/terminal_mouse_modes.dart';
import 'terminal_mouse_encoder.dart';
import 'terminal_mouse_event.dart';

enum TerminalMouseRouteDisposition { terminalReport, localSelection, ignored }

enum TerminalMouseIgnoreReason {
  noTrackingMotion,
  trackingFiltered,
  unsupportedButton,
  protocolCoordinateLimit,
}

enum TerminalLocalSelectionPhase { begin, update, end }

final class TerminalPointerCell {
  TerminalPointerCell({required this.row, required this.column}) {
    RangeError.checkValueInInterval(
      row,
      0,
      TerminalMouseEvent.maximumCoordinate - 1,
      'row',
    );
    RangeError.checkValueInInterval(
      column,
      0,
      TerminalMouseEvent.maximumCoordinate - 1,
      'column',
    );
  }

  final int row;
  final int column;

  int get terminalRow => row + 1;
  int get terminalColumn => column + 1;

  @override
  bool operator ==(Object other) =>
      other is TerminalPointerCell &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// Bounded local-selection handoff consumed by the following gesture task.
final class TerminalLocalSelectionIntent {
  TerminalLocalSelectionIntent({
    required this.phase,
    required this.cell,
    required this.button,
    required this.clickCount,
    required this.modifiers,
  }) {
    if (button == TerminalMouseButton.none) {
      throw ArgumentError('local selection requires a physical button');
    }
    RangeError.checkValueInInterval(clickCount, 0, 255, 'clickCount');
    if (modifiers.bits < 0 ||
        modifiers.bits & ~ModifierKeys.supportedBits != 0) {
      throw ArgumentError.value(
        modifiers.bits,
        'modifiers',
        'contains unsupported bits',
      );
    }
  }

  final TerminalLocalSelectionPhase phase;
  final TerminalPointerCell cell;
  final TerminalMouseButton button;
  final int clickCount;
  final ModifierKeys modifiers;
}

final class TerminalMouseRouteResult {
  TerminalMouseRouteResult._({
    required this.disposition,
    required Iterable<int> terminalBytes,
    required this.localSelection,
    required this.ignoreReason,
  }) : terminalBytes = List<int>.unmodifiable(terminalBytes) {
    for (final int byte in this.terminalBytes) {
      RangeError.checkValueInInterval(byte, 0, 0xff, 'terminal byte');
    }
    switch (disposition) {
      case TerminalMouseRouteDisposition.terminalReport:
        if (this.terminalBytes.isEmpty ||
            this.terminalBytes.length >
                TerminalMouseEncoder.maximumPacketBytes ||
            localSelection != null ||
            ignoreReason != null) {
          throw ArgumentError('terminal mouse result fields are inconsistent');
        }
      case TerminalMouseRouteDisposition.localSelection:
        if (this.terminalBytes.isNotEmpty ||
            localSelection == null ||
            ignoreReason != null) {
          throw ArgumentError('local mouse result fields are inconsistent');
        }
      case TerminalMouseRouteDisposition.ignored:
        if (this.terminalBytes.isNotEmpty ||
            localSelection != null ||
            ignoreReason == null) {
          throw ArgumentError('ignored mouse result fields are inconsistent');
        }
    }
  }

  factory TerminalMouseRouteResult.terminal(Iterable<int> bytes) =>
      TerminalMouseRouteResult._(
        disposition: TerminalMouseRouteDisposition.terminalReport,
        terminalBytes: bytes,
        localSelection: null,
        ignoreReason: null,
      );

  factory TerminalMouseRouteResult.local(TerminalLocalSelectionIntent intent) =>
      TerminalMouseRouteResult._(
        disposition: TerminalMouseRouteDisposition.localSelection,
        terminalBytes: const <int>[],
        localSelection: intent,
        ignoreReason: null,
      );

  factory TerminalMouseRouteResult.ignored(TerminalMouseIgnoreReason reason) =>
      TerminalMouseRouteResult._(
        disposition: TerminalMouseRouteDisposition.ignored,
        terminalBytes: const <int>[],
        localSelection: null,
        ignoreReason: reason,
      );

  final TerminalMouseRouteDisposition disposition;
  final List<int> terminalBytes;
  final TerminalLocalSelectionIntent? localSelection;
  final TerminalMouseIgnoreReason? ignoreReason;
}

typedef TerminalMouseReportCallback = void Function(Uint8List bytes);
typedef TerminalLocalSelectionCallback = void Function(
  TerminalLocalSelectionIntent intent,
);

/// Maps content-view logical points to cells and chooses one event owner.
final class TerminalMouseRouter {
  TerminalMouseRouter({
    required this.onTerminalReport,
    required this.onLocalSelection,
    TerminalMouseEncoder encoder = const TerminalMouseEncoder(),
  }) : _encoder = encoder;

  static const int maximumClickCount = 255;

  final TerminalMouseReportCallback onTerminalReport;
  final TerminalLocalSelectionCallback onLocalSelection;
  final TerminalMouseEncoder _encoder;

  TerminalMouseRouteResult route(
    AppKitMouseEvent source, {
    required TerminalMouseModes modes,
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    _validateGeometry(
      source,
      rows: rows,
      columns: columns,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
    final TerminalPointerCell cell = TerminalPointerCell(
      row: _cellIndex(source.y, cellHeight, rows),
      column: _cellIndex(source.x, cellWidth, columns),
    );
    final TerminalMouseButton? physicalButton = switch (source.kind) {
      AppKitMouseEventKind.moved => TerminalMouseButton.none,
      _ => TerminalMouseButton.fromAppKitButton(source.button),
    };
    if (physicalButton == null) {
      return TerminalMouseRouteResult.ignored(
        TerminalMouseIgnoreReason.unsupportedButton,
      );
    }
    final TerminalMouseModifiers modifiers = TerminalMouseModifiers(
      shift: source.modifiers.shift,
      option: source.modifiers.option,
      control: source.modifiers.control,
    );
    final TerminalMouseEvent event = TerminalMouseEvent(
      kind: switch (source.kind) {
        AppKitMouseEventKind.down => TerminalMouseEventKind.press,
        AppKitMouseEventKind.up => TerminalMouseEventKind.release,
        AppKitMouseEventKind.moved ||
        AppKitMouseEventKind.dragged => TerminalMouseEventKind.motion,
      },
      button: physicalButton,
      column: cell.terminalColumn,
      row: cell.terminalRow,
      modifiers: modifiers,
    );

    final bool localGesture = source.kind != AppKitMouseEventKind.moved;
    final bool localOverride = modes.reportingEnabled && modifiers.shift;
    if (localGesture && (!modes.reportingEnabled || localOverride)) {
      final TerminalLocalSelectionIntent intent = TerminalLocalSelectionIntent(
        phase: switch (source.kind) {
          AppKitMouseEventKind.down => TerminalLocalSelectionPhase.begin,
          AppKitMouseEventKind.dragged => TerminalLocalSelectionPhase.update,
          AppKitMouseEventKind.up => TerminalLocalSelectionPhase.end,
          AppKitMouseEventKind.moved => throw StateError(
            'moved event cannot become a local gesture',
          ),
        },
        cell: cell,
        button: physicalButton,
        clickCount: source.clickCount,
        modifiers: source.modifiers,
      );
      onLocalSelection(intent);
      return TerminalMouseRouteResult.local(intent);
    }

    if (_encoder.shouldReport(event, modes)) {
      try {
        final Uint8List bytes = _encoder.encode(event, modes);
        onTerminalReport(bytes);
        return TerminalMouseRouteResult.terminal(bytes);
      } on TerminalMouseEncodingLimitException {
        return TerminalMouseRouteResult.ignored(
          TerminalMouseIgnoreReason.protocolCoordinateLimit,
        );
      }
    }
    return TerminalMouseRouteResult.ignored(
      modes.reportingEnabled
          ? TerminalMouseIgnoreReason.trackingFiltered
          : TerminalMouseIgnoreReason.noTrackingMotion,
    );
  }

  static int _cellIndex(double point, double extent, int count) =>
      math.min(math.max((point / extent).floor(), 0), count - 1);

  static void _validateGeometry(
    AppKitMouseEvent source, {
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    if (!source.x.isFinite || !source.y.isFinite) {
      throw ArgumentError('mouse point must be finite');
    }
    if (!cellWidth.isFinite ||
        !cellHeight.isFinite ||
        cellWidth <= 0 ||
        cellHeight <= 0) {
      throw ArgumentError('mouse cell metrics must be finite and positive');
    }
    RangeError.checkValueInInterval(
      rows,
      1,
      TerminalMouseEvent.maximumCoordinate,
      'rows',
    );
    RangeError.checkValueInInterval(
      columns,
      1,
      TerminalMouseEvent.maximumCoordinate,
      'columns',
    );
    RangeError.checkValueInInterval(
      source.clickCount,
      0,
      maximumClickCount,
      'clickCount',
    );
    if (source.modifiers.bits < 0 ||
        source.modifiers.bits & ~ModifierKeys.supportedBits != 0) {
      throw ArgumentError.value(
        source.modifiers.bits,
        'modifiers',
        'contains unsupported bits',
      );
    }
  }
}
