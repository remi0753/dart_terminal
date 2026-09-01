/// Editable input and scrollback state for a terminal-like view.
final class TerminalBuffer {
  TerminalBuffer({this.maxTranscriptLines = 2000}) {
    if (maxTranscriptLines <= 0) {
      throw ArgumentError.value(
        maxTranscriptLines,
        'maxTranscriptLines',
        'must be positive',
      );
    }
  }

  final int maxTranscriptLines;

  final List<String> _transcript = <String>[];
  final List<String> _history = <String>[];
  List<int> _inputRunes = <int>[];
  List<int> _historyDraft = <int>[];
  int _cursor = 0;
  int? _historyPosition;

  String get input => String.fromCharCodes(_inputRunes);
  int get cursor => _cursor;
  List<String> get transcript => List<String>.unmodifiable(_transcript);
  List<String> get history => List<String>.unmodifiable(_history);

  void appendLine(String value) {
    final String normalized = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    _transcript.addAll(normalized.split('\n'));
    _trimTranscript();
  }

  void appendLines(Iterable<String> values) {
    for (final String value in values) {
      appendLine(value);
    }
  }

  void clearTranscript() => _transcript.clear();

  void insert(String value) {
    final List<int> inserted = value.runes.toList(growable: false);
    if (inserted.isEmpty) {
      return;
    }
    _leaveHistoryNavigation();
    _inputRunes.insertAll(_cursor, inserted);
    _cursor += inserted.length;
  }

  void deleteBackward() {
    if (_cursor == 0) {
      return;
    }
    _leaveHistoryNavigation();
    _inputRunes.removeAt(--_cursor);
  }

  void deleteForward() {
    if (_cursor >= _inputRunes.length) {
      return;
    }
    _leaveHistoryNavigation();
    _inputRunes.removeAt(_cursor);
  }

  void moveLeft() {
    if (_cursor > 0) {
      --_cursor;
    }
  }

  void moveRight() {
    if (_cursor < _inputRunes.length) {
      ++_cursor;
    }
  }

  void moveToStart() => _cursor = 0;

  void moveToEnd() => _cursor = _inputRunes.length;

  void previousHistory() {
    if (_history.isEmpty) {
      return;
    }
    final int? position = _historyPosition;
    if (position == null) {
      _historyDraft = List<int>.of(_inputRunes);
      _historyPosition = _history.length - 1;
    } else if (position > 0) {
      _historyPosition = position - 1;
    }
    _replaceInput(_history[_historyPosition!]);
  }

  void nextHistory() {
    final int? position = _historyPosition;
    if (position == null) {
      return;
    }
    if (position < _history.length - 1) {
      _historyPosition = position + 1;
      _replaceInput(_history[_historyPosition!]);
      return;
    }
    _inputRunes = List<int>.of(_historyDraft);
    _cursor = _inputRunes.length;
    _historyPosition = null;
    _historyDraft = <int>[];
  }

  String takeInput() {
    final String command = input;
    if (command.trim().isNotEmpty &&
        (_history.isEmpty || _history.last != command)) {
      _history.add(command);
    }
    _inputRunes = <int>[];
    _historyDraft = <int>[];
    _cursor = 0;
    _historyPosition = null;
    return command;
  }

  String render({
    required String prompt,
    required int rows,
    required bool isBusy,
  }) {
    if (rows <= 0) {
      throw ArgumentError.value(rows, 'rows', 'must be positive');
    }
    final List<String> visible = List<String>.of(_transcript);
    if (isBusy) {
      visible.add('… command running (Control-C to interrupt)');
    } else {
      final String beforeCursor = String.fromCharCodes(
        _inputRunes.take(_cursor),
      );
      final String afterCursor = String.fromCharCodes(
        _inputRunes.skip(_cursor),
      );
      visible.add('$prompt$beforeCursor▌$afterCursor');
    }
    final int firstVisible = visible.length > rows ? visible.length - rows : 0;
    return visible.skip(firstVisible).join('\n');
  }

  void _replaceInput(String value) {
    _inputRunes = value.runes.toList(growable: true);
    _cursor = _inputRunes.length;
  }

  void _leaveHistoryNavigation() {
    _historyPosition = null;
    _historyDraft = <int>[];
  }

  void _trimTranscript() {
    final int overflow = _transcript.length - maxTranscriptLines;
    if (overflow > 0) {
      _transcript.removeRange(0, overflow);
    }
  }
}
