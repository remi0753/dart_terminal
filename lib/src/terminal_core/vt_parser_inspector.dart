import 'dart:collection';
import 'dart:typed_data';

import 'vt_parser.dart';
import 'vt_parser_table.dart';

/// Parser action families retained by [VtParserInspector].
///
/// Printable terminal content is deliberately represented only by the
/// aggregate [VtParserInspector.printableScalarCount], never as an event.
enum VtParserInspectionKind {
  execute,
  escape,
  controlSequence,
  operatingSystemCommand,
  deviceControlString,
  controlString,
  cancel,
  limit,
  malformed,
  incomplete,
}

typedef VtParserInspectionObserver = void Function(
  VtParserInspectionEvent event,
);

/// Hard bounds for retained parser-inspection metadata.
final class VtParserInspectorLimits {
  const VtParserInspectorLimits({
    this.maxRecords = 256,
    this.maxMetadataBytes = 64 * 1024,
  });

  static const int minimumMetadataBytes = 48;
  static const int maximumRecords = 65536;
  static const int maximumMetadataBytes = 16 * 1024 * 1024;

  final int maxRecords;
  final int maxMetadataBytes;

  void validate() {
    if (maxRecords < 1 || maxRecords > maximumRecords) {
      throw ArgumentError.value(
        maxRecords,
        'maxRecords',
        'must be between 1 and $maximumRecords',
      );
    }
    if (maxMetadataBytes < minimumMetadataBytes ||
        maxMetadataBytes > maximumMetadataBytes) {
      throw ArgumentError.value(
        maxMetadataBytes,
        'maxMetadataBytes',
        'must be between $minimumMetadataBytes and $maximumMetadataBytes',
      );
    }
  }
}

/// Immutable, content-conscious observation of one parser action.
///
/// CSI/DCS syntax metadata is copied because it is required to identify a
/// sequence. OSC/DCS/SOS/PM/APC payload bytes are never retained; only their
/// bounded parser-reported length and terminator are exposed.
final class VtParserInspectionEvent {
  VtParserInspectionEvent._({
    required this.ordinal,
    required this.kind,
    this.state,
    this.controlByte,
    this.privateMarker,
    List<int?> parameters = const <int?>[],
    List<bool> subparameters = const <bool>[],
    Uint8List? intermediates,
    this.finalByte,
    this.stringKind,
    this.payloadLength = 0,
    this.terminator,
    this.limitKind,
  }) : parameters = List<int?>.unmodifiable(parameters),
       subparameters = List<bool>.unmodifiable(subparameters),
       _intermediates = Uint8List.fromList(intermediates ?? Uint8List(0)),
       metadataBytes =
           48 + parameters.length * 5 + (intermediates?.length ?? 0) {
    if (this.parameters.length != this.subparameters.length) {
      throw ArgumentError('parameter metadata lengths differ');
    }
  }

  final int ordinal;
  final VtParserInspectionKind kind;
  final VtParserState? state;
  final int? controlByte;
  final int? privateMarker;
  final List<int?> parameters;
  final List<bool> subparameters;
  final Uint8List _intermediates;
  final int? finalByte;
  final VtStringKind? stringKind;
  final int payloadLength;
  final VtStringTerminator? terminator;
  final VtParserLimitKind? limitKind;

  /// Deterministic accounting cost used by the inspector's byte bound.
  final int metadataBytes;

  int get intermediateCount => _intermediates.length;

  int intermediateAt(int index) {
    RangeError.checkValidIndex(index, _intermediates);
    return _intermediates[index];
  }

  Uint8List copyIntermediates() => Uint8List.fromList(_intermediates);
}

/// Immutable copy of one bounded inspection generation.
final class VtParserInspectionSnapshot {
  VtParserInspectionSnapshot._({
    required this.captureEnabled,
    required this.limits,
    required this.printableScalarCount,
    required this.totalEventCount,
    required this.retainedMetadataBytes,
    required this.evictedEventCount,
    required this.oversizedEventCount,
    required this.observerFailureCount,
    required Iterable<VtParserInspectionEvent> events,
    required Uint64List kindCounts,
  }) : events = List<VtParserInspectionEvent>.unmodifiable(events),
       _kindCounts = Uint64List.fromList(kindCounts);

  final bool captureEnabled;
  final VtParserInspectorLimits limits;
  final int printableScalarCount;
  final int totalEventCount;
  final int retainedMetadataBytes;
  final int evictedEventCount;
  final int oversizedEventCount;
  final int observerFailureCount;
  final List<VtParserInspectionEvent> events;
  final Uint64List _kindCounts;

  int get droppedEventCount => evictedEventCount + oversizedEventCount;

  int eventCount(VtParserInspectionKind kind) => _kindCounts[kind.index];
}

/// Optional bounded sink decorator for inspecting typed parser actions.
///
/// The downstream sink always runs first. Inspector bookkeeping and the
/// optional observer cannot change downstream exceptions or parser semantics;
/// observer exceptions are counted and suppressed. A disabled product-owned
/// decorator forwards without retaining records, counters, or observer work.
final class VtParserInspector implements VtParserSink, VtParserAsciiSink {
  factory VtParserInspector({
    required VtParserSink downstream,
    VtParserInspectorLimits limits = const VtParserInspectorLimits(),
    VtParserInspectionObserver? onEvent,
    bool captureEnabled = true,
  }) {
    limits.validate();
    return VtParserInspector._(
      downstream: downstream,
      limits: limits,
      onEvent: onEvent,
      captureEnabled: captureEnabled,
    );
  }

  VtParserInspector._({
    required this.downstream,
    required this.limits,
    required VtParserInspectionObserver? onEvent,
    required bool captureEnabled,
  }) : _onEvent = onEvent,
       _captureEnabled = captureEnabled,
       _asciiDownstream = downstream is VtParserAsciiSink
           ? downstream as VtParserAsciiSink
           : null;

  final VtParserSink downstream;
  final VtParserInspectorLimits limits;
  final VtParserAsciiSink? _asciiDownstream;
  final ListQueue<VtParserInspectionEvent> _events =
      ListQueue<VtParserInspectionEvent>();
  final Uint64List _kindCounts = Uint64List(
    VtParserInspectionKind.values.length,
  );

  int _nextOrdinal = 1;
  int _printableScalarCount = 0;
  int _totalEventCount = 0;
  int _retainedMetadataBytes = 0;
  int _evictedEventCount = 0;
  int _oversizedEventCount = 0;
  int _observerFailureCount = 0;
  VtParserInspectionObserver? _onEvent;
  bool _captureEnabled;

  bool get captureEnabled => _captureEnabled;
  int get printableScalarCount => _printableScalarCount;
  int get totalEventCount => _totalEventCount;
  int get retainedMetadataBytes => _retainedMetadataBytes;
  int get evictedEventCount => _evictedEventCount;
  int get oversizedEventCount => _oversizedEventCount;
  int get droppedEventCount => _evictedEventCount + _oversizedEventCount;
  int get observerFailureCount => _observerFailureCount;

  List<VtParserInspectionEvent> get events =>
      List<VtParserInspectionEvent>.unmodifiable(_events);

  int eventCount(VtParserInspectionKind kind) => _kindCounts[kind.index];

  VtParserInspectionSnapshot snapshot() => VtParserInspectionSnapshot._(
    captureEnabled: _captureEnabled,
    limits: limits,
    printableScalarCount: _printableScalarCount,
    totalEventCount: _totalEventCount,
    retainedMetadataBytes: _retainedMetadataBytes,
    evictedEventCount: _evictedEventCount,
    oversizedEventCount: _oversizedEventCount,
    observerFailureCount: _observerFailureCount,
    events: _events,
    kindCounts: _kindCounts,
  );

  /// Clears prior metadata and starts a fresh bounded capture.
  void beginCapture({VtParserInspectionObserver? onEvent}) {
    clear();
    _onEvent = onEvent;
    _captureEnabled = true;
  }

  /// Stops capture before optionally clearing every retained aggregate.
  void endCapture({bool clearRetained = true}) {
    _captureEnabled = false;
    _onEvent = null;
    if (clearRetained) clear();
  }

  /// Clears all retained records and aggregate counters.
  void clear() {
    _events.clear();
    _kindCounts.fillRange(0, _kindCounts.length, 0);
    _nextOrdinal = 1;
    _printableScalarCount = 0;
    _totalEventCount = 0;
    _retainedMetadataBytes = 0;
    _evictedEventCount = 0;
    _oversizedEventCount = 0;
    _observerFailureCount = 0;
  }

  @override
  void print(int scalar) {
    downstream.print(scalar);
    if (_captureEnabled) _printableScalarCount++;
  }

  @override
  void printAscii(Uint8List bytes, int start, int end) {
    final VtParserAsciiSink? ascii = _asciiDownstream;
    if (ascii == null) {
      for (var index = start; index < end; index++) {
        downstream.print(bytes[index]);
      }
    } else {
      ascii.printAscii(bytes, start, end);
    }
    if (_captureEnabled) _printableScalarCount += end - start;
  }

  @override
  void execute(int controlByte) {
    downstream.execute(controlByte);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.execute,
        controlByte: controlByte,
      ),
    );
  }

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    downstream.dispatchEscape(sequence);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.escape,
        intermediates: sequence.copyIntermediates(),
        finalByte: sequence.finalByte,
      ),
    );
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    downstream.dispatchCsi(sequence);
    if (!_captureEnabled) return;
    _recordHeader(VtParserInspectionKind.controlSequence, sequence);
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    downstream.dispatchOsc(sequence);
    if (!_captureEnabled) return;
    _recordString(VtParserInspectionKind.operatingSystemCommand, sequence);
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    downstream.dispatchDcs(sequence);
    if (!_captureEnabled) return;
    final ({List<int?> values, List<bool> subparameters}) parameters =
        _copyParameters(sequence.header.parameters);
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.deviceControlString,
        privateMarker: sequence.header.privateMarker,
        parameters: parameters.values,
        subparameters: parameters.subparameters,
        intermediates: sequence.header.copyIntermediates(),
        finalByte: sequence.header.finalByte,
        stringKind: VtStringKind.deviceControlString,
        payloadLength: sequence.payloadLength,
        terminator: sequence.terminator,
      ),
    );
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    downstream.dispatchString(sequence);
    if (!_captureEnabled) return;
    _recordString(VtParserInspectionKind.controlString, sequence);
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    downstream.cancel(state, controlByte);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.cancel,
        state: state,
        controlByte: controlByte,
      ),
    );
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    downstream.limit(state, kind);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.limit,
        state: state,
        limitKind: kind,
      ),
    );
  }

  @override
  void malformed(VtParserState state, int byte) {
    downstream.malformed(state, byte);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.malformed,
        state: state,
        controlByte: byte,
      ),
    );
  }

  @override
  void incomplete(VtParserState state) {
    downstream.incomplete(state);
    if (!_captureEnabled) return;
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: VtParserInspectionKind.incomplete,
        state: state,
      ),
    );
  }

  void _recordHeader(VtParserInspectionKind kind, VtSequenceHeader header) {
    final ({List<int?> values, List<bool> subparameters}) parameters =
        _copyParameters(header.parameters);
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: kind,
        privateMarker: header.privateMarker,
        parameters: parameters.values,
        subparameters: parameters.subparameters,
        intermediates: header.copyIntermediates(),
        finalByte: header.finalByte,
      ),
    );
  }

  void _recordString(VtParserInspectionKind kind, VtStringSequence sequence) {
    _record(
      VtParserInspectionEvent._(
        ordinal: _claimOrdinal(),
        kind: kind,
        stringKind: sequence.kind,
        payloadLength: sequence.payloadLength,
        terminator: sequence.terminator,
      ),
    );
  }

  ({List<int?> values, List<bool> subparameters}) _copyParameters(
    VtParameters parameters,
  ) {
    final List<int?> values = List<int?>.filled(parameters.length, null);
    final List<bool> subparameters = List<bool>.filled(
      parameters.length,
      false,
    );
    for (var index = 0; index < parameters.length; index++) {
      values[index] = parameters.valueAt(index);
      subparameters[index] = parameters.isSubparameter(index);
    }
    return (values: values, subparameters: subparameters);
  }

  int _claimOrdinal() => _nextOrdinal++;

  void _record(VtParserInspectionEvent event) {
    _totalEventCount++;
    _kindCounts[event.kind.index]++;
    if (event.metadataBytes > limits.maxMetadataBytes) {
      _oversizedEventCount++;
    } else {
      while (_events.isNotEmpty &&
          (_events.length >= limits.maxRecords ||
              _retainedMetadataBytes + event.metadataBytes >
                  limits.maxMetadataBytes)) {
        _retainedMetadataBytes -= _events.removeFirst().metadataBytes;
        _evictedEventCount++;
      }
      _events.addLast(event);
      _retainedMetadataBytes += event.metadataBytes;
    }
    final VtParserInspectionObserver? observer = _onEvent;
    if (observer != null) {
      try {
        observer(event);
      } on Object {
        _observerFailureCount++;
      }
    }
  }
}
