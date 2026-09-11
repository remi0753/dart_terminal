import 'dart:collection';
import 'dart:typed_data';

/// Fixed product ceilings for decoded Kitty image bytes retained per screen.
abstract final class TerminalKittyImageStoreLimits {
  static const int maximumImages = 64;
  static const int maximumRetainedBytes = 16 * 1024 * 1024;
  static const int maximumImageBytes = 1024 * 1024;
  static const int maximumPixels = maximumImageBytes ~/ 4;
  static const int maximumDimension = 4096;
}

/// One immutable canonical RGBA8 image owned by a terminal screen.
final class TerminalKittyImage {
  TerminalKittyImage._({
    required this.id,
    required this.number,
    required this.width,
    required this.height,
    required this.resourceGeneration,
    required this.transient,
    required Uint8List rgba,
  }) : _rgba = Uint8List.fromList(rgba);

  final int id;
  final int number;
  final int width;
  final int height;
  final int resourceGeneration;
  final bool transient;
  final Uint8List _rgba;

  int get byteLength => _rgba.length;

  Uint8List copyRgba() => Uint8List.fromList(_rgba);
}

enum TerminalKittyImageStoreDisposition { stored, resourceLimit }

final class TerminalKittyImageStoreResult {
  const TerminalKittyImageStoreResult(this.disposition, {this.image});

  final TerminalKittyImageStoreDisposition disposition;
  final TerminalKittyImage? image;
}

/// Per-screen, reject-on-cap storage for static Kitty image data.
final class TerminalKittyImageStore {
  TerminalKittyImageStore({
    this.maximumImages = TerminalKittyImageStoreLimits.maximumImages,
    this.maximumRetainedBytes =
        TerminalKittyImageStoreLimits.maximumRetainedBytes,
  }) {
    if (maximumImages <= 0 ||
        maximumImages > TerminalKittyImageStoreLimits.maximumImages ||
        maximumRetainedBytes <= 0 ||
        maximumRetainedBytes >
            TerminalKittyImageStoreLimits.maximumRetainedBytes) {
      throw ArgumentError('Kitty image store bounds exceed product limits');
    }
  }

  final int maximumImages;
  final int maximumRetainedBytes;
  final LinkedHashMap<int, TerminalKittyImage> _byId =
      LinkedHashMap<int, TerminalKittyImage>();
  var _retainedBytes = 0;
  var _nextImageId = 1;
  var _nextResourceGeneration = 1;
  var _stateGeneration = 1;

  int get length => _byId.length;
  int get retainedBytes => _retainedBytes;
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
        _retainedBytes - (replaced?.byteLength ?? 0) + rgba.length;
    if (projectedCount > maximumImages ||
        projectedBytes > maximumRetainedBytes) {
      return const TerminalKittyImageStoreResult(
        TerminalKittyImageStoreDisposition.resourceLimit,
      );
    }
    final TerminalKittyImage image = TerminalKittyImage._(
      id: resolvedId,
      number: generatedId ? imageNumber : 0,
      width: width,
      height: height,
      resourceGeneration: _takeResourceGeneration(),
      transient: transient,
      rgba: rgba,
    );
    if (replaced != null) {
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

  void clear() {
    if (_byId.isEmpty) return;
    _byId.clear();
    _retainedBytes = 0;
    _stateGeneration++;
  }

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
}
