import 'dart:convert';
import 'dart:typed_data';

abstract final class TerminalNotesLimits {
  static const int protocolVersion = 1;
  static const int headerBytes = 128;
  static const int cardRecordBytes = 32;
  static const int maximumCards = 64;
  static const int maximumMaterializedCards = 32;
  static const int maximumCardBodyUtf8Bytes = 4096;
  static const int maximumAggregateBodyUtf8Bytes = 256 * 1024;
  static const int maximumContextNotes = 128;
  static const int maximumDetachedNotes = 2048;
  static const int maximumUnsigned32 = 0xffffffff;
  static const int maximumSignedGeneration = 0x7fffffffffffffff;
  static final BigInt maximumUnsigned64 = (BigInt.one << 64) - BigInt.one;
}

enum TerminalNotesVisibility { collapsed, expanded }

enum TerminalNotesLocale { english, japanese }

enum TerminalNotesColor { neutral, yellow, blue, green, pink, purple }

enum TerminalNotesStatus { active, resolved }

enum TerminalNotesTriggerKind { onReturn, atNextPrompt }

enum TerminalNotesTriggerPhase {
  onReturnArmedHere,
  onReturnArmedAway,
  atNextPromptWaitingCommand,
  atNextPromptWaitingEnd,
  atNextPromptWaitingPromptStart,
  atNextPromptWaitingInput,
  due,
  suspended,
}

enum TerminalNotesFeatureState {
  disabled,
  starting,
  available,
  inUseByOtherProcess,
  recoveryRequired,
  incompatibleStore,
  unavailable,
}

enum TerminalNotesSurfaceState {
  attaching,
  ready,
  tooSmall,
  nativeUnavailable,
  disposed,
}

enum TerminalNotesCollectionSection { current, detached }

enum TerminalNotesEditorMode { inactive, creating, editing }

enum TerminalNotesMessageKey {
  none,
  paneTooSmall,
  nativeUnavailable,
  projectionRejected,
  storeUnavailable,
  recoveryRequired,
}

final class TerminalNotesProjectionException implements Exception {
  const TerminalNotesProjectionException(this.reason);

  final String reason;

  @override
  String toString() => 'TerminalNotesProjectionException($reason)';
}

final class TerminalNotesCard {
  TerminalNotesCard({
    required this.token,
    required this.body,
    required this.color,
    required this.status,
    required this.order,
    required this.due,
    required this.triggerKind,
    required this.triggerPhase,
  }) {
    final int bodyBytes = _validatedBodyBytes(body);
    if (token <= 0 ||
        token > TerminalNotesLimits.maximumSignedGeneration ||
        bodyBytes <= 0 ||
        bodyBytes > TerminalNotesLimits.maximumCardBodyUtf8Bytes ||
        order < 0 ||
        order > TerminalNotesLimits.maximumUnsigned32 ||
        (triggerKind == null) != (triggerPhase == null) ||
        !_triggerMatches(triggerKind, triggerPhase) ||
        due != (triggerPhase == TerminalNotesTriggerPhase.due)) {
      throw const TerminalNotesProjectionException('invalid card');
    }
  }

  final int token;
  final String body;
  final TerminalNotesColor color;
  final TerminalNotesStatus status;
  final int order;
  final bool due;
  final TerminalNotesTriggerKind? triggerKind;
  final TerminalNotesTriggerPhase? triggerPhase;

  int get bodyUtf8Bytes => utf8.encode(body).length;

  static int _validatedBodyBytes(String body) {
    var lineCount = 1;
    var hasNonWhitespace = false;
    for (var index = 0; index < body.length; index++) {
      final int unit = body.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index >= body.length) {
          throw const TerminalNotesProjectionException('invalid card body');
        }
        final int low = body.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) {
          throw const TerminalNotesProjectionException('invalid card body');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const TerminalNotesProjectionException('invalid card body');
      }
    }
    for (final int scalar in body.runes) {
      if (scalar == 0x0a) ++lineCount;
      final bool spacingControl = scalar == 0x09 || scalar == 0x0a;
      final bool forbiddenControl =
          (scalar <= 0x1f || (scalar >= 0x7f && scalar <= 0x9f)) &&
          !spacingControl;
      final bool forbiddenBidi =
          scalar == 0x200e ||
          scalar == 0x200f ||
          (scalar >= 0x202a && scalar <= 0x202e) ||
          (scalar >= 0x2066 && scalar <= 0x2069);
      if (forbiddenControl || forbiddenBidi) {
        throw const TerminalNotesProjectionException('invalid card body');
      }
      if (!_isUnicodeWhitespace(scalar)) hasNonWhitespace = true;
    }
    final int bodyBytes = utf8.encode(body).length;
    if (!hasNonWhitespace || lineCount > 64) {
      throw const TerminalNotesProjectionException('invalid card body');
    }
    return bodyBytes;
  }

  static bool _isUnicodeWhitespace(int scalar) =>
      (scalar >= 0x09 && scalar <= 0x0d) ||
      scalar == 0x20 ||
      scalar == 0x85 ||
      scalar == 0xa0 ||
      scalar == 0x1680 ||
      (scalar >= 0x2000 && scalar <= 0x200a) ||
      scalar == 0x2028 ||
      scalar == 0x2029 ||
      scalar == 0x202f ||
      scalar == 0x205f ||
      scalar == 0x3000;

  static bool _triggerMatches(
    TerminalNotesTriggerKind? kind,
    TerminalNotesTriggerPhase? phase,
  ) {
    if (kind == null || phase == null) return kind == null && phase == null;
    return switch (kind) {
      TerminalNotesTriggerKind.onReturn =>
        phase == TerminalNotesTriggerPhase.onReturnArmedHere ||
            phase == TerminalNotesTriggerPhase.onReturnArmedAway ||
            phase == TerminalNotesTriggerPhase.due ||
            phase == TerminalNotesTriggerPhase.suspended,
      TerminalNotesTriggerKind.atNextPrompt =>
        phase == TerminalNotesTriggerPhase.atNextPromptWaitingCommand ||
            phase == TerminalNotesTriggerPhase.atNextPromptWaitingEnd ||
            phase == TerminalNotesTriggerPhase.atNextPromptWaitingPromptStart ||
            phase == TerminalNotesTriggerPhase.atNextPromptWaitingInput ||
            phase == TerminalNotesTriggerPhase.due ||
            phase == TerminalNotesTriggerPhase.suspended,
    };
  }
}

final class TerminalNotesProjection {
  TerminalNotesProjection({
    required this.paneId,
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.storeRevision,
    required this.visibility,
    required this.presentationEligible,
    required this.activeCount,
    required this.dueCount,
    required this.featureState,
    required this.surfaceState,
    required this.readyCue,
    required this.section,
    required this.pageStart,
    required this.totalCount,
    required this.selectedToken,
    required this.editorMode,
    required this.messageKey,
    required Iterable<TerminalNotesCard> cards,
    this.darkAppearance = false,
    this.increaseContrast = false,
    this.differentiateWithoutColor = false,
    this.reduceMotion = false,
    this.systemBadgeVisible = false,
    this.locale = TerminalNotesLocale.english,
    this.draftGeneration = 0,
    this.bodyFontMilliPoints = 15000,
  }) : cards = List<TerminalNotesCard>.unmodifiable(cards) {
    final Set<int> tokens = this.cards
        .map((TerminalNotesCard card) => card.token)
        .toSet();
    final int aggregateBytes = this.cards.fold<int>(
      0,
      (int total, TerminalNotesCard card) => total + card.bodyUtf8Bytes,
    );
    if (paneId <= 0 ||
        paneId > TerminalNotesLimits.maximumSignedGeneration ||
        surfaceGeneration <= 0 ||
        surfaceGeneration > TerminalNotesLimits.maximumSignedGeneration ||
        projectionGeneration <= 0 ||
        projectionGeneration > TerminalNotesLimits.maximumSignedGeneration ||
        storeRevision < BigInt.zero ||
        storeRevision > TerminalNotesLimits.maximumUnsigned64 ||
        activeCount < 0 ||
        activeCount > TerminalNotesLimits.maximumContextNotes ||
        dueCount < 0 ||
        dueCount > activeCount ||
        this.cards.length > TerminalNotesLimits.maximumCards ||
        tokens.length != this.cards.length ||
        aggregateBytes > TerminalNotesLimits.maximumAggregateBodyUtf8Bytes ||
        totalCount < 0 ||
        totalCount >
            (section == TerminalNotesCollectionSection.current
                ? TerminalNotesLimits.maximumContextNotes
                : TerminalNotesLimits.maximumDetachedNotes) ||
        pageStart < 0 ||
        pageStart > totalCount ||
        pageStart + this.cards.length > totalCount ||
        bodyFontMilliPoints < 12000 ||
        bodyFontMilliPoints > 24000 ||
        draftGeneration < 0 ||
        draftGeneration > TerminalNotesLimits.maximumSignedGeneration ||
        ((editorMode == TerminalNotesEditorMode.inactive) !=
            (draftGeneration == 0)) ||
        (editorMode == TerminalNotesEditorMode.creating &&
            selectedToken != null) ||
        (editorMode == TerminalNotesEditorMode.editing &&
            selectedToken == null) ||
        (selectedToken != null && !tokens.contains(selectedToken)) ||
        (featureState != TerminalNotesFeatureState.available &&
            this.cards.isNotEmpty) ||
        (visibility == TerminalNotesVisibility.collapsed &&
            (this.cards.isNotEmpty || selectedToken != null))) {
      throw const TerminalNotesProjectionException('invalid projection');
    }
  }

  final int paneId;
  final int surfaceGeneration;
  final int projectionGeneration;
  final BigInt storeRevision;
  final TerminalNotesVisibility visibility;
  final bool presentationEligible;
  final int activeCount;
  final int dueCount;
  final TerminalNotesFeatureState featureState;
  final TerminalNotesSurfaceState surfaceState;
  final bool readyCue;
  final TerminalNotesCollectionSection section;
  final int pageStart;
  final int totalCount;
  final int? selectedToken;
  final TerminalNotesEditorMode editorMode;
  final TerminalNotesMessageKey messageKey;
  final List<TerminalNotesCard> cards;
  final bool darkAppearance;
  final bool increaseContrast;
  final bool differentiateWithoutColor;
  final bool reduceMotion;
  final bool systemBadgeVisible;
  final TerminalNotesLocale locale;
  final int draftGeneration;
  final int bodyFontMilliPoints;

  int get aggregateBodyUtf8Bytes => cards.fold<int>(
    0,
    (int total, TerminalNotesCard card) => total + card.bodyUtf8Bytes,
  );
}

abstract final class TerminalNotesProjectionCodec {
  static const int _magic = 0x31504e44; // DNP1 in little-endian bytes.
  static const int _flagPresentationEligible = 1 << 0;
  static const int _flagReadyCue = 1 << 1;
  static const int _flagDarkAppearance = 1 << 2;
  static const int _flagIncreaseContrast = 1 << 3;
  static const int _flagDifferentiateWithoutColor = 1 << 4;
  static const int _flagReduceMotion = 1 << 5;
  static const int _flagSystemBadgeVisible = 1 << 6;
  static const int _knownFlags =
      _flagPresentationEligible |
      _flagReadyCue |
      _flagDarkAppearance |
      _flagIncreaseContrast |
      _flagDifferentiateWithoutColor |
      _flagReduceMotion |
      _flagSystemBadgeVisible;
  static const int _cardFlagDue = 1 << 0;
  static const int _knownCardFlags = _cardFlagDue;

  static Uint8List encode(TerminalNotesProjection projection) {
    final List<Uint8List> bodies = projection.cards
        .map(
          (TerminalNotesCard card) =>
              Uint8List.fromList(utf8.encode(card.body)),
        )
        .toList(growable: false);
    final int cardsBytes =
        projection.cards.length * TerminalNotesLimits.cardRecordBytes;
    final int bodyOffset = TerminalNotesLimits.headerBytes + cardsBytes;
    final int totalBytes = bodyOffset + projection.aggregateBodyUtf8Bytes;
    final Uint8List result = Uint8List(totalBytes);
    final ByteData data = ByteData.sublistView(result);
    _setUint32(data, 0, _magic);
    _setUint32(data, 4, totalBytes);
    data.setUint16(8, TerminalNotesLimits.protocolVersion, Endian.little);
    data.setUint16(10, TerminalNotesLimits.headerBytes, Endian.little);
    data.setUint16(12, TerminalNotesLimits.cardRecordBytes, Endian.little);
    data.setUint8(14, projection.visibility.index);
    data.setUint8(15, _projectionFlags(projection));
    _setUint64(data, 16, projection.paneId);
    _setUint64(data, 24, projection.surfaceGeneration);
    _setUint64(data, 32, projection.projectionGeneration);
    _setBigUint64(data, 40, projection.storeRevision);
    _setUint64(data, 48, projection.selectedToken ?? 0);
    _setUint32(data, 56, projection.activeCount);
    _setUint32(data, 60, projection.dueCount);
    _setUint32(data, 64, projection.cards.length);
    _setUint32(data, 68, projection.aggregateBodyUtf8Bytes);
    _setUint32(data, 72, TerminalNotesLimits.headerBytes);
    _setUint32(data, 76, bodyOffset);
    data.setUint8(80, projection.featureState.index);
    data.setUint8(81, projection.surfaceState.index);
    data.setUint8(82, projection.section.index);
    data.setUint8(83, projection.editorMode.index);
    data.setUint16(84, projection.messageKey.index, Endian.little);
    data.setUint16(86, projection.locale.index, Endian.little);
    _setUint32(data, 88, projection.pageStart);
    _setUint32(data, 92, projection.cards.length);
    _setUint32(data, 96, projection.totalCount);
    _setUint32(data, 104, projection.bodyFontMilliPoints);
    _setUint64(data, 108, projection.draftGeneration);

    var runningBodyOffset = 0;
    for (var index = 0; index < projection.cards.length; index++) {
      final TerminalNotesCard card = projection.cards[index];
      final Uint8List body = bodies[index];
      final int offset =
          TerminalNotesLimits.headerBytes +
          index * TerminalNotesLimits.cardRecordBytes;
      _setUint64(data, offset, card.token);
      _setUint32(data, offset + 8, runningBodyOffset);
      _setUint32(data, offset + 12, body.length);
      _setUint32(data, offset + 16, card.order);
      data.setUint8(offset + 20, card.color.index);
      data.setUint8(offset + 21, card.status.index);
      data.setUint8(offset + 22, _encodeNullable(card.triggerKind));
      data.setUint8(offset + 23, _encodeNullable(card.triggerPhase));
      _setUint32(data, offset + 24, card.due ? _cardFlagDue : 0);
      result.setRange(
        bodyOffset + runningBodyOffset,
        bodyOffset + runningBodyOffset + body.length,
        body,
      );
      runningBodyOffset += body.length;
    }
    return result;
  }

  static TerminalNotesProjection decode(Uint8List bytes) {
    try {
      return _decode(bytes);
    } on TerminalNotesProjectionException {
      rethrow;
    } on Object {
      throw const TerminalNotesProjectionException('malformed packet');
    }
  }

  static TerminalNotesProjection _decode(Uint8List bytes) {
    if (bytes.length < TerminalNotesLimits.headerBytes ||
        bytes.length >
            TerminalNotesLimits.headerBytes +
                TerminalNotesLimits.maximumCards *
                    TerminalNotesLimits.cardRecordBytes +
                TerminalNotesLimits.maximumAggregateBodyUtf8Bytes) {
      throw const TerminalNotesProjectionException('invalid packet length');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int version = data.getUint16(8, Endian.little);
    final int flags = data.getUint8(15);
    final int cardCount = _uint32(data, 64);
    final int bodyBytes = _uint32(data, 68);
    final int expectedBodyOffset =
        TerminalNotesLimits.headerBytes +
        cardCount * TerminalNotesLimits.cardRecordBytes;
    if (_uint32(data, 0) != _magic ||
        _uint32(data, 4) != bytes.length ||
        version != TerminalNotesLimits.protocolVersion ||
        data.getUint16(10, Endian.little) != TerminalNotesLimits.headerBytes ||
        data.getUint16(12, Endian.little) !=
            TerminalNotesLimits.cardRecordBytes ||
        flags & ~_knownFlags != 0 ||
        cardCount > TerminalNotesLimits.maximumCards ||
        bodyBytes > TerminalNotesLimits.maximumAggregateBodyUtf8Bytes ||
        _uint32(data, 72) != TerminalNotesLimits.headerBytes ||
        _uint32(data, 76) != expectedBodyOffset ||
        expectedBodyOffset + bodyBytes != bytes.length) {
      throw const TerminalNotesProjectionException('non-canonical header');
    }
    final int visibilityValue = data.getUint8(14);
    if (visibilityValue >= TerminalNotesVisibility.values.length) {
      throw const TerminalNotesProjectionException('unknown visibility');
    }
    final TerminalNotesVisibility visibility =
        TerminalNotesVisibility.values[visibilityValue];
    final bool presentationEligible = flags & _flagPresentationEligible != 0;
    final int featureState = data.getUint8(80);
    final int surfaceState = data.getUint8(81);
    final int section = data.getUint8(82);
    final int editorMode = data.getUint8(83);
    final int messageKey = data.getUint16(84, Endian.little);
    final int locale = data.getUint16(86, Endian.little);
    final int pageStart = _uint32(data, 88);
    final int pageLength = _uint32(data, 92);
    final int totalCount = _uint32(data, 96);
    final int bodyFontMilliPoints = _uint32(data, 104);
    final int draftGeneration = _uint64(data, 108);
    if (featureState >= TerminalNotesFeatureState.values.length ||
        surfaceState >= TerminalNotesSurfaceState.values.length ||
        section >= TerminalNotesCollectionSection.values.length ||
        editorMode >= TerminalNotesEditorMode.values.length ||
        messageKey >= TerminalNotesMessageKey.values.length ||
        locale >= TerminalNotesLocale.values.length ||
        _uint32(data, 100) != 0 ||
        _uint32(data, 116) != 0 ||
        _uint32(data, 120) != 0 ||
        _uint32(data, 124) != 0 ||
        pageLength != cardCount) {
      throw const TerminalNotesProjectionException(
        'non-canonical presentation state',
      );
    }
    if (visibility == TerminalNotesVisibility.collapsed &&
        (cardCount != 0 || bodyBytes != 0)) {
      throw const TerminalNotesProjectionException('hidden body payload');
    }
    final Set<int> tokens = <int>{};
    final List<TerminalNotesCard> cards = <TerminalNotesCard>[];
    var expectedRelativeBodyOffset = 0;
    for (var index = 0; index < cardCount; index++) {
      final int offset =
          TerminalNotesLimits.headerBytes +
          index * TerminalNotesLimits.cardRecordBytes;
      final int token = _uint64(data, offset);
      final int relativeBodyOffset = _uint32(data, offset + 8);
      final int bodyLength = _uint32(data, offset + 12);
      final int order = _uint32(data, offset + 16);
      final int color = data.getUint8(offset + 20);
      final int status = data.getUint8(offset + 21);
      final int triggerKind = data.getUint8(offset + 22);
      final int triggerPhase = data.getUint8(offset + 23);
      final int cardFlags = _uint32(data, offset + 24);
      final int reserved = _uint32(data, offset + 28);
      if (token <= 0 ||
          token > TerminalNotesLimits.maximumSignedGeneration ||
          !tokens.add(token) ||
          relativeBodyOffset != expectedRelativeBodyOffset ||
          bodyLength <= 0 ||
          bodyLength > TerminalNotesLimits.maximumCardBodyUtf8Bytes ||
          relativeBodyOffset + bodyLength > bodyBytes ||
          color >= TerminalNotesColor.values.length ||
          status >= TerminalNotesStatus.values.length ||
          triggerKind > TerminalNotesTriggerKind.values.length ||
          triggerPhase > TerminalNotesTriggerPhase.values.length ||
          (triggerKind == 0) != (triggerPhase == 0) ||
          cardFlags & ~_knownCardFlags != 0 ||
          reserved != 0) {
        throw const TerminalNotesProjectionException(
          'non-canonical card record',
        );
      }
      final bool due = cardFlags & _cardFlagDue != 0;
      final TerminalNotesTriggerPhase? decodedPhase = _decodeNullable(
        TerminalNotesTriggerPhase.values,
        triggerPhase,
      );
      if (due != (decodedPhase == TerminalNotesTriggerPhase.due)) {
        throw const TerminalNotesProjectionException('inconsistent due state');
      }
      final int start = expectedBodyOffset + relativeBodyOffset;
      final String body = utf8.decode(
        bytes.sublist(start, start + bodyLength),
        allowMalformed: false,
      );
      cards.add(
        TerminalNotesCard(
          token: token,
          body: body,
          color: TerminalNotesColor.values[color],
          status: TerminalNotesStatus.values[status],
          order: order,
          due: due,
          triggerKind: _decodeNullable(
            TerminalNotesTriggerKind.values,
            triggerKind,
          ),
          triggerPhase: decodedPhase,
        ),
      );
      expectedRelativeBodyOffset += bodyLength;
    }
    if (expectedRelativeBodyOffset != bodyBytes) {
      throw const TerminalNotesProjectionException('non-canonical body area');
    }
    return TerminalNotesProjection(
      paneId: _positiveSigned64(data, 16),
      surfaceGeneration: _positiveSigned64(data, 24),
      projectionGeneration: _positiveSigned64(data, 32),
      storeRevision: _bigUint64(data, 40),
      visibility: visibility,
      presentationEligible: presentationEligible,
      activeCount: _uint32(data, 56),
      dueCount: _uint32(data, 60),
      featureState: TerminalNotesFeatureState.values[featureState],
      surfaceState: TerminalNotesSurfaceState.values[surfaceState],
      readyCue: flags & _flagReadyCue != 0,
      section: TerminalNotesCollectionSection.values[section],
      pageStart: pageStart,
      totalCount: totalCount,
      selectedToken: _nullableToken(_uint64(data, 48)),
      editorMode: TerminalNotesEditorMode.values[editorMode],
      messageKey: TerminalNotesMessageKey.values[messageKey],
      locale: TerminalNotesLocale.values[locale],
      draftGeneration: draftGeneration,
      cards: cards,
      darkAppearance: flags & _flagDarkAppearance != 0,
      increaseContrast: flags & _flagIncreaseContrast != 0,
      differentiateWithoutColor: flags & _flagDifferentiateWithoutColor != 0,
      reduceMotion: flags & _flagReduceMotion != 0,
      systemBadgeVisible: flags & _flagSystemBadgeVisible != 0,
      bodyFontMilliPoints: bodyFontMilliPoints,
    );
  }

  static int _projectionFlags(TerminalNotesProjection projection) {
    var flags = 0;
    if (projection.presentationEligible) flags |= _flagPresentationEligible;
    if (projection.readyCue) flags |= _flagReadyCue;
    if (projection.darkAppearance) flags |= _flagDarkAppearance;
    if (projection.increaseContrast) flags |= _flagIncreaseContrast;
    if (projection.differentiateWithoutColor) {
      flags |= _flagDifferentiateWithoutColor;
    }
    if (projection.reduceMotion) flags |= _flagReduceMotion;
    if (projection.systemBadgeVisible) flags |= _flagSystemBadgeVisible;
    return flags;
  }

  static int? _nullableToken(int value) => value == 0 ? null : value;

  static int _encodeNullable(Object? value) {
    if (value == null) return 0;
    if (value is TerminalNotesTriggerKind) return value.index + 1;
    if (value is TerminalNotesTriggerPhase) return value.index + 1;
    throw const TerminalNotesProjectionException('unsupported enum');
  }

  static T? _decodeNullable<T>(List<T> values, int encoded) =>
      encoded == 0 ? null : values[encoded - 1];

  static int _positiveSigned64(ByteData data, int offset) {
    final int value = _uint64(data, offset);
    if (value <= 0 || value > TerminalNotesLimits.maximumSignedGeneration) {
      throw const TerminalNotesProjectionException('invalid identity');
    }
    return value;
  }

  static int _uint32(ByteData data, int offset) =>
      data.getUint32(offset, Endian.little);

  static int _uint64(ByteData data, int offset) =>
      data.getUint64(offset, Endian.little);

  static BigInt _bigUint64(ByteData data, int offset) =>
      (BigInt.from(_uint32(data, offset + 4)) << 32) |
      BigInt.from(_uint32(data, offset));

  static void _setUint32(ByteData data, int offset, int value) =>
      data.setUint32(offset, value, Endian.little);

  static void _setUint64(ByteData data, int offset, int value) =>
      data.setUint64(offset, value, Endian.little);

  static void _setBigUint64(ByteData data, int offset, BigInt value) {
    final BigInt mask = BigInt.from(0xffffffff);
    _setUint32(data, offset, (value & mask).toInt());
    _setUint32(data, offset + 4, (value >> 32).toInt());
  }
}
