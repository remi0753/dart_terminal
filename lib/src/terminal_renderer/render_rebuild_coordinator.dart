import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import '../terminal_core/terminal_screen.dart';
import 'terminal_damage_transfer.dart';

abstract final class TerminalRenderRebuildReasonBits {
  static const int resize = 1 << 0;
  static const int scale = 1 << 1;
  static const int font = 1 << 2;
  static const int knownMask = resize | scale | font;
}

final class TerminalRenderRebuildReasons {
  const TerminalRenderRebuildReasons._(this.bits);

  static const TerminalRenderRebuildReasons none =
      TerminalRenderRebuildReasons._(0);

  final int bits;

  bool get hasResize => bits & TerminalRenderRebuildReasonBits.resize != 0;
  bool get hasScale => bits & TerminalRenderRebuildReasonBits.scale != 0;
  bool get hasFont => bits & TerminalRenderRebuildReasonBits.font != 0;
  bool get isEmpty => bits == 0;

  @override
  bool operator ==(Object other) =>
      other is TerminalRenderRebuildReasons && bits == other.bits;

  @override
  int get hashCode => bits;
}

/// The newest terminal/render configuration that must be published atomically.
final class TerminalRenderRebuildTarget {
  TerminalRenderRebuildTarget({
    required this.screen,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scale16_16,
    required this.fontConfigurationGeneration,
  }) {
    RangeError.checkValueInInterval(
      viewportWidth,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'viewportWidth',
    );
    RangeError.checkValueInInterval(
      viewportHeight,
      1,
      TerminalMetalFrameEncoder.maximumDimension,
      'viewportHeight',
    );
    RangeError.checkValueInInterval(scale16_16, 1 << 15, 4 << 16, 'scale16_16');
    _requirePositiveGeneration(
      fontConfigurationGeneration,
      'fontConfigurationGeneration',
    );
  }

  final TerminalScreen screen;
  final int viewportWidth;
  final int viewportHeight;
  final int scale16_16;
  final int fontConfigurationGeneration;

  int get rows => screen.rows;
  int get columns => screen.columns;
  double get scale => scale16_16 / 65536.0;

  bool _sameAs(TerminalRenderRebuildTarget other) =>
      identical(screen, other.screen) &&
      viewportWidth == other.viewportWidth &&
      viewportHeight == other.viewportHeight &&
      scale16_16 == other.scale16_16 &&
      fontConfigurationGeneration == other.fontConfigurationGeneration;
}

final class TerminalRenderResourceGenerations {
  TerminalRenderResourceGenerations({
    required this.catalogGeneration,
    required this.atlasGeneration,
  }) {
    _requirePositiveGeneration(catalogGeneration, 'catalogGeneration');
    _requirePositiveGeneration(atlasGeneration, 'atlasGeneration');
  }

  final int catalogGeneration;
  final int atlasGeneration;
}

final class TerminalRenderRebuildPlan {
  const TerminalRenderRebuildPlan._({
    required this.requestGeneration,
    required this.target,
    required this.reasons,
  });

  final int requestGeneration;
  final TerminalRenderRebuildTarget target;
  final TerminalRenderRebuildReasons reasons;
}

enum TerminalRenderRebuildCompletionDisposition { published, superseded }

final class TerminalRenderRebuildCompletion {
  const TerminalRenderRebuildCompletion({
    required this.disposition,
    required this.requestGeneration,
  });

  final TerminalRenderRebuildCompletionDisposition disposition;
  final int requestGeneration;

  bool get isPublished =>
      disposition == TerminalRenderRebuildCompletionDisposition.published;
}

/// Coalesces rebuild events and publishes only a fully prepared newest target.
///
/// Resource work happens between [beginNewest] and [complete]. A newer request
/// supersedes that work without publishing it. Failure retains the accumulated
/// reason set and one newest target for retry.
final class TerminalRenderRebuildCoordinator {
  TerminalRenderRebuildCoordinator({
    required this.damageOutbox,
    required TerminalRenderRebuildTarget initialTarget,
    required TerminalRenderResourceGenerations initialResources,
    int initialRequestGeneration = 0,
  }) : _requestedTarget = initialTarget,
       _publishedTarget = initialTarget,
       _publishedResources = initialResources,
       _nextRequestGeneration = initialRequestGeneration + 1 {
    if (!damageOutbox.isBoundToScreen(initialTarget.screen)) {
      throw ArgumentError('initial target is not owned by the damage outbox');
    }
    RangeError.checkValueInInterval(
      initialRequestGeneration,
      0,
      0x7ffffffffffffffe,
      'initialRequestGeneration',
    );
  }

  final TerminalDamageOutbox damageOutbox;
  TerminalRenderRebuildTarget _requestedTarget;
  TerminalRenderRebuildTarget _publishedTarget;
  TerminalRenderResourceGenerations _publishedResources;
  TerminalRenderRebuildReasons _reasons = TerminalRenderRebuildReasons.none;
  TerminalRenderRebuildPlan? _activePlan;
  int _nextRequestGeneration;
  int _requestGeneration = 0;
  bool _requestGenerationExhausted = false;
  bool _pending = false;
  int _requestCount = 0;
  int _publishedCount = 0;
  int _supersededCount = 0;
  int _failureCount = 0;

  TerminalRenderRebuildTarget get requestedTarget => _requestedTarget;
  TerminalRenderRebuildTarget get publishedTarget => _publishedTarget;
  TerminalRenderResourceGenerations get publishedResources =>
      _publishedResources;
  TerminalRenderRebuildReasons get pendingReasons => _reasons;
  int get requestGeneration => _requestGeneration;
  bool get hasPendingRebuild => _pending;
  bool get isRebuilding => _activePlan != null;
  int get pendingPlanCount => _pending ? 1 : 0;
  int get requestCount => _requestCount;
  int get publishedCount => _publishedCount;
  int get supersededCount => _supersededCount;
  int get failureCount => _failureCount;

  /// Retains one newest target and accumulates the categories that must reset.
  bool request(TerminalRenderRebuildTarget target) {
    final int reasonBits = _differenceBits(_requestedTarget, target);
    if (reasonBits == 0) return false;
    if (_requestGenerationExhausted) {
      throw StateError('render rebuild generation capacity exhausted');
    }
    damageOutbox.pauseForFullRebuild();
    _requestGeneration = _allocateRequestGeneration();
    _requestedTarget = target;
    _reasons = TerminalRenderRebuildReasons._(_reasons.bits | reasonBits);
    _pending = true;
    _requestCount++;
    return true;
  }

  TerminalRenderRebuildPlan? beginNewest() {
    if (_activePlan != null) {
      throw StateError('render rebuild is already active');
    }
    if (!_pending) return null;
    final TerminalRenderRebuildPlan plan = TerminalRenderRebuildPlan._(
      requestGeneration: _requestGeneration,
      target: _requestedTarget,
      reasons: _reasons,
    );
    _activePlan = plan;
    _pending = false;
    return plan;
  }

  TerminalRenderRebuildCompletion complete(
    TerminalRenderRebuildPlan plan, {
    required TerminalRenderResourceGenerations resources,
  }) {
    _requireActive(plan);
    if (plan.requestGeneration != _requestGeneration) {
      _activePlan = null;
      _pending = true;
      _supersededCount++;
      return TerminalRenderRebuildCompletion(
        disposition: TerminalRenderRebuildCompletionDisposition.superseded,
        requestGeneration: plan.requestGeneration,
      );
    }
    _validateResourceTransition(plan.reasons, resources);
    try {
      damageOutbox.rebindScreenForFullRebuild(plan.target.screen);
    } on Object {
      _pending = true;
      rethrow;
    }
    _publishedTarget = plan.target;
    _publishedResources = resources;
    _activePlan = null;
    _pending = false;
    _reasons = TerminalRenderRebuildReasons.none;
    _publishedCount++;
    return TerminalRenderRebuildCompletion(
      disposition: TerminalRenderRebuildCompletionDisposition.published,
      requestGeneration: plan.requestGeneration,
    );
  }

  void fail(TerminalRenderRebuildPlan plan) {
    _requireActive(plan);
    _activePlan = null;
    _pending = true;
    _failureCount++;
  }

  int _allocateRequestGeneration() {
    final int generation = _nextRequestGeneration;
    if (generation == 0x7fffffffffffffff) {
      _requestGenerationExhausted = true;
    } else {
      _nextRequestGeneration++;
    }
    return generation;
  }

  void _validateResourceTransition(
    TerminalRenderRebuildReasons reasons,
    TerminalRenderResourceGenerations resources,
  ) {
    final TerminalRenderResourceGenerations previous = _publishedResources;
    if (resources.catalogGeneration < previous.catalogGeneration ||
        resources.atlasGeneration < previous.atlasGeneration) {
      throw StateError('render resource generation regressed');
    }
    if (reasons.hasFont &&
        resources.catalogGeneration <= previous.catalogGeneration) {
      throw StateError('font rebuild did not advance catalog generation');
    }
    if ((reasons.hasScale || reasons.hasFont) &&
        resources.atlasGeneration <= previous.atlasGeneration) {
      throw StateError('scale/font rebuild did not advance atlas generation');
    }
  }

  void _requireActive(TerminalRenderRebuildPlan plan) {
    if (!identical(_activePlan, plan)) {
      throw StateError('render rebuild plan is stale or not active');
    }
  }
}

int _differenceBits(
  TerminalRenderRebuildTarget before,
  TerminalRenderRebuildTarget after,
) {
  if (before._sameAs(after)) return 0;
  var bits = 0;
  if (!identical(before.screen, after.screen) ||
      before.rows != after.rows ||
      before.columns != after.columns ||
      before.viewportWidth != after.viewportWidth ||
      before.viewportHeight != after.viewportHeight) {
    bits |= TerminalRenderRebuildReasonBits.resize;
  }
  if (before.scale16_16 != after.scale16_16) {
    bits |= TerminalRenderRebuildReasonBits.scale;
  }
  if (before.fontConfigurationGeneration != after.fontConfigurationGeneration) {
    bits |= TerminalRenderRebuildReasonBits.font;
  }
  return bits;
}

void _requirePositiveGeneration(int value, String name) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    throw RangeError.range(value, 1, 0x7fffffffffffffff, name);
  }
}
