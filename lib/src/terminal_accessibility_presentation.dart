import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

/// Product-owned projection of the macOS accessibility display preferences.
///
/// This value changes only presentation. It never mutates stored terminal
/// configuration, terminal data, or protocol state.
final class TerminalAccessibilityPresentation {
  const TerminalAccessibilityPresentation({
    required this.reduceMotion,
    required this.increaseContrast,
    required this.differentiateWithoutColor,
  });

  const TerminalAccessibilityPresentation.standard()
    : reduceMotion = false,
      increaseContrast = false,
      differentiateWithoutColor = false;

  factory TerminalAccessibilityPresentation.fromAppKit(
    AppKitAccessibilityDisplayPreferences? preferences,
  ) => preferences == null
      ? const TerminalAccessibilityPresentation.standard()
      : TerminalAccessibilityPresentation(
          reduceMotion: preferences.reduceMotion,
          increaseContrast: preferences.increaseContrast,
          differentiateWithoutColor: preferences.differentiateWithoutColor,
        );

  final bool reduceMotion;
  final bool increaseContrast;
  final bool differentiateWithoutColor;

  @override
  bool operator ==(Object other) =>
      other is TerminalAccessibilityPresentation &&
      other.reduceMotion == reduceMotion &&
      other.increaseContrast == increaseContrast &&
      other.differentiateWithoutColor == differentiateWithoutColor;

  @override
  int get hashCode =>
      Object.hash(reduceMotion, increaseContrast, differentiateWithoutColor);
}

typedef TerminalAccessibilityPresentationObserver = void Function(
  TerminalAccessibilityPresentation presentation,
);
typedef TerminalAccessibilityPresentationErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Retains and publishes one deduplicated application accessibility policy.
///
/// The generic AppKit snapshot and stream are injected so this controller owns
/// only product projection and remains independently testable.
final class TerminalApplicationAccessibilityProjection {
  TerminalApplicationAccessibilityProjection({
    required AppKitAccessibilityDisplayPreferences? initialPreferences,
    required Stream<ApplicationAccessibilityDisplayPreferencesChangedEvent>
    events,
    required TerminalAccessibilityPresentationObserver onChanged,
    required TerminalAccessibilityPresentationErrorHandler onError,
  }) : _presentation = TerminalAccessibilityPresentation.fromAppKit(
         initialPreferences,
       ),
       _onChanged = onChanged,
       _onError = onError {
    _subscription = events.listen(_handleEvent, onError: onError);
  }

  final TerminalAccessibilityPresentationObserver _onChanged;
  final TerminalAccessibilityPresentationErrorHandler _onError;
  late final StreamSubscription<
    ApplicationAccessibilityDisplayPreferencesChangedEvent
  >
  _subscription;

  TerminalAccessibilityPresentation _presentation;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  TerminalAccessibilityPresentation get presentation => _presentation;
  bool get isDisposed => _disposed;

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await _subscription.cancel();
  }

  void _handleEvent(
    ApplicationAccessibilityDisplayPreferencesChangedEvent event,
  ) {
    if (_disposed) return;
    final TerminalAccessibilityPresentation next =
        TerminalAccessibilityPresentation.fromAppKit(event.preferences);
    if (next == _presentation) return;
    _presentation = next;
    try {
      _onChanged(next);
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }
}
