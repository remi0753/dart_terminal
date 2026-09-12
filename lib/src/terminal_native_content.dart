import 'terminal_core/terminal_mouse_modes.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_input/terminal_paste.dart';

/// One terminal cell resolved from native View-local coordinates.
final class TerminalNativeContentCell {
  const TerminalNativeContentCell({required this.row, required this.column});

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is TerminalNativeContentCell &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// Native definition baseline derived from stable terminal cell geometry.
final class TerminalDefinitionPlacement {
  const TerminalDefinitionPlacement({
    required this.baselineX,
    required this.baselineY,
  });

  final double baselineX;
  final double baselineY;
}

/// Suppresses every native context-click phase from terminal mouse routing.
final class TerminalNativeContextGestureGate<T> {
  final Set<T> _activeTargets = <T>{};

  bool suppress({
    required T target,
    required bool isButtonDown,
    required bool isButtonUp,
    required bool startsNativeContextGesture,
  }) {
    if (isButtonDown) _activeTargets.remove(target);
    if (_activeTargets.contains(target) && !isButtonDown) {
      if (isButtonUp) _activeTargets.remove(target);
      return true;
    }
    if (startsNativeContextGesture) {
      _activeTargets.add(target);
      return true;
    }
    return false;
  }

  void cancel(T target) {
    _activeTargets.remove(target);
  }

  void clear() {
    _activeTargets.clear();
  }
}

/// Native-neutral policy shared by context-menu, Quick Look, and Services.
abstract final class TerminalNativeContentPolicy {
  static bool contextMenuAvailable({
    required bool isLive,
    required TerminalMouseModes mouseModes,
  }) => isLive && !mouseModes.reportingEnabled;

  static bool isContextGesture({
    required bool isButtonDown,
    required int button,
    required bool control,
  }) => isButtonDown && (button == 1 || button == 0 && control);

  static TerminalNativeContentCell? cellAtPoint({
    required double x,
    required double y,
    required double contentOriginX,
    required double contentOriginY,
    required double cellWidth,
    required double cellHeight,
    required int rows,
    required int columns,
  }) {
    if (!x.isFinite ||
        !y.isFinite ||
        !contentOriginX.isFinite ||
        !contentOriginY.isFinite ||
        !cellWidth.isFinite ||
        !cellHeight.isFinite ||
        cellWidth <= 0 ||
        cellHeight <= 0 ||
        rows <= 0 ||
        columns <= 0) {
      return null;
    }
    final double localX = x - contentOriginX;
    final double localY = y - contentOriginY;
    if (localX < 0 || localY < 0) return null;
    final int column = (localX / cellWidth).floor();
    final int row = (localY / cellHeight).floor();
    if (row >= rows || column >= columns) return null;
    return TerminalNativeContentCell(row: row, column: column);
  }

  static TerminalNativeContentCell? cursorCell({
    required TerminalViewport viewport,
    required int cursorRow,
    required int cursorColumn,
  }) {
    if (viewport.offset != 0 ||
        cursorRow < 0 ||
        cursorRow >= viewport.rows ||
        cursorColumn < 0 ||
        cursorColumn >= viewport.columns ||
        cursorColumn >= viewport.columnsAt(cursorRow)) {
      return null;
    }
    return TerminalNativeContentCell(row: cursorRow, column: cursorColumn);
  }

  static TerminalDefinitionPlacement? definitionPlacement({
    required TerminalWordCandidate candidate,
    required double contentOriginX,
    required double contentOriginY,
    required double cellWidth,
    required double cellHeight,
    required double fontBaseline,
  }) {
    if (!contentOriginX.isFinite ||
        !contentOriginY.isFinite ||
        !cellWidth.isFinite ||
        !cellHeight.isFinite ||
        !fontBaseline.isFinite ||
        cellWidth <= 0 ||
        cellHeight <= 0 ||
        fontBaseline < 0 ||
        fontBaseline > cellHeight) {
      return null;
    }
    return TerminalDefinitionPlacement(
      baselineX: contentOriginX + candidate.baselineColumn * cellWidth,
      baselineY:
          contentOriginY + candidate.baselineRow * cellHeight + fontBaseline,
    );
  }

  static String? servicesSelection(TerminalSelectionText? selection) {
    if (selection == null || selection.isTruncated || selection.text.isEmpty) {
      return null;
    }
    final TerminalExternalContentResult admitted =
        TerminalExternalContentAdmission.text(
          selection.text,
          source: TerminalExternalTextSource.service,
        );
    return admitted.content?.text;
  }

  static String? localFilePath(Uri fileUrl) {
    if (fileUrl.scheme != 'file' ||
        fileUrl.userInfo.isNotEmpty ||
        fileUrl.hasPort ||
        fileUrl.hasQuery ||
        fileUrl.hasFragment ||
        fileUrl.host.isNotEmpty && fileUrl.host.toLowerCase() != 'localhost') {
      return null;
    }
    try {
      final String path = Uri(path: fileUrl.path).toFilePath(windows: false);
      final TerminalExternalContentResult admitted =
          TerminalExternalContentAdmission.filePaths(<String>[path]);
      return admitted.isAdmitted ? path : null;
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  static String? folderWorkingDirectory(Uri directoryUrl) =>
      localFilePath(directoryUrl);
}

/// Why a terminal word cannot be offered to native Quick Look.
enum TerminalWordLookupDisposition {
  available,
  outsideViewport,
  unavailable,
  whitespace,
  boundaryLimited,
  tooLarge,
  stale,
}

/// One bounded word and its stable terminal geometry.
final class TerminalWordCandidate {
  const TerminalWordCandidate._({
    required this.text,
    required this.range,
    required this.viewportGeneration,
    required this.pointerRow,
    required this.pointerColumn,
    required this.baselineRow,
    required this.baselineColumn,
  });

  final String text;
  final TerminalSelectionRange range;
  final int viewportGeneration;
  final int pointerRow;
  final int pointerColumn;
  final int baselineRow;
  final int baselineColumn;
}

/// Typed result that never substitutes a partial or stale Quick Look word.
final class TerminalWordLookupResult {
  const TerminalWordLookupResult._(this.disposition, this.candidate);

  const TerminalWordLookupResult.rejected(
    TerminalWordLookupDisposition disposition,
  ) : this._(disposition, null);

  const TerminalWordLookupResult.available(TerminalWordCandidate candidate)
    : this._(TerminalWordLookupDisposition.available, candidate);

  final TerminalWordLookupDisposition disposition;
  final TerminalWordCandidate? candidate;

  bool get isAvailable =>
      disposition == TerminalWordLookupDisposition.available;
}

/// Resolves native pointer/caret coordinates through the canonical viewport.
abstract final class TerminalWordLookup {
  static const int defaultMaximumScalars = 256;
  static const int maximumScalars = 4096;

  static TerminalWordLookupResult atCell(
    TerminalViewport viewport,
    int row,
    int column, {
    int maxWordScanCells = TerminalSelectionRange.defaultMaxWordScanCells,
    int maxScalars = defaultMaximumScalars,
  }) {
    RangeError.checkValueInInterval(
      maxWordScanCells,
      1,
      TerminalSelectionRange.maximumWordScanCells,
      'maxWordScanCells',
    );
    RangeError.checkValueInInterval(
      maxScalars,
      1,
      maximumScalars,
      'maxScalars',
    );
    if (row < 0 ||
        row >= viewport.rows ||
        column < 0 ||
        column >= viewport.columns) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.outsideViewport,
      );
    }
    final int sourceColumns = viewport.columnsAt(row);
    if (column >= sourceColumns) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.outsideViewport,
      );
    }
    final int generation = viewport.generation;
    final TerminalLogicalAnchor focus = viewport.anchorAt(row, column);
    final TerminalSelectionRange? range = viewport.selectionRange(
      focus,
      focus,
      unit: TerminalSelectionUnit.word,
      maxWordScanCells: maxWordScanCells,
    );
    if (range == null) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.unavailable,
      );
    }
    if (range.isBoundaryLimited) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.boundaryLimited,
      );
    }
    final TerminalSelectionText? selected = viewport.extractSelection(
      range,
      maxScalars: maxScalars,
    );
    if (selected == null) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.unavailable,
      );
    }
    if (selected.isTruncated) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.tooLarge,
      );
    }
    if (selected.text.isEmpty || _isOnlyWhitespace(selected.text)) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.whitespace,
      );
    }
    final TerminalViewportPosition? baseline = viewport.positionOf(range.start);
    if (baseline == null || viewport.generation != generation) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    return TerminalWordLookupResult.available(
      TerminalWordCandidate._(
        text: selected.text,
        range: range,
        viewportGeneration: generation,
        pointerRow: row,
        pointerColumn: column,
        baselineRow: baseline.row,
        baselineColumn: baseline.column,
      ),
    );
  }

  static TerminalWordLookupResult revalidate(
    TerminalViewport viewport,
    TerminalWordCandidate candidate,
  ) {
    if (viewport.generation != candidate.viewportGeneration ||
        !viewport.isSelectionAvailable(candidate.range)) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    final TerminalSelectionText? selected = viewport.extractSelection(
      candidate.range,
      maxScalars: maximumScalars,
    );
    if (selected == null ||
        selected.isTruncated ||
        selected.text != candidate.text) {
      return const TerminalWordLookupResult.rejected(
        TerminalWordLookupDisposition.stale,
      );
    }
    return TerminalWordLookupResult.available(candidate);
  }
}

enum TerminalExternalContentKind { text, filePaths }

enum TerminalExternalTextSource { service, drop, appleScript }

enum TerminalExternalContentDisposition {
  admitted,
  empty,
  invalidPath,
  tooManyItems,
  tooLarge,
}

/// External text admitted for later paste planning; it is not a PTY write.
final class TerminalExternalContent {
  const TerminalExternalContent._({
    required this.kind,
    required this.textSource,
    required this.text,
    required this.utf8Bytes,
    required this.itemCount,
  });

  final TerminalExternalContentKind kind;
  final TerminalExternalTextSource textSource;
  final String text;
  final int utf8Bytes;
  final int itemCount;
}

final class TerminalExternalContentResult {
  const TerminalExternalContentResult._(this.disposition, this.content);

  const TerminalExternalContentResult.rejected(
    TerminalExternalContentDisposition disposition,
  ) : this._(disposition, null);

  const TerminalExternalContentResult.admitted(TerminalExternalContent content)
    : this._(TerminalExternalContentDisposition.admitted, content);

  final TerminalExternalContentDisposition disposition;
  final TerminalExternalContent? content;

  bool get isAdmitted =>
      disposition == TerminalExternalContentDisposition.admitted;
}

enum TerminalExternalPasteDisposition {
  completed,
  confirmationRequired,
  staleTarget,
  busy,
  tooLarge,
  transferIncomplete,
  disposed,
}

/// One resolved live target; [identity] must remain identical across planning.
final class TerminalExternalPasteTarget {
  const TerminalExternalPasteTarget({
    required this.identity,
    required this.bracketedPasteMode,
    required this.pasteInProgress,
    required this.showNotice,
    required this.paste,
  });

  final Object identity;
  final bool bracketedPasteMode;
  final bool pasteInProgress;
  final void Function(TerminalClipboardNotice notice) showNotice;
  final Future<TerminalPasteTransferResult> Function(TerminalPastePlan plan)
  paste;
}

final class TerminalExternalPasteResult {
  const TerminalExternalPasteResult(
    this.disposition, {
    this.analysis,
    this.transfer,
  });

  final TerminalExternalPasteDisposition disposition;
  final TerminalPasteAnalysis? analysis;
  final TerminalPasteTransferResult? transfer;
}

typedef TerminalExternalPasteTargetResolver<T> =
    TerminalExternalPasteTarget? Function(T identity);

/// Applies ordinary paste planning, confirmation, and transport to native data.
final class TerminalExternalPasteController<T> {
  factory TerminalExternalPasteController({
    required TerminalExternalPasteTargetResolver<T> resolveTarget,
    TerminalPasteConfirmationGate? confirmationGate,
    int Function()? monotonicMicros,
  }) {
    final Stopwatch clock = Stopwatch()..start();
    return TerminalExternalPasteController._(
      resolveTarget,
      confirmationGate ?? TerminalPasteConfirmationGate(),
      monotonicMicros ?? () => clock.elapsedMicroseconds,
    );
  }

  TerminalExternalPasteController._(
    this._resolveTarget,
    this._confirmationGate,
    this._monotonicMicros,
  );

  final TerminalExternalPasteTargetResolver<T> _resolveTarget;
  final TerminalPasteConfirmationGate _confirmationGate;
  final int Function() _monotonicMicros;
  bool _disposed = false;
  bool _requestInProgress = false;

  bool get isDisposed => _disposed;

  Future<TerminalExternalPasteResult> submit(
    T targetIdentity,
    TerminalExternalContent content,
  ) async {
    if (_disposed) {
      return const TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.disposed,
      );
    }
    if (_requestInProgress) {
      return const TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.busy,
      );
    }
    _requestInProgress = true;
    try {
      return await _submit(targetIdentity, content);
    } finally {
      _requestInProgress = false;
    }
  }

  Future<TerminalExternalPasteResult> _submit(
    T targetIdentity,
    TerminalExternalContent content,
  ) async {
    final TerminalExternalPasteTarget? initial = _resolveTarget(targetIdentity);
    if (initial == null) {
      return const TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.staleTarget,
      );
    }
    if (initial.pasteInProgress) {
      return const TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.busy,
      );
    }
    final int invocationMicros = _monotonicMicros();
    TerminalPastePlan plan;
    try {
      plan = await TerminalPasteCodec.planAsync(
        content.text,
        bracketed: initial.bracketedPasteMode,
      );
    } on TerminalPasteLimitException {
      initial.showNotice(
        const TerminalClipboardNotice(
          TerminalClipboardNoticeKind.pasteTooLarge,
        ),
      );
      return const TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.tooLarge,
      );
    }
    final TerminalExternalPasteTarget? current = _disposed
        ? null
        : _resolveTarget(targetIdentity);
    if (current == null || !identical(current.identity, initial.identity)) {
      return TerminalExternalPasteResult(
        _disposed
            ? TerminalExternalPasteDisposition.disposed
            : TerminalExternalPasteDisposition.staleTarget,
        analysis: plan.analysis,
      );
    }
    if (current.pasteInProgress) {
      return TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.busy,
        analysis: plan.analysis,
      );
    }
    final TerminalPasteApprovalResult approval = _confirmationGate.evaluate(
      pasteboardChangeCount: _sourceIdentity(content),
      plan: plan,
      invocationMicros: invocationMicros,
      confirmationIssuedMicros: _monotonicMicros(),
    );
    if (!approval.isApproved) {
      current.showNotice(
        TerminalClipboardNotice(
          TerminalClipboardNoticeKind.pasteConfirmationRequired,
          analysis: approval.analysis,
        ),
      );
      return TerminalExternalPasteResult(
        TerminalExternalPasteDisposition.confirmationRequired,
        analysis: approval.analysis,
      );
    }
    final TerminalPasteTransferResult transfer = await current.paste(plan);
    return TerminalExternalPasteResult(
      transfer.isCompleted
          ? TerminalExternalPasteDisposition.completed
          : TerminalExternalPasteDisposition.transferIncomplete,
      analysis: plan.analysis,
      transfer: transfer,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _confirmationGate.clear();
  }

  static int _sourceIdentity(TerminalExternalContent content) => switch ((
    content.kind,
    content.textSource,
  )) {
    (TerminalExternalContentKind.text, TerminalExternalTextSource.service) => 1,
    (TerminalExternalContentKind.text, TerminalExternalTextSource.drop) => 2,
    (
      TerminalExternalContentKind.text,
      TerminalExternalTextSource.appleScript,
    ) =>
      3,
    (TerminalExternalContentKind.filePaths, _) => 4,
  };
}

/// Bounded admission shared by Services and the terminal drop destination.
abstract final class TerminalExternalContentAdmission {
  static const int maximumUtf8Bytes =
      TerminalPasteCodec.maximumEncodedBodyBytes;
  static const int maximumFilePathUtf8Bytes = 1024 * 1024;
  static const int maximumFilePaths = 256;

  static TerminalExternalContentResult text(
    String value, {
    required TerminalExternalTextSource source,
    int maxUtf8Bytes = maximumUtf8Bytes,
  }) {
    _checkMaximum(maxUtf8Bytes);
    if (value.isEmpty) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.empty,
      );
    }
    final int? bytes = _boundedUtf8Length(value, maxUtf8Bytes);
    if (bytes == null) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.tooLarge,
      );
    }
    return TerminalExternalContentResult.admitted(
      TerminalExternalContent._(
        kind: TerminalExternalContentKind.text,
        textSource: source,
        text: value,
        utf8Bytes: bytes,
        itemCount: 1,
      ),
    );
  }

  static TerminalExternalContentResult filePaths(
    Iterable<String> values, {
    int maxUtf8Bytes = maximumUtf8Bytes,
    int maxFilePathUtf8Bytes = maximumFilePathUtf8Bytes,
    int maxFilePaths = maximumFilePaths,
  }) {
    _checkMaximum(maxUtf8Bytes);
    RangeError.checkValueInInterval(
      maxFilePathUtf8Bytes,
      1,
      maximumFilePathUtf8Bytes,
      'maxFilePathUtf8Bytes',
    );
    RangeError.checkValueInInterval(
      maxFilePaths,
      1,
      maximumFilePaths,
      'maxFilePaths',
    );
    final List<String> admitted = <String>[];
    var encodedBytes = 0;
    for (final String path in values) {
      if (admitted.length == maxFilePaths) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooManyItems,
        );
      }
      if (!_isSafeAbsolutePath(path)) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.invalidPath,
        );
      }
      final int? pathBytes = _boundedUtf8Length(path, maxFilePathUtf8Bytes);
      if (pathBytes == null) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooLarge,
        );
      }
      final int quoteCount = "'".allMatches(path).length;
      final int quotedBytes = pathBytes + 2 + quoteCount * 3 + 1;
      if (encodedBytes + quotedBytes > maxUtf8Bytes) {
        return const TerminalExternalContentResult.rejected(
          TerminalExternalContentDisposition.tooLarge,
        );
      }
      admitted.add(path);
      encodedBytes += quotedBytes;
    }
    if (admitted.isEmpty) {
      return const TerminalExternalContentResult.rejected(
        TerminalExternalContentDisposition.empty,
      );
    }
    final StringBuffer serialized = StringBuffer();
    for (final String path in admitted) {
      serialized
        ..write("'")
        ..write(path.replaceAll("'", "'\\''"))
        ..write("' ");
    }
    return TerminalExternalContentResult.admitted(
      TerminalExternalContent._(
        kind: TerminalExternalContentKind.filePaths,
        textSource: TerminalExternalTextSource.drop,
        text: serialized.toString(),
        utf8Bytes: encodedBytes,
        itemCount: admitted.length,
      ),
    );
  }

  static void _checkMaximum(int maximum) {
    RangeError.checkValueInInterval(
      maximum,
      1,
      maximumUtf8Bytes,
      'maxUtf8Bytes',
    );
  }
}

bool _isOnlyWhitespace(String value) {
  for (final int scalar in value.runes) {
    if (!(scalar >= 0x09 && scalar <= 0x0d ||
        scalar == 0x20 ||
        scalar == 0x85 ||
        scalar == 0xa0 ||
        scalar == 0x1680 ||
        scalar >= 0x2000 && scalar <= 0x200a ||
        scalar == 0x2028 ||
        scalar == 0x2029 ||
        scalar == 0x202f ||
        scalar == 0x205f ||
        scalar == 0x3000)) {
      return false;
    }
  }
  return true;
}

bool _isSafeAbsolutePath(String path) {
  if (path.isEmpty || !path.startsWith('/')) return false;
  for (var index = 0; index < path.length; index++) {
    final int unit = path.codeUnitAt(index);
    if (unit < 0x20 || unit == 0x7f) return false;
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= path.length) return false;
      final int second = path.codeUnitAt(index);
      if (second < 0xdc00 || second > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

int? _boundedUtf8Length(String value, int maximum) {
  var bytes = 0;
  for (var index = 0; index < value.length; index++) {
    final int first = value.codeUnitAt(index);
    if (first <= 0x7f) {
      bytes++;
    } else if (first <= 0x7ff) {
      bytes += 2;
    } else if (first >= 0xd800 && first <= 0xdbff) {
      if (index + 1 < value.length) {
        final int second = value.codeUnitAt(index + 1);
        if (second >= 0xdc00 && second <= 0xdfff) {
          index++;
          bytes += 4;
        } else {
          bytes += 3;
        }
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
    if (bytes > maximum) return null;
  }
  return bytes;
}
