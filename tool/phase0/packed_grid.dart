import 'dart:typed_data';

const int damageMagic = 0x44475444; // "DTGD" little-endian.
const int damageVersion = 1;
const int damageHeaderBytes = 80;
const int damageRowBytes = 24;

const int cellWidthMask = 0x03;
const int cellWidthContinuation = 0;
const int cellWidthNarrow = 1;
const int cellWidthWide = 2;
const int cellFlagGrapheme = 1 << 2;
const int cellFlagProtected = 1 << 3;

const int rowFlagSoftWrapped = 1 << 0;
const int rowFlagPrompt = 1 << 1;
const int rowFlagCommand = 1 << 2;
const int rowFlagOutput = 1 << 3;
const int rowFlagHardBreak = 1 << 4;
const int rowFlagKnownMask = (1 << 5) - 1;

const int damageFlagFullSnapshot = 1 << 0;

int _align8(int value) => (value + 7) & ~7;

final class PackedGrid {
  PackedGrid({required this.rows, required this.columns})
    : cellCount = rows * columns,
      content = Uint32List(rows * columns),
      foreground = Uint32List(rows * columns),
      background = Uint32List(rows * columns),
      styles = Uint16List(rows * columns),
      links = Uint16List(rows * columns),
      widthFlags = Uint8List(rows * columns),
      rowVersions = Uint32List(rows),
      dirtyStarts = Uint16List(rows),
      dirtyEnds = Uint16List(rows),
      rowFlags = Uint8List(rows),
      logicalLineIds = Uint32List(rows),
      _packLogicalRows = Uint32List(rows),
      _packPhysicalRows = Uint32List(rows) {
    if (rows <= 0 || columns <= 0 || columns > 65534) {
      throw ArgumentError('grid dimensions must be positive; columns <= 65534');
    }
    dirtyStarts.fillRange(0, rows, columns);
  }

  final int rows;
  final int columns;
  final int cellCount;

  final Uint32List content;
  final Uint32List foreground;
  final Uint32List background;
  final Uint16List styles;
  final Uint16List links;
  final Uint8List widthFlags;

  final Uint32List rowVersions;
  final Uint16List dirtyStarts;
  final Uint16List dirtyEnds;
  final Uint8List rowFlags;
  final Uint32List logicalLineIds;

  final Uint32List _packLogicalRows;
  final Uint32List _packPhysicalRows;
  int _firstPhysicalRow = 0;
  int _nextLogicalLineId = 1;

  int get typedStorageBytes => cellCount * 17 + rows * 13;

  int physicalRow(int logicalRow) {
    if (logicalRow < 0 || logicalRow >= rows) {
      throw RangeError.range(logicalRow, 0, rows - 1, 'logicalRow');
    }
    return (_firstPhysicalRow + logicalRow) % rows;
  }

  void fillDeterministic(int seed) {
    for (int logicalRow = 0; logicalRow < rows; logicalRow++) {
      final int physical = physicalRow(logicalRow);
      final int base = physical * columns;
      for (int column = 0; column < columns; column++) {
        final int index = base + column;
        final int value = seed + logicalRow * 131 + column * 17;
        content[index] = 0x20 + (value % 95);
        foreground[index] = 0x80000000 | (value & 0x00ffffff);
        background[index] = 0x80000000 | ((value * 13) & 0x00ffffff);
        styles[index] = value & 0x03ff;
        links[index] = column % 47 == 0 ? (logicalRow % 1023) + 1 : 0;
        widthFlags[index] = cellWidthNarrow;
      }
      rowVersions[physical]++;
      logicalLineIds[physical] = _nextLogicalLineId++;
      dirtyStarts[physical] = 0;
      dirtyEnds[physical] = columns;
    }
  }

  int mutateAll(int seed) {
    int checksum = 0;
    for (int logicalRow = 0; logicalRow < rows; logicalRow++) {
      final int physical = physicalRow(logicalRow);
      final int base = physical * columns;
      for (int column = 0; column < columns; column++) {
        final int index = base + column;
        final int value = seed + index * 33;
        content[index] = 0x20 + (value % 95);
        foreground[index] = 0x80000000 | (value & 0x00ffffff);
        background[index] = 0x80000000 | ((value * 13) & 0x00ffffff);
        styles[index] = value & 0x03ff;
        links[index] = value % 61 == 0 ? value & 0xffff : 0;
        widthFlags[index] = cellWidthNarrow;
        checksum = (checksum + content[index] + styles[index]) & 0x7fffffff;
      }
      _markDirty(physical, 0, columns);
    }
    return checksum;
  }

  void updateSpans({
    required int seed,
    required int damagedRows,
    required int span,
  }) {
    if (damagedRows <= 0 || damagedRows > rows || span <= 0 || span > columns) {
      throw ArgumentError('invalid sparse damage dimensions');
    }
    for (int offset = 0; offset < damagedRows; offset++) {
      final int logicalRow = (seed * 29 + offset * 7) % rows;
      final int physical = physicalRow(logicalRow);
      final int start = (seed * 43 + offset * 11) % (columns - span + 1);
      final int base = physical * columns;
      for (int column = start; column < start + span; column++) {
        final int index = base + column;
        final int value = seed + logicalRow * 257 + column;
        content[index] = 0x20 + (value % 95);
        foreground[index] = 0x80000000 | ((value * 3) & 0x00ffffff);
        background[index] = 0x80000000 | ((value * 7) & 0x00ffffff);
        styles[index] = value & 0x03ff;
        links[index] = value % 61 == 0 ? (value & 0xffff) : 0;
        widthFlags[index] = value % 97 == 0 ? cellWidthWide : cellWidthNarrow;
      }
      _markDirty(physical, start, start + span);
    }
  }

  void scrollUp(int lineCount) {
    if (lineCount <= 0 || lineCount > rows) {
      throw RangeError.range(lineCount, 1, rows, 'lineCount');
    }
    _firstPhysicalRow = (_firstPhysicalRow + lineCount) % rows;
    for (int offset = 0; offset < lineCount; offset++) {
      final int logicalRow = rows - lineCount + offset;
      final int physical = physicalRow(logicalRow);
      final int start = physical * columns;
      final int end = start + columns;
      content.fillRange(start, end, 0x20);
      foreground.fillRange(start, end, 0);
      background.fillRange(start, end, 0);
      styles.fillRange(start, end, 0);
      links.fillRange(start, end, 0);
      widthFlags.fillRange(start, end, cellWidthNarrow);
      logicalLineIds[physical] = _nextLogicalLineId++;
      rowFlags[physical] = 0;
      _markDirty(physical, 0, columns);
    }
  }

  void markAllDirty() {
    for (int physical = 0; physical < rows; physical++) {
      _markDirty(physical, 0, columns);
    }
  }

  void clearDamage() {
    dirtyStarts.fillRange(0, rows, columns);
    dirtyEnds.fillRange(0, rows, 0);
  }

  Uint8List packDamage({
    required int generation,
    required int resourceGeneration,
    bool fullSnapshot = false,
    bool consume = true,
  }) {
    int damagedRowCount = 0;
    int damagedCellCount = 0;
    for (int logical = 0; logical < rows; logical++) {
      final int physical = physicalRow(logical);
      if (dirtyStarts[physical] >= dirtyEnds[physical]) {
        continue;
      }
      _packLogicalRows[damagedRowCount] = logical;
      _packPhysicalRows[damagedRowCount] = physical;
      damagedCellCount += dirtyEnds[physical] - dirtyStarts[physical];
      damagedRowCount++;
    }

    const int rowOffset = damageHeaderBytes;
    final int contentOffset = _align8(
      rowOffset + damagedRowCount * damageRowBytes,
    );
    final int foregroundOffset = _align8(contentOffset + damagedCellCount * 4);
    final int backgroundOffset = _align8(
      foregroundOffset + damagedCellCount * 4,
    );
    final int styleOffset = _align8(backgroundOffset + damagedCellCount * 4);
    final int linkOffset = _align8(styleOffset + damagedCellCount * 2);
    final int flagOffset = _align8(linkOffset + damagedCellCount * 2);
    final int totalBytes = _align8(flagOffset + damagedCellCount);
    final Uint8List packet = Uint8List(totalBytes);
    final ByteData header = ByteData.sublistView(packet, 0, damageHeaderBytes);
    header.setUint32(0, damageMagic, Endian.little);
    header.setUint16(4, damageVersion, Endian.little);
    header.setUint16(6, damageHeaderBytes, Endian.little);
    header.setUint64(8, generation, Endian.little);
    header.setUint64(16, resourceGeneration, Endian.little);
    header.setUint32(24, columns, Endian.little);
    header.setUint32(28, rows, Endian.little);
    header.setUint32(32, damagedRowCount, Endian.little);
    header.setUint32(36, damagedCellCount, Endian.little);
    header.setUint32(40, rowOffset, Endian.little);
    header.setUint32(44, contentOffset, Endian.little);
    header.setUint32(48, foregroundOffset, Endian.little);
    header.setUint32(52, backgroundOffset, Endian.little);
    header.setUint32(56, styleOffset, Endian.little);
    header.setUint32(60, linkOffset, Endian.little);
    header.setUint32(64, flagOffset, Endian.little);
    header.setUint32(68, totalBytes, Endian.little);
    header.setUint32(
      72,
      fullSnapshot ? damageFlagFullSnapshot : 0,
      Endian.little,
    );
    header.setUint32(76, 0, Endian.little);

    final Uint32List packedContent = Uint32List.view(
      packet.buffer,
      contentOffset,
      damagedCellCount,
    );
    final Uint32List packedForeground = Uint32List.view(
      packet.buffer,
      foregroundOffset,
      damagedCellCount,
    );
    final Uint32List packedBackground = Uint32List.view(
      packet.buffer,
      backgroundOffset,
      damagedCellCount,
    );
    final Uint16List packedStyles = Uint16List.view(
      packet.buffer,
      styleOffset,
      damagedCellCount,
    );
    final Uint16List packedLinks = Uint16List.view(
      packet.buffer,
      linkOffset,
      damagedCellCount,
    );
    final Uint8List packedFlags = Uint8List.view(
      packet.buffer,
      flagOffset,
      damagedCellCount,
    );

    final ByteData rowsView = ByteData.sublistView(
      packet,
      rowOffset,
      rowOffset + damagedRowCount * damageRowBytes,
    );
    int cellOffset = 0;
    for (int rowIndex = 0; rowIndex < damagedRowCount; rowIndex++) {
      final int logical = _packLogicalRows[rowIndex];
      final int physical = _packPhysicalRows[rowIndex];
      final int startColumn = dirtyStarts[physical];
      final int count = dirtyEnds[physical] - startColumn;
      final int record = rowIndex * damageRowBytes;
      rowsView.setUint32(record, logical, Endian.little);
      rowsView.setUint32(record + 4, rowVersions[physical], Endian.little);
      rowsView.setUint32(record + 8, logicalLineIds[physical], Endian.little);
      rowsView.setUint32(record + 12, cellOffset, Endian.little);
      rowsView.setUint16(record + 16, startColumn, Endian.little);
      rowsView.setUint16(record + 18, count, Endian.little);
      rowsView.setUint8(record + 20, rowFlags[physical]);

      final int sourceStart = physical * columns + startColumn;
      final int targetEnd = cellOffset + count;
      packedContent.setRange(cellOffset, targetEnd, content, sourceStart);
      packedForeground.setRange(cellOffset, targetEnd, foreground, sourceStart);
      packedBackground.setRange(cellOffset, targetEnd, background, sourceStart);
      packedStyles.setRange(cellOffset, targetEnd, styles, sourceStart);
      packedLinks.setRange(cellOffset, targetEnd, links, sourceStart);
      packedFlags.setRange(cellOffset, targetEnd, widthFlags, sourceStart);
      cellOffset = targetEnd;
      if (consume) {
        dirtyStarts[physical] = columns;
        dirtyEnds[physical] = 0;
      }
    }
    return packet;
  }

  void _markDirty(int physicalRow, int start, int end) {
    if (dirtyStarts[physicalRow] >= dirtyEnds[physicalRow]) {
      rowVersions[physicalRow]++;
    }
    if (start < dirtyStarts[physicalRow]) {
      dirtyStarts[physicalRow] = start;
    }
    if (end > dirtyEnds[physicalRow]) {
      dirtyEnds[physicalRow] = end;
    }
  }
}

final class DamagePacketView {
  DamagePacketView(Uint8List bytes)
    : bytes = bytes,
      _header = _checkedHeader(bytes) {
    final int expectedContentOffset = _align8(
      rowOffset + rowCount * damageRowBytes,
    );
    final int expectedForegroundOffset = _align8(
      expectedContentOffset + cellCount * 4,
    );
    final int expectedBackgroundOffset = _align8(
      expectedForegroundOffset + cellCount * 4,
    );
    final int expectedStyleOffset = _align8(
      expectedBackgroundOffset + cellCount * 4,
    );
    final int expectedLinkOffset = _align8(expectedStyleOffset + cellCount * 2);
    final int expectedFlagOffset = _align8(expectedLinkOffset + cellCount * 2);
    final int expectedTotalBytes = _align8(expectedFlagOffset + cellCount);
    if (_header.getUint32(0, Endian.little) != damageMagic ||
        _header.getUint16(4, Endian.little) != damageVersion ||
        _header.getUint16(6, Endian.little) != damageHeaderBytes ||
        generation == 0 ||
        resourceGeneration == 0 ||
        columns == 0 ||
        columns > 65534 ||
        rows == 0 ||
        rowCount > rows ||
        cellCount > rows * columns ||
        totalBytes != bytes.length ||
        rowOffset != damageHeaderBytes ||
        contentOffset != expectedContentOffset ||
        foregroundOffset != expectedForegroundOffset ||
        backgroundOffset != expectedBackgroundOffset ||
        styleOffset != expectedStyleOffset ||
        linkOffset != expectedLinkOffset ||
        flagOffset != expectedFlagOffset ||
        totalBytes != expectedTotalBytes ||
        (flags & ~damageFlagFullSnapshot) != 0 ||
        _header.getUint32(76, Endian.little) != 0) {
      throw FormatException('invalid packed damage envelope');
    }
    _validateZeroPadding(rowOffset + rowCount * damageRowBytes, contentOffset);
    _validateZeroPadding(contentOffset + cellCount * 4, foregroundOffset);
    _validateZeroPadding(foregroundOffset + cellCount * 4, backgroundOffset);
    _validateZeroPadding(backgroundOffset + cellCount * 4, styleOffset);
    _validateZeroPadding(styleOffset + cellCount * 2, linkOffset);
    _validateZeroPadding(linkOffset + cellCount * 2, flagOffset);
    _validateZeroPadding(flagOffset + cellCount, totalBytes);
    _validateRows();
  }

  final Uint8List bytes;
  final ByteData _header;

  int get generation => _header.getUint64(8, Endian.little);
  int get resourceGeneration => _header.getUint64(16, Endian.little);
  int get columns => _header.getUint32(24, Endian.little);
  int get rows => _header.getUint32(28, Endian.little);
  int get rowCount => _header.getUint32(32, Endian.little);
  int get cellCount => _header.getUint32(36, Endian.little);
  int get rowOffset => _header.getUint32(40, Endian.little);
  int get contentOffset => _header.getUint32(44, Endian.little);
  int get foregroundOffset => _header.getUint32(48, Endian.little);
  int get backgroundOffset => _header.getUint32(52, Endian.little);
  int get styleOffset => _header.getUint32(56, Endian.little);
  int get linkOffset => _header.getUint32(60, Endian.little);
  int get flagOffset => _header.getUint32(64, Endian.little);
  int get totalBytes => _header.getUint32(68, Endian.little);
  int get flags => _header.getUint32(72, Endian.little);

  static ByteData _checkedHeader(Uint8List bytes) {
    if (bytes.length < damageHeaderBytes) {
      throw FormatException('packed damage is shorter than its header');
    }
    return ByteData.sublistView(bytes, 0, damageHeaderBytes);
  }

  void _validateZeroPadding(int start, int end) {
    for (int index = start; index < end; index++) {
      if (bytes[index] != 0) {
        throw FormatException('packed damage alignment padding is nonzero');
      }
    }
  }

  void _validateRows() {
    final ByteData records = ByteData.sublistView(
      bytes,
      rowOffset,
      rowOffset + rowCount * damageRowBytes,
    );
    int expectedCellOffset = 0;
    int previousLogicalRow = -1;
    for (int index = 0; index < rowCount; index++) {
      final int record = index * damageRowBytes;
      final int logicalRow = records.getUint32(record, Endian.little);
      final int version = records.getUint32(record + 4, Endian.little);
      final int logicalLineId = records.getUint32(record + 8, Endian.little);
      final int packedCellOffset = records.getUint32(
        record + 12,
        Endian.little,
      );
      final int start = records.getUint16(record + 16, Endian.little);
      final int count = records.getUint16(record + 18, Endian.little);
      final int flags = records.getUint8(record + 20);
      if (logicalRow >= rows ||
          logicalRow <= previousLogicalRow ||
          version == 0 ||
          logicalLineId == 0 ||
          packedCellOffset != expectedCellOffset ||
          count == 0 ||
          start + count > columns ||
          (flags & ~rowFlagKnownMask) != 0 ||
          records.getUint8(record + 21) != 0 ||
          records.getUint8(record + 22) != 0 ||
          records.getUint8(record + 23) != 0) {
        throw FormatException('invalid packed damage row record $index');
      }
      previousLogicalRow = logicalRow;
      expectedCellOffset += count;
    }
    if (expectedCellOffset != cellCount) {
      throw FormatException('packed row cell counts do not match header');
    }
  }

  int sampleChecksum() {
    if (cellCount == 0) {
      return generation & 0x7fffffff;
    }
    final Uint32List contents = Uint32List.view(
      bytes.buffer,
      contentOffset,
      cellCount,
    );
    final Uint32List foregrounds = Uint32List.view(
      bytes.buffer,
      foregroundOffset,
      cellCount,
    );
    final Uint8List cellFlags = Uint8List.view(
      bytes.buffer,
      flagOffset,
      cellCount,
    );
    final int middle = cellCount ~/ 2;
    return (contents.first ^
            contents[middle] ^
            contents.last ^
            foregrounds.first ^
            foregrounds.last ^
            cellFlags[middle] ^
            generation) &
        0x7fffffff;
  }
}
