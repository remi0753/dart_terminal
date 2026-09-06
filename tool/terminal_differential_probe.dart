import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _maximumInputBytes = 16 * 1024;
const int _maximumReplyBytes = 4096;

Future<void> main(List<String> arguments) async {
  final Map<String, String> options;
  try {
    options = _parseOptions(arguments);
  } on FormatException {
    exitCode = 64;
    return;
  }
  final String resultPath = options['result']!;
  final Uint8List input;
  try {
    input = _decodeHex(options['input-hex']!);
  } on FormatException {
    exitCode = 64;
    return;
  }
  final int deadlineMilliseconds = int.parse(options['deadline-ms']!);
  final int quietMilliseconds = int.parse(options['quiet-ms']!);
  if (!resultPath.startsWith('/') ||
      deadlineMilliseconds < 100 ||
      deadlineMilliseconds > 5000 ||
      quietMilliseconds < 10 ||
      quietMilliseconds > 1000 ||
      quietMilliseconds >= deadlineMilliseconds) {
    exitCode = 64;
    return;
  }

  final BytesBuilder replies = BytesBuilder(copy: false);
  final Completer<void> done = Completer<void>();
  Timer? quietTimer;
  final Timer deadline = Timer(
    Duration(milliseconds: deadlineMilliseconds),
    () {
      if (!done.isCompleted) done.complete();
    },
  );
  StreamSubscription<List<int>>? subscription;
  bool rawModeEnabled = false;
  bool overflowed = false;
  final bool hasTerminal = stdin.hasTerminal && stdout.hasTerminal;
  int terminalRows = 0;
  int terminalColumns = 0;
  try {
    if (hasTerminal) {
      terminalRows = stdout.terminalLines;
      terminalColumns = stdout.terminalColumns;
      stdin.echoMode = false;
      stdin.lineMode = false;
      rawModeEnabled = true;
      subscription = stdin.listen((List<int> chunk) {
        if (replies.length + chunk.length > _maximumReplyBytes) {
          overflowed = true;
          if (!done.isCompleted) done.complete();
          return;
        }
        replies.add(chunk);
        quietTimer?.cancel();
        quietTimer = Timer(Duration(milliseconds: quietMilliseconds), () {
          if (!done.isCompleted) done.complete();
        });
      });
      stdout.add(input);
      await stdout.flush();
      await done.future;
    }
  } on Object {
    overflowed = true;
  } finally {
    deadline.cancel();
    quietTimer?.cancel();
    await subscription?.cancel();
    if (rawModeEnabled) {
      try {
        stdin.lineMode = true;
        stdin.echoMode = true;
      } on Object {
        // The PTY may already be gone. Probe output is persisted separately.
      }
    }
  }

  final File result = File(resultPath);
  final File partial = File('$resultPath.partial');
  final String status = !hasTerminal
      ? 'not-a-terminal'
      : overflowed
      ? 'overflow'
      : 'ok';
  partial.writeAsStringSync(
    '${jsonEncode(<String, Object?>{'format': 'dart-terminal-differential-probe', 'version': 1, 'status': status, 'terminal_rows': terminalRows, 'terminal_columns': terminalColumns, 'replies_hex': _encodeHex(replies.takeBytes())})}\n',
    flush: true,
  );
  partial.renameSync(result.path);
}

Map<String, String> _parseOptions(List<String> arguments) {
  const Set<String> names = <String>{
    'result',
    'input-hex',
    'deadline-ms',
    'quiet-ms',
  };
  final Map<String, String> result = <String, String>{};
  for (final String argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) {
      throw const FormatException('invalid option');
    }
    final int separator = argument.indexOf('=');
    final String name = argument.substring(2, separator);
    final String value = argument.substring(separator + 1);
    if (!names.contains(name) || value.isEmpty || result.containsKey(name)) {
      throw const FormatException('invalid option');
    }
    result[name] = value;
  }
  if (result.length != names.length) {
    throw const FormatException('missing option');
  }
  int.parse(result['deadline-ms']!);
  int.parse(result['quiet-ms']!);
  return result;
}

Uint8List _decodeHex(String source) {
  if (source.length.isOdd || source.length > _maximumInputBytes * 2) {
    throw const FormatException('invalid input');
  }
  final Uint8List result = Uint8List(source.length ~/ 2);
  for (int index = 0; index < result.length; index++) {
    final int high = _hexNibble(source.codeUnitAt(index * 2));
    final int low = _hexNibble(source.codeUnitAt(index * 2 + 1));
    if (high < 0 || low < 0) throw const FormatException('invalid input');
    result[index] = high << 4 | low;
  }
  return result;
}

int _hexNibble(int value) {
  if (value >= 0x30 && value <= 0x39) return value - 0x30;
  if (value >= 0x61 && value <= 0x66) return value - 0x61 + 10;
  return -1;
}

String _encodeHex(List<int> bytes) => <String>[
  for (final int byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join();
