/// Supported static product language catalogs.
enum TerminalLanguage { english, japanese }

/// Direction for application-owned composition only.
enum TerminalTextDirection { leftToRight, rightToLeft }

/// Typed action-copy keys shared by the menu and command palette catalog.
enum TerminalActionMessageId {
  openCommandPalette,
  openSettings,
  reloadConfiguration,
  toggleQuickTerminal,
  toggleSecureKeyboardEntry,
  quitApplication,
  newWindow,
  closeWindow,
  copy,
  paste,
  allowOsc52Clipboard,
  denyOsc52Clipboard,
  newTab,
  splitPaneRight,
  splitPaneDown,
  quickLook,
  togglePaneZoom,
  equalizeSplits,
  moveDividerLeft,
  moveDividerRight,
  moveDividerUp,
  moveDividerDown,
  jumpToPreviousPrompt,
  jumpToNextPrompt,
  focusPreviousPane,
  focusNextPane,
  selectPreviousTab,
  selectNextTab,
}

final class TerminalActionMessages {
  TerminalActionMessages({
    required this.title,
    required Iterable<String> keywords,
  }) : keywords = List<String>.unmodifiable(keywords);

  final String title;
  final List<String> keywords;
}

/// Immutable selected language, fallback, and application UI direction.
final class TerminalLocalization {
  TerminalLocalization._({
    required this.requestedLocale,
    required this.language,
    required this.textDirection,
  });

  static final TerminalLocalization english = TerminalLocalization.resolve(
    'en',
  );
  static final TerminalLocalization japanese = TerminalLocalization.resolve(
    'ja',
  );

  factory TerminalLocalization.fromEnvironment(Map<String, String> values) {
    for (final String name in const <String>['LC_ALL', 'LC_MESSAGES', 'LANG']) {
      final String? value = values[name]?.trim();
      if (value != null && value.isNotEmpty) {
        return TerminalLocalization.resolve(value);
      }
    }
    return TerminalLocalization.resolve(null);
  }

  factory TerminalLocalization.resolve(String? localeTag) {
    final String raw = localeTag?.trim() ?? '';
    final String base = raw
        .split('@')
        .first
        .split('.')
        .first
        .replaceAll('_', '-');
    final String languageTag = base.split('-').first.toLowerCase();
    final bool validLanguage = RegExp(r'^[a-z]{2,8}$').hasMatch(languageTag);
    final String normalizedLanguage = validLanguage ? languageTag : 'en';
    return TerminalLocalization._(
      requestedLocale: raw.isEmpty ? null : raw,
      language: normalizedLanguage == 'ja'
          ? TerminalLanguage.japanese
          : TerminalLanguage.english,
      textDirection:
          const <String>{'ar', 'fa', 'he', 'ur'}.contains(normalizedLanguage)
          ? TerminalTextDirection.rightToLeft
          : TerminalTextDirection.leftToRight,
    );
  }

  final String? requestedLocale;
  final TerminalLanguage language;
  final TerminalTextDirection textDirection;

  bool get usesFallbackCatalog {
    final String raw = requestedLocale ?? '';
    final String languageTag = raw
        .split('@')
        .first
        .split('.')
        .first
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    return language == TerminalLanguage.english && languageTag != 'en';
  }

  TerminalActionMessages action(TerminalActionMessageId id) =>
      (language == TerminalLanguage.japanese
      ? _japaneseActions
      : _englishActions)[id]!;

  Iterable<TerminalActionMessageId> get actionMessageIds =>
      TerminalActionMessageId.values;
}

TerminalActionMessages _action(String title, List<String> keywords) =>
    TerminalActionMessages(title: title, keywords: keywords);

final Map<TerminalActionMessageId, TerminalActionMessages> _englishActions =
    Map<TerminalActionMessageId, TerminalActionMessages>.unmodifiable(
      <TerminalActionMessageId, TerminalActionMessages>{
        TerminalActionMessageId.openCommandPalette: _action(
          'Command Palette…',
          <String>['find', 'search', 'action', 'command'],
        ),
        TerminalActionMessageId.openSettings: _action('Settings…', <String>[
          'config',
          'preferences',
          'effective',
          'options',
          'diagnostics',
        ]),
        TerminalActionMessageId.reloadConfiguration: _action(
          'Reload Configuration',
          <String>['config', 'settings', 'refresh'],
        ),
        TerminalActionMessageId.toggleQuickTerminal: _action(
          'Toggle Quick Terminal',
          <String>['show', 'hide', 'dropdown', 'global', 'shortcut'],
        ),
        TerminalActionMessageId.toggleSecureKeyboardEntry: _action(
          'Secure Keyboard Entry',
          <String>['secure', 'keyboard', 'password', 'input', 'privacy'],
        ),
        TerminalActionMessageId.quitApplication: _action(
          'Quit Dart Terminal',
          <String>['exit', 'application'],
        ),
        TerminalActionMessageId.newWindow: _action('New Window', <String>[
          'create',
          'terminal',
        ]),
        TerminalActionMessageId.closeWindow: _action('Close Window', <String>[
          'close',
          'terminal',
        ]),
        TerminalActionMessageId.copy: _action('Copy', <String>[
          'clipboard',
          'selection',
        ]),
        TerminalActionMessageId.paste: _action('Paste', <String>[
          'clipboard',
          'insert',
        ]),
        TerminalActionMessageId.allowOsc52Clipboard: _action(
          'Allow OSC 52 Clipboard Request',
          <String>['clipboard', 'terminal', 'confirm', 'approve'],
        ),
        TerminalActionMessageId.denyOsc52Clipboard: _action(
          'Deny OSC 52 Clipboard Request',
          <String>['clipboard', 'terminal', 'confirm', 'reject'],
        ),
        TerminalActionMessageId.newTab: _action('New Tab', <String>[
          'create',
          'terminal',
        ]),
        TerminalActionMessageId.splitPaneRight: _action(
          'Split Pane Right',
          <String>['horizontal', 'column'],
        ),
        TerminalActionMessageId.splitPaneDown: _action(
          'Split Pane Down',
          <String>['vertical', 'row'],
        ),
        TerminalActionMessageId.quickLook: _action('Quick Look', <String>[
          'definition',
          'dictionary',
          'word',
          'lookup',
        ]),
        TerminalActionMessageId.togglePaneZoom: _action(
          'Toggle Pane Zoom',
          <String>['maximize', 'restore', 'focus'],
        ),
        TerminalActionMessageId.equalizeSplits: _action(
          'Equalize Splits',
          <String>['balance', 'resize', 'panes'],
        ),
        TerminalActionMessageId.moveDividerLeft: _action(
          'Move Split Divider Left',
          <String>['resize', 'pane', 'horizontal'],
        ),
        TerminalActionMessageId.moveDividerRight: _action(
          'Move Split Divider Right',
          <String>['resize', 'pane', 'horizontal'],
        ),
        TerminalActionMessageId.moveDividerUp: _action(
          'Move Split Divider Up',
          <String>['resize', 'pane', 'vertical'],
        ),
        TerminalActionMessageId.moveDividerDown: _action(
          'Move Split Divider Down',
          <String>['resize', 'pane', 'vertical'],
        ),
        TerminalActionMessageId.jumpToPreviousPrompt: _action(
          'Jump to Previous Prompt',
          <String>['scroll', 'history', 'shell', 'back'],
        ),
        TerminalActionMessageId.jumpToNextPrompt: _action(
          'Jump to Next Prompt',
          <String>['scroll', 'history', 'shell', 'forward'],
        ),
        TerminalActionMessageId.focusPreviousPane: _action(
          'Focus Previous Pane',
          <String>['navigate', 'back'],
        ),
        TerminalActionMessageId.focusNextPane: _action(
          'Focus Next Pane',
          <String>['navigate', 'forward'],
        ),
        TerminalActionMessageId.selectPreviousTab: _action(
          'Select Previous Tab',
          <String>['navigate', 'back'],
        ),
        TerminalActionMessageId.selectNextTab: _action(
          'Select Next Tab',
          <String>['navigate', 'forward'],
        ),
      },
    );

final Map<TerminalActionMessageId, TerminalActionMessages> _japaneseActions =
    Map<TerminalActionMessageId, TerminalActionMessages>.unmodifiable(<
      TerminalActionMessageId,
      TerminalActionMessages
    >{
      TerminalActionMessageId.openCommandPalette: _action('コマンドパレット…', <String>[
        '検索',
        '操作',
        'コマンド',
      ]),
      TerminalActionMessageId.openSettings: _action('設定…', <String>[
        '設定',
        '環境設定',
        'オプション',
        '診断',
      ]),
      TerminalActionMessageId.reloadConfiguration: _action('設定を再読み込み', <String>[
        '設定',
        '再読み込み',
        '更新',
      ]),
      TerminalActionMessageId.toggleQuickTerminal: _action(
        'クイックターミナルを切り替え',
        <String>['表示', '非表示', 'ショートカット'],
      ),
      TerminalActionMessageId.toggleSecureKeyboardEntry: _action(
        'セキュアキーボード入力',
        <String>['セキュア', 'キーボード', 'パスワード', 'プライバシー'],
      ),
      TerminalActionMessageId.quitApplication: _action(
        'Dart Terminalを終了',
        <String>['終了', 'アプリケーション'],
      ),
      TerminalActionMessageId.newWindow: _action('新規ウインドウ', <String>[
        '作成',
        'ターミナル',
      ]),
      TerminalActionMessageId.closeWindow: _action('ウインドウを閉じる', <String>[
        '閉じる',
        'ターミナル',
      ]),
      TerminalActionMessageId.copy: _action('コピー', <String>['クリップボード', '選択']),
      TerminalActionMessageId.paste: _action('ペースト', <String>['クリップボード', '挿入']),
      TerminalActionMessageId.allowOsc52Clipboard: _action(
        'OSC 52クリップボード要求を許可',
        <String>['クリップボード', '確認', '許可'],
      ),
      TerminalActionMessageId.denyOsc52Clipboard: _action(
        'OSC 52クリップボード要求を拒否',
        <String>['クリップボード', '確認', '拒否'],
      ),
      TerminalActionMessageId.newTab: _action('新規タブ', <String>['作成', 'ターミナル']),
      TerminalActionMessageId.splitPaneRight: _action('ペインを右に分割', <String>[
        '水平',
        '列',
      ]),
      TerminalActionMessageId.splitPaneDown: _action('ペインを下に分割', <String>[
        '垂直',
        '行',
      ]),
      TerminalActionMessageId.quickLook: _action('クイックルック', <String>[
        '定義',
        '辞書',
        '単語',
      ]),
      TerminalActionMessageId.togglePaneZoom: _action('ペインの拡大を切り替え', <String>[
        '最大化',
        '復元',
        'フォーカス',
      ]),
      TerminalActionMessageId.equalizeSplits: _action('分割幅を均等化', <String>[
        '均等',
        'サイズ変更',
        'ペイン',
      ]),
      TerminalActionMessageId.moveDividerLeft: _action('分割境界を左へ移動', <String>[
        'サイズ変更',
        'ペイン',
        '水平',
      ]),
      TerminalActionMessageId.moveDividerRight: _action('分割境界を右へ移動', <String>[
        'サイズ変更',
        'ペイン',
        '水平',
      ]),
      TerminalActionMessageId.moveDividerUp: _action('分割境界を上へ移動', <String>[
        'サイズ変更',
        'ペイン',
        '垂直',
      ]),
      TerminalActionMessageId.moveDividerDown: _action('分割境界を下へ移動', <String>[
        'サイズ変更',
        'ペイン',
        '垂直',
      ]),
      TerminalActionMessageId.jumpToPreviousPrompt: _action(
        '前のプロンプトへ移動',
        <String>['スクロール', '履歴', '前'],
      ),
      TerminalActionMessageId.jumpToNextPrompt: _action('次のプロンプトへ移動', <String>[
        'スクロール',
        '履歴',
        '次',
      ]),
      TerminalActionMessageId.focusPreviousPane: _action(
        '前のペインにフォーカス',
        <String>['移動', '前'],
      ),
      TerminalActionMessageId.focusNextPane: _action('次のペインにフォーカス', <String>[
        '移動',
        '次',
      ]),
      TerminalActionMessageId.selectPreviousTab: _action('前のタブを選択', <String>[
        '移動',
        '前',
      ]),
      TerminalActionMessageId.selectNextTab: _action('次のタブを選択', <String>[
        '移動',
        '次',
      ]),
    });
