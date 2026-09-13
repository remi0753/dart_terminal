import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == '--write-goldens') {
    _writeGoldens();
    return;
  }
  if (arguments.isNotEmpty) {
    throw ArgumentError.value(arguments, 'arguments', 'unsupported');
  }
  runGoldenImageTests();
}

void runGoldenImageTests() {
  _testExactCodecRoundTrip();
  _testMetadataAndPayloadRejection();
  _testCodecLimits();
  _testComparisonDiagnostics();
  _testCheckedInFixtures();
}

void _testExactCodecRoundTrip() {
  final TerminalReferenceImage image = _fixtureImage(scale: 1);
  final Uint8List first = TerminalGoldenImageCodec.encode(image);
  final Uint8List second = TerminalGoldenImageCodec.encode(image);
  _expect(_bytesEqual(first, second), 'repeated encoding is byte exact');
  final String text = ascii.decode(first);
  _expect(
    text.startsWith(
          'dart-terminal-golden-image\n'
          'version=1\n'
          'width=3\n'
          'height=2\n'
          'scale=1\n'
          'pixel-format=rgba8-srgb-straight\n'
          'row-stride=12\n'
          'payload-length=24\n'
          'checksum=fnv1a32:',
        ) &&
        text.endsWith('\n'),
    'version-one field order and trailing newline are canonical',
  );
  final TerminalReferenceImage decoded = TerminalGoldenImageCodec.decode(first);
  final TerminalGoldenImageComparison comparison =
      TerminalGoldenImageComparator.compare(image, decoded);
  _expect(
    comparison.matches && comparison.diagnostic.isEmpty,
    'codec round trip preserves geometry, scale, and exact pixels',
  );
  first.fillRange(0, first.length, 0);
  _expect(
    decoded.pixelAt(0, 0) == image.pixelAt(0, 0),
    'decoder owns pixels independently from encoded input',
  );
}

void _testMetadataAndPayloadRejection() {
  final String valid = ascii.decode(
    TerminalGoldenImageCodec.encode(_fixtureImage(scale: 1)),
  );
  _expectDecodeFails(
    valid.replaceFirst('dart-terminal-golden-image', 'wrong-format'),
    'format name corruption',
  );
  _expectDecodeFails(
    valid.replaceFirst('version=1', 'version=2'),
    'unsupported version',
  );
  _expectDecodeFails(
    valid.replaceFirst('width=3', 'width=03'),
    'noncanonical decimal',
  );
  _expectDecodeFails(
    valid.replaceFirst('width=3\nheight=2', 'height=2\nwidth=3'),
    'field reordering',
  );
  _expectDecodeFails(
    valid.replaceFirst(
      'pixel-format=rgba8-srgb-straight',
      'pixel-format=bgra8-srgb-straight',
    ),
    'unsupported pixel format',
  );
  _expectDecodeFails(
    valid.replaceFirst('row-stride=12', 'row-stride=13'),
    'row stride mismatch',
  );
  _expectDecodeFails(
    valid.replaceFirst('payload-length=24', 'payload-length=25'),
    'payload length mismatch',
  );
  _expectDecodeFails(
    valid.replaceFirst('checksum=fnv1a32:', 'checksum=sha256:'),
    'checksum algorithm change',
  );
  _expectDecodeFails(
    valid.replaceFirst(RegExp(r'[0-9a-f]{8}\npixels='), '00000000\npixels='),
    'checksum mismatch',
  );
  final RegExp payloadPattern = RegExp(r'pixels=([^\n]+)');
  final String payload = payloadPattern.firstMatch(valid)!.group(1)!;
  _expectDecodeFails(
    valid.replaceFirst(
      'pixels=$payload',
      'pixels=${payload.substring(0, payload.length - 1)}',
    ),
    'truncated Base64',
  );
  _expectDecodeFails(
    valid.replaceFirst('pixels=$payload', 'pixels=*$payload'),
    'non-Base64 character',
  );
  _expectDecodeFails('$valid\n', 'extra newline');
  _expectDecodeFails('${valid}trailing', 'trailing data');
  _expectDecodeBytesFail(<int>[
    ...ascii.encode(valid.substring(0, valid.length - 1)),
    0x80,
  ], 'non-ASCII byte');
  _expectDecodeBytesFail(<int>[-1], 'out-of-byte-range value');
}

void _testCodecLimits() {
  final TerminalReferenceImage image = _fixtureImage(scale: 1);
  final Uint8List encoded = TerminalGoldenImageCodec.encode(image);
  _expectThrows(
    () => TerminalGoldenImageCodec.encode(
      image,
      limits: TerminalGoldenImageLimits(
        maximumEncodedBytes: encoded.length - 1,
      ),
    ),
    'encoder byte cap',
  );
  _expectThrows(
    () => TerminalGoldenImageCodec.decode(
      encoded,
      limits: TerminalGoldenImageLimits(
        maximumEncodedBytes: encoded.length - 1,
      ),
    ),
    'decoder byte cap before text conversion',
  );
  _expectThrows(
    () => TerminalGoldenImageCodec.decode(
      encoded,
      limits: const TerminalGoldenImageLimits(
        renderLimits: TerminalReferenceRenderLimits(maximumPixelCount: 5),
      ),
    ),
    'decoded pixel cap before Base64 allocation',
  );
  _expectThrows(
    () => TerminalGoldenImageCodec.decode(
      TerminalGoldenImageCodec.encode(_fixtureImage(scale: 2)),
      limits: const TerminalGoldenImageLimits(
        renderLimits: TerminalReferenceRenderLimits(maximumScale: 1),
      ),
    ),
    'decoded scale cap',
  );
}

void _testComparisonDiagnostics() {
  final TerminalReferenceImage expected = TerminalReferenceImage.fromRgba(
    width: 2,
    height: 1,
    scale: 1,
    rgba: const <int>[1, 2, 3, 4, 5, 6, 7, 8],
  );
  final TerminalReferenceImage actual = TerminalReferenceImage.fromRgba(
    width: 2,
    height: 1,
    scale: 1,
    rgba: const <int>[1, 2, 3, 4, 5, 6, 9, 8],
  );
  final TerminalGoldenImageComparison mismatch =
      TerminalGoldenImageComparator.compare(expected, actual);
  _expect(
    !mismatch.matches &&
        mismatch.x == 1 &&
        mismatch.y == 0 &&
        mismatch.expectedRgba == 0x05060708 &&
        mismatch.actualRgba == 0x05060908 &&
        mismatch.diagnostic ==
            'golden pixel mismatch at (1, 0): expected 0x05060708, '
                'actual 0x05060908',
    'first pixel mismatch includes exact coordinate and RGBA',
  );
  _expectThrowsType<TerminalGoldenImageMismatchException>(
    () => mismatch.requireMatch('reference scene'),
    'typed comparison assertion',
  );
  final TerminalReferenceImage geometry = TerminalReferenceImage.fromRgba(
    width: 1,
    height: 1,
    scale: 1,
    rgba: const <int>[1, 2, 3, 4],
  );
  final TerminalGoldenImageComparison geometryMismatch =
      TerminalGoldenImageComparator.compare(expected, geometry);
  _expect(
    !geometryMismatch.matches &&
        geometryMismatch.x == null &&
        geometryMismatch.diagnostic.contains('expected 2x1@1x, actual 1x1@1x'),
    'geometry mismatch is distinct from pixel mismatch',
  );
  final TerminalGoldenImageComparison truncated =
      TerminalGoldenImageComparator.compare(
        expected,
        geometry,
        limits: const TerminalGoldenImageComparisonLimits(
          maximumDiagnosticCodeUnits: 12,
        ),
      );
  _expect(
    truncated.diagnostic.length == 12,
    'comparison diagnostic obeys its hard output cap',
  );
  _expectThrows(
    () => mismatch.requireMatch(
      'too long',
      limits: const TerminalGoldenImageComparisonLimits(
        maximumDescriptionCodeUnits: 2,
      ),
    ),
    'assertion description is bounded',
  );
}

void _testCheckedInFixtures() {
  for (final int scale in <int>[1, 2]) {
    final File fixture = File('test/goldens/reference/layers-${scale}x.dtgi');
    _expect(fixture.existsSync(), 'checked-in ${scale}x fixture exists');
    final Uint8List expectedBytes = fixture.readAsBytesSync();
    final TerminalReferenceImage rendered = _fixtureImage(scale: scale);
    final Uint8List actualBytes = TerminalGoldenImageCodec.encode(rendered);
    _expect(
      _bytesEqual(expectedBytes, actualBytes),
      'checked-in ${scale}x artifact is exact and never rewritten by tests',
    );
    final TerminalReferenceImage decoded = TerminalGoldenImageCodec.decode(
      expectedBytes,
    );
    TerminalGoldenImageComparator.compare(
      rendered,
      decoded,
    ).requireMatch('checked-in ${scale}x reference fixture');
  }
}

void _writeGoldens() {
  for (final int scale in <int>[1, 2]) {
    final File fixture = File('test/goldens/reference/layers-${scale}x.dtgi');
    fixture.writeAsBytesSync(
      TerminalGoldenImageCodec.encode(_fixtureImage(scale: scale)),
      flush: true,
    );
    stdout.writeln('wrote ${fixture.path}');
  }
}

TerminalReferenceImage _fixtureImage({required int scale}) =>
    TerminalReferenceRenderer.render(
      width: 3,
      height: 2,
      scale: scale,
      background: const TerminalReferenceColor(0x102030ff),
      primitives: <TerminalReferencePrimitive>[
        const TerminalReferenceSolid(
          layer: TerminalReferenceLayer.cellBackground,
          x: 0,
          y: 0,
          width: 2,
          height: 1,
          color: TerminalReferenceColor(0x804020ff),
        ),
        const TerminalReferenceSolid(
          layer: TerminalReferenceLayer.selection,
          x: 1,
          y: 0,
          width: 2,
          height: 2,
          color: TerminalReferenceColor(0x00ff0080),
        ),
        TerminalReferenceMask(
          layer: TerminalReferenceLayer.glyph,
          x: 0,
          y: 0,
          width: 2,
          height: 2,
          rowStride: 2,
          coverage: const <int>[0, 255, 128, 64],
          color: const TerminalReferenceColor(0xffffffff),
        ),
        TerminalReferenceBitmap(
          layer: TerminalReferenceLayer.glyph,
          x: 2,
          y: 0,
          width: 1,
          height: 1,
          rowStride: 4,
          rgba: const <int>[255, 0, 255, 128],
        ),
        const TerminalReferenceSolid(
          layer: TerminalReferenceLayer.decoration,
          x: 0,
          y: 1,
          width: 3,
          height: 1,
          color: TerminalReferenceColor(0x0000ff40),
        ),
        const TerminalReferenceSolid(
          layer: TerminalReferenceLayer.cursor,
          x: 1,
          y: 1,
          width: 1,
          height: 1,
          color: TerminalReferenceColor(0xffff00c0),
        ),
      ],
    );

void _expectDecodeFails(String encoded, String description) =>
    _expectDecodeBytesFail(ascii.encode(encoded), description);

void _expectDecodeBytesFail(List<int> encoded, String description) {
  _expectThrowsType<TerminalGoldenImageFormatException>(
    () => TerminalGoldenImageCodec.decode(encoded),
    description,
  );
}

bool _bytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('golden image expectation failed: $description');
  }
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError('golden image expectation failed: $description');
}

void _expectThrowsType<T extends Object>(
  void Function() action,
  String description,
) {
  try {
    action();
  } on T {
    return;
  } on Object catch (error) {
    throw StateError(
      'golden image expectation failed: $description threw '
      '${error.runtimeType}',
    );
  }
  throw StateError('golden image expectation failed: $description');
}
