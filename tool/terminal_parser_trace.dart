import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const String terminalParserTraceCasePath =
    'test/corpus/parser/sequence_trace_case_v1.json';
const String terminalParserTraceExpectedPath =
    'test/corpus/parser/sequence_trace_v1.json';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw const FormatException(
        'usage: terminal_parser_trace.dart '
        '[--check|--generate|--input-hex=HEX|--input-file=PATH]',
      );
    }
    final String argument = arguments.single;
    if (argument == '--check' || argument == '--generate') {
      final _TraceCase fixture = await _loadFixture();
      final String actual = _captureFixture(fixture);
      if (argument == '--generate') {
        await File(terminalParserTraceExpectedPath).writeAsString(actual);
        stdout.writeln(
          'TERMINAL_PARSER_TRACE_GENERATED '
          'path=$terminalParserTraceExpectedPath events=${fixture.eventCount}',
        );
        return;
      }
      final File expectedFile = File(terminalParserTraceExpectedPath);
      if (!await expectedFile.exists()) {
        throw StateError('missing parser trace: ${expectedFile.path}');
      }
      final String expected = await expectedFile.readAsString();
      if (actual != expected) {
        throw StateError(
          'stale parser trace; run '
          '`dart run tool/terminal_parser_trace.dart --generate`',
        );
      }
      stdout.writeln(
        'TERMINAL_PARSER_TRACE_CHECK_PASS '
        'input_bytes=${fixture.input.length} events=${fixture.eventCount}',
      );
      return;
    }

    final VtParserTraceExporter exporter = VtParserTraceExporter();
    if (argument.startsWith('--input-hex=')) {
      stdout.write(
        exporter.capture(_decodeHex(argument.substring('--input-hex='.length))),
      );
      return;
    }
    if (argument.startsWith('--input-file=')) {
      final File input = File(argument.substring('--input-file='.length));
      final int length = await input.length();
      if (length > exporter.limits.maxInputBytes) {
        throw VtParserTraceLimitException(
          kind: VtParserTraceLimitKind.inputBytes,
          actual: length,
          maximum: exporter.limits.maxInputBytes,
        );
      }
      stdout.write(exporter.capture(await input.readAsBytes()));
      return;
    }
    throw const FormatException('unknown parser trace option');
  } on Object catch (error) {
    stderr.writeln('TERMINAL_PARSER_TRACE_FAIL $error');
    exitCode = 64;
  }
}

String _captureFixture(_TraceCase fixture) {
  final VtParserTraceExporter exporter = VtParserTraceExporter(
    limits: fixture.exportLimits,
  );
  final String trace = exporter.capture(
    fixture.input,
    parserLimits: fixture.parserLimits,
    inspectorLimits: fixture.inspectorLimits,
  );
  final Object? root = jsonDecode(trace);
  if (root is! Map<String, Object?> ||
      root['events_total'] != fixture.eventCount) {
    throw StateError('fixture event count differs');
  }
  return trace;
}

Future<_TraceCase> _loadFixture() async {
  final Object? decoded = jsonDecode(
    await File(terminalParserTraceCasePath).readAsString(),
  );
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != 'dart-terminal-parser-trace-case' ||
      decoded['version'] != 1 ||
      decoded['case_id'] != 'all-action-families-redacted') {
    throw const FormatException('invalid parser trace fixture identity');
  }
  final Uint8List input = _decodeHex(_requiredString(decoded, 'input_hex'));
  final Map<String, Object?> parser = _requiredMap(decoded, 'parser_limits');
  final Map<String, Object?> inspector = _requiredMap(
    decoded,
    'inspector_limits',
  );
  final Map<String, Object?> export = _requiredMap(decoded, 'export_limits');
  final int eventCount = _requiredInt(decoded, 'expected_event_count');
  return _TraceCase(
    input: input,
    eventCount: eventCount,
    parserLimits: VtParserLimits(
      maxSequenceBytes: _requiredInt(parser, 'max_sequence_bytes'),
      maxStringBytes: _requiredInt(parser, 'max_string_bytes'),
      maxApplicationProgramCommandBytes: _requiredInt(
        parser,
        'max_application_program_command_bytes',
      ),
      maxParameters: _requiredInt(parser, 'max_parameters'),
      maxIntermediates: _requiredInt(parser, 'max_intermediates'),
      maxNumericValue: _requiredInt(parser, 'max_numeric_value'),
    ),
    inspectorLimits: VtParserInspectorLimits(
      maxRecords: _requiredInt(inspector, 'max_records'),
      maxMetadataBytes: _requiredInt(inspector, 'max_metadata_bytes'),
    ),
    exportLimits: VtParserTraceExportLimits(
      maxInputBytes: _requiredInt(export, 'max_input_bytes'),
      maxOutputBytes: _requiredInt(export, 'max_output_bytes'),
    ),
  );
}

Uint8List _decodeHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(value)) {
    throw const FormatException('input hex must be lowercase and byte-aligned');
  }
  final Uint8List result = Uint8List(value.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

Map<String, Object?> _requiredMap(Map<String, Object?> root, String key) {
  final Object? value = root[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object');
  }
  return value;
}

String _requiredString(Map<String, Object?> root, String key) {
  final Object? value = root[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _requiredInt(Map<String, Object?> root, String key) {
  final Object? value = root[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer');
  }
  return value;
}

final class _TraceCase {
  const _TraceCase({
    required this.input,
    required this.eventCount,
    required this.parserLimits,
    required this.inspectorLimits,
    required this.exportLimits,
  });

  final Uint8List input;
  final int eventCount;
  final VtParserLimits parserLimits;
  final VtParserInspectorLimits inspectorLimits;
  final VtParserTraceExportLimits exportLimits;
}
