import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_application_evidence.dart';
import 'terminal_application_matrix.dart';

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    throw const FormatException('unsupported arguments');
  }
  final TerminalApplicationMatrixManifest manifest =
      TerminalApplicationMatrixManifest.load(
        File(defaultTerminalApplicationMatrixPath),
      );
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  for (final TerminalApplicationScenario scenario in manifest.scenarios) {
    final File source = File(
      'test/corpus/applications/external/${scenario.id}.capture.json',
    );
    final TerminalApplicationRawEvidence raw =
        TerminalApplicationRawEvidence.parse(
          source.readAsStringSync(),
          scenario: scenario,
        );
    final TerminalApplicationUnsupportedTrace trace =
        traceTerminalApplicationUnsupported(
          raw.output,
          rows: scenario.rows,
          columns: scenario.columns,
          resizes: raw.resizes,
        );
    results.add(<String, Object?>{
      'application_id': scenario.applicationId,
      'scenario_id': scenario.id,
      'expected_unsupported_sequences': raw.parser['unsupported_sequences'],
      'traced_unsupported_sequences': trace.unsupportedSequences,
      'entries': <Map<String, Object?>>[
        for (final TerminalApplicationUnsupportedEntry entry in trace.entries)
          <String, Object?>{
            'kind': entry.kind,
            'hex': entry.hex,
            'occurrences': entry.occurrences,
            'unsupported_increments': entry.unsupportedIncrements,
          },
      ],
    });
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
}

final class TerminalApplicationUnsupportedEntry {
  TerminalApplicationUnsupportedEntry({
    required this.kind,
    required this.bytes,
    required this.occurrences,
    required this.unsupportedIncrements,
  });

  final String kind;
  final Uint8List bytes;
  int occurrences;
  int unsupportedIncrements;

  String get hex => _hex(bytes);
}

final class TerminalApplicationUnsupportedTrace {
  const TerminalApplicationUnsupportedTrace({
    required this.entries,
    required this.unsupportedControls,
    required this.unsupportedSequences,
    required this.cancel,
    required this.limit,
    required this.malformed,
    required this.incomplete,
  });

  final List<TerminalApplicationUnsupportedEntry> entries;
  final int unsupportedControls;
  final int unsupportedSequences;
  final int cancel;
  final int limit;
  final int malformed;
  final int incomplete;
}

TerminalApplicationUnsupportedTrace traceTerminalApplicationUnsupported(
  Uint8List output, {
  int rows = 24,
  int columns = 80,
  List<TerminalApplicationRawResize> resizes =
      const <TerminalApplicationRawResize>[],
}) {
  final TerminalScreenSet screens = TerminalScreenSet(
    rows: rows,
    columns: columns,
  );
  final TerminalScreenParserSink product =
      TerminalScreenParserSink.forScreenSet(
        screens,
        onReply: (Uint8List _) => true,
      );
  final _TracingSink tracing = _TracingSink(product);
  final VtParser parser = VtParser(sink: tracing);
  var offset = 0;
  for (final TerminalApplicationRawResize resize in resizes) {
    if (resize.outputBytesBefore < offset ||
        resize.outputBytesBefore > output.length) {
      throw StateError('resize output offset is outside the raw stream');
    }
    parser.parse(
      Uint8List.sublistView(output, offset, resize.outputBytesBefore),
    );
    screens.resize(rows: resize.rows, columns: resize.columns);
    offset = resize.outputBytesBefore;
  }
  parser.parse(Uint8List.sublistView(output, offset));
  parser.finish();
  return TerminalApplicationUnsupportedTrace(
    entries: tracing.entries,
    unsupportedControls: product.unsupportedControlCount,
    unsupportedSequences: product.unsupportedSequenceCount,
    cancel: product.cancelCount,
    limit: product.limitCount,
    malformed: product.malformedCount,
    incomplete: product.incompleteCount,
  );
}

bool terminalApplicationUnsupportedMutatesScreen(Uint8List sequence) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 24, columns: 80);
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List _) => true,
  );
  const TerminalSnapshotFormatter formatter = TerminalSnapshotFormatter();
  final String before = formatter.formatScreenSet(screens);
  final VtParser parser = VtParser(sink: sink);
  parser.parse(sequence);
  parser.finish();
  if (sink.unsupportedControlCount + sink.unsupportedSequenceCount == 0 ||
      sink.cancelCount != 0 ||
      sink.limitCount != 0 ||
      sink.malformedCount != 0 ||
      sink.incompleteCount != 0) {
    throw StateError('minimal unsupported sequence has an invalid outcome');
  }
  return before != formatter.formatScreenSet(screens);
}

final class _TracingSink implements VtParserSink {
  _TracingSink(this.product);

  final TerminalScreenParserSink product;
  final Map<String, TerminalApplicationUnsupportedEntry> _entries =
      <String, TerminalApplicationUnsupportedEntry>{};

  List<TerminalApplicationUnsupportedEntry> get entries {
    final List<TerminalApplicationUnsupportedEntry> result = _entries.values
        .toList();
    result.sort((
      TerminalApplicationUnsupportedEntry left,
      TerminalApplicationUnsupportedEntry right,
    ) {
      final int kind = left.kind.compareTo(right.kind);
      return kind == 0 ? left.hex.compareTo(right.hex) : kind;
    });
    return result;
  }

  @override
  void print(int scalar) => product.print(scalar);

  @override
  void execute(int controlByte) {
    final int before = product.unsupportedControlCount;
    product.execute(controlByte);
    _record(
      kind: 'control',
      bytes: Uint8List.fromList(<int>[controlByte]),
      increments: product.unsupportedControlCount - before,
    );
  }

  @override
  void dispatchEscape(VtEscapeSequence sequence) {
    final int before = product.unsupportedSequenceCount;
    product.dispatchEscape(sequence);
    _record(
      kind: 'escape',
      bytes: Uint8List.fromList(<int>[
        0x1b,
        ...sequence.copyIntermediates(),
        sequence.finalByte,
      ]),
      increments: product.unsupportedSequenceCount - before,
    );
  }

  @override
  void dispatchCsi(VtSequenceHeader sequence) {
    final int before = product.unsupportedSequenceCount;
    product.dispatchCsi(sequence);
    _record(
      kind: 'csi',
      bytes: _encodeCsi(sequence),
      increments: product.unsupportedSequenceCount - before,
    );
  }

  @override
  void dispatchOsc(VtStringSequence sequence) {
    final int before = product.unsupportedSequenceCount;
    product.dispatchOsc(sequence);
    _record(
      kind: 'osc',
      bytes: _encodeString(sequence),
      increments: product.unsupportedSequenceCount - before,
    );
  }

  @override
  void dispatchDcs(VtDcsSequence sequence) {
    final int before = product.unsupportedSequenceCount;
    product.dispatchDcs(sequence);
    _record(
      kind: 'dcs',
      bytes: Uint8List.fromList(<int>[
        0x1b,
        0x50,
        ..._encodeHeader(sequence.header),
        ...sequence.copyPayload(),
        0x1b,
        0x5c,
      ]),
      increments: product.unsupportedSequenceCount - before,
    );
  }

  @override
  void dispatchString(VtStringSequence sequence) {
    final int before = product.unsupportedSequenceCount;
    product.dispatchString(sequence);
    _record(
      kind: switch (sequence.kind) {
        VtStringKind.startOfString => 'sos',
        VtStringKind.privacyMessage => 'pm',
        VtStringKind.applicationProgramCommand => 'apc',
        VtStringKind.operatingSystemCommand => 'osc',
        VtStringKind.deviceControlString => 'dcs',
      },
      bytes: _encodeString(sequence),
      increments: product.unsupportedSequenceCount - before,
    );
  }

  @override
  void cancel(VtParserState state, int controlByte) {
    product.cancel(state, controlByte);
  }

  @override
  void limit(VtParserState state, VtParserLimitKind kind) {
    product.limit(state, kind);
  }

  @override
  void malformed(VtParserState state, int byte) {
    product.malformed(state, byte);
  }

  @override
  void incomplete(VtParserState state) {
    product.incomplete(state);
  }

  void _record({
    required String kind,
    required Uint8List bytes,
    required int increments,
  }) {
    if (increments == 0) return;
    final String key = '$kind:${_hex(bytes)}';
    final TerminalApplicationUnsupportedEntry? existing = _entries[key];
    if (existing != null) {
      existing.occurrences++;
      existing.unsupportedIncrements += increments;
      return;
    }
    _entries[key] = TerminalApplicationUnsupportedEntry(
      kind: kind,
      bytes: bytes,
      occurrences: 1,
      unsupportedIncrements: increments,
    );
  }
}

Uint8List _encodeCsi(VtSequenceHeader sequence) =>
    Uint8List.fromList(<int>[0x1b, 0x5b, ..._encodeHeader(sequence)]);

List<int> _encodeHeader(VtSequenceHeader sequence) {
  final List<int> bytes = <int>[];
  if (sequence.privateMarker case final int marker) bytes.add(marker);
  for (var index = 0; index < sequence.parameters.length; index++) {
    if (index != 0) {
      bytes.add(sequence.parameters.isSubparameter(index) ? 0x3a : 0x3b);
    }
    if (sequence.parameters.valueAt(index) case final int value) {
      bytes.addAll(value.toString().codeUnits);
    }
  }
  bytes.addAll(sequence.copyIntermediates());
  bytes.add(sequence.finalByte);
  return bytes;
}

Uint8List _encodeString(VtStringSequence sequence) {
  final int introducer = switch (sequence.kind) {
    VtStringKind.operatingSystemCommand => 0x5d,
    VtStringKind.deviceControlString => 0x50,
    VtStringKind.startOfString => 0x58,
    VtStringKind.privacyMessage => 0x5e,
    VtStringKind.applicationProgramCommand => 0x5f,
  };
  return Uint8List.fromList(<int>[
    0x1b,
    introducer,
    ...sequence.copyPayload(),
    if (sequence.terminator == VtStringTerminator.bell)
      0x07
    else ...<int>[0x1b, 0x5c],
  ]);
}

String _hex(List<int> bytes) =>
    bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
