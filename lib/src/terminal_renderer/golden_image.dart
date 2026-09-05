import 'dart:convert';
import 'dart:typed_data';

import 'reference_renderer.dart';

/// Limits for version-one Dart Terminal golden image artifacts.
final class TerminalGoldenImageLimits {
  const TerminalGoldenImageLimits({
    this.maximumEncodedBytes = 96 * 1024 * 1024,
    this.renderLimits = const TerminalReferenceRenderLimits(),
  });

  final int maximumEncodedBytes;
  final TerminalReferenceRenderLimits renderLimits;

  void validate() {
    if (maximumEncodedBytes <= 0) {
      throw RangeError.value(
        maximumEncodedBytes,
        'maximumEncodedBytes',
        'must be positive',
      );
    }
    renderLimits.validate();
  }
}

/// A malformed, noncanonical, corrupt, or over-limit golden artifact.
final class TerminalGoldenImageFormatException implements FormatException {
  const TerminalGoldenImageFormatException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  dynamic get source => null;

  @override
  String toString() => 'TerminalGoldenImageFormatException: $message';
}

/// Deterministic version-one codec for source-controlled RGBA golden images.
///
/// The format is an ASCII envelope with fixed field order and a canonical
/// Base64 payload. Its FNV-1a-32 checksum covers dimensions, scale, stride,
/// payload length, and exact RGBA bytes. Decoding rejects any noncanonical or
/// trailing data.
abstract final class TerminalGoldenImageCodec {
  static const String formatName = 'dart-terminal-golden-image';
  static const int formatVersion = 1;
  static const String pixelFormat = 'rgba8-srgb-straight';

  static Uint8List encode(
    TerminalReferenceImage image, {
    TerminalGoldenImageLimits limits = const TerminalGoldenImageLimits(),
  }) {
    limits.validate();
    _validateImageAgainstLimits(image, limits.renderLimits);
    final String sizingPrefix =
        '$formatName\n'
        'version=$formatVersion\n'
        'width=${image.width}\n'
        'height=${image.height}\n'
        'scale=${image.scale}\n'
        'pixel-format=$pixelFormat\n'
        'row-stride=${image.rowStride}\n'
        'payload-length=${image.byteLength}\n'
        'checksum=fnv1a32:00000000\n'
        'pixels=';
    final int base64Length = ((image.byteLength + 2) ~/ 3) * 4;
    final int encodedLength = sizingPrefix.length + base64Length + 1;
    if (encodedLength > limits.maximumEncodedBytes) {
      throw StateError(
        'golden encoded-byte limit exceeded: $encodedLength > '
        '${limits.maximumEncodedBytes}',
      );
    }
    final Uint8List rgba = image.copyRgbaBytes();
    final String checksum = _checksumHex(image, rgba);
    final String prefix = sizingPrefix.replaceFirst('00000000', checksum);
    final String encoded = '$prefix${base64Encode(rgba)}\n';
    final Uint8List result = Uint8List.fromList(ascii.encode(encoded));
    assert(result.length == encodedLength);
    return result;
  }

  static TerminalReferenceImage decode(
    List<int> encodedBytes, {
    TerminalGoldenImageLimits limits = const TerminalGoldenImageLimits(),
  }) {
    limits.validate();
    if (encodedBytes.length > limits.maximumEncodedBytes) {
      throw TerminalGoldenImageFormatException(
        'encoded-byte limit exceeded: ${encodedBytes.length} > '
        '${limits.maximumEncodedBytes}',
      );
    }
    final Uint8List owned = Uint8List(encodedBytes.length);
    for (int index = 0; index < encodedBytes.length; index++) {
      final int byte = encodedBytes[index];
      if (byte < 0 || byte > 0x7f) {
        throw TerminalGoldenImageFormatException(
          'non-ASCII byte at offset $index',
        );
      }
      owned[index] = byte;
    }
    final List<String> lines = ascii.decode(owned).split('\n');
    if (lines.length != 11 || lines.last.isNotEmpty) {
      throw const TerminalGoldenImageFormatException(
        'artifact must contain exactly ten newline-terminated lines',
      );
    }
    if (lines[0] != formatName) {
      throw const TerminalGoldenImageFormatException('invalid format name');
    }
    final int version = _parseDecimal(lines[1], 'version');
    if (version != formatVersion) {
      throw TerminalGoldenImageFormatException(
        'unsupported format version $version',
      );
    }
    final int width = _parseDecimal(lines[2], 'width');
    final int height = _parseDecimal(lines[3], 'height');
    final int scale = _parseDecimal(lines[4], 'scale');
    if (lines[5] != 'pixel-format=$pixelFormat') {
      throw const TerminalGoldenImageFormatException(
        'unsupported or misplaced pixel format',
      );
    }
    final int rowStride = _parseDecimal(lines[6], 'row-stride');
    final int payloadLength = _parseDecimal(lines[7], 'payload-length');
    final String checksum = _parseChecksum(lines[8]);
    final String payload = _parseValue(lines[9], 'pixels');
    if (!_canonicalBase64.hasMatch(payload)) {
      throw const TerminalGoldenImageFormatException(
        'pixel payload is not canonical Base64',
      );
    }

    _validateDecodedMetadata(
      width: width,
      height: height,
      scale: scale,
      rowStride: rowStride,
      payloadLength: payloadLength,
      limits: limits.renderLimits,
    );
    final int maximumBase64Length = ((payloadLength + 2) ~/ 3) * 4;
    if (payload.length != maximumBase64Length) {
      throw const TerminalGoldenImageFormatException(
        'Base64 length does not match payload length',
      );
    }
    final Uint8List rgba;
    try {
      rgba = base64Decode(payload);
    } on FormatException {
      throw const TerminalGoldenImageFormatException(
        'pixel payload is not valid Base64',
      );
    }
    if (rgba.length != payloadLength || base64Encode(rgba) != payload) {
      throw const TerminalGoldenImageFormatException(
        'pixel payload length or canonical encoding mismatch',
      );
    }
    final TerminalReferenceImage image;
    try {
      image = TerminalReferenceImage.fromRgba(
        width: width,
        height: height,
        scale: scale,
        rgba: rgba,
        limits: limits.renderLimits,
      );
    } on Object catch (error) {
      throw TerminalGoldenImageFormatException(
        'invalid image metadata: $error',
      );
    }
    final String actualChecksum = _checksumHex(image, rgba);
    if (checksum != actualChecksum) {
      throw TerminalGoldenImageFormatException(
        'checksum mismatch: expected $checksum, computed $actualChecksum',
      );
    }
    return image;
  }

  static final RegExp _canonicalBase64 = RegExp(
    r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
  );

  static String _checksumHex(TerminalReferenceImage image, Uint8List rgba) {
    var hash = 0x811c9dc5;
    final List<int> metadata = ascii.encode(
      '$formatName\u0000'
      'version=$formatVersion\u0000'
      'width=${image.width}\u0000'
      'height=${image.height}\u0000'
      'scale=${image.scale}\u0000'
      'pixel-format=$pixelFormat\u0000'
      'row-stride=${image.rowStride}\u0000'
      'payload-length=${image.byteLength}\u0000',
    );
    for (final int byte in metadata) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    for (final int byte in rgba) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// Limits for one golden comparison result and assertion description.
final class TerminalGoldenImageComparisonLimits {
  const TerminalGoldenImageComparisonLimits({
    this.maximumDiagnosticCodeUnits = 512,
    this.maximumDescriptionCodeUnits = 256,
  });

  final int maximumDiagnosticCodeUnits;
  final int maximumDescriptionCodeUnits;

  void validate() {
    if (maximumDiagnosticCodeUnits <= 0) {
      throw RangeError.value(
        maximumDiagnosticCodeUnits,
        'maximumDiagnosticCodeUnits',
        'must be positive',
      );
    }
    if (maximumDescriptionCodeUnits <= 0) {
      throw RangeError.value(
        maximumDescriptionCodeUnits,
        'maximumDescriptionCodeUnits',
        'must be positive',
      );
    }
  }
}

/// Exact equality result with bounded first-difference diagnostics.
final class TerminalGoldenImageComparison {
  const TerminalGoldenImageComparison._({
    required this.matches,
    required this.diagnostic,
    this.x,
    this.y,
    this.expectedRgba,
    this.actualRgba,
  });

  final bool matches;
  final String diagnostic;
  final int? x;
  final int? y;
  final int? expectedRgba;
  final int? actualRgba;

  void requireMatch(
    String description, {
    TerminalGoldenImageComparisonLimits limits =
        const TerminalGoldenImageComparisonLimits(),
  }) {
    limits.validate();
    if (description.length > limits.maximumDescriptionCodeUnits) {
      throw RangeError.range(
        description.length,
        0,
        limits.maximumDescriptionCodeUnits,
        'description.length',
      );
    }
    if (!matches) {
      throw TerminalGoldenImageMismatchException(description, diagnostic);
    }
  }
}

/// Typed assertion failure that never embeds either complete image.
final class TerminalGoldenImageMismatchException implements Exception {
  const TerminalGoldenImageMismatchException(this.description, this.diagnostic);

  final String description;
  final String diagnostic;

  @override
  String toString() => '$description: $diagnostic';
}

/// Compares exact dimensions, scale, and straight-alpha RGBA pixels.
abstract final class TerminalGoldenImageComparator {
  static TerminalGoldenImageComparison compare(
    TerminalReferenceImage expected,
    TerminalReferenceImage actual, {
    TerminalGoldenImageComparisonLimits limits =
        const TerminalGoldenImageComparisonLimits(),
  }) {
    limits.validate();
    if (expected.width != actual.width ||
        expected.height != actual.height ||
        expected.scale != actual.scale) {
      return TerminalGoldenImageComparison._(
        matches: false,
        diagnostic: _bounded(
          'golden geometry mismatch: expected '
          '${expected.width}x${expected.height}@${expected.scale}x, actual '
          '${actual.width}x${actual.height}@${actual.scale}x',
          limits.maximumDiagnosticCodeUnits,
        ),
      );
    }
    for (int y = 0; y < expected.height; y++) {
      for (int x = 0; x < expected.width; x++) {
        final int expectedRgba = expected.pixelAt(x, y);
        final int actualRgba = actual.pixelAt(x, y);
        if (expectedRgba == actualRgba) {
          continue;
        }
        return TerminalGoldenImageComparison._(
          matches: false,
          diagnostic: _bounded(
            'golden pixel mismatch at ($x, $y): expected '
            '${_rgbaHex(expectedRgba)}, actual ${_rgbaHex(actualRgba)}',
            limits.maximumDiagnosticCodeUnits,
          ),
          x: x,
          y: y,
          expectedRgba: expectedRgba,
          actualRgba: actualRgba,
        );
      }
    }
    return const TerminalGoldenImageComparison._(matches: true, diagnostic: '');
  }
}

int _parseDecimal(String line, String name) {
  final String value = _parseValue(line, name);
  if (!_canonicalDecimal.hasMatch(value)) {
    throw TerminalGoldenImageFormatException(
      '$name is not a canonical unsigned decimal',
    );
  }
  final int? result = int.tryParse(value);
  if (result == null) {
    throw TerminalGoldenImageFormatException('$name is out of range');
  }
  return result;
}

String _parseValue(String line, String name) {
  final String prefix = '$name=';
  if (!line.startsWith(prefix)) {
    throw TerminalGoldenImageFormatException('missing or misplaced $name');
  }
  return line.substring(prefix.length);
}

String _parseChecksum(String line) {
  final String value = _parseValue(line, 'checksum');
  const String prefix = 'fnv1a32:';
  if (!value.startsWith(prefix)) {
    throw const TerminalGoldenImageFormatException(
      'unsupported checksum algorithm',
    );
  }
  final String checksum = value.substring(prefix.length);
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(checksum)) {
    throw const TerminalGoldenImageFormatException(
      'checksum is not canonical lowercase hexadecimal',
    );
  }
  return checksum;
}

void _validateDecodedMetadata({
  required int width,
  required int height,
  required int scale,
  required int rowStride,
  required int payloadLength,
  required TerminalReferenceRenderLimits limits,
}) {
  if (width <= 0 || height <= 0 || scale <= 0) {
    throw const TerminalGoldenImageFormatException(
      'width, height, and scale must be positive',
    );
  }
  if (scale > limits.maximumScale ||
      width % scale != 0 ||
      height % scale != 0 ||
      width ~/ scale > limits.maximumLogicalWidth ||
      height ~/ scale > limits.maximumLogicalHeight) {
    throw const TerminalGoldenImageFormatException(
      'dimensions or scale exceed the configured logical limits',
    );
  }
  final int pixelCount = width * height;
  if (pixelCount > limits.maximumPixelCount) {
    throw TerminalGoldenImageFormatException(
      'pixel limit exceeded: $pixelCount > ${limits.maximumPixelCount}',
    );
  }
  final int expectedRowStride = width * 4;
  final int expectedPayloadLength = expectedRowStride * height;
  if (rowStride != expectedRowStride ||
      payloadLength != expectedPayloadLength) {
    throw const TerminalGoldenImageFormatException(
      'row stride or payload length does not match RGBA dimensions',
    );
  }
}

void _validateImageAgainstLimits(
  TerminalReferenceImage image,
  TerminalReferenceRenderLimits limits,
) {
  try {
    _validateDecodedMetadata(
      width: image.width,
      height: image.height,
      scale: image.scale,
      rowStride: image.rowStride,
      payloadLength: image.byteLength,
      limits: limits,
    );
  } on Object catch (error) {
    throw StateError('golden image exceeds configured limits: $error');
  }
}

final RegExp _canonicalDecimal = RegExp(r'^(?:0|[1-9][0-9]*)$');

String _rgbaHex(int rgba) => '0x${rgba.toRadixString(16).padLeft(8, '0')}';

String _bounded(String value, int maximumCodeUnits) {
  if (value.length <= maximumCodeUnits) {
    return value;
  }
  const String marker = '...[truncated]';
  if (maximumCodeUnits <= marker.length) {
    return marker.substring(0, maximumCodeUnits);
  }
  return '${value.substring(0, maximumCodeUnits - marker.length)}$marker';
}
