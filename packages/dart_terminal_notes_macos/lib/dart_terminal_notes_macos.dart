/// Bounded native Note presentation owned by the Dart Terminal product.
library;

import 'package:dart_macos_runtime/dart_macos_runtime.dart';

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

const String terminalNotesMacosCapabilityId = 'dart_terminal_notes_macos';

/// Loads the product-owned Notes native capability declared by the app.
abstract final class TerminalNotesMacos {
  static MacosNativeCapability? _capability;

  static bool get isInitialized => _capability != null;

  static void initialize() {
    _capability ??= MacosNativeCapability.load(terminalNotesMacosCapabilityId);
  }
}
