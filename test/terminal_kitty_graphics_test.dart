import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalKittyGraphicsTests();

void runTerminalKittyGraphicsTests() {
  _testDefaultsAndImmutableData();
  _testCompleteStaticControlValues();
  _testActionsAndSelectors();
  _testIntegerBoundariesAndRepeatedKeys();
  _testMalformedAndBoundedCommands();
  _testOuterParserEverySplitAndRecovery();
  _testDistinctApcAndGenericStringLimits();
  _testResponseEncodingAndQuietPolicy();
}

void _testDefaultsAndImmutableData() {
  final Uint8List payload = _bytes('G;QUJD');
  final TerminalKittyGraphicsCommand command =
      TerminalKittyGraphicsCommandParser.parse(payload);
  payload[2] = 0x5a;
  final Uint8List first = command.copyData();
  first[0] = 0x5a;
  _expect(
    command.action == TerminalKittyGraphicsAction.transmit &&
        command.quiet == TerminalKittyGraphicsQuiet.replies &&
        command.transmission.format == 32 &&
        command.transmission.medium == TerminalKittyGraphicsMedium.direct &&
        command.transmission.compression ==
            TerminalKittyGraphicsCompression.none &&
        command.transmission.width == 0 &&
        command.placement.z == 0 &&
        command.deletion.selector == TerminalKittyGraphicsDeleteSelector.all &&
        ascii.decode(command.copyData()) == 'QUJD',
    'default command values and copied encoded data are immutable',
  );
}

void _testCompleteStaticControlValues() {
  final TerminalKittyGraphicsCommand command = _parse(
    'Ga=T,q=1,f=100,t=d,s=640,v=480,S=123,O=7,i=10,I=11,p=12,'
    'o=z,m=1,N=5,x=1,y=2,w=3,h=4,X=5,Y=6,c=7,r=8,C=1,U=1,'
    'z=-9,P=13,Q=14,H=-15,V=16,b=future;QUJD',
  );
  final TerminalKittyGraphicsTransmission transmission = command.transmission;
  final TerminalKittyGraphicsPlacement placement = command.placement;
  _expect(
    command.action == TerminalKittyGraphicsAction.transmitAndPlace &&
        command.quiet == TerminalKittyGraphicsQuiet.errorsOnly &&
        transmission.format == 100 &&
        transmission.medium == TerminalKittyGraphicsMedium.direct &&
        transmission.width == 640 &&
        transmission.height == 480 &&
        transmission.dataSize == 123 &&
        transmission.dataOffset == 7 &&
        transmission.imageId == 10 &&
        transmission.imageNumber == 11 &&
        transmission.placementId == 12 &&
        transmission.compression == TerminalKittyGraphicsCompression.zlib &&
        transmission.moreChunks &&
        transmission.usage == 5 &&
        placement.sourceX == 1 &&
        placement.sourceY == 2 &&
        placement.sourceWidth == 3 &&
        placement.sourceHeight == 4 &&
        placement.cellOffsetX == 5 &&
        placement.cellOffsetY == 6 &&
        placement.columns == 7 &&
        placement.rows == 8 &&
        placement.cursorMovement == 1 &&
        placement.suppressCursorMovement &&
        placement.virtual &&
        placement.z == -9 &&
        placement.parentImageId == 13 &&
        placement.parentPlacementId == 14 &&
        placement.relativeColumnOffset == -15 &&
        placement.relativeRowOffset == 16 &&
        ascii.decode(command.copyData()) == 'QUJD',
    'all static transmission and placement controls retain typed values',
  );
  _expect(
    _parse('Ga=p,i=1,C=2,U=2').placement.cursorMovement == 2 &&
        _parse('Ga=p,i=1,C=2,U=2').placement.virtual,
    'non-default placement controls survive grammar for semantic rejection',
  );
}

void _testActionsAndSelectors() {
  const Map<String, TerminalKittyGraphicsAction> actions =
      <String, TerminalKittyGraphicsAction>{
        'a': TerminalKittyGraphicsAction.controlAnimation,
        'c': TerminalKittyGraphicsAction.composeAnimation,
        'd': TerminalKittyGraphicsAction.delete,
        'f': TerminalKittyGraphicsAction.transmitAnimationFrame,
        'p': TerminalKittyGraphicsAction.place,
        'q': TerminalKittyGraphicsAction.query,
        't': TerminalKittyGraphicsAction.transmit,
        'T': TerminalKittyGraphicsAction.transmitAndPlace,
      };
  for (final MapEntry<String, TerminalKittyGraphicsAction> entry
      in actions.entries) {
    _expect(
      _parse('Ga=${entry.key}').action == entry.value,
      'action ${entry.key} has a typed value',
    );
  }
  for (final TerminalKittyGraphicsDeleteSelector selector
      in TerminalKittyGraphicsDeleteSelector.values) {
    _expect(
      _parse('Ga=d,d=${selector.wireValue}').deletion.selector == selector,
      'delete selector ${selector.wireValue} has a typed value',
    );
  }
  _expect(
    _parse('Gt=f').transmission.medium == TerminalKittyGraphicsMedium.file &&
        _parse('Gt=t').transmission.medium ==
            TerminalKittyGraphicsMedium.temporaryFile &&
        _parse('Gt=s').transmission.medium ==
            TerminalKittyGraphicsMedium.sharedMemory,
    'all documented transport media parse for later policy rejection',
  );
  _expect(
    _parse('Ga=p,t=x,o=x,m=2,d=b').action == TerminalKittyGraphicsAction.place,
    'known controls outside the selected action are ignored',
  );
}

void _testIntegerBoundariesAndRepeatedKeys() {
  final TerminalKittyGraphicsCommand command = _parse(
    'Gi=0,i=4294967295,I=4294967295,z=-2147483648,H=2147483647,'
    'V=-0,q=2',
  );
  _expect(
    command.transmission.imageId == 0xffffffff &&
        command.transmission.imageNumber == 0xffffffff &&
        command.placement.z == -0x80000000 &&
        command.placement.relativeColumnOffset == 0x7fffffff &&
        command.placement.relativeRowOffset == 0 &&
        command.quiet == TerminalKittyGraphicsQuiet.none,
    'unsigned/signed 32-bit extrema and repeated-key last value are exact',
  );
}

void _testMalformedAndBoundedCommands() {
  for (final String input in <String>[
    '',
    'X',
    'Ga=',
    'Gaa=t',
    'G1=t',
    'Ga=t,',
    'Ga=t,,q=1',
    'Ga=x',
    'Gt=x',
    'Go=x',
    'Ga=d,d=b',
    'Gq=3',
    'Gm=2',
    'Gi=-1',
    'Gi=4294967296',
    'Gz=2147483648',
    'Gz=-2147483649',
    'Gi=1x',
  ]) {
    _expectParseFailure(_bytes(input), 'malformed command $input is rejected');
  }
  _expectParseFailure(
    _bytes('Gb=${'a' * 511}'),
    'control data over 512 bytes is rejected',
    code: 'E2BIG',
  );
  _expectParseFailure(
    Uint8List.fromList(<int>[0x47, 0x3b, ...List<int>.filled(4097, 0x41)]),
    'encoded data over 4096 bytes is rejected',
    code: 'E2BIG',
  );
  _expectParseFailure(
    _bytes('G${List<String>.filled(33, 'b=0').join(',')}'),
    'more than 32 control pairs are rejected',
    code: 'E2BIG',
  );
}

void _testOuterParserEverySplitAndRecovery() {
  final Uint8List bytes = _bytes('\x1b_Ga=T,f=24,s=1,v=1,i=31,p=7;AAAA\x1b\\');
  for (int split = 0; split <= bytes.length; split++) {
    final _KittySink sink = _KittySink();
    final VtParser parser = VtParser(sink: sink);
    parser.parse(bytes, 0, split);
    parser.parse(bytes, split, bytes.length);
    parser.finish();
    _expect(
      parser.isGround &&
          sink.commands.length == 1 &&
          sink.commands.single.action ==
              TerminalKittyGraphicsAction.transmitAndPlace &&
          sink.commands.single.transmission.imageId == 31 &&
          sink.commands.single.transmission.placementId == 7,
      'Kitty APC parses identically at split $split',
    );
  }

  final _KittySink bytewiseSink = _KittySink();
  final VtParser bytewise = VtParser(sink: bytewiseSink);
  for (int index = 0; index < bytes.length; index++) {
    bytewise.parse(bytes, index, index + 1);
  }
  bytewise.finish();
  _expect(bytewiseSink.commands.length == 1, 'Kitty APC parses bytewise');

  final _KittySink cancelledSink = _KittySink();
  final VtParser cancelled = VtParser(sink: cancelledSink);
  cancelled.parse(_bytes('\x1b_Gi=7;AAAA\x18X'));
  cancelled.finish();
  _expect(
    cancelled.isGround &&
        cancelledSink.commands.isEmpty &&
        cancelledSink.cancellations == 1 &&
        cancelledSink.text.toString() == 'X',
    'cancelled graphics APC is discarded and printable parsing recovers',
  );
}

void _testDistinctApcAndGenericStringLimits() {
  final String control = 'b=${'x' * 510}';
  final Uint8List maximumApc = Uint8List.fromList(<int>[
    ..._bytes('\x1b_G$control;'),
    ...List<int>.filled(4096, 0x41),
    0x1b,
    0x5c,
  ]);
  final _KittySink acceptedSink = _KittySink();
  final VtParser accepted = VtParser(sink: acceptedSink);
  accepted.parse(maximumApc);
  accepted.finish();
  _expect(
    acceptedSink.commands.single.dataLength == 4096 && acceptedSink.limits == 0,
    'exact 4610-byte Kitty APC payload is accepted',
  );

  final _KittySink apcLimitSink = _KittySink();
  final VtParser apcLimit = VtParser(sink: apcLimitSink);
  apcLimit.parse(
    Uint8List.fromList(<int>[
      ...maximumApc.sublist(0, maximumApc.length - 2),
      0x41,
      0x1b,
      0x5c,
    ]),
  );
  apcLimit.finish();
  _expect(
    apcLimitSink.commands.isEmpty && apcLimitSink.limits == 1,
    'Kitty APC over its dedicated bound is rejected by the outer parser',
  );

  final _KittySink oscLimitSink = _KittySink();
  final VtParser oscLimit = VtParser(sink: oscLimitSink);
  oscLimit.parse(
    Uint8List.fromList(<int>[
      0x1b,
      0x5d,
      ...List<int>.filled(4097, 0x41),
      0x07,
    ]),
  );
  oscLimit.finish();
  _expect(
    oscLimitSink.oscDispatches == 0 && oscLimitSink.limits == 1,
    'raising the APC bound does not raise the generic OSC bound',
  );
}

void _testResponseEncodingAndQuietPolicy() {
  _expectBytes(
    TerminalKittyGraphicsResponseEncoder.success(
      quiet: TerminalKittyGraphicsQuiet.replies,
      imageId: 31,
      imageNumber: 9,
      placementId: 7,
    ),
    '\x1b_Gi=31,I=9,p=7;OK\x1b\\',
    'success response encodes exact identifiers and terminator',
  );
  _expectBytes(
    TerminalKittyGraphicsResponseEncoder.error(
      quiet: TerminalKittyGraphicsQuiet.errorsOnly,
      code: 'EINVAL',
      description: 'unsupported medium',
      imageId: 31,
    ),
    '\x1b_Gi=31;EINVAL:unsupported medium\x1b\\',
    'q=1 preserves bounded error responses',
  );
  _expect(
    TerminalKittyGraphicsResponseEncoder.success(
          quiet: TerminalKittyGraphicsQuiet.errorsOnly,
          imageId: 1,
        ) ==
        null,
    'q=1 suppresses successful responses',
  );
  _expect(
    TerminalKittyGraphicsResponseEncoder.error(
          quiet: TerminalKittyGraphicsQuiet.none,
          code: 'EINVAL',
          description: 'hidden',
          imageId: 1,
        ) ==
        null,
    'q=2 suppresses error responses',
  );
  _expect(
    TerminalKittyGraphicsResponseEncoder.success(
          quiet: TerminalKittyGraphicsQuiet.replies,
          placementId: 7,
        ) ==
        null,
    'a response without an image id or image number is omitted',
  );
  _expectResponseFailure(
    () => TerminalKittyGraphicsResponseEncoder.error(
      quiet: TerminalKittyGraphicsQuiet.replies,
      code: 'bad',
      description: 'message',
      imageId: 1,
    ),
    'nonconforming error codes are rejected',
  );
  _expectResponseFailure(
    () => TerminalKittyGraphicsResponseEncoder.error(
      quiet: TerminalKittyGraphicsQuiet.replies,
      code: 'E2BIG',
      description: 'x' * 161,
      imageId: 1,
    ),
    'oversized error descriptions are rejected',
  );
}

TerminalKittyGraphicsCommand _parse(String value) =>
    TerminalKittyGraphicsCommandParser.parse(_bytes(value));

Uint8List _bytes(String value) => Uint8List.fromList(ascii.encode(value));

void _expectParseFailure(Uint8List payload, String message, {String? code}) {
  try {
    TerminalKittyGraphicsCommandParser.parse(payload);
  } on TerminalKittyGraphicsParseException catch (error) {
    _expect(
      code == null || error.code == code,
      '$message has error code $code',
    );
    return;
  }
  throw StateError('test failed: $message');
}

void _expectResponseFailure(Uint8List? Function() operation, String message) {
  try {
    operation();
  } on TerminalKittyGraphicsParseException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectBytes(Uint8List? actual, String expected, String message) {
  _expect(
    actual != null && ascii.decode(actual) == expected,
    '$message: ${actual == null ? 'null' : ascii.decode(actual)}',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}

final class _KittySink implements VtParserSink {
  final List<TerminalKittyGraphicsCommand> commands =
      <TerminalKittyGraphicsCommand>[];
  final StringBuffer text = StringBuffer();
  int cancellations = 0;
  int limits = 0;
  int oscDispatches = 0;

  @override
  void print(int scalar) => text.writeCharCode(scalar);

  @override
  void execute(int controlByte) {}

  @override
  void dispatchEscape(VtEscapeSequence sequence) {}

  @override
  void dispatchCsi(VtSequenceHeader sequence) {}

  @override
  void dispatchOsc(VtStringSequence sequence) => oscDispatches++;

  @override
  void dispatchDcs(VtDcsSequence sequence) {}

  @override
  void dispatchString(VtStringSequence sequence) {
    if (sequence.kind == VtStringKind.applicationProgramCommand) {
      commands.add(
        TerminalKittyGraphicsCommandParser.parse(sequence.copyPayload()),
      );
    }
  }

  @override
  void cancel(VtParserState state, int controlByte) => cancellations++;

  @override
  void limit(VtParserState state, VtParserLimitKind kind) => limits++;

  @override
  void malformed(VtParserState state, int byte) {}

  @override
  void incomplete(VtParserState state) {}
}
