import 'dart:convert';

import 'terminal_hyperlink.dart';
import 'terminal_screen.dart';
import 'terminal_screen_parser_sink.dart';
import 'terminal_screen_set.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

/// Finite limits applied before a terminal-state snapshot is returned.
final class TerminalSnapshotFormatLimits {
  const TerminalSnapshotFormatLimits({
    this.maxRows = 20000,
    this.maxCells = 4 * 1024 * 1024,
    this.maxStyleDefinitions = TerminalStyleTable.defaultCapacity,
    this.maxGraphemeDefinitions = TerminalGraphemeTable.defaultCapacity,
    this.maxHyperlinkDefinitions = TerminalHyperlinkTable.defaultCapacity,
    this.maxHyperlinkUtf8Bytes = TerminalHyperlinkTable.defaultMaximumUtf8Bytes,
    this.maxOutputCharacters = 16 * 1024 * 1024,
  }) : assert(maxRows > 0),
       assert(maxCells > 0),
       assert(maxStyleDefinitions >= 0),
       assert(maxGraphemeDefinitions >= 0),
       assert(maxHyperlinkDefinitions >= 0),
       assert(maxHyperlinkUtf8Bytes >= 0),
       assert(maxOutputCharacters > 0);

  final int maxRows;
  final int maxCells;
  final int maxStyleDefinitions;
  final int maxGraphemeDefinitions;
  final int maxHyperlinkDefinitions;
  final int maxHyperlinkUtf8Bytes;
  final int maxOutputCharacters;
}

/// Identifies a formatter bound that would make a snapshot incomplete.
final class TerminalSnapshotLimitException implements Exception {
  const TerminalSnapshotLimitException({
    required this.resource,
    required this.actual,
    required this.limit,
  });

  final String resource;
  final int actual;
  final int limit;

  @override
  String toString() =>
      'TerminalSnapshotLimitException: $resource $actual exceeds $limit';
}

/// Produces a deterministic, line-oriented terminal-state test oracle.
///
/// The format describes final semantic state. Mutation-path details such
/// as damage ranges and generation counters are deliberately omitted so equal
/// final states remain equal across parser chunk plans. The formatter only
/// observes terminal objects and never acknowledges damage or moves a viewport.
final class TerminalSnapshotFormatter {
  const TerminalSnapshotFormatter({
    this.limits = const TerminalSnapshotFormatLimits(),
  });

  static const String formatName = 'dart-terminal-state-snapshot';
  static const int formatVersion = 3;

  final TerminalSnapshotFormatLimits limits;

  String formatScreen(
    TerminalScreen screen, {
    TerminalScreenParserSink? parserSink,
  }) {
    _validateLimits();
    _validateScreenParserSink(screen, parserSink);
    _checkCount('rows', screen.rows, limits.maxRows);
    _checkCount('cells', screen.cellCount, limits.maxCells);
    _checkResources(
      screen.styleTable,
      screen.graphemeTable,
      screen.hyperlinkTable,
    );

    final _SnapshotWriter writer = _SnapshotWriter(limits.maxOutputCharacters);
    writer.line('$formatName version=$formatVersion kind=screen');
    _writeResources(
      writer,
      screen.styleTable,
      screen.graphemeTable,
      screen.hyperlinkTable,
      screen.palette,
    );
    _writeScreen(writer, 'screen', screen);
    if (parserSink != null) {
      _writeParserCounters(writer, parserSink);
    }
    writer.line('end');
    return writer.finish();
  }

  String formatScreenSet(
    TerminalScreenSet screens, {
    TerminalScreenParserSink? parserSink,
  }) {
    _validateLimits();
    if (parserSink != null && !identical(parserSink.screenSet, screens)) {
      throw ArgumentError.value(
        parserSink,
        'parserSink',
        'must own the formatted screen set',
      );
    }
    _checkScreenSetSize(screens);
    _checkResources(
      screens.styleTable,
      screens.graphemeTable,
      screens.hyperlinkTable,
    );

    final _SnapshotWriter writer = _SnapshotWriter(limits.maxOutputCharacters);
    writer.line('$formatName version=$formatVersion kind=screen-set');
    writer.line(
      'set active=${screens.activeKind.name} '
      'mode1049=${screens.mode1049Active} '
      'viewport_offset=${screens.viewport.offset} '
      'primary_viewport_offset=${screens.viewport.primaryOffset}',
    );
    writer.line(
      'metadata window_title=${jsonEncode(screens.metadata.windowTitle)} '
      'icon_title=${jsonEncode(screens.metadata.iconTitle)} '
      'cwd=${jsonEncode(screens.metadata.workingDirectory?.toString())} '
      'window_title_stack=${jsonEncode(screens.metadata.windowTitleStack)} '
      'icon_title_stack=${jsonEncode(screens.metadata.iconTitleStack)}',
    );
    _writeResources(
      writer,
      screens.styleTable,
      screens.graphemeTable,
      screens.hyperlinkTable,
      screens.palette,
    );
    _writeHistory(writer, screens.scrollback, screens.graphemeTable);
    _writeScreen(writer, 'primary', screens.primary);
    _writeScreen(writer, 'alternate', screens.alternate);
    if (parserSink != null) {
      _writeParserCounters(writer, parserSink);
    }
    writer.line('end');
    return writer.finish();
  }

  void _validateLimits() {
    if (limits.maxRows <= 0) {
      throw ArgumentError.value(limits.maxRows, 'limits.maxRows');
    }
    if (limits.maxCells <= 0) {
      throw ArgumentError.value(limits.maxCells, 'limits.maxCells');
    }
    if (limits.maxStyleDefinitions < 0) {
      throw ArgumentError.value(
        limits.maxStyleDefinitions,
        'limits.maxStyleDefinitions',
      );
    }
    if (limits.maxGraphemeDefinitions < 0) {
      throw ArgumentError.value(
        limits.maxGraphemeDefinitions,
        'limits.maxGraphemeDefinitions',
      );
    }
    if (limits.maxHyperlinkDefinitions < 0) {
      throw ArgumentError.value(
        limits.maxHyperlinkDefinitions,
        'limits.maxHyperlinkDefinitions',
      );
    }
    if (limits.maxHyperlinkUtf8Bytes < 0) {
      throw ArgumentError.value(
        limits.maxHyperlinkUtf8Bytes,
        'limits.maxHyperlinkUtf8Bytes',
      );
    }
    if (limits.maxOutputCharacters <= 0) {
      throw ArgumentError.value(
        limits.maxOutputCharacters,
        'limits.maxOutputCharacters',
      );
    }
  }

  void _validateScreenParserSink(
    TerminalScreen screen,
    TerminalScreenParserSink? parserSink,
  ) {
    if (parserSink == null) {
      return;
    }
    if (parserSink.screenSet != null || !identical(parserSink.screen, screen)) {
      throw ArgumentError.value(
        parserSink,
        'parserSink',
        'must own the formatted standalone screen',
      );
    }
  }

  void _checkScreenSetSize(TerminalScreenSet screens) {
    final int rowCount =
        screens.scrollback.length +
        screens.primary.rows +
        screens.alternate.rows;
    _checkCount('rows', rowCount, limits.maxRows);

    int cellCount = screens.primary.cellCount + screens.alternate.cellCount;
    for (int row = 0; row < screens.scrollback.length; row++) {
      cellCount += screens.scrollback.columnsAt(row);
      if (cellCount > limits.maxCells) {
        break;
      }
    }
    _checkCount('cells', cellCount, limits.maxCells);
  }

  void _checkResources(
    TerminalStyleTable styles,
    TerminalGraphemeTable graphemes,
    TerminalHyperlinkTable hyperlinks,
  ) {
    _checkCount(
      'style definitions',
      styles.definitionCount,
      limits.maxStyleDefinitions,
    );
    _checkCount(
      'grapheme definitions',
      graphemes.definitionCount,
      limits.maxGraphemeDefinitions,
    );
    _checkCount(
      'hyperlink definitions',
      hyperlinks.definitionCount,
      limits.maxHyperlinkDefinitions,
    );
    _checkCount(
      'hyperlink UTF-8 bytes',
      hyperlinks.utf8Bytes,
      limits.maxHyperlinkUtf8Bytes,
    );
  }

  static void _checkCount(String resource, int actual, int limit) {
    if (actual > limit) {
      throw TerminalSnapshotLimitException(
        resource: resource,
        actual: actual,
        limit: limit,
      );
    }
  }

  void _writeResources(
    _SnapshotWriter writer,
    TerminalStyleTable styles,
    TerminalGraphemeTable graphemes,
    TerminalHyperlinkTable hyperlinks,
    TerminalPalette palette,
  ) {
    writer.line(
      'resources styles=${styles.definitionCount} '
      'graphemes=${graphemes.definitionCount} '
      'palette=${TerminalPalette.colorCount}',
    );
    for (int id = 1; id <= styles.definitionCount; id++) {
      final int attributes = styles.attributesAt(id);
      writer.line(
        'style id=$id attributes=${_styleAttributes(attributes)} '
        'bits=${_hex(attributes, 4)}',
      );
    }
    for (int id = 1; id <= graphemes.definitionCount; id++) {
      final List<int> scalars = graphemes.scalarsAt(id);
      writer.line(
        'grapheme id=$id width=${graphemes.widthAt(id)} '
        'scalars=${scalars.map(_unicodeScalar).join(',')} '
        'text=${jsonEncode(String.fromCharCodes(scalars))}',
      );
    }
    if (hyperlinks.definitionCount != 0) {
      writer.line(
        'hyperlinks count=${hyperlinks.definitionCount} '
        'utf8_bytes=${hyperlinks.utf8Bytes}',
      );
      for (int id = 1; id <= hyperlinks.definitionCount; id++) {
        final TerminalHyperlinkDefinition definition = hyperlinks.definitionAt(
          id,
        );
        writer.line(
          'hyperlink id=$id explicit_id=${jsonEncode(definition.explicitId)} '
          'uri=${jsonEncode(definition.uri)}',
        );
      }
    }
    writer.line(
      'palette defaults foreground=${_directColor(palette.defaultForeground)} '
      'background=${_directColor(palette.defaultBackground)} '
      'cursor=${_directColor(palette.cursorColor)}',
    );
    for (int start = 0; start < TerminalPalette.colorCount; start += 16) {
      final List<String> colors = <String>[];
      for (int index = start; index < start + 16; index++) {
        colors.add(_directColor(palette.colorAt(index)));
      }
      writer.line(
        'palette range=${start.toString().padLeft(3, '0')}-'
        '${(start + 15).toString().padLeft(3, '0')} '
        'colors=${colors.join(',')}',
      );
    }
  }

  void _writeHistory(
    _SnapshotWriter writer,
    TerminalScrollback history,
    TerminalGraphemeTable graphemes,
  ) {
    writer.line(
      'history rows=${history.length} max_lines=${history.maxLines} '
      'max_bytes=${history.maxBytes} page_rows=${history.pageRows}',
    );
    for (int row = 0; row < history.length; row++) {
      final int columns = history.columnsAt(row);
      writer.line(
        'history row=$row columns=$columns '
        'flags=${_rowFlags(history.rowFlagsAt(row))} '
        'logical=${history.logicalLineEpochAt(row)}:'
        '${history.logicalLineIdAt(row)}+'
        '${history.logicalCellOffsetAt(row)} '
        'text=${jsonEncode(_rowText(columns, (int column) => history.contentAt(row, column), (int column) => history.widthFlagsAt(row, column), graphemes))}',
      );
      _writeCells(
        writer,
        'history',
        row,
        columns,
        contentAt: (int column) => history.contentAt(row, column),
        foregroundAt: (int column) => history.foregroundAt(row, column),
        backgroundAt: (int column) => history.backgroundAt(row, column),
        styleAt: (int column) => history.styleAt(row, column),
        hyperlinkAt: (int column) => history.hyperlinkAt(row, column),
        widthFlagsAt: (int column) => history.widthFlagsAt(row, column),
      );
    }
  }

  void _writeScreen(
    _SnapshotWriter writer,
    String name,
    TerminalScreen screen,
  ) {
    writer.line(
      'screen name=$name rows=${screen.rows} columns=${screen.columns}',
    );
    writer.line(
      '$name cursor=${screen.cursorRow},${screen.cursorColumn} '
      'saved=${screen.savedCursorRow},${screen.savedCursorColumn} '
      'current=${_colorToken(screen.currentForeground)}/'
      '${_colorToken(screen.currentBackground)}/${screen.currentStyleId} '
      'saved_rendition=${_colorToken(screen.savedForeground)}/'
      '${_colorToken(screen.savedBackground)}/${screen.savedStyleId}',
    );
    writer.line(
      '$name charsets=g0:${screen.g0CharacterSet.name},'
      'g1:${screen.g1CharacterSet.name},gl:${screen.glCharacterSetSlot} '
      'saved=g0:${screen.savedG0CharacterSet.name},'
      'g1:${screen.savedG1CharacterSet.name},'
      'gl:${screen.savedGlCharacterSetSlot}',
    );
    writer.line(
      '$name margins=${screen.topMargin},${screen.bottomMargin},'
      '${screen.leftMargin},${screen.rightMargin} '
      'modes=${TerminalScreenMode.values.map((TerminalScreenMode mode) => '${mode.name}:${screen.modeEnabled(mode)}').join(',')}',
    );
    writer.line(
      '$name cursor_style=${screen.cursorShape.name} '
      'visible=${screen.cursorVisible} blinking=${screen.cursorBlinking} '
      'wrap_pending=${screen.wrapPending}',
    );
    final List<String> tabs = <String>[];
    for (int column = 0; column < screen.columns; column++) {
      if (screen.isTabStop(column)) {
        tabs.add('$column');
      }
    }
    writer.line('$name tabs=${tabs.isEmpty ? '-' : tabs.join(',')}');
    for (int row = 0; row < screen.rows; row++) {
      writer.line(
        '$name row=$row flags=${_rowFlags(screen.rowFlagsAt(row))} '
        'logical=${screen.logicalLineEpochAt(row)}:'
        '${screen.logicalLineIdAt(row)}+${screen.logicalCellOffsetAt(row)} '
        'text=${jsonEncode(_rowText(screen.columns, (int column) => screen.contentAt(row, column), (int column) => screen.widthFlagsAt(row, column), screen.graphemeTable))}',
      );
      _writeCells(
        writer,
        name,
        row,
        screen.columns,
        contentAt: (int column) => screen.contentAt(row, column),
        foregroundAt: (int column) => screen.foregroundAt(row, column),
        backgroundAt: (int column) => screen.backgroundAt(row, column),
        styleAt: (int column) => screen.styleAt(row, column),
        hyperlinkAt: (int column) => screen.hyperlinkAt(row, column),
        widthFlagsAt: (int column) => screen.widthFlagsAt(row, column),
      );
    }
  }

  void _writeCells(
    _SnapshotWriter writer,
    String section,
    int row,
    int columns, {
    required int Function(int column) contentAt,
    required int Function(int column) foregroundAt,
    required int Function(int column) backgroundAt,
    required int Function(int column) styleAt,
    required int Function(int column) hyperlinkAt,
    required int Function(int column) widthFlagsAt,
  }) {
    for (int column = 0; column < columns; column++) {
      final int content = contentAt(column);
      final int foreground = foregroundAt(column);
      final int background = backgroundAt(column);
      final int style = styleAt(column);
      final int hyperlink = hyperlinkAt(column);
      final int flags = widthFlagsAt(column);
      if (_isDefaultBlank(
        content,
        foreground,
        background,
        style,
        hyperlink,
        flags,
      )) {
        continue;
      }
      writer.line(
        '$section cell=$row,$column content=${_cellContent(content, flags)} '
        'flags=${_cellFlags(flags)} foreground=${_colorToken(foreground)} '
        'background=${_colorToken(background)} style=$style '
        'hyperlink=$hyperlink',
      );
    }
  }

  static void _writeParserCounters(
    _SnapshotWriter writer,
    TerminalScreenParserSink sink,
  ) {
    writer.line(
      'parser unsupported_controls=${sink.unsupportedControlCount} '
      'unsupported_sequences=${sink.unsupportedSequenceCount} '
      'cancel=${sink.cancelCount} limit=${sink.limitCount} '
      'malformed=${sink.malformedCount} incomplete=${sink.incompleteCount} '
      'replies_accepted=${sink.acceptedReplyCount} '
      'replies_rejected=${sink.rejectedReplyCount}',
    );
  }

  static String _rowText(
    int columns,
    int Function(int column) contentAt,
    int Function(int column) widthFlagsAt,
    TerminalGraphemeTable graphemes,
  ) {
    final StringBuffer result = StringBuffer();
    for (int column = 0; column < columns; column++) {
      final int flags = widthFlagsAt(column);
      final int width = flags & TerminalCellFlags.widthMask;
      if (width == TerminalCellFlags.continuation) {
        result.write('\u00b7');
        continue;
      }
      final int content = contentAt(column);
      if (content == 0) {
        result.write(' ');
      } else if (flags & TerminalCellFlags.grapheme != 0) {
        result.write(String.fromCharCodes(graphemes.scalarsAt(content)));
      } else {
        result.writeCharCode(content);
      }
    }
    return result.toString();
  }

  static bool _isDefaultBlank(
    int content,
    int foreground,
    int background,
    int style,
    int hyperlink,
    int flags,
  ) =>
      content == 0 &&
      foreground == 0 &&
      background == 0 &&
      style == 0 &&
      hyperlink == 0 &&
      flags == TerminalCellFlags.narrow;

  static String _cellContent(int content, int flags) {
    final int width = flags & TerminalCellFlags.widthMask;
    if (width == TerminalCellFlags.continuation) {
      return 'continuation';
    }
    if (content == 0) {
      return 'blank';
    }
    if (flags & TerminalCellFlags.grapheme != 0) {
      return 'grapheme:$content';
    }
    return _unicodeScalar(content);
  }

  static String _cellFlags(int flags) {
    final List<String> names = <String>[
      switch (flags & TerminalCellFlags.widthMask) {
        TerminalCellFlags.continuation => 'continuation',
        TerminalCellFlags.narrow => 'narrow',
        TerminalCellFlags.wide => 'wide',
        _ => 'width:${flags & TerminalCellFlags.widthMask}',
      },
    ];
    if (flags & TerminalCellFlags.grapheme != 0) {
      names.add('grapheme');
    }
    if (flags & TerminalCellFlags.protected != 0) {
      names.add('protected');
    }
    final int unknown = flags & ~TerminalCellFlags.knownMask;
    if (unknown != 0) {
      names.add('unknown:${_hex(unknown, 2)}');
    }
    return names.join('|');
  }

  static String _rowFlags(int flags) {
    final List<String> names = <String>[];
    if (flags & TerminalRowFlags.softWrapped != 0) {
      names.add('soft-wrapped');
    }
    if (flags & TerminalRowFlags.prompt != 0) {
      names.add('prompt');
    }
    if (flags & TerminalRowFlags.command != 0) {
      names.add('command');
    }
    if (flags & TerminalRowFlags.output != 0) {
      names.add('output');
    }
    if (flags & TerminalRowFlags.hardBreak != 0) {
      names.add('hard-break');
    }
    final int unknown = flags & ~TerminalRowFlags.knownMask;
    if (unknown != 0) {
      names.add('unknown:${_hex(unknown, 2)}');
    }
    return names.isEmpty ? '-' : names.join('|');
  }

  static String _styleAttributes(int attributes) {
    final List<String> names = <String>[];
    if (TerminalStyleAttributes.has(attributes, TerminalStyleAttributes.bold)) {
      names.add('bold');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.faint,
    )) {
      names.add('faint');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.italic,
    )) {
      names.add('italic');
    }
    final TerminalUnderlineStyle underline = TerminalStyleAttributes.underline(
      attributes,
    );
    if (underline != TerminalUnderlineStyle.none) {
      names.add('underline:${underline.name}');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.blink,
    )) {
      names.add('blink');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.inverse,
    )) {
      names.add('inverse');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.conceal,
    )) {
      names.add('conceal');
    }
    if (TerminalStyleAttributes.has(
      attributes,
      TerminalStyleAttributes.strike,
    )) {
      names.add('strike');
    }
    return names.isEmpty ? '-' : names.join('|');
  }

  static String _colorToken(int token) {
    if (token == 0) {
      return 'default';
    }
    if (token <= TerminalPalette.colorCount) {
      return 'palette:${token - 1}';
    }
    return 'rgb:${_directColor(token)}';
  }

  static String _directColor(int color) =>
      '#${(color & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';

  static String _unicodeScalar(int scalar) =>
      'U+${scalar.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  static String _hex(int value, int digits) =>
      '0x${value.toRadixString(16).padLeft(digits, '0')}';
}

final class _SnapshotWriter {
  _SnapshotWriter(this.maximumCharacters);

  final int maximumCharacters;
  final StringBuffer _buffer = StringBuffer();
  int _characters = 0;

  void line(String value) {
    final int next = _characters + value.length + 1;
    if (next > maximumCharacters) {
      throw TerminalSnapshotLimitException(
        resource: 'output characters',
        actual: next,
        limit: maximumCharacters,
      );
    }
    _buffer.writeln(value);
    _characters = next;
  }

  String finish() => _buffer.toString();
}
