import 'dart:async';

import 'terminal_localization.dart';

/// Stable product-level commands shared by menus and the command palette.
enum TerminalActionId {
  openCommandPalette('application.open-command-palette'),
  openSettings('application.open-settings'),
  reloadConfiguration('application.reload-configuration'),
  toggleQuickTerminal('application.toggle-quick-terminal'),
  toggleSecureKeyboardEntry('application.toggle-secure-keyboard-entry'),
  quitApplication('application.quit'),
  newWindow('window.new'),
  closeWindow('window.close'),
  newTab('tab.new'),
  selectPreviousTab('tab.select-previous'),
  selectNextTab('tab.select-next'),
  splitPaneRight('pane.split-right'),
  splitPaneDown('pane.split-down'),
  focusPreviousPane('pane.focus-previous'),
  focusNextPane('pane.focus-next'),
  quickLook('pane.quick-look'),
  jumpToPreviousPrompt('pane.jump-to-previous-prompt'),
  jumpToNextPrompt('pane.jump-to-next-prompt'),
  togglePaneZoom('pane.toggle-zoom'),
  equalizeSplits('pane.equalize-splits'),
  moveDividerLeft('pane.move-divider-left'),
  moveDividerRight('pane.move-divider-right'),
  moveDividerUp('pane.move-divider-up'),
  moveDividerDown('pane.move-divider-down'),
  copy('edit.copy'),
  paste('edit.paste'),
  allowOsc52Clipboard('edit.allow-osc52-clipboard'),
  denyOsc52Clipboard('edit.deny-osc52-clipboard');

  const TerminalActionId(this.stableName);

  final String stableName;

  static TerminalActionId? fromStableName(String value) {
    for (final TerminalActionId id in values) {
      if (id.stableName == value) {
        return id;
      }
    }
    return null;
  }
}

enum TerminalActionMenu { application, file, edit, shell, view, window }

/// Platform-neutral native-menu shortcut metadata.
final class TerminalActionShortcut {
  const TerminalActionShortcut({
    required this.keyEquivalent,
    this.shift = false,
    this.control = false,
    this.option = false,
    this.command = false,
  });

  final String keyEquivalent;
  final bool shift;
  final bool control;
  final bool option;
  final bool command;

  String get identity => <String>[
    if (shift) 'shift',
    if (control) 'control',
    if (option) 'option',
    if (command) 'command',
    keyEquivalent.toLowerCase(),
  ].join('+');
}

/// Immutable presentation metadata for one product action.
final class TerminalActionDefinition {
  TerminalActionDefinition({
    required this.id,
    required this.title,
    required this.menu,
    Iterable<String> keywords = const <String>[],
    this.shortcut,
    this.separatorBefore = false,
    this.isVisibleInPalette = true,
    this.restoresTerminalFocusAfterInvocation = true,
  }) : keywords = List<String>.unmodifiable(keywords) {
    if (title.isEmpty ||
        title.length > TerminalActionLimits.maximumTitleUnits) {
      throw ArgumentError.value(
        title,
        'title',
        'must contain 1..${TerminalActionLimits.maximumTitleUnits} UTF-16 units',
      );
    }
    if (this.keywords.length > TerminalActionLimits.maximumKeywordsPerAction) {
      throw ArgumentError.value(
        this.keywords.length,
        'keywords',
        'exceeds ${TerminalActionLimits.maximumKeywordsPerAction}',
      );
    }
    for (final String keyword in this.keywords) {
      if (keyword.isEmpty ||
          keyword.length > TerminalActionLimits.maximumKeywordUnits) {
        throw ArgumentError.value(
          keyword,
          'keywords',
          'each keyword must contain 1..'
              '${TerminalActionLimits.maximumKeywordUnits} UTF-16 units',
        );
      }
    }
    final TerminalActionShortcut? selectedShortcut = shortcut;
    if (selectedShortcut != null) {
      if (selectedShortcut.keyEquivalent.isEmpty ||
          selectedShortcut.keyEquivalent.length >
              TerminalActionLimits.maximumKeyEquivalentUnits ||
          selectedShortcut.keyEquivalent.runes.any(
            (int scalar) => scalar < 0x20 || scalar == 0x7f,
          )) {
        throw ArgumentError.value(
          selectedShortcut.keyEquivalent,
          'shortcut.keyEquivalent',
          'must be printable and contain 1..'
              '${TerminalActionLimits.maximumKeyEquivalentUnits} UTF-16 units',
        );
      }
    }
  }

  final TerminalActionId id;
  final String title;
  final TerminalActionMenu menu;
  final List<String> keywords;
  final TerminalActionShortcut? shortcut;
  final bool separatorBefore;
  final bool isVisibleInPalette;
  final bool restoresTerminalFocusAfterInvocation;
}

abstract final class TerminalActionLimits {
  static const int maximumActions = 256;
  static const int maximumTitleUnits = 128;
  static const int maximumKeywordsPerAction = 16;
  static const int maximumKeywordUnits = 64;
  static const int maximumKeyEquivalentUnits = 8;
  static const int maximumPaletteQueryUnits = 256;
  static const int maximumPaletteResults = 32;
}

final class TerminalActionCatalogConflictException implements Exception {
  const TerminalActionCatalogConflictException({
    required this.kind,
    required this.identity,
    required this.firstIndex,
    required this.secondIndex,
  });

  final String kind;
  final String identity;
  final int firstIndex;
  final int secondIndex;

  @override
  String toString() =>
      'TerminalActionCatalogConflictException: duplicate $kind $identity at '
      'indices $firstIndex and $secondIndex';
}

final class TerminalActionLimitException implements Exception {
  const TerminalActionLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final String kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalActionLimitException: $kind has $actual units; maximum is '
      '$maximum';
}

/// Bounded immutable action metadata in deterministic menu/palette order.
final class TerminalActionCatalog {
  factory TerminalActionCatalog(Iterable<TerminalActionDefinition> actions) {
    final List<TerminalActionDefinition> collected =
        <TerminalActionDefinition>[];
    for (final TerminalActionDefinition action in actions) {
      if (collected.length >= TerminalActionLimits.maximumActions) {
        throw TerminalActionLimitException(
          kind: 'action catalog',
          actual: collected.length + 1,
          maximum: TerminalActionLimits.maximumActions,
        );
      }
      collected.add(action);
    }
    final Map<TerminalActionId, int> identityIndices =
        <TerminalActionId, int>{};
    final Map<String, int> shortcutIndices = <String, int>{};
    for (var index = 0; index < collected.length; index++) {
      final TerminalActionDefinition action = collected[index];
      final int? identityIndex = identityIndices[action.id];
      if (identityIndex != null) {
        throw TerminalActionCatalogConflictException(
          kind: 'action identity',
          identity: action.id.stableName,
          firstIndex: identityIndex,
          secondIndex: index,
        );
      }
      final String? shortcutIdentity = action.shortcut?.identity;
      if (shortcutIdentity != null) {
        final int? shortcutIndex = shortcutIndices[shortcutIdentity];
        if (shortcutIndex != null) {
          throw TerminalActionCatalogConflictException(
            kind: 'shortcut',
            identity: shortcutIdentity,
            firstIndex: shortcutIndex,
            secondIndex: index,
          );
        }
        shortcutIndices[shortcutIdentity] = index;
      }
      identityIndices[action.id] = index;
    }
    return TerminalActionCatalog._(
      List<TerminalActionDefinition>.unmodifiable(collected),
    );
  }

  factory TerminalActionCatalog.standard({TerminalLocalization? localization}) {
    final TerminalLocalization messages =
        localization ?? TerminalLocalization.english;
    TerminalActionDefinition action(
      TerminalActionId id,
      TerminalActionMenu menu, {
      TerminalActionShortcut? shortcut,
      bool separatorBefore = false,
      bool isVisibleInPalette = true,
      bool restoresTerminalFocusAfterInvocation = true,
    }) {
      final TerminalActionMessages text = messages.action(_actionMessageId(id));
      return TerminalActionDefinition(
        id: id,
        title: text.title,
        menu: menu,
        keywords: text.keywords,
        shortcut: shortcut,
        separatorBefore: separatorBefore,
        isVisibleInPalette: isVisibleInPalette,
        restoresTerminalFocusAfterInvocation:
            restoresTerminalFocusAfterInvocation,
      );
    }

    return TerminalActionCatalog(<TerminalActionDefinition>[
      action(
        TerminalActionId.openCommandPalette,
        TerminalActionMenu.application,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'p',
          shift: true,
          command: true,
        ),
        isVisibleInPalette: false,
      ),
      action(
        TerminalActionId.openSettings,
        TerminalActionMenu.application,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: ',',
          command: true,
        ),
        restoresTerminalFocusAfterInvocation: false,
      ),
      action(
        TerminalActionId.reloadConfiguration,
        TerminalActionMenu.application,
      ),
      action(
        TerminalActionId.toggleQuickTerminal,
        TerminalActionMenu.application,
        restoresTerminalFocusAfterInvocation: false,
      ),
      action(
        TerminalActionId.toggleSecureKeyboardEntry,
        TerminalActionMenu.application,
      ),
      action(
        TerminalActionId.quitApplication,
        TerminalActionMenu.application,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'q',
          command: true,
        ),
        separatorBefore: true,
        isVisibleInPalette: false,
      ),
      action(
        TerminalActionId.newWindow,
        TerminalActionMenu.file,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'n',
          command: true,
        ),
      ),
      action(
        TerminalActionId.closeWindow,
        TerminalActionMenu.file,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'w',
          command: true,
        ),
        separatorBefore: true,
      ),
      action(
        TerminalActionId.copy,
        TerminalActionMenu.edit,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'c',
          command: true,
        ),
      ),
      action(
        TerminalActionId.paste,
        TerminalActionMenu.edit,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'v',
          command: true,
        ),
      ),
      action(
        TerminalActionId.allowOsc52Clipboard,
        TerminalActionMenu.edit,
        separatorBefore: true,
      ),
      action(TerminalActionId.denyOsc52Clipboard, TerminalActionMenu.edit),
      action(
        TerminalActionId.newTab,
        TerminalActionMenu.shell,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 't',
          command: true,
        ),
      ),
      action(
        TerminalActionId.splitPaneRight,
        TerminalActionMenu.shell,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'd',
          command: true,
        ),
      ),
      action(
        TerminalActionId.splitPaneDown,
        TerminalActionMenu.shell,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'd',
          shift: true,
          command: true,
        ),
      ),
      action(
        TerminalActionId.quickLook,
        TerminalActionMenu.view,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: 'd',
          control: true,
          command: true,
        ),
      ),
      action(TerminalActionId.togglePaneZoom, TerminalActionMenu.view),
      action(TerminalActionId.equalizeSplits, TerminalActionMenu.view),
      action(
        TerminalActionId.moveDividerLeft,
        TerminalActionMenu.view,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: '\uF702',
          command: true,
        ),
        separatorBefore: true,
      ),
      action(
        TerminalActionId.moveDividerRight,
        TerminalActionMenu.view,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: '\uF703',
          command: true,
        ),
      ),
      action(
        TerminalActionId.moveDividerUp,
        TerminalActionMenu.view,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: '\uF700',
          command: true,
        ),
      ),
      action(
        TerminalActionId.moveDividerDown,
        TerminalActionMenu.view,
        shortcut: const TerminalActionShortcut(
          keyEquivalent: '\uF701',
          command: true,
        ),
      ),
      action(TerminalActionId.jumpToPreviousPrompt, TerminalActionMenu.view),
      action(TerminalActionId.jumpToNextPrompt, TerminalActionMenu.view),
      action(TerminalActionId.focusPreviousPane, TerminalActionMenu.window),
      action(TerminalActionId.focusNextPane, TerminalActionMenu.window),
      action(
        TerminalActionId.selectPreviousTab,
        TerminalActionMenu.window,
        separatorBefore: true,
      ),
      action(TerminalActionId.selectNextTab, TerminalActionMenu.window),
    ]);
  }

  TerminalActionCatalog._(this.actions)
    : _byId = Map<TerminalActionId, TerminalActionDefinition>.unmodifiable(
        <TerminalActionId, TerminalActionDefinition>{
          for (final TerminalActionDefinition action in actions)
            action.id: action,
        },
      );

  final List<TerminalActionDefinition> actions;
  final Map<TerminalActionId, TerminalActionDefinition> _byId;

  TerminalActionDefinition? actionForId(TerminalActionId id) => _byId[id];

  List<TerminalActionDefinition> actionsForMenu(TerminalActionMenu menu) =>
      List<TerminalActionDefinition>.unmodifiable(
        actions.where((TerminalActionDefinition action) => action.menu == menu),
      );
}

TerminalActionMessageId _actionMessageId(TerminalActionId id) => switch (id) {
  TerminalActionId.openCommandPalette =>
    TerminalActionMessageId.openCommandPalette,
  TerminalActionId.openSettings => TerminalActionMessageId.openSettings,
  TerminalActionId.reloadConfiguration =>
    TerminalActionMessageId.reloadConfiguration,
  TerminalActionId.toggleQuickTerminal =>
    TerminalActionMessageId.toggleQuickTerminal,
  TerminalActionId.toggleSecureKeyboardEntry =>
    TerminalActionMessageId.toggleSecureKeyboardEntry,
  TerminalActionId.quitApplication => TerminalActionMessageId.quitApplication,
  TerminalActionId.newWindow => TerminalActionMessageId.newWindow,
  TerminalActionId.closeWindow => TerminalActionMessageId.closeWindow,
  TerminalActionId.copy => TerminalActionMessageId.copy,
  TerminalActionId.paste => TerminalActionMessageId.paste,
  TerminalActionId.allowOsc52Clipboard =>
    TerminalActionMessageId.allowOsc52Clipboard,
  TerminalActionId.denyOsc52Clipboard =>
    TerminalActionMessageId.denyOsc52Clipboard,
  TerminalActionId.newTab => TerminalActionMessageId.newTab,
  TerminalActionId.splitPaneRight => TerminalActionMessageId.splitPaneRight,
  TerminalActionId.splitPaneDown => TerminalActionMessageId.splitPaneDown,
  TerminalActionId.quickLook => TerminalActionMessageId.quickLook,
  TerminalActionId.togglePaneZoom => TerminalActionMessageId.togglePaneZoom,
  TerminalActionId.equalizeSplits => TerminalActionMessageId.equalizeSplits,
  TerminalActionId.moveDividerLeft => TerminalActionMessageId.moveDividerLeft,
  TerminalActionId.moveDividerRight => TerminalActionMessageId.moveDividerRight,
  TerminalActionId.moveDividerUp => TerminalActionMessageId.moveDividerUp,
  TerminalActionId.moveDividerDown => TerminalActionMessageId.moveDividerDown,
  TerminalActionId.jumpToPreviousPrompt =>
    TerminalActionMessageId.jumpToPreviousPrompt,
  TerminalActionId.jumpToNextPrompt => TerminalActionMessageId.jumpToNextPrompt,
  TerminalActionId.focusPreviousPane =>
    TerminalActionMessageId.focusPreviousPane,
  TerminalActionId.focusNextPane => TerminalActionMessageId.focusNextPane,
  TerminalActionId.selectPreviousTab =>
    TerminalActionMessageId.selectPreviousTab,
  TerminalActionId.selectNextTab => TerminalActionMessageId.selectNextTab,
};

typedef TerminalActionAvailability = bool Function();
typedef TerminalActionHandler = FutureOr<void> Function();

final class TerminalActionRegistration {
  const TerminalActionRegistration({
    required this.id,
    required this.handler,
    this.isAvailable = _alwaysAvailable,
  });

  final TerminalActionId id;
  final TerminalActionHandler handler;
  final TerminalActionAvailability isAvailable;

  static bool _alwaysAvailable() => true;
}

final class TerminalActionSnapshot {
  const TerminalActionSnapshot({
    required this.definition,
    required this.isEnabled,
    required this.isRunning,
  });

  final TerminalActionDefinition definition;
  final bool isEnabled;
  final bool isRunning;
}

enum TerminalActionDispatchDisposition { executed, unavailable, busy, failed }

final class TerminalActionDispatchResult {
  const TerminalActionDispatchResult({
    required this.id,
    required this.disposition,
    this.error,
    this.stackTrace,
  });

  final TerminalActionId? id;
  final TerminalActionDispatchDisposition disposition;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Product-owned handlers and fail-closed dynamic availability.
final class TerminalActionDispatcher {
  factory TerminalActionDispatcher({
    required TerminalActionCatalog catalog,
    Iterable<TerminalActionRegistration> registrations =
        const <TerminalActionRegistration>[],
  }) {
    final Map<TerminalActionId, TerminalActionRegistration> byId =
        <TerminalActionId, TerminalActionRegistration>{};
    for (final TerminalActionRegistration registration in registrations) {
      if (catalog.actionForId(registration.id) == null) {
        throw ArgumentError.value(
          registration.id,
          'registrations',
          'is not present in the action catalog',
        );
      }
      if (byId.containsKey(registration.id)) {
        throw StateError(
          'duplicate action registration ${registration.id.stableName}',
        );
      }
      byId[registration.id] = registration;
    }
    return TerminalActionDispatcher._(
      catalog,
      Map<TerminalActionId, TerminalActionRegistration>.unmodifiable(byId),
    );
  }

  TerminalActionDispatcher._(this.catalog, this._registrations);

  final TerminalActionCatalog catalog;
  final Map<TerminalActionId, TerminalActionRegistration> _registrations;
  TerminalActionId? _runningAction;

  TerminalActionSnapshot snapshot(TerminalActionId id) {
    final TerminalActionDefinition? definition = catalog.actionForId(id);
    if (definition == null) {
      throw StateError('action ${id.stableName} is absent from the catalog');
    }
    final TerminalActionRegistration? registration = _registrations[id];
    final bool running = _runningAction != null;
    return TerminalActionSnapshot(
      definition: definition,
      isEnabled:
          !running && registration != null && _availability(registration),
      isRunning: _runningAction == id,
    );
  }

  List<TerminalActionSnapshot> snapshotsForMenu(TerminalActionMenu menu) =>
      List<TerminalActionSnapshot>.unmodifiable(
        catalog
            .actionsForMenu(menu)
            .map((TerminalActionDefinition action) => snapshot(action.id)),
      );

  List<TerminalActionSnapshot> search(
    String query, {
    int maximumResults = TerminalActionLimits.maximumPaletteResults,
  }) {
    if (query.length > TerminalActionLimits.maximumPaletteQueryUnits) {
      throw TerminalActionLimitException(
        kind: 'palette query',
        actual: query.length,
        maximum: TerminalActionLimits.maximumPaletteQueryUnits,
      );
    }
    if (maximumResults < 0 ||
        maximumResults > TerminalActionLimits.maximumPaletteResults) {
      throw ArgumentError.value(
        maximumResults,
        'maximumResults',
        'must be in 0..${TerminalActionLimits.maximumPaletteResults}',
      );
    }
    final List<String> queryTokens = _tokens(query);
    final List<_TerminalActionMatch> matches = <_TerminalActionMatch>[];
    for (var index = 0; index < catalog.actions.length; index++) {
      final TerminalActionDefinition definition = catalog.actions[index];
      if (!definition.isVisibleInPalette) {
        continue;
      }
      final int? score = _matchScore(definition, queryTokens);
      if (score != null) {
        matches.add(
          _TerminalActionMatch(
            snapshot: snapshot(definition.id),
            score: score,
            catalogIndex: index,
          ),
        );
      }
    }
    matches.sort((_TerminalActionMatch left, _TerminalActionMatch right) {
      final int enabled = (right.snapshot.isEnabled ? 1 : 0).compareTo(
        left.snapshot.isEnabled ? 1 : 0,
      );
      if (enabled != 0) {
        return enabled;
      }
      final int score = left.score.compareTo(right.score);
      return score != 0
          ? score
          : left.catalogIndex.compareTo(right.catalogIndex);
    });
    return List<TerminalActionSnapshot>.unmodifiable(
      matches
          .take(maximumResults)
          .map((_TerminalActionMatch match) => match.snapshot),
    );
  }

  Future<TerminalActionDispatchResult> dispatch(TerminalActionId id) async {
    final TerminalActionRegistration? registration = _registrations[id];
    if (catalog.actionForId(id) == null || registration == null) {
      return TerminalActionDispatchResult(
        id: id,
        disposition: TerminalActionDispatchDisposition.unavailable,
      );
    }
    if (_runningAction != null) {
      return TerminalActionDispatchResult(
        id: id,
        disposition: TerminalActionDispatchDisposition.busy,
      );
    }
    if (!_availability(registration)) {
      return TerminalActionDispatchResult(
        id: id,
        disposition: TerminalActionDispatchDisposition.unavailable,
      );
    }
    _runningAction = id;
    try {
      await Future<void>.sync(registration.handler);
      return TerminalActionDispatchResult(
        id: id,
        disposition: TerminalActionDispatchDisposition.executed,
      );
    } on Object catch (error, stackTrace) {
      return TerminalActionDispatchResult(
        id: id,
        disposition: TerminalActionDispatchDisposition.failed,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _runningAction = null;
    }
  }

  static bool _availability(TerminalActionRegistration registration) {
    try {
      return registration.isAvailable();
    } on Object {
      return false;
    }
  }
}

/// Starts one action dispatch without blocking the synchronous key event path.
///
/// The dispatcher remains the serialization authority: a second scheduled
/// action observes [TerminalActionDispatchDisposition.busy] instead of being
/// retained in an application-owned queue.
final class TerminalActionDispatchScheduler {
  const TerminalActionDispatchScheduler({
    required TerminalActionDispatcher dispatcher,
    required void Function(TerminalActionDispatchResult result) onDispatched,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) : _dispatcher = dispatcher,
       _onDispatched = onDispatched,
       _onError = onError;

  final TerminalActionDispatcher _dispatcher;
  final void Function(TerminalActionDispatchResult result) _onDispatched;
  final void Function(Object error, StackTrace stackTrace) _onError;

  void schedule(TerminalActionId id) {
    unawaited(_dispatch(id));
  }

  Future<void> _dispatch(TerminalActionId id) async {
    try {
      _onDispatched(await _dispatcher.dispatch(id));
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }
}

/// Platform-independent bounded query, selection, and invocation state.
final class TerminalCommandPaletteState {
  TerminalCommandPaletteState(this.dispatcher);

  final TerminalActionDispatcher dispatcher;
  bool _isOpen = false;
  String _query = '';
  int _selectedIndex = 0;
  List<TerminalActionSnapshot> _results = const <TerminalActionSnapshot>[];

  bool get isOpen => _isOpen;
  String get query => _query;
  int get selectedIndex => _selectedIndex;
  List<TerminalActionSnapshot> get results => _results;
  TerminalActionSnapshot? get selectedAction =>
      _results.isEmpty ? null : _results[_selectedIndex];

  void open() {
    _isOpen = true;
    _query = '';
    _selectedIndex = 0;
    _refresh();
  }

  void dismiss() {
    _isOpen = false;
    _query = '';
    _selectedIndex = 0;
    _results = const <TerminalActionSnapshot>[];
  }

  void setQuery(String value) {
    _ensureOpen();
    if (value.length > TerminalActionLimits.maximumPaletteQueryUnits) {
      throw TerminalActionLimitException(
        kind: 'palette query',
        actual: value.length,
        maximum: TerminalActionLimits.maximumPaletteQueryUnits,
      );
    }
    if (value.runes.any((int scalar) => scalar < 0x20 || scalar == 0x7f)) {
      throw ArgumentError.value(
        value,
        'value',
        'palette queries cannot contain control characters',
      );
    }
    _query = value;
    _selectedIndex = 0;
    _refresh();
  }

  void append(String text) => setQuery('$_query$text');

  void deleteLastScalar() {
    _ensureOpen();
    if (_query.isEmpty) {
      return;
    }
    final List<int> scalars = _query.runes.toList()..removeLast();
    setQuery(String.fromCharCodes(scalars));
  }

  void moveSelection(int delta) {
    _ensureOpen();
    if (_results.isEmpty) {
      _selectedIndex = 0;
      return;
    }
    _selectedIndex = (_selectedIndex + delta) % _results.length;
  }

  void refresh() {
    _ensureOpen();
    _refresh();
  }

  Future<TerminalActionDispatchResult> invokeSelected() async {
    _ensureOpen();
    final TerminalActionSnapshot? selected = selectedAction;
    if (selected == null) {
      return const TerminalActionDispatchResult(
        id: null,
        disposition: TerminalActionDispatchDisposition.unavailable,
      );
    }
    final TerminalActionDispatchResult result = await dispatcher.dispatch(
      selected.definition.id,
    );
    if (result.disposition == TerminalActionDispatchDisposition.executed) {
      dismiss();
    } else {
      _refresh();
    }
    return result;
  }

  void _refresh() {
    _results = dispatcher.search(_query);
    if (_results.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= _results.length) {
      _selectedIndex = _results.length - 1;
    }
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('command palette is not open');
    }
  }
}

final class _TerminalActionMatch {
  const _TerminalActionMatch({
    required this.snapshot,
    required this.score,
    required this.catalogIndex,
  });

  final TerminalActionSnapshot snapshot;
  final int score;
  final int catalogIndex;
}

List<String> _tokens(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((String token) => token.isNotEmpty)
    .toList(growable: false);

int? _matchScore(
  TerminalActionDefinition definition,
  List<String> queryTokens,
) {
  if (queryTokens.isEmpty) {
    return 0;
  }
  final List<String> candidateTokens = _tokens(
    <String>[
      definition.title,
      definition.id.stableName,
      ...definition.keywords,
    ].join(' '),
  );
  final List<String> searchableTokens = <String>[
    ...candidateTokens,
    candidateTokens.join(),
  ];
  var total = 0;
  for (final String queryToken in queryTokens) {
    int? best;
    for (final String candidate in searchableTokens) {
      final int? score = _tokenScore(queryToken, candidate);
      if (score != null && (best == null || score < best)) {
        best = score;
      }
    }
    if (best == null) {
      return null;
    }
    total += best;
  }
  return total;
}

int? _tokenScore(String query, String candidate) {
  if (candidate == query) {
    return 0;
  }
  if (candidate.startsWith(query)) {
    return 10 + candidate.length - query.length;
  }
  final int substring = candidate.indexOf(query);
  if (substring >= 0) {
    return 100 + substring + candidate.length - query.length;
  }
  var queryIndex = 0;
  var firstMatch = -1;
  var lastMatch = -1;
  for (
    var candidateIndex = 0;
    candidateIndex < candidate.length && queryIndex < query.length;
    candidateIndex++
  ) {
    if (candidate.codeUnitAt(candidateIndex) == query.codeUnitAt(queryIndex)) {
      firstMatch = firstMatch < 0 ? candidateIndex : firstMatch;
      lastMatch = candidateIndex;
      queryIndex++;
    }
  }
  if (queryIndex != query.length) {
    return null;
  }
  return 1000 + lastMatch - firstMatch + candidate.length - query.length;
}
