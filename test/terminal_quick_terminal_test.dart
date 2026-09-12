import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalQuickTerminalTests();

void runTerminalQuickTerminalTests() {
  _testOrderedTransitionsAndFailureRecovery();
  _testSupersededTransitionsAndAutohide();
  _testResetAndDisposal();
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
