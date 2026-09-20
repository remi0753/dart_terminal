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

abstract interface class TerminalNotesNativeBindings {
  int get abiVersion;

  Object createSurface();

  int applyProjection(Object handle, Uint8List bytes);

  TerminalNotesNativeRawSnapshot snapshot(Object handle);

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

@Native<Void Function(Pointer<Void>)>(
  symbol: 'dtn_surface_destroy',
  assetId: _assetId,
)
external void _surfaceDestroy(Pointer<Void> surface);

@Native<Uint64 Function()>(symbol: 'dtn_debug_live_surfaces', assetId: _assetId)
external int _debugLiveSurfaces();
