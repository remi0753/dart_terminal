import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const int _rows = 200;
const int _columns = 500;
const int _cells = _rows * _columns;
const int _warmupIterations = 8;
const int _timedIterations = 64;
const int _maximumP95Micros = 4000;
const int _expectedPacketBytes = 1704904;
const bool _releaseAot = bool.fromEnvironment('dart.vm.product');

final class ProductDamageBenchmarkResult {
  const ProductDamageBenchmarkResult({
    required this.captureMicros,
    required this.transferMicros,
    required this.endToEndMicros,
    required this.transferredBytes,
    required this.transferElapsedMicros,
    required this.timedIterations,
    required this.maximumP95Micros,
  });

  final List<int> captureMicros;
  final List<int> transferMicros;
  final List<int> endToEndMicros;
  final int transferredBytes;
  final int transferElapsedMicros;
  final int timedIterations;
  final int maximumP95Micros;

  int get captureP95 => _percentile95(captureMicros);
  int get transferP95 => _percentile95(transferMicros);
  int get endToEndP95 => _percentile95(endToEndMicros);
  int get captureMax => _maximum(captureMicros);
  int get transferMax => _maximum(transferMicros);
  double get transferMiBPerSecond =>
      transferredBytes * 1000000 / transferElapsedMicros / (1024 * 1024);
  bool get passed =>
      transferredBytes == _expectedPacketBytes * timedIterations &&
      captureP95 < maximumP95Micros &&
      transferP95 < maximumP95Micros;

  String machineLine() =>
      'PRODUCT_DAMAGE_BENCHMARK_${passed ? 'PASS' : 'FAIL'} '
      'mode=release-aot rows=$_rows columns=$_columns cells=$_cells '
      'packet_bytes=$_expectedPacketBytes iterations=$timedIterations '
      'capture_ttd_p95_us=$captureP95 capture_ttd_max_us=$captureMax '
      'transfer_decode_ack_p95_us=$transferP95 '
      'transfer_decode_ack_max_us=$transferMax '
      'end_to_end_p95_us=$endToEndP95 transfer_mib_s='
      '${transferMiBPerSecond.toStringAsFixed(2)} '
      'maximum_p95_us=$maximumP95Micros';
}

@pragma('vm:entry-point')
void _damageReceiver(SendPort parent) {
  final ReceivePort incoming = ReceivePort('product-damage-benchmark-receiver');
  parent.send(incoming.sendPort);
  incoming.listen((Object? message) {
    if (message == 'stop') {
      incoming.close();
      parent.send('stopped');
      return;
    }
    final List<Object?> envelope = message! as List<Object?>;
    final int generation = envelope[0]! as int;
    final int expectedBytes = envelope[1]! as int;
    final TransferableTypedData payload = envelope[2]! as TransferableTypedData;
    final Uint8List bytes = payload.materialize().asUint8List();
    final TerminalDecodedDamage damage = TerminalDamageCodec.decode(bytes);
    if (bytes.length != expectedBytes ||
        damage.damageGeneration != generation ||
        damage.damagedCellCount != _cells ||
        !damage.isFullSnapshot) {
      throw StateError('product damage transfer changed its contract');
    }
    parent.send(<Object?>[generation, bytes.length]);
  });
}

Future<ProductDamageBenchmarkResult> runProductDamageBenchmark({
  int warmupIterations = _warmupIterations,
  int timedIterations = _timedIterations,
  int maximumP95Micros = _maximumP95Micros,
}) async {
  if (warmupIterations < 0 || warmupIterations > 1024) {
    throw RangeError.range(warmupIterations, 0, 1024, 'warmupIterations');
  }
  if (timedIterations <= 0 || timedIterations > 4096) {
    throw RangeError.range(timedIterations, 1, 4096, 'timedIterations');
  }
  if (maximumP95Micros <= 0) {
    throw RangeError.value(
      maximumP95Micros,
      'maximumP95Micros',
      'must be positive',
    );
  }
  final ReceivePort replies = ReceivePort('product-damage-benchmark-root');
  final StreamIterator<Object?> iterator = StreamIterator<Object?>(replies);
  await Isolate.spawn<SendPort>(
    _damageReceiver,
    replies.sendPort,
    errorsAreFatal: true,
    debugName: 'product-damage-benchmark-renderer',
  );
  if (!await iterator.moveNext()) {
    throw StateError('product damage benchmark receiver did not start');
  }
  final SendPort receiver = iterator.current! as SendPort;
  final TerminalScreen screen = TerminalScreen(rows: _rows, columns: _columns);
  final List<int> captureMicros = <int>[];
  final List<int> transferMicros = <int>[];
  final List<int> endToEndMicros = <int>[];
  var transferredBytes = 0;
  var transferElapsedMicros = 0;

  for (
    int iteration = 0;
    iteration < warmupIterations + timedIterations;
    iteration++
  ) {
    if (!screen.fullSnapshotRequired) screen.requestFullSnapshot();
    final int generation = iteration + 1;
    final Stopwatch clock = Stopwatch()..start();
    final TerminalDamagePacket packet = TerminalDamageCodec.capture(
      screen,
      damageGeneration: generation,
      requiredResourceGeneration: 1,
    )!;
    final TransferableTypedData payload = TransferableTypedData.fromList(
      <TypedData>[packet.copyBytes()],
    );
    final int captureElapsed = clock.elapsedMicroseconds;
    receiver.send(<Object?>[generation, packet.byteLength, payload]);
    if (!await iterator.moveNext()) {
      throw StateError('product damage receiver stopped at $generation');
    }
    final List<Object?> acknowledgement = iterator.current! as List<Object?>;
    clock.stop();
    if (acknowledgement[0] != generation ||
        acknowledgement[1] != packet.byteLength) {
      throw StateError('invalid product damage benchmark ACK');
    }
    screen.acknowledgeFullSnapshot();
    if (iteration >= warmupIterations) {
      final int transferElapsed = clock.elapsedMicroseconds - captureElapsed;
      captureMicros.add(captureElapsed);
      transferMicros.add(transferElapsed);
      endToEndMicros.add(clock.elapsedMicroseconds);
      transferredBytes += packet.byteLength;
      transferElapsedMicros += transferElapsed;
    }
  }

  receiver.send('stop');
  if (!await iterator.moveNext() || iterator.current != 'stopped') {
    throw StateError('product damage benchmark receiver did not stop');
  }
  await iterator.cancel();
  replies.close();

  return ProductDamageBenchmarkResult(
    captureMicros: List<int>.unmodifiable(captureMicros),
    transferMicros: List<int>.unmodifiable(transferMicros),
    endToEndMicros: List<int>.unmodifiable(endToEndMicros),
    transferredBytes: transferredBytes,
    transferElapsedMicros: transferElapsedMicros,
    timedIterations: timedIterations,
    maximumP95Micros: maximumP95Micros,
  );
}

Future<void> main() async {
  if (!_releaseAot) {
    throw StateError('product damage benchmark must run as Release AOT');
  }
  final ProductDamageBenchmarkResult result = await runProductDamageBenchmark();
  stdout.writeln(result.machineLine());
  if (!result.passed) exitCode = 1;
}

int _percentile95(List<int> values) {
  final List<int> sorted = List<int>.of(values)..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

int _maximum(List<int> values) =>
    values.reduce((int left, int right) => left > right ? left : right);
