import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const String _assetId =
    'package:dart_terminal_applescript_macos/'
    'dart_terminal_applescript_macos.dart';

@Native<Uint32 Function()>(symbol: 'dtas_abi_version', assetId: _assetId)
external int _abiVersion();

@Native<Int32 Function(Uint32, Uint64)>(
  symbol: 'dtas_session_start',
  assetId: _assetId,
)
external int _sessionStart(int maximumPendingCommands, int timeoutMicros);

@Native<Int32 Function(Pointer<_DtasSummaryV1>)>(
  symbol: 'dtas_debug_summary',
  assetId: _assetId,
)
external int _debugSummary(Pointer<_DtasSummaryV1> summary);

final class _DtasSummaryV1 extends Struct {
  @Uint32()
  external int structSize;

  @Uint32()
  external int version;

  @Uint64()
  external int generation;

  @Uint64()
  external int windowCount;

  @Uint64()
  external int tabCount;

  @Uint64()
  external int terminalCount;

  @Uint64()
  external int queuedCommandCount;

  @Uint64()
  external int pendingCommandCount;

  @Uint64()
  external int resumedCommandCount;

  @Uint64()
  external int rejectedCommandCount;

  @Uint32()
  external int started;

  @Uint32()
  external int enabled;

  @Array<Uint32>(4)
  external Array<Uint32> reserved;
}

void main() {
  if (_abiVersion() != 1 || _sessionStart(1, 1000) != 8) {
    stderr.writeln('unexpected AppleScript native ABI or initialization state');
    exitCode = 1;
    return;
  }
  final Pointer<_DtasSummaryV1> summary = calloc<_DtasSummaryV1>();
  try {
    summary.ref
      ..structSize = sizeOf<_DtasSummaryV1>()
      ..version = 1;
    if (_debugSummary(summary) != 8) {
      stderr.writeln('AppleScript native asset accepted a non-AppKit thread');
      exitCode = 1;
      return;
    }
  } finally {
    calloc.free(summary);
  }
  stdout.writeln('terminal AppleScript native asset hook passed');
}
