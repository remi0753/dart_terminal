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
  });

  static const int startupBudgetMicroseconds = 5000000;
  static const int maximumRefreshIntervalMicroseconds = 50000;
  static const int maximumInputP95Microseconds = 2000;
  static const int visibleSlackMicroseconds = 4000;

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

  final int startupMicroseconds;
  final int refreshIntervalMicroseconds;
  final int inputP95Microseconds;
  final int visibleP95Microseconds;
  final int visibleBudgetMicroseconds;
  final int frameSamples;
  final int frameP95Microseconds;
  final int frameBudgetMicroseconds;

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
    final RegExpMatch match = matches.single;
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
        );
    result._validate(enforceLatencyBudgets: enforceLatencyBudgets);
    return result;
  }

  void _validate({required bool enforceLatencyBudgets}) {
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
  }
}
