import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalSettingsEditorTests();

void runTerminalSettingsEditorTests() {
  _testExplicitSearchAndModalKeys();
  _testDisabledAssignmentSyntax();
  _testModeInvariantSyntaxAndWholeDocumentSynchronization();
  _testContextDetailOutcomesAndDiagnostics();
  _testNextLaunchDetail();
  _testJapaneseProjection();
  _testSelectionAndBounds();
  _testFunctionPageNavigation();
}

void _testNextLaunchDetail() {
  final _EditorFixture fixture = _EditorFixture.create(
    initialText: 'notes = true\n',
  );
  final TerminalSettingsEditorState state = fixture.state..open();
  try {
    final TerminalSettingsOptionOccurrence notes = state.occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option == TerminalProductConfigSchema.notes,
        );
    state.setSelection(TerminalSettingsTextSelection(start: notes.nameStart));
    final String detail = state.renderDetail();
    _expect(
      notes.option.applicationPolicy ==
              TerminalConfigApplicationPolicy.nextLaunch &&
          detail.contains('Open terminals   Keep current value') &&
          detail.contains('New terminals    Keep current value') &&
          detail.contains('After app restart   Use saved value'),
      'next-launch detail does not clearly defer the value until app restart',
    );
  } finally {
    state.dismiss();
    fixture.dispose();
  }
}

void _testFunctionPageNavigation() {
  final _EditorFixture fixture = _EditorFixture.create();
  final TerminalSettingsEditorState state = fixture.state..open();
  final TerminalSettingsEditorKeyController keys =
      TerminalSettingsEditorKeyController(state);
  try {
    final List<String> lines = List<String>.generate(
      35,
      (int index) => 'font-size = 14 # 😀 ${index.toString().padLeft(2, '0')}',
    );
    final String document = lines.join('\n');
    int startOf(int line) => lines
        .take(line)
        .fold(0, (int offset, String text) => offset + text.length + 1);
    state.enterInsert(append: false);
    state.synchronizeNativeDocument(
      text: document,
      selection: const TerminalSettingsTextSelection(start: 3),
    );
    state.enterNormal();
    final List<TerminalSettingsSyntaxSpan> syntax = state.syntaxSpans;
    final bool dirty = state.isDirty;
    final bool details = state.detailsExpanded;
    const ModifierKeys function = ModifierKeys(
      ModifierKeys.functionBit | ModifierKeys.numericPadBit,
    );
    _expect(
      keys.handle(_key(keyCode: 121, modifiers: function)) ==
              TerminalSettingsEditorKeyDisposition.updated &&
          state.selection.start == startOf(10) + 3,
      'PageDown did not move ten lines while preserving column',
    );
    keys.handle(_key(keyCode: 116, modifiers: function));
    _expect(state.selection.start == 3, 'PageUp did not return ten lines');
    keys.handle(_key(keyCode: 125, characters: '\uf72d', modifiers: function));
    _expect(
      state.selection.start == startOf(10) + 3,
      'translated Fn+Down with arrow hardware code was not a page command',
    );
    keys.handle(_key(keyCode: 126, characters: '\uf72c', modifiers: function));
    _expect(state.selection.start == 3, 'translated Fn+Up did not page up');
    keys.handle(_key(keyCode: 125, characters: '\uf701', modifiers: function));
    _expect(
      state.selection.start == startOf(1) + 3,
      'ordinary arrow carrying Function became a page command',
    );
    for (final int modifier in <int>[
      ModifierKeys.shiftBit,
      ModifierKeys.commandBit,
      ModifierKeys.controlBit,
      ModifierKeys.optionBit,
    ]) {
      _expect(
        keys.handle(_key(keyCode: 121, modifiers: ModifierKeys(modifier))) ==
                TerminalSettingsEditorKeyDisposition.ignored &&
            state.selection.start == startOf(1) + 3,
        'modified PageDown unexpectedly changed NORMAL selection',
      );
    }
    for (var repeat = 0; repeat < 6; repeat++) {
      keys.handle(_key(keyCode: 121, modifiers: function));
    }
    _expect(
      state.selection.start == startOf(34) + 3,
      'repeated page down did not clamp at final line',
    );
    for (var repeat = 0; repeat < 6; repeat++) {
      keys.handle(_key(keyCode: 116, modifiers: function));
    }
    _expect(state.selection.start == 3, 'page up did not clamp at first line');
    state.enterSearch();
    state.appendSearch('font-size');
    keys.handle(_key(keyCode: 121, modifiers: function));
    _expect(
      state.selection.start == startOf(10) && state.query == 'font-size',
      'SEARCH page down did not advance ten matches with query intact',
    );
    for (var repeat = 0; repeat < 6; repeat++) {
      keys.handle(_key(keyCode: 121, modifiers: function));
    }
    _expect(state.selection.start == startOf(34), 'SEARCH page down wrapped');
    for (var repeat = 0; repeat < 6; repeat++) {
      keys.handle(_key(keyCode: 116, modifiers: function));
    }
    _expect(state.selection.start == 0, 'SEARCH page up wrapped');
    keys.handle(_key(keyCode: 125, modifiers: function));
    _expect(
      state.selection.start == startOf(1),
      'SEARCH arrow did not move one match',
    );
    state.deleteSearchScalar();
    state.appendSearch('___missing___');
    final TerminalSettingsTextSelection beforeEmptyPage = state.selection;
    keys.handle(_key(keyCode: 121, modifiers: function));
    _expect(
      state.selection == beforeEmptyPage,
      'empty SEARCH page command moved the selection',
    );
    state.enterNormal();
    state.enterInsert(append: false);
    final TerminalSettingsTextSelection beforeInsertPage = state.selection;
    _expect(
      keys.handle(_key(keyCode: 121, modifiers: function)) ==
              TerminalSettingsEditorKeyDisposition.nativeEditing &&
          state.selection == beforeInsertPage &&
          state.mode == TerminalSettingsEditorMode.insert,
      'INSERT page command was not delegated to AppKit',
    );
    _expect(
      state.text == document &&
          identical(state.syntaxSpans, syntax) &&
          state.isDirty == dirty &&
          state.detailsExpanded == details,
      'page navigation changed the document, syntax, dirty state or details',
    );
    final int emoji = lines.first.indexOf('😀');
    final String scalarDocument = document.replaceFirst('😀', 'xy');
    state.synchronizeNativeDocument(
      text: scalarDocument,
      selection: TerminalSettingsTextSelection(start: emoji + 1),
    );
    state.enterNormal();
    keys.handle(_key(keyCode: 121, modifiers: function));
    _expect(
      state.selection.start == startOf(10) + emoji,
      'page navigation split a target-line surrogate pair',
    );
  } finally {
    state.enterNormal();
    state.dismiss();
    fixture.dispose();
  }
}

void _testJapaneseProjection() {
  final _EditorFixture fixture = _EditorFixture.create(
    localization: TerminalLocalization.japanese,
  );
  final TerminalSettingsEditorState state = fixture.state..open();
  try {
    final TerminalSettingsOptionOccurrence font = state.occurrences.singleWhere(
      (TerminalSettingsOptionOccurrence occurrence) =>
          occurrence.option.name == 'font-size',
    );
    state.setSelection(TerminalSettingsTextSelection(start: font.nameStart));
    final String detail = state.renderDetail();
    _expect(
      state.renderStatus().contains('変更なし') &&
          detail.contains('現在の値') &&
          detail.contains('開いているターミナル') &&
          detail.contains('現在の値を維持') &&
          detail.contains('ターミナルのフォントサイズ'),
      'Japanese Settings state did not localize status, detail, and schema description',
    );
  } finally {
    state.dismiss();
    fixture.dispose();
  }
}

void _testDisabledAssignmentSyntax() {
  final _EditorFixture fixture = _EditorFixture.create();
  final TerminalSettingsEditorState state = fixture.state..open();
  try {
    final TerminalSettingsOptionOccurrence disabled = state.occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option.name == 'working-directory',
        );
    final List<TerminalSettingsSyntaxSpan> disabledSpans = state.syntaxSpans
        .where(
          (TerminalSettingsSyntaxSpan span) =>
              span.start < disabled.lineEnd && span.end > disabled.lineStart,
        )
        .toList(growable: false);
    state.setSelection(
      TerminalSettingsTextSelection(start: disabled.nameStart),
    );
    _expect(
      disabled.isCommented &&
          disabled.draftValue(state.text) == '<path>' &&
          state.selectedOccurrence == disabled &&
          state.renderDetail().contains('Draft (disabled)') &&
          disabledSpans.length == 1 &&
          disabledSpans.single.kind == TerminalSettingsSyntaxKind.comment &&
          disabledSpans.single.start == disabled.lineStart &&
          disabledSpans.single.end == disabled.lineEnd,
      'commented assignment was not retained as one disabled full-line span',
    );

    state.enterInsert(append: false);
    final String inlineComment = state.text.replaceFirst(
      'font-size = 14',
      'font-size = 14 # active setting',
    );
    state.synchronizeNativeDocument(
      text: inlineComment,
      selection: TerminalSettingsTextSelection(
        start: inlineComment.indexOf('font-size'),
      ),
    );
    final TerminalSettingsOptionOccurrence active = state.occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option.name == 'font-size',
        );
    final List<TerminalSettingsSyntaxSpan> activeSpans = state.syntaxSpans
        .where(
          (TerminalSettingsSyntaxSpan span) =>
              span.start < active.lineEnd && span.end > active.lineStart,
        )
        .toList(growable: false);
    final int inlineStart = inlineComment.indexOf('# active setting');
    _expect(
      !active.isCommented &&
          activeSpans.any(
            (TerminalSettingsSyntaxSpan span) =>
                span.kind == TerminalSettingsSyntaxKind.optionName &&
                span.start == active.nameStart,
          ) &&
          activeSpans.any(
            (TerminalSettingsSyntaxSpan span) =>
                span.kind == TerminalSettingsSyntaxKind.value &&
                inlineComment.substring(span.start, span.end) == '14',
          ) &&
          activeSpans.any(
            (TerminalSettingsSyntaxSpan span) =>
                span.kind == TerminalSettingsSyntaxKind.comment &&
                span.start == inlineStart &&
                span.end == active.lineEnd,
          ),
      'active assignment did not retain token colors before its inline comment',
    );
  } finally {
    state.enterNormal();
    state.dismiss();
    fixture.dispose();
  }
}

void _testExplicitSearchAndModalKeys() {
  final _EditorFixture fixture = _EditorFixture.create();
  final TerminalSettingsEditorState state = fixture.state..open();
  final TerminalSettingsEditorKeyController keys =
      TerminalSettingsEditorKeyController(state);
  try {
    final int initialCaret = state.selection.start;
    _expect(
      keys.handle(_key(keyCode: 7, characters: 'x')) ==
              TerminalSettingsEditorKeyDisposition.ignored &&
          state.mode == TerminalSettingsEditorMode.normal &&
          state.query.isEmpty &&
          state.selection.start == initialCaret,
      'printable NORMAL key unexpectedly became an implicit search',
    );
    _expect(
      keys.handle(_key(keyCode: 44, characters: '/')) ==
              TerminalSettingsEditorKeyDisposition.updated &&
          state.mode == TerminalSettingsEditorMode.search,
      'slash did not enter explicit SEARCH mode',
    );
    for (final ({int code, String text}) input in <({int code, String text})>[
      (code: 4, text: 'h'),
      (code: 34, text: 'i'),
      (code: 1, text: 's'),
      (code: 17, text: 't'),
      (code: 31, text: 'o'),
      (code: 15, text: 'r'),
      (code: 16, text: 'y'),
    ]) {
      keys.handle(_key(keyCode: input.code, characters: input.text));
    }
    _expect(
      state.query == 'history' &&
          state.selectedOccurrence?.option.name == 'scrollback-lines',
      'SEARCH did not match schema description and move the caret',
    );
    _expect(
      keys.handle(_key(keyCode: 53, characters: '\u001b')) ==
              TerminalSettingsEditorKeyDisposition.updated &&
          state.mode == TerminalSettingsEditorMode.normal &&
          state.isOpen,
      'first Escape did not return SEARCH to NORMAL',
    );
    _expect(
      keys.handle(_key(keyCode: 34, characters: 'i')) ==
              TerminalSettingsEditorKeyDisposition.updated &&
          state.mode == TerminalSettingsEditorMode.insert,
      'i did not enter INSERT',
    );
    _expect(
      keys.handle(_key(keyCode: 0, characters: 'a')) ==
          TerminalSettingsEditorKeyDisposition.nativeEditing,
      'INSERT printable input was not delegated to the native editor',
    );
    _expect(
      keys.handle(_key(keyCode: 53, characters: '\u001b')) ==
              TerminalSettingsEditorKeyDisposition.updated &&
          state.mode == TerminalSettingsEditorMode.normal &&
          state.isOpen,
      'first Escape did not return INSERT to NORMAL',
    );
    final bool details = state.detailsExpanded;
    keys.handle(_key(keyCode: 30, characters: ']'));
    _expect(
      state.detailsExpanded != details,
      'right-panel command did not toggle contextual details',
    );
    _expect(
      keys.handle(
            _key(
              keyCode: 1,
              characters: 's',
              modifiers: const ModifierKeys(ModifierKeys.commandBit),
            ),
          ) ==
          TerminalSettingsEditorKeyDisposition.saveRequested,
      'Command-S did not remain a shared save request in NORMAL',
    );
    _expect(
      keys.handle(_key(keyCode: 53, characters: '\u001b')) ==
              TerminalSettingsEditorKeyDisposition.dismissed &&
          !state.isOpen,
      'NORMAL Escape did not dismiss the editor',
    );
  } finally {
    if (state.isOpen) state.dismiss();
    fixture.dispose();
  }
}

void _testModeInvariantSyntaxAndWholeDocumentSynchronization() {
  final _EditorFixture fixture = _EditorFixture.create();
  final TerminalSettingsEditorState state = fixture.state..open();
  try {
    final String normalText = state.text;
    final List<TerminalSettingsSyntaxSpan> normalSpans = state.syntaxSpans;
    final TerminalSettingsOptionOccurrence font = state.occurrences.singleWhere(
      (TerminalSettingsOptionOccurrence occurrence) =>
          occurrence.option.name == 'font-size',
    );
    state.setSelection(TerminalSettingsTextSelection(start: font.valueStart));
    state.enterInsert(append: false);
    _expect(
      state.mode == TerminalSettingsEditorMode.insert &&
          state.text == normalText &&
          identical(state.syntaxSpans, normalSpans),
      'entering INSERT changed text or syntax presentation',
    );
    state.enterNormal();
    _expect(
      state.text == normalText && identical(state.syntaxSpans, normalSpans),
      'returning to NORMAL rebuilt or changed syntax presentation',
    );

    state.enterInsert(append: false);
    final String edited = normalText
        .replaceFirst('font-size = 14', 'font-size = 18')
        .replaceFirst('cursor-blink = true', 'cursor-blink = false');
    state.synchronizeNativeDocument(
      text: edited,
      selection: TerminalSettingsTextSelection(
        start: edited.indexOf('cursor-blink'),
      ),
    );
    _expect(
      state.text == edited &&
          state.isDirty &&
          state.saveState == TerminalSettingsSaveState.modified &&
          state.selectedOccurrence?.option.name == 'cursor-blink' &&
          state.syntaxSpans.any(
            (TerminalSettingsSyntaxSpan span) =>
                span.kind == TerminalSettingsSyntaxKind.optionName &&
                edited.substring(span.start, span.end) == 'font-size',
          ) &&
          state.syntaxSpans.any(
            (TerminalSettingsSyntaxSpan span) =>
                span.kind == TerminalSettingsSyntaxKind.value &&
                edited.substring(span.start, span.end) == 'false',
          ),
      'native synchronization did not accept edits across the full buffer',
    );
    final List<TerminalSettingsSyntaxSpan> editedSpans = state.syntaxSpans;
    state.enterNormal();
    state.enterInsert(append: false);
    _expect(
      identical(state.syntaxSpans, editedSpans) && state.text == edited,
      'mode transition changed syntax after a native full-buffer edit',
    );
  } finally {
    state.dismiss();
    fixture.dispose();
  }
}

void _testContextDetailOutcomesAndDiagnostics() {
  final _EditorFixture fixture = _EditorFixture.create();
  final TerminalSettingsEditorState state = fixture.state..open();
  try {
    final TerminalSettingsOptionOccurrence optionKey = state.occurrences
        .singleWhere(
          (TerminalSettingsOptionOccurrence occurrence) =>
              occurrence.option.name == 'macos-option-key',
        );
    state.setSelection(
      TerminalSettingsTextSelection(start: optionKey.nameStart),
    );
    final String liveDetail = state.renderDetail();
    _expect(
      liveDetail.startsWith('macos-option-key\n') &&
          liveDetail.contains('Open terminals   Change immediately') &&
          liveDetail.contains('New terminals    Use saved value') &&
          !liveDetail.contains('Source') &&
          !liveDetail.contains('Line') &&
          !liveDetail.contains('APPLIES') &&
          !liveDetail.contains('Config Lens'),
      'live detail is unclear or retained removed inspector fields',
    );

    final TerminalSettingsOptionOccurrence font = state.occurrences.singleWhere(
      (TerminalSettingsOptionOccurrence occurrence) =>
          occurrence.option.name == 'font-size',
    );
    state.setSelection(TerminalSettingsTextSelection(start: font.nameStart));
    final String newSessionDetail = state.renderDetail();
    _expect(
      newSessionDetail.contains('Open terminals   Keep current value') &&
          newSessionDetail.contains('New terminals    Use saved value'),
      'new-session outcome is not immediately understandable',
    );

    final String invalid = state.text.replaceFirst(
      'font-size = 14',
      'font-size = enormous',
    );
    state.synchronizeNativeDocument(
      text: invalid,
      selection: TerminalSettingsTextSelection(
        start: invalid.indexOf('enormous'),
      ),
    );
    final TerminalSettingsDocumentSaveResult result = state.saveDraft();
    final String invalidDetail = state.renderDetail();
    _expect(
      result.disposition == TerminalSettingsDocumentSaveDisposition.rejected &&
          state.saveState == TerminalSettingsSaveState.invalid &&
          state.diagnosticSpans.length == 1 &&
          invalid.substring(
                state.diagnosticSpans.single.start,
                state.diagnosticSpans.single.end,
              ) ==
              'enormous' &&
          invalidDetail.contains('ERROR CFG_INVALID_VALUE') &&
          invalidDetail.contains('Fix:') &&
          !invalidDetail.contains('/config:'),
      'invalid draft did not produce location-free contextual diagnostics',
    );
  } finally {
    state.dismiss();
    fixture.dispose();
  }
}

void _testSelectionAndBounds() {
  final _EditorFixture fixture = _EditorFixture.create(
    limits: const TerminalSettingsEditorLimits(maxQueryCharacters: 2),
  );
  final TerminalSettingsEditorState state = fixture.state..open();
  final TerminalSettingsEditorKeyController keys =
      TerminalSettingsEditorKeyController(state);
  try {
    final int emoji = state.text.indexOf('# Dart');
    final String withEmoji = state.text.replaceFirst('# Dart', '# 👻 Dart');
    state.enterInsert(append: false);
    state.synchronizeNativeDocument(
      text: withEmoji,
      selection: TerminalSettingsTextSelection(start: emoji + 2),
    );
    state.enterNormal();
    _expectThrows<RangeError>(
      () => state.setSelection(TerminalSettingsTextSelection(start: emoji + 3)),
      'selection split a surrogate pair',
    );
    state.setSelection(TerminalSettingsTextSelection(start: emoji + 2));
    state.moveCaretHorizontal(1);
    _expect(
      state.selection.start == emoji + 4,
      'horizontal navigation did not cross one Unicode scalar',
    );

    keys.handle(_key(keyCode: 44, characters: '/'));
    keys.handle(_key(keyCode: 3, characters: 'fo'));
    _expect(
      state.query == 'fo' &&
          keys.handle(_key(keyCode: 15, characters: 'r')) ==
              TerminalSettingsEditorKeyDisposition.overflow &&
          state.query == 'fo',
      'bounded SEARCH overflow changed the accepted query',
    );
  } finally {
    state.enterNormal();
    state.dismiss();
    fixture.dispose();
  }
}

final class _EditorFixture {
  _EditorFixture({
    required this.files,
    required this.controller,
    required this.state,
  });

  factory _EditorFixture.create({
    TerminalSettingsEditorLimits limits = const TerminalSettingsEditorLimits(),
    TerminalLocalization? localization,
    String initialText = '',
  }) {
    final _MemoryEditorFileSystem files = _MemoryEditorFileSystem(
      <String, String>{'/config': initialText},
    );
    final TerminalConfigLoader loader = TerminalConfigLoader(fileSystem: files);
    final List<String> arguments = const <String>['--config=/config'];
    final TerminalConfigSnapshot snapshot = loader
        .resolve(arguments, environment: const <String, String>{})
        .snapshot;
    final TerminalConfigReloadController controller =
        TerminalConfigReloadController(
          initialSnapshot: snapshot,
          resolver: () => TerminalConfigResolution(
            snapshot: snapshot,
            remainingArguments: const <String>[],
          ),
        );
    return _EditorFixture(
      files: files,
      controller: controller,
      state: TerminalSettingsEditorState(
        controller: controller,
        documentSession: TerminalSettingsDocumentSession(
          loader: loader,
          arguments: arguments,
          environment: const <String, String>{},
          writer: files,
        ),
        limits: limits,
        localization: localization,
      ),
    );
  }

  final _MemoryEditorFileSystem files;
  final TerminalConfigReloadController controller;
  final TerminalSettingsEditorState state;

  void dispose() => controller.dispose();
}

AppKitKeyEvent _key({
  required int keyCode,
  String characters = '',
  ModifierKeys modifiers = const ModifierKeys(0),
}) => AppKitKeyEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: AppKitKeyEventKind.down,
  keyCode: keyCode,
  modifiers: modifiers,
  isRepeat: false,
  characters: characters,
  charactersIgnoringModifiers: characters,
);

final class _MemoryEditorFileSystem
    implements TerminalConfigFileSystem, TerminalSettingsDocumentWriter {
  _MemoryEditorFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

  final Map<String, List<int>> _files;

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => _files.containsKey(absolutePath(path));

  @override
  List<int> readBytes(String path) =>
      List<int>.from(_files[absolutePath(path)]!);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      includedPath.startsWith('/') ? includedPath : '/$includedPath';

  @override
  void writeAtomically(String path, List<int> bytes) {
    _files[absolutePath(path)] = List<int>.from(bytes);
  }
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal settings editor expectation failed: $description',
    );
  }
}
