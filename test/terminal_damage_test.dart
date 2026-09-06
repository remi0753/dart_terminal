import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalDamageTests();

void runTerminalDamageTests() {
  _testFullSparseAndRingDamage();
  _testPresentationMetadataAndBell();
  _testAtomicApplicationAndGenerationOrdering();
  _testMalformedPackets();
  _testConfiguredLimits();
}

void _testPresentationMetadataAndBell() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 6);
  final TerminalDamageRenderModel model = TerminalDamageRenderModel();
  final TerminalDamagePacket full = _capture(
    screen,
    damageGeneration: 1,
    requiredResourceGeneration: 1,
  );
  _expect(
    model
        .apply(
          TerminalDamageCodec.decode(full.copyBytes()),
          availableResourceGeneration: 1,
        )
        .isApplied,
    'presentation baseline applies',
  );
  screen.acknowledgeFullSnapshot();

  screen.setCursorPosition(2, 4);
  screen.setCursorPresentation(
    shape: TerminalCursorShape.bar,
    visible: false,
    blinking: false,
  );
  final TerminalScreenParserSink sink = TerminalScreenParserSink(screen);
  sink.execute(0x07);
  sink.execute(0x07);
  _expect(
    sink.unsupportedControlCount == 0 && screen.visualBellGeneration == 2,
    'BEL advances one bounded generation and is a supported control',
  );

  final TerminalDamagePacket presentation = _capture(
    screen,
    damageGeneration: 2,
    requiredResourceGeneration: 1,
  );
  final TerminalDecodedDamage decoded = TerminalDamageCodec.decode(
    presentation.copyBytes(),
  );
  _expect(
    !presentation.isFullSnapshot &&
        presentation.damagedRowCount == 0 &&
        presentation.damagedCellCount == 0 &&
        presentation.byteLength == TerminalDamageCodec.headerBytes,
    'cursor and bell state use one canonical metadata-only packet',
  );
  _expect(
    decoded.cursorRow == 2 &&
        decoded.cursorColumn == 4 &&
        decoded.cursorShape == TerminalCursorShape.bar &&
        !decoded.cursorVisible &&
        !decoded.cursorBlinking &&
        decoded.visualBellGeneration == 2 &&
        presentation.cursorRow == decoded.cursorRow &&
        presentation.visualBellGeneration == decoded.visualBellGeneration,
    'packet and decoded metadata retain exact cursor and bell state',
  );
  _expect(
    model.apply(decoded, availableResourceGeneration: 1).isApplied &&
        model.cursorRow == 2 &&
        model.cursorColumn == 4 &&
        model.cursorShape == TerminalCursorShape.bar &&
        !model.cursorVisible &&
        !model.cursorBlinking &&
        model.visualBellGeneration == 2,
    'metadata-only damage publishes renderer presentation atomically',
  );
  _expect(
    TerminalDamageCodec.capture(
          screen,
          damageGeneration: 3,
          requiredResourceGeneration: 1,
        ) ==
        null,
    'captured presentation state does not emit duplicate packets',
  );

  final TerminalScreen regressed = TerminalScreen(rows: 3, columns: 6);
  final TerminalDamagePacket regression = _capture(
    regressed,
    damageGeneration: 3,
    requiredResourceGeneration: 1,
  );
  _expect(
    model
            .apply(
              TerminalDamageCodec.decode(regression.copyBytes()),
              availableResourceGeneration: 1,
            )
            .disposition ==
        TerminalDamageApplyDisposition.needsFullSnapshot,
    'a newer full packet cannot regress the retained bell generation',
  );
  _expect(
    model.lastDamageGeneration == 2 && model.visualBellGeneration == 2,
    'bell-generation rejection leaves the retained model unchanged',
  );

  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 4);
  screens.primary.ringVisualBell();
  screens.setAlternateMode47(true);
  _expect(
    screens.alternate.visualBellGeneration == 1,
    'alternate-screen activation inherits the session bell sequence',
  );
  screens.alternate.ringVisualBell();
  screens.setAlternateMode47(false);
  final TerminalScreen resized = screens.primary.resized(rows: 3, columns: 5);
  _expect(
    screens.primary.visualBellGeneration == 2 &&
        resized.visualBellGeneration == 2,
    'buffer switches and reflow preserve monotonic bell generation',
  );
}

void _testFullSparseAndRingDamage() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 6);
  screen.setNarrowCell(
    0,
    1,
    0x41,
    foreground: 7,
    background: 0x80010203,
    style: 11,
    hyperlink: 13,
    isProtected: true,
  );
  screen.setWideCell(
    1,
    2,
    0x754c,
    foreground: 256,
    background: 4,
    style: 17,
    hyperlink: 19,
  );
  screen.setRowFlags(1, TerminalRowFlags.softWrapped | TerminalRowFlags.output);
  screen.setLogicalLineId(1, 400);
  final int graphemeId = screen.graphemeTable.intern(const <int>[0x41, 0x0301]);
  screen.setGraphemeCell(2, 0, graphemeId, foreground: 9);

  final TerminalDamagePacket full = _capture(
    screen,
    damageGeneration: 1,
    requiredResourceGeneration: 7,
  );
  _expect(full.isFullSnapshot, 'first capture is a full snapshot');
  _expect(full.damagedRowCount == 3, 'full snapshot contains every row');
  _expect(full.damagedCellCount == 18, 'full snapshot contains every cell');
  _expect(
    !screen.isRowDirty(0) && !screen.isRowDirty(1) && !screen.isRowDirty(2),
    'capture clears only the copied dirty intervals',
  );
  _expect(
    screen.fullSnapshotRequired,
    'capture does not acknowledge a full snapshot',
  );

  final Uint8List transportBytes = full.copyBytes();
  final TerminalDecodedDamage decoded = TerminalDamageCodec.decode(
    transportBytes,
    expectedResourceGeneration: 7,
  );
  final int retainedFirstContent = decoded.contentAt(0);
  transportBytes[decoded.contentOffset] ^= 0xff;
  _expect(
    decoded.contentAt(0) == retainedFirstContent,
    'decoder owns a copy independent from transport bytes',
  );
  _expect(decoded.rowRecords[1].row == 1, 'full rows remain ordered');
  _expect(
    decoded.rowRecords[1].firstCell == 6 &&
        decoded.rowRecords[1].firstColumn == 0 &&
        decoded.rowRecords[1].cellCount == 6,
    'row records point at canonical packed spans',
  );

  final TerminalDamageRenderModel model = TerminalDamageRenderModel();
  final TerminalDamageApplyResult fullResult = model.apply(
    decoded,
    availableResourceGeneration: 7,
  );
  _expect(fullResult.isApplied, 'valid full snapshot applies');
  _expect(
    fullResult.acceptedBytes == full.byteLength,
    'accepted full snapshot reports its exact bytes',
  );
  _expect(model.contentAt(0, 1) == 0x41, 'narrow content is retained');
  _expect(
    model.foregroundAt(0, 1) == 7 &&
        model.backgroundAt(0, 1) == 0x80010203 &&
        model.styleAt(0, 1) == 11 &&
        model.hyperlinkAt(0, 1) == 13 &&
        model.widthFlagsAt(0, 1) ==
            (TerminalCellFlags.narrow | TerminalCellFlags.protected),
    'every narrow packed field is retained',
  );
  _expect(
    model.contentAt(1, 2) == 0x754c &&
        model.widthFlagsAt(1, 2) == TerminalCellFlags.wide &&
        model.widthFlagsAt(1, 3) == TerminalCellFlags.continuation,
    'wide topology is retained',
  );
  _expect(
    model.contentAt(2, 0) == graphemeId &&
        model.widthFlagsAt(2, 0) ==
            (TerminalCellFlags.narrow | TerminalCellFlags.grapheme),
    'grapheme resource references are retained without object sharing',
  );
  _expect(
    model.rowFlagsAt(1) ==
            (TerminalRowFlags.softWrapped | TerminalRowFlags.output) &&
        model.logicalLineIdAt(1) == 400,
    'row metadata is retained',
  );

  screen.acknowledgeFullSnapshot();
  final int previousRowVersion = model.rowVersionAt(0);
  screen.setNarrowCell(0, 4, 0x42);
  screen.setNarrowCell(0, 2, 0x43);
  final TerminalDamagePacket sparse = _capture(
    screen,
    damageGeneration: 2,
    requiredResourceGeneration: 7,
  );
  final TerminalDecodedDamage sparseDecoded = TerminalDamageCodec.decode(
    sparse.copyBytes(),
  );
  _expect(!sparse.isFullSnapshot, 'normal output uses incremental damage');
  _expect(
    sparse.damagedRowCount == 1 && sparse.damagedCellCount == 3,
    'disjoint row edits coalesce into one bounded interval',
  );
  _expect(
    sparseDecoded.rowRecords.single.firstColumn == 2 &&
        sparseDecoded.rowRecords.single.cellCount == 3 &&
        sparseDecoded.rowRecords.single.rowVersion == previousRowVersion + 1,
    'coalesced interval carries exactly one row-version step',
  );
  _expect(
    model.apply(sparseDecoded, availableResourceGeneration: 7).isApplied,
    'consecutive sparse damage applies',
  );
  _expect(
    model.contentAt(0, 2) == 0x43 &&
        model.contentAt(0, 3) == 0 &&
        model.contentAt(0, 4) == 0x42,
    'coalesced span includes the unchanged interior without altering it',
  );
  _expect(
    TerminalDamageCodec.capture(
          screen,
          damageGeneration: 3,
          requiredResourceGeneration: 7,
        ) ==
        null,
    'clean incremental state emits no packet',
  );

  final TerminalScreen ring = TerminalScreen(rows: 3, columns: 2);
  ring.setNarrowCell(0, 0, 0x41);
  ring.setNarrowCell(1, 0, 0x42);
  ring.setNarrowCell(2, 0, 0x43);
  ring.setRowFlags(1, TerminalRowFlags.output);
  ring.clearDamage();
  ring.setNarrowCell(0, 1, 0x58);
  final int movedLogicalLine = ring.logicalLineIdAt(1);
  final TerminalDamageRenderModel ringModel = TerminalDamageRenderModel();
  final TerminalDamagePacket ringFull = _capture(
    ring,
    damageGeneration: 1,
    requiredResourceGeneration: 1,
  );
  _expect(
    ringModel
        .apply(
          TerminalDamageCodec.decode(ringFull.copyBytes()),
          availableResourceGeneration: 1,
        )
        .isApplied,
    'ring baseline applies',
  );
  ring.acknowledgeFullSnapshot();
  ring.setNarrowCell(2, 1, 0x59);
  ring.scrollUp(1);
  final TerminalDamagePacket ringDelta = _capture(
    ring,
    damageGeneration: 2,
    requiredResourceGeneration: 1,
  );
  final TerminalDecodedDamage ringDecoded = TerminalDamageCodec.decode(
    ringDelta.copyBytes(),
  );
  _expect(
    !ringDelta.isFullSnapshot && ringDecoded.rowRecords.length == 3,
    'ring rotation publishes every logically moved viewport row as a delta',
  );
  _expect(
    ringModel.apply(ringDecoded, availableResourceGeneration: 1).isApplied,
    'ring rotation delta advances logical rather than physical row versions',
  );
  _expect(
    ringModel.contentAt(0, 0) == 0x42 &&
        ringModel.contentAt(1, 0) == 0x43 &&
        ringModel.contentAt(1, 1) == 0x59 &&
        ringModel.contentAt(2, 0) == 0 &&
        ringModel.rowFlagsAt(0) == TerminalRowFlags.output &&
        ringModel.logicalLineIdAt(0) == movedLogicalLine,
    'pre-scroll dirty content follows physical ring reuse without moving its '
    'damage metadata to another logical row',
  );
}

void _testAtomicApplicationAndGenerationOrdering() {
  final TerminalScreen screen = TerminalScreen(rows: 2, columns: 5);
  screen.setNarrowCell(0, 0, 0x41);
  final TerminalDamagePacket full = _capture(
    screen,
    damageGeneration: 1,
    requiredResourceGeneration: 5,
  );
  final TerminalDecodedDamage fullDecoded = TerminalDamageCodec.decode(
    full.copyBytes(),
  );
  final TerminalDamageRenderModel model = TerminalDamageRenderModel();
  _expect(
    model.apply(fullDecoded, availableResourceGeneration: 5).isApplied,
    'ordering baseline applies',
  );
  screen.acknowledgeFullSnapshot();

  screen.setNarrowCell(0, 4, 0x51);
  screen.setWideCell(1, 1, 0x754c);
  final TerminalDamagePacket wide = _capture(
    screen,
    damageGeneration: 2,
    requiredResourceGeneration: 5,
  );
  final Uint8List malformedTopology = wide.copyBytes();
  final TerminalDecodedDamage wideDecoded = TerminalDamageCodec.decode(
    malformedTopology,
  );
  final TerminalDamageRowRecord wideRow = wideDecoded.rowRecords[1];
  malformedTopology[wideDecoded.widthFlagsOffset + wideRow.firstCell + 1] =
      TerminalCellFlags.narrow;
  final TerminalDecodedDamage invalidDecoded = TerminalDamageCodec.decode(
    malformedTopology,
  );
  final int generationBeforeInvalid = model.lastDamageGeneration;
  final int firstRowContentBeforeInvalid = model.contentAt(0, 4);
  final int secondRowContentBeforeInvalid = model.contentAt(1, 1);
  final TerminalDamageApplyResult invalidResult = model.apply(
    invalidDecoded,
    availableResourceGeneration: 5,
  );
  _expect(
    invalidResult.disposition == TerminalDamageApplyDisposition.invalid &&
        invalidResult.acceptedBytes == 0,
    'cross-cell topology violation is rejected',
  );
  _expect(
    model.lastDamageGeneration == generationBeforeInvalid &&
        model.contentAt(0, 4) == firstRowContentBeforeInvalid &&
        model.contentAt(1, 1) == secondRowContentBeforeInvalid,
    'later invalid row publishes neither itself nor an earlier staged row',
  );
  _expect(
    model.apply(wideDecoded, availableResourceGeneration: 5).isApplied,
    'valid packet still applies after atomic rejection',
  );
  _expect(
    model.contentAt(0, 4) == 0x51 && model.contentAt(1, 1) == 0x754c,
    'valid multi-row packet publishes every staged row together',
  );
  _expect(
    model.apply(wideDecoded, availableResourceGeneration: 5).disposition ==
        TerminalDamageApplyDisposition.stale,
    'duplicate generation is stale',
  );

  screen.setNarrowCell(1, 4, 0x58);
  final TerminalDamagePacket resourceAhead = _capture(
    screen,
    damageGeneration: 3,
    requiredResourceGeneration: 9,
  );
  final TerminalDecodedDamage resourceDecoded = TerminalDamageCodec.decode(
    resourceAhead.copyBytes(),
  );
  _expect(
    model.apply(resourceDecoded, availableResourceGeneration: 8).disposition ==
        TerminalDamageApplyDisposition.resourceUnavailable,
    'damage waits for its required resource generation',
  );
  _expect(model.lastDamageGeneration == 2, 'resource wait does not advance');
  _expect(
    model.apply(resourceDecoded, availableResourceGeneration: 9).isApplied,
    'damage applies once resources are available',
  );

  screen.setNarrowCell(1, 3, 0x59);
  final TerminalDamagePacket future = _capture(
    screen,
    damageGeneration: 5,
    requiredResourceGeneration: 9,
  );
  _expect(
    model
            .apply(
              TerminalDamageCodec.decode(future.copyBytes()),
              availableResourceGeneration: 9,
            )
            .disposition ==
        TerminalDamageApplyDisposition.needsFullSnapshot,
    'incremental generation gap requires a full snapshot',
  );
  _expect(model.lastDamageGeneration == 3, 'gap rejection is atomic');

  screen.requestFullSnapshot();
  final TerminalDamagePacket replacement = _capture(
    screen,
    damageGeneration: 6,
    requiredResourceGeneration: 10,
  );
  _expect(
    model
        .apply(
          TerminalDamageCodec.decode(replacement.copyBytes()),
          availableResourceGeneration: 10,
        )
        .isApplied,
    'newer full snapshot explicitly supersedes a generation gap',
  );
  _expect(
    model.lastDamageGeneration == 6 && model.contentAt(1, 3) == 0x59,
    'replacement publishes the complete newest model',
  );

  final TerminalScreen olderResources = TerminalScreen(rows: 2, columns: 5);
  olderResources.setNarrowCell(0, 0, 0x5a);
  final TerminalDamagePacket resourceRegression = _capture(
    olderResources,
    damageGeneration: 7,
    requiredResourceGeneration: 9,
  );
  _expect(
    model
            .apply(
              TerminalDamageCodec.decode(resourceRegression.copyBytes()),
              availableResourceGeneration: 10,
            )
            .disposition ==
        TerminalDamageApplyDisposition.needsFullSnapshot,
    'even a full snapshot cannot regress retained resource generation',
  );
}

void _testMalformedPackets() {
  final TerminalScreen screen = TerminalScreen(rows: 3, columns: 6);
  screen.setNarrowCell(0, 0, 0x41, foreground: 1, style: 2);
  screen.setWideCell(1, 2, 0x754c);
  final TerminalDamagePacket packet = _capture(
    screen,
    damageGeneration: 4,
    requiredResourceGeneration: 3,
  );
  final TerminalDecodedDamage canonical = TerminalDamageCodec.decode(
    packet.copyBytes(),
    expectedResourceGeneration: 3,
  );

  _expectFormat(
    () => TerminalDamageCodec.decode(
      Uint8List(TerminalDamageCodec.headerBytes - 1),
    ),
    'truncated header',
  );
  _expectFormat(
    () => TerminalDamageCodec.decode(
      packet.copyBytes().sublist(0, packet.byteLength - 1),
    ),
    'truncated payload',
  );
  final Uint8List trailing = Uint8List(packet.byteLength + 1);
  trailing.setRange(0, packet.byteLength, packet.copyBytes());
  _expectFormat(() => TerminalDamageCodec.decode(trailing), 'trailing payload');
  _expectFormat(
    () => TerminalDamageCodec.decode(
      packet.copyBytes(),
      expectedResourceGeneration: 2,
    ),
    'resource-generation mismatch',
  );

  final List<_Corruption> corruptions = <_Corruption>[
    _Corruption('magic', (ByteData data, Uint8List _) => data.setUint32(0, 0)),
    _Corruption(
      'version',
      (ByteData data, Uint8List _) => data.setUint16(4, 1, Endian.little),
    ),
    _Corruption(
      'header length',
      (ByteData data, Uint8List _) => data.setUint16(6, 72, Endian.little),
    ),
    _Corruption(
      'zero damage generation',
      (ByteData data, Uint8List _) => data.setUint64(8, 0, Endian.little),
    ),
    _Corruption(
      'zero resource generation',
      (ByteData data, Uint8List _) => data.setUint64(16, 0, Endian.little),
    ),
    _Corruption(
      'zero columns',
      (ByteData data, Uint8List _) => data.setUint32(24, 0, Endian.little),
    ),
    _Corruption(
      'excess rows',
      (ByteData data, Uint8List _) => data.setUint32(28, 4097, Endian.little),
    ),
    _Corruption(
      'row count',
      (ByteData data, Uint8List _) => data.setUint32(32, 4, Endian.little),
    ),
    _Corruption(
      'cell count',
      (ByteData data, Uint8List _) => data.setUint32(36, 17, Endian.little),
    ),
    _Corruption(
      'row offset',
      (ByteData data, Uint8List _) => data.setUint32(40, 112, Endian.little),
    ),
    _Corruption(
      'content offset',
      (ByteData data, Uint8List _) => data.setUint32(44, 160, Endian.little),
    ),
    _Corruption(
      'foreground offset',
      (ByteData data, Uint8List _) => data.setUint32(48, 232, Endian.little),
    ),
    _Corruption(
      'background offset',
      (ByteData data, Uint8List _) => data.setUint32(52, 304, Endian.little),
    ),
    _Corruption(
      'style offset',
      (ByteData data, Uint8List _) => data.setUint32(56, 376, Endian.little),
    ),
    _Corruption(
      'hyperlink offset',
      (ByteData data, Uint8List _) => data.setUint32(60, 416, Endian.little),
    ),
    _Corruption(
      'width offset',
      (ByteData data, Uint8List _) => data.setUint32(64, 456, Endian.little),
    ),
    _Corruption(
      'total bytes',
      (ByteData data, Uint8List bytes) =>
          data.setUint32(68, bytes.length - 1, Endian.little),
    ),
    _Corruption(
      'unknown header flag',
      (ByteData data, Uint8List _) => data.setUint32(72, 2, Endian.little),
    ),
    _Corruption(
      'cursor row',
      (ByteData data, Uint8List _) => data.setUint32(76, 3, Endian.little),
    ),
    _Corruption(
      'cursor column',
      (ByteData data, Uint8List _) => data.setUint32(80, 6, Endian.little),
    ),
    _Corruption(
      'cursor shape',
      (ByteData data, Uint8List _) => data.setUint32(84, 3, Endian.little),
    ),
    _Corruption(
      'unknown cursor flag',
      (ByteData data, Uint8List _) => data.setUint32(84, 1 << 10),
    ),
    _Corruption(
      'bell generation',
      (ByteData data, Uint8List _) =>
          data.setUint64(88, 0xffffffffffffffff, Endian.little),
    ),
    _Corruption(
      'header reserved',
      (ByteData data, Uint8List _) => data.setUint64(96, 1, Endian.little),
    ),
    _Corruption(
      'duplicate row',
      (ByteData data, Uint8List _) => data.setUint32(
        TerminalDamageCodec.headerBytes + 24,
        0,
        Endian.little,
      ),
    ),
    _Corruption(
      'zero logical line',
      (ByteData data, Uint8List _) =>
          data.setUint32(TerminalDamageCodec.headerBytes + 8, 0, Endian.little),
    ),
    _Corruption(
      'noncontiguous cells',
      (ByteData data, Uint8List _) => data.setUint32(
        TerminalDamageCodec.headerBytes + 24 + 12,
        7,
        Endian.little,
      ),
    ),
    _Corruption(
      'out-of-range span',
      (ByteData data, Uint8List _) => data.setUint16(
        TerminalDamageCodec.headerBytes + 16,
        6,
        Endian.little,
      ),
    ),
    _Corruption(
      'unknown row flag',
      (ByteData data, Uint8List _) =>
          data.setUint8(TerminalDamageCodec.headerBytes + 20, 0x80),
    ),
    _Corruption(
      'row reserved',
      (ByteData data, Uint8List _) =>
          data.setUint8(TerminalDamageCodec.headerBytes + 21, 1),
    ),
    _Corruption(
      'style reserved ID',
      (ByteData data, Uint8List _) =>
          data.setUint16(canonical.styleOffset, 0xffff, Endian.little),
    ),
    _Corruption(
      'hyperlink reserved ID',
      (ByteData data, Uint8List _) =>
          data.setUint16(canonical.hyperlinkOffset, 0xffff, Endian.little),
    ),
    _Corruption(
      'invalid color',
      (ByteData data, Uint8List _) =>
          data.setUint32(canonical.foregroundOffset, 0x40000000, Endian.little),
    ),
    _Corruption(
      'direct color reserved bits',
      (ByteData data, Uint8List _) =>
          data.setUint32(canonical.backgroundOffset, 0x81000000, Endian.little),
    ),
    _Corruption(
      'invalid width bits',
      (ByteData _, Uint8List bytes) =>
          bytes[canonical.widthFlagsOffset] = TerminalCellFlags.widthMask,
    ),
    _Corruption(
      'unknown cell flag',
      (ByteData _, Uint8List bytes) => bytes[canonical.widthFlagsOffset] = 0x10,
    ),
    _Corruption(
      'blank wide lead',
      (ByteData _, Uint8List bytes) =>
          bytes[canonical.widthFlagsOffset + 1] = TerminalCellFlags.wide,
    ),
    _Corruption(
      'blank grapheme',
      (ByteData _, Uint8List bytes) => bytes[canonical.widthFlagsOffset + 1] =
          TerminalCellFlags.narrow | TerminalCellFlags.grapheme,
    ),
    _Corruption('grapheme ID out of range', (ByteData data, Uint8List bytes) {
      data.setUint32(canonical.contentOffset + 4, 0xffff, Endian.little);
      bytes[canonical.widthFlagsOffset + 1] =
          TerminalCellFlags.narrow | TerminalCellFlags.grapheme;
    }),
    _Corruption(
      'surrogate scalar',
      (ByteData data, Uint8List _) =>
          data.setUint32(canonical.contentOffset, 0xd800, Endian.little),
    ),
    _Corruption(
      'continuation content',
      (ByteData data, Uint8List _) =>
          data.setUint32(canonical.contentOffset + 9 * 4, 0x41, Endian.little),
    ),
    _Corruption(
      'scalar width mismatch',
      (ByteData data, Uint8List _) =>
          data.setUint32(canonical.contentOffset, 0x754c, Endian.little),
    ),
  ];
  for (final _Corruption corruption in corruptions) {
    final Uint8List bytes = packet.copyBytes();
    corruption.mutate(ByteData.sublistView(bytes), bytes);
    _expectFormat(
      () => TerminalDamageCodec.decode(bytes),
      corruption.description,
    );
  }

  final int stylePadding =
      canonical.styleOffset +
      canonical.damagedCellCount * Uint16List.bytesPerElement;
  _expect(
    stylePadding < canonical.hyperlinkOffset,
    'fixture has style padding',
  );
  final Uint8List padded = packet.copyBytes();
  padded[stylePadding] = 1;
  _expectFormat(
    () => TerminalDamageCodec.decode(padded),
    'nonzero section padding',
  );
}

void _testConfiguredLimits() {
  final TerminalScreen tooManyCells = TerminalScreen(rows: 2, columns: 3);
  _expectState(
    () => TerminalDamageCodec.capture(
      tooManyCells,
      damageGeneration: 1,
      requiredResourceGeneration: 1,
      limits: const TerminalDamageLimits(maximumCells: 5),
    ),
    'capture enforces configured cell limit before allocation',
  );
  _expect(
    tooManyCells.fullSnapshotRequired,
    'failed bounded capture leaves resync state intact',
  );

  final TerminalScreen packetTooLarge = TerminalScreen(rows: 1, columns: 1);
  _expectState(
    () => TerminalDamageCodec.capture(
      packetTooLarge,
      damageGeneration: 1,
      requiredResourceGeneration: 1,
      limits: const TerminalDamageLimits(maximumPacketBytes: 160),
    ),
    'capture enforces packet byte limit before publication',
  );
  _expect(
    packetTooLarge.fullSnapshotRequired,
    'failed packet-size capture remains eligible for a full retry',
  );
  final TerminalDamagePacket blank = _capture(
    packetTooLarge,
    damageGeneration: 1,
    requiredResourceGeneration: 1,
  );
  final TerminalDecodedDamage blankDecoded = TerminalDamageCodec.decode(
    blank.copyBytes(),
  );
  _expect(
    blankDecoded.rowRecords.single.rowVersion == 0 &&
        TerminalDamageRenderModel()
            .apply(blankDecoded, availableResourceGeneration: 1)
            .isApplied,
    'an untouched initial row version zero is valid in a full snapshot',
  );

  final TerminalDamagePacket packet = _capture(
    tooManyCells,
    damageGeneration: 1,
    requiredResourceGeneration: 1,
  );
  _expectFormat(
    () => TerminalDamageCodec.decode(
      packet.copyBytes(),
      limits: const TerminalDamageLimits(maximumRows: 1),
    ),
    'decode enforces configured dimension limit before typed allocation',
  );
  _expectFormat(
    () => TerminalDamageCodec.decode(
      packet.copyBytes(),
      limits: const TerminalDamageLimits(maximumPacketBytes: 160),
    ),
    'decode enforces configured packet byte limit',
  );
  _expectRange(
    () =>
        const TerminalDamageLimits(maximumPacketBytes: 32 * 1024 * 1024 + 1)
            .validate(),
    'configured packet cap cannot exceed the 32 MiB wire limit',
  );
}

TerminalDamagePacket _capture(
  TerminalScreen screen, {
  required int damageGeneration,
  required int requiredResourceGeneration,
}) {
  final TerminalDamagePacket? packet = TerminalDamageCodec.capture(
    screen,
    damageGeneration: damageGeneration,
    requiredResourceGeneration: requiredResourceGeneration,
  );
  if (packet == null) throw StateError('test expected damage packet');
  return packet;
}

final class _Corruption {
  const _Corruption(this.description, this.mutate);

  final String description;
  final void Function(ByteData data, Uint8List bytes) mutate;
}

void _expectFormat(void Function() action, String message) {
  try {
    action();
  } on TerminalDamageFormatException {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectState(void Function() action, String message) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expectRange(void Function() action, String message) {
  try {
    action();
  } on RangeError {
    return;
  }
  throw StateError('test failed: $message');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
