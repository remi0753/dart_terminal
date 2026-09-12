import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

void runTextInputTests() {
  _testEventFamiliesAndGenerations();
  _testMalformedPacketsAreAtomic();
  _testPublicLimitsAndRanges();
}

void _testEventFamiliesAndGenerations() {
  final TerminalTextInputPacketDecoder decoder = TerminalTextInputPacketDecoder(
    41,
  );
  final TerminalTextInputKeyEvent key = decoder.decode(
    _packet(
      generation: 1,
      kind: 1,
      flags: 1,
      keyCode: 126,
      modifiers: ModifierKeys.functionBit,
      text: '\uf700',
      unmodifiedText: '\uf700',
    ),
  ) as TerminalTextInputKeyEvent;
  _expect(
    key.kind == TerminalTextInputKeyKind.down &&
        key.keyCode == 126 &&
        key.modifiers.function &&
        key.isRepeat &&
        key.characters == '\uf700' &&
        key.charactersIgnoringModifiers == '\uf700',
    'raw key packet preserves independent fields',
  );

  final TerminalTextInputPreeditEvent preedit = decoder.decode(
    _packet(
      generation: 3,
      kind: 3,
      text: 'に😀ほん',
      selection: const TerminalTextInputRange(3, 0),
      replacement: const TerminalTextInputRange(8, 3),
    ),
  ) as TerminalTextInputPreeditEvent;
  _expect(
    preedit.text == 'に😀ほん' &&
        preedit.selection == const TerminalTextInputRange(3, 0) &&
        preedit.replacement == const TerminalTextInputRange(8, 3),
    'preedit permits a generation gap after native coalescing',
  );
  final TerminalTextInputCommitEvent commit = decoder.decode(
    _packet(
      generation: 4,
      kind: 4,
      text: '日本語',
      replacement: const TerminalTextInputRange(8, 3),
    ),
  ) as TerminalTextInputCommitEvent;
  _expect(
    commit.text == '日本語' &&
        commit.replacement == const TerminalTextInputRange(8, 3),
    'commit carries text and replacement metadata',
  );
  _expect(
    decoder.decode(_packet(generation: 5, kind: 5))
        is TerminalTextInputCancelEvent,
    'cancel has a distinct typed event',
  );
  _expect(
    decoder.decode(_packet(generation: 6, kind: 6))
        is TerminalTextInputOverflowEvent,
    'overflow has a distinct typed event',
  );
  _expect(decoder.lastGeneration == 6, 'decoder publishes newest generation');
}

void _testMalformedPacketsAreAtomic() {
  final TerminalTextInputPacketDecoder decoder = TerminalTextInputPacketDecoder(
    41,
  );
  final Uint8List valid = _packet(
    generation: 1,
    kind: 3,
    text: '😀',
    selection: const TerminalTextInputRange(2, 0),
  );
  final Uint8List wrongMagic = Uint8List.fromList(valid);
  ByteData.sublistView(wrongMagic).setUint32(0, 0, Endian.little);
  _expectFormat(() => decoder.decode(wrongMagic), 'wrong packet magic');

  final Uint8List splitSurrogate = Uint8List.fromList(valid);
  ByteData.sublistView(splitSurrogate)
    ..setUint32(72, 1, Endian.little)
    ..setUint32(76, 0, Endian.little);
  _expectFormat(
    () => decoder.decode(splitSurrogate),
    'selection splitting a surrogate pair',
  );

  final Uint8List noncanonicalRegion = Uint8List.fromList(valid);
  ByteData.sublistView(noncanonicalRegion).setUint32(56, 97, Endian.little);
  _expectFormat(
    () => decoder.decode(noncanonicalRegion),
    'noncanonical packet regions',
  );

  final Uint8List reserved = Uint8List.fromList(valid);
  ByteData.sublistView(reserved).setUint32(88, 1, Endian.little);
  _expectFormat(() => decoder.decode(reserved), 'changed reserved field');

  final Uint8List malformedUtf8 = _packet(generation: 1, kind: 4, text: 'a');
  malformedUtf8[96] = 0xff;
  _expectFormat(() => decoder.decode(malformedUtf8), 'malformed UTF-8');

  final Uint8List inconsistentCancel = _packet(
    generation: 1,
    kind: 5,
    text: 'x',
  );
  _expectFormat(
    () => decoder.decode(inconsistentCancel),
    'cancel carrying unexpected text',
  );

  final TerminalTextInputPreeditEvent accepted =
      decoder.decode(valid) as TerminalTextInputPreeditEvent;
  _expect(
    accepted.text == '😀' && decoder.lastGeneration == 1,
    'malformed packets do not consume the expected generation',
  );
  _expectFormat(() => decoder.decode(valid), 'duplicate event generation');
}

void _testPublicLimitsAndRanges() {
  _expect(
    TerminalTextInputClient.maximumTextBytes == 64 * 1024 &&
        TerminalTextInputClient.maximumQueuedEvents == 256 &&
        TerminalTextInputClient.maximumQueueBytes == 1024 * 1024 &&
        TerminalTextInputClient.maximumPacketBytes == 96 + 2 * 64 * 1024,
    'Dart limits reproduce the native bounded transport contract',
  );
  _expect(
    !TerminalTextInputRange.notFound.isFound &&
        const TerminalTextInputRange(0, 0).isFound,
    'not-found remains distinct from an empty found range',
  );
  _expectRange(
    () => TerminalTextInputPacketDecoder(0),
    'zero decoder client ID',
  );
}

Uint8List _packet({
  required int generation,
  required int kind,
  int flags = 0,
  int keyCode = 0,
  int modifiers = 0,
  String text = '',
  String unmodifiedText = '',
  TerminalTextInputRange selection = TerminalTextInputRange.notFound,
  TerminalTextInputRange replacement = TerminalTextInputRange.notFound,
}) {
  final List<int> textBytes = utf8.encode(text);
  final List<int> unmodifiedBytes = utf8.encode(unmodifiedText);
  final Uint8List bytes = Uint8List(
    96 + textBytes.length + unmodifiedBytes.length,
  );
  final ByteData data = ByteData.sublistView(bytes)
    ..setUint32(0, 0x49545444, Endian.little)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 96, Endian.little)
    ..setUint32(12, bytes.length, Endian.little)
    ..setUint64(16, 41, Endian.little)
    ..setUint64(24, generation, Endian.little)
    ..setUint64(32, 123, Endian.little)
    ..setUint32(40, kind, Endian.little)
    ..setUint32(44, flags, Endian.little)
    ..setUint32(48, keyCode, Endian.little)
    ..setUint32(52, modifiers, Endian.little)
    ..setUint32(56, 96, Endian.little)
    ..setUint32(60, textBytes.length, Endian.little)
    ..setUint32(64, 96 + textBytes.length, Endian.little)
    ..setUint32(68, unmodifiedBytes.length, Endian.little);
  _writeRange(data, 72, selection);
  _writeRange(data, 80, replacement);
  bytes.setRange(96, 96 + textBytes.length, textBytes);
  bytes.setRange(96 + textBytes.length, bytes.length, unmodifiedBytes);
  return bytes;
}

void _writeRange(ByteData data, int offset, TerminalTextInputRange range) {
  data
    ..setUint32(
      offset,
      range.isFound ? range.location : 0xffffffff,
      Endian.little,
    )
    ..setUint32(offset + 4, range.length, Endian.little);
}

void _expectFormat(void Function() callback, String description) {
  try {
    callback();
  } on FormatException {
    return;
  }
  throw StateError('Expected FormatException: $description');
}

void _expectRange(void Function() callback, String description) {
  try {
    callback();
  } on RangeError {
    return;
  }
  throw StateError('Expected RangeError: $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError(description);
}
