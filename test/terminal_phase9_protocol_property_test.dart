import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

const int _suiteSeed = 0x509f52a1;
const int _generatedCases = 64;
const int _mutationsPerAnchor = 8;
const int _maximumProgramBytes = 16 * 1024;
const TerminalSnapshotFormatter _formatter = TerminalSnapshotFormatter(
  limits: TerminalSnapshotFormatLimits(
    maxRows: 32,
    maxCells: 2048,
    maxStyleDefinitions: 256,
    maxGraphemeDefinitions: 128,
    maxHyperlinkDefinitions: 64,
    maxHyperlinkUtf8Bytes: 16 * 1024,
    maxOutputCharacters: 512 * 1024,
  ),
);

void main() {
  final TerminalPhase9ProtocolPropertyResult result =
      runTerminalPhase9ProtocolPropertyTests();
  stdout.writeln(result.machineLine());
}

final class TerminalPhase9ProtocolPropertyResult {
  const TerminalPhase9ProtocolPropertyResult({
    required this.anchors,
    required this.mutations,
    required this.generated,
    required this.executions,
    required this.parsedBytes,
    required this.stateHash,
  });

  final int anchors;
  final int mutations;
  final int generated;
  final int executions;
  final int parsedBytes;
  final int stateHash;

  String machineLine() =>
      'TERMINAL_PHASE9_PROTOCOL_PROPERTY_PASS '
      'seed=0x${_suiteSeed.toRadixString(16)} anchors=$anchors '
      'mutations=$mutations generated=$generated executions=$executions '
      'parsed_bytes=$parsedBytes state_hash=$stateHash';
}

TerminalPhase9ProtocolPropertyResult runTerminalPhase9ProtocolPropertyTests() {
  final _Accumulator accumulator = _Accumulator();
  final List<_Anchor> anchors = _anchors();
  _assertAnchorSemantics(anchors);
  for (int index = 0; index < anchors.length; index++) {
    final _Anchor anchor = anchors[index];
    final _XorShift32 random = _XorShift32(
      _caseSeed(_suiteSeed ^ 0xa5a5a5a5, index),
    );
    _comparePlans(anchor.input, random, 'anchor=${anchor.id}', accumulator);
    for (int mutation = 0; mutation < _mutationsPerAnchor; mutation++) {
      final Uint8List changed = Uint8List.fromList(anchor.input);
      final int offset = random.nextInt(changed.length);
      changed[offset] ^= 1 << random.nextInt(8);
      _comparePlans(
        changed,
        random,
        'anchor=${anchor.id} mutation=$mutation offset=$offset',
        accumulator,
      );
    }
  }
  for (int caseIndex = 0; caseIndex < _generatedCases; caseIndex++) {
    final int seed = _caseSeed(_suiteSeed, caseIndex);
    final _XorShift32 random = _XorShift32(seed);
    final Uint8List input = _generatedProgram(random, anchors);
    _comparePlans(
      input,
      random,
      'seed=0x${seed.toRadixString(16)} case=$caseIndex',
      accumulator,
    );
  }
  _expect(
    accumulator.kittyGraphicsCommands > 0 &&
        accumulator.osc52Requests > 0 &&
        accumulator.desktopNotifications > 0 &&
        accumulator.progressUpdates > 0 &&
        accumulator.replies > 0,
    'every callback/counter-bearing Phase 9 protocol family is exercised',
  );
  final TerminalPhase9ProtocolPropertyResult result =
      TerminalPhase9ProtocolPropertyResult(
        anchors: anchors.length,
        mutations: anchors.length * _mutationsPerAnchor,
        generated: _generatedCases,
        executions: accumulator.executions,
        parsedBytes: accumulator.parsedBytes,
        stateHash: accumulator.stateHash,
      );
  _expect(
    result.executions == 680,
    'fixed suite execution budget changed: ${result.executions}',
  );
  _expect(
    result.machineLine() ==
        'TERMINAL_PHASE9_PROTOCOL_PROPERTY_PASS seed=0x509f52a1 '
            'anchors=8 mutations=64 generated=64 executions=680 '
            'parsed_bytes=731150 state_hash=2246715040',
    'fixed suite digest changed: ${result.machineLine()}',
  );
  return result;
}

void _assertAnchorSemantics(List<_Anchor> anchors) {
  _RunObservation run(String id) {
    final Uint8List input = anchors
        .singleWhere((_Anchor anchor) => anchor.id == id)
        .input;
    return _run(input, <int>[input.length]);
  }

  final _RunObservation keyboard = run('kitty-keyboard-screen-stack');
  _expect(
    keyboard.kittyKeyboardFlags == 5 && keyboard.kittyKeyboardDepth == 1,
    'Kitty keyboard anchor retains primary-screen flags and one bounded frame',
  );
  final _RunObservation synchronized = run('synchronized-output');
  _expect(
    synchronized.synchronizedOutput,
    'synchronized-output anchor retains the final held state',
  );
  final _RunObservation reports = run('appearance-size-unicode-reports');
  _expect(
    reports.colorSchemeReporting &&
        reports.inBandSizeReporting &&
        reports.replyCount >= 5,
    'appearance/size/Unicode anchor enables both mutable reports and replies',
  );
  final _RunObservation graphics = run('kitty-graphics-animation');
  _expect(
    graphics.kittyGraphicsCommandCount == 4,
    'Kitty graphics anchor admits static, frame, control, and composition',
  );
  final _RunObservation desktop = run('desktop-signals');
  _expect(
    desktop.desktopQueued == 2 &&
        desktop.progressState == TerminalProgressState.paused,
    'desktop anchor retains bounded legacy/Kitty requests and progress',
  );
  final _RunObservation semantic = run('semantic-prompts');
  _expect(
    semantic.semanticState == TerminalSemanticShellState.commandOutput,
    'semantic prompt anchor retains only the content-free shell state',
  );
  final _RunObservation osc52 = run('osc52-policy');
  _expect(
    osc52.osc52RequestCount == 4 &&
        osc52.deniedClipboardReads == 2 &&
        osc52.acceptedClipboardWrites == 1 &&
        osc52.acceptedClipboardClears == 1,
    'OSC 52 anchor admits only the callback-selected bounded operations',
  );
  final _RunObservation limits = run('string-limits-recovery');
  _expect(
    limits.limitCount == 2 && limits.recoveryVisible,
    'OSC/APC over-limit anchor rejects both strings and recovers to text',
  );
}

void _comparePlans(
  Uint8List input,
  _XorShift32 random,
  String context,
  _Accumulator accumulator,
) {
  try {
    _expect(
      input.isNotEmpty && input.length <= _maximumProgramBytes,
      '$context respects the suite input bound',
    );
    final _RunObservation whole = _run(input, <int>[input.length]);
    final List<int> generatedChunks = _generatedChunks(input.length, random);
    final _RunObservation generated = _run(input, generatedChunks);
    final _RunObservation bytewise = _run(
      input,
      List<int>.filled(input.length, 1),
    );
    final _RunObservation repeated = _run(input, generatedChunks);
    _expect(
      whole.digest == generated.digest,
      '$context generated chunk drift '
      '${_firstDigestDifference(whole.digest, generated.digest)}',
    );
    _expect(
      whole.digest == bytewise.digest,
      '$context bytewise chunk drift '
      '${_firstDigestDifference(whole.digest, bytewise.digest)}',
    );
    _expect(
      generated.digest == repeated.digest,
      '$context repeated execution drift',
    );
    final _RunObservation recovery = _run(
      Uint8List.fromList(<int>[
        ...input,
        0x18,
        0x1b,
        0x63,
        ...ascii.encode('RECOVER'),
      ]),
      List<int>.filled(input.length + 10, 1),
    );
    _expect(recovery.recoveryVisible, '$context failed CAN/RIS recovery');
    _expect(
      recovery.kittyKeyboardFlags == 0 &&
          recovery.kittyKeyboardDepth == 0 &&
          !recovery.synchronizedOutput &&
          !recovery.colorSchemeReporting &&
          !recovery.inBandSizeReporting &&
          recovery.desktopPending == 0 &&
          recovery.desktopQueued == 0 &&
          recovery.progressState == TerminalProgressState.removed &&
          recovery.semanticState == TerminalSemanticShellState.unknown,
      '$context RIS retained Phase 9 protocol state',
    );
    accumulator.add(whole, input.length);
    accumulator.add(generated, input.length);
    accumulator.add(bytewise, input.length);
    accumulator.add(repeated, input.length);
    accumulator.add(recovery, input.length + 10);
  } on Object catch (error) {
    if (error.toString().contains('PHASE9_PROPERTY_FAILURE')) rethrow;
    throw StateError('PHASE9_PROPERTY_FAILURE $context execution: $error');
  }
}

_RunObservation _run(Uint8List input, List<int> chunks) {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 4, columns: 24)
    ..updateLogicalViewportSize(width: 240, height: 80)
    ..updateLogicalCellSize(width: 10, height: 20);
  final List<Uint8List> replies = <Uint8List>[];
  final List<String> kittyCommands = <String>[];
  final List<String> osc52Requests = <String>[];
  final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
    screens,
    onReply: (Uint8List reply) {
      _expect(
        reply.isNotEmpty &&
            reply.length <= TerminalKittyGraphicsLimits.maximumResponseBytes,
        'parser reply remains within the largest direct parser reply cap',
      );
      replies.add(Uint8List.fromList(reply));
      return true;
    },
    onKittyGraphicsCommand: (TerminalKittyGraphicsCommand command) {
      final Uint8List data = command.copyData();
      _expect(
        data.length <= TerminalKittyGraphicsLimits.maximumDataBytes,
        'Kitty callback data remains bounded',
      );
      kittyCommands.add(
        '${command.action.name}:${command.quiet.name}:'
        '${command.transmission.format}:${command.transmission.medium.name}:'
        '${command.transmission.imageId}:'
        '${command.transmission.placementId}:'
        '${command.frameTransmission.baseFrame}:'
        '${command.frameTransmission.editFrame}:${data.length}:'
        '${_hashBytes(data)}',
      );
      return command.transmission.medium == TerminalKittyGraphicsMedium.direct;
    },
    onOsc52Request: (TerminalOsc52Request request) {
      _expect(
        request.selection.length <= TerminalOsc52Protocol.maximumSelectionBytes,
        'OSC 52 callback selection remains bounded',
      );
      osc52Requests.add(
        '${request.operation.name}:${request.selection}:'
        '${request.encodedData?.length ?? 0}:${request.terminator.name}',
      );
      return request.targetsClipboard &&
          request.operation != TerminalOsc52Operation.read;
    },
  );
  final VtParser parser = VtParser(sink: sink);
  int offset = 0;
  for (final int chunk in chunks) {
    _expect(
      chunk >= 0 && offset + chunk <= input.length,
      'generated chunk plan remains in range',
    );
    parser.parse(input, offset, offset + chunk);
    offset += chunk;
  }
  _expect(offset == input.length, 'generated chunk plan consumes exact input');
  parser.finish();
  sink
    ..projectColorScheme(TerminalColorScheme.light)
    ..projectColorScheme(TerminalColorScheme.dark)
    ..reportInBandSizeAfterResize();

  screens.primary.validateCellTopology();
  screens.alternate.validateCellTopology();
  screens.scrollback.validateCellTopology();
  _expect(parser.isGround, 'parser finishes in ground state');
  _expect(
    screens.kittyKeyboardStackDepth <= 16 &&
        screens.keyboardModes.kittyKeyboardFlags &
                ~TerminalKeyboardModes.kittyKnownFlags ==
            0,
    'Kitty keyboard state remains within its fixed stack and flag masks',
  );
  _expect(
    screens.desktopNotifications.pendingRequestCount <=
            TerminalDesktopNotificationModel.maximumPendingRequests &&
        screens.desktopNotifications.queuedRequestCount <=
            TerminalDesktopNotificationModel.maximumQueuedRequests,
    'desktop signal parser state remains within queue caps',
  );
  for (final TerminalDesktopNotificationRequest request
      in screens.desktopNotifications.queuedRequests) {
    _expect(
      utf8.encode(request.title).length <=
              TerminalDesktopNotificationModel.maximumAggregateTitleBytes &&
          utf8.encode(request.body).length <=
              TerminalDesktopNotificationModel.maximumAggregateBodyBytes,
      'desktop signal text remains within aggregate UTF-8 caps',
    );
  }

  final List<String> replyDigests = <String>[
    for (final Uint8List reply in replies)
      '${reply.length}:${_hashBytes(reply)}',
  ];
  final List<String> notificationDigests = <String>[
    for (final TerminalDesktopNotificationRequest request
        in screens.desktopNotifications.queuedRequests)
      '${request.protocol.name}:${request.identifier ?? ''}:'
          '${utf8.encode(request.title).length}:${_hashString(request.title)}:'
          '${utf8.encode(request.body).length}:${_hashString(request.body)}',
  ];
  final String digest = <String>[
    _formatter.formatScreenSet(screens, parserSink: sink),
    'active=${screens.activeKind.name}',
    'keyboard=${screens.keyboardModes.kittyKeyboardFlags}:'
        '${screens.kittyKeyboardStackDepth}',
    'sync=${screens.synchronizedOutputMode}',
    'reports=${screens.colorSchemeReportingMode}:'
        '${screens.inBandSizeReportingMode}:${screens.colorScheme.name}',
    'desktop=${screens.desktopNotifications.pendingRequestCount}:'
        '${screens.desktopNotifications.queuedRequestCount}:'
        '${screens.desktopNotifications.droppedRequestCount}:'
        '${notificationDigests.join(',')}',
    'progress=${screens.progress.value.state.name}:'
        '${screens.progress.value.percent}',
    'semantic=${screens.semanticPrompt.shellState.name}',
    'kitty=${kittyCommands.join(',')}',
    'osc52=${osc52Requests.join(',')}',
    'phase9_counters=${sink.acceptedKittyGraphicsCommandCount}:'
        '${sink.rejectedKittyGraphicsCommandCount}:'
        '${sink.acceptedDesktopNotificationCount}:'
        '${sink.acceptedProgressUpdateCount}:'
        '${sink.acceptedClipboardReadCount}:'
        '${sink.acceptedClipboardWriteCount}:'
        '${sink.acceptedClipboardClearCount}:'
        '${sink.deniedClipboardReadCount}:'
        '${sink.deniedClipboardWriteCount}:'
        '${sink.deniedClipboardClearCount}:'
        '${sink.rejectedClipboardRequestCount}',
    'replies=${replyDigests.join(',')}',
  ].join('\n');
  return _RunObservation(
    digest: digest,
    replyCount: replies.length,
    kittyGraphicsCommandCount: kittyCommands.length,
    osc52RequestCount: osc52Requests.length,
    acceptedKittyGraphics: sink.acceptedKittyGraphicsCommandCount,
    acceptedDesktopNotifications: sink.acceptedDesktopNotificationCount,
    acceptedProgressUpdates: sink.acceptedProgressUpdateCount,
    acceptedClipboardWrites: sink.acceptedClipboardWriteCount,
    acceptedClipboardClears: sink.acceptedClipboardClearCount,
    deniedClipboardReads: sink.deniedClipboardReadCount,
    kittyKeyboardFlags: screens.keyboardModes.kittyKeyboardFlags,
    kittyKeyboardDepth: screens.kittyKeyboardStackDepth,
    synchronizedOutput: screens.synchronizedOutputMode,
    colorSchemeReporting: screens.colorSchemeReportingMode,
    inBandSizeReporting: screens.inBandSizeReportingMode,
    desktopPending: screens.desktopNotifications.pendingRequestCount,
    desktopQueued: screens.desktopNotifications.queuedRequestCount,
    progressState: screens.progress.value.state,
    semanticState: screens.semanticPrompt.shellState,
    limitCount: sink.limitCount,
    recoveryVisible: _rowStartsWith(screens.primary, 'RECOVER'),
  );
}

List<_Anchor> _anchors() => <_Anchor>[
  _Anchor(
    'kitty-keyboard-screen-stack',
    _bytes(<int>[
      ..._csi('>3u'),
      ..._csi('=5;1u'),
      ..._csi('?u'),
      ..._csi('?47h'),
      ..._csi('>8u'),
      ..._csi('<1u'),
      ..._csi('?47l'),
    ]),
  ),
  _Anchor(
    'synchronized-output',
    _bytes(<int>[
      ..._csi('?2026h'),
      ...ascii.encode('held'),
      ..._csi('?2026l'),
      ..._csi('?2026h'),
      ...ascii.encode('newest'),
    ]),
  ),
  _Anchor(
    'appearance-size-unicode-reports',
    _bytes(<int>[
      ..._csi('?2031h'),
      ..._csi('?996n'),
      ..._csi('?2048h'),
      ..._csi('16t'),
      ..._csi('?2027\$p'),
    ]),
  ),
  _Anchor(
    'kitty-graphics-animation',
    _bytes(<int>[
      ..._apc('Ga=T,f=32,s=1,v=1,i=7,p=3;AQIDBA=='),
      ..._apc('Ga=f,i=7,f=32,s=1,v=1,c=1,r=2,z=20;BQYHCA=='),
      ..._apc('Ga=a,i=7,s=3,r=2,z=30,c=2,v=4'),
      ..._apc('Ga=c,i=7,r=1,c=2,x=0,y=0,w=1,h=1'),
    ]),
  ),
  _Anchor(
    'desktop-signals',
    _bytes(<int>[
      ..._osc('9;legacy'),
      ..._osc('9;4;4;75'),
      ..._osc('99;i=job:d=0;Build '),
      ..._osc('99;i=job:p=body;done'),
    ]),
  ),
  _Anchor(
    'semantic-prompts',
    _bytes(<int>[
      ..._osc('133;A'),
      ...ascii.encode('% '),
      ..._osc('133;B'),
      ...ascii.encode('echo ok'),
      ..._osc('133;C'),
      ...ascii.encode('ok'),
    ]),
  ),
  _Anchor(
    'osc52-policy',
    _bytes(<int>[
      ..._osc('52;c;?'),
      ..._osc('52;c;cnVudGltZQ==', bell: false),
      ..._osc('52;c;!'),
      ..._osc('52;p;?'),
    ]),
  ),
  _Anchor(
    'string-limits-recovery',
    _bytes(<int>[
      0x1b,
      0x5d,
      ...List<int>.filled(4097, 0x41),
      0x07,
      0x1b,
      0x5f,
      0x47,
      ...List<int>.filled(4610, 0x41),
      0x1b,
      0x5c,
      0x18,
      0x1b,
      0x63,
      ...ascii.encode('RECOVER'),
    ]),
  ),
];

Uint8List _generatedProgram(_XorShift32 random, List<_Anchor> anchors) {
  final BytesBuilder builder = BytesBuilder(copy: false);
  final int fragmentCount = 8 + random.nextInt(17);
  for (int index = 0; index < fragmentCount; index++) {
    final _Anchor selected = anchors[random.nextInt(anchors.length - 1)];
    final Uint8List fragment = selected.input;
    if (random.nextInt(5) == 0) {
      final Uint8List changed = Uint8List.fromList(fragment);
      final int offset = random.nextInt(changed.length);
      changed[offset] ^= 1 << random.nextInt(8);
      builder.add(changed);
    } else {
      builder.add(fragment);
    }
    if (random.nextInt(4) == 0) {
      builder.add(<int>[
        random.nextInt(256),
        0x18,
        0x20 + random.nextInt(0x5f),
      ]);
    }
    if (builder.length >= 2048) break;
  }
  final Uint8List bytes = builder.takeBytes();
  return bytes.length <= _maximumProgramBytes
      ? bytes
      : Uint8List.sublistView(bytes, 0, _maximumProgramBytes);
}

List<int> _generatedChunks(int length, _XorShift32 random) {
  final List<int> result = <int>[if (random.nextInt(2) == 0) 0];
  int remaining = length;
  while (remaining > 0) {
    final int maximum = remaining < 97 ? remaining : 97;
    final int chunk = 1 + random.nextInt(maximum);
    result.add(chunk);
    remaining -= chunk;
    if (random.nextInt(11) == 0) result.add(0);
  }
  if (random.nextInt(2) == 0) result.add(0);
  return result;
}

List<int> _csi(String body) => <int>[0x1b, 0x5b, ...ascii.encode(body)];

List<int> _osc(String payload, {bool bell = true}) => <int>[
  0x1b,
  0x5d,
  ...ascii.encode(payload),
  if (bell) 0x07 else ...const <int>[0x1b, 0x5c],
];

List<int> _apc(String payload) => <int>[
  0x1b,
  0x5f,
  ...ascii.encode(payload),
  0x1b,
  0x5c,
];

Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);

bool _rowStartsWith(TerminalScreen screen, String value) {
  if (screen.columns < value.length) return false;
  for (int column = 0; column < value.length; column++) {
    if (screen.contentAt(0, column) != value.codeUnitAt(column)) return false;
  }
  return true;
}

int _caseSeed(int root, int index) {
  int value = (root + (index + 1) * 0x9e3779b9) & 0xffffffff;
  value ^= value >>> 16;
  value = (value * 0x7feb352d) & 0xffffffff;
  value ^= value >>> 15;
  value = (value * 0x846ca68b) & 0xffffffff;
  value ^= value >>> 16;
  return value == 0 ? 0x6d2b79f5 : value;
}

int _hashBytes(Uint8List value) {
  int hash = 0x811c9dc5;
  for (final int byte in value) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int _hashString(String value) =>
    _hashBytes(Uint8List.fromList(utf8.encode(value)));

String _firstDigestDifference(String expected, String actual) {
  final List<String> expectedLines = const LineSplitter().convert(expected);
  final List<String> actualLines = const LineSplitter().convert(actual);
  final int shared = expectedLines.length < actualLines.length
      ? expectedLines.length
      : actualLines.length;
  int line = 0;
  while (line < shared && expectedLines[line] == actualLines[line]) {
    line++;
  }
  String bounded(String value) => value.length <= 160
      ? value
      : '${value.substring(0, 160)}…(${value.length})';
  return 'line=${line + 1} '
      'expected=${jsonEncode(bounded(line < expectedLines.length ? expectedLines[line] : '<eof>'))} '
      'actual=${jsonEncode(bounded(line < actualLines.length ? actualLines[line] : '<eof>'))}';
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('PHASE9_PROPERTY_FAILURE $message');
}

final class _Anchor {
  const _Anchor(this.id, this.input);

  final String id;
  final Uint8List input;
}

final class _RunObservation {
  const _RunObservation({
    required this.digest,
    required this.replyCount,
    required this.kittyGraphicsCommandCount,
    required this.osc52RequestCount,
    required this.acceptedKittyGraphics,
    required this.acceptedDesktopNotifications,
    required this.acceptedProgressUpdates,
    required this.acceptedClipboardWrites,
    required this.acceptedClipboardClears,
    required this.deniedClipboardReads,
    required this.kittyKeyboardFlags,
    required this.kittyKeyboardDepth,
    required this.synchronizedOutput,
    required this.colorSchemeReporting,
    required this.inBandSizeReporting,
    required this.desktopPending,
    required this.desktopQueued,
    required this.progressState,
    required this.semanticState,
    required this.limitCount,
    required this.recoveryVisible,
  });

  final String digest;
  final int replyCount;
  final int kittyGraphicsCommandCount;
  final int osc52RequestCount;
  final int acceptedKittyGraphics;
  final int acceptedDesktopNotifications;
  final int acceptedProgressUpdates;
  final int acceptedClipboardWrites;
  final int acceptedClipboardClears;
  final int deniedClipboardReads;
  final int kittyKeyboardFlags;
  final int kittyKeyboardDepth;
  final bool synchronizedOutput;
  final bool colorSchemeReporting;
  final bool inBandSizeReporting;
  final int desktopPending;
  final int desktopQueued;
  final TerminalProgressState progressState;
  final TerminalSemanticShellState semanticState;
  final int limitCount;
  final bool recoveryVisible;
}

final class _Accumulator {
  int executions = 0;
  int parsedBytes = 0;
  int stateHash = 0x811c9dc5;
  int kittyGraphicsCommands = 0;
  int osc52Requests = 0;
  int desktopNotifications = 0;
  int progressUpdates = 0;
  int replies = 0;

  void add(_RunObservation observation, int bytes) {
    executions++;
    parsedBytes += bytes;
    stateHash =
        ((stateHash ^ _hashString(observation.digest)) * 0x01000193) &
        0xffffffff;
    kittyGraphicsCommands += observation.acceptedKittyGraphics;
    osc52Requests += observation.osc52RequestCount;
    desktopNotifications += observation.acceptedDesktopNotifications;
    progressUpdates += observation.acceptedProgressUpdates;
    replies += observation.replyCount;
  }
}

final class _XorShift32 {
  _XorShift32(int seed) : _state = seed & 0xffffffff;

  int _state;

  int nextUint32() {
    int value = _state;
    value ^= (value << 13) & 0xffffffff;
    value ^= value >>> 17;
    value ^= (value << 5) & 0xffffffff;
    _state = value & 0xffffffff;
    return _state;
  }

  int nextInt(int maximum) {
    if (maximum <= 0) throw ArgumentError.value(maximum, 'maximum');
    return nextUint32() % maximum;
  }
}
