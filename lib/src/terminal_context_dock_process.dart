import 'dart:async';

import 'package:dart_pty_macos/dart_pty_macos.dart';

import 'terminal_action_registry.dart';
import 'terminal_application_state.dart';
import 'terminal_context_dock.dart';
import 'terminal_pane.dart';

abstract final class TerminalContextDockProcessLimits {
  static const Duration foregroundActivationDelay = Duration(milliseconds: 75);
  static const Duration processStatePollInterval = Duration(milliseconds: 250);
  static const Duration foregroundInventoryInterval = Duration(seconds: 1);
  static const Duration terminalChangeDebounce = Duration(milliseconds: 75);
}

enum TerminalContextDockContentMode {
  directoryNavigator,
  foregroundJob,
  shellOwnedCommand,
  protected,
  unavailable,
}

enum TerminalContextDockProcessStatus {
  loading,
  ready,
  partial,
  shellOwned,
  unavailable,
}

final class TerminalContextDockForegroundJobIdentity {
  const TerminalContextDockForegroundJobIdentity({
    required this.sessionId,
    required this.foregroundProcessGroup,
    required this.epoch,
  });

  final TerminalSessionId sessionId;
  final int foregroundProcessGroup;
  final int epoch;

  @override
  bool operator ==(Object other) =>
      other is TerminalContextDockForegroundJobIdentity &&
      other.sessionId == sessionId &&
      other.foregroundProcessGroup == foregroundProcessGroup &&
      other.epoch == epoch;

  @override
  int get hashCode => Object.hash(sessionId, foregroundProcessGroup, epoch);
}

final class TerminalContextDockProcessMember {
  const TerminalContextDockProcessMember({
    required this.processId,
    required this.startTimeSeconds,
    required this.startTimeMicroseconds,
    required this.startAbsoluteTime,
    required this.elapsedMicroseconds,
    required this.name,
    required this.informationSystemError,
    required this.resourceUsageSystemError,
  });

  factory TerminalContextDockProcessMember.fromPty(
    PtyForegroundProcessSnapshot snapshot,
  ) => TerminalContextDockProcessMember(
    processId: snapshot.processId,
    startTimeSeconds: snapshot.startTimeSeconds,
    startTimeMicroseconds: snapshot.startTimeMicroseconds,
    startAbsoluteTime: snapshot.startAbsoluteTime,
    elapsedMicroseconds: snapshot.elapsedMicroseconds,
    name: snapshot.name,
    informationSystemError: snapshot.informationSystemError,
    resourceUsageSystemError: snapshot.resourceUsageSystemError,
  );

  final int processId;
  final int startTimeSeconds;
  final int startTimeMicroseconds;
  final int startAbsoluteTime;
  final int elapsedMicroseconds;
  final String name;
  final int informationSystemError;
  final int resourceUsageSystemError;

  bool get isPartial =>
      informationSystemError != 0 || resourceUsageSystemError != 0;

  TerminalContextDockProcessMember withElapsed(int elapsed) =>
      TerminalContextDockProcessMember(
        processId: processId,
        startTimeSeconds: startTimeSeconds,
        startTimeMicroseconds: startTimeMicroseconds,
        startAbsoluteTime: startAbsoluteTime,
        elapsedMicroseconds: elapsed,
        name: name,
        informationSystemError: informationSystemError,
        resourceUsageSystemError: resourceUsageSystemError,
      );
}

/// Content-bearing process projection retained only while its focused job
/// identity, Dock visibility, and privacy authority remain current.
final class TerminalContextDockProcessSnapshot {
  TerminalContextDockProcessSnapshot({
    required this.status,
    required this.identity,
    required this.observedAtMonotonicMicros,
    required this.elapsedMicroseconds,
    required Iterable<TerminalContextDockProcessMember> members,
    required this.totalMemberCount,
    required this.omittedMemberCount,
    required this.memberIssueCount,
    required this.primaryIndex,
    required this.executablePath,
    required this.executablePathSystemError,
    required Iterable<String> arguments,
    required this.totalArgumentCount,
    required this.omittedArgumentCount,
    required this.argumentsTruncated,
    required this.argumentsSystemError,
    required this.observationSystemError,
    this.argumentsHidden = false,
  }) : members = List<TerminalContextDockProcessMember>.unmodifiable(members),
       arguments = List<String>.unmodifiable(arguments);

  factory TerminalContextDockProcessSnapshot.loading({
    required TerminalContextDockForegroundJobIdentity identity,
    required int observedAtMonotonicMicros,
  }) => TerminalContextDockProcessSnapshot(
    status: TerminalContextDockProcessStatus.loading,
    identity: identity,
    observedAtMonotonicMicros: observedAtMonotonicMicros,
    elapsedMicroseconds: 0,
    members: const <TerminalContextDockProcessMember>[],
    totalMemberCount: 0,
    omittedMemberCount: 0,
    memberIssueCount: 0,
    primaryIndex: -1,
    executablePath: null,
    executablePathSystemError: 0,
    arguments: const <String>[],
    totalArgumentCount: 0,
    omittedArgumentCount: 0,
    argumentsTruncated: false,
    argumentsSystemError: 0,
    observationSystemError: 0,
  );

  factory TerminalContextDockProcessSnapshot.shellOwned({
    required int observedAtMonotonicMicros,
  }) => TerminalContextDockProcessSnapshot(
    status: TerminalContextDockProcessStatus.shellOwned,
    identity: null,
    observedAtMonotonicMicros: observedAtMonotonicMicros,
    elapsedMicroseconds: 0,
    members: const <TerminalContextDockProcessMember>[],
    totalMemberCount: 0,
    omittedMemberCount: 0,
    memberIssueCount: 0,
    primaryIndex: -1,
    executablePath: null,
    executablePathSystemError: 0,
    arguments: const <String>[],
    totalArgumentCount: 0,
    omittedArgumentCount: 0,
    argumentsTruncated: false,
    argumentsSystemError: 0,
    observationSystemError: 0,
  );

  factory TerminalContextDockProcessSnapshot.unavailable({
    required TerminalContextDockForegroundJobIdentity identity,
    required int observedAtMonotonicMicros,
    required int observationSystemError,
  }) => TerminalContextDockProcessSnapshot(
    status: TerminalContextDockProcessStatus.unavailable,
    identity: identity,
    observedAtMonotonicMicros: observedAtMonotonicMicros,
    elapsedMicroseconds: 0,
    members: const <TerminalContextDockProcessMember>[],
    totalMemberCount: 0,
    omittedMemberCount: 0,
    memberIssueCount: 0,
    primaryIndex: -1,
    executablePath: null,
    executablePathSystemError: 0,
    arguments: const <String>[],
    totalArgumentCount: 0,
    omittedArgumentCount: 0,
    argumentsTruncated: false,
    argumentsSystemError: 0,
    observationSystemError: observationSystemError,
  );

  final TerminalContextDockProcessStatus status;
  final TerminalContextDockForegroundJobIdentity? identity;
  final int observedAtMonotonicMicros;
  final int elapsedMicroseconds;
  final List<TerminalContextDockProcessMember> members;
  final int totalMemberCount;
  final int omittedMemberCount;
  final int memberIssueCount;
  final int primaryIndex;
  final String? executablePath;
  final int executablePathSystemError;
  final List<String> arguments;
  final int totalArgumentCount;
  final int omittedArgumentCount;
  final bool argumentsTruncated;
  final int argumentsSystemError;
  final int observationSystemError;
  final bool argumentsHidden;

  TerminalContextDockProcessMember? get primaryProcess =>
      primaryIndex < 0 ? null : members[primaryIndex];

  TerminalContextDockProcessSnapshot withElapsed(int elapsed) {
    final int advance = (elapsed - elapsedMicroseconds).clamp(
      0,
      0x7fffffffffffffff,
    );
    return TerminalContextDockProcessSnapshot(
      status: status,
      identity: identity,
      observedAtMonotonicMicros: observedAtMonotonicMicros,
      elapsedMicroseconds: elapsed,
      members: <TerminalContextDockProcessMember>[
        for (final TerminalContextDockProcessMember member in members)
          member.withElapsed(member.elapsedMicroseconds + advance),
      ],
      totalMemberCount: totalMemberCount,
      omittedMemberCount: omittedMemberCount,
      memberIssueCount: memberIssueCount,
      primaryIndex: primaryIndex,
      executablePath: executablePath,
      executablePathSystemError: executablePathSystemError,
      arguments: arguments,
      totalArgumentCount: totalArgumentCount,
      omittedArgumentCount: omittedArgumentCount,
      argumentsTruncated: argumentsTruncated,
      argumentsSystemError: argumentsSystemError,
      observationSystemError: observationSystemError,
      argumentsHidden: argumentsHidden,
    );
  }

  TerminalContextDockProcessSnapshot withoutArguments() =>
      TerminalContextDockProcessSnapshot(
        status: status,
        identity: identity,
        observedAtMonotonicMicros: observedAtMonotonicMicros,
        elapsedMicroseconds: elapsedMicroseconds,
        members: members,
        totalMemberCount: totalMemberCount,
        omittedMemberCount: omittedMemberCount,
        memberIssueCount: memberIssueCount,
        primaryIndex: primaryIndex,
        executablePath: executablePath,
        executablePathSystemError: executablePathSystemError,
        arguments: const <String>[],
        totalArgumentCount: 0,
        omittedArgumentCount: 0,
        argumentsTruncated: false,
        argumentsSystemError: 0,
        observationSystemError: observationSystemError,
        argumentsHidden: true,
      );
}

final class TerminalContextDockContentSnapshot {
  const TerminalContextDockContentSnapshot({
    required this.windowId,
    required this.paneId,
    required this.sessionId,
    required this.generation,
    required this.mode,
    required this.directorySuspended,
    required this.process,
    this.argumentsVisible = true,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final TerminalSessionId sessionId;
  final int generation;
  final TerminalContextDockContentMode mode;
  final bool directorySuspended;
  final TerminalContextDockProcessSnapshot? process;
  final bool argumentsVisible;
}

abstract interface class TerminalContextDockScheduledTask {
  bool get isCancelled;
  void cancel();
}

typedef TerminalContextDockScheduleTask =
    TerminalContextDockScheduledTask Function(
      Duration delay,
      void Function() callback,
    );
typedef TerminalContextDockProcessSnapshotResolver =
    TerminalPaneProcessSnapshot Function(PaneId paneId);
typedef TerminalContextDockForegroundJobResolver =
    FutureOr<PtyForegroundJobSnapshot?> Function(
      PaneId paneId,
      TerminalSessionId sessionId,
    );
typedef TerminalContextDockWindowPresentationPolicy = bool Function(
  TerminalWindowId windowId,
);
typedef TerminalContextDockProcessPrivacyPolicy = bool Function(
  PaneId paneId,
  TerminalPaneProcessSnapshot process,
);
typedef TerminalContextDockDirectoryPrivacyPolicy = bool Function(
  PaneId paneId,
);
typedef TerminalContextDockDirectoryDisplayPolicy = bool Function(
  PaneId paneId,
);
typedef TerminalContextDockDirectoryRetentionInvalidation = void Function(
  PaneId paneId,
);
typedef TerminalContextDockProcessTerminalFocus = bool Function(
  TerminalContextDockFocusRequest request,
);
typedef TerminalContextDockProcessNavigatorFocus = bool Function(
  TerminalContextDockFocusRequest request,
);

/// Selects one Context Dock document from focused-pane process authority.
///
/// Rich path/argv observation is delayed until a foreground group remains
/// stable and refreshed at most once per second. Presentation changes park one
/// content-free session/PGID authority per live pane. Returning to a pane must
/// revalidate its session and foreground PGID before Directory content can be
/// shown again; pane, session, or job replacement discards the authority.
final class TerminalContextDockProcessController {
  TerminalContextDockProcessController({
    required this.applicationState,
    required this.dockState,
    required TerminalContextDockProcessSnapshotResolver resolveProcessSnapshot,
    required TerminalContextDockForegroundJobResolver resolveForegroundJob,
    TerminalContextDockWindowPresentationPolicy? canPresentWindow,
    TerminalContextDockProcessPrivacyPolicy? canObserveProcess,
    TerminalContextDockDirectoryPrivacyPolicy? canObserveDirectory,
    TerminalContextDockDirectoryDisplayPolicy? canDisplayDirectory,
    TerminalContextDockDirectoryRetentionInvalidation?
    invalidateRetainedDirectory,
    TerminalContextDockProcessNavigatorFocus? focusNavigator,
    TerminalContextDockProcessTerminalFocus? focusTerminal,
    TerminalContextDockScheduleTask? scheduleTask,
    int Function()? monotonicMicros,
    void Function()? onChanged,
  }) : _resolveProcessSnapshot = resolveProcessSnapshot,
       _resolveForegroundJob = resolveForegroundJob,
       _canPresentWindow = canPresentWindow ?? _alwaysPresentWindow,
       _canObserveProcess = canObserveProcess ?? _alwaysObserveProcess,
       _canObserveDirectory = canObserveDirectory ?? _alwaysObserveDirectory,
       _canDisplayDirectory =
           canDisplayDirectory ??
           canObserveDirectory ??
           _alwaysObserveDirectory,
       _invalidateRetainedDirectory =
           invalidateRetainedDirectory ?? _ignoreDirectoryInvalidation,
       _focusNavigator = focusNavigator ?? _acceptNavigatorFocus,
       _focusTerminal = focusTerminal ?? _acceptTerminalFocus,
       _scheduleTask = scheduleTask ?? _scheduleTimerTask,
       _onChanged = onChanged {
    final Stopwatch? clock = monotonicMicros == null
        ? (Stopwatch()..start())
        : null;
    _monotonicMicros = monotonicMicros ?? () => clock!.elapsedMicroseconds;
  }

  final TerminalApplicationState applicationState;
  final TerminalContextDockState dockState;
  final TerminalContextDockProcessSnapshotResolver _resolveProcessSnapshot;
  final TerminalContextDockForegroundJobResolver _resolveForegroundJob;
  final TerminalContextDockWindowPresentationPolicy _canPresentWindow;
  final TerminalContextDockProcessPrivacyPolicy _canObserveProcess;
  final TerminalContextDockDirectoryPrivacyPolicy _canObserveDirectory;
  final TerminalContextDockDirectoryDisplayPolicy _canDisplayDirectory;
  final TerminalContextDockDirectoryRetentionInvalidation
  _invalidateRetainedDirectory;
  final TerminalContextDockProcessNavigatorFocus _focusNavigator;
  final TerminalContextDockProcessTerminalFocus _focusTerminal;
  final TerminalContextDockScheduleTask _scheduleTask;
  final void Function()? _onChanged;
  late final int Function() _monotonicMicros;
  final Map<TerminalWindowId, _TerminalContextDockProcessWindowState> _windows =
      <TerminalWindowId, _TerminalContextDockProcessWindowState>{};
  final Map<PaneId, _TerminalContextDockProcessWindowState>
  _paneFocusSuspended = <PaneId, _TerminalContextDockProcessWindowState>{};
  final Set<_TerminalContextDockRichRequest> _requests =
      <_TerminalContextDockRichRequest>{};
  TerminalContextDockScheduledTask? _pollTask;
  TerminalContextDockScheduledTask? _debounceTask;
  int _nextGeneration = 0;
  int _nextForegroundEpoch = 0;
  int _lastMonotonicMicros = 0;
  bool _hasObservedTime = false;
  bool _synchronizing = false;
  bool _isDisposed = false;
  bool _argumentsVisible = true;

  bool get isDisposed => _isDisposed;
  bool get argumentsVisible => _argumentsVisible;
  bool get activeWindowShowsDirectoryDuringProcess {
    if (_isDisposed) return false;
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null) return false;
    return _windows[window.id]?.directoryNavigatorOverride ?? false;
  }

  List<TerminalActionRegistration> registrations() =>
      <TerminalActionRegistration>[
        TerminalActionRegistration(
          id: TerminalActionId.toggleContextDockContent,
          isAvailable: _canToggleActiveWindowContent,
          handler: toggleActiveWindowContent,
        ),
        TerminalActionRegistration(
          id: TerminalActionId.toggleProcessArguments,
          isAvailable: () {
            final TerminalWindowState? window = applicationState.activeWindow;
            return !_isDisposed &&
                window?.role == TerminalWindowRole.standard &&
                applicationState
                        .paneForId(window!.selectedTab.focusedPaneId)
                        ?.isLive ==
                    true;
          },
          handler: toggleArgumentsVisibility,
        ),
      ];

  /// Toggles only the projected document for the current foreground job.
  ///
  /// Process observation remains active so returning to Process Inspector is
  /// immediate. The explicit Directory override grants bounded filesystem
  /// interaction only for this presented job identity and is never carried to
  /// another job.
  void toggleActiveWindowContent() {
    if (_isDisposed) return;
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) return;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    final _TerminalContextDockProcessWindowState? state = _windows[window.id];
    if (dock == null ||
        !dock.isVisible ||
        state == null ||
        state.paneId != dock.targetPaneId ||
        state.mode != TerminalContextDockContentMode.foregroundJob) {
      return;
    }
    if (!state.directoryNavigatorOverride &&
        !_safeCanDisplayDirectory(state.paneId)) {
      return;
    }
    state.directoryNavigatorOverride = !state.directoryNavigatorOverride;
    if (state.directoryNavigatorOverride) {
      _focusDirectoryNavigator(state, dock);
      return;
    }
    _returnInputToTerminal(dock);
    _onChanged?.call();
  }

  /// Application-lifetime display preference, unrelated to Secure Input.
  /// Hiding immediately drops retained argv. Revealing waits for the next
  /// bounded inventory refresh rather than resurrecting an old argument list.
  void toggleArgumentsVisibility() {
    if (_isDisposed) return;
    _argumentsVisible = !_argumentsVisible;
    if (!_argumentsVisible) {
      for (final _TerminalContextDockProcessWindowState state
          in _windows.values) {
        state.process = state.process?.withoutArguments();
      }
    }
    _onChanged?.call();
  }

  int get activeOperationCount => _requests.length;
  int get activeTimerCount =>
      (_isActive(_pollTask) ? 1 : 0) +
      (_isActive(_debounceTask) ? 1 : 0) +
      _windows.values.where((state) => _isActive(state.activationTask)).length;

  TerminalContextDockContentSnapshot? snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (_isDisposed) return null;
    final _TerminalContextDockProcessWindowState? state = _windows[windowId];
    if (state == null) return null;
    TerminalContextDockProcessSnapshot? process = state.process;
    final int now = _now();
    if (process != null) {
      final int advance = (now - process.observedAtMonotonicMicros).clamp(
        0,
        0x7fffffffffffffff,
      );
      process = process.withElapsed(process.elapsedMicroseconds + advance);
    }
    final bool showsDirectory =
        state.directoryNavigatorOverride &&
        state.mode == TerminalContextDockContentMode.foregroundJob;
    return TerminalContextDockContentSnapshot(
      windowId: state.windowId,
      paneId: state.paneId,
      sessionId: state.sessionId,
      generation: state.generation,
      mode: showsDirectory
          ? TerminalContextDockContentMode.directoryNavigator
          : state.mode,
      directorySuspended: showsDirectory ? false : state.directorySuspended,
      process: showsDirectory ? null : process,
      argumentsVisible: _argumentsVisible,
    );
  }

  bool canObserveDirectoryPane(PaneId paneId) {
    if (_isDisposed) return false;
    return _windows.values.any((state) {
      if (state.paneId != paneId) return false;
      if (state.mode == TerminalContextDockContentMode.directoryNavigator &&
          !state.directorySuspended) {
        return _safeCanObserveDirectory(paneId);
      }
      return state.mode == TerminalContextDockContentMode.foregroundJob &&
          state.directoryNavigatorOverride &&
          state.directoryRetentionEligible &&
          _safeCanPresentWindow(state.windowId) &&
          _safeCanDisplayDirectory(paneId);
    });
  }

  bool canRetainDirectoryPane(PaneId paneId) =>
      !_isDisposed &&
      <_TerminalContextDockProcessWindowState>[
        ..._windows.values,
        ..._paneFocusSuspended.values,
      ].any(
        (state) =>
            state.paneId == paneId &&
            state.directorySuspended &&
            state.directoryRetentionEligible,
      );

  void scheduleSynchronize() {
    if (_isDisposed || _debounceTask != null) return;
    late final TerminalContextDockScheduledTask scheduled;
    scheduled = _scheduleTask(
      TerminalContextDockProcessLimits.terminalChangeDebounce,
      () {
        if (!identical(_debounceTask, scheduled)) return;
        _debounceTask = null;
        synchronize();
      },
    );
    _debounceTask = scheduled;
  }

  void synchronize() {
    if (_isDisposed || _synchronizing) return;
    _synchronizing = true;
    var changed = false;
    try {
      _cancelDebounce();
      if (applicationState.isDisposed || dockState.isDisposed) {
        changed = _clearWindows();
        _cancelPoll();
        return;
      }
      dockState.synchronize(applicationState);
      final Set<PaneId> livePaneIds = <PaneId>{
        for (final TerminalWindowState window in applicationState.windows)
          for (final TerminalTabState tab in window.tabs) ...tab.paneIds,
      };
      for (final PaneId stale
          in _paneFocusSuspended.keys
              .where((PaneId paneId) => !livePaneIds.contains(paneId))
              .toList(growable: false)) {
        _discardPaneFocusSuspended(stale, invalidateDirectory: true);
        changed = true;
      }
      final Set<TerminalWindowId> eligible = <TerminalWindowId>{};
      for (final TerminalWindowState logicalWindow
          in applicationState.windows.where(
            (window) => window.role == TerminalWindowRole.standard,
          )) {
        eligible.add(logicalWindow.id);
        final TerminalContextDockWindowSnapshot? dock = dockState
            .snapshotForWindow(logicalWindow.id);
        if (dock == null) {
          changed = _discardWindowAuthority(logicalWindow.id) || changed;
          continue;
        }
        if (!dock.isVisible || !_safeCanPresentWindow(logicalWindow.id)) {
          changed = _suspendWindowProjection(logicalWindow.id) || changed;
          continue;
        }
        final TerminalPaneProcessSnapshot process = _safeProcessSnapshot(
          dock.targetPaneId,
        );
        _TerminalContextDockProcessWindowState? state =
            _windows[logicalWindow.id];
        if (state == null ||
            state.paneId != dock.targetPaneId ||
            state.sessionId != process.sessionId) {
          if (state != null) {
            _windows.remove(logicalWindow.id);
            final TerminalPaneLocation? priorLocation = applicationState
                .locationForPane(state.paneId);
            final bool sameWindow = priorLocation?.windowId == logicalWindow.id;
            if (state.paneId != dock.targetPaneId &&
                sameWindow &&
                (state.presentationSuspended || _suspendProjection(state))) {
              _parkPaneFocusSuspended(state);
            } else {
              if (state.presentationSuspended ||
                  state.paneId == dock.targetPaneId) {
                _safeInvalidateRetainedDirectory(state.paneId);
              }
              _cancelState(state);
            }
          }
          state = _paneFocusSuspended.remove(dock.targetPaneId);
          if (state != null &&
              (state.windowId != logicalWindow.id ||
                  state.sessionId != process.sessionId)) {
            _safeInvalidateRetainedDirectory(state.paneId);
            _cancelState(state);
            state = null;
          }
          state ??= _TerminalContextDockProcessWindowState(
            windowId: logicalWindow.id,
            paneId: dock.targetPaneId,
            sessionId: process.sessionId,
            generation: ++_nextGeneration,
          );
          _windows[logicalWindow.id] = state;
          changed = true;
        }
        if (state.presentationSuspended) {
          changed = _resumePresented(state, process) || changed;
        }
        changed = _reconcileWindow(state, dock, process) || changed;
      }
      for (final TerminalWindowId stale
          in _windows.keys
              .where((windowId) => !eligible.contains(windowId))
              .toList(growable: false)) {
        changed = _discardWindowAuthority(stale) || changed;
      }
    } finally {
      _synchronizing = false;
      _ensurePoll();
      if (changed) _onChanged?.call();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _cancelDebounce();
    _cancelPoll();
    _clearWindows();
    _requests.clear();
  }

  bool _reconcileWindow(
    _TerminalContextDockProcessWindowState state,
    TerminalContextDockWindowSnapshot dock,
    TerminalPaneProcessSnapshot process,
  ) {
    if (process.disposition == TerminalPaneProcessDisposition.nonLive ||
        process.disposition == TerminalPaneProcessDisposition.unavailable) {
      return _enterContentFree(
        state,
        TerminalContextDockContentMode.unavailable,
      );
    }
    if (!_safeCanObserveProcess(state.paneId, process)) {
      final bool changed = _enterContentFree(
        state,
        TerminalContextDockContentMode.protected,
      );
      _returnInputToTerminal(dock);
      return changed;
    }
    switch (process.disposition) {
      case TerminalPaneProcessDisposition.idleShell:
        return _enterDirectory(state);
      case TerminalPaneProcessDisposition.owningShellCommand:
        final bool changed = _enterShellOwned(state);
        _returnInputToTerminal(dock);
        return changed;
      case TerminalPaneProcessDisposition.foregroundProcess:
        final bool hadDirectoryOverride = state.directoryNavigatorOverride;
        var overrideChanged = false;
        if (state.directoryNavigatorOverride &&
            !_safeCanDisplayDirectory(state.paneId)) {
          state.directoryNavigatorOverride = false;
          overrideChanged = true;
        }
        final bool changed = _enterForeground(state, process);
        if (state.mode == TerminalContextDockContentMode.foregroundJob &&
            !state.directoryNavigatorOverride) {
          _returnInputToTerminal(dock);
        } else if (hadDirectoryOverride && !state.directoryNavigatorOverride) {
          // A replacement foreground identity clears the old explicit
          // Directory authority while it is still in activation debounce.
          _returnInputToTerminal(dock);
        }
        return changed || overrideChanged;
      case TerminalPaneProcessDisposition.nonLive:
      case TerminalPaneProcessDisposition.unavailable:
        throw StateError('unreachable process disposition');
    }
  }

  bool _suspendProjection(_TerminalContextDockProcessWindowState state) {
    final int? foregroundProcessGroup =
        state.identity?.foregroundProcessGroup ?? state.candidateProcessGroup;
    if (state.presentationSuspended ||
        foregroundProcessGroup == null ||
        !state.directoryRetentionEligible) {
      return false;
    }
    _cancelTransientState(state);
    state
      ..presentationSuspended = true
      ..suspendedForegroundProcessGroup = foregroundProcessGroup
      ..mode = TerminalContextDockContentMode.unavailable
      ..directorySuspended = true
      ..shellCommandStartedMicros = null
      ..generation = ++_nextGeneration;
    return true;
  }

  bool _resumePresented(
    _TerminalContextDockProcessWindowState state,
    TerminalPaneProcessSnapshot process,
  ) {
    final int? retainedProcessGroup = state.suspendedForegroundProcessGroup;
    final bool sameForegroundJob =
        process.disposition ==
            TerminalPaneProcessDisposition.foregroundProcess &&
        process.foregroundProcessGroup == retainedProcessGroup;
    state
      ..presentationSuspended = false
      ..suspendedForegroundProcessGroup = null
      ..generation = ++_nextGeneration;
    if (!sameForegroundJob) {
      state.directoryRetentionEligible = false;
      _safeInvalidateRetainedDirectory(state.paneId);
    }
    return true;
  }

  bool _enterDirectory(_TerminalContextDockProcessWindowState state) {
    final bool changed =
        state.mode != TerminalContextDockContentMode.directoryNavigator ||
        state.directorySuspended ||
        state.process != null ||
        state.candidateProcessGroup != null;
    _cancelTransientState(state);
    state
      ..mode = TerminalContextDockContentMode.directoryNavigator
      ..directorySuspended = false
      ..directoryRetentionEligible = true
      ..shellCommandStartedMicros = null;
    if (changed) state.generation = ++_nextGeneration;
    return changed;
  }

  bool _enterShellOwned(_TerminalContextDockProcessWindowState state) {
    final int now = _now();
    final bool entering =
        state.mode != TerminalContextDockContentMode.shellOwnedCommand;
    _cancelTransientState(state);
    state
      ..mode = TerminalContextDockContentMode.shellOwnedCommand
      ..directorySuspended = true
      ..shellCommandStartedMicros = entering
          ? now
          : state.shellCommandStartedMicros
      ..process = TerminalContextDockProcessSnapshot.shellOwned(
        observedAtMonotonicMicros: state.shellCommandStartedMicros ?? now,
      );
    if (entering) state.generation = ++_nextGeneration;
    return entering;
  }

  bool _enterForeground(
    _TerminalContextDockProcessWindowState state,
    TerminalPaneProcessSnapshot process,
  ) {
    final int? foreground = process.foregroundProcessGroup;
    if (foreground == null || foreground <= 0) {
      return _enterContentFree(
        state,
        TerminalContextDockContentMode.unavailable,
      );
    }
    final int now = _now();
    if (state.mode == TerminalContextDockContentMode.foregroundJob &&
        state.identity?.foregroundProcessGroup == foreground) {
      if (state.request == null &&
          (state.lastRichRequestMicros == null ||
              now - state.lastRichRequestMicros! >=
                  TerminalContextDockProcessLimits
                      .foregroundInventoryInterval
                      .inMicroseconds)) {
        _startRichRequest(state, process);
      }
      return false;
    }
    if (state.candidateProcessGroup != foreground) {
      _cancelTransientState(state);
      state
        ..mode = TerminalContextDockContentMode.directoryNavigator
        ..directorySuspended = true
        ..candidateProcessGroup = foreground
        ..candidateStartedMicros = now
        ..generation = ++_nextGeneration;
      _scheduleActivation(state);
      return true;
    }
    final int candidateStarted = state.candidateStartedMicros ?? now;
    final int remaining =
        TerminalContextDockProcessLimits
            .foregroundActivationDelay
            .inMicroseconds -
        (now - candidateStarted);
    if (remaining > 0) {
      _scheduleActivation(state, delay: Duration(microseconds: remaining));
      return false;
    }
    state.activationTask?.cancel();
    state
      ..activationTask = null
      ..candidateProcessGroup = null
      ..candidateStartedMicros = null
      ..mode = TerminalContextDockContentMode.foregroundJob
      ..directorySuspended = true
      ..identity = TerminalContextDockForegroundJobIdentity(
        sessionId: state.sessionId,
        foregroundProcessGroup: foreground,
        epoch: ++_nextForegroundEpoch,
      )
      ..process = TerminalContextDockProcessSnapshot.loading(
        identity: TerminalContextDockForegroundJobIdentity(
          sessionId: state.sessionId,
          foregroundProcessGroup: foreground,
          epoch: _nextForegroundEpoch,
        ),
        observedAtMonotonicMicros: now,
      )
      ..generation = ++_nextGeneration;
    _startRichRequest(state, process);
    return true;
  }

  bool _enterContentFree(
    _TerminalContextDockProcessWindowState state,
    TerminalContextDockContentMode mode,
  ) {
    final bool changed =
        state.mode != mode ||
        !state.directorySuspended ||
        state.process != null ||
        state.candidateProcessGroup != null;
    _cancelTransientState(state);
    state
      ..mode = mode
      ..directorySuspended = true
      ..directoryRetentionEligible = false
      ..shellCommandStartedMicros = null;
    if (changed) state.generation = ++_nextGeneration;
    return changed;
  }

  void _scheduleActivation(
    _TerminalContextDockProcessWindowState state, {
    Duration delay = TerminalContextDockProcessLimits.foregroundActivationDelay,
  }) {
    if (_isActive(state.activationTask)) return;
    late final TerminalContextDockScheduledTask scheduled;
    scheduled = _scheduleTask(delay, () {
      if (_isDisposed ||
          !_windows.containsValue(state) ||
          !identical(state.activationTask, scheduled)) {
        return;
      }
      state.activationTask = null;
      synchronize();
    });
    state.activationTask = scheduled;
  }

  void _startRichRequest(
    _TerminalContextDockProcessWindowState state,
    TerminalPaneProcessSnapshot process,
  ) {
    if (_isDisposed || state.request != null || state.identity == null) return;
    final int now = _now();
    final _TerminalContextDockRichRequest request =
        _TerminalContextDockRichRequest(
          windowId: state.windowId,
          paneId: state.paneId,
          sessionId: state.sessionId,
          identity: state.identity!,
          generation: state.generation,
        );
    state
      ..request = request
      ..lastRichRequestMicros = now;
    _requests.add(request);
    FutureOr<PtyForegroundJobSnapshot?> result;
    try {
      result = _resolveForegroundJob(state.paneId, state.sessionId);
    } on Object {
      _completeRichRequest(request, null);
      return;
    }
    unawaited(
      Future<PtyForegroundJobSnapshot?>.value(result).then(
        (snapshot) => _completeRichRequest(request, snapshot),
        onError: (Object _, StackTrace _) =>
            _completeRichRequest(request, null),
      ),
    );
  }

  void _completeRichRequest(
    _TerminalContextDockRichRequest request,
    PtyForegroundJobSnapshot? native,
  ) {
    _requests.remove(request);
    if (_isDisposed || request.cancelled) return;
    final _TerminalContextDockProcessWindowState? state =
        _windows[request.windowId];
    if (state == null || !identical(state.request, request)) return;
    state.request = null;
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      request.windowId,
    );
    final TerminalPaneProcessSnapshot process = _safeProcessSnapshot(
      request.paneId,
    );
    if (dock == null ||
        !dock.isVisible ||
        dock.targetPaneId != request.paneId ||
        !_safeCanPresentWindow(request.windowId) ||
        process.sessionId != request.sessionId ||
        process.disposition !=
            TerminalPaneProcessDisposition.foregroundProcess ||
        process.foregroundProcessGroup !=
            request.identity.foregroundProcessGroup ||
        !_safeCanObserveProcess(request.paneId, process) ||
        state.generation != request.generation ||
        state.identity != request.identity) {
      state.process = null;
      scheduleSynchronize();
      _onChanged?.call();
      return;
    }
    final int now = _now();
    if (native == null ||
        !native.isAvailable ||
        native.childProcessId != process.childProcessId ||
        native.owningProcessGroup != process.owningProcessGroup ||
        native.foregroundProcessGroup != process.foregroundProcessGroup) {
      state.process = TerminalContextDockProcessSnapshot.unavailable(
        identity: request.identity,
        observedAtMonotonicMicros: now,
        observationSystemError: native?.observationSystemError ?? -1,
      );
      state.generation = ++_nextGeneration;
      scheduleSynchronize();
      _onChanged?.call();
      return;
    }
    state
      ..process = _projectNative(request.identity, native, now)
      ..generation = ++_nextGeneration;
    _onChanged?.call();
  }

  TerminalContextDockProcessSnapshot _projectNative(
    TerminalContextDockForegroundJobIdentity identity,
    PtyForegroundJobSnapshot native,
    int now,
  ) {
    final List<TerminalContextDockProcessMember> members = native.members
        .map(TerminalContextDockProcessMember.fromPty)
        .toList(growable: false);
    final bool partial =
        native.observationSystemError != 0 ||
        native.memberIssueCount != 0 ||
        native.omittedMemberCount != 0 ||
        native.executablePath == null ||
        native.executablePathSystemError != 0 ||
        native.argumentsSystemError != 0 ||
        native.argumentsTruncated ||
        members.any((member) => member.isPartial);
    return TerminalContextDockProcessSnapshot(
      status: partial
          ? TerminalContextDockProcessStatus.partial
          : TerminalContextDockProcessStatus.ready,
      identity: identity,
      observedAtMonotonicMicros: now,
      elapsedMicroseconds: native.jobElapsedMicroseconds,
      members: members,
      totalMemberCount: native.totalMemberCount,
      omittedMemberCount: native.omittedMemberCount,
      memberIssueCount: native.memberIssueCount,
      primaryIndex: native.primaryIndex,
      executablePath: native.executablePath,
      executablePathSystemError: native.executablePathSystemError,
      arguments: _argumentsVisible ? native.arguments : const <String>[],
      totalArgumentCount: _argumentsVisible ? native.totalArgumentCount : 0,
      omittedArgumentCount: _argumentsVisible ? native.omittedArgumentCount : 0,
      argumentsTruncated: _argumentsVisible && native.argumentsTruncated,
      argumentsSystemError: _argumentsVisible ? native.argumentsSystemError : 0,
      observationSystemError: native.observationSystemError,
      argumentsHidden: !_argumentsVisible,
    );
  }

  void _focusDirectoryNavigator(
    _TerminalContextDockProcessWindowState state,
    TerminalContextDockWindowSnapshot dock,
  ) {
    try {
      dockState.requestNavigatorFocus(
        dock.windowId,
        dock.targetPaneId,
        TerminalContextDockNavigatorMode.move,
      );
    } on Object {
      state.directoryNavigatorOverride = false;
      _onChanged?.call();
      return;
    }
    // Project the Directory document and resume its bounded operations before
    // asking AppKit to move first responder into the editor.
    _onChanged?.call();
    final TerminalContextDockWindowSnapshot? projected = dockState
        .snapshotForWindow(dock.windowId);
    final _TerminalContextDockProcessWindowState? current =
        _windows[dock.windowId];
    if (projected == null ||
        !projected.isVisible ||
        projected.targetPaneId != dock.targetPaneId ||
        projected.pane.navigatorMode != TerminalContextDockNavigatorMode.move ||
        current == null ||
        !identical(current, state) ||
        current.mode != TerminalContextDockContentMode.foregroundJob ||
        !current.directoryNavigatorOverride) {
      state.directoryNavigatorOverride = false;
      _returnInputToTerminal(projected ?? dock);
      _onChanged?.call();
      return;
    }
    final TerminalContextDockFocusRequest request =
        TerminalContextDockFocusRequest(
          windowId: projected.windowId,
          paneId: projected.targetPaneId,
          stateGeneration: projected.generation,
          querySelectionGeneration: projected.pane.querySelectionGeneration,
        );
    var focused = false;
    try {
      focused = _focusNavigator(request);
    } on Object {
      focused = false;
    }
    if (!focused || !dockState.confirmNavigatorInput(request)) {
      state.directoryNavigatorOverride = false;
      final TerminalContextDockWindowSnapshot? latest = dockState
          .snapshotForWindow(dock.windowId);
      _returnInputToTerminal(latest ?? projected);
      _onChanged?.call();
      return;
    }
    _onChanged?.call();
  }

  void _returnInputToTerminal(TerminalContextDockWindowSnapshot dock) {
    if (!dock.navigatorOwnsInput) return;
    final TerminalContextDockFocusRequest request =
        TerminalContextDockFocusRequest(
          windowId: dock.windowId,
          paneId: dock.targetPaneId,
          stateGeneration: dock.generation,
          querySelectionGeneration: dock.pane.querySelectionGeneration,
        );
    try {
      if (_focusTerminal(request)) {
        final TerminalContextDockWindowSnapshot? current = dockState
            .snapshotForWindow(dock.windowId);
        if (current?.targetPaneId == dock.targetPaneId &&
            current!.navigatorOwnsInput) {
          dockState.focusTerminal(dock.windowId, dock.targetPaneId);
        }
      }
    } on Object {
      // The existing presenter reconciliation retains native focus authority.
    }
  }

  TerminalPaneProcessSnapshot _safeProcessSnapshot(PaneId paneId) {
    try {
      return _resolveProcessSnapshot(paneId);
    } on Object {
      return TerminalPaneProcessSnapshot.unavailable(
        sessionId: TerminalSessionId(paneId: paneId, generation: 1),
      );
    }
  }

  bool _safeCanPresentWindow(TerminalWindowId windowId) {
    try {
      return _canPresentWindow(windowId);
    } on Object {
      return false;
    }
  }

  bool _safeCanObserveProcess(
    PaneId paneId,
    TerminalPaneProcessSnapshot process,
  ) {
    try {
      return _canObserveProcess(paneId, process);
    } on Object {
      return false;
    }
  }

  bool _safeCanObserveDirectory(PaneId paneId) {
    try {
      return _canObserveDirectory(paneId);
    } on Object {
      return false;
    }
  }

  bool _safeCanDisplayDirectory(PaneId paneId) {
    try {
      return _canDisplayDirectory(paneId);
    } on Object {
      return false;
    }
  }

  void _safeInvalidateRetainedDirectory(PaneId paneId) {
    try {
      _invalidateRetainedDirectory(paneId);
    } on Object {
      // Invalidation is fail-closed in the process controller itself. The
      // callback only lets the Directory owner eagerly discard its content.
    }
  }

  bool _canToggleActiveWindowContent() {
    if (_isDisposed || applicationState.isDisposed || dockState.isDisposed) {
      return false;
    }
    final TerminalWindowState? window = applicationState.activeWindow;
    if (window == null || window.role != TerminalWindowRole.standard) {
      return false;
    }
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      window.id,
    );
    final _TerminalContextDockProcessWindowState? state = _windows[window.id];
    return dock != null &&
        dock.isVisible &&
        state != null &&
        state.paneId == dock.targetPaneId &&
        state.mode == TerminalContextDockContentMode.foregroundJob &&
        (state.directoryNavigatorOverride ||
            _safeCanDisplayDirectory(state.paneId));
  }

  void _ensurePoll() {
    if (_isDisposed ||
        !_windows.values.any((state) => !state.presentationSuspended)) {
      _cancelPoll();
      return;
    }
    if (_isActive(_pollTask)) return;
    late final TerminalContextDockScheduledTask scheduled;
    scheduled = _scheduleTask(
      TerminalContextDockProcessLimits.processStatePollInterval,
      () {
        if (!identical(_pollTask, scheduled)) return;
        _pollTask = null;
        synchronize();
      },
    );
    _pollTask = scheduled;
  }

  /// Removes the projected document without removing live-pane retention.
  ///
  /// Every presentation-only transition (pane, tab, window, application
  /// focus, native visibility, or Dock visibility) uses this one path. Rich
  /// process content and timers are discarded before the content-free job
  /// identity is parked by pane ID.
  bool _suspendWindowProjection(TerminalWindowId windowId) {
    final _TerminalContextDockProcessWindowState? state = _windows.remove(
      windowId,
    );
    if (state == null) return false;
    if (_suspendProjection(state)) {
      _parkPaneFocusSuspended(state);
      return true;
    }
    _cancelState(state);
    return true;
  }

  /// Discards every authority owned by a logical window after that window no
  /// longer exists. Presentation changes must use [_suspendWindowProjection].
  bool _discardWindowAuthority(TerminalWindowId windowId) {
    final _TerminalContextDockProcessWindowState? state = _windows.remove(
      windowId,
    );
    var changed = _discardPaneFocusSuspendedForWindow(windowId);
    if (state == null) return changed;
    if (state.presentationSuspended || state.directoryRetentionEligible) {
      _safeInvalidateRetainedDirectory(state.paneId);
    }
    _cancelState(state);
    return true;
  }

  bool _clearWindows() {
    if (_windows.isEmpty && _paneFocusSuspended.isEmpty) {
      return false;
    }
    for (final _TerminalContextDockProcessWindowState state
        in _windows.values) {
      if (state.presentationSuspended || state.directoryRetentionEligible) {
        _safeInvalidateRetainedDirectory(state.paneId);
      }
      _cancelState(state);
    }
    _windows.clear();
    for (final _TerminalContextDockProcessWindowState state
        in _paneFocusSuspended.values) {
      _safeInvalidateRetainedDirectory(state.paneId);
      _cancelState(state);
    }
    _paneFocusSuspended.clear();
    return true;
  }

  void _parkPaneFocusSuspended(_TerminalContextDockProcessWindowState state) {
    final _TerminalContextDockProcessWindowState? replaced = _paneFocusSuspended
        .remove(state.paneId);
    if (replaced != null && !identical(replaced, state)) {
      _safeInvalidateRetainedDirectory(replaced.paneId);
      _cancelState(replaced);
    }
    _paneFocusSuspended[state.paneId] = state;
  }

  bool _discardPaneFocusSuspendedForWindow(TerminalWindowId windowId) {
    final List<PaneId> paneIds = _paneFocusSuspended.entries
        .where((entry) => entry.value.windowId == windowId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final PaneId paneId in paneIds) {
      _discardPaneFocusSuspended(paneId, invalidateDirectory: true);
    }
    return paneIds.isNotEmpty;
  }

  void _discardPaneFocusSuspended(
    PaneId paneId, {
    required bool invalidateDirectory,
  }) {
    final _TerminalContextDockProcessWindowState? state = _paneFocusSuspended
        .remove(paneId);
    if (state == null) return;
    if (invalidateDirectory) _safeInvalidateRetainedDirectory(state.paneId);
    _cancelState(state);
  }

  void _cancelState(_TerminalContextDockProcessWindowState state) {
    _cancelTransientState(state);
    state
      ..process = null
      ..directoryRetentionEligible = false
      ..presentationSuspended = false
      ..suspendedForegroundProcessGroup = null;
  }

  void _cancelTransientState(_TerminalContextDockProcessWindowState state) {
    state.activationTask?.cancel();
    state.activationTask = null;
    final _TerminalContextDockRichRequest? request = state.request;
    if (request != null) {
      request.cancelled = true;
      _requests.remove(request);
      state.request = null;
    }
    state
      ..candidateProcessGroup = null
      ..candidateStartedMicros = null
      ..identity = null
      ..process = null
      ..lastRichRequestMicros = null
      ..directoryNavigatorOverride = false;
  }

  void _cancelDebounce() {
    _debounceTask?.cancel();
    _debounceTask = null;
  }

  void _cancelPoll() {
    _pollTask?.cancel();
    _pollTask = null;
  }

  int _now() {
    final int value = _monotonicMicros();
    if (value < 0 || (_hasObservedTime && value < _lastMonotonicMicros)) {
      throw StateError('Context Dock process monotonic time regressed');
    }
    _hasObservedTime = true;
    _lastMonotonicMicros = value;
    return value;
  }

  static bool _isActive(TerminalContextDockScheduledTask? task) =>
      task != null && !task.isCancelled;

  static bool _alwaysPresentWindow(TerminalWindowId _) => true;
  static bool _alwaysObserveProcess(PaneId _, TerminalPaneProcessSnapshot __) =>
      true;
  static bool _alwaysObserveDirectory(PaneId _) => true;
  static void _ignoreDirectoryInvalidation(PaneId _) {}
  static bool _acceptNavigatorFocus(TerminalContextDockFocusRequest _) => true;
  static bool _acceptTerminalFocus(TerminalContextDockFocusRequest _) => true;
  static TerminalContextDockScheduledTask _scheduleTimerTask(
    Duration delay,
    void Function() callback,
  ) => _TerminalContextDockTimerTask(delay, callback);
}

final class _TerminalContextDockProcessWindowState {
  _TerminalContextDockProcessWindowState({
    required this.windowId,
    required this.paneId,
    required this.sessionId,
    required this.generation,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final TerminalSessionId sessionId;
  int generation;
  TerminalContextDockContentMode mode =
      TerminalContextDockContentMode.unavailable;
  bool directorySuspended = true;
  int? candidateProcessGroup;
  int? candidateStartedMicros;
  TerminalContextDockScheduledTask? activationTask;
  TerminalContextDockForegroundJobIdentity? identity;
  TerminalContextDockProcessSnapshot? process;
  int? lastRichRequestMicros;
  int? shellCommandStartedMicros;
  _TerminalContextDockRichRequest? request;
  bool directoryNavigatorOverride = false;
  bool directoryRetentionEligible = false;
  bool presentationSuspended = false;
  int? suspendedForegroundProcessGroup;
}

final class _TerminalContextDockRichRequest {
  _TerminalContextDockRichRequest({
    required this.windowId,
    required this.paneId,
    required this.sessionId,
    required this.identity,
    required this.generation,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final TerminalSessionId sessionId;
  final TerminalContextDockForegroundJobIdentity identity;
  final int generation;
  bool cancelled = false;
}

final class _TerminalContextDockTimerTask
    implements TerminalContextDockScheduledTask {
  _TerminalContextDockTimerTask(Duration delay, void Function() callback) {
    _timer = Timer(delay, callback);
  }

  late final Timer _timer;

  @override
  bool get isCancelled => !_timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
