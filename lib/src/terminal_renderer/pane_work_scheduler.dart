import 'dart:async';
import 'dart:collection';

import '../terminal_pane.dart';

typedef TerminalPaneScheduledWork = void Function();
typedef TerminalPaneScheduledWorkError = void Function(
  TerminalSessionId sessionId,
  Object error,
  StackTrace stackTrace,
);

/// Fixed admission and event-loop turn bounds for shared pane work.
final class TerminalPaneWorkSchedulerLimits {
  const TerminalPaneWorkSchedulerLimits({
    this.maximumPanes = 64,
    this.maximumWorkPerTurn = 4,
    this.maximumTurnDuration = const Duration(milliseconds: 4),
  });

  static const int maximumSupportedPanes = 64;
  static const Duration maximumRequestDelay = Duration(minutes: 1);

  final int maximumPanes;
  final int maximumWorkPerTurn;
  final Duration maximumTurnDuration;

  void validate() {
    RangeError.checkValueInInterval(
      maximumPanes,
      1,
      maximumSupportedPanes,
      'maximumPanes',
    );
    RangeError.checkValueInInterval(
      maximumWorkPerTurn,
      1,
      maximumSupportedPanes,
      'maximumWorkPerTurn',
    );
    if (maximumTurnDuration <= Duration.zero ||
        maximumTurnDuration > const Duration(seconds: 1)) {
      throw RangeError.range(
        maximumTurnDuration.inMicroseconds,
        1,
        const Duration(seconds: 1).inMicroseconds,
        'maximumTurnDuration',
      );
    }
  }
}

/// Immutable bounded counters for one scheduler lifetime.
final class TerminalPaneWorkSchedulerSnapshot {
  const TerminalPaneWorkSchedulerSnapshot({
    required this.isDisposed,
    required this.registeredPaneCount,
    required this.pendingPaneCount,
    required this.peakPendingPaneCount,
    required this.requestCount,
    required this.coalescedRequestCount,
    required this.turnCount,
    required this.workCount,
    required this.yieldCount,
    required this.faultCount,
    required this.maximumWorkPerTurnObserved,
    required this.hasScheduledTimer,
  });

  final bool isDisposed;
  final int registeredPaneCount;
  final int pendingPaneCount;
  final int peakPendingPaneCount;
  final int requestCount;
  final int coalescedRequestCount;
  final int turnCount;
  final int workCount;
  final int yieldCount;
  final int faultCount;
  final int maximumWorkPerTurnObserved;
  final bool hasScheduledTimer;

  String machineLine() =>
      'TERMINAL_PANE_WORK_SCHEDULER registered=$registeredPaneCount '
      'pending=$pendingPaneCount peak_pending=$peakPendingPaneCount '
      'requests=$requestCount coalesced=$coalescedRequestCount '
      'turns=$turnCount work=$workCount yields=$yieldCount '
      'faults=$faultCount max_work=$maximumWorkPerTurnObserved '
      'timer=$hasScheduledTimer disposed=$isDisposed';
}

/// Result of one explicit scheduler turn.
final class TerminalPaneWorkTurnResult {
  const TerminalPaneWorkTurnResult({
    required this.workCount,
    required this.faultCount,
    required this.yielded,
    required this.pendingPaneCount,
  });

  final int workCount;
  final int faultCount;
  final bool yielded;
  final int pendingPaneCount;
}

/// One-timer, round-robin owner for bounded work across live panes.
///
/// Every registered pane retains at most one pending identity. The identities
/// present when a turn starts are each eligible at most once in that turn, so
/// a callback which requests itself is appended for a later event-loop turn.
final class TerminalPaneWorkScheduler {
  factory TerminalPaneWorkScheduler({
    TerminalPaneWorkSchedulerLimits limits =
        const TerminalPaneWorkSchedulerLimits(),
    TerminalPaneScheduledWorkError? onError,
    bool automaticScheduling = true,
    int Function()? monotonicMicros,
  }) {
    limits.validate();
    final Stopwatch? clock = monotonicMicros == null
        ? (Stopwatch()..start())
        : null;
    return TerminalPaneWorkScheduler._(
      limits: limits,
      onError: onError,
      automaticScheduling: automaticScheduling,
      monotonicMicros: monotonicMicros ?? () => clock!.elapsedMicroseconds,
    );
  }

  TerminalPaneWorkScheduler._({
    required this.limits,
    required this.onError,
    required this.automaticScheduling,
    required int Function() monotonicMicros,
  }) : _monotonicMicros = monotonicMicros;

  static const int maximumCounterValue = 0x7fffffffffffffff;

  final TerminalPaneWorkSchedulerLimits limits;
  final TerminalPaneScheduledWorkError? onError;
  final bool automaticScheduling;
  final int Function() _monotonicMicros;
  final LinkedHashMap<TerminalSessionId, _TerminalPaneWorkEntry> _entries =
      LinkedHashMap<TerminalSessionId, _TerminalPaneWorkEntry>();
  final LinkedHashSet<TerminalSessionId> _pending =
      LinkedHashSet<TerminalSessionId>();

  Timer? _timer;
  int? _timerDeadlineMicros;
  int _lastMonotonicMicros = 0;
  bool _processing = false;
  bool _disposed = false;
  int _peakPendingPaneCount = 0;
  int _requestCount = 0;
  int _coalescedRequestCount = 0;
  int _turnCount = 0;
  int _workCount = 0;
  int _yieldCount = 0;
  int _faultCount = 0;
  int _maximumWorkPerTurnObserved = 0;

  bool get isDisposed => _disposed;
  int get registeredPaneCount => _entries.length;
  int get pendingPaneCount => _pending.length;

  void register(TerminalSessionId sessionId, TerminalPaneScheduledWork work) {
    _requireLive();
    if (_entries.containsKey(sessionId)) {
      throw StateError('pane scheduler already owns session $sessionId');
    }
    if (_entries.length >= limits.maximumPanes) {
      throw StateError('pane scheduler registration limit is exhausted');
    }
    _entries[sessionId] = _TerminalPaneWorkEntry(work);
  }

  bool request(TerminalSessionId sessionId, {Duration delay = Duration.zero}) {
    if (delay < Duration.zero ||
        delay > TerminalPaneWorkSchedulerLimits.maximumRequestDelay) {
      throw RangeError.range(
        delay.inMicroseconds,
        0,
        TerminalPaneWorkSchedulerLimits.maximumRequestDelay.inMicroseconds,
        'delay',
      );
    }
    if (_disposed) return false;
    final _TerminalPaneWorkEntry? entry = _entries[sessionId];
    if (entry == null) return false;
    final int dueMicros = _readMonotonicMicros() + delay.inMicroseconds;
    _requestCount = _increment(_requestCount);
    if (entry.isPending) {
      _coalescedRequestCount = _increment(_coalescedRequestCount);
      if (dueMicros < entry.dueMicros) entry.dueMicros = dueMicros;
    } else {
      entry
        ..isPending = true
        ..dueMicros = dueMicros;
      _pending.add(sessionId);
      if (_pending.length > _peakPendingPaneCount) {
        _peakPendingPaneCount = _pending.length;
      }
    }
    _scheduleTimer();
    return true;
  }

  bool cancel(TerminalSessionId sessionId) {
    if (_disposed) return false;
    final _TerminalPaneWorkEntry? entry = _entries[sessionId];
    if (entry == null || !entry.isPending) return false;
    entry.isPending = false;
    _pending.remove(sessionId);
    _scheduleTimer(replaceExisting: true);
    return true;
  }

  bool unregister(TerminalSessionId sessionId) {
    if (_disposed) return false;
    final _TerminalPaneWorkEntry? entry = _entries.remove(sessionId);
    if (entry == null) return false;
    entry.isPending = false;
    _pending.remove(sessionId);
    _scheduleTimer(replaceExisting: true);
    return true;
  }

  bool isPending(TerminalSessionId sessionId) =>
      !_disposed && (_entries[sessionId]?.isPending ?? false);

  TerminalPaneWorkTurnResult processPending() {
    _requireLive();
    if (_processing) {
      throw StateError('pane scheduler turn is already in progress');
    }
    _timer?.cancel();
    _timer = null;
    _timerDeadlineMicros = null;
    final int turnStartMicros = _readMonotonicMicros();
    final int eligibleCount = _pending.length;
    var inspected = 0;
    var work = 0;
    var faults = 0;
    _processing = true;
    try {
      while (inspected < eligibleCount && _pending.isNotEmpty) {
        final int now = _readMonotonicMicros();
        if (work >= limits.maximumWorkPerTurn ||
            (work > 0 &&
                now - turnStartMicros >=
                    limits.maximumTurnDuration.inMicroseconds)) {
          break;
        }
        final TerminalSessionId sessionId = _pending.first;
        _pending.remove(sessionId);
        inspected++;
        final _TerminalPaneWorkEntry? entry = _entries[sessionId];
        if (entry == null || !entry.isPending) continue;
        if (entry.dueMicros > now) {
          _pending.add(sessionId);
          continue;
        }
        entry.isPending = false;
        work++;
        try {
          entry.work();
        } on Object catch (error, stackTrace) {
          faults++;
          try {
            onError?.call(sessionId, error, stackTrace);
          } on Object {
            // An observer cannot prevent another pane from receiving a turn.
          }
        }
      }
    } finally {
      _processing = false;
    }

    final int turnEndMicros = _readMonotonicMicros();
    final bool dueWorkRemains = _pending.any(
      (TerminalSessionId sessionId) =>
          (_entries[sessionId]?.dueMicros ?? maximumCounterValue) <=
          turnEndMicros,
    );
    final bool yielded = dueWorkRemains;
    _turnCount = _increment(_turnCount);
    _workCount = _add(_workCount, work);
    _faultCount = _add(_faultCount, faults);
    if (yielded) _yieldCount = _increment(_yieldCount);
    if (work > _maximumWorkPerTurnObserved) {
      _maximumWorkPerTurnObserved = work;
    }
    _scheduleTimer();
    return TerminalPaneWorkTurnResult(
      workCount: work,
      faultCount: faults,
      yielded: yielded,
      pendingPaneCount: _pending.length,
    );
  }

  TerminalPaneWorkSchedulerSnapshot snapshot() =>
      TerminalPaneWorkSchedulerSnapshot(
        isDisposed: _disposed,
        registeredPaneCount: _entries.length,
        pendingPaneCount: _pending.length,
        peakPendingPaneCount: _peakPendingPaneCount,
        requestCount: _requestCount,
        coalescedRequestCount: _coalescedRequestCount,
        turnCount: _turnCount,
        workCount: _workCount,
        yieldCount: _yieldCount,
        faultCount: _faultCount,
        maximumWorkPerTurnObserved: _maximumWorkPerTurnObserved,
        hasScheduledTimer: _timer != null,
      );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _timerDeadlineMicros = null;
    _pending.clear();
    _entries.clear();
  }

  void _scheduleTimer({bool replaceExisting = false}) {
    if (!automaticScheduling || _disposed || _processing) return;
    if (_pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
      _timerDeadlineMicros = null;
      return;
    }
    var deadlineMicros = maximumCounterValue;
    for (final TerminalSessionId sessionId in _pending) {
      final int? candidate = _entries[sessionId]?.dueMicros;
      if (candidate != null && candidate < deadlineMicros) {
        deadlineMicros = candidate;
      }
    }
    final int? currentDeadline = _timerDeadlineMicros;
    if (!replaceExisting &&
        _timer != null &&
        currentDeadline != null &&
        currentDeadline <= deadlineMicros) {
      return;
    }
    _timer?.cancel();
    final int now = _readMonotonicMicros();
    final Duration delay = Duration(
      microseconds: deadlineMicros <= now ? 0 : deadlineMicros - now,
    );
    _timerDeadlineMicros = deadlineMicros;
    _timer = Timer(delay, _runScheduledTurn);
  }

  void _runScheduledTurn() {
    _timer = null;
    _timerDeadlineMicros = null;
    if (_disposed) return;
    processPending();
  }

  int _readMonotonicMicros() {
    final int value = _monotonicMicros();
    if (value < _lastMonotonicMicros) {
      throw StateError('pane scheduler monotonic time regressed');
    }
    _lastMonotonicMicros = value;
    return value;
  }

  void _requireLive() {
    if (_disposed) throw StateError('pane scheduler is disposed');
  }

  static int _increment(int value) =>
      value >= maximumCounterValue ? maximumCounterValue : value + 1;

  static int _add(int value, int addition) {
    if (addition <= 0) return value;
    return value > maximumCounterValue - addition
        ? maximumCounterValue
        : value + addition;
  }
}

final class _TerminalPaneWorkEntry {
  _TerminalPaneWorkEntry(this.work);

  final TerminalPaneScheduledWork work;
  bool isPending = false;
  int dueMicros = 0;
}
