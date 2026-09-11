import 'dart:typed_data';

/// Product-owned bounds for one Kitty graphics APC command.
abstract final class TerminalKittyGraphicsLimits {
  static const int maximumControlBytes = 512;
  static const int maximumDataBytes = 4096;
  static const int maximumApcPayloadBytes =
      1 + maximumControlBytes + 1 + maximumDataBytes;
  static const int maximumControlPairs = 32;
  static const int maximumResponseBytes = 256;
  static const int maximumErrorCodeBytes = 16;
  static const int maximumErrorDescriptionBytes = 160;
}

enum TerminalKittyGraphicsAction {
  controlAnimation('a'),
  composeAnimation('c'),
  delete('d'),
  transmitAnimationFrame('f'),
  place('p'),
  query('q'),
  transmit('t'),
  transmitAndPlace('T');

  const TerminalKittyGraphicsAction(this.wireValue);

  final String wireValue;
}

enum TerminalKittyGraphicsMedium {
  direct('d'),
  file('f'),
  temporaryFile('t'),
  sharedMemory('s');

  const TerminalKittyGraphicsMedium(this.wireValue);

  final String wireValue;
}

enum TerminalKittyGraphicsCompression {
  none(null),
  zlib('z');

  const TerminalKittyGraphicsCompression(this.wireValue);

  final String? wireValue;
}

/// q=0 emits replies, q=1 suppresses success, and q=2 suppresses all replies.
enum TerminalKittyGraphicsQuiet { replies, errorsOnly, none }

enum TerminalKittyGraphicsAnimationState {
  unchanged,
  stopped,
  loading,
  running,
}

enum TerminalKittyGraphicsDeleteSelector {
  all('a'),
  allAndData('A'),
  animationFrames('f'),
  animationFramesAndData('F'),
  cursor('c'),
  cursorAndData('C'),
  newest('n'),
  newestAndData('N'),
  imageId('i'),
  imageIdAndData('I'),
  cell('p'),
  cellAndData('P'),
  cellAndZ('q'),
  cellAndZAndData('Q'),
  range('r'),
  rangeAndData('R'),
  column('x'),
  columnAndData('X'),
  row('y'),
  rowAndData('Y'),
  z('z'),
  zAndData('Z');

  const TerminalKittyGraphicsDeleteSelector(this.wireValue);

  final String wireValue;
}

final class TerminalKittyGraphicsTransmission {
  const TerminalKittyGraphicsTransmission({
    required this.format,
    required this.medium,
    required this.width,
    required this.height,
    required this.dataSize,
    required this.dataOffset,
    required this.imageId,
    required this.imageNumber,
    required this.placementId,
    required this.compression,
    required this.moreChunks,
    required this.usage,
  });

  final int format;
  final TerminalKittyGraphicsMedium medium;
  final int width;
  final int height;
  final int dataSize;
  final int dataOffset;
  final int imageId;
  final int imageNumber;
  final int placementId;
  final TerminalKittyGraphicsCompression compression;
  final bool moreChunks;
  final int usage;
}

final class TerminalKittyGraphicsPlacement {
  const TerminalKittyGraphicsPlacement({
    required this.imageId,
    required this.imageNumber,
    required this.placementId,
    required this.sourceX,
    required this.sourceY,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cellOffsetX,
    required this.cellOffsetY,
    required this.columns,
    required this.rows,
    required this.cursorMovement,
    required this.virtual,
    required this.z,
    required this.parentImageId,
    required this.parentPlacementId,
    required this.relativeColumnOffset,
    required this.relativeRowOffset,
  });

  final int imageId;
  final int imageNumber;
  final int placementId;
  final int sourceX;
  final int sourceY;
  final int sourceWidth;
  final int sourceHeight;
  final int cellOffsetX;
  final int cellOffsetY;
  final int columns;
  final int rows;
  final int cursorMovement;
  bool get suppressCursorMovement => cursorMovement == 1;
  final bool virtual;
  final int z;
  final int parentImageId;
  final int parentPlacementId;
  final int relativeColumnOffset;
  final int relativeRowOffset;
}

final class TerminalKittyGraphicsDeletion {
  const TerminalKittyGraphicsDeletion({
    required this.selector,
    required this.imageId,
    required this.imageNumber,
    required this.placementId,
    required this.x,
    required this.y,
    required this.z,
    required this.frameNumber,
  });

  final TerminalKittyGraphicsDeleteSelector selector;
  final int imageId;
  final int imageNumber;
  final int placementId;
  final int x;
  final int y;
  final int z;
  final int frameNumber;
}

final class TerminalKittyGraphicsFrameTransmission {
  const TerminalKittyGraphicsFrameTransmission({
    required this.x,
    required this.y,
    required this.baseFrame,
    required this.editFrame,
    required this.gapMilliseconds,
    required this.overwrite,
    required this.backgroundRgba,
  });

  final int x;
  final int y;
  final int baseFrame;
  final int editFrame;
  final int gapMilliseconds;
  final bool overwrite;
  final int backgroundRgba;
}

final class TerminalKittyGraphicsAnimationControl {
  const TerminalKittyGraphicsAnimationControl({
    required this.state,
    required this.frameNumber,
    required this.gapMilliseconds,
    required this.currentFrame,
    required this.loops,
  });

  final TerminalKittyGraphicsAnimationState state;
  final int frameNumber;
  final int gapMilliseconds;
  final int currentFrame;
  final int loops;
}

final class TerminalKittyGraphicsFrameComposition {
  const TerminalKittyGraphicsFrameComposition({
    required this.sourceFrame,
    required this.destinationFrame,
    required this.destinationX,
    required this.destinationY,
    required this.width,
    required this.height,
    required this.sourceX,
    required this.sourceY,
    required this.overwrite,
  });

  final int sourceFrame;
  final int destinationFrame;
  final int destinationX;
  final int destinationY;
  final int width;
  final int height;
  final int sourceX;
  final int sourceY;
  final bool overwrite;
}

/// An immutable, syntax-validated Kitty graphics command.
final class TerminalKittyGraphicsCommand {
  TerminalKittyGraphicsCommand._({
    required this.action,
    required this.quiet,
    required this.transmission,
    required this.placement,
    required this.deletion,
    required this.frameTransmission,
    required this.animationControl,
    required this.frameComposition,
    required this.hasImageIdKey,
    required this.hasImageNumberKey,
    required this.hasMoreChunksKey,
    required this.isMultipartContinuationCompatible,
    required this.isAnimationMultipartContinuationCompatible,
    required Uint8List data,
  }) : _data = Uint8List.fromList(data);

  final TerminalKittyGraphicsAction action;
  final TerminalKittyGraphicsQuiet quiet;
  final TerminalKittyGraphicsTransmission transmission;
  final TerminalKittyGraphicsPlacement placement;
  final TerminalKittyGraphicsDeletion deletion;
  final TerminalKittyGraphicsFrameTransmission frameTransmission;
  final TerminalKittyGraphicsAnimationControl animationControl;
  final TerminalKittyGraphicsFrameComposition frameComposition;
  final bool hasImageIdKey;
  final bool hasImageNumberKey;
  final bool hasMoreChunksKey;

  /// Whether the command carries only the `m` and optional `q` controls that
  /// Kitty permits after the first direct multipart chunk.
  final bool isMultipartContinuationCompatible;
  final bool isAnimationMultipartContinuationCompatible;
  final Uint8List _data;

  int get dataLength => _data.length;

  Uint8List copyData() => Uint8List.fromList(_data);

  bool isMultipartContinuationFor(TerminalKittyGraphicsAction initialAction) =>
      initialAction == TerminalKittyGraphicsAction.transmitAnimationFrame
      ? isAnimationMultipartContinuationCompatible
      : isMultipartContinuationCompatible;
}

final class TerminalKittyGraphicsParseException implements Exception {
  const TerminalKittyGraphicsParseException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'TerminalKittyGraphicsParseException($code, $message)';
}

/// Parses the payload of a complete APC, including its leading `G` byte.
abstract final class TerminalKittyGraphicsCommandParser {
  static TerminalKittyGraphicsCommand parse(Uint8List payload) {
    if (payload.isEmpty || payload[0] != 0x47) {
      throw const TerminalKittyGraphicsParseException(
        'EINVAL',
        'not a Kitty graphics APC',
      );
    }
    if (payload.length > TerminalKittyGraphicsLimits.maximumApcPayloadBytes) {
      throw const TerminalKittyGraphicsParseException(
        'E2BIG',
        'APC payload exceeds the product limit',
      );
    }

    final int separator = payload.indexOf(0x3b, 1);
    final int controlEnd = separator < 0 ? payload.length : separator;
    final int controlLength = controlEnd - 1;
    if (controlLength > TerminalKittyGraphicsLimits.maximumControlBytes) {
      throw const TerminalKittyGraphicsParseException(
        'E2BIG',
        'control data exceeds the product limit',
      );
    }
    final int dataStart = separator < 0 ? payload.length : separator + 1;
    final int dataLength = payload.length - dataStart;
    if (dataLength > TerminalKittyGraphicsLimits.maximumDataBytes) {
      throw const TerminalKittyGraphicsParseException(
        'E2BIG',
        'encoded data exceeds the product limit',
      );
    }

    final Map<int, Object> values = <int, Object>{};
    if (controlLength != 0) {
      if (payload[controlEnd - 1] == 0x2c) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'control data must not end with an empty pair',
        );
      }
      int pairStart = 1;
      var pairCount = 0;
      while (pairStart < controlEnd) {
        final int comma = payload.indexOf(0x2c, pairStart);
        final int pairEnd = comma < 0 || comma >= controlEnd
            ? controlEnd
            : comma;
        pairCount++;
        if (pairCount > TerminalKittyGraphicsLimits.maximumControlPairs) {
          throw const TerminalKittyGraphicsParseException(
            'E2BIG',
            'too many control pairs',
          );
        }
        _parsePair(payload, pairStart, pairEnd, values);
        pairStart = pairEnd + 1;
      }
    }

    final TerminalKittyGraphicsAction action = _action(values[0x61]);
    final TerminalKittyGraphicsQuiet quiet = _quiet(_unsigned(values, 0x71));
    final int imageId = _unsigned(values, 0x69);
    final int imageNumber = _unsigned(values, 0x49);
    final int placementId = _unsigned(values, 0x70);
    final bool usesTransmission =
        action == TerminalKittyGraphicsAction.query ||
        action == TerminalKittyGraphicsAction.transmit ||
        action == TerminalKittyGraphicsAction.transmitAndPlace ||
        action == TerminalKittyGraphicsAction.transmitAnimationFrame;
    final bool usesPlacement =
        action == TerminalKittyGraphicsAction.place ||
        action == TerminalKittyGraphicsAction.transmitAndPlace;
    final bool usesDeletion = action == TerminalKittyGraphicsAction.delete;
    return TerminalKittyGraphicsCommand._(
      action: action,
      quiet: quiet,
      transmission: TerminalKittyGraphicsTransmission(
        format: _unsigned(values, 0x66, defaultValue: 32),
        medium: usesTransmission
            ? _medium(values[0x74])
            : TerminalKittyGraphicsMedium.direct,
        width: _unsigned(values, 0x73),
        height: _unsigned(values, 0x76),
        dataSize: _unsigned(values, 0x53),
        dataOffset: _unsigned(values, 0x4f),
        imageId: imageId,
        imageNumber: imageNumber,
        placementId: placementId,
        compression: usesTransmission
            ? _compression(values[0x6f])
            : TerminalKittyGraphicsCompression.none,
        moreChunks: usesTransmission ? _binary(values, 0x6d) : false,
        usage: _unsigned(values, 0x4e),
      ),
      placement: TerminalKittyGraphicsPlacement(
        imageId: imageId,
        imageNumber: imageNumber,
        placementId: placementId,
        sourceX: _unsigned(values, 0x78),
        sourceY: _unsigned(values, 0x79),
        sourceWidth: _unsigned(values, 0x77),
        sourceHeight: _unsigned(values, 0x68),
        cellOffsetX: _unsigned(values, 0x58),
        cellOffsetY: _unsigned(values, 0x59),
        columns: _unsigned(values, 0x63),
        rows: _unsigned(values, 0x72),
        cursorMovement: usesPlacement ? _unsigned(values, 0x43) : 0,
        virtual: usesPlacement && _unsigned(values, 0x55) != 0,
        z: _signed(values, 0x7a),
        parentImageId: _unsigned(values, 0x50),
        parentPlacementId: _unsigned(values, 0x51),
        relativeColumnOffset: _signed(values, 0x48),
        relativeRowOffset: _signed(values, 0x56),
      ),
      deletion: TerminalKittyGraphicsDeletion(
        selector: usesDeletion
            ? _deleteSelector(values[0x64])
            : TerminalKittyGraphicsDeleteSelector.all,
        imageId: imageId,
        imageNumber: imageNumber,
        placementId: placementId,
        x: _unsigned(values, 0x78),
        y: _unsigned(values, 0x79),
        z: _signed(values, 0x7a),
        frameNumber: _unsigned(values, 0x72),
      ),
      frameTransmission: TerminalKittyGraphicsFrameTransmission(
        x: _unsigned(values, 0x78),
        y: _unsigned(values, 0x79),
        baseFrame: _unsigned(values, 0x63),
        editFrame: _unsigned(values, 0x72),
        gapMilliseconds: _signed(values, 0x7a),
        overwrite: _unsigned(values, 0x58) == 1,
        backgroundRgba: _unsigned(values, 0x59),
      ),
      animationControl: TerminalKittyGraphicsAnimationControl(
        state: _animationState(_unsigned(values, 0x73)),
        frameNumber: _unsigned(values, 0x72),
        gapMilliseconds: _signed(values, 0x7a),
        currentFrame: _unsigned(values, 0x63),
        loops: _unsigned(values, 0x76),
      ),
      frameComposition: TerminalKittyGraphicsFrameComposition(
        sourceFrame: _unsigned(values, 0x72),
        destinationFrame: _unsigned(values, 0x63),
        destinationX: _unsigned(values, 0x78),
        destinationY: _unsigned(values, 0x79),
        width: _unsigned(values, 0x77),
        height: _unsigned(values, 0x68),
        sourceX: _unsigned(values, 0x58),
        sourceY: _unsigned(values, 0x59),
        overwrite: _unsigned(values, 0x43) != 0,
      ),
      hasImageIdKey: values.containsKey(0x69),
      hasImageNumberKey: values.containsKey(0x49),
      hasMoreChunksKey: values.containsKey(0x6d),
      isMultipartContinuationCompatible: values.keys.every(
        (int key) => key == 0x6d || key == 0x71,
      ),
      isAnimationMultipartContinuationCompatible:
          action == TerminalKittyGraphicsAction.transmitAnimationFrame &&
          values.keys.every(
            (int key) => key == 0x61 || key == 0x6d || key == 0x71,
          ),
      data: Uint8List.sublistView(payload, dataStart),
    );
  }

  static void _parsePair(
    Uint8List payload,
    int start,
    int end,
    Map<int, Object> values,
  ) {
    if (end - start < 3 || payload[start + 1] != 0x3d) {
      throw const TerminalKittyGraphicsParseException(
        'EINVAL',
        'control pair must be one ASCII letter, equals, and a value',
      );
    }
    final int key = payload[start];
    if (!_isAsciiLetter(key)) {
      throw const TerminalKittyGraphicsParseException(
        'EINVAL',
        'control key must be one ASCII letter',
      );
    }
    final int valueStart = start + 2;
    for (int index = valueStart; index < end; index++) {
      final int byte = payload[index];
      if (byte < 0x20 || byte > 0x7e) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'control values must be printable ASCII',
        );
      }
    }
    if (!_knownKeys.contains(key)) {
      if (end == valueStart) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'unknown control value must not be empty',
        );
      }
      return;
    }
    if (_characterKeys.contains(key)) {
      if (end - valueStart != 1) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'character control value must contain exactly one byte',
        );
      }
      values[key] = payload[valueStart];
      return;
    }
    final bool signed = _signedKeys.contains(key);
    values[key] = _parseInteger(payload, valueStart, end, signed: signed);
  }

  static int _parseInteger(
    Uint8List payload,
    int start,
    int end, {
    required bool signed,
  }) {
    if (start == end) {
      throw const TerminalKittyGraphicsParseException(
        'EINVAL',
        'integer control value must not be empty',
      );
    }
    var negative = false;
    var index = start;
    if (signed && payload[index] == 0x2d) {
      negative = true;
      index++;
    }
    if (index == end) {
      throw const TerminalKittyGraphicsParseException(
        'EINVAL',
        'signed control value must contain digits',
      );
    }
    var value = 0;
    final int maximum = signed
        ? (negative ? 0x80000000 : 0x7fffffff)
        : 0xffffffff;
    while (index < end) {
      final int byte = payload[index++];
      if (byte < 0x30 || byte > 0x39) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'integer control value contains a non-digit',
        );
      }
      final int digit = byte - 0x30;
      if (value > (maximum - digit) ~/ 10) {
        throw const TerminalKittyGraphicsParseException(
          'ERANGE',
          'integer control value exceeds 32-bit range',
        );
      }
      value = value * 10 + digit;
    }
    return negative ? -value : value;
  }

  static TerminalKittyGraphicsAction _action(Object? value) {
    final int wire = value == null ? 0x74 : value as int;
    for (final TerminalKittyGraphicsAction action
        in TerminalKittyGraphicsAction.values) {
      if (action.wireValue.codeUnitAt(0) == wire) return action;
    }
    throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'unknown graphics action',
    );
  }

  static TerminalKittyGraphicsMedium _medium(Object? value) {
    final int wire = value == null ? 0x64 : value as int;
    for (final TerminalKittyGraphicsMedium medium
        in TerminalKittyGraphicsMedium.values) {
      if (medium.wireValue.codeUnitAt(0) == wire) return medium;
    }
    throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'unknown transmission medium',
    );
  }

  static TerminalKittyGraphicsCompression _compression(Object? value) {
    if (value == null) return TerminalKittyGraphicsCompression.none;
    if (value == 0x7a) return TerminalKittyGraphicsCompression.zlib;
    throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'unknown compression',
    );
  }

  static TerminalKittyGraphicsDeleteSelector _deleteSelector(Object? value) {
    final int wire = value == null ? 0x61 : value as int;
    for (final TerminalKittyGraphicsDeleteSelector selector
        in TerminalKittyGraphicsDeleteSelector.values) {
      if (selector.wireValue.codeUnitAt(0) == wire) return selector;
    }
    throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'unknown delete selector',
    );
  }

  static TerminalKittyGraphicsQuiet _quiet(int value) => switch (value) {
    0 => TerminalKittyGraphicsQuiet.replies,
    1 => TerminalKittyGraphicsQuiet.errorsOnly,
    2 => TerminalKittyGraphicsQuiet.none,
    _ => throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'quiet must be 0, 1, or 2',
    ),
  };

  static TerminalKittyGraphicsAnimationState _animationState(int value) =>
      switch (value) {
        1 => TerminalKittyGraphicsAnimationState.stopped,
        2 => TerminalKittyGraphicsAnimationState.loading,
        3 => TerminalKittyGraphicsAnimationState.running,
        _ => TerminalKittyGraphicsAnimationState.unchanged,
      };

  static int _unsigned(
    Map<int, Object> values,
    int key, {
    int defaultValue = 0,
  }) => values[key] as int? ?? defaultValue;

  static int _signed(Map<int, Object> values, int key) =>
      values[key] as int? ?? 0;

  static bool _binary(Map<int, Object> values, int key) {
    final int value = _unsigned(values, key);
    if (value == 0) return false;
    if (value == 1) return true;
    throw const TerminalKittyGraphicsParseException(
      'EINVAL',
      'binary control value must be 0 or 1',
    );
  }

  static bool _isAsciiLetter(int byte) =>
      byte >= 0x41 && byte <= 0x5a || byte >= 0x61 && byte <= 0x7a;

  static const Set<int> _characterKeys = <int>{
    0x61, // a
    0x64, // d
    0x6f, // o
    0x74, // t
  };
  static const Set<int> _signedKeys = <int>{
    0x48, // H
    0x56, // V
    0x7a, // z
  };
  static const Set<int> _knownKeys = <int>{
    0x43, // C
    0x48, // H
    0x49, // I
    0x4e, // N
    0x4f, // O
    0x50, // P
    0x51, // Q
    0x53, // S
    0x55, // U
    0x56, // V
    0x58, // X
    0x59, // Y
    0x61, // a
    0x63, // c
    0x64, // d
    0x66, // f
    0x68, // h
    0x69, // i
    0x6d, // m
    0x6f, // o
    0x70, // p
    0x71, // q
    0x72, // r
    0x73, // s
    0x74, // t
    0x76, // v
    0x77, // w
    0x78, // x
    0x79, // y
    0x7a, // z
  };
}

abstract final class TerminalKittyGraphicsResponseEncoder {
  static Uint8List? success({
    required TerminalKittyGraphicsQuiet quiet,
    int imageId = 0,
    int imageNumber = 0,
    int placementId = 0,
    int frameNumber = 0,
  }) {
    if (quiet != TerminalKittyGraphicsQuiet.replies) return null;
    return _encode(
      imageId: imageId,
      imageNumber: imageNumber,
      placementId: placementId,
      frameNumber: frameNumber,
      message: 'OK',
    );
  }

  static Uint8List? error({
    required TerminalKittyGraphicsQuiet quiet,
    required String code,
    required String description,
    int imageId = 0,
    int imageNumber = 0,
    int placementId = 0,
    int frameNumber = 0,
  }) {
    if (quiet == TerminalKittyGraphicsQuiet.none) return null;
    _validateErrorText(code, description);
    return _encode(
      imageId: imageId,
      imageNumber: imageNumber,
      placementId: placementId,
      frameNumber: frameNumber,
      message: '$code:$description',
    );
  }

  static Uint8List? _encode({
    required int imageId,
    required int imageNumber,
    required int placementId,
    required int frameNumber,
    required String message,
  }) {
    _validateIdentifier(imageId, 'imageId');
    _validateIdentifier(imageNumber, 'imageNumber');
    _validateIdentifier(placementId, 'placementId');
    _validateIdentifier(frameNumber, 'frameNumber');
    if (imageId == 0 && imageNumber == 0) return null;
    final StringBuffer buffer = StringBuffer('\x1b_G');
    var prior = false;
    if (imageId != 0) {
      buffer.write('i=$imageId');
      prior = true;
    }
    if (imageNumber != 0) {
      if (prior) buffer.write(',');
      buffer.write('I=$imageNumber');
      prior = true;
    }
    if (placementId != 0) {
      if (prior) buffer.write(',');
      buffer.write('p=$placementId');
      prior = true;
    }
    if (frameNumber != 0) {
      if (prior) buffer.write(',');
      buffer.write('r=$frameNumber');
    }
    buffer.write(';$message\x1b\\');
    final Uint8List result = Uint8List.fromList(buffer.toString().codeUnits);
    if (result.length > TerminalKittyGraphicsLimits.maximumResponseBytes) {
      throw const TerminalKittyGraphicsParseException(
        'E2BIG',
        'encoded response exceeds the product limit',
      );
    }
    return result;
  }

  static void _validateIdentifier(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw RangeError.range(value, 0, 0xffffffff, name);
    }
  }

  static void _validateErrorText(String code, String description) {
    if (code.isEmpty ||
        code.length > TerminalKittyGraphicsLimits.maximumErrorCodeBytes ||
        description.length >
            TerminalKittyGraphicsLimits.maximumErrorDescriptionBytes) {
      throw const TerminalKittyGraphicsParseException(
        'E2BIG',
        'error response text exceeds the product limit',
      );
    }
    for (final int byte in code.codeUnits) {
      if (!(byte >= 0x41 && byte <= 0x5a) &&
          !(byte >= 0x30 && byte <= 0x39) &&
          byte != 0x5f) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'error code must be uppercase printable ASCII',
        );
      }
    }
    for (final int byte in description.codeUnits) {
      if (byte < 0x20 || byte > 0x7e) {
        throw const TerminalKittyGraphicsParseException(
          'EINVAL',
          'error description must be printable ASCII',
        );
      }
    }
  }
}
