import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_session.dart';

const String terminalUsage = '''
Usage: Dart Terminal [application-options]

Application options:
  --working-directory=PATH   Initial command working directory.
  --auto-close-after=SECONDS Close automatically (for smoke testing).
''';

final class TerminalOptions {
  const TerminalOptions({this.initialWorkingDirectory, this.autoCloseAfter});

  factory TerminalOptions.parse(List<String> arguments) {
    String? initialWorkingDirectory;
    Duration? autoCloseAfter;
    for (final String argument in arguments) {
      const String workingDirectoryPrefix = '--working-directory=';
      const String autoClosePrefix = '--auto-close-after=';
      if (argument.startsWith(workingDirectoryPrefix)) {
        if (initialWorkingDirectory != null) {
          throw const FormatException(
            '--working-directory may only be supplied once',
          );
        }
        final String value = argument.substring(workingDirectoryPrefix.length);
        if (value.isEmpty) {
          throw const FormatException('--working-directory requires a path');
        }
        initialWorkingDirectory = value;
        continue;
      }
      if (argument.startsWith(autoClosePrefix)) {
        if (autoCloseAfter != null) {
          throw const FormatException(
            '--auto-close-after may only be supplied once',
          );
        }
        final int? seconds = int.tryParse(
          argument.substring(autoClosePrefix.length),
        );
        if (seconds == null || seconds <= 0) {
          throw FormatException(
            '--auto-close-after must be a positive number: $argument',
          );
        }
        autoCloseAfter = Duration(seconds: seconds);
        continue;
      }
      throw FormatException('unknown application option: $argument');
    }
    return TerminalOptions(
      initialWorkingDirectory: initialWorkingDirectory,
      autoCloseAfter: autoCloseAfter,
    );
  }

  final String? initialWorkingDirectory;
  final Duration? autoCloseAfter;
}

final class TerminalApplication {
  const TerminalApplication({this.options = const TerminalOptions()});

  final TerminalOptions options;

  Future<void> run() async {
    final AppKitApplication application = await AppKitApplication.attach();
    TextView? textView;
    Window? window;
    TerminalSession? session;
    StreamSubscription<WindowEvent>? eventSubscription;
    Timer? autoCloseTimer;
    final Completer<void> closed = Completer<void>();

    try {
      final TextView createdTextView = TextView();
      textView = createdTextView;
      final Window createdWindow = Window(
        frame: const Rect.fromLTWH(100, 90, 920, 580),
        title: 'Dart Terminal',
      )..contentView = createdTextView;
      window = createdWindow;

      late final TerminalSession createdSession;
      createdSession = TerminalSession(
        initialWorkingDirectory: options.initialWorkingDirectory,
        onChanged: () {
          if (!createdTextView.isDisposed) {
            createdTextView.text = createdSession.render();
          }
        },
        onExitRequested: createdWindow.close,
      );
      session = createdSession;
      createdTextView.text = createdSession.render();

      eventSubscription = createdWindow.events.listen(
        (WindowEvent event) {
          switch (event) {
            case WindowClosedEvent():
              if (!closed.isCompleted) {
                closed.complete();
              }
            case WindowResizedEvent(:final height):
              createdSession.viewportRows = _rowsForHeight(height);
              createdSession.refresh();
            case AppKitKeyEvent() when event.kind == AppKitKeyEventKind.down:
              _handleKeyDown(event, createdSession);
            case AppKitKeyEvent():
            case AppKitMouseEvent():
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!closed.isCompleted) {
            closed.completeError(error, stackTrace);
          }
        },
      );

      createdWindow.show();
      stdout.writeln('Dart Terminal is attached to the AppKit main thread.');
      final Duration? autoCloseAfter = options.autoCloseAfter;
      if (autoCloseAfter != null) {
        stdout.writeln(
          'Automated close scheduled after '
          '${autoCloseAfter.inSeconds} seconds.',
        );
        autoCloseTimer = Timer(autoCloseAfter, () {
          if (!createdWindow.isClosed && !createdWindow.isDisposed) {
            createdWindow.close();
          }
        });
      }
      await closed.future;
    } finally {
      autoCloseTimer?.cancel();
      await eventSubscription?.cancel();
      await session?.dispose();
      if (window != null && !window.isDisposed) {
        window.dispose();
      }
      if (textView != null && !textView.isDisposed) {
        textView.dispose();
      }
      await application.terminate();
    }
    stdout.writeln('Dart Terminal shut down cleanly.');
  }

  static int _rowsForHeight(double height) {
    final int rows = ((height - 40) / 22).floor();
    if (rows < 4) {
      return 4;
    }
    if (rows > 200) {
      return 200;
    }
    return rows;
  }

  static void _handleKeyDown(AppKitKeyEvent event, TerminalSession session) {
    if (event.modifiers.control && event.keyCode == 8) {
      session.interrupt();
      return;
    }
    if (event.modifiers.control && event.keyCode == 2) {
      session.requestExitIfIdle();
      return;
    }
    if (session.isBusy || event.modifiers.command) {
      return;
    }

    switch (event.keyCode) {
      case 36:
      case 76:
        unawaited(session.submit());
        return;
      case 51:
        session.deleteBackward();
        return;
      case 117:
        session.deleteForward();
        return;
      case 123:
        session.moveLeft();
        return;
      case 124:
        session.moveRight();
        return;
      case 125:
        session.nextHistory();
        return;
      case 126:
        session.previousHistory();
        return;
      case 115:
        session.moveToStart();
        return;
      case 119:
        session.moveToEnd();
        return;
    }

    if (event.modifiers.control || event.modifiers.function) {
      return;
    }
    final Iterable<int> printableRunes = event.characters.runes.where(
      (int rune) =>
          rune >= 0x20 && rune != 0x7f && (rune < 0xf700 || rune > 0xf8ff),
    );
    session.insertText(String.fromCharCodes(printableRunes));
  }
}
