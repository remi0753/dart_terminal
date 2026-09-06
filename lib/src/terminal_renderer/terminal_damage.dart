import 'dart:typed_data';

import '../terminal_core/terminal_screen.dart';
import '../terminal_core/terminal_unicode.dart';
import 'terminal_render_model.dart';

final class TerminalDamageFormatException implements Exception {
  const TerminalDamageFormatException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDamageFormatException: $message';
}

final class TerminalDamageLimits {
  const TerminalDamageLimits({
    this.maximumColumns = TerminalScreen.maxColumns,
    this.maximumRows = TerminalScreen.maxRows,
    this.maximumCells = TerminalScreen.maxCellCount,
    this.maximumPacketBytes = 32 * 1024 * 1024,
  });

  final int maximumColumns;
  final int maximumRows;
  final int maximumCells;
  final int maximumPacketBytes;

  void validate() {
    RangeError.checkValueInInterval(
      maximumColumns,
      1,
      TerminalScreen.maxColumns,
      'maximumColumns',
    );
    RangeError.checkValueInInterval(
      maximumRows,
      1,
      TerminalScreen.maxRows,
      'maximumRows',
    );
    RangeError.checkValueInInterval(
      maximumCells,
      1,
      TerminalScreen.maxCellCount,
      'maximumCells',
    );
    RangeError.checkValueInInterval(
      maximumPacketBytes,
      TerminalDamageCodec.headerBytes,
      32 * 1024 * 1024,
      'maximumPacketBytes',
    );
  }
}

final class TerminalDamagePacket {
  TerminalDamagePacket._({
    required this.damageGeneration,
    required this.requiredResourceGeneration,
    required this.columns,
    required this.rows,
    required this.damagedRowCount,
    required this.damagedCellCount,
    required this.isFullSnapshot,
    required this.cursorRow,
    required this.cursorColumn,
    required this.cursorShape,
    required this.cursorVisible,
    required this.cursorBlinking,
    required this.visualBellGeneration,
    required Uint8List bytes,
  }) : _bytes = bytes;

  final int damageGeneration;
  final int requiredResourceGeneration;
  final int columns;
  final int rows;
  final int damagedRowCount;
  final int damagedCellCount;
  final bool isFullSnapshot;
  final int cursorRow;
  final int cursorColumn;
  final TerminalCursorShape cursorShape;
  final bool cursorVisible;
  final bool cursorBlinking;
  final int visualBellGeneration;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}

final class TerminalDamageRowRecord {
  const TerminalDamageRowRecord({
    required this.row,
    required this.rowVersion,
    required this.logicalLineId,
    required this.firstCell,
    required this.firstColumn,
    required this.cellCount,
    required this.rowFlags,
  });

  final int row;
  final int rowVersion;
  final int logicalLineId;
  final int firstCell;
  final int firstColumn;
  final int cellCount;
  final int rowFlags;
}

final class TerminalDecodedDamage {
  TerminalDecodedDamage._({
    required this.damageGeneration,
    required this.requiredResourceGeneration,
    required this.columns,
    required this.rows,
    required this.isFullSnapshot,
    required this.cursorRow,
    required this.cursorColumn,
    required this.cursorShape,
    required this.cursorVisible,
    required this.cursorBlinking,
    required this.visualBellGeneration,
    required this.rowRecordsOffset,
    required this.contentOffset,
    required this.foregroundOffset,
    required this.backgroundOffset,
    required this.styleOffset,
    required this.hyperlinkOffset,
    required this.widthFlagsOffset,
    required List<TerminalDamageRowRecord> rowRecords,
    required Uint32List content,
    required Uint32List foreground,
    required Uint32List background,
    required Uint16List styles,
    required Uint16List hyperlinks,
    required Uint8List widthFlags,
    required Uint8List bytes,
  }) : rowRecords = List<TerminalDamageRowRecord>.unmodifiable(rowRecords),
       _content = content,
       _foreground = foreground,
       _background = background,
       _styles = styles,
       _hyperlinks = hyperlinks,
       _widthFlags = widthFlags,
       _bytes = bytes;

  final int damageGeneration;
  final int requiredResourceGeneration;
  final int columns;
  final int rows;
  final bool isFullSnapshot;
  final int cursorRow;
  final int cursorColumn;
  final TerminalCursorShape cursorShape;
  final bool cursorVisible;
  final bool cursorBlinking;
  final int visualBellGeneration;
  final int rowRecordsOffset;
  final int contentOffset;
  final int foregroundOffset;
  final int backgroundOffset;
  final int styleOffset;
  final int hyperlinkOffset;
  final int widthFlagsOffset;
  final List<TerminalDamageRowRecord> rowRecords;
  final Uint32List _content;
  final Uint32List _foreground;
  final Uint32List _background;
  final Uint16List _styles;
  final Uint16List _hyperlinks;
  final Uint8List _widthFlags;
  final Uint8List _bytes;

  int get damagedRowCount => rowRecords.length;
  int get damagedCellCount => _content.length;
  int get byteLength => _bytes.length;

  int contentAt(int packedCell) => _content[packedCell];
  int foregroundAt(int packedCell) => _foreground[packedCell];
  int backgroundAt(int packedCell) => _background[packedCell];
  int styleAt(int packedCell) => _styles[packedCell];
  int hyperlinkAt(int packedCell) => _hyperlinks[packedCell];
  int widthFlagsAt(int packedCell) => _widthFlags[packedCell];
  Uint8List copyBytes() => Uint8List.fromList(_bytes);
}

abstract final class TerminalDamageCodec {
  static const int magic = 0x44475444;
  static const int version = 2;
  static const int headerBytes = 104;
  static const int rowRecordBytes = 24;
  static const int cursorShapeMask = 0x3;
  static const int cursorVisibleFlag = 1 << 8;
  static const int cursorBlinkingFlag = 1 << 9;
  static const int cursorKnownMask =
      cursorShapeMask | cursorVisibleFlag | cursorBlinkingFlag;

  /// Copies the current full/dirty screen state and then clears only the
  /// captured dirty intervals. A full-snapshot requirement remains set until a
  /// later renderer acknowledgement.
  static TerminalDamagePacket? capture(
    TerminalScreen screen, {
    required int damageGeneration,
    required int requiredResourceGeneration,
    TerminalDamageLimits limits = const TerminalDamageLimits(),
  }) {
    limits.validate();
    _requireGeneration(damageGeneration, 'damageGeneration');
    _requireGeneration(
      requiredResourceGeneration,
      'requiredResourceGeneration',
    );
    _validateDimensions(screen.columns, screen.rows, limits);
    final bool full = screen.fullSnapshotRequired;
    final List<_CaptureRow> rows = <_CaptureRow>[];
    var cellCount = 0;
    for (int row = 0; row < screen.rows; row++) {
      final int start = full ? 0 : screen.dirtyStartAt(row);
      final int end = full ? screen.columns : screen.dirtyEndAt(row);
      if (start >= end) continue;
      rows.add(_CaptureRow(row, start, end));
      cellCount += end - start;
    }
    if (rows.isEmpty && !screen.presentationDamageRequired) return null;
    final _DamageLayout layout = _DamageLayout.compute(rows.length, cellCount);
    if (layout.totalBytes > limits.maximumPacketBytes) {
      throw StateError('damage packet byte limit exceeded');
    }
    final Uint8List bytes = Uint8List(layout.totalBytes);
    final ByteData data = ByteData.sublistView(bytes);
    data.setUint32(0, magic, Endian.little);
    data.setUint16(4, version, Endian.little);
    data.setUint16(6, headerBytes, Endian.little);
    data.setUint64(8, damageGeneration, Endian.little);
    data.setUint64(16, requiredResourceGeneration, Endian.little);
    data.setUint32(24, screen.columns, Endian.little);
    data.setUint32(28, screen.rows, Endian.little);
    data.setUint32(32, rows.length, Endian.little);
    data.setUint32(36, cellCount, Endian.little);
    data.setUint32(40, headerBytes, Endian.little);
    data.setUint32(44, layout.contentOffset, Endian.little);
    data.setUint32(48, layout.foregroundOffset, Endian.little);
    data.setUint32(52, layout.backgroundOffset, Endian.little);
    data.setUint32(56, layout.styleOffset, Endian.little);
    data.setUint32(60, layout.hyperlinkOffset, Endian.little);
    data.setUint32(64, layout.widthFlagsOffset, Endian.little);
    data.setUint32(68, layout.totalBytes, Endian.little);
    data.setUint32(72, full ? 1 : 0, Endian.little);
    data.setUint32(76, screen.cursorRow, Endian.little);
    data.setUint32(80, screen.cursorColumn, Endian.little);
    data.setUint32(
      84,
      screen.cursorShape.index |
          (screen.cursorVisible ? cursorVisibleFlag : 0) |
          (screen.cursorBlinking ? cursorBlinkingFlag : 0),
      Endian.little,
    );
    data.setUint64(88, screen.visualBellGeneration, Endian.little);
    final Uint32List content = Uint32List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.contentOffset,
      cellCount,
    );
    final Uint32List foreground = Uint32List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.foregroundOffset,
      cellCount,
    );
    final Uint32List background = Uint32List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.backgroundOffset,
      cellCount,
    );
    final Uint16List styles = Uint16List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.styleOffset,
      cellCount,
    );
    final Uint16List hyperlinks = Uint16List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.hyperlinkOffset,
      cellCount,
    );
    final Uint8List widthFlags = Uint8List.view(
      bytes.buffer,
      bytes.offsetInBytes + layout.widthFlagsOffset,
      cellCount,
    );
    var packedCell = 0;
    for (int index = 0; index < rows.length; index++) {
      final _CaptureRow captured = rows[index];
      final int record = headerBytes + index * rowRecordBytes;
      final int count = captured.end - captured.start;
      data.setUint32(record, captured.row, Endian.little);
      data.setUint32(
        record + 4,
        screen.rowVersionAt(captured.row),
        Endian.little,
      );
      data.setUint32(
        record + 8,
        screen.logicalLineIdAt(captured.row),
        Endian.little,
      );
      data.setUint32(record + 12, packedCell, Endian.little);
      data.setUint16(record + 16, captured.start, Endian.little);
      data.setUint16(record + 18, count, Endian.little);
      data.setUint8(record + 20, screen.rowFlagsAt(captured.row));
      screen.copyPackedCellSpanTo(
        row: captured.row,
        firstColumn: captured.start,
        cellCount: count,
        destinationOffset: packedCell,
        content: content,
        foreground: foreground,
        background: background,
        styles: styles,
        hyperlinks: hyperlinks,
        widthFlags: widthFlags,
      );
      packedCell += count;
    }
    if (packedCell != cellCount) {
      throw StateError('damage capture cell accounting is corrupt');
    }
    final TerminalDamagePacket packet = TerminalDamagePacket._(
      damageGeneration: damageGeneration,
      requiredResourceGeneration: requiredResourceGeneration,
      columns: screen.columns,
      rows: screen.rows,
      damagedRowCount: rows.length,
      damagedCellCount: cellCount,
      isFullSnapshot: full,
      cursorRow: screen.cursorRow,
      cursorColumn: screen.cursorColumn,
      cursorShape: screen.cursorShape,
      cursorVisible: screen.cursorVisible,
      cursorBlinking: screen.cursorBlinking,
      visualBellGeneration: screen.visualBellGeneration,
      bytes: bytes,
    );
    screen.clearDamage();
    return packet;
  }

  static TerminalDecodedDamage decode(
    Uint8List source, {
    int? expectedResourceGeneration,
    TerminalDamageLimits limits = const TerminalDamageLimits(),
  }) {
    limits.validate();
    if (source.length < headerBytes ||
        source.length > limits.maximumPacketBytes) {
      throw const TerminalDamageFormatException(
        'damage packet length is outside configured bounds',
      );
    }
    final Uint8List bytes = Uint8List.fromList(source);
    final ByteData data = ByteData.sublistView(bytes);
    final int damageGeneration = data.getUint64(8, Endian.little);
    final int resourceGeneration = data.getUint64(16, Endian.little);
    final int columns = data.getUint32(24, Endian.little);
    final int rows = data.getUint32(28, Endian.little);
    final int rowCount = data.getUint32(32, Endian.little);
    final int cellCount = data.getUint32(36, Endian.little);
    final int rowOffset = data.getUint32(40, Endian.little);
    final int contentOffset = data.getUint32(44, Endian.little);
    final int foregroundOffset = data.getUint32(48, Endian.little);
    final int backgroundOffset = data.getUint32(52, Endian.little);
    final int styleOffset = data.getUint32(56, Endian.little);
    final int hyperlinkOffset = data.getUint32(60, Endian.little);
    final int widthFlagsOffset = data.getUint32(64, Endian.little);
    final int totalBytes = data.getUint32(68, Endian.little);
    final int flags = data.getUint32(72, Endian.little);
    final int cursorRow = data.getUint32(76, Endian.little);
    final int cursorColumn = data.getUint32(80, Endian.little);
    final int cursorFlags = data.getUint32(84, Endian.little);
    final int cursorShape = cursorFlags & cursorShapeMask;
    final int visualBellGeneration = data.getUint64(88, Endian.little);
    if (data.getUint32(0, Endian.little) != magic ||
        data.getUint16(4, Endian.little) != version ||
        data.getUint16(6, Endian.little) != headerBytes ||
        damageGeneration <= 0 ||
        damageGeneration > 0x7fffffffffffffff ||
        resourceGeneration <= 0 ||
        resourceGeneration > 0x7fffffffffffffff ||
        (expectedResourceGeneration != null &&
            resourceGeneration != expectedResourceGeneration) ||
        flags & ~1 != 0 ||
        cursorFlags & ~cursorKnownMask != 0 ||
        cursorShape >= TerminalCursorShape.values.length ||
        visualBellGeneration < 0 ||
        visualBellGeneration > TerminalScreen.maxVisualBellGeneration ||
        data.getUint64(96, Endian.little) != 0 ||
        totalBytes != bytes.length) {
      throw const TerminalDamageFormatException('invalid damage header');
    }
    _validateDimensionsForDecode(columns, rows, limits);
    if (cursorRow >= rows ||
        cursorColumn >= columns ||
        rowCount > rows ||
        cellCount > limits.maximumCells) {
      throw const TerminalDamageFormatException('damage counts exceed limits');
    }
    final bool full = flags == 1;
    if ((!full && ((rowCount == 0) != (cellCount == 0))) ||
        (full && (rowCount != rows || cellCount != rows * columns))) {
      throw const TerminalDamageFormatException(
        'damage counts do not match snapshot kind',
      );
    }
    final _DamageLayout expected = _DamageLayout.compute(rowCount, cellCount);
    if (rowOffset != headerBytes ||
        contentOffset != expected.contentOffset ||
        foregroundOffset != expected.foregroundOffset ||
        backgroundOffset != expected.backgroundOffset ||
        styleOffset != expected.styleOffset ||
        hyperlinkOffset != expected.hyperlinkOffset ||
        widthFlagsOffset != expected.widthFlagsOffset ||
        totalBytes != expected.totalBytes ||
        totalBytes > limits.maximumPacketBytes) {
      throw const TerminalDamageFormatException(
        'damage section layout is not canonical',
      );
    }
    _validateZeroPadding(
      bytes,
      headerBytes + rowCount * rowRecordBytes,
      contentOffset,
    );
    _validateZeroPadding(
      bytes,
      contentOffset + cellCount * 4,
      foregroundOffset,
    );
    _validateZeroPadding(
      bytes,
      foregroundOffset + cellCount * 4,
      backgroundOffset,
    );
    _validateZeroPadding(bytes, backgroundOffset + cellCount * 4, styleOffset);
    _validateZeroPadding(bytes, styleOffset + cellCount * 2, hyperlinkOffset);
    _validateZeroPadding(
      bytes,
      hyperlinkOffset + cellCount * 2,
      widthFlagsOffset,
    );

    final List<TerminalDamageRowRecord> records = <TerminalDamageRowRecord>[];
    var previousRow = -1;
    var expectedFirstCell = 0;
    for (int index = 0; index < rowCount; index++) {
      final int offset = headerBytes + index * rowRecordBytes;
      final int row = data.getUint32(offset, Endian.little);
      final int rowVersion = data.getUint32(offset + 4, Endian.little);
      final int logicalLineId = data.getUint32(offset + 8, Endian.little);
      final int firstCell = data.getUint32(offset + 12, Endian.little);
      final int firstColumn = data.getUint16(offset + 16, Endian.little);
      final int count = data.getUint16(offset + 18, Endian.little);
      final int rowFlags = data.getUint8(offset + 20);
      if (row <= previousRow ||
          row >= rows ||
          logicalLineId == 0 ||
          firstCell != expectedFirstCell ||
          count == 0 ||
          firstColumn >= columns ||
          count > columns - firstColumn ||
          rowFlags & ~TerminalRowFlags.knownMask != 0 ||
          data.getUint8(offset + 21) != 0 ||
          data.getUint8(offset + 22) != 0 ||
          data.getUint8(offset + 23) != 0 ||
          (full && (row != index || firstColumn != 0 || count != columns))) {
        throw const TerminalDamageFormatException('invalid damage row record');
      }
      records.add(
        TerminalDamageRowRecord(
          row: row,
          rowVersion: rowVersion,
          logicalLineId: logicalLineId,
          firstCell: firstCell,
          firstColumn: firstColumn,
          cellCount: count,
          rowFlags: rowFlags,
        ),
      );
      previousRow = row;
      expectedFirstCell += count;
    }
    if (expectedFirstCell != cellCount) {
      throw const TerminalDamageFormatException(
        'damage row cells do not cover packed cells',
      );
    }

    final Uint32List content = Uint32List(cellCount);
    final Uint32List foreground = Uint32List(cellCount);
    final Uint32List background = Uint32List(cellCount);
    final Uint16List styles = Uint16List(cellCount);
    final Uint16List hyperlinks = Uint16List(cellCount);
    final Uint8List widthFlags = Uint8List(cellCount);
    for (int cell = 0; cell < cellCount; cell++) {
      content[cell] = data.getUint32(contentOffset + cell * 4, Endian.little);
      foreground[cell] = data.getUint32(
        foregroundOffset + cell * 4,
        Endian.little,
      );
      background[cell] = data.getUint32(
        backgroundOffset + cell * 4,
        Endian.little,
      );
      styles[cell] = data.getUint16(styleOffset + cell * 2, Endian.little);
      hyperlinks[cell] = data.getUint16(
        hyperlinkOffset + cell * 2,
        Endian.little,
      );
      widthFlags[cell] = data.getUint8(widthFlagsOffset + cell);
      _validatePackedCell(
        content[cell],
        foreground[cell],
        background[cell],
        styles[cell],
        hyperlinks[cell],
        widthFlags[cell],
      );
    }
    return TerminalDecodedDamage._(
      damageGeneration: damageGeneration,
      requiredResourceGeneration: resourceGeneration,
      columns: columns,
      rows: rows,
      isFullSnapshot: full,
      cursorRow: cursorRow,
      cursorColumn: cursorColumn,
      cursorShape: TerminalCursorShape.values[cursorShape],
      cursorVisible: cursorFlags & cursorVisibleFlag != 0,
      cursorBlinking: cursorFlags & cursorBlinkingFlag != 0,
      visualBellGeneration: visualBellGeneration,
      rowRecordsOffset: rowOffset,
      contentOffset: contentOffset,
      foregroundOffset: foregroundOffset,
      backgroundOffset: backgroundOffset,
      styleOffset: styleOffset,
      hyperlinkOffset: hyperlinkOffset,
      widthFlagsOffset: widthFlagsOffset,
      rowRecords: records,
      content: content,
      foreground: foreground,
      background: background,
      styles: styles,
      hyperlinks: hyperlinks,
      widthFlags: widthFlags,
      bytes: bytes,
    );
  }

  static void _validatePackedCell(
    int content,
    int foreground,
    int background,
    int style,
    int hyperlink,
    int flags,
  ) {
    final int width = flags & TerminalCellFlags.widthMask;
    final bool grapheme = flags & TerminalCellFlags.grapheme != 0;
    if (flags & ~TerminalCellFlags.knownMask != 0 ||
        width == TerminalCellFlags.widthMask ||
        style == 0xffff ||
        hyperlink == 0xffff ||
        !_validColor(foreground) ||
        !_validColor(background)) {
      throw const TerminalDamageFormatException('invalid packed cell fields');
    }
    if (width == TerminalCellFlags.continuation) {
      if (content != 0 || grapheme) {
        throw const TerminalDamageFormatException('invalid continuation cell');
      }
      return;
    }
    if (grapheme) {
      if (content == 0 || content > TerminalScreen.maxResourceId) {
        throw const TerminalDamageFormatException('invalid grapheme cell');
      }
      return;
    }
    if (content == 0) {
      if (width != TerminalCellFlags.narrow) {
        throw const TerminalDamageFormatException('invalid blank cell');
      }
      return;
    }
    if (!_validUnicodeScalar(content) ||
        TerminalUnicode.scalarWidth(content) !=
            (width == TerminalCellFlags.wide ? 2 : 1)) {
      throw const TerminalDamageFormatException('invalid scalar cell width');
    }
  }
}

enum TerminalDamageApplyDisposition {
  applied,
  stale,
  resourceUnavailable,
  needsFullSnapshot,
  invalid,
}

final class TerminalDamageApplyResult {
  const TerminalDamageApplyResult({
    required this.disposition,
    required this.damageGeneration,
    required this.acceptedBytes,
  });

  final TerminalDamageApplyDisposition disposition;
  final int damageGeneration;
  final int acceptedBytes;

  bool get isApplied => disposition == TerminalDamageApplyDisposition.applied;
}

/// Independently owned render-side SoA model updated only by validated damage.
final class TerminalDamageRenderModel implements TerminalRenderModel {
  TerminalDamageRenderModel({this.limits = const TerminalDamageLimits()}) {
    limits.validate();
  }

  final TerminalDamageLimits limits;
  Uint32List? _content;
  Uint32List? _foreground;
  Uint32List? _background;
  Uint16List? _styles;
  Uint16List? _hyperlinks;
  Uint8List? _widthFlags;
  Uint32List? _rowVersions;
  Uint8List? _rowFlags;
  Uint32List? _logicalLineIds;
  int _columns = 0;
  int _rows = 0;
  int _lastDamageGeneration = 0;
  int _requiredResourceGeneration = 0;
  int _cursorRow = 0;
  int _cursorColumn = 0;
  TerminalCursorShape _cursorShape = TerminalCursorShape.block;
  bool _cursorVisible = true;
  bool _cursorBlinking = true;
  int _visualBellGeneration = 0;

  bool get isInitialized => _content != null;
  int get columns => _columns;
  int get rows => _rows;
  int get lastDamageGeneration => _lastDamageGeneration;
  int get requiredResourceGeneration => _requiredResourceGeneration;
  int get cursorRow => _cursorRow;
  int get cursorColumn => _cursorColumn;
  TerminalCursorShape get cursorShape => _cursorShape;
  bool get cursorVisible => _cursorVisible;
  bool get cursorBlinking => _cursorBlinking;
  int get visualBellGeneration => _visualBellGeneration;

  int contentAt(int row, int column) => _content![_index(row, column)];
  int foregroundAt(int row, int column) => _foreground![_index(row, column)];
  int backgroundAt(int row, int column) => _background![_index(row, column)];
  int styleAt(int row, int column) => _styles![_index(row, column)];
  int hyperlinkAt(int row, int column) => _hyperlinks![_index(row, column)];
  int widthFlagsAt(int row, int column) => _widthFlags![_index(row, column)];
  int rowVersionAt(int row) {
    _checkRow(row);
    return _rowVersions![row];
  }

  int rowFlagsAt(int row) {
    _checkRow(row);
    return _rowFlags![row];
  }

  int logicalLineIdAt(int row) {
    _checkRow(row);
    return _logicalLineIds![row];
  }

  TerminalDamageApplyResult apply(
    TerminalDecodedDamage damage, {
    required int availableResourceGeneration,
  }) {
    _requireGeneration(
      availableResourceGeneration,
      'availableResourceGeneration',
    );
    if (damage.damageGeneration <= _lastDamageGeneration) {
      return _result(TerminalDamageApplyDisposition.stale, damage);
    }
    if (availableResourceGeneration < damage.requiredResourceGeneration) {
      return _result(
        TerminalDamageApplyDisposition.resourceUnavailable,
        damage,
      );
    }
    if (_requiredResourceGeneration > damage.requiredResourceGeneration) {
      return _result(TerminalDamageApplyDisposition.needsFullSnapshot, damage);
    }
    if (isInitialized && damage.visualBellGeneration < _visualBellGeneration) {
      return _result(TerminalDamageApplyDisposition.needsFullSnapshot, damage);
    }
    if (damage.isFullSnapshot) {
      return _applyFull(damage);
    }
    if (!isInitialized ||
        damage.columns != _columns ||
        damage.rows != _rows ||
        damage.damageGeneration != _lastDamageGeneration + 1) {
      return _result(TerminalDamageApplyDisposition.needsFullSnapshot, damage);
    }
    final List<_StagedDamageRow> staged = <_StagedDamageRow>[];
    for (final TerminalDamageRowRecord record in damage.rowRecords) {
      final int expectedVersion = _rowVersions![record.row] + 1;
      if (expectedVersion > TerminalScreen.maxRowVersion ||
          record.rowVersion != expectedVersion) {
        return _result(
          TerminalDamageApplyDisposition.needsFullSnapshot,
          damage,
        );
      }
      final _StagedDamageRow row = _stageIncrementalRow(damage, record);
      if (!_rowTopologyIsValid(row)) {
        return _result(TerminalDamageApplyDisposition.invalid, damage);
      }
      staged.add(row);
    }
    for (final _StagedDamageRow row in staged) {
      _publishRow(row);
    }
    _publishPresentation(damage);
    _lastDamageGeneration = damage.damageGeneration;
    _requiredResourceGeneration = damage.requiredResourceGeneration;
    return _result(TerminalDamageApplyDisposition.applied, damage);
  }

  TerminalDamageApplyResult _applyFull(TerminalDecodedDamage damage) {
    _validateDimensions(damage.columns, damage.rows, limits);
    final int cells = damage.columns * damage.rows;
    final Uint32List content = Uint32List(cells);
    final Uint32List foreground = Uint32List(cells);
    final Uint32List background = Uint32List(cells);
    final Uint16List styles = Uint16List(cells);
    final Uint16List hyperlinks = Uint16List(cells);
    final Uint8List widthFlags = Uint8List(cells);
    final Uint32List rowVersions = Uint32List(damage.rows);
    final Uint8List rowFlags = Uint8List(damage.rows);
    final Uint32List logicalLineIds = Uint32List(damage.rows);
    for (final TerminalDamageRowRecord record in damage.rowRecords) {
      final int base = record.row * damage.columns;
      for (int cell = 0; cell < record.cellCount; cell++) {
        final int source = record.firstCell + cell;
        final int destination = base + cell;
        content[destination] = damage._content[source];
        foreground[destination] = damage._foreground[source];
        background[destination] = damage._background[source];
        styles[destination] = damage._styles[source];
        hyperlinks[destination] = damage._hyperlinks[source];
        widthFlags[destination] = damage._widthFlags[source];
      }
      rowVersions[record.row] = record.rowVersion;
      rowFlags[record.row] = record.rowFlags;
      logicalLineIds[record.row] = record.logicalLineId;
      final _StagedDamageRow staged = _StagedDamageRow(
        row: record.row,
        rowVersion: record.rowVersion,
        rowFlags: record.rowFlags,
        logicalLineId: record.logicalLineId,
        content: Uint32List.sublistView(content, base, base + damage.columns),
        foreground: Uint32List.sublistView(
          foreground,
          base,
          base + damage.columns,
        ),
        background: Uint32List.sublistView(
          background,
          base,
          base + damage.columns,
        ),
        styles: Uint16List.sublistView(styles, base, base + damage.columns),
        hyperlinks: Uint16List.sublistView(
          hyperlinks,
          base,
          base + damage.columns,
        ),
        widthFlags: Uint8List.sublistView(
          widthFlags,
          base,
          base + damage.columns,
        ),
      );
      if (!_rowTopologyIsValid(staged)) {
        return _result(TerminalDamageApplyDisposition.invalid, damage);
      }
    }
    _columns = damage.columns;
    _rows = damage.rows;
    _content = content;
    _foreground = foreground;
    _background = background;
    _styles = styles;
    _hyperlinks = hyperlinks;
    _widthFlags = widthFlags;
    _rowVersions = rowVersions;
    _rowFlags = rowFlags;
    _logicalLineIds = logicalLineIds;
    _publishPresentation(damage);
    _lastDamageGeneration = damage.damageGeneration;
    _requiredResourceGeneration = damage.requiredResourceGeneration;
    return _result(TerminalDamageApplyDisposition.applied, damage);
  }

  _StagedDamageRow _stageIncrementalRow(
    TerminalDecodedDamage damage,
    TerminalDamageRowRecord record,
  ) {
    final Uint32List content = Uint32List(_columns);
    final Uint32List foreground = Uint32List(_columns);
    final Uint32List background = Uint32List(_columns);
    final Uint16List styles = Uint16List(_columns);
    final Uint16List hyperlinks = Uint16List(_columns);
    final Uint8List widthFlags = Uint8List(_columns);
    final int base = record.row * _columns;
    for (int column = 0; column < _columns; column++) {
      content[column] = _content![base + column];
      foreground[column] = _foreground![base + column];
      background[column] = _background![base + column];
      styles[column] = _styles![base + column];
      hyperlinks[column] = _hyperlinks![base + column];
      widthFlags[column] = _widthFlags![base + column];
    }
    for (int cell = 0; cell < record.cellCount; cell++) {
      final int source = record.firstCell + cell;
      final int column = record.firstColumn + cell;
      content[column] = damage._content[source];
      foreground[column] = damage._foreground[source];
      background[column] = damage._background[source];
      styles[column] = damage._styles[source];
      hyperlinks[column] = damage._hyperlinks[source];
      widthFlags[column] = damage._widthFlags[source];
    }
    return _StagedDamageRow(
      row: record.row,
      rowVersion: record.rowVersion,
      rowFlags: record.rowFlags,
      logicalLineId: record.logicalLineId,
      content: content,
      foreground: foreground,
      background: background,
      styles: styles,
      hyperlinks: hyperlinks,
      widthFlags: widthFlags,
    );
  }

  bool _rowTopologyIsValid(_StagedDamageRow row) {
    for (int column = 0; column < row.content.length; column++) {
      final int flags = row.widthFlags[column];
      final int width = flags & TerminalCellFlags.widthMask;
      if (width == TerminalCellFlags.continuation) {
        if (column == 0 ||
            (row.widthFlags[column - 1] & TerminalCellFlags.widthMask) !=
                TerminalCellFlags.wide ||
            row.foreground[column] != row.foreground[column - 1] ||
            row.background[column] != row.background[column - 1] ||
            row.styles[column] != row.styles[column - 1] ||
            row.hyperlinks[column] != row.hyperlinks[column - 1] ||
            (row.widthFlags[column] & TerminalCellFlags.protected) !=
                (row.widthFlags[column - 1] & TerminalCellFlags.protected)) {
          return false;
        }
      } else if (width == TerminalCellFlags.wide) {
        if (column + 1 >= row.content.length ||
            (row.widthFlags[column + 1] & TerminalCellFlags.widthMask) !=
                TerminalCellFlags.continuation) {
          return false;
        }
      }
    }
    return true;
  }

  void _publishRow(_StagedDamageRow row) {
    final int base = row.row * _columns;
    for (int column = 0; column < _columns; column++) {
      _content![base + column] = row.content[column];
      _foreground![base + column] = row.foreground[column];
      _background![base + column] = row.background[column];
      _styles![base + column] = row.styles[column];
      _hyperlinks![base + column] = row.hyperlinks[column];
      _widthFlags![base + column] = row.widthFlags[column];
    }
    _rowVersions![row.row] = row.rowVersion;
    _rowFlags![row.row] = row.rowFlags;
    _logicalLineIds![row.row] = row.logicalLineId;
  }

  void _publishPresentation(TerminalDecodedDamage damage) {
    _cursorRow = damage.cursorRow;
    _cursorColumn = damage.cursorColumn;
    _cursorShape = damage.cursorShape;
    _cursorVisible = damage.cursorVisible;
    _cursorBlinking = damage.cursorBlinking;
    _visualBellGeneration = damage.visualBellGeneration;
  }

  TerminalDamageApplyResult _result(
    TerminalDamageApplyDisposition disposition,
    TerminalDecodedDamage damage,
  ) => TerminalDamageApplyResult(
    disposition: disposition,
    damageGeneration: damage.damageGeneration,
    acceptedBytes: disposition == TerminalDamageApplyDisposition.applied
        ? damage.byteLength
        : 0,
  );

  int _index(int row, int column) {
    if (!isInitialized) throw StateError('damage render model is empty');
    RangeError.checkValueInInterval(row, 0, _rows - 1, 'row');
    RangeError.checkValueInInterval(column, 0, _columns - 1, 'column');
    return row * _columns + column;
  }

  void _checkRow(int row) {
    if (!isInitialized) throw StateError('damage render model is empty');
    RangeError.checkValueInInterval(row, 0, _rows - 1, 'row');
  }
}

final class _CaptureRow {
  const _CaptureRow(this.row, this.start, this.end);
  final int row;
  final int start;
  final int end;
}

final class _DamageLayout {
  const _DamageLayout({
    required this.contentOffset,
    required this.foregroundOffset,
    required this.backgroundOffset,
    required this.styleOffset,
    required this.hyperlinkOffset,
    required this.widthFlagsOffset,
    required this.totalBytes,
  });

  factory _DamageLayout.compute(int rows, int cells) {
    final int content = _align8(
      TerminalDamageCodec.headerBytes +
          rows * TerminalDamageCodec.rowRecordBytes,
    );
    final int foreground = _align8(content + cells * 4);
    final int background = _align8(foreground + cells * 4);
    final int style = _align8(background + cells * 4);
    final int hyperlink = _align8(style + cells * 2);
    final int widthFlags = _align8(hyperlink + cells * 2);
    return _DamageLayout(
      contentOffset: content,
      foregroundOffset: foreground,
      backgroundOffset: background,
      styleOffset: style,
      hyperlinkOffset: hyperlink,
      widthFlagsOffset: widthFlags,
      totalBytes: widthFlags + cells,
    );
  }

  final int contentOffset;
  final int foregroundOffset;
  final int backgroundOffset;
  final int styleOffset;
  final int hyperlinkOffset;
  final int widthFlagsOffset;
  final int totalBytes;
}

final class _StagedDamageRow {
  const _StagedDamageRow({
    required this.row,
    required this.rowVersion,
    required this.rowFlags,
    required this.logicalLineId,
    required this.content,
    required this.foreground,
    required this.background,
    required this.styles,
    required this.hyperlinks,
    required this.widthFlags,
  });

  final int row;
  final int rowVersion;
  final int rowFlags;
  final int logicalLineId;
  final Uint32List content;
  final Uint32List foreground;
  final Uint32List background;
  final Uint16List styles;
  final Uint16List hyperlinks;
  final Uint8List widthFlags;
}

int _align8(int value) => (value + 7) & ~7;

void _validateZeroPadding(Uint8List bytes, int start, int end) {
  if (start > end || end > bytes.length) {
    throw const TerminalDamageFormatException('invalid damage padding range');
  }
  for (int offset = start; offset < end; offset++) {
    if (bytes[offset] != 0) {
      throw const TerminalDamageFormatException('nonzero damage padding');
    }
  }
}

void _validateDimensions(int columns, int rows, TerminalDamageLimits limits) {
  if (columns <= 0 ||
      columns > limits.maximumColumns ||
      rows <= 0 ||
      rows > limits.maximumRows ||
      rows * columns > limits.maximumCells) {
    throw StateError('screen dimensions exceed damage limits');
  }
}

void _validateDimensionsForDecode(
  int columns,
  int rows,
  TerminalDamageLimits limits,
) {
  try {
    _validateDimensions(columns, rows, limits);
  } on Object {
    throw const TerminalDamageFormatException(
      'damage dimensions exceed configured limits',
    );
  }
}

void _requireGeneration(int value, String name) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    throw RangeError.range(value, 1, 0x7fffffffffffffff, name);
  }
}

bool _validColor(int token) =>
    token == 0 ||
    (token >= 1 && token <= 256) ||
    token & 0xff000000 == 0x80000000;

bool _validUnicodeScalar(int value) =>
    value > 0 && value <= 0x10ffff && (value < 0xd800 || value > 0xdfff);
