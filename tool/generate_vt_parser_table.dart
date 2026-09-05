import 'dart:io';

const String _defaultOutput =
    'lib/src/terminal_core/generated/vt_parser_table.g.dart';

final class _ByteRange {
  const _ByteRange(this.first, [int? last]) : last = last ?? first;

  final int first;
  final int last;
}

final class _Rule {
  const _Rule(
    this.bytes, {
    this.nextState,
    this.action = 'none',
    this.reenter = false,
  });

  final List<_ByteRange> bytes;
  final String? nextState;
  final String action;
  final bool reenter;
}

final class _StateSpec {
  const _StateSpec(
    this.name, {
    this.entryAction = 'none',
    this.exitAction = 'none',
    this.defaultAction = 'ignore',
    this.rules = const <_Rule>[],
  });

  final String name;
  final String entryAction;
  final String exitAction;
  final String defaultAction;
  final List<_Rule> rules;
}

const List<String> _actions = <String>[
  'none',
  'ignore',
  'print',
  'execute',
  'clear',
  'collect',
  'parameter',
  'escapeDispatch',
  'csiDispatch',
  'dcsHook',
  'dcsPut',
  'dcsUnhook',
  'oscStart',
  'oscPut',
  'oscEnd',
  'stringStart',
  'stringPut',
  'stringEnd',
  'cancel',
  'utf8',
];

const List<_ByteRange> _c0 = <_ByteRange>[
  _ByteRange(0x00, 0x17),
  _ByteRange(0x19),
  _ByteRange(0x1c, 0x1f),
];

const List<_ByteRange> _c1Execute = <_ByteRange>[
  _ByteRange(0x80, 0x8f),
  _ByteRange(0x91, 0x97),
  _ByteRange(0x99, 0x9a),
];

const List<_StateSpec> _states = <_StateSpec>[
  _StateSpec(
    'ground',
    defaultAction: 'utf8',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x7e)], action: 'print'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
      _Rule(_c1Execute, action: 'execute'),
    ],
  ),
  _StateSpec(
    'escape',
    entryAction: 'clear',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(
        <_ByteRange>[_ByteRange(0x20, 0x2f)],
        nextState: 'escapeIntermediate',
        action: 'collect',
      ),
      _Rule(
        <_ByteRange>[
          _ByteRange(0x30, 0x4f),
          _ByteRange(0x51, 0x57),
          _ByteRange(0x59, 0x5a),
          _ByteRange(0x5c),
          _ByteRange(0x60, 0x7e),
        ],
        nextState: 'ground',
        action: 'escapeDispatch',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x50)], nextState: 'dcsEntry'),
      _Rule(<_ByteRange>[_ByteRange(0x58)], nextState: 'sosPmApcString'),
      _Rule(<_ByteRange>[_ByteRange(0x5b)], nextState: 'csiEntry'),
      _Rule(<_ByteRange>[_ByteRange(0x5d)], nextState: 'oscString'),
      _Rule(<_ByteRange>[_ByteRange(0x5e, 0x5f)], nextState: 'sosPmApcString'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'escapeIntermediate',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x2f)], action: 'collect'),
      _Rule(
        <_ByteRange>[_ByteRange(0x30, 0x7e)],
        nextState: 'ground',
        action: 'escapeDispatch',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'csiEntry',
    entryAction: 'clear',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(
        <_ByteRange>[_ByteRange(0x20, 0x2f)],
        nextState: 'csiIntermediate',
        action: 'collect',
      ),
      _Rule(
        <_ByteRange>[_ByteRange(0x30, 0x3b)],
        nextState: 'csiParameter',
        action: 'parameter',
      ),
      _Rule(
        <_ByteRange>[_ByteRange(0x3c, 0x3f)],
        nextState: 'csiParameter',
        action: 'collect',
      ),
      _Rule(
        <_ByteRange>[_ByteRange(0x40, 0x7e)],
        nextState: 'ground',
        action: 'csiDispatch',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'csiParameter',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(
        <_ByteRange>[_ByteRange(0x20, 0x2f)],
        nextState: 'csiIntermediate',
        action: 'collect',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x30, 0x3b)], action: 'parameter'),
      _Rule(<_ByteRange>[_ByteRange(0x3c, 0x3f)], nextState: 'csiIgnore'),
      _Rule(
        <_ByteRange>[_ByteRange(0x40, 0x7e)],
        nextState: 'ground',
        action: 'csiDispatch',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'csiIntermediate',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x2f)], action: 'collect'),
      _Rule(<_ByteRange>[_ByteRange(0x30, 0x3f)], nextState: 'csiIgnore'),
      _Rule(
        <_ByteRange>[_ByteRange(0x40, 0x7e)],
        nextState: 'ground',
        action: 'csiDispatch',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'csiIgnore',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(<_ByteRange>[_ByteRange(0x40, 0x7e)], nextState: 'ground'),
    ],
  ),
  _StateSpec(
    'oscString',
    entryAction: 'oscStart',
    exitAction: 'oscEnd',
    rules: <_Rule>[
      _Rule(<_ByteRange>[_ByteRange(0x07)], nextState: 'ground'),
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x7e)], action: 'oscPut'),
      _Rule(<_ByteRange>[_ByteRange(0x80, 0xff)], action: 'oscPut'),
    ],
  ),
  _StateSpec(
    'dcsEntry',
    entryAction: 'clear',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(
        <_ByteRange>[_ByteRange(0x20, 0x2f)],
        nextState: 'dcsIntermediate',
        action: 'collect',
      ),
      _Rule(
        <_ByteRange>[_ByteRange(0x30, 0x3b)],
        nextState: 'dcsParameter',
        action: 'parameter',
      ),
      _Rule(
        <_ByteRange>[_ByteRange(0x3c, 0x3f)],
        nextState: 'dcsParameter',
        action: 'collect',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x40, 0x7e)], nextState: 'dcsPassthrough'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'dcsParameter',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(
        <_ByteRange>[_ByteRange(0x20, 0x2f)],
        nextState: 'dcsIntermediate',
        action: 'collect',
      ),
      _Rule(<_ByteRange>[_ByteRange(0x30, 0x3b)], action: 'parameter'),
      _Rule(<_ByteRange>[_ByteRange(0x3c, 0x3f)], nextState: 'dcsIgnore'),
      _Rule(<_ByteRange>[_ByteRange(0x40, 0x7e)], nextState: 'dcsPassthrough'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'dcsIntermediate',
    rules: <_Rule>[
      _Rule(_c0, action: 'execute'),
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x2f)], action: 'collect'),
      _Rule(<_ByteRange>[_ByteRange(0x30, 0x3f)], nextState: 'dcsIgnore'),
      _Rule(<_ByteRange>[_ByteRange(0x40, 0x7e)], nextState: 'dcsPassthrough'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec(
    'dcsPassthrough',
    entryAction: 'dcsHook',
    exitAction: 'dcsUnhook',
    rules: <_Rule>[
      _Rule(<_ByteRange>[
        _ByteRange(0x00, 0x17),
        _ByteRange(0x19, 0x7e),
        _ByteRange(0x80, 0xff),
      ], action: 'dcsPut'),
      _Rule(<_ByteRange>[_ByteRange(0x7f)]),
    ],
  ),
  _StateSpec('dcsIgnore'),
  _StateSpec(
    'sosPmApcString',
    entryAction: 'stringStart',
    exitAction: 'stringEnd',
    rules: <_Rule>[
      _Rule(<_ByteRange>[_ByteRange(0x20, 0x7e)], action: 'stringPut'),
      _Rule(<_ByteRange>[_ByteRange(0x80, 0xff)], action: 'stringPut'),
    ],
  ),
];

const List<_Rule> _anywhereRules = <_Rule>[
  _Rule(
    <_ByteRange>[_ByteRange(0x18), _ByteRange(0x1a)],
    nextState: 'ground',
    action: 'cancel',
  ),
  _Rule(<_ByteRange>[_ByteRange(0x1b)], nextState: 'escape', reenter: true),
  _Rule(<_ByteRange>[_ByteRange(0x90)], nextState: 'dcsEntry', reenter: true),
  _Rule(
    <_ByteRange>[_ByteRange(0x98)],
    nextState: 'sosPmApcString',
    reenter: true,
  ),
  _Rule(<_ByteRange>[_ByteRange(0x9b)], nextState: 'csiEntry', reenter: true),
  _Rule(<_ByteRange>[_ByteRange(0x9c)], nextState: 'ground'),
  _Rule(<_ByteRange>[_ByteRange(0x9d)], nextState: 'oscString', reenter: true),
  _Rule(
    <_ByteRange>[_ByteRange(0x9e, 0x9f)],
    nextState: 'sosPmApcString',
    reenter: true,
  ),
];

/// Produces the complete checked-in Dart source for the VT transition table.
String generateVtParserTableSource() {
  final Map<String, int> stateIds = _indexedNames(
    _states.map((_StateSpec state) => state.name),
    'state',
  );
  final Map<String, int> actionIds = _indexedNames(_actions, 'action');
  _validateRules(_anywhereRules, stateIds, actionIds, 'anywhere');

  final List<int> entryActions = <int>[];
  final List<int> exitActions = <int>[];
  final List<int> nextStates = <int>[];
  final List<int> transitionActions = <int>[];
  final List<int> transitionReentryFlags = <int>[];
  for (int stateId = 0; stateId < _states.length; stateId++) {
    final _StateSpec state = _states[stateId];
    final int entryAction = _requiredId(
      actionIds,
      state.entryAction,
      'entry action for ${state.name}',
    );
    final int exitAction = _requiredId(
      actionIds,
      state.exitAction,
      'exit action for ${state.name}',
    );
    final int defaultAction = _requiredId(
      actionIds,
      state.defaultAction,
      'default action for ${state.name}',
    );
    entryActions.add(entryAction);
    exitActions.add(exitAction);

    final List<int> stateNext = List<int>.filled(256, stateId);
    final List<int> stateActions = List<int>.filled(256, defaultAction);
    final List<int> stateReentry = List<int>.filled(256, 0);
    _applyRules(
      state.rules,
      stateNext,
      stateActions,
      stateReentry,
      stateIds,
      actionIds,
      state.name,
      currentStateId: stateId,
      rejectOverlap: true,
    );
    _applyRules(
      _anywhereRules,
      stateNext,
      stateActions,
      stateReentry,
      stateIds,
      actionIds,
      'anywhere/${state.name}',
      currentStateId: stateId,
      rejectOverlap: false,
    );
    nextStates.addAll(stateNext);
    transitionActions.addAll(stateActions);
    transitionReentryFlags.addAll(stateReentry);
  }

  final StringBuffer output = StringBuffer()
    ..writeln('// Generated by tool/generate_vt_parser_table.dart.')
    ..writeln('// Do not edit by hand.')
    ..writeln()
    ..writeln("part of '../vt_parser_table.dart';")
    ..writeln()
    ..writeln('enum VtParserState {')
    ..write(_formatNames(_states.map((_StateSpec state) => state.name)))
    ..writeln('}')
    ..writeln()
    ..writeln('enum VtParserAction {')
    ..write(_formatNames(_actions))
    ..writeln('}')
    ..writeln()
    ..writeln('abstract final class VtParserTable {')
    ..writeln('  static const int byteCount = 256;')
    ..writeln('  static const int stateCount = ${_states.length};')
    ..writeln('  static const int actionCount = ${_actions.length};')
    ..writeln()
    ..writeln('  // dart format off')
    ..write(_formatUint8List('_entryActionIds', entryActions))
    ..writeln()
    ..write(_formatUint8List('_exitActionIds', exitActions))
    ..writeln()
    ..write(_formatUint8List('_nextStateIds', nextStates))
    ..writeln()
    ..write(_formatUint8List('_transitionActionIds', transitionActions))
    ..writeln()
    ..write(_formatUint8List('_transitionReentryFlags', transitionReentryFlags))
    ..writeln('  // dart format on')
    ..writeln()
    ..writeln("  @pragma('vm:prefer-inline')")
    ..writeln('  static int nextStateIdUnchecked(int stateId, int byte) =>')
    ..writeln('      _nextStateIds[(stateId << 8) | byte];')
    ..writeln()
    ..writeln("  @pragma('vm:prefer-inline')")
    ..writeln(
      '  static int transitionActionIdUnchecked(int stateId, int byte) =>',
    )
    ..writeln('      _transitionActionIds[(stateId << 8) | byte];')
    ..writeln()
    ..writeln("  @pragma('vm:prefer-inline')")
    ..writeln(
      '  static bool transitionReentersUnchecked(int stateId, int byte) =>',
    )
    ..writeln('      _transitionReentryFlags[(stateId << 8) | byte] != 0;')
    ..writeln()
    ..writeln("  @pragma('vm:prefer-inline')")
    ..writeln(
      '  static int entryActionIdUnchecked(int stateId) => '
      '_entryActionIds[stateId];',
    )
    ..writeln()
    ..writeln("  @pragma('vm:prefer-inline')")
    ..writeln(
      '  static int exitActionIdUnchecked(int stateId) => '
      '_exitActionIds[stateId];',
    )
    ..writeln()
    ..writeln(
      '  static VtParserState nextState(VtParserState state, int byte) {',
    )
    ..writeln('    _checkByte(byte);')
    ..writeln(
      '    return VtParserState.values['
      'nextStateIdUnchecked(state.index, byte)];',
    )
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  static VtParserAction transitionAction(VtParserState state, int byte) {',
    )
    ..writeln('    _checkByte(byte);')
    ..writeln('    return VtParserAction.values[transitionActionIdUnchecked(')
    ..writeln('      state.index,')
    ..writeln('      byte,')
    ..writeln('    )];')
    ..writeln('  }')
    ..writeln()
    ..writeln(
      '  static bool transitionReenters(VtParserState state, int byte) {',
    )
    ..writeln('    _checkByte(byte);')
    ..writeln('    return transitionReentersUnchecked(state.index, byte);')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static VtParserAction entryAction(VtParserState state) =>')
    ..writeln(
      '      VtParserAction.values[entryActionIdUnchecked(state.index)];',
    )
    ..writeln()
    ..writeln('  static VtParserAction exitAction(VtParserState state) =>')
    ..writeln(
      '      VtParserAction.values[exitActionIdUnchecked(state.index)];',
    )
    ..writeln()
    ..writeln('  static void _checkByte(int byte) {')
    ..writeln('    if (byte < 0 || byte >= byteCount) {')
    ..writeln("      throw RangeError.range(byte, 0, byteCount - 1, 'byte');")
    ..writeln('    }')
    ..writeln('  }')
    ..writeln('}');
  return output.toString();
}

Map<String, int> _indexedNames(Iterable<String> names, String kind) {
  final Map<String, int> result = <String, int>{};
  for (final String name in names) {
    if (name.isEmpty || !RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(name)) {
      throw StateError('invalid $kind name: $name');
    }
    if (result.containsKey(name)) {
      throw StateError('duplicate $kind name: $name');
    }
    result[name] = result.length;
  }
  if (result.length > 256) {
    throw StateError('too many ${kind}s for a byte table: ${result.length}');
  }
  return result;
}

void _validateRules(
  List<_Rule> rules,
  Map<String, int> stateIds,
  Map<String, int> actionIds,
  String owner,
) {
  final List<int> placeholderStates = List<int>.filled(256, 0);
  final List<int> placeholderActions = List<int>.filled(256, 0);
  final List<int> placeholderReentry = List<int>.filled(256, 0);
  _applyRules(
    rules,
    placeholderStates,
    placeholderActions,
    placeholderReentry,
    stateIds,
    actionIds,
    owner,
    currentStateId: 0,
    rejectOverlap: true,
  );
}

void _applyRules(
  List<_Rule> rules,
  List<int> nextStates,
  List<int> actions,
  List<int> reentryFlags,
  Map<String, int> stateIds,
  Map<String, int> actionIds,
  String owner, {
  required int currentStateId,
  required bool rejectOverlap,
}) {
  final List<bool> assigned = List<bool>.filled(256, false);
  for (final _Rule rule in rules) {
    final int? nextState = rule.nextState == null
        ? null
        : _requiredId(stateIds, rule.nextState!, 'next state in $owner');
    final int action = _requiredId(
      actionIds,
      rule.action,
      'transition action in $owner',
    );
    for (final _ByteRange range in rule.bytes) {
      if (range.first < 0 || range.last < range.first || range.last > 0xff) {
        throw StateError(
          'invalid byte range in $owner: ${range.first}..${range.last}',
        );
      }
      for (int byte = range.first; byte <= range.last; byte++) {
        if (rejectOverlap && assigned[byte]) {
          throw StateError(
            'overlapping byte rule in $owner at '
            '0x${byte.toRadixString(16).padLeft(2, '0')}',
          );
        }
        assigned[byte] = true;
        if (nextState != null) {
          nextStates[byte] = nextState;
        }
        actions[byte] = action;
        reentryFlags[byte] = rule.reenter && nextStates[byte] == currentStateId
            ? 1
            : 0;
      }
    }
  }
}

int _requiredId(Map<String, int> ids, String name, String context) {
  final int? value = ids[name];
  if (value == null) {
    throw StateError('unknown $context: $name');
  }
  return value;
}

String _formatNames(Iterable<String> names) {
  final StringBuffer output = StringBuffer();
  for (final String name in names) {
    output.writeln('  $name,');
  }
  return output.toString();
}

String _formatUint8List(String name, List<int> values) {
  final StringBuffer output = StringBuffer()
    ..writeln('  static final Uint8List $name = Uint8List.fromList(<int>[');
  for (int start = 0; start < values.length; start += 16) {
    final int end = (start + 16).clamp(0, values.length);
    output
      ..write('    ')
      ..write(values.sublist(start, end).join(', '))
      ..writeln(',');
  }
  output.writeln('  ]);');
  return output.toString();
}

Future<void> main(List<String> arguments) async {
  bool check = false;
  String outputPath = _defaultOutput;
  for (final String argument in arguments) {
    if (argument == '--check') {
      check = true;
    } else if (argument.startsWith('--output=')) {
      outputPath = argument.substring('--output='.length);
    } else {
      throw FormatException('unknown argument: $argument');
    }
  }

  final String generated = generateVtParserTableSource();
  final File output = File(outputPath);
  if (check) {
    if (!output.existsSync() || output.readAsStringSync() != generated) {
      stderr.writeln(
        'VT parser table is stale; run '
        '`dart run tool/generate_vt_parser_table.dart`.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('VT_PARSER_TABLE_CHECK_PASS path=$outputPath');
    return;
  }

  output.parent.createSync(recursive: true);
  output.writeAsStringSync(generated);
  stdout.writeln('VT_PARSER_TABLE_GENERATED path=$outputPath');
}
