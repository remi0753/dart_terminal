import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_application_state.dart';
import 'terminal_config.dart';
import 'terminal_input/terminal_appkit_key_adapter.dart';
import 'terminal_input/terminal_key_binding.dart';
import 'terminal_native_hierarchy.dart';
import 'terminal_product_configuration.dart';

/// Stable presentation phases for the singleton Quick Terminal.
enum TerminalQuickTerminalVisibility {
  hidden,
  showing,
  visible,
  hiding,
  disposed,
}

/// Immutable identity for one requested Quick Terminal visibility transition.
final class TerminalQuickTerminalTransition {
  const TerminalQuickTerminalTransition._({
    required this.generation,
    required this.targetVisible,
  });

  final int generation;
  final bool targetVisible;
}

/// Pure, generation-checked Quick Terminal presentation state.
///
/// Native animation and focus work may finish asynchronously. A newer request
/// supersedes the active transition, so completion from the old request cannot
/// mutate the current logical state.
final class TerminalQuickTerminalLifecycle {
  TerminalQuickTerminalVisibility _visibility =
      TerminalQuickTerminalVisibility.hidden;
  TerminalQuickTerminalTransition? _activeTransition;
  var _generation = 0;

  TerminalQuickTerminalVisibility get visibility => _visibility;
  TerminalQuickTerminalTransition? get activeTransition => _activeTransition;
  bool get isDisposed =>
      _visibility == TerminalQuickTerminalVisibility.disposed;
  bool get isTransitioning => _activeTransition != null;
  bool get isVisibleOrShowing => switch (_visibility) {
    TerminalQuickTerminalVisibility.showing ||
    TerminalQuickTerminalVisibility.visible => true,
    TerminalQuickTerminalVisibility.hidden ||
    TerminalQuickTerminalVisibility.hiding ||
    TerminalQuickTerminalVisibility.disposed => false,
  };

  TerminalQuickTerminalTransition requestToggle() {
    _requireLive();
    return requestVisibility(visible: !isVisibleOrShowing)!;
  }

  TerminalQuickTerminalTransition? requestAutohide({required bool enabled}) {
    _requireLive();
    if (!enabled || !isVisibleOrShowing) return null;
    return requestVisibility(visible: false);
  }

  TerminalQuickTerminalTransition? requestVisibility({required bool visible}) {
    _requireLive();
    if (_activeTransition == null && isVisibleOrShowing == visible) {
      return null;
    }
    final TerminalQuickTerminalTransition transition =
        TerminalQuickTerminalTransition._(
          generation: ++_generation,
          targetVisible: visible,
        );
    _activeTransition = transition;
    _visibility = visible
        ? TerminalQuickTerminalVisibility.showing
        : TerminalQuickTerminalVisibility.hiding;
    return transition;
  }

  /// Completes [transition], returning false when it has been superseded.
  bool complete(
    TerminalQuickTerminalTransition transition, {
    required bool succeeded,
  }) {
    _requireLive();
    if (!identical(_activeTransition, transition) ||
        transition.generation != _generation) {
      return false;
    }
    _activeTransition = null;
    final bool visible = succeeded
        ? transition.targetVisible
        : !transition.targetVisible;
    _visibility = visible
        ? TerminalQuickTerminalVisibility.visible
        : TerminalQuickTerminalVisibility.hidden;
    return true;
  }

  /// Invalidates in-flight native work and returns to a reusable hidden state.
  void resetHidden() {
    _requireLive();
    _generation++;
    _activeTransition = null;
    _visibility = TerminalQuickTerminalVisibility.hidden;
  }

  /// Invalidates every transition permanently. Repeated disposal is harmless.
  void dispose() {
    if (isDisposed) return;
    _generation++;
    _activeTransition = null;
    _visibility = TerminalQuickTerminalVisibility.disposed;
  }

  void _requireLive() {
    if (isDisposed) {
      throw StateError('Quick Terminal lifecycle is disposed');
    }
  }
}

/// Fixed-size animation endpoints within one current screen's visible frame.
final class TerminalQuickTerminalFrames {
  const TerminalQuickTerminalFrames._({
    required this.hidden,
    required this.target,
  });

  factory TerminalQuickTerminalFrames.resolve({
    required Rect visibleFrame,
    required double desiredWidth,
    required double desiredHeight,
  }) {
    _validateFrame(visibleFrame);
    if (!desiredWidth.isFinite || desiredWidth <= 0) {
      throw ArgumentError.value(desiredWidth, 'desiredWidth', 'must be > 0');
    }
    if (!desiredHeight.isFinite || desiredHeight <= 0) {
      throw ArgumentError.value(desiredHeight, 'desiredHeight', 'must be > 0');
    }
    final double width = desiredWidth.clamp(1, visibleFrame.width).toDouble();
    final double height = desiredHeight
        .clamp(1, visibleFrame.height)
        .toDouble();
    final double left = visibleFrame.left + (visibleFrame.width - width) / 2;
    final double visibleTop = visibleFrame.top + visibleFrame.height;
    final Rect target = Rect.fromLTWH(left, visibleTop - height, width, height);
    return TerminalQuickTerminalFrames._(
      hidden: Rect.fromLTWH(left, visibleTop, width, height),
      target: target,
    );
  }

  final Rect hidden;
  final Rect target;

  static void _validateFrame(Rect value) {
    if (!value.left.isFinite ||
        !value.top.isFinite ||
        !value.width.isFinite ||
        !value.height.isFinite ||
        value.width <= 0 ||
        value.height <= 0) {
      throw ArgumentError.value(value, 'visibleFrame', 'must be valid');
    }
  }
}

/// Native global-hot-key values projected from one configured physical chord.
final class TerminalQuickTerminalHotKeyBinding {
  const TerminalQuickTerminalHotKeyBinding._({
    required this.keyCode,
    required this.modifiers,
  });

  factory TerminalQuickTerminalHotKeyBinding.fromChord(
    TerminalKeyBindingChord chord,
  ) {
    final int? keyCode = TerminalAppKitKeyAdapter.keyCodeForPhysicalKey(
      chord.physicalKey,
    );
    if (keyCode == null) {
      throw ArgumentError.value(
        chord.physicalKey,
        'chord',
        'has no supported macOS virtual key code',
      );
    }
    final ModifierKeys modifiers = ModifierKeys(
      (chord.shift ? ModifierKeys.shiftBit : 0) |
          (chord.control ? ModifierKeys.controlBit : 0) |
          (chord.option ? ModifierKeys.optionBit : 0) |
          (chord.command ? ModifierKeys.commandBit : 0),
    );
    if (modifiers.bits == 0) {
      throw ArgumentError.value(chord, 'chord', 'must include a modifier');
    }
    return TerminalQuickTerminalHotKeyBinding._(
      keyCode: keyCode,
      modifiers: modifiers,
    );
  }

  final int keyCode;
  final ModifierKeys modifiers;
}

enum TerminalQuickTerminalShortcutFailure {
  unsupportedKey,
  conflict,
  systemFailure,
}

enum TerminalQuickTerminalShortcutDisposition { disabled, registered, failed }

/// Bounded, user-displayable result of the latest shortcut replacement.
final class TerminalQuickTerminalShortcutStatus {
  const TerminalQuickTerminalShortcutStatus.disabled()
    : disposition = TerminalQuickTerminalShortcutDisposition.disabled,
      desired = null,
      active = null,
      failure = null;

  const TerminalQuickTerminalShortcutStatus.registered(this.active)
    : disposition = TerminalQuickTerminalShortcutDisposition.registered,
      desired = active,
      failure = null;

  const TerminalQuickTerminalShortcutStatus.failed({
    required this.desired,
    required this.active,
    required this.failure,
  }) : disposition = TerminalQuickTerminalShortcutDisposition.failed;

  final TerminalQuickTerminalShortcutDisposition disposition;
  final TerminalKeyBindingChord? desired;
  final TerminalKeyBindingChord? active;
  final TerminalQuickTerminalShortcutFailure? failure;

  String get settingsLine => switch (disposition) {
    TerminalQuickTerminalShortcutDisposition.disabled =>
      'Quick Terminal shortcut: disabled',
    TerminalQuickTerminalShortcutDisposition.registered =>
      'Quick Terminal shortcut: active (${active!.configName})',
    TerminalQuickTerminalShortcutDisposition.failed =>
      'Quick Terminal shortcut: ${failure!.name}; requested '
          '${desired!.configName}; retained ${active?.configName ?? 'none'}',
  };

  String machineLine() =>
      'TERMINAL_QUICK_TERMINAL_SHORTCUT '
      'status=${disposition.name} '
      'failure=${failure?.name ?? 'none'} '
      'retained=${active == null ? 'false' : 'true'}';
}

AppKitScreenSelection terminalQuickTerminalScreenSelection(
  TerminalConfiguredQuickTerminalScreen value,
) => switch (value) {
  TerminalConfiguredQuickTerminalScreen.main => AppKitScreenSelection.main,
  TerminalConfiguredQuickTerminalScreen.mouse => AppKitScreenSelection.mouse,
  TerminalConfiguredQuickTerminalScreen.macosMenuBar =>
    AppKitScreenSelection.menuBar,
};

Duration terminalQuickTerminalAnimationDuration(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

typedef TerminalQuickTerminalPaneConfigurationFactory =
    TerminalPaneConfiguration Function();
typedef TerminalQuickTerminalConfigurationProvider =
    TerminalProductConfiguration Function();
typedef TerminalQuickTerminalGlobalInvocation = Future<void> Function();
typedef TerminalQuickTerminalErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Owns the product Quick Terminal's retained native presentation and hot key.
///
/// All calls run on the AppKit root isolate. The logical pane remains in the
/// shared application state while hidden; only final product teardown releases
/// its session and native view through the normal hierarchy owner.
final class TerminalQuickTerminalController {
  TerminalQuickTerminalController({
    required this.application,
    required this.state,
    required this.hierarchy,
    required TerminalQuickTerminalPaneConfigurationFactory
    paneConfigurationFactory,
    required TerminalQuickTerminalConfigurationProvider configuration,
    required void Function() reconcile,
    required TerminalQuickTerminalGlobalInvocation onGlobalInvocation,
    required void Function() onStatusChanged,
    required TerminalQuickTerminalErrorObserver onError,
  }) : _paneConfigurationFactory = paneConfigurationFactory,
       _configuration = configuration,
       _reconcile = reconcile,
       _onGlobalInvocation = onGlobalInvocation,
       _onStatusChanged = onStatusChanged,
       _onError = onError;

  static const WindowPresentationConfiguration windowPresentation =
      WindowPresentationConfiguration(
        level: WindowPresentationLevel.status,
        canJoinAllSpaces: true,
        fullScreenAuxiliary: true,
        stationary: true,
        transient: true,
      );

  final AppKitApplication application;
  final TerminalApplicationState state;
  final TerminalNativeHierarchyAdapter hierarchy;
  final TerminalQuickTerminalPaneConfigurationFactory _paneConfigurationFactory;
  final TerminalQuickTerminalConfigurationProvider _configuration;
  final void Function() _reconcile;
  final TerminalQuickTerminalGlobalInvocation _onGlobalInvocation;
  final void Function() _onStatusChanged;
  final TerminalQuickTerminalErrorObserver _onError;
  final TerminalQuickTerminalLifecycle lifecycle =
      TerminalQuickTerminalLifecycle();

  Future<void> _tail = Future<void>.value();
  GlobalHotKey? _globalHotKey;
  StreamSubscription<GlobalHotKeyPressedEvent>? _globalHotKeySubscription;
  TerminalKeyBindingChord? _activeShortcut;
  TerminalWindowId? _previousStandardWindowId;
  TerminalQuickTerminalFrames? _lastFrames;
  double? _lastBackingScaleFactor;
  TerminalQuickTerminalShortcutStatus _shortcutStatus =
      const TerminalQuickTerminalShortcutStatus.disabled();
  var _disposed = false;
  var _observedFocusSinceShow = false;

  bool get isDisposed => _disposed;
  TerminalQuickTerminalShortcutStatus get shortcutStatus => _shortcutStatus;
  TerminalKeyBindingChord? get activeShortcut => _activeShortcut;
  GlobalHotKey? get registeredHotKey => _globalHotKey;
  TerminalQuickTerminalFrames? get lastFrames => _lastFrames;
  double? get lastBackingScaleFactor => _lastBackingScaleFactor;

  Future<void> toggle() => _serialize(_toggle);

  Future<void> hide() => _serialize(() async {
    if (_disposed) return;
    final TerminalQuickTerminalTransition? transition = lifecycle
        .requestVisibility(visible: false);
    if (transition == null) return;
    await _hide(transition, _configuration());
  });

  Future<void> autohide() => _serialize(() async {
    if (_disposed) return;
    final TerminalProductConfiguration configuration = _configuration();
    final TerminalQuickTerminalTransition? transition = lifecycle
        .requestAutohide(enabled: configuration.quickTerminalAutohide);
    if (transition == null) return;
    await _hide(transition, configuration);
  });

  Future<void> handleFocusChanged({required bool isFocused}) {
    if (_disposed) return Future<void>.value();
    if (isFocused) {
      _observedFocusSinceShow = lifecycle.isVisibleOrShowing;
      return Future<void>.value();
    }
    if (!_observedFocusSinceShow) return Future<void>.value();
    _observedFocusSinceShow = false;
    return autohide();
  }

  Future<void> handleApplicationActiveChanged({required bool isActive}) {
    if (_disposed || isActive || !_observedFocusSinceShow) {
      return Future<void>.value();
    }
    _observedFocusSinceShow = false;
    return autohide();
  }

  Future<void> replaceShortcut(TerminalKeyBindingChord? desired) =>
      _serialize(() => _replaceShortcut(desired));

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _tail;
    } on Object {
      // The originating caller already receives and reports operation errors.
    }
    final StreamSubscription<GlobalHotKeyPressedEvent>? subscription =
        _globalHotKeySubscription;
    _globalHotKeySubscription = null;
    await subscription?.cancel();
    final GlobalHotKey? hotKey = _globalHotKey;
    _globalHotKey = null;
    if (hotKey != null && !hotKey.isDisposed) hotKey.dispose();
    _activeShortcut = null;
    lifecycle.dispose();
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final Future<void> next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _toggle() async {
    if (_disposed) throw StateError('Quick Terminal controller is disposed');
    final TerminalQuickTerminalTransition transition = lifecycle
        .requestToggle();
    final TerminalProductConfiguration configuration = _configuration();
    if (transition.targetVisible) {
      await _show(transition, configuration);
    } else {
      await _hide(transition, configuration);
    }
  }

  Future<void> _show(
    TerminalQuickTerminalTransition transition,
    TerminalProductConfiguration configuration,
  ) async {
    try {
      final AppKitResolvedScreen resolved = application.resolveScreen(
        terminalQuickTerminalScreenSelection(configuration.quickTerminalScreen),
      );
      final TerminalQuickTerminalFrames frames =
          TerminalQuickTerminalFrames.resolve(
            visibleFrame: resolved.screen.visibleFrame,
            desiredWidth: configuration.windowWidth,
            desiredHeight: configuration.windowHeight,
          );
      _lastFrames = frames;
      _lastBackingScaleFactor = resolved.backingScaleFactor;

      TerminalWindowState? quickWindow = state.quickTerminalWindow;
      final TerminalWindowState? active = state.activeWindow;
      if (active != null && active.role == TerminalWindowRole.standard) {
        _previousStandardWindowId = active.id;
      }
      if (quickWindow == null) {
        quickWindow = await state.createWindow(
          _paneConfigurationFactory(),
          role: TerminalWindowRole.quickTerminal,
        );
        hierarchy.updateWindowedFrame(
          quickWindow.id,
          frames.target,
          screen: resolved.screen,
          project: false,
        );
        _reconcile();
        await state.paneForId(quickWindow.selectedTab.focusedPaneId)!.start();
      } else {
        state.activateWindow(quickWindow.id);
        hierarchy.updateWindowedFrame(
          quickWindow.id,
          frames.target,
          screen: resolved.screen,
          project: false,
        );
        _reconcile();
      }

      final TerminalTabState tab = quickWindow.selectedTab;
      final Window window = hierarchy.windowForTab(tab.id)!;
      final TerminalNativePaneResources resources = hierarchy.resourcesForPane(
        tab.focusedPaneId,
      )!;
      window.presentationConfiguration = windowPresentation;
      resources.applyBackingScale(resolved.backingScaleFactor);
      window.makeFirstResponder(resources.view);
      _observedFocusSinceShow = false;
      window.present(
        startFrame: frames.hidden,
        targetFrame: frames.target,
        duration: terminalQuickTerminalAnimationDuration(
          configuration.quickTerminalAnimationDuration,
        ),
      );
      lifecycle.complete(transition, succeeded: true);
      _onStatusChanged();
    } on Object {
      lifecycle.complete(transition, succeeded: false);
      rethrow;
    }
  }

  Future<void> _hide(
    TerminalQuickTerminalTransition transition,
    TerminalProductConfiguration configuration,
  ) async {
    try {
      final TerminalWindowState? quickWindow = state.quickTerminalWindow;
      final TerminalQuickTerminalFrames? frames = _lastFrames;
      if (quickWindow != null && frames != null) {
        final Window? window = hierarchy.windowForTab(
          quickWindow.selectedTabId,
        );
        if (window != null && !window.isClosed && !window.isDisposed) {
          window.hide(
            targetFrame: frames.hidden,
            duration: terminalQuickTerminalAnimationDuration(
              configuration.quickTerminalAnimationDuration,
            ),
          );
        }
      }
      final TerminalWindowState? restore = _standardWindowToRestore();
      if (restore != null) state.activateWindow(restore.id);
      _observedFocusSinceShow = false;
      lifecycle.complete(transition, succeeded: true);
      _onStatusChanged();
    } on Object {
      lifecycle.complete(transition, succeeded: false);
      rethrow;
    }
  }

  TerminalWindowState? _standardWindowToRestore() {
    final TerminalWindowId? preferred = _previousStandardWindowId;
    if (preferred != null) {
      final TerminalWindowState? window = state.windowForId(preferred);
      if (window != null && window.role == TerminalWindowRole.standard) {
        return window;
      }
    }
    for (final TerminalWindowState window in state.windows.reversed) {
      if (window.role == TerminalWindowRole.standard) return window;
    }
    return null;
  }

  Future<void> _replaceShortcut(TerminalKeyBindingChord? desired) async {
    if (_disposed) return;
    if (desired == _activeShortcut) {
      _setShortcutStatus(
        desired == null
            ? const TerminalQuickTerminalShortcutStatus.disabled()
            : TerminalQuickTerminalShortcutStatus.registered(desired),
      );
      return;
    }
    if (desired == null) {
      final StreamSubscription<GlobalHotKeyPressedEvent>? oldSubscription =
          _globalHotKeySubscription;
      _globalHotKeySubscription = null;
      await oldSubscription?.cancel();
      final GlobalHotKey? old = _globalHotKey;
      _globalHotKey = null;
      if (old != null && !old.isDisposed) old.dispose();
      _activeShortcut = null;
      _setShortcutStatus(const TerminalQuickTerminalShortcutStatus.disabled());
      return;
    }

    GlobalHotKey? candidate;
    StreamSubscription<GlobalHotKeyPressedEvent>? candidateSubscription;
    try {
      final TerminalQuickTerminalHotKeyBinding binding =
          TerminalQuickTerminalHotKeyBinding.fromChord(desired);
      candidate = GlobalHotKey(
        keyCode: binding.keyCode,
        modifiers: binding.modifiers,
      );
      candidateSubscription = candidate.onPressed.listen((_) {
        unawaited(
          _onGlobalInvocation().catchError((Object error, StackTrace stack) {
            _onError(error, stack);
          }),
        );
      }, onError: _onError);
    } on Object catch (error) {
      await candidateSubscription?.cancel();
      if (candidate != null && !candidate.isDisposed) candidate.dispose();
      final TerminalQuickTerminalShortcutFailure failure = _shortcutFailure(
        error,
      );
      _setShortcutStatus(
        TerminalQuickTerminalShortcutStatus.failed(
          desired: desired,
          active: _activeShortcut,
          failure: failure,
        ),
      );
      return;
    }

    final StreamSubscription<GlobalHotKeyPressedEvent>? oldSubscription =
        _globalHotKeySubscription;
    final GlobalHotKey? old = _globalHotKey;
    _globalHotKeySubscription = candidateSubscription;
    _globalHotKey = candidate;
    _activeShortcut = desired;
    await oldSubscription?.cancel();
    if (old != null && !old.isDisposed) old.dispose();
    _setShortcutStatus(TerminalQuickTerminalShortcutStatus.registered(desired));
  }

  void _setShortcutStatus(TerminalQuickTerminalShortcutStatus value) {
    _shortcutStatus = value;
    _onStatusChanged();
  }

  static TerminalQuickTerminalShortcutFailure _shortcutFailure(Object error) {
    if (error is GlobalHotKeyRegistrationException) {
      return switch (error.reason) {
        GlobalHotKeyRegistrationFailure.unsupportedKey =>
          TerminalQuickTerminalShortcutFailure.unsupportedKey,
        GlobalHotKeyRegistrationFailure.conflict =>
          TerminalQuickTerminalShortcutFailure.conflict,
        GlobalHotKeyRegistrationFailure.systemFailure =>
          TerminalQuickTerminalShortcutFailure.systemFailure,
      };
    }
    if (error is ArgumentError) {
      return TerminalQuickTerminalShortcutFailure.unsupportedKey;
    }
    return TerminalQuickTerminalShortcutFailure.systemFailure;
  }
}
