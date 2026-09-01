import 'dart:io';

const Set<String> _allowedUndefinedSymbols = <String>{
  '___error',
  '__exit',
  '_close',
  '_execve',
  '_write',
};

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: audit_pty_child.dart <PtyExecChild.o>');
    exitCode = 64;
    return;
  }

  final String objectPath = arguments.single;
  final ProcessResult undefinedResult = await Process.run('nm', <String>[
    '-u',
    objectPath,
  ]);
  if (undefinedResult.exitCode != 0) {
    stderr.write(undefinedResult.stderr);
    exitCode = undefinedResult.exitCode;
    return;
  }

  final Set<String> symbols = (undefinedResult.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.split(RegExp(r'\s+')).last)
      .toSet();
  final Set<String> forbidden = symbols.difference(_allowedUndefinedSymbols);
  final Set<String> required = <String>{
    '_close',
    '_execve',
    '_write',
    '__exit',
  };
  final Set<String> missing = required.difference(symbols);
  if (forbidden.isNotEmpty || missing.isNotEmpty) {
    stderr.writeln(
      'PHASE0_PTY_CHILD_AUDIT_FAIL '
      'forbidden=${forbidden.toList()..sort()} '
      'missing=${missing.toList()..sort()} '
      'all=${symbols.toList()..sort()}',
    );
    exitCode = 1;
    return;
  }

  final ProcessResult definedResult = await Process.run('nm', <String>[
    '-g',
    objectPath,
  ]);
  if (definedResult.exitCode != 0 ||
      !(definedResult.stdout as String).contains('_dt_pty_exec_child')) {
    stderr.writeln('PHASE0_PTY_CHILD_AUDIT_FAIL child symbol missing');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'PHASE0_PTY_CHILD_AUDIT_PASS '
    'undefined=${symbols.toList()..sort()}',
  );
}
