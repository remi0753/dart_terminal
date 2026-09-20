import 'dart:io';

import 'package:dart_terminal_notes_macos/dart_terminal_notes_macos.dart';
import 'package:dart_terminal_notes_macos/testing.dart';

void main() {
  final TerminalNotesNativeFfiBindings bindings =
      TerminalNotesNativeFfiBindings();
  if (bindings.abiVersion != 1 || bindings.liveSurfaceCount != 0) {
    stderr.writeln('unexpected terminal Notes native ABI state');
    exitCode = 1;
    return;
  }
  final TerminalNotesNativeSurface surface = TerminalNotesNativeSurface(
    bindings: bindings,
  );
  final TerminalNotesProjection projection = TerminalNotesProjection(
    paneId: 1,
    surfaceGeneration: 1,
    projectionGeneration: 1,
    storeRevision: BigInt.one,
    visibility: TerminalNotesVisibility.expanded,
    presentationEligible: true,
    activeCount: 1,
    dueCount: 0,
    featureState: TerminalNotesFeatureState.available,
    surfaceState: TerminalNotesSurfaceState.ready,
    readyCue: false,
    section: TerminalNotesCollectionSection.current,
    pageStart: 0,
    totalCount: 1,
    selectedToken: 1,
    editorMode: TerminalNotesEditorMode.inactive,
    messageKey: TerminalNotesMessageKey.none,
    cards: <TerminalNotesCard>[
      TerminalNotesCard(
        token: 1,
        body: 'native asset',
        color: TerminalNotesColor.yellow,
        status: TerminalNotesStatus.active,
        order: 0,
        due: false,
        triggerKind: null,
        triggerPhase: null,
      ),
    ],
  );
  if (surface.apply(projection) != TerminalNotesApplyDisposition.accepted) {
    stderr.writeln('native Note projection was rejected');
    exitCode = 1;
  }
  final TerminalNotesNativeSnapshot snapshot = surface.snapshot;
  if (!snapshot.initialized ||
      snapshot.projectionGeneration != 1 ||
      snapshot.projectedCardCount != 1 ||
      snapshot.acceptedProjectionCount != 1 ||
      snapshot.featureState != TerminalNotesFeatureState.available ||
      snapshot.surfaceState != TerminalNotesSurfaceState.ready ||
      snapshot.totalCount != 1) {
    stderr.writeln('native Note snapshot did not retain accepted state');
    exitCode = 1;
  }
  final TerminalNotesProjection maximumRevision = TerminalNotesProjection(
    paneId: 1,
    surfaceGeneration: 1,
    projectionGeneration: 2,
    storeRevision: TerminalNotesLimits.maximumUnsigned64,
    visibility: TerminalNotesVisibility.expanded,
    presentationEligible: true,
    activeCount: 1,
    dueCount: 0,
    featureState: TerminalNotesFeatureState.available,
    surfaceState: TerminalNotesSurfaceState.ready,
    readyCue: false,
    section: TerminalNotesCollectionSection.current,
    pageStart: 0,
    totalCount: 1,
    selectedToken: 1,
    editorMode: TerminalNotesEditorMode.inactive,
    messageKey: TerminalNotesMessageKey.none,
    cards: projection.cards,
  );
  if (surface.apply(maximumRevision) !=
          TerminalNotesApplyDisposition.accepted ||
      surface.snapshot.storeRevision != TerminalNotesLimits.maximumUnsigned64) {
    stderr.writeln('native Note surface lost unsigned revision bits');
    exitCode = 1;
  }
  if (surface.apply(projection) !=
          TerminalNotesApplyDisposition.rejectedStale ||
      surface.snapshot.projectionGeneration != 2) {
    stderr.writeln('native Note surface did not preserve last-good state');
    exitCode = 1;
  }
  surface.dispose();
  surface.dispose();
  if (bindings.liveSurfaceCount != 0) {
    stderr.writeln('native Note surface ownership leaked');
    exitCode = 1;
    return;
  }
  stdout.writeln('terminal Notes native asset hook passed');
}
