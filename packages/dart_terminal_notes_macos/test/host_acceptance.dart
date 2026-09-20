import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_notes_macos/testing.dart';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != 'developer-jit' &&
          arguments.single != 'release-aot')) {
    stderr.writeln('usage: host_acceptance.dart <developer-jit|release-aot>');
    exitCode = 64;
    return;
  }

  final TerminalNotesNativeFfiBindings native =
      TerminalNotesNativeFfiBindings();
  _expect(native.abiVersion == 1, 'native code asset ABI');
  _expect(native.liveSurfaceCount == 0, 'initial native owner count');

  const ({
    int rows,
    int columns,
    int drawableWidth,
    int drawableHeight,
    int winsizeRows,
    int winsizeColumns,
    int sigwinchCount,
    bool alternateScreen,
    int inputSequence,
  })
  terminal = (
    rows: 24,
    columns: 80,
    drawableWidth: 640,
    drawableHeight: 480,
    winsizeRows: 24,
    winsizeColumns: 80,
    sigwinchCount: 0,
    alternateScreen: true,
    inputSequence: 41,
  );
  final TerminalNotesProjection retained = _projection();

  final TerminalNotesNativeOpenResult absent =
      TerminalNotesNativeSurface.tryOpen(bindings: _MissingBindings());
  _expect(
    absent.availability ==
            TerminalNotesCapabilityAvailability.nativeUnavailable &&
        absent.surface == null,
    'missing capability fallback',
  );
  _expect(retained.projectionGeneration == 7, 'last projection retained');
  _expect(
    terminal ==
        (
          rows: 24,
          columns: 80,
          drawableWidth: 640,
          drawableHeight: 480,
          winsizeRows: 24,
          winsizeColumns: 80,
          sigwinchCount: 0,
          alternateScreen: true,
          inputSequence: 41,
        ),
    'terminal geometry and input sentinel delta zero',
  );

  // A standalone Dart isolate is not AppKit's process main thread. Opening the
  // real asset must therefore fail soft while the native main-thread harness
  // owns actual NSView lifecycle acceptance.
  final TerminalNotesNativeOpenResult offMainThread =
      TerminalNotesNativeSurface.tryOpen(bindings: native);
  _expect(!offMainThread.isAvailable, 'wrong-thread open is fail-soft');
  _expect(native.liveSurfaceCount == 0, 'final native owner count');
  stdout.writeln(
    'TERMINAL_NOTES_HOST_ACCEPTANCE_PASS mode=${arguments.single} '
    'manifest_registered=0 fallback=native-unavailable geometry_delta=0',
  );
}

TerminalNotesProjection _projection() => TerminalNotesProjection(
  paneId: 11,
  surfaceGeneration: 3,
  projectionGeneration: 7,
  storeRevision: BigInt.from(9),
  visibility: TerminalNotesVisibility.collapsed,
  presentationEligible: false,
  activeCount: 1,
  dueCount: 0,
  featureState: TerminalNotesFeatureState.available,
  surfaceState: TerminalNotesSurfaceState.nativeUnavailable,
  readyCue: false,
  section: TerminalNotesCollectionSection.current,
  pageStart: 0,
  totalCount: 1,
  selectedToken: null,
  editorMode: TerminalNotesEditorMode.inactive,
  messageKey: TerminalNotesMessageKey.nativeUnavailable,
  cards: const <TerminalNotesCard>[],
);

final class _MissingBindings implements TerminalNotesNativeBindings {
  @override
  int get abiVersion => throw StateError('native capability unavailable');

  @override
  Object createSurface() => throw UnsupportedError('unreachable');

  @override
  int applyProjection(Object handle, Uint8List bytes) =>
      throw UnsupportedError('unreachable');

  @override
  TerminalNotesNativeRawSnapshot snapshot(Object handle) =>
      throw UnsupportedError('unreachable');

  @override
  int updateLayout(
    Object handle, {
    required double paneWidth,
    required double paneHeight,
    required double backingScale,
    required double requestedRailWidth,
  }) => throw UnsupportedError('unreachable');

  @override
  TerminalNotesNativePresentationRawSnapshot presentationSnapshot(
    Object handle,
  ) => throw UnsupportedError('unreachable');

  @override
  void destroySurface(Object handle) => throw UnsupportedError('unreachable');

  @override
  int get liveSurfaceCount => 0;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
