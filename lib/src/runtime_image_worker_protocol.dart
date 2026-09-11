import 'dart:typed_data';

abstract final class RuntimeImageWorkerLimits {
  static const int maximumChunkBytes = 4096;
  static const int maximumDecodedBytes = 1024 * 1024;
  static const int maximumPixels = maximumDecodedBytes ~/ 4;
  static const int maximumDimension = 4096;
  static const int maximumEncodedBytes = 1398104;
  static const int maximumPendingTransfers = 64;
  static const int maximumPendingEncodedBytes = 8 * 1024 * 1024;
  static const int maximumPngChunks = 256;
  static const int maximumPngInflatedBytes =
      maximumDecodedBytes + maximumDimension;
}

enum RuntimeImageWorkerRequestKind {
  chunk(1),
  abort(2);

  const RuntimeImageWorkerRequestKind(this.wireValue);

  final int wireValue;

  static RuntimeImageWorkerRequestKind? fromWireValue(int value) {
    for (final RuntimeImageWorkerRequestKind candidate in values) {
      if (candidate.wireValue == value) return candidate;
    }
    return null;
  }
}

enum RuntimeImageWorkerStatus {
  pending(1),
  decoded(2),
  aborted(3),
  noPendingTransfer(4),
  invalidRequest(10),
  invalidBase64(11),
  invalidCompression(12),
  invalidDimensions(13),
  invalidDataLength(14),
  invalidPng(15),
  unsupportedFormat(16),
  resourceLimit(17);

  const RuntimeImageWorkerStatus(this.wireValue);

  final int wireValue;

  bool get isError => wireValue >= 10;

  static RuntimeImageWorkerStatus? fromWireValue(int value) {
    for (final RuntimeImageWorkerStatus candidate in values) {
      if (candidate.wireValue == value) return candidate;
    }
    return null;
  }
}

final class RuntimeImageWorkerRequest {
  RuntimeImageWorkerRequest._({
    required this.kind,
    required this.paneId,
    required this.sessionGeneration,
    required this.transferGeneration,
    required this.start,
    required this.finalChunk,
    required this.compressed,
    required this.format,
    required this.width,
    required this.height,
    required this.declaredDataSize,
    required Uint8List data,
  }) : _data = Uint8List.fromList(data);

  factory RuntimeImageWorkerRequest.chunk({
    required int paneId,
    required int sessionGeneration,
    required int transferGeneration,
    required bool start,
    required bool finalChunk,
    bool compressed = false,
    int format = 0,
    int width = 0,
    int height = 0,
    int declaredDataSize = 0,
    required Uint8List data,
  }) => RuntimeImageWorkerRequest._(
    kind: RuntimeImageWorkerRequestKind.chunk,
    paneId: paneId,
    sessionGeneration: sessionGeneration,
    transferGeneration: transferGeneration,
    start: start,
    finalChunk: finalChunk,
    compressed: compressed,
    format: format,
    width: width,
    height: height,
    declaredDataSize: declaredDataSize,
    data: data,
  );

  factory RuntimeImageWorkerRequest.abort({
    required int paneId,
    required int sessionGeneration,
    required int transferGeneration,
  }) => RuntimeImageWorkerRequest._(
    kind: RuntimeImageWorkerRequestKind.abort,
    paneId: paneId,
    sessionGeneration: sessionGeneration,
    transferGeneration: transferGeneration,
    start: false,
    finalChunk: false,
    compressed: false,
    format: 0,
    width: 0,
    height: 0,
    declaredDataSize: 0,
    data: Uint8List(0),
  );

  final RuntimeImageWorkerRequestKind kind;
  final int paneId;
  final int sessionGeneration;
  final int transferGeneration;
  final bool start;
  final bool finalChunk;
  final bool compressed;
  final int format;
  final int width;
  final int height;
  final int declaredDataSize;
  final Uint8List _data;

  int get dataLength => _data.length;

  Uint8List copyData() => Uint8List.fromList(_data);
}

final class RuntimeImageWorkerResponse {
  RuntimeImageWorkerResponse({
    required this.status,
    required this.paneId,
    required this.sessionGeneration,
    required this.transferGeneration,
    this.width = 0,
    this.height = 0,
    Uint8List? rgba,
  }) : _rgba = Uint8List.fromList(rgba ?? Uint8List(0));

  final RuntimeImageWorkerStatus status;
  final int paneId;
  final int sessionGeneration;
  final int transferGeneration;
  final int width;
  final int height;
  final Uint8List _rgba;

  int get rgbaLength => _rgba.length;

  Uint8List copyRgba() => Uint8List.fromList(_rgba);
}

final class RuntimeImageWorkerProtocolException implements Exception {
  const RuntimeImageWorkerProtocolException(this.message);

  final String message;

  @override
  String toString() => 'RuntimeImageWorkerProtocolException: $message';
}

abstract final class RuntimeImageWorkerRequestCodec {
  static const int magic = 0x4454494d;
  static const int version = 1;
  static const int headerLength = 40;
  static const int _startFlag = 1 << 0;
  static const int _finalFlag = 1 << 1;
  static const int _compressedFlag = 1 << 2;
  static const int _knownFlags = _startFlag | _finalFlag | _compressedFlag;

  static Uint8List encode(RuntimeImageWorkerRequest request) {
    _requireIdentifier(request.paneId, 'paneId');
    _requireIdentifier(request.sessionGeneration, 'sessionGeneration');
    _requireIdentifier(request.transferGeneration, 'transferGeneration');
    _requireUint32(request.width, 'width');
    _requireUint32(request.height, 'height');
    _requireUint32(request.declaredDataSize, 'declaredDataSize');
    if (request.format < 0 || request.format > 0xffff) {
      throw RangeError.range(request.format, 0, 0xffff, 'format');
    }
    if (request.dataLength > RuntimeImageWorkerLimits.maximumChunkBytes) {
      throw RangeError.range(
        request.dataLength,
        0,
        RuntimeImageWorkerLimits.maximumChunkBytes,
        'data.length',
      );
    }
    _validateShape(request);
    final Uint8List result = Uint8List(headerLength + request.dataLength);
    final ByteData header = ByteData.sublistView(result, 0, headerLength);
    header.setUint32(0, magic, Endian.big);
    header.setUint16(4, version, Endian.big);
    header.setUint16(6, request.kind.wireValue, Endian.big);
    header.setUint32(8, request.paneId, Endian.big);
    header.setUint32(12, request.sessionGeneration, Endian.big);
    header.setUint32(16, request.transferGeneration, Endian.big);
    var flags = 0;
    if (request.start) flags |= _startFlag;
    if (request.finalChunk) flags |= _finalFlag;
    if (request.compressed) flags |= _compressedFlag;
    header.setUint16(20, flags, Endian.big);
    header.setUint16(22, request.format, Endian.big);
    header.setUint32(24, request.width, Endian.big);
    header.setUint32(28, request.height, Endian.big);
    header.setUint32(32, request.declaredDataSize, Endian.big);
    header.setUint32(36, request.dataLength, Endian.big);
    result.setRange(headerLength, result.length, request.copyData());
    return result;
  }

  static RuntimeImageWorkerRequest decode(Uint8List payload) {
    if (payload.length < headerLength) {
      throw const RuntimeImageWorkerProtocolException(
        'image request is shorter than its header',
      );
    }
    final ByteData header = ByteData.sublistView(payload, 0, headerLength);
    if (header.getUint32(0, Endian.big) != magic) {
      throw const RuntimeImageWorkerProtocolException(
        'image request magic is invalid',
      );
    }
    if (header.getUint16(4, Endian.big) != version) {
      throw const RuntimeImageWorkerProtocolException(
        'image request version is unsupported',
      );
    }
    final RuntimeImageWorkerRequestKind? kind =
        RuntimeImageWorkerRequestKind.fromWireValue(
          header.getUint16(6, Endian.big),
        );
    if (kind == null) {
      throw const RuntimeImageWorkerProtocolException(
        'image request kind is unknown',
      );
    }
    final int flags = header.getUint16(20, Endian.big);
    if (flags & ~_knownFlags != 0) {
      throw const RuntimeImageWorkerProtocolException(
        'image request flags contain unknown bits',
      );
    }
    final int dataLength = header.getUint32(36, Endian.big);
    if (dataLength > RuntimeImageWorkerLimits.maximumChunkBytes ||
        payload.length != headerLength + dataLength) {
      throw const RuntimeImageWorkerProtocolException(
        'image request data length is invalid',
      );
    }
    final RuntimeImageWorkerRequest request = RuntimeImageWorkerRequest._(
      kind: kind,
      paneId: header.getUint32(8, Endian.big),
      sessionGeneration: header.getUint32(12, Endian.big),
      transferGeneration: header.getUint32(16, Endian.big),
      start: flags & _startFlag != 0,
      finalChunk: flags & _finalFlag != 0,
      compressed: flags & _compressedFlag != 0,
      format: header.getUint16(22, Endian.big),
      width: header.getUint32(24, Endian.big),
      height: header.getUint32(28, Endian.big),
      declaredDataSize: header.getUint32(32, Endian.big),
      data: Uint8List.sublistView(payload, headerLength),
    );
    _requireIdentifier(request.paneId, 'paneId');
    _requireIdentifier(request.sessionGeneration, 'sessionGeneration');
    _requireIdentifier(request.transferGeneration, 'transferGeneration');
    _validateShape(request);
    return request;
  }

  static bool hasMagic(Uint8List payload) =>
      payload.length >= 4 &&
      ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big) == magic;

  static void _validateShape(RuntimeImageWorkerRequest request) {
    if (request.kind == RuntimeImageWorkerRequestKind.abort) {
      if (request.start ||
          request.finalChunk ||
          request.compressed ||
          request.format != 0 ||
          request.width != 0 ||
          request.height != 0 ||
          request.declaredDataSize != 0 ||
          request.dataLength != 0) {
        throw const RuntimeImageWorkerProtocolException(
          'abort request carries chunk metadata',
        );
      }
      return;
    }
    if (!request.start &&
        (request.compressed ||
            request.format != 0 ||
            request.width != 0 ||
            request.height != 0 ||
            request.declaredDataSize != 0)) {
      throw const RuntimeImageWorkerProtocolException(
        'continuation request repeats start metadata',
      );
    }
  }

  static void _requireIdentifier(int value, String name) {
    if (value <= 0 || value > 0xffffffff) {
      throw RangeError.range(value, 1, 0xffffffff, name);
    }
  }

  static void _requireUint32(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, name);
    }
  }
}

abstract final class RuntimeImageWorkerResponseCodec {
  static const int magic = 0x44544952;
  static const int version = 1;
  static const int headerLength = 32;

  static Uint8List encode(RuntimeImageWorkerResponse response) {
    _requireUint32(response.paneId, 'paneId');
    _requireUint32(response.sessionGeneration, 'sessionGeneration');
    _requireUint32(response.transferGeneration, 'transferGeneration');
    _requireUint32(response.width, 'width');
    _requireUint32(response.height, 'height');
    if (response.rgbaLength > RuntimeImageWorkerLimits.maximumDecodedBytes) {
      throw RangeError.range(
        response.rgbaLength,
        0,
        RuntimeImageWorkerLimits.maximumDecodedBytes,
        'rgba.length',
      );
    }
    if (response.status == RuntimeImageWorkerStatus.decoded) {
      final int pixels = response.width * response.height;
      if (response.width == 0 ||
          response.height == 0 ||
          pixels > RuntimeImageWorkerLimits.maximumPixels ||
          response.rgbaLength != pixels * 4) {
        throw const RuntimeImageWorkerProtocolException(
          'decoded response dimensions do not match RGBA bytes',
        );
      }
    } else if (response.width != 0 ||
        response.height != 0 ||
        response.rgbaLength != 0) {
      throw const RuntimeImageWorkerProtocolException(
        'non-decoded response carries image data',
      );
    }
    final Uint8List result = Uint8List(headerLength + response.rgbaLength);
    final ByteData header = ByteData.sublistView(result, 0, headerLength);
    header.setUint32(0, magic, Endian.big);
    header.setUint16(4, version, Endian.big);
    header.setUint16(6, response.status.wireValue, Endian.big);
    header.setUint32(8, response.paneId, Endian.big);
    header.setUint32(12, response.sessionGeneration, Endian.big);
    header.setUint32(16, response.transferGeneration, Endian.big);
    header.setUint32(20, response.width, Endian.big);
    header.setUint32(24, response.height, Endian.big);
    header.setUint32(28, response.rgbaLength, Endian.big);
    result.setRange(headerLength, result.length, response.copyRgba());
    return result;
  }

  static RuntimeImageWorkerResponse decode(Uint8List payload) {
    if (payload.length < headerLength) {
      throw const RuntimeImageWorkerProtocolException(
        'image response is shorter than its header',
      );
    }
    final ByteData header = ByteData.sublistView(payload, 0, headerLength);
    if (header.getUint32(0, Endian.big) != magic ||
        header.getUint16(4, Endian.big) != version) {
      throw const RuntimeImageWorkerProtocolException(
        'image response identity is invalid',
      );
    }
    final RuntimeImageWorkerStatus? status =
        RuntimeImageWorkerStatus.fromWireValue(header.getUint16(6, Endian.big));
    if (status == null) {
      throw const RuntimeImageWorkerProtocolException(
        'image response status is unknown',
      );
    }
    final int rgbaLength = header.getUint32(28, Endian.big);
    if (rgbaLength > RuntimeImageWorkerLimits.maximumDecodedBytes ||
        payload.length != headerLength + rgbaLength) {
      throw const RuntimeImageWorkerProtocolException(
        'image response RGBA length is invalid',
      );
    }
    final RuntimeImageWorkerResponse response = RuntimeImageWorkerResponse(
      status: status,
      paneId: header.getUint32(8, Endian.big),
      sessionGeneration: header.getUint32(12, Endian.big),
      transferGeneration: header.getUint32(16, Endian.big),
      width: header.getUint32(20, Endian.big),
      height: header.getUint32(24, Endian.big),
      rgba: Uint8List.sublistView(payload, headerLength),
    );
    encode(response);
    return response;
  }

  static void _requireUint32(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, name);
    }
  }
}
