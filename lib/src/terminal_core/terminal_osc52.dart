import 'dart:typed_data';

import 'terminal_reply.dart';
import 'vt_parser.dart';

enum TerminalOsc52Operation { read, write, clear }

/// One immutable, parser-bounded OSC 52 request.
///
/// This value contains protocol data only. It deliberately has no clipboard,
/// application, or native authority.
final class TerminalOsc52Request {
  const TerminalOsc52Request._({
    required this.operation,
    required this.selection,
    required this.encodedData,
    required this.terminator,
  });

  final TerminalOsc52Operation operation;
  final String selection;
  final String? encodedData;
  final VtStringTerminator terminator;

  /// macOS exposes the xterm `c` selection through its general pasteboard.
  bool get targetsClipboard => selection.codeUnits.contains(0x63);
}

typedef TerminalOsc52RequestHandler = bool Function(
  TerminalOsc52Request request,
);

abstract final class TerminalOsc52Protocol {
  static const int maximumStringPayloadBytes = 4096;
  static const int maximumSelectionBytes =
      TerminalReplyEncoder.maximumOsc52SelectionBytes;

  /// Parses one already-captured OSC 52 payload without retaining parser state.
  ///
  /// A syntactically valid non-query payload that is not canonical RFC 4648
  /// base64 is the xterm clear operation. `null` means the OSC 52 envelope or
  /// selection itself is invalid.
  static TerminalOsc52Request? parse(
    VtStringSequence sequence,
    int selectionStart, {
    required bool hasPayload,
  }) {
    if (!hasPayload ||
        selectionStart < 0 ||
        sequence.payloadLength > maximumStringPayloadBytes) {
      return null;
    }
    final int selectionEnd = _findByte(sequence, selectionStart, 0x3b);
    final int selectionLength = selectionEnd - selectionStart;
    if (selectionEnd >= sequence.payloadLength ||
        selectionLength > maximumSelectionBytes) {
      return null;
    }
    final Uint8List selectionBytes = Uint8List(selectionLength);
    for (int index = 0; index < selectionLength; index++) {
      final int value = sequence.payloadByteAt(selectionStart + index);
      if (!_isSelectionByte(value)) return null;
      selectionBytes[index] = value;
    }

    final int dataStart = selectionEnd + 1;
    final int dataLength = sequence.payloadLength - dataStart;
    final String selection = String.fromCharCodes(selectionBytes);
    if (dataLength == 1 && sequence.payloadByteAt(dataStart) == 0x3f) {
      return TerminalOsc52Request._(
        operation: TerminalOsc52Operation.read,
        selection: selection,
        encodedData: null,
        terminator: sequence.terminator,
      );
    }
    if (dataLength > 0 && _isCanonicalBase64(sequence, dataStart, dataLength)) {
      return TerminalOsc52Request._(
        operation: TerminalOsc52Operation.write,
        selection: selection,
        encodedData: String.fromCharCodes(
          List<int>.generate(
            dataLength,
            (int index) => sequence.payloadByteAt(dataStart + index),
            growable: false,
          ),
        ),
        terminator: sequence.terminator,
      );
    }
    return TerminalOsc52Request._(
      operation: TerminalOsc52Operation.clear,
      selection: selection,
      encodedData: null,
      terminator: sequence.terminator,
    );
  }

  static int _findByte(VtStringSequence sequence, int start, int target) {
    for (int index = start; index < sequence.payloadLength; index++) {
      if (sequence.payloadByteAt(index) == target) return index;
    }
    return sequence.payloadLength;
  }

  static bool _isSelectionByte(int value) =>
      value == 0x63 ||
      value == 0x70 ||
      value == 0x71 ||
      value == 0x73 ||
      (value >= 0x30 && value <= 0x37);

  static bool _isCanonicalBase64(
    VtStringSequence sequence,
    int start,
    int length,
  ) {
    if (length == 0 || length % 4 != 0) return false;
    var padding = 0;
    if (sequence.payloadByteAt(start + length - 1) == 0x3d) padding++;
    if (length > 1 && sequence.payloadByteAt(start + length - 2) == 0x3d) {
      padding++;
    }
    final int unpaddedEnd = start + length - padding;
    for (int index = start; index < unpaddedEnd; index++) {
      final int value = sequence.payloadByteAt(index);
      final bool alphabet =
          (value >= 0x41 && value <= 0x5a) ||
          (value >= 0x61 && value <= 0x7a) ||
          (value >= 0x30 && value <= 0x39) ||
          value == 0x2b ||
          value == 0x2f;
      if (!alphabet) return false;
    }
    for (int index = unpaddedEnd; index < start + length; index++) {
      if (sequence.payloadByteAt(index) != 0x3d) return false;
    }
    if (padding == 0) return true;
    if (unpaddedEnd == start) return false;
    return padding == 1
        ? (length >= 4 && (unpaddedEnd - start) % 4 == 3)
        : (length >= 4 && (unpaddedEnd - start) % 4 == 2);
  }
}
