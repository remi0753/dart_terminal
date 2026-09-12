import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalLocalizationTests();

void runTerminalLocalizationTests() {
  _testLocaleSelectionAndDirection();
  _testActionCatalogCompletenessAndStablePolicy();
  _testPresenterAndStatusMessages();
}

void _testPresenterAndStatusMessages() {
  final TerminalLocalization messages = TerminalLocalization.japanese;
  _expect(
    messages.menuTitle(TerminalMenuMessageId.file) == 'ファイル' &&
        messages.commandPaletteTitle == 'コマンドパレット' &&
        messages.commandPaletteNoMatches.contains('一致') &&
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
  );
  final TerminalActionCatalog japanese = TerminalActionCatalog.standard(
    localization: TerminalLocalization.japanese,
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
