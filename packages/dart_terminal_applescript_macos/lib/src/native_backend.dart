import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'api.dart';

const String _assetId =
    'package:dart_terminal_applescript_macos/'
    'dart_terminal_applescript_macos.dart';

const int nativeStatusOk = 0;
const int nativeStatusNotFound = 5;
const int nativeStatusBufferTooSmall = 7;
const int nativeStatusInternal = 10;

final class TerminalAppleScriptMacosTakeResult {
  const TerminalAppleScriptMacosTakeResult(this.status, [this.bytes]);

  final int status;
  final Uint8List? bytes;
}

abstract interface class TerminalAppleScriptMacosBindings {
  int sessionStart(int maximumPendingCommands, int timeoutMicros);

  int publishSnapshot(Uint8List bytes);

  TerminalAppleScriptMacosTakeResult takeCommand();

  int completeCommand(int operationId, int disposition, String? objectId);

  int sessionShutdown();

  TerminalAppleScriptMacosSummary summary();
}

final class FfiTerminalAppleScriptMacosBindings
    implements TerminalAppleScriptMacosBindings {
  @override
  int sessionStart(int maximumPendingCommands, int timeoutMicros) =>
      _sessionStart(maximumPendingCommands, timeoutMicros);

  @override
  int publishSnapshot(Uint8List bytes) {
    final Pointer<Uint8> pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return _publishSnapshot(pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  TerminalAppleScriptMacosTakeResult takeCommand() {
    final Pointer<Size> length = calloc<Size>();
    try {
      final int sizing = _takeCommand(nullptr, 0, length);
      if (sizing == nativeStatusNotFound) {
        return const TerminalAppleScriptMacosTakeResult(nativeStatusNotFound);
      }
      if (sizing != nativeStatusBufferTooSmall ||
          length.value <= 0 ||
          length.value > TerminalAppleScriptMacosLimits.maximumCommandBytes) {
        return TerminalAppleScriptMacosTakeResult(
          sizing == nativeStatusOk ? nativeStatusInternal : sizing,
        );
      }
      final Pointer<Uint8> output = calloc<Uint8>(length.value);
      try {
        final int status = _takeCommand(output, length.value, length);
        if (status != nativeStatusOk) {
          return TerminalAppleScriptMacosTakeResult(status);
        }
        return TerminalAppleScriptMacosTakeResult(
          status,
          Uint8List.fromList(output.asTypedList(length.value)),
        );
      } finally {
        calloc.free(output);
      }
    } finally {
      calloc.free(length);
    }
  }

  @override
  int completeCommand(int operationId, int disposition, String? objectId) {
    if (objectId == null) {
      return _completeCommand(operationId, disposition, nullptr, 0);
    }
    final List<int> bytes = objectId.codeUnits;
    final Pointer<Uint8> pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return _completeCommand(operationId, disposition, pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  int sessionShutdown() => _sessionShutdown();

  @override
  TerminalAppleScriptMacosSummary summary() {
    final Pointer<_DtasSummaryV1> summary = calloc<_DtasSummaryV1>();
    try {
      summary.ref
        ..structSize = sizeOf<_DtasSummaryV1>()
        ..version = 1;
      final int status = _debugSummary(summary);
      if (status != nativeStatusOk) {
        throw TerminalAppleScriptMacosException(
          operation: 'summary',
          status: status,
        );
      }
      return TerminalAppleScriptMacosSummary(
        generation: summary.ref.generation,
        windowCount: summary.ref.windowCount,
        tabCount: summary.ref.tabCount,
        terminalCount: summary.ref.terminalCount,
        queuedCommandCount: summary.ref.queuedCommandCount,
        pendingCommandCount: summary.ref.pendingCommandCount,
        resumedCommandCount: summary.ref.resumedCommandCount,
        rejectedCommandCount: summary.ref.rejectedCommandCount,
        started: summary.ref.started != 0,
        enabled: summary.ref.enabled != 0,
      );
    } finally {
      calloc.free(summary);
    }
  }
}

/// In-process acceptance seam that enters the same validated native queue as
/// Cocoa Scripting without sending an Apple Event or touching TCC state.
final class TerminalAppleScriptMacosSelfAutomation {
  const TerminalAppleScriptMacosSelfAutomation._();

  static void enqueueCommand(Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > TerminalAppleScriptMacosLimits.maximumCommandBytes) {
      throw ArgumentError.value(bytes.length, 'bytes');
    }
    final Pointer<Uint8> pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final int status = _enqueueSelfAutomationCommand(pointer, bytes.length);
      if (status != nativeStatusOk) {
        throw TerminalAppleScriptMacosException(
          operation: 'enqueueSelfAutomationCommand',
          status: status,
        );
      }
    } finally {
      calloc.free(pointer);
    }
  }
}

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

@Native<Int32 Function(Uint32, Uint64)>(
  symbol: 'dtas_session_start',
  assetId: _assetId,
)
external int _sessionStart(int maximumPendingCommands, int timeoutMicros);

@Native<Int32 Function(Pointer<Uint8>, Size)>(
  symbol: 'dtas_publish_snapshot',
  assetId: _assetId,
)
external int _publishSnapshot(Pointer<Uint8> bytes, int length);

@Native<Int32 Function(Pointer<Uint8>, Size, Pointer<Size>)>(
  symbol: 'dtas_take_command',
  assetId: _assetId,
)
external int _takeCommand(
  Pointer<Uint8> output,
  int capacity,
  Pointer<Size> outputLength,
);

@Native<Int32 Function(Uint64, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'dtas_complete_command',
  assetId: _assetId,
)
external int _completeCommand(
  int operationId,
  int disposition,
  Pointer<Uint8> objectId,
  int objectIdLength,
);

@Native<Int32 Function()>(symbol: 'dtas_session_shutdown', assetId: _assetId)
external int _sessionShutdown();

@Native<Int32 Function(Pointer<_DtasSummaryV1>)>(
  symbol: 'dtas_debug_summary',
  assetId: _assetId,
)
external int _debugSummary(Pointer<_DtasSummaryV1> summary);

@Native<Int32 Function(Pointer<Uint8>, Size)>(
  symbol: 'dtas_enqueue_self_automation_command',
  assetId: _assetId,
)
external int _enqueueSelfAutomationCommand(Pointer<Uint8> bytes, int length);
