import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'terminal_damage.dart';

typedef TerminalFrameBuilder<Frame> = Frame Function(
  TerminalDamageRenderModel model, {
  required int modelRevision,
  required int frameGeneration,
});

typedef TerminalFrameSubmitter<Frame> = TerminalFrameSubmissionOutcome Function(
  Frame frame, {
  required int modelRevision,
  required int frameGeneration,
});

enum TerminalFrameSubmissionDisposition { accepted, stale, backpressured }

final class TerminalFrameSubmissionOutcome {
  const TerminalFrameSubmissionOutcome._({
    required this.disposition,
    required this.acceptedFrameGeneration,
    required this.submissionToken,
    required this.nativeLastAcceptedFrameGeneration,
  });

  factory TerminalFrameSubmissionOutcome.accepted({
    required int frameGeneration,
    required int submissionToken,
  }) {
    _requireFrameGeneration(frameGeneration, 'frameGeneration');
    _requireFrameGeneration(submissionToken, 'submissionToken');
    return TerminalFrameSubmissionOutcome._(
      disposition: TerminalFrameSubmissionDisposition.accepted,
      acceptedFrameGeneration: frameGeneration,
      submissionToken: submissionToken,
      nativeLastAcceptedFrameGeneration: frameGeneration,
    );
  }

  factory TerminalFrameSubmissionOutcome.stale({
    required int nativeLastAcceptedFrameGeneration,
  }) {
    _requireFrameGeneration(
      nativeLastAcceptedFrameGeneration,
      'nativeLastAcceptedFrameGeneration',
    );
    return TerminalFrameSubmissionOutcome._(
      disposition: TerminalFrameSubmissionDisposition.stale,
      acceptedFrameGeneration: 0,
      submissionToken: 0,
      nativeLastAcceptedFrameGeneration: nativeLastAcceptedFrameGeneration,
    );
  }

  static const TerminalFrameSubmissionOutcome backpressured =
      TerminalFrameSubmissionOutcome._(
        disposition: TerminalFrameSubmissionDisposition.backpressured,
        acceptedFrameGeneration: 0,
        submissionToken: 0,
        nativeLastAcceptedFrameGeneration: 0,
      );

  final TerminalFrameSubmissionDisposition disposition;
  final int acceptedFrameGeneration;
  final int submissionToken;
  final int nativeLastAcceptedFrameGeneration;
}

enum TerminalFrameAttemptDisposition {
  idle,
  accepted,
  stale,
  backpressured,
  superseded,
}

final class TerminalFrameAttemptResult {
  const TerminalFrameAttemptResult({
    required this.disposition,
    required this.modelRevision,
    required this.frameGeneration,
    required this.submissionToken,
  });

  final TerminalFrameAttemptDisposition disposition;
  final int modelRevision;
  final int frameGeneration;
  final int submissionToken;

  bool get isAccepted =>
      disposition == TerminalFrameAttemptDisposition.accepted;
}

/// Applies every damage delta but prepares only the newest useful frame.
///
/// A built frame is submitted or discarded in the same synchronous turn. On
/// backpressure/stale native outcomes only the newest model revision remains
/// pending; no packed frame or per-revision queue is retained.
final class TerminalNewestFrameScheduler<Frame> {
  TerminalNewestFrameScheduler({
    required this.model,
    required TerminalFrameBuilder<Frame> buildFrame,
    required TerminalFrameSubmitter<Frame> submitFrame,
    int initialFrameGeneration = 0,
  }) : _buildFrame = buildFrame,
       _submitFrame = submitFrame,
       _nextFrameGeneration = initialFrameGeneration + 1 {
    RangeError.checkValueInInterval(
      initialFrameGeneration,
      0,
      0x7ffffffffffffffe,
      'initialFrameGeneration',
    );
  }

  final TerminalDamageRenderModel model;
  final TerminalFrameBuilder<Frame> _buildFrame;
  final TerminalFrameSubmitter<Frame> _submitFrame;
  int _nextFrameGeneration;
  bool _frameGenerationExhausted = false;
  int _newestModelRevision = 0;
  int _lastAcceptedModelRevision = 0;
  int _lastAcceptedFrameGeneration = 0;
  bool _pending = false;
  bool _attempting = false;
  int _buildCount = 0;
  int _acceptedCount = 0;
  int _staleCount = 0;
  int _backpressureCount = 0;
  int _supersededCount = 0;

  int get newestModelRevision => _newestModelRevision;
  int get lastAcceptedModelRevision => _lastAcceptedModelRevision;
  int get lastAcceptedFrameGeneration => _lastAcceptedFrameGeneration;
  bool get hasPendingFrame => _pending;
  int get pendingFrameCount => _pending ? 1 : 0;
  bool get isAttempting => _attempting;
  int get buildCount => _buildCount;
  int get acceptedCount => _acceptedCount;
  int get staleCount => _staleCount;
  int get backpressureCount => _backpressureCount;
  int get supersededCount => _supersededCount;

  TerminalDamageApplyResult applyDamage(
    TerminalDecodedDamage damage, {
    required int availableResourceGeneration,
  }) {
    final TerminalDamageApplyResult result = model.apply(
      damage,
      availableResourceGeneration: availableResourceGeneration,
    );
    if (result.isApplied) {
      if (damage.damageGeneration <= _newestModelRevision) {
        throw StateError('applied damage did not advance the model revision');
      }
      _newestModelRevision = damage.damageGeneration;
      _pending = true;
    }
    return result;
  }

  TerminalFrameAttemptResult submitNewest() {
    if (_attempting) {
      throw StateError('frame submission attempt is already active');
    }
    if (!_pending) {
      return TerminalFrameAttemptResult(
        disposition: TerminalFrameAttemptDisposition.idle,
        modelRevision: _newestModelRevision,
        frameGeneration: 0,
        submissionToken: 0,
      );
    }
    if (_frameGenerationExhausted) {
      throw StateError('frame generation capacity exhausted');
    }
    _attempting = true;
    final int targetRevision = _newestModelRevision;
    final int frameGeneration = _allocateFrameGeneration();
    _pending = false;
    try {
      final Frame frame = _buildFrame(
        model,
        modelRevision: targetRevision,
        frameGeneration: frameGeneration,
      );
      _buildCount++;
      if (_newestModelRevision != targetRevision) {
        _pending = true;
        _supersededCount++;
        return TerminalFrameAttemptResult(
          disposition: TerminalFrameAttemptDisposition.superseded,
          modelRevision: targetRevision,
          frameGeneration: frameGeneration,
          submissionToken: 0,
        );
      }
      final TerminalFrameSubmissionOutcome outcome = _submitFrame(
        frame,
        modelRevision: targetRevision,
        frameGeneration: frameGeneration,
      );
      switch (outcome.disposition) {
        case TerminalFrameSubmissionDisposition.accepted:
          if (outcome.acceptedFrameGeneration != frameGeneration ||
              outcome.submissionToken <= 0) {
            throw StateError('native accepted the wrong frame generation');
          }
          _lastAcceptedModelRevision = targetRevision;
          _lastAcceptedFrameGeneration = frameGeneration;
          _acceptedCount++;
          if (_newestModelRevision != targetRevision) _pending = true;
          return TerminalFrameAttemptResult(
            disposition: TerminalFrameAttemptDisposition.accepted,
            modelRevision: targetRevision,
            frameGeneration: frameGeneration,
            submissionToken: outcome.submissionToken,
          );
        case TerminalFrameSubmissionDisposition.stale:
          if (outcome.nativeLastAcceptedFrameGeneration < frameGeneration) {
            throw StateError('native stale floor is below the attempted frame');
          }
          _advancePastNativeFrame(outcome.nativeLastAcceptedFrameGeneration);
          _pending = true;
          _staleCount++;
          return TerminalFrameAttemptResult(
            disposition: TerminalFrameAttemptDisposition.stale,
            modelRevision: targetRevision,
            frameGeneration: frameGeneration,
            submissionToken: 0,
          );
        case TerminalFrameSubmissionDisposition.backpressured:
          _pending = true;
          _backpressureCount++;
          return TerminalFrameAttemptResult(
            disposition: TerminalFrameAttemptDisposition.backpressured,
            modelRevision: targetRevision,
            frameGeneration: frameGeneration,
            submissionToken: 0,
          );
      }
    } on Object {
      _pending = true;
      rethrow;
    } finally {
      _attempting = false;
    }
  }

  int _allocateFrameGeneration() {
    final int generation = _nextFrameGeneration;
    if (generation == 0x7fffffffffffffff) {
      _frameGenerationExhausted = true;
    } else {
      _nextFrameGeneration++;
    }
    return generation;
  }

  void _advancePastNativeFrame(int nativeGeneration) {
    if (nativeGeneration == 0x7fffffffffffffff) {
      _frameGenerationExhausted = true;
      return;
    }
    if (!_frameGenerationExhausted &&
        _nextFrameGeneration <= nativeGeneration) {
      _nextFrameGeneration = nativeGeneration + 1;
    }
  }
}

final class TerminalScheduledMetalFrame {
  TerminalScheduledMetalFrame({
    required this.frame,
    Iterable<TerminalGlyphAtlasEntry> glyphEntries =
        const <TerminalGlyphAtlasEntry>[],
  }) : glyphEntries = List<TerminalGlyphAtlasEntry>.unmodifiable(glyphEntries);

  final TerminalMetalFrame frame;
  final List<TerminalGlyphAtlasEntry> glyphEntries;
}

/// Maps the typed native renderer result into scheduler-owned outcomes.
final class TerminalMetalFrameSubmissionAdapter {
  const TerminalMetalFrameSubmissionAdapter(this.bridge);

  final TerminalGlyphAtlasMetalBridge bridge;

  TerminalFrameSubmissionOutcome submit(
    TerminalScheduledMetalFrame scheduled, {
    required int modelRevision,
    required int frameGeneration,
  }) {
    if (modelRevision <= 0 ||
        scheduled.frame.frameGeneration != frameGeneration) {
      throw ArgumentError('scheduled Metal frame does not match its attempt');
    }
    final TerminalMetalSubmissionResult result = bridge.submit(
      scheduled.frame,
      glyphEntries: scheduled.glyphEntries,
    );
    return switch (result.disposition) {
      TerminalMetalSubmissionDisposition.accepted =>
        TerminalFrameSubmissionOutcome.accepted(
          frameGeneration: result.frameGeneration,
          submissionToken: result.submissionToken,
        ),
      TerminalMetalSubmissionDisposition.backpressured =>
        TerminalFrameSubmissionOutcome.backpressured,
      TerminalMetalSubmissionDisposition.stale =>
        TerminalFrameSubmissionOutcome.stale(
          nativeLastAcceptedFrameGeneration: bridge.renderer
              .state()
              .lastAcceptedFrameGeneration,
        ),
    };
  }
}

void _requireFrameGeneration(int value, String name) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    throw RangeError.range(value, 1, 0x7fffffffffffffff, name);
  }
}
