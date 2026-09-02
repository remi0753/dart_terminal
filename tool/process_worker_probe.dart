import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const bool _selfExecutingAot = bool.fromEnvironment('PROCESS_PROBE_SELF_EXEC');

const int _protocolMagic = 0x4454;
const int _protocolVersion = 1;
const int _headerLength = 12;
const int _maximumPayloadLength = 1024 * 1024;
const int _bulkByteCount = 128 * 1024 * 1024;
const int _bulkChunkLength = 1024 * 1024;
const Duration _operationTimeout = Duration(seconds: 10);

const int _readyType = 1;
const int _pingType = 2;
const int _pongType = 3;
const int _bulkBeginType = 4;
const int _bulkChunkType = 5;
const int _bulkDoneType = 6;
const int _crashType = 7;
const int _hangType = 8;
const int _hangAcknowledgedType = 9;
const int _stopType = 10;
const int _stopAcknowledgedType = 11;

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--worker') {
    await _runWorker();
    return;
  }
  if (arguments.isNotEmpty) {
    throw ArgumentError('usage: process_worker_probe.dart [--worker]');
  }
  await _runSupervisor();
}

Future<void> _runSupervisor() async {
  final String executable = Platform.resolvedExecutable;
  final List<String> workerArguments;
  final String mode;
  if (_selfExecutingAot) {
    workerArguments = <String>[];
    mode = 'aot';
  } else {
    if (Platform.script.scheme != 'file') {
      throw StateError('JIT probe source is not a file URI');
    }
    workerArguments = <String>[Platform.script.toFilePath()];
    mode = 'jit';
  }

  final List<_WorkerClient> clients = <_WorkerClient>[];
  final List<int> workerPids = <int>[];
  final List<int> startupMicros = <int>[];
  late final _BulkResult bulkResult;
  late final int gracefulExit;
  late final int crashExit;
  late final bool crashDiagnosticPreserved;
  late final int forcedExit;

  try {
    final _WorkerClient normal = await _launchTracked(
      executable,
      workerArguments,
      clients,
      workerPids,
      startupMicros,
    );
    await normal.ping(0x1020304050607080);
    bulkResult = await normal.transferBulkData();
    gracefulExit = await normal.stop();
    _require(gracefulExit == 0, 'graceful worker exited $gracefulExit');

    final _WorkerClient crashing = await _launchTracked(
      executable,
      workerArguments,
      clients,
      workerPids,
      startupMicros,
    );
    crashExit = await crashing.crash();
    crashDiagnosticPreserved = crashing.diagnostics.contains(
      'intentional process worker failure',
    );
    _require(crashExit != 0, 'crashing worker exited successfully');
    _require(
      crashDiagnosticPreserved,
      'crashing worker did not preserve its stderr diagnostic',
    );

    final _WorkerClient crashReplacement = await _launchTracked(
      executable,
      workerArguments,
      clients,
      workerPids,
      startupMicros,
    );
    await crashReplacement.ping(0x1122334455667788);
    _require(
      await crashReplacement.stop() == 0,
      'replacement after crash did not stop cleanly',
    );

    final _WorkerClient hanging = await _launchTracked(
      executable,
      workerArguments,
      clients,
      workerPids,
      startupMicros,
    );
    forcedExit = await hanging.hangAndKill();
    _require(forcedExit != 0, 'forcibly killed worker exited successfully');

    final _WorkerClient killReplacement = await _launchTracked(
      executable,
      workerArguments,
      clients,
      workerPids,
      startupMicros,
    );
    await killReplacement.ping(0x8877665544332211);
    _require(
      await killReplacement.stop() == 0,
      'replacement after forced termination did not stop cleanly',
    );
  } finally {
    for (final _WorkerClient client in clients) {
      await client.abortIfRunning();
    }
  }

  _require(
    workerPids.every((int workerPid) => workerPid != pid),
    'worker reused the supervisor process',
  );
  _require(
    _WorkerClient.outstanding == 0,
    '${_WorkerClient.outstanding} worker processes remain outstanding',
  );
  final int averageStartupMicros =
      startupMicros.reduce((int left, int right) => left + right) ~/
      startupMicros.length;

  stdout.writeln('probe.mode=$mode');
  stdout.writeln('probe.ready=true');
  stdout.writeln('probe.distinct_processes=true');
  stdout.writeln('probe.bulk_bytes=${bulkResult.byteCount}');
  stdout.writeln('probe.bulk_micros=${bulkResult.elapsedMicros}');
  stdout.writeln(
    'probe.bulk_mib_per_second='
    '${bulkResult.mebibytesPerSecond.toStringAsFixed(2)}',
  );
  stdout.writeln('probe.startup_micros=$averageStartupMicros');
  stdout.writeln('probe.graceful_exit=$gracefulExit');
  stdout.writeln('probe.crash_exit=$crashExit');
  stdout.writeln('probe.crash_stderr=$crashDiagnosticPreserved');
  stdout.writeln('probe.forced_exit=$forcedExit');
  stdout.writeln('probe.replacements=2');
  stdout.writeln('probe.final_outstanding=${_WorkerClient.outstanding}');
  stdout.writeln('probe.passed=true');
}

Future<_WorkerClient> _launchTracked(
  String executable,
  List<String> arguments,
  List<_WorkerClient> clients,
  List<int> workerPids,
  List<int> startupMicros,
) async {
  final _WorkerClient client = await _WorkerClient.launch(
    executable,
    arguments,
  );
  clients.add(client);
  workerPids.add(client.workerPid);
  startupMicros.add(client.startupMicros);
  return client;
}

Future<void> _runWorker() async {
  final _FrameReader reader = _FrameReader(stdin);
  final _FrameWriter writer = _FrameWriter(stdout);
  try {
    await writer.send(_readyType, 0, _uint64Payload(pid));
    while (true) {
      final _Frame? command = await reader.next();
      if (command == null) {
        return;
      }
      switch (command.type) {
        case _pingType:
          _require(command.payload.length == 8, 'invalid ping payload');
          await writer.send(_pongType, command.identifier, command.payload);
          continue;
        case _bulkBeginType:
          await _receiveBulkData(command, reader, writer);
          continue;
        case _crashType:
          throw StateError('intentional process worker failure');
        case _hangType:
          await writer.send(
            _hangAcknowledgedType,
            command.identifier,
            Uint8List(0),
          );
          await Completer<void>().future;
          continue;
        case _stopType:
          await writer.send(
            _stopAcknowledgedType,
            command.identifier,
            Uint8List(0),
          );
          return;
        default:
          throw StateError('unknown worker command type ${command.type}');
      }
    }
  } finally {
    await reader.cancel();
    await stdout.flush();
  }
}

Future<void> _receiveBulkData(
  _Frame begin,
  _FrameReader reader,
  _FrameWriter writer,
) async {
  _require(begin.payload.length == 8, 'invalid bulk-begin payload');
  final ByteData description = ByteData.sublistView(begin.payload);
  final int byteCount = description.getUint32(0, Endian.big);
  final int chunkLength = description.getUint32(4, Endian.big);
  _require(byteCount == _bulkByteCount, 'unexpected bulk byte count');
  _require(
    chunkLength > 0 && chunkLength <= _maximumPayloadLength,
    'invalid bulk chunk length',
  );
  _require(byteCount % chunkLength == 0, 'partial bulk chunk is unsupported');

  final int chunkCount = byteCount ~/ chunkLength;
  var receivedBytes = 0;
  for (var sequence = 0; sequence < chunkCount; sequence += 1) {
    final _Frame? chunk = await reader.next();
    _require(chunk != null, 'bulk stream ended before chunk $sequence');
    _require(chunk!.type == _bulkChunkType, 'expected bulk chunk $sequence');
    _require(chunk.identifier == sequence, 'out-of-order bulk chunk');
    _require(chunk.payload.length == chunkLength, 'short bulk chunk');
    _verifyChunkMarkers(chunk.payload, sequence);
    receivedBytes += chunk.payload.length;
  }
  _require(receivedBytes == byteCount, 'bulk byte count did not match');
  await writer.send(
    _bulkDoneType,
    begin.identifier,
    _uint64Payload(receivedBytes),
  );
}

class _WorkerClient {
  _WorkerClient._(
    this._process,
    this._reader,
    this._writer,
    this._stderrText,
    this.workerPid,
    this.startupMicros,
  );

  static int outstanding = 0;

  final Process _process;
  final _FrameReader _reader;
  final _FrameWriter _writer;
  final Future<String> _stderrText;
  final int workerPid;
  int startupMicros;
  var _nextIdentifier = 1;
  var _reaped = false;
  int? _exitStatus;
  String _diagnostics = '';

  String get diagnostics => _diagnostics;

  static Future<_WorkerClient> launch(
    String executable,
    List<String> arguments,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final Process process = await Process.start(executable, <String>[
      ...arguments,
      '--worker',
    ]);
    outstanding += 1;
    final _WorkerClient client = _WorkerClient._(
      process,
      _FrameReader(process.stdout),
      _FrameWriter(process.stdin),
      process.stderr.transform(utf8.decoder).join(),
      process.pid,
      0,
    );
    try {
      final _Frame ready = await client._expect(_readyType, 0);
      _require(ready.payload.length == 8, 'invalid ready payload');
      final int reportedPid = _readUint64(ready.payload);
      _require(
        reportedPid == process.pid,
        'ready PID $reportedPid did not match process PID ${process.pid}',
      );
      stopwatch.stop();
      client.startupMicros = stopwatch.elapsedMicroseconds;
      return client;
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      await client._reap();
      rethrow;
    }
  }

  Future<void> ping(int value) async {
    final int identifier = _takeIdentifier();
    final Uint8List payload = _uint64Payload(value);
    await _writer.send(_pingType, identifier, payload);
    final _Frame response = await _expect(_pongType, identifier);
    _require(
      _bytesEqual(response.payload, payload),
      'ping response payload did not match',
    );
  }

  Future<_BulkResult> transferBulkData() async {
    final int identifier = _takeIdentifier();
    final ByteData description = ByteData(8)
      ..setUint32(0, _bulkByteCount, Endian.big)
      ..setUint32(4, _bulkChunkLength, Endian.big);
    final Stopwatch stopwatch = Stopwatch()..start();
    await _writer.send(
      _bulkBeginType,
      identifier,
      description.buffer.asUint8List(),
    );
    final Uint8List payload = Uint8List(_bulkChunkLength);
    final int chunkCount = _bulkByteCount ~/ _bulkChunkLength;
    for (var sequence = 0; sequence < chunkCount; sequence += 1) {
      _writeChunkMarkers(payload, sequence);
      await _writer.send(_bulkChunkType, sequence, payload);
    }
    final _Frame response = await _expect(_bulkDoneType, identifier);
    stopwatch.stop();
    _require(response.payload.length == 8, 'invalid bulk-done payload');
    final int receivedBytes = _readUint64(response.payload);
    _require(receivedBytes == _bulkByteCount, 'worker lost bulk data');
    return _BulkResult(receivedBytes, stopwatch.elapsedMicroseconds);
  }

  Future<int> stop() async {
    final int identifier = _takeIdentifier();
    await _writer.send(_stopType, identifier, Uint8List(0));
    await _expect(_stopAcknowledgedType, identifier);
    return _reap();
  }

  Future<int> crash() async {
    final int identifier = _takeIdentifier();
    await _writer.send(_crashType, identifier, Uint8List(0));
    return _reap();
  }

  Future<int> hangAndKill() async {
    final int identifier = _takeIdentifier();
    await _writer.send(_hangType, identifier, Uint8List(0));
    await _expect(_hangAcknowledgedType, identifier);
    _require(
      _process.kill(ProcessSignal.sigkill),
      'could not terminate hanging worker',
    );
    return _reap();
  }

  Future<void> abortIfRunning() async {
    if (_reaped) {
      return;
    }
    _process.kill(ProcessSignal.sigkill);
    await _reap();
  }

  int _takeIdentifier() {
    final int identifier = _nextIdentifier;
    _nextIdentifier += 1;
    return identifier;
  }

  Future<_Frame> _expect(int type, int identifier) async {
    final _Frame? frame = await _reader.next().timeout(_operationTimeout);
    _require(frame != null, 'worker exited while waiting for frame type $type');
    _require(
      frame!.type == type,
      'expected frame type $type, got ${frame.type}',
    );
    _require(
      frame.identifier == identifier,
      'expected frame identifier $identifier, got ${frame.identifier}',
    );
    return frame;
  }

  Future<int> _reap() async {
    if (_reaped) {
      return _exitStatus!;
    }
    await _process.stdin.close();
    final int status = await _process.exitCode.timeout(_operationTimeout);
    _diagnostics = await _stderrText.timeout(_operationTimeout);
    await _reader.cancel();
    _exitStatus = status;
    _reaped = true;
    outstanding -= 1;
    return status;
  }
}

class _BulkResult {
  const _BulkResult(this.byteCount, this.elapsedMicros);

  final int byteCount;
  final int elapsedMicros;

  double get mebibytesPerSecond =>
      byteCount / (1024 * 1024) * 1000000 / elapsedMicros;
}

class _Frame {
  const _Frame(this.type, this.identifier, this.payload);

  final int type;
  final int identifier;
  final Uint8List payload;
}

class _FrameReader {
  _FrameReader(Stream<List<int>> stream)
    : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  List<int>? _chunk;
  var _chunkOffset = 0;
  var _cancelled = false;

  Future<_Frame?> next() async {
    final Uint8List? header = await _readExact(
      _headerLength,
      allowCleanEnd: true,
    );
    if (header == null) {
      return null;
    }
    final ByteData fields = ByteData.sublistView(header);
    _require(fields.getUint16(0, Endian.big) == _protocolMagic, 'bad magic');
    _require(
      fields.getUint8(2) == _protocolVersion,
      'unsupported protocol version',
    );
    final int type = fields.getUint8(3);
    final int identifier = fields.getUint32(4, Endian.big);
    final int payloadLength = fields.getUint32(8, Endian.big);
    _require(
      payloadLength <= _maximumPayloadLength,
      'frame payload exceeds $_maximumPayloadLength bytes',
    );
    final Uint8List payload =
        await _readExact(payloadLength) ??
        (throw StateError('frame payload unexpectedly ended'));
    return _Frame(type, identifier, payload);
  }

  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    await _iterator.cancel();
  }

  Future<Uint8List?> _readExact(
    int length, {
    bool allowCleanEnd = false,
  }) async {
    final Uint8List result = Uint8List(length);
    var written = 0;
    while (written < length) {
      final List<int>? chunk = _chunk;
      if (chunk == null || _chunkOffset == chunk.length) {
        final bool hasMore = await _iterator.moveNext();
        if (!hasMore) {
          if (allowCleanEnd && written == 0) {
            return null;
          }
          throw StateError('stream ended after $written of $length bytes');
        }
        _chunk = _iterator.current;
        _chunkOffset = 0;
        continue;
      }
      final int available = chunk.length - _chunkOffset;
      final int needed = length - written;
      final int copied = available < needed ? available : needed;
      result.setRange(written, written + copied, chunk, _chunkOffset);
      written += copied;
      _chunkOffset += copied;
    }
    return result;
  }
}

class _FrameWriter {
  const _FrameWriter(this._sink);

  final IOSink _sink;

  Future<void> send(int type, int identifier, Uint8List payload) async {
    _require(
      payload.length <= _maximumPayloadLength,
      'payload exceeds $_maximumPayloadLength bytes',
    );
    final ByteData header = ByteData(_headerLength)
      ..setUint16(0, _protocolMagic, Endian.big)
      ..setUint8(2, _protocolVersion)
      ..setUint8(3, type)
      ..setUint32(4, identifier, Endian.big)
      ..setUint32(8, payload.length, Endian.big);
    _sink.add(header.buffer.asUint8List());
    _sink.add(payload);
    await _sink.flush();
  }
}

Uint8List _uint64Payload(int value) {
  final ByteData data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _readUint64(Uint8List payload) =>
    ByteData.sublistView(payload).getUint64(0, Endian.big);

void _writeChunkMarkers(Uint8List payload, int sequence) {
  payload.fillRange(0, payload.length, sequence % 251);
  payload[0] = sequence & 0xff;
  payload[payload.length ~/ 2] = (sequence * 3) & 0xff;
  payload[payload.length - 1] = (sequence * 7) & 0xff;
}

void _verifyChunkMarkers(Uint8List payload, int sequence) {
  _require(payload[0] == (sequence & 0xff), 'bad leading chunk marker');
  _require(
    payload[payload.length ~/ 2] == (sequence * 3) & 0xff,
    'bad middle chunk marker',
  );
  _require(
    payload[payload.length - 1] == (sequence * 7) & 0xff,
    'bad trailing chunk marker',
  );
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
