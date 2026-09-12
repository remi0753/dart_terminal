/// Supported static product language catalogs.
enum TerminalLanguage { english, japanese }

/// Direction for application-owned composition only.
enum TerminalTextDirection { leftToRight, rightToLeft }

enum TerminalMenuMessageId {
  application,
  file,
  edit,
  shell,
  view,
  window,
  context,
}

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

  bool get _ja => language == TerminalLanguage.japanese;

  String menuTitle(TerminalMenuMessageId id) => switch ((language, id)) {
    (TerminalLanguage.english, TerminalMenuMessageId.application) ||
    (
      TerminalLanguage.japanese,
      TerminalMenuMessageId.application,
    ) => 'Dart Terminal',
    (TerminalLanguage.english, TerminalMenuMessageId.file) => 'File',
    (TerminalLanguage.english, TerminalMenuMessageId.edit) => 'Edit',
    (TerminalLanguage.english, TerminalMenuMessageId.shell) => 'Shell',
    (TerminalLanguage.english, TerminalMenuMessageId.view) => 'View',
    (TerminalLanguage.english, TerminalMenuMessageId.window) => 'Window',
    (TerminalLanguage.english, TerminalMenuMessageId.context) => 'Terminal',
    (TerminalLanguage.japanese, TerminalMenuMessageId.file) => 'ファイル',
    (TerminalLanguage.japanese, TerminalMenuMessageId.edit) => '編集',
    (TerminalLanguage.japanese, TerminalMenuMessageId.shell) => 'シェル',
    (TerminalLanguage.japanese, TerminalMenuMessageId.view) => '表示',
    (TerminalLanguage.japanese, TerminalMenuMessageId.window) => 'ウインドウ',
    (TerminalLanguage.japanese, TerminalMenuMessageId.context) => 'ターミナル',
  };

  String get commandPaletteTitle => _ja ? 'コマンドパレット' : 'Command Palette';
  String get commandPaletteNoMatches =>
      _ja ? '一致する操作はありません' : 'No matching actions';
  String get commandPaletteUnavailable => _ja ? '利用不可' : 'Unavailable';
  String get commandPaletteInstructions => _ja
      ? '↑↓ 選択    Return 実行    Esc 閉じる'
      : '↑↓ Select    Return Run    Esc Close';

  String get osc52Title => _ja ? 'OSC 52クリップボード要求' : 'OSC 52 Clipboard Request';
  String osc52Identity({
    required int pane,
    required int session,
    required int request,
  }) => _ja
      ? 'ペイン $pane  セッション $session  要求 $request'
      : 'Pane $pane  Session $session  Request $request';
  String osc52Selection(String value) =>
      _ja ? '選択: $value' : 'Selection: $value';
  String osc52Operation(String value) =>
      _ja ? '操作: $value' : 'Operation: $value';
  String get osc52ReadClipboard => _ja ? 'クリップボードを読み取る' : 'Read clipboard';
  String osc52WriteClipboard(int bytes) => _ja
      ? 'クリップボードに書き込む ($bytes UTF-8 bytes)'
      : 'Write clipboard ($bytes UTF-8 bytes)';
  String get osc52ClearClipboard => _ja ? 'クリップボードを消去' : 'Clear clipboard';
  String get osc52ReadExplanation => _ja
      ? 'フォーカス中のターミナルがクリップボードの内容を要求しています。'
      : 'The focused terminal is requesting clipboard contents.';
  String get osc52WriteExplanation => _ja
      ? 'フォーカス中のターミナルが次のテキストを書き込もうとしています:'
      : 'The focused terminal is requesting this exact text:';
  String get osc52ClearExplanation => _ja
      ? 'フォーカス中のターミナルがクリップボードの破壊的な消去を要求しています。'
      : 'The focused terminal is requesting destructive clipboard clear.';
  String get osc52Instructions =>
      _ja ? 'Return  許可      Esc  拒否' : 'Return  Allow      Esc  Deny';
  String get osc52PolicyHint => _ja
      ? '一致するクリップボードポリシーは設定で変更できます。'
      : 'You can change the matching clipboard policy in Settings.';

  String quickTerminalShortcutDisabled() =>
      _ja ? 'クイックターミナルのショートカット: 無効' : 'Quick Terminal shortcut: disabled';
  String quickTerminalShortcutActive(String chord) => _ja
      ? 'クイックターミナルのショートカット: 有効 ($chord)'
      : 'Quick Terminal shortcut: active ($chord)';
  String quickTerminalShortcutFailed({
    required String failure,
    required String requested,
    required String? retained,
  }) => _ja
      ? 'クイックターミナルのショートカット: ${_japaneseState(failure)}; 要求 $requested; 維持 ${retained ?? 'なし'}'
      : 'Quick Terminal shortcut: $failure; requested $requested; retained ${retained ?? 'none'}';

  String secureKeyboardStatus({
    required String mode,
    required String ownership,
    required bool automatic,
    required bool indicator,
  }) => _ja
      ? 'セキュアキーボード入力: ${_japaneseState(mode)} (${_japaneseState(ownership)}; 自動=${automatic ? 'オン' : 'オフ'}; インジケータ=${indicator ? 'オン' : 'オフ'})'
      : 'Secure Keyboard Entry: $mode ($ownership; automatic=${automatic ? 'on' : 'off'}; indicator=${indicator ? 'on' : 'off'})';
  String notificationStatus({
    required bool enabled,
    required String authorization,
    required int pending,
    required int responses,
    required String last,
    required bool stopped,
  }) => _ja
      ? '通知: ${enabled ? '有効' : '無効'} 許可=${_japaneseState(authorization)} 保留=$pending 応答=$responses 最終=${_japaneseState(last)}${stopped ? ' 停止' : ''}'
      : 'Notifications: ${enabled ? 'enabled' : 'disabled'} authorization=$authorization pending=$pending responses=$responses last=$last${stopped ? ' stopped' : ''}';
  String appIntentsStatus({
    required bool enabled,
    required String availability,
    required int pending,
    required int completed,
    required int rejected,
    required int failed,
    required String last,
  }) => _ja
      ? 'App Intents: ${enabled ? '有効' : '無効'} 利用状況=${_japaneseState(availability)} 保留=$pending 完了=$completed 拒否=$rejected 失敗=$failed 最終=${_japaneseState(last)}'
      : 'App Intents: ${enabled ? 'enabled' : 'disabled'} availability=$availability pending=$pending completed=$completed rejected=$rejected failed=$failed last=$last';

  String secureBadgeText({required bool automatic}) => _ja
      ? (automatic ? '保護 自動' : '保護 手動')
      : (automatic ? 'SECURE AUTO' : 'SECURE MANUAL');
  String secureBadgeLabel({required bool automatic}) => _ja
      ? 'セキュアキーボード入力 — ${automatic ? '自動' : '手動'}'
      : 'Secure Keyboard Entry — ${automatic ? 'Automatic' : 'Manual'}';
  String get secureBadgeHelp => _ja
      ? 'キーボード入力は他のアプリケーションから保護されています。'
      : 'Keyboard input is protected from other applications.';

  String _japaneseState(String value) => switch (value) {
    'disabled' => '無効',
    'automatic' => '自動',
    'manual' => '手動',
    'failed' => '失敗',
    'owned' => '保有',
    'yielded' => '譲渡',
    'released' => '解放',
    'ready' => '準備完了',
    'stopped' => '停止',
    'none' => 'なし',
    'notDetermined' => '未確定',
    'denied' => '拒否',
    'authorized' => '許可済み',
    'provisional' => '仮許可',
    'ephemeral' => '一時的',
    'unknown' => '不明',
    'system' => 'システム',
    'cancelled' => 'キャンセル',
    'staleResponse' => '古い応答',
    'capacity' => '容量上限',
    'nativeFailure' => 'ネイティブ失敗',
    'unavailable' => '利用不可',
    'busy' => '処理中',
    'actionFailed' => '操作失敗',
    'nativeRejected' => 'ネイティブ拒否',
    'timedOut' => 'タイムアウト',
    'unsupportedKey' => '非対応キー',
    'conflict' => '競合',
    'systemFailure' => 'システム失敗',
    _ => value,
  };
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
