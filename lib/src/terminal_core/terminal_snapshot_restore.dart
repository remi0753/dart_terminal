import 'dart:convert';

import 'terminal_hyperlink.dart';
import 'terminal_screen.dart';
import 'terminal_screen_set.dart';
import 'terminal_session_metadata.dart';
import 'terminal_snapshot.dart';
import 'terminal_style.dart';
import 'terminal_unicode.dart';

enum TerminalSnapshotRestoreErrorKind {
  syntax,
  unsupportedVersion,
  limit,
  invariant,
  nonCanonical,
}

/// Bounded failure returned by the versioned text snapshot decoder.
final class TerminalSnapshotRestoreException implements Exception {
  const TerminalSnapshotRestoreException({
    required this.kind,
    required this.line,
    required this.reason,
  });

  final TerminalSnapshotRestoreErrorKind kind;
  final int line;
  final String reason;

  @override
  String toString() =>
      'TerminalSnapshotRestoreException(${kind.name}, line $line): $reason';
}

final class TerminalSnapshotRestoreLimits {
  const TerminalSnapshotRestoreLimits({
    this.maxInputCharacters = 16 * 1024 * 1024,
    this.maxLineCharacters = 64 * 1024,
    this.maxCounterValue = 0x7fffffffffffffff,
    this.format = const TerminalSnapshotFormatLimits(),
  }) : assert(maxInputCharacters > 0),
       assert(maxLineCharacters > 0),
       assert(maxCounterValue >= 0);

  final int maxInputCharacters;
  final int maxLineCharacters;
  final int maxCounterValue;
  final TerminalSnapshotFormatLimits format;
}

enum TerminalSnapshotRestoredKind { screen, screenSet }

/// A fresh, independently owned model restored from one canonical snapshot.
final class TerminalSnapshotRestoreResult {
  const TerminalSnapshotRestoreResult._screen(this.screen, this.parserCounters)
    : kind = TerminalSnapshotRestoredKind.screen,
      screenSet = null;

  const TerminalSnapshotRestoreResult._screenSet(
    this.screenSet,
    this.parserCounters,
  ) : kind = TerminalSnapshotRestoredKind.screenSet,
      screen = null;

  final TerminalSnapshotRestoredKind kind;
  final TerminalScreen? screen;
  final TerminalScreenSet? screenSet;
  final TerminalSnapshotParserCounters? parserCounters;

  String format({TerminalSnapshotFormatLimits? limits}) {
    final TerminalSnapshotFormatter formatter = TerminalSnapshotFormatter(
      limits: limits ?? const TerminalSnapshotFormatLimits(),
    );
    return switch (kind) {
      TerminalSnapshotRestoredKind.screen => formatter.formatScreen(
        screen!,
        parserCounters: parserCounters,
      ),
      TerminalSnapshotRestoredKind.screenSet => formatter.formatScreenSet(
        screenSet!,
        parserCounters: parserCounters,
      ),
    };
  }
}

/// Strict decoder for the current canonical terminal-state snapshot format.
///
/// This is a test/debug restore oracle, not a PTY replay or live-session
/// persistence API. It accepts version 4 only, constructs fresh ownership,
/// validates model invariants, then requires format-restore-format identity.
final class TerminalSnapshotRestorer {
  const TerminalSnapshotRestorer({
    this.limits = const TerminalSnapshotRestoreLimits(),
  });

  final TerminalSnapshotRestoreLimits limits;

  TerminalSnapshotRestoreResult restore(String source) {
    _validateLimits();
    if (source.length > limits.maxInputCharacters) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: 1,
        reason: 'input exceeds configured character limit',
      );
    }
    if (source.length > limits.format.maxOutputCharacters) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: 1,
        reason: 'input exceeds snapshot output character limit',
      );
    }
    final _SnapshotLines lines = _SnapshotLines(
      source,
      maximumLineCharacters: limits.maxLineCharacters,
    );
    try {
      final String header = lines.take();
      final RegExpMatch? match = RegExp(
        r'^dart-terminal-state-snapshot version=([0-9]+) kind=(screen|screen-set)$',
      ).firstMatch(header);
      if (match == null) {
        throw lines.error('invalid snapshot header');
      }
      final int version = _natural(match.group(1)!, lines);
      if (version != TerminalSnapshotFormatter.formatVersion) {
        throw TerminalSnapshotRestoreException(
          kind: TerminalSnapshotRestoreErrorKind.unsupportedVersion,
          line: lines.lastLine,
          reason: 'unsupported snapshot version',
        );
      }
      final _SnapshotDecoder decoder = _SnapshotDecoder(lines, limits);
      final TerminalSnapshotRestoreResult result = match.group(2) == 'screen'
          ? decoder.decodeScreen()
          : decoder.decodeScreenSet();
      final String canonical = result.format(limits: limits.format);
      if (canonical != source) {
        throw TerminalSnapshotRestoreException(
          kind: TerminalSnapshotRestoreErrorKind.nonCanonical,
          line: lines.lastLine,
          reason: 'snapshot is not in canonical form',
        );
      }
      return result;
    } on TerminalSnapshotRestoreException {
      rethrow;
    } on Object {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.invariant,
        line: lines.lastLine,
        reason: 'snapshot violates terminal-state invariants',
      );
    }
  }

  void _validateLimits() {
    if (limits.maxInputCharacters <= 0 ||
        limits.maxLineCharacters <= 0 ||
        limits.maxCounterValue < 0 ||
        limits.format.maxRows <= 0 ||
        limits.format.maxCells <= 0 ||
        limits.format.maxStyleDefinitions < 0 ||
        limits.format.maxGraphemeDefinitions < 0 ||
        limits.format.maxHyperlinkDefinitions < 0 ||
        limits.format.maxHyperlinkUtf8Bytes < 0 ||
        limits.format.maxOutputCharacters <= 0) {
      throw ArgumentError.value(limits, 'limits', 'contains invalid bounds');
    }
  }
}

final class _SnapshotDecoder {
  _SnapshotDecoder(this.lines, this.limits);

  final _SnapshotLines lines;
  final TerminalSnapshotRestoreLimits limits;

  late TerminalStyleTable styles;
  late TerminalGraphemeTable graphemes;
  late TerminalHyperlinkTable hyperlinks;
  late TerminalPalette palette;

  TerminalSnapshotRestoreResult decodeScreen() {
    _decodeResources();
    final TerminalSnapshotScreenState state = _decodeScreenState('screen');
    final TerminalSnapshotParserCounters? counters = _decodeTail();
    final TerminalScreen screen = TerminalScreen(
      rows: state.rows,
      columns: state.columns,
      styleTable: styles,
      palette: palette,
      graphemeTable: graphemes,
      hyperlinkTable: hyperlinks,
    );
    restoreTerminalScreenSnapshotState(screen, state);
    return TerminalSnapshotRestoreResult._screen(screen, counters);
  }

  TerminalSnapshotRestoreResult decodeScreenSet() {
    final RegExpMatch set = _match(
      lines.take(),
      r'^set active=(primary|alternate) mode1049=(true|false) viewport_offset=([0-9]+) primary_viewport_offset=([0-9]+)$',
      'invalid screen-set header',
    );
    final TerminalScreenKind activeKind = set.group(1) == 'primary'
        ? TerminalScreenKind.primary
        : TerminalScreenKind.alternate;
    final bool mode1049 = _boolean(set.group(2)!, lines);
    final int viewportOffset = _natural(set.group(3)!, lines);
    final int primaryViewportOffset = _natural(set.group(4)!, lines);
    final _MetadataState metadata = _decodeMetadata();
    _decodeResources();
    final RegExpMatch historyHeader = _match(
      lines.take(),
      r'^history rows=([0-9]+) max_lines=([0-9]+) max_bytes=([0-9]+) page_rows=([0-9]+)$',
      'invalid history header',
    );
    final int historyCount = _boundedCount(
      historyHeader.group(1)!,
      limits.format.maxRows,
      'history rows',
    );
    final int maxLines = _natural(historyHeader.group(2)!, lines);
    final int maxBytes = _natural(historyHeader.group(3)!, lines);
    final int pageRows = _natural(historyHeader.group(4)!, lines);
    final List<TerminalSnapshotRowState> history = <TerminalSnapshotRowState>[];
    var cellCount = 0;
    for (var row = 0; row < historyCount; row++) {
      final TerminalSnapshotRowState state = _decodeRow('history', row);
      history.add(state);
      cellCount += state.columns;
      _checkCellCount(cellCount);
    }
    final TerminalSnapshotScreenState primary = _decodeScreenState('primary');
    cellCount += primary.rows * primary.columns;
    _checkCellCount(cellCount);
    final TerminalSnapshotScreenState alternate = _decodeScreenState(
      'alternate',
    );
    cellCount += alternate.rows * alternate.columns;
    _checkCellCount(cellCount);
    if (historyCount + primary.rows + alternate.rows > limits.format.maxRows) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: lines.lastLine,
        reason: 'rows exceed configured limit',
      );
    }
    if (primary.rows != alternate.rows ||
        primary.columns != alternate.columns) {
      throw lines.error('screen-set dimensions differ');
    }
    final TerminalSnapshotParserCounters? counters = _decodeTail();
    final List<TerminalSnapshotRowState> countedHistory =
        _withHistoryLogicalCounts(history, primary.rowStates);
    final TerminalScrollback scrollback = TerminalScrollback(
      maxLines: maxLines,
      maxBytes: maxBytes,
      pageRows: pageRows,
    );
    final TerminalScreenSet screens = TerminalScreenSet(
      rows: primary.rows,
      columns: primary.columns,
      styleTable: styles,
      palette: palette,
      graphemeTable: graphemes,
      hyperlinkTable: hyperlinks,
      scrollback: scrollback,
    );
    restoreTerminalScreenSnapshotState(screens.primary, primary);
    restoreTerminalScreenSnapshotState(screens.alternate, alternate);
    restoreTerminalScrollbackSnapshotState(
      scrollback,
      countedHistory,
      styles,
      graphemes,
      hyperlinks,
    );
    restoreTerminalSessionMetadataSnapshotState(
      screens.metadata,
      windowTitle: metadata.windowTitle,
      iconTitle: metadata.iconTitle,
      workingDirectory: metadata.workingDirectory,
      windowTitleStack: metadata.windowTitleStack,
      iconTitleStack: metadata.iconTitleStack,
    );
    restoreTerminalScreenSetSnapshotState(
      screens,
      activeKind: activeKind,
      mode1049Active: mode1049,
      viewportOffset: viewportOffset,
      primaryViewportOffset: primaryViewportOffset,
    );
    return TerminalSnapshotRestoreResult._screenSet(screens, counters);
  }

  _MetadataState _decodeMetadata() {
    final _FieldCursor cursor = _FieldCursor(lines.take(), lines);
    cursor.expect('metadata window_title=');
    final String? windowTitle = cursor.takeNullableString();
    cursor.expect(' icon_title=');
    final String? iconTitle = cursor.takeNullableString();
    cursor.expect(' cwd=');
    final String? cwd = cursor.takeNullableString();
    cursor.expect(' window_title_stack=');
    final List<String?> windowStack = cursor.takeNullableStringList();
    cursor.expect(' icon_title_stack=');
    final List<String?> iconStack = cursor.takeNullableStringList();
    cursor.finish();
    return _MetadataState(
      windowTitle,
      iconTitle,
      cwd == null ? null : Uri.parse(cwd),
      windowStack,
      iconStack,
    );
  }

  void _decodeResources() {
    final RegExpMatch header = _match(
      lines.take(),
      r'^resources styles=([0-9]+) graphemes=([0-9]+) palette=([0-9]+)$',
      'invalid resource header',
    );
    final int styleCount = _boundedCount(
      header.group(1)!,
      limits.format.maxStyleDefinitions,
      'style definitions',
    );
    final int graphemeCount = _boundedCount(
      header.group(2)!,
      limits.format.maxGraphemeDefinitions,
      'grapheme definitions',
    );
    if (_natural(header.group(3)!, lines) != TerminalPalette.colorCount) {
      throw lines.error('unsupported palette size');
    }
    styles = TerminalStyleTable(capacity: styleCount == 0 ? 1 : styleCount);
    for (var id = 1; id <= styleCount; id++) {
      final RegExpMatch style = _match(
        lines.take(),
        r'^style id=([0-9]+) attributes=([^ ]+) bits=(0x[0-9a-f]+) underline_color=([^ ]+)$',
        'invalid style definition',
      );
      if (_natural(style.group(1)!, lines) != id) {
        throw lines.error('style definitions are not contiguous');
      }
      final int attributes = _hex(style.group(3)!, lines);
      final int underlineColor = _color(style.group(4)!, lines);
      if (styles.intern(attributes, underlineColor: underlineColor) != id) {
        throw lines.error('duplicate style definition');
      }
    }
    final List<List<int>> stagedGraphemes = <List<int>>[];
    final List<int> stagedWidths = <int>[];
    var scalarCount = 0;
    var maximumCluster = 1;
    for (var id = 1; id <= graphemeCount; id++) {
      final RegExpMatch grapheme = _match(
        lines.take(),
        r'^grapheme id=([0-9]+) width=([0-9]+) scalars=([^ ]+) text=(.+)$',
        'invalid grapheme definition',
      );
      if (_natural(grapheme.group(1)!, lines) != id) {
        throw lines.error('grapheme definitions are not contiguous');
      }
      final List<int> scalars = grapheme
          .group(3)!
          .split(',')
          .map((String value) => _scalar(value, lines))
          .toList(growable: false);
      final Object? readable = _json(grapheme.group(4)!, lines);
      if (readable is! String) {
        throw lines.error('invalid grapheme display text');
      }
      stagedGraphemes.add(scalars);
      stagedWidths.add(_natural(grapheme.group(2)!, lines));
      scalarCount += scalars.length;
      if (scalars.length > maximumCluster) maximumCluster = scalars.length;
    }
    graphemes = TerminalGraphemeTable(
      capacity: graphemeCount == 0 ? 1 : graphemeCount,
      maximumScalarCount: scalarCount == 0 ? 1 : scalarCount,
      maximumClusterLength: maximumCluster,
    );
    for (var index = 0; index < stagedGraphemes.length; index++) {
      final int id = graphemes.intern(stagedGraphemes[index]);
      if (id != index + 1 || graphemes.widthAt(id) != stagedWidths[index]) {
        throw lines.error('invalid or duplicate grapheme definition');
      }
    }
    final List<(String?, String)> stagedLinks = <(String?, String)>[];
    var declaredUtf8Bytes = 0;
    if (lines.peek().startsWith('hyperlinks ')) {
      final RegExpMatch linkHeader = _match(
        lines.take(),
        r'^hyperlinks count=([0-9]+) utf8_bytes=([0-9]+)$',
        'invalid hyperlink header',
      );
      final int linkCount = _boundedCount(
        linkHeader.group(1)!,
        limits.format.maxHyperlinkDefinitions,
        'hyperlink definitions',
      );
      declaredUtf8Bytes = _boundedCount(
        linkHeader.group(2)!,
        limits.format.maxHyperlinkUtf8Bytes,
        'hyperlink UTF-8 bytes',
      );
      for (var id = 1; id <= linkCount; id++) {
        final _FieldCursor cursor = _FieldCursor(lines.take(), lines);
        cursor.expect('hyperlink id=$id explicit_id=');
        final String? explicitId = cursor.takeNullableString();
        cursor.expect(' uri=');
        final String? uri = cursor.takeNullableString();
        cursor.finish();
        if (uri == null) throw lines.error('hyperlink URI cannot be null');
        stagedLinks.add((explicitId, uri));
      }
    }
    var maximumDefinitionBytes = 1;
    for (final (String? explicitId, String uri) in stagedLinks) {
      final int bytes =
          utf8.encode(uri).length +
          (explicitId == null ? 0 : utf8.encode(explicitId).length);
      if (bytes > maximumDefinitionBytes) maximumDefinitionBytes = bytes;
    }
    hyperlinks = TerminalHyperlinkTable(
      capacity: stagedLinks.isEmpty ? 1 : stagedLinks.length,
      maximumUtf8Bytes: declaredUtf8Bytes == 0 ? 1 : declaredUtf8Bytes,
      maximumDefinitionUtf8Bytes: maximumDefinitionBytes,
    );
    for (var index = 0; index < stagedLinks.length; index++) {
      final (String? explicitId, String uri) = stagedLinks[index];
      if (hyperlinks.tryIntern(uri: uri, explicitId: explicitId) != index + 1) {
        throw lines.error('invalid or duplicate hyperlink definition');
      }
    }
    final RegExpMatch defaults = _match(
      lines.take(),
      r'^palette defaults foreground=(#[0-9a-f]{6}) background=(#[0-9a-f]{6}) cursor=(#[0-9a-f]{6})$',
      'invalid palette defaults',
    );
    final List<int> colors = <int>[];
    for (var start = 0; start < TerminalPalette.colorCount; start += 16) {
      final String expectedRange =
          '${start.toString().padLeft(3, '0')}-${(start + 15).toString().padLeft(3, '0')}';
      final RegExpMatch range = _match(
        lines.take(),
        r'^palette range=([0-9]{3}-[0-9]{3}) colors=(.+)$',
        'invalid palette range',
      );
      if (range.group(1) != expectedRange) {
        throw lines.error('palette ranges are not contiguous');
      }
      final List<String> values = range.group(2)!.split(',');
      if (values.length != 16) throw lines.error('invalid palette range size');
      colors.addAll(values.map((String value) => _directColor(value, lines)));
    }
    palette = TerminalPalette(
      colors: colors,
      defaultForeground: _directColor(defaults.group(1)!, lines),
      defaultBackground: _directColor(defaults.group(2)!, lines),
      cursorColor: _directColor(defaults.group(3)!, lines),
    );
  }

  TerminalSnapshotScreenState _decodeScreenState(String name) {
    final RegExpMatch header = _match(
      lines.take(),
      '^screen name=$name rows=([0-9]+) columns=([0-9]+)\$',
      'invalid $name screen header',
    );
    final int rows = _boundedCount(
      header.group(1)!,
      limits.format.maxRows,
      '$name rows',
    );
    final int columns = _natural(header.group(2)!, lines);
    validateTerminalScreenDimensions(rows, columns);
    _checkCellCount(rows * columns);
    final RegExpMatch cursor = _match(
      lines.take(),
      '^$name cursor=([0-9]+),([0-9]+) saved=([0-9]+),([0-9]+) current=([^/]+)/([^/]+)/([0-9]+) saved_rendition=([^/]+)/([^/]+)/([0-9]+) protection=current:(true|false),saved:(true|false)\$',
      'invalid $name cursor state',
    );
    final RegExpMatch charsets = _match(
      lines.take(),
      '^$name charsets=g0:([^,]+),g1:([^,]+),gl:([0-9]+) saved=g0:([^,]+),g1:([^,]+),gl:([0-9]+)\$',
      'invalid $name character sets',
    );
    final RegExpMatch margins = _match(
      lines.take(),
      '^$name margins=([0-9]+),([0-9]+),([0-9]+),([0-9]+) modes=(.+)\$',
      'invalid $name margins or modes',
    );
    final RegExpMatch presentation = _match(
      lines.take(),
      '^$name cursor_style=([^ ]+) visible=(true|false) blinking=(true|false) wrap_pending=(true|false)\$',
      'invalid $name cursor presentation',
    );
    final RegExpMatch tabs = _match(
      lines.take(),
      '^$name tabs=(-|[0-9]+(?:,[0-9]+)*)\$',
      'invalid $name tab stops',
    );
    final List<TerminalSnapshotRowState> rowStates =
        <TerminalSnapshotRowState>[];
    for (var row = 0; row < rows; row++) {
      rowStates.add(_decodeRow(name, row, columns: columns));
    }
    return TerminalSnapshotScreenState(
      rows: rows,
      columns: columns,
      cursorRow: _natural(cursor.group(1)!, lines),
      cursorColumn: _natural(cursor.group(2)!, lines),
      savedCursorRow: _natural(cursor.group(3)!, lines),
      savedCursorColumn: _natural(cursor.group(4)!, lines),
      currentForeground: _color(cursor.group(5)!, lines),
      currentBackground: _color(cursor.group(6)!, lines),
      currentStyle: _natural(cursor.group(7)!, lines),
      savedForeground: _color(cursor.group(8)!, lines),
      savedBackground: _color(cursor.group(9)!, lines),
      savedStyle: _natural(cursor.group(10)!, lines),
      currentProtected: _boolean(cursor.group(11)!, lines),
      savedProtected: _boolean(cursor.group(12)!, lines),
      g0: _characterSet(charsets.group(1)!),
      g1: _characterSet(charsets.group(2)!),
      gl: _natural(charsets.group(3)!, lines),
      savedG0: _characterSet(charsets.group(4)!),
      savedG1: _characterSet(charsets.group(5)!),
      savedGl: _natural(charsets.group(6)!, lines),
      topMargin: _natural(margins.group(1)!, lines),
      bottomMargin: _natural(margins.group(2)!, lines),
      leftMargin: _natural(margins.group(3)!, lines),
      rightMargin: _natural(margins.group(4)!, lines),
      modes: _modes(margins.group(5)!),
      cursorShape: _cursorShape(presentation.group(1)!),
      cursorVisible: _boolean(presentation.group(2)!, lines),
      cursorBlinking: _boolean(presentation.group(3)!, lines),
      wrapPending: _boolean(presentation.group(4)!, lines),
      tabStops: tabs.group(1) == '-'
          ? const <int>[]
          : tabs
                .group(1)!
                .split(',')
                .map((String value) {
                  return _natural(value, lines);
                })
                .toList(growable: false),
      rowStates: rowStates,
    );
  }

  TerminalSnapshotRowState _decodeRow(String section, int row, {int? columns}) {
    final RegExpMatch match = section == 'history'
        ? _match(
            lines.take(),
            r'^history row=([0-9]+) columns=([0-9]+) flags=([^ ]+) logical=([0-9]+):([0-9]+)\+([0-9]+) text=(.+)$',
            'invalid history row',
          )
        : _match(
            lines.take(),
            '^$section row=([0-9]+) flags=([^ ]+) logical=([0-9]+):([0-9]+)\\+([0-9]+) text=(.+)\$',
            'invalid $section row',
          );
    if (_natural(match.group(1)!, lines) != row) {
      throw lines.error('$section rows are not contiguous');
    }
    final int actualColumns = section == 'history'
        ? _natural(match.group(2)!, lines)
        : columns!;
    final int shift = section == 'history' ? 1 : 0;
    final Object? readable = _json(match.group(6 + shift)!, lines);
    if (readable is! String) throw lines.error('invalid row display text');
    final List<TerminalSnapshotCellState> cells = <TerminalSnapshotCellState>[];
    while (lines.hasNext && lines.peek().startsWith('$section cell=$row,')) {
      final RegExpMatch cell = _match(
        lines.take(),
        '^$section cell=([0-9]+),([0-9]+) content=([^ ]+) flags=([^ ]+) foreground=([^ ]+) background=([^ ]+) style=([0-9]+) hyperlink=([0-9]+)\$',
        'invalid $section cell',
      );
      final int flags = _cellFlags(cell.group(4)!);
      cells.add(
        TerminalSnapshotCellState(
          row: _natural(cell.group(1)!, lines),
          column: _natural(cell.group(2)!, lines),
          content: _content(cell.group(3)!, flags),
          flags: flags,
          foreground: _color(cell.group(5)!, lines),
          background: _color(cell.group(6)!, lines),
          style: _natural(cell.group(7)!, lines),
          hyperlink: _natural(cell.group(8)!, lines),
        ),
      );
    }
    return TerminalSnapshotRowState(
      columns: actualColumns,
      flags: _rowFlags(match.group(2 + shift)!),
      logicalLineEpoch: _natural(match.group(3 + shift)!, lines),
      logicalLineId: _natural(match.group(4 + shift)!, lines),
      logicalCellOffset: _natural(match.group(5 + shift)!, lines),
      cells: cells,
    );
  }

  TerminalSnapshotParserCounters? _decodeTail() {
    TerminalSnapshotParserCounters? counters;
    if (lines.peek().startsWith('parser ')) {
      final RegExpMatch parser = _match(
        lines.take(),
        r'^parser unsupported_controls=([0-9]+) unsupported_sequences=([0-9]+) cancel=([0-9]+) limit=([0-9]+) malformed=([0-9]+) incomplete=([0-9]+) replies_accepted=([0-9]+) replies_rejected=([0-9]+)$',
        'invalid parser counters',
      );
      final List<int> values = <int>[
        for (var index = 1; index <= 8; index++)
          _boundedCount(
            parser.group(index)!,
            limits.maxCounterValue,
            'parser counter',
          ),
      ];
      counters = TerminalSnapshotParserCounters(
        unsupportedControls: values[0],
        unsupportedSequences: values[1],
        cancel: values[2],
        limit: values[3],
        malformed: values[4],
        incomplete: values[5],
        repliesAccepted: values[6],
        repliesRejected: values[7],
      );
    }
    if (lines.take() != 'end' || lines.hasNext) {
      throw lines.error('missing end marker or trailing data');
    }
    return counters;
  }

  List<TerminalSnapshotRowState> _withHistoryLogicalCounts(
    List<TerminalSnapshotRowState> history,
    List<TerminalSnapshotRowState> primary,
  ) {
    final List<TerminalSnapshotRowState> result = <TerminalSnapshotRowState>[];
    for (var index = 0; index < history.length; index++) {
      final TerminalSnapshotRowState row = history[index];
      final TerminalSnapshotRowState? next = index + 1 < history.length
          ? history[index + 1]
          : (primary.isEmpty ? null : primary.first);
      int count = _visibleLogicalCount(row);
      if (next != null &&
          row.flags & TerminalRowFlags.softWrapped != 0 &&
          row.logicalLineId == next.logicalLineId &&
          row.logicalLineEpoch == next.logicalLineEpoch) {
        count = next.logicalCellOffset - row.logicalCellOffset;
      }
      result.add(
        TerminalSnapshotRowState(
          columns: row.columns,
          flags: row.flags,
          logicalLineId: row.logicalLineId,
          logicalLineEpoch: row.logicalLineEpoch,
          logicalCellOffset: row.logicalCellOffset,
          logicalCellCount: count,
          cells: row.cells,
        ),
      );
    }
    return result;
  }

  int _visibleLogicalCount(TerminalSnapshotRowState row) {
    var extent = 0;
    for (final TerminalSnapshotCellState cell in row.cells) {
      if (cell.column + 1 > extent) extent = cell.column + 1;
    }
    var count = 0;
    final Map<int, int> flags = <int, int>{
      for (final TerminalSnapshotCellState cell in row.cells)
        cell.column: cell.flags,
    };
    for (var column = 0; column < extent; column++) {
      if ((flags[column] ?? TerminalCellFlags.narrow) &
              TerminalCellFlags.widthMask !=
          TerminalCellFlags.continuation) {
        count++;
      }
    }
    return count;
  }

  int _boundedCount(String source, int maximum, String resource) {
    final int value = _natural(source, lines);
    if (value > maximum) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: lines.lastLine,
        reason: '$resource exceeds configured limit',
      );
    }
    return value;
  }

  void _checkCellCount(int count) {
    if (count > limits.format.maxCells) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: lines.lastLine,
        reason: 'cells exceed configured limit',
      );
    }
  }

  RegExpMatch _match(String source, String expression, String reason) {
    final RegExpMatch? match = RegExp(expression).firstMatch(source);
    if (match == null) throw lines.error(reason);
    return match;
  }

  TerminalCharacterSet _characterSet(String value) => switch (value) {
    'ascii' => TerminalCharacterSet.ascii,
    'decSpecialGraphics' => TerminalCharacterSet.decSpecialGraphics,
    _ => throw lines.error('unknown character set'),
  };

  TerminalCursorShape _cursorShape(String value) => switch (value) {
    'block' => TerminalCursorShape.block,
    'underline' => TerminalCursorShape.underline,
    'bar' => TerminalCursorShape.bar,
    _ => throw lines.error('unknown cursor shape'),
  };

  List<bool> _modes(String value) {
    final List<String> tokens = value.split(',');
    if (tokens.length != TerminalScreenMode.values.length) {
      throw lines.error('invalid screen mode count');
    }
    return <bool>[
      for (var index = 0; index < tokens.length; index++)
        _namedBoolean(tokens[index], TerminalScreenMode.values[index].name),
    ];
  }

  bool _namedBoolean(String token, String name) {
    if (!token.startsWith('$name:')) throw lines.error('invalid screen mode');
    return _boolean(token.substring(name.length + 1), lines);
  }

  int _rowFlags(String source) {
    if (source == '-') return 0;
    var result = 0;
    for (final String value in source.split('|')) {
      final int flag = switch (value) {
        'soft-wrapped' => TerminalRowFlags.softWrapped,
        'prompt' => TerminalRowFlags.prompt,
        'command' => TerminalRowFlags.command,
        'output' => TerminalRowFlags.output,
        'hard-break' => TerminalRowFlags.hardBreak,
        _ => throw lines.error('unknown row flag'),
      };
      if (result & flag != 0) throw lines.error('duplicate row flag');
      result |= flag;
    }
    return result;
  }

  int _cellFlags(String source) {
    var result = 0;
    var hasWidth = false;
    for (final String value in source.split('|')) {
      switch (value) {
        case 'continuation':
          if (hasWidth) throw lines.error('duplicate cell width');
          hasWidth = true;
        case 'narrow':
          if (hasWidth) throw lines.error('duplicate cell width');
          result |= TerminalCellFlags.narrow;
          hasWidth = true;
        case 'wide':
          if (hasWidth) throw lines.error('duplicate cell width');
          result |= TerminalCellFlags.wide;
          hasWidth = true;
        case 'grapheme':
          if (result & TerminalCellFlags.grapheme != 0) {
            throw lines.error('duplicate grapheme flag');
          }
          result |= TerminalCellFlags.grapheme;
        case 'protected':
          if (result & TerminalCellFlags.protected != 0) {
            throw lines.error('duplicate protected flag');
          }
          result |= TerminalCellFlags.protected;
        default:
          throw lines.error('unknown cell flag');
      }
    }
    if (!hasWidth) throw lines.error('cell width is missing');
    return result;
  }

  int _content(String source, int flags) {
    if (source == 'continuation' || source == 'blank') return 0;
    if (source.startsWith('grapheme:')) {
      return _natural(source.substring(9), lines);
    }
    return _scalar(source, lines);
  }

  int _color(String source, _SnapshotLines lines) {
    if (source == 'default') return 0;
    if (source.startsWith('palette:')) {
      final int index = _natural(source.substring(8), lines);
      if (index >= TerminalPalette.colorCount) {
        throw lines.error('palette color is out of range');
      }
      return index + 1;
    }
    if (source.startsWith('rgb:')) {
      return _directColor(source.substring(4), lines);
    }
    throw lines.error('invalid color token');
  }
}

final class _MetadataState {
  const _MetadataState(
    this.windowTitle,
    this.iconTitle,
    this.workingDirectory,
    this.windowTitleStack,
    this.iconTitleStack,
  );

  final String? windowTitle;
  final String? iconTitle;
  final Uri? workingDirectory;
  final List<String?> windowTitleStack;
  final List<String?> iconTitleStack;
}

final class _SnapshotLines {
  _SnapshotLines(this.source, {required this.maximumLineCharacters});

  final String source;
  final int maximumLineCharacters;
  int _offset = 0;
  int _nextLine = 1;
  int lastLine = 1;
  String? _peeked;

  bool get hasNext => _peeked != null || _offset < source.length;

  String peek() => _peeked ??= _read();

  String take() {
    final String result = _peeked ?? _read();
    _peeked = null;
    return result;
  }

  String _read() {
    if (_offset >= source.length) throw error('unexpected end of snapshot');
    final int newline = source.indexOf('\n', _offset);
    if (newline < 0) throw error('snapshot line is not newline terminated');
    final int length = newline - _offset;
    if (length > maximumLineCharacters) {
      throw TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.limit,
        line: _nextLine,
        reason: 'line exceeds configured character limit',
      );
    }
    final String result = source.substring(_offset, newline);
    lastLine = _nextLine++;
    _offset = newline + 1;
    return result;
  }

  TerminalSnapshotRestoreException error(String reason) =>
      TerminalSnapshotRestoreException(
        kind: TerminalSnapshotRestoreErrorKind.syntax,
        line: lastLine,
        reason: reason,
      );
}

final class _FieldCursor {
  _FieldCursor(this.source, this.lines);

  final String source;
  final _SnapshotLines lines;
  int offset = 0;

  void expect(String value) {
    if (!source.startsWith(value, offset)) throw lines.error('invalid field');
    offset += value.length;
  }

  String? takeNullableString() {
    final Object? value = _takeJson();
    if (value != null && value is! String) {
      throw lines.error('field must be a string or null');
    }
    return value as String?;
  }

  List<String?> takeNullableStringList() {
    final Object? value = _takeJson();
    if (value is! List<Object?> ||
        value.any((Object? item) => item != null && item is! String)) {
      throw lines.error('field must be a string-or-null list');
    }
    return value.cast<String?>();
  }

  Object? _takeJson() {
    final int end = _jsonValueEnd(source, offset, lines);
    final Object? value = _json(source.substring(offset, end), lines);
    offset = end;
    return value;
  }

  void finish() {
    if (offset != source.length) throw lines.error('trailing field data');
  }
}

int _jsonValueEnd(String source, int start, _SnapshotLines lines) {
  if (source.startsWith('null', start)) return start + 4;
  if (start >= source.length) throw lines.error('missing JSON value');
  final int first = source.codeUnitAt(start);
  if (first == 0x22) {
    var escaped = false;
    for (var index = start + 1; index < source.length; index++) {
      final int unit = source.codeUnitAt(index);
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        return index + 1;
      }
    }
  } else if (first == 0x5b) {
    var inString = false;
    var escaped = false;
    for (var index = start + 1; index < source.length; index++) {
      final int unit = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
        }
      } else if (unit == 0x22) {
        inString = true;
      } else if (unit == 0x5d) {
        return index + 1;
      }
    }
  }
  throw lines.error('unterminated JSON value');
}

Object? _json(String source, _SnapshotLines lines) {
  try {
    return jsonDecode(source);
  } on FormatException {
    throw lines.error('invalid JSON value');
  }
}

int _natural(String source, _SnapshotLines lines) {
  final int? value = int.tryParse(source);
  if (value == null || value < 0) throw lines.error('invalid integer');
  return value;
}

int _hex(String source, _SnapshotLines lines) {
  if (!source.startsWith('0x')) throw lines.error('invalid hexadecimal value');
  final int? value = int.tryParse(source.substring(2), radix: 16);
  if (value == null) throw lines.error('invalid hexadecimal value');
  return value;
}

int _scalar(String source, _SnapshotLines lines) {
  if (!source.startsWith('U+')) throw lines.error('invalid Unicode scalar');
  final int? value = int.tryParse(source.substring(2), radix: 16);
  if (value == null) throw lines.error('invalid Unicode scalar');
  TerminalUnicode.validateScalar(value);
  return value;
}

int _directColor(String source, _SnapshotLines lines) {
  if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(source)) {
    throw lines.error('invalid direct color');
  }
  return 0x80000000 | int.parse(source.substring(1), radix: 16);
}

bool _boolean(String source, _SnapshotLines lines) => switch (source) {
  'true' => true,
  'false' => false,
  _ => throw lines.error('invalid boolean'),
};
