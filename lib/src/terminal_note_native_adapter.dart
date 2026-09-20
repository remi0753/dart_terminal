import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';

import 'terminal_note_model.dart';
import 'terminal_note_projection.dart';

/// Injectable product seam around the product-owned native Notes package.
///
/// The seam is deliberately defined in dart_terminal: generic AppKit code does
/// not know about Note projections, intents, or persistent authority state.
abstract interface class TerminalNoteNativeSurfaceChannel {
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection);

  TerminalNotesNativeIntent? takeIntent();

  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  );

  bool focus(TerminalNotesNativeFocusTarget target);

  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  });

  void dispose();
}

final class TerminalNoteFfiSurfaceChannel
    implements TerminalNoteNativeSurfaceChannel {
  TerminalNoteFfiSurfaceChannel(this.surface);

  final TerminalNotesNativeSurface surface;

  @override
  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) =>
      surface.apply(projection);

  @override
  TerminalNotesNativeIntent? takeIntent() => surface.takeIntent();

  @override
  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) => surface.applyResult(result);

  @override
  bool focus(TerminalNotesNativeFocusTarget target) => surface.focus(target);

  @override
  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) => surface.updateLayout(
    paneWidth: paneWidth,
    paneHeight: paneHeight,
    backingScale: backingScale,
    requestedRailWidth: requestedRailWidth,
  );

  @override
  void dispose() => surface.dispose();
}

/// Product presentation values that are intentionally absent from the durable
/// authority projection.
final class TerminalNoteNativePresentationState {
  const TerminalNoteNativePresentationState({
    this.featureState = TerminalNotesFeatureState.available,
    this.surfaceState = TerminalNotesSurfaceState.ready,
    this.readyCue = false,
    this.darkAppearance = false,
    this.increaseContrast = false,
    this.differentiateWithoutColor = false,
    this.reduceMotion = false,
    this.systemBadgeVisible = false,
    this.locale = TerminalNotesLocale.english,
    this.bodyFontMilliPoints = 15000,
  }) : assert(
         bodyFontMilliPoints >= 12000 && bodyFontMilliPoints <= 24000,
         'bodyFontMilliPoints must be in 12000..24000',
       );

  final TerminalNotesFeatureState featureState;
  final TerminalNotesSurfaceState surfaceState;
  final bool readyCue;
  final bool darkAppearance;
  final bool increaseContrast;
  final bool differentiateWithoutColor;
  final bool reduceMotion;
  final bool systemBadgeVisible;
  final TerminalNotesLocale locale;
  final int bodyFontMilliPoints;
}

/// Converts authority-owned, persistent-ID-free projections into the strict
/// native ABI. It retains only the last projection accepted by native code.
final class TerminalNoteNativeSurfaceAdapter
    implements TerminalNoteSurfacePort {
  TerminalNoteNativeSurfaceAdapter({
    required TerminalNoteNativeSurfaceChannel channel,
    TerminalNoteNativePresentationState presentation =
        const TerminalNoteNativePresentationState(),
  }) : _channel = channel,
       _presentation = presentation;

  final TerminalNoteNativeSurfaceChannel _channel;
  TerminalNoteNativePresentationState _presentation;
  TerminalNoteSurfaceProjection? _lastAuthorityProjection;
  TerminalNotesProjection? _lastNativeProjection;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  TerminalNoteSurfaceProjection? get lastAuthorityProjection =>
      _lastAuthorityProjection;
  TerminalNotesProjection? get lastNativeProjection => _lastNativeProjection;

  void updatePresentation(TerminalNoteNativePresentationState presentation) {
    _ensureLive();
    _presentation = presentation;
  }

  @override
  bool applyProjection(TerminalNoteSurfaceProjection projection) {
    _ensureLive();
    final TerminalNotesProjection nativeProjection = _convertProjection(
      projection,
      _presentation,
    );
    if (_channel.apply(nativeProjection) !=
        TerminalNotesApplyDisposition.accepted) {
      return false;
    }
    _lastAuthorityProjection = projection;
    _lastNativeProjection = nativeProjection;
    return true;
  }

  TerminalNotesNativeIntent? takeIntent() {
    _ensureLive();
    return _channel.takeIntent();
  }

  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) {
    _ensureLive();
    return _channel.applyResult(result);
  }

  bool focus(TerminalNotesNativeFocusTarget target) {
    _ensureLive();
    return _channel.focus(target);
  }

  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    _ensureLive();
    _channel.updateLayout(
      paneWidth: paneWidth,
      paneHeight: paneHeight,
      backingScale: backingScale,
      requestedRailWidth: requestedRailWidth,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lastAuthorityProjection = null;
    _lastNativeProjection = null;
    _channel.dispose();
  }

  void _ensureLive() {
    if (_disposed) throw StateError('native Note surface adapter is disposed');
  }

  static TerminalNotesProjection _convertProjection(
    TerminalNoteSurfaceProjection projection,
    TerminalNoteNativePresentationState presentation,
  ) {
    final List<TerminalNotesCard> cards = projection.cards
        .map(
          (TerminalNoteCardProjection card) => TerminalNotesCard(
            token: card.token.value,
            body: card.body,
            color: _color(card.color),
            status: _status(card.status),
            order: card.order,
            due: card.due,
            triggerKind: _triggerKind(card.triggerKind),
            triggerPhase: _triggerPhase(card.triggerPhase),
          ),
        )
        .toList(growable: false);
    return TerminalNotesProjection(
      paneId: projection.paneId.value,
      surfaceGeneration: projection.surfaceGeneration,
      projectionGeneration: projection.projectionGeneration,
      storeRevision: projection.storeRevision,
      visibility: switch (projection.visibility) {
        TerminalNoteSurfaceVisibility.collapsed =>
          TerminalNotesVisibility.collapsed,
        TerminalNoteSurfaceVisibility.expanded =>
          TerminalNotesVisibility.expanded,
      },
      presentationEligible: projection.presentationEligible,
      activeCount: projection.activeCount,
      dueCount: projection.dueCount,
      featureState: presentation.featureState,
      surfaceState: presentation.surfaceState,
      readyCue: presentation.readyCue,
      section: TerminalNotesCollectionSection.current,
      pageStart: 0,
      totalCount: cards.length,
      selectedToken: null,
      editorMode: TerminalNotesEditorMode.inactive,
      messageKey: TerminalNotesMessageKey.none,
      darkAppearance: presentation.darkAppearance,
      increaseContrast: presentation.increaseContrast,
      differentiateWithoutColor: presentation.differentiateWithoutColor,
      reduceMotion: presentation.reduceMotion,
      systemBadgeVisible: presentation.systemBadgeVisible,
      locale: presentation.locale,
      bodyFontMilliPoints: presentation.bodyFontMilliPoints,
      cards: cards,
    );
  }

  static TerminalNotesColor _color(NoteColorKey color) => switch (color) {
    NoteColorKey.neutral => TerminalNotesColor.neutral,
    NoteColorKey.yellow => TerminalNotesColor.yellow,
    NoteColorKey.blue => TerminalNotesColor.blue,
    NoteColorKey.green => TerminalNotesColor.green,
    NoteColorKey.pink => TerminalNotesColor.pink,
    NoteColorKey.purple => TerminalNotesColor.purple,
  };

  static TerminalNotesStatus _status(NoteStatus status) => switch (status) {
    NoteStatus.active => TerminalNotesStatus.active,
    NoteStatus.resolved => TerminalNotesStatus.resolved,
  };

  static TerminalNotesTriggerKind? _triggerKind(NoteTriggerKind? kind) =>
      switch (kind) {
        null => null,
        NoteTriggerKind.onReturn => TerminalNotesTriggerKind.onReturn,
        NoteTriggerKind.atNextPrompt => TerminalNotesTriggerKind.atNextPrompt,
      };

  static TerminalNotesTriggerPhase? _triggerPhase(NoteTriggerPhase? phase) =>
      switch (phase) {
        null => null,
        NoteTriggerPhase.onReturnArmedHere =>
          TerminalNotesTriggerPhase.onReturnArmedHere,
        NoteTriggerPhase.onReturnArmedAway =>
          TerminalNotesTriggerPhase.onReturnArmedAway,
        NoteTriggerPhase.atNextPromptWaitingCommand =>
          TerminalNotesTriggerPhase.atNextPromptWaitingCommand,
        NoteTriggerPhase.atNextPromptWaitingEnd =>
          TerminalNotesTriggerPhase.atNextPromptWaitingEnd,
        NoteTriggerPhase.atNextPromptWaitingPromptStart =>
          TerminalNotesTriggerPhase.atNextPromptWaitingPromptStart,
        NoteTriggerPhase.atNextPromptWaitingInput =>
          TerminalNotesTriggerPhase.atNextPromptWaitingInput,
        NoteTriggerPhase.due => TerminalNotesTriggerPhase.due,
        NoteTriggerPhase.suspended => TerminalNotesTriggerPhase.suspended,
      };
}
