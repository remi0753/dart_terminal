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

final class TerminalNotesRect {
  const TerminalNotesRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

final class TerminalNotesNativePresentation {
  const TerminalNotesNativePresentation({
    required this.projectionGeneration,
    required this.paneWidth,
    required this.paneHeight,
    required this.backingScale,
    required this.badgeHit,
    required this.badgeVisual,
    required this.rail,
    required this.firstCard,
    required this.flags,
    required this.materializedCardCount,
    required this.accessibilityNodeCount,
    required this.accessibilityBodyCount,
    required this.firstSurfaceRgba,
    required this.firstAccentRgba,
    required this.bodyTextRgba,
    required this.animationMilliseconds,
    required this.bodyFontMilliPoints,
  });

  static const int _badgeVisible = 1 << 0;
  static const int _railVisible = 1 << 1;
  static const int _smallPane = 1 << 2;
  static const int _opaqueCards = 1 << 3;
  static const int _cardShadows = 1 << 4;
  static const int _readyCue = 1 << 5;
  static const int _reducedMotion = 1 << 6;
  static const int _differentiateWithoutColor = 1 << 7;
  static const int _increaseContrast = 1 << 8;
  static const int _dark = 1 << 9;
  static const int _systemBadgeVisible = 1 << 10;

  final int projectionGeneration;
  final double paneWidth;
  final double paneHeight;
  final double backingScale;
  final TerminalNotesRect badgeHit;
  final TerminalNotesRect badgeVisual;
  final TerminalNotesRect rail;
  final TerminalNotesRect firstCard;
  final int flags;
  final int materializedCardCount;
  final int accessibilityNodeCount;
  final int accessibilityBodyCount;
  final int firstSurfaceRgba;
  final int firstAccentRgba;
  final int bodyTextRgba;
  final int animationMilliseconds;
  final int bodyFontMilliPoints;

  bool get badgeVisible => flags & _badgeVisible != 0;
  bool get railVisible => flags & _railVisible != 0;
  bool get smallPane => flags & _smallPane != 0;
  bool get opaqueCards => flags & _opaqueCards != 0;
  bool get cardShadows => flags & _cardShadows != 0;
  bool get readyCue => flags & _readyCue != 0;
  bool get reducedMotion => flags & _reducedMotion != 0;
  bool get differentiateWithoutColor => flags & _differentiateWithoutColor != 0;
  bool get increaseContrast => flags & _increaseContrast != 0;
  bool get darkAppearance => flags & _dark != 0;
  bool get systemBadgeVisible => flags & _systemBadgeVisible != 0;
}

final class TerminalNotesNativeCardPresentation {
  const TerminalNotesNativeCardPresentation({
    required this.index,
    required this.order,
    required this.color,
    required this.status,
    required this.due,
    required this.visibleLineLimit,
    required this.surfaceRgba,
    required this.accentRgba,
    required this.bodyTextRgba,
    required this.nonColorCue,
    required this.frame,
  });

  final int index;
  final int order;
  final TerminalNotesColor color;
  final TerminalNotesStatus status;
  final bool due;
  final int visibleLineLimit;
  final int surfaceRgba;
  final int accentRgba;
  final int bodyTextRgba;
  final bool nonColorCue;
  final TerminalNotesRect frame;
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

  void updateLayout({
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    double requestedRailWidth = 0,
  }) {
    final int status = _bindings.updateLayout(
      _requireHandle(),
      paneWidth: paneWidth,
      paneHeight: paneHeight,
      backingScale: backingScale,
      requestedRailWidth: requestedRailWidth,
    );
    if (status != nativeStatusOk) {
      throw TerminalNotesNativeException('updateLayout', status);
    }
  }

  TerminalNotesNativePresentation get presentation {
    final TerminalNotesNativePresentationRawSnapshot raw = _bindings
        .presentationSnapshot(_requireHandle());
    TerminalNotesRect rect(
      ({double x, double y, double width, double height}) value,
    ) => TerminalNotesRect(
      x: value.x,
      y: value.y,
      width: value.width,
      height: value.height,
    );
    return TerminalNotesNativePresentation(
      projectionGeneration: raw.projectionGeneration,
      paneWidth: raw.paneWidth,
      paneHeight: raw.paneHeight,
      backingScale: raw.backingScale,
      badgeHit: rect(raw.badgeHit),
      badgeVisual: rect(raw.badgeVisual),
      rail: rect(raw.rail),
      firstCard: rect(raw.firstCard),
      flags: raw.flags,
      materializedCardCount: raw.materializedCardCount,
      accessibilityNodeCount: raw.accessibilityNodeCount,
      accessibilityBodyCount: raw.accessibilityBodyCount,
      firstSurfaceRgba: raw.firstSurfaceRgba,
      firstAccentRgba: raw.firstAccentRgba,
      bodyTextRgba: raw.bodyTextRgba,
      animationMilliseconds: raw.animationMilliseconds,
      bodyFontMilliPoints: raw.bodyFontMilliPoints,
    );
  }

  TerminalNotesNativeCardPresentation cardPresentation(int index) {
    if (index < 0 || index >= TerminalNotesLimits.maximumMaterializedCards) {
      throw RangeError.range(
        index,
        0,
        TerminalNotesLimits.maximumMaterializedCards - 1,
        'index',
      );
    }
    final TerminalNotesNativeCardPresentationRawSnapshot raw = _bindings
        .cardPresentationSnapshot(_requireHandle(), index);
    if (raw.color >= TerminalNotesColor.values.length ||
        raw.status >= TerminalNotesStatus.values.length) {
      throw const TerminalNotesNativeException('cardPresentation.enum', -1);
    }
    return TerminalNotesNativeCardPresentation(
      index: raw.index,
      order: raw.order,
      color: TerminalNotesColor.values[raw.color],
      status: TerminalNotesStatus.values[raw.status],
      due: raw.due,
      visibleLineLimit: raw.visibleLineLimit,
      surfaceRgba: raw.surfaceRgba,
      accentRgba: raw.accentRgba,
      bodyTextRgba: raw.bodyTextRgba,
      nonColorCue: raw.nonColorCue,
      frame: TerminalNotesRect(
        x: raw.frame.x,
        y: raw.frame.y,
        width: raw.frame.width,
        height: raw.frame.height,
      ),
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
