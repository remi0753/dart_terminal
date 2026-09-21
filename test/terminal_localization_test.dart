import 'dart:convert';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalLocalizationTests();

void runTerminalLocalizationTests() {
  _testLocaleSelectionAndDirection();
  _testActionCatalogCompletenessAndStablePolicy();
  _testPresenterAndStatusMessages();
  _testEnumBackedCatalogCompleteness();
  _testSettingsCatalogAndResourceDeclarations();
}

void _testEnumBackedCatalogCompleteness() {
  final TerminalLocalization japanese = TerminalLocalization.japanese;
  for (final TerminalMenuMessageId id in TerminalMenuMessageId.values) {
    _expect(
      japanese.menuTitle(id).trim().isNotEmpty &&
          TerminalLocalization.english.menuTitle(id).trim().isNotEmpty,
      'both menu catalogs cover ${id.name}',
    );
  }
  for (final TerminalSettingsSaveState state
      in TerminalSettingsSaveState.values) {
    _expectLocalizedState(
      japanese.settingsSaveState(state.name),
      state.name,
      'Settings save state',
    );
  }
  for (final TerminalQuickTerminalShortcutFailure failure
      in TerminalQuickTerminalShortcutFailure.values) {
    _expectLocalizedState(
      japanese.quickTerminalShortcutFailed(
        failure: failure.name,
        requested: 'command-f18',
        retained: null,
      ),
      failure.name,
      'Quick Terminal failure',
    );
  }
  for (final TerminalSecureKeyboardEntryMode mode
      in TerminalSecureKeyboardEntryMode.values) {
    _expectLocalizedState(
      japanese.secureKeyboardStatus(
        mode: mode.name,
        ownership: 'owned',
        automatic: true,
        indicator: true,
      ),
      mode.name,
      'Secure Input mode',
    );
  }
  for (final String ownership in const <String>[
    'owned',
    'yielded',
    'released',
  ]) {
    _expectLocalizedState(
      japanese.secureKeyboardStatus(
        mode: 'automatic',
        ownership: ownership,
        automatic: true,
        indicator: true,
      ),
      ownership,
      'Secure Input ownership',
    );
  }
  for (final AppKitUserNotificationAuthorizationStatus authorization
      in AppKitUserNotificationAuthorizationStatus.values) {
    _expectLocalizedState(
      japanese.notificationStatus(
        enabled: true,
        authorization: authorization.name,
        pending: 0,
        responses: 0,
        last: TerminalNotificationProductFailure.none.name,
        stopped: false,
      ),
      authorization.name,
      'notification authorization',
    );
  }
  for (final TerminalNotificationProductFailure failure
      in TerminalNotificationProductFailure.values) {
    _expectLocalizedState(
      japanese.notificationStatus(
        enabled: true,
        authorization:
            AppKitUserNotificationAuthorizationStatus.authorized.name,
        pending: 0,
        responses: 0,
        last: failure.name,
        stopped: false,
      ),
      failure.name,
      'notification failure',
    );
  }
  for (final String availability in const <String>[
    'stopped',
    'ready',
    'disabled',
  ]) {
    _expectLocalizedState(
      japanese.appIntentsStatus(
        enabled: true,
        availability: availability,
        pending: 0,
        completed: 0,
        rejected: 0,
        failed: 0,
        last: TerminalAppIntentsProductFailure.none.name,
      ),
      availability,
      'App Intents availability',
    );
  }
  for (final TerminalAppIntentsProductFailure failure
      in TerminalAppIntentsProductFailure.values) {
    _expectLocalizedState(
      japanese.appIntentsStatus(
        enabled: true,
        availability: 'ready',
        pending: 0,
        completed: 0,
        rejected: 0,
        failed: 0,
        last: failure.name,
      ),
      failure.name,
      'App Intents failure',
    );
  }
}

void _expectLocalizedState(String output, String raw, String kind) {
  _expect(
    output.trim().isNotEmpty && !output.contains(raw),
    'Japanese $kind catalog covers $raw',
  );
}

void _testSettingsCatalogAndResourceDeclarations() {
  final TerminalLocalization japanese = TerminalLocalization.japanese;
  _expect(
    japanese
            .settingsNormalStatus(japanese.settingsSaveState('modified'))
            .contains('変更あり') &&
        japanese.settingsCollapsedDetail == '›\n\n詳\n細' &&
        TerminalLocalization.resolve('ar').settingsCollapsedDetail ==
            '‹\n\nD\nE\nT\nA\nI\nL' &&
        japanese
            .settingsInspectorDiagnostics(latestAttempt: true, count: 2)
            .contains('最新の再読み込み試行') &&
        japanese
            .settingsFontResolutionStatus(
              appliedVariations: 1,
              configuredVariations: 2,
              unavailableVariations: 1,
              availableOverrides: 1,
              configuredOverrides: 2,
              unavailableOverrides: 1,
              overrideMatches: 3,
              overrideFallbacks: 1,
              coreTextFallbacks: 4,
              missingGlyphs: 1,
              faceSummary: 'Menlo-Regular',
            )
            .contains('フェイス Menlo-Regular') &&
        japanese.settingsFontResolutionUnavailable.contains('利用不可'),
    'Settings shell and directional markers use the selected catalog',
  );
  for (final TerminalConfigOptionBase option
      in TerminalProductConfigSchema.instance.options) {
    _expect(
      japanese.settingsOptionDescription(option.name, option.description) !=
          option.description,
      'Japanese Settings description covers ${option.name}',
    );
  }

  final Map<String, Object?> manifest = jsonDecode(
    _projectFile('macos_application.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final Map<String, Object?> application =
      manifest['application']! as Map<String, Object?>;
  final Set<String> resources = (manifest['resources']! as List<Object?>)
      .cast<String>()
      .toSet();
  const Set<String> localizedResources = <String>{
    'en.lproj/InfoPlist.strings',
    'en.lproj/Localizable.strings',
    'en.lproj/AppShortcuts.strings',
    'en.lproj/ServicesMenu.strings',
    'ja.lproj/InfoPlist.strings',
    'ja.lproj/Localizable.strings',
    'ja.lproj/AppShortcuts.strings',
    'ja.lproj/ServicesMenu.strings',
  };
  _expect(
    application['displayName'] == 'Dart Terminal' &&
        resources.containsAll(localizedResources),
    'manifest injects the display name and both localization resource sets',
  );
  for (final String fileName in const <String>[
    'InfoPlist.strings',
    'Localizable.strings',
    'AppShortcuts.strings',
    'ServicesMenu.strings',
  ]) {
    final Set<String> english = _stringsKeys(
      _projectFile('en.lproj/$fileName').readAsStringSync(),
    );
    final Set<String> japaneseKeys = _stringsKeys(
      _projectFile('ja.lproj/$fileName').readAsStringSync(),
    );
    _expect(
      english.isNotEmpty &&
          english.difference(japaneseKeys).isEmpty &&
          japaneseKeys.difference(english).isEmpty,
      '$fileName has identical nonempty English and Japanese key sets',
    );
  }
  final String swift = _projectFile(
    'packages/dart_terminal_app_intents_macos/native/'
    'TerminalAppIntents.swift',
  ).readAsStringSync();
  final Set<String> localizableKeys = _stringsKeys(
    _projectFile('en.lproj/Localizable.strings').readAsStringSync(),
  );
  _expect(
    localizableKeys.every(swift.contains) &&
        swift.contains('String(localized:'),
    'App Intent declarations and localized errors are covered by resources',
  );
  final Set<String> serviceKeys = _stringsKeys(
    _projectFile('en.lproj/ServicesMenu.strings').readAsStringSync(),
  );
  final Set<String> declaredServices = (manifest['services']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((Map<String, Object?> value) => value['menuItem']! as String)
      .toSet();
  _expect(
    serviceKeys.length == declaredServices.length &&
        serviceKeys.containsAll(declaredServices),
    'Finder Service default menu titles have exact localization keys',
  );
}

File _projectFile(String relativePath) =>
    File.fromUri(Platform.script.resolve('../$relativePath'));

Set<String> _stringsKeys(String source) => RegExp(
  r'^"((?:[^"\\]|\\.)+)"\s*=',
  multiLine: true,
).allMatches(source).map((RegExpMatch match) => match.group(1)!).toSet();

void _testPresenterAndStatusMessages() {
  final TerminalLocalization messages = TerminalLocalization.japanese;
  _expect(
    messages.menuTitle(TerminalMenuMessageId.file) == 'ファイル' &&
        messages.commandPaletteTitle == 'コマンドパレット' &&
        messages.commandPaletteNoMatches.contains('一致') &&
        messages.terminalInspectorWindowTitle == 'ターミナルインスペクタ' &&
        messages.terminalInspectorInstructions.contains('Esc') &&
        messages.diagnosticsSavePanelTitle.contains('診断') &&
        messages.diagnosticsSavePanelMessage.contains('パスを含まない') &&
        messages.diagnosticsSavePanelPrompt == '書き出す' &&
        messages.diagnosticsDefaultFileName ==
            'dart-terminal-diagnostics.json' &&
        messages.incidentWindowTitle == 'ローカル障害診断' &&
        messages.incidentCrashSavePanelMessage.contains('ファイルパス') &&
        messages.incidentSampleSavePanelMessage.contains('1秒間') &&
        messages.incidentSavePanelPrompt == '保存して続ける' &&
        messages.processInspectorTitle == 'プロセスインスペクタ' &&
        messages.processInspectorForegroundJob(2).contains('2 プロセス') &&
        messages.processInspectorCommandArgv.contains('argv') &&
        messages.processInspectorProtectedHelp.contains('表示しません') &&
        messages.processInspectorArgumentsHidden == '引数は非表示です' &&
        messages.processInspectorArgumentsRefreshing.contains('再取得') &&
        TerminalLocalization.english.processInspectorArgumentsHidden ==
            'Arguments are hidden' &&
        TerminalLocalization.english.processInspectorArgumentsRefreshing ==
            'Refreshing arguments…' &&
        TerminalLocalization.english.processInspectorTitle ==
            'Process Inspector' &&
        TerminalLocalization.english
            .processInspectorForegroundJob(1)
            .endsWith('1 process') &&
        TerminalLocalization.english
            .processInspectorForegroundJob(2)
            .endsWith('2 processes') &&
        messages.osc52Identity(pane: 2, session: 3, request: 4) ==
            'ペイン 2  セッション 3  要求 4' &&
        messages.osc52WriteClipboard(9).contains('9 UTF-8 bytes') &&
        messages.osc52Instructions.contains('許可'),
    'menu, palette, and OSC 52 presenter copy uses Japanese catalog entries',
  );

  const TerminalKeyBindingChord chord = TerminalKeyBindingChord(
    physicalKey: TerminalPhysicalKey.f18,
    command: true,
  );
  final String quick = TerminalQuickTerminalShortcutStatus.failed(
    desired: chord,
    active: null,
    failure: TerminalQuickTerminalShortcutFailure.conflict,
  ).settingsLineFor(messages);
  final String secure = const TerminalSecureKeyboardEntryStatus(
    mode: TerminalSecureKeyboardEntryMode.manual,
    manualRequested: true,
    automaticEnabled: true,
    indicationEnabled: true,
    applicationActive: true,
    desired: true,
    ownedEnabled: true,
    systemEnabled: true,
    lastOsStatus: 0,
    targetIdentity: null,
    terminalEchoEnabled: false,
    failure: null,
  ).settingsLineFor(messages);
  final String notification = const TerminalNotificationProductStatus(
    enabled: true,
    authorizationStatus: AppKitUserNotificationAuthorizationStatus.authorized,
    pendingRequestCount: 1,
    liveResponseCount: 2,
    lastFailure: TerminalNotificationProductFailure.none,
    disposed: false,
  ).settingsLineFor(messages);
  final String intents = const TerminalAppIntentsProductStatus(
    enabled: true,
    polling: false,
    pendingCommandCount: 1,
    disposed: false,
    completedCommandCount: 2,
    rejectedCommandCount: 3,
    failedCommandCount: 4,
    lastFailure: TerminalAppIntentsProductFailure.none,
  ).settingsLineFor(messages);
  final ViewBadge badge = appKitSecureInputBadge(
    TerminalSecureKeyboardEntryIndicator.automatic,
    localization: messages,
  )!;
  _expect(
    quick.contains('競合') &&
        quick.contains('維持 なし') &&
        secure.contains('手動') &&
        secure.contains('保有') &&
        notification.contains('許可済み') &&
        intents.contains('準備完了') &&
        badge.text == '保護 自動' &&
        badge.accessibilityLabel.contains('自動') &&
        badge.accessibilityHelp.contains('保護'),
    'status lines and secure badge localize states without exposing payloads',
  );
}

void _testLocaleSelectionAndDirection() {
  final TerminalLocalization japanese = TerminalLocalization.fromEnvironment(
    const <String, String>{'LANG': 'en_US.UTF-8', 'LC_MESSAGES': 'ja_JP.UTF-8'},
  );
  _expect(
    japanese.language == TerminalLanguage.japanese &&
        japanese.textDirection == TerminalTextDirection.leftToRight &&
        !japanese.usesFallbackCatalog,
    'LC_MESSAGES selects the Japanese regional catalog before LANG',
  );

  final TerminalLocalization rtlFallback = TerminalLocalization.fromEnvironment(
    const <String, String>{'LC_ALL': 'ar-EG', 'LC_MESSAGES': 'ja_JP.UTF-8'},
  );
  _expect(
    rtlFallback.language == TerminalLanguage.english &&
        rtlFallback.textDirection == TerminalTextDirection.rightToLeft &&
        rtlFallback.usesFallbackCatalog &&
        rtlFallback.action(TerminalActionMessageId.copy).title == 'Copy',
    'unsupported RTL locale uses English copy without losing UI direction',
  );

  for (final String locale in <String>['C', 'POSIX', '@broken', '']) {
    final TerminalLocalization fallback = TerminalLocalization.resolve(locale);
    _expect(
      fallback.language == TerminalLanguage.english &&
          fallback.textDirection == TerminalTextDirection.leftToRight &&
          fallback.action(TerminalActionMessageId.openSettings).title ==
              'Settings…',
      '$locale deterministically falls back to English LTR copy',
    );
  }
}

void _testActionCatalogCompletenessAndStablePolicy() {
  final TerminalActionCatalog english = TerminalActionCatalog.standard(
    localization: TerminalLocalization.english,
    includeNotes: true,
  );
  final TerminalActionCatalog japanese = TerminalActionCatalog.standard(
    localization: TerminalLocalization.japanese,
    includeNotes: true,
  );
  _expect(
    english.actions.length == TerminalActionId.values.length &&
        japanese.actions.length == TerminalActionId.values.length &&
        TerminalLocalization.english.actionMessageIds.length ==
            TerminalActionMessageId.values.length &&
        TerminalLocalization.japanese.actionMessageIds.length ==
            TerminalActionMessageId.values.length,
    'both catalogs cover every stable action exactly once',
  );
  for (var index = 0; index < TerminalActionId.values.length; index++) {
    final TerminalActionDefinition left = english.actions[index];
    final TerminalActionDefinition right = japanese.actions[index];
    _expect(
      left.id == right.id &&
          left.menu == right.menu &&
          left.shortcut == right.shortcut &&
          left.separatorBefore == right.separatorBefore &&
          left.isVisibleInPalette == right.isVisibleInPalette &&
          left.restoresTerminalFocusAfterInvocation ==
              right.restoresTerminalFocusAfterInvocation &&
          left.title.isNotEmpty &&
          right.title.isNotEmpty &&
          left.keywords.isNotEmpty &&
          right.keywords.isNotEmpty,
      'localized action ${left.id.stableName} preserves non-text policy',
    );
  }
  _expect(
    japanese.actionForId(TerminalActionId.copy)!.title == 'コピー' &&
        english.actionForId(TerminalActionId.newNote)!.title == 'New Note…' &&
        english.actionForId(TerminalActionId.toggleNotes)!.title ==
            'Show/Hide Notes' &&
        japanese.actionForId(TerminalActionId.newNote)!.title == '新規ノート…' &&
        japanese.actionForId(TerminalActionId.toggleNotes)!.title ==
            'ノートを表示／非表示' &&
        TerminalActionDispatcher(catalog: japanese)
            .search('分割')
            .map((snapshot) => snapshot.definition.id)
            .contains(TerminalActionId.splitPaneRight) &&
        english.actionForId(TerminalActionId.copy)!.id.stableName ==
            'edit.copy',
    'Japanese action copy and search change without translating stable IDs',
  );
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
