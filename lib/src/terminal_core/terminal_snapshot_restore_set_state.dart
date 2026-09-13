part of 'terminal_screen_set.dart';

/// Restores formatter-visible buffer ownership and viewport state after both
/// fresh grids and history have been populated.
void restoreTerminalScreenSetSnapshotState(
  TerminalScreenSet screens, {
  required TerminalScreenKind activeKind,
  required bool mode1049Active,
  required int viewportOffset,
  required int primaryViewportOffset,
}) {
  if (primaryViewportOffset < 0 ||
      primaryViewportOffset > screens.scrollback.length ||
      viewportOffset !=
          (activeKind == TerminalScreenKind.alternate
              ? 0
              : primaryViewportOffset) ||
      mode1049Active && activeKind != TerminalScreenKind.alternate) {
    throw StateError('invalid snapshot screen-set ownership');
  }
  screens._activeKind = activeKind;
  screens._mode1049Active = mode1049Active;
  screens._transitionGeneration++;
  screens._viewport
    .._primaryOffset = primaryViewportOffset
    .._seenHistoryGeneration = screens.scrollback.generation
    .._seenRowsAppended = screens.scrollback.totalRowsAppended
    .._seenContinuityGeneration = screens.scrollback.continuityGeneration
    .._seenPrimaryGeneration = screens.primary.generation
    .._seenAlternateGeneration = screens.alternate.generation
    .._seenTransitionGeneration = screens.transitionGeneration
    .._generation = screens._viewport._generation + 1;
  screens.activeScreen.requestFullSnapshot();
}
