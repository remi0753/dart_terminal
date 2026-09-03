import 'dart:ffi';

typedef _NativeAbiVersion = Uint32 Function();
typedef _DartAbiVersion = int Function();
typedef _NativeRecordPhase = Int32 Function(Uint32 phase);
typedef _DartRecordPhase = int Function(int phase);

enum RuntimeDiagnosticPhase {
  rootStarting(1),
  rootReady(2),
  shutdownStarted(3),
  rootStopped(4);

  const RuntimeDiagnosticPhase(this.nativeValue);

  final int nativeValue;
}

abstract final class RuntimeDiagnosticsHost {
  static const int _expectedAbiVersion = 1;

  static final DynamicLibrary _process = DynamicLibrary.process();
  static final _DartAbiVersion _abiVersion = _process
      .lookupFunction<_NativeAbiVersion, _DartAbiVersion>(
        'dt_runtime_diagnostics_abi_version',
      );
  static final _DartRecordPhase _recordPhase = _process
      .lookupFunction<_NativeRecordPhase, _DartRecordPhase>(
        'dt_runtime_diagnostics_record_phase',
      );

  static void recordPhase(RuntimeDiagnosticPhase phase) {
    final int actual = _abiVersion();
    if (actual != _expectedAbiVersion) {
      throw StateError(
        'runtime diagnostics ABI $actual != $_expectedAbiVersion',
      );
    }
    final int result = _recordPhase(phase.nativeValue);
    if (result != 0) {
      throw StateError(
        'runtime diagnostics could not record ${phase.name}: $result',
      );
    }
  }
}
