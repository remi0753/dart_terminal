import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';

const int _maximumCaptureBytes = 16 * 1024;
const PtySize _captureSize = PtySize(rows: 8, columns: 40);
const Duration _quietPeriod = Duration(milliseconds: 150);
const Duration _stepTimeout = Duration(seconds: 5);

Future<void> main(List<String> arguments) async {
  final String application = _applicationArgument(arguments);
  final Uint8List recording = await captureProductApplicationStream(
    application,
  );
  stdout.writeln(
    'APPLICATION_RECORDING name=$application bytes=${recording.length} '
    'hash=${_hash(recording)}',
  );
  for (var offset = 0; offset < recording.length; offset += 24) {
    stdout.writeln(
      recording
          .skip(offset)
          .take(24)
          .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' '),
    );
  }
}

String _applicationArgument(List<String> arguments) {
  if (arguments.length != 1 || !arguments.single.startsWith('--application=')) {
    throw ArgumentError(
      'usage: dart run tool/capture_product_application_stream.dart '
      '--application=shell|less|top|vim',
    );
  }
  final String application = arguments.single.substring(
    '--application='.length,
  );
  if (!const <String>{'shell', 'less', 'top', 'vim'}.contains(application)) {
    throw ArgumentError.value(application, 'application', 'unsupported');
  }
  return application;
}

Future<Uint8List> captureProductApplicationStream(String application) async {
  final _CaptureRecipe recipe = switch (application) {
    'shell' => _shellRecipe(),
    'less' => _lessRecipe(),
    'top' => _topRecipe(),
    'vim' => _vimRecipe(),
    _ => throw ArgumentError.value(application, 'application', 'unsupported'),
  };
  final PtyProcess process = await startPty(
    recipe.command,
    initialSize: _captureSize,
    readHighWaterBytes: _maximumCaptureBytes,
    readLowWaterBytes: _maximumCaptureBytes ~/ 2,
    writeCapacityBytes: 4096,
  ).timeout(_stepTimeout);
  final List<int> bytes = <int>[];
  Object? outputError;
  final Completer<void> outputDone = Completer<void>();
  final StreamSubscription<Uint8List> outputSubscription = process.output
      .listen(
        (Uint8List chunk) {
          if (bytes.length + chunk.length > _maximumCaptureBytes) {
            outputError = StateError(
              '$application capture exceeds $_maximumCaptureBytes bytes',
            );
            process.forceClose();
            return;
          }
          bytes.addAll(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          outputError = error;
          if (!outputDone.isCompleted) {
            outputDone.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!outputDone.isCompleted) {
            outputDone.complete();
          }
        },
      );

  var exited = false;
  try {
    await recipe.interact(process, bytes);
    final PtyExit exit = await process.exit.timeout(_stepTimeout);
    exited = true;
    if (exit.exitCode != 0 || exit.signal != null) {
      throw StateError(
        '$application exited with code ${exit.exitCode} signal ${exit.signal}',
      );
    }
    await outputDone.future.timeout(_stepTimeout);
    if (outputError case final Object error) {
      throw error;
    }
  } finally {
    if (!exited) {
      process.forceClose();
    }
    await outputSubscription.cancel();
    await process.dispose().timeout(_stepTimeout);
  }

  final Uint8List captured = Uint8List.fromList(bytes);
  if (captured.isEmpty) {
    throw StateError('$application produced no terminal bytes');
  }
  return application == 'top' ? sanitizeTopRecording(captured) : captured;
}

_CaptureRecipe _shellRecipe() => _CaptureRecipe(
  command: PtyCommand(
    executable: '/bin/zsh',
    arguments: const <String>['-f'],
    environment: <String, String>{
      ..._baseEnvironment,
      'PS1': 'corpus% ',
      'PROMPT_EOL_MARK': '',
      'RPROMPT': '',
    },
    includeParentEnvironment: false,
  ),
  interact: (PtyProcess process, List<int> bytes) async {
    await _waitForQuiet(bytes, minimumBytes: 1);
    final int beforeCommand = bytes.length;
    _write(process, 'print -r -- shell-ready\r');
    await _waitForQuiet(bytes, minimumBytes: beforeCommand + 1);
    _write(process, 'exit\r');
  },
);

_CaptureRecipe _lessRecipe() => _CaptureRecipe(
  command: PtyCommand(
    executable: '/bin/zsh',
    arguments: const <String>[
      '-f',
      '-c',
      "printf 'less line 01\\nless line 02\\nless line 03\\n"
          "less line 04\\nless line 05\\nless line 06\\nless line 07\\n"
          "less line 08\\nless line 09\\nless line 10\\n' | "
          '/usr/bin/less -R',
    ],
    environment: <String, String>{
      ..._baseEnvironment,
      'LESS': '-R',
      'LESSCHARSET': 'utf-8',
    },
    includeParentEnvironment: false,
  ),
  interact: (PtyProcess process, List<int> bytes) async {
    await _waitForQuiet(bytes, minimumBytes: 1);
    _write(process, 'q');
  },
);

_CaptureRecipe _topRecipe() => _CaptureRecipe(
  command: PtyCommand(
    executable: '/usr/bin/top',
    arguments: const <String>['-l', '1', '-n', '0'],
    environment: _baseEnvironment,
    includeParentEnvironment: false,
  ),
  interact: (PtyProcess process, List<int> bytes) async {},
);

_CaptureRecipe _vimRecipe() => _CaptureRecipe(
  command: PtyCommand(
    executable: '/usr/bin/vim',
    arguments: const <String>[
      '-Nu',
      'NONE',
      '-U',
      'NONE',
      '-i',
      'NONE',
      '-n',
      '--cmd',
      'set nomore noshowmode noruler laststatus=0',
    ],
    environment: _baseEnvironment,
    includeParentEnvironment: false,
  ),
  interact: (PtyProcess process, List<int> bytes) async {
    await _waitForQuiet(bytes, minimumBytes: 1);
    final int beforeInsert = bytes.length;
    _write(process, 'iVim corpus\rline two\u001b');
    await _waitForQuiet(bytes, minimumBytes: beforeInsert + 1);
    _write(process, ':q!\r');
  },
);

const Map<String, String> _baseEnvironment = <String, String>{
  'LANG': 'C',
  'LC_ALL': 'C',
  'PATH': '/usr/bin:/bin',
  'TERM': 'xterm-256color',
};

final class _CaptureRecipe {
  const _CaptureRecipe({required this.command, required this.interact});

  final PtyCommand command;
  final Future<void> Function(PtyProcess process, List<int> bytes) interact;
}

Future<void> _waitForQuiet(List<int> bytes, {required int minimumBytes}) async {
  final Stopwatch timeout = Stopwatch()..start();
  var previousLength = -1;
  while (timeout.elapsed < _stepTimeout) {
    await Future<void>.delayed(_quietPeriod);
    if (bytes.length >= minimumBytes && bytes.length == previousLength) {
      return;
    }
    previousLength = bytes.length;
  }
  throw TimeoutException(
    'capture did not become quiet after ${_stepTimeout.inSeconds} seconds',
  );
}

void _write(PtyProcess process, String value) {
  final PtyWriteResult result = process.write(
    Uint8List.fromList(utf8.encode(value)),
  );
  if (result != PtyWriteResult.accepted) {
    throw StateError('capture input was backpressured');
  }
}

Uint8List sanitizeTopRecording(Uint8List input) {
  final String decoded;
  try {
    decoded = ascii.decode(input, allowInvalid: false);
  } on FormatException catch (error) {
    throw StateError('top output is not strict ASCII: $error');
  }
  if (RegExp(r'[\x00-\x09\x0b\x0c\x0e-\x1f\x7f]').hasMatch(decoded)) {
    throw StateError('top output contains unexpected control bytes');
  }
  final List<String> lines = decoded.split('\n');
  final List<String> categories = <String>[];
  final StringBuffer sanitized = StringBuffer();
  for (var index = 0; index < lines.length; index++) {
    String line = lines[index];
    final bool hadCarriageReturn = line.endsWith('\r');
    if (hadCarriageReturn) {
      line = line.substring(0, line.length - 1);
    }
    if (line.isEmpty) {
      if (index != lines.length - 1) {
        sanitized.write(hadCarriageReturn ? '\r\n' : '\n');
      }
      continue;
    }
    final String category = _topCategory(line);
    if (categories.contains(category)) {
      throw StateError('top output repeats $category');
    }
    categories.add(category);
    sanitized
      ..write('$category: sanitized')
      ..write(hadCarriageReturn ? '\r\n' : '\n');
  }
  const List<String> required = <String>[
    'Processes',
    'Clock',
    'Load Avg',
    'CPU usage',
    'SharedLibs',
    'MemRegions',
    'PhysMem',
    'VM',
    'Networks',
    'Disks',
  ];
  for (var index = 0; index < required.length; index++) {
    final String category = required[index];
    if (categories.length <= index) {
      throw StateError('top output is missing $category');
    }
    if (categories[index] != category) {
      throw StateError(
        'top output category ${categories[index]} is out of order; '
        'expected $category',
      );
    }
  }
  return Uint8List.fromList(ascii.encode(sanitized.toString()));
}

String _topCategory(String line) {
  for (final String prefix in const <String>[
    'Processes:',
    'Load Avg:',
    'CPU usage:',
    'SharedLibs:',
    'MemRegions:',
    'PhysMem:',
    'VM:',
    'Networks:',
    'Disks:',
  ]) {
    if (line.startsWith(prefix)) {
      return prefix.substring(0, prefix.length - 1);
    }
  }
  if (RegExp(r'^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(line)) {
    return 'Clock';
  }
  throw StateError('top output has an unknown line category');
}

int _hash(Iterable<int> bytes) {
  var hash = 0x811c9dc5;
  for (final int byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
