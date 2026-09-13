import 'package:dart_process_resource_macos/dart_process_resource_macos.dart';

/// A content-free snapshot of resources owned by the current product process.
final class TerminalProcessResourceSnapshot {
  const TerminalProcessResourceSnapshot({
    required this.cpuTimeMicroseconds,
    required this.currentResidentBytes,
    required this.peakResidentBytes,
  });

  final int cpuTimeMicroseconds;
  final int currentResidentBytes;
  final int peakResidentBytes;
}

/// A fixed-window delta derived from two monotonic process snapshots.
final class TerminalProcessResourceWindow {
  TerminalProcessResourceWindow({
    required this.before,
    required this.after,
    required this.elapsedMicroseconds,
  }) : cpuMicroseconds = after.cpuTimeMicroseconds - before.cpuTimeMicroseconds,
       maximumResidentBytes =
           before.currentResidentBytes > after.currentResidentBytes
           ? before.currentResidentBytes
           : after.currentResidentBytes {
    if (elapsedMicroseconds <= 0) {
      throw ArgumentError.value(elapsedMicroseconds, 'elapsedMicroseconds');
    }
    if (cpuMicroseconds < 0) {
      throw StateError('process CPU time regressed');
    }
    if (before.currentResidentBytes <= 0 ||
        after.currentResidentBytes <= 0 ||
        before.peakResidentBytes <= 0 ||
        after.peakResidentBytes <= 0) {
      throw StateError('process resident memory is unavailable');
    }
  }

  final TerminalProcessResourceSnapshot before;
  final TerminalProcessResourceSnapshot after;
  final int elapsedMicroseconds;
  final int cpuMicroseconds;
  final int maximumResidentBytes;

  int get cpuBasisPoints => cpuMicroseconds * 10000 ~/ elapsedMicroseconds;
}

/// Samples current-process CPU time through POSIX `getrusage` and RSS through
/// Dart's public process information API. This intentionally does not retain a
/// process identifier, command, path, environment, or raw application data.
final class TerminalCurrentProcessResourceSampler {
  TerminalCurrentProcessResourceSampler()
    : _sampler = MacosCurrentProcessResourceSampler();

  final MacosCurrentProcessResourceSampler _sampler;

  static const int maximumDescriptorScanCount =
      MacosCurrentProcessResourceSampler.maximumDescriptorScanCount;

  TerminalProcessResourceSnapshot snapshot() {
    final MacosCurrentProcessResourceSnapshot snapshot = _sampler.snapshot();
    return TerminalProcessResourceSnapshot(
      cpuTimeMicroseconds: snapshot.cpuTimeMicroseconds,
      currentResidentBytes: snapshot.currentResidentBytes,
      peakResidentBytes: snapshot.peakResidentBytes,
    );
  }

  /// Counts open current-process descriptors without retaining their identity.
  int openFileDescriptorCount() => _sampler.openFileDescriptorCount();
}
