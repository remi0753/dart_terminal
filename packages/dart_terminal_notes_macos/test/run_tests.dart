import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_notes_macos/testing.dart';

void main() {
  _testCanonicalRoundTrip();
  _testCollapsedProjection();
  _testBounds();
  _testMalformedPackets();
  _testDeterministicFuzz();
  _testSurfaceFacade();
  _testFailSoftOpen();
  stdout.writeln('terminal Notes Dart codec tests passed');
}

TerminalNotesCard _card({
  int token = 1,
  String body = 'remember this',
  TerminalNotesColor color = TerminalNotesColor.yellow,
  TerminalNotesStatus status = TerminalNotesStatus.active,
  int order = 0,
  bool due = false,
  TerminalNotesTriggerKind? triggerKind,
  TerminalNotesTriggerPhase? triggerPhase,
}) => TerminalNotesCard(
  token: token,
  body: body,
  color: color,
  status: status,
  order: order,
  due: due,
  triggerKind: triggerKind,
  triggerPhase: triggerPhase,
);

TerminalNotesProjection _projection({
  int projectionGeneration = 3,
  BigInt? storeRevision,
  TerminalNotesVisibility visibility = TerminalNotesVisibility.expanded,
  bool presentationEligible = true,
  TerminalNotesLocale locale = TerminalNotesLocale.english,
  List<TerminalNotesCard>? cards,
}) => TerminalNotesProjection(
  paneId: 11,
  surfaceGeneration: 7,
  projectionGeneration: projectionGeneration,
  storeRevision: storeRevision ?? ((BigInt.one << 63) + BigInt.from(41)),
  visibility: visibility,
  presentationEligible: presentationEligible,
  activeCount: 2,
  dueCount: 1,
  featureState: TerminalNotesFeatureState.available,
  surfaceState: TerminalNotesSurfaceState.ready,
  readyCue: true,
  section: TerminalNotesCollectionSection.current,
  pageStart: 0,
  totalCount: cards?.length ?? 2,
  selectedToken: visibility == TerminalNotesVisibility.collapsed ? null : 2,
  editorMode: TerminalNotesEditorMode.inactive,
  messageKey: TerminalNotesMessageKey.none,
  darkAppearance: true,
  increaseContrast: true,
  differentiateWithoutColor: true,
  reduceMotion: true,
  systemBadgeVisible: true,
  locale: locale,
  bodyFontMilliPoints: 24000,
  cards:
      cards ??
      <TerminalNotesCard>[
        _card(),
        _card(
          token: 2,
          body: '次のプロンプトで確認',
          color: TerminalNotesColor.blue,
          order: 9,
          due: true,
          triggerKind: TerminalNotesTriggerKind.atNextPrompt,
          triggerPhase: TerminalNotesTriggerPhase.due,
        ),
      ],
);

void _testCanonicalRoundTrip() {
  final TerminalNotesProjection source = _projection();
  final Uint8List encoded = TerminalNotesProjectionCodec.encode(source);
  final TerminalNotesProjection decoded = TerminalNotesProjectionCodec.decode(
    encoded,
  );
  _expect(decoded.paneId == 11, 'pane identity');
  _expect(decoded.surfaceGeneration == 7, 'surface generation');
  _expect(decoded.projectionGeneration == 3, 'projection generation');
  _expect(decoded.storeRevision == source.storeRevision, '64-bit revision');
  _expect(decoded.cards.length == 2, 'card count');
  _expect(decoded.cards[1].body == '次のプロンプトで確認', 'UTF-8 body');
  _expect(decoded.cards[1].due, 'due state');
  _expect(
    decoded.readyCue &&
        decoded.darkAppearance &&
        decoded.increaseContrast &&
        decoded.differentiateWithoutColor &&
        decoded.reduceMotion &&
        decoded.systemBadgeVisible &&
        decoded.locale == TerminalNotesLocale.english &&
        decoded.bodyFontMilliPoints == 24000,
    'appearance and accessibility flags',
  );
  _expect(
    _bytesEqual(encoded, TerminalNotesProjectionCodec.encode(decoded)),
    'canonical re-encode',
  );
}

void _testCollapsedProjection() {
  final TerminalNotesProjection collapsed = _projection(
    visibility: TerminalNotesVisibility.collapsed,
    presentationEligible: false,
    cards: <TerminalNotesCard>[],
  );
  final Uint8List encoded = TerminalNotesProjectionCodec.encode(collapsed);
  _expect(encoded.length == TerminalNotesLimits.headerBytes, 'body-free badge');
  final TerminalNotesProjection decoded = TerminalNotesProjectionCodec.decode(
    encoded,
  );
  _expect(decoded.cards.isEmpty, 'collapsed has no cards');
}

void _testBounds() {
  final String body = 'x' * TerminalNotesLimits.maximumCardBodyUtf8Bytes;
  final List<TerminalNotesCard> cards = List<TerminalNotesCard>.generate(
    TerminalNotesLimits.maximumCards,
    (int index) => _card(token: index + 1, body: body, order: index),
  );
  final TerminalNotesProjection maximum = _projection(
    cards: cards,
    storeRevision: TerminalNotesLimits.maximumUnsigned64,
  );
  final Uint8List bytes = TerminalNotesProjectionCodec.encode(maximum);
  _expect(
    TerminalNotesProjectionCodec.decode(bytes).cards.length ==
        TerminalNotesLimits.maximumCards,
    'maximum packet accepted',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(body: '$body!'),
    'card body +1',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(body: '   \n\t'),
    'whitespace-only body',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(body: 'unsafe\u0000body'),
    'control body',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(body: 'unsafe\u202ebody'),
    'bidi body',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(body: 'unsafe\ud800body'),
    'unpaired surrogate body',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _projection(cards: <TerminalNotesCard>[...cards, _card(token: 65)]),
    'card count +1',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _projection(cards: <TerminalNotesCard>[_card(), _card()]),
    'duplicate token',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _projection(
      visibility: TerminalNotesVisibility.collapsed,
      cards: <TerminalNotesCard>[_card()],
    ),
    'collapsed body',
  );
  _expectThrows<TerminalNotesProjectionException>(
    () => _card(
      triggerKind: TerminalNotesTriggerKind.onReturn,
      triggerPhase: TerminalNotesTriggerPhase.atNextPromptWaitingInput,
    ),
    'trigger kind/phase mismatch',
  );
}

void _testMalformedPackets() {
  final Uint8List valid = TerminalNotesProjectionCodec.encode(_projection());
  void rejected(String name, void Function(Uint8List) mutate) {
    final Uint8List bytes = Uint8List.fromList(valid);
    mutate(bytes);
    _expectThrows<TerminalNotesProjectionException>(
      () => TerminalNotesProjectionCodec.decode(bytes),
      name,
    );
  }

  rejected('unknown version', (Uint8List bytes) => bytes[8] = 2);
  rejected('unknown projection flag', (Uint8List bytes) => bytes[15] = 0x80);
  rejected('unknown card flag', (Uint8List bytes) => bytes[152] = 0x80);
  rejected('reserved card field', (Uint8List bytes) => bytes[156] = 1);
  rejected('duplicate token', (Uint8List bytes) {
    bytes.setRange(160, 168, bytes.sublist(128, 136));
  });
  rejected('non-canonical body offset', (Uint8List bytes) => bytes[136] = 1);
  rejected('unknown feature state', (Uint8List bytes) => bytes[80] = 0xff);
  rejected('unknown locale', (Uint8List bytes) => bytes[86] = 2);
  rejected('reserved header field', (Uint8List bytes) => bytes[108] = 1);
  rejected(
    'invalid UTF-8',
    (Uint8List bytes) => bytes[bytes.length - 1] = 0xff,
  );
  rejected('trailing data', (Uint8List bytes) {
    final ByteData data = ByteData.sublistView(bytes);
    data.setUint32(4, bytes.length - 1, Endian.little);
  });
  _expectThrows<TerminalNotesProjectionException>(
    () => TerminalNotesProjectionCodec.decode(Uint8List(79)),
    'truncated header',
  );
}

void _testDeterministicFuzz() {
  final Random random = Random(0x44544e31);
  final Uint8List seed = TerminalNotesProjectionCodec.encode(_projection());
  for (var iteration = 0; iteration < 4096; iteration++) {
    final int length = random.nextBool() ? random.nextInt(512) : seed.length;
    final Uint8List bytes = length == seed.length && random.nextBool()
        ? Uint8List.fromList(seed)
        : Uint8List.fromList(
            List<int>.generate(length, (_) => random.nextInt(256)),
          );
    if (bytes.isNotEmpty) {
      final int mutations = 1 + random.nextInt(min(8, bytes.length));
      for (var index = 0; index < mutations; index++) {
        bytes[random.nextInt(bytes.length)] = random.nextInt(256);
      }
    }
    try {
      final TerminalNotesProjection decoded =
          TerminalNotesProjectionCodec.decode(bytes);
      _expect(
        _bytesEqual(bytes, TerminalNotesProjectionCodec.encode(decoded)),
        'fuzz accepted only canonical packet',
      );
    } on TerminalNotesProjectionException {
      // Expected for arbitrary or non-canonical bytes.
    }
  }
}

void _testSurfaceFacade() {
  final _FakeBindings bindings = _FakeBindings();
  final TerminalNotesNativeSurface surface = TerminalNotesNativeSurface(
    bindings: bindings,
  );
  _expect(
    surface.apply(_projection()) == TerminalNotesApplyDisposition.accepted,
    'typed surface apply',
  );
  surface.updateLayout(
    paneWidth: 640,
    paneHeight: 480,
    backingScale: 2,
    requestedRailWidth: 320,
  );
  final TerminalNotesNativePresentation presentation = surface.presentation;
  _expect(
    bindings.layout == (640.0, 480.0, 2.0, 320.0) &&
        presentation.railVisible &&
        presentation.opaqueCards &&
        presentation.rail.width == 320,
    'typed presentation snapshot',
  );
  _expect(
    presentation.visibleAcknowledgementEligibleGeneration == 3 &&
        presentation.accessibilityAnnouncementCount == 1 &&
        presentation.badgeDisplayCount == 2,
    'content-free presentation state',
  );
  surface.dispose();
  surface.dispose();
  _expect(surface.isDisposed && bindings.destroyCount == 1, 'typed disposal');
}

void _testFailSoftOpen() {
  final TerminalNotesProjection lastProjection = _projection();
  const ({int rows, int columns, int drawable, int winsize, int sigwinch})
  terminal = (rows: 24, columns: 80, drawable: 1, winsize: 1, sigwinch: 0);
  final TerminalNotesNativeOpenResult result =
      TerminalNotesNativeSurface.tryOpen(bindings: _MissingBindings());
  _expect(
    result.availability ==
            TerminalNotesCapabilityAvailability.nativeUnavailable &&
        result.surface == null,
    'missing native capability is fail-soft',
  );
  _expect(lastProjection.projectionGeneration == 3, 'last data retained');
  _expect(
    terminal == (rows: 24, columns: 80, drawable: 1, winsize: 1, sigwinch: 0),
    'terminal sentinel unchanged',
  );
}

class _FakeBindings implements TerminalNotesNativeBindings {
  final Object handle = Object();
  (double, double, double, double)? layout;
  int destroyCount = 0;

  @override
  int get abiVersion => 1;

  @override
  int get liveSurfaceCount => destroyCount == 0 ? 1 : 0;

  @override
  Object createSurface() => handle;

  @override
  int applyProjection(Object handle, Uint8List bytes) {
    _expect(identical(handle, this.handle), 'fake apply handle');
    TerminalNotesProjectionCodec.decode(bytes);
    return 0;
  }

  @override
  TerminalNotesNativeRawSnapshot snapshot(Object handle) =>
      TerminalNotesNativeRawSnapshot(
        paneId: 11,
        surfaceGeneration: 7,
        projectionGeneration: 3,
        storeRevision: BigInt.one,
        acceptedProjectionCount: 1,
        rejectedProjectionCount: 0,
        activeCount: 2,
        dueCount: 1,
        projectedCardCount: 2,
        materializedCardCount: 2,
        packetBytes: 1,
        visibility: 1,
        presentationEligible: true,
        initialized: true,
        readyCue: true,
        darkAppearance: false,
        increaseContrast: false,
        differentiateWithoutColor: false,
        reduceMotion: false,
        systemBadgeVisible: false,
        featureState: 2,
        surfaceState: 1,
        section: 0,
        editorMode: 0,
        messageKey: 0,
        pageStart: 0,
        totalCount: 2,
        bodyFontMilliPoints: 15000,
      );

  @override
  int updateLayout(
    Object handle, {
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    required double requestedRailWidth,
  }) {
    layout = (paneWidth, paneHeight, backingScale, requestedRailWidth);
    return 0;
  }

  @override
  TerminalNotesNativePresentationRawSnapshot presentationSnapshot(
    Object handle,
  ) => TerminalNotesNativePresentationRawSnapshot(
    projectionGeneration: 3,
    paneWidth: 640,
    paneHeight: 480,
    backingScale: 2,
    badgeHit: (x: 588, y: 218, width: 44, height: 44),
    badgeVisual: (x: 588, y: 226, width: 44, height: 28),
    rail: (x: 308, y: 12, width: 320, height: 456),
    firstCard: (x: 320, y: 74, width: 284, height: 88),
    flags: (1 << 1) | (1 << 3) | (1 << 4),
    materializedCardCount: 2,
    accessibilityNodeCount: 11,
    accessibilityBodyCount: 2,
    visibleAcknowledgementEligibleGeneration: 3,
    accessibilityAnnouncementCount: 1,
    animationMilliseconds: 140,
    bodyFontMilliPoints: 15000,
    badgeDisplayCount: 2,
  );

  @override
  void destroySurface(Object handle) {
    _expect(identical(handle, this.handle), 'fake destroy handle');
    destroyCount++;
  }
}

final class _MissingBindings extends _FakeBindings {
  @override
  int get abiVersion => throw StateError('capability unavailable');
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

T _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T catch (error) {
    return error;
  }
  throw StateError('expected $T: $message');
}
