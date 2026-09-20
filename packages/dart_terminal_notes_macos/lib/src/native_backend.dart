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

final class TerminalNotesNativeRawSnapshot {
  const TerminalNotesNativeRawSnapshot({
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
    required this.firstSurfaceRgba,
    required this.firstAccentRgba,
    required this.bodyTextRgba,
    required this.animationMilliseconds,
    required this.bodyFontMilliPoints,
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
  final int firstSurfaceRgba;
  final int firstAccentRgba;
  final int bodyTextRgba;
  final int animationMilliseconds;
  final int bodyFontMilliPoints;
}

final class TerminalNotesNativeCardPresentationRawSnapshot {
  const TerminalNotesNativeCardPresentationRawSnapshot({
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
  final int color;
  final int status;
  final bool due;
  final int visibleLineLimit;
  final int surfaceRgba;
  final int accentRgba;
  final int bodyTextRgba;
  final bool nonColorCue;
  final ({double x, double y, double width, double height}) frame;
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

  TerminalNotesNativeCardPresentationRawSnapshot cardPresentationSnapshot(
    Object handle,
    int index,
  );

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
        firstSurfaceRgba: snapshot.ref.firstSurfaceRgba,
        firstAccentRgba: snapshot.ref.firstAccentRgba,
        bodyTextRgba: snapshot.ref.bodyTextRgba,
        animationMilliseconds: snapshot.ref.animationMilliseconds,
        bodyFontMilliPoints: snapshot.ref.bodyFontMilliPoints,
      );
    } finally {
      calloc.free(snapshot);
    }
  }

  @override
  TerminalNotesNativeCardPresentationRawSnapshot cardPresentationSnapshot(
    Object handle,
    int index,
  ) {
    final Pointer<_DtnCardPresentationSnapshotV1> snapshot =
        calloc<_DtnCardPresentationSnapshotV1>();
    try {
      snapshot.ref
        ..structSize = sizeOf<_DtnCardPresentationSnapshotV1>()
        ..version = 1;
      final int status = _surfaceCardPresentationSnapshot(
        _handle(handle),
        index,
        snapshot,
      );
      if (status != nativeStatusOk) {
        throw StateError('native Note card snapshot failed: $status');
      }
      return TerminalNotesNativeCardPresentationRawSnapshot(
        index: snapshot.ref.index,
        order: snapshot.ref.order,
        color: snapshot.ref.color,
        status: snapshot.ref.status,
        due: snapshot.ref.due != 0,
        visibleLineLimit: snapshot.ref.visibleLineLimit,
        surfaceRgba: snapshot.ref.surfaceRgba,
        accentRgba: snapshot.ref.accentRgba,
        bodyTextRgba: snapshot.ref.bodyTextRgba,
        nonColorCue: snapshot.ref.nonColorCue != 0,
        frame: (
          x: snapshot.ref.x,
          y: snapshot.ref.y,
          width: snapshot.ref.width,
          height: snapshot.ref.height,
        ),
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

  @Array<Uint32>(7)
  external Array<Uint32> reserved;
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

  @Uint32()
  external int firstSurfaceRgba;

  @Uint32()
  external int firstAccentRgba;

  @Uint32()
  external int bodyTextRgba;

  @Uint32()
  external int animationMilliseconds;

  @Uint32()
  external int bodyFontMilliPoints;

  @Array<Uint32>(7)
  external Array<Uint32> reserved;
}

final class _DtnCardPresentationSnapshotV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint32()
  external int index;

  @Uint32()
  external int order;

  @Uint32()
  external int color;

  @Uint32()
  external int status;

  @Uint32()
  external int due;

  @Uint32()
  external int visibleLineLimit;

  @Uint32()
  external int surfaceRgba;

  @Uint32()
  external int accentRgba;

  @Uint32()
  external int bodyTextRgba;

  @Uint32()
  external int nonColorCue;

  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;

  @Array<Uint32>(8)
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
  Int32 Function(Pointer<Void>, Uint32, Pointer<_DtnCardPresentationSnapshotV1>)
>(symbol: 'dtn_surface_card_presentation_snapshot', assetId: _assetId)
external int _surfaceCardPresentationSnapshot(
  Pointer<Void> surface,
  int index,
  Pointer<_DtnCardPresentationSnapshotV1> snapshot,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'dtn_surface_destroy',
  assetId: _assetId,
)
external void _surfaceDestroy(Pointer<Void> surface);

@Native<Uint64 Function()>(symbol: 'dtn_debug_live_surfaces', assetId: _assetId)
external int _debugLiveSurfaces();
