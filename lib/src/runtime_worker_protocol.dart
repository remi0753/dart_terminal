import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const int runtimeWorkerProtocolMagic = 0x44545257;
const int runtimeWorkerProtocolVersion = 1;
const int runtimeWorkerHeaderLength = 20;
// Includes one canonical 16 MiB Note document plus bounded base64 framing and
// its deletion journal. Individual worker services retain stricter limits.
const int runtimeWorkerMaximumPayloadLength = 32 * 1024 * 1024;

enum RuntimeWorkerMessageType {
  ready(1),
  request(2),
  response(3),
  stop(4),
  stopAcknowledged(5);

  const RuntimeWorkerMessageType(this.wireValue);

  final int wireValue;

  static RuntimeWorkerMessageType? fromWireValue(int value) {
    for (final RuntimeWorkerMessageType candidate in values) {
      if (candidate.wireValue == value) {
        return candidate;
      }
    }
    return null;
  }
}

final class RuntimeWorkerFrame {
  const RuntimeWorkerFrame({
    required this.type,
    required this.generation,
    required this.operation,
    required this.payload,
  });

  final RuntimeWorkerMessageType type;
  final int generation;
  final int operation;
  final Uint8List payload;
}

abstract final class RuntimeWorkerFrameCodec {
  static Uint8List encode(RuntimeWorkerFrame frame) {
    _requireUint32(frame.generation, 'generation');
    _requireUint32(frame.operation, 'operation');
    if (frame.payload.length > runtimeWorkerMaximumPayloadLength) {
      throw FormatException(
        'worker payload ${frame.payload.length} exceeds '
        '$runtimeWorkerMaximumPayloadLength bytes',
      );
    }
    final Uint8List encoded = Uint8List(
      runtimeWorkerHeaderLength + frame.payload.length,
    );
    final ByteData header = ByteData.sublistView(
      encoded,
      0,
      runtimeWorkerHeaderLength,
    );
    header.setUint32(0, runtimeWorkerProtocolMagic, Endian.big);
    header.setUint16(4, runtimeWorkerProtocolVersion, Endian.big);
    header.setUint16(6, frame.type.wireValue, Endian.big);
    header.setUint32(8, frame.generation, Endian.big);
    header.setUint32(12, frame.operation, Endian.big);
    header.setUint32(16, frame.payload.length, Endian.big);
    encoded.setRange(runtimeWorkerHeaderLength, encoded.length, frame.payload);
    return encoded;
  }

  static Uint8List int64Payload(int value) {
    final ByteData payload = ByteData(8)..setInt64(0, value, Endian.big);
    return payload.buffer.asUint8List();
  }

  static int readInt64Payload(RuntimeWorkerFrame frame) {
    return readInt64Bytes(frame.payload, context: frame.type.name);
  }

  static int readInt64Bytes(Uint8List payload, {String context = 'worker'}) {
    if (payload.length != 8) {
      throw FormatException(
        '$context payload must contain one signed 64-bit integer',
      );
    }
    return ByteData.sublistView(payload).getInt64(0, Endian.big);
  }

  static void _requireUint32(int value, String field) {
    if (value < 0 || value > 0xffffffff) {
      throw FormatException('$field is outside unsigned 32-bit range: $value');
    }
  }
}

final class RuntimeWorkerFrameDecoder {
  RuntimeWorkerFrameDecoder(Stream<List<int>> source) {
    _subscription = source.listen(
      _add,
      onError: _handleSourceError,
      onDone: _handleSourceDone,
      cancelOnError: false,
    );
  }

  final StreamController<RuntimeWorkerFrame> _frames =
      StreamController<RuntimeWorkerFrame>();
  late final StreamSubscription<List<int>> _subscription;
  Uint8List _pending = Uint8List(0);
  bool _closed = false;

  Stream<RuntimeWorkerFrame> get frames => _frames.stream;
  Future<void> get done => _frames.done;

  Future<void> cancel() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _frames.close();
  }

  void _add(List<int> chunk) {
    if (_closed || chunk.isEmpty) {
      return;
    }
    final Uint8List combined = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    var offset = 0;
    try {
      while (combined.length - offset >= runtimeWorkerHeaderLength) {
        final ByteData header = ByteData.sublistView(
          combined,
          offset,
          offset + runtimeWorkerHeaderLength,
        );
        final int magic = header.getUint32(0, Endian.big);
        final int version = header.getUint16(4, Endian.big);
        final int typeValue = header.getUint16(6, Endian.big);
        final int generation = header.getUint32(8, Endian.big);
        final int operation = header.getUint32(12, Endian.big);
        final int payloadLength = header.getUint32(16, Endian.big);
        if (magic != runtimeWorkerProtocolMagic) {
          throw FormatException(
            'worker frame magic 0x${magic.toRadixString(16)} is invalid',
          );
        }
        if (version != runtimeWorkerProtocolVersion) {
          throw FormatException(
            'worker protocol version $version is unsupported',
          );
        }
        final RuntimeWorkerMessageType? type =
            RuntimeWorkerMessageType.fromWireValue(typeValue);
        if (type == null) {
          throw FormatException('worker message type $typeValue is unknown');
        }
        if (payloadLength > runtimeWorkerMaximumPayloadLength) {
          throw FormatException(
            'worker payload $payloadLength exceeds '
            '$runtimeWorkerMaximumPayloadLength bytes',
          );
        }
        final int frameLength = runtimeWorkerHeaderLength + payloadLength;
        if (combined.length - offset < frameLength) {
          break;
        }
        _frames.add(
          RuntimeWorkerFrame(
            type: type,
            generation: generation,
            operation: operation,
            payload: Uint8List.fromList(
              combined.sublist(
                offset + runtimeWorkerHeaderLength,
                offset + frameLength,
              ),
            ),
          ),
        );
        offset += frameLength;
      }
      _pending = Uint8List.fromList(combined.sublist(offset));
      if (_pending.length >
          runtimeWorkerHeaderLength + runtimeWorkerMaximumPayloadLength) {
        throw const FormatException('worker frame buffer exceeded its cap');
      }
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleSourceError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _handleSourceDone() {
    if (_closed) {
      return;
    }
    if (_pending.isNotEmpty) {
      _frames.addError(
        const FormatException('worker stream ended with a partial frame'),
      );
    }
    _closed = true;
    unawaited(_frames.close());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_closed) {
      return;
    }
    _closed = true;
    _frames.addError(error, stackTrace);
    unawaited(_subscription.cancel());
    unawaited(_frames.close());
  }
}

final class RuntimeWorkerFrameWriter {
  RuntimeWorkerFrameWriter(this._sink);

  final IOSink _sink;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Future<void> send(RuntimeWorkerFrame frame) {
    if (_closed) {
      return Future<void>.error(StateError('worker frame writer is closed'));
    }
    final Uint8List encoded = RuntimeWorkerFrameCodec.encode(frame);
    final Future<void> operation = _tail.then<void>((_) async {
      _sink.add(encoded);
      await _sink.flush();
    });
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _tail;
    await _sink.flush();
    await _sink.close();
  }
}
