import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';

import '../terminal_core/terminal_keyboard_modes.dart';
import '../terminal_core/terminal_mouse_modes.dart';
import 'terminal_mouse_encoder.dart';
import 'terminal_mouse_event.dart';

enum TerminalScrollDisposition {
  terminalReport,
  localScroll,
  alternateScreenInput,
  ignored,
}

enum TerminalScrollIgnoreReason {
  noVerticalDelta,
  subRowDelta,
  protocolCoordinateLimit,
}

final class TerminalScrollRouteResult {
  TerminalScrollRouteResult._({
    required this.disposition,
    required Iterable<int> terminalBytes,
    required this.localRows,
    required this.ignoreReason,
  }) : terminalBytes = List<int>.unmodifiable(terminalBytes) {
    for (final int byte in this.terminalBytes) {
      RangeError.checkValueInInterval(byte, 0, 0xff, 'terminal byte');
    }
    switch (disposition) {
      case TerminalScrollDisposition.terminalReport:
      case TerminalScrollDisposition.alternateScreenInput:
        if (this.terminalBytes.isEmpty ||
            this.terminalBytes.length >
                TerminalScrollRouter.maximumOutputBytes ||
            localRows != 0 ||
            ignoreReason != null) {
          throw ArgumentError('terminal scroll result fields are inconsistent');
        }
      case TerminalScrollDisposition.localScroll:
        if (this.terminalBytes.isNotEmpty ||
            localRows == 0 ||
            localRows.abs() > TerminalScrollAccumulator.maximumRowsPerEvent ||
            ignoreReason != null) {
          throw ArgumentError('local scroll result fields are inconsistent');
        }
      case TerminalScrollDisposition.ignored:
        if (this.terminalBytes.isNotEmpty ||
            localRows != 0 ||
            ignoreReason == null) {
          throw ArgumentError('ignored scroll result fields are inconsistent');
        }
    }
  }

  factory TerminalScrollRouteResult.terminal(Iterable<int> bytes) =>
      TerminalScrollRouteResult._(
        disposition: TerminalScrollDisposition.terminalReport,
        terminalBytes: bytes,
        localRows: 0,
        ignoreReason: null,
      );

  factory TerminalScrollRouteResult.local(int rows) =>
      TerminalScrollRouteResult._(
        disposition: TerminalScrollDisposition.localScroll,
        terminalBytes: const <int>[],
        localRows: rows,
        ignoreReason: null,
      );

  factory TerminalScrollRouteResult.alternate(Iterable<int> bytes) =>
      TerminalScrollRouteResult._(
        disposition: TerminalScrollDisposition.alternateScreenInput,
        terminalBytes: bytes,
        localRows: 0,
        ignoreReason: null,
      );

  factory TerminalScrollRouteResult.ignored(
    TerminalScrollIgnoreReason reason,
  ) => TerminalScrollRouteResult._(
    disposition: TerminalScrollDisposition.ignored,
    terminalBytes: const <int>[],
    localRows: 0,
    ignoreReason: reason,
  );

  final TerminalScrollDisposition disposition;
  final List<int> terminalBytes;
  final int localRows;
  final TerminalScrollIgnoreReason? ignoreReason;
}

/// Converts AppKit's pixel-like precise deltas or line-like wheel deltas into
/// a bounded physical-row count without replaying time between events.
final class TerminalScrollAccumulator {
  static const int maximumRowsPerEvent = 32;

  double _residualRows = 0.0;
  bool? _previousPrecise;
  int _previousDirection = 0;

  double get residualRows => _residualRows;

  void reset() {
    _residualRows = 0.0;
    _previousPrecise = null;
    _previousDirection = 0;
  }

  int consume(AppKitScrollEvent source, {required double cellHeight}) {
    if (!cellHeight.isFinite || cellHeight <= 0.0) {
      throw ArgumentError.value(
        cellHeight,
        'cellHeight',
        'must be finite and positive',
      );
    }
    if (!source.scrollingDeltaY.isFinite) {
      throw ArgumentError.value(
        source.scrollingDeltaY,
        'scrollingDeltaY',
        'must be finite',
      );
    }

    if (source.phase == AppKitScrollPhase.began ||
        source.phase == AppKitScrollPhase.mayBegin) {
      reset();
    }
    if (source.phase == AppKitScrollPhase.cancelled ||
        source.momentumPhase == AppKitScrollPhase.cancelled) {
      reset();
      return 0;
    }

    final double rawRows = source.hasPreciseScrollingDeltas
        ? source.scrollingDeltaY / cellHeight
        : source.scrollingDeltaY;
    final double boundedRows = rawRows.clamp(
      -maximumRowsPerEvent.toDouble(),
      maximumRowsPerEvent.toDouble(),
    );
    final int direction = boundedRows.sign.toInt();
    if ((_previousPrecise != null &&
            _previousPrecise != source.hasPreciseScrollingDeltas) ||
        (_previousDirection != 0 &&
            direction != 0 &&
            direction != _previousDirection)) {
      _residualRows = 0.0;
    }
    _previousPrecise = source.hasPreciseScrollingDeltas;
    if (direction != 0) {
      _previousDirection = direction;
    }

    final double totalRows = _residualRows + boundedRows;
    final int emittedRows = totalRows.truncate().clamp(
      -maximumRowsPerEvent,
      maximumRowsPerEvent,
    );
    _residualRows = totalRows - emittedRows;
    if (source.momentumPhase == AppKitScrollPhase.ended) {
      reset();
    }
    return emittedRows;
  }
}

typedef TerminalLocalScrollCallback = void Function(int rows);
typedef TerminalAlternateScrollInputCallback = void Function(Uint8List bytes);
typedef TerminalScrollReportCallback = void Function(Uint8List bytes);

enum _TerminalScrollOwner { terminal, local, alternate }

/// Normalizes one native scroll event and assigns exactly one terminal owner.
final class TerminalScrollRouter {
  TerminalScrollRouter({
    required this.onTerminalReport,
    required this.onLocalScroll,
    required this.onAlternateScreenInput,
    TerminalMouseEncoder mouseEncoder = const TerminalMouseEncoder(),
    TerminalScrollAccumulator? accumulator,
  }) : _mouseEncoder = mouseEncoder,
       _accumulator = accumulator ?? TerminalScrollAccumulator();

  static const int maximumOutputBytes =
      TerminalScrollAccumulator.maximumRowsPerEvent *
      TerminalMouseEncoder.maximumPacketBytes;

  final TerminalScrollReportCallback onTerminalReport;
  final TerminalLocalScrollCallback onLocalScroll;
  final TerminalAlternateScrollInputCallback onAlternateScreenInput;
  final TerminalMouseEncoder _mouseEncoder;
  final TerminalScrollAccumulator _accumulator;
  _TerminalScrollOwner? _previousOwner;

  TerminalScrollRouteResult route(
    AppKitScrollEvent source, {
    required TerminalMouseModes mouseModes,
    required TerminalKeyboardModes keyboardModes,
    required bool usingAlternateScreen,
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    _validate(
      source,
      rows: rows,
      columns: columns,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );

    final bool terminalReporting =
        mouseModes.reportingEnabled && !source.modifiers.shift;
    final _TerminalScrollOwner owner = terminalReporting
        ? _TerminalScrollOwner.terminal
        : usingAlternateScreen
        ? _TerminalScrollOwner.alternate
        : _TerminalScrollOwner.local;
    if (_previousOwner != null && _previousOwner != owner) {
      _accumulator.reset();
    }
    _previousOwner = owner;

    final int rowDelta = _accumulator.consume(source, cellHeight: cellHeight);
    if (rowDelta == 0) {
      return TerminalScrollRouteResult.ignored(
        source.scrollingDeltaY == 0.0
            ? TerminalScrollIgnoreReason.noVerticalDelta
            : TerminalScrollIgnoreReason.subRowDelta,
      );
    }

    switch (owner) {
      case _TerminalScrollOwner.terminal:
        final int terminalColumn = _cellIndex(source.x, cellWidth, columns) + 1;
        final int terminalRow = _cellIndex(source.y, cellHeight, rows) + 1;
        final TerminalMouseButton button = rowDelta > 0
            ? TerminalMouseButton.wheelUp
            : TerminalMouseButton.wheelDown;
        final TerminalMouseEvent wheel = TerminalMouseEvent(
          kind: TerminalMouseEventKind.press,
          button: button,
          column: terminalColumn,
          row: terminalRow,
          modifiers: TerminalMouseModifiers(
            option: source.modifiers.option,
            control: source.modifiers.control,
          ),
        );
        try {
          final List<int> output = <int>[];
          for (int index = 0; index < rowDelta.abs(); index++) {
            output.addAll(_mouseEncoder.encode(wheel, mouseModes));
          }
          final Uint8List bytes = Uint8List.fromList(output);
          onTerminalReport(bytes);
          return TerminalScrollRouteResult.terminal(bytes);
        } on TerminalMouseEncodingLimitException {
          return TerminalScrollRouteResult.ignored(
            TerminalScrollIgnoreReason.protocolCoordinateLimit,
          );
        }
      case _TerminalScrollOwner.local:
        onLocalScroll(rowDelta);
        return TerminalScrollRouteResult.local(rowDelta);
      case _TerminalScrollOwner.alternate:
        final List<int> key = keyboardModes.applicationCursorKeys
            ? <int>[0x1b, 0x4f, rowDelta > 0 ? 0x41 : 0x42]
            : <int>[0x1b, 0x5b, rowDelta > 0 ? 0x41 : 0x42];
        final Uint8List bytes = Uint8List.fromList(<int>[
          for (int index = 0; index < rowDelta.abs(); index++) ...key,
        ]);
        onAlternateScreenInput(bytes);
        return TerminalScrollRouteResult.alternate(bytes);
    }
  }

  static int _cellIndex(double point, double extent, int count) =>
      math.min(math.max((point / extent).floor(), 0), count - 1);

  static void _validate(
    AppKitScrollEvent source, {
    required int rows,
    required int columns,
    required double cellWidth,
    required double cellHeight,
  }) {
    if (source.protocolVersion < 5) {
      throw ArgumentError.value(
        source.protocolVersion,
        'protocolVersion',
        'scroll events require protocol version 5',
      );
    }
    if (!source.x.isFinite ||
        !source.y.isFinite ||
        !source.scrollingDeltaX.isFinite ||
        !source.scrollingDeltaY.isFinite) {
      throw ArgumentError('scroll position and deltas must be finite');
    }
    if (!cellWidth.isFinite ||
        !cellHeight.isFinite ||
        cellWidth <= 0.0 ||
        cellHeight <= 0.0) {
      throw ArgumentError('scroll cell metrics must be finite and positive');
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
