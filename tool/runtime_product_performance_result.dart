final class RuntimeProductPerformanceResult {
  const RuntimeProductPerformanceResult._({
    required this.startupMicroseconds,
    required this.refreshIntervalMicroseconds,
    required this.inputP95Microseconds,
    required this.visibleP95Microseconds,
    required this.visibleBudgetMicroseconds,
    required this.frameSamples,
    required this.frameP95Microseconds,
    required this.frameBudgetMicroseconds,
    required this.idleWindowMicroseconds,
    required this.idleCpuMicroseconds,
    required this.idleCpuBasisPoints,
    required this.idleResidentBytes,
    required this.workloadResidentBytes,
    required this.peakResidentBytes,
    required this.scrollbackAllocatedBytes,
    required this.occludedWindowMicroseconds,
    required this.occludedCpuMicroseconds,
    required this.occludedCpuBasisPoints,
    required this.occludedResidentBytes,
    required this.aggregateCpuBasisPoints,
  });

  static const int startupBudgetMicroseconds = 5000000;
  static const int maximumRefreshIntervalMicroseconds = 50000;
  static const int maximumInputP95Microseconds = 2000;
  static const int visibleSlackMicroseconds = 4000;
  static const int minimumResourceWindowMicroseconds = 2000000;
  static const int maximumResourceWindowMicroseconds = 10000000;
  static const int resourceWorkloadBytes = 22048;
  static const int residentMemoryBudgetBytes = 512 * 1024 * 1024;
  static const int scrollbackMinimumLines = 9745;
  static const int scrollbackMaximumLines = 10000;
  static const int scrollbackPageRows = 256;
  static const int scrollbackMaximumBytes = 64 * 1024 * 1024;

  static final RegExp _machineLine = RegExp(
    r'^TERMINAL_PRODUCT_PERFORMANCE_TEST refresh_samples=8 '
    r'refresh_interval_us=([1-9][0-9]*) input_samples=7 '
    r'input_p95_us=([1-9][0-9]*) visible_p95_us=([1-9][0-9]*) '
    r'visible_budget_us=([1-9][0-9]*) frame_samples=([1-9][0-9]*) '
    r'frame_p95_us=([1-9][0-9]*) frame_budget_us=([1-9][0-9]*) '
    r'idle_build_delta=0 idle_frame_delta=0 occluded_build_delta=0 '
    r'occluded_frame_delta=0 resume_frame=true pending_bound=true '
    r'content_free=true$',
    multiLine: true,
  );
  static final RegExp _resourceMachineLine = RegExp(
    r'^TERMINAL_PRODUCT_RESOURCE_TEST idle_window_us=([1-9][0-9]*) '
    r'idle_cpu_us=([0-9]+) idle_cpu_basis_points=([0-9]+) '
    r'idle_rss_bytes=([1-9][0-9]*) workload_bytes=([1-9][0-9]*) '
    r'workload_rss_bytes=([1-9][0-9]*) peak_rss_bytes=([1-9][0-9]*) '
    r'rss_budget_bytes=([1-9][0-9]*) scrollback_lines=([1-9][0-9]*) '
    r'scrollback_pages=([1-9][0-9]*) '
    r'scrollback_allocated_bytes=([1-9][0-9]*) '
    r'scrollback_max_bytes=([1-9][0-9]*) '
    r'occluded_window_us=([1-9][0-9]*) occluded_cpu_us=([0-9]+) '
    r'occluded_cpu_basis_points=([0-9]+) '
    r'occluded_rss_bytes=([1-9][0-9]*) '
    r'aggregate_cpu_basis_points=([0-9]+) idle_frame_delta=0 '
    r'occluded_frame_delta=0 resume_frame=true rss_bound=(true|false) '
    r'cpu_bound=(true|false) resource_counts_bound=true panes=1 sessions=1 '
    r'metal=1 content_free=true$',
    multiLine: true,
  );

  final int startupMicroseconds;
  final int refreshIntervalMicroseconds;
  final int inputP95Microseconds;
  final int visibleP95Microseconds;
  final int visibleBudgetMicroseconds;
  final int frameSamples;
  final int frameP95Microseconds;
  final int frameBudgetMicroseconds;
  final int idleWindowMicroseconds;
  final int idleCpuMicroseconds;
  final int idleCpuBasisPoints;
  final int idleResidentBytes;
  final int workloadResidentBytes;
  final int peakResidentBytes;
  final int scrollbackAllocatedBytes;
  final int occludedWindowMicroseconds;
  final int occludedCpuMicroseconds;
  final int occludedCpuBasisPoints;
  final int occludedResidentBytes;
  final int aggregateCpuBasisPoints;

  static RuntimeProductPerformanceResult parse(
    String output, {
    required Duration startupElapsed,
    bool enforceLatencyBudgets = true,
  }) {
    final List<RegExpMatch> matches = _machineLine.allMatches(output).toList();
    if (matches.length != 1) {
      throw const FormatException(
        'product performance result is missing, duplicated, or malformed',
      );
    }
    final List<RegExpMatch> resourceMatches = _resourceMachineLine
        .allMatches(output)
        .toList();
    if (resourceMatches.length != 1) {
      throw const FormatException(
        'product resource result is missing, duplicated, or malformed',
      );
    }
    final RegExpMatch match = matches.single;
    final RegExpMatch resource = resourceMatches.single;
    final RuntimeProductPerformanceResult result =
        RuntimeProductPerformanceResult._(
          startupMicroseconds: startupElapsed.inMicroseconds,
          refreshIntervalMicroseconds: int.parse(match.group(1)!),
          inputP95Microseconds: int.parse(match.group(2)!),
          visibleP95Microseconds: int.parse(match.group(3)!),
          visibleBudgetMicroseconds: int.parse(match.group(4)!),
          frameSamples: int.parse(match.group(5)!),
          frameP95Microseconds: int.parse(match.group(6)!),
          frameBudgetMicroseconds: int.parse(match.group(7)!),
          idleWindowMicroseconds: int.parse(resource.group(1)!),
          idleCpuMicroseconds: int.parse(resource.group(2)!),
          idleCpuBasisPoints: int.parse(resource.group(3)!),
          idleResidentBytes: int.parse(resource.group(4)!),
          workloadResidentBytes: int.parse(resource.group(6)!),
          peakResidentBytes: int.parse(resource.group(7)!),
          scrollbackAllocatedBytes: int.parse(resource.group(11)!),
          occludedWindowMicroseconds: int.parse(resource.group(13)!),
          occludedCpuMicroseconds: int.parse(resource.group(14)!),
          occludedCpuBasisPoints: int.parse(resource.group(15)!),
          occludedResidentBytes: int.parse(resource.group(16)!),
          aggregateCpuBasisPoints: int.parse(resource.group(17)!),
        );
    result._validate(
      enforceLatencyBudgets: enforceLatencyBudgets,
      resourceWorkloadBytes: int.parse(resource.group(5)!),
      resourceBudgetBytes: int.parse(resource.group(8)!),
      resourceScrollbackLines: int.parse(resource.group(9)!),
      resourceScrollbackPages: int.parse(resource.group(10)!),
      resourceScrollbackMaximumBytes: int.parse(resource.group(12)!),
      claimedResidentMemoryBound: resource.group(18) == 'true',
      claimedIdleCpuBound: resource.group(19) == 'true',
    );
    return result;
  }

  void _validate({
    required bool enforceLatencyBudgets,
    required int resourceWorkloadBytes,
    required int resourceBudgetBytes,
    required int resourceScrollbackLines,
    required int resourceScrollbackPages,
    required int resourceScrollbackMaximumBytes,
    required bool claimedResidentMemoryBound,
    required bool claimedIdleCpuBound,
  }) {
    if (startupMicroseconds <= 0) {
      throw const FormatException('product startup milestone is invalid');
    }
    if (refreshIntervalMicroseconds <= 0 ||
        refreshIntervalMicroseconds > maximumRefreshIntervalMicroseconds) {
      throw const FormatException('product refresh tier is outside its bound');
    }
    if (visibleBudgetMicroseconds !=
        refreshIntervalMicroseconds + visibleSlackMicroseconds) {
      throw const FormatException('product visible echo budget is malformed');
    }
    if (frameSamples < 8 ||
        frameSamples > 10 ||
        frameBudgetMicroseconds != refreshIntervalMicroseconds * 7 ~/ 10) {
      throw const FormatException('product frame budget is malformed');
    }
    if (idleWindowMicroseconds < minimumResourceWindowMicroseconds ||
        idleWindowMicroseconds > maximumResourceWindowMicroseconds ||
        occludedWindowMicroseconds < minimumResourceWindowMicroseconds ||
        occludedWindowMicroseconds > maximumResourceWindowMicroseconds ||
        idleCpuMicroseconds > idleWindowMicroseconds ||
        occludedCpuMicroseconds > occludedWindowMicroseconds) {
      throw const FormatException('product resource window is malformed');
    }
    final int expectedIdleBasisPoints =
        idleCpuMicroseconds * 10000 ~/ idleWindowMicroseconds;
    final int expectedOccludedBasisPoints =
        occludedCpuMicroseconds * 10000 ~/ occludedWindowMicroseconds;
    final int totalCpuMicroseconds =
        idleCpuMicroseconds + occludedCpuMicroseconds;
    final int totalWindowMicroseconds =
        idleWindowMicroseconds + occludedWindowMicroseconds;
    final int expectedAggregateBasisPoints =
        totalCpuMicroseconds * 10000 ~/ totalWindowMicroseconds;
    if (idleCpuBasisPoints != expectedIdleBasisPoints ||
        occludedCpuBasisPoints != expectedOccludedBasisPoints ||
        aggregateCpuBasisPoints != expectedAggregateBasisPoints) {
      throw const FormatException('product CPU proxy ratio is malformed');
    }
    if (resourceWorkloadBytes !=
            RuntimeProductPerformanceResult.resourceWorkloadBytes ||
        resourceBudgetBytes != residentMemoryBudgetBytes ||
        resourceScrollbackLines < scrollbackMinimumLines ||
        resourceScrollbackLines > scrollbackMaximumLines ||
        resourceScrollbackPages !=
            (resourceScrollbackLines + scrollbackPageRows - 1) ~/
                scrollbackPageRows ||
        resourceScrollbackMaximumBytes != scrollbackMaximumBytes ||
        scrollbackAllocatedBytes <= 0 ||
        scrollbackAllocatedBytes > scrollbackMaximumBytes ||
        peakResidentBytes < idleResidentBytes ||
        peakResidentBytes < workloadResidentBytes ||
        peakResidentBytes < occludedResidentBytes) {
      throw const FormatException('product resource inventory is malformed');
    }
    final bool residentMemoryBound =
        idleResidentBytes <= residentMemoryBudgetBytes &&
        workloadResidentBytes <= residentMemoryBudgetBytes &&
        occludedResidentBytes <= residentMemoryBudgetBytes &&
        peakResidentBytes <= residentMemoryBudgetBytes;
    final bool idleCpuBound =
        totalCpuMicroseconds * 200 < totalWindowMicroseconds;
    if (claimedResidentMemoryBound != residentMemoryBound ||
        claimedIdleCpuBound != idleCpuBound) {
      throw const FormatException('product resource gate claim is malformed');
    }
    if (!enforceLatencyBudgets) return;
    if (startupMicroseconds > startupBudgetMicroseconds) {
      throw const FormatException('product startup exceeded its fixed budget');
    }
    if (inputP95Microseconds >= maximumInputP95Microseconds) {
      throw const FormatException('product input admission exceeded 2 ms');
    }
    if (visibleP95Microseconds > visibleBudgetMicroseconds) {
      throw const FormatException('product visible echo exceeded its budget');
    }
    if (frameP95Microseconds >= frameBudgetMicroseconds) {
      throw const FormatException('product frame work exceeded its budget');
    }
    if (!residentMemoryBound) {
      throw const FormatException('product resident memory exceeded its cap');
    }
    if (!idleCpuBound) {
      throw const FormatException('product idle CPU exceeded 0.5 percent');
    }
  }
}
