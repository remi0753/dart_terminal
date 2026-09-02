import 'dart:ffi';

const int runtimeUsageExitCode = 64;
const int runtimeSoftwareExitCode = 70;
const int runtimeTemporaryFailureExitCode = 75;

typedef _NativeAbiVersion = Uint32 Function();
typedef _DartAbiVersion = int Function();
typedef _NativeExitControl = Int32 Function(Int32 exitCode);
typedef _DartExitControl = int Function(int exitCode);

abstract final class RuntimeLifecycleHost {
  static const int _expectedAbiVersion = 1;

  static final DynamicLibrary _process = DynamicLibrary.process();
  static final _DartAbiVersion _abiVersion = _process
      .lookupFunction<_NativeAbiVersion, _DartAbiVersion>(
        'dt_runtime_lifecycle_abi_version',
      );
  static final _DartExitControl _setExitCode = _process
      .lookupFunction<_NativeExitControl, _DartExitControl>(
        'dt_runtime_lifecycle_set_exit_code',
      );
  static final _DartExitControl _requestTermination = _process
      .lookupFunction<_NativeExitControl, _DartExitControl>(
        'dt_runtime_lifecycle_request_termination',
      );

  static void setExitCode(int exitCode) {
    _validateAbi();
    _expectSuccess(_setExitCode(exitCode), 'set exit code');
  }

  static void requestTermination(int exitCode) {
    _validateAbi();
    _expectSuccess(_requestTermination(exitCode), 'request termination');
  }

  static void _validateAbi() {
    final int actual = _abiVersion();
    if (actual != _expectedAbiVersion) {
      throw StateError('runtime lifecycle ABI $actual != $_expectedAbiVersion');
    }
  }

  static void _expectSuccess(int result, String operation) {
    if (result != 0) {
      throw StateError('runtime lifecycle could not $operation: $result');
    }
  }
}
