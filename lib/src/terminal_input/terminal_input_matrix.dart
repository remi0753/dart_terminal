import 'dart:convert';

import 'terminal_key_event.dart';

enum TerminalInputMatrixCategory {
  us,
  jis,
  deadKey,
  cjk,
  emoji,
  unicodeHex,
  keyRepeat,
}

enum TerminalInputMatrixDelivery { committedText, rawKey }

final class TerminalInputMatrixRow {
  TerminalInputMatrixRow.committed({
    required this.id,
    required this.category,
    required String text,
  }) : delivery = TerminalInputMatrixDelivery.committedText,
       committedText = text,
       keyEvent = null,
       repetitions = 1,
       expectedBytesPerEvent = List<int>.unmodifiable(utf8.encode(text)) {
    _validate();
  }

  TerminalInputMatrixRow.raw({
    required this.id,
    required this.category,
    required TerminalKeyEvent event,
    this.repetitions = 1,
    required Iterable<int> expectedBytesPerEvent,
  }) : delivery = TerminalInputMatrixDelivery.rawKey,
       committedText = null,
       keyEvent = event,
       expectedBytesPerEvent = List<int>.unmodifiable(expectedBytesPerEvent) {
    _validate();
  }

  final String id;
  final TerminalInputMatrixCategory category;
  final TerminalInputMatrixDelivery delivery;
  final String? committedText;
  final TerminalKeyEvent? keyEvent;
  final int repetitions;
  final List<int> expectedBytesPerEvent;

  int get eventCount => repetitions;
  int get expectedByteCount => expectedBytesPerEvent.length * repetitions;

  void _validate() {
    if (id.isEmpty ||
        id.length > 64 ||
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a stable kebab-case ID');
    }
    if (repetitions <= 0 || repetitions > 32) {
      throw RangeError.range(repetitions, 1, 32, 'repetitions');
    }
    if (expectedBytesPerEvent.isEmpty ||
        expectedBytesPerEvent.length >
            TerminalInputLimits.maximumEncodedBytesPerKeyEvent) {
      throw RangeError.range(
        expectedBytesPerEvent.length,
        1,
        TerminalInputLimits.maximumEncodedBytesPerKeyEvent,
        'expectedBytesPerEvent.length',
      );
    }
    for (final int byte in expectedBytesPerEvent) {
      RangeError.checkValueInInterval(byte, 0, 0xff, 'expected byte');
    }
    switch (delivery) {
      case TerminalInputMatrixDelivery.committedText:
        if (committedText == null ||
            committedText!.isEmpty ||
            keyEvent != null ||
            repetitions != 1) {
          throw ArgumentError('committed matrix row has inconsistent fields');
        }
      case TerminalInputMatrixDelivery.rawKey:
        if (committedText != null || keyEvent == null) {
          throw ArgumentError('raw matrix row has inconsistent fields');
        }
    }
  }
}

/// Immutable fixed corpus used by native event and real-PTY input acceptance.
final class TerminalInputAcceptanceMatrix {
  TerminalInputAcceptanceMatrix(
    Iterable<TerminalInputMatrixRow> rows, {
    bool requireAllCategories = true,
  }) : rows = List<TerminalInputMatrixRow>.unmodifiable(rows) {
    if (this.rows.isEmpty || this.rows.length > maximumRows) {
      throw RangeError.range(this.rows.length, 1, maximumRows, 'rows.length');
    }
    final Set<String> ids = <String>{};
    final Set<TerminalInputMatrixCategory> categories =
        <TerminalInputMatrixCategory>{};
    var bytes = 0;
    for (final TerminalInputMatrixRow row in this.rows) {
      if (!ids.add(row.id)) {
        throw ArgumentError.value(row.id, 'rows', 'duplicate matrix row ID');
      }
      categories.add(row.category);
      bytes += row.expectedByteCount;
      if (bytes > maximumExpectedBytes) {
        throw RangeError.range(
          bytes,
          1,
          maximumExpectedBytes,
          'expected byte count',
        );
      }
    }
    if (requireAllCategories &&
        categories.length != TerminalInputMatrixCategory.values.length) {
      throw ArgumentError('input acceptance matrix is missing a category');
    }
  }

  static const int version = 2;
  static const int maximumRows = 32;
  static const int maximumExpectedBytes = 4096;

  static final TerminalInputAcceptanceMatrix standard =
      TerminalInputAcceptanceMatrix(<TerminalInputMatrixRow>[
        TerminalInputMatrixRow.committed(
          id: 'us-lowercase',
          category: TerminalInputMatrixCategory.us,
          text: 'a',
        ),
        TerminalInputMatrixRow.committed(
          id: 'us-uppercase',
          category: TerminalInputMatrixCategory.us,
          text: 'A',
        ),
        TerminalInputMatrixRow.committed(
          id: 'jis-yen',
          category: TerminalInputMatrixCategory.jis,
          text: '¥',
        ),
        TerminalInputMatrixRow.committed(
          id: 'jis-underscore',
          category: TerminalInputMatrixCategory.jis,
          text: '_',
        ),
        TerminalInputMatrixRow.committed(
          id: 'dead-key-acute',
          category: TerminalInputMatrixCategory.deadKey,
          text: 'é',
        ),
        TerminalInputMatrixRow.committed(
          id: 'cjk-chinese',
          category: TerminalInputMatrixCategory.cjk,
          text: '中文',
        ),
        TerminalInputMatrixRow.committed(
          id: 'cjk-japanese',
          category: TerminalInputMatrixCategory.cjk,
          text: '日本語',
        ),
        TerminalInputMatrixRow.committed(
          id: 'cjk-korean',
          category: TerminalInputMatrixCategory.cjk,
          text: '한글',
        ),
        TerminalInputMatrixRow.committed(
          id: 'emoji-zwj',
          category: TerminalInputMatrixCategory.emoji,
          text: '👩‍💻',
        ),
        TerminalInputMatrixRow.committed(
          id: 'unicode-hex-command',
          category: TerminalInputMatrixCategory.unicodeHex,
          text: '⌘',
        ),
        TerminalInputMatrixRow.raw(
          id: 'repeat-initial',
          category: TerminalInputMatrixCategory.keyRepeat,
          event: _arrowRight,
          expectedBytesPerEvent: const <int>[0x1b, 0x5b, 0x43],
        ),
        TerminalInputMatrixRow.raw(
          id: 'repeat-held',
          category: TerminalInputMatrixCategory.keyRepeat,
          event: _repeatedArrowRight,
          repetitions: 2,
          expectedBytesPerEvent: const <int>[0x1b, 0x5b, 0x43],
        ),
        TerminalInputMatrixRow.raw(
          id: 'option-word-left',
          category: TerminalInputMatrixCategory.us,
          event: _optionArrowLeft,
          expectedBytesPerEvent: const <int>[0x1b, 0x62],
        ),
        TerminalInputMatrixRow.raw(
          id: 'option-word-right',
          category: TerminalInputMatrixCategory.us,
          event: _optionArrowRight,
          expectedBytesPerEvent: const <int>[0x1b, 0x66],
        ),
      ]);

  static const TerminalKeyEvent _arrowRight = TerminalKeyEvent(
    physicalKey: TerminalPhysicalKey.arrowRight,
    text: '\uf703',
    unmodifiedText: '\uf703',
    modifiers: TerminalKeyModifiers(function: true),
  );
  static const TerminalKeyEvent _repeatedArrowRight = TerminalKeyEvent(
    physicalKey: TerminalPhysicalKey.arrowRight,
    text: '\uf703',
    unmodifiedText: '\uf703',
    modifiers: TerminalKeyModifiers(function: true),
    isRepeat: true,
  );
  static const TerminalKeyEvent _optionArrowLeft = TerminalKeyEvent(
    physicalKey: TerminalPhysicalKey.arrowLeft,
    text: '\uf702',
    unmodifiedText: '\uf702',
    modifiers: TerminalKeyModifiers(option: true, function: true),
  );
  static const TerminalKeyEvent _optionArrowRight = TerminalKeyEvent(
    physicalKey: TerminalPhysicalKey.arrowRight,
    text: '\uf703',
    unmodifiedText: '\uf703',
    modifiers: TerminalKeyModifiers(option: true, function: true),
  );

  final List<TerminalInputMatrixRow> rows;

  int get eventCount => rows.fold<int>(
    0,
    (int count, TerminalInputMatrixRow row) => count + row.eventCount,
  );

  List<int> get expectedBytes => List<int>.unmodifiable(<int>[
    for (final TerminalInputMatrixRow row in rows)
      for (int repetition = 0; repetition < row.repetitions; repetition++)
        ...row.expectedBytesPerEvent,
  ]);

  String get expectedHex => expectedBytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
