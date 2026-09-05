import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_core/terminal_screen.dart';
import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'terminal_damage.dart';

typedef TerminalFrameBuilder<Frame> = Frame Function(
  TerminalDamageRenderModel model, {
  required int modelRevision,
  required int frameGeneration,
  required TerminalFramePresentation presentation,
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
  paused,
  accepted,
  stale,
  backpressured,
  superseded,
}

final class TerminalFramePresentation {
  const TerminalFramePresentation({
    required this.revision,
    required this.cursorDrawn,
    required this.visualBellActive,
    required this.requiresFullRedraw,
  });

  final int revision;
  final bool cursorDrawn;
  final bool visualBellActive;
  final bool requiresFullRedraw;
}

/// One deadline per animation kind, driven by an injected monotonic clock.
///
/// Late calls toggle a cursor at most once and schedule from the observed
/// instant. Pause drops all deadlines and bell pulses; resume starts a visible
/// cursor phase without replaying hidden work.
final class TerminalPresentationClock {
  TerminalPresentationClock({
    this.cursorOnDuration = const Duration(milliseconds: 500),
    this.cursorOffDuration = const Duration(milliseconds: 500),
    this.visualBellDuration = const Duration(milliseconds: 100),
    int initialRevision = 0,
  }) : _revision = initialRevision {
    _validateDuration(cursorOnDuration, 'cursorOnDuration');
    _validateDuration(cursorOffDuration, 'cursorOffDuration');
    _validateDuration(visualBellDuration, 'visualBellDuration');
    RangeError.checkValueInInterval(
      initialRevision,
      0,
      _maximumSignedGeneration,
      'initialRevision',
    );
  }

  static const Duration maximumDuration = Duration(minutes: 1);

  final Duration cursorOnDuration;
  final Duration cursorOffDuration;
  final Duration visualBellDuration;

  int _revision;
  bool _running = true;
  bool _cursorDrawn = false;
  bool _cursorBlinking = false;
  bool _cursorVisible = false;
  int _cursorRow = 0;
  int _cursorColumn = 0;
  TerminalCursorShape _cursorShape = TerminalCursorShape.block;
  int _lastVisualBellGeneration = 0;
  bool _visualBellActive = false;
  int? _cursorDeadlineMicros;
  int? _visualBellDeadlineMicros;
  int _lastMonotonicMicros = 0;
  bool _hasObservedTime = false;

  int get revision => _revision;
  bool get isRunning => _running;
  bool get cursorDrawn => _running && _cursorDrawn;
  bool get visualBellActive => _running && _visualBellActive;
  int get lastVisualBellGeneration => _lastVisualBellGeneration;
  int? get nextDeadlineMicros {
    if (!_running) return null;
    final int? cursor = _cursorDeadlineMicros;
    final int? bell = _visualBellDeadlineMicros;
    if (cursor == null) return bell;
    if (bell == null) return cursor;
    return cursor < bell ? cursor : bell;
  }

  void synchronize(
    TerminalDamageRenderModel model, {
    required int monotonicMicros,
  }) {
    if (!model.isInitialized) {
      throw StateError('presentation clock requires an initialized model');
    }
    _validateTime(monotonicMicros);
    if (model.visualBellGeneration < _lastVisualBellGeneration) {
      throw StateError('presentation bell generation regressed');
    }
    _observeTime(monotonicMicros);
    final bool cursorChanged =
        _cursorVisible != model.cursorVisible ||
        _cursorBlinking != model.cursorBlinking ||
        _cursorRow != model.cursorRow ||
        _cursorColumn != model.cursorColumn ||
        _cursorShape != model.cursorShape;
    _cursorVisible = model.cursorVisible;
    _cursorBlinking = model.cursorBlinking;
    _cursorRow = model.cursorRow;
    _cursorColumn = model.cursorColumn;
    _cursorShape = model.cursorShape;

    if (_running) {
      if (!_cursorVisible) {
        _cursorDrawn = false;
        _cursorDeadlineMicros = null;
      } else if (!_cursorBlinking) {
        _cursorDrawn = true;
        _cursorDeadlineMicros = null;
      } else if (cursorChanged || _cursorDeadlineMicros == null) {
        _cursorDrawn = true;
        _cursorDeadlineMicros = _boundedDeadline(
          monotonicMicros,
          cursorOnDuration.inMicroseconds,
        );
      }
    }

    if (model.visualBellGeneration > _lastVisualBellGeneration) {
      _lastVisualBellGeneration = model.visualBellGeneration;
      if (_running) {
        _visualBellActive = true;
        _visualBellDeadlineMicros = _boundedDeadline(
          monotonicMicros,
          visualBellDuration.inMicroseconds,
        );
      }
    }
  }

  bool advance({required int monotonicMicros}) {
    _validateTime(monotonicMicros);
    if (!_running) {
      _observeTime(monotonicMicros);
      return false;
    }
    final bool cursorDue =
        _cursorDeadlineMicros != null &&
        monotonicMicros >= _cursorDeadlineMicros!;
    final bool bellDue =
        _visualBellDeadlineMicros != null &&
        monotonicMicros >= _visualBellDeadlineMicros!;
    if (!cursorDue && !bellDue) {
      _observeTime(monotonicMicros);
      return false;
    }
    _advanceRevision();
    _observeTime(monotonicMicros);
    if (cursorDue) {
      _cursorDrawn = !_cursorDrawn;
      _cursorDeadlineMicros = monotonicMicros == _maximumSignedGeneration
          ? null
          : _boundedDeadline(
              monotonicMicros,
              (_cursorDrawn ? cursorOnDuration : cursorOffDuration)
                  .inMicroseconds,
            );
    }
    if (bellDue) {
      _visualBellActive = false;
      _visualBellDeadlineMicros = null;
    }
    return true;
  }

  bool pause({required int monotonicMicros}) {
    _validateTime(monotonicMicros);
    if (!_running) {
      _observeTime(monotonicMicros);
      return false;
    }
    _advanceRevision();
    _observeTime(monotonicMicros);
    _running = false;
    _cursorDrawn = false;
    _visualBellActive = false;
    _cursorDeadlineMicros = null;
    _visualBellDeadlineMicros = null;
    return true;
  }

  bool resume(
    TerminalDamageRenderModel? model, {
    required int monotonicMicros,
  }) {
    _validateTime(monotonicMicros);
    if (_running) {
      _observeTime(monotonicMicros);
      return false;
    }
    _advanceRevision();
    _observeTime(monotonicMicros);
    _running = true;
    _visualBellActive = false;
    _visualBellDeadlineMicros = null;
    if (model == null || !model.isInitialized) {
      _cursorDrawn = false;
      _cursorDeadlineMicros = null;
      return true;
    }
    _cursorVisible = model.cursorVisible;
    _cursorBlinking = model.cursorBlinking;
    _cursorRow = model.cursorRow;
    _cursorColumn = model.cursorColumn;
    _cursorShape = model.cursorShape;
    _lastVisualBellGeneration = model.visualBellGeneration;
    _cursorDrawn = _cursorVisible;
    _cursorDeadlineMicros = _cursorVisible && _cursorBlinking
        ? _boundedDeadline(monotonicMicros, cursorOnDuration.inMicroseconds)
        : null;
    return true;
  }

  TerminalFramePresentation snapshot({required bool requiresFullRedraw}) =>
      TerminalFramePresentation(
        revision: _revision,
        cursorDrawn: cursorDrawn,
        visualBellActive: visualBellActive,
        requiresFullRedraw: requiresFullRedraw,
      );

  void _validateTime(int monotonicMicros) {
    RangeError.checkValueInInterval(
      monotonicMicros,
      0,
      _maximumSignedGeneration,
      'monotonicMicros',
    );
    if (_hasObservedTime && monotonicMicros < _lastMonotonicMicros) {
      throw StateError('presentation monotonic time regressed');
    }
  }

  void _observeTime(int monotonicMicros) {
    _validateTime(monotonicMicros);
    _lastMonotonicMicros = monotonicMicros;
    _hasObservedTime = true;
  }

  int _boundedDeadline(int now, int duration) =>
      now > _maximumSignedGeneration - duration
      ? _maximumSignedGeneration
      : now + duration;

  void _advanceRevision() {
    if (_revision == _maximumSignedGeneration) {
      throw StateError('presentation revision capacity exhausted');
    }
    _revision++;
  }

  static void _validateDuration(Duration duration, String name) {
    if (duration <= Duration.zero ||
        duration.inMicroseconds > maximumDuration.inMicroseconds) {
      throw ArgumentError.value(
        duration,
        name,
        'must be positive and at most $maximumDuration',
      );
    }
  }
}

final class TerminalFrameAttemptResult {
  const TerminalFrameAttemptResult({
    required this.disposition,
    required this.modelRevision,
    required this.presentationRevision,
    required this.frameGeneration,
    required this.submissionToken,
    required this.requiresFullRedraw,
  });

  final TerminalFrameAttemptDisposition disposition;
  final int modelRevision;
  final int presentationRevision;
  final int frameGeneration;
  final int submissionToken;
  final bool requiresFullRedraw;

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
    TerminalPresentationClock? presentationClock,
    int initialFrameGeneration = 0,
  }) : _buildFrame = buildFrame,
       _submitFrame = submitFrame,
       presentationClock = presentationClock ?? TerminalPresentationClock(),
       _nextFrameGeneration = initialFrameGeneration + 1 {
    RangeError.checkValueInInterval(
      initialFrameGeneration,
      0,
      0x7ffffffffffffffe,
      'initialFrameGeneration',
    );
  }

  final TerminalDamageRenderModel model;
  final TerminalPresentationClock presentationClock;
  final TerminalFrameBuilder<Frame> _buildFrame;
  final TerminalFrameSubmitter<Frame> _submitFrame;
  int _nextFrameGeneration;
  bool _frameGenerationExhausted = false;
  int _newestModelRevision = 0;
  int _lastAcceptedModelRevision = 0;
  int _lastAcceptedFrameGeneration = 0;
  int _lastAcceptedPresentationRevision = 0;
  bool _isWindowVisible = true;
  bool _isWindowOccluded = false;
  Object? _fullRedrawMarker;
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
  int get lastAcceptedPresentationRevision => _lastAcceptedPresentationRevision;
  bool get isWindowVisible => _isWindowVisible;
  bool get isWindowOccluded => _isWindowOccluded;
  bool get isPresentationActive => _isWindowVisible && !_isWindowOccluded;
  int? get nextPresentationDeadlineMicros =>
      isPresentationActive ? presentationClock.nextDeadlineMicros : null;
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
    required int monotonicMicros,
  }) {
    presentationClock._validateTime(monotonicMicros);
    final TerminalDamageApplyResult result = model.apply(
      damage,
      availableResourceGeneration: availableResourceGeneration,
    );
    if (result.isApplied) {
      if (damage.damageGeneration <= _newestModelRevision) {
        throw StateError('applied damage did not advance the model revision');
      }
      _newestModelRevision = damage.damageGeneration;
      presentationClock.synchronize(model, monotonicMicros: monotonicMicros);
      if (damage.isFullSnapshot) _fullRedrawMarker = Object();
      _pending = true;
    }
    return result;
  }

  bool advancePresentation({required int monotonicMicros}) {
    final bool changed = presentationClock.advance(
      monotonicMicros: monotonicMicros,
    );
    if (changed && model.isInitialized) _pending = true;
    return changed;
  }

  /// Applies immutable AppKit visibility/occlusion observations.
  ///
  /// Remaining hidden through a raw state change does not create work. A
  /// transition back to presentable state retains one full-redraw marker.
  bool updateWindowState({
    bool? isVisible,
    bool? isOccluded,
    required int monotonicMicros,
  }) {
    presentationClock._validateTime(monotonicMicros);
    final bool nextVisible = isVisible ?? _isWindowVisible;
    final bool nextOccluded = isOccluded ?? _isWindowOccluded;
    if (nextVisible == _isWindowVisible && nextOccluded == _isWindowOccluded) {
      presentationClock._observeTime(monotonicMicros);
      return false;
    }
    final bool wasActive = isPresentationActive;
    final bool becomesActive = nextVisible && !nextOccluded;
    if (wasActive && !becomesActive) {
      presentationClock.pause(monotonicMicros: monotonicMicros);
    } else if (!wasActive && becomesActive) {
      presentationClock.resume(
        model.isInitialized ? model : null,
        monotonicMicros: monotonicMicros,
      );
    } else {
      presentationClock._observeTime(monotonicMicros);
    }
    _isWindowVisible = nextVisible;
    _isWindowOccluded = nextOccluded;
    if (!wasActive && becomesActive && model.isInitialized) {
      _fullRedrawMarker = Object();
      _pending = true;
    }
    return true;
  }

  TerminalFrameAttemptResult submitNewest() {
    if (_attempting) {
      throw StateError('frame submission attempt is already active');
    }
    if (!_pending) {
      return TerminalFrameAttemptResult(
        disposition: TerminalFrameAttemptDisposition.idle,
        modelRevision: _newestModelRevision,
        presentationRevision: presentationClock.revision,
        frameGeneration: 0,
        submissionToken: 0,
        requiresFullRedraw: false,
      );
    }
    if (!isPresentationActive) {
      return TerminalFrameAttemptResult(
        disposition: TerminalFrameAttemptDisposition.paused,
        modelRevision: _newestModelRevision,
        presentationRevision: presentationClock.revision,
        frameGeneration: 0,
        submissionToken: 0,
        requiresFullRedraw: _fullRedrawMarker != null,
      );
    }
    if (_frameGenerationExhausted) {
      throw StateError('frame generation capacity exhausted');
    }
    _attempting = true;
    final int targetRevision = _newestModelRevision;
    final int targetPresentationRevision = presentationClock.revision;
    final Object? targetFullRedrawMarker = _fullRedrawMarker;
    final TerminalFramePresentation presentation = presentationClock.snapshot(
      requiresFullRedraw: targetFullRedrawMarker != null,
    );
    final int frameGeneration = _allocateFrameGeneration();
    _pending = false;
    try {
      final Frame frame = _buildFrame(
        model,
        modelRevision: targetRevision,
        frameGeneration: frameGeneration,
        presentation: presentation,
      );
      _buildCount++;
      if (_newestModelRevision != targetRevision ||
          presentationClock.revision != targetPresentationRevision ||
          !isPresentationActive) {
        _pending = true;
        _supersededCount++;
        return TerminalFrameAttemptResult(
          disposition: TerminalFrameAttemptDisposition.superseded,
          modelRevision: targetRevision,
          presentationRevision: targetPresentationRevision,
          frameGeneration: frameGeneration,
          submissionToken: 0,
          requiresFullRedraw: presentation.requiresFullRedraw,
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
          _lastAcceptedPresentationRevision = targetPresentationRevision;
          _lastAcceptedFrameGeneration = frameGeneration;
          if (identical(_fullRedrawMarker, targetFullRedrawMarker)) {
            _fullRedrawMarker = null;
          }
          _acceptedCount++;
          if (_newestModelRevision != targetRevision ||
              presentationClock.revision != targetPresentationRevision ||
              !isPresentationActive) {
            _pending = true;
          }
          return TerminalFrameAttemptResult(
            disposition: TerminalFrameAttemptDisposition.accepted,
            modelRevision: targetRevision,
            presentationRevision: targetPresentationRevision,
            frameGeneration: frameGeneration,
            submissionToken: outcome.submissionToken,
            requiresFullRedraw: presentation.requiresFullRedraw,
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
            presentationRevision: targetPresentationRevision,
            frameGeneration: frameGeneration,
            submissionToken: 0,
            requiresFullRedraw: presentation.requiresFullRedraw,
          );
        case TerminalFrameSubmissionDisposition.backpressured:
          _pending = true;
          _backpressureCount++;
          return TerminalFrameAttemptResult(
            disposition: TerminalFrameAttemptDisposition.backpressured,
            modelRevision: targetRevision,
            presentationRevision: targetPresentationRevision,
            frameGeneration: frameGeneration,
            submissionToken: 0,
            requiresFullRedraw: presentation.requiresFullRedraw,
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

const int _maximumSignedGeneration = 0x7fffffffffffffff;

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
