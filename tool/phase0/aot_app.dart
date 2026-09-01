import 'dart:async';
import 'dart:ffi';
import 'dart:io';

typedef _Uint32Native = Uint32 Function();
typedef _Uint32Dart = int Function();
typedef _Int32Native = Int32 Function();
typedef _Int32Dart = int Function();
typedef _ReportSuccessNative = Int32 Function(Uint64);
typedef _ReportSuccessDart = int Function(int);

void main() {
  final DynamicLibrary process = DynamicLibrary.process();
  final _Uint32Dart abiVersion = process
      .lookupFunction<_Uint32Native, _Uint32Dart>('dt_phase0_aot_abi_version');
  final _Int32Dart isMainThread = process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_is_main_thread');
  final _Int32Dart showWindow = process
      .lookupFunction<_Int32Native, _Int32Dart>('dt_phase0_aot_show_window');
  final _ReportSuccessDart reportSuccess = process
      .lookupFunction<_ReportSuccessNative, _ReportSuccessDart>(
        'dt_phase0_aot_report_success',
      );
  final _Int32Dart terminate = process.lookupFunction<_Int32Native, _Int32Dart>(
    'dt_phase0_aot_terminate',
  );

  final Stopwatch elapsed = Stopwatch()..start();
  final int abi = abiVersion();
  final int initialMainThread = isMainThread();
  final int showStatus = showWindow();
  stdout.writeln(
    'PHASE0_AOT_START '
    'abi=$abi main_thread=$initialMainThread show_status=$showStatus',
  );

  if (abi != 1 || initialMainThread != 1 || showStatus != 0) {
    stderr.writeln('PHASE0_AOT_FAIL initial validation failed');
    terminate();
    return;
  }

  Timer(const Duration(milliseconds: 250), () {
    final int timerMainThread = isMainThread();
    final int elapsedMicros = elapsed.elapsedMicroseconds;
    if (timerMainThread != 1) {
      stderr.writeln('PHASE0_AOT_FAIL Timer callback left the main thread');
      terminate();
      return;
    }

    final int reportStatus = reportSuccess(elapsedMicros);
    stdout.writeln(
      'PHASE0_AOT_DART_PASS '
      'timer_main_thread=$timerMainThread '
      'elapsed_us=$elapsedMicros report_status=$reportStatus',
    );
    terminate();
  });
}
