import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalAccessibilityPresentationTests();

Future<void> runTerminalAccessibilityPresentationTests() async {
  const AppKitAccessibilityDisplayPreferences initial =
      AppKitAccessibilityDisplayPreferences(
        reduceMotion: true,
        increaseContrast: false,
        differentiateWithoutColor: false,
      );
  final StreamController<ApplicationAccessibilityDisplayPreferencesChangedEvent>
  events =
      StreamController<
        ApplicationAccessibilityDisplayPreferencesChangedEvent
      >.broadcast(sync: true);
  final List<TerminalAccessibilityPresentation> changes =
      <TerminalAccessibilityPresentation>[];
  final List<Object> errors = <Object>[];
  final TerminalApplicationAccessibilityProjection projection =
      TerminalApplicationAccessibilityProjection(
        initialPreferences: initial,
        events: events.stream,
        onChanged: changes.add,
        onError: (Object error, StackTrace _) => errors.add(error),
      );
  try {
    _expect(
      projection.presentation ==
          const TerminalAccessibilityPresentation(
            reduceMotion: true,
            increaseContrast: false,
            differentiateWithoutColor: false,
          ),
      'the product projection copies the generic initial snapshot',
    );
    events.add(
      const ApplicationAccessibilityDisplayPreferencesChangedEvent(
        monotonicMicros: 1,
        preferences: initial,
      ),
    );
    _expect(changes.isEmpty, 'equal snapshots are deduplicated');

    const AppKitAccessibilityDisplayPreferences changed =
        AppKitAccessibilityDisplayPreferences(
          reduceMotion: false,
          increaseContrast: true,
          differentiateWithoutColor: true,
        );
    events.add(
      const ApplicationAccessibilityDisplayPreferencesChangedEvent(
        monotonicMicros: 2,
        preferences: changed,
      ),
    );
    _expect(
      changes.length == 1 &&
          identical(changes.single, projection.presentation) &&
          projection.presentation.increaseContrast &&
          projection.presentation.differentiateWithoutColor &&
          !projection.presentation.reduceMotion &&
          errors.isEmpty,
      'one distinct generic snapshot updates and publishes product policy',
    );

    await projection.dispose();
    await projection.dispose();
    events.add(
      const ApplicationAccessibilityDisplayPreferencesChangedEvent(
        monotonicMicros: 3,
        preferences: initial,
      ),
    );
    _expect(
      projection.isDisposed && changes.length == 1,
      'disposal is idempotent and prevents stale delivery',
    );
  } finally {
    await projection.dispose();
    await events.close();
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
