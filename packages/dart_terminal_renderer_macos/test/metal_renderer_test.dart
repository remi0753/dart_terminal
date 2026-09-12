import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

@Native<Int32 Function(Uint32)>(
  symbol: 'dtr_debug_metal_fail_next',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _failNextMetalOperation(int failure);

void main() => runMetalRendererTests();

void runMetalRendererTests() {
  _testTypedCreationFailures();
  _testEncoderValidationAndOwnership();
  _testTypedRendererReadback();
}

void _testTypedCreationFailures() {
  _expect(
    _failNextMetalOperation(1) == 0,
    'device creation failure injection is accepted once',
  );
  _expectMetalFailure(
    TerminalMetalRenderer.open,
    TerminalMetalFailureKind.deviceUnavailable,
    'device creation failure is typed',
  );
  _expect(
    _failNextMetalOperation(2) == 0,
    'shader creation failure injection is accepted once',
  );
  _expectMetalFailure(
    TerminalMetalRenderer.open,
    TerminalMetalFailureKind.shaderLibrary,
    'shader creation failure is typed',
  );
}

void _testEncoderValidationAndOwnership() {
  final List<TerminalMetalInstance> source = <TerminalMetalInstance>[
    TerminalMetalInstance.solid(
      kind: TerminalMetalInstanceKind.cellBackground,
      x: 0,
      y: 0,
      width: 2,
      height: 1,
      colorRgba: 0x112233ff,
    ),
  ];
  final TerminalMetalRenderer encoderRenderer = TerminalMetalRenderer.open(
    config: const TerminalMetalRendererConfig(
      maximumViewportWidth: 2,
      maximumViewportHeight: 1,
      maximumInstances: 2,
      atlasWidth: 1,
      atlasHeight: 1,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
    ),
  );
  final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
    renderer: encoderRenderer,
    frameGeneration: 2,
    atlasGeneration: 3,
    viewportWidth: 2,
    viewportHeight: 1,
    scale16_16: 1 << 16,
    backgroundRgba: 0x010203ff,
    instances: source,
  );
  source.clear();
  final Uint8List first = frame.copyBytes();
  final ByteData data = ByteData.sublistView(first);
  _expect(
    frame.byteLength == 128 &&
        frame.instanceCount == 1 &&
        data.getUint32(0, Endian.little) == 0x46525444 &&
        data.getUint32(8, Endian.little) == 80 &&
        data.getUint64(16, Endian.little) == frame.rendererGeneration &&
        data.getUint64(24, Endian.little) == 2 &&
        data.getUint64(32, Endian.little) == 3 &&
        data.getUint32(60, Endian.little) == 48 &&
        data.getUint32(112, Endian.little) == 0x112233ff,
    'little-endian frame layout is exact',
  );
  first.fillRange(0, first.length, 0);
  _expect(
    frame.copyBytes()[0] == 0x44,
    'encoded frame owns bytes independently from callers',
  );
  _expectThrows(
    () => TerminalMetalFrameEncoder.encode(
      renderer: encoderRenderer,
      frameGeneration: 1,
      atlasGeneration: 1,
      viewportWidth: 2,
      viewportHeight: 1,
      scale16_16: 1 << 16,
      backgroundRgba: 0,
      instances: <TerminalMetalInstance>[
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.cursor,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          colorRgba: 0xffffffff,
        ),
        TerminalMetalInstance.solid(
          kind: TerminalMetalInstanceKind.selection,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          colorRgba: 0xffffffff,
        ),
      ],
    ),
    'out-of-order layers are rejected before encoding',
  );
  var yielded = 0;
  Iterable<TerminalMetalInstance> unbounded() sync* {
    while (true) {
      yielded++;
      yield TerminalMetalInstance.solid(
        kind: TerminalMetalInstanceKind.cellBackground,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        colorRgba: 0,
      );
    }
  }

  _expectThrows(
    () => TerminalMetalFrameEncoder.encode(
      renderer: encoderRenderer,
      frameGeneration: 1,
      atlasGeneration: 1,
      viewportWidth: 1,
      viewportHeight: 1,
      scale16_16: 1 << 16,
      backgroundRgba: 0,
      instances: unbounded(),
    ),
    'unbounded instance iterables stop at the renderer cap',
  );
  _expect(
    yielded == 3,
    'encoder does not traverse beyond the first excess instance',
  );
  encoderRenderer.dispose();
}

void _testTypedRendererReadback() {
  final TerminalMetalRenderer renderer = TerminalMetalRenderer.open(
    config: const TerminalMetalRendererConfig(
      maximumViewportWidth: 8,
      maximumViewportHeight: 8,
      maximumInstances: 8,
      atlasWidth: 4,
      atlasHeight: 4,
      maximumAlphaPages: 1,
      maximumColorPages: 1,
    ),
  );
  try {
    _expect(
      renderer.resetAtlas(atlasGeneration: 1) ==
          TerminalMetalUploadDisposition.uploaded,
      'empty atlas reset publishes a complete generation',
    );
    _expect(
      renderer.resetAtlas(atlasGeneration: 1) ==
          TerminalMetalUploadDisposition.stale,
      'atlas reset generations cannot be reused',
    );
    final Uint8List alpha = Uint8List.fromList(<int>[128]);
    final TerminalMetalAtlasUpload alphaUpload = TerminalMetalAtlasUpload(
      rendererGeneration: renderer.generation,
      atlasGeneration: 1,
      pageGeneration: 1,
      format: TerminalMetalAtlasFormat.alpha8,
      pageIndex: 0,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      rowStride: 1,
      bytes: alpha,
    );
    alpha[0] = 0;
    _expect(
      alphaUpload.copyBytes().single == 128 &&
          renderer.uploadAtlas(alphaUpload) ==
              TerminalMetalUploadDisposition.uploaded,
      'alpha upload is copied and accepted',
    );
    final TerminalMetalAtlasUpload colorUpload = TerminalMetalAtlasUpload(
      rendererGeneration: renderer.generation,
      atlasGeneration: 2,
      pageGeneration: 1,
      format: TerminalMetalAtlasFormat.rgba8Straight,
      pageIndex: 0,
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      rowStride: 4,
      bytes: const <int>[0, 255, 0, 128],
    );
    _expect(
      renderer.uploadAtlas(colorUpload) ==
          TerminalMetalUploadDisposition.uploaded,
      'new snapshot preserves the unchanged alpha slice',
    );
    final TerminalMetalFrame frame = TerminalMetalFrameEncoder.encode(
      renderer: renderer,
      frameGeneration: 1,
      atlasGeneration: 2,
      viewportWidth: 2,
      viewportHeight: 1,
      scale16_16: 1 << 16,
      backgroundRgba: 0x101010ff,
      instances: <TerminalMetalInstance>[
        TerminalMetalInstance.glyph(
          format: TerminalMetalAtlasFormat.alpha8,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          atlasX: 0,
          atlasY: 0,
          colorRgba: 0xff0000ff,
          pageIndex: 0,
          pageGeneration: 1,
        ),
        TerminalMetalInstance.glyph(
          format: TerminalMetalAtlasFormat.rgba8Straight,
          x: 1,
          y: 0,
          width: 1,
          height: 1,
          atlasX: 0,
          atlasY: 0,
          colorRgba: 0xffffffff,
          pageIndex: 0,
          pageGeneration: 1,
        ),
      ],
    );
    final Uint8List rgba = renderer.renderRgba(frame);
    _expectPixelNear(rgba, 0, 0x880808ff);
    _expectPixelNear(rgba, 4, 0x088808ff);
    final TerminalMetalRendererState state = renderer.state();
    _expect(
      !state.isBound &&
          state.isAdmitting &&
          !state.isFaulted &&
          state.failure == TerminalMetalFailureKind.none &&
          state.failureGeneration == 0 &&
          state.lastFailedFrameGeneration == 0 &&
          state.drawableUnavailableCount == 0 &&
          state.commandFailureCount == 0 &&
          state.gpuTimingSampleCount == 0 &&
          state.gpuTotalTimeNanoseconds == 0 &&
          state.gpuMaximumTimeNanoseconds == 0 &&
          state.acceptedAtlasUploadCount == 2 &&
          state.acceptedAtlasUploadBytes == 5 &&
          state.readySlotCount == 0 &&
          state.inFlightSlotCount == 0,
      'typed state validates an unbound renderer snapshot',
    );
    _expectThrowsType<TerminalMetalRendererException>(
      renderer.requestPresentation,
      'unbound renderer cannot request presentation',
    );
    _expectThrowsType<TerminalMetalRendererException>(
      () => renderer.submit(frame),
      'unbound production submission is rejected',
    );
    _expect(
      renderer.uploadAtlas(alphaUpload) == TerminalMetalUploadDisposition.stale,
      'older atlas snapshot is surfaced as a typed stale result',
    );
    _expect(
      renderer.resetAtlas(atlasGeneration: 3) ==
          TerminalMetalUploadDisposition.uploaded,
      'empty full rebuild advances without a synthetic glyph upload',
    );
    _expectThrowsType<TerminalMetalRendererException>(
      () => renderer.renderRgba(frame),
      'full reset invalidates all previous page definitions',
    );
  } finally {
    renderer.dispose();
  }
  _expect(renderer.isDisposed, 'explicit release invalidates the facade');
  _expectThrows(
    renderer.state,
    'disposed renderer cannot cross the native boundary',
  );
}

void _expectMetalFailure(
  TerminalMetalRenderer Function() action,
  TerminalMetalFailureKind expected,
  String description,
) {
  try {
    final TerminalMetalRenderer unexpected = action();
    unexpected.dispose();
  } on TerminalMetalRendererException catch (error) {
    _expect(error.failure == expected, description);
    return;
  }
  _expect(false, description);
}

void _expectPixelNear(Uint8List bytes, int offset, int expected) {
  for (int channel = 0; channel < 4; channel++) {
    final int wanted = (expected >> ((3 - channel) * 8)) & 0xff;
    final int actual = bytes[offset + channel];
    if ((actual - wanted).abs() > 1) {
      throw StateError(
        'Metal renderer pixel mismatch at byte ${offset + channel}: '
        'expected $wanted, actual $actual',
      );
    }
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    stderr.writeln('Metal renderer test failed: $description');
    exitCode = 1;
  }
}

void _expectThrows(void Function() action, String description) {
  try {
    action();
  } on Object {
    return;
  }
  _expect(false, description);
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
    throw StateError('$description threw ${error.runtimeType}');
  }
  _expect(false, description);
}
