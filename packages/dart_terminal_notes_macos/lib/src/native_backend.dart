import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const String _assetId =
    'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';

const int nativeStatusOk = 0;
const int nativeStatusInvalidArgument = 1;
const int nativeStatusUnsupportedVersion = 2;
const int nativeStatusStale = 3;
const int nativeStatusInternal = 4;
const int nativeStatusNotFound = 6;
const int nativeStatusBusy = 7;

final class TerminalNotesNativeRawSnapshot {
  const TerminalNotesNativeRawSnapshot({
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
    required this.interactionFlags,
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
  final int visibility;
  final bool presentationEligible;
  final bool initialized;
  final bool readyCue;
  final bool darkAppearance;
  final bool increaseContrast;
  final bool differentiateWithoutColor;
  final bool reduceMotion;
  final bool systemBadgeVisible;
  final int featureState;
  final int surfaceState;
  final int section;
  final int editorMode;
  final int messageKey;
  final int pageStart;
  final int totalCount;
  final int bodyFontMilliPoints;
  final bool outstandingIntent;
  final int emittedIntentCount;
  final int appliedResultCount;
  final int interactionFlags;
  final int focusTarget;
}

final class TerminalNotesNativeRawIntent {
  const TerminalNotesNativeRawIntent({
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.eventGeneration,
    required this.draftGeneration,
    required this.cardToken,
    required this.expectedStoreRevision,
    required this.kind,
    required this.color,
    required this.payload,
  });

  final int surfaceGeneration;
  final int projectionGeneration;
  final int eventGeneration;
  final int draftGeneration;
  final int cardToken;
  final int expectedStoreRevision;
  final int kind;
  final int color;
  final Uint8List payload;
}

final class TerminalNotesNativeRawResult {
  const TerminalNotesNativeRawResult({
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.eventGeneration,
    required this.draftGeneration,
    required this.newStoreRevision,
    required this.newProjectionGeneration,
    required this.disposition,
  });

  final int surfaceGeneration;
  final int projectionGeneration;
  final int eventGeneration;
  final int draftGeneration;
  final int newStoreRevision;
  final int newProjectionGeneration;
  final int disposition;
}

final class TerminalNotesNativePresentationRawSnapshot {
  const TerminalNotesNativePresentationRawSnapshot({
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

  final int projectionGeneration;
  final double paneWidth;
  final double paneHeight;
  final double backingScale;
  final ({double x, double y, double width, double height}) badgeHit;
  final ({double x, double y, double width, double height}) badgeVisual;
  final ({double x, double y, double width, double height}) rail;
  final ({double x, double y, double width, double height}) firstCard;
  final int flags;
  final int materializedCardCount;
  final int accessibilityNodeCount;
  final int accessibilityBodyCount;
  final int visibleAcknowledgementEligibleGeneration;
  final int accessibilityAnnouncementCount;
  final int animationMilliseconds;
  final int bodyFontMilliPoints;
  final int badgeDisplayCount;
}

abstract interface class TerminalNotesNativeBindings {
  int get abiVersion;

  Object createSurface();

  int applyProjection(Object handle, Uint8List bytes);

  TerminalNotesNativeRawSnapshot snapshot(Object handle);

  int updateLayout(
    Object handle, {
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    required double requestedRailWidth,
  });

  TerminalNotesNativePresentationRawSnapshot presentationSnapshot(
    Object handle,
  );

  TerminalNotesNativeRawIntent? takeIntent(Object handle);

  int applyResult(Object handle, TerminalNotesNativeRawResult result);

  int focus(Object handle, int target);

  int attachToRenderer(
    Object handle, {
    required int rendererHandle,
    required int rendererGeneration,
  });

  int detachFromHost(Object handle);

  void destroySurface(Object handle);

  int get liveSurfaceCount;
}

final class TerminalNotesNativeFfiBindings
    implements TerminalNotesNativeBindings {
  @override
  int get abiVersion => _abiVersion();

  @override
  Object createSurface() {
    final Pointer<Void> handle = _surfaceCreate();
    if (handle == nullptr) throw StateError('native Note surface unavailable');
    return handle;
  }

  @override
  TerminalNotesNativeRawIntent? takeIntent(Object handle) {
    final Pointer<_DtnSurfaceIntentV1> intent = calloc<_DtnSurfaceIntentV1>();
    final Pointer<Uint8> payload = calloc<Uint8>(4096);
    try {
      intent.ref
        ..structSize = sizeOf<_DtnSurfaceIntentV1>()
        ..version = 1;
      final int status = _surfaceTakeIntent(
        _handle(handle),
        intent,
        payload,
        4096,
      );
      if (status == nativeStatusNotFound) return null;
      if (status != nativeStatusOk) {
        throw StateError('native Note intent take failed: $status');
      }
      return TerminalNotesNativeRawIntent(
        surfaceGeneration: intent.ref.surfaceGeneration,
        projectionGeneration: intent.ref.projectionGeneration,
        eventGeneration: intent.ref.eventGeneration,
        draftGeneration: intent.ref.draftGeneration,
        cardToken: intent.ref.cardToken,
        expectedStoreRevision: intent.ref.expectedStoreRevision,
        kind: intent.ref.kind,
        color: intent.ref.color,
        payload: Uint8List.fromList(
          payload.asTypedList(intent.ref.payloadBytes),
        ),
      );
    } finally {
      calloc.free(payload);
      calloc.free(intent);
    }
  }

  @override
  int applyResult(Object handle, TerminalNotesNativeRawResult result) {
    final Pointer<_DtnSurfaceResultV1> native = calloc<_DtnSurfaceResultV1>();
    try {
      native.ref
        ..structSize = sizeOf<_DtnSurfaceResultV1>()
        ..version = 1
        ..surfaceGeneration = result.surfaceGeneration
        ..projectionGeneration = result.projectionGeneration
        ..eventGeneration = result.eventGeneration
        ..draftGeneration = result.draftGeneration
        ..newStoreRevision = result.newStoreRevision
        ..newProjectionGeneration = result.newProjectionGeneration
        ..disposition = result.disposition;
      return _surfaceApplyResult(_handle(handle), native);
    } finally {
      calloc.free(native);
    }
  }

  @override
  int focus(Object handle, int target) =>
      _surfaceFocus(_handle(handle), target);

  @override
  int attachToRenderer(
    Object handle, {
    required int rendererHandle,
    required int rendererGeneration,
  }) => _surfaceAttachToRenderer(
    _handle(handle),
    rendererHandle,
    rendererGeneration,
  );

  @override
  int detachFromHost(Object handle) => _surfaceDetachFromHost(_handle(handle));

  @override
  int applyProjection(Object handle, Uint8List bytes) {
    final Pointer<Void> nativeHandle = _handle(handle);
    final Pointer<Uint8> pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return _surfaceApplyProjection(nativeHandle, pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  TerminalNotesNativeRawSnapshot snapshot(Object handle) {
    final Pointer<_DtnSurfaceSnapshotV1> snapshot =
        calloc<_DtnSurfaceSnapshotV1>();
    try {
      snapshot.ref
        ..structSize = sizeOf<_DtnSurfaceSnapshotV1>()
        ..version = 1;
      final int status = _surfaceSnapshot(_handle(handle), snapshot);
      if (status != nativeStatusOk) {
        throw StateError('native Note snapshot failed: $status');
      }
      final int projectionFlags = snapshot.ref.projectionFlags;
      return TerminalNotesNativeRawSnapshot(
        paneId: snapshot.ref.paneId,
        surfaceGeneration: snapshot.ref.surfaceGeneration,
        projectionGeneration: snapshot.ref.projectionGeneration,
        storeRevision:
            (_unsigned64(snapshot.ref.storeRevisionHigh) << 64) |
            _unsigned64(snapshot.ref.storeRevisionLow),
        acceptedProjectionCount: snapshot.ref.acceptedProjectionCount,
        rejectedProjectionCount: snapshot.ref.rejectedProjectionCount,
        draftGeneration: snapshot.ref.draftGeneration,
        activeCount: snapshot.ref.activeCount,
        dueCount: snapshot.ref.dueCount,
        projectedCardCount: snapshot.ref.projectedCardCount,
        materializedCardCount: snapshot.ref.materializedCardCount,
        packetBytes: snapshot.ref.packetBytes,
        visibility: snapshot.ref.visibility,
        presentationEligible: snapshot.ref.presentationEligible != 0,
        initialized: snapshot.ref.initialized != 0,
        readyCue: projectionFlags & (1 << 1) != 0,
        darkAppearance: projectionFlags & (1 << 2) != 0,
        increaseContrast: projectionFlags & (1 << 3) != 0,
        differentiateWithoutColor: projectionFlags & (1 << 4) != 0,
        reduceMotion: projectionFlags & (1 << 5) != 0,
        systemBadgeVisible: projectionFlags & (1 << 6) != 0,
        featureState: snapshot.ref.featureState,
        surfaceState: snapshot.ref.surfaceState,
        section: snapshot.ref.section,
        editorMode: snapshot.ref.editorMode,
        messageKey: snapshot.ref.messageKey,
        pageStart: snapshot.ref.pageStart,
        totalCount: snapshot.ref.totalCount,
        bodyFontMilliPoints: snapshot.ref.bodyFontMilliPoints,
        outstandingIntent: snapshot.ref.outstandingIntent != 0,
        emittedIntentCount: snapshot.ref.emittedIntentCount,
        appliedResultCount: snapshot.ref.appliedResultCount,
        interactionFlags: snapshot.ref.interactionFlags,
        focusTarget: snapshot.ref.focusTarget,
      );
    } finally {
      calloc.free(snapshot);
    }
  }

  @override
  int updateLayout(
    Object handle, {
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    required double requestedRailWidth,
  }) {
    final Pointer<_DtnLayoutV1> layout = calloc<_DtnLayoutV1>();
    try {
      layout.ref
        ..structSize = sizeOf<_DtnLayoutV1>()
        ..version = 1
        ..paneWidth = paneWidth
        ..paneHeight = paneHeight
        ..backingScale = backingScale
        ..requestedRailWidth = requestedRailWidth;
      return _surfaceUpdateLayout(_handle(handle), layout);
    } finally {
      calloc.free(layout);
    }
  }

  @override
  TerminalNotesNativePresentationRawSnapshot presentationSnapshot(
    Object handle,
  ) {
    final Pointer<_DtnPresentationSnapshotV1> snapshot =
        calloc<_DtnPresentationSnapshotV1>();
    try {
      snapshot.ref
        ..structSize = sizeOf<_DtnPresentationSnapshotV1>()
        ..version = 1;
      final int status = _surfacePresentationSnapshot(
        _handle(handle),
        snapshot,
      );
      if (status != nativeStatusOk) {
        throw StateError('native Note presentation snapshot failed: $status');
      }
      return TerminalNotesNativePresentationRawSnapshot(
        projectionGeneration: snapshot.ref.projectionGeneration,
        paneWidth: snapshot.ref.paneWidth,
        paneHeight: snapshot.ref.paneHeight,
        backingScale: snapshot.ref.backingScale,
        badgeHit: (
          x: snapshot.ref.badgeHitX,
          y: snapshot.ref.badgeHitY,
          width: snapshot.ref.badgeHitWidth,
          height: snapshot.ref.badgeHitHeight,
        ),
        badgeVisual: (
          x: snapshot.ref.badgeVisualX,
          y: snapshot.ref.badgeVisualY,
          width: snapshot.ref.badgeVisualWidth,
          height: snapshot.ref.badgeVisualHeight,
        ),
        rail: (
          x: snapshot.ref.railX,
          y: snapshot.ref.railY,
          width: snapshot.ref.railWidth,
          height: snapshot.ref.railHeight,
        ),
        firstCard: (
          x: snapshot.ref.firstCardX,
          y: snapshot.ref.firstCardY,
          width: snapshot.ref.firstCardWidth,
          height: snapshot.ref.firstCardHeight,
        ),
        flags: snapshot.ref.flags,
        materializedCardCount: snapshot.ref.materializedCardCount,
        accessibilityNodeCount: snapshot.ref.accessibilityNodeCount,
        accessibilityBodyCount: snapshot.ref.accessibilityBodyCount,
        visibleAcknowledgementEligibleGeneration:
            snapshot.ref.visibleAcknowledgementEligibleGeneration,
        accessibilityAnnouncementCount:
            snapshot.ref.accessibilityAnnouncementCount,
        animationMilliseconds: snapshot.ref.animationMilliseconds,
        bodyFontMilliPoints: snapshot.ref.bodyFontMilliPoints,
        badgeDisplayCount: snapshot.ref.badgeDisplayCount,
      );
    } finally {
      calloc.free(snapshot);
    }
  }

  @override
  void destroySurface(Object handle) => _surfaceDestroy(_handle(handle));

  @override
  int get liveSurfaceCount => _debugLiveSurfaces();

  static Pointer<Void> _handle(Object handle) {
    if (handle is! Pointer<Void> || handle == nullptr) {
      throw ArgumentError.value(handle, 'handle');
    }
    return handle;
  }

  static BigInt _unsigned64(int value) =>
      value >= 0 ? BigInt.from(value) : BigInt.from(value) + (BigInt.one << 64);
}

final class _DtnSurfaceSnapshotV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int paneId;

  @Uint64()
  external int surfaceGeneration;

  @Uint64()
  external int projectionGeneration;

  @Uint64()
  external int storeRevisionLow;

  @Uint64()
  external int storeRevisionHigh;

  @Uint64()
  external int acceptedProjectionCount;

  @Uint64()
  external int rejectedProjectionCount;

  @Uint64()
  external int draftGeneration;

  @Uint32()
  external int activeCount;

  @Uint32()
  external int dueCount;

  @Uint32()
  external int projectedCardCount;

  @Uint32()
  external int materializedCardCount;

  @Uint32()
  external int packetBytes;

  @Uint32()
  external int visibility;

  @Uint32()
  external int presentationEligible;

  @Uint32()
  external int initialized;

  @Uint32()
  external int projectionFlags;

  @Uint32()
  external int featureState;

  @Uint32()
  external int surfaceState;

  @Uint32()
  external int section;

  @Uint32()
  external int editorMode;

  @Uint32()
  external int messageKey;

  @Uint32()
  external int pageStart;

  @Uint32()
  external int totalCount;

  @Uint32()
  external int bodyFontMilliPoints;

  @Uint32()
  external int outstandingIntent;

  @Uint32()
  external int emittedIntentCount;

  @Uint32()
  external int appliedResultCount;

  @Uint32()
  external int interactionFlags;

  @Uint32()
  external int focusTarget;
}

final class _DtnLayoutV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Double()
  external double paneWidth;

  @Double()
  external double paneHeight;

  @Double()
  external double backingScale;

  @Double()
  external double requestedRailWidth;

  @Array<Uint32>(8)
  external Array<Uint32> reserved;
}

final class _DtnPresentationSnapshotV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int projectionGeneration;

  @Double()
  external double paneWidth;

  @Double()
  external double paneHeight;

  @Double()
  external double backingScale;

  @Double()
  external double badgeHitX;

  @Double()
  external double badgeHitY;

  @Double()
  external double badgeHitWidth;

  @Double()
  external double badgeHitHeight;

  @Double()
  external double badgeVisualX;

  @Double()
  external double badgeVisualY;

  @Double()
  external double badgeVisualWidth;

  @Double()
  external double badgeVisualHeight;

  @Double()
  external double railX;

  @Double()
  external double railY;

  @Double()
  external double railWidth;

  @Double()
  external double railHeight;

  @Double()
  external double firstCardX;

  @Double()
  external double firstCardY;

  @Double()
  external double firstCardWidth;

  @Double()
  external double firstCardHeight;

  @Uint32()
  external int flags;

  @Uint32()
  external int materializedCardCount;

  @Uint32()
  external int accessibilityNodeCount;

  @Uint32()
  external int accessibilityBodyCount;

  @Uint64()
  external int visibleAcknowledgementEligibleGeneration;

  @Uint64()
  external int accessibilityAnnouncementCount;

  @Uint32()
  external int animationMilliseconds;

  @Uint32()
  external int bodyFontMilliPoints;

  @Uint32()
  external int badgeDisplayCount;

  @Array<Uint32>(5)
  external Array<Uint32> reserved;
}

final class _DtnSurfaceIntentV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int surfaceGeneration;

  @Uint64()
  external int projectionGeneration;

  @Uint64()
  external int eventGeneration;

  @Uint64()
  external int draftGeneration;

  @Uint64()
  external int cardToken;

  @Uint64()
  external int expectedStoreRevision;

  @Uint32()
  external int kind;

  @Uint32()
  external int payloadBytes;

  @Uint32()
  external int color;

  @Uint32()
  external int reserved0;

  @Array<Uint32>(10)
  external Array<Uint32> reserved;
}

final class _DtnSurfaceResultV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int surfaceGeneration;

  @Uint64()
  external int projectionGeneration;

  @Uint64()
  external int eventGeneration;

  @Uint64()
  external int draftGeneration;

  @Uint64()
  external int newStoreRevision;

  @Uint64()
  external int newProjectionGeneration;

  @Uint32()
  external int disposition;

  @Uint32()
  external int reserved0;

  @Array<Uint32>(6)
  external Array<Uint32> reserved;
}

@Native<Uint32 Function()>(symbol: 'dtn_abi_version', assetId: _assetId)
external int _abiVersion();

@Native<Pointer<Void> Function()>(
  symbol: 'dtn_surface_create',
  assetId: _assetId,
)
external Pointer<Void> _surfaceCreate();

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size)>(
  symbol: 'dtn_surface_apply_projection',
  assetId: _assetId,
)
external int _surfaceApplyProjection(
  Pointer<Void> surface,
  Pointer<Uint8> bytes,
  int length,
);

@Native<Int32 Function(Pointer<Void>, Pointer<_DtnSurfaceSnapshotV1>)>(
  symbol: 'dtn_surface_snapshot',
  assetId: _assetId,
)
external int _surfaceSnapshot(
  Pointer<Void> surface,
  Pointer<_DtnSurfaceSnapshotV1> snapshot,
);

@Native<Int32 Function(Pointer<Void>, Pointer<_DtnLayoutV1>)>(
  symbol: 'dtn_surface_update_layout',
  assetId: _assetId,
)
external int _surfaceUpdateLayout(
  Pointer<Void> surface,
  Pointer<_DtnLayoutV1> layout,
);

@Native<Int32 Function(Pointer<Void>, Pointer<_DtnPresentationSnapshotV1>)>(
  symbol: 'dtn_surface_presentation_snapshot',
  assetId: _assetId,
)
external int _surfacePresentationSnapshot(
  Pointer<Void> surface,
  Pointer<_DtnPresentationSnapshotV1> snapshot,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<_DtnSurfaceIntentV1>,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'dtn_surface_take_intent', assetId: _assetId)
external int _surfaceTakeIntent(
  Pointer<Void> surface,
  Pointer<_DtnSurfaceIntentV1> intent,
  Pointer<Uint8> payload,
  int payloadCapacity,
);

@Native<Int32 Function(Pointer<Void>, Pointer<_DtnSurfaceResultV1>)>(
  symbol: 'dtn_surface_apply_result',
  assetId: _assetId,
)
external int _surfaceApplyResult(
  Pointer<Void> surface,
  Pointer<_DtnSurfaceResultV1> result,
);

@Native<Int32 Function(Pointer<Void>, Uint32)>(
  symbol: 'dtn_surface_focus',
  assetId: _assetId,
)
external int _surfaceFocus(Pointer<Void> surface, int target);

@Native<Int32 Function(Pointer<Void>, Uint64, Uint64)>(
  symbol: 'dtn_surface_attach_to_renderer',
  assetId: _assetId,
)
external int _surfaceAttachToRenderer(
  Pointer<Void> surface,
  int rendererHandle,
  int rendererGeneration,
);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'dtn_surface_detach_from_host',
  assetId: _assetId,
)
external int _surfaceDetachFromHost(Pointer<Void> surface);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'dtn_surface_destroy',
  assetId: _assetId,
)
external void _surfaceDestroy(Pointer<Void> surface);

@Native<Uint64 Function()>(symbol: 'dtn_debug_live_surfaces', assetId: _assetId)
external int _debugLiveSurfaces();
