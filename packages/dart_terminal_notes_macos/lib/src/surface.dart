import 'dart:typed_data';

import 'native_backend.dart';
import 'projection.dart';

enum TerminalNotesApplyDisposition {
  accepted,
  rejectedInvalid,
  rejectedUnsupportedVersion,
  rejectedStale,
  failed,
}

final class TerminalNotesNativeException implements Exception {
  const TerminalNotesNativeException(this.operation, this.status);

  final String operation;
  final int status;

  @override
  String toString() => 'TerminalNotesNativeException($operation, $status)';
}

final class TerminalNotesNativeSnapshot {
  const TerminalNotesNativeSnapshot({
    required this.paneId,
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.storeRevision,
    required this.acceptedProjectionCount,
    required this.rejectedProjectionCount,
    required this.activeCount,
    required this.dueCount,
    required this.projectedCardCount,
    required this.materializedCardCount,
    required this.packetBytes,
    required this.visibility,
    required this.presentationEligible,
    required this.initialized,
    required this.readyCue,
    required this.darkAppearance,
    required this.increaseContrast,
    required this.differentiateWithoutColor,
    required this.reduceMotion,
    required this.systemBadgeVisible,
    required this.featureState,
    required this.surfaceState,
    required this.section,
    required this.editorMode,
    required this.messageKey,
    required this.pageStart,
    required this.totalCount,
    required this.bodyFontMilliPoints,
  });

  final int paneId;
  final int surfaceGeneration;
  final int projectionGeneration;
  final BigInt storeRevision;
  final int acceptedProjectionCount;
  final int rejectedProjectionCount;
  final int activeCount;
  final int dueCount;
  final int projectedCardCount;
  final int materializedCardCount;
  final int packetBytes;
  final TerminalNotesVisibility visibility;
  final bool presentationEligible;
  final bool initialized;
  final bool readyCue;
  final bool darkAppearance;
  final bool increaseContrast;
  final bool differentiateWithoutColor;
  final bool reduceMotion;
  final bool systemBadgeVisible;
  final TerminalNotesFeatureState featureState;
  final TerminalNotesSurfaceState surfaceState;
  final TerminalNotesCollectionSection section;
  final TerminalNotesEditorMode editorMode;
  final TerminalNotesMessageKey messageKey;
  final int pageStart;
  final int totalCount;
  final int bodyFontMilliPoints;
}

final class TerminalNotesNativeSurface {
  factory TerminalNotesNativeSurface({TerminalNotesNativeBindings? bindings}) {
    final TerminalNotesNativeBindings resolved =
        bindings ?? TerminalNotesNativeFfiBindings();
    if (resolved.abiVersion != TerminalNotesLimits.protocolVersion) {
      throw StateError('unsupported native Note ABI');
    }
    return TerminalNotesNativeSurface._(resolved, resolved.createSurface());
  }

  TerminalNotesNativeSurface._(this._bindings, this._handle);

  final TerminalNotesNativeBindings _bindings;
  Object? _handle;

  bool get isDisposed => _handle == null;

  TerminalNotesApplyDisposition apply(TerminalNotesProjection projection) {
    final Object handle = _requireHandle();
    final Uint8List bytes = TerminalNotesProjectionCodec.encode(projection);
    return switch (_bindings.applyProjection(handle, bytes)) {
      nativeStatusOk => TerminalNotesApplyDisposition.accepted,
      nativeStatusInvalidArgument =>
        TerminalNotesApplyDisposition.rejectedInvalid,
      nativeStatusUnsupportedVersion =>
        TerminalNotesApplyDisposition.rejectedUnsupportedVersion,
      nativeStatusStale => TerminalNotesApplyDisposition.rejectedStale,
      _ => TerminalNotesApplyDisposition.failed,
    };
  }

  TerminalNotesNativeSnapshot get snapshot {
    final TerminalNotesNativeRawSnapshot raw = _bindings.snapshot(
      _requireHandle(),
    );
    if (raw.visibility >= TerminalNotesVisibility.values.length ||
        raw.featureState >= TerminalNotesFeatureState.values.length ||
        raw.surfaceState >= TerminalNotesSurfaceState.values.length ||
        raw.section >= TerminalNotesCollectionSection.values.length ||
        raw.editorMode >= TerminalNotesEditorMode.values.length ||
        raw.messageKey >= TerminalNotesMessageKey.values.length) {
      throw const TerminalNotesNativeException('snapshot.visibility', -1);
    }
    return TerminalNotesNativeSnapshot(
      paneId: raw.paneId,
      surfaceGeneration: raw.surfaceGeneration,
      projectionGeneration: raw.projectionGeneration,
      storeRevision: raw.storeRevision,
      acceptedProjectionCount: raw.acceptedProjectionCount,
      rejectedProjectionCount: raw.rejectedProjectionCount,
      activeCount: raw.activeCount,
      dueCount: raw.dueCount,
      projectedCardCount: raw.projectedCardCount,
      materializedCardCount: raw.materializedCardCount,
      packetBytes: raw.packetBytes,
      visibility: TerminalNotesVisibility.values[raw.visibility],
      presentationEligible: raw.presentationEligible,
      initialized: raw.initialized,
      readyCue: raw.readyCue,
      darkAppearance: raw.darkAppearance,
      increaseContrast: raw.increaseContrast,
      differentiateWithoutColor: raw.differentiateWithoutColor,
      reduceMotion: raw.reduceMotion,
      systemBadgeVisible: raw.systemBadgeVisible,
      featureState: TerminalNotesFeatureState.values[raw.featureState],
      surfaceState: TerminalNotesSurfaceState.values[raw.surfaceState],
      section: TerminalNotesCollectionSection.values[raw.section],
      editorMode: TerminalNotesEditorMode.values[raw.editorMode],
      messageKey: TerminalNotesMessageKey.values[raw.messageKey],
      pageStart: raw.pageStart,
      totalCount: raw.totalCount,
      bodyFontMilliPoints: raw.bodyFontMilliPoints,
    );
  }

  void dispose() {
    final Object? handle = _handle;
    if (handle == null) return;
    _handle = null;
    _bindings.destroySurface(handle);
  }

  Object _requireHandle() {
    final Object? handle = _handle;
    if (handle == null) throw StateError('native Note surface is disposed');
    return handle;
  }
}
