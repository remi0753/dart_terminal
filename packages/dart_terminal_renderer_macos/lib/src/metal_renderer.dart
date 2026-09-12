import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:ffi/ffi.dart';

const String _metalAssetId =
    'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

enum TerminalMetalInstanceKind {
  cellBackground(1, 1),
  selection(2, 2),
  alphaGlyph(3, 3),
  colorGlyph(4, 3),
  decoration(5, 5),
  cursor(6, 6);

  const TerminalMetalInstanceKind(this.nativeValue, this.layerOrder);

  final int nativeValue;
  final int layerOrder;

  bool get isGlyph =>
      this == TerminalMetalInstanceKind.alphaGlyph ||
      this == TerminalMetalInstanceKind.colorGlyph;
}

enum TerminalMetalAtlasFormat {
  alpha8(1, 1),
  rgba8Straight(2, 4);

  const TerminalMetalAtlasFormat(this.nativeValue, this.bytesPerPixel);

  final int nativeValue;
  final int bytesPerPixel;
}

enum TerminalMetalUploadDisposition { uploaded, stale, backpressured }

enum TerminalMetalSubmissionDisposition { accepted, stale, backpressured }

enum TerminalMetalFailureKind {
  none(0),
  deviceUnavailable(1),
  shaderLibrary(2),
  shaderFunction(3),
  pipeline(4),
  resourceAllocation(5),
  commandEncoding(6),
  commandExecution(7),
  deviceLost(8);

  const TerminalMetalFailureKind(this.nativeValue);

  final int nativeValue;
}

final class TerminalMetalRendererException implements Exception {
  const TerminalMetalRendererException({
    required this.operation,
    required this.status,
    this.failure = TerminalMetalFailureKind.none,
  });

  final String operation;
  final int status;
  final TerminalMetalFailureKind failure;

  @override
  String toString() =>
      'TerminalMetalRendererException('
      '$operation, status=$status, failure=${failure.name})';
}

final class TerminalMetalRendererConfig {
  const TerminalMetalRendererConfig({
    this.maximumViewportWidth = 4096,
    this.maximumViewportHeight = 4096,
    this.maximumInstances = 131072,
    this.atlasWidth = 512,
    this.atlasHeight = 512,
    this.maximumAlphaPages = 8,
    this.maximumColorPages = 4,
  });

  final int maximumViewportWidth;
  final int maximumViewportHeight;
  final int maximumInstances;
  final int atlasWidth;
  final int atlasHeight;
  final int maximumAlphaPages;
  final int maximumColorPages;

  void validate() {
    RangeError.checkValueInInterval(
      maximumViewportWidth,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'maximumViewportWidth',
    );
    RangeError.checkValueInInterval(
      maximumViewportHeight,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'maximumViewportHeight',
    );
    RangeError.checkValueInInterval(
      maximumInstances,
      1,
      TerminalMetalFrameEncoder.maximumInstances,
      'maximumInstances',
    );
    RangeError.checkValueInInterval(
      atlasWidth,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'atlasWidth',
    );
    RangeError.checkValueInInterval(
      atlasHeight,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'atlasHeight',
    );
    RangeError.checkValueInInterval(
      maximumAlphaPages,
      1,
      TerminalMetalRenderer.maximumAtlasPages,
      'maximumAlphaPages',
    );
    RangeError.checkValueInInterval(
      maximumColorPages,
      1,
      TerminalMetalRenderer.maximumAtlasPages,
      'maximumColorPages',
    );
    final int pixels = atlasWidth * atlasHeight;
    final int bytes =
        pixels * maximumAlphaPages + pixels * 4 * maximumColorPages;
    if (bytes > TerminalMetalRenderer.maximumAtlasBytes) {
      throw RangeError.range(
        bytes,
        1,
        TerminalMetalRenderer.maximumAtlasBytes,
        'aggregateAtlasBytes',
      );
    }
  }
}

final class TerminalMetalInstance {
  const TerminalMetalInstance._({
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.atlasX,
    required this.atlasY,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.colorRgba,
    required this.pageIndex,
    required this.pageGeneration,
  });

  factory TerminalMetalInstance.solid({
    required TerminalMetalInstanceKind kind,
    required int x,
    required int y,
    required int width,
    required int height,
    required int colorRgba,
  }) {
    if (kind.isGlyph) {
      throw ArgumentError.value(kind, 'kind', 'must be a solid visual kind');
    }
    return TerminalMetalInstance._(
      kind: kind,
      x: x,
      y: y,
      width: width,
      height: height,
      atlasX: 0,
      atlasY: 0,
      atlasWidth: 0,
      atlasHeight: 0,
      colorRgba: colorRgba,
      pageIndex: 0,
      pageGeneration: 0,
    );
  }

  factory TerminalMetalInstance.glyph({
    required TerminalMetalAtlasFormat format,
    required int x,
    required int y,
    required int width,
    required int height,
    required int atlasX,
    required int atlasY,
    required int colorRgba,
    required int pageIndex,
    required int pageGeneration,
  }) => TerminalMetalInstance._(
    kind: format == TerminalMetalAtlasFormat.alpha8
        ? TerminalMetalInstanceKind.alphaGlyph
        : TerminalMetalInstanceKind.colorGlyph,
    x: x,
    y: y,
    width: width,
    height: height,
    atlasX: atlasX,
    atlasY: atlasY,
    atlasWidth: width,
    atlasHeight: height,
    colorRgba: colorRgba,
    pageIndex: pageIndex,
    pageGeneration: pageGeneration,
  );

  final TerminalMetalInstanceKind kind;
  final int x;
  final int y;
  final int width;
  final int height;
  final int atlasX;
  final int atlasY;
  final int atlasWidth;
  final int atlasHeight;
  final int colorRgba;
  final int pageIndex;
  final int pageGeneration;
}

final class TerminalMetalFrame {
  TerminalMetalFrame._({
    required this.rendererGeneration,
    required this.frameGeneration,
    required this.atlasGeneration,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scale16_16,
    required this.instanceCount,
    required Uint8List bytes,
  }) : _bytes = bytes;

  final int rendererGeneration;
  final int frameGeneration;
  final int atlasGeneration;
  final int viewportWidth;
  final int viewportHeight;
  final int scale16_16;
  final int instanceCount;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}

abstract final class TerminalMetalFrameEncoder {
  static const int maximumDimension = 4096;
  static const int maximumInstances = 131072;
  static const int maximumFrameBytes = 8 * 1024 * 1024;
  static const int headerBytes = 80;
  static const int instanceBytes = 48;

  static TerminalMetalFrame encode({
    required TerminalMetalRenderer renderer,
    required int frameGeneration,
    required int atlasGeneration,
    required int viewportWidth,
    required int viewportHeight,
    required int scale16_16,
    required int backgroundRgba,
    required Iterable<TerminalMetalInstance> instances,
  }) {
    renderer._liveHandle();
    _requirePositiveInt64(frameGeneration, 'frameGeneration');
    _requirePositiveInt64(atlasGeneration, 'atlasGeneration');
    RangeError.checkValueInInterval(
      viewportWidth,
      1,
      renderer.config.maximumViewportWidth,
      'viewportWidth',
    );
    RangeError.checkValueInInterval(
      viewportHeight,
      1,
      renderer.config.maximumViewportHeight,
      'viewportHeight',
    );
    RangeError.checkValueInInterval(scale16_16, 1, 16 << 16, 'scale16_16');
    _requireUint32(backgroundRgba, 'backgroundRgba');
    final List<TerminalMetalInstance> retained = <TerminalMetalInstance>[];
    var previousLayer = 0;
    for (final TerminalMetalInstance instance in instances) {
      if (retained.length == renderer.config.maximumInstances) {
        throw StateError('Metal instance limit exceeded');
      }
      _validateInstance(
        instance,
        viewportWidth,
        viewportHeight,
        renderer.config,
      );
      if (instance.kind.layerOrder < previousLayer) {
        throw ArgumentError.value(
          instance.kind,
          'instances',
          'must use nondecreasing terminal layer order',
        );
      }
      previousLayer = instance.kind.layerOrder;
      retained.add(instance);
    }
    final int totalBytes = headerBytes + retained.length * instanceBytes;
    if (totalBytes > maximumFrameBytes) {
      throw StateError('Metal frame byte limit exceeded');
    }
    final Uint8List bytes = Uint8List(totalBytes);
    final ByteData data = ByteData.sublistView(bytes);
    void u32(int offset, int value) =>
        data.setUint32(offset, value, Endian.little);
    void i32(int offset, int value) =>
        data.setInt32(offset, value, Endian.little);
    void u64(int offset, int value) =>
        data.setUint64(offset, value, Endian.little);
    u32(0, 0x46525444);
    u32(4, 1);
    u32(8, headerBytes);
    u32(12, totalBytes);
    u64(16, renderer.generation);
    u64(24, frameGeneration);
    u64(32, atlasGeneration);
    u32(40, viewportWidth);
    u32(44, viewportHeight);
    u32(48, scale16_16);
    u32(52, backgroundRgba);
    u32(56, retained.length);
    u32(60, instanceBytes);
    u32(64, headerBytes);
    for (int index = 0; index < retained.length; index++) {
      final TerminalMetalInstance instance = retained[index];
      final int offset = headerBytes + index * instanceBytes;
      i32(offset, instance.x);
      i32(offset + 4, instance.y);
      u32(offset + 8, instance.width);
      u32(offset + 12, instance.height);
      u32(offset + 16, instance.atlasX);
      u32(offset + 20, instance.atlasY);
      u32(offset + 24, instance.atlasWidth);
      u32(offset + 28, instance.atlasHeight);
      u32(offset + 32, instance.colorRgba);
      u32(offset + 36, instance.kind.nativeValue);
      u32(offset + 40, instance.pageIndex);
      u32(offset + 44, instance.pageGeneration);
    }
    return TerminalMetalFrame._(
      rendererGeneration: renderer.generation,
      frameGeneration: frameGeneration,
      atlasGeneration: atlasGeneration,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      scale16_16: scale16_16,
      instanceCount: retained.length,
      bytes: bytes,
    );
  }

  static void _validateInstance(
    TerminalMetalInstance instance,
    int viewportWidth,
    int viewportHeight,
    TerminalMetalRendererConfig config,
  ) {
    _requireInt32(instance.x, 'instance.x');
    _requireInt32(instance.y, 'instance.y');
    _requireUint32(instance.width, 'instance.width');
    _requireUint32(instance.height, 'instance.height');
    _requireUint32(instance.colorRgba, 'instance.colorRgba');
    if (instance.width == 0 ||
        instance.height == 0 ||
        instance.width > viewportWidth ||
        instance.height > viewportHeight ||
        instance.x + instance.width <= 0 ||
        instance.y + instance.height <= 0 ||
        instance.x >= viewportWidth ||
        instance.y >= viewportHeight) {
      throw ArgumentError.value(instance, 'instances', 'invalid bounds');
    }
    if (!instance.kind.isGlyph) {
      if (instance.atlasX != 0 ||
          instance.atlasY != 0 ||
          instance.atlasWidth != 0 ||
          instance.atlasHeight != 0 ||
          instance.pageIndex != 0 ||
          instance.pageGeneration != 0) {
        throw ArgumentError.value(
          instance,
          'instances',
          'solid instance must not reference an atlas',
        );
      }
      return;
    }
    _requireUint32(instance.atlasX, 'instance.atlasX');
    _requireUint32(instance.atlasY, 'instance.atlasY');
    _requireUint32(instance.atlasWidth, 'instance.atlasWidth');
    _requireUint32(instance.atlasHeight, 'instance.atlasHeight');
    _requireUint32(instance.pageIndex, 'instance.pageIndex');
    _requireUint32(instance.pageGeneration, 'instance.pageGeneration');
    if (instance.atlasWidth != instance.width ||
        instance.atlasHeight != instance.height ||
        instance.pageGeneration == 0 ||
        instance.atlasX + instance.atlasWidth > config.atlasWidth ||
        instance.atlasY + instance.atlasHeight > config.atlasHeight ||
        instance.pageIndex >=
            (instance.kind == TerminalMetalInstanceKind.alphaGlyph
                ? config.maximumAlphaPages
                : config.maximumColorPages)) {
      throw ArgumentError.value(instance, 'instances', 'invalid atlas shape');
    }
  }
}

final class TerminalMetalAtlasUpload {
  TerminalMetalAtlasUpload({
    required this.rendererGeneration,
    required this.atlasGeneration,
    required this.pageGeneration,
    required this.format,
    required this.pageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rowStride,
    required List<int> bytes,
  }) : _bytes = Uint8List.fromList(bytes) {
    _requirePositiveInt64(rendererGeneration, 'rendererGeneration');
    _requirePositiveInt64(atlasGeneration, 'atlasGeneration');
    _requireUint32(pageGeneration, 'pageGeneration');
    if (pageGeneration == 0) {
      throw RangeError.value(pageGeneration, 'pageGeneration');
    }
    _requireUint32(pageIndex, 'pageIndex');
    _requireUint32(x, 'x');
    _requireUint32(y, 'y');
    _requireUint32(width, 'width');
    _requireUint32(height, 'height');
    _requireUint32(rowStride, 'rowStride');
    if (width == 0 ||
        height == 0 ||
        rowStride != width * format.bytesPerPixel ||
        _bytes.length != rowStride * height) {
      throw ArgumentError('invalid Metal atlas upload byte layout');
    }
  }

  final int rendererGeneration;
  final int atlasGeneration;
  final int pageGeneration;
  final TerminalMetalAtlasFormat format;
  final int pageIndex;
  final int x;
  final int y;
  final int width;
  final int height;
  final int rowStride;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}

final class TerminalMetalSubmissionResult {
  const TerminalMetalSubmissionResult._({
    required this.disposition,
    required this.rendererGeneration,
    required this.submissionToken,
    required this.frameGeneration,
  });

  final TerminalMetalSubmissionDisposition disposition;
  final int rendererGeneration;
  final int submissionToken;
  final int frameGeneration;

  bool get isAccepted =>
      disposition == TerminalMetalSubmissionDisposition.accepted;
}

final class TerminalMetalRendererState {
  const TerminalMetalRendererState({
    required this.rendererGeneration,
    required this.lastAcceptedFrameGeneration,
    required this.lastSubmissionToken,
    required this.retiredThroughToken,
    required this.lastPresentedFrameGeneration,
    required this.acceptedSubmissionCount,
    required this.completedSubmissionCount,
    required this.staleReadyDropCount,
    required this.backpressureCount,
    required this.readySlotCount,
    required this.inFlightSlotCount,
    required this.isBound,
    required this.isAdmitting,
    required this.isFaulted,
    required this.failure,
    required this.failureGeneration,
    required this.lastFailedFrameGeneration,
    required this.drawableUnavailableCount,
    required this.commandFailureCount,
    required this.gpuTimingSampleCount,
    required this.gpuTotalTimeNanoseconds,
    required this.gpuMaximumTimeNanoseconds,
    required this.acceptedAtlasUploadCount,
    required this.acceptedAtlasUploadBytes,
  });

  final int rendererGeneration;
  final int lastAcceptedFrameGeneration;
  final int lastSubmissionToken;
  final int retiredThroughToken;
  final int lastPresentedFrameGeneration;
  final int acceptedSubmissionCount;
  final int completedSubmissionCount;
  final int staleReadyDropCount;
  final int backpressureCount;
  final int readySlotCount;
  final int inFlightSlotCount;
  final bool isBound;
  final bool isAdmitting;
  final bool isFaulted;
  final TerminalMetalFailureKind failure;
  final int failureGeneration;
  final int lastFailedFrameGeneration;
  final int drawableUnavailableCount;
  final int commandFailureCount;
  final int gpuTimingSampleCount;
  final int gpuTotalTimeNanoseconds;
  final int gpuMaximumTimeNanoseconds;
  final int acceptedAtlasUploadCount;
  final int acceptedAtlasUploadBytes;
}

/// Generation-owned, bounded native Metal renderer.
///
/// [submit] only validates and copies. Native view presentation and GPU
/// completion are asynchronous and observable through [state].
final class TerminalMetalRenderer implements Finalizable {
  factory TerminalMetalRenderer.open({
    TerminalMetalRendererConfig config = const TerminalMetalRendererConfig(),
  }) {
    config.validate();
    _checkMetalLayout();
    final Arena arena = Arena();
    try {
      final Pointer<_MetalRendererConfigV1> nativeConfig =
          arena<_MetalRendererConfigV1>();
      nativeConfig.ref
        ..structSize = sizeOf<_MetalRendererConfigV1>()
        ..version = 1
        ..maximumViewportWidth = config.maximumViewportWidth
        ..maximumViewportHeight = config.maximumViewportHeight
        ..maximumInstances = config.maximumInstances
        ..atlasWidth = config.atlasWidth
        ..atlasHeight = config.atlasHeight
        ..maximumAlphaPages = config.maximumAlphaPages
        ..maximumColorPages = config.maximumColorPages;
      final Pointer<_MetalRendererSummaryV1> output =
          arena<_MetalRendererSummaryV1>();
      output.ref
        ..structSize = sizeOf<_MetalRendererSummaryV1>()
        ..version = 2;
      final int status = _metalRendererCreate(nativeConfig, output);
      final _MetalRendererSummaryV1 summary = output.ref;
      if (summary.structSize != sizeOf<_MetalRendererSummaryV1>() ||
          summary.version != 2 ||
          !_reservedZero(summary.reserved, 2)) {
        if (summary.handle != 0) _metalRendererRelease(summary.handle);
        throw const FormatException('invalid native Metal renderer summary');
      }
      final TerminalMetalFailureKind failure = _metalFailureFromNative(
        summary.failureKind,
      );
      if (status != 0) {
        if (summary.handle != 0 ||
            summary.generation != 0 ||
            failure == TerminalMetalFailureKind.none) {
          if (summary.handle != 0) _metalRendererRelease(summary.handle);
          throw const FormatException('invalid failed Metal renderer summary');
        }
        throw TerminalMetalRendererException(
          operation: 'Metal renderer create',
          status: status,
          failure: failure,
        );
      }
      if (failure != TerminalMetalFailureKind.none ||
          summary.handle == 0 ||
          summary.generation == 0 ||
          summary.maximumViewportWidth != config.maximumViewportWidth ||
          summary.maximumViewportHeight != config.maximumViewportHeight ||
          summary.maximumInstances != config.maximumInstances ||
          summary.atlasWidth != config.atlasWidth ||
          summary.atlasHeight != config.atlasHeight ||
          summary.maximumAlphaPages != config.maximumAlphaPages ||
          summary.maximumColorPages != config.maximumColorPages) {
        if (summary.handle != 0) _metalRendererRelease(summary.handle);
        throw const FormatException('invalid native Metal renderer summary');
      }
      final TerminalMetalRenderer renderer = TerminalMetalRenderer._(
        handle: summary.handle,
        generation: summary.generation,
        config: config,
      );
      _metalRendererFinalizer.attach(
        renderer,
        Pointer<Void>.fromAddress(summary.handle),
        detach: renderer,
      );
      return renderer;
    } finally {
      arena.releaseAll();
    }
  }

  TerminalMetalRenderer._({
    required int handle,
    required this.generation,
    required this.config,
  }) : _handle = handle;

  static const int maximumAtlasPages = 16;
  static const int maximumAtlasBytes = 64 * 1024 * 1024;

  int _handle;
  final int generation;
  final TerminalMetalRendererConfig config;

  bool get isDisposed => _handle == 0;

  void bindToView(View view) {
    final int handle = _liveHandle();
    final Uint8List payload = Uint8List(32);
    final ByteData data = ByteData.sublistView(payload);
    data.setUint32(0, 32, Endian.little);
    data.setUint32(4, 1, Endian.little);
    data.setUint32(8, 1, Endian.little);
    data.setUint64(16, handle, Endian.little);
    data.setUint64(24, generation, Endian.little);
    view.performCustomOperation(payload);
  }

  /// Retriggers on-demand presentation of a retained READY frame.
  ///
  /// Native never installs an automatic retry loop when a drawable is absent;
  /// the window visibility/resume owner calls this at its next useful epoch.
  void requestPresentation() {
    _checkMetalStatus(
      _metalRendererRequestDraw(_liveHandle()),
      'Metal presentation request',
    );
  }

  TerminalMetalUploadDisposition resetAtlas({required int atlasGeneration}) {
    final int handle = _liveHandle();
    _requirePositiveInt64(atlasGeneration, 'atlasGeneration');
    final Arena arena = Arena();
    try {
      final Pointer<_MetalAtlasResetV1> reset = arena<_MetalAtlasResetV1>();
      reset.ref
        ..structSize = sizeOf<_MetalAtlasResetV1>()
        ..version = 1
        ..rendererGeneration = generation
        ..atlasGeneration = atlasGeneration;
      final int status = _metalRendererResetAtlas(handle, reset);
      return switch (status) {
        0 => TerminalMetalUploadDisposition.uploaded,
        8 => TerminalMetalUploadDisposition.stale,
        9 => TerminalMetalUploadDisposition.backpressured,
        _ => throw TerminalMetalRendererException(
          operation: 'Metal atlas reset',
          status: status,
        ),
      };
    } finally {
      arena.releaseAll();
    }
  }

  TerminalMetalUploadDisposition uploadAtlas(TerminalMetalAtlasUpload upload) {
    final int handle = _liveHandle();
    if (upload.rendererGeneration != generation ||
        upload.pageIndex >= _pageLimit(upload.format) ||
        upload.x + upload.width > config.atlasWidth ||
        upload.y + upload.height > config.atlasHeight) {
      throw ArgumentError('atlas upload is outside this renderer domain');
    }
    final Arena arena = Arena();
    try {
      final Pointer<_MetalAtlasUploadV1> nativeUpload =
          arena<_MetalAtlasUploadV1>();
      nativeUpload.ref
        ..structSize = sizeOf<_MetalAtlasUploadV1>()
        ..version = 1
        ..rendererGeneration = upload.rendererGeneration
        ..atlasGeneration = upload.atlasGeneration
        ..pageGeneration = upload.pageGeneration
        ..format = upload.format.nativeValue
        ..pageIndex = upload.pageIndex
        ..x = upload.x
        ..y = upload.y
        ..width = upload.width
        ..height = upload.height
        ..rowStride = upload.rowStride
        ..byteLength = upload.byteLength;
      final Pointer<Uint8> pixels = arena<Uint8>(upload.byteLength);
      pixels.asTypedList(upload.byteLength).setAll(0, upload._bytes);
      final int status = _metalRendererUpload(handle, nativeUpload, pixels);
      return switch (status) {
        0 => TerminalMetalUploadDisposition.uploaded,
        8 => TerminalMetalUploadDisposition.stale,
        9 => TerminalMetalUploadDisposition.backpressured,
        _ => throw TerminalMetalRendererException(
          operation: 'Metal atlas upload',
          status: status,
        ),
      };
    } finally {
      arena.releaseAll();
    }
  }

  TerminalMetalSubmissionResult submit(TerminalMetalFrame frame) {
    final int handle = _liveHandle();
    _validateFrameDomain(frame);
    final Arena arena = Arena();
    try {
      final Pointer<Uint8> bytes = arena<Uint8>(frame.byteLength);
      bytes.asTypedList(frame.byteLength).setAll(0, frame._bytes);
      final Pointer<_MetalSubmissionV1> output = arena<_MetalSubmissionV1>();
      output.ref
        ..structSize = sizeOf<_MetalSubmissionV1>()
        ..version = 1;
      final int status = _metalRendererSubmit(
        handle,
        bytes,
        frame.byteLength,
        output,
      );
      final _MetalSubmissionV1 submission = output.ref;
      if (submission.structSize != sizeOf<_MetalSubmissionV1>() ||
          submission.version != 1 ||
          !_reservedZero(submission.reserved, 2)) {
        throw const FormatException('invalid native Metal submission result');
      }
      if (status == 0) {
        if (submission.rendererGeneration != generation ||
            submission.submissionToken == 0 ||
            submission.frameGeneration != frame.frameGeneration) {
          throw const FormatException('invalid accepted Metal submission');
        }
        return TerminalMetalSubmissionResult._(
          disposition: TerminalMetalSubmissionDisposition.accepted,
          rendererGeneration: submission.rendererGeneration,
          submissionToken: submission.submissionToken,
          frameGeneration: submission.frameGeneration,
        );
      }
      if (submission.rendererGeneration != 0 ||
          submission.submissionToken != 0 ||
          submission.frameGeneration != 0) {
        throw const FormatException('rejected Metal submission published data');
      }
      if (status == 8 || status == 9) {
        return TerminalMetalSubmissionResult._(
          disposition: status == 8
              ? TerminalMetalSubmissionDisposition.stale
              : TerminalMetalSubmissionDisposition.backpressured,
          rendererGeneration: 0,
          submissionToken: 0,
          frameGeneration: 0,
        );
      }
      throw TerminalMetalRendererException(
        operation: 'Metal frame submit',
        status: status,
      );
    } finally {
      arena.releaseAll();
    }
  }

  TerminalMetalRendererState state() {
    final int handle = _liveHandle();
    final Arena arena = Arena();
    try {
      final Pointer<_MetalRendererStateV1> output =
          arena<_MetalRendererStateV1>();
      output.ref
        ..structSize = sizeOf<_MetalRendererStateV1>()
        ..version = 3;
      _checkMetalStatus(
        _metalRendererState(handle, output),
        'Metal renderer state',
      );
      final _MetalRendererStateV1 value = output.ref;
      final TerminalMetalFailureKind failure = _metalFailureFromNative(
        value.failureKind,
      );
      final bool isFaulted = value.flags & 4 != 0;
      if (value.structSize != sizeOf<_MetalRendererStateV1>() ||
          value.version != 3 ||
          value.rendererGeneration != generation ||
          value.retiredThroughToken > value.lastSubmissionToken ||
          value.lastAcceptedFrameGeneration <
              value.lastPresentedFrameGeneration ||
          value.readySlotCount + value.inFlightSlotCount > 3 ||
          !_validMetalMetrics(value) ||
          value.flags & ~7 != 0 ||
          !_reservedZero(value.reserved, 2) ||
          (isFaulted != (failure != TerminalMetalFailureKind.none)) ||
          (isFaulted &&
              (value.failureGeneration == 0 ||
                  value.lastFailedFrameGeneration == 0 ||
                  value.commandFailureCount == 0)) ||
          (!isFaulted &&
              (value.failureGeneration != 0 ||
                  value.lastFailedFrameGeneration != 0 ||
                  value.commandFailureCount != 0))) {
        throw const FormatException('invalid native Metal renderer state');
      }
      return TerminalMetalRendererState(
        rendererGeneration: value.rendererGeneration,
        lastAcceptedFrameGeneration: value.lastAcceptedFrameGeneration,
        lastSubmissionToken: value.lastSubmissionToken,
        retiredThroughToken: value.retiredThroughToken,
        lastPresentedFrameGeneration: value.lastPresentedFrameGeneration,
        acceptedSubmissionCount: value.acceptedSubmissionCount,
        completedSubmissionCount: value.completedSubmissionCount,
        staleReadyDropCount: value.staleReadyDropCount,
        backpressureCount: value.backpressureCount,
        readySlotCount: value.readySlotCount,
        inFlightSlotCount: value.inFlightSlotCount,
        isBound: value.flags & 1 != 0,
        isAdmitting: value.flags & 2 != 0,
        isFaulted: isFaulted,
        failure: failure,
        failureGeneration: value.failureGeneration,
        lastFailedFrameGeneration: value.lastFailedFrameGeneration,
        drawableUnavailableCount: value.drawableUnavailableCount,
        commandFailureCount: value.commandFailureCount,
        gpuTimingSampleCount: value.gpuTimingSampleCount,
        gpuTotalTimeNanoseconds: value.gpuTotalTimeNanoseconds,
        gpuMaximumTimeNanoseconds: value.gpuMaximumTimeNanoseconds,
        acceptedAtlasUploadCount: value.acceptedAtlasUploadCount,
        acceptedAtlasUploadBytes: value.acceptedAtlasUploadBytes,
      );
    } finally {
      arena.releaseAll();
    }
  }

  Uint8List renderRgba(TerminalMetalFrame frame) {
    final int handle = _liveHandle();
    _validateFrameDomain(frame);
    final Arena arena = Arena();
    try {
      final Pointer<Uint8> bytes = arena<Uint8>(frame.byteLength);
      bytes.asTypedList(frame.byteLength).setAll(0, frame._bytes);
      final Pointer<Uint32> required = arena<Uint32>();
      final int queryStatus = _metalRendererRenderRgba(
        handle,
        bytes,
        frame.byteLength,
        nullptr,
        0,
        required,
      );
      final int expectedBytes = frame.viewportWidth * frame.viewportHeight * 4;
      if (queryStatus != 7 || required.value != expectedBytes) {
        throw TerminalMetalRendererException(
          operation: 'Metal RGBA size query',
          status: queryStatus,
        );
      }
      final Pointer<Uint8> output = arena<Uint8>(required.value);
      _checkMetalStatus(
        _metalRendererRenderRgba(
          handle,
          bytes,
          frame.byteLength,
          output,
          required.value,
          required,
        ),
        'Metal RGBA render',
      );
      if (required.value != expectedBytes) {
        throw const FormatException('Metal RGBA output size changed');
      }
      return Uint8List.fromList(output.asTypedList(required.value));
    } finally {
      arena.releaseAll();
    }
  }

  void dispose() {
    final int handle = _handle;
    if (handle == 0) return;
    _handle = 0;
    _metalRendererFinalizer.detach(this);
    _checkMetalStatus(_metalRendererRelease(handle), 'Metal renderer release');
  }

  int _liveHandle() {
    if (_handle == 0) throw StateError('TerminalMetalRenderer is disposed');
    return _handle;
  }

  int _pageLimit(TerminalMetalAtlasFormat format) =>
      format == TerminalMetalAtlasFormat.alpha8
      ? config.maximumAlphaPages
      : config.maximumColorPages;

  void _validateFrameDomain(TerminalMetalFrame frame) {
    if (frame.rendererGeneration != generation ||
        frame.viewportWidth > config.maximumViewportWidth ||
        frame.viewportHeight > config.maximumViewportHeight ||
        frame.instanceCount > config.maximumInstances) {
      throw ArgumentError('Metal frame is outside this renderer domain');
    }
  }
}

final class _MetalRendererConfigV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint32()
  external int maximumViewportWidth;
  @Uint32()
  external int maximumViewportHeight;
  @Uint32()
  external int maximumInstances;
  @Uint32()
  external int atlasWidth;
  @Uint32()
  external int atlasHeight;
  @Uint32()
  external int maximumAlphaPages;
  @Uint32()
  external int maximumColorPages;
  @Array(3)
  external Array<Uint32> reserved;
}

final class _MetalRendererSummaryV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint64()
  external int handle;
  @Uint64()
  external int generation;
  @Uint32()
  external int maximumViewportWidth;
  @Uint32()
  external int maximumViewportHeight;
  @Uint32()
  external int maximumInstances;
  @Uint32()
  external int atlasWidth;
  @Uint32()
  external int atlasHeight;
  @Uint32()
  external int maximumAlphaPages;
  @Uint32()
  external int maximumColorPages;
  @Uint32()
  external int failureKind;
  @Array(2)
  external Array<Uint32> reserved;
}

final class _MetalAtlasUploadV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint64()
  external int rendererGeneration;
  @Uint64()
  external int atlasGeneration;
  @Uint64()
  external int pageGeneration;
  @Uint32()
  external int format;
  @Uint32()
  external int pageIndex;
  @Uint32()
  external int x;
  @Uint32()
  external int y;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int rowStride;
  @Uint32()
  external int byteLength;
  @Array(4)
  external Array<Uint32> reserved;
}

final class _MetalAtlasResetV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint64()
  external int rendererGeneration;
  @Uint64()
  external int atlasGeneration;
  @Array(2)
  external Array<Uint32> reserved;
}

final class _MetalSubmissionV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint64()
  external int rendererGeneration;
  @Uint64()
  external int submissionToken;
  @Uint64()
  external int frameGeneration;
  @Array(2)
  external Array<Uint32> reserved;
}

final class _MetalRendererStateV1 extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int version;
  @Uint64()
  external int rendererGeneration;
  @Uint64()
  external int lastAcceptedFrameGeneration;
  @Uint64()
  external int lastSubmissionToken;
  @Uint64()
  external int retiredThroughToken;
  @Uint64()
  external int lastPresentedFrameGeneration;
  @Uint64()
  external int acceptedSubmissionCount;
  @Uint64()
  external int completedSubmissionCount;
  @Uint64()
  external int staleReadyDropCount;
  @Uint64()
  external int backpressureCount;
  @Uint32()
  external int readySlotCount;
  @Uint32()
  external int inFlightSlotCount;
  @Uint32()
  external int flags;
  @Uint32()
  external int failureKind;
  @Uint64()
  external int failureGeneration;
  @Uint64()
  external int lastFailedFrameGeneration;
  @Uint64()
  external int drawableUnavailableCount;
  @Uint64()
  external int commandFailureCount;
  @Uint64()
  external int gpuTimingSampleCount;
  @Uint64()
  external int gpuTotalTimeNanoseconds;
  @Uint64()
  external int gpuMaximumTimeNanoseconds;
  @Uint64()
  external int acceptedAtlasUploadCount;
  @Uint64()
  external int acceptedAtlasUploadBytes;
  @Array(2)
  external Array<Uint32> reserved;
}

void _checkMetalLayout() {
  if (sizeOf<_MetalRendererConfigV1>() != 48 ||
      sizeOf<_MetalRendererSummaryV1>() != 64 ||
      sizeOf<_MetalAtlasResetV1>() != 32 ||
      sizeOf<_MetalAtlasUploadV1>() != 80 ||
      sizeOf<_MetalSubmissionV1>() != 40 ||
      sizeOf<_MetalRendererStateV1>() != 176) {
    throw StateError('unexpected Dart FFI Metal ABI layout');
  }
}

bool _validMetalMetrics(_MetalRendererStateV1 value) {
  const int maximum = 0x7fffffffffffffff;
  if (value.gpuTimingSampleCount < 0 ||
      value.gpuTotalTimeNanoseconds < 0 ||
      value.gpuMaximumTimeNanoseconds < 0 ||
      value.acceptedAtlasUploadCount < 0 ||
      value.acceptedAtlasUploadBytes < 0 ||
      value.gpuTimingSampleCount > maximum ||
      value.gpuTotalTimeNanoseconds > maximum ||
      value.gpuMaximumTimeNanoseconds > maximum ||
      value.acceptedAtlasUploadCount > maximum ||
      value.acceptedAtlasUploadBytes > maximum ||
      value.gpuTimingSampleCount > value.completedSubmissionCount) {
    return false;
  }
  if (value.gpuTimingSampleCount == 0) {
    if (value.gpuTotalTimeNanoseconds != 0 ||
        value.gpuMaximumTimeNanoseconds != 0) {
      return false;
    }
  } else if (value.gpuTotalTimeNanoseconds == 0 ||
      value.gpuMaximumTimeNanoseconds == 0 ||
      value.gpuMaximumTimeNanoseconds > value.gpuTotalTimeNanoseconds) {
    return false;
  }
  return (value.acceptedAtlasUploadCount == 0) ==
          (value.acceptedAtlasUploadBytes == 0) &&
      value.acceptedAtlasUploadBytes >= value.acceptedAtlasUploadCount;
}

TerminalMetalFailureKind _metalFailureFromNative(int value) {
  for (final TerminalMetalFailureKind failure
      in TerminalMetalFailureKind.values) {
    if (failure.nativeValue == value) return failure;
  }
  throw const FormatException('unknown native Metal failure kind');
}

bool _reservedZero(Array<Uint32> values, int length) {
  for (int index = 0; index < length; index++) {
    if (values[index] != 0) return false;
  }
  return true;
}

void _requireUint32(int value, String name) {
  if (value < 0 || value > 0xffffffff) {
    throw RangeError.range(value, 0, 0xffffffff, name);
  }
}

void _requireInt32(int value, String name) {
  if (value < -0x80000000 || value > 0x7fffffff) {
    throw RangeError.range(value, -0x80000000, 0x7fffffff, name);
  }
}

void _requirePositiveInt64(int value, String name) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    throw RangeError.range(value, 1, 0x7fffffffffffffff, name);
  }
}

void _checkMetalStatus(int status, String operation) {
  if (status != 0) {
    throw TerminalMetalRendererException(operation: operation, status: status);
  }
}

@Native<
  Int32 Function(
    Pointer<_MetalRendererConfigV1>,
    Pointer<_MetalRendererSummaryV1>,
  )
>(symbol: 'dtr_metal_renderer_create', assetId: _metalAssetId)
external int _metalRendererCreate(
  Pointer<_MetalRendererConfigV1> config,
  Pointer<_MetalRendererSummaryV1> output,
);

@Native<Int32 Function(Uint64)>(
  symbol: 'dtr_metal_renderer_release',
  assetId: _metalAssetId,
)
external int _metalRendererRelease(int handle);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'dtr_metal_renderer_release_finalizer',
  assetId: _metalAssetId,
)
external void _metalRendererReleaseFinalizer(Pointer<Void> handle);

final NativeFinalizer _metalRendererFinalizer = NativeFinalizer(
  Native.addressOf(_metalRendererReleaseFinalizer),
);

@Native<Int32 Function(Uint64, Pointer<_MetalAtlasResetV1>)>(
  symbol: 'dtr_metal_renderer_reset_atlas',
  assetId: _metalAssetId,
)
external int _metalRendererResetAtlas(
  int handle,
  Pointer<_MetalAtlasResetV1> reset,
);

@Native<Int32 Function(Uint64, Pointer<_MetalAtlasUploadV1>, Pointer<Uint8>)>(
  symbol: 'dtr_metal_renderer_upload_atlas',
  assetId: _metalAssetId,
)
external int _metalRendererUpload(
  int handle,
  Pointer<_MetalAtlasUploadV1> upload,
  Pointer<Uint8> pixels,
);

@Native<
  Int32 Function(Uint64, Pointer<Uint8>, Uint32, Pointer<_MetalSubmissionV1>)
>(symbol: 'dtr_metal_renderer_submit', assetId: _metalAssetId)
external int _metalRendererSubmit(
  int handle,
  Pointer<Uint8> frame,
  int frameLength,
  Pointer<_MetalSubmissionV1> output,
);

@Native<Int32 Function(Uint64, Pointer<_MetalRendererStateV1>)>(
  symbol: 'dtr_metal_renderer_state',
  assetId: _metalAssetId,
)
external int _metalRendererState(
  int handle,
  Pointer<_MetalRendererStateV1> output,
);

@Native<Int32 Function(Uint64)>(
  symbol: 'dtr_metal_renderer_request_draw',
  assetId: _metalAssetId,
)
external int _metalRendererRequestDraw(int handle);

@Native<
  Int32 Function(
    Uint64,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
  )
>(symbol: 'dtr_metal_renderer_render_rgba', assetId: _metalAssetId)
external int _metalRendererRenderRgba(
  int handle,
  Pointer<Uint8> frame,
  int frameLength,
  Pointer<Uint8> output,
  int outputCapacity,
  Pointer<Uint32> outputRequired,
);
