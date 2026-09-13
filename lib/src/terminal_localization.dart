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
  checkForUpdates,
  quitApplication,
  newWindow,
  exportDiagnostics,
  exportLatestCrashReport,
  captureHangSample,
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
  openTerminalInspector,
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

  static const String englishSecureAutomaticBadgeText = 'SECURE AUTO';
  static const String englishSecureManualBadgeText = 'SECURE MANUAL';
  static const String englishSecureAutomaticBadgeLabel =
      'Secure Keyboard Entry — Automatic';
  static const String englishSecureManualBadgeLabel =
      'Secure Keyboard Entry — Manual';
  static const String englishSecureBadgeHelp =
      'Keyboard input is protected from other applications.';

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

  String get applicationName => 'Dart Terminal';

  String get directionalSelectionMarker =>
      textDirection == TerminalTextDirection.rightToLeft ? '‹' : '›';

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
      : (automatic
            ? englishSecureAutomaticBadgeText
            : englishSecureManualBadgeText);
  String secureBadgeLabel({required bool automatic}) => _ja
      ? 'セキュアキーボード入力 — ${automatic ? '自動' : '手動'}'
      : (automatic
            ? englishSecureAutomaticBadgeLabel
            : englishSecureManualBadgeLabel);
  String get secureBadgeHelp =>
      _ja ? 'キーボード入力は他のアプリケーションから保護されています。' : englishSecureBadgeHelp;

  String get settingsWindowTitle => _ja ? '設定' : 'Settings';

  String get terminalInspectorWindowTitle =>
      _ja ? 'ターミナルインスペクタ' : 'Terminal Inspector';
  String get terminalInspectorUnavailable =>
      _ja ? 'フォーカス中のターミナルは利用できません。' : 'The focused terminal is unavailable.';
  String get terminalInspectorInstructions =>
      _ja ? 'Escで閉じる' : 'Press Esc to close';
  String get updateWindowTitle => _ja ? 'ソフトウェアアップデート' : 'Software Update';
  String updateStatus(String status) => switch ((language, status)) {
    (TerminalLanguage.english, 'notConfigured') =>
      'Updates are not configured for this build.',
    (TerminalLanguage.english, 'idle') => 'Ready to check for updates.',
    (TerminalLanguage.english, 'checking') => 'Checking for updates…',
    (TerminalLanguage.english, 'available') =>
      'An authenticated update is available.',
    (TerminalLanguage.english, 'upToDate') => 'Dart Terminal is up to date.',
    (TerminalLanguage.english, 'installing') =>
      'Verifying and preparing the update…',
    (TerminalLanguage.english, 'restartRequired') =>
      'The verified update is ready. Restart to finish installation.',
    (TerminalLanguage.english, 'cancelled') =>
      'The update operation was cancelled.',
    (TerminalLanguage.english, 'failed') =>
      'The update could not be verified or prepared.',
    (TerminalLanguage.english, 'disposed') => 'Updates are unavailable.',
    (TerminalLanguage.japanese, 'notConfigured') => 'このビルドではアップデートが構成されていません。',
    (TerminalLanguage.japanese, 'idle') => 'アップデートを確認できます。',
    (TerminalLanguage.japanese, 'checking') => 'アップデートを確認中…',
    (TerminalLanguage.japanese, 'available') => '認証済みアップデートがあります。',
    (TerminalLanguage.japanese, 'upToDate') => 'Dart Terminalは最新です。',
    (TerminalLanguage.japanese, 'installing') => 'アップデートを検証・準備中…',
    (TerminalLanguage.japanese, 'restartRequired') =>
      '検証済みアップデートの準備ができました。再起動して完了してください。',
    (TerminalLanguage.japanese, 'cancelled') => 'アップデート操作をキャンセルしました。',
    (TerminalLanguage.japanese, 'failed') => 'アップデートを検証または準備できませんでした。',
    (TerminalLanguage.japanese, 'disposed') => 'アップデートは利用できません。',
    _ => status,
  };
  String updateVersion(String version, int build) =>
      _ja ? 'バージョン $version（ビルド $build）' : 'Version $version (build $build)';
  String get updateReleaseNotesTitle => _ja ? 'リリースノート' : 'Release notes';
  String get updateNoReleaseNotes => _ja ? '記載なし' : 'No release notes.';
  String updateInstructions({required bool canInstall}) => _ja
      ? (canInstall ? 'Returnで検証・準備    Escで閉じる' : 'Returnで再確認    Escで閉じる')
      : (canInstall
            ? 'Press Return to verify and prepare    Esc to close'
            : 'Press Return to check again    Esc to close');
  String get diagnosticsSavePanelTitle =>
      _ja ? '診断情報を書き出す' : 'Export Diagnostics';
  String get diagnosticsSavePanelMessage => _ja
      ? '内容やパスを含まない診断情報をJSONファイルに保存します。'
      : 'Save content-free diagnostics without terminal text or paths.';
  String get diagnosticsSavePanelPrompt => _ja ? '書き出す' : 'Export';
  String get diagnosticsDefaultFileName => 'dart-terminal-diagnostics.json';
  String get incidentWindowTitle =>
      _ja ? 'ローカル障害診断' : 'Local Incident Diagnostics';
  String get incidentCrashSavePanelTitle =>
      _ja ? '最新のクラッシュレポートを書き出す' : 'Export Latest Crash Report';
  String get incidentCrashSavePanelMessage => _ja
      ? 'クラッシュレポートは生データで、スタックトレース、ファイルパス、プロセス情報を含む場合があります。選択したファイルにローカル保存する場合のみ続けてください。'
      : 'Crash reports are raw data and may contain stack traces, file paths, and process details. Continue only to save one locally to the selected file.';
  String get incidentSampleSavePanelTitle =>
      _ja ? 'ハングサンプルを取得' : 'Capture Hang Sample';
  String get incidentSampleSavePanelMessage => _ja
      ? 'ハングサンプルは生データで、スタックトレース、ファイルパス、プロセス情報を含みます。現在のDart Terminalを1秒間取得し、選択したファイルにローカル保存する場合のみ続けてください。'
      : 'A hang sample is raw data containing stack traces, file paths, and process details. Continue only to sample this Dart Terminal for one second and save it locally to the selected file.';
  String get incidentSavePanelPrompt => _ja ? '保存して続ける' : 'Save and Continue';
  String get incidentCrashDefaultFileName => 'dart-terminal-crash-report.ips';
  String get incidentSampleDefaultFileName => 'dart-terminal-hang.sample.txt';
  String get incidentLocalOnlyNotice => _ja
      ? '生データは明示的に選択した場所にだけ保存され、送信されません。'
      : 'Raw data is saved only to the explicitly selected location and is never uploaded.';
  String incidentStatus(String status) =>
      _ja ? '状態: ${_japaneseState(status)}' : 'Status: $status';
  String incidentMatchingReports(int count) =>
      _ja ? '一致したクラッシュレポート: $count' : 'Matching crash reports: $count';
  String incidentCompletedOperations(int count) =>
      _ja ? '完了した保存: $count' : 'Completed saves: $count';
  String incidentFailures(int count) => _ja ? '失敗: $count' : 'Failures: $count';
  String get incidentWindowInstructions =>
      _ja ? 'Escでキャンセルして閉じる' : 'Press Esc to cancel and close';
  String settingsSaveState(String state) => switch ((language, state)) {
    (TerminalLanguage.english, 'unchanged') => 'UNCHANGED',
    (TerminalLanguage.english, 'modified') => 'MODIFIED',
    (TerminalLanguage.english, 'saved') => 'SAVED',
    (TerminalLanguage.english, 'invalid') => 'FIX ERRORS',
    (TerminalLanguage.english, 'conflict') => 'FILE CHANGED',
    (TerminalLanguage.english, 'unavailable') => 'SAVE UNAVAILABLE',
    (TerminalLanguage.english, 'failed') => 'SAVE FAILED',
    (TerminalLanguage.japanese, 'unchanged') => '変更なし',
    (TerminalLanguage.japanese, 'modified') => '変更あり',
    (TerminalLanguage.japanese, 'saved') => '保存済み',
    (TerminalLanguage.japanese, 'invalid') => 'エラーを修正',
    (TerminalLanguage.japanese, 'conflict') => 'ファイル変更あり',
    (TerminalLanguage.japanese, 'unavailable') => '保存不可',
    (TerminalLanguage.japanese, 'failed') => '保存失敗',
    _ => state,
  };
  String settingsNormalStatus(String save) => _ja
      ? 'NORMAL  $save    i 挿入  a 追記  / 検索  ] 詳細  ⌘S 保存  Esc 閉じる'
      : 'NORMAL  $save    i Insert  a Append  / Search  '
            '] Details  ⌘S Save  Esc Close';
  String settingsInsertStatus(String save) => _ja
      ? 'INSERT  $save    Esc NORMAL  ⌘S 保存'
      : 'INSERT  $save    Esc Normal  ⌘S Save';
  String settingsSearchStatus(String query) => _ja
      ? '/$query    ↑↓ 一致項目  Return 選択  Esc NORMAL'
      : '/$query    ↑↓ Match  Enter Select  Esc Normal';
  String get settingsFontResolutionUnavailable =>
      _ja ? 'フォント診断: 利用不可' : 'Font diagnostics: unavailable';
  String settingsFontResolutionStatus({
    required int appliedVariations,
    required int configuredVariations,
    required int unavailableVariations,
    required int availableOverrides,
    required int configuredOverrides,
    required int unavailableOverrides,
    required int overrideMatches,
    required int overrideFallbacks,
    required int coreTextFallbacks,
    required int missingGlyphs,
    required String faceSummary,
  }) => _ja
      ? 'フォント: 軸 $appliedVariations/$configuredVariations '
            '(利用不可 $unavailableVariations)、上書き '
            '$availableOverrides/$configuredOverrides '
            '(利用不可 $unavailableOverrides、一致 $overrideMatches、'
            'フォールバック $overrideFallbacks)、CoreTextフォールバック '
            '$coreTextFallbacks、欠落 $missingGlyphs、フェイス $faceSummary'
      : 'Font: axes $appliedVariations/$configuredVariations '
            '(unavailable $unavailableVariations), overrides '
            '$availableOverrides/$configuredOverrides '
            '(unavailable $unavailableOverrides, matches $overrideMatches, '
            'fallback $overrideFallbacks), CoreText fallback '
            '$coreTextFallbacks, missing $missingGlyphs, faces $faceSummary';
  String get settingsNoSettingAtCursor =>
      _ja ? 'カーソル位置に設定項目はありません' : 'No setting at the cursor';
  String get settingsEmptyValue => _ja ? '<空>' : '<empty>';
  String get settingsNotSetValue => _ja ? '<未設定>' : '<not set>';
  String get settingsNoValue => _ja ? '<なし>' : '<none>';
  String get settingsCurrentValue => _ja ? '現在の値' : 'Current value';
  String settingsDraft({required bool disabled}) => _ja
      ? '下書き${disabled ? '（無効）' : ''}'
      : 'Draft${disabled ? ' (disabled)' : ''}';
  String get settingsSyntax => _ja ? '構文' : 'Syntax';
  String get settingsAfterSave => _ja ? '保存後' : 'After save';
  String get settingsOpenTerminals => _ja ? '開いているターミナル' : 'Open terminals';
  String get settingsNewTerminals => _ja ? '新しいターミナル' : 'New terminals';
  String get settingsChangeImmediately => _ja ? 'ただちに変更' : 'Change immediately';
  String get settingsKeepCurrentValue => _ja ? '現在の値を維持' : 'Keep current value';
  String get settingsUseSavedValue => _ja ? '保存した値を使用' : 'Use saved value';
  String get settingsIssues => _ja ? '問題' : 'Issues';
  String get settingsFix => _ja ? '修正' : 'Fix';
  String get settingsCollapsedDetail {
    final String label = _ja ? '詳\n細' : 'D\nE\nT\nA\nI\nL';
    return '$directionalSelectionMarker\n\n$label';
  }

  String get settingsInspectorTitle =>
      _ja ? '設定 — 有効な構成' : 'Settings — Effective Configuration';
  String settingsInspectorSearch(String query) =>
      _ja ? '検索: $query' : 'Search: $query';
  String settingsInspectorGeneration({
    required int generation,
    required bool inProgress,
  }) => _ja
      ? '承認世代: $generation    再読み込み: ${inProgress ? '処理中' : '待機中'}'
      : 'Accepted generation: $generation    '
            'Reload: ${inProgress ? 'in progress' : 'idle'}';
  String settingsInspectorConfigFile(String path) =>
      _ja ? '設定ファイル: $path' : 'Config file: $path';
  String settingsInspectorMatches({required int matches, required int total}) =>
      _ja
      ? '一致: 有効な$total項目中$matches項目'
      : 'Matches: $matches of $total effective entries';
  String get settingsInspectorNoMatches =>
      _ja ? '  一致する設定項目はありません' : '  No matching configuration entries';
  String settingsInspectorShowing({
    required int first,
    required int last,
    required int total,
  }) =>
      _ja ? '  $total項目中 $first–$last を表示' : '  Showing $first-$last of $total';
  String get settingsInspectorSelectedEntry => _ja ? '選択項目' : 'Selected entry';
  String get settingsInspectorName => _ja ? '名前' : 'Name';
  String get settingsInspectorValue => _ja ? '値' : 'Value';
  String get settingsInspectorPolicy => _ja ? '適用方針' : 'Policy';
  String get settingsInspectorSource => _ja ? '出典' : 'Source';
  String get settingsInspectorOccurrence => _ja ? '出現回数' : 'Occurrence';
  String settingsInspectorDiagnostics({
    required bool latestAttempt,
    required int count,
  }) => _ja
      ? '診断 — ${settingsInspectorDiagnosticContext(latestAttempt)} ($count)'
      : 'Diagnostics — ${settingsInspectorDiagnosticContext(latestAttempt)} ($count)';
  String settingsInspectorDiagnosticContext(bool latestAttempt) => _ja
      ? (latestAttempt ? '最新の再読み込み試行' : '有効な構成')
      : (latestAttempt ? 'latest reload attempt' : 'effective configuration');
  String get settingsInspectorNone => _ja ? '  なし' : '  None';
  String settingsInspectorMoreDiagnostics(int count) =>
      _ja ? '  … 他$count件の診断' : '  … $count more diagnostics';
  String settingsInspectorReloadFailure(String failure) =>
      _ja ? '  再読み込み失敗: $failure' : '  Reload failure: $failure';
  String get settingsInspectorInstructions => _ja
      ? '入力して検索    ↑↓ 選択    ⌘R 再読み込み    Esc 閉じる'
      : 'Type to search    ↑↓ Select    ⌘R Reload    Esc Close';
  String settingsDiagnosticSeverity(String severity) =>
      switch ((language, severity)) {
        (TerminalLanguage.japanese, 'WARNING') => '警告',
        (TerminalLanguage.japanese, 'ERROR') => 'エラー',
        _ => severity,
      };
  String settingsApplicationPolicy(String policy) =>
      switch ((language, policy)) {
        (TerminalLanguage.japanese, 'live') => '即時',
        (TerminalLanguage.japanese, 'new-session') => '新規セッション',
        _ => policy,
      };
  String settingsSourceKind(String kind) => switch ((language, kind)) {
    (TerminalLanguage.japanese, 'default') => '既定値',
    (TerminalLanguage.japanese, 'file') => 'ファイル',
    (TerminalLanguage.japanese, 'command-line') => 'コマンドライン',
    _ => kind,
  };

  String settingsOptionDescription(String name, String englishFallback) {
    if (!_ja) return englishFallback;
    if (name.startsWith('palette-')) {
      final int? index = int.tryParse(name.substring('palette-'.length));
      if (index != null && index >= 0 && index <= 15) {
        return 'ANSIパレット色 $index。';
      }
    }
    return _japaneseSettingsOptionDescriptions[name] ?? englishFallback;
  }

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
    'idle' => '待機中',
    'discovering' => 'レポートを検索中',
    'exporting' => 'レポートを保存中',
    'exported' => 'レポートを保存済み',
    'notFound' => 'レポートなし',
    'sampling' => 'ハングサンプルを取得中',
    'sampled' => 'ハングサンプルを保存済み',
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
        TerminalActionMessageId.checkForUpdates: _action(
          'Check for Updates…',
          <String>['software', 'release', 'version', 'upgrade'],
        ),
        TerminalActionMessageId.quitApplication: _action(
          'Quit Dart Terminal',
          <String>['exit', 'application'],
        ),
        TerminalActionMessageId.newWindow: _action('New Window', <String>[
          'create',
          'terminal',
        ]),
        TerminalActionMessageId.exportDiagnostics: _action(
          'Export Diagnostics…',
          <String>['save', 'support', 'privacy', 'json'],
        ),
        TerminalActionMessageId.exportLatestCrashReport: _action(
          'Export Latest Crash Report…',
          <String>['save', 'support', 'incident', 'privacy', 'crash'],
        ),
        TerminalActionMessageId.captureHangSample: _action(
          'Capture Hang Sample…',
          <String>['save', 'support', 'incident', 'privacy', 'sample'],
        ),
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
        TerminalActionMessageId.openTerminalInspector: _action(
          'Open Terminal Inspector',
          <String>['parser', 'diagnostics', 'state', 'debug'],
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
      TerminalActionMessageId.checkForUpdates: _action('アップデートを確認…', <String>[
        'ソフトウェア',
        'リリース',
        'バージョン',
        '更新',
      ]),
      TerminalActionMessageId.quitApplication: _action(
        'Dart Terminalを終了',
        <String>['終了', 'アプリケーション'],
      ),
      TerminalActionMessageId.newWindow: _action('新規ウインドウ', <String>[
        '作成',
        'ターミナル',
      ]),
      TerminalActionMessageId.exportDiagnostics: _action('診断情報を書き出す…', <String>[
        '保存',
        'サポート',
        'プライバシー',
        'JSON',
      ]),
      TerminalActionMessageId.exportLatestCrashReport: _action(
        '最新のクラッシュレポートを書き出す…',
        <String>['保存', 'サポート', '障害', 'プライバシー', 'クラッシュ'],
      ),
      TerminalActionMessageId.captureHangSample: _action(
        'ハングサンプルを取得…',
        <String>['保存', 'サポート', '障害', 'プライバシー', 'サンプル'],
      ),
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
      TerminalActionMessageId.openTerminalInspector: _action(
        'ターミナルインスペクタを開く',
        <String>['パーサー', '診断', '状態', 'デバッグ'],
      ),
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

final Map<String, String> _japaneseSettingsOptionDescriptions =
    Map<String, String>.unmodifiable(<String, String>{
      'working-directory': 'コマンドの初期作業ディレクトリ。',
      'shell': '新しいターミナルセッションで使う実行ファイルの絶対パス。',
      'shell-integration': 'シェル統合方針: detect、none、zsh、bash、fish、nushell。',
      'theme': '基本テーマ: system、light、dark。',
      'palette-foreground': 'ターミナルの既定の前景色。',
      'palette-background': 'ターミナルの既定の背景色。',
      'palette-cursor': 'ターミナルのカーソル色。',
      'font-family': 'ターミナルの等幅フォント、または `system`。',
      'font-size': 'ターミナルのフォントサイズ（ポイント）。',
      'font-synthetic-style': '不足している太字・斜体フェイスの合成を許可するか。',
      'font-variation-regular': '通常フェイスに適用するOpenTypeバリエーション座標。',
      'font-variation-bold': '太字フェイスに適用するOpenTypeバリエーション座標。',
      'font-variation-italic': '斜体フェイスに適用するOpenTypeバリエーション座標。',
      'font-variation-bold-italic': '太字斜体フェイスに適用するOpenTypeバリエーション座標。',
      'font-codepoint-override': 'Unicodeスカラー範囲へ明示的に割り当てるフォントファミリー。',
      'window-width': 'ターミナルウインドウの初期幅（論理ポイント）。',
      'window-height': 'ターミナルウインドウの初期高さ（論理ポイント）。',
      'window-padding-horizontal': 'ターミナル内容の左右余白（論理ポイント）。',
      'window-padding-vertical': 'ターミナル内容の上下余白（論理ポイント）。',
      'quick-terminal-shortcut':
          'クイックターミナル切り替え専用のmacOSグローバルショートカット、または `none`。',
      'quick-terminal-screen': 'クイックターミナルを表示する画面: キーボードフォーカス、マウス、macOSメニューバー。',
      'quick-terminal-animation-duration': 'クイックターミナル表示・非表示アニメーションの秒数。0で無効。',
      'quick-terminal-autohide': 'ウインドウがフォーカスを失ったときクイックターミナルを自動的に隠す。',
      'macos-app-intents': 'ショートカットに公開する引数なしのターミナル操作を許可する。',
      'macos-notifications': 'macOSのシステム方針に従ってターミナル通知を許可する。',
      'macos-secure-input-auto': 'フォーカス中のターミナルでechoが無効な間、セキュアキーボード入力を自動要求する。',
      'macos-applescript': 'TCCで許可されたAppleScriptの照会とターミナル操作を許可する。',
      'macos-secure-input-indication': '自動または手動のセキュアキーボード入力をアクセシブルに表示する。',
      'macos-option-key': 'macOSのOptionキーを `escape` または合成 `text` として扱う。',
      'scrollback-lines': '保持するプライマリ画面履歴の最大行数。',
      'scrollback-bytes': '保持するプライマリ画面履歴の最大バイト数。',
      'cursor-shape': 'ターミナルカーソルの初期形状。',
      'cursor-blink': '初期状態でターミナルカーソルを点滅させるか。',
      'clipboard-read': 'OSC 52クリップボード読み取り方針: deny、ask、allow。',
      'clipboard-write': 'OSC 52クリップボード書き込み・消去方針: deny、ask、allow。',
      'keybind': '物理キーの正確な組み合わせと操作の上書き。',
    });
