import 'dart:convert';
import 'dart:typed_data';

import 'vt_parser.dart';
import 'vt_parser_inspector.dart';
import 'vt_parser_table.dart';

enum VtParserTraceLimitKind { inputBytes, outputBytes }

final class VtParserTraceLimitException implements Exception {
  const VtParserTraceLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final VtParserTraceLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'VtParserTraceLimitException(${kind.name}: $actual > $maximum)';
}

/// Hard input and serialized-output bounds for parser trace export.
final class VtParserTraceExportLimits {
  const VtParserTraceExportLimits({
    this.maxInputBytes = 1024 * 1024,
    this.maxOutputBytes = 1024 * 1024,
  });

  static const int maximumInputBytes = 16 * 1024 * 1024;
  static const int maximumOutputBytes = 16 * 1024 * 1024;

  final int maxInputBytes;
  final int maxOutputBytes;

  void validate() {
    if (maxInputBytes < 1 || maxInputBytes > maximumInputBytes) {
      throw ArgumentError.value(
        maxInputBytes,
        'maxInputBytes',
        'must be between 1 and $maximumInputBytes',
      );
    }
    if (maxOutputBytes < 1 || maxOutputBytes > maximumOutputBytes) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'must be between 1 and $maximumOutputBytes',
      );
    }
  }
}

/// Creates deterministic, privacy-conscious JSON from parser observations.
final class VtParserTraceExporter {
  factory VtParserTraceExporter({
    VtParserTraceExportLimits limits = const VtParserTraceExportLimits(),
  }) {
    limits.validate();
    return VtParserTraceExporter._(limits);
  }

  const VtParserTraceExporter._(this.limits);

  static const String formatName = 'dart-terminal-parser-trace';
  static const int formatVersion = 1;

  final VtParserTraceExportLimits limits;

  /// Parses [input] into a diagnostic-only sink and exports the observation.
  String capture(
    Uint8List input, {
    VtParserLimits parserLimits = const VtParserLimits(),
    VtParserInspectorLimits inspectorLimits = const VtParserInspectorLimits(),
  }) {
    _checkInputLength(input.length);
    final VtParserInspector inspector = VtParserInspector(
      downstream: const _DiscardingVtParserSink(),
      limits: inspectorLimits,
    );
    final VtParser parser = VtParser(sink: inspector, limits: parserLimits);
    parser.parse(input);
    parser.finish();
    return format(
      inspector,
      inputBytes: input.length,
      parserLimits: parserLimits,
    );
  }

  /// Exports an inspector populated by a caller-controlled chunk plan.
  String format(
    VtParserInspector inspector, {
    required int inputBytes,
    VtParserLimits parserLimits = const VtParserLimits(),
  }) {
    _checkInputLength(inputBytes);
    parserLimits.validate();
    final Map<String, Object?> report = <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'privacy': <String, Object?>{
        'printable_text': 'count_only',
        'string_payloads': 'length_only',
        'input_hash': 'omitted',
        'wall_clock': 'omitted',
        'paths': 'omitted',
        'environment': 'omitted',
      },
      'limits': <String, Object?>{
        'parser': <String, Object?>{
          'sequence_bytes': parserLimits.maxSequenceBytes,
          'string_bytes': parserLimits.maxStringBytes,
          'parameters': parserLimits.maxParameters,
          'intermediates': parserLimits.maxIntermediates,
          'numeric_value': parserLimits.maxNumericValue,
        },
        'inspector': <String, Object?>{
          'records': inspector.limits.maxRecords,
          'metadata_bytes': inspector.limits.maxMetadataBytes,
        },
        'export': <String, Object?>{
          'input_bytes': limits.maxInputBytes,
          'output_bytes': limits.maxOutputBytes,
        },
      },
      'input_bytes': inputBytes,
      'printable_scalars': inspector.printableScalarCount,
      'events_total': inspector.totalEventCount,
      'events_retained': inspector.events.length,
      'retained_metadata_bytes': inspector.retainedMetadataBytes,
      'events_evicted': inspector.evictedEventCount,
      'events_oversized': inspector.oversizedEventCount,
      'observer_failures': inspector.observerFailureCount,
      'event_counts': <String, Object?>{
        for (final VtParserInspectionKind kind in VtParserInspectionKind.values)
          kind.name: inspector.eventCount(kind),
      },
      'events': <Object?>[
        for (final VtParserInspectionEvent event in inspector.events)
          _eventJson(event),
      ],
    };
    final _BoundedByteSink output = _BoundedByteSink(limits.maxOutputBytes);
    final Sink<Object?> encoder = JsonUtf8Encoder('  ')
        .startChunkedConversion(output);
    encoder.add(report);
    encoder.close();
    output.add(const <int>[0x0a]);
    return utf8.decode(output.takeBytes());
  }

  void _checkInputLength(int length) {
    if (length < 0 || length > limits.maxInputBytes) {
      throw VtParserTraceLimitException(
        kind: VtParserTraceLimitKind.inputBytes,
        actual: length,
        maximum: limits.maxInputBytes,
      );
    }
  }

  Map<String, Object?> _eventJson(VtParserInspectionEvent event) {
    final Map<String, Object?> result = <String, Object?>{
      'ordinal': event.ordinal,
      'kind': event.kind.name,
      'metadata_bytes': event.metadataBytes,
    };
    final VtParserState? state = event.state;
    if (state != null) result['state'] = state.name;
    final int? controlByte = event.controlByte;
    if (controlByte != null) result['byte_hex'] = _byteHex(controlByte);
    final VtParserLimitKind? limitKind = event.limitKind;
    if (limitKind != null) result['limit'] = limitKind.name;

    switch (event.kind) {
      case VtParserInspectionKind.escape:
        result['canonical_bytes_hex'] = _hex(<int>[
          0x1b,
          ...event.copyIntermediates(),
          event.finalByte!,
        ]);
      case VtParserInspectionKind.controlSequence:
        _addHeaderJson(result, event, introducer: 0x5b);
        result['canonical_bytes_hex'] = _hex(
          _canonicalHeaderBytes(event, introducer: 0x5b),
        );
      case VtParserInspectionKind.deviceControlString:
        _addHeaderJson(result, event, introducer: 0x50);
        _addRedactedStringJson(result, event);
      case VtParserInspectionKind.operatingSystemCommand:
      case VtParserInspectionKind.controlString:
        _addRedactedStringJson(result, event);
      case VtParserInspectionKind.execute:
      case VtParserInspectionKind.cancel:
      case VtParserInspectionKind.limit:
      case VtParserInspectionKind.malformed:
      case VtParserInspectionKind.incomplete:
        break;
    }
    return result;
  }

  void _addHeaderJson(
    Map<String, Object?> result,
    VtParserInspectionEvent event, {
    required int introducer,
  }) {
    result['private_marker_hex'] = event.privateMarker == null
        ? null
        : _byteHex(event.privateMarker!);
    result['parameters'] = event.parameters;
    result['subparameters'] = event.subparameters;
    result['intermediates_hex'] = _hex(event.copyIntermediates());
    result['final_byte_hex'] = _byteHex(event.finalByte!);
    if (event.kind == VtParserInspectionKind.deviceControlString) {
      result['canonical_prefix_hex'] = _hex(
        _canonicalHeaderBytes(event, introducer: introducer),
      );
    }
  }

  void _addRedactedStringJson(
    Map<String, Object?> result,
    VtParserInspectionEvent event,
  ) {
    result['string_kind'] = event.stringKind!.name;
    result['canonical_prefix_hex'] ??= _hex(<int>[
      0x1b,
      _stringIntroducer(event.stringKind!),
    ]);
    result['payload_redacted_bytes'] = event.payloadLength;
    result['canonical_terminator_hex'] = switch (event.terminator!) {
      VtStringTerminator.bell => '07',
      VtStringTerminator.stringTerminator => '1b5c',
    };
  }

  List<int> _canonicalHeaderBytes(
    VtParserInspectionEvent event, {
    required int introducer,
  }) {
    final List<int> bytes = <int>[0x1b, introducer];
    final int? privateMarker = event.privateMarker;
    if (privateMarker != null) bytes.add(privateMarker);
    for (var index = 0; index < event.parameters.length; index++) {
      if (index != 0) {
        bytes.add(event.subparameters[index] ? 0x3a : 0x3b);
      }
      final int? value = event.parameters[index];
      if (value != null) bytes.addAll(ascii.encode(value.toString()));
    }
    bytes
      ..addAll(event.copyIntermediates())
      ..add(event.finalByte!);
    return bytes;
  }

  int _stringIntroducer(VtStringKind kind) => switch (kind) {
    VtStringKind.operatingSystemCommand => 0x5d,
    VtStringKind.deviceControlString => 0x50,
    VtStringKind.startOfString => 0x58,
    VtStringKind.privacyMessage => 0x5e,
    VtStringKind.applicationProgramCommand => 0x5f,
  };

  String _byteHex(int byte) => byte.toRadixString(16).padLeft(2, '0');

  String _hex(Iterable<int> bytes) {
    final StringBuffer result = StringBuffer();
    for (final int byte in bytes) {
      result.write(_byteHex(byte));
    }
    return result.toString();
  }
}

final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> data) {
    final int nextLength = _length + data.length;
    if (nextLength > maximumBytes) {
      throw VtParserTraceLimitException(
        kind: VtParserTraceLimitKind.outputBytes,
        actual: nextLength,
        maximum: maximumBytes,
      );
    }
    _bytes.add(data);
    _length = nextLength;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class _DiscardingVtParserSink implements VtParserSink, VtParserAsciiSink {
  const _DiscardingVtParserSink();

  @override
  void print(int scalar) {}

  @override
  void printAscii(Uint8List bytes, int start, int end) {}

  @override
  void execute(int controlByte) {}

  @override
  void dispatchEscape(VtEscapeSequence sequence) {}

  @override
  void dispatchCsi(VtSequenceHeader sequence) {}

  @override
  void dispatchOsc(VtStringSequence sequence) {}

  @override
  void dispatchDcs(VtDcsSequence sequence) {}

  @override
  void dispatchString(VtStringSequence sequence) {}

  @override
  void cancel(VtParserState state, int controlByte) {}

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {}

  @override
  void malformed(VtParserState state, int byte) {}

  @override
  void incomplete(VtParserState state) {}
}
