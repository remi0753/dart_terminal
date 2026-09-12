import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'api.dart';

const int nativeStatusOk = 0;
const int nativeStatusNotFound = 5;
const int nativeStatusInternal = 10;

final class TerminalAppIntentsMacosTakeResult {
  const TerminalAppIntentsMacosTakeResult(
    this.status, {
    this.operationId,
    this.generation,
    this.action,
  });

  final int status;
  final int? operationId;
  final int? generation;
  final int? action;
}

abstract interface class TerminalAppIntentsMacosBindings {
  int sessionStart(int maximumPendingCommands, int timeoutMicros);

  int setEnabled(bool enabled);

  TerminalAppIntentsMacosTakeResult takeCommand();

  int completeCommand(int operationId, int generation, int disposition);

  int sessionShutdown();

  TerminalAppIntentsMacosSummary summary();

  int debugEnqueueAction(int action);
}

final class FfiTerminalAppIntentsMacosBindings
    implements TerminalAppIntentsMacosBindings {
  FfiTerminalAppIntentsMacosBindings(DynamicLibrary library)
    : _functions = _TerminalAppIntentsFunctions(library) {
    final int version = _functions.abiVersion();
    if (version != 1) {
      throw TerminalAppIntentsMacosException(
        operation: 'abiVersion',
        status: version,
      );
    }
  }

  final _TerminalAppIntentsFunctions _functions;

  @override
  int sessionStart(int maximumPendingCommands, int timeoutMicros) =>
      _functions.sessionStart(maximumPendingCommands, timeoutMicros);

  @override
  int setEnabled(bool enabled) => _functions.setEnabled(enabled ? 1 : 0);

  @override
  TerminalAppIntentsMacosTakeResult takeCommand() {
    final Pointer<Uint64> operationId = calloc<Uint64>();
    final Pointer<Uint64> generation = calloc<Uint64>();
    final Pointer<Uint32> action = calloc<Uint32>();
    try {
      final int status = _functions.takeCommand(
        operationId,
        generation,
        action,
      );
      if (status != nativeStatusOk) {
        return TerminalAppIntentsMacosTakeResult(status);
      }
      return TerminalAppIntentsMacosTakeResult(
        status,
        operationId: operationId.value,
        generation: generation.value,
        action: action.value,
      );
    } finally {
      calloc
        ..free(operationId)
        ..free(generation)
        ..free(action);
    }
  }

  @override
  int completeCommand(int operationId, int generation, int disposition) =>
      _functions.completeCommand(operationId, generation, disposition);

  @override
  int sessionShutdown() => _functions.sessionShutdown();

  @override
  TerminalAppIntentsMacosSummary summary() {
    final List<Pointer<Uint64>> counts = List<Pointer<Uint64>>.generate(
      7,
      (_) => calloc<Uint64>(),
      growable: false,
    );
    final Pointer<Uint32> started = calloc<Uint32>();
    final Pointer<Uint32> enabled = calloc<Uint32>();
    try {
      final int status = _functions.debugSummary(
        counts[0],
        counts[1],
        counts[2],
        counts[3],
        counts[4],
        counts[5],
        counts[6],
        started,
        enabled,
      );
      if (status != nativeStatusOk) {
        throw TerminalAppIntentsMacosException(
          operation: 'summary',
          status: status,
        );
      }
      return TerminalAppIntentsMacosSummary(
        generation: counts[0].value,
        queuedCommandCount: counts[1].value,
        pendingCommandCount: counts[2].value,
        acceptedCommandCount: counts[3].value,
        resolvedCommandCount: counts[4].value,
        rejectedCommandCount: counts[5].value,
        timedOutCommandCount: counts[6].value,
        started: started.value != 0,
        enabled: enabled.value != 0,
      );
    } finally {
      for (final Pointer<Uint64> count in counts) {
        calloc.free(count);
      }
      calloc
        ..free(started)
        ..free(enabled);
    }
  }

  @override
  int debugEnqueueAction(int action) => _functions.debugEnqueueAction(action);
}

final class TerminalAppIntentsMacosSelfAutomation {
  TerminalAppIntentsMacosSelfAutomation.withBindings(this._bindings);

  factory TerminalAppIntentsMacosSelfAutomation.fromLibrary(
    DynamicLibrary library,
  ) => TerminalAppIntentsMacosSelfAutomation.withBindings(
    FfiTerminalAppIntentsMacosBindings(library),
  );

  final TerminalAppIntentsMacosBindings _bindings;

  void enqueue(TerminalAppIntentAction action) {
    final int status = _bindings.debugEnqueueAction(action.nativeValue);
    if (status != nativeStatusOk) {
      throw TerminalAppIntentsMacosException(
        operation: 'debugEnqueueAction',
        status: status,
      );
    }
  }
}

typedef _AbiNative = Uint32 Function();
typedef _AbiDart = int Function();
typedef _StartNative = Int32 Function(Uint32, Uint64);
typedef _StartDart = int Function(int, int);
typedef _SetEnabledNative = Int32 Function(Uint32);
typedef _SetEnabledDart = int Function(int);
typedef _TakeNative = Int32 Function(
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint32>,
);
typedef _TakeDart = int Function(
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint32>,
);
typedef _CompleteNative = Int32 Function(Uint64, Uint64, Uint32);
typedef _CompleteDart = int Function(int, int, int);
typedef _ShutdownNative = Int32 Function();
typedef _ShutdownDart = int Function();
typedef _SummaryNative = Int32 Function(
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);
typedef _SummaryDart = int Function(
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint64>,
  Pointer<Uint32>,
  Pointer<Uint32>,
);
typedef _DebugEnqueueNative = Int32 Function(Uint32);
typedef _DebugEnqueueDart = int Function(int);

final class _TerminalAppIntentsFunctions {
  _TerminalAppIntentsFunctions(DynamicLibrary library)
    : abiVersion = library.lookupFunction<_AbiNative, _AbiDart>(
        'dtai_abi_version',
      ),
      sessionStart = library.lookupFunction<_StartNative, _StartDart>(
        'dtai_session_start',
      ),
      setEnabled = library.lookupFunction<_SetEnabledNative, _SetEnabledDart>(
        'dtai_session_set_enabled',
      ),
      takeCommand = library.lookupFunction<_TakeNative, _TakeDart>(
        'dtai_take_command',
      ),
      completeCommand = library.lookupFunction<_CompleteNative, _CompleteDart>(
        'dtai_complete_command',
      ),
      sessionShutdown = library.lookupFunction<_ShutdownNative, _ShutdownDart>(
        'dtai_session_shutdown',
      ),
      debugSummary = library.lookupFunction<_SummaryNative, _SummaryDart>(
        'dtai_debug_summary',
      ),
      debugEnqueueAction = library
          .lookupFunction<_DebugEnqueueNative, _DebugEnqueueDart>(
            'dtai_debug_enqueue_action',
          );

  final _AbiDart abiVersion;
  final _StartDart sessionStart;
  final _SetEnabledDart setEnabled;
  final _TakeDart takeCommand;
  final _CompleteDart completeCommand;
  final _ShutdownDart sessionShutdown;
  final _SummaryDart debugSummary;
  final _DebugEnqueueDart debugEnqueueAction;
}
