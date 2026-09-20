/// Bounded native Note presentation owned by the Dart Terminal product.
library;

export 'src/projection.dart'
    show
        TerminalNotesCard,
        TerminalNotesColor,
        TerminalNotesCollectionSection,
        TerminalNotesEditorMode,
        TerminalNotesFeatureState,
        TerminalNotesLimits,
        TerminalNotesLocale,
        TerminalNotesMessageKey,
        TerminalNotesProjection,
        TerminalNotesProjectionCodec,
        TerminalNotesProjectionException,
        TerminalNotesSurfaceState,
        TerminalNotesStatus,
        TerminalNotesTriggerKind,
        TerminalNotesTriggerPhase,
        TerminalNotesVisibility;
export 'src/surface.dart'
    show
        TerminalNotesApplyDisposition,
        TerminalNotesCapabilityAvailability,
        TerminalNotesIntentKind,
        TerminalNotesNativeIntent,
        TerminalNotesNativeOpenResult,
        TerminalNotesNativeResult,
        TerminalNotesNativeException,
        TerminalNotesNativeFocusTarget,
        TerminalNotesNativePresentation,
        TerminalNotesNativeSnapshot,
        TerminalNotesNativeSurface,
        TerminalNotesResultApplyDisposition,
        TerminalNotesResultDisposition,
        TerminalNotesRect;
