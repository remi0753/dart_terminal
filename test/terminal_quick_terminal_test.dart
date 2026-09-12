import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalQuickTerminalTests();

void runTerminalQuickTerminalTests() {
  _testOrderedTransitionsAndFailureRecovery();
  _testSupersededTransitionsAndAutohide();
  _testResetAndDisposal();
  _testFixedSizeScreenGeometry();
  _testHotKeyProjectionAndStatus();
}

void _testOrderedTransitionsAndFailureRecovery() {
  final TerminalQuickTerminalLifecycle lifecycle =
      TerminalQuickTerminalLifecycle();
  _expect(
    lifecycle.visibility == TerminalQuickTerminalVisibility.hidden &&
        !lifecycle.isVisibleOrShowing &&
        !lifecycle.isTransitioning,
    'Quick Terminal starts hidden and stable',
  );

  final TerminalQuickTerminalTransition show = lifecycle.requestToggle();
  _expect(
    show.targetVisible &&
        show.generation == 1 &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.showing &&
        lifecycle.isVisibleOrShowing &&
        lifecycle.isTransitioning &&
        lifecycle.complete(show, succeeded: true) &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.visible,
    'a successful toggle reaches visible through one checked generation',
  );

  final TerminalQuickTerminalTransition hide = lifecycle.requestToggle();
  _expect(
    !hide.targetVisible &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.hiding &&
        lifecycle.complete(hide, succeeded: false) &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.visible &&
        !lifecycle.isTransitioning,
    'failed hiding restores the previous visible stable state',
  );
}

void _testSupersededTransitionsAndAutohide() {
  final TerminalQuickTerminalLifecycle lifecycle =
      TerminalQuickTerminalLifecycle();
  final TerminalQuickTerminalTransition show = lifecycle.requestToggle();
  final TerminalQuickTerminalTransition hide = lifecycle.requestToggle();
  _expect(
    show.generation == 1 &&
        hide.generation == 2 &&
        !hide.targetVisible &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.hiding &&
        !lifecycle.complete(show, succeeded: true) &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.hiding,
    'a stale native completion cannot overwrite a newer toggle',
  );
  _expect(
    lifecycle.complete(hide, succeeded: true) &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.hidden &&
        lifecycle.requestAutohide(enabled: true) == null,
    'the latest transition completes and hidden state ignores autohide',
  );

  final TerminalQuickTerminalTransition showAgain = lifecycle.requestToggle();
  lifecycle.complete(showAgain, succeeded: true);
  _expect(
    lifecycle.requestAutohide(enabled: false) == null &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.visible,
    'disabled autohide preserves visible state',
  );
  final TerminalQuickTerminalTransition autohide = lifecycle.requestAutohide(
    enabled: true,
  )!;
  _expect(
    !autohide.targetVisible &&
        lifecycle.complete(autohide, succeeded: true) &&
        lifecycle.visibility == TerminalQuickTerminalVisibility.hidden,
    'enabled autohide uses the same serialized hiding transition',
  );
}

void _testResetAndDisposal() {
  final TerminalQuickTerminalLifecycle lifecycle =
      TerminalQuickTerminalLifecycle();
  final TerminalQuickTerminalTransition stale = lifecycle.requestToggle();
  lifecycle.resetHidden();
  _expect(
    lifecycle.visibility == TerminalQuickTerminalVisibility.hidden &&
        !lifecycle.complete(stale, succeeded: true),
    'reset invalidates in-flight native completion',
  );
  lifecycle.dispose();
  lifecycle.dispose();
  _expect(
    lifecycle.visibility == TerminalQuickTerminalVisibility.disposed &&
        lifecycle.isDisposed &&
        !lifecycle.isTransitioning,
    'disposal is idempotent and terminal',
  );
  _expectThrows<StateError>(
    lifecycle.requestToggle,
    'disposed lifecycle rejects new presentation work',
  );
}

void _testFixedSizeScreenGeometry() {
  final TerminalQuickTerminalFrames ordinary =
      TerminalQuickTerminalFrames.resolve(
        visibleFrame: const Rect.fromLTWH(-1512, 48, 1512, 934),
        desiredWidth: 920,
        desiredHeight: 580,
      );
  _expect(
    ordinary.target == const Rect.fromLTWH(-1216, 402, 920, 580) &&
        ordinary.hidden == const Rect.fromLTWH(-1216, 982, 920, 580) &&
        ordinary.target.width == ordinary.hidden.width &&
        ordinary.target.height == ordinary.hidden.height,
    'Quick Terminal uses fixed-size endpoints at a negative-coordinate '
    'screen top edge',
  );

  final TerminalQuickTerminalFrames clamped =
      TerminalQuickTerminalFrames.resolve(
        visibleFrame: const Rect.fromLTWH(100, -200, 640, 480),
        desiredWidth: 920,
        desiredHeight: 580,
      );
  _expect(
    clamped.target == const Rect.fromLTWH(100, -200, 640, 480) &&
        clamped.hidden == const Rect.fromLTWH(100, 280, 640, 480),
    'Quick Terminal clamps both endpoints without changing their scale',
  );
}

void _testHotKeyProjectionAndStatus() {
  const TerminalKeyBindingChord chord = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.f18,
    control: true,
    option: true,
    command: true,
  );
  final TerminalQuickTerminalHotKeyBinding binding =
      TerminalQuickTerminalHotKeyBinding.fromChord(chord);
  _expect(
    binding.keyCode == 79 &&
        binding.modifiers.control &&
        binding.modifiers.option &&
        binding.modifiers.command &&
        !binding.modifiers.shift,
    'configured physical chord projects to its macOS virtual identity',
  );
  _expect(
    const TerminalQuickTerminalShortcutStatus.disabled().settingsLine ==
            'Quick Terminal shortcut: disabled' &&
        const TerminalQuickTerminalShortcutStatus.registered(chord).settingsLine
            .contains('active') &&
        const TerminalQuickTerminalShortcutStatus.failed(
              desired: chord,
              active: null,
              failure: TerminalQuickTerminalShortcutFailure.conflict,
            ).machineLine() ==
            'TERMINAL_QUICK_TERMINAL_SHORTCUT status=failed '
                'failure=conflict retained=false',
    'shortcut state has bounded Settings and machine projections',
  );
  _expect(
    terminalQuickTerminalScreenSelection(
          TerminalConfiguredQuickTerminalScreen.macosMenuBar,
        ) ==
        AppKitScreenSelection.menuBar,
    'configured screen maps to the reusable AppKit selector',
  );
  _expectThrows<ArgumentError>(
    () => TerminalQuickTerminalHotKeyBinding.fromChord(
      const TerminalKeyBindingChord(
        physicalKey: TerminalPhysicalKey.unknown,
        command: true,
      ),
    ),
    'unsupported physical key is rejected before native registration',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() body, String message) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError(message);
}
