import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'packed_grid.dart';

const int _rows = 200;
const int _columns = 500;
const int _cells = _rows * _columns;
const int _fullIterations = 64;
const int _sparseIterations = 256;
const int _transferIterations = 64;

final class _ObjectCell {
  _ObjectCell();

  int content = 0;
  int foreground = 0;
  int background = 0;
  int style = 0;
  int link = 0;
  int flags = 0;
}

final class _Timings {
  _Timings(this.values);

  final List<int> values;

  int get p95 {
    final List<int> sorted = List<int>.of(values)..sort();
    return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
  }

  int get max => values.reduce((int a, int b) => a > b ? a : b);
}

void _expectDamageRejected(Uint8List bytes, String description) {
  try {
    DamagePacketView(bytes);
  } on FormatException {
    return;
  }
  throw StateError('malformed damage accepted: $description');
}

int _align8(int value) => (value + 7) & ~7;

Uint8List _packObjectCells(List<_ObjectCell> cells, int generation) {
  const int rowOffset = damageHeaderBytes;
  final int contentOffset = _align8(rowOffset + _rows * damageRowBytes);
  final int foregroundOffset = _align8(contentOffset + _cells * 4);
  final int backgroundOffset = _align8(foregroundOffset + _cells * 4);
  final int styleOffset = _align8(backgroundOffset + _cells * 4);
  final int linkOffset = _align8(styleOffset + _cells * 2);
  final int flagOffset = _align8(linkOffset + _cells * 2);
  final int totalBytes = _align8(flagOffset + _cells);
  final Uint8List packet = Uint8List(totalBytes);
  final ByteData header = ByteData.sublistView(packet, 0, damageHeaderBytes);
  header.setUint32(0, damageMagic, Endian.little);
  header.setUint16(4, damageVersion, Endian.little);
  header.setUint16(6, damageHeaderBytes, Endian.little);
  header.setUint64(8, generation, Endian.little);
  header.setUint64(16, 2, Endian.little);
  header.setUint32(24, _columns, Endian.little);
  header.setUint32(28, _rows, Endian.little);
  header.setUint32(32, _rows, Endian.little);
  header.setUint32(36, _cells, Endian.little);
  header.setUint32(40, rowOffset, Endian.little);
  header.setUint32(44, contentOffset, Endian.little);
  header.setUint32(48, foregroundOffset, Endian.little);
  header.setUint32(52, backgroundOffset, Endian.little);
  header.setUint32(56, styleOffset, Endian.little);
  header.setUint32(60, linkOffset, Endian.little);
  header.setUint32(64, flagOffset, Endian.little);
  header.setUint32(68, totalBytes, Endian.little);
  header.setUint32(72, damageFlagFullSnapshot, Endian.little);

  final ByteData rowRecords = ByteData.sublistView(
    packet,
    rowOffset,
    rowOffset + _rows * damageRowBytes,
  );
  for (int row = 0; row < _rows; row++) {
    final int record = row * damageRowBytes;
    rowRecords.setUint32(record, row, Endian.little);
    rowRecords.setUint32(record + 4, 1, Endian.little);
    rowRecords.setUint32(record + 8, row + 1, Endian.little);
    rowRecords.setUint32(record + 12, row * _columns, Endian.little);
    rowRecords.setUint16(record + 16, 0, Endian.little);
    rowRecords.setUint16(record + 18, _columns, Endian.little);
  }

  final Uint32List contents = Uint32List.view(
    packet.buffer,
    contentOffset,
    _cells,
  );
  final Uint32List foregrounds = Uint32List.view(
    packet.buffer,
    foregroundOffset,
    _cells,
  );
  final Uint32List backgrounds = Uint32List.view(
    packet.buffer,
    backgroundOffset,
    _cells,
  );
  final Uint16List styles = Uint16List.view(packet.buffer, styleOffset, _cells);
  final Uint16List links = Uint16List.view(packet.buffer, linkOffset, _cells);
  final Uint8List flags = Uint8List.view(packet.buffer, flagOffset, _cells);
  for (int index = 0; index < cells.length; index++) {
    final _ObjectCell cell = cells[index];
    contents[index] = cell.content;
    foregrounds[index] = cell.foreground;
    backgrounds[index] = cell.background;
    styles[index] = cell.style;
    links[index] = cell.link;
    flags[index] = cell.flags;
  }
  return packet;
}

@pragma('vm:entry-point')
void _transferReceiver(SendPort rootPort) {
  final ReceivePort messages = ReceivePort('phase0-grid-transfer-receiver');
  rootPort.send(messages.sendPort);
  messages.listen((Object? message) {
    if (message == 'stop') {
      rootPort.send('stopped');
      messages.close();
      return;
    }
    final List<Object?> envelope = message! as List<Object?>;
    final int sequence = envelope[0]! as int;
    final TransferableTypedData transfer =
        envelope[1]! as TransferableTypedData;
    final Uint8List bytes = transfer.materialize().asUint8List();
    final DamagePacketView packet = DamagePacketView(bytes);
    rootPort.send(<Object?>[
      sequence,
      bytes.length,
      packet.generation,
      packet.sampleChecksum(),
    ]);
  });
}

int _mutateObjects(List<_ObjectCell> cells, int seed) {
  int checksum = 0;
  for (int index = 0; index < cells.length; index++) {
    final _ObjectCell cell = cells[index];
    final int value = seed + index * 33;
    cell.content = 0x20 + (value % 95);
    cell.foreground = 0x80000000 | (value & 0x00ffffff);
    cell.background = 0x80000000 | ((value * 13) & 0x00ffffff);
    cell.style = value & 0x03ff;
    cell.link = value % 61 == 0 ? value & 0xffff : 0;
    cell.flags = cellWidthNarrow;
    checksum = (checksum + cell.content + cell.style) & 0x7fffffff;
  }
  return checksum;
}

Future<List<Object>> _measureTransfer(Uint8List packet) async {
  final ReceivePort replies = ReceivePort('phase0-grid-transfer-root');
  final StreamIterator<Object?> iterator = StreamIterator<Object?>(replies);
  final Isolate receiver = await Isolate.spawn<SendPort>(
    _transferReceiver,
    replies.sendPort,
    errorsAreFatal: true,
    debugName: 'phase0-grid-render-receiver',
  );
  if (!await iterator.moveNext()) {
    throw StateError('transfer receiver did not start');
  }
  final SendPort receiverPort = iterator.current! as SendPort;
  final List<int> latencies = <int>[];
  int aggregateChecksum = 0;
  final Stopwatch total = Stopwatch()..start();
  for (int sequence = 0; sequence < _transferIterations; sequence++) {
    final Stopwatch one = Stopwatch()..start();
    receiverPort.send(<Object?>[
      sequence,
      TransferableTypedData.fromList(<Uint8List>[packet]),
    ]);
    if (!await iterator.moveNext()) {
      throw StateError('transfer receiver stopped at $sequence');
    }
    final List<Object?> acknowledgement = iterator.current! as List<Object?>;
    if (acknowledgement[0] != sequence ||
        acknowledgement[1] != packet.length ||
        acknowledgement[2] != 9001) {
      throw StateError('bad transfer acknowledgement at $sequence');
    }
    aggregateChecksum =
        (aggregateChecksum + (acknowledgement[3]! as int)) & 0x7fffffff;
    latencies.add(one.elapsedMicroseconds);
  }
  final int elapsedMicros = total.elapsedMicroseconds;
  receiverPort.send('stop');
  if (!await iterator.moveNext() || iterator.current != 'stopped') {
    throw StateError('transfer receiver did not stop cleanly');
  }
  await iterator.cancel();
  replies.close();
  receiver.kill(priority: Isolate.immediate);
  final double mibPerSecond =
      packet.length *
      _transferIterations *
      1000000 /
      elapsedMicros /
      (1024 * 1024);
  final _Timings timings = _Timings(latencies);
  return <Object>[
    timings.p95,
    timings.max,
    elapsedMicros,
    mibPerSecond,
    aggregateChecksum,
  ];
}

void _measureGridMemory() {
  final int before = ProcessInfo.currentRss;
  final PackedGrid grid = PackedGrid(rows: _rows, columns: _columns);
  grid.fillDeterministic(73);
  int checksum = 0;
  for (int index = 0; index < grid.cellCount; index += 997) {
    checksum ^= grid.content[index] ^ grid.foreground[index];
  }
  final int after = ProcessInfo.currentRss;
  stdout.writeln(
    'PHASE0_GRID_MEMORY kind=soa before=$before after=$after '
    'delta=${after - before} deterministic_bytes=${grid.typedStorageBytes} '
    'checksum=$checksum',
  );
}

void _measureObjectMemory() {
  final int before = ProcessInfo.currentRss;
  final List<_ObjectCell> cells = List<_ObjectCell>.generate(
    _cells,
    (int _) => _ObjectCell(),
    growable: false,
  );
  final int checksum = _mutateObjects(cells, 73);
  final int after = ProcessInfo.currentRss;
  const int payloadLowerBound = _cells * 56;
  stdout.writeln(
    'PHASE0_GRID_MEMORY kind=objects before=$before after=$after '
    'delta=${after - before} payload_lower_bound=$payloadLowerBound '
    'checksum=$checksum',
  );
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--memory-grid') {
    _measureGridMemory();
    return;
  }
  if (arguments.length == 1 && arguments.single == '--memory-objects') {
    _measureObjectMemory();
    return;
  }
  if (arguments.isNotEmpty) {
    throw FormatException('unknown arguments: ${arguments.join(' ')}');
  }
  final int rssAtStart = ProcessInfo.currentRss;
  final PackedGrid grid = PackedGrid(rows: _rows, columns: _columns);
  grid.fillDeterministic(17);
  final Uint8List initialPacket = grid.packDamage(
    generation: 1,
    resourceGeneration: 1,
    fullSnapshot: true,
  );
  final DamagePacketView initialView = DamagePacketView(initialPacket);
  if (initialView.rows != _rows ||
      initialView.columns != _columns ||
      initialView.rowCount != _rows ||
      initialView.cellCount != _cells ||
      initialView.flags != damageFlagFullSnapshot ||
      initialView.sampleChecksum() == 0) {
    throw StateError('initial full damage packet failed validation');
  }
  _expectDamageRejected(
    Uint8List.sublistView(initialPacket, 0, initialPacket.length - 1),
    'truncated payload',
  );
  final Uint8List unknownFlags = Uint8List.fromList(initialPacket);
  ByteData.sublistView(unknownFlags).setUint32(72, 0x80000000, Endian.little);
  _expectDamageRejected(unknownFlags, 'unknown flags');
  final Uint8List wrongCellOffset = Uint8List.fromList(initialPacket);
  ByteData.sublistView(wrongCellOffset)
      .setUint32(damageHeaderBytes + 12, 1, Endian.little);
  _expectDamageRejected(wrongCellOffset, 'noncontiguous cell offset');
  final Uint8List nonzeroReserved = Uint8List.fromList(initialPacket);
  nonzeroReserved[damageHeaderBytes + 23] = 1;
  _expectDamageRejected(nonzeroReserved, 'nonzero row reserved byte');
  final Uint8List zeroGeneration = Uint8List.fromList(initialPacket);
  ByteData.sublistView(zeroGeneration).setUint64(8, 0, Endian.little);
  _expectDamageRejected(zeroGeneration, 'zero generation');
  final PackedGrid paddingGrid = PackedGrid(rows: 1, columns: 3)
    ..fillDeterministic(1);
  final Uint8List nonzeroPadding = paddingGrid.packDamage(
    generation: 1,
    resourceGeneration: 1,
    fullSnapshot: true,
  );
  final DamagePacketView paddingView = DamagePacketView(nonzeroPadding);
  nonzeroPadding[paddingView.contentOffset + paddingView.cellCount * 4] = 1;
  _expectDamageRejected(nonzeroPadding, 'nonzero alignment padding');

  for (int warmup = 0; warmup < 8; warmup++) {
    grid.mutateAll(warmup);
    grid.packDamage(
      generation: 100 + warmup,
      resourceGeneration: 1,
      fullSnapshot: true,
    );
  }

  final List<int> soaSweepMicros = <int>[];
  int soaChecksum = 0;
  for (int iteration = 0; iteration < _fullIterations; iteration++) {
    final Stopwatch clock = Stopwatch()..start();
    soaChecksum ^= grid.mutateAll(1000 + iteration);
    soaSweepMicros.add(clock.elapsedMicroseconds);
    grid.clearDamage();
  }
  final int rssWithGrid = ProcessInfo.currentRss;

  final List<_ObjectCell> objectCells = List<_ObjectCell>.generate(
    _cells,
    (int _) => _ObjectCell(),
    growable: false,
  );
  for (int warmup = 0; warmup < 8; warmup++) {
    _mutateObjects(objectCells, warmup);
  }
  final List<int> objectSweepMicros = <int>[];
  int objectChecksum = 0;
  for (int iteration = 0; iteration < _fullIterations; iteration++) {
    final Stopwatch clock = Stopwatch()..start();
    objectChecksum ^= _mutateObjects(objectCells, 1000 + iteration);
    objectSweepMicros.add(clock.elapsedMicroseconds);
  }
  final int rssWithObjects = ProcessInfo.currentRss;

  final List<int> objectPackMicros = <int>[];
  int objectPacketChecksum = 0;
  for (int iteration = 0; iteration < _fullIterations; iteration++) {
    final Stopwatch clock = Stopwatch()..start();
    final Uint8List packet = _packObjectCells(objectCells, 1500 + iteration);
    objectPackMicros.add(clock.elapsedMicroseconds);
    final DamagePacketView view = DamagePacketView(packet);
    if (view.rowCount != _rows ||
        view.cellCount != _cells ||
        packet.length != initialPacket.length) {
      throw StateError('object packet topology changed');
    }
    objectPacketChecksum =
        (objectPacketChecksum + view.sampleChecksum()) & 0x7fffffff;
  }

  final List<int> fullPackMicros = <int>[];
  Uint8List? fullPacket;
  int packetChecksum = 0;
  for (int iteration = 0; iteration < _fullIterations; iteration++) {
    grid.markAllDirty();
    final Stopwatch clock = Stopwatch()..start();
    final Uint8List packet = grid.packDamage(
      generation: 2000 + iteration,
      resourceGeneration: 2,
      fullSnapshot: true,
    );
    fullPackMicros.add(clock.elapsedMicroseconds);
    final DamagePacketView view = DamagePacketView(packet);
    if (view.rowCount != _rows || view.cellCount != _cells) {
      throw StateError('full packet topology changed');
    }
    packetChecksum = (packetChecksum + view.sampleChecksum()) & 0x7fffffff;
    fullPacket = packet;
  }

  final List<int> sparseMicros = <int>[];
  int sparseBytes = 0;
  int sparseCells = 0;
  for (int iteration = 0; iteration < _sparseIterations; iteration++) {
    final Stopwatch clock = Stopwatch()..start();
    grid.updateSpans(seed: iteration + 1, damagedRows: 32, span: 128);
    final Uint8List packet = grid.packDamage(
      generation: 3000 + iteration,
      resourceGeneration: 2,
    );
    sparseMicros.add(clock.elapsedMicroseconds);
    final DamagePacketView view = DamagePacketView(packet);
    if (view.rowCount == 0 || view.cellCount < 32 * 128) {
      throw StateError('sparse packet lost damage');
    }
    sparseBytes += packet.length;
    sparseCells += view.cellCount;
    packetChecksum = (packetChecksum + view.sampleChecksum()) & 0x7fffffff;
  }

  grid.clearDamage();
  final List<int> scrollMicros = <int>[];
  for (int iteration = 0; iteration < 2048; iteration++) {
    final Stopwatch clock = Stopwatch()..start();
    grid.scrollUp(1);
    scrollMicros.add(clock.elapsedMicroseconds);
    grid.clearDamage();
  }

  final Uint8List transferPacket = Uint8List.fromList(fullPacket!);
  final ByteData transferHeader = ByteData.sublistView(
    transferPacket,
    0,
    damageHeaderBytes,
  );
  transferHeader.setUint64(8, 9001, Endian.little);
  final List<Object> transfer = await _measureTransfer(transferPacket);

  final _Timings soa = _Timings(soaSweepMicros);
  final _Timings objects = _Timings(objectSweepMicros);
  final _Timings objectPack = _Timings(objectPackMicros);
  final _Timings full = _Timings(fullPackMicros);
  final _Timings sparse = _Timings(sparseMicros);
  final _Timings scroll = _Timings(scrollMicros);
  final double soaMillionCellsPerSecond = _cells / soa.p95;
  final double objectMillionCellsPerSecond = _cells / objects.p95;
  final double averageSparseBytes = sparseBytes / _sparseIterations;
  final double averageSparseCells = sparseCells / _sparseIterations;

  final bool passed =
      grid.typedStorageBytes == 1702600 &&
      initialPacket.length == 1704880 &&
      full.p95 < 4000 &&
      sparse.p95 < 1000 &&
      scroll.p95 < 100 &&
      (transfer[0] as int) < 4000 &&
      (transfer[3] as double) >= 500 &&
      soaChecksum == objectChecksum &&
      packetChecksum != 0 &&
      objectPacketChecksum != 0 &&
      (transfer[4] as int) != 0;

  stdout.writeln(
    'PHASE0_GRID_${passed ? 'PASS' : 'FAIL'} rows=$_rows columns=$_columns '
    'cells=$_cells typed_storage_bytes=${grid.typedStorageBytes} '
    'full_packet_bytes=${initialPacket.length} full_pack_p95_us=${full.p95} '
    'full_pack_max_us=${full.max} sparse_p95_us=${sparse.p95} '
    'sparse_max_us=${sparse.max} sparse_avg_bytes='
    '${averageSparseBytes.toStringAsFixed(1)} sparse_avg_cells='
    '${averageSparseCells.toStringAsFixed(1)} scroll_p95_us=${scroll.p95} '
    'soa_sweep_p95_us=${soa.p95} soa_mcells_s='
    '${soaMillionCellsPerSecond.toStringAsFixed(2)} '
    'object_sweep_p95_us=${objects.p95} object_mcells_s='
    '${objectMillionCellsPerSecond.toStringAsFixed(2)} '
    'object_pack_p95_us=${objectPack.p95} object_pack_max_us=${objectPack.max} '
    'ttd_p95_us=${transfer[0]} ttd_max_us=${transfer[1]} '
    'ttd_elapsed_us=${transfer[2]} ttd_mib_s='
    '${(transfer[3] as double).toStringAsFixed(2)} '
    'checksums=$soaChecksum/$objectChecksum/$packetChecksum/'
    '$objectPacketChecksum/${transfer[4]} rss_start=$rssAtStart '
    'rss_grid=$rssWithGrid rss_objects=$rssWithObjects '
    'rss_final=${ProcessInfo.currentRss}',
  );
  if (!passed) {
    exitCode = 1;
  }
}
