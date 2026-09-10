import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_core/terminal_screen.dart';
import 'terminal_product_configuration.dart';

typedef TerminalApplicationThemeErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Owns the application appearance subscription and each pane's captured
/// theme policy without replacing pane resources.
final class TerminalApplicationThemeProjection<Key extends Object> {
  TerminalApplicationThemeProjection({
    required AppKitApplication application,
    required TerminalApplicationThemeErrorHandler onError,
  }) : _systemAppearance = _brightness(application.effectiveAppearance),
       _onError = onError {
    _subscription = application.onAppearanceChanged.listen(
      _handleAppearanceChanged,
      onError: onError,
    );
  }

  final TerminalApplicationThemeErrorHandler _onError;
  final Map<Key, _TerminalApplicationThemeTarget> _targets =
      <Key, _TerminalApplicationThemeTarget>{};
  late final StreamSubscription<ApplicationAppearanceChangedEvent>
  _subscription;

  TerminalThemeBrightness _systemAppearance;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  TerminalThemeBrightness get systemAppearance => _systemAppearance;
  int get registeredPaneCount => _targets.length;
  bool get isDisposed => _disposed;

  /// Creates a pane-owned palette from the current appearance and retains the
  /// immutable creation-time configuration for later system changes.
  TerminalPalette createPaletteForPane({
    required Key key,
    required TerminalProductConfiguration configuration,
    required void Function() onChanged,
  }) {
    _ensureRunning();
    if (_targets.containsKey(key)) {
      throw StateError('theme projection already contains pane $key');
    }
    final TerminalPalette palette = configuration.createPalette(
      systemAppearance: _systemAppearance,
    );
    _targets[key] = _TerminalApplicationThemeTarget(
      configuration: configuration,
      palette: palette,
      onChanged: onChanged,
    );
    return palette;
  }

  bool removePane(Key key) => _targets.remove(key) != null;

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _targets.clear();
    await _subscription.cancel();
  }

  void _handleAppearanceChanged(ApplicationAppearanceChangedEvent event) {
    if (_disposed) return;
    _systemAppearance = _brightness(event.appearance);
    for (final MapEntry<Key, _TerminalApplicationThemeTarget> entry
        in _targets.entries.toList(growable: false)) {
      if (_disposed) break;
      if (!identical(_targets[entry.key], entry.value)) continue;
      try {
        if (entry.value.configuration.applySystemAppearanceToPalette(
          entry.value.palette,
          _systemAppearance,
        )) {
          entry.value.onChanged();
        }
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }
  }

  void _ensureRunning() {
    if (_disposed) {
      throw StateError('application theme projection is disposed');
    }
  }

  static TerminalThemeBrightness _brightness(AppKitAppearance? appearance) =>
      switch (appearance) {
        AppKitAppearance.light => TerminalThemeBrightness.light,
        AppKitAppearance.dark || null => TerminalThemeBrightness.dark,
      };
}

final class _TerminalApplicationThemeTarget {
  const _TerminalApplicationThemeTarget({
    required this.configuration,
    required this.palette,
    required this.onChanged,
  });

  final TerminalProductConfiguration configuration;
  final TerminalPalette palette;
  final void Function() onChanged;
}
