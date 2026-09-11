import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'runtime_image_worker_protocol.dart';

/// Worker-only owner for multipart Kitty image bytes and static decode.
final class RuntimeImageWorkerService {
  RuntimeImageWorkerService({
    this.maximumEncodedBytes = RuntimeImageWorkerLimits.maximumEncodedBytes,
    this.maximumPendingTransfers =
        RuntimeImageWorkerLimits.maximumPendingTransfers,
    this.maximumPendingEncodedBytes =
        RuntimeImageWorkerLimits.maximumPendingEncodedBytes,
  }) {
    if (maximumEncodedBytes <= 0 ||
        maximumEncodedBytes > RuntimeImageWorkerLimits.maximumEncodedBytes ||
        maximumPendingTransfers <= 0 ||
        maximumPendingTransfers >
            RuntimeImageWorkerLimits.maximumPendingTransfers ||
        maximumPendingEncodedBytes <= 0 ||
        maximumPendingEncodedBytes >
            RuntimeImageWorkerLimits.maximumPendingEncodedBytes) {
      throw ArgumentError('image worker bounds exceed product limits');
    }
  }

  final int maximumEncodedBytes;
  final int maximumPendingTransfers;
  final int maximumPendingEncodedBytes;
  final Map<(int, int), _PendingImageTransfer> _pending =
      <(int, int), _PendingImageTransfer>{};
  var _pendingEncodedBytes = 0;
  var _disposed = false;

  int get pendingTransferCount => _pending.length;
  int get pendingEncodedBytes => _pendingEncodedBytes;

  Uint8List handle(Uint8List payload) {
    RuntimeImageWorkerRequest? request;
    try {
      if (_disposed) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidRequest,
        );
      }
      request = RuntimeImageWorkerRequestCodec.decode(payload);
      return RuntimeImageWorkerResponseCodec.encode(_handleRequest(request));
    } on _RuntimeImageDecodeFailure catch (error) {
      if (request != null &&
          request.kind == RuntimeImageWorkerRequestKind.chunk) {
        _remove((request.paneId, request.sessionGeneration));
      }
      return RuntimeImageWorkerResponseCodec.encode(
        RuntimeImageWorkerResponse(
          status: error.status,
          paneId: request?.paneId ?? 0,
          sessionGeneration: request?.sessionGeneration ?? 0,
          transferGeneration: request?.transferGeneration ?? 0,
        ),
      );
    } on Object {
      if (request != null &&
          request.kind == RuntimeImageWorkerRequestKind.chunk) {
        _remove((request.paneId, request.sessionGeneration));
      }
      return RuntimeImageWorkerResponseCodec.encode(
        RuntimeImageWorkerResponse(
          status: RuntimeImageWorkerStatus.invalidRequest,
          paneId: request?.paneId ?? 0,
          sessionGeneration: request?.sessionGeneration ?? 0,
          transferGeneration: request?.transferGeneration ?? 0,
        ),
      );
    }
  }

  RuntimeImageWorkerResponse _handleRequest(RuntimeImageWorkerRequest request) {
    final (int, int) key = (request.paneId, request.sessionGeneration);
    if (request.kind == RuntimeImageWorkerRequestKind.abort) {
      final bool removed = _remove(key);
      return _response(
        request,
        removed
            ? RuntimeImageWorkerStatus.aborted
            : RuntimeImageWorkerStatus.noPendingTransfer,
      );
    }

    late final _PendingImageTransfer transfer;
    if (request.start) {
      _remove(key);
      _validateStart(request);
      if (_pending.length >= maximumPendingTransfers) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.resourceLimit,
        );
      }
      transfer = _PendingImageTransfer(request);
      _pending[key] = transfer;
    } else {
      final _PendingImageTransfer? existing = _pending[key];
      if (existing == null ||
          existing.transferGeneration != request.transferGeneration) {
        return _response(request, RuntimeImageWorkerStatus.noPendingTransfer);
      }
      transfer = existing;
    }

    _validateChunk(request.copyData(), finalChunk: request.finalChunk);
    if (transfer.encodedLength + request.dataLength > maximumEncodedBytes ||
        _pendingEncodedBytes + request.dataLength >
            maximumPendingEncodedBytes) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.resourceLimit,
      );
    }
    final Uint8List chunk = request.copyData();
    transfer.add(chunk);
    _pendingEncodedBytes += chunk.length;
    if (!request.finalChunk) {
      return _response(request, RuntimeImageWorkerStatus.pending);
    }

    _remove(key);
    final _DecodedImage image = _decode(transfer);
    return RuntimeImageWorkerResponse(
      status: RuntimeImageWorkerStatus.decoded,
      paneId: request.paneId,
      sessionGeneration: request.sessionGeneration,
      transferGeneration: request.transferGeneration,
      width: image.width,
      height: image.height,
      rgba: image.rgba,
    );
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _pendingEncodedBytes = 0;
  }

  RuntimeImageWorkerResponse _response(
    RuntimeImageWorkerRequest request,
    RuntimeImageWorkerStatus status,
  ) => RuntimeImageWorkerResponse(
    status: status,
    paneId: request.paneId,
    sessionGeneration: request.sessionGeneration,
    transferGeneration: request.transferGeneration,
  );

  bool _remove((int, int) key) {
    final _PendingImageTransfer? removed = _pending.remove(key);
    if (removed == null) return false;
    _pendingEncodedBytes -= removed.encodedLength;
    if (_pendingEncodedBytes < 0) {
      throw StateError('image worker pending byte count underflow');
    }
    return true;
  }

  static void _validateStart(RuntimeImageWorkerRequest request) {
    if (request.format != 24 && request.format != 32 && request.format != 100) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.unsupportedFormat,
      );
    }
    if (request.width > RuntimeImageWorkerLimits.maximumDimension ||
        request.height > RuntimeImageWorkerLimits.maximumDimension ||
        request.declaredDataSize >
            RuntimeImageWorkerLimits.maximumDecodedBytes) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.resourceLimit,
      );
    }
    if (request.format == 24 || request.format == 32) {
      if (request.width == 0 || request.height == 0) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidDimensions,
        );
      }
      final int pixels = request.width * request.height;
      if (pixels > RuntimeImageWorkerLimits.maximumPixels ||
          pixels * (request.format == 24 ? 3 : 4) >
              RuntimeImageWorkerLimits.maximumDecodedBytes) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.resourceLimit,
        );
      }
    }
    if (request.format == 100 &&
        request.compressed &&
        request.declaredDataSize == 0) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidDataLength,
      );
    }
  }

  static void _validateChunk(Uint8List bytes, {required bool finalChunk}) {
    if (!finalChunk && (bytes.isEmpty || bytes.length % 4 != 0)) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidBase64,
      );
    }
    for (final int byte in bytes) {
      final bool alphabet =
          byte >= 0x41 && byte <= 0x5a ||
          byte >= 0x61 && byte <= 0x7a ||
          byte >= 0x30 && byte <= 0x39 ||
          byte == 0x2b ||
          byte == 0x2f ||
          byte == 0x3d;
      if (!alphabet || (!finalChunk && byte == 0x3d)) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidBase64,
        );
      }
    }
  }

  static _DecodedImage _decode(_PendingImageTransfer transfer) {
    final Uint8List encoded = transfer.encodedBytes();
    if (encoded.isEmpty || encoded.length % 4 != 0) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidBase64,
      );
    }
    var padding = 0;
    if (encoded.last == 0x3d) padding++;
    if (encoded.length >= 2 && encoded[encoded.length - 2] == 0x3d) padding++;
    for (int index = 0; index < encoded.length - padding; index++) {
      if (encoded[index] == 0x3d) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidBase64,
        );
      }
    }

    late final Uint8List binary;
    try {
      binary = Uint8List.fromList(base64.decode(String.fromCharCodes(encoded)));
    } on FormatException {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidBase64,
      );
    }
    if (binary.length > RuntimeImageWorkerLimits.maximumDecodedBytes) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.resourceLimit,
      );
    }

    Uint8List decoded = binary;
    if (transfer.compressed) {
      final int maximum = transfer.format == 100
          ? RuntimeImageWorkerLimits.maximumDecodedBytes
          : transfer.width * transfer.height * (transfer.format == 24 ? 3 : 4);
      try {
        decoded = _decodeZlib(binary, maximum);
      } on _BoundedOutputException {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.resourceLimit,
        );
      } on Object {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidCompression,
        );
      }
      if (transfer.declaredDataSize != 0 &&
          decoded.length != transfer.declaredDataSize) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidDataLength,
        );
      }
    }

    if (transfer.format == 100) {
      final _DecodedImage image = _decodePng(decoded);
      if (transfer.width != 0 && transfer.width != image.width ||
          transfer.height != 0 && transfer.height != image.height) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidDimensions,
        );
      }
      return image;
    }
    return _decodeRaw(
      decoded,
      width: transfer.width,
      height: transfer.height,
      bytesPerPixel: transfer.format == 24 ? 3 : 4,
    );
  }

  static _DecodedImage _decodeRaw(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerPixel,
  }) {
    final int expected = width * height * bytesPerPixel;
    if (bytes.length != expected) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidDataLength,
      );
    }
    if (bytesPerPixel == 4) {
      return _DecodedImage(width, height, Uint8List.fromList(bytes));
    }
    final Uint8List rgba = Uint8List(width * height * 4);
    var source = 0;
    var target = 0;
    while (source < bytes.length) {
      rgba[target++] = bytes[source++];
      rgba[target++] = bytes[source++];
      rgba[target++] = bytes[source++];
      rgba[target++] = 0xff;
    }
    return _DecodedImage(width, height, rgba);
  }
}

final class _PendingImageTransfer {
  _PendingImageTransfer(RuntimeImageWorkerRequest request)
    : transferGeneration = request.transferGeneration,
      compressed = request.compressed,
      format = request.format,
      width = request.width,
      height = request.height,
      declaredDataSize = request.declaredDataSize;

  final int transferGeneration;
  final bool compressed;
  final int format;
  final int width;
  final int height;
  final int declaredDataSize;
  final BytesBuilder _encoded = BytesBuilder(copy: false);

  int get encodedLength => _encoded.length;

  void add(Uint8List bytes) => _encoded.add(bytes);

  Uint8List encodedBytes() => _encoded.toBytes();
}

final class _DecodedImage {
  const _DecodedImage(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

final class _RuntimeImageDecodeFailure implements Exception {
  const _RuntimeImageDecodeFailure(this.status);

  final RuntimeImageWorkerStatus status;
}

final class _BoundedOutputException implements Exception {
  const _BoundedOutputException();
}

final class _BoundedByteSink extends ByteConversionSinkBase {
  _BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _closed = false;

  @override
  void add(List<int> chunk) {
    if (_closed) throw StateError('bounded byte sink is closed');
    if (_builder.length + chunk.length > maximumBytes) {
      throw const _BoundedOutputException();
    }
    _builder.add(chunk);
  }

  @override
  void close() => _closed = true;

  Uint8List takeBytes() {
    if (!_closed) throw StateError('bounded byte sink is not closed');
    return _builder.toBytes();
  }
}

Uint8List _decodeZlib(Uint8List input, int maximumBytes) {
  final _BoundedByteSink sink = _BoundedByteSink(maximumBytes);
  final ByteConversionSink decoder = ZLibDecoder().startChunkedConversion(sink);
  decoder.add(input);
  decoder.close();
  return sink.takeBytes();
}

_DecodedImage _decodePng(Uint8List png) {
  const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (png.length < signature.length || !_sameRange(png, 0, signature)) {
    throw const _RuntimeImageDecodeFailure(RuntimeImageWorkerStatus.invalidPng);
  }
  var offset = signature.length;
  var chunkCount = 0;
  var sawHeader = false;
  var sawData = false;
  var dataEnded = false;
  var sawEnd = false;
  var width = 0;
  var height = 0;
  var colorType = 0;
  var bytesPerPixel = 0;
  Uint8List? palette;
  Uint8List? transparency;
  final BytesBuilder compressed = BytesBuilder(copy: false);

  while (offset < png.length) {
    if (++chunkCount > RuntimeImageWorkerLimits.maximumPngChunks ||
        png.length - offset < 12) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidPng,
      );
    }
    final ByteData view = ByteData.sublistView(png, offset, offset + 8);
    final int length = view.getUint32(0, Endian.big);
    if (length > RuntimeImageWorkerLimits.maximumDecodedBytes ||
        length > png.length - offset - 12) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.resourceLimit,
      );
    }
    final int typeOffset = offset + 4;
    final int dataOffset = offset + 8;
    final int crcOffset = dataOffset + length;
    final int expectedCrc = ByteData.sublistView(
      png,
      crcOffset,
      crcOffset + 4,
    ).getUint32(0, Endian.big);
    if (_crc32(png, typeOffset, crcOffset) != expectedCrc) {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidPng,
      );
    }
    for (var index = typeOffset; index < typeOffset + 4; index++) {
      final int byte = png[index];
      if (!(byte >= 0x41 && byte <= 0x5a) && !(byte >= 0x61 && byte <= 0x7a)) {
        throw const _RuntimeImageDecodeFailure(
          RuntimeImageWorkerStatus.invalidPng,
        );
      }
    }
    final String type = String.fromCharCodes(
      Uint8List.sublistView(png, typeOffset, typeOffset + 4),
    );
    if (!sawHeader && type != 'IHDR') {
      throw const _RuntimeImageDecodeFailure(
        RuntimeImageWorkerStatus.invalidPng,
      );
    }
    switch (type) {
      case 'IHDR':
        if (sawHeader || length != 13) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        final ByteData header = ByteData.sublistView(
          png,
          dataOffset,
          dataOffset + length,
        );
        width = header.getUint32(0, Endian.big);
        height = header.getUint32(4, Endian.big);
        final int bitDepth = header.getUint8(8);
        colorType = header.getUint8(9);
        bytesPerPixel = switch (colorType) {
          0 => 1,
          2 => 3,
          3 => 1,
          4 => 2,
          6 => 4,
          _ => 0,
        };
        if (width == 0 ||
            height == 0 ||
            width > RuntimeImageWorkerLimits.maximumDimension ||
            height > RuntimeImageWorkerLimits.maximumDimension ||
            width * height > RuntimeImageWorkerLimits.maximumPixels) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidDimensions,
          );
        }
        if (bitDepth != 8 ||
            bytesPerPixel == 0 ||
            header.getUint8(10) != 0 ||
            header.getUint8(11) != 0 ||
            header.getUint8(12) != 0) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        sawHeader = true;
        break;
      case 'PLTE':
        if (!sawHeader ||
            sawData ||
            palette != null ||
            colorType == 0 ||
            colorType == 4 ||
            length == 0 ||
            length > 768 ||
            length % 3 != 0) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        palette = Uint8List.fromList(
          Uint8List.sublistView(png, dataOffset, dataOffset + length),
        );
        break;
      case 'tRNS':
        if (!sawHeader || sawData || transparency != null) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        final bool validLength = switch (colorType) {
          0 => length == 2,
          2 => length == 6,
          3 => length > 0 && length <= (palette?.length ?? 0) ~/ 3,
          _ => false,
        };
        if (!validLength) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        transparency = Uint8List.fromList(
          Uint8List.sublistView(png, dataOffset, dataOffset + length),
        );
        break;
      case 'IDAT':
        if (!sawHeader || dataEnded || sawEnd) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        if (compressed.length + length >
            RuntimeImageWorkerLimits.maximumDecodedBytes) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.resourceLimit,
          );
        }
        compressed.add(
          Uint8List.sublistView(png, dataOffset, dataOffset + length),
        );
        sawData = true;
        break;
      case 'IEND':
        if (!sawData || sawEnd || length != 0) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        sawEnd = true;
        break;
      default:
        if (sawData) dataEnded = true;
        final int firstTypeByte = png[typeOffset];
        if (firstTypeByte & 0x20 == 0) {
          throw const _RuntimeImageDecodeFailure(
            RuntimeImageWorkerStatus.invalidPng,
          );
        }
        break;
    }
    offset = crcOffset + 4;
    if (sawEnd) break;
  }
  if (!sawEnd || offset != png.length || colorType == 3 && palette == null) {
    throw const _RuntimeImageDecodeFailure(RuntimeImageWorkerStatus.invalidPng);
  }

  final int rowBytes = width * bytesPerPixel;
  final int inflatedLength = height * (rowBytes + 1);
  if (inflatedLength > RuntimeImageWorkerLimits.maximumPngInflatedBytes) {
    throw const _RuntimeImageDecodeFailure(
      RuntimeImageWorkerStatus.resourceLimit,
    );
  }
  late final Uint8List scanlines;
  try {
    scanlines = _decodeZlib(compressed.toBytes(), inflatedLength);
  } on _BoundedOutputException {
    throw const _RuntimeImageDecodeFailure(
      RuntimeImageWorkerStatus.resourceLimit,
    );
  } on Object {
    throw const _RuntimeImageDecodeFailure(RuntimeImageWorkerStatus.invalidPng);
  }
  if (scanlines.length != inflatedLength) {
    throw const _RuntimeImageDecodeFailure(RuntimeImageWorkerStatus.invalidPng);
  }

  final Uint8List rgba = Uint8List(width * height * 4);
  Uint8List previous = Uint8List(rowBytes);
  Uint8List current = Uint8List(rowBytes);
  var sourceOffset = 0;
  var targetOffset = 0;
  for (var row = 0; row < height; row++) {
    final int filter = scanlines[sourceOffset++];
    current.setRange(0, rowBytes, scanlines, sourceOffset);
    sourceOffset += rowBytes;
    _unfilter(current, previous, bytesPerPixel, filter);
    for (var column = 0; column < width; column++) {
      final int pixelOffset = column * bytesPerPixel;
      switch (colorType) {
        case 0:
          final int gray = current[pixelOffset];
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = _grayAlpha(gray, transparency);
          break;
        case 2:
          final int red = current[pixelOffset];
          final int green = current[pixelOffset + 1];
          final int blue = current[pixelOffset + 2];
          rgba[targetOffset++] = red;
          rgba[targetOffset++] = green;
          rgba[targetOffset++] = blue;
          rgba[targetOffset++] = _rgbAlpha(red, green, blue, transparency);
          break;
        case 3:
          final int index = current[pixelOffset];
          final int paletteOffset = index * 3;
          if (paletteOffset + 2 >= palette!.length) {
            throw const _RuntimeImageDecodeFailure(
              RuntimeImageWorkerStatus.invalidPng,
            );
          }
          rgba[targetOffset++] = palette[paletteOffset];
          rgba[targetOffset++] = palette[paletteOffset + 1];
          rgba[targetOffset++] = palette[paletteOffset + 2];
          rgba[targetOffset++] =
              transparency != null && index < transparency.length
              ? transparency[index]
              : 0xff;
          break;
        case 4:
          final int gray = current[pixelOffset];
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = gray;
          rgba[targetOffset++] = current[pixelOffset + 1];
          break;
        case 6:
          rgba.setRange(targetOffset, targetOffset + 4, current, pixelOffset);
          targetOffset += 4;
          break;
      }
    }
    final Uint8List swap = previous;
    previous = current;
    current = swap;
  }
  return _DecodedImage(width, height, rgba);
}

void _unfilter(Uint8List row, Uint8List previous, int bpp, int filter) {
  if (filter < 0 || filter > 4) {
    throw const _RuntimeImageDecodeFailure(RuntimeImageWorkerStatus.invalidPng);
  }
  for (var index = 0; index < row.length; index++) {
    final int left = index >= bpp ? row[index - bpp] : 0;
    final int above = previous[index];
    final int upperLeft = index >= bpp ? previous[index - bpp] : 0;
    final int predictor = switch (filter) {
      0 => 0,
      1 => left,
      2 => above,
      3 => (left + above) ~/ 2,
      4 => _paeth(left, above, upperLeft),
      _ => 0,
    };
    row[index] = (row[index] + predictor) & 0xff;
  }
}

int _paeth(int left, int above, int upperLeft) {
  final int prediction = left + above - upperLeft;
  final int leftDistance = (prediction - left).abs();
  final int aboveDistance = (prediction - above).abs();
  final int upperLeftDistance = (prediction - upperLeft).abs();
  if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

int _grayAlpha(int gray, Uint8List? transparency) {
  if (transparency == null) return 0xff;
  final int transparent = transparency[0] << 8 | transparency[1];
  return transparent == gray ? 0 : 0xff;
}

int _rgbAlpha(int red, int green, int blue, Uint8List? transparency) {
  if (transparency == null) return 0xff;
  final int transparentRed = transparency[0] << 8 | transparency[1];
  final int transparentGreen = transparency[2] << 8 | transparency[3];
  final int transparentBlue = transparency[4] << 8 | transparency[5];
  return transparentRed == red &&
          transparentGreen == green &&
          transparentBlue == blue
      ? 0
      : 0xff;
}

bool _sameRange(Uint8List bytes, int offset, List<int> expected) {
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) return false;
  }
  return true;
}

final List<int> _crcTable = List<int>.generate(256, (int value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
  }
  return crc;
});

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index++) {
    crc = _crcTable[(crc ^ bytes[index]) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
