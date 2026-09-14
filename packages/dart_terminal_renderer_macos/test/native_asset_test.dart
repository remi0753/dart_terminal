import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

@Native<Uint32 Function()>(
  symbol: 'dtr_abi_version',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _abiVersion();

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_view_count',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _liveViewCount();

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_font_catalog_count',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _liveFontCatalogCount();

@Native<Int32 Function()>(
  symbol: 'dtr_debug_live_metal_renderer_count',
  assetId:
      'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart',
)
external int _liveMetalRendererCount();

void main() => runNativeAssetTests();

void runNativeAssetTests() {
  if (terminalRendererMacosCapabilityId != 'dart_terminal_renderer_macos') {
    stderr.writeln('unexpected terminal renderer capability identifier');
    exitCode = 1;
  }
  if (terminalMetalViewProviderIdentifier !=
      'dart_terminal.TerminalMetalView') {
    stderr.writeln('unexpected terminal renderer provider identifier');
    exitCode = 1;
  }
  if (TerminalRendererMacos.isInitialized) {
    stderr.writeln('terminal renderer facade starts initialized');
    exitCode = 1;
  }
  try {
    TerminalRendererMacos.createView();
    stderr.writeln('terminal renderer view creation skipped initialization');
    exitCode = 1;
  } on StateError {
    // Expected: the facade must explicitly load the declared capability first.
  }
  if (_abiVersion() != 12) {
    stderr.writeln('unexpected terminal renderer native asset ABI');
    exitCode = 1;
  }
  final Uint8List presentation =
      TerminalRendererMacos.encodeBackgroundOpacityOperation(0.625);
  final ByteData presentationData = ByteData.sublistView(presentation);
  if (presentation.length != 24 ||
      presentationData.getUint32(0, Endian.little) != 24 ||
      presentationData.getUint32(4, Endian.little) != 1 ||
      presentationData.getUint32(8, Endian.little) != 9 ||
      presentationData.getUint32(12, Endian.little) != 0 ||
      presentationData.getFloat64(16, Endian.little) != 0.625) {
    stderr.writeln('terminal background presentation encoding drifted');
    exitCode = 1;
  }
  for (final double invalid in <double>[
    -0.01,
    1.01,
    double.nan,
    double.infinity,
  ]) {
    try {
      TerminalRendererMacos.encodeBackgroundOpacityOperation(invalid);
      stderr.writeln('invalid terminal background opacity was encoded');
      exitCode = 1;
    } on RangeError {
      // Expected.
    }
  }
  if (_liveViewCount() != 0) {
    stderr.writeln('terminal renderer asset starts with a live view');
    exitCode = 1;
  }
  if (_liveFontCatalogCount() != 0) {
    stderr.writeln('terminal renderer asset starts with a live font catalog');
    exitCode = 1;
  }
  if (_liveMetalRendererCount() != 0) {
    stderr.writeln('terminal renderer asset starts with a live Metal renderer');
    exitCode = 1;
  }
  if (exitCode == 0) {
    stdout.writeln('terminal renderer native asset hook passed');
  }
}
