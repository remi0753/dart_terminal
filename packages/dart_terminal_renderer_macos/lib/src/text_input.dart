import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:ffi/ffi.dart';

const String _textInputAssetId =
    'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

final class TerminalTextInputRange {
  const TerminalTextInputRange(this.location, this.length)
    : assert(location >= -1),
      assert(length >= 0),
      assert(location >= 0 || length == 0);

  static const TerminalTextInputRange notFound = TerminalTextInputRange(-1, 0);

  final int location;
  final int length;

  bool get isFound => location >= 0;

  @override
  bool operator ==(Object other) =>
      other is TerminalTextInputRange &&
      other.location == location &&
      other.length == length;

  @override
  int get hashCode => Object.hash(location, length);
}

sealed class TerminalTextInputEvent {
  const TerminalTextInputEvent({
    required this.clientId,
    required this.generation,
    required this.monotonicNanoseconds,
  });

  final int clientId;
  final int generation;
  final int monotonicNanoseconds;
}

enum TerminalTextInputKeyKind { down, up }

final class TerminalTextInputKeyEvent extends TerminalTextInputEvent {
  const TerminalTextInputKeyEvent({
    required super.clientId,
    required super.generation,
    required super.monotonicNanoseconds,
    required this.kind,
    required this.keyCode,
    required this.modifiers,
    required this.isRepeat,
    required this.characters,
    required this.charactersIgnoringModifiers,
  });

  final TerminalTextInputKeyKind kind;
  final int keyCode;
  final ModifierKeys modifiers;
  final bool isRepeat;
  final String characters;
  final String charactersIgnoringModifiers;
}

final class TerminalTextInputPreeditEvent extends TerminalTextInputEvent {
  const TerminalTextInputPreeditEvent({
    required super.clientId,
    required super.generation,
    required super.monotonicNanoseconds,
    required this.text,
    required this.selection,
    required this.replacement,
  });

  final String text;
  final TerminalTextInputRange selection;
  final TerminalTextInputRange replacement;
}

final class TerminalTextInputCommitEvent extends TerminalTextInputEvent {
  const TerminalTextInputCommitEvent({
    required super.clientId,
    required super.generation,
    required super.monotonicNanoseconds,
    required this.text,
    required this.replacement,
  });

  final String text;
  final TerminalTextInputRange replacement;
}

final class TerminalTextInputCancelEvent extends TerminalTextInputEvent {
  const TerminalTextInputCancelEvent({
    required super.clientId,
    required super.generation,
    required super.monotonicNanoseconds,
  });
}

final class TerminalTextInputOverflowEvent extends TerminalTextInputEvent {
  const TerminalTextInputOverflowEvent({
    required super.clientId,
    required super.generation,
    required super.monotonicNanoseconds,
  });
}

final class TerminalTextInputException implements Exception {
  const TerminalTextInputException(this.message);

  final String message;

  @override
  String toString() => 'TerminalTextInputException: $message';
}

/// Stateful strict decoder for the versioned native text-input packet stream.
final class TerminalTextInputPacketDecoder {
  TerminalTextInputPacketDecoder(this.clientId) {
    RangeError.checkValueInInterval(
      clientId,
      1,
      0x7fffffffffffffff,
      'clientId',
    );
  }

  final int clientId;
  int _lastGeneration = 0;

  int get lastGeneration => _lastGeneration;

  TerminalTextInputEvent decode(Uint8List bytes) {
    if (bytes.length < TerminalTextInputClient._eventHeaderBytes) {
      throw const FormatException('text-input event header is truncated');
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) !=
            TerminalTextInputClient._eventMagic ||
        data.getUint32(4, Endian.little) !=
            TerminalTextInputClient._eventVersion ||
        data.getUint32(8, Endian.little) !=
            TerminalTextInputClient._eventHeaderBytes ||
        data.getUint32(12, Endian.little) != bytes.length ||
        data.getUint64(16, Endian.little) != clientId) {
      throw const FormatException('text-input event identity is invalid');
    }
    final int generation = data.getUint64(24, Endian.little);
    final int monotonicNanoseconds = data.getUint64(32, Endian.little);
    if (generation <= _lastGeneration ||
        generation > 0x7fffffffffffffff ||
        monotonicNanoseconds > 0x7fffffffffffffff) {
      throw const FormatException('text-input event generation is invalid');
    }
    final int kind = data.getUint32(40, Endian.little);
    final int flags = data.getUint32(44, Endian.little);
    final int keyCode = data.getUint32(48, Endian.little);
    final int modifiers = data.getUint32(52, Endian.little);
    if (flags & ~1 != 0 || modifiers & ~ModifierKeys.supportedBits != 0) {
      throw const FormatException('text-input event flags are invalid');
    }
    final String text = _decodeTextRegion(
      bytes,
      data.getUint32(56, Endian.little),
      data.getUint32(60, Endian.little),
    );
    final String unmodifiedText = _decodeTextRegion(
      bytes,
      data.getUint32(64, Endian.little),
      data.getUint32(68, Endian.little),
    );
    if (data.getUint32(56, Endian.little) !=
            TerminalTextInputClient._eventHeaderBytes ||
        data.getUint32(64, Endian.little) !=
            TerminalTextInputClient._eventHeaderBytes +
                data.getUint32(60, Endian.little) ||
        data.getUint32(64, Endian.little) + data.getUint32(68, Endian.little) !=
            bytes.length) {
      throw const FormatException('text-input event regions are not canonical');
    }
    final TerminalTextInputRange selection = _decodeRange(
      data.getUint32(72, Endian.little),
      data.getUint32(76, Endian.little),
    );
    final TerminalTextInputRange replacement = _decodeRange(
      data.getUint32(80, Endian.little),
      data.getUint32(84, Endian.little),
    );
    if (data.getUint32(88, Endian.little) != 0 ||
        data.getUint32(92, Endian.little) != 0) {
      throw const FormatException('text-input event reserved fields changed');
    }
    final bool raw = kind == 1 || kind == 2;
    final bool preedit = kind == 3;
    final bool commit = kind == 4;
    final bool terminal = kind == 5 || kind == 6;
    if ((!raw && flags != 0) ||
        (!raw && (keyCode != 0 || modifiers != 0)) ||
        (raw && keyCode > 0xffff) ||
        (raw && (selection.isFound || replacement.isFound)) ||
        (preedit &&
            (text.isEmpty ||
                unmodifiedText.isNotEmpty ||
                !selection.isFound ||
                !_validUtf16Range(text, selection))) ||
        (commit && (unmodifiedText.isNotEmpty || selection.isFound)) ||
        (terminal &&
            (text.isNotEmpty ||
                unmodifiedText.isNotEmpty ||
                selection.isFound ||
                replacement.isFound)) ||
        (!raw && !preedit && !commit && !terminal)) {
      throw const FormatException('text-input event fields are inconsistent');
    }
    final TerminalTextInputEvent result = switch (kind) {
      1 || 2 => TerminalTextInputKeyEvent(
        clientId: clientId,
        generation: generation,
        monotonicNanoseconds: monotonicNanoseconds,
        kind: kind == 1
            ? TerminalTextInputKeyKind.down
            : TerminalTextInputKeyKind.up,
        keyCode: keyCode,
        modifiers: ModifierKeys(modifiers),
        isRepeat: flags & 1 != 0,
        characters: text,
        charactersIgnoringModifiers: unmodifiedText,
      ),
      3 => TerminalTextInputPreeditEvent(
        clientId: clientId,
        generation: generation,
        monotonicNanoseconds: monotonicNanoseconds,
        text: text,
        selection: selection,
        replacement: replacement,
      ),
      4 => TerminalTextInputCommitEvent(
        clientId: clientId,
        generation: generation,
        monotonicNanoseconds: monotonicNanoseconds,
        text: text,
        replacement: replacement,
      ),
      5 => TerminalTextInputCancelEvent(
        clientId: clientId,
        generation: generation,
        monotonicNanoseconds: monotonicNanoseconds,
      ),
      6 => TerminalTextInputOverflowEvent(
        clientId: clientId,
        generation: generation,
        monotonicNanoseconds: monotonicNanoseconds,
      ),
      _ => throw FormatException('unknown text-input event kind $kind'),
    };
    _lastGeneration = generation;
    return result;
  }

  static String _decodeTextRegion(Uint8List bytes, int offset, int length) {
    if (length > TerminalTextInputClient.maximumTextBytes ||
        offset < TerminalTextInputClient._eventHeaderBytes ||
        offset > bytes.length ||
        length > bytes.length - offset) {
      throw const FormatException('text-input UTF-8 region is invalid');
    }
    return utf8.decode(
      Uint8List.sublistView(bytes, offset, offset + length),
      allowMalformed: false,
    );
  }

  static TerminalTextInputRange _decodeRange(int location, int length) {
    if (location == 0xffffffff) {
      if (length != 0) {
        throw const FormatException('NSNotFound range has a nonzero length');
      }
      return TerminalTextInputRange.notFound;
    }
    if (location + length > 0xffffffff) {
      throw const FormatException('text-input range overflows uint32');
    }
    return TerminalTextInputRange(location, length);
  }

  static bool _validUtf16Range(String text, TerminalTextInputRange range) {
    final int end = range.location + range.length;
    if (range.location > text.length || end > text.length) return false;
    bool boundary(int index) =>
        index == 0 ||
        index == text.length ||
        !(text.codeUnitAt(index - 1) >= 0xd800 &&
            text.codeUnitAt(index - 1) <= 0xdbff &&
            text.codeUnitAt(index) >= 0xdc00 &&
            text.codeUnitAt(index) <= 0xdfff);
    return boundary(range.location) && boundary(end);
  }
}

/// Owns one bounded asynchronous NSTextInputClient event stream for a view.
final class TerminalTextInputClient {
  factory TerminalTextInputClient.attach(View view) {
    if (_nextClientId > 0x7fffffffffffffff) {
      throw StateError('terminal text-input client ID space is exhausted');
    }
    _initializeNotification();
    final int clientId = _nextClientId++;
    final TerminalTextInputClient client = TerminalTextInputClient._(
      view,
      clientId,
    );
    final Uint8List payload = Uint8List(_clientPayloadBytes);
    ByteData.sublistView(payload)
      ..setUint32(0, _clientPayloadBytes, Endian.little)
      ..setUint32(4, _clientVersion, Endian.little)
      ..setUint32(8, _operationAttach, Endian.little)
      ..setUint64(16, clientId, Endian.little);
    view.performCustomOperation(payload);
    _clients[clientId] = client;
    return client;
  }

  TerminalTextInputClient._(this.view, this.clientId)
    : _events = StreamController<TerminalTextInputEvent>.broadcast(sync: true),
      _decoder = TerminalTextInputPacketDecoder(clientId);

  static const int maximumTextBytes = 64 * 1024;
  static const int maximumQueuedEvents = 256;
  static const int maximumQueueBytes = 1024 * 1024;
  static const int maximumPacketBytes =
      _eventHeaderBytes + 2 * maximumTextBytes;
  static const int _clientVersion = 1;
  static const int _geometryVersion = 1;
  static const int _eventVersion = 1;
  static const int _eventMagic = 0x49545444;
  static const int _clientPayloadBytes = 24;
  static const int _geometryPayloadBytes = 64;
  static const int _acceptancePayloadBytes = 32;
  static const int _eventHeaderBytes = 96;
  static const int _operationAttach = 2;
  static const int _operationGeometry = 3;
  static const int _operationDetach = 4;
  static const int _operationAcceptance = 5;
  static const int _operationMatrix = 6;
  static const int _statusOk = 0;
  static const int _statusNotFound = 3;
  static const int _statusBufferTooSmall = 7;
  static const int _maximumDrainBatch = 32;
  static int _nextClientId = 1;
  static bool _notificationInitialized = false;
  static final Map<int, TerminalTextInputClient> _clients =
      <int, TerminalTextInputClient>{};

  final View view;
  final int clientId;
  final StreamController<TerminalTextInputEvent> _events;
  final TerminalTextInputPacketDecoder _decoder;
  int _geometryGeneration = 0;
  bool _drainScheduled = false;
  bool _disposed = false;

  Stream<TerminalTextInputEvent> get events => _events.stream;
  bool get isDisposed => _disposed;
  int get lastEventGeneration => _decoder.lastGeneration;
  int get geometryGeneration => _geometryGeneration;

  void publishCaretRect({
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    _requireLive();
    if (!x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      throw ArgumentError('caret rectangle must be finite and positive');
    }
    if (_geometryGeneration == 0x7fffffffffffffff) {
      throw StateError('text-input geometry generation is exhausted');
    }
    final int generation = ++_geometryGeneration;
    final Uint8List payload = Uint8List(_geometryPayloadBytes);
    ByteData.sublistView(payload)
      ..setUint32(0, _geometryPayloadBytes, Endian.little)
      ..setUint32(4, _geometryVersion, Endian.little)
      ..setUint32(8, _operationGeometry, Endian.little)
      ..setUint64(16, clientId, Endian.little)
      ..setUint64(24, generation, Endian.little)
      ..setFloat64(32, x, Endian.little)
      ..setFloat64(40, y, Endian.little)
      ..setFloat64(48, width, Endian.little)
      ..setFloat64(56, height, Endian.little);
    view.performCustomOperation(payload);
  }

  /// Drives one deterministic stage through the attached native
  /// `NSTextInputClient` for bundled product acceptance only.
  ///
  /// Stage 1 emits a raw navigation command and leaves Japanese marked text
  /// active after verifying candidate geometry. Stage 2 commits that text once
  /// and leaves a second marked value active while proving raw suppression.
  /// Stage 3 cancels the second composition.
  void debugRunAcceptanceStage(int stage) {
    _requireLive();
    RangeError.checkValueInInterval(stage, 1, 3, 'stage');
    final Uint8List payload = Uint8List(_acceptancePayloadBytes);
    ByteData.sublistView(payload)
      ..setUint32(0, _acceptancePayloadBytes, Endian.little)
      ..setUint32(4, _clientVersion, Endian.little)
      ..setUint32(8, _operationAcceptance, Endian.little)
      ..setUint32(12, stage, Endian.little)
      ..setUint64(16, clientId, Endian.little);
    view.performCustomOperation(payload);
  }

  /// Drives the fixed input-source and key-repeat corpus through the attached
  /// native `NSTextInputClient` for bundled product acceptance only.
  void debugRunAcceptanceMatrix() {
    _requireLive();
    final Uint8List payload = Uint8List(_clientPayloadBytes);
    ByteData.sublistView(payload)
      ..setUint32(0, _clientPayloadBytes, Endian.little)
      ..setUint32(4, _clientVersion, Endian.little)
      ..setUint32(8, _operationMatrix, Endian.little)
      ..setUint64(16, clientId, Endian.little);
    view.performCustomOperation(payload);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clients.remove(clientId);
    if (!view.isDisposed) {
      final Uint8List payload = Uint8List(_clientPayloadBytes);
      ByteData.sublistView(payload)
        ..setUint32(0, _clientPayloadBytes, Endian.little)
        ..setUint32(4, _clientVersion, Endian.little)
        ..setUint32(8, _operationDetach, Endian.little)
        ..setUint64(16, clientId, Endian.little);
      view.performCustomOperation(payload);
    }
    unawaited(_events.close());
  }

  void _requestDrain() {
    if (_disposed || _drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _drainScheduled = false;
    if (_disposed) return;
    final Arena arena = Arena();
    try {
      final Pointer<Uint32> required = arena<Uint32>();
      var processed = 0;
      while (processed < _maximumDrainBatch) {
        required.value = 0;
        final int query = _textInputTakeEvent(clientId, nullptr, 0, required);
        if (query == _statusNotFound) return;
        if (query != _statusBufferTooSmall ||
            required.value < _eventHeaderBytes ||
            required.value > maximumPacketBytes) {
          throw TerminalTextInputException(
            'invalid event size query status=$query bytes=${required.value}',
          );
        }
        final Pointer<Uint8> output = arena<Uint8>(required.value);
        final int status = _textInputTakeEvent(
          clientId,
          output,
          required.value,
          required,
        );
        if (status != _statusOk) {
          throw TerminalTextInputException(
            'event copy failed status=$status bytes=${required.value}',
          );
        }
        final TerminalTextInputEvent event = _decoder.decode(
          Uint8List.fromList(output.asTypedList(required.value)),
        );
        _events.add(event);
        processed++;
      }
      _requestDrain();
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    } finally {
      arena.releaseAll();
    }
  }

  void _requireLive() {
    if (_disposed) throw StateError('TerminalTextInputClient is disposed');
  }

  static void _initializeNotification() {
    if (_notificationInitialized) return;
    final int status = _textInputSetNotifyCallback(
      _textInputNotification.nativeFunction,
    );
    if (status != _statusOk) {
      throw TerminalTextInputException(
        'notification initialization failed status=$status',
      );
    }
    _notificationInitialized = true;
  }
}

typedef _TextInputNotifyNative = Void Function(Uint64 clientId);

void _dispatchTextInputNotification(int clientId) {
  TerminalTextInputClient._clients[clientId]?._requestDrain();
}

final NativeCallable<_TextInputNotifyNative> _textInputNotification =
    NativeCallable<_TextInputNotifyNative>.listener(
      _dispatchTextInputNotification,
    );

@Native<
  Int32 Function(Pointer<NativeFunction<_TextInputNotifyNative>> callback)
>(symbol: 'dtr_text_input_set_notify_callback', assetId: _textInputAssetId)
external int _textInputSetNotifyCallback(
  Pointer<NativeFunction<_TextInputNotifyNative>> callback,
);

@Native<
  Int32 Function(
    Uint64 clientId,
    Pointer<Uint8> output,
    Uint32 outputCapacity,
    Pointer<Uint32> outputRequired,
  )
>(symbol: 'dtr_text_input_take_event', assetId: _textInputAssetId)
external int _textInputTakeEvent(
  int clientId,
  Pointer<Uint8> output,
  int outputCapacity,
  Pointer<Uint32> outputRequired,
);

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_text_input_client_count',
  assetId: _textInputAssetId,
)
external int debugLiveTerminalTextInputClientCount();
