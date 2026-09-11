import 'dart:collection';
import 'dart:typed_data';

import 'terminal_kitty_graphics.dart';

/// Fixed product ceilings for decoded Kitty image bytes retained per screen.
abstract final class TerminalKittyImageStoreLimits {
  static const int maximumImages = 64;
  static const int maximumPlacements = 256;
  static const int maximumRetainedBytes = 16 * 1024 * 1024;
  static const int maximumImageBytes = 1024 * 1024;
  static const int maximumPixels = maximumImageBytes ~/ 4;
  static const int maximumDimension = 4096;
  static const int maximumFramesPerImage = 64;
  static const int maximumAnimationFrames = 256;
}

enum TerminalKittyImageAnimationState { stopped, loading, running }

final class _TerminalKittyImageFrame {
  _TerminalKittyImageFrame({
    required Uint8List rgba,
    required this.gapMilliseconds,
    required this.transient,
  }) : rgba = Uint8List.fromList(rgba);

  final Uint8List rgba;
  int gapMilliseconds;
  bool transient;
}

/// One generation-owned canonical RGBA8 image owned by a terminal screen.
final class TerminalKittyImage {
  TerminalKittyImage._({
    required this.id,
    required this.number,
    required this.width,
    required this.height,
    required this.resourceGeneration,
    required int contentGeneration,
    required this.transient,
    required Uint8List rgba,
  }) : _contentGeneration = contentGeneration,
       _rgba = Uint8List.fromList(rgba);

  final int id;
  final int number;
  final int width;
  final int height;
  final int resourceGeneration;
  bool transient;
  Uint8List _rgba;
  final List<_TerminalKittyImageFrame> _frames = <_TerminalKittyImageFrame>[];
  int _contentGeneration;
  int _rootGapMilliseconds = 0;
  int _currentFrameIndex = 0;
  TerminalKittyImageAnimationState _animationState =
      TerminalKittyImageAnimationState.stopped;
  int _maximumLoops = 0;
  int _completedLoops = 0;
  int? _frameShownAtMilliseconds;

  int get byteLength => _rgba.length;
  int get animationByteLength => _frames.fold(
    0,
    (int total, _TerminalKittyImageFrame frame) => total + frame.rgba.length,
  );
  int get storageByteLength => byteLength + animationByteLength;
  int get frameCount => _frames.length + 1;
  int get currentFrameNumber => _currentFrameIndex + 1;
  int get contentGeneration => _contentGeneration;
  TerminalKittyImageAnimationState get animationState => _animationState;
  int get maximumLoops => _maximumLoops;
  int get completedLoops => _completedLoops;
  int? get frameShownAtMilliseconds => _frameShownAtMilliseconds;

  Uint8List copyRgba() => Uint8List.fromList(_rgba);

  Uint8List copyFrameRgba(int frameNumber) =>
      Uint8List.fromList(_frameRgba(frameNumber));

  Uint8List copyCurrentRgba() =>
      Uint8List.fromList(_frameRgba(currentFrameNumber));

  int frameGapMilliseconds(int frameNumber) => frameNumber == 1
      ? _rootGapMilliseconds
      : _extraFrame(frameNumber)?.gapMilliseconds ??
            (throw RangeError.range(frameNumber, 1, frameCount, 'frameNumber'));

  bool frameIsTransient(int frameNumber) => frameNumber == 1
      ? transient
      : _extraFrame(frameNumber)?.transient ??
            (throw RangeError.range(frameNumber, 1, frameCount, 'frameNumber'));

  _TerminalKittyImageFrame? _extraFrame(int frameNumber) {
    final int index = frameNumber - 2;
    return index < 0 || index >= _frames.length ? null : _frames[index];
  }

  Uint8List _frameRgba(int frameNumber) {
    if (frameNumber == 1) return _rgba;
    return _extraFrame(frameNumber)?.rgba ??
        (throw RangeError.range(frameNumber, 1, frameCount, 'frameNumber'));
  }
}

/// One source rectangle after intersection with its immutable image.
final class TerminalKittyImageSourceRect {
  const TerminalKittyImageSourceRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

/// Pixel and grid geometry resolved for the current logical cell metrics.
final class TerminalKittyImagePlacementGeometry {
  const TerminalKittyImagePlacementGeometry({
    required this.source,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.columns,
    required this.rows,
  });

  final TerminalKittyImageSourceRect source;
  final int cellOffsetX;
  final int cellOffsetY;
  final int pixelWidth;
  final int pixelHeight;
  final int columns;
  final int rows;
}

/// Immutable logical placement tied to one decoded image generation.
final class TerminalKittyImagePlacement {
  const TerminalKittyImagePlacement._({
    required this.placementGeneration,
    required this.imageId,
    required this.imageResourceGeneration,
    required this.placementId,
    required this.logicalLineId,
    required this.logicalLineEpoch,
    required this.logicalCellOffset,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.requestedColumns,
    required this.requestedRows,
    required this.z,
    required this.fixedPixelWidth,
    required this.fixedPixelHeight,
  });

  final int placementGeneration;
  final int imageId;
  final int imageResourceGeneration;
  final int placementId;
  final int logicalLineId;
  final int logicalLineEpoch;
  final int logicalCellOffset;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int cellOffsetX;
  final int cellOffsetY;
  final int requestedColumns;
  final int requestedRows;
  final int z;
  final int? fixedPixelWidth;
  final int? fixedPixelHeight;

  TerminalKittyImageSourceRect sourceRect(TerminalKittyImage image) {
    _requireImageGeneration(image);
    final int x = sourceX.clamp(0, image.width);
    final int y = sourceY.clamp(0, image.height);
    return TerminalKittyImageSourceRect(
      x: x,
      y: y,
      width: (sourceWidth == 0 ? image.width : sourceWidth).clamp(
        0,
        image.width - x,
      ),
      height: (sourceHeight == 0 ? image.height : sourceHeight).clamp(
        0,
        image.height - y,
      ),
    );
  }

  TerminalKittyImagePlacementGeometry geometry({
    required TerminalKittyImage image,
    required int cellWidth,
    required int cellHeight,
  }) {
    _requireImageGeneration(image);
    if (cellWidth < 0 || cellHeight < 0) {
      throw ArgumentError('logical cell dimensions must not be negative');
    }
    final TerminalKittyImageSourceRect source = sourceRect(image);
    final int offsetX = cellWidth == 0
        ? 0
        : cellOffsetX.clamp(0, cellWidth - 1);
    final int offsetY = cellHeight == 0
        ? 0
        : cellOffsetY.clamp(0, cellHeight - 1);
    late final int naturalPixelWidth;
    late final int naturalPixelHeight;
    if (requestedColumns == 0 && requestedRows == 0) {
      naturalPixelWidth = source.width;
      naturalPixelHeight = source.height;
    } else if (requestedColumns != 0 && requestedRows != 0) {
      naturalPixelWidth =
          (_saturatingProduct(cellWidth, requestedColumns) - offsetX).clamp(
            0,
            0xffffffff,
          );
      naturalPixelHeight =
          (_saturatingProduct(cellHeight, requestedRows) - offsetY).clamp(
            0,
            0xffffffff,
          );
    } else if (requestedColumns != 0) {
      naturalPixelWidth =
          (_saturatingProduct(cellWidth, requestedColumns) - offsetX).clamp(
            0,
            0xffffffff,
          );
      naturalPixelHeight = _scaleDimension(
        naturalPixelWidth,
        source.height,
        source.width,
      );
    } else {
      naturalPixelHeight =
          (_saturatingProduct(cellHeight, requestedRows) - offsetY).clamp(
            0,
            0xffffffff,
          );
      naturalPixelWidth = _scaleDimension(
        naturalPixelHeight,
        source.width,
        source.height,
      );
    }
    final int pixelWidth = fixedPixelWidth ?? naturalPixelWidth;
    final int pixelHeight = fixedPixelHeight ?? naturalPixelHeight;
    final int columns = requestedColumns != 0 && requestedRows != 0
        ? requestedColumns
        : _ceilDivide(pixelWidth + offsetX, cellWidth);
    final int rows = requestedColumns != 0 && requestedRows != 0
        ? requestedRows
        : _ceilDivide(pixelHeight + offsetY, cellHeight);
    return TerminalKittyImagePlacementGeometry(
      source: source,
      cellOffsetX: offsetX,
      cellOffsetY: offsetY,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      columns: columns,
      rows: rows,
    );
  }

  void _requireImageGeneration(TerminalKittyImage image) {
    if (image.id != imageId ||
        image.resourceGeneration != imageResourceGeneration) {
      throw StateError('Kitty placement refers to a stale image generation');
    }
  }

  static int _saturatingProduct(int left, int right) {
    final int product = left * right;
    return product > 0xffffffff ? 0xffffffff : product;
  }

  static int _scaleDimension(int value, int numerator, int denominator) {
    if (denominator == 0) return 0;
    return ((value * numerator + denominator ~/ 2) ~/ denominator).clamp(
      0,
      0xffffffff,
    );
  }

  static int _ceilDivide(int value, int divisor) {
    if (value == 0 || divisor == 0) return 0;
    return (value + divisor - 1) ~/ divisor;
  }
}

final class TerminalKittyImagePlacementPosition {
  const TerminalKittyImagePlacementPosition({
    required this.row,
    required this.column,
  });

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is TerminalKittyImagePlacementPosition &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

typedef TerminalKittyImagePlacementPositionResolver =
    TerminalKittyImagePlacementPosition? Function(
      TerminalKittyImagePlacement placement,
    );

enum TerminalKittyImagePlacementDisposition {
  stored,
  imageMissing,
  resourceLimit,
}

final class TerminalKittyImagePlacementResult {
  const TerminalKittyImagePlacementResult(
    this.disposition, {
    this.image,
    this.placement,
  });

  final TerminalKittyImagePlacementDisposition disposition;
  final TerminalKittyImage? image;
  final TerminalKittyImagePlacement? placement;
}

final class TerminalKittyImageDeleteResult {
  const TerminalKittyImageDeleteResult({
    required this.deletedPlacements,
    required this.deletedImages,
  });

  final int deletedPlacements;
  final int deletedImages;
  bool get mutated => deletedPlacements != 0 || deletedImages != 0;
}

enum TerminalKittyImageStoreDisposition { stored, resourceLimit }

final class TerminalKittyImageStoreResult {
  const TerminalKittyImageStoreResult(this.disposition, {this.image});

  final TerminalKittyImageStoreDisposition disposition;
  final TerminalKittyImage? image;
}

enum TerminalKittyAnimationMutationDisposition {
  stored,
  imageMissing,
  baseFrameMissing,
  sourceFrameMissing,
  destinationFrameMissing,
  invalidRectangle,
  resourceLimit,
}

final class TerminalKittyAnimationMutationResult {
  const TerminalKittyAnimationMutationResult(
    this.disposition, {
    this.image,
    this.frameNumber = 0,
  });

  final TerminalKittyAnimationMutationDisposition disposition;
  final TerminalKittyImage? image;
  final int frameNumber;
}

enum TerminalKittyAnimationControlDisposition { applied, imageMissing }

final class TerminalKittyAnimationControlResult {
  const TerminalKittyAnimationControlResult(this.disposition, {this.image});

  final TerminalKittyAnimationControlDisposition disposition;
  final TerminalKittyImage? image;
}

/// Per-screen, reject-on-cap storage for static Kitty image data.
final class TerminalKittyImageStore {
  TerminalKittyImageStore({
    this.maximumImages = TerminalKittyImageStoreLimits.maximumImages,
    this.maximumPlacements = TerminalKittyImageStoreLimits.maximumPlacements,
    this.maximumAnimationFrames =
        TerminalKittyImageStoreLimits.maximumAnimationFrames,
    this.maximumRetainedBytes =
        TerminalKittyImageStoreLimits.maximumRetainedBytes,
  }) {
    if (maximumImages <= 0 ||
        maximumImages > TerminalKittyImageStoreLimits.maximumImages ||
        maximumPlacements <= 0 ||
        maximumPlacements > TerminalKittyImageStoreLimits.maximumPlacements ||
        maximumAnimationFrames <= 0 ||
        maximumAnimationFrames >
            TerminalKittyImageStoreLimits.maximumAnimationFrames ||
        maximumRetainedBytes <= 0 ||
        maximumRetainedBytes >
            TerminalKittyImageStoreLimits.maximumRetainedBytes) {
      throw ArgumentError('Kitty image store bounds exceed product limits');
    }
  }

  final int maximumImages;
  final int maximumPlacements;
  final int maximumAnimationFrames;
  final int maximumRetainedBytes;
  final LinkedHashMap<int, TerminalKittyImage> _byId =
      LinkedHashMap<int, TerminalKittyImage>();
  final LinkedHashMap<int, TerminalKittyImagePlacement> _placements =
      LinkedHashMap<int, TerminalKittyImagePlacement>();
  var _retainedBytes = 0;
  var _animationFrameCount = 0;
  var _nextImageId = 1;
  var _nextResourceGeneration = 1;
  var _nextPlacementGeneration = 1;
  var _stateGeneration = 1;

  int get length => _byId.length;
  int get retainedBytes => _retainedBytes;
  int get placementCount => _placements.length;
  int get animationFrameCount => _animationFrameCount;
  int get stateGeneration => _stateGeneration;
  bool get isEmpty => _byId.isEmpty;

  TerminalKittyImage? imageById(int id) => _byId[id];

  TerminalKittyImage? newestImageByNumber(int number) {
    if (number <= 0 || number > 0xffffffff) return null;
    for (final TerminalKittyImage image in _byId.values.toList().reversed) {
      if (image.number == number) return image;
    }
    return null;
  }

  List<TerminalKittyImage> snapshot() =>
      List<TerminalKittyImage>.unmodifiable(_byId.values);

  List<TerminalKittyImagePlacement> placementSnapshot() =>
      List<TerminalKittyImagePlacement>.unmodifiable(_placements.values);

  TerminalKittyImageStoreResult store({
    required int imageId,
    required int imageNumber,
    required int width,
    required int height,
    required bool transient,
    required Uint8List rgba,
  }) {
    _validateIdentity(imageId, imageNumber);
    _validateImage(width, height, rgba);
    final bool generatedId = imageId == 0;
    final int resolvedId = generatedId ? _allocateImageId() : imageId;
    final TerminalKittyImage? replaced = _byId[resolvedId];
    final int projectedCount = _byId.length + (replaced == null ? 1 : 0);
    final int projectedBytes =
        _retainedBytes - (replaced?.storageByteLength ?? 0) + rgba.length;
    if (projectedCount > maximumImages ||
        projectedBytes > maximumRetainedBytes) {
      return const TerminalKittyImageStoreResult(
        TerminalKittyImageStoreDisposition.resourceLimit,
      );
    }
    final int generation = _takeResourceGeneration();
    final TerminalKittyImage image = TerminalKittyImage._(
      id: resolvedId,
      number: generatedId ? imageNumber : 0,
      width: width,
      height: height,
      resourceGeneration: generation,
      contentGeneration: generation,
      transient: transient,
      rgba: rgba,
    );
    if (replaced != null) {
      _animationFrameCount -= replaced._frames.length;
      _removePlacementsWhere(
        (TerminalKittyImagePlacement placement) =>
            placement.imageId == resolvedId,
        bumpGeneration: false,
      );
      _byId.remove(resolvedId);
    }
    _byId[resolvedId] = image;
    _retainedBytes = projectedBytes;
    _stateGeneration++;
    return TerminalKittyImageStoreResult(
      TerminalKittyImageStoreDisposition.stored,
      image: image,
    );
  }

  TerminalKittyAnimationMutationResult storeAnimationFrame({
    required int imageId,
    required int imageNumber,
    required int expectedResourceGeneration,
    required int width,
    required int height,
    required int x,
    required int y,
    required int baseFrame,
    required int editFrame,
    required int gapMilliseconds,
    required bool overwrite,
    required int backgroundRgba,
    required bool transient,
    required Uint8List rgba,
  }) {
    _validateIdentity(imageId, imageNumber);
    _validateImage(width, height, rgba);
    final TerminalKittyImage? image = imageId != 0
        ? imageById(imageId)
        : newestImageByNumber(imageNumber);
    if (image == null ||
        image.resourceGeneration != expectedResourceGeneration) {
      return const TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.imageMissing,
      );
    }
    if (width > image.width ||
        height > image.height ||
        x < 0 ||
        x > 0xffffffff ||
        y < 0 ||
        y > 0xffffffff ||
        baseFrame < 0 ||
        baseFrame > 0xffffffff ||
        editFrame < 0 ||
        editFrame > 0xffffffff ||
        gapMilliseconds < -0x80000000 ||
        gapMilliseconds > 0x7fffffff ||
        backgroundRgba < 0 ||
        backgroundRgba > 0xffffffff) {
      return TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.invalidRectangle,
        image: image,
        frameNumber: editFrame,
      );
    }

    final int count = image.frameCount;
    final bool create = editFrame == 0 || editFrame > count;
    final int frameNumber = create ? count + 1 : editFrame;
    if (create) {
      if (baseFrame != 0 && baseFrame > count) {
        return TerminalKittyAnimationMutationResult(
          TerminalKittyAnimationMutationDisposition.baseFrameMissing,
          image: image,
          frameNumber: frameNumber,
        );
      }
      if (count >= TerminalKittyImageStoreLimits.maximumFramesPerImage ||
          _animationFrameCount >= maximumAnimationFrames ||
          _retainedBytes + image.byteLength > maximumRetainedBytes) {
        return TerminalKittyAnimationMutationResult(
          TerminalKittyAnimationMutationDisposition.resourceLimit,
          image: image,
          frameNumber: frameNumber,
        );
      }
      final Uint8List canvas = baseFrame == 0
          ? _filledRgba(image.width, image.height, backgroundRgba)
          : image.copyFrameRgba(baseFrame);
      _composeRect(
        destination: canvas,
        destinationWidth: image.width,
        destinationHeight: image.height,
        source: rgba,
        sourceWidth: width,
        sourceHeight: height,
        destinationX: x,
        destinationY: y,
        overwrite: overwrite,
      );
      image._frames.add(
        _TerminalKittyImageFrame(
          rgba: canvas,
          gapMilliseconds: gapMilliseconds > 0
              ? gapMilliseconds
              : gapMilliseconds < 0
              ? 0
              : 40,
          transient:
              transient ||
              (baseFrame != 0 && image.frameIsTransient(baseFrame)),
        ),
      );
      _animationFrameCount++;
      _retainedBytes += image.byteLength;
      _stateGeneration++;
      return TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.stored,
        image: image,
        frameNumber: frameNumber,
      );
    }

    final Uint8List destination = image._frameRgba(frameNumber);
    _composeRect(
      destination: destination,
      destinationWidth: image.width,
      destinationHeight: image.height,
      source: rgba,
      sourceWidth: width,
      sourceHeight: height,
      destinationX: x,
      destinationY: y,
      overwrite: overwrite,
    );
    if (gapMilliseconds != 0) {
      _setFrameGap(
        image,
        frameNumber,
        gapMilliseconds > 0 ? gapMilliseconds : 0,
      );
    }
    _setFrameTransient(
      image,
      frameNumber,
      image.frameIsTransient(frameNumber) || transient,
    );
    if (frameNumber == image.currentFrameNumber) {
      image._frameShownAtMilliseconds = null;
      _markImageContentChanged(image);
    } else {
      _stateGeneration++;
    }
    return TerminalKittyAnimationMutationResult(
      TerminalKittyAnimationMutationDisposition.stored,
      image: image,
      frameNumber: frameNumber,
    );
  }

  TerminalKittyAnimationControlResult controlAnimation({
    required int imageId,
    required int imageNumber,
    required TerminalKittyGraphicsAnimationControl control,
  }) {
    _validateIdentity(imageId, imageNumber);
    final TerminalKittyImage? image = imageId != 0
        ? imageById(imageId)
        : newestImageByNumber(imageNumber);
    if (image == null) {
      return const TerminalKittyAnimationControlResult(
        TerminalKittyAnimationControlDisposition.imageMissing,
      );
    }
    var mutated = false;
    var contentChanged = false;
    if (control.frameNumber > 0 &&
        control.frameNumber <= image.frameCount &&
        control.gapMilliseconds != 0) {
      _setFrameGap(
        image,
        control.frameNumber,
        control.gapMilliseconds > 0 ? control.gapMilliseconds : 0,
      );
      mutated = true;
    }
    if (control.currentFrame > 0 &&
        control.currentFrame <= image.frameCount &&
        control.currentFrame != image.currentFrameNumber) {
      image._currentFrameIndex = control.currentFrame - 1;
      image._frameShownAtMilliseconds = null;
      mutated = true;
      contentChanged = true;
    }
    final TerminalKittyImageAnimationState? nextState = switch (control.state) {
      TerminalKittyGraphicsAnimationState.unchanged => null,
      TerminalKittyGraphicsAnimationState.stopped =>
        TerminalKittyImageAnimationState.stopped,
      TerminalKittyGraphicsAnimationState.loading =>
        TerminalKittyImageAnimationState.loading,
      TerminalKittyGraphicsAnimationState.running =>
        TerminalKittyImageAnimationState.running,
    };
    if (nextState != null) {
      final TerminalKittyImageAnimationState oldState = image._animationState;
      image._animationState = nextState;
      if (oldState == TerminalKittyImageAnimationState.stopped &&
          nextState != TerminalKittyImageAnimationState.stopped) {
        image._frameShownAtMilliseconds = null;
      }
      image._completedLoops = 0;
      mutated = true;
    }
    if (control.loops != 0) {
      image._maximumLoops = control.loops - 1;
      mutated = true;
    }
    if (contentChanged) {
      _markImageContentChanged(image);
    } else if (mutated) {
      _stateGeneration++;
    }
    return TerminalKittyAnimationControlResult(
      TerminalKittyAnimationControlDisposition.applied,
      image: image,
    );
  }

  TerminalKittyAnimationMutationResult composeAnimationFrames({
    required int imageId,
    required int imageNumber,
    required TerminalKittyGraphicsFrameComposition composition,
  }) {
    _validateIdentity(imageId, imageNumber);
    final TerminalKittyImage? image = imageId != 0
        ? imageById(imageId)
        : newestImageByNumber(imageNumber);
    if (image == null) {
      return const TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.imageMissing,
      );
    }
    if (composition.sourceFrame <= 0 ||
        composition.sourceFrame > image.frameCount) {
      return TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.sourceFrameMissing,
        image: image,
        frameNumber: composition.sourceFrame,
      );
    }
    if (composition.destinationFrame <= 0 ||
        composition.destinationFrame > image.frameCount) {
      return TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.destinationFrameMissing,
        image: image,
        frameNumber: composition.destinationFrame,
      );
    }
    final int width = composition.width == 0 ? image.width : composition.width;
    final int height = composition.height == 0
        ? image.height
        : composition.height;
    if (width <= 0 ||
        height <= 0 ||
        composition.destinationX + width > image.width ||
        composition.destinationY + height > image.height ||
        composition.sourceX + width > image.width ||
        composition.sourceY + height > image.height ||
        (composition.sourceFrame == composition.destinationFrame &&
            _rectanglesOverlap(
              composition.sourceX,
              composition.sourceY,
              composition.destinationX,
              composition.destinationY,
              width,
              height,
            ))) {
      return TerminalKittyAnimationMutationResult(
        TerminalKittyAnimationMutationDisposition.invalidRectangle,
        image: image,
      );
    }
    final Uint8List source = image._frameRgba(composition.sourceFrame);
    final Uint8List destination = image._frameRgba(
      composition.destinationFrame,
    );
    _composeCanvasRect(
      destination: destination,
      source: source,
      canvasWidth: image.width,
      sourceX: composition.sourceX,
      sourceY: composition.sourceY,
      destinationX: composition.destinationX,
      destinationY: composition.destinationY,
      width: width,
      height: height,
      overwrite: composition.overwrite,
    );
    _setFrameTransient(
      image,
      composition.destinationFrame,
      image.frameIsTransient(composition.destinationFrame) ||
          image.frameIsTransient(composition.sourceFrame),
    );
    if (composition.destinationFrame == image.currentFrameNumber) {
      _markImageContentChanged(image);
    } else {
      _stateGeneration++;
    }
    return TerminalKittyAnimationMutationResult(
      TerminalKittyAnimationMutationDisposition.stored,
      image: image,
      frameNumber: composition.destinationFrame,
    );
  }

  TerminalKittyImageDeleteResult deleteAnimationFrame(
    TerminalKittyGraphicsDeletion deletion,
  ) {
    final TerminalKittyImage? image = deletion.imageId != 0
        ? imageById(deletion.imageId)
        : newestImageByNumber(deletion.imageNumber);
    if (image == null) {
      return const TerminalKittyImageDeleteResult(
        deletedPlacements: 0,
        deletedImages: 0,
      );
    }
    if (image.frameCount == 1) {
      if (deletion.selector ==
          TerminalKittyGraphicsDeleteSelector.animationFrames) {
        return const TerminalKittyImageDeleteResult(
          deletedPlacements: 0,
          deletedImages: 0,
        );
      }
      final int deletedPlacements = _removePlacementsWhere(
        (TerminalKittyImagePlacement placement) =>
            placement.imageId == image.id,
        bumpGeneration: false,
      );
      _removeImage(image.id);
      _stateGeneration++;
      return TerminalKittyImageDeleteResult(
        deletedPlacements: deletedPlacements,
        deletedImages: 1,
      );
    }
    final int frameNumber = deletion.frameNumber.clamp(1, image.frameCount);
    final int removedIndex = frameNumber - 1;
    var contentChanged = false;
    if (frameNumber == 1) {
      final _TerminalKittyImageFrame promoted = image._frames.removeAt(0);
      _retainedBytes -= image._rgba.length;
      image._rgba = promoted.rgba;
      image._rootGapMilliseconds = promoted.gapMilliseconds;
      image.transient = promoted.transient;
      _animationFrameCount--;
    } else {
      final _TerminalKittyImageFrame removed = image._frames.removeAt(
        frameNumber - 2,
      );
      _retainedBytes -= removed.rgba.length;
      _animationFrameCount--;
    }
    final int lastIndex = image.frameCount - 1;
    if (image._currentFrameIndex > lastIndex) {
      image._currentFrameIndex = lastIndex;
      contentChanged = true;
    } else if (image._currentFrameIndex == removedIndex) {
      contentChanged = true;
    } else if (removedIndex < image._currentFrameIndex) {
      image._currentFrameIndex--;
    }
    if (contentChanged) {
      image._frameShownAtMilliseconds = null;
      _markImageContentChanged(image);
    } else {
      _stateGeneration++;
    }
    return const TerminalKittyImageDeleteResult(
      deletedPlacements: 0,
      deletedImages: 0,
    );
  }

  TerminalKittyImagePlacementResult place({
    required int imageId,
    required int imageNumber,
    required int placementId,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int logicalCellOffset,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int cellOffsetX,
    required int cellOffsetY,
    required int columns,
    required int rows,
    required int z,
  }) {
    _validateIdentity(imageId, imageNumber);
    _validatePlacement(
      placementId: placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: sourceX,
      sourceY: sourceY,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      columns: columns,
      rows: rows,
      z: z,
    );
    final TerminalKittyImage? image = imageId != 0
        ? imageById(imageId)
        : newestImageByNumber(imageNumber);
    if (image == null) {
      return const TerminalKittyImagePlacementResult(
        TerminalKittyImagePlacementDisposition.imageMissing,
      );
    }
    final TerminalKittyImagePlacement? replaced = placementId == 0
        ? null
        : _findExplicitPlacement(image.id, placementId);
    if (replaced == null && _placements.length >= maximumPlacements) {
      return TerminalKittyImagePlacementResult(
        TerminalKittyImagePlacementDisposition.resourceLimit,
        image: image,
      );
    }
    if (replaced != null) {
      _placements.remove(replaced.placementGeneration);
    }
    final int placementGeneration = _takePlacementGeneration();
    final TerminalKittyImagePlacement placement = TerminalKittyImagePlacement._(
      placementGeneration: placementGeneration,
      imageId: image.id,
      imageResourceGeneration: image.resourceGeneration,
      placementId: placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: sourceX,
      sourceY: sourceY,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      requestedColumns: columns,
      requestedRows: rows,
      z: z,
      fixedPixelWidth: null,
      fixedPixelHeight: null,
    );
    _placements[placementGeneration] = placement;
    _stateGeneration++;
    return TerminalKittyImagePlacementResult(
      TerminalKittyImagePlacementDisposition.stored,
      image: image,
      placement: placement,
    );
  }

  /// Reanchors one retained placement after a screen scroll and optionally
  /// clips whole destination pixels from its top or bottom edge.
  bool reconcilePlacement({
    required int placementGeneration,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int logicalCellOffset,
    required int cellOffsetX,
    required int cellOffsetY,
    required int cellWidth,
    required int cellHeight,
    int clipTopPixels = 0,
    int clipBottomPixels = 0,
  }) {
    final TerminalKittyImagePlacement? placement =
        _placements[placementGeneration];
    if (placement == null) return false;
    final TerminalKittyImage? image = _byId[placement.imageId];
    if (image == null ||
        image.resourceGeneration != placement.imageResourceGeneration) {
      _placements.remove(placementGeneration);
      _stateGeneration++;
      return true;
    }
    if (cellWidth <= 0 ||
        cellHeight <= 0 ||
        clipTopPixels < 0 ||
        clipBottomPixels < 0) {
      throw ArgumentError('invalid Kitty placement reconciliation geometry');
    }
    final TerminalKittyImagePlacementGeometry geometry = placement.geometry(
      image: image,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
    if (geometry.pixelWidth <= 0 ||
        geometry.pixelHeight <= 0 ||
        geometry.source.width <= 0 ||
        geometry.source.height <= 0 ||
        clipTopPixels + clipBottomPixels >= geometry.pixelHeight) {
      _placements.remove(placementGeneration);
      _stateGeneration++;
      return true;
    }
    final TerminalKittyImageSourceRect source = geometry.source;
    final int retainedPixelHeight =
        geometry.pixelHeight - clipTopPixels - clipBottomPixels;
    final int sourceTop =
        source.y + clipTopPixels * source.height ~/ geometry.pixelHeight;
    final int sourceBottom =
        source.y +
        _ceilDivide(
          (geometry.pixelHeight - clipBottomPixels) * source.height,
          geometry.pixelHeight,
        );
    final int clippedSourceBottom = sourceBottom.clamp(
      sourceTop + 1,
      source.y + source.height,
    );
    _validatePlacement(
      placementId: placement.placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: source.x,
      sourceY: sourceTop,
      sourceWidth: source.width,
      sourceHeight: clippedSourceBottom - sourceTop,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      columns: placement.requestedColumns,
      rows: placement.requestedRows,
      z: placement.z,
    );
    final TerminalKittyImagePlacement next = TerminalKittyImagePlacement._(
      placementGeneration: placement.placementGeneration,
      imageId: placement.imageId,
      imageResourceGeneration: placement.imageResourceGeneration,
      placementId: placement.placementId,
      logicalLineId: logicalLineId,
      logicalLineEpoch: logicalLineEpoch,
      logicalCellOffset: logicalCellOffset,
      sourceX: source.x,
      sourceY: sourceTop,
      sourceWidth: source.width,
      sourceHeight: clippedSourceBottom - sourceTop,
      cellOffsetX: cellOffsetX,
      cellOffsetY: cellOffsetY,
      requestedColumns: placement.requestedColumns,
      requestedRows: placement.requestedRows,
      z: placement.z,
      fixedPixelWidth: geometry.pixelWidth,
      fixedPixelHeight: retainedPixelHeight,
    );
    if (_samePlacementState(placement, next)) return false;
    _placements[placementGeneration] = next;
    _stateGeneration++;
    return true;
  }

  /// Drops placement records whose logical anchors are no longer retained.
  int removeUnresolvedPlacements(
    TerminalKittyImagePlacementPositionResolver resolvePosition,
  ) => _removePlacementsWhere(
    (TerminalKittyImagePlacement placement) =>
        resolvePosition(placement) == null,
  );

  int removePlacementsForImage(int imageId) {
    if (imageId <= 0 || imageId > 0xffffffff) return 0;
    return _removePlacementsWhere(
      (TerminalKittyImagePlacement placement) => placement.imageId == imageId,
    );
  }

  bool removePlacement(int placementGeneration) {
    if (_placements.remove(placementGeneration) == null) return false;
    _stateGeneration++;
    return true;
  }

  TerminalKittyImageDeleteResult removePlacementsWhere({
    required bool Function(TerminalKittyImagePlacement placement) predicate,
    required bool reclaimUnusedData,
  }) {
    final Set<int> imageCandidates = <int>{};
    final int beforePlacements = _placements.length;
    _removePlacementsWhere((TerminalKittyImagePlacement placement) {
      if (!predicate(placement)) return false;
      imageCandidates.add(placement.imageId);
      return true;
    }, bumpGeneration: false);
    final int beforeImages = _byId.length;
    if (reclaimUnusedData) {
      for (final int imageId in imageCandidates) {
        _removeImageIfUnused(imageId);
      }
    }
    final int deletedPlacements = beforePlacements - _placements.length;
    final int deletedImages = beforeImages - _byId.length;
    if (deletedPlacements != 0 || deletedImages != 0) _stateGeneration++;
    return TerminalKittyImageDeleteResult(
      deletedPlacements: deletedPlacements,
      deletedImages: deletedImages,
    );
  }

  TerminalKittyImageDeleteResult delete({
    required TerminalKittyGraphicsDeletion deletion,
    required int cursorRow,
    required int cursorColumn,
    required int screenRows,
    required int screenColumns,
    required int cellWidth,
    required int cellHeight,
    required TerminalKittyImagePlacementPositionResolver resolvePosition,
  }) {
    if (screenRows <= 0 ||
        screenColumns <= 0 ||
        cellWidth < 0 ||
        cellHeight < 0) {
      throw ArgumentError('screen dimensions or cell metrics are invalid');
    }
    final TerminalKittyGraphicsDeleteSelector selector = deletion.selector;
    if (selector == TerminalKittyGraphicsDeleteSelector.animationFrames ||
        selector ==
            TerminalKittyGraphicsDeleteSelector.animationFramesAndData) {
      throw UnsupportedError('animation frame deletion is not supported');
    }
    final bool deleteData = _selectorDeletesData(selector);
    final Set<int> dataCandidates = <int>{};
    final Set<int> directCandidates = <int>{};
    bool Function(TerminalKittyImagePlacement placement) matches;
    switch (selector) {
      case TerminalKittyGraphicsDeleteSelector.imageId:
      case TerminalKittyGraphicsDeleteSelector.imageIdAndData:
        final int id = deletion.imageId;
        if (id <= 0 || !_byId.containsKey(id)) {
          matches = (_) => false;
          break;
        }
        matches = (TerminalKittyImagePlacement placement) =>
            placement.imageId == id &&
            (deletion.placementId == 0 ||
                placement.placementId == deletion.placementId);
        if (deletion.placementId == 0) directCandidates.add(id);
        break;
      case TerminalKittyGraphicsDeleteSelector.newest:
      case TerminalKittyGraphicsDeleteSelector.newestAndData:
        final TerminalKittyImage? image = newestImageByNumber(
          deletion.imageNumber,
        );
        if (image == null) {
          matches = (_) => false;
          break;
        }
        matches = (TerminalKittyImagePlacement placement) =>
            placement.imageId == image.id &&
            (deletion.placementId == 0 ||
                placement.placementId == deletion.placementId);
        if (deletion.placementId == 0) directCandidates.add(image.id);
        break;
      case TerminalKittyGraphicsDeleteSelector.range:
      case TerminalKittyGraphicsDeleteSelector.rangeAndData:
        final int first = deletion.x;
        final int last = deletion.y;
        matches = first > last || last == 0
            ? (_) => false
            : (TerminalKittyImagePlacement placement) =>
                  placement.imageId >= first && placement.imageId <= last;
        if (deleteData && first <= last && last != 0) {
          directCandidates.addAll(
            _byId.keys.where((int id) => id >= first && id <= last),
          );
        }
        break;
      case TerminalKittyGraphicsDeleteSelector.all:
      case TerminalKittyGraphicsDeleteSelector.allAndData:
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              _intersects(
                placement,
                position,
                row: 0,
                column: 0,
                rows: screenRows,
                columns: screenColumns,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.cursor:
      case TerminalKittyGraphicsDeleteSelector.cursorAndData:
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              _containsCell(
                placement,
                position,
                cursorRow,
                cursorColumn,
                cellWidth,
                cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.cell:
      case TerminalKittyGraphicsDeleteSelector.cellAndData:
      case TerminalKittyGraphicsDeleteSelector.cellAndZ:
      case TerminalKittyGraphicsDeleteSelector.cellAndZAndData:
        if (deletion.x == 0 || deletion.y == 0) {
          matches = (_) => false;
          break;
        }
        final int row = deletion.y - 1;
        final int column = deletion.x - 1;
        final bool matchZ =
            selector == TerminalKittyGraphicsDeleteSelector.cellAndZ ||
            selector == TerminalKittyGraphicsDeleteSelector.cellAndZAndData;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              (!matchZ || placement.z == deletion.z) &&
              _containsCell(
                placement,
                position,
                row,
                column,
                cellWidth,
                cellHeight,
              );
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.column:
      case TerminalKittyGraphicsDeleteSelector.columnAndData:
        if (deletion.x == 0) {
          matches = (_) => false;
          break;
        }
        final int column = deletion.x - 1;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              column >= position.column &&
              column <
                  position.column +
                      _placementColumns(placement, cellWidth, cellHeight);
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.row:
      case TerminalKittyGraphicsDeleteSelector.rowAndData:
        if (deletion.y == 0) {
          matches = (_) => false;
          break;
        }
        final int row = deletion.y - 1;
        matches = (TerminalKittyImagePlacement placement) {
          final TerminalKittyImagePlacementPosition? position = resolvePosition(
            placement,
          );
          return position != null &&
              row >= position.row &&
              row <
                  position.row +
                      _placementRows(placement, cellWidth, cellHeight);
        };
        break;
      case TerminalKittyGraphicsDeleteSelector.z:
      case TerminalKittyGraphicsDeleteSelector.zAndData:
        matches = (TerminalKittyImagePlacement placement) =>
            placement.z == deletion.z;
        break;
      case TerminalKittyGraphicsDeleteSelector.animationFrames:
      case TerminalKittyGraphicsDeleteSelector.animationFramesAndData:
        throw StateError('animation selector reached static deletion');
    }
    final int beforePlacements = _placements.length;
    _removePlacementsWhere((TerminalKittyImagePlacement placement) {
      if (!matches(placement)) return false;
      dataCandidates.add(placement.imageId);
      return true;
    }, bumpGeneration: false);
    if (deleteData) dataCandidates.addAll(directCandidates);
    final int beforeImages = _byId.length;
    if (deleteData) {
      for (final int imageId in dataCandidates) {
        _removeImageIfUnused(imageId);
      }
    }
    final int deletedPlacements = beforePlacements - _placements.length;
    final int deletedImages = beforeImages - _byId.length;
    if (deletedPlacements != 0 || deletedImages != 0) _stateGeneration++;
    return TerminalKittyImageDeleteResult(
      deletedPlacements: deletedPlacements,
      deletedImages: deletedImages,
    );
  }

  void clear() {
    if (_byId.isEmpty && _placements.isEmpty) return;
    _byId.clear();
    _placements.clear();
    _retainedBytes = 0;
    _animationFrameCount = 0;
    _stateGeneration++;
  }

  TerminalKittyImagePlacement? _findExplicitPlacement(
    int imageId,
    int placementId,
  ) {
    for (final TerminalKittyImagePlacement placement in _placements.values) {
      if (placement.imageId == imageId &&
          placement.placementId == placementId) {
        return placement;
      }
    }
    return null;
  }

  int _removePlacementsWhere(
    bool Function(TerminalKittyImagePlacement placement) predicate, {
    bool bumpGeneration = true,
  }) {
    final List<int> removed = <int>[];
    for (final MapEntry<int, TerminalKittyImagePlacement> entry
        in _placements.entries) {
      if (predicate(entry.value)) removed.add(entry.key);
    }
    for (final int key in removed) {
      _placements.remove(key);
    }
    if (bumpGeneration && removed.isNotEmpty) _stateGeneration++;
    return removed.length;
  }

  bool _removeImageIfUnused(int imageId) {
    for (final TerminalKittyImagePlacement placement in _placements.values) {
      if (placement.imageId == imageId) return false;
    }
    return _removeImage(imageId);
  }

  bool _removeImage(int imageId) {
    final TerminalKittyImage? removed = _byId.remove(imageId);
    if (removed == null) return false;
    _retainedBytes -= removed.storageByteLength;
    _animationFrameCount -= removed._frames.length;
    return true;
  }

  void _markImageContentChanged(TerminalKittyImage image) {
    image._contentGeneration = _takeResourceGeneration();
    _stateGeneration++;
  }

  static void _setFrameGap(
    TerminalKittyImage image,
    int frameNumber,
    int gapMilliseconds,
  ) {
    if (frameNumber == 1) {
      image._rootGapMilliseconds = gapMilliseconds;
    } else {
      image._extraFrame(frameNumber)!.gapMilliseconds = gapMilliseconds;
    }
  }

  static void _setFrameTransient(
    TerminalKittyImage image,
    int frameNumber,
    bool transient,
  ) {
    if (frameNumber == 1) {
      image.transient = transient;
    } else {
      image._extraFrame(frameNumber)!.transient = transient;
    }
  }

  static Uint8List _filledRgba(int width, int height, int rgba) {
    final Uint8List result = Uint8List(width * height * 4);
    final int red = rgba >> 24 & 0xff;
    final int green = rgba >> 16 & 0xff;
    final int blue = rgba >> 8 & 0xff;
    final int alpha = rgba & 0xff;
    for (var offset = 0; offset < result.length; offset += 4) {
      result[offset] = red;
      result[offset + 1] = green;
      result[offset + 2] = blue;
      result[offset + 3] = alpha;
    }
    return result;
  }

  static void _composeRect({
    required Uint8List destination,
    required int destinationWidth,
    required int destinationHeight,
    required Uint8List source,
    required int sourceWidth,
    required int sourceHeight,
    required int destinationX,
    required int destinationY,
    required bool overwrite,
  }) {
    final int copiedWidth = sourceWidth.clamp(
      0,
      (destinationWidth - destinationX).clamp(0, destinationWidth),
    );
    final int copiedHeight = sourceHeight.clamp(
      0,
      (destinationHeight - destinationY).clamp(0, destinationHeight),
    );
    for (var row = 0; row < copiedHeight; row++) {
      for (var column = 0; column < copiedWidth; column++) {
        final int sourceOffset = (row * sourceWidth + column) * 4;
        final int destinationOffset =
            ((destinationY + row) * destinationWidth + destinationX + column) *
            4;
        _composePixel(
          destination,
          destinationOffset,
          source,
          sourceOffset,
          overwrite,
        );
      }
    }
  }

  static void _composeCanvasRect({
    required Uint8List destination,
    required Uint8List source,
    required int canvasWidth,
    required int sourceX,
    required int sourceY,
    required int destinationX,
    required int destinationY,
    required int width,
    required int height,
    required bool overwrite,
  }) {
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final int sourceOffset =
            ((sourceY + row) * canvasWidth + sourceX + column) * 4;
        final int destinationOffset =
            ((destinationY + row) * canvasWidth + destinationX + column) * 4;
        _composePixel(
          destination,
          destinationOffset,
          source,
          sourceOffset,
          overwrite,
        );
      }
    }
  }

  static void _composePixel(
    Uint8List destination,
    int destinationOffset,
    Uint8List source,
    int sourceOffset,
    bool overwrite,
  ) {
    final int sourceAlpha = source[sourceOffset + 3];
    if (overwrite || sourceAlpha == 255) {
      destination.setRange(
        destinationOffset,
        destinationOffset + 4,
        source,
        sourceOffset,
      );
      return;
    }
    if (sourceAlpha == 0) return;
    final int destinationAlpha = destination[destinationOffset + 3];
    final int inverseSourceAlpha = 255 - sourceAlpha;
    final int alphaNumerator =
        sourceAlpha * 255 + destinationAlpha * inverseSourceAlpha;
    for (var channel = 0; channel < 3; channel++) {
      final int colorNumerator =
          source[sourceOffset + channel] * sourceAlpha * 255 +
          destination[destinationOffset + channel] *
              destinationAlpha *
              inverseSourceAlpha;
      destination[destinationOffset + channel] =
          (colorNumerator + alphaNumerator ~/ 2) ~/ alphaNumerator;
    }
    destination[destinationOffset + 3] = (alphaNumerator + 127) ~/ 255;
  }

  static bool _rectanglesOverlap(
    int firstX,
    int firstY,
    int secondX,
    int secondY,
    int width,
    int height,
  ) =>
      firstX < secondX + width &&
      secondX < firstX + width &&
      firstY < secondY + height &&
      secondY < firstY + height;

  static bool _samePlacementState(
    TerminalKittyImagePlacement left,
    TerminalKittyImagePlacement right,
  ) =>
      left.logicalLineId == right.logicalLineId &&
      left.logicalLineEpoch == right.logicalLineEpoch &&
      left.logicalCellOffset == right.logicalCellOffset &&
      left.sourceX == right.sourceX &&
      left.sourceY == right.sourceY &&
      left.sourceWidth == right.sourceWidth &&
      left.sourceHeight == right.sourceHeight &&
      left.cellOffsetX == right.cellOffsetX &&
      left.cellOffsetY == right.cellOffsetY &&
      left.fixedPixelWidth == right.fixedPixelWidth &&
      left.fixedPixelHeight == right.fixedPixelHeight;

  static int _ceilDivide(int value, int divisor) =>
      value == 0 ? 0 : (value + divisor - 1) ~/ divisor;

  int _placementColumns(
    TerminalKittyImagePlacement placement,
    int cellWidth,
    int cellHeight,
  ) {
    final TerminalKittyImage? image = _byId[placement.imageId];
    if (image == null ||
        image.resourceGeneration != placement.imageResourceGeneration) {
      return 0;
    }
    return placement
        .geometry(image: image, cellWidth: cellWidth, cellHeight: cellHeight)
        .columns;
  }

  int _placementRows(
    TerminalKittyImagePlacement placement,
    int cellWidth,
    int cellHeight,
  ) {
    final TerminalKittyImage? image = _byId[placement.imageId];
    if (image == null ||
        image.resourceGeneration != placement.imageResourceGeneration) {
      return 0;
    }
    return placement
        .geometry(image: image, cellWidth: cellWidth, cellHeight: cellHeight)
        .rows;
  }

  bool _containsCell(
    TerminalKittyImagePlacement placement,
    TerminalKittyImagePlacementPosition position,
    int row,
    int column,
    int cellWidth,
    int cellHeight,
  ) {
    final int columns = _placementColumns(placement, cellWidth, cellHeight);
    final int rows = _placementRows(placement, cellWidth, cellHeight);
    return columns > 0 &&
        rows > 0 &&
        row >= position.row &&
        row < position.row + rows &&
        column >= position.column &&
        column < position.column + columns;
  }

  bool _intersects(
    TerminalKittyImagePlacement placement,
    TerminalKittyImagePlacementPosition position, {
    required int row,
    required int column,
    required int rows,
    required int columns,
    required int cellWidth,
    required int cellHeight,
  }) {
    final int placementColumns = _placementColumns(
      placement,
      cellWidth,
      cellHeight,
    );
    final int placementRows = _placementRows(placement, cellWidth, cellHeight);
    return placementColumns > 0 &&
        placementRows > 0 &&
        position.row < row + rows &&
        position.row + placementRows > row &&
        position.column < column + columns &&
        position.column + placementColumns > column;
  }

  static bool _selectorDeletesData(
    TerminalKittyGraphicsDeleteSelector selector,
  ) => switch (selector) {
    TerminalKittyGraphicsDeleteSelector.allAndData ||
    TerminalKittyGraphicsDeleteSelector.animationFramesAndData ||
    TerminalKittyGraphicsDeleteSelector.cursorAndData ||
    TerminalKittyGraphicsDeleteSelector.newestAndData ||
    TerminalKittyGraphicsDeleteSelector.imageIdAndData ||
    TerminalKittyGraphicsDeleteSelector.cellAndData ||
    TerminalKittyGraphicsDeleteSelector.cellAndZAndData ||
    TerminalKittyGraphicsDeleteSelector.rangeAndData ||
    TerminalKittyGraphicsDeleteSelector.columnAndData ||
    TerminalKittyGraphicsDeleteSelector.rowAndData ||
    TerminalKittyGraphicsDeleteSelector.zAndData => true,
    _ => false,
  };

  int _allocateImageId() {
    for (var attempts = 0; attempts <= _byId.length; attempts++) {
      final int candidate = _nextImageId;
      _nextImageId = candidate == 0xffffffff ? 1 : candidate + 1;
      if (!_byId.containsKey(candidate)) return candidate;
    }
    throw StateError('bounded Kitty image ID space is unexpectedly exhausted');
  }

  int _takeResourceGeneration() {
    final int result = _nextResourceGeneration;
    _nextResourceGeneration++;
    return result;
  }

  int _takePlacementGeneration() {
    if (_nextPlacementGeneration > 0x7fffffffffffffff) {
      throw StateError('Kitty placement generation space is exhausted');
    }
    return _nextPlacementGeneration++;
  }

  static void _validateIdentity(int imageId, int imageNumber) {
    if (imageId < 0 ||
        imageId > 0xffffffff ||
        imageNumber < 0 ||
        imageNumber > 0xffffffff ||
        (imageId == 0) == (imageNumber == 0)) {
      throw ArgumentError(
        'exactly one positive image ID or number is required',
      );
    }
  }

  static void _validateImage(int width, int height, Uint8List rgba) {
    if (width <= 0 ||
        height <= 0 ||
        width > TerminalKittyImageStoreLimits.maximumDimension ||
        height > TerminalKittyImageStoreLimits.maximumDimension ||
        width * height > TerminalKittyImageStoreLimits.maximumPixels ||
        rgba.length != width * height * 4 ||
        rgba.length > TerminalKittyImageStoreLimits.maximumImageBytes) {
      throw ArgumentError('canonical Kitty image exceeds storage limits');
    }
  }

  static void _validatePlacement({
    required int placementId,
    required int logicalLineId,
    required int logicalLineEpoch,
    required int logicalCellOffset,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int cellOffsetX,
    required int cellOffsetY,
    required int columns,
    required int rows,
    required int z,
  }) {
    final List<int> unsigned32 = <int>[
      placementId,
      sourceX,
      sourceY,
      sourceWidth,
      sourceHeight,
      cellOffsetX,
      cellOffsetY,
      columns,
      rows,
    ];
    if (unsigned32.any((int value) => value < 0 || value > 0xffffffff) ||
        logicalLineId <= 0 ||
        logicalLineId > 0xffffffff ||
        logicalLineEpoch <= 0 ||
        logicalLineEpoch > 0x7fffffffffffffff ||
        logicalCellOffset < 0 ||
        logicalCellOffset > 0x7fffffffffffffff ||
        z < -0x80000000 ||
        z > 0x7fffffff) {
      throw ArgumentError('Kitty placement metadata is out of range');
    }
  }
}
