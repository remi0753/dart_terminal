import 'dart:isolate';
import 'dart:typed_data';

String _domain = 'uninitialized';
ReceivePort? _inbox;
SendPort? _peer;
final List<String> _events = <String>[];
int _bulkChunkCount = 0;
int _bulkChunkBytes = 0;
int _bulkNextSequence = 0;
int _bulkAcknowledged = 0;
int _bulkTransferredBytes = 0;
int _bulkElapsedMicros = 0;
Stopwatch? _bulkStopwatch;

void main() {}

@pragma('vm:entry-point', 'call')
SendPort startDomain(String name) {
  if (_inbox != null) {
    throw StateError('domain already started');
  }
  _domain = name;
  final ReceivePort inbox = ReceivePort('$name-inbox');
  _inbox = inbox;
  inbox.listen(_handleMessage);
  _events.add('$name:ready');
  return inbox.sendPort;
}

@pragma('vm:entry-point', 'call')
void setPeer(SendPort peer) {
  _peer = peer;
}

@pragma('vm:entry-point', 'call')
void sendToPeer(String command, int sequence) {
  final SendPort? peer = _peer;
  if (peer == null) {
    throw StateError('peer is not configured');
  }
  peer.send(<Object>[command, sequence]);
}

@pragma('vm:entry-point', 'call')
void startBulkTransfer(int chunkCount, int chunkBytes) {
  if (chunkCount <= 0 || chunkBytes < 2) {
    throw ArgumentError('bulk dimensions must be positive');
  }
  if (_peer == null) {
    throw StateError('peer is not configured');
  }
  _bulkChunkCount = chunkCount;
  _bulkChunkBytes = chunkBytes;
  _bulkNextSequence = 0;
  _bulkAcknowledged = 0;
  _bulkTransferredBytes = 0;
  _bulkElapsedMicros = 0;
  _events.add('$_domain:bulk-start');
  _bulkStopwatch = Stopwatch()..start();
  _sendNextBulkChunk();
}

@pragma('vm:entry-point', 'call')
bool bulkTransferDone() =>
    _bulkChunkCount > 0 && _bulkAcknowledged == _bulkChunkCount;

@pragma('vm:entry-point', 'call')
int bulkTransferredBytes() => _bulkTransferredBytes;

@pragma('vm:entry-point', 'call')
int bulkElapsedMicros() => _bulkElapsedMicros;

@pragma('vm:entry-point', 'call')
void closeDomain() {
  _events.add('$_domain:closed');
  _inbox?.close();
  _inbox = null;
  _peer = null;
}

@pragma('vm:entry-point', 'call')
String eventLog() => _events.join('|');

void _handleMessage(Object? message) {
  if (message is! List<Object?> ||
      message.length < 2 ||
      message[0] is! String ||
      message[1] is! int) {
    throw ArgumentError.value(message, 'message', 'invalid probe message');
  }

  final String command = message[0]! as String;
  final int sequence = message[1]! as int;
  switch (command) {
    case 'ping':
      if (message.length != 2) {
        throw ArgumentError.value(message, 'message', 'invalid ping');
      }
      _events.add('$_domain:ping:$sequence');
      final SendPort? peer = _peer;
      if (peer == null) {
        throw StateError('peer disappeared while handling ping');
      }
      peer.send(<Object>['pong', sequence]);
      return;
    case 'pong':
      if (message.length != 2) {
        throw ArgumentError.value(message, 'message', 'invalid pong');
      }
      _events.add('$_domain:pong:$sequence');
      return;
    case 'fail':
      if (message.length != 2) {
        throw ArgumentError.value(message, 'message', 'invalid failure');
      }
      _events.add('$_domain:fail:$sequence');
      throw StateError('intentional $_domain failure $sequence');
    case 'bulk':
      if (message.length != 3 || message[2] is! TransferableTypedData) {
        throw ArgumentError.value(message, 'message', 'invalid bulk chunk');
      }
      final Uint8List bytes = (message[2]! as TransferableTypedData)
          .materialize()
          .asUint8List();
      final int marker = sequence & 0xff;
      if (bytes.length < 2 ||
          bytes.first != marker ||
          bytes.last != (marker ^ 0xff)) {
        throw StateError('bulk marker mismatch at $sequence');
      }
      final SendPort? peer = _peer;
      if (peer == null) {
        throw StateError('peer disappeared while handling bulk data');
      }
      peer.send(<Object>['bulk-ack', sequence, bytes.length]);
      return;
    case 'bulk-ack':
      if (message.length != 3 || message[2] is! int) {
        throw ArgumentError.value(
          message,
          'message',
          'invalid bulk acknowledgement',
        );
      }
      if (sequence != _bulkAcknowledged) {
        throw StateError(
          'bulk acknowledgement order mismatch: '
          '$sequence != $_bulkAcknowledged',
        );
      }
      if (message[2] != _bulkChunkBytes) {
        throw StateError('bulk acknowledgement length mismatch at $sequence');
      }
      _bulkAcknowledged += 1;
      _bulkTransferredBytes += message[2]! as int;
      if (_bulkAcknowledged == _bulkChunkCount) {
        final Stopwatch stopwatch = _bulkStopwatch!..stop();
        _bulkElapsedMicros = stopwatch.elapsedMicroseconds;
        _events.add('$_domain:bulk-done');
      } else {
        _sendNextBulkChunk();
      }
      return;
    default:
      throw UnsupportedError('unknown probe command: $command');
  }
}

void _sendNextBulkChunk() {
  final SendPort? peer = _peer;
  if (peer == null) {
    throw StateError('peer disappeared during bulk transfer');
  }
  final int sequence = _bulkNextSequence;
  _bulkNextSequence += 1;
  final Uint8List bytes = Uint8List(_bulkChunkBytes);
  final int marker = sequence & 0xff;
  bytes.first = marker;
  bytes.last = marker ^ 0xff;
  peer.send(<Object>[
    'bulk',
    sequence,
    TransferableTypedData.fromList(<Uint8List>[bytes]),
  ]);
}
