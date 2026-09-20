import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';

Future<void> main() => runTerminalNoteNativeAdapterTests();

Future<void> runTerminalNoteNativeAdapterTests() async {
  await _testStrictProjectionConversionAndLastGood();
  await _testNativeIntentResultAndTeardown();
}

Future<void> _testStrictProjectionConversionAndLastGood() async {
  final _FakeNativeChannel channel = _FakeNativeChannel();
  final TerminalNoteNativeSurfaceAdapter adapter =
      TerminalNoteNativeSurfaceAdapter(
        channel: channel,
        presentation: const TerminalNoteNativePresentationState(
          readyCue: true,
          darkAppearance: true,
          increaseContrast: true,
          differentiateWithoutColor: true,
          reduceMotion: true,
          systemBadgeVisible: true,
          locale: TerminalNotesLocale.japanese,
          bodyFontMilliPoints: 24000,
        ),
      );
  final TerminalNoteSurfaceProjection expanded = _projection(
    generation: 2,
    visibility: TerminalNoteSurfaceVisibility.expanded,
    selectedToken: TerminalNoteCardToken(31),
    editorMode: TerminalNoteEditorMode.editing,
    draftGeneration: 8,
    pageStart: 1,
    totalCount: 3,
  );
  _expect(adapter.applyProjection(expanded), 'expanded projection accepted');
  final TerminalNotesProjection native = channel.projections.single;
  _expect(
    native.paneId == 7 &&
        native.surfaceGeneration == 11 &&
        native.projectionGeneration == 2 &&
        native.storeRevision == BigInt.from(9) &&
        native.visibility == TerminalNotesVisibility.expanded &&
        native.cards.length == 2 &&
        native.cards.first.token == 31 &&
        native.cards.first.body == 'alpha' &&
        native.cards.first.color == TerminalNotesColor.yellow &&
        native.cards.first.status == TerminalNotesStatus.active &&
        native.cards.last.status == TerminalNotesStatus.resolved &&
        native.cards.last.triggerKind == TerminalNotesTriggerKind.onReturn &&
        native.cards.last.triggerPhase == TerminalNotesTriggerPhase.due &&
        native.cards.last.due &&
        native.readyCue &&
        native.darkAppearance &&
        native.increaseContrast &&
        native.differentiateWithoutColor &&
        native.reduceMotion &&
        native.systemBadgeVisible &&
        native.locale == TerminalNotesLocale.japanese &&
        native.bodyFontMilliPoints == 24000 &&
        native.section == TerminalNotesCollectionSection.current &&
        native.pageStart == 1 &&
        native.totalCount == 3 &&
        native.selectedToken == 31 &&
        native.editorMode == TerminalNotesEditorMode.editing &&
        native.draftGeneration == 8,
    'adapter maps the bounded authority projection without persistent IDs',
  );

  channel.nextApply = TerminalNotesApplyDisposition.rejectedStale;
  final TerminalNoteSurfaceProjection rejected = _projection(
    generation: 3,
    visibility: TerminalNoteSurfaceVisibility.collapsed,
  );
  _expect(
    !adapter.applyProjection(rejected) &&
        identical(adapter.lastAuthorityProjection, expanded) &&
        identical(adapter.lastNativeProjection, native),
    'native rejection retains the last-good authority and ABI projection',
  );
  await adapter.dispose();
}

Future<void> _testNativeIntentResultAndTeardown() async {
  final _FakeNativeChannel channel = _FakeNativeChannel();
  final TerminalNoteNativeSurfaceAdapter adapter =
      TerminalNoteNativeSurfaceAdapter(channel: channel);
  final TerminalNotesNativeIntent intent = TerminalNotesNativeIntent(
    surfaceGeneration: 11,
    projectionGeneration: 2,
    eventGeneration: 4,
    draftGeneration: 8,
    cardToken: 31,
    expectedStoreRevision: BigInt.from(9),
    kind: TerminalNotesIntentKind.save,
    color: TerminalNotesColor.blue,
    body: 'changed',
  );
  channel.intent = intent;
  _expect(identical(adapter.takeIntent(), intent), 'intent is consumed once');
  channel.intent = null;
  final TerminalNotesNativeResult result = TerminalNotesNativeResult(
    intent: intent,
    disposition: TerminalNotesResultDisposition.accepted,
    newStoreRevision: BigInt.from(10),
    newProjectionGeneration: 3,
  );
  _expect(
    adapter.applyResult(result) ==
            TerminalNotesResultApplyDisposition.accepted &&
        identical(channel.result, result) &&
        adapter.focus(TerminalNotesNativeFocusTarget.editor),
    'result and bounded focus use the same native channel',
  );
  adapter.updateLayout(
    paneWidth: 900,
    paneHeight: 600,
    backingScale: 2,
    requestedRailWidth: 320,
  );
  await adapter.dispose();
  await adapter.dispose();
  _expect(
    channel.layoutCount == 1 &&
        channel.detachCount == 1 &&
        channel.disposeCount == 1 &&
        adapter.isDisposed,
    'layout is bounded and teardown is idempotent',
  );
  var threw = false;
  try {
    adapter.takeIntent();
  } on StateError {
    threw = true;
  }
  _expect(threw, 'disposed adapters reject late native events');
}

TerminalNoteSurfaceProjection _projection({
  required int generation,
  required TerminalNoteSurfaceVisibility visibility,
  TerminalNoteCardToken? selectedToken,
  TerminalNoteEditorMode editorMode = TerminalNoteEditorMode.inactive,
  int draftGeneration = 0,
  int pageStart = 0,
  int? totalCount,
}) => TerminalNoteSurfaceProjection(
  paneId: const PaneId(7),
  surfaceGeneration: 11,
  projectionGeneration: generation,
  storeRevision: BigInt.from(9),
  visibility: visibility,
  presentationEligible: visibility == TerminalNoteSurfaceVisibility.expanded,
  activeCount: 1,
  dueCount: 1,
  pageStart: pageStart,
  totalCount: totalCount,
  selectedToken: selectedToken,
  editorMode: editorMode,
  draftGeneration: draftGeneration,
  cards: visibility == TerminalNoteSurfaceVisibility.collapsed
      ? const <TerminalNoteCardProjection>[]
      : <TerminalNoteCardProjection>[
          TerminalNoteCardProjection(
            token: TerminalNoteCardToken(31),
            body: 'alpha',
            color: NoteColorKey.yellow,
            status: NoteStatus.active,
            order: 0,
            due: false,
            triggerKind: null,
            triggerPhase: null,
          ),
          TerminalNoteCardProjection(
            token: TerminalNoteCardToken(32),
            body: 'beta',
            color: NoteColorKey.purple,
            status: NoteStatus.resolved,
            order: 1,
            due: true,
            triggerKind: NoteTriggerKind.onReturn,
            triggerPhase: NoteTriggerPhase.due,
          ),
        ],
);

final class _FakeNativeChannel implements TerminalNoteNativeSurfaceChannel {
  final List<TerminalNotesProjection> projections = <TerminalNotesProjection>[];
  TerminalNotesApplyDisposition nextApply =
      TerminalNotesApplyDisposition.accepted;
  TerminalNotesNativeIntent? intent;
  TerminalNotesNativeResult? result;
  int layoutCount = 0;
  int detachCount = 0;
  int disposeCount = 0;

  @override
  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) => TerminalNotesAttachDisposition.attached;

  @override
  void detachFromHost() {
    detachCount++;
  }

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    projections.add(projection);
    return nextApply;
  }

  @override
  TerminalNotesNativeIntent? takeIntent() => intent;

  @override
  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) {
    this.result = result;
    return TerminalNotesResultApplyDisposition.accepted;
  }

  @override
  bool focus(TerminalNotesNativeFocusTarget target) =>
      target == TerminalNotesNativeFocusTarget.editor;

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    if (paneWidth != 900 ||
        paneHeight != 600 ||
        backingScale != 2 ||
        requestedRailWidth != 320) {
      throw StateError('unexpected layout');
    }
    layoutCount++;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
