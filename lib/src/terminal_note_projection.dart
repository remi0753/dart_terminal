import 'dart:convert';

import 'terminal_note_model.dart';
import 'terminal_pane.dart';

abstract final class TerminalNoteProjectionLimits {
  static const int protocolVersion = 1;
  static const int maximumExpandedCards = 64;
  static const int maximumExpandedBodyUtf8Bytes = 256 * 1024;
  static const int maximumGeneration = 0x7fffffffffffffff;
}

enum TerminalNoteSurfaceVisibility { collapsed, expanded }

enum TerminalNoteCollectionSection { current, detached }

enum TerminalNoteEditorMode { inactive, creating, editing }

/// Process-local card identity. It is never persisted or derived from Note ID.
final class TerminalNoteCardToken implements Comparable<TerminalNoteCardToken> {
  TerminalNoteCardToken(this.value) {
    if (value <= 0 || value > TerminalNoteProjectionLimits.maximumGeneration) {
      throw ArgumentError.value(value, 'value', 'must be a positive token');
    }
  }

  final int value;

  @override
  int compareTo(TerminalNoteCardToken other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is TerminalNoteCardToken && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TerminalNoteCardToken(<redacted>)';
}

/// Content-bearing card data allowed only in one expanded native projection.
final class TerminalNoteCardProjection {
  TerminalNoteCardProjection({
    required this.token,
    required this.body,
    required this.color,
    required this.status,
    required this.order,
    required this.due,
    required this.triggerKind,
    required this.triggerPhase,
  }) {
    final int bodyBytes = utf8.encode(body).length;
    if (bodyBytes > TerminalNoteLimits.maximumBodyUtf8Bytes || order < 0) {
      throw ArgumentError('Note card projection exceeds its bounds');
    }
    if (due != (triggerPhase == NoteTriggerPhase.due)) {
      throw ArgumentError('Note card delivery state is inconsistent');
    }
  }

  final TerminalNoteCardToken token;
  final String body;
  final NoteColorKey color;
  final NoteStatus status;
  final int order;
  final bool due;
  final NoteTriggerKind? triggerKind;
  final NoteTriggerPhase? triggerPhase;

  int get bodyUtf8Bytes => utf8.encode(body).length;

  @override
  String toString() =>
      'TerminalNoteCardProjection(<redacted>, due=$due, status=${status.name})';
}

/// Versioned immutable projection sent from the authority to one pane surface.
final class TerminalNoteSurfaceProjection {
  TerminalNoteSurfaceProjection({
    required this.paneId,
    required this.surfaceGeneration,
    required this.projectionGeneration,
    required this.storeRevision,
    required this.visibility,
    required this.presentationEligible,
    this.automaticPresentation = false,
    required this.activeCount,
    required this.dueCount,
    this.section = TerminalNoteCollectionSection.current,
    this.pageStart = 0,
    int? totalCount,
    this.selectedToken,
    this.editorMode = TerminalNoteEditorMode.inactive,
    this.draftGeneration = 0,
    required Iterable<TerminalNoteCardProjection> cards,
  }) : cards = List<TerminalNoteCardProjection>.unmodifiable(cards),
       totalCount = totalCount ?? cards.length {
    if (surfaceGeneration <= 0 ||
        surfaceGeneration > TerminalNoteProjectionLimits.maximumGeneration ||
        projectionGeneration <= 0 ||
        projectionGeneration > TerminalNoteProjectionLimits.maximumGeneration ||
        storeRevision < BigInt.zero ||
        activeCount < 0 ||
        dueCount < 0 ||
        dueCount > activeCount ||
        pageStart < 0 ||
        this.totalCount < 0 ||
        pageStart > this.totalCount ||
        pageStart + this.cards.length > this.totalCount ||
        draftGeneration < 0 ||
        draftGeneration > TerminalNoteProjectionLimits.maximumGeneration ||
        ((editorMode == TerminalNoteEditorMode.inactive) !=
            (draftGeneration == 0)) ||
        (editorMode == TerminalNoteEditorMode.creating &&
            selectedToken != null) ||
        (editorMode == TerminalNoteEditorMode.editing &&
            selectedToken == null) ||
        this.cards.length > TerminalNoteProjectionLimits.maximumExpandedCards ||
        this.cards
                .map((TerminalNoteCardProjection card) => card.token)
                .toSet()
                .length !=
            this.cards.length ||
        (selectedToken != null &&
            !this.cards.any(
              (TerminalNoteCardProjection card) => card.token == selectedToken,
            )) ||
        this.cards.fold<int>(
              0,
              (int total, TerminalNoteCardProjection card) =>
                  total + card.bodyUtf8Bytes,
            ) >
            TerminalNoteProjectionLimits.maximumExpandedBodyUtf8Bytes ||
        (visibility == TerminalNoteSurfaceVisibility.collapsed &&
            (this.cards.isNotEmpty ||
                selectedToken != null ||
                editorMode == TerminalNoteEditorMode.editing ||
                automaticPresentation)) ||
        (automaticPresentation &&
            editorMode != TerminalNoteEditorMode.inactive)) {
      throw ArgumentError('Note surface projection is invalid');
    }
  }

  static const int protocolVersion =
      TerminalNoteProjectionLimits.protocolVersion;

  final PaneId paneId;
  final int surfaceGeneration;
  final int projectionGeneration;
  final BigInt storeRevision;
  final TerminalNoteSurfaceVisibility visibility;
  final bool presentationEligible;
  final bool automaticPresentation;
  final int activeCount;
  final int dueCount;
  final TerminalNoteCollectionSection section;
  final int pageStart;
  final int totalCount;
  final TerminalNoteCardToken? selectedToken;
  final TerminalNoteEditorMode editorMode;
  final int draftGeneration;
  final List<TerminalNoteCardProjection> cards;

  int get aggregateBodyUtf8Bytes => cards.fold<int>(
    0,
    (int total, TerminalNoteCardProjection card) => total + card.bodyUtf8Bytes,
  );

  @override
  String toString() =>
      'TerminalNoteSurfaceProjection(v=$protocolVersion, '
      'surface=$surfaceGeneration, projection=$projectionGeneration, '
      'visibility=${visibility.name}, active=$activeCount, due=$dueCount, '
      'cards=${cards.length})';
}

/// Fake/native boundary owned by a pane. Apply must be atomic.
abstract interface class TerminalNoteSurfacePort {
  bool applyProjection(TerminalNoteSurfaceProjection projection);

  Future<void> dispose();
}
