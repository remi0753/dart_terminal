import 'dart:typed_data';

enum TerminalFocusReportDisposition {
  terminalReport,
  modeDisabled,
  duplicateTransition,
}

final class TerminalFocusReportResult {
  TerminalFocusReportResult._(this.disposition, List<int> bytes)
    : terminalBytes = List<int>.unmodifiable(bytes);

  factory TerminalFocusReportResult.report(Uint8List bytes) =>
      TerminalFocusReportResult._(
        TerminalFocusReportDisposition.terminalReport,
        bytes,
      );

  factory TerminalFocusReportResult.ignored(
    TerminalFocusReportDisposition disposition,
  ) {
    if (disposition == TerminalFocusReportDisposition.terminalReport) {
      throw ArgumentError.value(
        disposition,
        'disposition',
        'must describe an ignored focus transition',
      );
    }
    return TerminalFocusReportResult._(disposition, const <int>[]);
  }

  final TerminalFocusReportDisposition disposition;
  final List<int> terminalBytes;
}

typedef TerminalFocusReportCallback = void Function(Uint8List bytes);

/// Routes native focus transitions through DEC private mode 1004.
///
/// [modeGeneration] must change whenever mode 1004 changes. This keeps
/// duplicate suppression correct across disable/re-enable without coupling the
/// native event owner to parser callbacks.
final class TerminalFocusReporter {
  TerminalFocusReporter({required this.onTerminalReport});

  static const int maximumReportBytes = 3;

  final TerminalFocusReportCallback onTerminalReport;

  int? _observedModeGeneration;
  bool? _lastReportedFocus;

  TerminalFocusReportResult route({
    required bool isFocused,
    required bool modeEnabled,
    required int modeGeneration,
  }) {
    RangeError.checkValueInInterval(
      modeGeneration,
      1,
      0x7fffffffffffffff,
      'modeGeneration',
    );
    if (_observedModeGeneration != modeGeneration) {
      _observedModeGeneration = modeGeneration;
      _lastReportedFocus = null;
    }
    if (!modeEnabled) {
      _lastReportedFocus = null;
      return TerminalFocusReportResult.ignored(
        TerminalFocusReportDisposition.modeDisabled,
      );
    }
    if (_lastReportedFocus == isFocused) {
      return TerminalFocusReportResult.ignored(
        TerminalFocusReportDisposition.duplicateTransition,
      );
    }
    _lastReportedFocus = isFocused;
    final Uint8List bytes = Uint8List.fromList(
      isFocused ? const <int>[0x1b, 0x5b, 0x49] : const <int>[0x1b, 0x5b, 0x4f],
    );
    if (bytes.length > maximumReportBytes) {
      throw StateError('focus reporter violated its packet bound');
    }
    onTerminalReport(bytes);
    return TerminalFocusReportResult.report(bytes);
  }
}
