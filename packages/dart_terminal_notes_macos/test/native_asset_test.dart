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
  try {
    TerminalNotesNativeSurface(bindings: bindings);
    stderr.writeln('standalone Dart unexpectedly created an AppKit surface');
    exitCode = 1;
    return;
  } on StateError {
    // `dart run` does not execute on AppKit's process main thread. The direct
    // code-asset gate proves loading without weakening native thread affinity;
    // the native executable owns presentation lifecycle acceptance.
  }
  if (bindings.liveSurfaceCount != 0) {
    stderr.writeln('native Note surface ownership leaked');
    exitCode = 1;
    return;
  }
  stdout.writeln('terminal Notes native asset hook passed');
}
