import 'dart:convert';
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

enum TerminalNotesCapabilityAvailability { available, nativeUnavailable }

enum TerminalNotesAttachDisposition { attached, rendererUnavailable, busy }

enum TerminalNotesIntentKind {
  save,
  cancel,
  changeColor,
  moveEarlier,
  moveLater,
  resolve,
  reopen,
  delete,
  reattach,
  export,
  copy,
  open,
  close,
  selectCard,
  beginCreate,
  beginEdit,
}

enum TerminalNotesResultDisposition {
  accepted,
  conflict,
  rejected,
  busy,
  unavailable,
}

enum TerminalNotesResultApplyDisposition {
  accepted,
  rejectedInvalid,
  rejectedStale,
  failed,
}

enum TerminalNotesNativeFocusTarget { none, rail, editor }

final class TerminalNotesNativeIntent {
  const TerminalNotesNativeIntent({
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.eventGeneration,
    required this.draftGeneration,
    required this.cardToken,
    required this.expectedStoreRevision,
    required this.kind,
    required this.color,
    required this.body,
  });

  final int surfaceGeneration;
  final int projectionGeneration;
  final int eventGeneration;
  final int draftGeneration;
  final int? cardToken;
  final BigInt expectedStoreRevision;
  final TerminalNotesIntentKind kind;
  final TerminalNotesColor? color;
  final String? body;
}

final class TerminalNotesNativeResult {
  TerminalNotesNativeResult({
    required this.intent,
    required this.disposition,
    required this.newStoreRevision,
    required this.newProjectionGeneration,
  }) {
    if (newStoreRevision < BigInt.zero ||
        newStoreRevision > TerminalNotesLimits.maximumUnsigned64 ||
        newProjectionGeneration <= 0 ||
        newProjectionGeneration > TerminalNotesLimits.maximumSignedGeneration) {
      throw ArgumentError('invalid native Note result generation');
    }
  }

  final TerminalNotesNativeIntent intent;
  final TerminalNotesResultDisposition disposition;
  final BigInt newStoreRevision;
  final int newProjectionGeneration;
}

final class TerminalNotesNativeOpenResult {
  const TerminalNotesNativeOpenResult._({
    required this.availability,
    this.surface,
  });

  const TerminalNotesNativeOpenResult.available(
    TerminalNotesNativeSurface surface,
  ) : this._(
        availability: TerminalNotesCapabilityAvailability.available,
        surface: surface,
      );

  const TerminalNotesNativeOpenResult.unavailable()
    : this._(
        availability: TerminalNotesCapabilityAvailability.nativeUnavailable,
      );

  final TerminalNotesCapabilityAvailability availability;
  final TerminalNotesNativeSurface? surface;

  bool get isAvailable => surface != null;
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
    required this.draftGeneration,
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
    required this.outstandingIntent,
    required this.emittedIntentCount,
    required this.appliedResultCount,
    required this.editorDirty,
    required this.confirmingDiscard,
    required this.focusTarget,
  });

  final int paneId;
  final int surfaceGeneration;
  final int projectionGeneration;
  final BigInt storeRevision;
  final int acceptedProjectionCount;
  final int rejectedProjectionCount;
  final int draftGeneration;
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
  final bool outstandingIntent;
  final int emittedIntentCount;
  final int appliedResultCount;
  final bool editorDirty;
  final bool confirmingDiscard;
  final TerminalNotesNativeFocusTarget focusTarget;
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
    required this.visibleAcknowledgementEligibleGeneration,
    required this.accessibilityAnnouncementCount,
    required this.animationMilliseconds,
    required this.bodyFontMilliPoints,
    required this.badgeDisplayCount,
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
  static const int _badgeCountCapped = 1 << 11;

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
  final int visibleAcknowledgementEligibleGeneration;
  final int accessibilityAnnouncementCount;
  final int animationMilliseconds;
  final int bodyFontMilliPoints;
  final int badgeDisplayCount;

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
  bool get badgeCountCapped => flags & _badgeCountCapped != 0;
}

final class TerminalNotesNativeSurface {
  static TerminalNotesNativeOpenResult tryOpen({
    TerminalNotesNativeBindings? bindings,
  }) {
    try {
      return TerminalNotesNativeOpenResult.available(
        TerminalNotesNativeSurface(bindings: bindings),
      );
    } on StateError {
      return const TerminalNotesNativeOpenResult.unavailable();
    } on ArgumentError {
      return const TerminalNotesNativeOpenResult.unavailable();
    }
  }

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
        raw.messageKey >= TerminalNotesMessageKey.values.length ||
        raw.focusTarget >= TerminalNotesNativeFocusTarget.values.length ||
        raw.interactionFlags & ~3 != 0) {
      throw const TerminalNotesNativeException('snapshot.visibility', -1);
    }
    return TerminalNotesNativeSnapshot(
      paneId: raw.paneId,
      surfaceGeneration: raw.surfaceGeneration,
      projectionGeneration: raw.projectionGeneration,
      storeRevision: raw.storeRevision,
      acceptedProjectionCount: raw.acceptedProjectionCount,
      rejectedProjectionCount: raw.rejectedProjectionCount,
      draftGeneration: raw.draftGeneration,
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
      outstandingIntent: raw.outstandingIntent,
      emittedIntentCount: raw.emittedIntentCount,
      appliedResultCount: raw.appliedResultCount,
      editorDirty: raw.interactionFlags & 1 != 0,
      confirmingDiscard: raw.interactionFlags & 2 != 0,
      focusTarget: TerminalNotesNativeFocusTarget.values[raw.focusTarget],
    );
  }

  bool focus(TerminalNotesNativeFocusTarget target) {
    if (target == TerminalNotesNativeFocusTarget.none) {
      throw ArgumentError.value(target, 'target');
    }
    final int status = _bindings.focus(_requireHandle(), target.index);
    if (status == nativeStatusOk) return true;
    if (status == nativeStatusNotFound) return false;
    throw TerminalNotesNativeException('focus', status);
  }

  TerminalNotesAttachDisposition attachToRenderer({
    required int rendererHandle,
    required int rendererGeneration,
  }) {
    RangeError.checkValueInInterval(
      rendererHandle,
      1,
      TerminalNotesLimits.maximumSignedGeneration,
      'rendererHandle',
    );
    RangeError.checkValueInInterval(
      rendererGeneration,
      1,
      TerminalNotesLimits.maximumSignedGeneration,
      'rendererGeneration',
    );
    final int status = _bindings.attachToRenderer(
      _requireHandle(),
      rendererHandle: rendererHandle,
      rendererGeneration: rendererGeneration,
    );
    return switch (status) {
      nativeStatusOk => TerminalNotesAttachDisposition.attached,
      nativeStatusNotFound =>
        TerminalNotesAttachDisposition.rendererUnavailable,
      nativeStatusBusy => TerminalNotesAttachDisposition.busy,
      _ => throw TerminalNotesNativeException('attachToRenderer', status),
    };
  }

  void detachFromHost() {
    final int status = _bindings.detachFromHost(_requireHandle());
    if (status != nativeStatusOk) {
      throw TerminalNotesNativeException('detachFromHost', status);
    }
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
      visibleAcknowledgementEligibleGeneration:
          raw.visibleAcknowledgementEligibleGeneration,
      accessibilityAnnouncementCount: raw.accessibilityAnnouncementCount,
      animationMilliseconds: raw.animationMilliseconds,
      bodyFontMilliPoints: raw.bodyFontMilliPoints,
      badgeDisplayCount: raw.badgeDisplayCount,
    );
  }

  TerminalNotesNativeIntent? takeIntent() {
    final TerminalNotesNativeRawIntent? raw = _bindings.takeIntent(
      _requireHandle(),
    );
    if (raw == null) return null;
    if (raw.kind >= TerminalNotesIntentKind.values.length ||
        (raw.color != TerminalNotesLimits.maximumUnsigned32 &&
            raw.color >= TerminalNotesColor.values.length)) {
      throw const TerminalNotesNativeException('takeIntent.enum', -1);
    }
    final TerminalNotesIntentKind kind =
        TerminalNotesIntentKind.values[raw.kind];
    final bool payloadKind =
        kind == TerminalNotesIntentKind.save ||
        kind == TerminalNotesIntentKind.copy;
    if (payloadKind != raw.payload.isNotEmpty) {
      throw const TerminalNotesNativeException('takeIntent.payload', -1);
    }
    return TerminalNotesNativeIntent(
      surfaceGeneration: raw.surfaceGeneration,
      projectionGeneration: raw.projectionGeneration,
      eventGeneration: raw.eventGeneration,
      draftGeneration: raw.draftGeneration,
      cardToken: raw.cardToken == 0 ? null : raw.cardToken,
      expectedStoreRevision: _unsigned64(raw.expectedStoreRevision),
      kind: kind,
      color: raw.color == TerminalNotesLimits.maximumUnsigned32
          ? null
          : TerminalNotesColor.values[raw.color],
      body: payloadKind
          ? utf8.decode(raw.payload, allowMalformed: false)
          : null,
    );
  }

  TerminalNotesResultApplyDisposition applyResult(
    TerminalNotesNativeResult result,
  ) {
    final TerminalNotesNativeIntent intent = result.intent;
    final int status = _bindings.applyResult(
      _requireHandle(),
      TerminalNotesNativeRawResult(
        surfaceGeneration: intent.surfaceGeneration,
        projectionGeneration: intent.projectionGeneration,
        eventGeneration: intent.eventGeneration,
        draftGeneration: intent.draftGeneration,
        newStoreRevision: result.newStoreRevision.toInt(),
        newProjectionGeneration: result.newProjectionGeneration,
        disposition: result.disposition.index,
      ),
    );
    return switch (status) {
      nativeStatusOk => TerminalNotesResultApplyDisposition.accepted,
      nativeStatusInvalidArgument =>
        TerminalNotesResultApplyDisposition.rejectedInvalid,
      nativeStatusStale => TerminalNotesResultApplyDisposition.rejectedStale,
      _ => TerminalNotesResultApplyDisposition.failed,
    };
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

  static BigInt _unsigned64(int value) =>
      value >= 0 ? BigInt.from(value) : BigInt.from(value) + (BigInt.one << 64);
}
