import 'dart:async';
import 'dart:typed_data';

const String dartPtyMacosLibraryName = 'libdart_pty_macos.dylib';

final class PtyException implements Exception {
  const PtyException(this.message, {this.status, this.systemError});

  final String message;
  final int? status;
  final int? systemError;

  @override
  String toString() {
    final List<String> details = <String>[
      if (status != null) 'status $status',
      if (systemError != null && systemError != 0) 'errno $systemError',
    ];
    return details.isEmpty ? message : '$message (${details.join(', ')})';
  }
}

final class PtySize {
  const PtySize({required this.rows, required this.columns})
    : assert(rows > 0 && rows <= 65535),
      assert(columns > 0 && columns <= 65535);

  final int rows;
  final int columns;
}

final class PtyCommand {
  PtyCommand({
    required this.executable,
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    this.includeParentEnvironment = true,
    this.workingDirectory,
    this.loginShell = false,
    this.readBatchBytes = defaultReadBatchBytes,
    this.readBatchesPerEventLoopTurn = 0,
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment) {
    if (!executable.startsWith('/') || executable.contains('\u0000')) {
      throw ArgumentError.value(
        executable,
        'executable',
        'must be an absolute path without NUL',
      );
    }
    if (readBatchBytes <= 0 || readBatchBytes > maximumReadBatchBytes) {
      throw RangeError.range(
        readBatchBytes,
        1,
        maximumReadBatchBytes,
        'readBatchBytes',
      );
    }
    if (readBatchesPerEventLoopTurn < 0 ||
        readBatchesPerEventLoopTurn > maximumReadBatchesPerEventLoopTurn) {
      throw RangeError.range(
        readBatchesPerEventLoopTurn,
        0,
        maximumReadBatchesPerEventLoopTurn,
        'readBatchesPerEventLoopTurn',
      );
    }
    final String? directory = workingDirectory;
    if (directory != null &&
        (!directory.startsWith('/') || directory.contains('\u0000'))) {
      throw ArgumentError.value(
        directory,
        'workingDirectory',
        'must be an absolute path without NUL',
      );
    }
    for (final String argument in this.arguments) {
      if (argument.contains('\u0000')) {
        throw ArgumentError.value(
          argument,
          'arguments',
          'must not contain NUL',
        );
      }
    }
    for (final MapEntry<String, String> entry in this.environment.entries) {
      if (entry.key.isEmpty ||
          entry.key.contains('=') ||
          entry.key.contains('\u0000') ||
          entry.value.contains('\u0000')) {
        throw ArgumentError.value(
          entry.key,
          'environment',
          'keys must be non-empty and neither keys nor values may contain NUL',
        );
      }
    }
  }

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool includeParentEnvironment;
  final String? workingDirectory;
  final bool loginShell;
  final int readBatchBytes;
  final int readBatchesPerEventLoopTurn;

  static const int defaultReadBatchBytes = 64 * 1024;
  static const int maximumReadBatchBytes = 64 * 1024;
  static const int maximumReadBatchesPerEventLoopTurn = 8;
}

enum PtySignal { interrupt, suspend, quit, hangup, terminate, kill }

enum PtyWriteResult { accepted, backpressured }

final class PtyWriteReceipt {
  const PtyWriteReceipt({required this.result, required this.requestId});

  final PtyWriteResult result;
  final int? requestId;
}

enum PtyDiagnosticStage {
  writeEnqueued,
  writeDequeued,
  writeCompleted,
  writeError,
  forceCloseDequeued,
  signalDelivery,
  waitpidResult,
  exitPublished,
  stateSnapshot,
  termiosSnapshot,
  processExitReady,
  externalReapObserved,
}

/// Content-free observation of a native PTY lifecycle boundary.
///
/// Fields which do not apply to [stage] are null. No input/output bytes,
/// commands, environment values, working directories, or terminal text are
/// included.
final class PtyDiagnosticEvent {
  const PtyDiagnosticEvent({
    required this.stage,
    this.requestId,
    this.byteCount,
    this.queuedBytes,
    this.foregroundProcessGroup,
    this.sessionStateFlags,
    this.terminalLocalFlags,
    this.terminalEofCharacter,
    this.signal,
    this.signalTarget,
    this.operationResult,
    this.waitpidResult,
    this.childStatus,
    this.exitCode,
    this.exitSignal,
    this.childProcessId,
    this.systemError = 0,
  });

  final PtyDiagnosticStage stage;
  final int? requestId;
  final int? byteCount;
  final int? queuedBytes;
  final int? foregroundProcessGroup;
  final int? sessionStateFlags;
  final int? terminalLocalFlags;
  final int? terminalEofCharacter;
  final int? signal;
  final int? signalTarget;
  final int? operationResult;
  final int? waitpidResult;
  final int? childStatus;
  final int? exitCode;
  final int? exitSignal;
  final int? childProcessId;
  final int systemError;
}

final class PtyExit {
  const PtyExit({required this.exitCode, required this.signal});

  final int exitCode;
  final int? signal;
}

final class PtyStats {
  const PtyStats({
    required this.bytesRead,
    required this.bytesWritten,
    required this.readBatches,
    required this.writeBackpressureRejections,
    required this.maxReadInFlightBytes,
    required this.maxWriteQueuedBytes,
    required this.readPauseCount,
    required this.childPid,
    required this.hasExited,
  });

  final int bytesRead;
  final int bytesWritten;
  final int readBatches;
  final int writeBackpressureRejections;
  final int maxReadInFlightBytes;
  final int maxWriteQueuedBytes;
  final int readPauseCount;
  final int childPid;
  final bool hasExited;
}

/// Content-free identity snapshot of one live PTY process hierarchy.
final class PtyProcessSnapshot {
  const PtyProcessSnapshot({
    required this.childPid,
    required this.childProcessGroup,
    required this.foregroundProcessGroup,
    required this.childProcessGroupSystemError,
    required this.foregroundProcessGroupSystemError,
    required this.hasExited,
    this.terminalEchoEnabled,
    this.terminalAttributesSystemError = 0,
  });

  final int? childPid;
  final int? childProcessGroup;
  final int? foregroundProcessGroup;
  final int childProcessGroupSystemError;
  final int foregroundProcessGroupSystemError;
  final bool hasExited;
  final bool? terminalEchoEnabled;
  final int terminalAttributesSystemError;

  bool get isAvailable =>
      childPid != null &&
      childProcessGroup != null &&
      foregroundProcessGroup != null &&
      childProcessGroupSystemError == 0 &&
      foregroundProcessGroupSystemError == 0;

  bool get hasDistinctForegroundProcess =>
      isAvailable && foregroundProcessGroup != childProcessGroup;

  bool get hasTerminalAttributes =>
      terminalEchoEnabled != null && terminalAttributesSystemError == 0;
}

abstract interface class PtyProcess {
  int get pid;
  Stream<Uint8List> get output;
  Stream<PtyDiagnosticEvent> get diagnostics;
  Future<PtyExit> get exit;
  PtyStats? get finalStats;

  PtyProcessSnapshot processSnapshot();

  PtyWriteResult write(Uint8List bytes);
  PtyWriteReceipt writeTracked(Uint8List bytes);
  void resize(PtySize size);
  void sendSignal(PtySignal signal);
  void close({Duration gracePeriod = const Duration(seconds: 2)});
  void forceClose();
  Future<void> dispose();
}

abstract interface class PtyBackend {
  Future<PtyProcess> start(
    PtyCommand command, {
    PtySize initialSize = const PtySize(rows: 24, columns: 80),
    int readHighWaterBytes = 1024 * 1024,
    int readLowWaterBytes = 512 * 1024,
    int writeCapacityBytes = 1024 * 1024,
    bool enableDiagnostics = false,
  });
}
