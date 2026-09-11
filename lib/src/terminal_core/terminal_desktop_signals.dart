import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'terminal_session_metadata.dart';
import 'vt_parser.dart';

/// Wire protocol that produced a bounded desktop-notification request.
enum TerminalDesktopNotificationProtocol { legacyOsc9, kittyOsc99 }

/// Immutable, plain-text-only request awaiting policy and native admission.
final class TerminalDesktopNotificationRequest {
  const TerminalDesktopNotificationRequest({
    required this.protocol,
    required this.title,
    required this.body,
    this.identifier,
  });

  final TerminalDesktopNotificationProtocol protocol;
  final String title;
  final String body;
  final String? identifier;
}

/// Bounded parser state for legacy OSC 9 and the selected OSC 99 subset.
///
/// This model has no native authority. It retains at most [maximumQueuedRequests]
/// complete requests and [maximumPendingRequests] incomplete OSC 99 messages.
final class TerminalDesktopNotificationModel {
  static const int maximumPlainPayloadBytes = 2048;
  static const int maximumMetadataBytes = 512;
  static const int maximumIdentifierBytes = 64;
  static const int maximumAggregateTitleBytes = 2048;
  static const int maximumAggregateBodyBytes = 2048;
  static const int maximumPendingRequests = 8;
  static const int maximumQueuedRequests = 8;

  final LinkedHashMap<String, _PendingNotification> _pending =
      LinkedHashMap<String, _PendingNotification>();
  final ListQueue<TerminalDesktopNotificationRequest> _queued =
      ListQueue<TerminalDesktopNotificationRequest>();
  int _generation = 1;
  int _droppedRequestCount = 0;

  int get generation => _generation;
  int get pendingRequestCount => _pending.length;
  int get queuedRequestCount => _queued.length;
  int get droppedRequestCount => _droppedRequestCount;
  TerminalDesktopNotificationRequest? get nextRequest =>
      _queued.isEmpty ? null : _queued.first;

  List<TerminalDesktopNotificationRequest> get queuedRequests =>
      List<TerminalDesktopNotificationRequest>.unmodifiable(_queued);

  /// Applies an iTerm2-style OSC 9 body after the command delimiter.
  bool applyLegacyOsc9(VtStringSequence sequence, int start) {
    final int length = sequence.payloadLength - start;
    if (length < 0 || length > maximumPlainPayloadBytes) return false;
    final String? body = _decodeSafeText(sequence, start, length);
    if (body == null) return false;
    if (body.isNotEmpty) {
      _enqueue(
        TerminalDesktopNotificationRequest(
          protocol: TerminalDesktopNotificationProtocol.legacyOsc9,
          title: '',
          body: body,
        ),
      );
    }
    return true;
  }

  /// Applies the plain UTF-8 title/body and `i`/`d` subset of Kitty OSC 99.
  bool applyKittyOsc99(VtStringSequence sequence, int start) {
    final int separator = _findByte(sequence, start, 0x3b);
    if (separator < start || separator >= sequence.payloadLength) return false;
    final int metadataLength = separator - start;
    if (metadataLength > maximumMetadataBytes) return false;
    final _KittyNotificationMetadata? metadata = _parseKittyMetadata(
      sequence,
      start,
      metadataLength,
    );
    if (metadata == null || metadata.encoded) return false;
    final int payloadStart = separator + 1;
    final int payloadLength = sequence.payloadLength - payloadStart;
    if (payloadLength > maximumPlainPayloadBytes) return false;
    final String? payload = _decodeSafeText(
      sequence,
      payloadStart,
      payloadLength,
    );
    if (payload == null) return false;

    final String? identifier = metadata.identifier;
    if (!metadata.done && identifier == null) return false;
    _PendingNotification pending;
    if (identifier != null && _pending.containsKey(identifier)) {
      pending = _pending[identifier]!;
    } else {
      if (!metadata.done && _pending.length >= maximumPendingRequests) {
        return false;
      }
      pending = _PendingNotification();
    }
    if (!pending.append(metadata.payload, payload, payloadLength)) {
      if (identifier != null) _pending.remove(identifier);
      return false;
    }
    if (!metadata.done) {
      _pending[identifier!] = pending;
      _generation++;
      return true;
    }
    if (identifier != null) _pending.remove(identifier);
    if (pending.title.isNotEmpty || pending.body.isNotEmpty) {
      _enqueue(
        TerminalDesktopNotificationRequest(
          protocol: TerminalDesktopNotificationProtocol.kittyOsc99,
          title: pending.title,
          body: pending.body,
          identifier: identifier,
        ),
      );
    } else {
      _generation++;
    }
    return true;
  }

  TerminalDesktopNotificationRequest? takeNextRequest() {
    if (_queued.isEmpty) return null;
    final TerminalDesktopNotificationRequest result = _queued.removeFirst();
    _generation++;
    return result;
  }

  void reset() {
    if (_pending.isEmpty && _queued.isEmpty) return;
    _pending.clear();
    _queued.clear();
    _generation++;
  }

  void _enqueue(TerminalDesktopNotificationRequest request) {
    if (_queued.length >= maximumQueuedRequests) {
      if (_droppedRequestCount < 0x7fffffff) _droppedRequestCount++;
    } else {
      _queued.addLast(request);
    }
    _generation++;
  }

  static _KittyNotificationMetadata? _parseKittyMetadata(
    VtStringSequence sequence,
    int start,
    int length,
  ) {
    String? identifier;
    var done = true;
    var encoded = false;
    var payload = _KittyNotificationPayload.title;
    var sawIdentifier = false;
    var sawDone = false;
    var sawEncoded = false;
    var sawPayload = false;
    final int end = start + length;
    int partStart = start;
    while (partStart <= end) {
      final int partEnd = _findByte(sequence, partStart, 0x3a, end: end);
      int trimmedStart = partStart;
      int trimmedEnd = partEnd;
      while (trimmedStart < trimmedEnd &&
          sequence.payloadByteAt(trimmedStart) == 0x20) {
        trimmedStart++;
      }
      while (trimmedEnd > trimmedStart &&
          sequence.payloadByteAt(trimmedEnd - 1) == 0x20) {
        trimmedEnd--;
      }
      if (trimmedStart < trimmedEnd) {
        final int equals = _findByte(
          sequence,
          trimmedStart,
          0x3d,
          end: trimmedEnd,
        );
        if (equals == trimmedEnd || equals == trimmedStart) return null;
        int valueStart = equals + 1;
        int valueEnd = trimmedEnd;
        while (valueStart < valueEnd &&
            sequence.payloadByteAt(valueStart) == 0x20) {
          valueStart++;
        }
        while (valueEnd > valueStart &&
            sequence.payloadByteAt(valueEnd - 1) == 0x20) {
          valueEnd--;
        }
        final int keyLength = equals - trimmedStart;
        if (keyLength == 1) {
          switch (sequence.payloadByteAt(trimmedStart)) {
            case 0x69: // i
              if (sawIdentifier) return null;
              sawIdentifier = true;
              final int valueLength = valueEnd - valueStart;
              if (valueLength < 1 ||
                  valueLength > maximumIdentifierBytes ||
                  !_isIdentifier(sequence, valueStart, valueEnd)) {
                return null;
              }
              identifier = _decodeAscii(sequence, valueStart, valueEnd);
            case 0x64: // d
              if (sawDone || valueEnd - valueStart != 1) return null;
              sawDone = true;
              final int value = sequence.payloadByteAt(valueStart);
              if (value != 0x30 && value != 0x31) return null;
              done = value == 0x31;
            case 0x65: // e
              if (sawEncoded || valueEnd - valueStart != 1) return null;
              sawEncoded = true;
              final int value = sequence.payloadByteAt(valueStart);
              if (value != 0x30 && value != 0x31) return null;
              encoded = value == 0x31;
            case 0x70: // p
              if (sawPayload) return null;
              sawPayload = true;
              if (_asciiEquals(sequence, valueStart, valueEnd, 'title')) {
                payload = _KittyNotificationPayload.title;
              } else if (_asciiEquals(sequence, valueStart, valueEnd, 'body')) {
                payload = _KittyNotificationPayload.body;
              } else {
                return null;
              }
            case 0x61: // a
            case 0x63: // c
            case 0x66: // f
            case 0x67: // g
            case 0x6e: // n
            case 0x6f: // o
            case 0x73: // s
            case 0x74: // t
            case 0x75: // u
            case 0x77: // w
              return null;
          }
        }
      }
      if (partEnd == end) break;
      partStart = partEnd + 1;
    }
    return _KittyNotificationMetadata(
      identifier: identifier,
      done: done,
      encoded: encoded,
      payload: payload,
    );
  }

  static int _findByte(
    VtStringSequence sequence,
    int start,
    int byte, {
    int? end,
  }) {
    final int limit = end ?? sequence.payloadLength;
    for (int index = start; index < limit; index++) {
      if (sequence.payloadByteAt(index) == byte) return index;
    }
    return limit;
  }

  static bool _isIdentifier(VtStringSequence sequence, int start, int end) {
    for (int index = start; index < end; index++) {
      final int byte = sequence.payloadByteAt(index);
      final bool valid =
          (byte >= 0x30 && byte <= 0x39) ||
          (byte >= 0x41 && byte <= 0x5a) ||
          (byte >= 0x61 && byte <= 0x7a) ||
          byte == 0x2d ||
          byte == 0x2e ||
          byte == 0x2b ||
          byte == 0x5f;
      if (!valid) return false;
    }
    return true;
  }

  static String _decodeAscii(VtStringSequence sequence, int start, int end) =>
      String.fromCharCodes(
        List<int>.generate(end - start, (int index) {
          return sequence.payloadByteAt(start + index);
        }, growable: false),
      );

  static bool _asciiEquals(
    VtStringSequence sequence,
    int start,
    int end,
    String expected,
  ) {
    if (end - start != expected.length) return false;
    for (int index = 0; index < expected.length; index++) {
      if (sequence.payloadByteAt(start + index) != expected.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }

  static String? _decodeSafeText(
    VtStringSequence sequence,
    int start,
    int length,
  ) {
    final Uint8List bytes = Uint8List(length);
    for (int index = 0; index < length; index++) {
      bytes[index] = sequence.payloadByteAt(start + index);
    }
    try {
      final String value = utf8.decode(bytes, allowMalformed: false);
      return TerminalSessionMetadata.isSafeDisplayText(
            value,
            maximumUtf8Bytes: maximumPlainPayloadBytes,
          )
          ? value
          : null;
    } on FormatException {
      return null;
    }
  }
}

enum _KittyNotificationPayload { title, body }

final class _KittyNotificationMetadata {
  const _KittyNotificationMetadata({
    required this.identifier,
    required this.done,
    required this.encoded,
    required this.payload,
  });

  final String? identifier;
  final bool done;
  final bool encoded;
  final _KittyNotificationPayload payload;
}

final class _PendingNotification {
  String title = '';
  String body = '';
  int titleBytes = 0;
  int bodyBytes = 0;

  bool append(_KittyNotificationPayload target, String value, int byteLength) {
    switch (target) {
      case _KittyNotificationPayload.title:
        if (titleBytes + byteLength >
            TerminalDesktopNotificationModel.maximumAggregateTitleBytes) {
          return false;
        }
        title += value;
        titleBytes += byteLength;
      case _KittyNotificationPayload.body:
        if (bodyBytes + byteLength >
            TerminalDesktopNotificationModel.maximumAggregateBodyBytes) {
          return false;
        }
        body += value;
        bodyBytes += byteLength;
    }
    return true;
  }
}

/// ConEmu OSC 9;4 progress state projected per terminal session.
enum TerminalProgressState { removed, set, error, indeterminate, paused }

/// Immutable bounded progress update.
final class TerminalProgressUpdate {
  const TerminalProgressUpdate({required this.state, required this.percent});

  final TerminalProgressState state;
  final int? percent;
}

final class TerminalProgressModel {
  TerminalProgressUpdate _value = const TerminalProgressUpdate(
    state: TerminalProgressState.removed,
    percent: null,
  );
  int _generation = 1;

  TerminalProgressUpdate get value => _value;
  int get generation => _generation;

  static TerminalProgressUpdate? parseOsc9(
    VtStringSequence sequence,
    int start,
  ) {
    final int length = sequence.payloadLength - start;
    if (length < 3 ||
        sequence.payloadByteAt(start) != 0x34 ||
        sequence.payloadByteAt(start + 1) != 0x3b) {
      return null;
    }
    final TerminalProgressState? state = switch (sequence.payloadByteAt(
      start + 2,
    )) {
      0x30 => TerminalProgressState.removed,
      0x31 => TerminalProgressState.set,
      0x32 => TerminalProgressState.error,
      0x33 => TerminalProgressState.indeterminate,
      0x34 => TerminalProgressState.paused,
      _ => null,
    };
    if (state == null) return null;
    if (length == 3) {
      return TerminalProgressUpdate(
        state: state,
        percent: state == TerminalProgressState.set ? 0 : null,
      );
    }
    if (sequence.payloadByteAt(start + 3) != 0x3b) return null;
    final int valueLength = length - 4;
    if (valueLength == 0) {
      return TerminalProgressUpdate(state: state, percent: null);
    }
    if (state == TerminalProgressState.removed ||
        state == TerminalProgressState.indeterminate ||
        valueLength > 3) {
      return null;
    }
    var percent = 0;
    for (int index = start + 4; index < sequence.payloadLength; index++) {
      final int byte = sequence.payloadByteAt(index);
      if (byte < 0x30 || byte > 0x39) return null;
      percent = percent * 10 + byte - 0x30;
    }
    return TerminalProgressUpdate(state: state, percent: percent.clamp(0, 100));
  }

  void apply(TerminalProgressUpdate update) {
    if (_value.state == update.state && _value.percent == update.percent)
      return;
    _value = update;
    _generation++;
  }

  void reset() {
    if (_value.state == TerminalProgressState.removed &&
        _value.percent == null) {
      return;
    }
    _value = const TerminalProgressUpdate(
      state: TerminalProgressState.removed,
      percent: null,
    );
    _generation++;
  }
}
