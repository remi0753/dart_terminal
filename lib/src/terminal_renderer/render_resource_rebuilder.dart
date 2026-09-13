import 'dart:convert';

import 'package:dart_terminal_renderer_macos/dart_terminal_renderer_macos.dart';

import 'glyph_atlas.dart';
import 'metal_atlas_bridge.dart';
import 'render_rebuild_coordinator.dart';
import 'terminal_damage_transfer.dart';

final class TerminalRenderFontConfiguration {
  TerminalRenderFontConfiguration({
    required this.generation,
    this.family = 'Menlo',
    this.pointSize = 14,
    this.syntheticStylePolicy = TerminalSyntheticStylePolicy.allow,
    TerminalFontCatalogConfiguration? catalogConfiguration,
  }) : catalogConfiguration =
           catalogConfiguration ?? TerminalFontCatalogConfiguration.empty {
    if (generation <= 0 || generation > 0x7fffffffffffffff) {
      throw RangeError.range(generation, 1, 0x7fffffffffffffff, 'generation');
    }
    if (!pointSize.isFinite || pointSize < 4 || pointSize > 128) {
      throw RangeError.range(pointSize, 4, 128, 'pointSize');
    }
    final List<int> familyBytes = utf8.encode(family);
    if (familyBytes.length > TerminalFontCatalog.maximumFamilyBytes ||
        familyBytes.contains(0)) {
      throw ArgumentError.value(
        family,
        'family',
        'must be NUL-free UTF-8 within '
            '${TerminalFontCatalog.maximumFamilyBytes} bytes',
      );
    }
  }

  final int generation;
  final String family;
  final double pointSize;
  final TerminalSyntheticStylePolicy syntheticStylePolicy;
  final TerminalFontCatalogConfiguration catalogConfiguration;

  bool matchesCatalog(TerminalFontCatalog catalog) =>
      !catalog.isDisposed &&
      catalog.family == family &&
      catalog.metrics.pointSize == pointSize &&
      catalog.syntheticStylePolicy == syntheticStylePolicy &&
      catalog.configuration == catalogConfiguration;

  bool _sameAs(TerminalRenderFontConfiguration other) =>
      generation == other.generation &&
      family == other.family &&
      pointSize == other.pointSize &&
      syntheticStylePolicy == other.syntheticStylePolicy &&
      catalogConfiguration == other.catalogConfiguration;
}

typedef TerminalRenderAtlasWarmup = void Function(
  TerminalFontCatalog catalog,
  TerminalShapingCache shapingCache,
  TerminalGlyphAtlas atlas,
);

enum TerminalRenderResourceRebuildDisposition {
  idle,
  published,
  superseded,
  backpressured,
}

final class TerminalRenderResourceRebuildResult {
  const TerminalRenderResourceRebuildResult({
    required this.disposition,
    required this.requestGeneration,
  });

  final TerminalRenderResourceRebuildDisposition disposition;
  final int requestGeneration;

  bool get isPublished =>
      disposition == TerminalRenderResourceRebuildDisposition.published;
}

/// Applies rebuild plans on one synchronous font/render owner domain.
///
/// The object owns [catalog] and [shapingCache]. The renderer, bridge, atlas,
/// coordinator, and damage outbox remain owned by their surrounding pane or
/// window domain. Callers must not invoke this object from an AppKit callback.
final class TerminalRenderResourceRebuilder {
  TerminalRenderResourceRebuilder({
    required this.coordinator,
    required this.bridge,
    required TerminalFontCatalog catalog,
    required TerminalShapingCache shapingCache,
    required TerminalRenderFontConfiguration fontConfiguration,
  }) : _catalog = catalog,
       _shapingCache = shapingCache,
       _fontConfiguration = fontConfiguration {
    final TerminalRenderRebuildTarget target = coordinator.publishedTarget;
    final TerminalRenderResourceGenerations resources =
        coordinator.publishedResources;
    if (coordinator.hasPendingRebuild ||
        coordinator.isRebuilding ||
        coordinator.damageOutbox.isPausedForFullRebuild) {
      throw ArgumentError('initial rebuild state is not published and idle');
    }
    if (!coordinator.damageOutbox.isBoundToScreen(target.screen)) {
      throw ArgumentError('published target is outside the damage outbox');
    }
    if (!identical(shapingCache.catalog, catalog) || shapingCache.isDisposed) {
      throw ArgumentError('shaping cache does not own the initial catalog');
    }
    if (!fontConfiguration.matchesCatalog(catalog) ||
        target.fontConfigurationGeneration != fontConfiguration.generation) {
      throw ArgumentError('font configuration does not match the catalog');
    }
    if (atlas.catalogGeneration != catalog.generation ||
        atlas.scale16_16 != target.scale16_16 ||
        resources.catalogGeneration != catalog.generation ||
        resources.atlasGeneration != atlas.resourceGeneration) {
      throw ArgumentError('published resources do not match the target');
    }
    _validateViewport(target);
    if (!bridge.isSynchronized) {
      throw ArgumentError('initial native atlas is not synchronized');
    }
  }

  final TerminalRenderRebuildCoordinator coordinator;
  final TerminalGlyphAtlasMetalBridge bridge;
  TerminalFontCatalog _catalog;
  TerminalShapingCache _shapingCache;
  TerminalRenderFontConfiguration _fontConfiguration;
  TerminalRenderRebuildPlan? _activePlan;
  TerminalRenderFontConfiguration? _activeFontConfiguration;
  TerminalFontCatalog? _replacementCatalog;
  TerminalShapingCache? _replacementShapingCache;
  bool _prepared = false;
  bool _disposed = false;

  TerminalGlyphAtlas get atlas => bridge.atlas;
  TerminalMetalRenderer get renderer => bridge.renderer;
  TerminalFontCatalog get catalog => _catalog;
  TerminalShapingCache get shapingCache => _shapingCache;
  TerminalRenderFontConfiguration get fontConfiguration => _fontConfiguration;
  bool get isDisposed => _disposed;
  bool get hasActiveWork => _activePlan != null;

  bool request(TerminalRenderRebuildTarget target) {
    _requireLive();
    return coordinator.request(target);
  }

  /// Captures damage against exactly the currently published atlas.
  TerminalDamageTransferEnvelope? tryCreateDamageTransfer() {
    _requireLive();
    return coordinator.damageOutbox.tryCreateTransfer(
      requiredResourceGeneration:
          coordinator.publishedResources.atlasGeneration,
    );
  }

  /// Advances at most one synchronous resource preparation attempt.
  ///
  /// Native backpressure retains the prepared newest plan for a later call.
  /// A request received between calls supersedes and discards staged font
  /// resources before any target or damage publication occurs.
  TerminalRenderResourceRebuildResult processNewest({
    required TerminalRenderFontConfiguration fontConfiguration,
    TerminalRenderAtlasWarmup? warmup,
  }) {
    _requireLive();
    TerminalRenderRebuildPlan? plan = _activePlan;
    if (plan != null &&
        plan.requestGeneration != coordinator.requestGeneration) {
      final TerminalRenderRebuildCompletion completion = coordinator.complete(
        plan,
        resources: coordinator.publishedResources,
      );
      if (completion.disposition !=
          TerminalRenderRebuildCompletionDisposition.superseded) {
        throw StateError('stale resource plan was unexpectedly published');
      }
      _discardReplacement();
      _clearActive();
      return TerminalRenderResourceRebuildResult(
        disposition: TerminalRenderResourceRebuildDisposition.superseded,
        requestGeneration: plan.requestGeneration,
      );
    }

    if (plan == null) {
      plan = coordinator.beginNewest();
      if (plan == null) {
        return const TerminalRenderResourceRebuildResult(
          disposition: TerminalRenderResourceRebuildDisposition.idle,
          requestGeneration: 0,
        );
      }
      _activePlan = plan;
      _activeFontConfiguration = fontConfiguration;
    }

    try {
      _validatePlanConfiguration(plan, fontConfiguration);
      _validateViewport(plan.target);
      bridge.retireCompletedSubmissions();
      if (atlas.livePinCount != 0) {
        return TerminalRenderResourceRebuildResult(
          disposition: TerminalRenderResourceRebuildDisposition.backpressured,
          requestGeneration: plan.requestGeneration,
        );
      }

      if (!_prepared) {
        if (plan.reasons.hasFont) {
          final TerminalFontCatalog replacement = _openFontCatalog(
            fontConfiguration,
          );
          if (replacement.generation <= _catalog.generation ||
              !fontConfiguration.matchesCatalog(replacement)) {
            replacement.dispose();
            throw StateError('replacement catalog does not match its config');
          }
          _replacementCatalog = replacement;
          _replacementShapingCache = TerminalShapingCache(
            replacement,
            maximumEntries: _shapingCache.maximumEntries,
            maximumBytes: _shapingCache.maximumBytes,
          );
        }
        if (plan.reasons.hasScale || plan.reasons.hasFont) {
          final TerminalFontCatalog selected = _replacementCatalog ?? _catalog;
          atlas.reset(
            catalogGeneration: selected.generation,
            scale: plan.target.scale,
          );
          warmup?.call(
            selected,
            _replacementShapingCache ?? _shapingCache,
            atlas,
          );
        }
        _prepared = true;
      }

      final TerminalGlyphAtlasSyncDisposition sync = bridge.synchronize();
      if (sync == TerminalGlyphAtlasSyncDisposition.backpressured) {
        return TerminalRenderResourceRebuildResult(
          disposition: TerminalRenderResourceRebuildDisposition.backpressured,
          requestGeneration: plan.requestGeneration,
        );
      }
      final TerminalFontCatalog selectedCatalog =
          _replacementCatalog ?? _catalog;
      final TerminalRenderResourceGenerations resources =
          TerminalRenderResourceGenerations(
            catalogGeneration: selectedCatalog.generation,
            atlasGeneration: atlas.resourceGeneration,
          );
      final TerminalRenderRebuildCompletion completion = coordinator.complete(
        plan,
        resources: resources,
      );
      if (!completion.isPublished) {
        throw StateError('newest synchronous resource plan was superseded');
      }
      if (_replacementCatalog case final TerminalFontCatalog replacement) {
        final TerminalFontCatalog previousCatalog = _catalog;
        final TerminalShapingCache previousCache = _shapingCache;
        _catalog = replacement;
        _shapingCache = _replacementShapingCache!;
        _replacementCatalog = null;
        _replacementShapingCache = null;
        _fontConfiguration = fontConfiguration;
        previousCache.dispose();
        previousCatalog.dispose();
      } else {
        _fontConfiguration = fontConfiguration;
      }
      _clearActive();
      return TerminalRenderResourceRebuildResult(
        disposition: TerminalRenderResourceRebuildDisposition.published,
        requestGeneration: completion.requestGeneration,
      );
    } on Object {
      if (identical(_activePlan, plan) && coordinator.isRebuilding) {
        coordinator.fail(plan);
      }
      _discardReplacement();
      _clearActive();
      rethrow;
    }
  }

  /// Encodes only the completely published target/resource generation.
  TerminalMetalFrame encodeFrame({
    required int frameGeneration,
    required int backgroundRgba,
    required Iterable<TerminalMetalInstance> instances,
  }) {
    _requireLive();
    if (coordinator.hasPendingRebuild ||
        coordinator.isRebuilding ||
        coordinator.damageOutbox.isPausedForFullRebuild) {
      throw StateError('cannot encode a frame during a render rebuild');
    }
    final TerminalRenderRebuildTarget target = coordinator.publishedTarget;
    final TerminalRenderResourceGenerations resources =
        coordinator.publishedResources;
    if (!bridge.isSynchronized ||
        resources.catalogGeneration != _catalog.generation ||
        resources.atlasGeneration != atlas.resourceGeneration ||
        atlas.catalogGeneration != _catalog.generation ||
        atlas.scale16_16 != target.scale16_16 ||
        target.fontConfigurationGeneration != _fontConfiguration.generation) {
      throw StateError('published render resource domain is inconsistent');
    }
    _validateViewport(target);
    return TerminalMetalFrameEncoder.encode(
      renderer: renderer,
      frameGeneration: frameGeneration,
      atlasGeneration: resources.atlasGeneration,
      viewportWidth: target.viewportWidth,
      viewportHeight: target.viewportHeight,
      scale16_16: target.scale16_16,
      backgroundRgba: backgroundRgba,
      instances: instances,
    );
  }

  void dispose() {
    if (_disposed) return;
    final TerminalRenderRebuildPlan? plan = _activePlan;
    if (plan != null && coordinator.isRebuilding) {
      coordinator.fail(plan);
    }
    _discardReplacement();
    _shapingCache.dispose();
    _catalog.dispose();
    _clearActive();
    _disposed = true;
  }

  void _validatePlanConfiguration(
    TerminalRenderRebuildPlan plan,
    TerminalRenderFontConfiguration supplied,
  ) {
    final TerminalRenderFontConfiguration active = _activeFontConfiguration!;
    if (!active._sameAs(supplied)) {
      throw ArgumentError('active rebuild font configuration changed');
    }
    if (supplied.generation != plan.target.fontConfigurationGeneration) {
      throw ArgumentError('font configuration generation misses the target');
    }
    if (!plan.reasons.hasFont && !supplied._sameAs(_fontConfiguration)) {
      throw ArgumentError('resize/scale rebuild changed font configuration');
    }
  }

  void _validateViewport(TerminalRenderRebuildTarget target) {
    if (target.viewportWidth > renderer.config.maximumViewportWidth ||
        target.viewportHeight > renderer.config.maximumViewportHeight) {
      throw RangeError('rebuild viewport exceeds the Metal renderer capacity');
    }
  }

  void _discardReplacement() {
    _replacementShapingCache?.dispose();
    _replacementCatalog?.dispose();
    _replacementShapingCache = null;
    _replacementCatalog = null;
  }

  void _clearActive() {
    _activePlan = null;
    _activeFontConfiguration = null;
    _prepared = false;
  }

  void _requireLive() {
    if (_disposed) {
      throw StateError('TerminalRenderResourceRebuilder is disposed');
    }
  }
}

TerminalFontCatalog _openFontCatalog(TerminalRenderFontConfiguration config) =>
    TerminalFontCatalog.open(
      family: config.family,
      pointSize: config.pointSize,
      syntheticStylePolicy: config.syntheticStylePolicy,
      configuration: config.catalogConfiguration,
    );
